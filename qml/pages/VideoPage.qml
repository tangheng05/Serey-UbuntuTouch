import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/VideoService.js" as VideoService
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
    property var reelsInflight: null
    property var reels: []
    readonly property bool hasReels: reels && reels.length > 0
    readonly property int reelsInsertIndex: feedModel.count > 1 ? 1 : 0

    // Zero-height header keeps the Page off Lomiri's deprecated Page.head path; the global AppHeader is the real top bar.
    header: Item { height: 0 }

    ListModel { id: feedModel; dynamicRoles: true }

    // Source switching lives in the global AppHeader community pill; the list just reloads when Config.sourceIndex changes.
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
                    Toast.show(Lang.tr("Post hidden"));
                    return;
                }
            }
        }
        function onPostDeleted(author, permlink) {
            for (var i = feedModel.count - 1; i >= 0; i--) {
                if (feedModel.get(i).permlink === permlink) feedModel.remove(i);
            }
        }
        function onPostUpdated(author, permlink, title, body) {
            for (var i = 0; i < feedModel.count; i++) {
                if (feedModel.get(i).permlink === permlink) {
                    feedModel.setProperty(i, "title", title);
                    feedModel.setProperty(i, "body", body);
                    break;
                }
            }
        }
        function onUserBlocked(username) {
            for (var i = feedModel.count - 1; i >= 0; i--) {
                if (feedModel.get(i).author === username) feedModel.remove(i);
            }
        }
        function onUserUnblocked(username) { page.reload(); }
    }

    function reload() {
        page.reqEpoch++;
        if (inflight) { inflight.abort(); inflight = null; }
        if (reelsInflight) { reelsInflight.abort(); reelsInflight = null; }
        offset = 0;
        endReached = false;
        loading = false;
        // Also clear refreshing so a reload that interrupts an in-flight pull-to-refresh can't leave it stuck true (disabling refresh).
        refreshing = false;
        errorMsg = "";
        reels = [];
        feedModel.clear();
        loadReels();
        loadMore();
    }

    // Pull-to-refresh re-fetches page one but keeps current rows until new ones arrive (no skeleton flash, just the pull spinner).
    property bool refreshing: false
    function refresh() {
        if (page.refreshing) return;
        page.refreshing = true;
        page.reqEpoch++;
        if (inflight) { inflight.abort(); inflight = null; }
        if (reelsInflight) { reelsInflight.abort(); reelsInflight = null; }
        loadReels();
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
                var hidden = HiddenPosts.loadAll();
                var blocked = BlockedUsers.loadAll();
                for (var i = 0; i < result.length; i++)
                    if (!hidden[result[i].permlink || ""] && !blocked[result[i].author || ""])
                        feedModel.append(result[i]);
                page.offset = rawCount;
                page.endReached = rawCount < Config.pageSize;
                // Keep paging if filtering left less than a screenful
                if (!page.endReached && feedModel.count < Config.pageSize) page.loadMore();
            },
            function (err) {
                if (epoch !== page.reqEpoch) return;
                inflight = null;
                page.refreshing = false;
                // Must also clear loading — an aborted in-flight loadMore's own callback early-returns and would leave the skeleton stuck otherwise.
                page.loading = false;
            });
    }

    function loadReels() {
        var epoch = page.reqEpoch;
        var params = { limit: 30, offset: 0 };
        if (Config.communityId > 0)
            params.community_id = Config.communityId;
        reelsInflight = VideoService.listVideos(Config.baseUrl, params, Session.token,
            function (result) {
                if (epoch !== page.reqEpoch) return;
                reelsInflight = null;
                var hidden = HiddenPosts.loadAll();
                var blocked = BlockedUsers.loadAll();
                var out = [];
                var seen = {};
                for (var i = 0; i < result.length; i++) {
                    var v = result[i];
                    if (v.platform !== "SEREY") continue;
                    if (!(v.videoLink || "").length) continue;
                    if (hidden[v.permlink || ""] || blocked[v.author || ""]) continue;
                    if (seen[v.permlink || ""]) continue;
                    seen[v.permlink || ""] = true;
                    out.push(v);
                    if (out.length >= 12) break;
                }
                page.reels = out;
            },
            function (err) {
                if (epoch !== page.reqEpoch) return;
                reelsInflight = null;
                page.reels = [];
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

    Component.onCompleted: {
        loadReels();
        loadMore();
    }

    ListView {
        id: list
        anchors { top: parent.top; bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
        width: Math.min(parent.width, page.maxContentWidth)
        clip: true
        model: feedModel
        cacheBuffer: units.gu(16)

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

        header: Item {
            width: list.width
            height: headerLabel.height + Style.spacingM + Style.spacingS
            Label {
                id: headerLabel
                x: Style.spacingM
                y: Style.spacingM
                text: Lang.tr("Latest Videos")
                font.pixelSize: Style.fontMedium
                font.weight: Font.DemiBold
                color: Style.textPrimary
            }

        }

        // ListItem for swipe actions (leading = Hide, trailing = Share); tap still opens detail via VideoCard.onClicked either way.
        delegate: Item {
            id: rowWrap
            width: list.width
            readonly property bool showReelShelf: page.hasReels && index === page.reelsInsertIndex
            height: (showReelShelf ? reelsShelf.implicitHeight : 0) + videoRow.height

            Item {
                id: reelsShelf
                visible: rowWrap.showReelShelf
                width: parent.width
                readonly property int reelsCount: page.reels.length
                readonly property int reelsColumns: reelsCount <= 1 ? 1 : 2
                readonly property int reelsRows: reelsCount <= 2 ? 1 : 2
                implicitHeight: reelsHeader.height + reelsGrid.height + Style.spacingS + Style.spacingM

                Item {
                    id: reelsHeader
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        topMargin: Style.spacingXs
                        leftMargin: Style.spacingM
                        rightMargin: Style.spacingM
                    }
                    height: units.gu(3.2)

                    Row {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        spacing: Style.spacingS
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: units.gu(2.2); height: width
                            name: "media-playback-start"
                            color: Style.brand
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Lang.tr("Reels")
                            font.pixelSize: Style.fontRegular
                            font.weight: Font.DemiBold
                            color: Style.textPrimary
                        }
                    }

                }

                GridView {
                    id: reelsGrid
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: reelsHeader.bottom
                        topMargin: Style.spacingS
                        leftMargin: Style.spacingM
                        rightMargin: Style.spacingM
                    }
                    height: cellHeight * reelsShelf.reelsRows + (reelsShelf.reelsRows > 1 ? Style.spacingS : 0)
                    clip: true
                    model: page.reels
                    cellWidth: reelsShelf.reelsColumns === 1 ? width : width / 2
                    cellHeight: cellWidth * 1.45
                    flow: GridView.TopToBottom
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: AbstractButton {
                        width: reelsGrid.cellWidth
                        height: reelsGrid.cellHeight
                        onClicked: page.pageStack.push(Qt.resolvedUrl("ReelsPage.qml"), { startIndex: index })
                        readonly property int rowIndex: index % reelsShelf.reelsRows
                        readonly property int colIndex: Math.floor(index / reelsShelf.reelsRows)

                        Rectangle {
                            anchors {
                                fill: parent
                                leftMargin: reelsShelf.reelsColumns > 1 && colIndex > 0 ? Style.spacingS / 2 : 0
                                rightMargin: reelsShelf.reelsColumns > 1 && colIndex < reelsShelf.reelsColumns - 1 ? Style.spacingS / 2 : 0
                                bottomMargin: reelsShelf.reelsRows > 1 && rowIndex < reelsShelf.reelsRows - 1 ? Style.spacingS : 0
                            }
                            radius: Style.thumbRadius
                            color: Style.iconBackground

                            Image {
                                anchors.fill: parent
                                source: modelData.thumbnail || ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: units.gu(36)
                            }

                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: units.gu(7)
                                color: "#99000000"
                            }

                            Label {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    bottom: parent.bottom
                                    margins: Style.spacingS
                                }
                                text: modelData.title || ""
                                color: "white"
                                font.pixelSize: Style.fontSmall
                                font.weight: Font.DemiBold
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            ListItem {
                id: videoRow
                y: rowWrap.showReelShelf ? reelsShelf.implicitHeight : 0
                width: parent.width
                height: card.height
                // VideoCard draws its own bottom divider — suppress ListItem's to avoid a double hairline.
                divider.visible: false

                // HIG polarity: LEADING = negative (red), TRAILING = positive.
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
                                var vm = feedModel.get(index);
                                if (vm) PostActions.hideRequested(vm.author, vm.permlink);
                            }
                        }
                    ]
                }
                trailingActions: ListItemActions {
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
                                var vm = feedModel.get(index);
                                if (vm) Share.open("https://serey.io/video-component/watch?author=" + vm.author + "&permalink=" + vm.permlink);
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
        }

        // Constant-height footer: a conditional height feeds back into contentHeight/atYEnd and trips a "height" binding loop.
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
        message: Lang.tr("No videos to show")
    }

    // Upload lives in the global header action now (gated on the Video tab) — Lomiri uses a header action, not a Material floating button.
}
