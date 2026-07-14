pragma Singleton
import QtQuick 2.7

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
