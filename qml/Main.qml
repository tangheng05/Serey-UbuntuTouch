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

    // Convergence breakpoint shared with AdaptiveStack.qml via Config; drives the side nav rail, independent of any tab's column state.
    readonly property bool wideMode: width >= Config.convergenceBreakpoint
    Binding { target: Config; property: "wideMode"; value: root.wideMode }
    readonly property bool desktopMode: width >= Config.desktopBreakpoint
    Binding { target: Config; property: "desktopMode"; value: root.desktopMode }

    // Follow OS light/dark setting: bind Style.dark to the active Suru theme luminance
    Binding { target: Style; property: "dark"; value: root.theme.palette.normal.background.hslLightness < 0.5 }

    // Cut/Copy/Paste popover text color
    theme.palette: Palette {
        normal.overlayText: Style.dark ? "#F7F7F7" : "#262626"
    }

    property int currentTab: 0
    property int _lastTab: 0
    // No fade for Homepage: animating opacity over live Chromium recomposites every frame
    onCurrentTabChanged: {
        // My Feed is a destination borrowed by whichever tab opened it, not that tab's own
        // content; leaving would otherwise strand it there and hide the tab's list on return.
        var prev = root._stackForTab(root._lastTab);
        if (prev && prev.popMaster && prev.rootPage && prev.rootPage.isFeedPage)
            prev.popMaster();
        root._lastTab = currentTab;

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

    // Tabs are created lazily on first visit; launching all four at once made the Homepage web view janky on low-end devices.
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
    function _stackForTab(tab) {
        return tab === 0 ? homeStack : tab === 1 ? newsStack : tab === 2 ? videoStack : settingsStack;
    }
    // Offline shortcut to what's on the device; opens on whichever tab asked for it.
    function openLibrary() {
        var stack = root.activeStack;
        if (!stack) return;
        var cur = stack.currentPage;
        if (cur && cur.isLibraryPage) return;
        stack.push(Qt.resolvedUrl("pages/DownloadedContentPage.qml"));
    }
    readonly property var activeStack: currentTab === 0 ? homeStack
                                     : currentTab === 1 ? newsStack
                                     : currentTab === 2 ? videoStack
                                     : settingsStack
    // My Feed draws the same iconFeed logo in its own header, and in split mode
    // this header stays up, so the shortcut showed the logo twice and pointed at
    // the page you were already on.
    // rootPage, not currentPage: the feed holds the leading column while an article
    // it opened is the current page.
    readonly property bool feedPageOpen: {
        var p = activeStack ? activeStack.rootPage : null;
        return !!(p && p.isFeedPage);
    }
    // The library list, or a downloaded video / saved article opened from it (offlineMode).
    readonly property bool _onDeviceContent: {
        var p = activeStack ? activeStack.currentPage : null;
        return !!(p && (p.isLibraryPage || p.offlineMode));
    }
    readonly property bool showHeader: (activeColumns > 1 || activeDepth <= 1) && currentTab !== 3
    // Wide windows keep the rail inside pushed pages too: it's app chrome there.
    readonly property bool showNavBar: root.wideMode || activeColumns > 1 || activeDepth <= 1

    Component.onCompleted: {
        // Expired tokens caught lazily via 401; only clear if rejected token is still current
        Http.setUnauthorizedHandler(function (tokenUsed) {
            if (!Session.isLoggedIn) return;
            if (tokenUsed !== Session.token) return;
            Session.clear();
            Toast.error(Lang.tr("Your session expired. Please log in again."));
        });

        // Every request doubles as a reachability sample, so the whole app knows it's offline.
        Http.setNetworkStatusHandler(function (reachable) { Net.report(reachable); });

        // Needed immediately: the header pill icons and can-post gates read it.
        _loadCommunities();

        // Country hint for community picker; fire-and-forget, failure leaves app as-is
        GeoService.detectCountry(
            function (code) { Config.detectedCountryCode = code; root._applyGeoSource(); },
            // No hint: Global stays selected, so the community is settled now
            function () { root._prefetchFeeds(); });

        _prefetchLate.start();
        root._checkLaunchUrl();
    }

    // cold start via a push-notification tap
    function _checkLaunchUrl() {
        var args = Qt.application.arguments || [];
        for (var i = 0; i < args.length; i++) {
            if (String(args[i]).indexOf("notif=") !== -1) {
                root._handleIncomingUrl(args[i]);
                break;
            }
        }
    }

    function _extractNotifId(url) {
        var m = String(url || "").match(/[?&#]notif=([^&]+)/);
        return m ? decodeURIComponent(m[1]) : "";
    }

    function _handleIncomingUrl(url) {
        var id = root._extractNotifId(url);
        if (id) root._openNotification(id);
    }

    // resolves a tapped notification and navigates there
    function _openNotification(notifId) {
        if (!Session.isLoggedIn) return;
        NotificationService.getById(Config.baseUrl, Session.token, notifId,
            function (n) {
                if (!n) return;
                root.currentTab = 0;
                root._ensureTab(0);
                if (n.type === "FOLLOW") {
                    homeStack.push(Qt.resolvedUrl("pages/ProfileViewPage.qml"), { username: n.actor });
                    return;
                }
                var info = n.information || {};
                var postAuthor = info.post_author || "";
                var postPermlink = info.post_permlink || "";
                var scrollPermlink = info.commented_on_permlink || "";
                if (!postAuthor || !postPermlink) return;
                PostService.detail(Config.baseUrl, postAuthor, postPermlink, Session.token,
                    function (result) {
                        var cats = (result.post && result.post.categories) || [];
                        var isGallery = false;
                        for (var c = 0; c < cats.length; c++) {
                            if (cats[c].toLowerCase() === "gallery") { isGallery = true; break; }
                        }
                        if (isGallery) {
                            homeStack.push(Qt.resolvedUrl("pages/GalleryDetailPage.qml"),
                                { author: postAuthor, permlink: postPermlink });
                        } else {
                            homeStack.push(Qt.resolvedUrl("pages/PostDetailPage.qml"),
                                { author: postAuthor, permlink: postPermlink, scrollToCommentPermlink: scrollPermlink });
                        }
                    },
                    function (err) {
                        homeStack.push(Qt.resolvedUrl("pages/PostDetailPage.qml"),
                            { author: postAuthor, permlink: postPermlink });
                    });
            },
            function (err) { /* silent — notification may be gone/read elsewhere */ });
    }

    // Open on the user's own country instead of Global; called from whichever of geo/sources lands second
    property bool _geoSourceApplied: false
    // Explicit flag, not sources.length: sources is pre-seeded with baseSources
    property bool _communitiesLoaded: false
    function _applyGeoSource() {
        if (root._geoSourceApplied) return;
        if (Config.detectedCountryCode === "" || !root._communitiesLoaded) return;
        var i = Config.indexForCountryCode(Config.detectedCountryCode);
        root._geoSourceApplied = true;   // both inputs are in: this is the decision
        if (i > 0 && Config.sourceIndex === 0 && !Config.selectedSubCommunity)
            Config.sourceIndex = i;
        root._prefetchFeeds();
    }

    // Backstop: geo or get-communities may never answer, and the feeds still want warming.
    Timer {
        id: _prefetchLate
        interval: 2500
        onTriggered: root._prefetchFeeds()
    }

    // Fetch get-communities and rebuild picker's sources + maps; runs at startup and on refreshCommunities()
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
                // listAll's `list` is the top level of the tree, i.e. the countries.
                var topIds = {};
                for (var t = 0; t < list.length; t++) topIds[String(list[t].id)] = true;
                Config.topLevelCommunityIds = topIds;

                // dns of the three fixed rows; leave their icons untouched.
                var baseDns = {};
                for (var b = 0; b < Config.baseSources.length; b++)
                    baseDns[Config.baseSources[b].dns] = true;

                // Append top-level countries below fixed rows; icons derive from flagcdn
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
                // Country rows just landed; apply geo hint if it beat them here
                root._communitiesLoaded = true;
                root._applyGeoSource();
            },
            function (err) { /* keep globe fallback */ });
    }

    // Launched offline, every startup fetch failed silently and nothing ever asked again:
    // the picker kept only its three seeded rows ("No platforms found" under a country) and
    // the composer had no post targets. Pick up whatever is still missing once we're back.
    Connections {
        target: Net
        function onOnlineChanged() {
            if (!Net.online) return;
            if (!root._communitiesLoaded) root._loadCommunities();
            if (Config.detectedCountryCode === "")
                GeoService.detectCountry(
                    function (code) { Config.detectedCountryCode = code; root._applyGeoSource(); },
                    function () { /* no hint; Global stays selected */ });
            // Cheap and idempotent, and both no-op when logged out.
            if (root.startupSettled) {
                root._syncBlockedUsers();
                root._syncOwnedCommunities();
            }
        }
    }

    // After create/delete: refresh now, then again past the server's 60s cache TTL
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

    // Warm News/Video feeds at launch so tabs paint rows; data only, never the pages.
    // Runs only once the community is settled: geo detection can move it, and rows cached
    // under the pre-geo community are keyed where no page ever looks.
    property bool _prefetched: false
    function _prefetchFeeds() {
        if (root._prefetched) return;
        root._prefetched = true;
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
                // Must match VideoPage's first-page request (initialLimit) to coalesce
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
            _maybeReRegisterPush();
            // The avatar isn't persisted with the session; refetch it.
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
            function (err) { /* offline / failed, keep last-known local set */ });
    }

    // Communities the user owns/manages; an owner may post even when the community is owner-only.
    function _syncOwnedCommunities() {
        if (!Session.isLoggedIn) { Config.ownedCommunityIdSet = ({}); return; }
        AccountService.ownedCommunityIds(Config.baseUrl, Session.token,
            function (ids) {
                var set = {};
                for (var i = 0; i < ids.length; i++) set[ids[i]] = true;
                Config.ownedCommunityIdSet = set;
            },
            function (err) { /* offline / failed, keep last-known set */ });
    }

    // --- Push / local notification handles (created dynamically) ---
    property var  sysNotif:   null   // Lomiri.Notifications Notification
    property var  pushClient: null   // Ubuntu.PushNotifications PushClient
    property string pushToken: ""
    property var  notifSound: null

    function _showNotif(body) {
        // Lazy, not at startup: constructing QtMultimedia Audio SIGSEGVs on an icon relaunch
        if (!root.notifSound) {
            try {
                root.notifSound = Qt.createQmlObject(
                    'import QtMultimedia 5.6; Audio { autoPlay: false }', root, "notifSound")
            } catch (e) { /* QtMultimedia unavailable, stay silent */ }
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
            function () { Session.setLastPushRegisterAt(Date.now()); },
            function ()  { /* silent; retried on next app launch */ })
    }

    // re-send daily — catches a silently expired/rotated token
    readonly property int pushReRegisterIntervalMs: 24 * 60 * 60 * 1000
    function _maybeReRegisterPush() {
        if (!Session.isLoggedIn || !root.pushClient) return;
        var t = root.pushClient.token;
        if (!t) return;
        if (Date.now() - Session.lastPushRegisterAt < root.pushReRegisterIntervalMs) return;
        root._registerPushToken(t);
    }

    function _initNotifications() {
        // Notification sound deliberately not created here (see _showNotif)

        try {
            root.sysNotif = Qt.createQmlObject(
                'import Lomiri.Notifications 1.0; Notification { summary: "Serey" }',
                root, "sysNotif")
        } catch (e) { /* Lomiri.Notifications not available on desktop, expected */ }

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

            // already shown by the OS — just clear, don't re-alert
            root.pushClient.notificationsChanged.connect(function () {
                var notifs = root.pushClient.notifications
                if (notifs.length > 0) {
                    NotificationState.unread = -1
                    root.pushClient.clearAll()
                }
            })
        } catch (e) { console.warn("Push: PushClient failed to create:", e) }
    }

    // re-check push token on foreground
    Connections {
        target: Qt.application
        onStateChanged: {
            if (Qt.application.state === Qt.ApplicationActive && root.startupSettled)
                root._maybeReRegisterPush();
        }
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

    // Catches crypto payments made after the sheet or app closed; PaymentSheet polls while open
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
                        // Still waiting/confirming; keep checking a day past expiry for late confirmations
                        var exp = Date.parse(p.expiresAt)
                        if (!isNaN(exp) && Date.now() > exp + 24 * 3600 * 1000)
                            Payments.clearPendingCrypto()
                    }
                },
                function () { /* transient, next tick retries */ })
        }
    }

    Connections {
        target: Session
        // Keyed off the token (not isLoggedIn) so account switches resync; one account's blocks must never leak into another's feed.
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
            // tab may already equal currentTab (no change signal); ensure explicitly.
            root._ensureTab(tab);
            while (settingsStack.depth > 1)
                settingsStack.pop();
        }
        // Buy-plan -> create-platform funnel; wizard re-checks the now-active subscription
        function onCreatePlatform() {
            root.currentTab = 3;
            root._ensureTab(3);
            while (settingsStack.depth > 1)
                settingsStack.pop();
            settingsStack.push(Qt.resolvedUrl("pages/CreatePlatformPage.qml"));
        }
        // Category badge tapped: switch community, then jump to the blog tab.
        function onFilterCategory(category, community) {
            Nav.pendingCategory = category;
            if (community) Config.selectedSubCommunity = community;
            root.currentTab = 1;
            root._ensureTab(1);
            while (newsStack.depth > 1)
                newsStack.pop();
        }
        // Fresh login/signup: land on Homepage tab with My Feed pushed on top.
        function onGoToFeed() {
            root.currentTab = 0;
            root._ensureTab(0);
            while (settingsStack.depth > 1)
                settingsStack.pop();
            while (homeStack.depth > 1)
                homeStack.pop();
            homeStack.pushMaster(Qt.resolvedUrl("pages/FeedPage.qml"));
        }
        // An offline panel asked for the on-device library.
        function onOpenLibrary() { root.openLibrary(); }
        // Invite link opened in-app: redeem it natively on the Homepage tab.
        function onRedeemInvite(code) {
            root.currentTab = 0;
            root._ensureTab(0);
            while (homeStack.depth > 1)
                homeStack.pop();
            homeStack.push(Qt.resolvedUrl("pages/RedeemInvitePage.qml"), { prefillCode: code });
        }
    }

    AppHeader {
        id: appHeader
        anchors { left: root.wideMode ? sideNavBar.right : parent.left; right: parent.right; top: parent.top }
        height: root.showHeader ? units.gu(6) : 0
        visible: root.showHeader
        wide: root.wideMode
        onCommunityButtonClicked: communityPicker.open()

        center: AbstractButton {
            id: feedBtn
            visible: Session.isLoggedIn && !root.feedPageOpen
            anchors.centerIn: parent
            // Tap target fills header height for comfort; icon keeps smaller visual size
            width: units.gu(6)
            height: width
            // Destination, not a detail: it takes the leading column and opens posts beside itself.
            onClicked: root.activeStack.pushMaster(Qt.resolvedUrl("pages/FeedPage.qml"))
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
                    postCommunityPicker.openFor(function (target) {
                        var props = target ? { targetCommunity: target } : {};
                        var ed = newsStack.push(Qt.resolvedUrl("pages/CreatePostPage.qml"), props);
                        if (ed && ed.saved && np)
                            ed.saved.connect(function (isNew) {
                                // New post -> jump to Latest so it shows at the top; edit -> just reload.
                                if (isNew && np.showLatest) np.showLatest();
                                else if (np.reload) np.reload();
                            });
                    // desktop only: anchors the dropdown
                    }, root.desktopMode ? composeBtn : null);
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
                    // Target the Video master page; currentPage in split mode has no reload()
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

        // Zero-height while online, so the stacks below keep one fixed anchor either way.
        OfflineBanner {
            id: offlineBanner
            anchors { top: parent.top; left: parent.left; right: parent.right }
            z: 1
            // The Homepage draws its own offline panel, and anything opened from the device
            // (the library, a downloaded video, a saved article) is already the offline
            // answer: saying "you're offline" on top of it is just noise.
            suppressed: (root.currentTab === 0 && homeStack.depth <= 1) || root._onDeviceContent
            onOpenLibrary: root.openLibrary()
        }

        AdaptiveStack {
            id: homeStack
            // The web app is the panel, never split; sub-pages cover it full-screen instead
            neverSplit: true
            anchors.fill: parent
            anchors.topMargin: offlineBanner.height
            visible: root.currentTab === 0
            Component.onCompleted: push(Qt.resolvedUrl("pages/HomepagePage.qml"))
        }
        // News/Video/Settings are filled lazily by _ensureTab() on first visit.
        AdaptiveStack {
            id: newsStack
            emptyDetailIconName: "stock_note"
            emptyDetailMessage: Lang.tr("Select a post to read")
            anchors.fill: parent
            anchors.topMargin: offlineBanner.height
            visible: root.currentTab === 1
        }
        AdaptiveStack {
            id: videoStack
            emptyDetailIconName: "camcorder"
            emptyDetailMessage: Lang.tr("Select a video to watch")
            anchors.fill: parent
            anchors.topMargin: offlineBanner.height
            visible: root.currentTab === 2
        }
        AdaptiveStack {
            id: settingsStack
            emptyDetailIconName: "settings"
            emptyDetailMessage: Lang.tr("Select a setting")
            anchors { top: parent.top; topMargin: offlineBanner.height; bottom: parent.bottom; left: parent.left; right: accountPanelDivider.visible ? accountPanelDivider.left : parent.right }
            visible: root.currentTab === 3
        }

        // Desktop-only (not tablet)
        readonly property bool _showAccountPanel: root.currentTab === 3 && root.desktopMode

        // Draggable splitter (Account status rail)
        readonly property real _minAccountPanelW: units.gu(30)
        readonly property real _maxAccountPanelW: Math.max(_minAccountPanelW, Math.min(body.width * 0.55, body.width - units.gu(45)))
        property real accountPanelWidth: units.gu(40)
        readonly property real _accountPanelW: Math.max(_minAccountPanelW, Math.min(_maxAccountPanelW, accountPanelWidth))

        Rectangle {
            id: accountPanelDivider
            anchors { top: parent.top; topMargin: offlineBanner.height; bottom: parent.bottom; right: accountStatusPanel.left }
            width: units.dp(1)
            visible: accountStatusPanel.visible
            color: accountPanelDragArea.containsMouse || accountPanelDragArea.pressed ? Style.brand : Style.divider
        }
        MouseArea {
            id: accountPanelDragArea
            visible: accountStatusPanel.visible
            anchors { top: parent.top; topMargin: offlineBanner.height; bottom: parent.bottom }
            x: accountPanelDivider.x - width / 2
            width: units.gu(1.5)
            hoverEnabled: true
            preventStealing: true
            cursorShape: Qt.SplitHCursor
            onPositionChanged: {
                if (!pressed) return;
                var pointX = mapToItem(body, mouse.x, 0).x;
                body.accountPanelWidth = Math.max(body._minAccountPanelW, Math.min(body._maxAccountPanelW, body.width - pointX));
            }
        }

        // Account status rail (outside settingsStack's own split)
        AccountStatusPanel {
            id: accountStatusPanel
            anchors { top: parent.top; topMargin: offlineBanner.height; bottom: parent.bottom; right: parent.right }
            width: body._showAccountPanel ? body._accountPanelW : 0
            visible: body._showAccountPanel
            profile: settingsStack.rootPage ? settingsStack.rootPage.profile : null
            pageStack: settingsStack
        }
    }

    // Ctrl+1..4 switch tabs; must MOVE focus too or it stays trapped in the Homepage Chromium view.
    // fromKeyboard gates the visible keyboard-cursor ring: mouse clicks move focus quietly.
    function switchTab(i, fromKeyboard) { root.currentTab = i; Qt.callLater(function () { root.focusActiveContent(!!fromKeyboard); }); }

    Shortcut { sequence: "Ctrl+1"; enabled: root.showNavBar; onActivated: root.switchTab(0, true) }
    Shortcut { sequence: "Ctrl+2"; enabled: root.showNavBar; onActivated: root.switchTab(1, true) }
    Shortcut { sequence: "Ctrl+3"; enabled: root.showNavBar; onActivated: root.switchTab(2, true) }
    Shortcut { sequence: "Ctrl+4"; enabled: root.showNavBar; onActivated: root.switchTab(3, true) }

    // Ctrl+Tab cycling via StandardKey; shortcuts fire before focused item, so it's the only way in from the Homepage view
    Shortcut {
        sequence: StandardKey.NextChild
        enabled: root.showNavBar
        onActivated: root.switchTab((root.currentTab + 1) % root._tabs.length, true)
    }
    Shortcut {
        sequence: StandardKey.PreviousChild
        enabled: root.showNavBar
        onActivated: root.switchTab((root.currentTab - 1 + root._tabs.length) % root._tabs.length, true)
    }

    // F6 jumps to the tab nav from anywhere; escape hatch from the Homepage view which swallows Tab/arrows
    Shortcut { sequence: "F6"; enabled: root.showNavBar; onActivated: root.focusNavRail() }

    // Focus the active tab's button in whichever nav layout is showing.
    function focusNavRail() {
        var rep = root.wideMode ? railRep : navRep;
        var it = rep.itemAt(root.currentTab);
        if (it) it.keyArea.forceActiveFocus();
    }
    // Focus active tab's content page; fromKeyboard shows the list cursor ring, otherwise focus moves quietly (mouse entry)
    function focusActiveContent(fromKeyboard) {
        var stack = root.currentTab === 0 ? homeStack
                  : root.currentTab === 1 ? newsStack
                  : root.currentTab === 2 ? videoStack
                  : settingsStack;
        var p = stack.rootPage;
        if (!p) return;
        if (fromKeyboard && p.focusListKeyNav) { p.focusListKeyNav(); return; }
        (p.keyboardFocusItem ? p.keyboardFocusItem : p).forceActiveFocus();
    }
    Connections {
        target: Nav
        function onFocusNav() { root.focusNavRail(); }
        function onFocusContent() { root.focusActiveContent(); }
        // Only the Settings tab currently has a persistent right rail outside its AdaptiveStack.
        function onFocusRightPanel() { if (body._showAccountPanel) accountStatusPanel.focusPanel(); }
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
                    // Route click through switchTab() (moves focus too)
                    onClicked: root.switchTab(index)
                    KeyTapArea {
                        id: navTap
                        // Enter always drops into the tab's content, even when already active
                        onActivated: root.switchTab(index, true)
                        // Horizontal bar: Left/Right walk the tabs
                        onLeftPressed:  { var it = navRep.itemAt(index - 1); if (it) it.keyArea.forceActiveFocus(); }
                        onRightPressed: { var it = navRep.itemAt(index + 1); if (it) it.keyArea.forceActiveFocus(); }
                    }
                }
            }
        }
    }

    // Side navigation: full-height vertical rail (convergence, not scaling); icon-only on tablet
    Rectangle {
        id: sideNavBar
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: (root.showNavBar && root.wideMode) ? (root.desktopMode ? units.gu(20) : units.gu(8)) : 0
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
                    height: units.gu(6)
                    property bool active: root.currentTab === index
                    property alias keyArea: railTap

                    Row {
                        // Centered icon-only (tablet) or left-aligned with label (desktop)
                        anchors.verticalCenter: parent.verticalCenter
                        x: root.desktopMode ? units.gu(2) : (parent.width - width) / 2
                        spacing: units.gu(1.5)

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: units.gu(3.2)
                            height: width
                            name: modelData.icon
                            color: active ? Style.brand : Style.textSecondary
                        }
                        Label {
                            visible: root.desktopMode
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            font.pixelSize: Style.fontMedium
                            font.weight: active ? Font.DemiBold : Font.Normal
                            color: active ? Style.brand : Style.textSecondary
                        }
                    }
                    // Same fix as navRep
                    onClicked: root.switchTab(index)
                    KeyTapArea {
                        id: railTap
                        // Enter always drops into the tab's content, even when already active
                        onActivated: root.switchTab(index, true)
                        // Vertical rail: Up/Down walk the tabs; Right steps into content (mirrors list -> detail)
                        onUpPressed:   { var it = railRep.itemAt(index - 1); if (it) it.keyArea.forceActiveFocus(); }
                        onDownPressed: { var it = railRep.itemAt(index + 1); if (it) it.keyArea.forceActiveFocus(); }
                        onRightPressed: root.focusActiveContent(true)
                    }
                }
            }
        }
    }

    CommunityPicker { id: communityPicker; anchorItem: appHeader.communityButton }
    PostCommunityPicker { id: postCommunityPicker }
    PostActionSheet { }
    ShareSheet { }
    PaymentSheet { }
    StripeCheckoutSheet { }
    Toaster { }
}
