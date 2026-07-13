.pragma library
.import "Http.js" as Http

/*
 * Create-your-platform (community) flow, gated on an active subscription plan.
 * Mirrors the web wizard (fe-serey-web social-media-owners) against the same
 * endpoints:
 *   GET  /subscription/active                      — plan gate
 *   GET  /dns/check-subdomain?subdomain=<slug>     — availability (server
 *        appends the base domain, send the slug only)
 *   GET  /country/list-countries                   — Country rows (uuid ids)
 *   GET  /community/categories                     — topical categories
 *   POST /community/create-or-update-community     — the create call
 *
 * Backend rules worth knowing (community_service.js):
 *  - needs an active subscription OR approved BuySerey status (403 otherwise);
 *  - one active community per user — the server rejects a second with a clear
 *    message, so we surface its error text rather than pre-blocking;
 *  - community_name must be letters/digits/spaces only (server regex);
 *  - `dns` is the SUBDOMAIN SLUG — the server appends ".serey.io" itself.
 */

function getActiveSubscription(baseUrl, token, onOk, onErr) {
    Http.get(baseUrl, "/subscription/active", {}, token, function (data) {
        onOk({
            hasActive: !!(data && data.has_active_subscription),
            status: (data && data.subscription_status) || "none",
            planType: (data && data.subscription && data.subscription.plan_type) || ""
        });
    }, onErr);
}

// onOk(isTaken) — true when the subdomain already exists.
function checkSubdomain(baseUrl, slug, onOk, onErr) {
    Http.get(baseUrl, "/dns/check-subdomain", { subdomain: slug }, null,
             function (data) { onOk(!!(data && data.is_exists)); }, onErr);
}

// onOk([{ id, name, iconUrl }]) — Country table rows; `id` is a uuid STRING
// (the create payload's country_id is a string, not a number).
function getCountries(baseUrl, onOk, onErr) {
    Http.get(baseUrl, "/country/list-countries", {}, null, function (data) {
        var rows = (data && data.countries) || [];
        var out = [];
        for (var i = 0; i < rows.length; i++) {
            out.push({
                id: String(rows[i].id),
                name: rows[i].name || "",
                iconUrl: rows[i].icon_url || ""
            });
        }
        onOk(out);
    }, onErr);
}

// onOk([{ id, name, color, iconUrl }]) — community topical categories.
// `id` maps to community_category_id (a NUMBER in the create payload).
function getCategories(baseUrl, onOk, onErr) {
    Http.get(baseUrl, "/community/categories", {}, null, function (data) {
        var rows = (data && data.categories) || [];
        var out = [];
        for (var i = 0; i < rows.length; i++) {
            out.push({
                id: parseInt(rows[i].community_category_id, 10) || 0,
                name: rows[i].description || rows[i].category_name || "",
                color: rows[i].color || "",
                iconUrl: rows[i].icon || ""
            });
        }
        onOk(out);
    }, onErr);
}

/*
 * Create the community. `form`:
 *   { name, slug, independent (bool), countryId (string|null),
 *     categoryId (number|0), iconUrl, logoUrl, footerLogoUrl }
 * Image URLs default to the site's own "/logo.png" placeholder — same default
 * the web wizard sends — because logo_url/footer_logo_url are required strings.
 * onOk({ id, dns }) with the created community's id and full dns.
 */
// ---- Manage (owner CMS basics) ---------------------------------------------
// The server authorizes every mutation by CommunityManager membership, so the
// app only needs to find WHICH community the user manages and show its state.

/*
 * Find EVERY community in the get-communities tree whose id is in `idSet`
 * (the { id: true } map Main.qml builds from permission-by-current-user).
 * Searches nested child_communities too — owned platforms usually live at
 * level 3 under a country. onOk(list) — possibly empty; managers of several
 * communities get them all so the manage page can offer a switcher.
 */
function findManagedCommunities(baseUrl, idSet, onOk, onErr) {
    Http.get(baseUrl, "/general/get-communities", {}, "", function (data) {
        var groups = ["globals", "locals", "foreigns", "independents"];
        var out = [];
        var seen = {};
        function walk(node) {
            if (!node) return;
            if (idSet[node.id] && !seen[node.id]) {
                seen[node.id] = true;
                out.push({
                    id: node.id,
                    title: node.title || "",
                    dns: node.dns || "",
                    icon: node.icon_url || node.logo_url || "",
                    // Raw logo fields, echoed back by updateCommunityLogo (the
                    // update-logo schema requires logo_url + footer_logo_url
                    // even when only the icon changes).
                    logoUrl: node.logo_url || "",
                    footerLogoUrl: node.footer_logo_url || "",
                    isAllowPost: !!node.is_allow_post,
                    videoIsAllowPost: !!node.video_is_allow_post
                });
            }
            var kids = node.child_communities || [];
            for (var i = 0; i < kids.length; i++) walk(kids[i]);
        }
        for (var g = 0; g < groups.length; g++) {
            var arr = (data && data[groups[g]]) || [];
            for (var i = 0; i < arr.length; i++) walk(arr[i]);
        }
        onOk(out);
    }, onErr);
}

/*
 * Whether the community has POSTER members (CommunityManager role 2; role 1 is
 * the owner). The web dashboard derives the blog-posting mode from this:
 * is_allow_post=true → "everyone"; false + posters → "custom"; false → "only me".
 */
function hasPosterMembers(baseUrl, communityId, onOk, onErr) {
    Http.get(baseUrl, "/community/list-community-manager-by-community-id/" + communityId,
             {}, "", function (data) {
        var rows = (data && data.community_managers) || [];
        for (var i = 0; i < rows.length; i++)
            if (rows[i].role === 2) { onOk(true); return; }
        onOk(false);
    }, onErr);
}

function updateCommunityName(baseUrl, token, id, name, onOk, onErr) {
    Http.post(baseUrl, "/community/update-community-name",
              { id: id, community_name: name }, token, onOk, onErr);
}

/*
 * Change the community's profile picture (icon_url). The schema requires
 * logo_url + footer_logo_url as strict strings too, so the caller passes the
 * community's current values back unchanged (default "/logo.png" when a
 * community somehow has none — the create wizard's own default).
 */
function updateCommunityIcon(baseUrl, token, community, iconUrl, onOk, onErr) {
    Http.post(baseUrl, "/community/update-logo", {
        community_id: community.id,
        icon_url: iconUrl,
        logo_url: community.logoUrl || "/logo.png",
        footer_logo_url: community.footerLogoUrl || "/logo.png"
    }, token, onOk, onErr);
}

// is_allow_post=true → anyone may post articles; false → owner/managers only.
function updateAllowPost(baseUrl, token, id, allow, onOk, onErr) {
    Http.post(baseUrl, "/community/update-community-allow-post",
              { id: id, is_allow_post: !!allow }, token, onOk, onErr);
}

function updateVideoAllowPost(baseUrl, token, id, allow, onOk, onErr) {
    Http.post(baseUrl, "/community/update-community-video-allow-post",
              { id: id, video_is_allow_post: !!allow }, token, onOk, onErr);
}

function createCommunity(baseUrl, token, form, onOk, onErr) {
    var body = {
        is_topic_community: false,
        is_superhub: false,
        is_independent: !!form.independent,
        community_name: form.name,
        dns: form.slug,
        logo_url: form.logoUrl || "/logo.png",
        icon_url: form.iconUrl || "/logo.png",
        footer_logo_url: form.footerLogoUrl || "/logo.png",
        country_id: form.independent ? null : (form.countryId || null),
        community_id: null,
        community_category_id: (!form.independent && form.categoryId > 0)
                               ? form.categoryId : null
    };
    Http.post(baseUrl, "/community/create-or-update-community", body, token,
              function (data) {
        var c = (data && data.community) || {};
        onOk({ id: c.id || 0, dns: c.dns || "" });
    }, onErr);
}
