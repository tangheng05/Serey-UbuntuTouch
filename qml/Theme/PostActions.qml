pragma Singleton
import QtQuick 2.7

QtObject {
    property var post: null
    property bool visible: false
    // content kind ("blog"|"gallery"|"video"), gates owner actions
    property string kind: "blog"

    signal hideRequested(string author, string permlink)
    signal editRequested(var post)
    signal postDeleted(string author, string permlink)
    // after in-place edit, refresh without full reload
    signal postUpdated(string author, string permlink, string title, string body)
    signal userBlocked(string username)
    signal userUnblocked(string username)
    // patch row's comment count without full reload
    signal commentCountChanged(string permlink, int count)

    // step the sheet opens on, skips straight to a sub-flow
    property int startStep: 0

    function open(postData, postKind, atStep) {
        post = postData;
        kind = postKind || "blog";
        startStep = atStep || 0;
        visible = true;
    }
    function close() {
        visible = false;
        post = null;
    }
}
