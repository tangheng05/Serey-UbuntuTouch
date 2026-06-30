.pragma library

/*
 * Image upload to Serey's media server. The server only accepts
 * multipart/form-data (field name `image`, header `api-secret`) and returns
 * { url }. QML's XMLHttpRequest has no FormData/File, so we read the picked
 * file's bytes and hand-build the multipart body as a single ArrayBuffer:
 *
 *   --BOUNDARY\r\n
 *   Content-Disposition: form-data; name="image"; filename="avatar.jpg"\r\n
 *   Content-Type: image/jpeg\r\n
 *   \r\n
 *   <raw file bytes>\r\n
 *   --BOUNDARY--\r\n
 *
 * Callbacks: onOk(url), onErr({ message }).
 */

function _ascii(str) {
    // Latin-1 bytes for the multipart envelope (header text is ASCII only).
    var out = new Uint8Array(str.length);
    for (var i = 0; i < str.length; i++)
        out[i] = str.charCodeAt(i) & 0xff;
    return out;
}

function _contentType(fileUrl) {
    var u = String(fileUrl).toLowerCase();
    if (u.indexOf(".png") >= 0) return { mime: "image/png", ext: "png" };
    if (u.indexOf(".gif") >= 0) return { mime: "image/gif", ext: "gif" };
    if (u.indexOf(".webp") >= 0) return { mime: "image/webp", ext: "webp" };
    return { mime: "image/jpeg", ext: "jpg" };
}

// The most recent in-flight request (reader or upload). PhotoUploader's
// watchdog calls abort() when QML's XMLHttpRequest hangs without honouring its
// own `timeout` — see PhotoUploader.qml. Only one upload runs at a time (every
// caller guards with an `uploading` flag), so a single handle is enough.
var _active = null;

function abort() {
    if (_active) {
        try { _active.abort(); } catch (e) { /* already done */ }
        _active = null;
    }
}

function uploadImage(uploadUrl, secret, fileUrl, onOk, onErr) {
    var type = _contentType(fileUrl);

    // 1. Read the local file's raw bytes.
    var reader = new XMLHttpRequest();
    _active = reader;
    reader.open("GET", fileUrl);
    reader.responseType = "arraybuffer";
    reader.onreadystatechange = function () {
        if (reader.readyState !== XMLHttpRequest.DONE)
            return;
        if (!reader.response) {
            _active = null;
            onErr({ message: "Couldn't read the selected image." });
            return;
        }
        try {
            _post(uploadUrl, secret, type, new Uint8Array(reader.response), onOk, onErr);
        } catch (e) {
            _active = null;
            onErr({ message: "Couldn't prepare the image for upload." });
        }
    };
    reader.send();
}

// --- Thumbnail (data URL) upload -----------------------------------------
// VideoThumbnailGrabber captures a frame as a "data:image/jpeg;base64,…" URL
// (QtMultimedia can't decode our confined local files, and grabToImage returns
// black on UT — so we read canvas pixels in-page). QML's JS engine has no atob,
// so decode base64 by hand into bytes and POST them with the normal `image`
// multipart envelope. Callbacks: onOk(url), onErr({ message }).
function _b64decode(s) {
    var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    var lookup = {};
    for (var i = 0; i < chars.length; i++) lookup[chars.charAt(i)] = i;
    s = s.replace(/[^A-Za-z0-9+/]/g, "");          // strip padding/whitespace
    var bytes = new Uint8Array(Math.floor(s.length * 3 / 4));
    var p = 0, buffer = 0, bits = 0;
    for (var j = 0; j < s.length; j++) {
        buffer = (buffer << 6) | lookup[s.charAt(j)];
        bits += 6;
        if (bits >= 8) { bits -= 8; bytes[p++] = (buffer >> bits) & 0xff; }
    }
    return bytes.subarray(0, p);
}

function uploadImageData(uploadUrl, secret, dataUrl, onOk, onErr) {
    var comma = String(dataUrl).indexOf(",");
    if (comma < 0) { onErr({ message: "Bad image data." }); return; }
    var bytes;
    try { bytes = _b64decode(dataUrl.substring(comma + 1)); }
    catch (e) { onErr({ message: "Couldn't decode the thumbnail." }); return; }
    if (!bytes || bytes.length === 0) { onErr({ message: "Empty thumbnail." }); return; }
    _post(uploadUrl, secret, { mime: "image/jpeg", ext: "jpg" }, bytes, onOk, onErr);
}

// --- Video upload --------------------------------------------------------
// The simple /uploads/upload_video endpoint accepts the same multipart envelope
// as images (field name `video`, header `api-secret`, returns { url }). QML's
// XMLHttpRequest reads the whole file into memory, so we cap well under the
// server's ~95 MB limit; larger files need the web's chunked S3 flow (TODO).
var MAX_VIDEO_BYTES = 90 * 1024 * 1024;

function _videoType(fileUrl) {
    var u = String(fileUrl).toLowerCase();
    if (u.indexOf(".webm") >= 0) return { mime: "video/webm", ext: "webm" };
    if (u.indexOf(".mov") >= 0)  return { mime: "video/quicktime", ext: "mov" };
    if (u.indexOf(".mkv") >= 0)  return { mime: "video/x-matroska", ext: "mkv" };
    if (u.indexOf(".ogv") >= 0 || u.indexOf(".ogg") >= 0) return { mime: "video/ogg", ext: "ogv" };
    if (u.indexOf(".mpeg") >= 0 || u.indexOf(".mpg") >= 0) return { mime: "video/mpeg", ext: "mpeg" };
    return { mime: "video/mp4", ext: "mp4" };   // most common; also the default ext
}

function uploadVideo(uploadUrl, secret, fileUrl, onOk, onErr) {
    var type = _videoType(fileUrl);
    var reader = new XMLHttpRequest();
    _active = reader;
    reader.open("GET", fileUrl);
    reader.responseType = "arraybuffer";
    reader.onreadystatechange = function () {
        if (reader.readyState !== XMLHttpRequest.DONE)
            return;
        if (!reader.response) {
            _active = null;
            onErr({ message: "Couldn't read the selected video." });
            return;
        }
        var bytes = new Uint8Array(reader.response);
        if (bytes.length > MAX_VIDEO_BYTES) {
            _active = null;
            onErr({ message: "Video is too large (max " + Math.round(MAX_VIDEO_BYTES / 1048576) + " MB)." });
            return;
        }
        try {
            _postVideo(uploadUrl, secret, type, bytes, onOk, onErr);
        } catch (e) {
            _active = null;
            onErr({ message: "Couldn't prepare the video for upload." });
        }
    };
    reader.send();
}

function _postVideo(uploadUrl, secret, type, fileBytes, onOk, onErr) {
    var boundary = "----SereyBoundary" + Date.now() + Math.floor(Math.random() * 1e9);
    var preamble = _ascii(
        "--" + boundary + "\r\n" +
        'Content-Disposition: form-data; name="video"; filename="video.' + type.ext + '"\r\n' +
        "Content-Type: " + type.mime + "\r\n\r\n");
    var trailer = _ascii("\r\n--" + boundary + "--\r\n");

    var body = new Uint8Array(preamble.length + fileBytes.length + trailer.length);
    body.set(preamble, 0);
    body.set(fileBytes, preamble.length);
    body.set(trailer, preamble.length + fileBytes.length);

    var xhr = new XMLHttpRequest();
    _active = xhr;
    xhr.open("POST", uploadUrl);
    xhr.setRequestHeader("Content-Type", "multipart/form-data; boundary=" + boundary);
    xhr.setRequestHeader("api-secret", secret);
    xhr.setRequestHeader("Accept", "application/json");
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE)
            return;
        _active = null;
        if (xhr.status === 0) {
            onErr({ message: "Network error during upload." });
            return;
        }
        var data = null;
        try { data = xhr.responseText ? JSON.parse(xhr.responseText) : null; }
        catch (e) { onErr({ message: "Upload server returned an invalid response." }); return; }
        var url = data && data.url;
        if (xhr.status >= 200 && xhr.status < 300 && url) {
            onOk(url);
        } else {
            var msg = (data && data.message) ? data.message : "Upload failed (" + xhr.status + ").";
            onErr({ message: msg });
        }
    };
    xhr.send(body.buffer);
}

function _post(uploadUrl, secret, type, fileBytes, onOk, onErr) {
    var boundary = "----SereyBoundary" + Date.now() + Math.floor(Math.random() * 1e9);
    var preamble = _ascii(
        "--" + boundary + "\r\n" +
        'Content-Disposition: form-data; name="image"; filename="avatar.' + type.ext + '"\r\n' +
        "Content-Type: " + type.mime + "\r\n\r\n");
    var trailer = _ascii("\r\n--" + boundary + "--\r\n");

    var body = new Uint8Array(preamble.length + fileBytes.length + trailer.length);
    body.set(preamble, 0);
    body.set(fileBytes, preamble.length);
    body.set(trailer, preamble.length + fileBytes.length);

    var xhr = new XMLHttpRequest();
    _active = xhr;
    xhr.open("POST", uploadUrl);
    xhr.setRequestHeader("Content-Type", "multipart/form-data; boundary=" + boundary);
    xhr.setRequestHeader("api-secret", secret);
    xhr.setRequestHeader("Accept", "application/json");
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE)
            return;
        _active = null;
        if (xhr.status === 0) {
            // status 0 at DONE means the request was aborted (by the watchdog)
            // or the network dropped; the caller surfaces the message.
            onErr({ message: "Network error during upload." });
            return;
        }
        var data = null;
        try { data = xhr.responseText ? JSON.parse(xhr.responseText) : null; }
        catch (e) { onErr({ message: "Upload server returned an invalid response." }); return; }
        var url = data && data.url;
        if (xhr.status >= 200 && xhr.status < 300 && url) {
            onOk(url);
        } else {
            var msg = (data && data.message) ? data.message : "Upload failed (" + xhr.status + ").";
            onErr({ message: msg });
        }
    };
    xhr.send(body.buffer);
}
