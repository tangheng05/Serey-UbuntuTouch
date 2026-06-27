.pragma library

/*
 * Low-level HTTP helper built on QML's XMLHttpRequest. Every API call in the
 * app goes through here. Callbacks are used (no Promises in this Qt JS engine):
 *   onOk(parsedJson)
 *   onErr({ status, message, data })
 *
 * Note: the Serey API returns HTTP 200 with `{ "status": false, "message": ... }`
 * for logical failures (e.g. "User not found!"), so we treat status===false as
 * an error too.
 */

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

function send(method, url, token, bodyObj, onOk, onErr) {
    var xhr = new XMLHttpRequest();
    xhr.open(method, url);
    xhr.setRequestHeader("Accept", "application/json");
    if (bodyObj)
        xhr.setRequestHeader("Content-Type", "application/json");
    if (token)
        xhr.setRequestHeader("Authorization", "Bearer " + token);

    // Without a timeout a stalled mobile request never resolves, leaving the
    // caller's `loading` flag stuck true and permanently blocking pagination.
    xhr.timeout = 15000;
    xhr.ontimeout = function () {
        onErr({ status: 0, message: "Request timed out. Check your connection." });
    };

    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE)
            return;

        if (xhr.status === 0) {
            onErr({ status: 0, message: "Network error. Check your connection." });
            return;
        }

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
            var msg = (data && data.message) ? data.message
                                             : ("Request failed (" + xhr.status + ").");
            onErr({ status: xhr.status, message: msg, data: data });
        }
    };

    xhr.send(bodyObj ? JSON.stringify(bodyObj) : null);
    return xhr;   // returned so callers can abort() a stale/in-flight request
}

function get(baseUrl, path, params, token, onOk, onErr) {
    return send("GET", baseUrl + path + buildQuery(params), token, null, onOk, onErr);
}

function post(baseUrl, path, bodyObj, token, onOk, onErr) {
    return send("POST", baseUrl + path, token, bodyObj || {}, onOk, onErr);
}

function del(baseUrl, path, token, onOk, onErr) {
    return send("DELETE", baseUrl + path, token, null, onOk, onErr);
}
