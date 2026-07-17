import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Themes 1.3
// Lomiri.Notifications/Ubuntu.PushNotifications exist only on-device, so they're created dynamically to keep desktop builds alive.
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

    // Convergence breakpoint shared with AdaptiveStack.qml via Config — drives the side nav rail, independent of any tab's column state.
    readonly property bool wideMode: width >= Config.convergenceBreakpoint
    Binding { target: Config; property: "wideMode"; value: root.wideMode }

    // Follow the OS light/dark setting: bind the Style singleton's `dark` switch to
    // the active Suru theme so every color token re-skins centrally (no call-site
    // change). Luminance of the theme background works regardless of the theme name.
    Binding { target: Style; property: "dark"; value: root.theme.palette.normal.background.hslLightness < 0.5 }

    // Cut/Copy/Paste popover text color
    theme.palette: Palette {
        normal.overlayText: Style.dark ? "#F7F7F7" : "#262626"
    }

    property int currentTab: 0
    onCurrentTabChanged: { Config.currentTab = currentTab; _ensureTab(currentTab); body.opacity = 0; tabFadeIn.start(); }

    // Tabs are created lazily on first visit — launching all four at once made the Homepage web view janky on low-end devices.
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

    // Header/nav hide at depth > 1 on phone; stay up when the stack shows 2 columns, per Lomiri convergence HIG.
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
        // Expired tokens are caught lazily via 401 (can't check up-front); only clear if the rejected token is still the current one.
        Http.setUnauthorizedHandler(function (tokenUsed) {
            if (!Session.isLoggedIn) return;
            if (tokenUsed !== Session.token) return;
            Session.clear();
            Toast.error(Lang.tr("Your session expired. Please log in again."));
        });

        // Needed immediately: the header pill icons and can-post gates read it.
        _loadCommunities();

        // Country hint for the community picker. Fire-and-forget: it only
        // reorders that sheet, so a failure (offline, VPN, unknown IP) must
        // leave the app exactly as it is today.
        GeoService.detectCountry(
            function (code) { Config.detectedCountryCode = code; root._applyGeoSource(); },
            function () { /* no hint — Global stays selected, picker keeps its order */ });

        _prefetchFeeds();
    }

    /*
     * Open on the user's own country instead of Global, once we know it.
     *
     * Needs BOTH the geo hint and the source list, which race — so this is
     * called from whichever lands second and no-ops until both are in.
     *
     * Only ever moves OFF Global: sourceIndex isn't persisted, so every launch
     * starts there and there's no saved choice to trample — but detection is
     * async, and a user who picked a community while it was in flight must keep
     * it. That's also why it can't run again later (Nav.refreshCommunities
     * rebuilds sources after a platform create/delete); by then any selection is
     * the user's own.
     */
    property bool _geoSourceApplied: false
    // Explicit flag, NOT sources.length: `sources` is seeded with baseSources
    // (Global/Netherlands/US) before the fetch, so a length check reads as
    // "loaded" while the country rows are still missing — the geo hint would
    // then find no match, latch, and never retry.
    property bool _communitiesLoaded: false
    function _applyGeoSource() {
        if (root._geoSourceApplied) return;
        if (Config.detectedCountryCode === "" || !root._communitiesLoaded) return;
        var i = Config.indexForCountryCode(Config.detectedCountryCode);
        root._geoSourceApplied = true;   // both inputs are in: this is the decision
        if (i > 0 && Config.sourceIndex === 0 && !Config.selectedSubCommunity)
            Config.sourceIndex = i;
    }

    // Fetch get-communities and rebuild the picker's source list + every derived
    // map. Ran once at startup, and again via Nav.refreshCommunities() after a
    // platform is created or deleted — Config.sources was otherwise never
    // refreshed, so the picker only showed the change after an app restart.
    function _loadCommunities() {
        CommunityService.listAll(Config.baseUrl,
            function (list, superhubChildren, byId) {
                var icons = CommunityService.iconMap(list);
                Config.allowPostByDns = CommunityService.allowPostMap(list);
                Config.videoAllowPostByDns = CommunityService.videoAllowPostMap(list);
                Config.superhubChildrenById = superhubChildren || ({});
                Config.communityById = byId || ({});

                // dns of the three fixed rows — leave their icons untouched.
                var baseDns = {};
                for (var b = 0; b < Config.baseSources.length; b++)
                    baseDns[Config.baseSources[b].dns] = true;

                // Append every top-level country (except Cambodia) below the fixed rows; icons derive from a flagcdn flag since backend icon_url is empty.
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
                // The country rows just landed — if the geo hint beat them here,
                // this is where it gets applied.
                root._communitiesLoaded = true;
                root._applyGeoSource();
            },
            function (err) { /* keep globe fallback */ });
    }

    // After a platform create/delete: refresh now, then once more past the
    // server's 60s in-process cache TTL. The write busts Redis and its own
    // instance's local copy, but another instance (or a not-yet-redeployed API)
    // can still serve its stale local entry to the immediate re-fetch — the
    // second pass lands after every local TTL has expired.
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

    /*
     * Warm the News and Video feeds while the user is still on the Homepage, so
     * tapping either tab shows rows instead of a skeleton. Worth the most on
     * Video: that request costs seconds server-side, and starting it here means
     * it has usually landed before the user gets there.
     *
     * Data only — never the pages. _ensureTab stays lazy on purpose (see its
     * comment): instantiating the tabs at launch is what made the Homepage web
     * view janky, whereas this is ~50KB of JSON.
     *
     * Not deferred behind startupSettleTimer: a prefetch that arrives 3.5s late
     * has missed the tab tap it exists to cover. FeedCache coalesces, so a user
     * who taps News immediately attaches to this request rather than racing it.
     */
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
                // Must match VideoPage's first-page request (initialLimit) or the
                // page's own fetch won't coalesce with this one.
                var p = { limit: 30, offset: 0 };
                if (Config.communityId > 0) p.community_id = Config.communityId;
                else p.exclude_home = 1;
                return VideoService.listVideos(Config.baseUrl, p, Session.token, ok, err);
            },
            function (result) { /* stored by FeedCache; the page reads it */ },
            function (err) { /* offline: the page will show its own error */ });
    }

    // Non-critical launch work is deferred so the Homepage web view's first load gets the CPU/network to itself on slow devices.
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

    // Communities the user owns/manages — an owner may post even when the community is owner-only.
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
        // Create the sound player lazily, on the first real notification — NOT at
        // startup. Merely constructing a QtMultimedia Audio spins up media-hub's
        // Hybris video sink, which SIGSEGVs on an icon relaunch after a kill (it
        // races the app window: "event to a non-existent window"). By the time a
        // notification actually fires, the window is up, so it's safe.
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
        // NOTE: the notification sound (QtMultimedia Audio) is intentionally NOT
        // created here. Constructing it spins up media-hub's Hybris video sink,
        // which SIGSEGVs on an icon relaunch after a kill. It's created lazily on
        // the first notification instead (see _showNotif).

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

    // Poll every 30 s while logged in; the first poll waits for startupSettled.
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

    // Background check for a pending crypto plan payment. Crypto activation
    // only happens when OUR client pings check-status (no webhook reliance),
    // so if the user paid after closing the payment sheet — or the whole app —
    // this is what still activates the plan. Payments.pendingCrypto is
    // persisted in SQLite; the PaymentSheet's own 10 s poll takes over while
    // it is open (hence !Payments.cryptoOpen).
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
                        // Still waiting/confirming. Give up well past expiry —
                        // late blockchain confirmations can land after the
                        // NOWPayments window, so keep checking for an extra day.
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
        // Keyed off the token (not isLoggedIn) so account switches resync — one account's blocks must never leak into another's feed.
        function onTokenChanged() { root._syncBlockedUsers(); root._syncOwnedCommunities() }
        function onIsLoggedInChanged() {
            if (!Session.isLoggedIn) {
                NotificationState.unread = -1
            } else if (root.pushToken !== "") {
                root._registerPushToken(root.pushToken)
            }
        }
    }

    // Tab switch requested by a page (e.g. signup success); also unwinds auth pages left on the Settings stack.
    Connections {
        target: Nav
        function onGoToTab(tab) {
            root.currentTab = tab;
            // tab may already equal currentTab (no change signal) — ensure explicitly.
            root._ensureTab(tab);
            while (settingsStack.depth > 1)
                settingsStack.pop();
        }
        // Buy-plan → create-platform funnel: land on Settings with the wizard
        // pushed (its own gate re-checks the now-active subscription).
        function onCreatePlatform() {
            root.currentTab = 3;
            root._ensureTab(3);
            while (settingsStack.depth > 1)
                settingsStack.pop();
            settingsStack.push(Qt.resolvedUrl("pages/CreatePlatformPage.qml"));
        }
        // Fresh login/signup: land on Homepage tab with My Feed pushed on top.
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
            width: root.wideMode ? units.gu(5) : units.gu(4)
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
                    // Target the News master page (not whatever's open in the detail column).
                    var np = newsStack.rootPage;
                    var ed = newsStack.push(Qt.resolvedUrl("pages/CreatePostPage.qml"));
                    if (ed && ed.saved && np)
                        ed.saved.connect(function (isNew) {
                            // New post -> jump to Latest so it shows at the top; edit -> just reload.
                            if (isNew && np.showLatest) np.showLatest();
                            else if (np.reload) np.reload();
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

            // Upload video (Video tab only), gated on the community's video posting permission.
            AbstractButton {
                id: uploadBtn
                visible: Session.isLoggedIn && root.currentTab === 2 && Config.canPostVideoCurrent
                anchors.verticalCenter: parent.verticalCenter
                width: root.wideMode ? units.gu(4.2) : units.gu(3.2)
                height: width
                onClicked: {
                    // Target the Video master page, not whatever's open in the
                    // detail column: in split mode currentPage is VideoDetailPage,
                    // which has no reload(), so the guard below silently skipped
                    // the connect and the feed never showed the new upload.
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
            // The web app is the panel: never split — sub-pages (My Feed, Login)
            // cover it full-screen instead of shrinking it into a master column.
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

    // Keyboard access to the tab nav (desktop convention, morph-browser style):
    // Ctrl+1..4 switch tabs directly, whatever currently has focus. Disabled
    // whenever the nav itself is hidden (e.g. inside a full-screen sub-page).
    // Switching by keyboard must MOVE focus, not just flip the tab: otherwise focus
    // stays where it was — notably trapped in the Homepage's Chromium view, which
    // then keeps eating every key while a different tab is on screen.
    function switchTab(i) { root.currentTab = i; Qt.callLater(root.focusActiveContent); }

    Shortcut { sequence: "Ctrl+1"; enabled: root.showNavBar; onActivated: root.switchTab(0) }
    Shortcut { sequence: "Ctrl+2"; enabled: root.showNavBar; onActivated: root.switchTab(1) }
    Shortcut { sequence: "Ctrl+3"; enabled: root.showNavBar; onActivated: root.switchTab(2) }
    Shortcut { sequence: "Ctrl+4"; enabled: root.showNavBar; onActivated: root.switchTab(3) }

    // Sequential tab switching, mirroring morph-browser (Lomiri's own browser):
    // StandardKey.NextChild/PreviousChild with modulo wrap. StandardKey rather than a
    // literal "Ctrl+Tab" because it adapts per platform — the same call morph-browser
    // makes. Shortcuts fire before the focused item, so this is the only way to change
    // tabs from inside the Homepage, whose Chromium view owns the arrow keys.
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

    // F6 = jump to the tab nav from anywhere — an escape from the Homepage's Chromium
    // view, which swallows Tab and the arrows for the web page itself. Not a cycle:
    // morph-browser's F6 likewise jumps to a single target (its address bar).
    Shortcut { sequence: "F6"; enabled: root.showNavBar; onActivated: root.focusNavRail() }

    // Focus the active tab's button in whichever nav layout is showing.
    function focusNavRail() {
        var rep = root.wideMode ? railRep : navRep;
        var it = rep.itemAt(root.currentTab);
        if (it) it.keyArea.forceActiveFocus();
    }
    // Focus the active tab's content page (works on every tab incl. the
    // Homepage web view — unlike Nav.focusMaster, which only split stacks service).
    function focusActiveContent() {
        var stack = root.currentTab === 0 ? homeStack
                  : root.currentTab === 1 ? newsStack
                  : root.currentTab === 2 ? videoStack
                  : settingsStack;
        var p = stack.rootPage;
        if (!p) return;
        // Reaching content by keyboard should show the list cursor (same contract as
        // AdaptiveStack.focusMaster); plain forceActiveFocus leaves it invisible.
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
                        // Enter always drops into the tab's content — including
                        // when the tab is already active (a tab change alone only
                        // moves focus via the page's onVisibleChanged).
                        onActivated: root.switchTab(index)
                        // Horizontal bar: Left/Right walk the tabs.
                        onLeftPressed:  { var it = navRep.itemAt(index - 1); if (it) it.keyArea.forceActiveFocus(); }
                        onRightPressed: { var it = navRep.itemAt(index + 1); if (it) it.keyArea.forceActiveFocus(); }
                    }
                }
            }
        }
    }

    // Side navigation: a separate vertical rail spanning full height, matching Lomiri's desktop shell convention — convergence, not scaling.
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
                        // Enter always drops into the tab's content — including
                        // when the tab is already active (a tab change alone only
                        // moves focus via the page's onVisibleChanged).
                        onActivated: root.switchTab(index)
                        // Vertical rail: Up/Down walk the tabs; Right steps into
                        // the active tab's content list (mirrors list -> detail).
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
    PostActionSheet { }
    ShareSheet { }
    PaymentSheet { }
    StripeCheckoutSheet { }
    Toaster { }
}
