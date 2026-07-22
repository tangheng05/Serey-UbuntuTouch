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
    // open row in split-pane detail
    property string openPermlink: ""
    // bumped on reload to drop stale responses
    property int reqEpoch: 0
    property var inflight: null
    // true when rows came from FeedCache, not network
    property bool showingCached: false

    // cap width, center instead of grid
    readonly property real maxContentWidth: units.gu(60)

    // Category filter chips — per-community, loaded from the backend. "" = All.
    property var categories: []
    property string selectedCategory: ""
    property bool categoriesLoading: false
    property int catEpoch: 0
    property var inflightCat: null

    function loadCategories() {
        var epoch = ++page.catEpoch;
        var prevSel = page.selectedCategory;
        if (page.inflightCat) { page.inflightCat.abort(); page.inflightCat = null; }
        // clear stale categories immediately
        page.categories = [];
        page.categoriesLoading = false;

        // no category selector on Global
        if (Config.communityId <= 0) {
            if (prevSel !== "") { page.selectedCategory = ""; page.reload(); }
            return;
        }

        // read source object directly, name may lag
        var communityTitle = Config.selectedSubCommunity ? Config.selectedSubCommunity.name : Config.communityName;

        page.categoriesLoading = true;
        page.inflightCat = CategoryService.listByCommunity(Config.baseUrl, communityTitle, Config.communityId, Session.token,
            function (names) {
                if (epoch !== page.catEpoch) return;   // stale community switch
                page.inflightCat = null;
                page.categoriesLoading = false;
                page.categories = names;
                // case-insensitive compare
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

    // case-insensitive compare
    function _norm(s) { return (s || "").trim().toLowerCase(); }

    // raw fetch results, not ListModel-wrapped yet
    function _matchesCategory(p) {
        if (page.selectedCategory === "") return true;
        if (!p.categories) return false;
        var target = page._norm(page.selectedCategory);
        for (var i = 0; i < p.categories.length; i++)
            if (page._norm(p.categories[i]) === target) return true;
        return false;
    }

    // client-side filter, fetch bigger batches
    function _fetchLimit() { return page.selectedCategory !== "" ? Config.pageSize * 4 : Config.pageSize; }
    property int autoFetches: 0

    // zero-height, global AppHeader is the top bar
    header: Item { height: 0 }

    ListModel { id: feedModel; dynamicRoles: true }

    // reload on community switch
    Connections {
        target: Config
        // also warm the other tab
        function onCommunityIdChanged() { page.loadCategories(); page.reload(); page._warmOtherFeed(); }
    }

    // clear highlighted row on return from detail pane
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
        // see _fetchLimit
        var params = { limit: page._fetchLimit(), offset: offset };
        if (Config.communityId > 0)
            params.community_id = Config.communityId;
        else
            params.exclude_home = 1;   // Global feed hides the Cambodia community + children
        return params;
    }

    // prefetch other tab so first toggle paints from cache
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
        // clear refreshing too, avoid stuck spinner
        refreshing = false;
        errorMsg = "";
        autoFetches = 0;
        page.showingCached = false;
        // only clear if nothing cached to show
        if (!_paintCached()) feedModel.clear();
        // reset scroll position
        list.positionViewAtBeginning();
        loadMore();
    }

    // re-filter hides/blocks on the way in
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

    // replace model contents in place, avoid clear() thumbnail fade
    // true when row needs rewriting
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
        // overwrite in place by index, keeps delegate
        var n = Math.min(rows.length, feedModel.count);
        for (var i = 0; i < n; i++)
            if (_rowDiffers(feedModel.get(i), rows[i]))
                feedModel.set(i, rows[i]);
        for (var j = feedModel.count; j < rows.length; j++)
            feedModel.append(rows[j]);
        while (feedModel.count > rows.length)
            feedModel.remove(feedModel.count - 1);
    }

    // paint last-seen rows, returns false on cold cache
    function _paintCached() {
        var cached = FeedCache.peek(FeedCache.newsKey(page.feedIndex, Config.communityId));
        if (!cached) return false;
        _syncRows(_filterRows(cached));
        page.showingCached = feedModel.count > 0;
        return page.showingCached;
    }

    // refetch first page, keep rows on screen until new arrive
    property bool refreshing: false
    function refresh() {
        if (page.refreshing) return;
        page.refreshing = true;
        page.reqEpoch++;
        if (inflight) { inflight.abort(); inflight = null; }
        var epoch = page.reqEpoch;
        var params = _pageParams(0);
        // through FeedCache so it updates stored rows
        inflight = FeedCache.request(FeedCache.newsKey(page.feedIndex, Config.communityId),
            function (ok, err) { return feedFn()(Config.baseUrl, params, Session.token, ok, err); },
            function (result, rawCount) {
                if (epoch !== page.reqEpoch) return;
                inflight = null;
                page.refreshing = false;
                page.loading = false;
                // sync in place, avoid visible rebuild
                page._syncRows(page._filterRows(result));
                page.showingCached = false;
                page.offset = rawCount;
                page.endReached = rawCount < params.limit;
                // keep paging if filtered thin, capped (see _fetchLimit)
                if (!page.endReached && feedModel.count < Config.pageSize && page.autoFetches < 6) {
                    page.autoFetches++;
                    page.loadMore();
                }
                endRecheck.restart();   // may already sit at end
            },
            function (err) {
                if (epoch !== page.reqEpoch) return;
                inflight = null;
                page.refreshing = false;
                // clear loading too, avoid stuck skeleton
                page.loading = false;
                // surface error so Retry shows instead of EmptyState
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
            if (epoch !== page.reqEpoch) return;   // stale response — ignore
            inflight = null;
            loading = false;
            var rows = page._filterRows(result);
            if (isFirstPage) {
                // sync in place, avoid rebuild
                page._syncRows(rows);
                page.showingCached = false;
            } else {
                for (var i = 0; i < rows.length; i++)
                    feedModel.append(rows[i]);
            }
            page.offset += rawCount;
            if (rawCount < params.limit) page.endReached = true;
            // keep paging if filtered thin, capped (see _fetchLimit)
            if (!page.endReached && feedModel.count < Config.pageSize && page.autoFetches < 6) {
                page.autoFetches++;
                page.loadMore();
            }
            // recheck atYEnd once layout settles
            endRecheck.restart();
        };
        var onErr = function (err) {
            if (epoch !== page.reqEpoch) return;
            inflight = null;
            loading = false;
            // keep cached rows instead of error screen
            if (!page.showingCached) page.errorMsg = err.message;
        };

        // page 0 through FeedCache, deeper pages go direct
        if (isFirstPage) {
            inflight = FeedCache.request(FeedCache.newsKey(page.feedIndex, Config.communityId),
                function (ok, err) { return feedFn()(Config.baseUrl, params, Session.token, ok, err); },
                onOk, onErr);
        } else {
            inflight = feedFn()(Config.baseUrl, params, Session.token, onOk, onErr);
        }
    }

    // re-check atYEnd after layout settles, continue if parked at end
    Timer {
        id: endRecheck
        interval: 120
        repeat: false
        onTriggered: if (!page.loading && !page.endReached && page.errorMsg === "" && list.atYEnd)
                         page.loadMore()
    }

    // category-badge deep link, for already-alive page
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
    // focus list on page arrival
    onVisibleChanged: if (visible) list.forceActiveFocus()

    // jump to Latest tab after publishing
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
            // tab click steals focus, hand it back
            list.forceActiveFocus();
        }
        // reset cursor so next Down lands on first card
        onFocusList: { list.currentIndex = -1; list.forceActiveFocus(); }
    }

    // Category filter chips — stays visible as a spinner while loading.
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

    // owns arrow-key focus for master-detail nav
    property Item keyboardFocusItem: list

    // sets key-nav focus reason so ListItem draws its frame
    function focusListKeyNav() {
        if (list.currentIndex < 0 && list.count > 0) list.currentIndex = 0;
        var it = list.currentItem;
        if (!it) { list.forceActiveFocus(); return; }
        // drop focus first, then re-take with key-nav reason
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
        // no custom highlight, uses ListItem's own key-nav frame
        // Right steps into detail pane
        Keys.onRightPressed: Nav.focusDetail()
        // Left steps to tab nav
        Keys.onLeftPressed: Nav.focusNav()
        // Up on first card climbs into tab strip
        Keys.onUpPressed: {
            if (list.atYBeginning && list.currentIndex <= 0) { tabs.focusCurrent(); event.accepted = true; }
            else event.accepted = false;
        }

        PullToRefresh {
            refreshing: page.refreshing
            onRefresh: page.refresh()
            // opacity not visible, style sets visible itself
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
            // highlight row open in detail pane (wide layout)
            color: (Config.wideMode && page.openPermlink !== "" && page.openPermlink === model.permlink)
                ? Style.iconBackground : Style.surface

            // Enter/tap activation for keyboard nav
            onClicked: {
                // push first, avoid race with stack depth reset
                var p = feedModel.get(index)
                if (!p) return
                // sync key-nav cursor to pointer click
                list.currentIndex = index
                page.pageStack.push(Qt.resolvedUrl("PostDetailPage.qml"),
                    { author: p.author, permlink: p.permlink, title: p.title })
                page.openPermlink = p.permlink
            }

            // touch equivalent of ••• menu
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
                                // persist so it stays hidden across restarts
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
                    // highlight Follow action if already following
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

        // fixed height avoids binding loop on contentHeight
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

        // prefetch ~2 screens before end, atYEnd is fallback
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

    // compose lives in global header action now
}
