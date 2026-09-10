pragma Singleton
import QtQuick 2.7
import "../services/FollowService.js" as FollowService

QtObject {
    id: store

    property int rev: 0
    property var _map: ({})      // author -> bool
    property var _busy: ({})     // author -> true while a status query is in flight
    property string _viewer: ""  // resets the cache when the logged-in user changes

    // Reactive read (touches `rev` so bindings depend on it).
    function isFollowing(author) { return rev >= 0 && !!_map[author]; }
    function known(author) { return rev >= 0 && _map.hasOwnProperty(author); }

    function _resetIfViewerChanged(viewer) {
        // Drop queue too: entries carry the previous viewer and would flush wrong-account
        if (_viewer !== viewer) { _map = ({}); _busy = ({}); _queue = []; _viewer = viewer; rev++; }
    }

    // Hold the first burst of ~10 status queries so thumbnails get the connection first
    property bool _warm: false
    property var _queue: []
    property Timer _burstTimer: Timer {
        interval: 1200
        repeat: false
        onTriggered: {
            store._warm = true;
            var q = store._queue;
            store._queue = [];
            for (var i = 0; i < q.length; i++)
                store._send(q[i].baseUrl, q[i].viewer, q[i].author);
        }
    }

    // Query a user's follow state once (no-op if already known or in flight).
    function load(baseUrl, viewer, author) {
        _resetIfViewerChanged(viewer);
        if (!author || _map.hasOwnProperty(author) || _busy[author]) return;
        if (!_warm) {
            // Mark busy now so the same author queued twice can't be sent twice on flush
            _busy[author] = true;
            _queue.push({ baseUrl: baseUrl, viewer: viewer, author: author });
            // start, not restart: restarting per author pushed the flush out indefinitely
            // while a list kept creating delegates
            if (!_burstTimer.running) _burstTimer.start();
            return;
        }
        _busy[author] = true;
        _send(baseUrl, viewer, author);
    }

    function _send(baseUrl, viewer, author) {
        FollowService.status(baseUrl, viewer, author,
            function (f) { delete store._busy[author]; store._map[author] = f; store.rev++; },
            function () { delete store._busy[author]; });
    }

    function set(author, val) { _map[author] = !!val; rev++; }

    // Flip optimistically, confirm with the server, revert on failure. Returns the optimistic state so the caller can toast.
    function toggle(baseUrl, author, token) {
        var was = !!_map[author];
        _map[author] = !was; rev++;
        FollowService.toggle(baseUrl, author, was, token,
            function (now) { store._map[author] = now; store.rev++; },
            function () { store._map[author] = was; store.rev++; });
        return !was;
    }

    function reset() { _map = ({}); _busy = ({}); _queue = []; _viewer = ""; rev++; }
}
