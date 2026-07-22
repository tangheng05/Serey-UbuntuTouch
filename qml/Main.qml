import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Themes 1.3
// created dynamically; on-device only
import "Theme"
import "Session"
import "components"
import "services/CommunityService.js" as CommunityService
import "services/Flags.js" as Flags
import "services/GeoService.js" as GeoService
import "services/AccountService.js" as AccountService
import "services/Http.js" as Http
import "services/NotificationService.js" as NotificationService
import "services/BlockedUsers.js" as BlockedUsers
import "services/PaymentService.js" as PaymentService
import "services/PostService.js" as PostService
import "services/VideoService.js" as VideoService

MainView {
    id: root
    objectName: "mainView"
    applicationName: "serey.serey-io"
    automaticOrientation: true

    width: units.gu(45)
    height: units.gu(80)

    // convergence breakpoint drives side nav rail
    readonly property bool wideMode: width >= Config.convergenceBreakpoint
    Binding { target: Config; property: "wideMode"; value: root.wideMode }

    // follow OS light/dark theme
    Binding { target: Style; property: "dark"; value: root.theme.palette.normal.background.hslLightness < 0.5 }

    // Cut/Copy/Paste popover text color
    theme.palette: Palette {
        normal.overlayText: Style.dark ? "#F7F7F7" : "#262626"
    }

    property int currentTab: 0
    // no fade for Homepage; avoids recomposite
    onCurrentTabChanged: {
        Config.currentTab = currentTab;
        _ensureTab(currentTab);
        if (currentTab === 0) {
            tabFadeIn.stop();
            body.opacity = 1;
        } else {
            body.opacity = 0;
            tabFadeIn.start();
        }
    }

    // tabs created lazily on first visit
    function _ensureTab(tab) {
        if (tab === 0 && homeStack.depth === 0)
            homeStack.push(Qt.resolvedUrl("pages/HomepagePage.qml"));
        else if (tab === 1 && newsStack.depth === 0)
            newsStack.push(Qt.resolvedUrl("pages/NewsPage.qml"));
        else if (tab === 2 && videoStack.depth === 0)
            videoStack.push(Qt.resolvedUrl("pages/VideoPage.qml"));
        else if (tab === 3 && settingsStack.depth === 0)
            settingsStack.push(Qt.resolvedUrl("pages/SettingsPage.qml"));
    }
    NumberAnimation { id: tabFadeIn; target: body; property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutQuad }

    // header/nav hide at depth > 1 on phone
    property int activeDepth: currentTab === 0 ? homeStack.depth
                            : currentTab === 1 ? newsStack.depth
                            : currentTab === 2 ? videoStack.depth
                            : settingsStack.depth
    property int activeColumns: currentTab === 0 ? homeStack.columns
                              : currentTab === 1 ? newsStack.columns
                              : currentTab === 2 ? videoStack.columns
                              : settingsStack.columns
    readonly property bool showHeader: (activeColumns > 1 || activeDepth <= 1) && currentTab !== 3
    readonly property bool showNavBar: activeColumns > 1 || activeDepth <= 1

    Component.onCompleted: {
        // clear only if rejected token is still current
        Http.setUnauthorizedHandler(function (tokenUsed) {
            if (!Session.isLoggedIn) return;
            if (tokenUsed !== Session.token) return;
            Session.clear();
            Toast.error(Lang.tr("Your session expired. Please log in again."));
        });

        // Needed immediately: the header pill icons and can-post gates read it.
        _loadCommunities();

        // country hint for community picker; fire-and-forget
        GeoService.detectCountry(
            function (code) { Config.detectedCountryCode = code; root._applyGeoSource(); },
            function () { /* no hint — Global stays selected, picker keeps its order */ });

        _prefetchFeeds();
    }

    // open on user's own country once geo hint + source list are both in
    property bool _geoSourceApplied: false
    // explicit flag; sources.length isn't a reliable "loaded" signal
    property bool _communitiesLoaded: false
    function _applyGeoSource() {
        if (root._geoSourceApplied) return;
        if (Config.detectedCountryCode === "" || !root._communitiesLoaded) return;
        var i = Config.indexForCountryCode(Config.detectedCountryCode);
        root._geoSourceApplied = true;   // both inputs ready
        if (i > 0 && Config.sourceIndex === 0 && !Config.selectedSubCommunity)
            Config.sourceIndex = i;
    }

    // rebuild picker sources; also called after platform create/delete
    function _loadCommunities() {
        CommunityService.listAll(Config.baseUrl,
            function (list, superhubChildren, byId, hiddenIds, parents) {
                Config.hiddenCommunityIds = hiddenIds || ({});
                Config.parentCommunityById = parents || ({});
                var icons = CommunityService.iconMap(list);
                Config.allowPostByDns = CommunityService.allowPostMap(list);
                Config.videoAllowPostByDns = CommunityService.videoAllowPostMap(list);
                Config.superhubChildrenById = superhubChildren || ({});
                Config.communityById = byId || ({});
                // top level of tree = countries
                var topIds = {};
                for (var t = 0; t < list.length; t++) topIds[String(list[t].id)] = true;
                Config.topLevelCommunityIds = topIds;

                // dns of fixed rows
                var baseDns = {};
                for (var b = 0; b < Config.baseSources.length; b++)
                    baseDns[Config.baseSources[b].dns] = true;

                // append countries below fixed rows
                var extra = [];
                for (var i = 0; i < list.length; i++) {
                    var c = list[i];
                    if (!c.dns || baseDns[c.dns]) continue;
                    if ((c.country || "").toLowerCase() === "cambodia") continue;
                    if (c.childCount <= 0) continue;   // hide countries with no communities yet
                    var flag = Flags.flagUrl(c.title);
                    if (flag) icons[c.dns] = flag;   // override generic logo with the flag
                    extra.push({ name: c.title, id: c.id, dns: c.dns, icon: flag || c.icon || "" });
                }

                Config.iconByDns = icons;
                Config.appendCountries(extra);
                // geo hint may have beaten this; apply now
                root._communitiesLoaded = true;
                root._applyGeoSource();
            },
            function (err) { /* keep globe fallback */ });
    }

    // refresh again past server cache TTL
    property Timer _communitiesRetry: Timer {
        interval: 65000
        repeat: false
        onTriggered: root._loadCommunities()
    }
    Connections {
        target: Nav
        function onRefreshCommunities() {
            root._loadCommunities();
            root._communitiesRetry.restart();
        }
    }

    // prefetch News/Video feeds while on Homepage
    function _prefetchFeeds() {
        FeedCache.request(FeedCache.newsKey(0, Config.communityId),
            function (ok, err) {
                var p = { limit: Config.pageSize, offset: 0 };
                if (Config.communityId > 0) p.community_id = Config.communityId;
                else p.exclude_home = 1;
                return PostService.listTrending(Config.baseUrl, p, Session.token, ok, err);
            },
            function (result) { /* stored by FeedCache; the page reads it */ },
            function (err) { /* offline: the page will show its own error */ });

        FeedCache.request(FeedCache.videoKey(Config.communityId),
            function (ok, err) {
                // must match VideoPage's initialLimit to coalesce
                var p = { limit: 30, offset: 0 };
                if (Config.communityId > 0) p.community_id = Config.communityId;
                else p.exclude_home = 1;
                return VideoService.listVideos(Config.baseUrl, p, Session.token, ok, err);
            },
            function (result) { /* stored by FeedCache; the page reads it */ },
            function (err) { /* offline: the page will show its own error */ });
    }

    // defer non-critical launch work
    property bool startupSettled: false
    Timer {
        id: startupSettleTimer
        interval: 3500
        repeat: false
        running: true
        onTriggered: {
            root.startupSettled = true;
            _initNotifications();
            // The avatar isn't persisted with the session — refetch it.
            if (Session.isLoggedIn) {
                AccountService.profile(Config.baseUrl, Session.username, Session.token,
                    function (user) { Session.avatarUrl = user.profileUrl; },
                    function (err) { /* keep letter-fallback avatar */ });
            }
            _syncBlockedUsers();
            _syncOwnedCommunities();
        }
    }

    // Mirror the server's blocked-users list (feeds filter on it).
    function _syncBlockedUsers() {
        if (!Session.isLoggedIn) { BlockedUsers.replaceAll([]); return; }
        AccountService.listBlocked(Config.baseUrl, Session.token,
            function (list) { BlockedUsers.replaceAll(list); },
            function (err) { /* offline / failed — keep last-known local set */ });
    }

    // communities user owns/manages
    function _syncOwnedCommunities() {
        if (!Session.isLoggedIn) { Config.ownedCommunityIdSet = ({}); return; }
        AccountService.ownedCommunityIds(Config.baseUrl, Session.token,
            function (ids) {
                var set = {};
                for (var i = 0; i < ids.length; i++) set[ids[i]] = true;
                Config.ownedCommunityIdSet = set;
            },
            function (err) { /* offline / failed — keep last-known set */ });
    }

    // ── Push / local notification handles (created dynamically) ─────────────
    property var  sysNotif:   null   // Lomiri.Notifications Notification
    property var  pushClient: null   // Ubuntu.PushNotifications PushClient
    property string pushToken: ""
    property var  notifSound: null

    function _showNotif(body) {
        // create sound player lazily to avoid startup SIGSEGV
        if (!root.notifSound) {
            try {
                root.notifSound = Qt.createQmlObject(
                    'import QtMultimedia 5.6; Audio { autoPlay: false }', root, "notifSound")
            } catch (e) { /* QtMultimedia unavailable — silent */ }
        }
        if (root.notifSound) {
            if (String(root.notifSound.source || "") === "")
                root.notifSound.source = "file:///usr/share/sounds/lomiri/notifications/Xylo.ogg"
            root.notifSound.play()
        }

        if (root.sysNotif) {
            root.sysNotif.body = body
            root.sysNotif.show()
        }

        Toast.show(body)
    }

    function _registerPushToken(pt) {
        NotificationService.registerPushToken(Config.baseUrl, Session.token, pt,
            function () { /* fire-and-forget */ },
            function ()  { /* silent — retry on next app launch */ })
    }

    function _initNotifications() {
        // sound created lazily in _showNotif
        try {
            root.sysNotif = Qt.createQmlObject(
                'import Lomiri.Notifications 1.0; Notification { summary: "Serey" }',
                root, "sysNotif")
        } catch (e) { /* Lomiri.Notifications not available on desktop — expected */ }

        try {
            root.pushClient = Qt.createQmlObject(
                'import Ubuntu.PushNotifications 0.1; PushClient {' +
                '  appId: "serey.serey-io_serey"; }',
                root, "pushClient")

            root.pushClient.tokenChanged.connect(function () {
                var t = root.pushClient.token
                if (t === "" || t === root.pushToken) return
                root.pushToken = t
                if (Session.isLoggedIn) root._registerPushToken(t)
            })

            root.pushClient.notificationsChanged.connect(function () {
                var notifs = root.pushClient.notifications
                if (notifs.length > 0) {
                    var msg = notifs.length === 1
                        ? Lang.tr("You have 1 new notification")
                        : Lang.tr("You have %1 new notifications").arg(notifs.length)
                    root._showNotif(msg)
                    NotificationState.unread = -1
                    root.pushClient.clearAll()
                }
            })
        } catch (e) { console.warn("Push: PushClient failed to create:", e) }
    }

    // poll every 30s while logged in
    Timer {
        id: notifPoller
        interval: 30000
        repeat: true
        running: Session.isLoggedIn && Session.pushEnabled && root.startupSettled
        triggeredOnStart: true
        onTriggered: {
            if (!Session.isLoggedIn || !Session.pushEnabled) return
            NotificationService.listSerey(Config.baseUrl, Session.token, 50, 0,
                function (items) {
                    var count = 0
                    for (var i = 0; i < items.length; i++) {
                        if (!items[i].is_read) count++
                    }
                    if (NotificationState.unread < 0) { NotificationState.unread = count; return }
                    if (count > NotificationState.unread) {
                        var diff = count - NotificationState.unread
                        root._showNotif(diff === 1
                            ? Lang.tr("You have 1 new notification")
                            : Lang.tr("You have %1 new notifications").arg(diff))
                    }
                    NotificationState.unread = count
                },
                function (err) { /* silent */ })
        }
    }

    // poll for pending crypto payment activation
    Timer {
        id: cryptoPendingPoller
        interval: 60000
        repeat: true
        triggeredOnStart: true   // also fires on app launch/resume via `running`
        running: Session.isLoggedIn && Payments.pendingCrypto !== null
                 && !Payments.cryptoOpen && root.startupSettled
        onTriggered: {
            var p = Payments.pendingCrypto
            if (!p) return
            PaymentService.checkCryptoStatus(Config.baseUrl, Session.token, p.paymentId,
                function (status) {
                    if (status === "finished") {
                        Payments.clearPendingCrypto()
                        Toast.success(Lang.tr("Payment confirmed!"))
                        Payments.paymentSucceeded()
                    } else if (status === "failed" || status === "refunded" || status === "expired") {
                        Payments.clearPendingCrypto()
                    } else {
                        // keep checking up to a day past expiry
                        var exp = Date.parse(p.expiresAt)
                        if (!isNaN(exp) && Date.now() > exp + 24 * 3600 * 1000)
                            Payments.clearPendingCrypto()
                    }
                },
                function () { /* transient — next tick retries */ })
        }
    }

    Connections {
        target: Session
        // keyed off token so account switches resync
        function onTokenChanged() { root._syncBlockedUsers(); root._syncOwnedCommunities() }
        function onIsLoggedInChanged() {
            if (!Session.isLoggedIn) {
                NotificationState.unread = -1
            } else if (root.pushToken !== "") {
                root._registerPushToken(root.pushToken)
            }
        }
    }

    // tab switch requested by a page
    Connections {
        target: Nav
        function onGoToTab(tab) {
            root.currentTab = tab;
            // ensure explicitly; tab may equal currentTab already
            root._ensureTab(tab);
            while (settingsStack.depth > 1)
                settingsStack.pop();
        }
        // buy-plan -> create-platform funnel
        function onCreatePlatform() {
            root.currentTab = 3;
            root._ensureTab(3);
            while (settingsStack.depth > 1)
                settingsStack.pop();
            settingsStack.push(Qt.resolvedUrl("pages/CreatePlatformPage.qml"));
        }
        // category badge: switch community, jump to blog tab
        function onFilterCategory(category, community) {
            Nav.pendingCategory = category;
            if (community) Config.selectedSubCommunity = community;
            root.currentTab = 1;
            root._ensureTab(1);
            while (newsStack.depth > 1)
                newsStack.pop();
        }
        // fresh login/signup lands on Homepage/My Feed
        function onGoToFeed() {
            root.currentTab = 0;
            root._ensureTab(0);
            while (settingsStack.depth > 1)
                settingsStack.pop();
            while (homeStack.depth > 1)
                homeStack.pop();
            homeStack.push(Qt.resolvedUrl("pages/FeedPage.qml"));
        }
    }

    // --- Global header (community pill + logo) ----------------------------
    AppHeader {
        id: appHeader
        anchors { left: root.wideMode ? sideNavBar.right : parent.left; right: parent.right; top: parent.top }
        height: root.showHeader ? units.gu(6) : 0
        visible: root.showHeader
        wide: root.wideMode
        onCommunityButtonClicked: communityPicker.open()

        center: AbstractButton {
            id: feedBtn
            visible: Session.isLoggedIn
            anchors.centerIn: parent
            // tap target fills header height
            width: units.gu(6)
            height: width
            onClicked: {
                var stack = root.currentTab === 0 ? homeStack
                          : root.currentTab === 1 ? newsStack
                          : root.currentTab === 2 ? videoStack
                          : settingsStack;
                stack.push(Qt.resolvedUrl("pages/FeedPage.qml"));
            }
            Image {
                anchors.centerIn: parent
                width: root.wideMode ? units.gu(4.5) : units.gu(3.5)
                height: width
                source: Qt.resolvedUrl("../assets/iconFeed.png")
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }
            KeyTapArea { onActivated: feedBtn.clicked() }
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacingS

            // Compose (News tab only). Reloads the feed once a post is saved.
            AbstractButton {
                id: composeBtn
                visible: Session.isLoggedIn && root.currentTab === 1
                anchors.verticalCenter: parent.verticalCenter
                width: root.wideMode ? units.gu(4.2) : units.gu(3.2)
                height: width
                onClicked: {
                    // target News master page, not detail column
                    var np = newsStack.rootPage;
                    postCommunityPicker.openFor(function (target) {
                        var props = target ? { targetCommunity: target } : {};
                        var ed = newsStack.push(Qt.resolvedUrl("pages/CreatePostPage.qml"), props);
                        if (ed && ed.saved && np)
                            ed.saved.connect(function (isNew) {
                                // new post jumps to Latest; edit just reloads
                                if (isNew && np.showLatest) np.showLatest();
                                else if (np.reload) np.reload();
                            });
                    });
                }
                Rectangle {
                    anchors.fill: parent
                    radius: units.gu(0.8)
                    color: "transparent"
                    border.width: units.dp(1.5)
                    border.color: Style.brand
                }
                Icon {
                    anchors.centerIn: parent
                    width: root.wideMode ? units.gu(3) : units.gu(2.2)
                    height: width
                    name: "edit"
                    color: Style.brand
                }
                KeyTapArea { onActivated: composeBtn.clicked() }
            }

            // upload video, gated on posting permission
            AbstractButton {
                id: uploadBtn
                visible: Session.isLoggedIn && root.currentTab === 2 && Config.canPostVideoCurrent
                anchors.verticalCenter: parent.verticalCenter
                width: root.wideMode ? units.gu(4.2) : units.gu(3.2)
                height: width
                onClicked: {
                    // target Video master page, not detail column
                    var vp = videoStack.rootPage;
                    var ed = videoStack.push(Qt.resolvedUrl("pages/CreateVideoPage.qml"));
                    if (ed && ed.saved && vp && vp.reload) ed.saved.connect(vp.reload);
                }
                Rectangle {
                    anchors.fill: parent
                    radius: units.gu(0.8)
                    color: "transparent"
                    border.width: units.dp(1.5)
                    border.color: Style.brand
                }
                Icon {
                    anchors.centerIn: parent
                    width: root.wideMode ? units.gu(3) : units.gu(2.2)
                    height: width
                    name: "add"
                    color: Style.brand
                }
                KeyTapArea { onActivated: uploadBtn.clicked() }
            }
        }
    }

    // --- Content area: four stacks, only the active one visible ----------
    Item {
        id: body
        anchors {
            left: root.wideMode ? sideNavBar.right : parent.left
            right: parent.right
            top: appHeader.bottom
            bottom: (root.showNavBar && !root.wideMode) ? navBar.top : parent.bottom
        }

        AdaptiveStack {
            id: homeStack
            // web app never splits; sub-pages cover full-screen
            neverSplit: true
            anchors.fill: parent
            visible: root.currentTab === 0
            Component.onCompleted: push(Qt.resolvedUrl("pages/HomepagePage.qml"))
        }
        // News/Video/Settings are filled lazily by _ensureTab() on first visit.
        AdaptiveStack {
            id: newsStack
            emptyDetailIconName: "stock_note"
            emptyDetailMessage: Lang.tr("Select a post to read")
            anchors.fill: parent
            visible: root.currentTab === 1
        }
        AdaptiveStack {
            id: videoStack
            emptyDetailIconName: "camcorder"
            emptyDetailMessage: Lang.tr("Select a video to watch")
            anchors.fill: parent
            visible: root.currentTab === 2
        }
        AdaptiveStack {
            id: settingsStack
            emptyDetailIconName: "settings"
            emptyDetailMessage: Lang.tr("Select a setting")
            anchors.fill: parent
            visible: root.currentTab === 3
        }
    }

    // Ctrl+1..4 switch tabs, moving focus off Chromium view
    function switchTab(i) { root.currentTab = i; Qt.callLater(root.focusActiveContent); }

    Shortcut { sequence: "Ctrl+1"; enabled: root.showNavBar; onActivated: root.switchTab(0) }
    Shortcut { sequence: "Ctrl+2"; enabled: root.showNavBar; onActivated: root.switchTab(1) }
    Shortcut { sequence: "Ctrl+3"; enabled: root.showNavBar; onActivated: root.switchTab(2) }
    Shortcut { sequence: "Ctrl+4"; enabled: root.showNavBar; onActivated: root.switchTab(3) }

    // sequential tab switching via StandardKey.Next/PreviousChild
    Shortcut {
        sequence: StandardKey.NextChild
        enabled: root.showNavBar
        onActivated: root.switchTab((root.currentTab + 1) % root._tabs.length)
    }
    Shortcut {
        sequence: StandardKey.PreviousChild
        enabled: root.showNavBar
        onActivated: root.switchTab((root.currentTab - 1 + root._tabs.length) % root._tabs.length)
    }

    // F6 jumps to tab nav from Homepage's Chromium view
    Shortcut { sequence: "F6"; enabled: root.showNavBar; onActivated: root.focusNavRail() }

    // Focus the active tab's button in whichever nav layout is showing.
    function focusNavRail() {
        var rep = root.wideMode ? railRep : navRep;
        var it = rep.itemAt(root.currentTab);
        if (it) it.keyArea.forceActiveFocus();
    }
    // focus active tab's content, incl. Homepage web view
    function focusActiveContent() {
        var stack = root.currentTab === 0 ? homeStack
                  : root.currentTab === 1 ? newsStack
                  : root.currentTab === 2 ? videoStack
                  : settingsStack;
        var p = stack.rootPage;
        if (!p) return;
        // show list cursor for keyboard nav
        if (p.focusListKeyNav) { p.focusListKeyNav(); return; }
        (p.keyboardFocusItem ? p.keyboardFocusItem : p).forceActiveFocus();
    }
    Connections {
        target: Nav
        function onFocusNav() { root.focusNavRail(); }
        function onFocusContent() { root.focusActiveContent(); }
    }

    // Shared by both nav layouts below, so the tab list only exists once.
    readonly property var _tabs: [
        { label: Lang.tr("Homepage"), icon: "home" },
        { label: Lang.tr("News"),     icon: "stock_note" },
        { label: Lang.tr("Video"),    icon: "camcorder" },
        { label: Lang.tr("Settings"), icon: "settings" }
    ]

    // --- Bottom navigation (phone / narrow window) -------------------------
    Rectangle {
        id: navBar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: (root.showNavBar && !root.wideMode) ? units.gu(7) : 0
        visible: root.showNavBar && !root.wideMode
        color: Style.surface

        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: units.dp(1)
            color: Style.divider
        }

        Row {
            anchors.fill: parent

            Repeater {
                id: navRep
                model: root._tabs
                delegate: AbstractButton {
                    width: navBar.width / 4
                    height: navBar.height
                    property bool active: root.currentTab === index
                    property alias keyArea: navTap

                    Icon {
                        anchors.centerIn: parent
                        width: units.gu(3)
                        height: width
                        name: modelData.icon
                        color: active ? Style.brand : Style.textSecondary
                    }
                    onClicked: root.currentTab = index
                    KeyTapArea {
                        id: navTap
                        // Enter always drops into tab content
                        onActivated: root.switchTab(index)
                        // Horizontal bar: Left/Right walk the tabs.
                        onLeftPressed:  { var it = navRep.itemAt(index - 1); if (it) it.keyArea.forceActiveFocus(); }
                        onRightPressed: { var it = navRep.itemAt(index + 1); if (it) it.keyArea.forceActiveFocus(); }
                    }
                }
            }
        }
    }

    // side nav rail for wide/convergence mode
    Rectangle {
        id: sideNavBar
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: (root.showNavBar && root.wideMode) ? units.gu(9) : 0
        visible: root.showNavBar && root.wideMode
        color: Style.surface

        Rectangle {
            anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
            width: units.dp(1)
            color: Style.divider
        }

        Column {
            anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: units.gu(2) }
            spacing: units.gu(1)

            Repeater {
                id: railRep
                model: root._tabs
                delegate: AbstractButton {
                    width: sideNavBar.width
                    height: units.gu(7)
                    property bool active: root.currentTab === index
                    property alias keyArea: railTap

                    Icon {
                        anchors.centerIn: parent
                        width: units.gu(4)
                        height: width
                        name: modelData.icon
                        color: active ? Style.brand : Style.textSecondary
                    }
                    onClicked: root.currentTab = index
                    KeyTapArea {
                        id: railTap
                        // Enter always drops into tab content
                        onActivated: root.switchTab(index)
                        // Vertical rail: Up/Down walk tabs; Right steps into content
                        onUpPressed:   { var it = railRep.itemAt(index - 1); if (it) it.keyArea.forceActiveFocus(); }
                        onDownPressed: { var it = railRep.itemAt(index + 1); if (it) it.keyArea.forceActiveFocus(); }
                        onRightPressed: root.focusActiveContent()
                    }
                }
            }
        }
    }

    // --- Overlays (bottom sheets + toasts) ---------------------------------
    CommunityPicker { id: communityPicker }
    PostCommunityPicker { id: postCommunityPicker }
    PostActionSheet { }
    ShareSheet { }
    PaymentSheet { }
    StripeCheckoutSheet { }
    Toaster { }
}
