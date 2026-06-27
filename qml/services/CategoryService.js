.pragma library
.import "Http.js" as Http

/*
 * Per-community post categories. GET /category/list-by-community matches on the
 * community TITLE (community_title ILIKE :community) and returns
 * { categories: [{ name, sub_categories, ... }] } ordered by position. Each
 * community defines its own set, so the create-post picker must load these for
 * the selected community rather than show a fixed list. Defaults to the
 * backend's own 'global' set when no community is given.
 */
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
