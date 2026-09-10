.pragma library

// Fired on a 401 (expired/invalid JWT). Main.qml registers this once to clear the session and prompt re-login.
var _onUnauthorized = null;
function setUnauthorizedHandler(fn) { _onUnauthorized = fn; }

// Every request outcome doubles as a reachability sample; Main.qml pipes this into Theme/Net.
var _onNetworkStatus = null;
function setNetworkStatusHandler(fn) { _onNetworkStatus = fn; }
function _reportNet(reachable) { if (_onNetworkStatus) _onNetworkStatus(reachable); }

// How many requests are waiting for an answer. A dropped connection is only reported when a
// request finally times out, so Net watches this instead and probes while one is still hanging.
var _pending = 0;
var _onPending = null;
function setPendingHandler(fn) { _onPending = fn; }
function _pendingDelta(d) {
    _pending += d;
    if (_pending < 0) _pending = 0;
    if (_onPending) _onPending(_pending);
}
function pendingCount() { return _pending; }

function buildQuery(params) {
    if (!params)
        return "";
    var parts = [];
    for (var k in params) {
        var v = params[k];
        if (v === undefined || v === null || v === "")
            continue;
        parts.push(encodeURIComponent(k) + "=" + encodeURIComponent(v));
    }
    return parts.length ? "?" + parts.join("&") : "";
}

function send(method, url, token, bodyObj, onOk, onErr, timeoutMs) {
    var xhr = new XMLHttpRequest();
    xhr.open(method, url);
    xhr.setRequestHeader("Accept", "application/json");
    if (bodyObj)
        xhr.setRequestHeader("Content-Type", "application/json");
    if (token)
        xhr.setRequestHeader("Authorization", "Bearer " + token);

    // Without a timeout a stalled mobile request never resolves, leaving the caller's `loading` flag stuck true and permanently blocking pagination.
    // Callers doing an on-chain write pass a longer one: a broadcast outlives the default wait.
    xhr.timeout = timeoutMs || 15000;
    // One settle per request, whichever way it ends (abort() fires readystatechange too).
    var settled = false;
    function _settle() { if (settled) return; settled = true; _pendingDelta(-1); }
    xhr.ontimeout = function () {
        _settle();
        _reportNet(false);
        // `timeout: true` lets a caller tell "we stopped waiting" apart from "it failed".
        onErr({ status: 0, timeout: true, message: "Request timed out. Check your connection." });
    };

    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE)
            return;
        _settle();

        if (xhr.status === 0) {
            _reportNet(false);
            onErr({ status: 0, message: "Network error. Check your connection." });
            return;
        }
        _reportNet(true);

        var data = null;
        try {
            data = xhr.responseText ? JSON.parse(xhr.responseText) : null;
        } catch (e) {
            onErr({ status: xhr.status, message: "Invalid response from server." });
            return;
        }

        var logicalFail = data && data.status === false;
        if (xhr.status >= 200 && xhr.status < 300 && !logicalFail) {
            onOk(data);
        } else {
            // Pass the token this request used, so the handler can ignore a stale 401 from a previous account's dying request.
            if (xhr.status === 401 && token && _onUnauthorized)
                _onUnauthorized(token);
            var msg = (data && data.message) ? data.message
                                             : ("Request failed (" + xhr.status + ").");
            onErr({ status: xhr.status, message: msg, data: data });
        }
    };

    _pendingDelta(1);
    xhr.send(bodyObj ? JSON.stringify(bodyObj) : null);
    return xhr;   // returned so callers can abort() a stale/in-flight request
}

function get(baseUrl, path, params, token, onOk, onErr) {
    return send("GET", baseUrl + path + buildQuery(params), token, null, onOk, onErr);
}

function post(baseUrl, path, bodyObj, token, onOk, onErr, timeoutMs) {
    return send("POST", baseUrl + path, token, bodyObj || {}, onOk, onErr, timeoutMs);
}

function postForm(baseUrl, path, formBody, token, onOk, onErr) {
    var xhr = new XMLHttpRequest();
    xhr.open("POST", baseUrl + path);
    xhr.setRequestHeader("Accept", "application/json");
    xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
    if (token) xhr.setRequestHeader("Authorization", "Bearer " + token);
    xhr.timeout = 15000;
    xhr.ontimeout = function () { onErr({ status: 0, message: "Request timed out." }); };
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE) return;
        if (xhr.status === 0) { onErr({ status: 0, message: "Network error." }); return; }
        var data = null;
        try { data = xhr.responseText ? JSON.parse(xhr.responseText) : null; } catch (e) { }
        if (xhr.status >= 200 && xhr.status < 300) onOk(data);
        else onErr({ status: xhr.status, message: (data && data.message) || "Request failed.", data: data });
    };
    xhr.send(formBody);
    return xhr;
}

function put(baseUrl, path, bodyObj, token, onOk, onErr) {
    return send("PUT", baseUrl + path, token, bodyObj || {}, onOk, onErr);
}

// Verified: Qt 5.15's QML XHR does send a body with PATCH (unlike DELETE, which drops it).
function patch(baseUrl, path, bodyObj, token, onOk, onErr) {
    return send("PATCH", baseUrl + path, token, bodyObj || {}, onOk, onErr);
}

function del(baseUrl, path, token, onOk, onErr) {
    return send("DELETE", baseUrl + path, token, null, onOk, onErr);
}

// Some admin endpoints need a DELETE with a JSON body; `del()` sends none
function delWithBody(baseUrl, path, bodyObj, token, onOk, onErr) {
    return send("DELETE", baseUrl + path, token, bodyObj || {}, onOk, onErr);
}
