pragma Singleton
import QtQuick 2.7

QtObject {
    property var post: null
    property bool visible: false
    // What kind of content the menu was opened for: "blog" | "gallery" | "video".
    // Drives owner actions (e.g. Edit is hidden for video — no video editor).
    property string kind: "blog"

    signal hideRequested(string author, string permlink)
    // The owner chose Edit on their own post; the active page opens the editor.
    signal editRequested(var post)
    // A post was deleted; feed pages prune the matching row from their models.
    signal postDeleted(string author, string permlink)

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
