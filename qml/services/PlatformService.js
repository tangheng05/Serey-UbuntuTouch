.pragma library
.import "Http.js" as Http

// Create-your-platform flow, gated on an active subscription. Server rules:
// dns is the subdomain SLUG only (server appends ".serey.io"), country ids are
// uuid strings, name is letters/digits/spaces, one community per user.

// Resolved by username from the JWT; no community_id involved.
function getActiveSubscription(baseUrl, token, onOk, onErr) {
    Http.get(baseUrl, "/subscription/active", {}, token, function (data) {
        var sub = (data && data.subscription) || {};
        onOk({
            hasActive: !!(data && data.has_active_subscription),
            status: (data && data.subscription_status) || "none",
            planName: sub.plan_name || "",
            planType: sub.plan_type || "",
            validStartDate: sub.valid_start_date || "",
            validEndDate: sub.valid_end_date || "",
            daysUntilExpiry: (data && data.days_until_expiry !== undefined) ? data.days_until_expiry : null,
            isTrial: !!(data && data.is_trial),
            isRecurring: !!(data && data.is_recurring),
            autoRenew: !!(data && data.auto_renew),
            isCancelling: !!(data && data.is_cancelling),
            isPastDue: !!(data && data.is_past_due)
        });
    }, onErr);
}

// Paid-amount field names are unconfirmed (no documented schema); try the
// common candidates and fall back to "" rather than guessing wrong.
function getLatestPayment(baseUrl, token, onOk, onErr) {
    Http.get(baseUrl, "/subscription/payment-history", { page: 1, limit: 1 }, token, function (data) {
        var rows = (data && (data.payments || data.data || data.history)) || [];
        if (!Array.isArray(rows) || rows.length === 0) { onOk(null); return; }
        var p = rows[0];
        var amount = p.amount_paid !== undefined ? p.amount_paid
                   : p.amount !== undefined ? p.amount
                   : p.total !== undefined ? p.total : null;
        onOk({ amount: amount, currency: p.currency || "", date: p.created_at || p.date || "" });
    }, onErr);
}

// Banned users. `community` is the community TITLE string, not the numeric id
// (unlike every other community endpoint).
function listBannedUsers(baseUrl, communityTitle, token, onOk, onErr) {
    Http.get(baseUrl, "/banning-user/list-by-community", { community: communityTitle }, token,
        function (data) {
            var raw = (data && (data.banning_users || data.banned_users || data.users || data.data)) || [];
            if (!Array.isArray(raw)) raw = [];
            var out = [];
            for (var i = 0; i < raw.length; i++) {
                var r = raw[i];
                out.push({
                    username: (typeof r === "string") ? r : (r.username || ""),
                    reason: (r && r.reason) || ""
                });
            }
            onOk(out.filter(function (u) { return u.username.length > 0; }));
        }, onErr);
}

function banUser(baseUrl, token, communityTitle, username, reason, onOk, onErr) {
    var body = { username: username, community: communityTitle };
    if (reason) body.reason = reason;
    Http.post(baseUrl, "/banning-user/add", body, token, onOk, onErr);
}

function unbanUser(baseUrl, token, communityTitle, username, onOk, onErr) {
    // POST alias: Qt's QML XMLHttpRequest drops the body on DELETE, and the
    // backend reads username/community from req.body, so DELETE was silently ignored.
    var body = { username: username, community: communityTitle };
    Http.post(baseUrl, "/banning-user/remove", body, token, onOk, onErr);
}

// Soft delete - sets deleted/deleted_at/deleted_reason on the Community row.
function deleteCommunity(baseUrl, token, id, onOk, onErr) {
    // POST alias (added to serey-api). Qt's QML XMLHttpRequest drops the body on
    // DELETE, so the DELETE route arrives with no id ("id is a required field").
    // POST delivers the body reliably; the alias reuses the same controller/schema.
    // deleted_reason is optional server-side, so it's omitted.
    Http.post(baseUrl, "/community/delete-community", { id: id }, token, onOk, onErr);
}

// onOk(isTaken): true when the subdomain already exists.
function checkSubdomain(baseUrl, slug, onOk, onErr) {
    Http.get(baseUrl, "/dns/check-subdomain", { subdomain: slug }, null,
             function (data) { onOk(!!(data && data.is_exists)); }, onErr);
}

// onOk([{ id, name, iconUrl }]) - Country table rows; `id` is a uuid STRING
// (the create payload's country_id is a string, not a number).
function getCountries(baseUrl, onOk, onErr) {
    Http.get(baseUrl, "/country/list-countries", {}, null, function (data) {
        var rows = (data && data.countries) || [];
        var out = [];
        for (var i = 0; i < rows.length; i++) {
            // Cambodia is hidden for now (product decision) - omit it from every
            // country picker (Create Platform and Edit > Parent Country both use this).
            if ((rows[i].name || "").toLowerCase() === "cambodia") continue;
            out.push({
                id: String(rows[i].id),
                name: rows[i].name || "",
                iconUrl: rows[i].icon_url || ""
            });
        }
        onOk(out);
    }, onErr);
}

// onOk([{ id, name, color, iconUrl }]) - community topical categories.
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
 * createCommunity `form`: { name, slug, independent, countryId, categoryId,
 * iconUrl, logoUrl, footerLogoUrl }. Image URLs default to "/logo.png" (the web
 * wizard's default) since logo_url/footer_logo_url are required strings.
 */
// ---- Manage (owner CMS basics) ---------------------------------------------
// The server authorizes every mutation by CommunityManager membership, so the
// app only needs to find WHICH community the user manages and show its state.

/*
 * Find every community in the get-communities tree whose id is in `idSet`.
 * Searches nested child_communities (owned platforms usually live at level 3
 * under a country). onOk(list), possibly empty; may return several to switch between.
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
 * Resolve a community's parent country (its top-level ancestor in the tree,
 * not a field on the node) and its community_category_id.
 */
function getCommunityContext(baseUrl, id, onOk, onErr) {
    Http.get(baseUrl, "/general/get-communities", {}, "", function (data) {
        var groups = ["globals", "locals", "foreigns", "independents"];
        var result = null;
        function walk(node, ancestorTitle) {
            if (!node || result) return;
            if (node.id === id) {
                result = {
                    name: node.title || "",
                    parentCountry: ancestorTitle,
                    categoryId: parseInt(node.community_category_id, 10) || 0,
                    countryId: String(node.country_id || ""),
                    metaDescription: node.meta_description || ""
                };
                return;
            }
            var kids = node.child_communities || [];
            for (var i = 0; i < kids.length; i++)
                walk(kids[i], ancestorTitle || node.title || "");
        }
        for (var g = 0; g < groups.length && !result; g++) {
            var arr = (data && data[groups[g]]) || [];
            for (var i = 0; i < arr.length && !result; i++) walk(arr[i], "");
        }
        onOk(result || { name: "", parentCountry: "", categoryId: 0, countryId: "", metaDescription: "" });
    }, onErr);
}

/*
 * Whether the community has POSTER members (CommunityManager role 2, role 1 =
 * owner). Blog-posting mode: is_allow_post=true -> everyone; false + posters ->
 * custom; false -> only me.
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

function updateCommunityCountry(baseUrl, token, id, countryId, onOk, onErr) {
    Http.post(baseUrl, "/community/update-community-country",
              { id: id, country_id: countryId }, token, onOk, onErr);
}

function updateCommunityCategory(baseUrl, token, id, categoryId, onOk, onErr) {
    Http.post(baseUrl, "/community/update-community-category",
              { id: id, community_category_id: categoryId }, token, onOk, onErr);
}

// meta_description is nullable, max 160 chars (the SEO field's counter).
function updateCommunityMetaDescription(baseUrl, token, id, desc, onOk, onErr) {
    Http.post(baseUrl, "/community/update-community-meta-description",
              { id: id, meta_description: desc }, token, onOk, onErr);
}

/*
 * Change the community icon (icon_url). Schema also requires logo_url +
 * footer_logo_url as strict strings, so the caller passes current values back
 * unchanged (default "/logo.png" when a community has none).
 */
function updateCommunityIcon(baseUrl, token, community, iconUrl, onOk, onErr) {
    Http.post(baseUrl, "/community/update-logo", {
        community_id: community.id,
        icon_url: iconUrl,
        logo_url: community.logoUrl || "/logo.png",
        footer_logo_url: community.footerLogoUrl || "/logo.png"
    }, token, onOk, onErr);
}

// is_allow_post=true -> anyone may post articles; false -> owner/managers only.
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
        // Seed the in-session cache without a re-fetch; get-communities is
        // server-cached and returns stale data right after a create.
        onOk({
            id: c.id || 0,
            dns: c.dns || "",
            title: c.title || form.name || "",
            iconUrl: c.icon_url || c.logo_url || form.iconUrl || form.logoUrl || ""
        });
    }, onErr);
}
