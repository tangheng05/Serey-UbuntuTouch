.pragma library
.import "Http.js" as Http
.import "Mappers.js" as M

function listVideos(baseUrl, params, token, onOk, onErr) {
    var path = params.community_id
        ? "/video-component/"
        : "/video-component/list-all-videos-by-author"
    // Community endpoint defaults to curated order, burying fresh uploads — type=new sorts by created_at DESC to match the Global feed instead.
    if (params.community_id)
        params.type = "new";
    return Http.get(baseUrl, path, params, token, function (data) {
        var raw = data.data || [];
        onOk(raw.map(M.toVideo), raw.length);
    }, onErr);
}

function detail(baseUrl, author, permlink, token, onOk, onErr) {
    Http.get(baseUrl, "/video-component/detail-video-post",
             { author: author, permlink: permlink }, token, function (data) {
        var raw = data.post || data.content || data.data || {};
        onOk(M.toVideo(raw));
    }, onErr);
}

// --- Admin/CMS moderation (requires an owner/manager token) ----------------

// POST /video-component/up-or-down — move a video's position; direction is
// the obvious "up"/"down" string (backend schema not available in this repo).
function reorder(baseUrl, id, direction, token, onOk, onErr) {
    Http.post(baseUrl, "/video-component/up-or-down", { id: id, direction: direction }, token,
              function (data) { onOk(data || {}); }, onErr);
}

function pinOrUnpin(baseUrl, id, token, onOk, onErr) {
    Http.post(baseUrl, "/video-component/pin-or-unpin", { id: id }, token,
              function (data) { onOk(data || {}); }, onErr);
}

function toggleRecommended(baseUrl, id, token, onOk, onErr) {
    Http.post(baseUrl, "/video-component/add-or-remove-recommended", { id: id }, token,
              function (data) { onOk(data || {}); }, onErr);
}

function toggleSpecial(baseUrl, id, token, onOk, onErr) {
    Http.post(baseUrl, "/video-component/add-or-remove-special", { id: id }, token,
              function (data) { onOk(data || {}); }, onErr);
}
