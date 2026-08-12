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

    // Docked mode: a side panel the caller positions (wide-window reels) instead of a
    // modal bottom sheet, so it sits beside the video rather than on top of it.
    property bool docked: false
    property rect dockRect: Qt.rect(0, 0, 0, 0)

    readonly property real kbHeight: Qt.inputMethod.visible ? Qt.inputMethod.keyboardRectangle.height : 0

    signal countChanged(int delta)

    function open(a, p) {
        sheet.author = a; sheet.permlink = p;
        sheet.comments = []; sheet.replyTarget = null; composer.text = "";
        sheet.visible = true;
        if (sheet.docked) panel.panelOff = 0;
        else { backdropFade.start(); panelAnim.to = 0; panelAnim.start(); }
        sheet.load();
    }
    function close() {
        Qt.inputMethod.hide();
        if (sheet.docked) { sheet.visible = false; return; }
        backdropFadeOut.start(); panelAnim.to = panel.height; panelAnim.start();
    }

    function load() {
        sheet.loading = true;
        PostService.detail(Config.baseUrl, sheet.author, sheet.permlink, Session.token,
            function (result) { sheet.loading = false; if (result) sheet.comments = result.replies || []; },
            function () { sheet.loading = false; });
    }

    // comment tree helpers (same as VideoDetailPage)
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
        // Server delete must run in this sheet-level scope; the CommentService import resolves to null inside Repeater/Loader-created reply row delegates.
        CommentService.remove(Config.baseUrl, p, Session.username, Session.token,
            function () {},
            function (err) {
                Toast.error((err && err.message) ? err.message : Lang.tr("Couldn't delete comment."));
            });
    }
    function editComment(p, b, parentAuthor, parentPermlink) {
        sheet.comments = _editIn(sheet.comments, p, b);
        // Server update runs in this sheet-level scope, not CommentItem, since its CommentService import is null inside Loader-created reply rows.
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
        // Enter bypasses the Send button's enabled state, so a fast double tap posted twice.
        if (sheet.posting) return;
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

    Rectangle {
        id: backdrop
        anchors.fill: parent
        // Docked panels don't dim or swallow clicks: the reel behind stays swipeable.
        visible: !sheet.docked
        color: Qt.rgba(0, 0, 0, 0.5)
        opacity: 0
        MouseArea { anchors.fill: parent; onClicked: sheet.close() }
        NumberAnimation { id: backdropFade; target: backdrop; property: "opacity"; from: 0; to: 1; duration: 180 }
        NumberAnimation { id: backdropFadeOut; target: backdrop; property: "opacity"; to: 0; duration: 180
            onStopped: sheet.visible = false }
    }

    Rectangle {
        id: panel
        // Geometry, not anchors: docked and sheet modes differ on every edge, and an
        // anchor set can't be swapped from a ternary (see the AnchorChanges note in CLAUDE.md).
        x: sheet.docked ? sheet.dockRect.x : (parent.width - width) / 2
        y: sheet.docked ? sheet.dockRect.y : (parent.height - sheet.kbHeight - height)
        width: sheet.docked ? sheet.dockRect.width : Math.min(parent.width, Config.sheetMaxWidth)
        // Docked still yields to the on-screen keyboard: a wide tablet has one, and the
        // composer sits at the panel's bottom edge.
        height: sheet.docked ? Math.max(units.gu(10), sheet.dockRect.height - sheet.kbHeight)
                             : Math.min(sheet.height * 0.72, sheet.height - sheet.kbHeight - units.gu(2))
        color: Style.surface
        // Docked, it's a right rail flush with the window edge, like VideoDetailPage's side panel.
        radius: sheet.docked ? 0 : Style.cardRadius

        Rectangle {
            visible: sheet.docked
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
            width: units.dp(1)
            color: Style.divider
        }

        // Slide via a translate (0 = open, height = hidden below screen).
        property real panelOff: height
        transform: Translate { y: panel.panelOff }
        NumberAnimation { id: panelAnim; target: panel; property: "panelOff"; duration: 220; easing.type: Easing.OutCubic }

        MouseArea { anchors.fill: parent /* swallow taps so backdrop doesn't close */ }

        Rectangle {
            id: cHeader
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: units.gu(6)
            color: "transparent"
            // Docked reuses the rail's section heading; the modal keeps its centered title.
            Label {
                visible: sheet.docked
                anchors { left: parent.left; leftMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                text: Lang.tr("COMMENTS (%1)").arg(sheet.comments.length)
                font.pixelSize: Style.fontSmall
                font.weight: Font.Bold
                color: Style.textSecondary
            }
            Label {
                visible: !sheet.docked
                anchors.centerIn: parent
                text: Lang.tr("Comments")
                font.pixelSize: Style.fontMedium
                font.weight: Font.DemiBold
                font.family: Style.fontFor(text)
                color: Style.textPrimary
            }
            AbstractButton {
                // Docked, the panel is permanent furniture like the video rail, so there's nothing to dismiss.
                visible: !sheet.docked
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
            // Docked mirrors the side panel: compact rows separated by a rule, no avatar indent.
            delegate: Column {
                width: cList.width
                spacing: sheet.docked ? Style.spacingS : 0

                Rectangle {
                    visible: sheet.docked && index > 0
                    width: parent.width
                    height: units.dp(1)
                    color: Style.divider
                }

                CommentItem {
                    width: parent.width
                    compact: sheet.docked
                    comment: modelData
                    topLevel: true
                    onDeleted: sheet.removeComment(permlink)
                    onEdited: sheet.editComment(permlink, newBody, parentAuthor, parentPermlink)
                    onReplyRequested: sheet.startReply(comment)
                }
            }
        }

        ActivityIndicator {
            anchors.centerIn: cList
            running: sheet.loading && sheet.comments.length === 0
            visible: running
        }
        Label {
            // Same copy and placement as the video side panel: top-left, not centered.
            visible: sheet.docked && !sheet.loading && sheet.comments.length === 0
            anchors { left: cList.left; right: cList.right; top: cList.top
                      leftMargin: Style.spacingM; rightMargin: Style.spacingM; topMargin: Style.spacingS }
            text: Lang.tr("No comments yet. Be the first!")
            font.pixelSize: Style.fontSmall
            font.family: Style.fontFor(text)
            wrapMode: Text.Wrap
            color: Style.textSecondary
        }
        Label {
            anchors.centerIn: cList
            visible: !sheet.docked && !sheet.loading && sheet.comments.length === 0
            text: Lang.tr("No comments yet")
            font.family: Style.fontFor(text)
            color: Style.textSecondary
        }

        Column {
            id: composerBar
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            spacing: 0

            // "Replying to @x  Cancel", the same treatment as the video composers
            Row {
                visible: sheet.replyTarget !== null
                x: Style.spacingS
                width: parent.width - Style.spacingS * 2
                height: visible ? units.gu(3) : 0
                spacing: Style.spacingS

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Lang.tr("Replying to @%1").arg(sheet.replyTarget ? sheet.replyTarget.author : "")
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                }
                AbstractButton {
                    anchors.verticalCenter: parent.verticalCenter
                    width: cancelReplyLabel.implicitWidth
                    height: cancelReplyLabel.implicitHeight
                    onClicked: sheet.replyTarget = null
                    Label {
                        id: cancelReplyLabel
                        text: Lang.tr("Cancel")
                        font.pixelSize: Style.fontSmall
                        font.weight: Font.DemiBold
                        color: Style.brand
                    }
                }
            }

            Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

            // Same pill + round send button as VideoDetailPage's composers, so every
            // comment box in the app looks alike.
            Item {
                x: Style.spacingS
                width: parent.width - Style.spacingS * 2
                height: units.gu(5)

                Rectangle {
                    anchors.fill: parent
                    radius: Style.cardRadius
                    color: Style.iconBackground
                    border.width: units.dp(1)
                    border.color: Style.divider
                }

                TextField {
                    id: composer
                    anchors { left: parent.left; leftMargin: Style.spacingM
                              right: sendBtn.left; rightMargin: Style.spacingXs
                              verticalCenter: parent.verticalCenter }
                    height: parent.height - units.dp(2)
                    StyleHints {
                        backgroundColor: "transparent"
                        borderColor: "transparent"
                        color: Style.textPrimary
                    }
                    hasClearButton: false
                    placeholderText: Session.isLoggedIn ? Lang.tr("Post a comment…") : Lang.tr("Log in to comment…")
                    font.family: Style.fontFor(text)
                    font.pixelSize: Style.fontRegular
                    onAccepted: sheet.submit()
                }

                AbstractButton {
                    id: sendBtn
                    anchors { right: parent.right; rightMargin: units.dp(3); verticalCenter: parent.verticalCenter }
                    width: units.gu(3.8); height: width
                    enabled: !sheet.posting && composer.text.trim().length > 0
                    onClicked: sheet.submit()

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: sendBtn.enabled ? Style.brand : "transparent"
                    }
                    Icon {
                        anchors.centerIn: parent
                        width: units.gu(2.2); height: width
                        name: "send"
                        color: sendBtn.enabled ? Style.textOnBrand : Style.textSecondary
                    }
                }
            }

            Item { width: 1; height: Style.spacingS }
        }
    }
}
