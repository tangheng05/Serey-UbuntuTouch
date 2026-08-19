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
    // user_devices row (UUID) for this login; lets Active sessions mark "This device". "" = unknown (pre-existing session).
    property string deviceId: ""
    property string language: "en"   // "en" or "nl"
    // True once the language was picked by hand in Settings; blocks the geo default from
    // overwriting that choice on later launches.
    property bool languageChosen: false
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
                var sawLanguage = false, sawChosen = false;
                for (var i = 0; i < rs.rows.length; i++) {
                    var row = rs.rows.item(i);
                    if (row.k === "language") sawLanguage = true;
                    if (row.k === "languageChosen") sawChosen = true;
                    if (row.k === "token") session.token = row.v;
                    else if (row.k === "username") session.username = row.v;
                    else if (row.k === "pushEnabled") session.pushEnabled = (row.v !== "false");
                    else if (row.k === "language") session.language = row.v;
                    else if (row.k === "languageChosen") session.languageChosen = (row.v === "true");
                    else if (row.k === "lastPushRegisterAt") session.lastPushRegisterAt = Number(row.v) || 0;
                    else if (row.k === "deviceId") session.deviceId = row.v || "";
                }
                // Installs from before the geo default: a language row could only come from
                // the Settings picker, so honour it as an explicit choice rather than
                // overwriting it on the next launch. Both writers store the flag now, so its
                // absence is what dates the row.
                if (sawLanguage && !sawChosen) {
                    session.languageChosen = true;
                    tx.executeSql("INSERT OR REPLACE INTO auth(k, v) VALUES('languageChosen', 'true')");
                }
            });
        } catch (e) {
            console.warn("Session load error: " + e);
        }
    }

    // Write then read back to catch a silent write failure
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

    function setAuth(newToken, newUsername, newDeviceId) {
        // Username first: token fires onTokenChanged synchronously
        username = newUsername;
        token = newToken;
        _save();
        setDeviceId(newDeviceId || "");
    }

    function setDeviceId(id) {
        deviceId = id;
        try {
            _db().transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS auth(k TEXT PRIMARY KEY, v TEXT)");
                tx.executeSql("INSERT OR REPLACE INTO auth(k, v) VALUES('deviceId', ?)", [String(id)]);
            });
        } catch (e) { console.warn("Session save deviceId error: " + e); }
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

    function _saveKey(k, v) {
        try {
            _db().transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS auth(k TEXT PRIMARY KEY, v TEXT)");
                tx.executeSql("INSERT OR REPLACE INTO auth(k, v) VALUES(?, ?)", [k, v]);
            });
        } catch (e) { console.warn("Session save " + k + " error: " + e); }
    }

    // Explicit pick from Settings: remembered as the user's own choice.
    function setLanguage(lang) {
        language = lang;
        languageChosen = true;
        _saveKey("language", lang);
        _saveKey("languageChosen", "true");
    }

    // Geo default (Main.qml, from the detected country). Yields to an explicit pick, and is
    // still persisted so a launch with no network keeps the language it settled on.
    function setLanguageAuto(lang) {
        if (languageChosen || lang === language) return;
        language = lang;
        _saveKey("language", lang);
        // Stamped false, not left absent: _load() reads a missing flag as a pre-geo manual pick.
        _saveKey("languageChosen", "false");
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
        deviceId = "";
        // Deletes credentials rather than persisting empty (avoids a spurious write-verify failure)
        try {
            _db().transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS auth(k TEXT PRIMARY KEY, v TEXT)");
                tx.executeSql("DELETE FROM auth WHERE k IN ('token','username','deviceId')");
            });
        } catch (e) { console.warn("Session clear error: " + e); }
    }

    Component.onCompleted: _load()
}
