.pragma library
.import "Http.js" as Http

// Bug / feedback / feature-request reports. JWT required.
// Backend: serey-api src/routes/ubuntu_report_route.js, mounted at /ubuntu-app/report.
// Delta Chat notification + own DB row (ubuntu_reports). View/delete own only — no edit.

var BASE = "/ubuntu-app/report";

function submit(baseUrl, token, payload, onOk, onErr) {
    var body = { description: payload.description };
    if (payload.imageUrls && payload.imageUrls.length) body.image_urls = payload.imageUrls;
    if (payload.videoUrls && payload.videoUrls.length) body.video_urls = payload.videoUrls;
    if (payload.videoThumbUrls && payload.videoThumbUrls.length) body.video_thumb_urls = payload.videoThumbUrls;
    if (payload.deviceInfo) body.device_info = payload.deviceInfo;
    Http.post(baseUrl, BASE, body, token,
              function (data) { onOk(mapReport(data && data.data)); }, onErr);
}

function myReports(baseUrl, token, onOk, onErr) {
    Http.get(baseUrl, BASE + "/mine", null, token, function (data) {
        var arr = (data && data.data) || [];
        if (!Array.isArray(arr)) arr = [];
        onOk(arr.map(mapReport));
    }, onErr);
}

function removeOwn(baseUrl, token, id, onOk, onErr) {
    Http.del(baseUrl, BASE + "/" + id, token, onOk, onErr);
}

function _asArray(v) {
    if (typeof v === "string") {
        try { v = JSON.parse(v); } catch (e) { v = []; }
    }
    return Array.isArray(v) ? v : [];
}

function mapReport(r) {
    r = r || {};
    var imgs = _asArray(r.image_urls);
    var vids = _asArray(r.video_urls);
    var vidThumbs = _asArray(r.video_thumb_urls);
    return {
        id: r.id,
        description: r.description || "",
        images: imgs,
        videos: vids,
        videoThumbs: vidThumbs,
        // Joined for the ListModel: array fields come back wrapped and lose .length there.
        imagesStr: imgs.join("\n"),
        videosStr: vids.join("\n"),
        videoThumbsStr: vidThumbs.join("\n"),
        createdAt: r.created_at || r.createdAt || ""
    };
}
