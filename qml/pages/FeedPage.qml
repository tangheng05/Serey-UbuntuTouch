import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/PostService.js" as PostService
import "../services/VideoService.js" as VideoService
import "../services/FollowService.js" as FollowService
import "../services/CommunitySubscriberService.js" as SubscriberService
import "../services/HiddenPosts.js" as HiddenPosts
import "../services/BlockedUsers.js" as BlockedUsers

Page {
    id: page

    // Cards need swipe actions, so a fixed-cell GridView won't work — cap + center instead
    readonly property real maxContentWidth: units.gu(60)

    // master-detail split on wide pages, phone-style push when narrow
    readonly property bool wide: width >= Config.convergenceBreakpoint
    readonly property real listPaneW: units.gu(40)

    // My Feed handles its own master-detail keyboard-focus signals
    property bool _ownsKeyboardNav: page.wide && innerDetail.depth > 0
    property Item keyboardFocusItem: list
    // row cursor needs focus REASON, not just forceActiveFocus()
    function _focusFeedList() {
        if (list.currentIndex < 0 && list.count > 0) list.currentIndex = 0;
        var it = list.currentItem;
        if (!it) { list.forceActiveFocus(); return; }
        // drop focus first so the key-nav reason lands
        it.focus = false;
        it.forceActiveFocus(Qt.TabFocusReason);
    }
    function _focusFeedDetail() {
        var p = innerDetail.currentPage;
        if (p) (p.keyboardFocusItem ? p.keyboardFocusItem : p).forceActiveFocus();
    }
    Connections {
        target: Nav
        function onFocusMaster() { if (page.visible && page._ownsKeyboardNav) page._focusFeedList(); }
        function onFocusDetail() { if (page.visible && page._ownsKeyboardNav) page._focusFeedDetail(); }
    }

    // which row's detail is open in the split-pane layout
    property string openPermlink: ""

    // routes a card tap to detail panel (wide) or full-screen push (narrow)
    function openDetail(url, props) {
        // push first, avoids racing the onDepthChanged reset below
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

    // independent per-source pagination cursors
    property int  blogOffset: 0
    property bool blogEnded: false
    property int  vidOffset: 0
    property bool vidEnded: false
    // own posts, a third source since follow feed excludes self
    property int  ownOffset: 0
    property bool ownEnded: false
    property var  inflightBlog: null
    property var  inflightVideo: null
    property var  inflightOwn: null

    property bool loading: false
    property string errorMsg: ""
    property int reqEpoch: 0
    // caps auto-continue burst per user-initiated load
    property int autoFetches: 0

    property bool refreshing: false
    // true while rows on screen came from FeedCache
    property bool showingCached: false

    // follows + subscriptions; videos filtered against these client-side
    property var followingSet: ({})
    property var subscribedSet: ({})
    property bool followingLoaded: false
    // next merged batch replaces list instead of appending
    property bool _firstRound: false

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
    // Own posts ride the Blog filter (the video-category ones are dropped by
    // _isVideo, exactly like the following-blog source).
    function _wantOwn()   { return Session.isLoggedIn && page.filterMode !== 2; }

    function _isOwn(author) {
        return Session.isLoggedIn && !!author && author === Session.username;
    }

    // true if user follows nobody and subscribes to nothing
    function _followsNobody() {
        if (!page.followingLoaded) return false;
        for (var k in page.followingSet) return false;
        for (var c in page.subscribedSet) return false;
        return true;
    }

    function _allEnded() {
        return (!_wantBlog()  || page.blogEnded)
            && (!_wantVideo() || page.vidEnded || page._followsNobody())
            && (!_wantOwn()   || page.ownEnded);
    }

    function _params(offset, limit) {
        var p = { limit: limit, offset: offset };
        if (Config.communityId > 0) p.community_id = Config.communityId;
        return p;
    }

    // true if post is a video, used to drop from blog source
    function _isVideo(p) {
        if (p.primaryCategory === "video") return true;
        var c = p.categories;
        return !!(c && c.indexOf && c.indexOf("video") >= 0);
    }

    // publish date as sortable timestamp
    function _ts(row) {
        var t = Date.parse(row.date || "");
        return isNaN(t) ? 0 : t;
    }

    // keyed per filter mode, community and account
    function _cacheKey() {
        return "myfeed:v2:" + page.filterMode + ":" + Config.communityId + ":"
               + (Session.username || "__guest__");
    }

    // merged sources can surface duplicate posts, keep first
    function _dedupe(rows) {
        var seen = {};
        var out = [];
        for (var i = 0; i < rows.length; i++) {
            var k = (rows[i].author || "") + "/" + (rows[i].permlink || "");
            if (seen[k]) continue;
            seen[k] = true;
            out.push(rows[i]);
        }
        return out;
    }

    // true if model already holds this row
    function _inModel(row) {
        for (var i = 0; i < feedModel.count; i++) {
            var m = feedModel.get(i);
            if (m.permlink === row.permlink && m.author === row.author) return true;
        }
        return false;
    }

    function _filterRows(rows) {
        var hidden = HiddenPosts.loadAll();
        var blocked = BlockedUsers.loadAll();
        var out = [];
        for (var i = 0; i < rows.length; i++)
            if (!hidden[rows[i].permlink || ""] && !blocked[rows[i].author || ""])
                out.push(rows[i]);
        return out;
    }

    // overwrite rows in place, avoids delegate thumbnail refade
    function _rowDiffers(cur, next) {
        return cur.permlink !== next.permlink
            || cur.votes !== next.votes
            || cur.comments !== next.comments
            || cur.payout !== next.payout
            || cur.title !== next.title
            || cur.excerpt !== next.excerpt
            || cur.thumbnail !== next.thumbnail;
    }
    function _syncRows(rows) {
        var n = Math.min(rows.length, feedModel.count);
        for (var i = 0; i < n; i++)
            if (_rowDiffers(feedModel.get(i), rows[i]))
                feedModel.set(i, rows[i]);
        for (var j = feedModel.count; j < rows.length; j++)
            feedModel.append(rows[j]);
        while (feedModel.count > rows.length)
            feedModel.remove(feedModel.count - 1);
    }

    // paint last-seen rows so reopening shows content at once
    function _paintCached() {
        var cached = FeedCache.peek(_cacheKey());
        if (!cached) return false;
        _syncRows(_filterRows(cached));
        page.showingCached = feedModel.count > 0;
        return page.showingCached;
    }

    // pages to fill a screenful, capped
    function _maybeAutoContinue() {
        if (!page._allEnded() && feedModel.count < Config.pageSize && page.autoFetches < 6) {
            page.autoFetches++;
            page.loadMore();
        }
        // atYEnd is stale until relayout, recheck on a timer
        endRecheck.restart();
    }

    Timer {
        id: endRecheck
        interval: 120
        repeat: false
        onTriggered: if (!page.loading && !page._allEnded() && page.errorMsg === "" && list.atYEnd) {
                         page.autoFetches = 0;   // a user-position continue is a fresh burst
                         page.loadMore();
                     }
    }

    // fetches next page from all wanted sources, merges and sorts
    function loadMore() {
        if (page.loading || page._allEnded()) return;
        page.loading = true;
        page.errorMsg = "";
        var epoch = page.reqEpoch;
        var blogRows = [];
        var vidRows = [];
        var ownRows = [];
        var pending = 0;
        var lastErr = null;

        function finish() {
            if (epoch !== page.reqEpoch) return;
            page.loading = false;
            page.refreshing = false;
            // error only if this round produced nothing and screen is empty
            if (lastErr && feedModel.count === 0
                    && blogRows.length === 0 && vidRows.length === 0
                    && ownRows.length === 0) {
                page.errorMsg = lastErr.message || Lang.tr("Something went wrong");
                return;
            }
            var batch = blogRows.concat(vidRows).concat(ownRows);
            batch.sort(function (a, b) { return page._ts(b) - page._ts(a); });
            var rows = page._dedupe(page._filterRows(batch));
            if (page._firstRound) {
                // first merged batch replaces list in place
                page._syncRows(rows);
                page._firstRound = false;
                page.showingCached = false;
                FeedCache.put(page._cacheKey(), rows);
            } else {
                for (var i = 0; i < rows.length; i++)
                    if (!page._inModel(rows[i]))
                        feedModel.append(rows[i]);
            }
            page._maybeAutoContinue();
        }

        if (page._wantBlog() && !page.blogEnded) {
            pending++;
            // over-fetch since videos get filtered out
            var blogLimit = Config.pageSize * 2;
            page.inflightBlog = PostService.listFeedMixed(Config.baseUrl,
                page._params(page.blogOffset, blogLimit), Session.token,
                function (result, rawCount) {
                    // page can be destroyed with request in flight
                    if (!page || epoch !== page.reqEpoch) return;
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
                    if (!page || epoch !== page.reqEpoch) return;
                    page.inflightBlog = null;
                    lastErr = err;
                    if (--pending === 0) finish();
                });
        }

        // skip request if nothing followed
        if (page._wantVideo() && !page.vidEnded && !page._followsNobody()) {
            pending++;
            var vidLimit = Config.pageSize;
            page.inflightVideo = VideoService.listVideos(Config.baseUrl,
                page._params(page.vidOffset, vidLimit), Session.token,
                function (result, rawCount) {
                    if (!page || epoch !== page.reqEpoch) return;
                    page.inflightVideo = null;
                    for (var i = 0; i < result.length; i++) {
                        var v = result[i];
                        // keep followed authors, subscribed communities, own uploads
                        if (!page._isOwn(v.author)
                                && !page.followingSet[v.author || ""]
                                && !page.subscribedSet[String(v.communityId || "")]) continue;
                        v._kind = "video";
                        vidRows.push(v);
                    }
                    page.vidOffset += rawCount;
                    if (rawCount < vidLimit) page.vidEnded = true;
                    if (--pending === 0) finish();
                },
                function (err) {
                    if (!page || epoch !== page.reqEpoch) return;
                    page.inflightVideo = null;
                    lastErr = err;
                    if (--pending === 0) finish();
                });
        }

        // Your own posts: the follow-keyed feed can never return them.
        if (page._wantOwn() && !page.ownEnded) {
            pending++;
            var ownLimit = Config.pageSize;
            page.inflightOwn = PostService.listByAuthor(Config.baseUrl, Session.username,
                { limit: ownLimit, offset: page.ownOffset }, Session.token,
                function (result, rawCount) {
                    if (!page || epoch !== page.reqEpoch) return;
                    page.inflightOwn = null;
                    for (var i = 0; i < result.length; i++) {
                        var o = result[i];
                        if (page._isVideo(o)) continue;   // videos come from the video source
                        o._kind = "blog";
                        ownRows.push(o);
                    }
                    page.ownOffset += rawCount;
                    if (rawCount < ownLimit) page.ownEnded = true;
                    if (--pending === 0) finish();
                },
                function (err) {
                    if (!page || epoch !== page.reqEpoch) return;
                    page.inflightOwn = null;
                    lastErr = err;
                    if (--pending === 0) finish();
                });
        }

        if (pending === 0) { page.loading = false; page.refreshing = false; }
    }

    function _abortInflight() {
        if (page.inflightBlog)  { page.inflightBlog.abort();  page.inflightBlog = null; }
        if (page.inflightVideo) { page.inflightVideo.abort(); page.inflightVideo = null; }
        if (page.inflightOwn)   { page.inflightOwn.abort();   page.inflightOwn = null; }
    }

    function _resetCursors() {
        page.blogOffset = 0; page.blogEnded = false;
        page.vidOffset = 0;  page.vidEnded = false;
        page.ownOffset = 0;  page.ownEnded = false;
        page.autoFetches = 0;
        page.loading = false;
        page.errorMsg = "";
    }

    // resolve follows + subscriptions once per session before first load
    function _withFollowing(next) {
        if (page.followingLoaded || !Session.isLoggedIn) { next(); return; }
        var pending = 2;
        // guard against page destroyed while in flight
        function done() { if (!page) return; if (--pending === 0) { page.followingLoaded = true; next(); } }
        FollowService.listAllFollowings(Config.baseUrl, Session.token,
            function (map) { if (page) page.followingSet = map; done(); }, done);
        SubscriberService.fetchSubscribed(Config.baseUrl, Session.token,
            function (map) { if (page) page.subscribedSet = map; done(); }, done);
    }

    function reload() {
        page.reqEpoch++;
        page._abortInflight();
        page._resetCursors();
        page.showingCached = false;
        page._firstRound = true;
        // wipe only if nothing cached can stand in
        if (!_paintCached()) feedModel.clear();
        // reset scroll offset explicitly
        list.positionViewAtBeginning();
        var epoch = page.reqEpoch;
        page.loading = true;   // hold the spinner across the follow-list fetch
        _withFollowing(function () {
            if (epoch !== page.reqEpoch) return;
            page.loading = false;
            // nothing left to fetch would strand cache-painted rows
            if (page._allEnded()) {
                feedModel.clear();
                FeedCache.remove(page._cacheKey());
                page.showingCached = false;
                page._firstRound = false;
                return;
            }
            loadMore();
        });
    }

    function refresh() {
        if (page.refreshing) return;
        page.refreshing = true;
        page.reqEpoch++;
        page._abortInflight();
        page._resetCursors();
        // first new batch replaces rows in place
        page._firstRound = true;
        // re-fetch follow list too, stale set keeps new videos out
        page.followingLoaded = false;
        var epoch = page.reqEpoch;
        _withFollowing(function () {
            if (epoch !== page.reqEpoch) return;
            loadMore();
        });
    }

    Component.onCompleted: {
        page.reload();
        if (visible) list.forceActiveFocus();
    }
    // list takes arrow-key focus whenever page is shown
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
        // wide: left side-list; narrow: centered reading column
        anchors { top: topBar.bottom; bottom: parent.bottom }
        width: page.wide ? page.listPaneW : Math.min(parent.width, page.maxContentWidth)
        x: page.wide ? 0 : Math.max(0, (parent.width - width) / 2)
        clip: true
        // right arrow steps into reading pane
        Keys.onRightPressed: Nav.focusDetail()
        model: feedModel
        cacheBuffer: units.gu(12)
        // uses Lomiri ListItem's own key-nav frame, no custom highlight

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
            // dark-greys the row whose article is open (wide layout only)
            color: (page.wide && page.openPermlink !== "" && postData && postData.permlink === page.openPermlink)
                ? Style.iconBackground : Style.surface

            // keyboard/whole-row activation, mirrors NewsPage
            onClicked: {
                var p = feedModel.get(index)
                if (!p) return
                // pointer clicks don't move currentIndex
                list.currentIndex = index
                if (p._kind === "video")
                    page.openDetail(Qt.resolvedUrl("VideoDetailPage.qml"), { video: p })
                else
                    page.openDetail(Qt.resolvedUrl("PostDetailPage.qml"),
                        { author: p.author, permlink: p.permlink, title: p.title })
            }

            // opens Hide/Report/Block sheet
            onPressAndHold: {
                var p = feedModel.get(index)
                if (p) PostActions.open(p, p._kind === "video" ? "video" : "blog")
            }

            // leading = destructive, trailing = confirming
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
                        iconName: "view-off"
                        text: Lang.tr("Hide")
                        onTriggered: {
                            var p = feedModel.get(index)
                            if (p) {
                                // persist so it stays hidden across restarts
                                HiddenPosts.hide(p.permlink || "")
                                PostActions.hideRequested(p.author, p.permlink)
                            }
                        }
                    }
                ]
            }

            trailingActions: ListItemActions {
                delegate: Item {
                    width: units.gu(7)
                    height: parent ? parent.height : units.gu(6)
                    // highlights follow action when already following
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

        // Prefetch ~2 screens early (see NewsPage) — atYEnd stays as fallback.
        onContentYChanged: {
            if (!page.loading && !page._allEnded() && page.errorMsg === ""
                    && contentHeight > height
                    && contentY + height >= contentHeight - height * 2) {
                page.autoFetches = 0;   // user-scroll driven, same as atYEnd
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
    // empty feed = follow suggestions
    FeedEmptyState {
        anchors.fill: list
        visible: !page.loading && page.errorMsg === "" && feedModel.count === 0
                 && Session.isLoggedIn
        // coalesce follow bursts into one refetch
        onFollowed: emptyStateRefetch.restart()
        onWritePostRequested: {
            // My Feed spans every community, so there's no active source to post
            // into — the composer asks for the platform itself.
            var ed = page.pageStack.push(Qt.resolvedUrl("CreatePostPage.qml"), { pickPlatform: true });
            if (ed && ed.saved) ed.saved.connect(function () { page.refresh(); });
        }
    }
    Timer {
        id: emptyStateRefetch
        interval: 700
        repeat: false
        onTriggered: page.refresh()
    }
    EmptyState {
        anchors.fill: list
        visible: !page.loading && page.errorMsg === "" && feedModel.count === 0
                 && !Session.isLoggedIn
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
