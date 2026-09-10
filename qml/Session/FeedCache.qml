pragma Singleton
import QtQuick 2.7
import QtQuick.LocalStorage 2.0

// Page-0 cache so a relaunch paints rows, not a skeleton; peek() is sync, request() coalesces callers
QtObject {
    id: store

    // key -> { items: [...], fetchedAt: ms }
    property var _mem: ({})
    // key -> [ { ok: fn, err: fn } ] while a request for that key is in flight
    property var _waiters: ({})
    property var _dbHandle: null

    // Enough to fill the first screen; this is a paint-fast cache, not an offline store
    readonly property int maxRows: 12
    // Rows older than this are dropped at load rather than shown stale
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
                    } catch (e) { /* unparseable row, treat as a miss */ }
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

    // Drop a key; put() refuses empty lists so this is needed to clear stale rows
    function remove(key) {
        delete store._mem[key];
        try {
            _db().transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS feed_cache(key TEXT PRIMARY KEY, fetched_at INTEGER, data TEXT)");
                tx.executeSql("DELETE FROM feed_cache WHERE key = ?", [key]);
            });
        } catch (e) {
            console.log("FeedCache remove error: " + e);
        }
    }

    function put(key, items) {
        var trimmed = (items || []).slice(0, store.maxRows);
        // Empty means "nothing to paint next time": clear, don't keep stale rows.
        if (trimmed.length === 0) { store.remove(key); return; }
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

    // `starter(ok, err)` fires the request and returns its xhr; null when joining an in-flight one
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

    // Keyed per account: server personalises the authed feed, so a shared key would leak
    function _who() {
        return (Session.isLoggedIn && Session.username && Session.username.length > 0)
                ? Session.username : "__guest__";
    }

    // `bucket` is the optional country category filter; callers that omit it keep
    // the key they always had, so the unfiltered feed's cache is untouched.
    function newsKey(feedIndex, communityId, bucket) {
        return "news:" + (feedIndex === 1 ? "new" : "trending") + ":" + communityId
               + (bucket ? ":" + String(bucket).toLowerCase() : "") + ":" + _who();
    }

    function videoKey(communityId) {
        return "video:" + communityId + ":" + _who();
    }

    Component.onCompleted: _load()
}
