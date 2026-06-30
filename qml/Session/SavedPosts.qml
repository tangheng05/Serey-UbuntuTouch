pragma Singleton
import QtQuick 2.7
import QtQuick.LocalStorage 2.0
import "../Theme"

/*
 * Registry of blog/news articles saved for offline reading — the text-content
 * counterpart of Downloads.qml (which saves video files). An article is just its
 * already-loaded view-model (title + full body HTML + author/date/thumbnail), so
 * there's nothing to stream: we persist the view-model JSON in SQLite (commits
 * synchronously, surviving a swipe-kill, same as Session/Downloads) and the
 * detail page renders straight from it when offline.
 *
 * `items` is reassigned wholesale and `rev` bumped on every change so QML
 * bindings that read isSaved()/get() re-evaluate.
 *
 * Note: body images are remote URLs, so they need a connection to render; the
 * article TEXT reads fully offline.
 */
QtObject {
    id: store

    property var items: []   // saved post view-models, newest first
    property int rev: 0
    property var _dbHandle: null

    function _db() {
        if (!_dbHandle)
            _dbHandle = LocalStorage.openDatabaseSync("SereySavedPosts", "1.0", "Serey saved articles", 1000000);
        return _dbHandle;
    }

    function _load() {
        var out = [];
        try {
            _db().transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS saved_posts(permlink TEXT PRIMARY KEY, author TEXT, saved_at INTEGER, data TEXT)");
                var rs = tx.executeSql("SELECT permlink, data FROM saved_posts ORDER BY saved_at DESC");
                for (var i = 0; i < rs.rows.length; i++) {
                    var row = rs.rows.item(i);
                    var vm = {};
                    try { vm = JSON.parse(row.data); } catch (e) { vm = {}; }
                    vm.permlink = row.permlink;
                    out.push(vm);
                }
            });
        } catch (e) {
            console.log("SavedPosts load error: " + e);
        }
        store.items = out;
        store.rev++;
    }

    function isSaved(permlink) {
        for (var i = 0; i < items.length; i++)
            if (items[i].permlink === permlink) return true;
        return false;
    }

    function get(permlink) {
        for (var i = 0; i < items.length; i++)
            if (items[i].permlink === permlink) return items[i];
        return null;
    }

    function save(post) {
        if (!post || !post.permlink || post.permlink.length === 0) return;
        try {
            _db().transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS saved_posts(permlink TEXT PRIMARY KEY, author TEXT, saved_at INTEGER, data TEXT)");
                tx.executeSql("INSERT OR REPLACE INTO saved_posts(permlink, author, saved_at, data) VALUES(?, ?, ?, ?)",
                    [post.permlink, post.author || "", Date.now(), JSON.stringify(post)]);
            });
        } catch (e) {
            console.log("SavedPosts save error: " + e);
        }
        store._load();
        Toast.success("Saved for offline");
    }

    function remove(permlink) {
        try {
            _db().transaction(function (tx) {
                tx.executeSql("DELETE FROM saved_posts WHERE permlink = ?", [permlink]);
            });
        } catch (e) {
            console.log("SavedPosts delete error: " + e);
        }
        store._load();
        Toast.show("Removed from saved");
    }

    Component.onCompleted: _load()
}
