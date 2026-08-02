.pragma library
.import QtQuick.LocalStorage 2.0 as LS

var _db = null

// loadAll() does a full table scan; memoise and let writers below invalidate
var _cache = null

function _invalidate() { _cache = null }

function _open() {
    if (!_db) {
        _db = LS.LocalStorage.openDatabaseSync("SereyBlockedUsers", "1.0", "Blocked users", 1000000)
        // CREATE TABLE only on first open, not on every call, since a write transaction per call would be needless work on the hot feed path.
        _db.transaction(function (tx) {
            tx.executeSql("CREATE TABLE IF NOT EXISTS blocked (username TEXT PRIMARY KEY)")
        })
    }
    return _db
}

function add(username) {
    if (!username) return
    _open().transaction(function (tx) {
        tx.executeSql("INSERT OR IGNORE INTO blocked VALUES (?)", [username])
    })
    _invalidate()
}

function remove(username) {
    if (!username) return
    _open().transaction(function (tx) {
        tx.executeSql("DELETE FROM blocked WHERE username=?", [username])
    })
    _invalidate()
}

// Replace the whole set with the authoritative server list (startup sync).
function replaceAll(usernames) {
    _open().transaction(function (tx) {
        tx.executeSql("DELETE FROM blocked")
        for (var i = 0; i < usernames.length; i++)
            if (usernames[i])
                tx.executeSql("INSERT OR IGNORE INTO blocked VALUES (?)", [usernames[i]])
    })
    _invalidate()
}

// Returns a JS object { username: true } for fast per-load lookup.
function loadAll() {
    if (_cache) return _cache
    var map = {}
    _open().readTransaction(function (tx) {
        var rs = tx.executeSql("SELECT username FROM blocked")
        for (var i = 0; i < rs.rows.length; i++)
            map[rs.rows.item(i).username] = true
    })
    _cache = map
    return map
}
