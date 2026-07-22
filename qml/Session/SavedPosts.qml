pragma Singleton
import QtQuick 2.7
import QtQuick.LocalStorage 2.0
import "../Theme"

QtObject {
    id: store

    property var items: []   // saved post view-models, newest first
    property int rev: 0
    property var _dbHandle: null
    property var _dlComp: null

    function _db() {
        if (!_dbHandle)
            _dbHandle = LocalStorage.openDatabaseSync("SereySavedPosts", "1.0", "Serey saved articles", 1000000);
        return _dbHandle;
    }

    // guest bucket, avoids empty-string-as-NULL matching bug
    readonly property string guestOwner: "__guest__"

    function _owner() {
        return (Session.isLoggedIn && Session.username && Session.username.length > 0)
                ? Session.username : store.guestOwner;
    }

    // fold legacy NULL/'' owner rows onto guest bucket
    readonly property string _ownerExpr: "IFNULL(NULLIF(owner,''),'" + guestOwner + "')"

    function _load() {
        var out = [];
        try {
            _db().transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS saved_posts(permlink TEXT, author TEXT, saved_at INTEGER, data TEXT, owner TEXT DEFAULT '', PRIMARY KEY(permlink, owner))");
                // migrate old tables missing owner column
                try { tx.executeSql("ALTER TABLE saved_posts ADD COLUMN owner TEXT DEFAULT ''"); } catch (e2) { }
                var rs = tx.executeSql("SELECT permlink, data FROM saved_posts WHERE " + store._ownerExpr + " = ? ORDER BY saved_at DESC", [store._owner()]);
                var seen = {};
                for (var i = 0; i < rs.rows.length; i++) {
                    var row = rs.rows.item(i);
                    // dedupe legacy NULL-owner duplicates, newest wins
                    if (seen[row.permlink]) continue;
                    seen[row.permlink] = true;
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

    function _persist(post) {
        try {
            _db().transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS saved_posts(permlink TEXT, author TEXT, saved_at INTEGER, data TEXT, owner TEXT DEFAULT '', PRIMARY KEY(permlink, owner))");
                // explicit delete before insert, legacy NULL owner rows can't dedupe
                tx.executeSql("DELETE FROM saved_posts WHERE permlink = ? AND " + store._ownerExpr + " = ?", [post.permlink, store._owner()]);
                tx.executeSql("INSERT INTO saved_posts(permlink, author, saved_at, data, owner) VALUES(?, ?, ?, ?, ?)",
                    [post.permlink, post.author || "", Date.now(), JSON.stringify(post), store._owner()]);
            });
        } catch (e) {
            console.log("SavedPosts persist error: " + e);
        }
    }

    function save(post) {
        if (!post || !post.permlink || post.permlink.length === 0) return;
        // persist text now, cache images in background
        _persist(post);
        store._load();
        Toast.success("Saved for offline");
        store._cacheImages(post.permlink, post);
    }

    // --- Offline image caching ---------------------------------------------
    function _downloaderComponent() {
        if (_dlComp === null)
            _dlComp = Qt.createComponent(Qt.resolvedUrl("../components/VideoDownloader.qml"));
        return _dlComp;
    }

    // collect remote image URLs: thumbnail + body img/data-image-url
    function _imageUrls(post) {
        var urls = [];
        function add(u) { if (u && u.indexOf("http") === 0 && urls.indexOf(u) < 0) urls.push(u); }
        add(post.thumbnail || "");
        var body = post.body || "";
        var re = /(?:src|data-image-url)=["']([^"']+)["']/g;
        var m;
        while ((m = re.exec(body)) !== null) add(m[1]);
        return urls;
    }

    function _cacheImages(permlink, post) {
        var urls = _imageUrls(post);
        if (urls.length === 0) return;
        var comp = _downloaderComponent();
        if (!comp || comp.status === Component.Error) return;

        var map = {};                 // remote URL -> local file:// path
        var pending = urls.length;
        function done() { if (--pending === 0) store._applyLocalImages(permlink, map); }

        for (var i = 0; i < urls.length; i++) {
            (function (u) {
                var dl = comp.createObject(store, { url: u, title: "image", showInIndicator: false });
                if (!dl) { done(); return; }
                dl.finished.connect(function (path) {
                    map[u] = path.indexOf("file://") === 0 ? path : "file://" + path;
                    dl.destroy(); done();
                });
                dl.failed.connect(function () { dl.destroy(); done(); });   // keep remote URL on failure
                dl.start(u);
            })(urls[i]);
        }
    }

    // rewrite image URLs to local paths for offline rendering
    function _applyLocalImages(permlink, map) {
        var post = get(permlink);
        if (!post) return;
        var body = post.body || "";
        var thumb = post.thumbnail || "";
        for (var remote in map) {
            var local = map[remote];
            body = body.split(remote).join(local);     // string (not regex) replace-all
            if (thumb === remote) thumb = local;
        }
        post.body = body;
        post.thumbnail = thumb;
        _persist(post);
        store._load();
    }

    function remove(permlink) {
        try {
            _db().transaction(function (tx) {
                tx.executeSql("DELETE FROM saved_posts WHERE permlink = ? AND " + store._ownerExpr + " = ?", [permlink, store._owner()]);
            });
        } catch (e) {
            console.log("SavedPosts delete error: " + e);
        }
        store._load();
        Toast.show("Removed from saved");
    }

    Component.onCompleted: _load()

    // react to account changes
    property Connections _sessionWatcher: Connections {
        target: Session
        onUsernameChanged: store._load()
        onTokenChanged: store._load()
    }
}
