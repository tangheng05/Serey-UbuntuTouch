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
    // Kept out of errorMsg (a plain string) so the "banned" message stays a live Lang.tr() binding
    // and re-translates immediately on a language switch, instead of being baked in at reload() time.
    property bool bannedHere: false
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

        if (Config.isBannedFromCurrentCommunity) return;

        // Global and countries own no categories, so their chips are the shared
        // buckets: the union of every platform's names is unusable as a filter,
        // and the buckets mean the same thing at both levels. No request needed,
        // so these survive being offline too.
        if (page.bucketSource()) {
            page.categories = Config.countryBuckets;
            if (prevSel !== "" && Config.countryBuckets.indexOf(prevSel) < 0) {
                page.selectedCategory = "";
                page.reload();
            }
            return;
        }

        // Offline this request just hangs (QML's XHR ignores its own timeout on a stalled
        // connection) and the chips bar sits above the offline cover, so the spinner outlived
        // the outage. The Net handler below re-runs this once we're back.
        if (!Net.online) return;

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

    // Global and countries have no categories of their own; both show the shared
    // buckets, which the backend resolves server-side. Only a sub-community has a
    // category list of its own, and it keeps the client-side filter below.
    // Read as functions, never as sibling bindings. Both this and Config.communityId
    // derive from Config.selectedSubCommunity, and the only trigger below is
    // onCommunityIdChanged; when two bindings share a dependency their re-evaluation
    // order is undefined, so a binding read from that handler could still hold the
    // previous community's answer. That showed up as chips lagging one switch behind:
    // the country fetched its own (zero) categories, the sub-community showed buckets.
    // Computing straight from Config is order-proof.
    function bucketSource() {
        return !Config.selectedSubCommunity || Config.isGlobalCommunity(Config.communityId);
    }
    function serverBucket() {
        return (page.bucketSource() && page.selectedCategory !== "") ? page.selectedCategory : "";
    }

    // Display only: the chip label re-renders whenever this settles, so binding
    // order is harmless here.
    readonly property bool isBucketSourceView: !Config.selectedSubCommunity
                                               || Config.isGlobalCommunity(Config.communityId)

    // Case-insensitive compare: post tags vs. category list casing can differ.
    function _norm(s) { return (s || "").trim().toLowerCase(); }

    // Raw fetch results are plain JS objects (not yet ListModel-wrapped), so categories[] indexes normally here.
    function _matchesCategory(p) {
        if (page.selectedCategory === "") return true;
        if (page.serverBucket() !== "") return true;   // filtered server-side already
        if (!p.categories) return false;
        var target = page._norm(page.selectedCategory);
        for (var i = 0; i < p.categories.length; i++)
            if (page._norm(p.categories[i]) === target) return true;
        return false;
    }

    // Over-fetch only when filtering client-side; a server-filtered page is already dense.
    function _fetchLimit() {
        if (page.serverBucket() !== "") return Config.pageSize;
        return page.selectedCategory !== "" ? Config.pageSize * 4 : Config.pageSize;
    }
    property int autoFetches: 0

    // --- Article search ---
    property bool searchOpen: false
    property string searchQuery: ""
    property bool searching: false
    property string searchErrorMsg: ""
    property int searchReqEpoch: 0
    property var searchInflight: null
    ListModel { id: searchModel; dynamicRoles: true }

    function openSearch() {
        page.searchOpen = true;
        searchField.forceActiveFocus();
    }
    function closeSearch() {
        page.searchOpen = false;
        page.searchQuery = "";
        page.searchReqEpoch++;
        if (page.searchInflight) { page.searchInflight.abort(); page.searchInflight = null; }
        page.searching = false;
        page.searchErrorMsg = "";
        searchModel.clear();
    }
    // Debounced from the field's onTextChanged
    function runSearch() {
        page.searchReqEpoch++;
        var epoch = page.searchReqEpoch;
        if (page.searchInflight) { page.searchInflight.abort(); page.searchInflight = null; }
        var q = page.searchQuery.trim();
        searchModel.clear();
        page.searchErrorMsg = "";
        if (q.length === 0) { page.searching = false; return; }
        page.searching = true;
        var extraParams = {};
        if (Config.communityId > 0) extraParams.community_id = Config.communityId;
        page.searchInflight = PostService.searchPosts(Config.baseUrl, q, extraParams, Session.token,
            function (result) {
                if (epoch !== page.searchReqEpoch) return;
                page.searchInflight = null;
                page.searching = false;
                for (var i = 0; i < result.length; i++) searchModel.append(result[i]);
            },
            function (err) {
                if (epoch !== page.searchReqEpoch) return;
                page.searchInflight = null;
                page.searching = false;
                page.searchErrorMsg = err.message || Lang.tr("Search failed.");
            });
    }
    Timer { id: searchDebounce; interval: 350; onTriggered: page.runSearch() }

    // Zero-height header: the global AppHeader provides the top bar, but keeping an explicit header avoids Lomiri's deprecated Page.head path.
    header: Item { height: 0 }

    ListModel { id: feedModel; dynamicRoles: true }

    // Source switching lives in the global AppHeader community pill; the feed just reloads when Config.sourceIndex changes.
    Connections {
        target: Config
        // Warm the other tab too, or first toggle after a community switch flashes skeleton
        function onCommunityIdChanged() {
            page.loadCategories(); page.reload(); page._warmOtherFeed();
            // Re-run search for new community
            if (page.searchOpen) page.runSearch();
        }
        // Account switch (or a fresh ban) can flip this for the SAME community id already on screen.
        function onIsBannedFromCurrentCommunityChanged() { page.reload(); }
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
        var bucket = page.serverBucket();
        if (bucket !== "") params.category_bucket = bucket;
        return params;
    }

    // Prefetch the other tab on arrival so first toggle paints from cache, not skeleton
    function _warmOtherFeed() {
        if (Config.isBannedFromCurrentCommunity) return;
        var other = page.feedIndex === 1 ? 0 : 1;
        var params = _pageParams(0);
        var fn = _feedFnFor(other);
        FeedCache.request(FeedCache.newsKey(other, Config.communityId, page.serverBucket()),
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
        page.bannedHere = Config.isBannedFromCurrentCommunity;
        if (page.bannedHere) {
            feedModel.clear();
            page.endReached = true;
            return;
        }
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
        var cached = FeedCache.peek(FeedCache.newsKey(page.feedIndex, Config.communityId, page.serverBucket()));
        if (!cached) return false;
        _syncRows(_filterRows(cached));
        page.showingCached = feedModel.count > 0;
        return page.showingCached;
    }

    // Pull-to-refresh re-fetches the first page but keeps current rows on screen until new ones arrive, Facebook-style.
    property bool refreshing: false
    function refresh() {
        if (page.refreshing) return;
        if (Config.isBannedFromCurrentCommunity) return;
        page.refreshing = true;
        page.reqEpoch++;
        if (inflight) { inflight.abort(); inflight = null; }
        var epoch = page.reqEpoch;
        var params = _pageParams(0);
        // Through FeedCache so a manual refresh also updates the stored rows.
        inflight = FeedCache.request(FeedCache.newsKey(page.feedIndex, Config.communityId, page.serverBucket()),
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
        if (Config.isBannedFromCurrentCommunity) { page.bannedHere = true; page.endReached = true; return; }
        // Offline: every page request would just fail, and parking at the end retries forever.
        if (!Net.online) return;
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
            inflight = FeedCache.request(FeedCache.newsKey(page.feedIndex, Config.communityId, page.serverBucket()),
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

    // Trending/Latest strip, or search field when open
    Item {
        id: tabsHeader
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: tabs.implicitHeight

        SectionTabs {
            id: tabs
            visible: !page.searchOpen
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
            width: parent.width - searchIconBtn.width
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

        // Separates the tabs from the search icon; stops short of the bottom so it
        // doesn't cross (and double up on) SectionTabs' own horizontal divider.
        Rectangle {
            visible: !page.searchOpen
            anchors { top: parent.top; bottom: parent.bottom; bottomMargin: units.dp(1); right: searchIconBtn.left }
            width: units.dp(1)
            color: Style.divider
        }

        AbstractButton {
            id: searchIconBtn
            visible: !page.searchOpen
            anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
            width: units.gu(6)
            onClicked: page.openSearch()
            Icon {
                anchors.centerIn: parent
                width: units.gu(2.4); height: width
                name: "find"
                color: Style.textSecondary
            }
            // SectionTabs' own bottom divider only spans its own (reduced) width, so it
            // never reaches under this icon — closes that box's 4th (bottom) side.
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: units.dp(1)
                color: Style.divider
            }
        }

        TextField {
            id: searchField
            visible: page.searchOpen
            anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingS; topMargin: Style.spacingXs; bottomMargin: Style.spacingXs }
            hasClearButton: false
            placeholderText: Lang.tr("Search articles")
            text: page.searchQuery
            onTextChanged: {
                page.searchQuery = text;
                searchDebounce.restart();
            }
            Keys.onEscapePressed: page.closeSearch()
            // Close button rendered inside the field's own border, not as a separate box.
            secondaryItem: AbstractButton {
                height: parent.height; width: height
                onClicked: page.closeSearch()
                Icon { anchors.centerIn: parent; width: units.gu(2.2); height: width; name: "close"; color: Style.textSecondary }
            }
        }

        // Divider for the search row
        Rectangle {
            visible: page.searchOpen
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: units.dp(1)
            color: Style.divider
        }
    }

    // Category filter chips; hidden during search
    Flickable {
        id: catBar
        anchors { top: tabsHeader.bottom; left: parent.left; right: parent.right }
        readonly property bool showBar: !page.searchOpen && (page.categories.length > 0 || page.categoriesLoading)
        height: showBar ? units.gu(5.5) : 0
        visible: showBar
        contentWidth: catRow.width + Style.spacingM
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        clip: true

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
                        // Buckets are our own vocabulary, so they translate. A
                        // community's own categories are author-defined and render as-is.
                        text: catName === "" ? Lang.tr("All")
                              : (page.isBucketSourceView ? Lang.tr(catName) : catName)
                        font.pixelSize: Style.fontSmall
                        font.weight: Font.DemiBold
                        color: parent.isSelected ? Style.textOnBrand : Style.textPrimary
                    }
                }
            }
        }
    }

    // Sibling of catBar, not a child (Flickable children stretch to contentWidth)
    Rectangle {
        anchors { left: catBar.left; right: catBar.right; bottom: catBar.bottom }
        visible: catBar.showBar
        height: units.dp(1)
        color: Style.divider
    }

    // Also a sibling: inside the Flickable it centres on contentWidth (one "All" chip while
    // the fetch is out), which parked it at the left edge instead of the middle of the bar.
    ActivityIndicator {
        anchors.centerIn: catBar
        running: catBar.showBar && page.categoriesLoading && page.categories.length === 0
        visible: running
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
        visible: !page.searchOpen
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
            // Swipe is a touch affordance: on desktop the card's "..." menu already offers these.
            leadingActions: Config.desktopMode ? null : swipeHideActions
            ListItemActions {
                id: swipeHideActions
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

            trailingActions: Config.desktopMode ? null : swipeShareActions
            ListItemActions {
                id: swipeShareActions
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
                        text: Lang.tr("Share…")
                        onTriggered: {
                            var p = feedModel.get(index)
                            if (p) Share.open("https://serey.io/authors/" + p.author + "/" + p.permlink, card.menuAnchor)
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
        visible: !page.searchOpen && page.loading && feedModel.count === 0
    }
    // Paging is blocked while offline; pick it up again as soon as the network is back.
    Connections {
        target: Net
        function onOnlineChanged() {
            // Losing the network mid-request used to leave the spinner up until the HTTP
            // timeout (~15s). Drop the request as soon as Net says we're offline, so the
            // offline surface is immediate.
            if (!Net.online) {
                if (page.inflight) { page.inflight.abort(); page.inflight = null; }
                // Same for the categories: their spinner is outside the offline cover.
                if (page.inflightCat) { page.inflightCat.abort(); page.inflightCat = null; }
                page.categoriesLoading = false;
                page.loading = false;
                page.refreshing = false;
                if (feedModel.count === 0 && page.errorMsg === "")
                    page.errorMsg = Lang.tr("There is currently no network connection.");
                return;
            }
            // Chips were skipped while offline; fetch them before the feed comes back.
            if (page.categories.length === 0) page.loadCategories();
            if (feedModel.count === 0) page.reload();
            else if (!page.loading && !page.endReached && list.atYEnd) page.loadMore();
        }
    }

    // ErrorState carries the offline panel itself, so this covers both cases.
    ErrorState {
        anchors.fill: list
        autoRetry: false   // the Net handler above already reloads and resumes paging
        // Offline is the cover below; this stays the online-error panel only.
        visible: !page.searchOpen && Net.online && (page.errorMsg !== "" || page.bannedHere) && feedModel.count === 0
        // Live Lang.tr() binding (not baked into errorMsg) so a language switch re-translates immediately.
        message: page.bannedHere ? Lang.tr("You're banned from this community.") : page.errorMsg
        onRetry: page.reload()
    }

    // Offline shows the Homepage's panel over the whole list, cached rows and all, so the
    // offline face of the app is the same everywhere (opaque, or rows read through it).
    Rectangle {
        id: offlineCover
        anchors.fill: list
        // The backdrop cuts in hard: cross-fading it let the feed show through the panel for
        // the whole animation, which looked like a rendering fault. Only the panel's own
        // content fades, so the feed is gone the instant we know we're offline.
        visible: !Net.online
        color: Style.surface
        z: 2
        // Swallow taps so the list can't be scrolled or opened behind the panel.
        MouseArea { anchors.fill: parent }
        OfflineState {
            anchors.fill: parent
            opacity: offlineCover.visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
            onRetry: page.reload()
        }
    }

    EmptyState {
        anchors.fill: list
        visible: !page.searchOpen && !page.loading && page.errorMsg === "" && !page.bannedHere && feedModel.count === 0
        iconName: "stock_note"
        message: page.selectedCategory !== ""
            ? Lang.tr("No posts tagged \"%1\" in %2").arg(page.selectedCategory).arg(Config.currentCommunityName)
            : Lang.tr("No posts in %1").arg(Config.currentCommunityName)
    }

    // --- Search results list ---
    ListView {
        id: searchList
        visible: page.searchOpen
        anchors { top: catBar.bottom; bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
        width: Math.min(parent.width, page.maxContentWidth)
        clip: true
        model: searchModel

        delegate: PostCard {
            width: searchList.width
            post: searchModel.get(index)
            highlightQuery: page.searchQuery
            onClicked: page.pageStack.push(Qt.resolvedUrl("PostDetailPage.qml"),
                { author: post.author, permlink: post.permlink, title: post.title, seedPost: post })
            onAuthorClicked: page.pageStack.push(Qt.resolvedUrl("ProfileViewPage.qml"), { username: post.author })
            onMoreClicked: PostActions.open(post, "blog")
            onRequireLogin: page.pageStack.push(Qt.resolvedUrl("LoginPage.qml"))
        }
    }

    ActivityIndicator {
        anchors.centerIn: searchList
        running: page.searchOpen && page.searching && searchModel.count === 0
        visible: running
    }

    EmptyState {
        anchors.fill: searchList
        visible: page.searchOpen && !page.searching && page.searchErrorMsg === ""
                 && searchModel.count === 0 && page.searchQuery.trim().length > 0
        iconName: "find"
        message: Lang.tr("No articles match \"%1\"").arg(page.searchQuery.trim())
    }

    EmptyState {
        anchors.fill: searchList
        visible: page.searchOpen && page.searchQuery.trim().length === 0
        iconName: "find"
        message: Lang.tr("Type to search articles")
    }

    ErrorState {
        anchors.fill: searchList
        autoRetry: false
        visible: page.searchOpen && page.searchErrorMsg !== "" && searchModel.count === 0
        message: page.searchErrorMsg
        onRetry: page.runSearch()
    }

    // Compose lives in the global header action now (gated on the News tab); Lomiri uses a header action, not a Material floating button.
}
