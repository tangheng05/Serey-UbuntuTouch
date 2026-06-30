.pragma library
.import QtQuick.LocalStorage 2.0 as LS

var _db = null

function _open() {
    if (!_db)
        _db = LS.LocalStorage.openDatabaseSync("SereyhiddenPosts", "1.0", "Hidden posts", 1000000)
    _db.transaction(function (tx) {
        tx.executeSql("CREATE TABLE IF NOT EXISTS hidden (permlink TEXT PRIMARY KEY)")
    })
    return _db
}

function hide(permlink) {
    _open().transaction(function (tx) {
        tx.executeSql("INSERT OR IGNORE INTO hidden VALUES (?)", [permlink])
    })
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
    var map = {}
    _open().readTransaction(function (tx) {
        var rs = tx.executeSql("SELECT permlink FROM hidden")
        for (var i = 0; i < rs.rows.length; i++)
            map[rs.rows.item(i).permlink] = true
    })
    return map
}
