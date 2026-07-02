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
    _generation++;   // invalidate any scheduled tus continuation / status poll
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

// --- Video upload (tus → storage.serey.io) --------------------------------
// The dedicated storage API speaks the tus 1.0.0 resumable-upload protocol:
//   1. POST   {base}/files            (Upload-Length + Upload-Metadata) → Location
//   2. PATCH  Location                50 MB chunks (application/offset+octet-stream)
//   3. GET    {base}/videos/{id}/status  poll until server-side processing
//      (ffprobe validation + faststart remux + thumbnail) finishes
// Every request carries the shared key in `x-upload-key`. Chunks must stay
// under Cloudflare's 100 MB per-request proxy cap.
//
// Memory: CreateVideoPage installs a Serey.FileUtils FileChunkReader (C++)
// via setFileReader, so each 25 MB chunk is read from disk right before its
// PATCH — constant memory, files up to the server's 2 GB limit. Without the
// reader (shouldn't happen in a packaged build) we fall back to QML XHR's
// whole-file read, capped at 300 MB: holding a bigger file in RAM OOM-crashed
// phones (observed reboot at ~70-80% of a large upload).
// Callbacks: onOk(url, job), onErr({ message }), optional onProgress(percent).
var MAX_VIDEO_BYTES_STREAM = 2 * 1024 * 1024 * 1024;   // server maxSize
var MAX_VIDEO_BYTES_FALLBACK = 300 * 1024 * 1024;
var CHUNK_BYTES = 25 * 1024 * 1024;

// C++ FileChunkReader (Serey.FileUtils 1.0), installed by CreateVideoPage.
var _fileReader = null;
function setFileReader(reader) { _fileReader = reader; }

// Persisted resume record, so an upload interrupted by an app restart picks up
// where it left off (the server keeps incomplete tus uploads for 24h).
// CreateVideoPage installs a store backed by Qt Settings:
//   { get: function () -> string, set: function (string) }
var _uploadStore = null;
function setUploadStore(store) { _uploadStore = store; }

function _saveResume(fingerprint, location) {
    if (_uploadStore) _uploadStore.set(JSON.stringify({ f: fingerprint, l: location }));
}
function _loadResume(fingerprint) {
    if (!_uploadStore) return null;
    try {
        var rec = JSON.parse(_uploadStore.get() || "null");
        return (rec && rec.f === fingerprint) ? rec.l : null;
    } catch (e) { return null; }
}
function _clearResume() {
    if (_uploadStore) _uploadStore.set("");
}
var CHUNK_RETRIES = 3;
var STATUS_POLL_MS = 2000;
var STATUS_POLL_MAX = 150;          // give processing up to ~5 minutes

// Only types the storage API accepts (it rejects others with 415).
function _videoType(fileUrl) {
    var u = String(fileUrl).toLowerCase();
    if (u.indexOf(".webm") >= 0) return { mime: "video/webm", ext: "webm" };
    if (u.indexOf(".mov") >= 0)  return { mime: "video/quicktime", ext: "mov" };
    if (u.indexOf(".mkv") >= 0)  return { mime: "video/x-matroska", ext: "mkv" };
    if (u.indexOf(".avi") >= 0)  return { mime: "video/x-msvideo", ext: "avi" };
    if (u.indexOf(".mp4") >= 0 || u.indexOf(".m4v") >= 0) return { mime: "video/mp4", ext: "mp4" };
    return null;
}

// tus metadata values are base64; QML JS has no btoa (mirror of _b64decode).
function _b64encode(bytes) {
    var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    var out = "", i;
    for (i = 0; i + 2 < bytes.length; i += 3) {
        var n = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
        out += chars[(n >> 18) & 63] + chars[(n >> 12) & 63] + chars[(n >> 6) & 63] + chars[n & 63];
    }
    if (i + 1 === bytes.length) {
        out += chars[(bytes[i] >> 2) & 63] + chars[(bytes[i] << 4) & 63] + "==";
    } else if (i + 2 === bytes.length) {
        var m = (bytes[i] << 8) | bytes[i + 1];
        out += chars[(m >> 10) & 63] + chars[(m >> 4) & 63] + chars[(m << 2) & 63] + "=";
    }
    return out;
}

function _b64str(str) { return _b64encode(_ascii(str)); }

// Cancellation: clearVideo() calls abort(), which kills the in-flight xhr; the
// generation counter makes any still-scheduled continuation a no-op.
var _generation = 0;

function uploadVideo(storageBase, key, fileUrl, onOk, onErr, onProgress) {
    var base = String(storageBase).replace(/\/$/, "");
    var type = _videoType(fileUrl);
    if (!type) {
        onErr({ message: "Unsupported video type. Use mp4, mov, mkv, webm or avi." });
        return;
    }
    _generation++;
    var gen = _generation;
    var progress = onProgress || function () {};

    // Streaming path: read 25 MB slices from disk as each PATCH needs them.
    if (_fileReader) {
        var size = _fileReader.size(fileUrl);
        if (size <= 0) {
            onErr({ message: "Couldn't read the selected video." });
            return;
        }
        if (size > MAX_VIDEO_BYTES_STREAM) {
            onErr({ message: "Video is too large (max " + Math.round(MAX_VIDEO_BYTES_STREAM / 1073741824) + " GB)." });
            return;
        }
        var streamSource = {
            size: size,
            read: function (offset, end) {
                return _fileReader.read(fileUrl, offset, end - offset);
            },
        };
        _tusCreate(base, key, type, streamSource, String(fileUrl) + ":" + size, gen, onOk, onErr, progress);
        return;
    }

    // Fallback: whole-file XHR read (dev harness / missing plugin only).
    var reader = new XMLHttpRequest();
    _active = reader;
    reader.open("GET", fileUrl);
    reader.responseType = "arraybuffer";
    reader.onreadystatechange = function () {
        if (reader.readyState !== XMLHttpRequest.DONE || gen !== _generation)
            return;
        if (!reader.response) {
            _active = null;
            onErr({ message: "Couldn't read the selected video." });
            return;
        }
        var bytes = new Uint8Array(reader.response);
        if (bytes.length === 0) {
            _active = null;
            onErr({ message: "Selected video is empty." });
            return;
        }
        if (bytes.length > MAX_VIDEO_BYTES_FALLBACK) {
            _active = null;
            onErr({ message: "Video is too large (max " + Math.round(MAX_VIDEO_BYTES_FALLBACK / 1048576) + " MB)." });
            return;
        }
        var bufferSource = {
            size: bytes.length,
            read: function (offset, end) {
                return new Uint8Array(bytes.subarray(offset, end)).buffer;
            },
        };
        _tusCreate(base, key, type, bufferSource, String(fileUrl) + ":" + bytes.length, gen, onOk, onErr, progress);
    };
    reader.send();
}

// `source` abstracts where chunk bytes come from:
//   { size: <bytes>, read: function (offset, end) -> ArrayBuffer }
// If this exact file (url+size fingerprint) has a saved partial upload from a
// previous app run, ask the server how far it got and continue from there;
// otherwise create a fresh upload.
function _tusCreate(base, key, type, source, fingerprint, gen, onOk, onErr, onProgress) {
    var saved = _loadResume(fingerprint);
    if (!saved) {
        _tusStart(base, key, type, source, fingerprint, gen, onOk, onErr, onProgress);
        return;
    }
    var head = new XMLHttpRequest();
    _active = head;
    head.open("HEAD", saved);
    head.setRequestHeader("Tus-Resumable", "1.0.0");
    head.setRequestHeader("x-upload-key", key);
    head.onreadystatechange = function () {
        if (head.readyState !== XMLHttpRequest.DONE || gen !== _generation)
            return;
        _active = null;
        var offset = parseInt(head.getResponseHeader("Upload-Offset") || "-1", 10);
        if (head.status === 200 && offset >= 0 && offset < source.size) {
            onProgress(Math.round((offset / source.size) * 100));
            _tusPatch(base, key, saved, source, offset, 0, gen, onOk, onErr, onProgress);
        } else if (head.status === 200 && offset >= source.size) {
            // Fully uploaded last time; only processing/polling was cut short.
            _clearResume();
            _pollStatus(base, key, saved.replace(/\/$/, "").split("/").pop(), 0, gen, onOk, onErr);
        } else {
            // Expired or gone — start over cleanly.
            _clearResume();
            _tusStart(base, key, type, source, fingerprint, gen, onOk, onErr, onProgress);
        }
    };
    head.send();
}

function _tusStart(base, key, type, source, fingerprint, gen, onOk, onErr, onProgress) {
    var xhr = new XMLHttpRequest();
    _active = xhr;
    xhr.open("POST", base + "/files");
    xhr.setRequestHeader("Tus-Resumable", "1.0.0");
    xhr.setRequestHeader("Upload-Length", String(source.size));
    xhr.setRequestHeader("Upload-Metadata",
        "filename " + _b64str("video." + type.ext) + ",filetype " + _b64str(type.mime));
    xhr.setRequestHeader("x-upload-key", key);
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE || gen !== _generation)
            return;
        _active = null;
        if (xhr.status === 201) {
            var location = xhr.getResponseHeader("Location") || "";
            if (location.indexOf("http") !== 0)
                location = base + location;          // relative Location
            _saveResume(fingerprint, location);
            _tusPatch(base, key, location, source, 0, 0, gen, onOk, onErr, onProgress);
        } else if (xhr.status === 401) {
            onErr({ message: "Upload not authorized (bad upload key)." });
        } else if (xhr.status === 413) {
            onErr({ message: "Video is too large for the server." });
        } else if (xhr.status === 415) {
            onErr({ message: "The server doesn't accept this video type." });
        } else if (xhr.status === 0) {
            onErr({ message: "Network error starting the upload." });
        } else {
            onErr({ message: "Couldn't start the upload (" + xhr.status + ")." });
        }
    };
    xhr.send();
}

function _tusPatch(base, key, location, source, offset, attempt, gen, onOk, onErr, onProgress) {
    var end = Math.min(offset + CHUNK_BYTES, source.size);
    var chunk = source.read(offset, end);
    if (!chunk || chunk.byteLength === undefined || chunk.byteLength === 0) {
        onErr({ message: "Couldn't read the video while uploading." });
        return;
    }

    var xhr = new XMLHttpRequest();
    _active = xhr;
    xhr.open("PATCH", location);
    xhr.setRequestHeader("Tus-Resumable", "1.0.0");
    xhr.setRequestHeader("Upload-Offset", String(offset));
    xhr.setRequestHeader("Content-Type", "application/offset+octet-stream");
    xhr.setRequestHeader("x-upload-key", key);
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE || gen !== _generation)
            return;
        _active = null;
        if (xhr.status === 204 || xhr.status === 200) {
            var newOffset = parseInt(xhr.getResponseHeader("Upload-Offset") || String(end), 10);
            onProgress(Math.round((newOffset / source.size) * 100));
            if (newOffset >= source.size) {
                _clearResume();   // done — never resume into a finished upload
                var id = location.replace(/\/$/, "").split("/").pop();
                _pollStatus(base, key, id, 0, gen, onOk, onErr);
            } else {
                _tusPatch(base, key, location, source, newOffset, 0, gen, onOk, onErr, onProgress);
            }
        } else if (attempt < CHUNK_RETRIES && (xhr.status === 0 || xhr.status >= 500 || xhr.status === 409)) {
            // Transient failure: ask the server where it actually is (HEAD),
            // then resume from that offset. This is tus's whole point.
            _tusResume(base, key, location, source, attempt + 1, gen, onOk, onErr, onProgress);
        } else if (xhr.status === 0) {
            onErr({ message: "Network error during upload." });
        } else {
            onErr({ message: "Upload failed (" + xhr.status + ")." });
        }
    };
    xhr.send(chunk);
}

function _tusResume(base, key, location, source, attempt, gen, onOk, onErr, onProgress) {
    var xhr = new XMLHttpRequest();
    _active = xhr;
    xhr.open("HEAD", location);
    xhr.setRequestHeader("Tus-Resumable", "1.0.0");
    xhr.setRequestHeader("x-upload-key", key);
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE || gen !== _generation)
            return;
        _active = null;
        var offset = parseInt(xhr.getResponseHeader("Upload-Offset") || "-1", 10);
        if (xhr.status === 200 && offset >= 0) {
            _tusPatch(base, key, location, source, offset, attempt, gen, onOk, onErr, onProgress);
        } else if (attempt < CHUNK_RETRIES) {
            _tusResume(base, key, location, source, attempt + 1, gen, onOk, onErr, onProgress);
        } else {
            onErr({ message: "Lost connection to the upload server." });
        }
    };
    xhr.send();
}

// After the last chunk the server queues ffprobe/remux/thumbnail work; poll
// until it lands on ready (→ public URL) or failed.
function _pollStatus(base, key, id, tries, gen, onOk, onErr) {
    if (gen !== _generation)
        return;
    if (tries >= STATUS_POLL_MAX) {
        onErr({ message: "Video processing timed out. Try again later." });
        return;
    }
    var xhr = new XMLHttpRequest();
    _active = xhr;
    xhr.open("GET", base + "/videos/" + id + "/status");
    xhr.setRequestHeader("x-upload-key", key);
    xhr.setRequestHeader("Accept", "application/json");
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE || gen !== _generation)
            return;
        _active = null;
        var job = null;
        try { job = xhr.responseText ? JSON.parse(xhr.responseText) : null; }
        catch (e) { /* fall through to retry */ }
        if (job && job.state === "ready" && job.url) {
            onOk(job.url, job);
        } else if (job && job.state === "failed") {
            var reasons = {
                not_a_video: "That file isn't a playable video.",
                unsupported_codec: "This video's format isn't supported.",
                invalid_duration: "The video's length couldn't be read or is too long."
            };
            onErr({ message: reasons[job.error] || "The server couldn't process this video." });
        } else {
            // uploading/queued/processing (or a blip) — poll again.
            _delay(STATUS_POLL_MS, function () {
                _pollStatus(base, key, id, tries + 1, gen, onOk, onErr);
            });
        }
    };
    xhr.send();
}

// setTimeout doesn't exist in QML JS libraries; fake a delay with an XHR to a
// data: URL? No — Qt honours neither reliably. Callers must provide a Timer.
// Instead we lean on XMLHttpRequest's timeout: a GET to an unroutable address
// would be fragile, so the poll delay is driven by the page via _delayHook.
var _delayHook = null;   // set by the QML page: function (ms, fn)
function setDelayHook(fn) { _delayHook = fn; }
function _delay(ms, fn) {
    if (_delayHook) { _delayHook(ms, fn); return; }
    fn();   // no hook installed: poll immediately (still correct, just chattier)
}

// Delete a video that finished uploading but was never published (user backed
// out of the post after the upload completed). Best-effort: fire-and-forget,
// no retry — an orphaned file is a minor storage cost, not a correctness bug,
// and the caller is usually navigating away already.
function deleteVideo(storageBase, key, id) {
    if (!id) return;
    _clearResume();   // user discarded it; don't resume into a deleted upload
    var base = String(storageBase).replace(/\/$/, "");
    var xhr = new XMLHttpRequest();
    xhr.open("DELETE", base + "/videos/" + id);
    xhr.setRequestHeader("x-upload-key", key);
    xhr.send();
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
