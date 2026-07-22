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

    // cap + center instead of fixed-cell GridView
    readonly property real maxContentWidth: units.gu(60)

    property int offset: 0
    property bool loading: false
    property bool endReached: false
    property string errorMsg: ""
    // bumped on reload to drop stale responses
    property int reqEpoch: 0
    property var inflight: null
    property var reels: []
    // rows on screen came from FeedCache
    property bool showingCached: false
    // first page shares reel shelf + list; deeper pages use pageSize
    readonly property int initialLimit: 30
    readonly property bool hasReels: reels && reels.length > 0
    readonly property int reelsInsertIndex: feedModel.count > 1 ? 1 : 0
    // open detail row, for split-pane highlight
    property string openPermlink: ""

    // zero-height, global AppHeader is the real top bar
    header: Item { height: 0 }

    ListModel { id: feedModel; dynamicRoles: true }

    // reload on community change
    Connections {
        target: Config
        function onCommunityIdChanged() { page.reload(); }
    }

    // clear highlighted row when returning from detail pane
    Connections {
        target: page.pageStack
        ignoreUnknownSignals: true
        function onCurrentPageChanged() {
            if (page.pageStack.currentPage === page) page.openPermlink = "";
        }
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
        offset = 0;
        endReached = false;
        loading = false;
        // clear refreshing to avoid it sticking true
        refreshing = false;
        errorMsg = "";
        page.showingCached = false;
        // only wipe when nothing cached, else list flashes empty
        if (!_paintCached()) { reels = []; feedModel.clear(); }
        // reset scroll offset explicitly (see NewsPage)
        list.positionViewAtBeginning();
        _fetchInitial(false);
    }

    // paint last-seen rows so relaunch shows videos at once
    function _paintCached() {
        var cached = FeedCache.peek(FeedCache.videoKey(Config.communityId));
        if (!cached) return false;
        _applyRows(cached, -1);
        page.showingCached = feedModel.count > 0;
        return page.showingCached;
    }

    // overwrite rows in place, avoids clear()+append flash
    function _rowDiffers(cur, next) {
        return cur.permlink !== next.permlink
            || cur.votes !== next.votes
            || cur.comments !== next.comments;
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

    // one response drives list + reel shelf
    function _applyRows(result, rawCount) {
        var hidden = HiddenPosts.loadAll();
        var blocked = BlockedUsers.loadAll();
        var rows = [];
        var out = [];
        var seen = {};
        for (var i = 0; i < result.length; i++) {
            var v = result[i];
            if (hidden[v.permlink || ""] || blocked[v.author || ""]) continue;
            rows.push(v);
            // reel shelf: Serey-hosted, playable, deduped, capped at 12
            if (out.length < 12 && v.platform === "SEREY" && (v.videoLink || "").length > 0
                    && !seen[v.permlink || ""]) {
                seen[v.permlink || ""] = true;
                out.push(v);
            }
        }
        _syncRows(rows);
        page.reels = out;
        if (rawCount >= 0) {
            page.offset = rawCount;
            // compare against what we asked for, not pageSize
            page.endReached = rawCount < page.initialLimit;
        }
    }

    function _fetchInitial(isRefresh) {
        var epoch = page.reqEpoch;
        if (!isRefresh) { page.loading = true; page.errorMsg = ""; }
        var params = { limit: page.initialLimit, offset: 0 };
        if (Config.communityId > 0)
            params.community_id = Config.communityId;
        else
            params.exclude_home = 1;   // Global feed hides the Cambodia community + children
        // via FeedCache: reuses Main.qml's startup prefetch
        inflight = FeedCache.request(FeedCache.videoKey(Config.communityId),
            function (ok, err) { return VideoService.listVideos(Config.baseUrl, params, Session.token, ok, err); },
            function (result, rawCount) {
                if (epoch !== page.reqEpoch) return;   // stale response — ignore
                inflight = null;
                page.loading = false;
                page.refreshing = false;
                page.showingCached = false;
                page._applyRows(result, rawCount);
                if (!page.endReached && feedModel.count < Config.pageSize) page.loadMore();
                // deferred atYEnd recheck (see NewsPage)
                endRecheck.restart();
            },
            function (err) {
                if (epoch !== page.reqEpoch) return;
                inflight = null;
                page.loading = false;
                page.refreshing = false;
                // keep cached rows on failure
                if (feedModel.count === 0) page.errorMsg = err.message;
            });
    }

    // re-fetches page one, keeps rows until new ones arrive
    property bool refreshing: false
    function refresh() {
        if (page.refreshing) return;
        page.refreshing = true;
        page.reqEpoch++;
        if (inflight) { inflight.abort(); inflight = null; }
        _fetchInitial(true);
    }

    function loadMore() {
        if (loading || endReached) return;
        // page 0 is the shared list+reels fetch
        if (page.offset === 0) { _fetchInitial(false); return; }
        loading = true;
        errorMsg = "";
        var epoch = page.reqEpoch;
        var params = { limit: Config.pageSize, offset: page.offset };
        if (Config.communityId > 0)
            params.community_id = Config.communityId;
        else
            params.exclude_home = 1;   // Global feed hides the Cambodia community + children
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
                // keep paging if filtered below a screenful
                if (!page.endReached && feedModel.count < Config.pageSize) page.loadMore();
                endRecheck.restart();   // user may sit at the end already (see _fetchInitial)
            },
            function (err) {
                if (epoch !== page.reqEpoch) return;
                inflight = null;
                loading = false;
                page.errorMsg = err.message;
            });
    }

    // post-layout atYEnd recheck (see NewsPage)
    Timer {
        id: endRecheck
        interval: 120
        repeat: false
        onTriggered: if (!page.loading && !page.endReached && page.errorMsg === "" && list.atYEnd)
                         page.loadMore()
    }

    Component.onCompleted: {
        _paintCached();
        _fetchInitial(false);
        if (visible) list.forceActiveFocus();
    }
    // list takes arrow-key focus on (re)show
    onVisibleChanged: if (visible) {
        list.kbEngaged = false;
        // clear stale scope focus from a previous keyboard session
        if (list.currentItem) list.currentItem.focus = false;
        list.forceActiveFocus();
    }

    // owns arrow-key focus for master-detail nav
    property Item keyboardFocusItem: list

    // cursor is VideoCard's own ring, revealed once kbEngaged (see NewsPage)
    function focusListKeyNav() {
        if (list.currentIndex < 0 && list.count > 0) list.currentIndex = 0;
        list.kbEngaged = true;
        var w = list.currentItem;
        if (!w) { list.forceActiveFocus(); return; }
        if (w.rowCard) w.rowCard.forceActiveFocus();
        else w.forceActiveFocus();
    }

    ListView {
        id: list
        anchors { top: parent.top; bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
        width: Math.min(parent.width, page.maxContentWidth)
        clip: true
        model: feedModel
        cacheBuffer: units.gu(16)
        // gates focus forwarding so auto-focus doesn't paint a ring for touch
        property bool kbEngaged: false
        Keys.onPressed: {
            if (!list.kbEngaged) {
                list.kbEngaged = true;
                if (list.currentItem) list.currentItem.forceActiveFocus();
                if (event.key === Qt.Key_Down) { event.accepted = true; return; }
            }
        }
        // Right steps into detail pane (split windows)
        Keys.onRightPressed: Nav.focusDetail()
        // Left steps out to tab nav
        Keys.onLeftPressed: Nav.focusNav()

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

        // ListItem for swipe actions; tap opens detail via VideoCard.onClicked
        delegate: Item {
            id: rowWrap
            width: list.width
            readonly property bool showReelShelf: page.hasReels && index === page.reelsInsertIndex
            height: (showReelShelf ? reelsShelf.implicitHeight : 0) + videoRow.height
            // lets focusListKeyNav() reach the real focus owner
            property alias rowCard: card

            // hand focus to VideoCard's own ring, gated on kbEngaged
            onActiveFocusChanged: if (activeFocus && list.kbEngaged) card.forceActiveFocus()

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
                // suppress ListItem's own divider (VideoCard draws its own)
                divider.visible: false
                // highlight row open in detail pane (wide layout)
                color: (Config.wideMode && page.openPermlink !== "" && model.permlink === page.openPermlink)
                    ? Style.iconBackground : Style.surface

                // touch equivalent of the ••• button
                onPressAndHold: {
                    var vm = feedModel.get(index);
                    if (vm) PostActions.open(vm, "video");
                }

                // HIG polarity: leading = negative, trailing = positive
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
                                var vm = feedModel.get(index);
                                if (vm) {
                                    // persist so it stays hidden across restarts
                                    HiddenPosts.hide(vm.permlink || "");
                                    PostActions.hideRequested(vm.author, vm.permlink);
                                }
                            }
                        }
                    ]
                }
                trailingActions: ListItemActions {
                    delegate: Item {
                        width: units.gu(7)
                        height: parent ? parent.height : units.gu(6)
                        // reflects already-following on the Follow action
                        readonly property bool isFollowAction: action.iconName === "contact"
                        readonly property var _rowVideo: isFollowAction ? feedModel.get(index) : null
                        Icon {
                            anchors.centerIn: parent
                            width: units.gu(2.5); height: width
                            name: action.iconName
                            color: (parent.isFollowAction && parent._rowVideo && FollowStore.isFollowing(parent._rowVideo.author))
                                ? Style.brand : Style.textPrimary
                        }
                    }
                    actions: [
                        Action {
                            iconName: "contact"
                            text: Lang.tr("Follow")
                            onTriggered: {
                                var vm = feedModel.get(index);
                                if (!vm || !vm.author || vm.author === Session.username) return;
                                if (!Session.isLoggedIn) { Toast.error(Lang.tr("Please log in first.")); return; }
                                var now = FollowStore.toggle(Config.baseUrl, vm.author, Session.token);
                                Toast.show(now ? Lang.tr("Following") : Lang.tr("Unfollowed"));
                            }
                        },
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
                    onClicked: {
                        // push first, avoids race with the depth-0 reset
                        var v = feedModel.get(index);
                        // pointer clicks don't move currentIndex
                        list.currentIndex = index;
                        page.pageStack.push(Qt.resolvedUrl("VideoDetailPage.qml"), { video: v });
                        page.openPermlink = v ? v.permlink : "";
                    }
                    onAuthorClicked: page.pageStack.push(Qt.resolvedUrl("ProfileViewPage.qml"),
                        { username: feedModel.get(index).author })
                    onMoreClicked: PostActions.open(feedModel.get(index), "video")
                }
            }
        }

        // constant height, avoids a contentHeight binding loop
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

        // Prefetch ~2 screens early (see NewsPage) — atYEnd stays as fallback.
        onContentYChanged: {
            if (!page.loading && !page.endReached
                    && contentHeight > height
                    && contentY + height >= contentHeight - height * 2)
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

    // upload lives in the global header action now
}
