pragma Singleton
import QtQuick 2.7

QtObject {
    property var post: null
    property bool visible: false
    // What kind of content the menu opened for ("blog"|"gallery"|"video"); drives owner actions like hiding Edit for video.
    property string kind: "blog"

    // fires on every open(), even a re-open while already visible
    signal opened()

    signal hideRequested(string author, string permlink)
    signal editRequested(var post)
    signal postDeleted(string author, string permlink)
    // Emitted after an in-place edit succeeds so pages showing the post can refresh their copy without a full reload.
    signal postUpdated(string author, string permlink, string title, string body)
    signal userBlocked(string username)
    signal userUnblocked(string username)
    // Emitted when a detail page's comment count changes so feed pages can patch the row's count without a full reload.
    signal commentCountChanged(string permlink, int count)

    // Step the sheet should open on; lets a caller jump straight to a sub-flow
    property int startStep: 0

    function open(postData, postKind, atStep) {
        post = postData;
        kind = postKind || "blog";
        startStep = atStep || 0;
        visible = true;
        opened();
    }
    function close() {
        visible = false;
        post = null;
    }
}
