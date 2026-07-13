import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../services/PostService.js" as PostService
import "../services/CommentService.js" as CommentService

Item {
    id: sheet
    anchors.fill: parent
    visible: false
    z: 2000

    property string author: ""
    property string permlink: ""
    property var comments: []
    property bool loading: false
    property bool posting: false
    property var replyTarget: null

    readonly property real kbHeight: Qt.inputMethod.visible ? Qt.inputMethod.keyboardRectangle.height : 0

    signal countChanged(int delta)

    function open(a, p) {
        sheet.author = a; sheet.permlink = p;
        sheet.comments = []; sheet.replyTarget = null; composer.text = "";
        sheet.visible = true;
        backdropFade.start(); panelAnim.to = 0; panelAnim.start();
        sheet.load();
    }
    function close() {
        Qt.inputMethod.hide();
        backdropFadeOut.start(); panelAnim.to = panel.height; panelAnim.start();
    }

    function load() {
        sheet.loading = true;
        PostService.detail(Config.baseUrl, sheet.author, sheet.permlink, Session.token,
            function (result) { sheet.loading = false; if (result) sheet.comments = result.replies || []; },
            function () { sheet.loading = false; });
    }

    // --- comment tree helpers (same as VideoDetailPage) --------------------
    function _appendReply(list, parentPermlink, reply) {
        var out = [];
        for (var i = 0; i < list.length; i++) {
            var node = list[i];
            if (node.permlink === parentPermlink)
                node = Object.assign({}, node, { replies: [reply].concat(node.replies || []) });
            else if (node.replies && node.replies.length)
                node = Object.assign({}, node, { replies: _appendReply(node.replies, parentPermlink, reply) });
            out.push(node);
        }
        return out;
    }
    function _removeFrom(list, permlinkToRemove) {
        var out = [];
        for (var i = 0; i < list.length; i++) {
            if (list[i].permlink === permlinkToRemove) continue;
            var node = list[i];
            if (node.replies && node.replies.length)
                node = Object.assign({}, node, { replies: _removeFrom(node.replies, permlinkToRemove) });
            out.push(node);
        }
        return out;
    }
    function _editIn(list, permlinkToEdit, newBody) {
        var out = [];
        for (var i = 0; i < list.length; i++) {
            var node = list[i];
            if (node.permlink === permlinkToEdit)
                node = Object.assign({}, node, { body: newBody });
            else if (node.replies && node.replies.length)
                node = Object.assign({}, node, { replies: _editIn(node.replies, permlinkToEdit, newBody) });
            out.push(node);
        }
        return out;
    }
    function removeComment(p) {
        sheet.comments = _removeFrom(sheet.comments, p);
        sheet.countChanged(-1);
        // Server delete must run in this sheet-level scope: the CommentService JS
        // import resolves to null inside the Repeater delegate's inline handler
        // (and inside Loader-created nested reply rows), so calling it there threw
        // "Cannot call method 'remove' of null" and the delete never reached the
        // server. Here in the sheet root the import is valid.
        CommentService.remove(Config.baseUrl, p, Session.username, Session.token,
            function () {},
            function (err) {
                Toast.error((err && err.message) ? err.message : Lang.tr("Couldn't delete comment."));
            });
    }
    function editComment(p, b, parentAuthor, parentPermlink) {
        sheet.comments = _editIn(sheet.comments, p, b);
        // Server update runs in this sheet-level scope, not in CommentItem: its
        // CommentService import is null inside Loader-created reply rows (see
        // removeComment). Passing the existing permlink updates that comment.
        CommentService.create(Config.baseUrl,
            { parentAuthor: parentAuthor, parentPermlink: parentPermlink,
              body: b, permlink: p },
            Session.token,
            function () {},
            function (err) {
                Toast.error((err && err.message) ? err.message : Lang.tr("Couldn't update comment."));
            });
    }
    function startReply(c) { sheet.replyTarget = c; composer.forceActiveFocus(); }

    function submit() {
        var text = composer.text.trim();
        if (text.length === 0) return;
        if (!Session.isLoggedIn) { Toast.error(Lang.tr("Please log in first.")); return; }
        var target = sheet.replyTarget;
        var pa = target ? target.author : sheet.author;
        var pp = target ? target.permlink : sheet.permlink;
        sheet.posting = true;
        CommentService.create(Config.baseUrl,
            { parentAuthor: pa, parentPermlink: pp, body: text }, Session.token,
            function () {
                sheet.posting = false; composer.text = "";
                var mine = { author: Session.username, permlink: "", body: text,
                             parentAuthor: pa, parentPermlink: pp, date: Lang.tr("just now"),
                             votes: 0, voters: [], replies: [], authorImage: Session.avatarUrl };
                sheet.comments = target ? _appendReply(sheet.comments, target.permlink, mine)
                                        : [mine].concat(sheet.comments);
                sheet.replyTarget = null;
                sheet.countChanged(1);
                Toast.success(Lang.tr("Comment posted"));
                sheet.load();
            },
            function (err) {
                sheet.posting = false;
                Toast.error((err && err.message) ? err.message : Lang.tr("Couldn't post comment."));
            });
    }

    // --- Backdrop ----------------------------------------------------------
    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.5)
        opacity: 0
        MouseArea { anchors.fill: parent; onClicked: sheet.close() }
        NumberAnimation { id: backdropFade; target: backdrop; property: "opacity"; from: 0; to: 1; duration: 180 }
        NumberAnimation { id: backdropFadeOut; target: backdrop; property: "opacity"; to: 0; duration: 180
            onStopped: sheet.visible = false }
    }

    // --- Panel -------------------------------------------------------------
    Rectangle {
        id: panel
        // Anchored above the keyboard; height clamps so it never runs off the top
        // when the OSK is up.
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: sheet.kbHeight }
        height: Math.min(sheet.height * 0.72, sheet.height - sheet.kbHeight - units.gu(2))
        color: Style.surface
        radius: Style.cardRadius

        // Slide via a translate (0 = open, height = hidden below screen).
        property real panelOff: height
        transform: Translate { y: panel.panelOff }
        NumberAnimation { id: panelAnim; target: panel; property: "panelOff"; duration: 220; easing.type: Easing.OutCubic }

        MouseArea { anchors.fill: parent /* swallow taps so backdrop doesn't close */ }

        // Header
        Rectangle {
            id: cHeader
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: units.gu(6)
            color: "transparent"
            Label {
                anchors.centerIn: parent
                text: Lang.tr("Comments")
                font.pixelSize: Style.fontMedium
                font.weight: Font.DemiBold
                font.family: Style.fontFor(text)
                color: Style.textPrimary
            }
            AbstractButton {
                anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                width: units.gu(4); height: width
                onClicked: sheet.close()
                Icon { anchors.centerIn: parent; width: units.gu(2.5); height: width; name: "close"; color: Style.textPrimary }
            }
            Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: units.dp(1); color: Style.divider }
        }

        ListView {
            id: cList
            anchors { left: parent.left; right: parent.right; top: cHeader.bottom; bottom: composerBar.top }
            clip: true
            model: sheet.comments
            spacing: 0
            delegate: CommentItem {
                width: cList.width
                comment: modelData
                topLevel: true
                onDeleted: sheet.removeComment(permlink)
                onEdited: sheet.editComment(permlink, newBody, parentAuthor, parentPermlink)
                onReplyRequested: sheet.startReply(comment)
            }
        }

        ActivityIndicator {
            anchors.centerIn: cList
            running: sheet.loading && sheet.comments.length === 0
            visible: running
        }
        Label {
            anchors.centerIn: cList
            visible: !sheet.loading && sheet.comments.length === 0
            text: Lang.tr("No comments yet")
            font.family: Style.fontFor(text)
            color: Style.textSecondary
        }

        // Composer
        Column {
            id: composerBar
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            spacing: 0

            // "Replying to" chip
            Rectangle {
                width: parent.width
                height: visible ? units.gu(4) : 0
                visible: sheet.replyTarget !== null
                color: Style.iconBackground
                Label {
                    anchors { left: parent.left; leftMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                    text: Lang.tr("Replying to @%1").arg(sheet.replyTarget ? sheet.replyTarget.author : "")
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                }
                AbstractButton {
                    anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                    width: units.gu(3); height: width
                    onClicked: sheet.replyTarget = null
                    Icon { anchors.centerIn: parent; width: units.gu(2); height: width; name: "close"; color: Style.textSecondary }
                }
            }

            Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

            Row {
                width: parent.width - Style.spacingM * 2
                x: Style.spacingM
                height: units.gu(7)
                spacing: Style.spacingS

                TextField {
                    id: composer
                    width: parent.width - sendBtn.width - Style.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    placeholderText: Lang.tr("Add a comment…")
                    font.family: Style.fontFor(text)
                    onAccepted: sheet.submit()
                }
                AbstractButton {
                    id: sendBtn
                    anchors.verticalCenter: parent.verticalCenter
                    width: units.gu(8); height: units.gu(4.5)
                    enabled: !sheet.posting && composer.text.trim().length > 0
                    onClicked: sheet.submit()
                    Rectangle {
                        anchors.fill: parent
                        radius: Style.cardRadius
                        color: parent.enabled ? Style.brand : Style.iconBackground
                    }
                    Label {
                        anchors.centerIn: parent
                        text: sheet.posting ? Lang.tr("…") : Lang.tr("Send")
                        font.pixelSize: Style.fontSmall
                        font.weight: Font.DemiBold
                        color: parent.enabled ? Style.textOnBrand : Style.textSecondary
                    }
                }
            }
        }
    }
}
