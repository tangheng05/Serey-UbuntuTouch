.pragma library
.import "Http.js" as Http
.import "Mappers.js" as M

/*
 * Communities (regional sources). GET /general/get-communities returns
 * { globals, locals, foreigns, independents }, each a list of community objects
 * with id/title/dns/icon_url/logo_url and a nested child_communities tree.
 *
 * onOk receives (list, superhubChildren):
 *   list             — top-level communities, flattened and de-duped by dns.
 *   superhubChildren — { superhubId(string): [child view-model, …] } for every
 *                      node marked is_superhub, so the picker can nest a hub's
 *                      children (list-by-parent-id/<country> returns the hub but
 *                      NOT its children, so we take them from this tree instead).
 */
function listAll(baseUrl, onOk, onErr) {
    Http.get(baseUrl, "/general/get-communities", {}, "",
        function (data) {
            var groups = ["globals", "locals", "foreigns", "independents"];
            var seen = {};
            var out = [];
            var hubs = {};
            // Every community visited (top-level AND nested at any depth),
            // keyed by numeric id — lets callers resolve a specific community's
            // name/icon (e.g. an owned sub-community) without a dedicated
            // "get community by id" endpoint.
            var byId = {};

            function collectHubs(node) {
                if (node.id !== undefined) byId[String(node.id)] = M.toCommunity(node);
                var kids = node.child_communities || [];
                if (node.is_superhub && kids.length > 0) {
                    var mapped = [];
                    for (var i = 0; i < kids.length; i++) mapped.push(M.toCommunity(kids[i]));
                    hubs[String(node.id)] = mapped;
                }
                for (var j = 0; j < kids.length; j++) collectHubs(kids[j]);
            }

            for (var g = 0; g < groups.length; g++) {
                var arr = (data && data[groups[g]]) || [];
                for (var i = 0; i < arr.length; i++) {
                    collectHubs(arr[i]);
                    var c = M.toCommunity(arr[i]);
                    if (c.dns && !seen[c.dns]) {
                        seen[c.dns] = true;
                        out.push(c);
                    }
                }
            }
            onOk(out, hubs, byId);
        }, onErr);
}

// Convenience: build a { dns: iconUrl } map from listAll's result.
function iconMap(list) {
    var map = {};
    for (var i = 0; i < list.length; i++) {
        if (list[i].dns && list[i].icon)
            map[list[i].dns] = list[i].icon;
    }
    return map;
}

// Convenience: build a { dns: allowPost(bool) } map from listAll's result, used
// to gate the compose buttons (only show when the community permits posting).
function allowPostMap(list) {
    var map = {};
    for (var i = 0; i < list.length; i++) {
        if (list[i].dns)
            map[list[i].dns] = !!list[i].allowPost;
    }
    return map;
}

// Convenience: build a { dns: videoAllowPost(bool) } map from listAll's result,
// used to gate the Video upload FAB — only show when the community lets everyone
// post a video. Independent of allowPostMap (which is the blog posting flag).
function videoAllowPostMap(list) {
    var map = {};
    for (var i = 0; i < list.length; i++) {
        if (list[i].dns)
            map[list[i].dns] = !!list[i].videoAllowPost;
    }
    return map;
}

// POST /community/update-logo (JWT) — platform branding. Backend requires
// logo_url + footer_logo_url; icon_url is optional. The mobile CMS only
// captures one uploaded image, so the same hosted URL is sent for all three
// (there's no separate footer/icon image picker here).
function updateLogo(baseUrl, token, logoUrl, onOk, onErr) {
    Http.post(baseUrl, "/community/update-logo",
              { logo_url: logoUrl, footer_logo_url: logoUrl, icon_url: logoUrl }, token,
              function (data) { onOk(data || {}); }, onErr);
}
