pragma Singleton
import QtQuick 2.7

QtObject {
    property var post: null
    property bool visible: false

    signal hideRequested(string author, string permlink)

    function open(postData) {
        post = postData;
        visible = true;
    }
    function close() {
        visible = false;
        post = null;
    }
}
