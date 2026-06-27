pragma Singleton
import QtQuick 2.7
import "../services/FollowService.js" as FollowService

/*
 * Single source of truth for follow state, shared reactively across every
 * follow button in the app (feed cards, gallery cards, the profile view).
 * Previously each card held its own `isFollowing` boolean set once at bind
 * time, so following a user in one place left the others showing "Follow".
 *
 * Cards bind `isFollowing: FollowStore.isFollowing(author)` — reading the `rev`
 * counter inside the function makes that binding re-evaluate whenever any state
 * changes, so all buttons for the same author stay in sync. `rev` is bumped on
 * every mutation; the JS map itself is mutated in place.
 */
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
        if (_viewer !== viewer) { _map = ({}); _busy = ({}); _viewer = viewer; rev++; }
    }

    // Query a user's follow state once (no-op if already known or in flight).
    function load(baseUrl, viewer, author) {
        _resetIfViewerChanged(viewer);
        if (!author || _map.hasOwnProperty(author) || _busy[author]) return;
        _busy[author] = true;
        FollowService.status(baseUrl, viewer, author,
            function (f) { delete store._busy[author]; store._map[author] = f; store.rev++; },
            function () { delete store._busy[author]; });
    }

    function set(author, val) { _map[author] = !!val; rev++; }

    // Optimistically flip now, confirm with the server, revert on failure.
    // Returns the optimistic new state so the caller can show a toast.
    function toggle(baseUrl, author, token) {
        var was = !!_map[author];
        _map[author] = !was; rev++;
        FollowService.toggle(baseUrl, author, was, token,
            function (now) { store._map[author] = now; store.rev++; },
            function () { store._map[author] = was; store.rev++; });
        return !was;
    }

    function reset() { _map = ({}); _busy = ({}); _viewer = ""; rev++; }
}
