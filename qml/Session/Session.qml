pragma Singleton
import QtQuick 2.7
import QtQuick.LocalStorage 2.0

QtObject {
    id: session

    property string token: ""
    property string username: ""
    // Not persisted; refetched each launch via AccountService.profile()
    property string avatarUrl: ""
    property bool pushEnabled: true
    property string language: "en"   // "en" or "nl"
    // epoch ms of last push-token registration
    property double lastPushRegisterAt: 0

    readonly property bool isLoggedIn: token.length > 0

    property var _dbHandle: null
    function _db() {
        if (!_dbHandle)
            _dbHandle = LocalStorage.openDatabaseSync("SereyAuth", "1.0", "Serey auth store", 100000);
        return _dbHandle;
    }

    // Own database (unbounded, written every vote) so it can't interfere with the small, critical auth rows below.
    property var _votesDbHandle: null
    function _votesDb() {
        if (!_votesDbHandle)
            _votesDbHandle = LocalStorage.openDatabaseSync("SereyVotes", "1.0", "Serey vote cache", 1000000);
        return _votesDbHandle;
    }

    function _load() {
        try {
            _db().transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS auth(k TEXT PRIMARY KEY, v TEXT)");
                var rs = tx.executeSql("SELECT k, v FROM auth");
                for (var i = 0; i < rs.rows.length; i++) {
                    var row = rs.rows.item(i);
                    if (row.k === "token") session.token = row.v;
                    else if (row.k === "username") session.username = row.v;
                    else if (row.k === "pushEnabled") session.pushEnabled = (row.v !== "false");
                    else if (row.k === "language") session.language = row.v;
                    else if (row.k === "lastPushRegisterAt") session.lastPushRegisterAt = Number(row.v) || 0;
                }
            });
        } catch (e) {
            console.warn("Session load error: " + e);
        }
    }

    // Write then read back and verify; a silent write failure is how an old account resurrects next launch.
    function _writeAuthOnce() {
        _db().transaction(function (tx) {
            tx.executeSql("CREATE TABLE IF NOT EXISTS auth(k TEXT PRIMARY KEY, v TEXT)");
            tx.executeSql("INSERT OR REPLACE INTO auth(k, v) VALUES('token', ?)", [session.token]);
            tx.executeSql("INSERT OR REPLACE INTO auth(k, v) VALUES('username', ?)", [session.username]);
        });
    }

    function _authWriteVerified() {
        var ok = false;
        _db().readTransaction(function (tx) {
            var t = "", u = "";
            var rs = tx.executeSql("SELECT k, v FROM auth WHERE k IN ('token','username')");
            for (var i = 0; i < rs.rows.length; i++) {
                var row = rs.rows.item(i);
                if (row.k === "token") t = row.v;
                else if (row.k === "username") u = row.v;
            }
            ok = (t === session.token && u === session.username);
        });
        return ok;
    }

    function _save() {
        for (var attempt = 1; attempt <= 2; attempt++) {
            try {
                _writeAuthOnce();
                if (_authWriteVerified()) {
                    if (attempt > 1)
                        console.warn("Session: auth write succeeded on retry " + attempt);
                    return;
                }
                console.warn("Session: auth write VERIFY FAILED (attempt " + attempt
                             + ") for user '" + session.username + "'");
            } catch (e) {
                console.warn("Session: auth write ERROR (attempt " + attempt + "): " + e);
            }
        }
        console.warn("Session: auth state NOT persisted — user '" + session.username
                     + "' will not survive an app restart");
    }

    function setAuth(newToken, newUsername) {
        // Username first: token fires onTokenChanged synchronously, and listeners fetch the profile by username immediately.
        username = newUsername;
        token = newToken;
        _save();
    }

    function setPushEnabled(enabled) {
        pushEnabled = enabled;
        try {
            _db().transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS auth(k TEXT PRIMARY KEY, v TEXT)");
                tx.executeSql("INSERT OR REPLACE INTO auth(k, v) VALUES('pushEnabled', ?)", [enabled ? "true" : "false"]);
            });
        } catch (e) { console.warn("Session save pushEnabled error: " + e); }
    }

    function setLastPushRegisterAt(ts) {
        lastPushRegisterAt = ts;
        try {
            _db().transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS auth(k TEXT PRIMARY KEY, v TEXT)");
                tx.executeSql("INSERT OR REPLACE INTO auth(k, v) VALUES('lastPushRegisterAt', ?)", [String(ts)]);
            });
        } catch (e) { console.warn("Session save lastPushRegisterAt error: " + e); }
    }

    function setLanguage(lang) {
        language = lang;
        try {
            _db().transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS auth(k TEXT PRIMARY KEY, v TEXT)");
                tx.executeSql("INSERT OR REPLACE INTO auth(k, v) VALUES('language', ?)", [lang]);
            });
        } catch (e) { console.warn("Session save language error: " + e); }
    }

    function saveVote(author, permlink, upvoted, flagged, votes) {
        if (!author || !permlink) return;
        try {
            _votesDb().transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS votes(k TEXT PRIMARY KEY, upvoted INTEGER, flagged INTEGER, votes INTEGER)");
                tx.executeSql("INSERT OR REPLACE INTO votes(k, upvoted, flagged, votes) VALUES(?,?,?,?)",
                    [author + "/" + permlink, upvoted ? 1 : 0, flagged ? 1 : 0, votes]);
            });
        } catch (e) { console.warn("Session saveVote error: " + e); }
    }

    function loadVote(author, permlink) {
        if (!author || !permlink) return null;
        var result = null;
        try {
            _votesDb().transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS votes(k TEXT PRIMARY KEY, upvoted INTEGER, flagged INTEGER, votes INTEGER)");
                var rs = tx.executeSql("SELECT upvoted, flagged, votes FROM votes WHERE k=?",
                                       [author + "/" + permlink]);
                var row = rs.rows.length > 0 ? rs.rows.item(0) : null;
                if (row)
                    result = { upvoted: !!row.upvoted, flagged: !!row.flagged, votes: row.votes };
            });
        } catch (e) { console.warn("Session loadVote error: " + e); }
        return result;
    }

    function clear() {
        token = "";
        username = "";
        avatarUrl = "";
        // Logout deletes the stored credentials rather than persisting empty strings, since _save()'s write-verify would log a spurious failure for an empty session.
        try {
            _db().transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS auth(k TEXT PRIMARY KEY, v TEXT)");
                tx.executeSql("DELETE FROM auth WHERE k IN ('token','username')");
            });
        } catch (e) { console.warn("Session clear error: " + e); }
    }

    Component.onCompleted: _load()
}
