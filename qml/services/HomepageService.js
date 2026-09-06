.pragma library
.import "Http.js" as Http

// Does a community actually have a homepage of its own? The mini app falls back to
// the generic Serey landing page when it doesn't, so the Homepage tab is hidden by
// default in that case (Main.qml). Mirrors serey-cambodia-mini-app's [cid]/index.js:
// a hardcoded page for the ids below, else landing-page v2 / v1 content, else generic.

// Keep in sync with the hardcoded branches in the mini app's [cid]/index.js.
// 0/1 are Global, where the generic Serey page IS the right homepage.
var STATIC_IDS = {
    "0": true, "1": true,       // Global
    "3": true,                  // Cambodia
    "13": true,                 // Liberty
    "16": true,                 // pDoge
    "17": true,                 // SmartVey
    "26": true,                 // United States
    "46": true,                 // Khmer Ball
    "52": true,                 // Shadow of Utopia
    "58": true,                 // Bright Khmer
    "84": true,                 // USA Sport
    "98": true,                 // Web3 Nederland
    "99": true,                 // Netherlands
    "100": true,                // Vrij Nederland
    "101": true,                // Voetbal
    "113": true,                // IAO Asia
    "122": true,                // Web3 USA
    "145": true                 // Path of Change
};

var _cache = {};      // communityId -> bool
var _pending = {};    // communityId -> [ cb, ... ]

// true/false when settled, null when it still needs a round trip. Lets callers
// skip the async path entirely for Global and for anything asked about before.
function known(communityId) {
    var key = String(communityId);
    if (STATIC_IDS[key]) return true;
    return _cache.hasOwnProperty(key) ? _cache[key] : null;
}

function hasHomepage(baseUrl, communityId, onOk) {
    var key = String(communityId);
    var settled = known(communityId);
    if (settled !== null) { onOk(settled); return; }

    if (_pending.hasOwnProperty(key)) { _pending[key].push(onOk); return; }
    _pending[key] = [onOk];

    var v1 = null, v2 = null, failed = false;

    function hasContent(data) {
        var lp = data && data.landing_page;
        return !!(lp && lp.content && lp.content.length);
    }
    function settle() {
        if (v1 === null || v2 === null) return;
        var has = v1 || v2;
        // A failed lookup must not hide a homepage that may well exist: keep the tab
        // and leave it uncached so the next community switch asks again.
        if (!has && failed) has = true;
        else _cache[key] = has;
        var waiters = _pending[key] || [];
        delete _pending[key];
        for (var i = 0; i < waiters.length; i++) waiters[i](has);
    }

    // Own timeout rather than Http's 15s default: the Homepage tab holds its web view
    // back until this answers, so a slow lookup must not sit on a blank tab for long.
    Http.send("GET", baseUrl + "/landing-page-v2/get-by-community/" + key, null, null,
        function (data) { v2 = hasContent(data); settle(); },
        function () { v2 = false; failed = true; settle(); }, 6000);
    Http.send("GET", baseUrl + "/landing-page/get-landing-page-by-community/" + key, null, null,
        function (data) { v1 = hasContent(data); settle(); },
        function () { v1 = false; failed = true; settle(); }, 6000);
}
