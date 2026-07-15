import QtQuick 2.7
import Lomiri.Components 1.3
// Lomiri.Notifications/Ubuntu.PushNotifications exist only on-device, so they're created dynamically to keep desktop builds alive.
import "Theme"
import "Session"
import "components"
import "services/CommunityService.js" as CommunityService
import "services/Flags.js" as Flags
import "services/AccountService.js" as AccountService
import "services/Http.js" as Http
import "services/NotificationService.js" as NotificationService
import "services/BlockedUsers.js" as BlockedUsers
import "services/PaymentService.js" as PaymentService

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
            },
            function (err) { /* keep globe fallback */ });
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
        if (root.notifSound) root.notifSound.play()

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
        // QtMultimedia Audio (not SoundEffect) for ogg support.
        try {
            root.notifSound = Qt.createQmlObject(
                'import QtMultimedia 5.6; Audio { source: "/usr/share/sounds/lomiri/notifications/Xylo.ogg"; autoPlay: false }',
                root, "notifSound")
        } catch (e) { /* QtMultimedia not available — silent */ }

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
                    var vp = videoStack.currentPage;
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
