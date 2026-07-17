.pragma library

// Country detection via Cloudflare, mirroring fe-serey-web.
//
// The web reads Cloudflare's `cf-ipcountry` request header (see
// src/pages/api/geo/detect-country.js). A native client can't: Cloudflare adds
// that header to requests arriving at the origin, so only serey.io's own server
// sees it. `/cdn-cgi/trace` is Cloudflare's client-facing equivalent — served by
// the same edge, from the same IP lookup — and returns `loc=KH` in a plain-text
// key=value body. serey.io sits behind Cloudflare, so this is the direct route.
//
// If the edge can't be reached we fall back to serey.io's own geo route, which
// re-does cf-ipcountry server-side and then ip-api.com (the web's own fallback
// for non-Cloudflare traffic).
//
// Deliberately NOT via Http.js: these are serey.io, not the API base, need no
// auth, and must never trip the global 401 -> logout handler.
var TRACE_URL = "https://serey.io/cdn-cgi/trace";
var FALLBACK_URL = "https://serey.io/api/geo/detect-country";

// Cloudflare reports XX when it can't place the IP (Tor, some VPNs); the web
// guards on it too, so treat it as "not detected" rather than a country.
function _clean(code) {
    if (!code) return "";
    var c = String(code).trim().toUpperCase();
    return (c.length === 2 && c !== "XX") ? c : "";
}

function _parseTrace(body) {
    var lines = String(body || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        if (lines[i].indexOf("loc=") === 0)
            return _clean(lines[i].substring(4));
    }
    return "";
}

// onOk(iso2Uppercase) on success. Detection is a nice-to-have: every failure
// path just calls onErr (optional) and callers keep the undetected layout.
function detectCountry(onOk, onErr) {
    function fail() { if (onErr) onErr(); }

    function tryFallback() {
        var f = new XMLHttpRequest();
        f.onreadystatechange = function () {
            if (f.readyState !== XMLHttpRequest.DONE) return;
            if (f.status !== 200) { fail(); return; }
            try {
                var d = JSON.parse(f.responseText);
                // Match the web's guard (see cambodia/index.js): localhost and
                // unknown IPs answer status:true with NO countryCode, so
                // `status` alone is not enough. Read countryCode, not country —
                // on the Cloudflare path the name comes from a 6-entry map
                // (KH/BD/RU/UA/NL/VE) and is null everywhere else.
                var code = (d && d.status) ? _clean(d.countryCode) : "";
                if (code) onOk(code); else fail();
            } catch (e) { fail(); }
        };
        try { f.open("GET", FALLBACK_URL); f.send(); } catch (e2) { fail(); }
    }

    var xhr = new XMLHttpRequest();
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE) return;
        if (xhr.status !== 200) { tryFallback(); return; }
        var code = _parseTrace(xhr.responseText);
        if (code) onOk(code); else tryFallback();
    };
    try {
        xhr.open("GET", TRACE_URL);
        xhr.send();
    } catch (e3) {
        tryFallback();
    }
    return xhr;
}
