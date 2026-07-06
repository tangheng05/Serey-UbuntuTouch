pragma Singleton
import QtQuick 2.7
import QtQuick.LocalStorage 2.0
import "../Theme"

/*
 * Registry of videos saved for offline playback, persisted in SQLite using the
 * same QtQuick.LocalStorage approach as Session.qml: transactions commit
 * synchronously, so a saved video survives a swipe-kill (Qt.labs.Settings would
 * buffer and lose it).
 *
 * Scope: Serey-hosted / direct-file videos only. The gate is the caller's
 * VideoDetailPage.remoteDirectUrl(), which is empty for YouTube/TikTok/Facebook
 * embeds — there are no bytes to download for those. The actual transfer runs in
 * the Lomiri.DownloadManager system daemon via VideoDownloader.qml, created
 * lazily and guarded so the desktop preview (no daemon) degrades to a disabled
 * feature instead of crashing.
 *
 * Reactivity: `items` is reassigned wholesale and `rev` is bumped on every
 * change (including in-flight progress) so QML bindings that read isSaved() /
 * activeFor() / pathFor() re-evaluate — plain array/map mutation isn't reactive.
 */
QtObject {
    id: store

    // Saved view-models (the original video object + { localPath }), newest first.
    property var items: []
    // Bumped on every mutation so UI re-reads the lookup helpers.
    property int rev: 0

    // permlink -> { progress, downloader } for downloads in flight.
    property var _active: ({})
    // permlink -> file:// poster path, and the live poster downloaders.
    property var _pendingThumb: ({})
    property var _thumbDls: ({})
    property var _comp: null
    property var _dbHandle: null

    function _db() {
        if (!_dbHandle)
            _dbHandle = LocalStorage.openDatabaseSync("SereyDownloads", "1.0", "Serey offline videos", 1000000);
        return _dbHandle;
    }

    // Scoped to the signed-in account so switching accounts shows a fresh list;
    // logged-out downloads (owner "") are their own bucket.
    function _owner() {
        return Session.isLoggedIn ? Session.username : "";
    }

    function _load() {
        var out = [];
        try {
            _db().transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS downloads(permlink TEXT, local_path TEXT, saved_at INTEGER, data TEXT, owner TEXT DEFAULT '', PRIMARY KEY(permlink, owner))");
                try { tx.executeSql("ALTER TABLE downloads ADD COLUMN owner TEXT DEFAULT ''"); } catch (e2) { }
                var rs = tx.executeSql("SELECT permlink, local_path, data FROM downloads WHERE owner = ? ORDER BY saved_at DESC", [store._owner()]);
                for (var i = 0; i < rs.rows.length; i++) {
                    var row = rs.rows.item(i);
                    var vm = {};
                    try { vm = JSON.parse(row.data); } catch (e) { vm = {}; }
                    vm.permlink = row.permlink;
                    vm.localPath = row.local_path;
                    out.push(vm);
                }
            });
        } catch (e) {
            console.log("Downloads load error: " + e);
        }
        store.items = out;
        store.rev++;
    }

    function _persist(vm, localPath) {
        try {
            _db().transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS downloads(permlink TEXT, local_path TEXT, saved_at INTEGER, data TEXT, owner TEXT DEFAULT '', PRIMARY KEY(permlink, owner))");
                tx.executeSql("INSERT OR REPLACE INTO downloads(permlink, local_path, saved_at, data, owner) VALUES(?, ?, ?, ?, ?)",
                    [vm.permlink, localPath, Date.now(), JSON.stringify(vm), store._owner()]);
            });
        } catch (e) {
            console.log("Downloads persist error: " + e);
        }
    }

    function _deleteRow(permlink) {
        try {
            _db().transaction(function (tx) {
                tx.executeSql("DELETE FROM downloads WHERE permlink = ? AND owner = ?", [permlink, store._owner()]);
            });
        } catch (e) {
            console.log("Downloads delete error: " + e);
        }
    }

    function isSaved(permlink) {
        for (var i = 0; i < items.length; i++)
            if (items[i].permlink === permlink) return true;
        return false;
    }

    // file://-prefixed URL ready for QtMultimedia / Chromium <video>, or "".
    function pathFor(permlink) {
        for (var i = 0; i < items.length; i++) {
            if (items[i].permlink === permlink) {
                var p = items[i].localPath || "";
                if (p.length === 0) return "";
                return p.indexOf("file://") === 0 ? p : "file://" + p;
            }
        }
        return "";
    }

    function activeFor(permlink) {
        return _active[permlink] || null;
    }

    function _downloaderComponent() {
        if (_comp === null)
            _comp = Qt.createComponent(Qt.resolvedUrl("../components/VideoDownloader.qml"));
        return _comp;
    }

    function start(video, url) {
        if (!video || !url || url.length === 0) return;
        var permlink = video.permlink || "";
        if (permlink.length === 0 || isSaved(permlink) || _active[permlink]) return;

        var comp = _downloaderComponent();
        if (!comp || comp.status === Component.Error) {
            if (comp) console.log("VideoDownloader unavailable: " + comp.errorString());
            Toast.error("Downloads aren't available on this device.");
            return;
        }

        var dl = comp.createObject(store, { url: url, title: video.title || "Serey video" });
        if (!dl) { Toast.error("Couldn't start download."); return; }

        _active[permlink] = { progress: 0, downloader: dl };
        store.rev++;

        // Grab the poster too, so the thumbnail shows offline.
        store._saveThumb(video, permlink);

        dl.progress.connect(function (pct) {
            if (_active[permlink]) { _active[permlink].progress = pct; store.rev++; }
        });
        dl.finished.connect(function (path) {
            var vm = video;
            var t = store._pendingThumb[permlink];
            if (t) { vm = Object.assign({}, video, { localThumb: t }); delete store._pendingThumb[permlink]; }
            store._persist(vm, path);
            delete _active[permlink];
            dl.destroy();
            store._load();
            Toast.success("Saved for offline");
        });
        dl.failed.connect(function (message) {
            delete _active[permlink];
            delete store._pendingThumb[permlink];
            dl.destroy();
            store.rev++;
            Toast.error("Download failed.");
        });

        Toast.show("Downloading…");
        dl.start(url);
    }

    // Best-effort local copy of the poster image so the thumbnail shows offline.
    // Hidden from the system download indicator; failures are silent (the video
    // still saves, the card just falls back to the remote URL).
    function _saveThumb(video, permlink) {
        var thumb = (video && video.thumbnail) || "";
        if (thumb.indexOf("http") !== 0) return;       // only remote http(s) posters
        var comp = _downloaderComponent();
        if (!comp || comp.status === Component.Error) return;
        var tdl = comp.createObject(store, { url: thumb, title: "thumbnail", showInIndicator: false });
        if (!tdl) return;
        _thumbDls[permlink] = tdl;
        tdl.finished.connect(function (path) {
            var fp = path.indexOf("file://") === 0 ? path : "file://" + path;
            store._pendingThumb[permlink] = fp;
            if (store.isSaved(permlink)) store._updateThumb(permlink, fp);  // video saved first
            delete store._thumbDls[permlink];
            tdl.destroy();
        });
        tdl.failed.connect(function () { delete store._thumbDls[permlink]; tdl.destroy(); });
        tdl.start(thumb);
    }

    // Patch an already-saved row with the local poster path (poster finished after
    // the video did).
    function _updateThumb(permlink, fp) {
        for (var i = 0; i < items.length; i++) {
            if (items[i].permlink !== permlink) continue;
            var vm = items[i];
            vm.localThumb = fp;
            store._persist(vm, vm.localPath);
            store.items = items.slice();
            store.rev++;
            return;
        }
    }

    function remove(permlink) {
        store._deleteRow(permlink);
        store._load();
        Toast.show("Removed from downloads");
    }

    Component.onCompleted: _load()

    // Re-scope the list when the signed-in account changes (login/logout/switch).
    // QtObject has no default property, so this must be assigned, not a child.
    // Session.setAuth() sets username before token, so isLoggedIn is still stale
    // when onUsernameChanged fires — must also react to onTokenChanged.
    property Connections _sessionWatcher: Connections {
        target: Session
        onUsernameChanged: store._load()
        onTokenChanged: store._load()
    }
}
