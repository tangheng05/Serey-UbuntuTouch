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

    // Scoped to the signed-in account so switching accounts shows a fresh list; logged-out saves (owner "") are their own bucket.
    function _owner() {
        return Session.isLoggedIn ? Session.username : "";
    }

    function _load() {
        var out = [];
        try {
            _db().transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS saved_posts(permlink TEXT, author TEXT, saved_at INTEGER, data TEXT, owner TEXT DEFAULT '', PRIMARY KEY(permlink, owner))");
                // Add `owner` to tables created before per-account scoping existed; harmlessly throws (caught) once the column is present.
                try { tx.executeSql("ALTER TABLE saved_posts ADD COLUMN owner TEXT DEFAULT ''"); } catch (e2) { }
                var rs = tx.executeSql("SELECT permlink, data FROM saved_posts WHERE owner = ? ORDER BY saved_at DESC", [store._owner()]);
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

    function _persist(post) {
        try {
            _db().transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS saved_posts(permlink TEXT, author TEXT, saved_at INTEGER, data TEXT, owner TEXT DEFAULT '', PRIMARY KEY(permlink, owner))");
                tx.executeSql("INSERT OR REPLACE INTO saved_posts(permlink, author, saved_at, data, owner) VALUES(?, ?, ?, ?, ?)",
                    [post.permlink, post.author || "", Date.now(), JSON.stringify(post), store._owner()]);
            });
        } catch (e) {
            console.log("SavedPosts persist error: " + e);
        }
    }

    function save(post) {
        if (!post || !post.permlink || post.permlink.length === 0) return;
        // Persist the text immediately, then cache images in the background and rewrite to local paths as they arrive.
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

    // Collect every remote http(s) image URL referenced by the post: cover thumbnail plus each <img src>/data-image-url in the body HTML.
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

    // Rewrite the saved copy's image URLs to downloaded local paths so it renders offline; failed downloads keep their remote URL.
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
                tx.executeSql("DELETE FROM saved_posts WHERE permlink = ? AND owner = ?", [permlink, store._owner()]);
            });
        } catch (e) {
            console.log("SavedPosts delete error: " + e);
        }
        store._load();
        Toast.show("Removed from saved");
    }

    Component.onCompleted: _load()

    // QtObject has no default property so this must be assigned, not a child; react to both username and token changes.
    property Connections _sessionWatcher: Connections {
        target: Session
        onUsernameChanged: store._load()
        onTokenChanged: store._load()
    }
}
