import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/VideoService.js" as VideoService

/*
 * Video section: list of videos. Tapping opens VideoDetailPage, passing the
 * already-loaded video view-model (it carries the embed URL).
 */
Page {
    id: page

    property int offset: 0
    property bool loading: false
    property bool endReached: false
    property string errorMsg: ""
    // Request generation: bumped on reload() so a late response from a previous
    // community can't append stale rows into the freshly-cleared model.
    property int reqEpoch: 0
    property var inflight: null

    // Zero-height header keeps the Page off Lomiri's deprecated Page.head path;
    // the global AppHeader is the real top bar.
    header: Item { height: 0 }

    ListModel { id: feedModel; dynamicRoles: true }

    // Source switching lives in the global AppHeader community pill; the list
    // just reloads when Config.sourceIndex changes.
    Connections {
        target: Config
        function onCommunityIdChanged() { page.reload(); }
    }

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
        // Video has no in-app editor, so only delete-prune is handled here.
        function onPostDeleted(author, permlink) {
            for (var i = feedModel.count - 1; i >= 0; i--) {
                if (feedModel.get(i).permlink === permlink) feedModel.remove(i);
            }
        }
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

    // Pull-to-refresh: re-fetch page one but keep current rows until the new
    // ones arrive (no skeleton flash — just the pull spinner).
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
        inflight = VideoService.listVideos(Config.baseUrl, params, Session.token,
            function (result, rawCount) {
                if (epoch !== page.reqEpoch) return;
                inflight = null;
                page.refreshing = false;
                page.loading = false;
                feedModel.clear();
                for (var i = 0; i < result.length; i++)
                    feedModel.append(result[i]);
                page.offset = rawCount;
                page.endReached = rawCount < Config.pageSize;
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
        inflight = VideoService.listVideos(Config.baseUrl, params, Session.token,
            function (result, rawCount) {
                if (epoch !== page.reqEpoch) return;   // stale response — ignore
                inflight = null;
                loading = false;
                for (var i = 0; i < result.length; i++)
                    feedModel.append(result[i]);
                page.offset += rawCount;
                if (rawCount < Config.pageSize) page.endReached = true;
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
        anchors { top: parent.top; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: true
        model: feedModel
        cacheBuffer: units.gu(16)

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

        header: Item {
            width: list.width
            height: headerLabel.height + Style.spacingM + Style.spacingS
            Label {
                id: headerLabel
                x: Style.spacingM
                y: Style.spacingM
                text: i18n.tr("Latest Videos")
                font.pixelSize: Style.fontMedium
                font.weight: Font.DemiBold
                color: Style.textPrimary
            }

            // Reels (short native videos) viewer.
            AbstractButton {
                id: reelsBtn
                anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: headerLabel.verticalCenter }
                width: reelsRow.width + Style.spacingS * 2
                height: units.gu(4)
                onClicked: page.pageStack.push(Qt.resolvedUrl("ReelsPage.qml"))

                Row {
                    id: reelsRow
                    anchors.centerIn: parent
                    spacing: Style.spacingXs
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(2); height: width
                        name: "media-playback-start"
                        color: Style.brand
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: i18n.tr("Reels")
                        font.pixelSize: Style.fontSmall
                        font.weight: Font.DemiBold
                        color: Style.brand
                    }
                }
            }

            // Offline library shortcut.
            AbstractButton {
                anchors { right: reelsBtn.left; rightMargin: Style.spacingM; verticalCenter: headerLabel.verticalCenter }
                width: dlShortcutRow.width + Style.spacingS * 2
                height: units.gu(4)
                onClicked: page.pageStack.push(Qt.resolvedUrl("DownloadsPage.qml"))

                Row {
                    id: dlShortcutRow
                    anchors.centerIn: parent
                    spacing: Style.spacingXs
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(2); height: width
                        name: "save"
                        color: Style.brand
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: i18n.tr("Downloaded")
                        font.pixelSize: Style.fontSmall
                        font.weight: Font.DemiBold
                        color: Style.brand
                    }
                }
            }
        }

        // VideoCard wrapped in a Lomiri ListItem so the row gains native swipe
        // context actions (and the same actions via pointer right-click / keyboard
        // MENU — convergence). Leading = negative (Hide), trailing = positive
        // (Share), mirroring the ••• sheet. Tap still opens the detail through
        // VideoCard.onClicked, so navigation is unchanged even if the swipe
        // gesture is unavailable.
        delegate: ListItem {
            id: videoRow
            width: list.width
            height: card.height
            // VideoCard draws its own bottom divider — suppress ListItem's to
            // avoid a double hairline.
            divider.visible: false

            leadingActions: ListItemActions {
                actions: [
                    Action {
                        iconName: "close"
                        text: i18n.tr("Hide")
                        onTriggered: {
                            var vm = feedModel.get(index);
                            if (vm) PostActions.hideRequested(vm.author, vm.permlink);
                        }
                    }
                ]
            }
            trailingActions: ListItemActions {
                actions: [
                    Action {
                        iconName: "share"
                        text: i18n.tr("Share")
                        onTriggered: {
                            var vm = feedModel.get(index);
                            if (vm) Qt.openUrlExternally("https://serey.io/authors/@" + vm.author + "/" + vm.permlink);
                        }
                    }
                ]
            }

            VideoCard {
                id: card
                width: parent.width
                video: feedModel.get(index)
                onClicked: page.pageStack.push(Qt.resolvedUrl("VideoDetailPage.qml"),
                    { video: feedModel.get(index) })
                onAuthorClicked: page.pageStack.push(Qt.resolvedUrl("ProfileViewPage.qml"),
                    { username: feedModel.get(index).author })
                onMoreClicked: PostActions.open(feedModel.get(index), "video")
            }
        }

        // Constant-height footer: a conditional height feeds back into
        // contentHeight/atYEnd and trips a "height" binding loop.
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
            if (atYEnd && !page.loading && !page.endReached && feedModel.count > 0)
                page.loadMore();
        }
    }

    LoadingState {
        anchors.fill: list
        variant: "video"
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
        iconName: "camcorder"
        message: i18n.tr("No videos to show")
    }

    // Upload lives in the global header action now (see Main.qml, gated on the
    // Video tab) — Lomiri uses a header action, not a Material floating button.
}
