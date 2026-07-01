import QtQuick 2.7
import QtWebEngine 1.10

/*
 * Hidden WebView that generates Serey self-custody keys by running the vendored
 * @sereynetwork/sereyjs bundle (assets/keygen.html). QML calls generate() and
 * gets the keys back through runJavaScript's return-value callback — no console
 * bridge needed since QML is the initiator. Kept 1x1 + opacity 0 (rather than
 * visible:false) so QtWebEngine still loads the page and runs its JS.
 */
Item {
    id: root

    width: 1
    height: 1
    opacity: 0

    // True once keygen.html (and serey.min.js) has finished loading.
    readonly property bool ready: _ready
    property bool _ready: false

    WebEngineView {
        id: web
        anchors.fill: parent
        url: Qt.resolvedUrl("../../assets/keygen.html")
        onLoadingChanged: {
            if (loadRequest.status === WebEngineLoadRequest.LoadSucceededStatus)
                root._ready = true;
            else if (loadRequest.status === WebEngineLoadRequest.LoadFailedStatus)
                console.warn("KeygenBridge: failed to load keygen.html");
        }
    }

    // Generate keys for `username`. Calls onKeys(keysObject) on success or
    // onErr(message) on failure. keysObject has master_password, the four
    // *_public_key fields and posting_private_key.
    function generate(username, onKeys, onErr) {
        if (!_ready) {
            onErr(qsTr("Still preparing — please try again in a moment."));
            return;
        }
        web.runJavaScript("JSON.stringify(generateSereyKeys(" + JSON.stringify(username) + "))",
            function (result) {
                var data = null;
                try { data = result ? JSON.parse(result) : null; } catch (e) { data = null; }
                if (data && data.ok) onKeys(data);
                else onErr((data && data.error) ? data.error : qsTr("Could not generate your keys."));
            });
    }
}
