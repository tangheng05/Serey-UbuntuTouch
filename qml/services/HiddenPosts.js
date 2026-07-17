.pragma library
.import QtQuick.LocalStorage 2.0 as LS

var _db = null

// loadAll() runs a full table scan, and the feeds call it on every response —
// including each pass of their "keep paging until a screenful survives" loop, so
// several times per cold start. Only hide() changes the set, so memoise the map
// and invalidate there.
var _cache = null

function _open() {
    if (!_db) {
        _db = LS.LocalStorage.openDatabaseSync("SereyhiddenPosts", "1.0", "Hidden posts", 1000000)
        // CREATE TABLE only on first open, since running a write transaction on every isHidden()/loadAll() call was needless work on the hot feed path.
        _db.transaction(function (tx) {
            tx.executeSql("CREATE TABLE IF NOT EXISTS hidden (permlink TEXT PRIMARY KEY)")
        })
    }
    return _db
}

function hide(permlink) {
    _open().transaction(function (tx) {
        tx.executeSql("INSERT OR IGNORE INTO hidden VALUES (?)", [permlink])
    })
    _cache = null
}

function isHidden(permlink) {
    var found = false
    _open().readTransaction(function (tx) {
        var rs = tx.executeSql("SELECT 1 FROM hidden WHERE permlink=? LIMIT 1", [permlink])
        found = rs.rows.length > 0
    })
    return found
}

// Returns a JS object { permlink: true } for fast lookup
function loadAll() {
    if (_cache) return _cache
    var map = {}
    _open().readTransaction(function (tx) {
        var rs = tx.executeSql("SELECT permlink FROM hidden")
        for (var i = 0; i < rs.rows.length; i++)
            map[rs.rows.item(i).permlink] = true
    })
    _cache = map
    return map
}
