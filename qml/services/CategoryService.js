.pragma library
.import "Http.js" as Http

function listByCommunity(baseUrl, community, token, onOk, onErr) {
    Http.get(baseUrl, "/category/list-by-community",
             { community: community || "global" }, token || "",
        function (data) {
            var raw = (data && data.categories) || [];
            var names = raw
                .map(function (c) { return c && c.name; })
                .filter(function (n) { return !!n; });
            onOk(names, raw);
        }, onErr);
}

// POST /category/create-or-update (JWT) — omit `id` to create, pass it to rename/update.
function createOrUpdate(baseUrl, token, params, onOk, onErr) {
    var body = { community_id: params.communityId, name: params.name };
    if (params.id) body.id = params.id;
    Http.post(baseUrl, "/category/create-or-update", body, token, onOk, onErr);
}

// POST /category/delete (JWT)
function remove(baseUrl, token, id, onOk, onErr) {
    Http.post(baseUrl, "/category/delete", { id: id }, token, onOk, onErr);
}

// GET /general/list-marketplace-categories (general_route.js -> general_controller.js
// getAllMarketplaceCategories). This is the taxonomy the web CMS's "Category"
// picker on Edit Platform Information uses (e.g. "PRODUCTS & SERVICES") — a
// platform/community classification, distinct from listByCommunity's per-post
// categories above.
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
