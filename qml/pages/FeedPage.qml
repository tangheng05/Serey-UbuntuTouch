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

    function feedFn() {
        if (feedIndex === 1) return VideoService.listVideos;
        return PostService.listFeedMixed;
    }

    function reload() {
        page.reqEpoch++;
        if (inflight) { inflight.abort(); inflight = null; }
        offset = 0;
        endReached = false;
        loading = false;
        errorMsg = "";
        feedModel.clear();
        loadMore();
    }

    property bool refreshing: false
    function refresh() {
        if (page.refreshing) return;
        page.refreshing = true;
        page.reqEpoch++;
        if (inflight) { inflight.abort(); inflight = null; }
        var epoch = page.reqEpoch;
        var params = { limit: Config.pageSize, offset: 0 };
        if (Config.communityId > 0)
            params.community_id = Config.communityId;
        inflight = feedFn()(Config.baseUrl, params, Session.token,
            function (result, rawCount) {
                if (epoch !== page.reqEpoch) return;
                inflight = null;
                page.refreshing = false;
                page.loading = false;
                feedModel.clear();
                var hidden = HiddenPosts.loadAll();
                var blocked = BlockedUsers.loadAll();
                for (var i = 0; i < result.length; i++)
                    if (!hidden[result[i].permlink || ""] && !blocked[result[i].author || ""])
                        feedModel.append(result[i]);
                page.offset = rawCount;
                page.endReached = rawCount < Config.pageSize;
                // A page can be mostly/entirely filtered out (hidden/blocked); keep
                // paging until there's a screenful or the server runs out, else the
                // feed stalls or looks empty despite more content on later pages.
                if (!page.endReached && feedModel.count < Config.pageSize) page.loadMore();
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
        var params = { limit: Config.pageSize, offset: page.offset };
        if (Config.communityId > 0)
            params.community_id = Config.communityId;
        inflight = feedFn()(Config.baseUrl, params, Session.token,
            function (result, rawCount) {
                if (epoch !== page.reqEpoch) return;
                inflight = null;
                loading = false;
                var hidden = HiddenPosts.loadAll();
                var blocked = BlockedUsers.loadAll();
                for (var i = 0; i < result.length; i++)
                    if (!hidden[result[i].permlink || ""] && !blocked[result[i].author || ""])
                        feedModel.append(result[i]);
                page.offset += rawCount;
                if (rawCount < Config.pageSize) page.endReached = true;
                // Keep paging if this page was filtered below a screenful (see refresh()).
                if (!page.endReached && feedModel.count < Config.pageSize) page.loadMore();
            },
            function (err) {
                if (epoch !== page.reqEpoch) return;
                inflight = null;
                loading = false;
                page.errorMsg = err.message;
            });
    }

    Component.onCompleted: loadMore()

    Connections {
        target: PostActions
        function onHideRequested(author, permlink) {
            for (var i = 0; i < feedModel.count; i++) {
                if (feedModel.get(i).permlink === permlink) {
                    feedModel.remove(i);
                    Toast.show(i18n.tr("Post hidden"));
                    return;
                }
            }
        }
        function onPostDeleted(author, permlink) {
            for (var i = feedModel.count - 1; i >= 0; i--) {
                if (feedModel.get(i).permlink === permlink) feedModel.remove(i);
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

    SectionTabs {
        id: tabs
        anchors { top: topBar.bottom; left: parent.left; right: parent.right }
        model: [i18n.tr("Blog"), i18n.tr("Video")]
        currentIndex: page.feedIndex
        onSelected: {
            page.feedIndex = index;
            page.reload();
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
                text: i18n.tr("Pull to refresh")
                opacity: list.dragging ? 1 : 0
                font.pixelSize: Style.fontSmall
                color: Style.textSecondary
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        delegate: Loader {
            width: list.width
            property var postData: feedModel.get(index)

            sourceComponent: page.feedIndex === 1 ? videoDelegate : blogDelegate

            Component {
                id: blogDelegate
                PostCard {
                    width: parent ? parent.width : 0
                    post: postData
                    onClicked: page.pageStack.push(Qt.resolvedUrl("PostDetailPage.qml"),
                        { author: postData.author, permlink: postData.permlink, title: postData.title })
                    onAuthorClicked: page.pageStack.push(Qt.resolvedUrl("ProfileViewPage.qml"),
                        { username: postData.author })
                    onRequireLogin: page.pageStack.push(Qt.resolvedUrl("LoginPage.qml"))
                    onMoreClicked: PostActions.open(postData, "blog")
                }
            }

            Component {
                id: videoDelegate
                VideoCard {
                    width: parent ? parent.width : 0
                    video: postData
                    onClicked: page.pageStack.push(Qt.resolvedUrl("VideoDetailPage.qml"),
                        { video: postData })
                    onAuthorClicked: page.pageStack.push(Qt.resolvedUrl("ProfileViewPage.qml"),
                        { username: postData.author })
                    onMoreClicked: PostActions.open(postData, "video")
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
            if (atYEnd && !page.loading && !page.endReached)
                page.loadMore();
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
        message: i18n.tr("Follow people to see their posts here")
    }
}
