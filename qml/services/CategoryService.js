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
