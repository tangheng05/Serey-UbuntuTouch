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
