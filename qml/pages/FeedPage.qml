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
 * "My Feed" page: content from authors the user follows. Shows a *mixed* feed
 * (blog + video) by default, with a filter strip to narrow to All / Blog / Video.
 * Requires login.
 *
 * Two sources feed the mixed view because they carry different data:
 *   - Blog/gallery posts come from the authenticated /list-by-feed-following
 *     endpoint (mapped as posts).
 *   - Videos come from VideoService — the feed endpoint's video rows lack the
 *     playable fields (videoLink/embedUrl/platform) VideoDetailPage needs, so we
 *     always source videos from the video endpoint and exclude them from the blog
 *     source to avoid duplicates.
 * Each loaded batch is date-sorted and appended; every row is tagged `_kind`
 * ("blog"|"video") so the delegate picks PostCard vs VideoCard.
 */
Page {
    id: page

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
    // Bounds one "fill the screen" burst so a heavily-filtered feed can't spiral
    // into many sequential requests. Reset on every user-initiated load.
    property int autoFetches: 0

    property bool refreshing: false
    // On refresh, keep the old rows on screen until the first new batch arrives
    // (clear then), so there's no skeleton flash — just the pull spinner.
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

        // Filter button: opens the All / Blog / Video menu. Shows the active
        // filter's name (and tints) when narrowed to something other than All.
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

    // A post is a video if its (primary) category says so — used to drop videos
    // from the blog source (they're sourced from the video endpoint instead).
    function _isVideo(p) {
        if (p.primaryCategory === "video") return true;
        var c = p.categories;
        return !!(c && c.indexOf && c.indexOf("video") >= 0);
    }

    // Parse a row's publish date to a sortable timestamp (0 if unparseable), so a
    // mixed batch can be ordered newest-first before it's appended.
    function _ts(row) {
        var t = Date.parse(row.date || "");
        return isNaN(t) ? 0 : t;
    }

    // Bounded auto-continue: keep paging to fill a screenful, but cap the chain so
    // a heavily-filtered feed can't fire many sequential requests.
    function _maybeAutoContinue() {
        if (!page._allEnded() && feedModel.count < Config.pageSize && page.autoFetches < 6) {
            page.autoFetches++;
            page.loadMore();
        }
    }

    // --- Loading -------------------------------------------------------------
    // Fetches the next page from every wanted, not-yet-ended source in parallel,
    // then merges the combined batch (date-sorted, hidden/blocked removed) once
    // all responses are in.
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
            // Over-fetch: videos are filtered out of this source, so a larger
            // round-trip fills the screen instead of many small sequential ones.
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

    Component.onCompleted: page.reload()

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
        anchors { top: topBar.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
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
            readonly property bool isVideo: postData && postData._kind === "video"

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
                            if (p._kind === "video")
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
                sourceComponent: feedItem.isVideo ? videoDelegate : blogDelegate

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
            if (atYEnd && !page.loading && !page._allEnded()) {
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

    // --- Filter dropdown -----------------------------------------------------
    // Only Blog / Video are offered (All is the default, so it needs no button);
    // tapping the active filter again clears back to the mixed All feed.
    Item {
        anchors.fill: parent
        visible: page.filterMenuOpen
        z: 100

        MouseArea { anchors.fill: parent; onClicked: page.filterMenuOpen = false }

        Rectangle {
            // This Item fills the page and topBar is its sibling (not this
            // Rectangle's), so anchoring to topBar.bottom is invalid ("Cannot
            // anchor to an item that isn't a parent or sibling"). Anchor to
            // parent.top instead and offset by topBar.height (an id read is fine).
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
