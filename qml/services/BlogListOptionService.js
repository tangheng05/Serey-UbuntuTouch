.pragma library
.import "Http.js" as Http

/*
 * Per-community blog visibility toggle under /blog-list-option (JWT-protected).
 */

function getByCommunity(baseUrl, communityId, token, onOk, onErr) {
    Http.get(baseUrl, "/blog-list-option/list-by-community-id/" + communityId, {}, token, function (data) {
        onOk(data.data || data || {});
    }, onErr);
}

function updateIsShow(baseUrl, communityId, isShow, token, onOk, onErr) {
    Http.post(baseUrl, "/blog-list-option/update-is-show",
              { community_id: communityId, is_show: isShow }, token,
              function (data) { onOk(data || {}); }, onErr);
}
