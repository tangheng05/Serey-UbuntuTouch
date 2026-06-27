.pragma library
.import "Http.js" as Http

/*
 * Following another author. `status` is public (no auth) so a feed card can
 * show the current state for any viewer; `toggle` requires the viewer's JWT
 * and flips follow/unfollow server-side based on the current state.
 *
 *   GET  /follow/status               username, author -> { is_following }
 *   POST /follow/follow-or-unfollow   { author, action_type } JWT
 *
 * `action_type` per the API: "follow" | "unfollow".
 */

// Feed cards ask for follow state once per visible card AND again on every
// ListView recycle, so an uncached `status` fires dozens–hundreds of identical
// requests while scrolling. Cache the result per author for the session, and
// coalesce concurrent first-time requests for the same author (`_pending`).
// The cache auto-resets when the viewer (logged-in user) changes.
var _cache = {};            // author -> bool
var _pending = {};          // author -> [ {onOk, onErr}, ... ]
var _cacheViewer = null;

function clearCache() { _cache = {}; _pending = {}; _cacheViewer = null; }

function status(baseUrl, viewerUsername, author, onOk, onErr) {
    if (_cacheViewer !== viewerUsername) { _cache = {}; _pending = {}; _cacheViewer = viewerUsername; }

    if (_cache.hasOwnProperty(author)) { onOk(_cache[author]); return; }

    if (_pending.hasOwnProperty(author)) { _pending[author].push({ onOk: onOk, onErr: onErr }); return; }
    _pending[author] = [{ onOk: onOk, onErr: onErr }];

    Http.get(baseUrl, "/follow/status", { username: viewerUsername, author: author }, null,
        function (data) {
            // The backend returns `following_status` (boolean). The older field
            // names are kept as fallbacks in case the endpoint shape changes.
            var f = !!(data && (data.following_status || data.is_following || data.following));
            _cache[author] = f;
            var waiters = _pending[author] || []; delete _pending[author];
            for (var i = 0; i < waiters.length; i++) waiters[i].onOk(f);
        },
        function (err) {
            var waiters = _pending[author] || []; delete _pending[author];
            for (var i = 0; i < waiters.length; i++) if (waiters[i].onErr) waiters[i].onErr(err);
        });
}

function toggle(baseUrl, author, isCurrentlyFollowing, token, onOk, onErr) {
    Http.post(baseUrl, "/follow/follow-or-unfollow",
        { author: author, action_type: isCurrentlyFollowing ? "unfollow" : "follow" },
        token,
        function () { var now = !isCurrentlyFollowing; _cache[author] = now; onOk(now); },
        onErr);
}
