.pragma library
.import "Http.js" as Http
.import "Mappers.js" as M

function listVideos(baseUrl, params, token, onOk, onErr) {
    var path = params.community_id
        ? "/video-component/"
        : "/video-component/list-all-videos-by-author"
    // Community endpoint defaults to curated order, burying fresh uploads —
    // type=new sorts by created_at DESC to match the Global feed instead.
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
