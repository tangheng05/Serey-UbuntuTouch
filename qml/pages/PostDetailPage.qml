import QtQuick 2.7
import QtGraphicalEffects 1.0
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/PostService.js" as PostService
import "../services/CommentService.js" as CommentService
import "../services/VoteService.js" as VoteService
import "../services/HiddenPosts.js" as HiddenPosts

Page {
    id: page

    property string author: ""
    property string permlink: ""
    property string title: ""

    // cap article width on wide windows
    readonly property real maxContentWidth: units.gu(100)

    // from Saved Articles, renders instantly offline
    property var preloadedPost: null

    property var post: null
    property var comments: []
    property int commentCount: 0
    // patches feed card behind this page on go-back
    onCommentCountChanged: if (page.permlink) PostActions.commentCountChanged(page.permlink, page.commentCount)
    property bool loading: false
    property bool posting: false
    property string errorMsg: ""
    // deep-link scroll target after load
    property string scrollToCommentPermlink: ""
    // on-screen-keyboard height, composer rides above it
    readonly property real kbHeight: Qt.inputMethod.visible ? Qt.inputMethod.keyboardRectangle.height : 0
    // replying to a specific comment, cleared after post/cancel
    property var replyTarget: null

    readonly property bool postReady: page.post !== null && (page.permlink || "").length > 0
    readonly property bool isSaved: (SavedPosts.rev, SavedPosts.isSaved(page.permlink))
    // same URL shape as VoteBar share / feed rows
    readonly property string shareUrl: (page.author.length > 0 && page.permlink.length > 0)
        ? ("https://serey.io/authors/" + page.author + "/" + page.permlink) : ""
    // own post gets Edit/Delete instead of moderation
    readonly property bool isOwnPost: Session.isLoggedIn && page.author !== "" && page.author === Session.username

    function toggleSaved() {
        if (page.isSaved) SavedPosts.remove(page.permlink);
        else SavedPosts.save(page.post);
    }

    // same as sheet's Hide row, plus a pop
    function hidePost() {
        HiddenPosts.hide(page.permlink);
        PostActions.hideRequested(page.author, page.permlink);
        page.pageStack.pop();
    }

    function openEditor() {
        var ed = page.pageStack.push(Qt.resolvedUrl("CreatePostPage.qml"), { editPost: page.post });
        if (ed && ed.saved) ed.saved.connect(page.load);
    }

    // content is gone either way, unwind to feed
    Connections {
        target: PostActions
        function onPostDeleted(author, permlink) {
            if (permlink === page.permlink) page.pageStack.pop();
        }
        function onUserBlocked(username) {
            if (username === page.author) page.pageStack.pop();
        }
        function onEditRequested(post) {
            if (post && post.permlink === page.permlink) page.openEditor();
        }
    }

    header: Item { height: 0 }

    Rectangle {
        id: postDetailHeader
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: units.gu(6) + units.dp(1)
        color: Style.surface
        z: 10

        AbstractButton {
            id: backBtn
            anchors { left: parent.left; leftMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
            width: units.gu(4); height: width
            onClicked: page.pageStack.pop()
            Icon { anchors.centerIn: parent; width: units.gu(2.4); height: width; name: "back"; color: Style.textPrimary }
        }

        Label {
            anchors { left: backBtn.right; leftMargin: Style.spacingS; right: shareHeaderBtn.left; rightMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
            text: page.postReady ? (page.isVideoPost() ? Lang.tr("Video") : Lang.tr("Blog")) : ""
            font.pixelSize: Style.fontLarge
            font.weight: Font.Light
            color: Style.textPrimary
            elide: Text.ElideRight
        }

        AbstractButton {
            id: shareHeaderBtn
            anchors { right: moreHeaderBtn.left; rightMargin: Style.spacingXs; verticalCenter: parent.verticalCenter }
            width: units.gu(4); height: units.gu(4)
            enabled: page.shareUrl.length > 0
            onClicked: Share.open(page.shareUrl, shareHeaderBtn)
            Icon { anchors.centerIn: parent; width: units.gu(2.2); height: width; name: "share"; color: Style.textPrimary }
        }

        AbstractButton {
            id: moreHeaderBtn
            anchors { right: parent.right; rightMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
            width: units.gu(4); height: units.gu(4)
            enabled: page.postReady
            onClicked: PostActions.open(page.post, "blog")
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
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: units.dp(1)
            color: Style.divider
        }
    }

    function maincategory() {
        if (page.post && page.post.categories && page.post.categories.length > 0)
            return page.post.categories[0];
        return "serey";
    }

    // same rule FeedPage uses to route to VideoDetailPage
    function isVideoPost() {
        var p = page.post;
        if (!p) return false;
        if (p.primaryCategory === "video") return true;
        var c = p.categories;
        return !!(c && c.indexOf && c.indexOf("video") >= 0);
    }

    function load() {
        page.loading = true;
        page.errorMsg = "";
        PostService.detail(Config.baseUrl, author, permlink, Session.token,
            function (result) {
                page.loading = false;
                page.post = result.post;
                page.comments = result.replies || [];
                page.commentCount = page._countAll(page.comments);
                page._parseBody();
                // scroll to comment notification target once laid out
                if (page.scrollToCommentPermlink !== "") scrollToTimer.start();

                // cache wins over API, feed may be ahead
                if (detailVoteBar) {
                    detailVoteBar.voters = result.post.voters || [];
                    var cached = VoteService.getCached(page.author, page.permlink);
                    if (cached) {
                        detailVoteBar.votes = cached.votes;
                        detailVoteBar.upvoted = cached.upvoted;
                        detailVoteBar.flagged = cached.flagged;
                        if (cached.payout) detailVoteBar.payout = cached.payout;
                    } else {
                        var p = result.post;
                        detailVoteBar.votes = p.votes || 0;
                        detailVoteBar.flaggers = p.flaggers ? p.flaggers.length : 0;
                        detailVoteBar.payout = p.payout || "";
                        detailVoteBar.upvoted = p.voters && p.voters.indexOf(Session.username) >= 0;
                        detailVoteBar.flagged = p.flaggers && p.flaggers.indexOf(Session.username) >= 0;
                    }
                }
            },
            function (err) {
                page.loading = false;
                // Offline/failed fetch: fall back to a saved copy if we have one
                if (page.post === null) {
                    var saved = SavedPosts.get(page.permlink);
                    if (saved) {
                        page.post = saved;
                        page.commentCount = saved.comments || 0;
                        page._parseBody();
                        page.errorMsg = "";
                    } else {
                        page.errorMsg = err.message;
                    }
                }
            });
    }

    function pushLogin() {
        page.pageStack.push(Qt.resolvedUrl("LoginPage.qml"));
    }

    function _countAll(list) {
        var n = 0;
        for (var i = 0; i < list.length; i++) {
            n++;
            if (list[i].replies && list[i].replies.length)
                n += page._countAll(list[i].replies);
        }
        return n;
    }

    // Recursively drop a comment by permlink, wherever it sits in the tree.
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
        // must run in page scope, JS import is null in Loader delegates
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
        page.replyTarget = comment;
        composer.forceActiveFocus();
        Qt.inputMethod.show();
    }

    function cancelReply() {
        page.replyTarget = null;
    }

    function submitComment() {
        var text = composer.text.trim();
        if (text.length === 0)
            return;
        if (!Session.isLoggedIn) {
            Toast.error(Lang.tr("Please log in first."));
            page.pushLogin();
            return;
        }
        var target = page.replyTarget;
        var parentAuthor = target ? target.author : page.author;
        var parentPermlink = target ? target.permlink : page.permlink;

        page.posting = true;
        CommentService.create(Config.baseUrl,
            { parentAuthor: parentAuthor, parentPermlink: parentPermlink,
              maincategory: page.maincategory(), body: text },
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
                // reload for real server permlink
                page.load();
            },
            function (err) {
                page.posting = false;
                Toast.error((err && err.message) ? err.message : Lang.tr("Couldn't post comment."));
            });
    }

    // Recursively insert `reply` under the comment matching `parentPermlink`.
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

    // --- Body HTML -> {type: "text"|"image", content} blocks -----------------
    ListModel { id: bodyModel }

    function _parseBody() {
        bodyModel.clear();
        if (!page.post)
            return;
        var html = page.post.body || "";

        // data-image-url containers -> plain <img> for the splitter
        html = html.replace(/<[^>]*data-image-url="([^"]*)"[^>]*>/g, '<img src="$1"/>');

        var pieces = [];
        var remaining = html;
        var imgPattern = /<img[^>]*src=["']([^"']*)["'][^>]*\/?>/;
        var m;
        while ((m = imgPattern.exec(remaining)) !== null) {
            var before = remaining.substring(0, m.index);
            if (before) pieces.push({ type: "html", content: before });
            pieces.push({ type: "image", content: m[1] });
            remaining = remaining.substring(m.index + m[0].length);
        }
        if (remaining) pieces.push({ type: "html", content: remaining });

        var featuredSrc = page.post.thumbnail || "";
        var seenImages = {};
        for (var i = 0; i < pieces.length; i++) {
            var piece = pieces[i];
            if (piece.type === "image") {
                if (piece.content === featuredSrc) continue;
                if (seenImages[piece.content]) continue;
                seenImages[piece.content] = true;
                bodyModel.append({ type: "image", content: piece.content, links: "[]" });
            } else {
                var text = piece.content;
                // RichText collapses "\n", use <br/> for block boundaries
                text = text.replace(/<\/p>/gi, "<br/><br/>");
                text = text.replace(/<p[^>]*>/gi, "");
                text = text.replace(/<div[^>]*>/gi, "");
                text = text.replace(/<\/div>/gi, "<br/>");
                text = text.replace(/<strong>/gi, "<b>");
                text = text.replace(/<\/strong>/gi, "</b>");
                text = text.replace(/<em>/gi, "<i>");
                text = text.replace(/<\/em>/gi, "</i>");
                text = text.replace(/<h[1-6][^>]*>/gi, "<b>");
                text = text.replace(/<\/h[1-6]>/gi, "</b><br/><br/>");
                text = text.replace(/<li[^>]*>/gi, "• ");
                text = text.replace(/<\/li>/gi, "<br/>");
                text = text.replace(/<\/?(?:ul|ol)[^>]*>/gi, "");
                text = text.replace(/<br\s*\/?>/gi, "<br/>");
                text = text.replace(/<(?!\/?(?:b|i|br|u|a)\b)[^>]*>/gi, "");
                text = text.replace(/&nbsp;/g, " ");
                text = text.replace(/&amp;/g, "&");
                text = text.replace(/&lt;/g, "<");
                text = text.replace(/&gt;/g, ">");
                text = text.replace(/&quot;/g, "\"");
                // decode numeric entities, keep &,<,> encoded
                text = text.replace(/&#(\d+);/g, function (mm, n) {
                    var code = parseInt(n, 10);
                    return (code === 38 || code === 60 || code === 62) ? mm : String.fromCharCode(code);
                });
                text = text.replace(/&#x([0-9a-fA-F]+);/gi, function (mm, n) {
                    var code = parseInt(n, 16);
                    return (code === 38 || code === 60 || code === 62) ? mm : String.fromCharCode(code);
                });
                // collapse/trim break runs, no blank-line edges
                text = text.replace(/(?:<br\/>\s*){3,}/gi, "<br/><br/>");
                text = text.replace(/^(?:\s|<br\/>)+/i, "");
                text = text.replace(/(?:\s|<br\/>)+$/i, "");
                // capture anchor href + visible text for tap-to-open
                var links = [];
                var reA = /<a\s+[^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/a>/gi;
                var am;
                while ((am = reA.exec(text)) !== null) {
                    var vis = am[2].replace(/<[^>]+>/g, "")       // strip inner <b>/<i> etc.
                                   .replace(/&amp;/g, "&").replace(/&lt;/g, "<")
                                   .replace(/&gt;/g, ">").replace(/&quot;/g, "\"")
                                   .replace(/&#(\d+);/g, function (mm, n) { return String.fromCharCode(parseInt(n, 10)); })
                                   .replace(/&#x([0-9a-fA-F]+);/gi, function (mm, n) { return String.fromCharCode(parseInt(n, 16)); });
                    if (vis.length > 0) links.push({ href: am[1], text: vis });
                }
                if (text.length > 0)
                    bodyModel.append({ type: "text", content: text, links: JSON.stringify(links) });
            }
        }
    }

    Component.onCompleted: {
        // Render the saved copy immediately (instant + offline), then refresh.
        if (page.preloadedPost) {
            page.post = page.preloadedPost;
            page.commentCount = page.preloadedPost.comments || 0;
            page._parseBody();
        }
        load();
    }

    // Open a creator's profile (post author or a comment author).
    function openProfile(username) {
        if (username)
            page.pageStack.push(Qt.resolvedUrl("ProfileViewPage.qml"), { username: username });
    }
    function openAuthor() { if (page.post) page.openProfile(page.post.author); }

    // deep-link scroll target, after layout settles
    Timer {
        id: scrollToTimer
        interval: 350
        onTriggered: {
            for (var i = 0; i < page.comments.length; i++) {
                if (page.comments[i].permlink === page.scrollToCommentPermlink) {
                    var it = commentsRepeater.itemAt(i)
                    if (it) {
                        var targetY = contentCol.y + it.mapToItem(contentCol, 0, 0).y
                        scroll.contentY = Math.max(0, Math.min(targetY - units.gu(2),
                                          scroll.contentHeight - scroll.height))
                    }
                    return
                }
            }
        }
    }

    // owns arrow-key focus, focusDetail() targets this
    property Item keyboardFocusItem: scroll

    KeyboardAwareFlickable {
        id: scroll
        anchors { top: postDetailHeader.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.bottomMargin: footer.visible ? footer.height + page.kbHeight : 0
        // move in step with footer's own bottomMargin
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
        contentWidth: width
        contentHeight: contentCol.height
        clip: true
        visible: page.post !== null
        // dismiss keyboard only if composer was focused
        onMovementStarted: if (composer.activeFocus) Qt.inputMethod.hide()
        opacity: 0
        NumberAnimation on opacity { from: 0; to: 1; duration: 250; easing.type: Easing.OutQuad }

        // arrow/Page/Space/Home/End scroll the article
        activeFocusOnTab: true
        function _kbScroll(dy) {
            var maxY = Math.max(0, scroll.contentHeight - scroll.height + scroll.bottomMargin);
            scroll.contentY = Math.max(0, Math.min(maxY, scroll.contentY + dy));
        }
        Keys.onPressed: {
            var pageStep = scroll.height * 0.9;
            var lineStep = units.gu(6);
            if (event.key === Qt.Key_Down)          { scroll._kbScroll(lineStep);  event.accepted = true; }
            else if (event.key === Qt.Key_Up)       { scroll._kbScroll(-lineStep); event.accepted = true; }
            else if (event.key === Qt.Key_PageDown) { scroll._kbScroll(pageStep);  event.accepted = true; }
            else if (event.key === Qt.Key_PageUp)   { scroll._kbScroll(-pageStep); event.accepted = true; }
            else if (event.key === Qt.Key_Home)     { scroll.contentY = 0; event.accepted = true; }
            else if (event.key === Qt.Key_End)      { scroll._kbScroll(scroll.contentHeight); event.accepted = true; }
            else if (event.key === Qt.Key_Space)    { scroll._kbScroll((event.modifiers & Qt.ShiftModifier) ? -pageStep : pageStep); event.accepted = true; }
            // back to master list
            else if (event.key === Qt.Key_Left || event.key === Qt.Key_Escape) { Nav.focusMaster(); event.accepted = true; }
        }
        onVisibleChanged: if (visible && !composer.activeFocus) Qt.callLater(scroll.forceActiveFocus)
        Component.onCompleted: if (visible && !composer.activeFocus) scroll.forceActiveFocus()

        Column {
            id: contentCol
            width: Math.min(scroll.width, page.maxContentWidth)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.spacingM

            Item { width: 1; height: Style.spacingS }

            // Category badge
            Row {
                visible: page.post && page.post.categories && page.post.categories.length > 0
                x: Style.spacingM
                spacing: Style.spacingXs

                Rectangle {
                    width: units.dp(10); height: units.dp(10)
                    radius: units.dp(2)
                    color: Style.accentRed
                    anchors.verticalCenter: parent.verticalCenter
                }
                Label {
                    text: page.maincategory().toUpperCase()
                    font.pixelSize: Style.fontSmall
                    font.weight: Font.Bold
                    color: Style.accentRed
                    anchors.verticalCenter: parent.verticalCenter

                    // Opens the blog tab filtered to this category, in the post's own community.
                    MouseArea {
                        anchors { fill: parent; margins: -Style.spacingXs }
                        onClicked: {
                            var cid = page.post ? page.post.communityId : 0;
                            var info = cid > 0 ? Config.communityInfoFor(cid) : null;
                            var community = info ? {
                                id: cid,
                                name: info.title || info.name || "",
                                icon: info.icon || "",
                                allowPost: !!info.allowPost,
                                videoAllowPost: !!info.videoAllowPost
                            } : null;
                            Nav.filterCategory(page.maincategory(), community);
                        }
                    }
                }
                // Sub-categories (everything after the main tag), e.g. "› Running".
                Label {
                    visible: text.length > 0
                    text: (page.post && page.post.subCategories && page.post.subCategories.length > 0)
                          ? ("› " + page.post.subCategories.join(" · ").toUpperCase()) : ""
                    font.pixelSize: Style.fontSmall
                    font.weight: Font.Bold
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Label {
                width: parent.width - Style.spacingM * 2 - Style.wrapSafeMargin
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.post ? page.post.title : ""
                font.pixelSize: Style.fontTitle
                font.weight: Font.DemiBold
                font.family: Style.fontFor(text)
                color: Style.textPrimary
                wrapMode: Text.Wrap
            }

            Row {
                visible: !Config.wideMode
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - Style.spacingM * 2
                spacing: Style.spacingS

                Item {
                    id: detailAvatar
                    anchors.verticalCenter: parent.verticalCenter
                    width: units.gu(4.25); height: width

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Style.avatarTint(page.post ? page.post.author : "")
                        visible: !page.post || (page.post.authorImage || "") === ""

                        Label {
                            anchors.centerIn: parent
                            text: page.post && page.post.author ? page.post.author.charAt(0).toUpperCase() : "?"
                            font.pixelSize: Style.fontMedium
                            font.bold: true
                            color: Style.brand
                        }
                    }

                    Image {
                        id: detailAvatarImg
                        anchors.fill: parent
                        source: page.post ? (page.post.authorImage || "") : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: false
                    }
                    Rectangle {
                        id: detailAvatarMask
                        anchors.fill: parent
                        radius: width / 2
                        visible: false
                    }
                    OpacityMask {
                        anchors.fill: parent
                        source: detailAvatarImg
                        maskSource: detailAvatarMask
                        visible: page.post && (page.post.authorImage || "") !== ""
                    }

                    MouseArea { anchors.fill: parent; onClicked: page.openAuthor() }
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        var name = page.post ? page.post.author : "";
                        var time = page.post ? Style.formatTimeAgo(page.post.date) : "";
                        return name + (time ? "  ·  " + time : "");
                    }
                    textSize: Label.Small
                    font.weight: Font.DemiBold
                    color: Style.textPrimary
                    MouseArea { anchors.fill: parent; onClicked: page.openAuthor() }
                }
            }

            Rectangle { width: parent.width; height: units.dp(1); color: "black" }

            // masked against rounded Rectangle for true rounded crop
            Item {
                id: coverFrame
                width: parent.width - Style.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                height: visible ? width * 0.6 : 0
                visible: page.post && (page.post.thumbnail || "") !== ""

                Rectangle {
                    anchors.fill: parent
                    radius: Style.thumbRadius
                    color: Style.iconBackground
                }
                Image {
                    id: coverImg
                    anchors.fill: parent
                    source: page.post ? (page.post.thumbnail || "") : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    autoTransform: true     // honour EXIF orientation
                    visible: false
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    opacity: status === Image.Ready ? 1.0 : 0.0
                }
                Rectangle {
                    id: coverMask
                    anchors.fill: parent
                    radius: Style.thumbRadius
                    visible: false
                }
                OpacityMask {
                    anchors.fill: parent
                    source: coverImg
                    maskSource: coverMask
                    opacity: coverImg.opacity
                }
            }

            // shared left/right inset for text blocks and images
            Column {
                width: parent.width - Style.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.spacingS

                Repeater {
                    model: bodyModel

                    delegate: Loader {
                        width: parent.width
                        sourceComponent: model.type === "image" ? bodyImageComp : bodyTextComp

                        Component {
                            id: bodyImageComp
                            Item {
                                width: parent.width
                                height: bImg.height

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Style.thumbRadius
                                    color: Style.iconBackground
                                }
                                Image {
                                    id: bImg
                                    width: parent.width
                                    fillMode: Image.PreserveAspectFit
                                    source: model.content
                                    asynchronous: true
                                    autoTransform: true     // honour EXIF orientation
                                    visible: false
                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                    opacity: status === Image.Ready ? 1.0 : 0.0
                                }
                                Rectangle {
                                    id: bImgMask
                                    anchors.fill: parent
                                    radius: Style.thumbRadius
                                    visible: false
                                }
                                OpacityMask {
                                    anchors.fill: parent
                                    source: bImg
                                    maskSource: bImgMask
                                    opacity: bImg.opacity
                                }
                            }
                        }

                        Component {
                            id: bodyTextComp
                            // sized to full content height, avoid clipping
                            Item {
                                width: parent.width - Style.wrapSafeMargin
                                height: bodyTxt.height

                                // native long-press selection UI (drag handles + Copy)
                                TextArea {
                                    id: bodyTxt
                                    width: parent.width
                                    // stray-selection guard: ignore selection from a scroll gesture
                                    property real _lastScrollMs: 0
                                    property bool _scrolledSinceFocus: false
                                    readonly property int _scrollSelGuardMs: 1500
                                    text: model.content
                                    textFormat: TextEdit.RichText
                                    readOnly: true
                                    // disables internal scroll so outer Flickable can cancel long-press
                                    autoSize: true
                                    maximumLineCount: 0
                                    // autoSize under-measures RichText, grow to painted height
                                    onPaintedHeightChanged: Qt.callLater(_fitHeight)
                                    onLineCountChanged: Qt.callLater(_fitHeight)
                                    Component.onCompleted: Qt.callLater(_fitHeight)
                                    function _fitHeight() { if (height < paintedHeight) height = paintedHeight; }
                                    // long-press needs focus first
                                    activeFocusOnPress: true
                                    // forward reading keys to flick, copy/select-all pass through
                                    Keys.forwardTo: [scroll]
                                    font.pixelSize: Config.wideMode ? Style.fontMedium * 1.2 : Style.fontMedium
                                    font.family: Style.fontFor(text)
                                    color: Style.textPrimary
                                    // Flat look — not a text field
                                    StyleHints {
                                        backgroundColor: "transparent"
                                        frameSpacing: 0
                                        overlaySpacing: 0
                                    }
                                    onLinkActivated: Qt.openUrlExternally(link)
                                    // fresh press resets stray-scroll flag
                                    onActiveFocusChanged: if (activeFocus) bodyTxt._scrolledSinceFocus = false
                                    // caret visible only while selected, gates Copy popover
                                    onSelectedTextChanged: {
                                        // clear stray selection from scroll gesture
                                        if (selectedText.length > 0
                                                && (scroll.moving || scroll.flicking
                                                    || (bodyTxt._scrolledSinceFocus
                                                        && (Date.now() - bodyTxt._lastScrollMs) < bodyTxt._scrollSelGuardMs))) {
                                            bodyTxt.deselect();
                                            return;
                                        }
                                        cursorVisible = (selectedText.length > 0);
                                    }
                                    onCursorVisibleChanged: if (!cursorVisible && selectedText.length > 0) cursorVisible = true
                                }

                                // feeds the selection guard above
                                Connections {
                                    target: scroll
                                    onMovementStarted: { bodyTxt._scrolledSinceFocus = true; bodyTxt._lastScrollMs = Date.now(); bodyTxt.deselect() }
                                    onMovementEnded:   bodyTxt._lastScrollMs = Date.now()
                                    onFlickStarted:    { bodyTxt._scrolledSinceFocus = true; bodyTxt._lastScrollMs = Date.now() }
                                    onFlickEnded:      bodyTxt._lastScrollMs = Date.now()
                                    onDraggingChanged: { if (scroll.dragging) bodyTxt._scrolledSinceFocus = true; bodyTxt._lastScrollMs = Date.now() }
                                }

                                // resolve tap position to a link span ourselves
                                MouseArea {
                                    anchors.fill: bodyTxt
                                    propagateComposedEvents: true
                                    property string _pendingHref: ""
                                    function _hrefAt(x, y) {
                                        var arr;
                                        try { arr = JSON.parse(model.links || "[]"); } catch (e) { return ""; }
                                        if (!arr.length) return "";
                                        var pos = bodyTxt.positionAt(x, y);
                                        var plain = bodyTxt.getText(0, bodyTxt.length);
                                        for (var i = 0; i < arr.length; i++) {
                                            var t = arr[i].text;
                                            if (!t) continue;
                                            var from = 0, idx;
                                            while ((idx = plain.indexOf(t, from)) !== -1) {
                                                if (pos >= idx && pos <= idx + t.length) return arr[i].href;
                                                from = idx + 1;
                                            }
                                        }
                                        return "";
                                    }
                                    onPressed: {
                                        _pendingHref = _hrefAt(mouse.x, mouse.y);
                                        // only grab press when it's on a link
                                        mouse.accepted = (_pendingHref.length > 0);
                                    }
                                    onClicked: {
                                        if (_pendingHref.length > 0) Qt.openUrlExternally(_pendingHref);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: units.dp(1); color: "black" }

            // --- Comments ---------------------------------------------------
            Label {
                width: parent.width - Style.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                text: Lang.tr("COMMENTS (%1)").arg(page.commentCount)
                font.pixelSize: Style.fontSmall
                font.weight: Font.Bold
                color: Style.textSecondary
            }

            Label {
                width: parent.width - Style.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                visible: page.comments.length === 0
                text: Lang.tr("No comments yet. Be the first!")
                textSize: Label.Small
                color: Style.textSecondary
            }

            Repeater {
                id: commentsRepeater
                model: page.comments
                delegate: CommentItem {
                    width: contentCol.width
                    comment: modelData
                    onDeleted: page.removeComment(permlink)
                    onEdited: page.editComment(permlink, newBody, parentAuthor, parentPermlink)
                    onReplyRequested: page.startReply(comment)
                    onAuthorClicked: page.openProfile(author)
                }
            }

            Item { width: 1; height: Style.spacingM }
        }

    }

    LoadingState {
        anchors { top: postDetailHeader.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: page.loading && page.post === null
        count: 1
    }
    ErrorState {
        anchors { top: postDetailHeader.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: page.errorMsg !== "" && page.post === null
        message: page.errorMsg
        onRetry: page.load()
    }

    // --- Fixed footer: votes/voters/share + comment composer ---------------
    Rectangle {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        // ride above on-screen keyboard
        anchors.bottomMargin: page.kbHeight
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
        height: footerCol.height
        visible: page.post !== null
        color: Style.surface

    Column {
        id: footerCol
        width: Math.min(parent.width, page.maxContentWidth)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: units.dp(4)

        Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

        VoteBar {
            id: detailVoteBar
            width: parent.width - Style.spacingM * 2
            anchors.horizontalCenter: parent.horizontalCenter
            author: page.author
            permlink: page.permlink
            voteType: "post"
            onChain: page.post ? (page.post.postToBlockchain !== false) : true
            showComments: false
            showVotersLabel: false
            showShare: false   // Share now lives in the header action bar, not duplicated here
            onRequireLogin: page.pushLogin()

            // sync count with what feed card shows
            function applyCache() {
                var cached = VoteService.getCached(page.author, page.permlink);
                if (cached) {
                    detailVoteBar.votes = cached.votes;
                    detailVoteBar.upvoted = cached.upvoted;
                    detailVoteBar.flagged = cached.flagged;
                    if (cached.payout) detailVoteBar.payout = cached.payout;
                }
            }
            Component.onCompleted: applyCache()
            onVisibleChanged: if (visible) applyCache()
        }

        // Replying-to banner
        Row {
            visible: page.replyTarget !== null
            width: parent.width - Style.spacingM * 2
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.spacingS

            Label {
                text: page.replyTarget ? Lang.tr("Replying to @%1").arg(page.replyTarget.author) : ""
                font.pixelSize: Style.fontSmall
                color: Style.textSecondary
            }
            AbstractButton {
                width: cancelLabel.implicitWidth
                height: cancelLabel.implicitHeight
                onClicked: page.cancelReply()
                Label {
                    id: cancelLabel
                    text: Lang.tr("Cancel")
                    font.pixelSize: Style.fontSmall
                    font.weight: Font.DemiBold
                    color: Style.brand
                }
            }
        }

        // Comment input pill
        Row {
            width: parent.width - Style.spacingM * 2
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.spacingS

            // styled TextField for native selection + Cut/Copy/Paste
            TextField {
                id: composer
                width: parent.width - sendButton.width - Style.spacingS
                height: units.gu(5)
                StyleHints {
                    backgroundColor: Style.iconBackground
                    borderColor: "transparent"
                    color: Style.textPrimary
                }
                hasClearButton: false
                placeholderText: Session.isLoggedIn
                    ? Lang.tr("Post a comment…")
                    : Lang.tr("Log in to comment…")
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
