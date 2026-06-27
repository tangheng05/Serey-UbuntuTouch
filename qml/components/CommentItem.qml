import QtQuick 2.7
import QtQuick.Controls 2.2
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../services/CommentService.js" as CommentService

/*
 * A single comment row (iOS-style): circular avatar + author + relative time
 * + "•••" menu, body text, a like + reply action row, and — when the comment
 * has replies — a "Hide replies / N replies" toggle that reveals a nested,
 * left-indented sub-tree (recursive CommentItem). Own comments (with a
 * server-assigned permlink) can be edited or deleted via the "•••" menu;
 * each is reported up (edited()/deleted()) so the page updates its tree.
 */
Item {
    id: item
    property var comment: ({})
    readonly property var c: comment ? comment : ({})
    readonly property var replies: c.replies || []
    property bool repliesExpanded: true
    property bool topLevel: true

    // Only the author can edit/delete, and only a comment that exists
    // server-side (optimistic local comments carry an empty permlink).
    readonly property bool canModify: Session.isLoggedIn
                                      && c.author === Session.username
                                      && (c.permlink || "").length > 0
    property bool menuOpen: false
    property bool confirmingDelete: false
    property bool editing: false
    property string editText: ""
    property bool saving: false

    signal deleted(string permlink)
    signal edited(string permlink, string newBody)
    signal replyRequested(var comment)
    signal authorClicked(string author)

    function startEdit() {
        item.editText = c.body || "";
        item.editing = true;
    }

    function cancelEdit() {
        item.editing = false;
    }

    function saveEdit() {
        var text = item.editText.trim();
        if (text.length === 0 || item.saving)
            return;
        item.saving = true;
        CommentService.create(Config.baseUrl,
            { parentAuthor: c.parentAuthor, parentPermlink: c.parentPermlink,
              body: text, permlink: c.permlink },
            Session.token,
            function () {
                item.saving = false;
                item.editing = false;
                item.edited(c.permlink, text);
            },
            function (err) {
                item.saving = false;
                Toast.error((err && err.message) ? err.message : i18n.tr("Couldn't update comment."));
            });
    }

    // Optimistic: drop it from the page's tree immediately rather than waiting
    // on the round-trip, which made deleting feel sluggish. The DELETE request
    // still fires — a failure just surfaces a toast (the comment doesn't come
    // back, same as most apps' optimistic delete).
    function doDelete() {
        var permlinkToDelete = c.permlink;
        item.deleted(permlinkToDelete);
        CommentService.remove(Config.baseUrl, permlinkToDelete, Session.username, Session.token,
            function () { /* already removed from the UI */ },
            function (err) {
                Toast.error((err && err.message) ? err.message : i18n.tr("Couldn't delete comment."));
            });
    }

    width: parent ? parent.width : units.gu(40)
    implicitHeight: col.implicitHeight + Style.spacingM

    Column {
        id: col
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: Style.spacingM
            rightMargin: Style.spacingM
            topMargin: Style.spacingS
        }
        spacing: Style.spacingXs

        // Author row: avatar + name + time on the left, ••• on the right
        Item {
            width: parent.width
            height: avatar.height

            Item {
                id: avatar
                anchors.verticalCenter: parent.verticalCenter
                width: units.gu(3.5); height: width

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Style.avatarTint(c.author || "")
                    visible: (c.authorImage || "") === ""

                    Label {
                        anchors.centerIn: parent
                        text: (c.author || "?").charAt(0).toUpperCase()
                        font.pixelSize: Style.fontSmall
                        font.bold: true
                        color: Style.brand
                    }
                }

                // Masked to a true circle (Rectangle.clip ignores radius).
                CircleImage {
                    anchors.fill: parent
                    source: c.authorImage || ""
                    decode: units.gu(8)
                    visible: (c.authorImage || "") !== ""
                }

                MouseArea { anchors.fill: parent; onClicked: item.authorClicked(c.author || "") }
            }

            Row {
                id: nameCol
                anchors {
                    left: avatar.right
                    leftMargin: Style.spacingS
                    right: moreButton.left
                    verticalCenter: parent.verticalCenter
                }
                spacing: Style.spacingXs

                Label {
                    text: c.author || ""
                    font.pixelSize: Style.fontSmall
                    font.weight: Font.DemiBold
                    color: Style.textPrimary
                    MouseArea { anchors.fill: parent; onClicked: item.authorClicked(c.author || "") }
                }
                Label {
                    text: "· " + Style.formatTimeAgo(c.date || "")
                    font.pixelSize: Style.fontXSmall
                    color: Style.textSecondary
                }
            }

            AbstractButton {
                id: moreButton
                visible: item.canModify
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: units.gu(3); height: units.gu(3)
                onClicked: item.menuOpen = !item.menuOpen

                Label {
                    anchors.centerIn: parent
                    text: "•••"
                    font.pixelSize: Style.fontMedium
                    font.weight: Font.Bold
                    color: Style.textSecondary
                }
            }

            // Edit / Delete dropdown — Delete swaps to an inline confirm step
            // rather than closing, so it's a single small popup either way.
            Rectangle {
                id: menu
                visible: item.menuOpen
                z: 10
                anchors { top: moreButton.bottom; right: moreButton.right; topMargin: Style.spacingXs }
                width: units.gu(16)
                height: item.confirmingDelete ? confirmCol.height : menuCol.height
                radius: units.dp(8)
                color: Style.surface
                border.width: units.dp(1)
                border.color: Style.divider

                Column {
                    id: menuCol
                    width: parent.width
                    visible: !item.confirmingDelete

                    AbstractButton {
                        width: parent.width; height: units.gu(5)
                        onClicked: { item.menuOpen = false; item.startEdit(); }
                        Label {
                            anchors { left: parent.left; leftMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                            text: i18n.tr("Edit")
                            color: Style.textPrimary
                        }
                    }
                    Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }
                    AbstractButton {
                        width: parent.width; height: units.gu(5)
                        onClicked: item.confirmingDelete = true
                        Label {
                            anchors { left: parent.left; leftMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                            text: i18n.tr("Delete")
                            color: Style.danger
                        }
                    }
                }

                Column {
                    id: confirmCol
                    width: parent.width
                    visible: item.confirmingDelete

                    Item { width: 1; height: Style.spacingS }
                    Label {
                        width: parent.width - Style.spacingM * 2
                        x: Style.spacingM
                        text: i18n.tr("Delete this comment?")
                        font.pixelSize: Style.fontSmall
                        color: Style.textPrimary
                        wrapMode: Text.WordWrap
                    }
                    Item { width: 1; height: Style.spacingS }
                    Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }
                    Row {
                        width: parent.width
                        AbstractButton {
                            width: parent.width / 2; height: units.gu(5)
                            onClicked: { item.menuOpen = false; item.confirmingDelete = false; }
                            Label { anchors.centerIn: parent; text: i18n.tr("Cancel"); color: Style.textSecondary }
                        }
                        AbstractButton {
                            width: parent.width / 2; height: units.gu(5)
                            onClicked: { item.menuOpen = false; item.confirmingDelete = false; item.doDelete(); }
                            Label { anchors.centerIn: parent; text: i18n.tr("Delete"); color: Style.danger; font.weight: Font.DemiBold }
                        }
                    }
                }
            }
        }

        Label {
            visible: !item.editing
            width: parent.width
            x: units.gu(3.5) + Style.spacingS
            text: c.body || ""
            font.pixelSize: Style.fontRegular
            font.family: Style.fontFamily
            color: Style.textPrimary
            wrapMode: Text.WordWrap
        }

        // Inline edit mode
        Column {
            visible: item.editing
            width: parent.width - (units.gu(3.5) + Style.spacingS)
            x: units.gu(3.5) + Style.spacingS
            spacing: Style.spacingXs

            TextArea {
                id: editField
                width: parent.width
                text: item.editText
                font.pixelSize: Style.fontRegular
                wrapMode: Text.WordWrap
                onTextChanged: item.editText = text
            }
            Row {
                spacing: Style.spacingS

                AbstractButton {
                    width: saveLabel.implicitWidth + Style.spacingM * 2
                    height: units.gu(3.5)
                    enabled: !item.saving && item.editText.trim().length > 0
                    onClicked: item.saveEdit()
                    Rectangle { anchors.fill: parent; radius: height / 2; color: parent.enabled ? Style.brand : Style.iconBackground }
                    Label {
                        id: saveLabel
                        anchors.centerIn: parent
                        text: item.saving ? i18n.tr("Saving…") : i18n.tr("Save")
                        color: Style.textOnBrand
                    }
                }
                AbstractButton {
                    width: cancelEditLabel.implicitWidth + Style.spacingM * 2
                    height: units.gu(3.5)
                    onClicked: item.cancelEdit()
                    Label {
                        id: cancelEditLabel
                        anchors.centerIn: parent
                        text: i18n.tr("Cancel")
                        color: Style.textSecondary
                    }
                }
            }
        }

        // Like + reply action row
        Row {
            x: units.gu(3.5) + Style.spacingS
            spacing: Style.spacingM

            VoteBar {
                anchors.verticalCenter: parent.verticalCenter
                author: c.author || ""
                permlink: c.permlink || ""
                voteType: "comment"
                showComments: false
                showShare: false
                votes: c.votes || 0
                upvoted: (c.voters || []).indexOf(Session.username) >= 0
                width: units.gu(8)
            }

            AbstractButton {
                anchors.verticalCenter: parent.verticalCenter
                width: replyRow.implicitWidth
                height: units.gu(3.5)
                onClicked: item.replyRequested(c)

                Row {
                    id: replyRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.spacingXs
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(2.2); height: width
                        name: "message"
                        color: Style.textSecondary
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: i18n.tr("Reply")
                        font.pixelSize: Style.fontSmall
                        color: Style.textSecondary
                    }
                }
            }
        }

        // Replies toggle
        AbstractButton {
            visible: item.replies.length > 0
            x: units.gu(3.5) + Style.spacingS
            width: toggleLabel.implicitWidth
            height: units.gu(3)
            onClicked: item.repliesExpanded = !item.repliesExpanded

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacingXs
                Label {
                    id: toggleLabel
                    text: item.repliesExpanded
                        ? i18n.tr("Hide replies")
                        : i18n.tr("%1 replies").arg(item.replies.length)
                    font.pixelSize: Style.fontSmall
                    font.weight: Font.DemiBold
                    color: Style.textSecondary
                }
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: units.gu(1.6); height: width
                    name: item.repliesExpanded ? "up" : "down"
                    color: Style.textSecondary
                }
            }
        }

        // Nested replies, indented with a vertical guide line
        Item {
            visible: item.repliesExpanded && item.replies.length > 0
            width: parent.width
            height: visible ? repliesCol.height : 0

            Rectangle {
                x: units.gu(1.75) - units.dp(1)
                width: units.dp(2)
                height: parent.height
                color: Style.divider
            }

            Column {
                id: repliesCol
                x: units.gu(3.5)
                width: parent.width - x

                // A QML type cannot instantiate itself by name within its own
                // file ("instantiated recursively"), so nested replies are
                // loaded dynamically instead of via a direct CommentItem {}.
                Repeater {
                    model: item.replies
                    delegate: Loader {
                        id: replyLoader
                        width: repliesCol.width
                        property var replyData: modelData
                        Component.onCompleted: setSource(Qt.resolvedUrl("CommentItem.qml"), {
                            comment: replyData,
                            topLevel: false
                        })
                        Connections {
                            target: replyLoader.item
                            onDeleted: item.deleted(permlink)
                            onEdited: item.edited(permlink, newBody)
                            onReplyRequested: item.replyRequested(comment)
                            onAuthorClicked: item.authorClicked(author)
                        }
                    }
                }
            }
        }
    }
}
