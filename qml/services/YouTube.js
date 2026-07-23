.pragma library

// InnerTube clients tried in order; each returns progressive direct URLs without a PoToken in practice, falling through to the next on failure.
var CLIENTS = [
    {
        name: "IOS",
        nameNum: 5,
        version: "20.10.4",
        key: "AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc",
        userAgent: "com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)",
        extra: { deviceMake: "Apple", deviceModel: "iPhone16,2", osName: "iPhone", osVersion: "18.3.2.22D82" }
    },
    {
        name: "ANDROID",
        nameNum: 3,
        version: "20.10.38",
        key: "AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w",
        userAgent: "com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip",
        extra: { androidSdkVersion: 34, osName: "Android", osVersion: "14" }
    },
    {
        name: "MWEB",
        nameNum: 2,
        version: "2.20250101.00.00",
        key: "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8",
        userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Mobile/15E148 Safari/604.1",
        extra: { osName: "iPhone", osVersion: "18.3.0.22D60" }
    }
];

function extract(videoId, cb) {
    if (!videoId || videoId.length === 0) { cb(null, "No YouTube video id"); return; }
    _tryClient(videoId, 0, cb);
}

function _tryClient(videoId, idx, cb) {
    if (idx >= CLIENTS.length) { cb(null, "No downloadable stream found"); return; }
    var c = CLIENTS[idx];

    var xhr = new XMLHttpRequest();
    xhr.open("POST", "https://www.youtube.com/youtubei/v1/player?key=" + c.key + "&prettyPrint=false");
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.setRequestHeader("Accept", "application/json");
    xhr.setRequestHeader("X-YouTube-Client-Name", "" + c.nameNum);
    xhr.setRequestHeader("X-YouTube-Client-Version", c.version);
    // Qt's QML XHR allows User-Agent (unlike a browser); harmless if it doesn't.
    try { xhr.setRequestHeader("User-Agent", c.userAgent); } catch (e) {}

    xhr.timeout = 15000;
    xhr.ontimeout = function () { _tryClient(videoId, idx + 1, cb); };

    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE) return;
        var result = null;
        if (xhr.status === 200) {
            try { result = _parse(JSON.parse(xhr.responseText)); } catch (e) { result = null; }
        }
        if (result) cb(result, null);
        else _tryClient(videoId, idx + 1, cb);   // this client failed, try next
    };

    var client = { clientName: c.name, clientVersion: c.version, hl: "en", gl: "US" };
    for (var k in c.extra) client[k] = c.extra[k];

    xhr.send(JSON.stringify({
        context: { client: client },
        videoId: videoId,
        contentCheckOk: true,
        racyCheckOk: true
    }));
}

// Pick the best progressive MP4 with a ready-to-use direct URL, or null.
function _parse(data) {
    if (!data || !data.streamingData) return null;
    var ps = data.playabilityStatus;
    if (ps && ps.status && ps.status !== "OK") return null;   // login/age/geo gated

    var formats = data.streamingData.formats || [];   // progressive (audio+video)
    var best = null;
    for (var i = 0; i < formats.length; i++) {
        var f = formats[i];
        if (!f.url) continue;                                   // ciphered, skip
        if ((f.mimeType || "").indexOf("video/mp4") < 0) continue;
        if (!best || (f.height || 0) > (best.height || 0)) best = f;
    }
    if (!best) return null;

    var vd = data.videoDetails || {};
    return {
        url: best.url,
        height: best.height || 0,
        mimeType: best.mimeType || "",
        title: vd.title || "",
        durationSeconds: parseInt(vd.lengthSeconds || "0", 10)
    };
}
