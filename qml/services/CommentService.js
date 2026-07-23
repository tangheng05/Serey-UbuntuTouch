.pragma library
.import "Http.js" as Http

function create(baseUrl, params, token, onOk, onErr) {
    var body = {
        parent_author: params.parentAuthor,
        parent_permlink: params.parentPermlink,
        maincategory: params.maincategory || "serey",
        body: params.body
    };
    if (params.permlink)
        body.permlink = params.permlink;
    Http.post(baseUrl, "/serey-web/create-or-update-comment", body, token,
              function (data) { onOk(data || {}); }, onErr);
}

// Delete a comment (or post); backend authorises against the token's username.
// Uses the POST alias because Qt's QML XMLHttpRequest can't attach a body to DELETE.
function remove(baseUrl, permlink, username, token, onOk, onErr) {
    Http.post(baseUrl, "/serey-web/delete-post-or-comment",
              { username: username, permlink: permlink }, token,
              function (data) { onOk(data || {}); }, onErr);
}
