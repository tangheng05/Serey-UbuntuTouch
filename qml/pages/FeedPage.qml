import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/PostService.js" as PostService
import "../services/VideoService.js" as VideoService
import "../services/HiddenPosts.js" as HiddenPosts
import "../services/BlockedUsers.js" as BlockedUsers

/*
 * "My Feed" page: posts from followed users + trending, served by the
 * authenticated /list-by-feed-mixed endpoint. Requires login. Tabs switch
 * between Blog, Gallery and Drum feeds.
 */
Page {
    id: page

    property int offset: 0
    property bool loading: false
    property bool endReached: false
    property string errorMsg: ""
    property int feedIndex: 0
    property int reqEpoch: 0
    property var inflight: null
    // Bounds one "fill the screen" burst: how many sequential loadMore() calls the
    // auto-continue may chain, so a video-heavy Blog feed can't spiral into many
    // requests. Reset on every user-initiated load; the rest loads on scroll.
    property int autoFetches: 0
    // Per-tab cache (0 = Blog, 1 = Video): switching tabs restores instantly
    // instead of refetching. rows holds the plain mapped view-models (not the
    // ListModel-wrapped copies), so re-appending them is clean.
    property var tabCache: [
        { rows: [], offset: 0, endReached: false, loaded: false, contentY: 0 },
        { rows: [], offset: 0, endReached: false, loaded: false, contentY: 0 }
    ]
    property real pendingContentY: 0

    header: Item { height: 0 }

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

        Image {
            anchors.centerIn: parent
            width: units.gu(3.5); height: width
            source: Qt.resolvedUrl("../../assets/iconFeed.png")
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }

        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: units.dp(1)
            color: Style.divider
        }
    }

    ListModel { id: feedModel; dynamicRoles: true }

    // Restore a cached tab's scroll position after its rows are re-appended (the
    // ListView needs a frame to lay out before contentY will stick). Best-effort.
    Timer {
        id: restoreScrollTimer
        interval: 16
        repeat: false
        onTriggered: list.contentY = page.pendingContentY
    }

    function feedFn() {
        if (feedIndex === 1) return VideoService.listVideos;
        return PostService.listFeedMixed;
    }

    // The Blog tab draws from list-by-feed-mixed (blog + gallery + video) but must
    // exclude videos — the Video tab owns those. Mirrors the web's
    // categories.includes('video') classification.
    function _isVideo(p) {
        if (p.primaryCategory === "video") return true;
        var c = p.categories;
        return !!(c && c.indexOf && c.indexOf("video") >= 0);
    }
    // Filtering videos out of the mixed feed can empty a page, so over-fetch the
    // Blog tab: one larger round-trip fills the screen instead of several small
    // sequential ones (the auto-continue loadMore below), which is the slow part.
    function feedLimit() {
        return page.feedIndex === 0 ? Config.pageSize * 2 : Config.pageSize;
    }
    // Append server rows minus hidden/blocked (and videos on the Blog tab), and
    // mirror them into the active tab's cache. Loads the hidden/blocked sets once
    // per page, not per row.
    function _appendFiltered(result) {
        var hidden = HiddenPosts.loadAll();
        var blocked = BlockedUsers.loadAll();
        var cacheRows = page.tabCache[page.feedIndex].rows;
        for (var i = 0; i < result.length; i++) {
            var p = result[i];
            if (hidden[p.permlink || ""] || blocked[p.author || ""])
                continue;
            if (page.feedIndex === 0 && _isVideo(p))
                continue;
            feedModel.append(p);
            cacheRows.push(p);
        }
    }
    // After a successful load, mirror the live pagination state into the active
    // tab's cache slot (rows are already appended in _appendFiltered).
    function _syncSlot() {
        var slot = page.tabCache[page.feedIndex];
        slot.offset = page.offset;
        slot.endReached = page.endReached;
        slot.loaded = true;
    }
    // Bounded auto-continue: keep paging to fill a screenful, but cap the chain so
    // a heavily-filtered (video) feed can't fire many sequential requests.
    function _maybeAutoContinue() {
        if (!page.endReached && feedModel.count < Config.pageSize && page.autoFetches < 6) {
            page.autoFetches++;
            page.loadMore();
        }
    }
    // Drop rows matching pred from BOTH tab caches, so a blocked author / deleted
    // post can't resurrect when the other tab is restored.
    function _purgeCache(pred) {
        for (var t = 0; t < page.tabCache.length; t++) {
            var rows = page.tabCache[t].rows;
            for (var i = rows.length - 1; i >= 0; i--)
                if (pred(rows[i])) rows.splice(i, 1);
        }
    }

    function reload() {
        page.reqEpoch++;
        if (inflight) { inflight.abort(); inflight = null; }
        offset = 0;
        endReached = false;
        loading = false;
        errorMsg = "";
        page.autoFetches = 0;
        var slot = page.tabCache[page.feedIndex];
        slot.rows = [];
        slot.offset = 0;
        slot.endReached = false;
        slot.loaded = false;
        slot.contentY = 0;
        feedModel.clear();
        loadMore();
    }

    property bool refreshing: false
    function refresh() {
        if (page.refreshing) return;
        page.refreshing = true;
        page.reqEpoch++;
        if (inflight) { inflight.abort(); inflight = null; }
        page.autoFetches = 0;
        var epoch = page.reqEpoch;
        var limit = page.feedLimit();
        var params = { limit: limit, offset: 0 };
        if (Config.communityId > 0)
            params.community_id = Config.communityId;
        inflight = feedFn()(Config.baseUrl, params, Session.token,
            function (result, rawCount) {
                if (epoch !== page.reqEpoch) return;
                inflight = null;
                page.refreshing = false;
                page.loading = false;
                feedModel.clear();
                page.tabCache[page.feedIndex].rows = [];   // rebuild this tab's cache
                page._appendFiltered(result);
                page.offset = rawCount;
                page.endReached = rawCount < limit;
                page._syncSlot();
                // A page can be mostly/entirely filtered out (hidden/blocked/video);
                // keep paging (bounded) so the feed doesn't look empty despite more
                // content on later pages.
                page._maybeAutoContinue();
            },
            function (err) {
                if (epoch !== page.reqEpoch) return;
                inflight = null;
                page.refreshing = false;
            });
    }

    function loadMore() {
        if (loading || endReached) return;
        loading = true;
        errorMsg = "";
        var epoch = page.reqEpoch;
        var limit = page.feedLimit();
        var params = { limit: limit, offset: page.offset };
        if (Config.communityId > 0)
            params.community_id = Config.communityId;
        inflight = feedFn()(Config.baseUrl, params, Session.token,
            function (result, rawCount) {
                if (epoch !== page.reqEpoch) return;
                inflight = null;
                loading = false;
                page._appendFiltered(result);
                page.offset += rawCount;
                if (rawCount < limit) page.endReached = true;
                page._syncSlot();
                // Keep paging (bounded) if this page was filtered below a screenful.
                page._maybeAutoContinue();
            },
            function (err) {
                if (epoch !== page.reqEpoch) return;
                inflight = null;
                loading = false;
                page.errorMsg = err.message;
            });
    }

    Component.onCompleted: page.reload()

    Connections {
        target: PostActions
        function onHideRequested(author, permlink) {
            for (var i = 0; i < feedModel.count; i++) {
                if (feedModel.get(i).permlink === permlink) {
                    feedModel.remove(i);
                    Toast.show(Lang.tr("Post hidden"));
                    break;
                }
            }
            page._purgeCache(function (r) { return r.permlink === permlink; });
        }
        function onPostDeleted(author, permlink) {
            for (var i = feedModel.count - 1; i >= 0; i--) {
                if (feedModel.get(i).permlink === permlink) feedModel.remove(i);
            }
            page._purgeCache(function (r) { return r.permlink === permlink; });
        }
        function onPostUpdated(author, permlink, title, body) {
            for (var i = 0; i < feedModel.count; i++) {
                if (feedModel.get(i).permlink === permlink) {
                    feedModel.setProperty(i, "title", title);
                    feedModel.setProperty(i, "body", body);
                    break;
                }
            }
            // Update both tab caches too, so restoring a tab shows the new caption.
            for (var t = 0; t < page.tabCache.length; t++) {
                var rows = page.tabCache[t].rows;
                for (var j = 0; j < rows.length; j++) {
                    if (rows[j].permlink === permlink) {
                        rows[j].title = title;
                        rows[j].body = body;
                    }
                }
            }
        }
        function onUserBlocked(username) {
            for (var i = feedModel.count - 1; i >= 0; i--) {
                if (feedModel.get(i).author === username) feedModel.remove(i);
            }
            page._purgeCache(function (r) { return r.author === username; });
        }
        function onUserUnblocked(username) {
            // Unblock brings a user's posts back — invalidate both tab caches so
            // each refetches on its next visit.
            page.tabCache[0].loaded = false; page.tabCache[0].rows = [];
            page.tabCache[1].loaded = false; page.tabCache[1].rows = [];
            page.reload();
        }
        function onEditRequested(post) {
            if (!page.visible) return;
            var ed = page.pageStack.push(Qt.resolvedUrl("CreatePostPage.qml"), { editPost: post });
            if (ed && ed.saved) ed.saved.connect(page.reload);
        }
    }

    SectionTabs {
        id: tabs
        anchors { top: topBar.bottom; left: parent.left; right: parent.right }
        model: [Lang.tr("Blog"), Lang.tr("Video")]
        currentIndex: page.feedIndex
        onSelected: {
            if (index === page.feedIndex) return;
            // Save the outgoing tab's scroll position (rows/pagination are kept in
            // sync by each load), then invalidate its in-flight request.
            page.tabCache[page.feedIndex].contentY = list.contentY;
            page.reqEpoch++;
            if (page.inflight) { page.inflight.abort(); page.inflight = null; }

            page.feedIndex = index;
            page.errorMsg = "";
            page.autoFetches = 0;

            var slot = page.tabCache[index];
            if (slot.loaded) {
                // Restore instantly — no network.
                page.loading = false;
                page.offset = slot.offset;
                page.endReached = slot.endReached;
                feedModel.clear();
                for (var i = 0; i < slot.rows.length; i++)
                    feedModel.append(slot.rows[i]);
                page.pendingContentY = slot.contentY;
                restoreScrollTimer.restart();
            } else {
                page.reload();
            }
        }
    }

    ListView {
        id: list
        anchors { top: tabs.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: true
        model: feedModel
        cacheBuffer: units.gu(12)

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

            leadingActions: ListItemActions {
                delegate: Item {
                    width: units.gu(7)
                    height: parent ? parent.height : units.gu(6)
                    Icon {
                        anchors.centerIn: parent
                        width: units.gu(2.5); height: width
                        name: action.iconName
                        color: "black"
                    }
                }
                actions: [
                    Action {
                        iconName: "share"
                        text: Lang.tr("Share")
                        onTriggered: {
                            var p = feedModel.get(index)
                            if (!p) return
                            if (page.feedIndex === 1)
                                Share.open("https://serey.io/video-component/watch?author=" + p.author + "&permalink=" + p.permlink)
                            else
                                Share.open("https://serey.io/authors/" + p.author + "/" + p.permlink)
                        }
                    }
                ]
            }

            trailingActions: ListItemActions {
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

            Loader {
                id: contentLoader
                width: parent.width
                height: item ? item.implicitHeight : 0
                sourceComponent: page.feedIndex === 1 ? videoDelegate : blogDelegate

                Component {
                    id: blogDelegate
                    PostCard {
                        width: parent ? parent.width : 0
                        post: feedItem.postData
                        onClicked: page.pageStack.push(Qt.resolvedUrl("PostDetailPage.qml"),
                            { author: feedItem.postData.author, permlink: feedItem.postData.permlink, title: feedItem.postData.title })
                        onAuthorClicked: page.pageStack.push(Qt.resolvedUrl("ProfileViewPage.qml"),
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
                        onClicked: page.pageStack.push(Qt.resolvedUrl("VideoDetailPage.qml"),
                            { video: feedItem.postData })
                        onAuthorClicked: page.pageStack.push(Qt.resolvedUrl("ProfileViewPage.qml"),
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
            if (atYEnd && !page.loading && !page.endReached) {
                page.autoFetches = 0;   // fresh burst budget per user scroll
                page.loadMore();
            }
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
}
