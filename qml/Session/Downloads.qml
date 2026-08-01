pragma Singleton
import QtQuick 2.7
import QtQuick.LocalStorage 2.0
import "../Theme"

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

    // Per-account buckets; logged-out uses "__guest__", never "": QML LocalStorage
    // binds an empty string as SQL NULL, so a guest `owner = ?` matched nothing
    // and the list came back empty on restart. "__guest__" can't be a real username.
    readonly property string guestOwner: "__guest__"

    function _owner() {
        return (Session.isLoggedIn && Session.username && Session.username.length > 0)
                ? Session.username : store.guestOwner;
    }

    // Rows written before the sentinel existed have owner NULL or ''; fold both onto
    // the guest bucket so old downloads stay visible.
    readonly property string _ownerExpr: "IFNULL(NULLIF(owner,''),'" + guestOwner + "')"

    function _load() {
        var out = [];
        try {
            _db().transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS downloads(permlink TEXT, local_path TEXT, saved_at INTEGER, data TEXT, owner TEXT DEFAULT '', PRIMARY KEY(permlink, owner))");
                // Add `owner` to tables created before per-account scoping existed; harmlessly throws (caught) once the column is present.
                try { tx.executeSql("ALTER TABLE downloads ADD COLUMN owner TEXT DEFAULT ''"); } catch (e2) { }
                var rs = tx.executeSql("SELECT permlink, local_path, data FROM downloads WHERE " + store._ownerExpr + " = ? ORDER BY saved_at DESC", [store._owner()]);
                var seen = {};
                for (var i = 0; i < rs.rows.length; i++) {
                    var row = rs.rows.item(i);
                    // A NULL owner also defeats PRIMARY KEY(permlink, owner) dedupe
                    // (SQLite allows repeated NULLs in a PK), so older duplicate rows
                    // can exist; newest-first ordering means the first wins.
                    if (seen[row.permlink]) continue;
                    seen[row.permlink] = true;
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

    // `owner` is passed explicitly for downloads finishing after an account switch; defaults to the current account for synchronous saves.
    function _persist(vm, localPath, owner) {
        var o = (owner === undefined) ? store._owner() : owner;
        try {
            _db().transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS downloads(permlink TEXT, local_path TEXT, saved_at INTEGER, data TEXT, owner TEXT DEFAULT '', PRIMARY KEY(permlink, owner))");
                // Explicit delete before insert: legacy rows with owner NULL (see
                // _owner) can't be deduped by the PRIMARY KEY, so INSERT OR REPLACE
                // piled up a new row per download instead of replacing the old one.
                tx.executeSql("DELETE FROM downloads WHERE permlink = ? AND " + store._ownerExpr + " = ?", [vm.permlink, o]);
                tx.executeSql("INSERT INTO downloads(permlink, local_path, saved_at, data, owner) VALUES(?, ?, ?, ?, ?)",
                    [vm.permlink, localPath, Date.now(), JSON.stringify(vm), o]);
            });
        } catch (e) {
            console.log("Downloads persist error: " + e);
        }
    }

    function _deleteRow(permlink) {
        try {
            _db().transaction(function (tx) {
                tx.executeSql("DELETE FROM downloads WHERE permlink = ? AND " + store._ownerExpr + " = ?", [permlink, store._owner()]);
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

    // Copy the view-model to a plain JS object: threaded ListModel elements fail
    // JSON.stringify ("unregistered datatype") and their thread affinity hid the
    // persisted row from reload (isSaved stayed false -> endless re-downloads).
    function _toPlain(v) {
        var keys = ["id", "author", "permlink", "title", "body", "excerpt", "thumbnail",
                    "localThumb", "authorImage", "date", "votes", "comments", "payout",
                    "embedUrl", "videoLink", "videoId", "platform", "dimensions",
                    "community", "communityId", "postToBlockchain"];
        var o = {};
        if (v) for (var i = 0; i < keys.length; i++) {
            var val = v[keys[i]];
            if (val !== undefined && val !== null) o[keys[i]] = val;
        }
        return o;
    }

    function start(video, url) {
        if (!video || !url || url.length === 0) return;
        // Snapshot to a plain object immediately; everything downstream uses this.
        var pv = _toPlain(video);
        var permlink = pv.permlink || "";
        if (permlink.length === 0 || isSaved(permlink) || _active[permlink]) return;
        // Capture the account that started this download so it's filed under the requester even if the account switches mid-download.
        var startOwner = store._owner();

        var comp = _downloaderComponent();
        if (!comp || comp.status === Component.Error) {
            if (comp) console.log("VideoDownloader unavailable: " + comp.errorString());
            Toast.error("Downloads aren't available on this device.");
            return;
        }

        var dl = comp.createObject(store, { url: url, title: pv.title || "Serey video" });
        if (!dl) { Toast.error("Couldn't start download."); return; }

        _active[permlink] = { progress: 0, downloader: dl };
        store.rev++;

        // Grab the poster too, so the thumbnail shows offline.
        store._saveThumb(pv, permlink);

        dl.progress.connect(function (pct) {
            if (_active[permlink]) { _active[permlink].progress = pct; store.rev++; }
        });
        dl.finished.connect(function (path) {
            var vm = pv;
            var t = store._pendingThumb[permlink];
            if (t) { vm = Object.assign({}, pv, { localThumb: t }); delete store._pendingThumb[permlink]; }
            store._persist(vm, path, startOwner);
            // Update the in-memory list directly so the tick + downloaded list reflect
            // the save right away, independent of the DB reload (which the worker-thread
            // affinity could return empty). Persist above still records it for next launch.
            var savedVm = Object.assign({}, vm, { permlink: permlink, localPath: path });
            var next = [savedVm];
            for (var i = 0; i < store.items.length; i++)
                if (store.items[i].permlink !== permlink) next.push(store.items[i]);
            store.items = next;
            delete _active[permlink];
            dl.destroy();
            store.rev++;
            Toast.success(Lang.tr("Saved for offline use"));
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

    // Best-effort poster copy for offline thumbnails; failures fall back to the remote URL
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

    // Patch an already-saved row with the local poster path (poster finished after the video did).
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

    // QtObject has no default property so this must be assigned, not a child; react to both username and token changes.
    property Connections _sessionWatcher: Connections {
        target: Session
        onUsernameChanged: store._load()
        onTokenChanged: store._load()
    }
}
