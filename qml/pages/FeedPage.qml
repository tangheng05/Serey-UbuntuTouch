import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/PostService.js" as PostService
import "../services/VideoService.js" as VideoService
import "../services/HiddenPosts.js" as HiddenPosts
import "../services/BlockedUsers.js" as BlockedUsers

Page {
    id: page

    // Cards need swipe actions, so a fixed-cell GridView won't work — cap + center instead
    readonly property real maxContentWidth: units.gu(60)

    // Master-detail (like the News/blog page) when the page itself is wide enough:
    // the feed becomes a left side-list and the tapped article opens in a detail
    // panel on the right. Based on the page's OWN width so it adapts whether it's
    // full-screen (Homepage) or already inside a column. Narrow keeps the phone
    // model: tapping a card pushes the article full-screen onto the outer stack.
    readonly property bool wide: width >= Config.convergenceBreakpoint
    readonly property real listPaneW: units.gu(40)

    // My Feed runs its OWN split, so it services the master-detail keyboard-focus
    // signals itself; the enclosing AdaptiveStack defers to it (sees _ownsKeyboardNav).
    property bool _ownsKeyboardNav: page.wide && innerDetail.depth > 0
    property Item keyboardFocusItem: list
    function _focusFeedList() { list.forceActiveFocus(); }
    function _focusFeedDetail() {
        var p = innerDetail.currentPage;
        if (p) (p.keyboardFocusItem ? p.keyboardFocusItem : p).forceActiveFocus();
    }
    Connections {
        target: Nav
        function onFocusMaster() { if (page.visible && page._ownsKeyboardNav) page._focusFeedList(); }
        function onFocusDetail() { if (page.visible && page._ownsKeyboardNav) page._focusFeedDetail(); }
    }

    // Tracks which row's detail is open in the split-pane (wide) layout so the master list can highlight it.
    property string openPermlink: ""

    // Route a card tap: into the right detail panel when split, else a full-screen
    // push onto the outer page stack. Replaces the current detail (no stacking) so
    // picking another item swaps the article, exactly like News master-detail.
    function openDetail(url, props) {
        // Push first: while (depth > 0) pop() transiently drops innerDetail to depth 0,
        // which would otherwise race with — and clear — this via the onDepthChanged reset above.
        if (page.wide) {
            while (innerDetail.depth > 0) innerDetail.pop();
            innerDetail.push(url, props);
        } else {
            page.pageStack.push(url, props);
        }
        page.openPermlink = (props && props.permlink) || (props && props.video && props.video.permlink) || "";
    }

    // 0 = All (mixed), 1 = Blog only, 2 = Video only.
    property int filterMode: 0
    property bool filterMenuOpen: false
    readonly property var filterNames: [Lang.tr("All"), Lang.tr("Blog"), Lang.tr("Video")]

    // Independent per-source pagination cursors.
    property int  blogOffset: 0
    property bool blogEnded: false
    property int  vidOffset: 0
    property bool vidEnded: false
    property var  inflightBlog: null
    property var  inflightVideo: null

    property bool loading: false
    property string errorMsg: ""
    property int reqEpoch: 0
    // Bounds one "fill the screen" burst so a heavily-filtered feed can't spiral into many sequential requests; reset on every user-initiated load.
    property int autoFetches: 0

    property bool refreshing: false
    // On refresh, keep the old rows on screen until the first new batch arrives so there's no skeleton flash, just the pull spinner.
    property bool _refreshClear: false

    header: Item { height: 0 }

    ListModel { id: feedModel; dynamicRoles: true }

    Rectangle {
        id: topBar
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: units.gu(6)
        color: Style.navigationBg
        z: 10

        BackButton {
            anchors { left: parent.left; leftMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
            onClicked: page.pageStack.pop()
        }

        Row {
            anchors.centerIn: parent
            spacing: Style.spacingS

            Image {
                anchors.verticalCenter: parent.verticalCenter
                width: units.gu(3.5); height: width
                source: Qt.resolvedUrl("../../assets/iconFeed.png")
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: Lang.tr("My Feed")
                font.pixelSize: Style.fontMedium
                font.weight: Font.DemiBold
                font.family: Style.fontFor(text)
                color: Style.textPrimary
            }
        }

        // Filter button: opens the All / Blog / Video menu.
        AbstractButton {
            id: filterButton
            anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
            height: units.gu(4)
            width: filterRow.width + Style.spacingS * 2
            onClicked: page.filterMenuOpen = !page.filterMenuOpen

            Row {
                id: filterRow
                anchors.centerIn: parent
                spacing: Style.spacingXs

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: page.filterMode !== 0
                    text: page.filterNames[page.filterMode]
                    font.pixelSize: Style.fontSmall
                    font.weight: Font.DemiBold
                    color: Style.brand
                }
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: units.gu(2.4); height: width
                    name: "filters"
                    color: page.filterMode !== 0 ? Style.brand : Style.textPrimary
                }
            }
        }

        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: units.dp(1)
            color: Style.divider
        }
    }

    // --- Source helpers ------------------------------------------------------
    function _wantBlog()  { return page.filterMode !== 2; }   // All or Blog
    function _wantVideo() { return page.filterMode !== 1; }   // All or Video
    function _allEnded() {
        return (!_wantBlog()  || page.blogEnded)
            && (!_wantVideo() || page.vidEnded);
    }

    function _params(offset, limit) {
        var p = { limit: limit, offset: offset };
        if (Config.communityId > 0) p.community_id = Config.communityId;
        return p;
    }

    // A post is a video if its (primary) category says so — used to drop videos from the blog source.
    function _isVideo(p) {
        if (p.primaryCategory === "video") return true;
        var c = p.categories;
        return !!(c && c.indexOf && c.indexOf("video") >= 0);
    }

    // Parse a row's publish date to a sortable timestamp (0 if unparseable) so a mixed batch can be ordered newest-first.
    function _ts(row) {
        var t = Date.parse(row.date || "");
        return isNaN(t) ? 0 : t;
    }

    // Bounded auto-continue: keep paging to fill a screenful, but cap the chain so a heavily-filtered feed can't fire many sequential requests.
    function _maybeAutoContinue() {
        if (!page._allEnded() && feedModel.count < Config.pageSize && page.autoFetches < 6) {
            page.autoFetches++;
            page.loadMore();
        }
    }

    // Loading: fetches the next page from every wanted, not-yet-ended source in parallel, then merges the combined, date-sorted, filtered batch.
    function loadMore() {
        if (page.loading || page._allEnded()) return;
        page.loading = true;
        page.errorMsg = "";
        var epoch = page.reqEpoch;
        var blogRows = [];
        var vidRows = [];
        var pending = 0;
        var lastErr = null;

        function finish() {
            if (epoch !== page.reqEpoch) return;
            page.loading = false;
            page.refreshing = false;
            if (page._refreshClear) { feedModel.clear(); page._refreshClear = false; }
            if (lastErr && feedModel.count === 0) {
                page.errorMsg = lastErr.message || Lang.tr("Something went wrong");
                return;
            }
            var hidden = HiddenPosts.loadAll();
            var blocked = BlockedUsers.loadAll();
            var batch = blogRows.concat(vidRows);
            batch.sort(function (a, b) { return page._ts(b) - page._ts(a); });
            for (var i = 0; i < batch.length; i++) {
                var p = batch[i];
                if (hidden[p.permlink || ""] || blocked[p.author || ""]) continue;
                feedModel.append(p);
            }
            page._maybeAutoContinue();
        }

        if (page._wantBlog() && !page.blogEnded) {
            pending++;
            // Over-fetch since videos are filtered out of this source, so a larger round-trip fills the screen instead of many small ones.
            var blogLimit = Config.pageSize * 2;
            page.inflightBlog = PostService.listFeedFollowing(Config.baseUrl,
                page._params(page.blogOffset, blogLimit), Session.token,
                function (result, rawCount) {
                    if (epoch !== page.reqEpoch) return;
                    page.inflightBlog = null;
                    for (var i = 0; i < result.length; i++) {
                        var p = result[i];
                        if (page._isVideo(p)) continue;
                        p._kind = "blog";
                        blogRows.push(p);
                    }
                    page.blogOffset += rawCount;
                    if (rawCount < blogLimit) page.blogEnded = true;
                    if (--pending === 0) finish();
                },
                function (err) {
                    if (epoch !== page.reqEpoch) return;
                    page.inflightBlog = null;
                    lastErr = err;
                    if (--pending === 0) finish();
                });
        }

        if (page._wantVideo() && !page.vidEnded) {
            pending++;
            var vidLimit = Config.pageSize;
            page.inflightVideo = VideoService.listVideos(Config.baseUrl,
                page._params(page.vidOffset, vidLimit), Session.token,
                function (result, rawCount) {
                    if (epoch !== page.reqEpoch) return;
                    page.inflightVideo = null;
                    for (var i = 0; i < result.length; i++) {
                        var v = result[i];
                        v._kind = "video";
                        vidRows.push(v);
                    }
                    page.vidOffset += rawCount;
                    if (rawCount < vidLimit) page.vidEnded = true;
                    if (--pending === 0) finish();
                },
                function (err) {
                    if (epoch !== page.reqEpoch) return;
                    page.inflightVideo = null;
                    lastErr = err;
                    if (--pending === 0) finish();
                });
        }

        if (pending === 0) { page.loading = false; page.refreshing = false; }
    }

    function _abortInflight() {
        if (page.inflightBlog)  { page.inflightBlog.abort();  page.inflightBlog = null; }
        if (page.inflightVideo) { page.inflightVideo.abort(); page.inflightVideo = null; }
    }

    function _resetCursors() {
        page.blogOffset = 0; page.blogEnded = false;
        page.vidOffset = 0;  page.vidEnded = false;
        page.autoFetches = 0;
        page.loading = false;
        page.errorMsg = "";
    }

    function reload() {
        page.reqEpoch++;
        page._abortInflight();
        page._resetCursors();
        feedModel.clear();
        loadMore();
    }

    function refresh() {
        if (page.refreshing) return;
        page.refreshing = true;
        page._refreshClear = true;   // clear rows only once the new batch lands
        page.reqEpoch++;
        page._abortInflight();
        page._resetCursors();
        loadMore();
    }

    Component.onCompleted: {
        page.reload();
        if (visible) list.forceActiveFocus();
    }
    // Keyboard parity on arrival: the list takes arrow-key focus whenever this
    // page is (re)shown, so keyboard nav works before the first click/tap.
    onVisibleChanged: if (visible) list.forceActiveFocus()

    Connections {
        target: PostActions
        function _removeByPermlink(permlink) {
            for (var i = feedModel.count - 1; i >= 0; i--)
                if (feedModel.get(i).permlink === permlink) feedModel.remove(i);
        }
        function onHideRequested(author, permlink) {
            for (var i = 0; i < feedModel.count; i++) {
                if (feedModel.get(i).permlink === permlink) {
                    feedModel.remove(i);
                    Toast.show(Lang.tr("Post hidden"));
                    return;
                }
            }
        }
        function onPostDeleted(author, permlink) { _removeByPermlink(permlink); }
        function onCommentCountChanged(permlink, count) {
            for (var i = 0; i < feedModel.count; i++)
                if (feedModel.get(i).permlink === permlink) { feedModel.setProperty(i, "comments", count); return; }
        }
        function onPostUpdated(author, permlink, title, body) {
            for (var i = 0; i < feedModel.count; i++) {
                if (feedModel.get(i).permlink === permlink) {
                    feedModel.setProperty(i, "title", title);
                    feedModel.setProperty(i, "body", body);
                    return;
                }
            }
        }
        function onUserBlocked(username) {
            for (var i = feedModel.count - 1; i >= 0; i--) {
                if (feedModel.get(i).author === username) feedModel.remove(i);
            }
        }
        function onUserUnblocked(username) { page.reload(); }
        function onEditRequested(post) {
            if (!page.visible) return;
            var ed = page.pageStack.push(Qt.resolvedUrl("CreatePostPage.qml"), { editPost: post });
            if (ed && ed.saved) ed.saved.connect(page.reload);
        }
    }

    ListView {
        id: list
        // Vertical via anchors; horizontal via x/width so the wide<->narrow switch
        // is a plain binding (no conditional anchor to strand). Wide: left side-list
        // at listPaneW. Narrow: centered reading column, capped at maxContentWidth.
        anchors { top: topBar.bottom; bottom: parent.bottom }
        width: page.wide ? page.listPaneW : Math.min(parent.width, page.maxContentWidth)
        x: page.wide ? 0 : Math.max(0, (parent.width - width) / 2)
        clip: true
        // Right arrow steps into the open article's reading pane (split windows).
        Keys.onRightPressed: Nav.focusDetail()
        model: feedModel
        cacheBuffer: units.gu(12)
        // Keyboard cursor visual: the Lomiri ListItem's own key-navigation frame
        // (see NewsPage) — no custom highlight, it double-ringed.

        PullToRefresh {
            refreshing: page.refreshing
            onRefresh: page.refresh()
            content: Label {
                text: Lang.tr("Pull to refresh")
                opacity: list.dragging ? 1 : 0
                font.pixelSize: Style.fontSmall
                color: Style.textSecondary
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        delegate: ListItem {
            id: feedItem
            width: list.width
            height: contentLoader.height
            property var postData: feedModel.get(index)
            readonly property bool isVideo: postData && postData._kind === "video"
            // Dark-greys the row whose article is currently open in the detail pane (wide layout only).
            color: (page.wide && page.openPermlink !== "" && postData && postData.permlink === page.openPermlink)
                ? Style.iconBackground : Style.surface

            // Keyboard/whole-row activation: Lomiri ListItem emits clicked() on
            // Enter when key-nav focused (and on a tap of any non-interactive
            // area) — same wiring as NewsPage; without this, Enter does nothing.
            onClicked: {
                var p = feedModel.get(index)
                if (!p) return
                if (p._kind === "video")
                    page.openDetail(Qt.resolvedUrl("VideoDetailPage.qml"), { video: p })
                else
                    page.openDetail(Qt.resolvedUrl("PostDetailPage.qml"),
                        { author: p.author, permlink: p.permlink, title: p.title })
            }

            // Touch equivalent of the removed ••• button — opens the same Hide/Report/Block sheet.
            onPressAndHold: {
                var p = feedModel.get(index)
                if (p) PostActions.open(p, p._kind === "video" ? "video" : "blog")
            }

            // Lomiri HIG (Presenting data): leading = negative/destructive, trailing = positive/confirming.
            leadingActions: ListItemActions {
                delegate: Rectangle {
                    width: units.gu(7)
                    height: parent ? parent.height : units.gu(6)
                    color: Style.danger
                    Icon {
                        anchors.centerIn: parent
                        width: units.gu(2.5); height: width
                        name: action.iconName
                        color: "white"
                    }
                }
                actions: [
                    Action {
                        iconName: "close"
                        text: Lang.tr("Hide")
                        onTriggered: {
                            var p = feedModel.get(index)
                            if (p) PostActions.hideRequested(p.author, p.permlink)
                        }
                    }
                ]
            }

            trailingActions: ListItemActions {
                delegate: Item {
                    width: units.gu(7)
                    height: parent ? parent.height : units.gu(6)
                    // Reflects already-following on the "contact"/Follow action; every other action keeps the neutral color.
                    readonly property bool isFollowAction: action.iconName === "contact"
                    readonly property var _rowPost: isFollowAction ? feedModel.get(index) : null
                    Icon {
                        anchors.centerIn: parent
                        width: units.gu(2.5); height: width
                        name: action.iconName
                        color: (parent.isFollowAction && parent._rowPost && FollowStore.isFollowing(parent._rowPost.author))
                            ? Style.brand : Style.textPrimary
                    }
                }
                actions: [
                    Action {
                        iconName: "contact"
                        text: Lang.tr("Follow")
                        onTriggered: {
                            var p = feedModel.get(index)
                            if (!p || !p.author || p.author === Session.username) return
                            if (!Session.isLoggedIn) { Toast.error(Lang.tr("Please log in first.")); return; }
                            var now = FollowStore.toggle(Config.baseUrl, p.author, Session.token)
                            Toast.show(now ? Lang.tr("Following") : Lang.tr("Unfollowed"))
                        }
                    },
                    Action {
                        iconName: "share"
                        text: Lang.tr("Share")
                        onTriggered: {
                            var p = feedModel.get(index)
                            if (!p) return
                            if (p._kind === "video")
                                Share.open("https://serey.io/video-component/watch?author=" + p.author + "&permalink=" + p.permlink)
                            else
                                Share.open("https://serey.io/authors/" + p.author + "/" + p.permlink)
                        }
                    }
                ]
            }

            Loader {
                id: contentLoader
                width: parent.width
                height: item ? item.implicitHeight : 0
                sourceComponent: feedItem.isVideo ? videoDelegate : blogDelegate

                Component {
                    id: blogDelegate
                    PostCard {
                        width: parent ? parent.width : 0
                        post: feedItem.postData
                        onClicked: page.openDetail(Qt.resolvedUrl("PostDetailPage.qml"),
                            { author: feedItem.postData.author, permlink: feedItem.postData.permlink, title: feedItem.postData.title })
                        onAuthorClicked: page.openDetail(Qt.resolvedUrl("ProfileViewPage.qml"),
                            { username: feedItem.postData.author })
                        onRequireLogin: page.pageStack.push(Qt.resolvedUrl("LoginPage.qml"))
                        onMoreClicked: PostActions.open(feedItem.postData, "blog")
                    }
                }

                Component {
                    id: videoDelegate
                    VideoCard {
                        width: parent ? parent.width : 0
                        video: feedItem.postData
                        onClicked: page.openDetail(Qt.resolvedUrl("VideoDetailPage.qml"),
                            { video: feedItem.postData })
                        onAuthorClicked: page.openDetail(Qt.resolvedUrl("ProfileViewPage.qml"),
                            { username: feedItem.postData.author })
                        onMoreClicked: PostActions.open(feedItem.postData, "video")
                    }
                }
            }
        }

        footer: Item {
            width: list.width
            height: units.gu(6)
            ActivityIndicator {
                anchors.centerIn: parent
                running: page.loading && feedModel.count > 0
                visible: running
            }
        }

        onAtYEndChanged: {
            if (atYEnd && !page.loading && !page._allEnded()) {
                page.autoFetches = 0;   // fresh burst budget per user scroll
                page.loadMore();
            }
        }
    }

    // Detail panel (split mode only): the tapped article/video renders here beside
    // the feed list, so picking items feels like the News master-detail view.
    Rectangle {
        id: feedDivider
        visible: page.wide
        anchors { top: topBar.bottom; bottom: parent.bottom }
        x: list.width
        width: units.dp(1)
        color: Style.divider
    }
    Item {
        id: detailPane
        visible: page.wide
        anchors { top: topBar.bottom; bottom: parent.bottom; left: feedDivider.right; right: parent.right }

        // Opaque panel background (Pages are transparent) + empty placeholder.
        Rectangle {
            anchors.fill: parent
            color: Style.surface
            EmptyState {
                anchors.fill: parent
                visible: innerDetail.depth === 0
                iconName: "stock_note"
                message: Lang.tr("Select a post to read")
            }
        }
        // Clears the highlighted row once the detail pane's back button empties this stack.
        PageStack {
            id: innerDetail
            anchors.fill: parent
            onDepthChanged: if (depth === 0) page.openPermlink = ""
        }
    }

    LoadingState {
        anchors.fill: list
        visible: page.loading && feedModel.count === 0
    }
    ErrorState {
        anchors.fill: list
        visible: page.errorMsg !== "" && feedModel.count === 0
        message: page.errorMsg
        onRetry: page.reload()
    }
    EmptyState {
        anchors.fill: list
        visible: !page.loading && page.errorMsg === "" && feedModel.count === 0
        iconName: "stock_note"
        message: Lang.tr("Follow people to see their posts here")
    }

    // Filter dropdown: only Blog/Video are offered (All is default); tapping the active filter again clears back to the mixed All feed.
    Item {
        anchors.fill: parent
        visible: page.filterMenuOpen
        z: 100

        MouseArea { anchors.fill: parent; onClicked: page.filterMenuOpen = false }

        Rectangle {
            // topBar is a sibling of this Item's parent, not of this Rectangle, so anchor to parent.top and offset by topBar.height instead.
            anchors { top: parent.top; right: parent.right; topMargin: topBar.height + Style.spacingXs; rightMargin: Style.spacingM }
            width: units.gu(20)
            height: menuCol.height
            radius: Style.cardRadius
            color: Style.surface
            border.width: units.dp(1)
            border.color: Style.divider

            Column {
                id: menuCol
                width: parent.width

                Repeater {
                    model: [ { label: Lang.tr("Blog"), mode: 1 }, { label: Lang.tr("Video"), mode: 2 } ]

                    delegate: AbstractButton {
                        width: menuCol.width
                        height: units.gu(6)
                        onClicked: {
                            // Toggle: re-selecting the active filter returns to All.
                            page.filterMode = (page.filterMode === modelData.mode) ? 0 : modelData.mode;
                            page.filterMenuOpen = false;
                            page.reload();
                        }

                        Row {
                            anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                            spacing: Style.spacingM

                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - checkIcon.width - Style.spacingM
                                text: modelData.label
                                font.pixelSize: Style.fontRegular
                                font.family: Style.fontFor(text)
                                color: page.filterMode === modelData.mode ? Style.brand : Style.textPrimary
                                font.weight: page.filterMode === modelData.mode ? Font.DemiBold : Font.Normal
                            }
                            Icon {
                                id: checkIcon
                                anchors.verticalCenter: parent.verticalCenter
                                width: units.gu(2.2); height: width
                                name: "tick"
                                color: Style.brand
                                visible: page.filterMode === modelData.mode
                            }
                        }

                        Rectangle {
                            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                            height: units.dp(1)
                            color: Style.divider
                            visible: index === 0
                        }
                    }
                }
            }
        }
    }
}
