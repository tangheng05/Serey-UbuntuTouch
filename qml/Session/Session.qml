pragma Singleton
import QtQuick 2.7
import QtQuick.LocalStorage 2.0

/*
 * Authentication state, persisted across launches in a local SQLite database.
 *
 * We use Qt.labs.LocalStorage rather than Qt.labs.Settings because Settings
 * (QSettings) buffers writes and only flushes on a clean shutdown — when the
 * user swipe-kills the app the token is lost. LocalStorage transactions commit
 * to disk synchronously, so the token survives even an abrupt kill.
 *
 * UI binds to `isLoggedIn`.
 */
QtObject {
    id: session

    property string token: ""
    property string username: ""
    // Not persisted to disk (only token/username are) — refetched each launch
    // via AccountService.profile() so optimistic local comments can show a
    // real avatar instead of the letter-fallback.
    property string avatarUrl: ""
    property bool pushEnabled: true
    property string language: "en"   // "en" or "nl"

    readonly property bool isLoggedIn: token.length > 0

    property var _dbHandle: null
    function _db() {
        if (!_dbHandle)
            _dbHandle = LocalStorage.openDatabaseSync("SereyAuth", "1.0", "Serey auth store", 100000);
        return _dbHandle;
    }

    // The vote cache lives in its OWN database. It's unbounded and written on
    // every vote; keeping it out of SereyAuth means nothing can interfere with
    // the small, critical auth rows (a failed/blocked auth write is how an old
    // account can silently resurrect on the next launch).
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
                }
            });
        } catch (e) {
            console.warn("Session load error: " + e);
        }
    }

    // Write token+username, then read them back and verify. A silently-failed
    // write here is how an old account resurrects on the next launch (the user
    // logs in as B, the write never lands, _load() restores A) — so failures are
    // retried once and logged loudly enough to spot in `clickable logs`.
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
        // Set username first: assigning `token` fires onTokenChanged synchronously,
        // and listeners (e.g. SettingsPage) immediately fetch the profile by
        // username — so username must already be in place or the fetch uses "".
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
        _save();
    }

    Component.onCompleted: _load()
}
