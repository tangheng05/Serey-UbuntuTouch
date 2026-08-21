import QtQuick 2.7
import QtQuick.Window 2.2
import QtGraphicalEffects 1.0
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/PostService.js" as PostService
import "../services/CommentService.js" as CommentService
import "../services/VoteService.js" as VoteService
import "../services/HiddenPosts.js" as HiddenPosts
import "../services/BlockedUsers.js" as BlockedUsers
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
    // Hides votes/SEREY value/comments, skips live fetch
    property bool offlineMode: false

    property var post: null
    property var comments: []
    property int commentCount: 0
    // Wide mode: right rail — related posts
    property var relatedPosts: []
    property bool relatedLoading: false
    // Feed row from the pushing page: lets related start before the article request returns
    property var seedPost: null
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
    // Set while editing one of your own comments: the same composer, in edit mode.
    property var editTarget: null
    // Desktop-only "•••" dropdown in the header (see moreHeaderBtn).
    property bool headerMenuOpen: false
    // Keyboard nav within headerMenu: -1 = nothing highlighted yet.
    property int headerMenuIndex: -1

    // Flattened, keyboard-navigable rows for headerMenu, Block appended last.
    // No divider: Block belongs with Hide/Report in the negative group.
    function headerMenuRows() {
        var items = page.headerMenuItems();
        if (!page.isOwnPost)
            items.push({ icon: "", label: Lang.tr("Block %1").arg(page.author), danger: true, action: "block", custom: "block" });
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

    // Desktop "•••" dropdown rows; report/delete/block route through PostActionSheet
    function headerMenuItems() {
        // Tablet: already in header row
        var items = [
            { icon: "stock_link", label: Lang.tr("Copy link"), action: "copyLink" }
        ];
        if (!Config.tabletMode) {
            items.push({ icon: "external-link", label: Lang.tr("Open in browser"), action: "openBrowser" });
            items.push({ icon: page.isSaved ? "tick" : "save",
              label: page.isSaved ? Lang.tr("Remove from saved") : Lang.tr("Save for offline"),
              action: "toggleSaved" });
        }
        // Same split as the video menu: content actions above, negative below.
        items.push({ divider: true });
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

    // Delete/Block reach us only as signals; content is gone, so pop back to feed
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
        // Only the article column: the right rail (or, while loading, the space held
        // for it) gets its own header row.
        anchors {
            top: parent.top; left: parent.left
            right: page.showSidePanel ? sidePanel.left : parent.right
            rightMargin: page._pendingRailW
        }
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

        // Row, not anchors: invisible buttons drop out instead of leaving a hole
        Row {
            id: headerActions
            anchors { right: parent.right; rightMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
            spacing: Style.spacingXs

            // Tablet only: save-offline + open-in-browser promoted out of the "..." menu
            AbstractButton {
                id: saveHeaderBtn
                visible: Config.tabletMode && page.postReady
                width: units.gu(4); height: units.gu(4)
                onClicked: page.toggleSaved()
                Icon {
                    anchors.centerIn: parent
                    width: units.gu(2.2); height: width
                    // Same save/tick pair the "..." menu and action sheet use; a
                    // bookmark glyph here read as a different action than the row below it.
                    name: page.isSaved ? "tick" : "save"
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
                visible: !Config.wideMode || Config.tabletMode
                width: units.gu(4); height: units.gu(4)
                enabled: page.shareUrl.length > 0
                onClicked: Share.open(page.shareUrl, shareHeaderBtn)
                Icon { anchors.centerIn: parent; width: units.gu(2.2); height: width; name: "share"; color: Style.textPrimary }
            }

            AbstractButton {
                id: moreHeaderBtn
                width: units.gu(4); height: units.gu(4)
                enabled: page.postReady
                // Desktop: anchored dropdown. Phone: full-screen sheet (needs more room)
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

        // Desktop dropdown menu (mirrors PostActionSheet's rows); arrow keys move, Enter activates, Escape closes
        Rectangle {
            id: headerMenu
            visible: page.headerMenuOpen
            z: 20
            // Anchored to headerActions (last item's edge = Row's right edge)
            anchors { top: headerActions.bottom; right: headerActions.right; topMargin: Style.spacingXs }
            // gu(24) fit the English labels only; translations run longer.
            width: units.gu(30)
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
                                    // Bounded + elided so no translation can spill past the panel.
                                    width: Math.max(0, parent.width - units.gu(2.2) - parent.spacing)
                                    elide: Text.ElideRight
                                    text: modelData.label || ""
                                    font.pixelSize: Style.fontSmall
                                    font.family: Style.fontFor(text)   // labels carry usernames
                                    color: modelData.danger ? Style.danger : Style.textPrimary
                                }
                            }
                        }
                    }
                }
            }
        }

    }

    // Dismiss header dropdown on outside click; page-level so it catches clicks anywhere
    MouseArea {
        visible: page.headerMenuOpen
        z: 9
        anchors.fill: parent
        onClicked: page.headerMenuOpen = false
    }

    // Single divider under both header rows, avoids a mismatched double line at the seam
    Rectangle {
        z: 9
        anchors {
            top: parent.top
            topMargin: postDetailHeader.height
            left: parent.left
            right: page.showSidePanel ? sidePanel.left : parent.right
            rightMargin: page._pendingRailW
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

    // AI TL;DR, server-cached per article; failure just leaves the box hidden
    property var summaryBullets: []
    property int summaryMinutes: 0
    property bool summaryLoading: false
    // A failed call and a post with no summary both end at zero bullets; the drawer
    // needs to tell them apart, so keep the reason instead of dropping the error.
    property string summaryError: ""
    property bool summaryRequested: false

    // Very short articles get no summary bar at all: it promises a one-minute read of
    // something already shorter than that, and generating one spends a request from a
    // budget shared by every reader. 120 words is about 35 seconds at the 200 wpm below;
    // above that a summary earns its keep, below it the post is a couple of sentences.
    readonly property int _summaryMinWords: 120
    property bool summarySkipped: false

    function _wordCount(html) {
        var text = String(html || "").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
        return text === "" ? 0 : text.split(" ").length;
    }

    // Local word-count estimate shown immediately; AI bullets fill in behind it (200 wpm)
    function _localReadMinutes(html) {
        var words = page._wordCount(html);
        return words === 0 ? 0 : Math.max(1, Math.round(words / 200));
    }

    // Read time is a local word count, so the bar stands on its own; only the
    // bullets need the server.
    function _initSummary() {
        page.summaryBullets = [];
        page.summaryError = "";
        page.summaryLoading = false;
        page.summaryRequested = false;
        page.summarySkipped = !page.post || page._wordCount(page.post.body) < page._summaryMinWords;
        // Zero minutes is what hides the bar, so a skipped article shows nothing at all.
        page.summaryMinutes = page.summarySkipped ? 0 : page._localReadMinutes(page.post.body);
        page._prefetchSummary();
    }

    // Opening the article asks for a summary that already exists (cache_only never
    // reaches the AI service, and rides its own rate limit). Expanding the drawer
    // then costs nothing for every article that has been summarized before.
    function _prefetchSummary() {
        if (page.summarySkipped) return;
        if (!page.post || !page.post.author || !page.post.permlink) return;
        var permlink = page.post.permlink;
        SummaryService.summarize(Config.baseUrl, page.post, Session.token, Session.language, true,
            function (res) {
                // Guard the late reply: the reader may have moved to another article,
                // or asked for the real thing in the meantime.
                if (!page || !page.post || page.post.permlink !== permlink) return;
                if (page.summaryRequested || page.summaryLoading) return;
                if (!res.bullets || res.bullets.length === 0) return;
                page.summaryBullets = res.bullets;
                page.summaryMinutes = res.readMinutes;
                page.summaryRequested = true;
            },
            // Nothing cached, or the lookup failed: the on-expand request still stands.
            function () {});
    }

    // The paid generation is still spent only on a reader who expands the drawer: a
    // request per article opened exhausted the 30-per-10-minutes budget in one browsing
    // session, and every drawer after that opened empty. Prefetch above is cache-only
    // for exactly that reason.
    function _loadSummary(force) {
        if (page.summarySkipped) return;
        if (!page.post || !page.post.body) return;
        if (page.summaryLoading || (page.summaryRequested && !force)) return;
        page.summaryRequested = true;
        page.summaryMinutes = page._localReadMinutes(page.post.body);
        page.summaryLoading = true;
        page.summaryError = "";
        // Bullets follow the app language; the server falls back to English when it
        // has no translation and the article is too old to pay for one.
        SummaryService.summarize(Config.baseUrl, page.post, Session.token, Session.language, false,
            function (res) {
                // Generation can take seconds; the reader may have closed the page by now.
                if (!page) return;
                page.summaryLoading = false;
                page.summaryBullets = res.bullets;
                page.summaryMinutes = res.readMinutes;
            },
            function (err) {
                // The bar still stands, but the drawer has to say why it's empty:
                // silently showing nothing reads as a broken expander.
                if (!page) return;
                page.summaryLoading = false;
                page.summaryBullets = [];
                page.summaryError = (err && err.status === 429)
                    ? Lang.tr("Too many summary requests. Try again in a minute.")
                    : Lang.tr("Summary didn't load.");
            });
    }

    readonly property int _relatedWanted: 3

    // Enough to load related before the article itself lands; the feed row passed at push
    // time carries the community and category, which is all this needs.
    function _relatedSeed() { return page.post || page.seedPost || page.preloadedPost || null; }

    // Same category first, then anything else in the pool: a loosely related rail beats an
    // empty one. `pass1` restricts to the category.
    function _fillRelated(pool, cat, out, seen, hidden, blocked, sameCatOnly) {
        for (var i = 0; i < pool.length && out.length < page._relatedWanted; i++) {
            var p = pool[i];
            if (!p || !p.permlink || seen[p.permlink]) continue;
            if (hidden[p.permlink] || blocked[p.author || ""]) continue;
            if (sameCatOnly && cat !== "" && p.primaryCategory !== cat) continue;
            seen[p.permlink] = true;
            out.push(p);
        }
    }

    // Right rail. Cache first: the list the reader came from is already in FeedCache, so the
    // common case costs no request at all and paints before the article arrives.
    function loadRelated() {
        var seed = page._relatedSeed();
        // Only desktop renders the rail, so anywhere else this would be a request nobody sees
        if (!seed || !page.allowSidePanel || !Config.desktopMode) return;
        // Called twice on purpose (seed, then again once the post lands); both are no-ops
        // once the rail is full or a request is already out.
        if (page.relatedLoading || page.relatedPosts.length >= page._relatedWanted) return;

        var cat = seed.primaryCategory || "";
        var communityId = seed.communityId || 0;
        var hidden = HiddenPosts.loadAll();
        var blocked = BlockedUsers.loadAll();
        var out = [];
        var seen = {};
        seen[page.permlink] = true;
        var key = "related:" + communityId + ":" + cat + ":"
                  + (Session.isLoggedIn && Session.username ? Session.username : "__guest__");

        // The cached feed only describes the community being browsed. seedPost means the
        // reader came from that list, so the rows belong to this post; a deep link doesn't.
        var pool = [];
        if (page.seedPost) {
            for (var f = 0; f < 2; f++) {
                var cached = FeedCache.peek(FeedCache.newsKey(f, Config.communityId));
                if (cached) pool = pool.concat(cached);
            }
        }
        var prev = FeedCache.peek(key);      // an earlier article already paid for this one
        if (prev) pool = pool.concat(prev);

        page._fillRelated(pool, cat, out, seen, hidden, blocked, true);
        if (out.length < page._relatedWanted)
            page._fillRelated(pool, cat, out, seen, hidden, blocked, false);
        if (out.length > 0) page.relatedPosts = out;
        if (out.length >= page._relatedWanted) { page.relatedLoading = false; return; }

        // Narrow server-side rather than pulling 20 posts to keep 3. No `category` on the
        // global path: that SQL branch compares against a null community_id and drops
        // cross-posted rows, so filter those client-side instead.
        page.relatedLoading = true;
        var params = { limit: 8, offset: 0 };
        if (communityId > 0) params.community_id = communityId;
        else params.exclude_home = 1;
        if (cat !== "" && communityId > 0) params.category = cat;
        FeedCache.request(key,
            function (ok, err) { return PostService.listTrending(Config.baseUrl, params, Session.token, ok, err); },
            function (posts) {
                if (!page) return;
                page.relatedLoading = false;
                page._fillRelated(posts, cat, out, seen, hidden, blocked, true);
                if (out.length < page._relatedWanted)
                    page._fillRelated(posts, cat, out, seen, hidden, blocked, false);
                page.relatedPosts = out;
            },
            function (err) { if (page) page.relatedLoading = false; });
    }

    function load() {
        if (page.offlineMode) return;   // offline
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
                page._initSummary();
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
                        // Reading the stored copy IS offline mode: no comments, no related rail
                        page.offlineMode = true;
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
        page.editTarget = null;
        page.replyTarget = comment;
        composer.forceActiveFocus();
        Qt.inputMethod.show();
    }

    function cancelReply() {
        page.replyTarget = null;
    }

    // Edit runs through the docked composer, pre-filled, instead of a second field in the row.
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

    // YouTube only
    function _isEmbeddableVideoUrl(url) {
        return /(?:youtube\.com\/(?:watch\?|embed\/|shorts\/)|youtu\.be\/)/i.test(url || "");
    }

    // Web editor's nested-div video embed -> our <p><a> shape
    function _stripWebVideoContainers(html) {
        var re = /<div\b[^>]*data-video-url="([^"]*)"[^>]*>/gi;
        var tagRe = /<div\b[^>]*>|<\/div>/gi;
        var out = "";
        var lastIndex = 0;
        var m;
        while ((m = re.exec(html)) !== null) {
            out += html.substring(lastIndex, m.index);
            var url = m[1];
            var depth = 1;
            var end = html.length;
            tagRe.lastIndex = re.lastIndex;
            var tm;
            while ((tm = tagRe.exec(html)) !== null) {
                depth += tm[0].charAt(1) === "/" ? -1 : 1;
                if (depth === 0) { end = tm.index + tm[0].length; break; }
            }
            out += url.length > 0 ? ('<p><a href="' + url + '">' + url + '</a></p>') : "";
            lastIndex = end;
            re.lastIndex = end;
        }
        out += html.substring(lastIndex);
        return out;
    }

    function _parseBody() {
        bodyModel.clear();
        if (!page.post)
            return;
        var html = page.post.body || "";

        // Must run before <img>/tag stripping below
        html = page._stripWebVideoContainers(html);

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

        // Isolated video link -> own "embed" block
        var pieces2 = [];
        var linkParaRe = /<p[^>]*>\s*<a\s+[^>]*href="([^"]*)"[^>]*>[^<]*<\/a>\s*<\/p>/gi;
        for (var pi = 0; pi < pieces.length; pi++) {
            var pc = pieces[pi];
            if (pc.type !== "html") { pieces2.push(pc); continue; }
            var rem2 = pc.content, lastIdx = 0, mm;
            linkParaRe.lastIndex = 0;
            while ((mm = linkParaRe.exec(rem2)) !== null) {
                var before2 = rem2.substring(lastIdx, mm.index);
                if (before2) pieces2.push({ type: "html", content: before2 });
                if (page._isEmbeddableVideoUrl(mm[1])) pieces2.push({ type: "embed", content: mm[1] });
                else pieces2.push({ type: "html", content: mm[0] });
                lastIdx = mm.index + mm[0].length;
            }
            var tail2 = rem2.substring(lastIdx);
            if (tail2) pieces2.push({ type: "html", content: tail2 });
        }
        pieces = pieces2;

        var seenImages = {};
        for (var i = 0; i < pieces.length; i++) {
            var piece = pieces[i];
            if (piece.type === "image") {
                if (seenImages[piece.content]) continue;   // container tag + inner <img> = same src twice
                seenImages[piece.content] = true;
                bodyModel.append({ type: "image", content: piece.content, links: "[]" });
            } else if (piece.type === "embed") {
                bodyModel.append({ type: "embed", content: piece.content, links: "[]" });
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
                text = text.replace(/<(?!\/?(?:b|i|br|u|s|a)\b)[^>]*>/gi, "");
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
                // No linkAt() API: capture href + visible text so taps can be hit-tested
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
        // Before load(), not after it: the seed carries community and category, so the rail
        // fills from cache while the article is still in flight.
        if (!page.offlineMode) page.loadRelated();
        load();
    }

    // Open a creator's profile (post author or a comment author).
    function openProfile(username) {
        if (username)
            page.pageStack.push(Qt.resolvedUrl("ProfileViewPage.qml"), { username: username });
    }
    function openAuthor() { if (page.post) page.openProfile(page.post.author); }

    // Right steps into side panel; Down/Up walk related posts, upvote, downvote, composer
    function focusSidePanel() {
        if (!page.showSidePanel) return;
        page._sidePanelFocusRing = true;
        sidePanelFlick.forceActiveFocus();
        page.sidePanelIndex = 0;
    }
    // keyboard nav only, not for taps
    property bool _sidePanelFocusRing: false

    // Highlighted item while the panel owns arrow-key focus; -1 = none (composer has focus instead).
    property int sidePanelIndex: -1
    readonly property int _voteUpIdx: page.relatedPosts.length
    readonly property int _voteDownIdx: page.relatedPosts.length + 1
    readonly property int _sidePanelItemCount: page.relatedPosts.length + 2

    function openRelated(post, byKeyboard) {
        // Pass the row as the seed: the next page's rail fills before its article lands
        page.pageStack.push(Qt.resolvedUrl("PostDetailPage.qml"),
                            { author: post.author, permlink: post.permlink,
                              title: post.title || "", seedPost: post,
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

    // Owns arrow-key focus; AdaptiveStack.focusDetail() targets this from the list
    property Item keyboardFocusItem: scroll

    // Push from detail column skips focusDetail(); waits for postReady so scroll exists
    property bool focusOnOpen: false
    onPostReadyChanged: if (postReady && page.focusOnOpen) {
        page.focusOnOpen = false;
        Qt.callLater(function () { if (scroll.visible) scroll.forceActiveFocus(); });
    }

    // Opened inside a stack that already owns a third column (Settings > Saved
    // articles / Downloaded Content): its rail would make a fourth.
    property bool allowSidePanel: true

    // Right rail (related/votes/comments): desktop only, tablet has no room for a 3rd column
    readonly property bool showSidePanel: Config.desktopMode && page.allowSidePanel && page.postReady

    // Resizable via the drag handle below; clamped so the article column always keeps a sane minimum width.
    property real sidePanelWidth: units.gu(34)
    // was 26gu, too tight for the vote bar content
    readonly property real _minSidePanelW: units.gu(30)
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

        // Plain Flickable ignores keys, so scroll keys are handled here
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
            // Right steps into the side panel (related/votes/comments)
            else if (event.key === Qt.Key_Right && page.showSidePanel) { page.focusSidePanel(); event.accepted = true; }
        }
        // No auto-focus-on-load: used to steal focus even for mouse opens

        // closes open comment menu on outside tap
        MouseArea {
            width: scroll.contentWidth; height: scroll.contentHeight
            enabled: CommentMenu.openKey !== ""
            onClicked: CommentMenu.openKey = ""
        }

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
                error: page.summaryError
                onSummaryNeeded: page._loadSummary(false)
                onRetryRequested: page._loadSummary(true)
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

            Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

            // Body is parsed into text blocks and rounded images; inset once here so every block shares the same left/right padding as the title/author row.
            Column {
                width: parent.width - Style.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.spacingS

                Repeater {
                    model: bodyModel

                    delegate: Loader {
                        width: parent.width
                        sourceComponent: model.type === "image" ? bodyImageComp
                                        : model.type === "embed" ? bodyEmbedComp
                                        : bodyTextComp

                        Component {
                            id: bodyEmbedComp
                            // No OpacityMask: WebEngineView doesn't mask reliably
                            Rectangle {
                                id: embedBox
                                width: parent.width
                                height: width * 9 / 16
                                radius: Style.thumbRadius
                                color: "black"
                                clip: true

                                VideoWebView {
                                    id: embedPlayer
                                    anchors.fill: parent
                                    wrap: true
                                    embedUrl: model.content
                                    // Reparent only; anchors.fill: parent follows automatically
                                    onFullscreenToggled: {
                                        page.videoFullscreenActive = on;
                                        embedPlayer.parent = on ? videoFsHost : embedBox;
                                        embedPlayer.focusWeb();
                                    }
                                }
                            }
                        }

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
                                    // Stray-selection guard: scroll doesn't cancel the press-and-hold word-select timer
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
                                    // Chain reading keys to the flick; copy/select-all fall through untouched
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
                                    // Fresh press resets the flag so a deliberate long-press is never blocked
                                    onActiveFocusChanged: if (activeFocus) bodyTxt._scrolledSinceFocus = false
                                    // Words currently selected, so the haptic ticks per word rather than per character.
                                    property int _selWords: 0
                                    // Caret visible only while selected, gating the native Copy popover; always-on left an idle blue cursor while reading.
                                    onSelectedTextChanged: {
                                        // Stray if scroller is moving, or scrolled recently during this press
                                        if (selectedText.length > 0
                                                && (scroll.moving || scroll.flicking
                                                    || (bodyTxt._scrolledSinceFocus
                                                        && (Date.now() - bodyTxt._lastScrollMs) < bodyTxt._scrollSelGuardMs))) {
                                            bodyTxt.deselect();
                                            return;
                                        }
                                        cursorVisible = (selectedText.length > 0);
                                        bodyTxt._tickSelection();
                                    }
                                    // A tick as the selection lands on a word and each time it grows by one, the way
                                    // the handles feel elsewhere. Per character would buzz continuously while dragging.
                                    function _tickSelection() {
                                        var t = selectedText.replace(/^\s+|\s+$/g, "");
                                        var words = t.length > 0 ? t.split(/\s+/).length : 0;
                                        if (words === bodyTxt._selWords) return;
                                        // Growing only: releasing or shrinking back shouldn't buzz.
                                        if (words > bodyTxt._selWords) Haptics.play();
                                        bodyTxt._selWords = words;
                                    }
                                    onCursorVisibleChanged: if (!cursorVisible && selectedText.length > 0) cursorVisible = true
                                }

                                // Track scroll activity so the selection guard can distinguish stray vs deliberate
                                Connections {
                                    target: scroll
                                    onMovementStarted: { bodyTxt._scrolledSinceFocus = true; bodyTxt._lastScrollMs = Date.now(); bodyTxt.deselect() }
                                    onMovementEnded:   bodyTxt._lastScrollMs = Date.now()
                                    onFlickStarted:    { bodyTxt._scrolledSinceFocus = true; bodyTxt._lastScrollMs = Date.now() }
                                    onFlickEnded:      bodyTxt._lastScrollMs = Date.now()
                                    onDraggingChanged: { if (scroll.dragging) bodyTxt._scrolledSinceFocus = true; bodyTxt._lastScrollMs = Date.now() }
                                }

                                // Tap-to-open links: no linkAt()/onLinkActivated inside a Flickable, hit-test instead
                                MouseArea {
                                    anchors.fill: bodyTxt
                                    propagateComposedEvents: true
                                    property string _pendingHref: ""
                                    function _hrefAt(x, y) {
                                        var arr;
                                        try { arr = JSON.parse(model.links || "[]"); } catch (e) { return ""; }
                                        if (!arr.length) return "";
                                        // confirm click is inside the link's own rect
                                        var pos = bodyTxt.positionAt(x, y);
                                        var plain = bodyTxt.getText(0, bodyTxt.length);
                                        for (var i = 0; i < arr.length; i++) {
                                            var t = arr[i].text;
                                            if (!t) continue;
                                            var from = 0, idx;
                                            while ((idx = plain.indexOf(t, from)) !== -1) {
                                                if (pos >= idx && pos <= idx + t.length) {
                                                    var r0 = bodyTxt.positionToRectangle(idx);
                                                    var r1 = bodyTxt.positionToRectangle(idx + t.length);
                                                    if (y >= r0.y && y <= r0.y + r0.height && x >= r0.x && x <= r1.x)
                                                        return arr[i].href;
                                                }
                                                from = idx + 1;
                                            }
                                        }
                                        return "";
                                    }
                                    onPressed: {
                                        _pendingHref = _hrefAt(mouse.x, mouse.y);
                                        // Only grab the press when it's on a link
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

            // Narrow mode only; hidden offline
            Column {
                id: commentsColumn
                visible: !page.offlineMode
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
                    // Wrapper carries the between-comments rule the rail needs; the
                    // article column keeps the roomier avatar-indented layout.
                    delegate: Column {
                        width: commentsColumn.width
                        spacing: Style.spacingS

                        Rectangle {
                            visible: page.showSidePanel && index > 0
                            width: parent.width
                            height: units.dp(1)
                            color: Style.divider
                        }

                        CommentItem {
                            width: parent.width
                            compact: page.showSidePanel
                            comment: modelData
                            onDeleted: page.removeComment(permlink)
                            onEditRequested: page.startEdit(comment)
                            onReplyRequested: page.startReply(comment)
                            onAuthorClicked: page.openProfile(author)
                        }
                    }
                }
            }

            Item { width: 1; height: Style.spacingM }
        }

    }

    // Draggable splitter for sidePanel; z above postDetailHeader for an unbroken line
    Rectangle {
        id: sidePanelDivider
        z: 11
        anchors { top: parent.top; bottom: parent.bottom; right: sidePanel.left }
        width: units.dp(1)
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

    // --- Right rail (wide mode): related posts, vote bar, comments, composer; own header row ---
    Rectangle {
        id: sidePanel
        anchors { top: parent.top; right: parent.right; bottom: parent.bottom }
        width: page.showSidePanel ? page._sidePanelW : 0
        visible: page.showSidePanel
        clip: true
        color: Style.surface

        // No border here: sidePanelDivider (page-level sibling) is the single vertical line

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

        // Keyboard focus ring; must live inside sidePanel, since anchors only reach a
        // parent or sibling and the page-scope copy could never resolve the flick.
        Rectangle {
            anchors.fill: sidePanelFlick
            visible: page.showSidePanel && sidePanelFlick.activeFocus && page._sidePanelFocusRing
            color: "transparent"
            border.width: units.dp(2)
            border.color: Style.brand
            z: 12
        }

        Flickable {
            id: sidePanelFlick
            anchors { top: sidePanelHeader.bottom; left: parent.left; right: parent.right; bottom: sideComposerBar.top }
            contentWidth: width
            contentHeight: sidePanelCol.height + Style.spacingM * 2
            clip: true

            // Same keyboard-scroll contract as article; Left/Escape steps back to article
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

                RelatedSkeleton {
                    width: sidePanelCol.width
                    // showSidePanel too: an invisible ancestor doesn't stop the pulse animations
                    visible: page.showSidePanel && page.relatedPosts.length === 0 && page.relatedLoading
                }

                Label {
                    width: sidePanelCol.width
                    visible: page.relatedPosts.length === 0 && !page.relatedLoading && page.postReady
                    text: Lang.tr("Nothing related yet")
                    font.pixelSize: Style.fontSmall
                    color: Style.textSecondary
                    wrapMode: Text.Wrap
                }

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
                                    // Cap the decode: gu(6.5) thumbs, not full-size covers
                                    sourceSize.width: units.gu(13)
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
                                // guards against negative width
                                width: Math.max(units.gu(4), parent.width - units.gu(6.5) - Style.spacingS)
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

                // Hidden offline
                VoteBar {
                    id: detailVoteBar
                    visible: !page.offlineMode
                    parent: page.showSidePanel ? sidePanelCol : footerCol
                    // Full rail width: the coin pill needs every pixel to keep its "SEREY"
                    // unit word, and the column already insets it from the window frame.
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

        // Click grabs keyboard focus for the panel; press unaccepted so buttons still fire
        MouseArea {
            anchors.fill: sidePanelFlick
            propagateComposedEvents: true
            onPressed: { page._sidePanelFocusRing = false; sidePanelFlick.forceActiveFocus(); mouse.accepted = false; }
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

            // Continues the panel's left border past this bar's opaque background
            Rectangle {
                visible: page.showSidePanel
                anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                width: units.dp(1)
                color: Style.divider
            }

            Column {
                id: composerArea
                // Hidden offline, like the comment list it posts into: a stored copy has no
                // comments loaded, so a live box here posts into something you can't see.
                visible: !page.offlineMode
                parent: page.showSidePanel ? sideComposerBar : footerCol
                x: page.showSidePanel ? Style.spacingS : 0
                y: page.showSidePanel ? Style.spacingS : 0
                width: page.showSidePanel ? parent.width - Style.spacingS * 2 : parent.width - Style.spacingM * 2
                anchors.horizontalCenter: page.showSidePanel ? undefined : parent.horizontalCenter
                spacing: units.dp(4)

                Row {
                    visible: page.replyTarget !== null || page.editTarget !== null
                    width: parent.width
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

                // Comment composer: plain Rectangle behind a borderless TextField
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
                    // Stands in for the keyboard's auto-shift on the first letter.
                    AutoCapitalize { field: composer }
                        anchors { left: parent.left; leftMargin: Style.spacingM; right: sendButton.left; rightMargin: Style.spacingXs; verticalCenter: parent.verticalCenter }
                        height: parent.height - units.dp(2)
                        StyleHints {
                            backgroundColor: "transparent"
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
                        // Up steps back to the downvote button; Escape returns to the article.
                        Keys.onUpPressed: {
                            if (page.showSidePanel) {
                                page.sidePanelIndex = page._voteDownIdx;
                                page._sidePanelFocusRing = true;
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
                        enabled: !page.posting && composer.displayText.trim().length > 0
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

    // The rail only exists once the post lands, so on desktop the placeholder has to
    // hold its column open; otherwise the page loads full-bleed and then snaps to three.
    readonly property real _pendingRailW: (Config.desktopMode && page.allowSidePanel && !page.showSidePanel)
                                          ? page._sidePanelW : 0

    Item {
        id: railSkeleton
        anchors { top: parent.top; right: parent.right; bottom: parent.bottom }
        width: page._pendingRailW
        // Not on the error path: the skeleton would pulse forever next to a failed article
        visible: page._pendingRailW > 0 && page.post === null && page.errorMsg === ""

        Rectangle { anchors.fill: parent; color: Style.surface }
        Rectangle {
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
            width: units.dp(1)
            color: Style.divider
        }

        // Real header, skeleton contents: the column announces what it is while it fills.
        Item {
            id: railSkeletonHeader
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: postDetailHeader.height
            Label {
                anchors { left: parent.left; leftMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                text: Lang.tr("Related")
                font.pixelSize: Style.fontSmall
                font.weight: Font.Bold
                color: Style.textSecondary
            }
        }

        RelatedSkeleton {
            anchors { top: railSkeletonHeader.bottom; left: parent.left; right: parent.right; margins: Style.spacingM }
            visible: railSkeleton.visible
        }
    }

    LoadingState {
        anchors {
            top: postDetailHeader.bottom
            left: parent.left
            right: page.showSidePanel ? sidePanel.left : parent.right
            rightMargin: page._pendingRailW
            bottom: parent.bottom
        }
        visible: page.loading && page.post === null
        count: 1
        contentMaxWidth: page.maxContentWidth
    }
    ErrorState {
        anchors {
            top: postDetailHeader.bottom
            left: parent.left
            right: page.showSidePanel ? sidePanel.left : parent.right
            rightMargin: page._pendingRailW
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

    // Fullscreen host for body embeds (mirrors VideoDetailPage's fsHost)
    property bool videoFullscreenActive: false
    Item {
        id: videoFsHost
        parent: (page.videoFullscreenActive && Window.contentItem) ? Window.contentItem : page
        anchors.fill: parent
        z: 2000
        visible: page.videoFullscreenActive
        Rectangle { anchors.fill: parent; color: "black" }
    }
}
