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
        // Drop the queue too: those entries carry the previous viewer and would
        // flush a logged-out (or wrong-account) query after the switch.
        if (_viewer !== viewer) { _map = ({}); _busy = ({}); _queue = []; _viewer = viewer; rev++; }
    }

    /*
     * The first feed paints ~10 cards at once and each asks for its author's
     * follow state, so a burst of /follow/status requests left the gate at the
     * exact moment the thumbnails did — and thumbnails are what the user is
     * actually waiting to see. Hold the first burst briefly so images get the
     * connection first; the buttons just render "Follow" until it lands, which
     * they already did while the request was in flight.
     *
     * Only the first burst waits. Once flushed, `_warm` sends later queries
     * (scrolling, new cards) straight out with no delay.
     */
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
            // Mark busy now so the same author queued twice (ListView recycling)
            // can't be sent twice on flush.
            _busy[author] = true;
            _queue.push({ baseUrl: baseUrl, viewer: viewer, author: author });
            _burstTimer.restart();
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

    // Optimistically flip now, confirm with the server, revert on failure — returns the optimistic state so the caller can toast.
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
