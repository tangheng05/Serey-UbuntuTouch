.pragma library

// Country detection via Cloudflare's /cdn-cgi/trace, falling back to serey.io's geo route
var TRACE_URL = "https://serey.io/cdn-cgi/trace";
var FALLBACK_URL = "https://serey.io/api/geo/detect-country";

// Cloudflare reports XX when it can't place the IP; treat as "not detected"
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

// onOk(iso2Uppercase) on success; detection is a nice-to-have, failures are silent
function detectCountry(onOk, onErr) {
    function fail() { if (onErr) onErr(); }

    function tryFallback() {
        var f = new XMLHttpRequest();
        f.onreadystatechange = function () {
            if (f.readyState !== XMLHttpRequest.DONE) return;
            if (f.status !== 200) { fail(); return; }
            try {
                var d = JSON.parse(f.responseText);
                // Unknown IPs answer status:true with NO countryCode
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
