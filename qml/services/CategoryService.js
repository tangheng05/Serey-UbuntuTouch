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
