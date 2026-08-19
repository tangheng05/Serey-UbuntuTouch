import QtQuick 2.7
import QtQuick.Controls 2.2
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/PostService.js" as PostService
import "../services/CommentService.js" as CommentService

Page {
    id: page

    property string author: ""
    property string permlink: ""
    readonly property real maxContentWidth: units.gu(60)

    property var post: null
    property var comments: []
    property int commentCount: 0
    // Broadcast so the feed card behind this page reflects adds/deletes when the user goes back; feed pages patch the row by permlink.
    onCommentCountChanged: if (page.permlink) PostActions.commentCountChanged(page.permlink, page.commentCount)
    property bool loading: false
    property bool posting: false
    property string errorMsg: ""
    property var replyTarget: null
    // Set while editing one of your own comments: the same composer, in edit mode.
    property var editTarget: null
    readonly property real kbHeight: Qt.inputMethod.visible ? Qt.inputMethod.keyboardRectangle.height : 0

    readonly property var imgs: post && post.images ? post.images : []

    header: Rectangle {
        height: units.gu(6)
        color: Style.surface

        BackButton {
            anchors { left: parent.left; leftMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
            onClicked: page.pageStack.pop()
        }

        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: units.dp(1)
            color: Style.divider
        }
    }

    function load() {
        loading = true;
        errorMsg = "";
        PostService.detailGallery(Config.baseUrl, author, permlink, Session.token,
            function (result) {
                loading = false;
                page.post = result.post;
                page.commentCount = result.post.comments;
                page.comments = result.replies || [];
            },
            function (err) {
                loading = false;
                page.errorMsg = err.message;
            });
    }

    function pushLogin() {
        page.pageStack.push(Qt.resolvedUrl("LoginPage.qml"));
    }

    function _removeFrom(list, permlinkToRemove) {
        var out = [];
        for (var i = 0; i < list.length; i++) {
            if (list[i].permlink === permlinkToRemove)
                continue;
            var node = list[i];
            if (node.replies && node.replies.length)
                node = Object.assign({}, node, { replies: page._removeFrom(node.replies, permlinkToRemove) });
            out.push(node);
        }
        return out;
    }

    function removeComment(permlinkToRemove) {
        page.comments = page._removeFrom(page.comments, permlinkToRemove);
        page.commentCount = Math.max(0, page.commentCount - 1);
        Toast.success(Lang.tr("Comment deleted"));
        // Must run in this page-level scope: the CommentService import resolves to null inside Loader-created reply row delegates.
        CommentService.remove(Config.baseUrl, permlinkToRemove, Session.username, Session.token,
            function () {},
            function (err) {
                Toast.error((err && err.message) ? err.message : Lang.tr("Couldn't delete comment."));
            });
    }

    function _editIn(list, permlinkToEdit, newBody) {
        var out = [];
        for (var i = 0; i < list.length; i++) {
            var node = list[i];
            if (node.permlink === permlinkToEdit)
                node = Object.assign({}, node, { body: newBody });
            else if (node.replies && node.replies.length)
                node = Object.assign({}, node, { replies: page._editIn(node.replies, permlinkToEdit, newBody) });
            out.push(node);
        }
        return out;
    }

    function editComment(permlinkToEdit, newBody, parentAuthor, parentPermlink) {
        page.comments = page._editIn(page.comments, permlinkToEdit, newBody);
        Toast.success(Lang.tr("Comment updated"));
        // Same page-level-scope reason as removeComment; existing permlink = update
        CommentService.create(Config.baseUrl,
            { parentAuthor: parentAuthor, parentPermlink: parentPermlink,
              body: newBody, permlink: permlinkToEdit },
            Session.token,
            function () {},
            function (err) {
                Toast.error((err && err.message) ? err.message : Lang.tr("Couldn't update comment."));
            });
    }

    function startReply(comment) {
        page.editTarget = null;
        page.replyTarget = comment;
        composer.forceActiveFocus();
        Qt.inputMethod.show();
    }

    function cancelReply() {
        page.replyTarget = null;
    }

    // Edit runs through the composer, pre-filled, instead of a second field in the row.
    function startEdit(comment) {
        page.replyTarget = null;
        page.editTarget = comment;
        composer.text = comment.body || "";
        composer.forceActiveFocus();
        Qt.inputMethod.show();
    }

    function cancelEdit() {
        page.editTarget = null;
        composer.text = "";
    }

    function _appendReply(list, parentPermlink, reply) {
        var out = [];
        for (var i = 0; i < list.length; i++) {
            var node = list[i];
            if (node.permlink === parentPermlink) {
                node = Object.assign({}, node, { replies: [reply].concat(node.replies || []) });
            } else if (node.replies && node.replies.length) {
                node = Object.assign({}, node, { replies: page._appendReply(node.replies, parentPermlink, reply) });
            }
            out.push(node);
        }
        return out;
    }

    function submitComment() {
        // Enter bypasses the Send button's enabled state, so a fast double tap posted twice.
        if (page.posting) return;
        // Word prediction can commit the first word before AutoCapitalize sees it, so the
        // send path capitalizes too; both are no-ops when the text already starts upper.
        var text = Style.sentenceCase(composer.text.trim());
        if (text.length === 0)
            return;
        if (!Session.isLoggedIn) {
            Toast.error(Lang.tr("Please log in first."));
            page.pushLogin();
            return;
        }
        // Same box, same Send: an edit updates instead of posting a new comment.
        if (page.editTarget) {
            var edited = page.editTarget;
            page.editTarget = null;
            composer.text = "";
            page.editComment(edited.permlink, text,
                             edited.parentAuthor || "", edited.parentPermlink || "");
            return;
        }
        var target = page.replyTarget;
        var parentAuthor = target ? target.author : page.author;
        var parentPermlink = target ? target.permlink : page.permlink;

        page.posting = true;
        CommentService.create(Config.baseUrl,
            { parentAuthor: parentAuthor, parentPermlink: parentPermlink, body: text },
            Session.token,
            function (data) {
                page.posting = false;
                composer.text = "";
                var mine = { author: Session.username, permlink: "", body: text,
                             parentAuthor: parentAuthor, parentPermlink: parentPermlink,
                             date: Lang.tr("just now"), votes: 0, voters: [], replies: [],
                             authorImage: Session.avatarUrl };
                if (target) {
                    page.comments = page._appendReply(page.comments, target.permlink, mine);
                } else {
                    page.comments = [mine].concat(page.comments);
                }
                page.commentCount = page.commentCount + 1;
                page.replyTarget = null;
                Toast.success(Lang.tr("Comment posted"));
                page.load();
            },
            function (err) {
                page.posting = false;
                Toast.error((err && err.message) ? err.message : Lang.tr("Couldn't post comment."));
            });
    }

    function openProfile() {
        if (page.post && page.post.author)
            page.pageStack.push(Qt.resolvedUrl("ProfileViewPage.qml"), { username: page.post.author });
    }

    Component.onCompleted: load()

    KeyboardAwareFlickable {
        id: scroll
        anchors { top: page.header.bottom; bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
        width: Math.min(parent.width, page.maxContentWidth)
        anchors.bottomMargin: footer.visible ? footer.height + page.kbHeight : 0
        contentWidth: width
        contentHeight: contentCol.height
        clip: true
        visible: page.post !== null
        opacity: 0
        NumberAnimation on opacity { from: 0; to: 1; duration: 250; easing.type: Easing.OutQuad }

        Column {
            id: contentCol
            width: scroll.width

            Item {
                width: parent.width
                height: units.gu(6)

                Row {
                    id: authorRow
                    // No right anchor: the row hugs the avatar + name, so the dead space beside it doesn't open the profile.
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom; leftMargin: Style.spacingM }
                    spacing: Style.spacingS

                    CircleImage {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(4.25); height: width
                        source: page.post ? (page.post.authorImage || "") : ""
                        decode: units.gu(9)
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(4.25); height: width
                        radius: width / 2
                        visible: !page.post || (page.post.authorImage || "") === ""
                        color: Style.avatarTint(page.post ? page.post.author : "")
                        Label {
                            anchors.centerIn: parent
                            text: page.post && page.post.author ? page.post.author.charAt(0).toUpperCase() : "?"
                            font.pixelSize: Style.fontMedium
                            font.bold: true
                            color: Style.brand
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0
                        Label {
                            text: page.post ? page.post.author : ""
                            font.pixelSize: Style.fontSmall
                            font.weight: Font.DemiBold
                            color: Style.textPrimary
                        }
                        Label {
                            text: page.post ? Style.formatTimeAgo(page.post.date) : ""
                            font.pixelSize: Style.fontXSmall
                            color: Style.textSecondary
                        }
                    }
                }

                MouseArea {
                    anchors { left: authorRow.left; top: parent.top; bottom: parent.bottom }
                    width: authorRow.width
                    onClicked: page.openProfile()
                }
            }

            Item {
                id: cover
                width: parent.width
                height: width

                Rectangle { anchors.fill: parent; color: Style.iconBackground }

                SwipeView {
                    id: swipe
                    anchors.fill: parent
                    clip: true

                    Repeater {
                        model: page.imgs
                        delegate: Image {
                            source: modelData
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            autoTransform: true     // honour EXIF orientation
                            sourceSize.width: cover.width * 2
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            opacity: status === Image.Ready ? 1.0 : 0.0
                        }
                    }
                }

                Row {
                    visible: page.imgs.length > 1
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: Style.spacingS }
                    spacing: Style.spacingXs

                    Repeater {
                        model: page.imgs.length
                        delegate: Rectangle {
                            width: units.dp(7); height: units.dp(7)
                            radius: width / 2
                            color: swipe.currentIndex === index ? Style.brand : Style.dotInactive
                        }
                    }
                }
            }

            Item { width: 1; height: Style.spacingM }

            Label {
                visible: page.post && (page.post.caption || "") !== ""
                width: parent.width - Style.spacingM * 2 - Style.wrapSafeMargin
                x: Style.spacingM
                text: page.post ? page.post.caption : ""
                font.pixelSize: Style.fontRegular
                font.family: Style.fontFor(text)
                color: Style.textPrimary
                wrapMode: Text.Wrap
            }

            Item { width: 1; height: Style.spacingM }

            Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

            Item { width: 1; height: Style.spacingS }

            // --- Comments ---------------------------------------------------
            Label {
                width: parent.width - Style.spacingM * 2
                x: Style.spacingM
                visible: page.comments.length === 0
                text: Lang.tr("No comments yet. Be the first!")
                textSize: Label.Small
                color: Style.textSecondary
            }

            Repeater {
                model: page.comments
                delegate: CommentItem {
                    width: contentCol.width
                    comment: modelData
                    onDeleted: page.removeComment(permlink)
                    onEditRequested: page.startEdit(comment)
                    onReplyRequested: page.startReply(comment)
                    onAuthorClicked: page.pageStack.push(Qt.resolvedUrl("ProfileViewPage.qml"), { username: author })
                }
            }

            Item { width: 1; height: Style.spacingM }
        }
    }

    LoadingState {
        anchors { top: page.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: page.loading && page.post === null
        count: 1
        fullBleedCover: true
    }
    ErrorState {
        anchors { top: page.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: page.errorMsg !== "" && page.post === null
        message: page.errorMsg
        onRetry: page.load()
    }

    // --- Fixed footer: votes/voters/share + comment composer ---------------
    Rectangle {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.bottomMargin: page.kbHeight
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
        height: footerCol.height
        visible: page.post !== null
        color: Style.surface

    Column {
        id: footerCol
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width, page.maxContentWidth)
        spacing: Style.spacingS

        Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

        Item { width: 1; height: Style.spacingXs }

        VoteBar {
            width: parent.width - Style.spacingM * 2
            anchors.horizontalCenter: parent.horizontalCenter
            author: page.author
            permlink: page.permlink
            voteType: "post"
            onChain: page.post ? (page.post.postToBlockchain !== false) : true
            votes: page.post ? page.post.votes : 0
            voters: page.post ? (page.post.voters || []) : []
            flaggers: page.post && page.post.flaggers ? page.post.flaggers.length : 0
            showComments: false
            showVotersLabel: false
            payout: page.post ? page.post.payout : ""
            upvoted: page.post && page.post.voters ? page.post.voters.indexOf(Session.username) >= 0 : false
            flagged: page.post && page.post.flaggers ? page.post.flaggers.indexOf(Session.username) >= 0 : false
            onRequireLogin: page.pushLogin()
        }

        Row {
            visible: page.replyTarget !== null || page.editTarget !== null
            width: parent.width - Style.spacingM * 2
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.spacingS

            Label {
                text: page.editTarget ? Lang.tr("Editing your comment")
                    : page.replyTarget ? Lang.tr("Replying to @%1").arg(page.replyTarget.author) : ""
                font.pixelSize: Style.fontSmall
                color: Style.textSecondary
            }
            AbstractButton {
                width: cancelLabel.implicitWidth
                height: cancelLabel.implicitHeight
                onClicked: page.editTarget ? page.cancelEdit() : page.cancelReply()
                Label {
                    id: cancelLabel
                    text: Lang.tr("Cancel")
                    font.pixelSize: Style.fontSmall
                    font.weight: Font.DemiBold
                    color: Style.brand
                }
            }
        }

        Row {
            width: parent.width - Style.spacingM * 2
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.spacingS

            // Lomiri TextField (not a raw TextInput): only the styled component wires up native long-press selection + Cut/Copy/Paste; StyleHints keep the gray-pill look.
            TextField {
                id: composer
                // Stands in for the keyboard's auto-shift on the first letter.
                AutoCapitalize { field: composer }
                width: parent.width - sendButton.width - Style.spacingS
                height: units.gu(5)
                StyleHints {
                    backgroundColor: Style.iconBackground
                    borderColor: "transparent"
                    color: Style.textPrimary
                }
                hasClearButton: false
                placeholderText: !Session.isLoggedIn ? Lang.tr("Log in to comment…")
                               : page.editTarget ? Lang.tr("Edit your comment…")
                                                 : Lang.tr("Post a comment…")
                font.family: Style.fontFor(text)
                font.pixelSize: Style.fontRegular
                onAccepted: page.submitComment()
            }

            AbstractButton {
                id: sendButton
                width: units.gu(5); height: units.gu(5)
                enabled: !page.posting && composer.text.trim().length > 0
                onClicked: page.submitComment()

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: sendButton.enabled ? Style.brand : Style.iconBackground
                }
                Icon {
                    anchors.centerIn: parent
                    width: units.gu(2.4); height: width
                    name: "send"
                    color: sendButton.enabled ? Style.textOnBrand : Style.textSecondary
                }
            }
        }

        Item { width: 1; height: Style.spacingS }
    }
    }
}
