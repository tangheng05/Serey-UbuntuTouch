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
    property var reels: []
    // True while the rows on screen came from FeedCache rather than the network.
    property bool showingCached: false
    // The first page is fetched at this depth so the reel shelf (<=12 rows) and
    // the list can share one response. Deeper pages go back to Config.pageSize.
    readonly property int initialLimit: 30
    readonly property bool hasReels: reels && reels.length > 0
    readonly property int reelsInsertIndex: feedModel.count > 1 ? 1 : 0
    // Tracks which row's detail is open in the split-pane (wide) layout so the master list can highlight it.
    property string openPermlink: ""

    // Zero-height header keeps the Page off Lomiri's deprecated Page.head path; the global AppHeader is the real top bar.
    header: Item { height: 0 }

    ListModel { id: feedModel; dynamicRoles: true }

    // Source switching lives in the global AppHeader community pill; the list just reloads when Config.sourceIndex changes.
    Connections {
        target: Config
        function onCommunityIdChanged() { page.reload(); }
    }

    // Clears the highlighted row once the detail pane's back button returns here (split/wide layout).
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
        // Also clear refreshing so a reload that interrupts an in-flight pull-to-refresh can't leave it stuck true (disabling refresh).
        refreshing = false;
        errorMsg = "";
        page.showingCached = false;
        // Only wipe when there's nothing cached to put in its place, or the list
        // flashes empty between communities.
        if (!_paintCached()) { reels = []; feedModel.clear(); }
        // In-place sync keeps the scroll offset, so reset it explicitly (see NewsPage).
        list.positionViewAtBeginning();
        _fetchInitial(false);
    }

    // Paint the last-seen rows for this community so a relaunch (or switching
    // back to a community already visited) shows videos at once instead of the
    // skeleton, which is bound to `count === 0`.
    function _paintCached() {
        var cached = FeedCache.peek(FeedCache.videoKey(Config.communityId));
        if (!cached) return false;
        _applyRows(cached, -1);
        page.showingCached = feedModel.count > 0;
        return page.showingCached;
    }

    // Overwrite rows in place by index rather than clear() + append: clearing
    // destroys every delegate and VideoCard's thumbnail fades back in from
    // opacity 0, so an unchanged list visibly flashes. Reusing the row keeps its
    // delegate; only rows whose content changed are rewritten. Same reasoning
    // (and shape) as NewsPage._syncRows.
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

    // One response drives both the list and the reel shelf. They used to be two
    // concurrent requests to the same URL — on Global that is ~2.7s server-side
    // each, so the cold start paid it twice to show the same videos.
    // rawCount < 0 means "painted from cache": leave the paging counters alone so
    // the real response still fetches page 0.
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
            // Reel shelf: Serey-hosted and playable only, deduped, capped at 12.
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
            // Compare against what we actually asked for, not pageSize — asking
            // for 30 and getting 12 means the feed is exhausted, not that a
            // second page is waiting.
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
        // Through FeedCache: stores the rows, and attaches to Main.qml's startup
        // prefetch rather than firing the same 2.7s request again.
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
                // Deferred atYEnd recheck: the user can reach the end while this
                // request was in flight (trigger fired into the loading guard);
                // checked on a timer because atYEnd is stale until relayout (see NewsPage).
                endRecheck.restart();
            },
            function (err) {
                if (epoch !== page.reqEpoch) return;
                inflight = null;
                page.loading = false;
                page.refreshing = false;
                // Keep cached rows on failure; only an empty list becomes an error
                // (it used to fall through to EmptyState's "No videos" instead).
                if (feedModel.count === 0) page.errorMsg = err.message;
            });
    }

    // Pull-to-refresh re-fetches page one but keeps current rows until new ones arrive (no skeleton flash, just the pull spinner).
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
        // Page 0 is the shared list+reels fetch; only deeper pages come through here.
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
                // Keep paging if this page was filtered below a screenful (see refresh()).
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

    // Post-layout atYEnd recheck — same rationale and shape as NewsPage's.
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
    // Keyboard parity on arrival: the list takes arrow-key focus whenever this
    // page is (re)shown, so keyboard nav works before the first click/tap.
    onVisibleChanged: if (visible) {
        list.kbEngaged = false;
        // Clear any card that kept scope focus from a previous keyboard session,
        // else its ring reappears uninvited when the tab regains focus.
        if (list.currentItem) list.currentItem.focus = false;
        list.forceActiveFocus();
    }

    // This list owns arrow-key focus for master-detail keyboard nav (AdaptiveStack.focusMaster targets it).
    property Item keyboardFocusItem: list

    // Same "no cursor on the first Left" problem as NewsPage, different mechanism:
    // the cursor here is the VideoCard's own ring (the delegate root is a wrapper,
    // so Lomiri's key-nav frame never applies), revealed only once kbEngaged flips
    // on a real key press. Returning from the detail IS a keyboard action, so
    // engage it up front and focus the card directly — going via the wrapper would
    // rely on onActiveFocusChanged, which never fires if it already holds focus.
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
        // The keyboard cursor visual here is the VideoCard's own ring (the
        // delegate forwards focus to the card — see rowWrap). kbEngaged gates
        // that forwarding so the page's programmatic auto-focus on show never
        // paints a ring for touch users; the first real key press reveals it
        // on the current card without moving the cursor.
        property bool kbEngaged: false
        Keys.onPressed: {
            if (!list.kbEngaged) {
                list.kbEngaged = true;
                if (list.currentItem) list.currentItem.forceActiveFocus();
                if (event.key === Qt.Key_Down) { event.accepted = true; return; }
            }
        }
        // Right arrow steps into the open detail's pane (split windows).
        Keys.onRightPressed: Nav.focusDetail()
        // Left steps out of the content to the tab nav (rail / bottom bar).
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

        // ListItem for swipe actions (leading = Hide, trailing = Share); tap still opens detail via VideoCard.onClicked either way.
        delegate: Item {
            id: rowWrap
            width: list.width
            readonly property bool showReelShelf: page.hasReels && index === page.reelsInsertIndex
            height: (showReelShelf ? reelsShelf.implicitHeight : 0) + videoRow.height
            // Lets focusListKeyNav() reach the real focus owner: the ListView only
            // hands focus to this wrapper, and the ring lives on the card.
            property alias rowCard: card

            // Arrow-key nav: the ListView focuses its current delegate, which here
            // is this plain wrapper (needed for the Reels shelf), not the Lomiri
            // ListItem — so ListItem's keyNavigationFocus frame never shows (on
            // NewsPage the ListItem IS the delegate root and draws it). Hand the
            // focus to the VideoCard, which draws its own ring and handles
            // Enter (open) / MENU (context menu). Gated on kbEngaged so the
            // page's auto-focus on show doesn't paint the ring uninvited.
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
                // VideoCard draws its own bottom divider — suppress ListItem's to avoid a double hairline.
                divider.visible: false
                // Dark-greys the row whose video is currently open in the detail pane (wide layout only).
                color: (Config.wideMode && page.openPermlink !== "" && model.permlink === page.openPermlink)
                    ? Style.iconBackground : Style.surface

                // Touch equivalent of the removed ••• button — opens the same Hide/Report/Block sheet.
                onPressAndHold: {
                    var vm = feedModel.get(index);
                    if (vm) PostActions.open(vm, "video");
                }

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
                            iconName: "view-off"
                            text: Lang.tr("Hide")
                            onTriggered: {
                                var vm = feedModel.get(index);
                                if (vm) {
                                    // Persist to the local hidden-posts store so it stays hidden across
                                    // restarts, matching the overflow-menu Hide (PostActionSheet).
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
                        // Reflects already-following on the "contact"/Follow action; every other action keeps the neutral color.
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
                        // Push first: swapping the detail pane transiently drops the stack to depth 0,
                        // which would otherwise race with — and clear — this via the currentPageChanged reset below.
                        var v = feedModel.get(index);
                        // Pointer clicks don't move currentIndex, so the key-nav cursor would
                        // sit at the top when Left brings focus back from the detail.
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
