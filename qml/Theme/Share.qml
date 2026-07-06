pragma Singleton
import QtQuick 2.7

/*
 * App-wide share sheet state. Any page calls Share.open(url); the single
 * ShareSheet instance mounted in Main.qml renders the ContentHub peer picker
 * (system share targets) plus Copy link / Open in browser. Mirrors the
 * Toast/PostActions state-vs-renderer split.
 */
QtObject {
    id: share

    property bool visible: false
    property string url: ""

    function open(u) {
        url = u || "";
        if (url.length > 0) visible = true;
    }
    function close() { visible = false; }
}
