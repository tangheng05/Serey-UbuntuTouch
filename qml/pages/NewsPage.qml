import QtQuick 2.12
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/PostService.js" as PostService
import "../services/HiddenPosts.js" as HiddenPosts
import "../services/BlockedUsers.js" as BlockedUsers

Page {
    id: page

    property int offset: 0
    property bool loading: false
    property bool endReached: false
    property string errorMsg: ""
    property int feedIndex: 0
    // Tracks which row's detail is open in the split-pane (wide) layout so the master list can highlight it.
    property string openPermlink: ""
    // Request generation bumped on reload() so a late response from a previous community/tab can't append stale rows into the freshly-cleared model.
    property int reqEpoch: 0
    property var inflight: null

    // Cards need swipe actions, so a fixed-cell GridView won't work — cap + center instead
    readonly property real maxContentWidth: units.gu(60)

    // Zero-height header: the global AppHeader provides the top bar, but keeping an explicit header avoids Lomiri's deprecated Page.head path.
    header: Item { height: 0 }

    ListModel { id: feedModel; dynamicRoles: true }

    // Source switching lives in the global AppHeader community pill; the feed just reloads when Config.sourceIndex changes.
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
        function onCommentCountChanged(permlink, count) {
            for (var i = 0; i < feedModel.count; i++) {
                if (feedModel.get(i).permlink === permlink) {
                    feedModel.setProperty(i, "comments", count);
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

    function feedFn() {
        if (feedIndex === 1) return PostService.listNew;
        return PostService.listTrending;
    }

    function reload() {
        page.reqEpoch++;
        if (inflight) { inflight.abort(); inflight = null; }
        offset = 0;
        endReached = false;
        loading = false;
        // Clear too, or an interrupted pull-to-refresh leaves this stuck true
        refreshing = false;
        errorMsg = "";
        feedModel.clear();
        loadMore();
    }

    // Pull-to-refresh re-fetches the first page but keeps current rows on screen until new ones arrive, Facebook-style.
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
                // Keep paging if filtering left less than a screenful, or the feed stalls looking empty despite more content on later pages.
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
        loadMore();
        if (visible) list.forceActiveFocus();
    }
    // Keyboard parity on arrival: the list takes arrow-key focus whenever this
    // page is (re)shown, so keyboard nav works before the first click/tap.
    onVisibleChanged: if (visible) list.forceActiveFocus()

    // After publishing a new post: jump to the Latest tab (newest-first) and
    // reload, so the just-published post appears at the top.
    function showLatest() {
        page.feedIndex = 1;
        page.reload();
    }

    SectionTabs {
        id: tabs
        anchors { top: parent.top; left: parent.left; right: parent.right }
        model: [Lang.tr("Trending"), Lang.tr("Latest")]
        currentIndex: page.feedIndex
        onSelected: {
            page.feedIndex = index;
            page.reload();
            // Lomiri buttons take focus on press, which silently killed the
            // list's arrow keys after a tab click — always hand focus back.
            list.forceActiveFocus();
        }
        // Reset the keyboard cursor when dropping back in from the strip — a
        // stale currentIndex made the first Down appear dead and the second
        // jump far down. -1 so the next Down lands on (and frames) the FIRST card.
        onFocusList: { list.currentIndex = -1; list.forceActiveFocus(); }
    }

    // This list owns arrow-key focus for master-detail keyboard nav (AdaptiveStack.focusMaster targets it).
    property Item keyboardFocusItem: list

    ListView {
        id: list
        anchors { top: tabs.bottom; bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
        width: Math.min(parent.width, page.maxContentWidth)
        clip: true
        model: feedModel
        cacheBuffer: units.gu(12)
        // The keyboard cursor visual is the Lomiri ListItem's own key-navigation
        // frame (drawn only on true key navigation, so nothing shows on the
        // page's programmatic auto-focus). A custom ListView highlight on top
        // of it painted a second ring — don't re-add one.
        // Right arrow steps into the open article's reading pane (split windows).
        Keys.onRightPressed: Nav.focusDetail()
        // Left steps out of the content to the tab nav (rail / bottom bar).
        Keys.onLeftPressed: Nav.focusNav()
        // Up on the very first card climbs into the Trending/Latest strip;
        // anywhere else Up stays unaccepted so the ListView moves the cursor.
        Keys.onUpPressed: {
            if (list.atYBeginning && list.currentIndex <= 0) { tabs.focusCurrent(); event.accepted = true; }
            else event.accepted = false;
        }

        PullToRefresh {
            refreshing: page.refreshing
            onRefresh: page.refresh()
            // Opacity, not visible — PullToRefresh's style imperatively sets `visible` itself, which would clobber a visible binding.
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
            id: newsItem
            width: list.width
            height: card.implicitHeight
            // Dark-greys the row of the article currently open in the detail pane (wide/tablet layout only).
            color: (Config.wideMode && page.openPermlink !== "" && page.openPermlink === model.permlink)
                ? Style.iconBackground : Style.surface

            // Keyboard/whole-row activation: Lomiri ListItem emits clicked() on
            // Enter when focused (and on a tap of any non-interactive area), so
            // opening the post here is what makes Enter work in keyboard nav.
            onClicked: {
                // Push first: swapping the detail pane transiently drops the stack to depth 0,
                // which would otherwise race with — and clear — this via the currentPageChanged reset below.
                var p = feedModel.get(index)
                if (!p) return
                page.pageStack.push(Qt.resolvedUrl("PostDetailPage.qml"),
                    { author: p.author, permlink: p.permlink, title: p.title })
                page.openPermlink = p.permlink
            }

            // Touch equivalent of the removed ••• button — opens the same Hide/Report/Block sheet.
            onPressAndHold: {
                var p = feedModel.get(index)
                if (p) PostActions.open(p, "blog")
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
                            if (p) Share.open("https://serey.io/authors/" + p.author + "/" + p.permlink)
                        }
                    }
                ]
            }

            PostCard {
                id: card
                width: parent.width
                post: feedModel.get(index)
                onClicked: {
                    var p = feedModel.get(index)
                    page.pageStack.push(Qt.resolvedUrl("PostDetailPage.qml"),
                        { author: p.author, permlink: p.permlink, title: p.title })
                    page.openPermlink = p.permlink
                }
                onAuthorClicked: page.pageStack.push(Qt.resolvedUrl("ProfileViewPage.qml"),
                    { username: feedModel.get(index).author })
                onRequireLogin: page.pageStack.push(Qt.resolvedUrl("LoginPage.qml"))
                onMoreClicked: PostActions.open(feedModel.get(index), "blog")
            }
        }

        // Constant-height footer: a conditional height feeds back into contentHeight/atYEnd and trips a "height" binding loop, so keep it fixed and toggle the spinner.
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
        message: Lang.tr("No posts in %1").arg(Config.currentCommunityName)
    }

    // Compose lives in the global header action now (gated on the News tab) — Lomiri uses a header action, not a Material floating button.
}
