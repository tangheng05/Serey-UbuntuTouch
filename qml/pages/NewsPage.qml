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
    // True while the rows on screen came from FeedCache rather than the network.
    // The page-0 response replaces them wholesale instead of appending onto them,
    // and a failed load keeps them rather than blanking to an error.
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
        // Warm the other tab for the new community too, or the first toggle after
        // a community switch flashes the skeleton again.
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
        // Bigger batches while a category filter is on (no server-side filter,
        // so most of a page can be dropped client-side) - see _fetchLimit.
        var params = { limit: page._fetchLimit(), offset: offset };
        if (Config.communityId > 0)
            params.community_id = Config.communityId;
        else
            params.exclude_home = 1;   // Global feed hides the Cambodia community + children
        return params;
    }

    // Prefetch the tab the user isn't on so the first Trending/Latest toggle
    // paints from cache instead of flashing the skeleton. Only done on arrival;
    // the toggle itself already revalidates through FeedCache.
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
        // Only wipe the list when there's nothing cached to show in its place;
        // clearing first would flash the skeleton between the two feeds.
        if (!_paintCached()) feedModel.clear();
        // Back to the top: rows are synced in place, so unlike the old
        // clear()-based reload the ListView keeps its scroll offset; switching
        // tabs mid-scroll landed the user mid-list of the OTHER feed.
        list.positionViewAtBeginning();
        loadMore();
    }

    // Hides and blocks change independently of any rows we hold, so re-filter on
    // the way in rather than trusting whatever was stored.
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

    // Sync the model in place instead of clear() + append: clear() destroys
    // delegates, so PostCard thumbnails fade back in from nothing on every
    // Trending/Latest toggle. Reused rows don't flash.
    // True when a row needs rewriting: a different article, or the same one with
    // stale counts or content. Content matters because an edit keeps the permlink
    // and counters; comparing only those left the old title/body on the card.
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
        // Overwrite by index: reusing rows keeps delegates, so an unchanged feed
        // does nothing. Reconciling by permlink was tried and is worse: the two
        // feeds are disjoint, so every row became insert + trim (full teardown).
        var n = Math.min(rows.length, feedModel.count);
        for (var i = 0; i < n; i++)
            if (_rowDiffers(feedModel.get(i), rows[i]))
                feedModel.set(i, rows[i]);
        for (var j = feedModel.count; j < rows.length; j++)
            feedModel.append(rows[j]);
        while (feedModel.count > rows.length)
            feedModel.remove(feedModel.count - 1);
    }

    // Paint cached rows for this feed+community so tab switches show content at
    // once (this is also what suppresses the count===0 skeleton); the request
    // fired right after replaces them. Returns false on a cold cache.
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
                // In place, same as loadMore's page 0: a refresh that returns the
                // same rows shouldn't visibly rebuild the list.
                page._syncRows(page._filterRows(result));
                page.showingCached = false;
                page.offset = rawCount;
                page.endReached = rawCount < params.limit;
                // Keep paging if filtering left less than a screenful, but cap
                // the chain (see _fetchLimit) so a sparse category can't spiral.
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
                // On an empty feed surface the error so ErrorState's Retry shows;
                // falling through to EmptyState reads as "nothing here" rather
                // than "this didn't load".
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
                // Page 0 owns the whole list: sync in place so unchanged rows keep
                // their delegates (and loaded thumbnails). This also replaces the
                // old "clear cached rows first" step, which left duplicates.
                page._syncRows(rows);
                page.showingCached = false;
            } else {
                for (var i = 0; i < rows.length; i++)
                    feedModel.append(rows[i]);
            }
            page.offset += rawCount;
            if (rawCount < params.limit) page.endReached = true;
            // Keep paging if this page was filtered below a screenful, but cap
            // the chain (see _fetchLimit) so a sparse category can't spiral.
            if (!page.endReached && feedModel.count < Config.pageSize && page.autoFetches < 6) {
                page.autoFetches++;
                page.loadMore();
            }
            // An atYEnd trigger during this request hit the `loading` guard and
            // won't re-fire. Re-check after layout settles; a synchronous atYEnd
            // read here is stale and over-fetched a page on every load.
            endRecheck.restart();
        };
        var onErr = function (err) {
            if (epoch !== page.reqEpoch) return;
            inflight = null;
            loading = false;
            // Cached rows are better than an error screen - keep them on failure.
            if (!page.showingCached) page.errorMsg = err.message;
        };

        // Page 0 goes through FeedCache (stores the result, attaches to Main.qml's
        // startup prefetch); deeper pages are one-shot and go direct.
        if (isFirstPage) {
            inflight = FeedCache.request(FeedCache.newsKey(page.feedIndex, Config.communityId),
                function (ok, err) { return feedFn()(Config.baseUrl, params, Session.token, ok, err); },
                onOk, onErr);
        } else {
            inflight = feedFn()(Config.baseUrl, params, Session.token, onOk, onErr);
        }
    }

    // Fires after rows are applied and the ListView has re-laid-out (atYEnd is
    // trustworthy by then): keep loading if the user is parked at the end, since
    // their flick landed while `loading` was true and won't re-fire.
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
            // list's arrow keys after a tab click; always hand focus back.
            list.forceActiveFocus();
        }
        // Reset the keyboard cursor when dropping back in from the strip; a stale
        // currentIndex made the first Down appear dead. -1 lands on the first card.
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

    // Lomiri only paints a ListItem's focus frame when the Qt focus REASON is
    // key-nav; plain forceActiveFocus() leaves the cursor invisible. Only the
    // keyboard path (Nav.focusMaster) calls this, so touch users never see it.
    function focusListKeyNav() {
        if (list.currentIndex < 0 && list.count > 0) list.currentIndex = 0;
        var it = list.currentItem;
        if (!it) { list.forceActiveFocus(); return; }
        // Qt delivers no focusInEvent to an item that already holds focus, so the
        // key-nav reason never lands; drop focus first, then re-take it.
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
        // The keyboard cursor visual is the ListItem's own key-navigation frame;
        // a custom ListView highlight painted a second ring, don't re-add one.
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

            // ListItem emits clicked() on Enter when focused (and on taps of
            // non-interactive areas); this is what makes Enter open the post.
            onClicked: {
                // Push first: swapping the detail pane transiently drops the stack to
                // depth 0, which would race with the currentPageChanged reset below.
                var p = feedModel.get(index)
                if (!p) return
                // Pointer clicks don't move currentIndex, so the key-nav cursor would
                // sit at the top when Left brings focus back from the detail.
                list.currentIndex = index
                page.pageStack.push(Qt.resolvedUrl("PostDetailPage.qml"),
                    { author: p.author, permlink: p.permlink, title: p.title })
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
                                // Persist to the local hidden-posts store so it stays hidden across
                                // restarts, matching the overflow-menu Hide (PostActionSheet).
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

        // Prefetch: start the next page while ~2 screens of content remain, so
        // a steady scroll almost never lands on the footer spinner. atYEnd above
        // stays as the fallback for flicks that outrun this trigger.
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
