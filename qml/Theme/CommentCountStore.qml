pragma Singleton
import QtQuick 2.7

/*
 * Single source of truth for a post's comment count, shared reactively across
 * every feed card (PostCard, GalleryCard) and the detail pages. Feed cards bind
 * their count once from the list model's `comments` field, so deleting (or
 * adding) a comment inside a detail page left the card behind it showing the
 * old number when the user went back.
 *
 * Mirrors FollowStore: cards read `countFor(permlink, fallback)`, which touches
 * the `rev` counter so the binding re-evaluates whenever any detail page calls
 * `set(permlink, n)`. Until a post is opened, `countFor` just returns the card's
 * own fallback (the server count), so nothing changes for untouched posts.
 */
QtObject {
    id: store

    property int rev: 0
    property var _map: ({})   // permlink -> latest known comment count

    // Reactive read: returns the override if we have one, else the card's own
    // server-provided fallback. Touches `rev` so bindings depend on it.
    function countFor(permlink, fallback) {
        return (rev >= 0 && permlink && _map.hasOwnProperty(permlink))
            ? _map[permlink] : fallback;
    }

    function set(permlink, n) {
        if (!permlink) return;
        _map[permlink] = Math.max(0, n | 0);
        rev++;
    }

    function reset() { _map = ({}); rev++; }
}
