.pragma library
.import "Http.js" as Http
.import "Mappers.js" as M

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

// Convenience: build a { dns: allowPost(bool) } map from listAll's result, used to gate the compose buttons.
function allowPostMap(list) {
    var map = {};
    for (var i = 0; i < list.length; i++) {
        if (list[i].dns)
            map[list[i].dns] = !!list[i].allowPost;
    }
    return map;
}

// Gates the Video upload FAB — independent of allowPostMap (the blog flag)
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
