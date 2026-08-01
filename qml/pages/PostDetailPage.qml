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
import "../services/SummaryService.js" as SummaryService

Page {
    id: page

    property string author: ""
    property string permlink: ""
    property string title: ""

    // Adapt, not scale: caps the article to a centered column on wide windows
    readonly property real maxContentWidth: units.gu(100)

    // Passed in when opened from Saved Articles, so it renders instantly offline
    property var preloadedPost: null

    property var post: null
    property var comments: []
    property int commentCount: 0
    // Wide mode: right rail — related posts
    property var relatedPosts: []
    // Broadcast so the feed card behind this page reflects adds/deletes when the user goes back; feed pages patch the row by permlink.
    onCommentCountChanged: if (page.permlink) PostActions.commentCountChanged(page.permlink, page.commentCount)
    property bool loading: false
    property bool posting: false
    property string errorMsg: ""
    // When opened from a notification, scroll to this comment permlink after load.
    property string scrollToCommentPermlink: ""
    // On-screen-keyboard height; the docked comment composer rides above it.
    readonly property real kbHeight: Qt.inputMethod.visible ? Qt.inputMethod.keyboardRectangle.height : 0
    // Set while replying to a specific comment rather than the post itself; cleared after posting or via the composer's Cancel.
    property var replyTarget: null
    // Desktop-only "•••" dropdown in the header (see moreHeaderBtn).
    property bool headerMenuOpen: false
    // Keyboard nav within headerMenu: -1 = nothing highlighted yet.
    property int headerMenuIndex: -1

    // Flattened, keyboard-navigable rows for headerMenu, Block appended last.
    function headerMenuRows() {
        var items = page.headerMenuItems();
        if (!page.isOwnPost)
            items.push({ divider: true }, { icon: "", label: Lang.tr("Block %1").arg(page.author), danger: true, action: "block", custom: "block" });
        return items;
    }
    function headerMenuMove(delta) {
        var rows = page.headerMenuRows();
        var i = page.headerMenuIndex;
        for (var n = 0; n < rows.length; n++) {
            i = (i + delta + rows.length) % rows.length;
            if (!rows[i].divider) { page.headerMenuIndex = i; return; }
        }
    }
    function headerMenuActivate() {
        var rows = page.headerMenuRows();
        if (page.headerMenuIndex < 0 || page.headerMenuIndex >= rows.length) return;
        var row = rows[page.headerMenuIndex];
        page.headerMenuOpen = false;
        if (row.action === "block") PostActions.open(page.post, "blog", 3);
        else page.runHeaderMenuAction(row.action);
    }

    readonly property bool postReady: page.post !== null && (page.permlink || "").length > 0
    readonly property bool isSaved: (SavedPosts.rev, SavedPosts.isSaved(page.permlink))
    // Same URL shape the VoteBar's share button and the feed rows use.
    readonly property string shareUrl: (page.author.length > 0 && page.permlink.length > 0)
        ? ("https://serey.io/authors/" + page.author + "/" + page.permlink) : ""
    // The viewer owns this post, so offer Edit/Delete instead of moderation (you can't report or block yourself).
    readonly property bool isOwnPost: Session.isLoggedIn && page.author !== "" && page.author === Session.username

    function toggleSaved() {
        if (page.isSaved) SavedPosts.remove(page.permlink);
        else SavedPosts.save(page.post);
    }

    // Same as the sheet's Hide row, plus a pop: you're looking at the post you just hid.
    function hidePost() {
        HiddenPosts.hide(page.permlink);
        PostActions.hideRequested(page.author, page.permlink);
        page.pageStack.pop();
    }

    function openEditor() {
        var ed = page.pageStack.push(Qt.resolvedUrl("CreatePostPage.qml"), { editPost: page.post });
        if (ed && ed.saved) ed.saved.connect(page.load);
    }

    // Row data for the desktop "•••" dropdown (see moreHeaderBtn). Mirrors
    // PostActionSheet's main-menu rows; report/delete/block still route through
    // that sheet (opened at the matching step) since those need their own sub-flow.
    function headerMenuItems() {
        var items = [
            { icon: "stock_link", label: Lang.tr("Copy link"), action: "copyLink" },
            { icon: "external-link", label: Lang.tr("Open in browser"), action: "openBrowser" },
            { divider: true },
            { icon: page.isSaved ? "tick" : "save",
              label: page.isSaved ? Lang.tr("Remove from saved") : Lang.tr("Save for offline"),
              action: "toggleSaved" }
        ];
        if (page.isOwnPost) {
            items.push({ icon: "edit", label: Lang.tr("Edit post"), action: "edit" });
            items.push({ icon: "delete", label: Lang.tr("Delete post"), danger: true, action: "delete" });
        } else {
            items.push({ icon: "close", label: Lang.tr("Hide this post"), action: "hide" });
            items.push({ icon: "dialog-warning-symbolic", label: Lang.tr("Report post"), action: "report" });
        }
        return items;
    }

    function runHeaderMenuAction(action) {
        if (action === "copyLink") { Clipboard.push(page.shareUrl); Toast.show(Lang.tr("Link copied")); }
        else if (action === "openBrowser") Qt.openUrlExternally(page.shareUrl);
        else if (action === "toggleSaved") page.toggleSaved();
        else if (action === "edit") page.openEditor();
        else if (action === "delete") PostActions.open(page.post, "blog", 2);
        else if (action === "hide") page.hidePost();
        else if (action === "report") PostActions.open(page.post, "blog", 1);
    }

    // Delete and Block run in the sheet and only reach us as signals; either way this
    // page is left showing content that's gone, so unwind to the feed behind it.
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
        // Only the article column: the right rail gets its own header row (below).
        anchors { top: parent.top; left: parent.left; right: page.showSidePanel ? sidePanel.left : parent.right }
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
            anchors { left: backBtn.right; leftMargin: Style.spacingS; right: headerActions.left; rightMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
            text: page.postReady ? (page.post.title || (page.isVideoPost() ? Lang.tr("Video") : Lang.tr("Blog"))) : ""
            font.pixelSize: Style.fontLarge
            font.weight: Font.Light
            color: Style.textPrimary
            elide: Text.ElideRight
        }

        // A Row, not anchor-chained buttons: invisible ones drop out of the layout
        // instead of leaving a hole where they would have sat.
        Row {
            id: headerActions
            anchors { right: parent.right; rightMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
            spacing: Style.spacingXs

            // Tablet only: bookmark + open-in-browser are promoted out of the "..."
            // menu. Desktop keeps them in the menu, phone keeps the share button.
            AbstractButton {
                id: saveHeaderBtn
                visible: Config.tabletMode && page.postReady
                width: units.gu(4); height: units.gu(4)
                onClicked: page.toggleSaved()
                Icon {
                    anchors.centerIn: parent
                    width: units.gu(2.2); height: width
                    name: "bookmark"
                    color: page.isSaved ? Style.brand : Style.textPrimary
                }
            }

            AbstractButton {
                id: browserHeaderBtn
                visible: Config.tabletMode && page.shareUrl.length > 0
                width: units.gu(4); height: units.gu(4)
                onClicked: Qt.openUrlExternally(page.shareUrl)
                Icon { anchors.centerIn: parent; width: units.gu(2.2); height: width; name: "external-link"; color: Style.textPrimary }
            }

            AbstractButton {
                id: shareHeaderBtn
                visible: !Config.wideMode
                width: units.gu(4); height: units.gu(4)
                enabled: page.shareUrl.length > 0
                onClicked: Share.open(page.shareUrl, shareHeaderBtn)
                Icon { anchors.centerIn: parent; width: units.gu(2.2); height: width; name: "share"; color: Style.textPrimary }
            }

            AbstractButton {
                id: moreHeaderBtn
                width: units.gu(4); height: units.gu(4)
                enabled: page.postReady
                // Desktop: a compact anchored dropdown. Phone: the full-screen action sheet
                // (report reasons / delete-confirm need more room than a dropdown row gives).
                onClicked: Config.wideMode ? (page.headerMenuOpen = !page.headerMenuOpen) : PostActions.open(page.post, "blog")
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
        }

        // ----- Desktop dropdown menu (mirrors PostActionSheet's rows, minus the ones that need a sub-flow) -----
        // Keyboard: Down/Up move headerMenuIndex, Enter/Return activates, Escape closes.
        Rectangle {
            id: headerMenu
            visible: page.headerMenuOpen
            z: 20
            // headerActions, not moreHeaderBtn: the button now lives inside that Row,
            // and anchors only reach a parent or sibling. It's the last item, so the
            // Row's right edge is the button's right edge.
            anchors { top: headerActions.bottom; right: headerActions.right; topMargin: Style.spacingXs }
            width: units.gu(24)
            height: headerMenuCol.height
            radius: Style.cardRadius
            color: Style.surface
            border.width: units.dp(1)
            border.color: Style.divider

            activeFocusOnTab: true
            Keys.onEscapePressed: page.headerMenuOpen = false
            Keys.onDownPressed: page.headerMenuMove(1)
            Keys.onUpPressed: page.headerMenuMove(-1)
            Keys.onReturnPressed: page.headerMenuActivate()
            Keys.onEnterPressed: page.headerMenuActivate()
            onVisibleChanged: if (visible) { page.headerMenuIndex = -1; headerMenu.forceActiveFocus(); }

            Column {
                id: headerMenuCol
                width: parent.width

                Repeater {
                    // {divider:true} | {icon, label, danger, action, custom}
                    model: page.headerMenuRows()
                    delegate: Item {
                        width: headerMenuCol.width
                        height: modelData.divider ? units.dp(1) : units.gu(5.5)

                        Rectangle {
                            visible: !!modelData.divider
                            anchors.fill: parent
                            color: Style.divider
                        }

                        Rectangle {
                            visible: !modelData.divider && index === page.headerMenuIndex
                            anchors.fill: parent
                            color: Style.iconBackground
                        }

                        AbstractButton {
                            visible: !modelData.divider
                            anchors.fill: parent
                            onClicked: {
                                page.headerMenuOpen = false;
                                if (modelData.action === "block") PostActions.open(page.post, "blog", 3);
                                else page.runHeaderMenuAction(modelData.action);
                            }
                            Row {
                                anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                                spacing: Style.spacingM
                                // No "block" glyph in the Suru icon set (same reason PostActionSheet draws its own).
                                Icon {
                                    visible: modelData.custom !== "block"
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(2.2); height: width
                                    name: modelData.icon || ""
                                    color: modelData.danger ? Style.danger : Style.textPrimary
                                }
                                Item {
                                    visible: modelData.custom === "block"
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(2.2); height: width
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: width / 2
                                        color: "transparent"
                                        border.width: units.dp(1.5)
                                        border.color: Style.danger
                                    }
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width * 0.7; height: units.dp(1.5)
                                        color: Style.danger
                                        rotation: 45
                                    }
                                }
                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.label || ""
                                    font.pixelSize: Style.fontSmall
                                    color: modelData.danger ? Style.danger : Style.textPrimary
                                }
                            }
                        }
                    }
                }
            }
        }

    }

    // Dismiss the header dropdown on an outside click. A page-level sibling (not
    // nested in postDetailHeader) so it catches clicks anywhere, not just the header;
    // z above the scroll/panel content but below postDetailHeader and the menu itself.
    MouseArea {
        visible: page.headerMenuOpen
        z: 9
        anchors.fill: parent
        onClicked: page.headerMenuOpen = false
    }

    // Single divider under both header rows (article + right rail), spanning the
    // full page width, so the two headers' own borders never show as a mismatched
    // double line at the seam between them. z above the scroll/panel content
    // declared later, so their backgrounds don't paint over this line. Article
    // column only — the right rail has no divider below its own "Related" row.
    Rectangle {
        z: 9
        anchors {
            top: parent.top
            topMargin: postDetailHeader.height
            left: parent.left
            right: page.showSidePanel ? sidePanel.left : parent.right
        }
        height: units.dp(1)
        color: Style.divider
    }

    function maincategory() {
        if (page.post && page.post.categories && page.post.categories.length > 0)
            return page.post.categories[0];
        return "serey";
    }

    // A post is a video if its (primary) category says so; same rule FeedPage uses to route to VideoDetailPage.
    function isVideoPost() {
        var p = page.post;
        if (!p) return false;
        if (p.primaryCategory === "video") return true;
        var c = p.categories;
        return !!(c && c.indexOf && c.indexOf("video") >= 0);
    }

    // AI TL;DR. Server-cached per article, so this is one cheap call per open;
    // a failure just leaves the box hidden.
    property var summaryBullets: []
    property int summaryMinutes: 0
    property bool summaryLoading: false

    // Reading time is just a word count, so compute it locally and show the bar
    // immediately; the AI bullets fill in behind it. 200 wpm, same as the server.
    function _localReadMinutes(html) {
        var text = String(html || "").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
        if (text === "") return 0;
        return Math.max(1, Math.round(text.split(" ").length / 200));
    }

    function _loadSummary() {
        if (!page.post || !page.post.body) return;
        page.summaryMinutes = page._localReadMinutes(page.post.body);
        page.summaryLoading = true;
        SummaryService.summarize(Config.baseUrl, page.post, Session.token,
            function (res) {
                // Generation can take seconds; the reader may have closed the page by now.
                if (!page) return;
                page.summaryLoading = false;
                page.summaryBullets = res.bullets;
                page.summaryMinutes = res.readMinutes;
            },
            function () {
                // No summary is a non-event: the reading-time bar still stands.
                if (!page) return;
                page.summaryLoading = false;
                page.summaryBullets = [];
            });
    }

    // Right rail — other posts in the same category, current post excluded.
    function loadRelated() {
        if (!page.post) return;
        var cat = page.maincategory();
        var p = { limit: 20, offset: 0 };
        if (page.post.communityId > 0) p.community_id = page.post.communityId;
        else p.exclude_home = 1;
        PostService.listTrending(Config.baseUrl, p, Session.token,
            function (posts) {
                var out = [];
                for (var i = 0; i < posts.length && out.length < 3; i++) {
                    if (posts[i].permlink === page.permlink) continue;
                    if (posts[i].primaryCategory !== cat) continue;
                    out.push(posts[i]);
                }
                page.relatedPosts = out;
            },
            function (err) { /* right rail stays empty */ });
    }

    function load() {
        page.loading = true;
        page.errorMsg = "";
        PostService.detail(Config.baseUrl, author, permlink, Session.token,
            function (result) {
                if (!page) return;   // page closed while the fetch was in flight
                page.loading = false;
                page.post = result.post;
                page.comments = result.replies || [];
                page.commentCount = page._countAll(page.comments);
                page._parseBody();
                page._loadSummary();
                page.loadRelated();
                // Deep-link from a comment/reply notification: scroll to the target once the comment rows have laid out.
                if (page.scrollToCommentPermlink !== "") scrollToTimer.start();

                // Sync vote bar: cache wins over API data since the feed may have recorded a vote the detail endpoint hasn't caught up with.
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
                // Reload so the optimistic comment gets its real server permlink, otherwise replying to it would fail (parent_permlink required).
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

        // Custom editor containers carry the real src in data-image-url; replace the entire parent tag with a plain <img> so the splitter catches them.
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
                // The blocks render as RichText, which collapses literal "\n" to a space; block boundaries become <br/> tags, and a paragraph gap is a double break.
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
                // Decode numeric entities (smart quotes etc.) that the rich-text renderer can't render, but leave &,<,> encoded so they aren't mistaken for markup.
                text = text.replace(/&#(\d+);/g, function (mm, n) {
                    var code = parseInt(n, 10);
                    return (code === 38 || code === 60 || code === 62) ? mm : String.fromCharCode(code);
                });
                text = text.replace(/&#x([0-9a-fA-F]+);/gi, function (mm, n) {
                    var code = parseInt(n, 16);
                    return (code === 38 || code === 60 || code === 62) ? mm : String.fromCharCode(code);
                });
                // Collapse runs of breaks and trim leading/trailing ones so blocks don't start or end with blank lines.
                text = text.replace(/(?:<br\/>\s*){3,}/gi, "<br/><br/>");
                text = text.replace(/^(?:\s|<br\/>)+/i, "");
                text = text.replace(/(?:\s|<br\/>)+$/i, "");
                // Lomiri TextArea has no linkAt(), so capture each anchor's href and the
                // exact visible text it renders. The delegate hit-tests a tap position
                // (positionAt) against these spans in the displayed plain text to open links.
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

    // Keyboard: Right from the article steps into the side panel (see scroll's
    // Keys.onPressed); the panel's own Flickable handles scrolling from there,
    // with Left/Escape stepping back out to the article. Down/Up walk a single
    // ordered chain: related posts, then upvote, then downvote, then the comment
    // composer — mirroring the panel's own visual top-to-bottom order.
    function focusSidePanel() {
        if (!page.showSidePanel) return;
        sidePanelFlick.forceActiveFocus();
        page.sidePanelIndex = 0;
    }

    // Highlighted item while the panel owns arrow-key focus; -1 = none (composer has focus instead).
    property int sidePanelIndex: -1
    readonly property int _voteUpIdx: page.relatedPosts.length
    readonly property int _voteDownIdx: page.relatedPosts.length + 1
    readonly property int _sidePanelItemCount: page.relatedPosts.length + 2

    function openRelated(post, byKeyboard) {
        page.pageStack.push(Qt.resolvedUrl("PostDetailPage.qml"),
                            { author: post.author, permlink: post.permlink,
                              focusOnOpen: byKeyboard === true });
    }
    function sidePanelActivate() {
        if (page.sidePanelIndex < 0) return;
        if (page.sidePanelIndex < page.relatedPosts.length) page.openRelated(page.relatedPosts[page.sidePanelIndex], true);
        else if (page.sidePanelIndex === page._voteUpIdx) detailVoteBar.doUpvote();
        else if (page.sidePanelIndex === page._voteDownIdx) detailVoteBar.doFlag();
    }
    // Down past the last item (downvote) hands off to the comment composer for typing.
    function sidePanelFocusComposer() {
        page.sidePanelIndex = -1;
        composer.forceActiveFocus();
    }

    // Scroll to a specific comment after the layout settles post-load (deep-link from a notification).
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

    // The scroll view owns arrow-key focus so a keyboard user can scroll the article;
    // AdaptiveStack.focusDetail() targets this when entering from the list.
    property Item keyboardFocusItem: scroll

    // A push from inside the detail column skips AdaptiveStack.focusDetail(), so a
    // keyboard-opened related post would land unfocused. Waits for postReady since
    // `scroll` is hidden until then and focusing a hidden item does nothing.
    property bool focusOnOpen: false
    onPostReadyChanged: if (postReady && page.focusOnOpen) {
        page.focusOnOpen = false;
        Qt.callLater(function () { if (scroll.visible) scroll.forceActiveFocus(); });
    }

    // Right rail: related posts, vote bar and comments — wide mode only.
    // Desktop only: tablet has room for list + article, not a third column.
    readonly property bool showSidePanel: Config.desktopMode && page.postReady

    // Resizable via the drag handle below; clamped so the article column always keeps a sane minimum width.
    property real sidePanelWidth: units.gu(34)
    readonly property real _minSidePanelW: units.gu(26)
    readonly property real _maxSidePanelW: Math.max(_minSidePanelW, Math.min(page.width * 0.5, page.width - units.gu(40)))
    readonly property real _sidePanelW: Math.max(_minSidePanelW, Math.min(_maxSidePanelW, sidePanelWidth))

    KeyboardAwareFlickable {
        id: scroll
        anchors {
            top: postDetailHeader.bottom
            left: parent.left
            right: page.showSidePanel ? sidePanel.left : parent.right
            bottom: parent.bottom
        }
        anchors.bottomMargin: footer.visible ? footer.height + page.kbHeight : 0
        // Animate in step with the footer's own bottomMargin so the list and the docked composer move together when the keyboard shows/hides.
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
        contentWidth: width
        contentHeight: contentCol.height
        clip: true
        visible: page.post !== null
        // Dismiss the keyboard on scroll only when the docked composer is the focused input, so editing a comment inline isn't interrupted.
        onMovementStarted: if (composer.activeFocus) Qt.inputMethod.hide()
        opacity: 0
        NumberAnimation on opacity { from: 0; to: 1; duration: 250; easing.type: Easing.OutQuad }

        // Keyboard reading: a plain Flickable ignores keys, so scroll keys are handled
        // here. Focus lands on the flick when the article opens (never stealing it from
        // the comment box); tapping the body TextArea still takes focus for selection.
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
            // Hand focus back to the master list (the sidebar) so the reader can pick the next post.
            else if (event.key === Qt.Key_Left || event.key === Qt.Key_Escape) { Nav.focusMaster(); event.accepted = true; }
            // Right steps into the side panel (related/votes/comments), mirroring
            // the rail's own Right-steps-into-content convention.
            else if (event.key === Qt.Key_Right && page.showSidePanel) { page.focusSidePanel(); event.accepted = true; }
        }
        // No auto-focus-on-load here: that used to steal focus (and show the
        // keyboard focus border) even for mouse opens. Keyboard entry already
        // focuses scroll explicitly via keyboardFocusItem (AdaptiveStack.focusDetail()).

        Column {
            id: contentCol
            width: Math.min(scroll.width, page.maxContentWidth)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.spacingM

            Item { width: 1; height: Style.spacingS }

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
                // Sub-categories (everything after the main tag), rendered as a suffix.
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

            ArticleSummary {
                width: parent.width - Style.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                bullets: page.summaryBullets
                readMinutes: page.summaryMinutes
                loading: page.summaryLoading
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

            // Featured/cover image: Rectangle.clip only clips to the bounding box, so the Image is masked against a rounded Rectangle for a true rounded crop.
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

            // Body is parsed into text blocks and rounded images; inset once here so every block shares the same left/right padding as the title/author row.
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
                            // Wrapped in an Item sized to full content height, else the surrounding Loader/Column only sees a one-line implicit height and clips the rest.
                            Item {
                                width: parent.width - Style.wrapSafeMargin
                                height: bodyTxt.height

                                // Lomiri TextArea (not plain Text) for the native long-press selection UI (drag handles + Copy popover).
                                TextArea {
                                    id: bodyTxt
                                    width: parent.width
                                    // Stray-selection guard: a scrolling press doesn't cancel TextEdit's
                                    // press-and-hold word-select timer, so it can fire well after motion stops.
                                    // Flag "scrolled since focus" and clear any selection that appears meanwhile.
                                    property real _lastScrollMs: 0
                                    property bool _scrolledSinceFocus: false
                                    readonly property int _scrollSelGuardMs: 1500
                                    text: model.content
                                    textFormat: TextEdit.RichText
                                    readOnly: true
                                    // autoSize + maximumLineCount<=0 disables the TextArea's internal scroll so the outer Flickable's scroll can cancel the long-press timer natively.
                                    autoSize: true
                                    maximumLineCount: 0
                                    // autoSize under-measures RichText (taller bold/heading lines); grow to the true painted height.
                                    onPaintedHeightChanged: Qt.callLater(_fitHeight)
                                    onLineCountChanged: Qt.callLater(_fitHeight)
                                    Component.onCompleted: Qt.callLater(_fitHeight)
                                    function _fitHeight() { if (height < paintedHeight) height = paintedHeight; }
                                    // Long-press selection requires the field to already be focused
                                    activeFocusOnPress: true
                                    // Once focused, the read-only cursor would swallow the reading keys;
                                    // chain them to the flick (arrows/Page/Space/Left/Escape) while copy
                                    // and select-all fall through untouched.
                                    Keys.forwardTo: [scroll]
                                    font.pixelSize: Config.wideMode ? Style.fontMedium * 1.2 : Style.fontMedium
                                    font.family: Style.fontFor(text)
                                    color: Style.textPrimary
                                    // Flat look, not a text field
                                    StyleHints {
                                        backgroundColor: "transparent"
                                        frameSpacing: 0
                                        overlaySpacing: 0
                                    }
                                    onLinkActivated: Qt.openUrlExternally(link)
                                    // A fresh press (focus gained) starts a new gesture; reset the flag so a
                                    // deliberate long-press with no scroll is never blocked.
                                    onActiveFocusChanged: if (activeFocus) bodyTxt._scrolledSinceFocus = false
                                    // Caret visible only while selected, gating the native Copy popover; always-on left an idle blue cursor while reading.
                                    onSelectedTextChanged: {
                                        // Stray if the scroller is in motion, or a scroll happened during this
                                        // press and is still recent (the late press-and-hold timer). A
                                        // deliberate long-press is never cleared.
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

                                // Track scroll activity so the selection guard above can distinguish a stray
                                // (scroll happened during this press) from a deliberate long-press.
                                Connections {
                                    target: scroll
                                    onMovementStarted: { bodyTxt._scrolledSinceFocus = true; bodyTxt._lastScrollMs = Date.now(); bodyTxt.deselect() }
                                    onMovementEnded:   bodyTxt._lastScrollMs = Date.now()
                                    onFlickStarted:    { bodyTxt._scrolledSinceFocus = true; bodyTxt._lastScrollMs = Date.now() }
                                    onFlickEnded:      bodyTxt._lastScrollMs = Date.now()
                                    onDraggingChanged: { if (scroll.dragging) bodyTxt._scrolledSinceFocus = true; bodyTxt._lastScrollMs = Date.now() }
                                }

                                // Tap-to-open links: Lomiri TextArea has no linkAt() and onLinkActivated is
                                // unreliable inside a Flickable, so hit-test the tap (positionAt) against the
                                // block's link spans. A non-link press falls through so scrolling still works.
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
                                        // Only grab the press when it's on a link; otherwise let the TextArea/
                                        // Flickable underneath handle selection and scrolling.
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

            // Narrow mode only: the right rail (below) owns these in wide mode.
            Column {
                id: commentsColumn
                parent: page.showSidePanel ? sidePanelCol : contentCol
                width: page.showSidePanel ? parent.width : parent.width - Style.spacingM * 2
                anchors.horizontalCenter: page.showSidePanel ? undefined : parent.horizontalCenter
                spacing: Style.spacingS

                Label {
                    width: parent.width
                    text: Lang.tr("COMMENTS (%1)").arg(page.commentCount)
                    font.pixelSize: Style.fontSmall
                    font.weight: Font.Bold
                    color: Style.textSecondary
                }

                Label {
                    width: parent.width
                    visible: page.comments.length === 0
                    text: Lang.tr("No comments yet. Be the first!")
                    textSize: Label.Small
                    color: Style.textSecondary
                }

                Repeater {
                    id: commentsRepeater
                    model: page.comments
                    delegate: CommentItem {
                        width: commentsColumn.width
                        comment: modelData
                        onDeleted: page.removeComment(permlink)
                        onEdited: page.editComment(permlink, newBody, parentAuthor, parentPermlink)
                        onReplyRequested: page.startReply(comment)
                        onAuthorClicked: page.openProfile(author)
                    }
                }
            }

            Item { width: 1; height: Style.spacingM }
        }

    }

    // Draggable splitter: resizes sidePanel by dragging its left edge. Runs the
    // full page height so it lines up with the panel's own header row, not just
    // the article's — the two headers sit side by side, not one above the other.
    // The ONLY vertical divider between the two columns (z above postDetailHeader's
    // z:10, so it stays a single unbroken line instead of getting hidden behind it
    // for the header's height and needing a second, differently-sized patch there).
    Rectangle {
        id: sidePanelDivider
        z: 11
        anchors { top: parent.top; bottom: parent.bottom; right: sidePanel.left }
        width: units.dp(2)
        visible: page.showSidePanel
        color: sidePanelDragArea.containsMouse || sidePanelDragArea.pressed ? Style.brand : Style.divider
    }
    MouseArea {
        id: sidePanelDragArea
        visible: page.showSidePanel
        anchors { top: parent.top; bottom: parent.bottom }
        x: sidePanel.x - width / 2
        width: units.gu(1.5)
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.SplitHCursor
        onPositionChanged: {
            if (!pressed) return;
            var pagePointX = mapToItem(page, mouse.x, 0).x;
            page.sidePanelWidth = Math.max(page._minSidePanelW, Math.min(page._maxSidePanelW, page.width - pagePointX));
        }
    }

    // --- Right rail (wide mode): related posts, vote bar, comments, composer ---------
    // Starts at the page's own top (not below the article's header), with its own
    // header row, so it reads as its own column rather than sitting under the blog header.
    Rectangle {
        id: sidePanel
        anchors { top: parent.top; right: parent.right; bottom: parent.bottom }
        width: page.showSidePanel ? page._sidePanelW : 0
        visible: page.showSidePanel
        clip: true
        color: Style.surface

        // No border drawn here — sidePanelDivider (a page-level sibling, sitting
        // just outside sidePanel's own left edge) is the single vertical line for
        // the whole height; a second one here would double up or drift out of sync.

        Rectangle {
            id: sidePanelHeader
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: postDetailHeader.height
            color: Style.surface

            Label {
                anchors { left: parent.left; leftMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                text: Lang.tr("Related")
                font.pixelSize: Style.fontSmall
                font.weight: Font.Bold
                color: Style.textSecondary
            }
        }

        Flickable {
            id: sidePanelFlick
            anchors { top: sidePanelHeader.bottom; left: parent.left; right: parent.right; bottom: sideComposerBar.top }
            contentWidth: width
            contentHeight: sidePanelCol.height + Style.spacingM * 2
            clip: true

            // Same keyboard-scroll contract as the article's own scroll view;
            // Left/Escape steps back out to the article instead of the master list.
            activeFocusOnTab: true
            function _kbScroll(dy) {
                var maxY = Math.max(0, sidePanelFlick.contentHeight - sidePanelFlick.height);
                sidePanelFlick.contentY = Math.max(0, Math.min(maxY, sidePanelFlick.contentY + dy));
            }
            // Scrolls the highlighted item (related-post row or the vote bar) into view.
            function _revealSelected() {
                var it = page.sidePanelIndex < page.relatedPosts.length
                    ? relatedRepeater.itemAt(page.sidePanelIndex) : detailVoteBar;
                if (!it) return;
                var top = it.mapToItem(sidePanelFlick.contentItem, 0, 0).y;
                var bottom = top + it.height;
                if (bottom > sidePanelFlick.contentY + sidePanelFlick.height)
                    sidePanelFlick.contentY = bottom - sidePanelFlick.height;
                else if (top < sidePanelFlick.contentY)
                    sidePanelFlick.contentY = top;
            }
            Keys.onPressed: {
                var pageStep = sidePanelFlick.height * 0.9;
                if (event.key === Qt.Key_Down) {
                    if (page.sidePanelIndex < page._sidePanelItemCount - 1) {
                        page.sidePanelIndex = page.sidePanelIndex + 1;
                        sidePanelFlick._revealSelected();
                    } else {
                        page.sidePanelFocusComposer();
                    }
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up && page.sidePanelIndex > 0) {
                    page.sidePanelIndex = page.sidePanelIndex - 1;
                    sidePanelFlick._revealSelected(); event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    page.sidePanelActivate(); event.accepted = true;
                } else if (event.key === Qt.Key_PageDown) { sidePanelFlick._kbScroll(pageStep);  event.accepted = true; }
                else if (event.key === Qt.Key_PageUp)   { sidePanelFlick._kbScroll(-pageStep); event.accepted = true; }
                else if (event.key === Qt.Key_Home)     { sidePanelFlick.contentY = 0; event.accepted = true; }
                else if (event.key === Qt.Key_End)      { sidePanelFlick._kbScroll(sidePanelFlick.contentHeight); event.accepted = true; }
                else if (event.key === Qt.Key_Left || event.key === Qt.Key_Escape) { page.sidePanelIndex = -1; scroll.forceActiveFocus(); event.accepted = true; }
            }

            Column {
                id: sidePanelCol
                // "Related" now lives in the header row itself, level with the article's header.
                x: Style.spacingM
                y: Style.spacingM
                width: parent.width - Style.spacingM * 2
                spacing: Style.spacingM

                Repeater {
                    id: relatedRepeater
                    model: page.relatedPosts
                    delegate: AbstractButton {
                        id: relatedBtn
                        width: sidePanelCol.width
                        height: units.gu(7)
                        onClicked: page.openRelated(modelData)

                        Rectangle {
                            anchors.fill: parent
                            radius: Style.cardRadius
                            color: (index === page.sidePanelIndex || relatedHover.containsMouse) ? Style.iconBackground : "transparent"
                            border.width: index === page.sidePanelIndex ? units.dp(2) : 0
                            border.color: Style.brand
                        }
                        MouseArea {
                            id: relatedHover
                            anchors.fill: parent
                            hoverEnabled: true
                            propagateComposedEvents: true
                            onClicked: (mouse) => { mouse.accepted = false; }
                        }

                        Row {
                            anchors.fill: parent
                            anchors.margins: units.dp(4)
                            spacing: Style.spacingS

                            Item {
                                anchors.verticalCenter: parent.verticalCenter
                                width: units.gu(6.5); height: units.gu(6.5)
                                Rectangle { anchors.fill: parent; radius: Style.thumbRadius; color: Style.iconBackground }
                                Image {
                                    id: relatedThumbImg
                                    anchors.fill: parent
                                    source: modelData.thumbnail || ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    visible: false
                                }
                                Rectangle {
                                    id: relatedThumbMask
                                    anchors.fill: parent
                                    radius: Style.thumbRadius
                                    visible: false
                                }
                                OpacityMask {
                                    anchors.fill: parent
                                    source: relatedThumbImg
                                    maskSource: relatedThumbMask
                                    visible: (modelData.thumbnail || "") !== ""
                                }
                            }
                            Label {
                                width: parent.width - units.gu(6.5) - Style.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.title || ""
                                font.pixelSize: Style.fontSmall
                                font.weight: Font.DemiBold
                                font.family: Style.fontFor(text)
                                color: Style.textPrimary
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                // Native home for the vote bar: sits above comments whenever the panel is shown.
                VoteBar {
                    id: detailVoteBar
                    parent: page.showSidePanel ? sidePanelCol : footerCol
                    width: page.showSidePanel ? parent.width : parent.width - Style.spacingM * 2
                    anchors.horizontalCenter: page.showSidePanel ? undefined : parent.horizontalCenter
                    author: page.author
                    permlink: page.permlink
                    voteType: "post"
                    onChain: page.post ? (page.post.postToBlockchain !== false) : true
                    showComments: false
                    showVotersLabel: false
                    showShare: false   // Share now lives in the header action bar, not duplicated here
                    compact: page.showSidePanel
                    onRequireLogin: page.pushLogin()
                    keyboardHighlight: page.sidePanelIndex === page._voteUpIdx ? 0
                        : page.sidePanelIndex === page._voteDownIdx ? 1 : -1

                    // Apply cached vote state on every visibility change and on init, so the count always matches what the feed card shows.
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

                Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }
            }
        }

        // A mouse click anywhere in the panel grabs keyboard focus for it too, so
        // arrow-key scrolling keeps working after a mouse interaction; passes the
        // press through unaccepted so related-post/vote buttons underneath still fire.
        MouseArea {
            anchors.fill: sidePanelFlick
            propagateComposedEvents: true
            onPressed: { sidePanelFlick.forceActiveFocus(); mouse.accepted = false; }
        }

        // Sticky comment composer, pinned to the bottom of the panel.
        Rectangle {
            id: sideComposerBar
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            anchors.bottomMargin: page.kbHeight
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
            height: composerArea.height + Style.spacingS * 2
            color: Style.surface

            Rectangle {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: units.dp(1)
                color: Style.divider
            }

            // Continues the panel's own left border past this bar, which would
            // otherwise paint over it with its opaque background.
            Rectangle {
                visible: page.showSidePanel
                anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                width: units.dp(1)
                color: Style.divider
            }

            Column {
                id: composerArea
                parent: page.showSidePanel ? sideComposerBar : footerCol
                x: page.showSidePanel ? Style.spacingS : 0
                y: page.showSidePanel ? Style.spacingS : 0
                width: page.showSidePanel ? parent.width - Style.spacingS * 2 : parent.width - Style.spacingM * 2
                anchors.horizontalCenter: page.showSidePanel ? undefined : parent.horizontalCenter
                spacing: units.dp(4)

                Row {
                    visible: page.replyTarget !== null
                    width: parent.width
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

                // Comment composer: a plain Rectangle behind a borderless TextField,
                // with the send button riding inside its right edge.
                Item {
                    width: parent.width
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
                        anchors { left: parent.left; leftMargin: Style.spacingM; right: sendButton.left; rightMargin: Style.spacingXs; verticalCenter: parent.verticalCenter }
                        height: parent.height - units.dp(2)
                        StyleHints {
                            backgroundColor: "transparent"
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
                        // Up steps back to the downvote button; Escape returns to the article.
                        Keys.onUpPressed: {
                            if (page.showSidePanel) {
                                page.sidePanelIndex = page._voteDownIdx;
                                sidePanelFlick.forceActiveFocus();
                                sidePanelFlick._revealSelected();
                            }
                        }
                        Keys.onEscapePressed: { page.sidePanelIndex = -1; scroll.forceActiveFocus(); }
                    }

                    AbstractButton {
                        id: sendButton
                        anchors { right: parent.right; rightMargin: units.dp(3); verticalCenter: parent.verticalCenter }
                        width: units.gu(3.8); height: width
                        enabled: !page.posting && composer.text.trim().length > 0
                        onClicked: page.submitComment()

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: sendButton.enabled ? Style.brand : "transparent"
                        }
                        Icon {
                            anchors.centerIn: parent
                            width: units.gu(2.2); height: width
                            name: "send"
                            color: sendButton.enabled ? Style.textOnBrand : Style.textSecondary
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.fill: scroll
        visible: scroll.activeFocus
        color: "transparent"
        border.width: units.dp(2)
        border.color: Style.brand
        // Above sidePanelDivider's z:11, else the divider paints over this border's right edge.
        z: 12
    }
    Rectangle {
        anchors.fill: sidePanelFlick
        visible: page.showSidePanel && sidePanelFlick.activeFocus
        color: "transparent"
        border.width: units.dp(2)
        border.color: Style.brand
        z: 12
    }

    LoadingState {
        anchors {
            top: postDetailHeader.bottom
            left: parent.left
            right: page.showSidePanel ? sidePanel.left : parent.right
            bottom: parent.bottom
        }
        visible: page.loading && page.post === null
        count: 1
    }
    ErrorState {
        anchors {
            top: postDetailHeader.bottom
            left: parent.left
            right: page.showSidePanel ? sidePanel.left : parent.right
            bottom: parent.bottom
        }
        visible: page.errorMsg !== "" && page.post === null
        message: page.errorMsg
        onRetry: page.load()
    }

    Rectangle {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        // Ride above the on-screen keyboard so the composer stays visible while typing; the scroll above is anchored to footer.top and shrinks to suit.
        anchors.bottomMargin: page.kbHeight
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
        height: footerCol.height
        // Wide mode: the vote bar and composer live in the right rail instead.
        visible: page.post !== null && !page.showSidePanel
        color: Style.surface

    Column {
        id: footerCol
        width: Math.min(parent.width, page.maxContentWidth)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: units.dp(4)

        Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

        // composerArea (reply banner + pill composer) reparents in here; declared under sidePanel.
    }
    }
}
