.pragma library
.import "Http.js" as Http
.import "Mappers.js" as M

/*
 * Video endpoints under /video-component. We use /list-all-videos-by-author
 * (works with just limit/offset and returns { data: [...] }); the bare "/" and
 * /list-by-recommended endpoints currently return server errors upstream.
 */

function listVideos(baseUrl, params, token, onOk, onErr) {
    var path = params.community_id
        ? "/video-component/"
        : "/video-component/list-all-videos-by-author"
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
