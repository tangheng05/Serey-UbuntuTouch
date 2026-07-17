pragma Singleton
import QtQuick 2.7
import QtQuick.LocalStorage 2.0

/*
 * Last-seen page-0 rows for the News and Video feeds, so a relaunch paints
 * content instead of a skeleton.
 *
 * Two jobs, deliberately separate:
 *   peek(key)    — the rows we last saw, available synchronously at page mount.
 *   request(...) — fire the real request, store the result, and coalesce callers.
 *
 * `request` never returns the cache; it always hits the network. Pages paint
 * peek() first and let request() replace those rows when it lands
 * (stale-while-revalidate), so the skeleton only ever shows on a cold cache.
 *
 * Coalescing matters because Main.qml prefetches these feeds at launch: without
 * it, a user who taps News while the prefetch is still in flight would fire a
 * second identical request. Same idea as FollowService's per-author coalescing.
 */
QtObject {
    id: store

    // key -> { items: [...], fetchedAt: ms }
    property var _mem: ({})
    // key -> [ { ok: fn, err: fn } ] while a request for that key is in flight
    property var _waiters: ({})
    property var _dbHandle: null

    // Enough to fill the first screen, no more. This is a paint-fast cache, not
    // an offline store — SavedPosts/Downloads are the real offline features.
    readonly property int maxRows: 12
    // Rows older than this are dropped at load: showing week-old rows for the
    // instant it takes to revalidate is worse than showing the skeleton.
    readonly property int maxAgeMs: 3 * 24 * 60 * 60 * 1000

    function _db() {
        if (!_dbHandle)
            _dbHandle = LocalStorage.openDatabaseSync("SereyFeedCache", "1.0", "Serey feed cache", 1000000);
        return _dbHandle;
    }

    function _load() {
        var mem = {};
        try {
            _db().transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS feed_cache(key TEXT PRIMARY KEY, fetched_at INTEGER, data TEXT)");
                tx.executeSql("DELETE FROM feed_cache WHERE fetched_at < ?", [Date.now() - store.maxAgeMs]);
                var rs = tx.executeSql("SELECT key, fetched_at, data FROM feed_cache");
                for (var i = 0; i < rs.rows.length; i++) {
                    var row = rs.rows.item(i);
                    try {
                        mem[row.key] = { items: JSON.parse(row.data), fetchedAt: row.fetched_at };
                    } catch (e) { /* unparseable row — treat as a miss */ }
                }
            });
        } catch (e) {
            console.log("FeedCache load error: " + e);
        }
        store._mem = mem;
    }

    // The rows to paint immediately, or null for a cold cache.
    function peek(key) {
        var e = store._mem[key];
        return (e && e.items && e.items.length > 0) ? e.items : null;
    }

    function put(key, items) {
        var trimmed = (items || []).slice(0, store.maxRows);
        if (trimmed.length === 0) return;
        var entry = { items: trimmed, fetchedAt: Date.now() };
        store._mem[key] = entry;
        try {
            _db().transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS feed_cache(key TEXT PRIMARY KEY, fetched_at INTEGER, data TEXT)");
                tx.executeSql("INSERT OR REPLACE INTO feed_cache(key, fetched_at, data) VALUES(?, ?, ?)",
                              [key, entry.fetchedAt, JSON.stringify(trimmed)]);
            });
        } catch (e) {
            console.log("FeedCache put error: " + e);
        }
    }

    /*
     * `starter(ok, err)` must fire the request and return its xhr.
     * Returns that xhr, or null when this call attached to an in-flight request
     * (nothing of its own to abort — callers already guard `if (inflight)`).
     * Callers keep their own reqEpoch guard: attaching means the response can
     * outlive a reload, exactly like a direct request would.
     */
    function request(key, starter, onOk, onErr) {
        if (store._waiters[key]) {
            store._waiters[key].push({ ok: onOk, err: onErr });
            return null;
        }
        store._waiters[key] = [{ ok: onOk, err: onErr }];
        return starter(function (result, rawCount) {
            var ws = store._waiters[key] || [];
            delete store._waiters[key];
            store.put(key, result);
            for (var i = 0; i < ws.length; i++)
                if (ws[i].ok) ws[i].ok(result, rawCount);
        }, function (err) {
            var ws = store._waiters[key] || [];
            delete store._waiters[key];
            for (var i = 0; i < ws.length; i++)
                if (ws[i].err) ws[i].err(err);
        });
    }

    // Keyed per account: the server personalises the authed blog feed (it drops
    // the viewer's own hidden posts), so a shared key would paint one user's
    // feed for another. Guest gets its own bucket.
    function _who() {
        return (Session.isLoggedIn && Session.username && Session.username.length > 0)
                ? Session.username : "__guest__";
    }

    function newsKey(feedIndex, communityId) {
        return "news:" + (feedIndex === 1 ? "new" : "trending") + ":" + communityId + ":" + _who();
    }

    function videoKey(communityId) {
        return "video:" + communityId + ":" + _who();
    }

    Component.onCompleted: _load()
}
