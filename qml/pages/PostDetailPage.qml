import QtQuick 2.7
import QtGraphicalEffects 1.0
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/PostService.js" as PostService
import "../services/CommentService.js" as CommentService
import "../services/VoteService.js" as VoteService

/*
 * Full post view. Receives author/permlink (and an optional title for the
 * header) when pushed; fetches the full body + replies from the detail
 * endpoint. Provides upvote/downvote (VoteBar) and a comment composer + list.
 *
 * Body rendering: the API returns raw HTML with inline styles and unconstrained
 * <img> tags that Lomiri's Text.RichText can't lay out sanely (broken styles,
 * images overflowing the viewport). _parseBody() strips that down to alternating
 * plain-text blocks (bold/italic/links preserved) and full-width rounded images,
 * rendered as native Image/Label items instead of one big RichText blob.
 */
Page {
    id: page

    property string author: ""
    property string permlink: ""
    property string title: ""

    // When opened from the Saved Articles list, the full view-model is passed in
    // so the article renders instantly and reads offline; load() still runs as a
    // best-effort refresh (and silently no-ops when there's no connection).
    property var preloadedPost: null

    property var post: null
    property var comments: []
    property int commentCount: 0
    // Broadcast so the feed card behind this page reflects adds/deletes when the
    // user goes back; feed pages patch the row by permlink (like onPostDeleted).
    onCommentCountChanged: if (page.permlink) PostActions.commentCountChanged(page.permlink, page.commentCount)
    property bool loading: false
    property bool posting: false
    property string errorMsg: ""
    // When opened from a notification, scroll to this comment permlink after load.
    property string scrollToCommentPermlink: ""
    // On-screen-keyboard height; the docked comment composer rides above it.
    readonly property real kbHeight: Qt.inputMethod.visible ? Qt.inputMethod.keyboardRectangle.height : 0
    // Set while replying to a specific comment (rather than the post itself);
    // cleared after posting or via the composer's "Cancel" affordance.
    property var replyTarget: null

    // Minimal header: just a back button, no title text.
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

    // Save / unsave for offline reading. A sibling overlay (NOT inside the
    // Page.header item, whose right-anchored children don't lay out reliably on
    // Lomiri — the codebase's working pattern is a z-stacked overlay). Sits at the
    // header's top-right; enabled once the body has loaded so there's content to
    // persist. Filled blue = saved.
    AbstractButton {
        id: saveBtn
        anchors { right: parent.right; rightMargin: Style.spacingM; top: parent.top }
        height: units.gu(6)
        width: units.gu(6)
        z: 50
        enabled: page.post !== null && (page.permlink || "").length > 0
        readonly property bool isSaved: (SavedPosts.rev, SavedPosts.isSaved(page.permlink))
        onClicked: {
            if (saveBtn.isSaved) SavedPosts.remove(page.permlink);
            else SavedPosts.save(page.post);
        }
        Icon {
            anchors.centerIn: parent
            width: units.gu(2.6); height: width
            name: "save"
            color: saveBtn.isSaved ? Style.brand : Style.textSecondary
            opacity: saveBtn.enabled ? 1 : 0.35
        }
    }

    function maincategory() {
        if (page.post && page.post.categories && page.post.categories.length > 0)
            return page.post.categories[0];
        return "serey";
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
                // Deep-link from a comment/reply notification: scroll to the target
                // once the comment rows have laid out.
                if (page.scrollToCommentPermlink !== "") scrollToTimer.start();

                // Sync vote bar: cache wins over API data (the feed may have
                // recorded a vote the detail endpoint hasn't caught up with).
                if (detailVoteBar) {
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
                // Offline (or fetch failed): fall back to a saved copy so the
                // article still reads. If we already have a post (preloaded from
                // the saved list), keep it and swallow the refresh error.
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
        // Server delete must run in this page-level scope: the CommentService JS
        // import resolves to null inside the Repeater delegate's inline handler
        // (and inside Loader-created nested reply rows), so calling it there threw
        // "Cannot call method 'remove' of null" and the delete never reached the
        // server. Here in the page root the import is valid.
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
        // Server update runs in this page-level scope, not in CommentItem: its
        // CommentService import is null inside Loader-created reply rows (see
        // removeComment). Passing the existing permlink updates that comment.
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
                // Reload so the optimistic comment gets its real server
                // permlink — otherwise replying to it would fail with
                // "parent_permlink is a required field".
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

        // Custom editor containers carry the real src in data-image-url; replace
        // the entire parent tag with a plain <img> so the splitter catches them.
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
                bodyModel.append({ type: "image", content: piece.content });
            } else {
                var text = piece.content;
                // The blocks render as RichText, which (being HTML) collapses literal
                // "\n" to a single space — so block boundaries must become <br/> tags,
                // and a paragraph gap is a double break, to match the web spacing.
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
                // Decode numeric entities (e.g. &#8220; smart quotes, &#8217;
                // apostrophes) that the rich-text renderer can't render — but leave
                // &,<,> encoded so they aren't mistaken for markup.
                text = text.replace(/&#(\d+);/g, function (mm, n) {
                    var code = parseInt(n, 10);
                    return (code === 38 || code === 60 || code === 62) ? mm : String.fromCharCode(code);
                });
                text = text.replace(/&#x([0-9a-fA-F]+);/gi, function (mm, n) {
                    var code = parseInt(n, 16);
                    return (code === 38 || code === 60 || code === 62) ? mm : String.fromCharCode(code);
                });
                // Collapse runs of breaks and trim leading/trailing ones so blocks
                // don't start or end with blank lines.
                text = text.replace(/(?:<br\/>\s*){3,}/gi, "<br/><br/>");
                text = text.replace(/^(?:\s|<br\/>)+/i, "");
                text = text.replace(/(?:\s|<br\/>)+$/i, "");
                if (text.length > 0)
                    bodyModel.append({ type: "text", content: text });
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

    // Scroll to a specific comment after the layout settles post-load (deep-link
    // from a notification). Runs off scrollToCommentPermlink, set by the caller.
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

    KeyboardAwareFlickable {
        id: scroll
        anchors { top: page.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.bottomMargin: footer.visible ? footer.height + page.kbHeight : 0
        // Animate in step with the footer's own bottomMargin so the list and the
        // docked composer move together when the keyboard shows/hides.
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
        contentWidth: width
        contentHeight: contentCol.height
        clip: true
        visible: page.post !== null
        // Dismiss the keyboard on scroll, but only when the docked composer is the
        // focused input — otherwise scrolling while editing a comment inline would
        // close its keyboard mid-edit.
        onMovementStarted: if (composer.activeFocus) Qt.inputMethod.hide()
        opacity: 0
        NumberAnimation on opacity { from: 0; to: 1; duration: 250; easing.type: Easing.OutQuad }

        Column {
            id: contentCol
            width: scroll.width
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
                }
            }

            Label {
                width: parent.width - Style.spacingM * 2 - Style.wrapSafeMargin
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.post ? page.post.title : ""
                textSize: Label.Large
                font.weight: Font.DemiBold
                font.family: Style.fontFor(text)
                color: Style.textPrimary
                wrapMode: Text.Wrap
            }

            OffChainBadge {
                anchors.horizontalCenter: parent.horizontalCenter
                onChain: page.post ? (page.post.postToBlockchain !== false) : true
            }

            Row {
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

            // Featured / cover image. Rectangle.clip only clips to the
            // bounding box (not rounded corners), so the Image is masked
            // against a rounded Rectangle instead, for a true rounded crop.
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

            // Body — parsed into text blocks and rounded images. Inset once
            // here (rather than per-item) so every block shares the same
            // left/right padding as the title and author row above.
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
                            // Wrap the TextArea in an Item sized to its full content
                            // height (like the image block does). The TextArea's own
                            // autoSize sets its height to the whole paragraph; without
                            // this wrapper the surrounding Loader/Column only sees a
                            // one-line implicit height and the internal Flickable clips
                            // the rest (you'd have to drag-select to scroll it in).
                            Item {
                                width: parent.width - Style.wrapSafeMargin
                                height: bodyTxt.height

                                // Read-only Lomiri TextArea: it wraps a TextEdit and
                                // ships the native long-press selection UI (blue drag
                                // handles + Copy/Select-All popover), just like the
                                // comment field. RichText renders the parsed <b>/<i>/<a>
                                // markup; native Copy puts plain text on the clipboard.
                                TextArea {
                                    id: bodyTxt
                                    width: parent.width
                                    text: model.content
                                    textFormat: TextEdit.RichText
                                    readOnly: true
                                    // autoSize + maximumLineCount<=0 is the intended
                                    // config for a TextArea living inside an outer
                                    // Flickable: it disables the internal scroll and
                                    // routes the OUTER flickable's movement into the
                                    // input handler's "scrolling" state, which cancels
                                    // the long-press timer so a scroll drag never turns
                                    // into a text selection. This is what makes scroll
                                    // vs. select behave natively, with no custom hacks.
                                    // (Lomiri InputHandler.qml: scrollingDisabled / scroller.)
                                    autoSize: true
                                    maximumLineCount: 0
                                    // autoSize measures height as lineCount×lineHeight,
                                    // which under-measures RichText (taller bold/heading
                                    // lines); with the internal flick disabled that would
                                    // clip the text. Grow to the true painted height.
                                    onPaintedHeightChanged: Qt.callLater(_fitHeight)
                                    onLineCountChanged: Qt.callLater(_fitHeight)
                                    Component.onCompleted: Qt.callLater(_fitHeight)
                                    function _fitHeight() { if (height < paintedHeight) height = paintedHeight; }
                                    // Focus-on-press is required: Lomiri's long-press
                                    // timer bails unless the field is already focused.
                                    // readOnly keeps the on-screen keyboard suppressed.
                                    activeFocusOnPress: true
                                    font.pixelSize: Style.fontMedium
                                    font.family: Style.fontFor(text)
                                    color: Style.textPrimary
                                    // Flat: strip the input frame/background and padding
                                    // so it reads as plain article body, not a text field.
                                    StyleHints {
                                        backgroundColor: "transparent"
                                        frameSpacing: 0
                                        overlaySpacing: 0
                                    }
                                    onLinkActivated: Qt.openUrlExternally(link)
                                    // Show the caret only while text is selected. The
                                    // caret gates the native Copy popover (openPopover()
                                    // bails if it's hidden), but keeping it always-on left
                                    // an idle blue cursor when just reading. Long-press
                                    // selects a word first, flipping this on in time for
                                    // the popover; tapping away clears the selection and
                                    // hides the caret again. The second handler re-asserts
                                    // it against the read-only editor's reset, but only
                                    // while a selection exists (so idle stays caret-free).
                                    onSelectedTextChanged: {
                                        // A genuine selection only happens while the page
                                        // is still. If one appears while the scroll is
                                        // moving/flicking (e.g. a finger pressed down to
                                        // catch a flick grabs a word, then momentum slides
                                        // the text under it and extends it), it's a stray —
                                        // clear it. Dragging the selection handles freezes
                                        // the scroller, so a real selection never trips this.
                                        if (selectedText.length > 0 && scroll.moving) {
                                            bodyTxt.deselect();
                                            return;
                                        }
                                        cursorVisible = (selectedText.length > 0);
                                    }
                                    onCursorVisibleChanged: if (!cursorVisible && selectedText.length > 0) cursorVisible = true
                                }

                                // A scroll drag can grab a word in the few pixels before
                                // the Flickable crosses its drag threshold and enters the
                                // native "scrolling" state. Clear any such stray selection
                                // once the page actually moves. This never fires during a
                                // real selection adjust, because dragging the handles puts
                                // the handler in "select" state, which freezes the scroller.
                                Connections {
                                    target: scroll
                                    onMovementStarted: bodyTxt.deselect()
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
        anchors { top: page.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: page.loading && page.post === null
        count: 1
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
        // Ride above the on-screen keyboard so the composer stays visible while
        // typing; the scroll above is anchored to footer.top and shrinks to suit.
        anchors.bottomMargin: page.kbHeight
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
        height: footerCol.height
        visible: page.post !== null
        color: Style.surface

    Column {
        id: footerCol
        width: parent.width
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
            onRequireLogin: page.pushLogin()

            // Apply cached vote state on every visibility change (footer
            // appears when page.post loads) and on init, so the count
            // always matches what the feed card shows.
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

            // Lomiri TextField (not a raw TextInput): only the styled component
            // wires up the native long-press selection + Cut/Copy/Paste popover.
            // StyleHints keep the existing gray-pill look.
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
