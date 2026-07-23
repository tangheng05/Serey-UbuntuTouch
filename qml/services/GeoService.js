.pragma library

// Country detection: a native client can't read cf-ipcountry (origin-only header),
// so use Cloudflare's client-facing /cdn-cgi/trace (loc=XX), falling back to
// serey.io's own geo route. Not via Http.js: no auth, must never trip the 401 handler.
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
                // Unknown IPs answer status:true with NO countryCode, so check
                // countryCode itself (country is null outside a 6-entry map).
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
