pragma Singleton
import QtQuick 2.7

QtObject {
    property var post: null
    property bool visible: false
    // What kind of content the menu was opened for: "blog" | "gallery" | "video".
    // Drives owner actions (e.g. Edit is hidden for video — no video editor).
    property string kind: "blog"

    signal hideRequested(string author, string permlink)
    signal editRequested(var post)
    signal postDeleted(string author, string permlink)
    signal userBlocked(string username)
    signal userUnblocked(string username)

    function open(postData, postKind) {
        post = postData;
        kind = postKind || "blog";
        visible = true;
    }
    function close() {
        visible = false;
        post = null;
    }
}
