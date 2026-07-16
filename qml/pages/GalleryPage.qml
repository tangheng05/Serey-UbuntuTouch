import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/PostService.js" as PostService
import "../services/HiddenPosts.js" as HiddenPosts
import "../services/BlockedUsers.js" as BlockedUsers

Page {
    id: page

    // Cards need swipe actions, so a fixed-cell GridView won't work — cap + center instead
    readonly property real maxContentWidth: units.gu(60)

    property int offset: 0
    property bool loading: false
    property bool endReached: false
    property string errorMsg: ""
    // Request generation bumped on reload() so a late response from a previous community can't append stale rows into the freshly-cleared model.
    property int reqEpoch: 0
    property var inflight: null

    header: Item { height: 0 }

    ListModel { id: galleryModel; dynamicRoles: true }

    Connections {
        target: Config
        function onSourceIndexChanged() { page.reload(); }
    }

    Connections {
        target: PostActions
        function onHideRequested(author, permlink) {
            for (var i = 0; i < galleryModel.count; i++) {
                if (galleryModel.get(i).permlink === permlink) {
                    galleryModel.remove(i);
                    Toast.show(Lang.tr("Post hidden"));
                    return;
                }
            }
        }
        function onPostDeleted(author, permlink) {
            for (var i = galleryModel.count - 1; i >= 0; i--) {
                if (galleryModel.get(i).permlink === permlink) galleryModel.remove(i);
            }
        }
        function onUserBlocked(username) {
            for (var i = galleryModel.count - 1; i >= 0; i--) {
                if (galleryModel.get(i).author === username) galleryModel.remove(i);
            }
        }
        function onUserUnblocked(username) { page.reload(); }
        function onEditRequested(post) {
            if (!page.visible) return;
            var ed = page.pageStack.push(Qt.resolvedUrl("CreateGalleryPostPage.qml"), { editPost: post });
            if (ed && ed.saved) ed.saved.connect(page.reload);
        }
    }

    function reload() {
        page.reqEpoch++;
        if (inflight) { inflight.abort(); inflight = null; }
        offset = 0;
        endReached = false;
        loading = false;
        errorMsg = "";
        galleryModel.clear();
        loadMore();
    }

    // Pull-to-refresh re-fetches page one but keeps current rows until new ones arrive (no skeleton flash, just the pull spinner).
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
        inflight = PostService.listGallery(Config.baseUrl, params, Session.token,
            function (result, rawCount) {
                if (epoch !== page.reqEpoch) return;
                inflight = null;
                page.refreshing = false;
                page.loading = false;
                galleryModel.clear();
                var hidden = HiddenPosts.loadAll();
                var blocked = BlockedUsers.loadAll();
                for (var i = 0; i < result.length; i++)
                    if (!hidden[result[i].permlink || ""] && !blocked[result[i].author || ""])
                        galleryModel.append(result[i]);
                page.offset = rawCount;
                page.endReached = rawCount < Config.pageSize;
                // Image-only filtering can leave a page thin — keep paging to a screenful
                if (!page.endReached && galleryModel.count < Config.pageSize) page.loadMore();
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
        inflight = PostService.listGallery(Config.baseUrl, params, Session.token,
            function (result, rawCount) {
                if (epoch !== page.reqEpoch) return;   // stale response — ignore
                inflight = null;
                loading = false;
                var hidden = HiddenPosts.loadAll();
                var blocked = BlockedUsers.loadAll();
                for (var i = 0; i < result.length; i++)
                    if (!hidden[result[i].permlink || ""] && !blocked[result[i].author || ""])
                        galleryModel.append(result[i]);
                // Advance by RAW server count (not the image-filtered length) so the next page doesn't re-request already-seen rows.
                page.offset += rawCount;
                if (rawCount < Config.pageSize) page.endReached = true;
                // Keep paging if this page fell below a screenful (see refresh()).
                if (!page.endReached && galleryModel.count < Config.pageSize) page.loadMore();
            },
            function (err) {
                if (epoch !== page.reqEpoch) return;
                inflight = null;
                loading = false;
                page.errorMsg = err.message;
            });
    }

    Component.onCompleted: loadMore()

    ListView {
        id: list
        anchors { top: parent.top; bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
        width: Math.min(parent.width, page.maxContentWidth)
        clip: true
        model: galleryModel
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

        // GalleryCard wrapped in a Lomiri ListItem for native swipe actions (leading = Hide, trailing = Share), mirroring VideoPage.
        delegate: ListItem {
            width: list.width
            height: card.height
            divider.visible: false

            leadingActions: ListItemActions {
                actions: [
                    Action {
                        iconName: "view-off"
                        text: Lang.tr("Hide")
                        onTriggered: {
                            var vm = galleryModel.get(index);
                            if (vm) PostActions.hideRequested(vm.author, vm.permlink);
                        }
                    }
                ]
            }
            trailingActions: ListItemActions {
                actions: [
                    Action {
                        iconName: "share"
                        text: Lang.tr("Share")
                        onTriggered: {
                            var vm = galleryModel.get(index);
                            if (vm) Share.open("https://serey.io/authors/" + vm.author + "/" + vm.permlink);
                        }
                    }
                ]
            }

            GalleryCard {
                id: card
                width: parent.width
                post: galleryModel.get(index)
                onClicked: {
                    var p = galleryModel.get(index);
                    page.pageStack.push(Qt.resolvedUrl("GalleryDetailPage.qml"),
                        { author: p.author, permlink: p.permlink });
                }
                onAuthorClicked: page.pageStack.push(Qt.resolvedUrl("ProfileViewPage.qml"),
                    { username: galleryModel.get(index).author })
                onRequireLogin: page.pageStack.push(Qt.resolvedUrl("LoginPage.qml"))
                onMoreClicked: PostActions.open(galleryModel.get(index), "gallery")
            }
        }

        // Constant-height footer: a conditional height feeds back into contentHeight/atYEnd and trips a "height" binding loop.
        footer: Item {
            width: list.width
            height: units.gu(6)
            ActivityIndicator {
                anchors.centerIn: parent
                running: page.loading && galleryModel.count > 0
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
        variant: "gallery"
        visible: page.loading && galleryModel.count === 0
    }
    ErrorState {
        anchors.fill: list
        visible: page.errorMsg !== "" && galleryModel.count === 0
        message: page.errorMsg
        onRetry: page.reload()
    }
    EmptyState {
        anchors.fill: list
        visible: !page.loading && page.errorMsg === "" && galleryModel.count === 0
        iconName: "image-x-generic-symbolic"
        message: Lang.tr("No gallery posts in %1").arg(Config.communityName)
    }

    // Floating compose button
    AbstractButton {
        visible: Session.isLoggedIn
        anchors {
            right: parent.right
            bottom: parent.bottom
            rightMargin: Style.spacingM
            bottomMargin: Style.spacingM
        }
        width: units.gu(5.5); height: width
        z: 10
        onClicked: {
            var ed = page.pageStack.push(Qt.resolvedUrl("CreateGalleryPostPage.qml"));
            if (ed && ed.saved) ed.saved.connect(page.reload);   // show the new post immediately
        }

        Rectangle {
            anchors.fill: parent
            radius: units.dp(14)
            color: Style.brand
        }
        Icon {
            anchors.centerIn: parent
            width: units.gu(2.5); height: width
            name: "edit"
            color: Style.textOnBrand
        }
    }
}
