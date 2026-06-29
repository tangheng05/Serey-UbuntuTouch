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

    readonly property bool isLoggedIn: token.length > 0

    property var _dbHandle: null
    function _db() {
        if (!_dbHandle)
            _dbHandle = LocalStorage.openDatabaseSync("SereyAuth", "1.0", "Serey auth store", 100000);
        return _dbHandle;
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
                }
            });
        } catch (e) {
            console.warn("Session load error: " + e);
        }
    }

    function _save() {
        try {
            _db().transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS auth(k TEXT PRIMARY KEY, v TEXT)");
                tx.executeSql("INSERT OR REPLACE INTO auth(k, v) VALUES('token', ?)", [session.token]);
                tx.executeSql("INSERT OR REPLACE INTO auth(k, v) VALUES('username', ?)", [session.username]);
            });
        } catch (e) {
            console.warn("Session save error: " + e);
        }
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

    function clear() {
        token = "";
        username = "";
        avatarUrl = "";
        _save();
    }

    Component.onCompleted: _load()
}
