.pragma library
.import "Http.js" as Http

// AI TL;DR; server caches per author/permlink/language. cacheOnly never generates.
function summarize(baseUrl, post, token, lang, cacheOnly, onOk, onErr) {
    var body = {
        author: post.author || "",
        permlink: post.permlink || "",
        language: lang || "en",
        cache_only: !!cacheOnly
    };
    Http.post(baseUrl, "/serey-web/summarize-post", body, token, function (data) {
        var d = (data && data.data) || {};
        var bullets = d.bullets;
        if (!Array.isArray(bullets)) bullets = [];
        onOk({
            bullets: bullets,
            readMinutes: parseInt(d.read_minutes, 10) || 1,
            cached: !!d.cached
        });
    }, onErr);
}
