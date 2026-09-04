.pragma library
.import "Http.js" as Http

// communityId filters client-side; backend matches `community` by title text, which can collide
function listByCommunity(baseUrl, community, communityId, token, onOk, onErr) {
    return Http.get(baseUrl, "/category/list-by-community",
             { community: community || "global" }, token || "",
        function (data) {
            var raw = (data && data.categories) || [];
            if (communityId) {
                raw = raw.filter(function (c) { return String(c && c.community_id) === String(communityId); });
            }
            var names = raw
                .map(function (c) { return c && c.name; })
                .filter(function (n) { return !!n; });
            onOk(names, raw);
        }, onErr);
}

// Omit `id` to create; on update pass current icon_url/color/subs or they get wiped
function createOrUpdate(baseUrl, token, params, onOk, onErr) {
    var body = { community_id: params.communityId, name: params.name };
    if (params.id) body.id = params.id;
    if (params.iconUrl !== undefined && params.iconUrl !== null) body.icon_url = params.iconUrl;
    if (params.color !== undefined && params.color !== null) body.color = params.color;
    if (params.subs !== undefined && params.subs !== null) {
        // Normalize: strip to {name, position}, drop blanks, renumber from 1.
        var subs = [];
        for (var i = 0; i < params.subs.length; i++) {
            var s = params.subs[i];
            var nm = (s && (typeof s === "string" ? s : s.name) || "").trim();
            if (nm.length === 0) continue;
            subs.push({ name: nm, position: subs.length + 1 });
        }
        body.sub_categories = subs;
    }
    Http.post(baseUrl, "/category/create-or-update", body, token, onOk, onErr);
}

function remove(baseUrl, token, id, onOk, onErr) {
    Http.post(baseUrl, "/category/delete", { id: id }, token, onOk, onErr);
}

// Platform/community classification taxonomy, distinct from per-post categories above
function listMarketplaceCategories(baseUrl, token, onOk, onErr) {
    Http.get(baseUrl, "/general/list-marketplace-categories", {}, token || "",
        function (data) {
            var raw = data.categories || data.data || [];
            if (!Array.isArray(raw)) raw = [];
            var names = raw
                .map(function (c) { return (typeof c === "string") ? c : (c && (c.name || c.title || c.category)); })
                .filter(function (n) { return !!n; });
            onOk(names, raw);
        }, onErr);
}

// AI category suggestion, shown when the author taps Publish. Proxied by
// serey-api (/serey-web/categorize-post) because the AI service's shared key
// can't ship inside the app. Answers { category, subCategory } - both may be
// empty, which just means the author picks for themselves.
function categorize(baseUrl, token, params, onOk, onErr) {
    // Only the opening of the article is sent: the classifier reads the first few
    // hundred characters, so shipping the whole body would just slow the publish tap.
    var article = String(params.article || "").slice(0, 2000);
    Http.post(baseUrl, "/serey-web/categorize-post", {
        community_id: params.communityId || 0,
        community_name: params.communityName || "global",
        article: article
    }, token,
    function (data) {
        var d = (data && data.data) || data || {};
        var cc = d.community_categories || [];
        var main = cc[0] || null;
        // The first entry wraps the category in a `categories` array; the second, when
        // present, is the sub-category object itself.
        var mainName = "";
        if (main) {
            var inner = (main.categories && main.categories[0]) || main;
            mainName = (inner && (inner.name || inner)) || "";
        }
        var sub = cc[1] || null;
        var subName = sub ? (sub.name || sub) : "";
        onOk({ category: String(mainName || ""), subCategory: String(subName || "") });
    }, onErr, 10000);   // publishing must not hang on the model; the caller falls back to the list
}
