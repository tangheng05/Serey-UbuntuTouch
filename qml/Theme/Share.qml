pragma Singleton
import QtQuick 2.7

QtObject {
    id: share

    property bool visible: false
    property string url: ""
    // Button that triggered the sheet, if any — lets the dropdown anchor to it.
    property var anchorItem: null

    function open(u, anchor) {
        url = u || "";
        anchorItem = anchor || null;
        if (url.length > 0) visible = true;
    }
    function close() { visible = false; anchorItem = null; }
}
