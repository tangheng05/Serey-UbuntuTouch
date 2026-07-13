.pragma library

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

// Current in-flight request — PhotoUploader's watchdog calls abort() when
// XMLHttpRequest hangs without honouring its own `timeout`.
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
// VideoThumbnailGrabber hands us a "data:image/jpeg;base64,…" URL (canvas
// pixels read in-page — grabToImage returns black on UT). QML's JS engine
// has no atob, so decode base64 by hand.
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

// --- Video upload (tus → storage.serey.io, scoped per-upload token) --------
// Direct-creator-upload pattern (like S3 presigned URLs) — the app never
// holds the storage master key. Serey web backend mints a scoped per-upload
// token (POST createUploadUrl); chunks PATCH straight to storage.serey.io
// under the 100 MB Cloudflare proxy cap; statusUrl is polled until server-side
// processing (ffprobe/remux/thumbnail) finishes.
//
// Memory: CreateVideoPage's FileChunkReader (C++) streams each 25 MB chunk
// from disk, so RAM stays constant up to the server's 2 GB limit. Without it
// we fall back to a whole-file XHR read capped at 300 MB — bigger files OOM-
// crashed phones (observed reboot at ~70-80% of a large upload).
var MAX_VIDEO_BYTES_STREAM = 2 * 1024 * 1024 * 1024;   // server maxSize
var MAX_VIDEO_BYTES_FALLBACK = 300 * 1024 * 1024;
var CHUNK_BYTES = 25 * 1024 * 1024;

// C++ FileChunkReader (Serey.FileUtils 1.0), installed by CreateVideoPage.
var _fileReader = null;
function setFileReader(reader) { _fileReader = reader; }

// Persisted resume record (server keeps incomplete tus uploads for 24h). The
// scoped token can't be re-derived, so the whole session is stored, not just
// the fingerprint. CreateVideoPage installs a Qt Settings-backed store.
var _uploadStore = null;
function setUploadStore(store) { _uploadStore = store; }

function _saveResume(fingerprint, session) {
    if (_uploadStore) _uploadStore.set(JSON.stringify({
        f: fingerprint, l: session.uploadUrl, t: session.token, s: session.statusUrl
    }));
}
function _loadResume(fingerprint) {
    if (!_uploadStore) return null;
    try {
        var rec = JSON.parse(_uploadStore.get() || "null");
        return (rec && rec.f === fingerprint && rec.l && rec.t)
            ? { uploadUrl: rec.l, token: rec.t, statusUrl: rec.s }
            : null;
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

// Cancellation: clearVideo() calls abort(), which kills the in-flight xhr; the
// generation counter makes any still-scheduled continuation a no-op.
var _generation = 0;

function uploadVideo(createUploadUrl, sessionToken, fileUrl, onOk, onErr, onProgress) {
    var type = _videoType(fileUrl);
    if (!type) {
        onErr({ message: "Unsupported video type. Use mp4, mov, mkv, webm or avi." });
        return;
    }
    if (!sessionToken) {
        onErr({ message: "Please log in first." });
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
        _tusCreate(createUploadUrl, sessionToken, type, streamSource, String(fileUrl) + ":" + size, gen, onOk, onErr, progress);
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
        _tusCreate(createUploadUrl, sessionToken, type, bufferSource, String(fileUrl) + ":" + bytes.length, gen, onOk, onErr, progress);
    };
    reader.send();
}

// `source`: { size: <bytes>, read: function (offset, end) -> ArrayBuffer }
// Resumes a saved partial upload for this fingerprint if one exists, else
// starts a fresh session.
function _tusCreate(createUploadUrl, sessionToken, type, source, fingerprint, gen, onOk, onErr, onProgress) {
    var saved = _loadResume(fingerprint);
    if (!saved) {
        _tusStart(createUploadUrl, sessionToken, type, source, fingerprint, gen, onOk, onErr, onProgress);
        return;
    }
    var head = new XMLHttpRequest();
    _active = head;
    head.open("HEAD", saved.uploadUrl);
    head.setRequestHeader("Tus-Resumable", "1.0.0");
    head.setRequestHeader("x-upload-key", saved.token);
    head.onreadystatechange = function () {
        if (head.readyState !== XMLHttpRequest.DONE || gen !== _generation)
            return;
        _active = null;
        var offset = parseInt(head.getResponseHeader("Upload-Offset") || "-1", 10);
        if (head.status === 200 && offset >= 0 && offset < source.size) {
            onProgress(Math.round((offset / source.size) * 100));
            _tusPatch(saved, source, offset, 0, gen, onOk, onErr, onProgress);
        } else if (head.status === 200 && offset >= source.size) {
            // Fully uploaded last time; only processing/polling was cut short.
            _clearResume();
            _pollStatus(saved, 0, gen, onOk, onErr);
        } else {
            // Expired, gone, or the scoped token no longer valid — start over.
            _clearResume();
            _tusStart(createUploadUrl, sessionToken, type, source, fingerprint, gen, onOk, onErr, onProgress);
        }
    };
    head.send();
}

// Asks the Serey web backend (logged-in users only) to create the upload on
// the storage API and hand back the session: { uploadUrl, token, statusUrl }.
function _tusStart(createUploadUrl, sessionToken, type, source, fingerprint, gen, onOk, onErr, onProgress) {
    var xhr = new XMLHttpRequest();
    _active = xhr;
    xhr.open("POST", createUploadUrl);
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.setRequestHeader("Accept", "application/json");
    xhr.setRequestHeader("Authorization", "Bearer " + sessionToken);
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE || gen !== _generation)
            return;
        _active = null;
        var data = null;
        try { data = xhr.responseText ? JSON.parse(xhr.responseText) : null; }
        catch (e) { /* handled below */ }
        if (xhr.status === 200 && data && data.uploadUrl && data.token) {
            var session = {
                uploadUrl: data.uploadUrl,
                token: data.token,
                statusUrl: data.statusUrl
            };
            _saveResume(fingerprint, session);
            _tusPatch(session, source, 0, 0, gen, onOk, onErr, onProgress);
        } else if (xhr.status === 401) {
            onErr({ message: "Your session has expired. Please log in again." });
        } else if (xhr.status === 413) {
            onErr({ message: "Video is too large for the server." });
        } else if (xhr.status === 415) {
            onErr({ message: "The server doesn't accept this video type." });
        } else if (xhr.status === 429) {
            onErr({ message: "Too many uploads. Please try again later." });
        } else if (xhr.status === 0) {
            onErr({ message: "Network error starting the upload." });
        } else {
            onErr({ message: "Couldn't start the upload (" + xhr.status + ")." });
        }
    };
    xhr.send(JSON.stringify({
        filename: "video." + type.ext,
        filetype: type.mime,
        size: source.size
    }));
}

// `session` is { uploadUrl, token, statusUrl } — the scoped upload session
// minted by the web backend in _tusStart (or restored from the resume store).
function _tusPatch(session, source, offset, attempt, gen, onOk, onErr, onProgress) {
    var end = Math.min(offset + CHUNK_BYTES, source.size);
    var chunk = source.read(offset, end);
    if (!chunk || chunk.byteLength === undefined || chunk.byteLength === 0) {
        onErr({ message: "Couldn't read the video while uploading." });
        return;
    }

    var xhr = new XMLHttpRequest();
    _active = xhr;
    xhr.open("PATCH", session.uploadUrl);
    xhr.setRequestHeader("Tus-Resumable", "1.0.0");
    xhr.setRequestHeader("Upload-Offset", String(offset));
    xhr.setRequestHeader("Content-Type", "application/offset+octet-stream");
    xhr.setRequestHeader("x-upload-key", session.token);
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE || gen !== _generation)
            return;
        _active = null;
        if (xhr.status === 204 || xhr.status === 200) {
            var newOffset = parseInt(xhr.getResponseHeader("Upload-Offset") || String(end), 10);
            onProgress(Math.round((newOffset / source.size) * 100));
            if (newOffset >= source.size) {
                _clearResume();   // done — never resume into a finished upload
                _pollStatus(session, 0, gen, onOk, onErr);
            } else {
                _tusPatch(session, source, newOffset, 0, gen, onOk, onErr, onProgress);
            }
        } else if (attempt < CHUNK_RETRIES && (xhr.status === 0 || xhr.status >= 500 || xhr.status === 409)) {
            // Transient failure: ask the server where it actually is (HEAD),
            // then resume from that offset. This is tus's whole point.
            _tusResume(session, source, attempt + 1, gen, onOk, onErr, onProgress);
        } else if (xhr.status === 0) {
            onErr({ message: "Network error during upload." });
        } else {
            onErr({ message: "Upload failed (" + xhr.status + ")." });
        }
    };
    xhr.send(chunk);
}

function _tusResume(session, source, attempt, gen, onOk, onErr, onProgress) {
    var xhr = new XMLHttpRequest();
    _active = xhr;
    xhr.open("HEAD", session.uploadUrl);
    xhr.setRequestHeader("Tus-Resumable", "1.0.0");
    xhr.setRequestHeader("x-upload-key", session.token);
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE || gen !== _generation)
            return;
        _active = null;
        var offset = parseInt(xhr.getResponseHeader("Upload-Offset") || "-1", 10);
        if (xhr.status === 200 && offset >= 0) {
            _tusPatch(session, source, offset, attempt, gen, onOk, onErr, onProgress);
        } else if (attempt < CHUNK_RETRIES) {
            _tusResume(session, source, attempt + 1, gen, onOk, onErr, onProgress);
        } else {
            onErr({ message: "Lost connection to the upload server." });
        }
    };
    xhr.send();
}

// After the last chunk the server queues ffprobe/remux/thumbnail work; poll
// statusUrl until it lands on ready (→ public URL) or failed. The scoped
// token authorizes reading this one upload's status.
function _pollStatus(session, tries, gen, onOk, onErr) {
    if (gen !== _generation)
        return;
    if (tries >= STATUS_POLL_MAX) {
        onErr({ message: "Video processing timed out. Try again later." });
        return;
    }
    var xhr = new XMLHttpRequest();
    _active = xhr;
    xhr.open("GET", session.statusUrl);
    xhr.setRequestHeader("x-upload-key", session.token);
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
                _pollStatus(session, tries + 1, gen, onOk, onErr);
            });
        }
    };
    xhr.send();
}

// No setTimeout in QML JS libraries — the poll delay is driven by a Timer the
// QML page provides via _delayHook.
var _delayHook = null;   // set by the QML page: function (ms, fn)
function setDelayHook(fn) { _delayHook = fn; }
function _delay(ms, fn) {
    if (_delayHook) { _delayHook(ms, fn); return; }
    fn();   // no hook installed: poll immediately (still correct, just chattier)
}

// Deletes a video that finished uploading but was never published (the
// scoped upload token can't delete, so this goes through the web backend).
// Fire-and-forget: an orphaned file is a minor storage cost, not a bug.
function deleteVideo(deleteUploadUrl, sessionToken, id) {
    if (!id) return;
    _clearResume();   // user discarded it; don't resume into a deleted upload
    var xhr = new XMLHttpRequest();
    xhr.open("DELETE", deleteUploadUrl + "?type=videos&id=" + encodeURIComponent(id));
    xhr.setRequestHeader("Authorization", "Bearer " + sessionToken);
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
