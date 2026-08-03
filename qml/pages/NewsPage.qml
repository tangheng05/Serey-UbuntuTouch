import QtQuick 2.12
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/PostService.js" as PostService
import "../services/HiddenPosts.js" as HiddenPosts
import "../services/BlockedUsers.js" as BlockedUsers
import "../services/CategoryService.js" as CategoryService

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
    // Cached rows: page-0 replaces wholesale, failed load keeps them instead of blanking
    property bool showingCached: false

    // Cards need swipe actions, so a fixed-cell GridView won't work; cap + center instead
    readonly property real maxContentWidth: units.gu(60)

    // Category filter chips, per-community, loaded from the backend. "" = All.
    property var categories: []
    property string selectedCategory: ""
    property bool categoriesLoading: false
    property int catEpoch: 0
    property var inflightCat: null

    function loadCategories() {
        var epoch = ++page.catEpoch;
        var prevSel = page.selectedCategory;
        if (page.inflightCat) { page.inflightCat.abort(); page.inflightCat = null; }
        // Clear right away so the previous community's categories don't linger.
        page.categories = [];
        page.categoriesLoading = false;

        // No selector on Global, there is no coherent taxonomy across every community.
        if (Config.communityId <= 0) {
            if (prevSel !== "") { page.selectedCategory = ""; page.reload(); }
            return;
        }

        // currentCommunityName can lag a tick behind communityId here - read the source object directly.
        var communityTitle = Config.selectedSubCommunity ? Config.selectedSubCommunity.name : Config.communityName;

        page.categoriesLoading = true;
        page.inflightCat = CategoryService.listByCommunity(Config.baseUrl, communityTitle, Config.communityId, Session.token,
            function (names) {
                if (epoch !== page.catEpoch) return;   // stale community switch
                page.inflightCat = null;
                page.categoriesLoading = false;
                page.categories = names;
                // Case-insensitive: post tags and category names don't always match casing.
                if (prevSel !== "") {
                    var stillValid = false;
                    for (var i = 0; i < names.length; i++)
                        if (page._norm(names[i]) === page._norm(prevSel)) { stillValid = true; break; }
                    if (!stillValid) { page.selectedCategory = ""; page.reload(); }
                }
            },
            function (err) {
                if (epoch !== page.catEpoch) return;
                page.inflightCat = null;
                page.categoriesLoading = false;
                page.categories = [];
            });
    }

    function selectCategory(cat) {
        if (page.selectedCategory === cat) return;
        page.selectedCategory = cat;
        page.reload();
    }

    // Case-insensitive compare: post tags vs. category list casing can differ.
    function _norm(s) { return (s || "").trim().toLowerCase(); }

    // Raw fetch results are plain JS objects (not yet ListModel-wrapped), so categories[] indexes normally here.
    function _matchesCategory(p) {
        if (page.selectedCategory === "") return true;
        if (!p.categories) return false;
        var target = page._norm(page.selectedCategory);
        for (var i = 0; i < p.categories.length; i++)
            if (page._norm(p.categories[i]) === target) return true;
        return false;
    }

    // No server-side category filter; applied client-side, so fetch bigger batches while filtering.
    function _fetchLimit() { return page.selectedCategory !== "" ? Config.pageSize * 4 : Config.pageSize; }
    property int autoFetches: 0

    // Zero-height header: the global AppHeader provides the top bar, but keeping an explicit header avoids Lomiri's deprecated Page.head path.
    header: Item { height: 0 }

    ListModel { id: feedModel; dynamicRoles: true }

    // Source switching lives in the global AppHeader community pill; the feed just reloads when Config.sourceIndex changes.
    Connections {
        target: Config
        // Warm the other tab too, or first toggle after a community switch flashes skeleton
        function onCommunityIdChanged() { page.loadCategories(); page.reload(); page._warmOtherFeed(); }
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

    function _feedFnFor(idx) {
        return idx === 1 ? PostService.listNew : PostService.listTrending;
    }

    function feedFn() { return _feedFnFor(page.feedIndex); }

    function _pageParams(offset) {
        // Bigger batches while filtering client-side (no server-side filter) - see _fetchLimit
        var params = { limit: page._fetchLimit(), offset: offset };
        if (Config.communityId > 0)
            params.community_id = Config.communityId;
        else
            params.exclude_home = 1;   // Global feed hides the Cambodia community + children
        return params;
    }

    // Prefetch the other tab on arrival so first toggle paints from cache, not skeleton
    function _warmOtherFeed() {
        var other = page.feedIndex === 1 ? 0 : 1;
        var params = _pageParams(0);
        var fn = _feedFnFor(other);
        FeedCache.request(FeedCache.newsKey(other, Config.communityId),
            function (ok, err) { return fn(Config.baseUrl, params, Session.token, ok, err); },
            function () { /* stored by FeedCache; the toggle reads it */ },
            function () { /* offline: the toggle falls back to its own request */ });
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
        autoFetches = 0;
        page.showingCached = false;
        // Only wipe list if nothing cached, else clearing flashes skeleton between feeds
        if (!_paintCached()) feedModel.clear();
        // Force to top: synced-in-place rows keep scroll offset, unlike old clear()-based reload
        list.positionViewAtBeginning();
        loadMore();
    }

    // Re-filter on the way in; hides/blocks can change independently of stored rows
    function _filterRows(rows) {
        var hidden = HiddenPosts.loadAll();
        var blocked = BlockedUsers.loadAll();
        var out = [];
        for (var i = 0; i < rows.length; i++)
            if (!hidden[rows[i].permlink || ""] && !blocked[rows[i].author || ""]
                    && page._matchesCategory(rows[i]))
                out.push(rows[i]);
        return out;
    }

    // Sync in place (not clear()+append, which re-fades thumbnails); differs if permlink/votes/comments changed
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
        // Overwrite by index to keep delegates; permlink reconciliation caused full teardown
        var n = Math.min(rows.length, feedModel.count);
        for (var i = 0; i < n; i++)
            if (_rowDiffers(feedModel.get(i), rows[i]))
                feedModel.set(i, rows[i]);
        for (var j = feedModel.count; j < rows.length; j++)
            feedModel.append(rows[j]);
        while (feedModel.count > rows.length)
            feedModel.remove(feedModel.count - 1);
    }

    // Paint cached rows immediately (suppresses skeleton); the fresh request replaces them
    function _paintCached() {
        var cached = FeedCache.peek(FeedCache.newsKey(page.feedIndex, Config.communityId));
        if (!cached) return false;
        _syncRows(_filterRows(cached));
        page.showingCached = feedModel.count > 0;
        return page.showingCached;
    }

    // Pull-to-refresh re-fetches the first page but keeps current rows on screen until new ones arrive, Facebook-style.
    property bool refreshing: false
    function refresh() {
        if (page.refreshing) return;
        page.refreshing = true;
        page.reqEpoch++;
        if (inflight) { inflight.abort(); inflight = null; }
        var epoch = page.reqEpoch;
        var params = _pageParams(0);
        // Through FeedCache so a manual refresh also updates the stored rows.
        inflight = FeedCache.request(FeedCache.newsKey(page.feedIndex, Config.communityId),
            function (ok, err) { return feedFn()(Config.baseUrl, params, Session.token, ok, err); },
            function (result, rawCount) {
                if (epoch !== page.reqEpoch) return;
                inflight = null;
                page.refreshing = false;
                page.loading = false;
                // In place like loadMore's page 0: unchanged refresh shouldn't rebuild the list
                page._syncRows(page._filterRows(result));
                page.showingCached = false;
                page.offset = rawCount;
                page.endReached = rawCount < params.limit;
                // Keep paging if filtered below a screenful, capped so a sparse category can't spiral
                if (!page.endReached && feedModel.count < Config.pageSize && page.autoFetches < 6) {
                    page.autoFetches++;
                    page.loadMore();
                }
                endRecheck.restart();   // user may sit at the end already (see loadMore)
            },
            function (err) {
                if (epoch !== page.reqEpoch) return;
                inflight = null;
                page.refreshing = false;
                // Must also clear loading: an aborted in-flight loadMore's own callback early-returns and would leave the skeleton stuck otherwise.
                page.loading = false;
                // On empty feed, surface the error (ErrorState/Retry) rather than EmptyState
                if (feedModel.count === 0) page.errorMsg = err.message;
            });
    }

    function loadMore() {
        if (loading || endReached) return;
        loading = true;
        errorMsg = "";
        var epoch = page.reqEpoch;
        var isFirstPage = page.offset === 0;
        var params = _pageParams(page.offset);

        var onOk = function (result, rawCount) {
            if (epoch !== page.reqEpoch) return;   // stale response, ignore
            inflight = null;
            loading = false;
            var rows = page._filterRows(result);
            if (isFirstPage) {
                // Page 0 owns the whole list: sync in place, replaces old clear-first step (dupes)
                page._syncRows(rows);
                page.showingCached = false;
            } else {
                for (var i = 0; i < rows.length; i++)
                    feedModel.append(rows[i]);
            }
            page.offset += rawCount;
            if (rawCount < params.limit) page.endReached = true;
            // Keep paging if filtered below a screenful, capped so a sparse category can't spiral
            if (!page.endReached && feedModel.count < Config.pageSize && page.autoFetches < 6) {
                page.autoFetches++;
                page.loadMore();
            }
            // Re-check atYEnd after layout settles; a synchronous read here over-fetched
            endRecheck.restart();
        };
        var onErr = function (err) {
            if (epoch !== page.reqEpoch) return;
            inflight = null;
            loading = false;
            // Cached rows are better than an error screen - keep them on failure.
            if (!page.showingCached) page.errorMsg = err.message;
        };

        // Page 0 goes through FeedCache (ties into Main.qml prefetch); deeper pages go direct
        if (isFirstPage) {
            inflight = FeedCache.request(FeedCache.newsKey(page.feedIndex, Config.communityId),
                function (ok, err) { return feedFn()(Config.baseUrl, params, Session.token, ok, err); },
                onOk, onErr);
        } else {
            inflight = feedFn()(Config.baseUrl, params, Session.token, onOk, onErr);
        }
    }

    // Fires after layout settles (atYEnd trustworthy); resumes loading if parked at the end
    Timer {
        id: endRecheck
        interval: 120
        repeat: false
        onTriggered: if (!page.loading && !page.endReached && page.errorMsg === "" && list.atYEnd)
                         page.loadMore()
    }

    // Category-badge deep link: handles an already-alive page (Component.onCompleted covers a fresh one).
    Connections {
        target: Nav
        function onPendingCategoryChanged() {
            if (Nav.pendingCategory === "") return;
            page.selectedCategory = Nav.pendingCategory;
            Nav.pendingCategory = "";
            page.reload();
        }
    }

    Component.onCompleted: {
        if (Nav.pendingCategory !== "") {
            page.selectedCategory = Nav.pendingCategory;
            Nav.pendingCategory = "";
        }
        loadCategories();
        _paintCached();
        loadMore();
        _warmOtherFeed();
        if (visible) list.forceActiveFocus();
    }
    // Keyboard parity: list grabs arrow-key focus whenever page is (re)shown
    onVisibleChanged: if (visible) {
        list.kbEngaged = false
        if (list.currentItem) list.currentItem.focus = false
        list.forceActiveFocus()
    }

    // After publishing: jump to Latest tab and reload so the new post is on top
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
            // Lomiri buttons steal focus on press; hand it back to the list after a tab click
            list.forceActiveFocus();
        }
        // Reset cursor from the strip: stale currentIndex made first Down appear dead
        onFocusList: { list.currentIndex = -1; list.forceActiveFocus(); }
    }

    // Category filter chips; stays visible as a spinner while loading.
    Flickable {
        id: catBar
        anchors { top: tabs.bottom; left: parent.left; right: parent.right }
        readonly property bool showBar: page.categories.length > 0 || page.categoriesLoading
        height: showBar ? units.gu(5.5) : 0
        visible: showBar
        contentWidth: catRow.width + Style.spacingM
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        clip: true

        ActivityIndicator {
            anchors.centerIn: parent
            running: page.categoriesLoading && page.categories.length === 0
            visible: running
        }

        Row {
            visible: !(page.categoriesLoading && page.categories.length === 0)
            id: catRow
            anchors.verticalCenter: parent.verticalCenter
            x: Style.spacingM
            spacing: Style.spacingS

            Repeater {
                model: [""].concat(page.categories)

                delegate: AbstractButton {
                    readonly property string catName: modelData
                    readonly property bool isSelected: catName === ""
                        ? page.selectedCategory === ""
                        : page._norm(page.selectedCategory) === page._norm(catName)
                    height: units.gu(3.75)
                    width: catLbl.width + units.gu(2.4)
                    onClicked: page.selectCategory(catName)

                    Rectangle {
                        anchors.fill: parent
                        radius: Style.pillRadius
                        color: parent.isSelected ? Style.brand : Style.iconBackground
                    }
                    Label {
                        id: catLbl
                        anchors.centerIn: parent
                        text: catName === "" ? Lang.tr("All") : catName
                        font.pixelSize: Style.fontSmall
                        font.weight: Font.DemiBold
                        color: parent.isSelected ? Style.textOnBrand : Style.textPrimary
                    }
                }
            }
        }

        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: units.dp(1)
            color: Style.divider
        }
    }

    // This list owns arrow-key focus for master-detail keyboard nav (AdaptiveStack.focusMaster targets it).
    property Item keyboardFocusItem: list

    // Focus frame only paints for key-nav focus reason; touch path never calls this
    function focusListKeyNav() {
        list.kbEngaged = true;
        if (list.currentIndex < 0 && list.count > 0) list.currentIndex = 0;
        var it = list.currentItem;
        if (!it) { list.forceActiveFocus(); return; }
        // Drop focus first: Qt won't re-fire focusInEvent on an item that already has it
        it.focus = false;
        it.forceActiveFocus(Qt.TabFocusReason);
    }

    ListView {
        id: list
        anchors { top: catBar.bottom; bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
        width: Math.min(parent.width, page.maxContentWidth)
        clip: true
        model: feedModel
        cacheBuffer: units.gu(12)
        // Gates the tap-triggered focus frame so it doesn't double up with ListItem's own ring (mirrors VideoPage)
        property bool kbEngaged: false
        Keys.onPressed: list.kbEngaged = true
        // Right arrow steps into the open article's reading pane (split windows).
        Keys.onRightPressed: Nav.focusDetail()
        // Left steps out of the content to the tab nav (rail / bottom bar).
        Keys.onLeftPressed: Nav.focusNav()
        // Up on the first card climbs to the Trending/Latest strip, else moves the cursor
        Keys.onUpPressed: {
            if (list.atYBeginning && list.currentIndex <= 0) { tabs.focusCurrent(); event.accepted = true; }
            else event.accepted = false;
        }

        PullToRefresh {
            refreshing: page.refreshing
            onRefresh: page.refresh()
            // Opacity, not visible: PullToRefresh's style imperatively sets `visible` itself, which would clobber a visible binding.
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

            // ListItem emits clicked() on Enter when focused; this is what opens the post
            onClicked: {
                // Push first: swapping panes transiently drops stack to depth 0 (races reset below)
                var p = feedModel.get(index)
                if (!p) return
                // Pointer clicks don't move currentIndex; sync it so Left returns to the right row
                list.currentIndex = index
                // Drop tap focus; deferred again since currentIndex change re-grants it a tick later
                if (!list.kbEngaged) {
                    newsItem.focus = false
                    Qt.callLater(function () { newsItem.focus = false })
                }
                page.pageStack.push(Qt.resolvedUrl("PostDetailPage.qml"),
                    { author: p.author, permlink: p.permlink, title: p.title, seedPost: p })
                page.openPermlink = p.permlink
            }

            // Touch equivalent of the removed overflow button; opens the same Hide/Report/Block sheet.
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
                        iconName: "view-off"
                        text: Lang.tr("Hide")
                        onTriggered: {
                            var p = feedModel.get(index)
                            if (p) {
                                // Persist to local hidden-posts store to survive restarts (matches PostActionSheet)
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
                    // Reflects already-following on the "contact"/Follow action; every other action keeps the neutral color.
                    readonly property bool isFollowAction: action.iconName === "contact"
                    readonly property var _rowPost: isFollowAction ? feedModel.get(index) : null
                    // Only built when the row is swiped open, so this is one request per swipe
                    Component.onCompleted: {
                        if (isFollowAction && _rowPost && Session.isLoggedIn
                                && _rowPost.author && _rowPost.author !== Session.username)
                            FollowStore.load(Config.baseUrl, Session.username, _rowPost.author);
                    }
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
                        { author: p.author, permlink: p.permlink, title: p.title, seedPost: p })
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

        // Prefetch next page ~2 screens early so scrolling rarely hits the footer spinner
        onContentYChanged: {
            if (!page.loading && !page.endReached && page.errorMsg === ""
                    && contentHeight > height
                    && contentY + height >= contentHeight - height * 2)
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
        message: page.selectedCategory !== ""
            ? Lang.tr("No posts tagged \"%1\" in %2").arg(page.selectedCategory).arg(Config.currentCommunityName)
            : Lang.tr("No posts in %1").arg(Config.currentCommunityName)
    }

    // Compose lives in the global header action now (gated on the News tab); Lomiri uses a header action, not a Material floating button.
}
