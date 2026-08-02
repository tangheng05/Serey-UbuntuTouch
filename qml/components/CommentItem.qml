import QtQuick 2.7
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../services/CommentService.js" as CommentService
import "../services/VoteService.js" as VoteService

Item {
    id: item
    property var comment: ({})
    readonly property var c: comment ? comment : ({})
    readonly property var replies: c.replies || []
    property int depth: 0
    // Nested replies start collapsed so a deep thread doesn't eagerly instantiate
    property bool repliesExpanded: depth < 1
    property bool topLevel: true

    // Only the author can edit/delete, and only a comment that exists server-side (optimistic local comments carry an empty permlink).
    readonly property bool canModify: Session.isLoggedIn
                                      && c.author === Session.username
                                      && (c.permlink || "").length > 0
    property bool menuOpen: false
    property bool confirmingDelete: false
    property bool editing: false
    property string editText: ""
    property bool saving: false

    signal deleted(string permlink)
    signal edited(string permlink, string newBody, string parentAuthor, string parentPermlink)
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
        if (text.length === 0)
            return;
        // Emit only. CommentItem is Loader-instantiated for nested replies, where JS module imports resolve to null, so the host page's handler makes the server call.
        item.editing = false;
        item.edited(c.permlink, text, c.parentAuthor || "", c.parentPermlink || "");
    }

    // Optimistic delete; same Loader/null-import reason as saveEdit for why the host page's onDeleted handler does the actual call.
    function doDelete() {
        item.deleted(c.permlink);
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

        Item {
            width: parent.width
            height: avatar.height
            z: item.menuOpen ? 20 : 0

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

            RowLayout {
                id: nameCol
                anchors {
                    left: avatar.right
                    leftMargin: Style.spacingS
                    right: moreButton.left
                    rightMargin: Style.spacingXs
                    verticalCenter: parent.verticalCenter
                }
                spacing: Style.spacingXs

                Label {
                    Layout.fillWidth: true
                    text: c.author || ""
                    font.pixelSize: Style.fontSmall
                    font.weight: Font.DemiBold
                    color: Style.textPrimary
                    elide: Text.ElideRight
                    MouseArea { anchors.fill: parent; onClicked: item.authorClicked(c.author || "") }
                }
                Label {
                    Layout.preferredWidth: implicitWidth
                    text: "· " + Style.formatTimeAgo(c.date || "")
                    font.pixelSize: Style.fontXSmall
                    color: Style.textSecondary
                    elide: Text.ElideRight
                }
            }

            AbstractButton {
                id: moreButton
                visible: item.canModify
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: units.gu(3); height: units.gu(3)
                onClicked: item.menuOpen = !item.menuOpen

                Column {
                    anchors.centerIn: parent
                    spacing: units.dp(3)
                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            width: units.dp(4); height: units.dp(4)
                            radius: width / 2
                            color: Style.textSecondary
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }
            }

            Rectangle {
                id: menu
                visible: item.menuOpen
                z: 10
                anchors { top: moreButton.bottom; right: moreButton.right; topMargin: Style.spacingXs }
                width: units.gu(16)
                height: item.confirmingDelete ? confirmCol.height : menuCol.height
                radius: Style.cardRadius
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
                            text: Lang.tr("Edit")
                            color: Style.textPrimary
                        }
                    }
                    Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }
                    AbstractButton {
                        width: parent.width; height: units.gu(5)
                        onClicked: item.confirmingDelete = true
                        Label {
                            anchors { left: parent.left; leftMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                            text: Lang.tr("Delete")
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
                        text: Lang.tr("Delete this comment?")
                        font.pixelSize: Style.fontSmall
                        color: Style.textPrimary
                        wrapMode: Text.Wrap
                    }
                    Item { width: 1; height: Style.spacingS }
                    Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }
                    Row {
                        width: parent.width
                        AbstractButton {
                            width: parent.width / 2; height: units.gu(5)
                            onClicked: { item.menuOpen = false; item.confirmingDelete = false; }
                            Label { anchors.centerIn: parent; text: Lang.tr("Cancel"); color: Style.textSecondary }
                        }
                        AbstractButton {
                            width: parent.width / 2; height: units.gu(5)
                            onClicked: { item.menuOpen = false; item.confirmingDelete = false; item.doDelete(); }
                            Label { anchors.centerIn: parent; text: Lang.tr("Delete"); color: Style.danger; font.weight: Font.DemiBold }
                        }
                    }
                }
            }
        }

        Label {
            visible: !item.editing
            width: parent.width - x - Style.wrapSafeMargin
            x: units.gu(3.5) + Style.spacingS
            text: c.body || ""
            font.pixelSize: Style.fontRegular
            font.family: Style.fontFor(text)
            color: Style.textPrimary
            wrapMode: Text.Wrap
        }

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
                wrapMode: Text.Wrap
                onTextChanged: item.editText = text
            }
            Row {
                spacing: Style.spacingS

                AbstractButton {
                    width: saveLabel.implicitWidth + Style.spacingM * 2
                    height: units.gu(3.5)
                    enabled: !item.saving && item.editText.trim().length > 0
                    onClicked: item.saveEdit()
                    Rectangle { anchors.fill: parent; radius: Style.cardRadius; color: parent.enabled ? Style.brand : Style.iconBackground }
                    Label {
                        id: saveLabel
                        anchors.centerIn: parent
                        text: item.saving ? Lang.tr("Saving…") : Lang.tr("Save")
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
                        text: Lang.tr("Cancel")
                        color: Style.textSecondary
                    }
                }
            }
        }

        Row {
            anchors.right: parent.right
            spacing: Style.spacingM

            VoteBar {
                anchors.verticalCenter: parent.verticalCenter
                author: c.author || ""
                permlink: c.permlink || ""
                voters: c.voters || []
                voteType: "comment"
                showComments: false
                showShare: false
                width: units.gu(8)
                Component.onCompleted: {
                    var me = Session.username || ""
                    var cached = VoteService.getCached(item.c.author || "", item.c.permlink || "")
                    if (cached) {
                        votes   = cached.votes
                        upvoted = cached.upvoted
                        flagged = cached.flagged
                    } else {
                        votes   = item.c.votes || 0
                        upvoted = me.length > 0 && (item.c.voterStr   || "").indexOf("," + me + ",") >= 0
                        flagged = me.length > 0 && (item.c.flaggerStr || "").indexOf("," + me + ",") >= 0
                        loadPersisted()
                    }
                }
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
                        text: Lang.tr("Reply")
                        font.pixelSize: Style.fontSmall
                        color: Style.textSecondary
                    }
                }
            }
        }

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
                        ? Lang.tr("Hide replies")
                        : Lang.tr("%1 replies").arg(item.replies.length)
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

        // Nested replies: only indent one level deep; deeper replies stay flat
        Item {
            visible: item.repliesExpanded && item.replies.length > 0
            width: parent.width
            height: visible ? repliesCol.height : 0

            // Guide line only on the first indent level; brand-tinted to trace the thread
            Rectangle {
                visible: item.depth === 0
                x: units.gu(1.25) - units.dp(1)
                width: units.dp(2)
                height: parent.height
                color: Style.brand
                opacity: 0.35
            }

            Column {
                id: repliesCol
                // 'item' inside a Loader delegate shadows the outer CommentItem id
                readonly property int ownerDepth: item.depth
                x: ownerDepth === 0 ? units.gu(2.5) : 0
                width: parent.width - x

                function forwardSignals(loaderItem) {
                    if (!loaderItem) return;
                    loaderItem.deleted.connect(function(permlink) { item.deleted(permlink) })
                    loaderItem.edited.connect(function(permlink, newBody, pa, pp) { item.edited(permlink, newBody, pa, pp) })
                    loaderItem.replyRequested.connect(function(c) { item.replyRequested(c) })
                    loaderItem.authorClicked.connect(function(author) { item.authorClicked(author) })
                }

                Repeater {
                    // Only instantiate reply rows while expanded; collapsing frees them.
                    model: item.repliesExpanded ? item.replies : []
                    delegate: Loader {
                        id: replyLoader
                        width: repliesCol.width
                        property var replyData: modelData
                        Component.onCompleted: setSource(Qt.resolvedUrl("CommentItem.qml"), {
                            comment:  replyData,
                            topLevel: false,
                            depth:    Math.min(repliesCol.ownerDepth + 1, 1)
                        })
                        onItemChanged: repliesCol.forwardSignals(replyLoader.item)
                    }
                }
            }
        }
    }
}
