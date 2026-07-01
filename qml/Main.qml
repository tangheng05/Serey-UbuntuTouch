import QtQuick 2.7
import Lomiri.Components 1.3
// Lomiri.Notifications and Ubuntu.PushNotifications are only available on a
// real Ubuntu Touch device, not in the clickable desktop container. We load
// them dynamically so the desktop build doesn't crash.
import "Theme"
import "Session"
import "components"
import "services/CommunityService.js" as CommunityService
import "services/AccountService.js" as AccountService
import "services/Http.js" as Http
import "services/NotificationService.js" as NotificationService
import "services/BlockedUsers.js" as BlockedUsers

/*
 * Application shell: a persistent bottom tab bar with one PageStack per tab so
 * each section keeps its own navigation history. On launch we validate any
 * stored auth token in the background.
 */
MainView {
    id: root
    objectName: "mainView"
    applicationName: "serey.ubuntu"
    automaticOrientation: true

    width: units.gu(45)
    height: units.gu(80)

    property int currentTab: 0
    onCurrentTabChanged: { Config.currentTab = currentTab; body.opacity = 0; tabFadeIn.start(); }
    NumberAnimation { id: tabFadeIn; target: body; property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutQuad }

    // Depth of the active tab's stack. The global header only shows at a tab's
    // root (depth 1); pushed sub-pages (detail/login) bring their own back-bar.
    property int activeDepth: currentTab === 0 ? homeStack.depth
                            : currentTab === 1 ? newsStack.depth
                            : currentTab === 2 ? videoStack.depth
                            : settingsStack.depth
    readonly property bool showHeader: activeDepth <= 1 && currentTab !== 3
    readonly property bool showNavBar: activeDepth <= 1

    Component.onCompleted: {
        // A stale/expired JWT can't be detected up-front (see note below), so
        // catch it lazily: any authed request that comes back 401 clears the
        // session and prompts re-login, instead of leaving the user "logged in"
        // with a dead token while publishing etc. silently fail. Guarded on
        // isLoggedIn so concurrent 401s only clear + toast once.
        Http.setUnauthorizedHandler(function () {
            if (!Session.isLoggedIn) return;
            Session.clear();
            Toast.error(i18n.tr("Your session expired. Please log in again."));
        });

        // NOTE: we deliberately do NOT validate the token via /auth/authenticated
        // on startup. That endpoint additionally requires a *device* JWT
        // (isDeviceJwtAuthenticated) which the native client never has, so it
        // always returns 401 — calling it would wrongly clear a perfectly valid
        // session on every launch (the original "logged out on reopen" bug). The
        // stored token is trusted; it works for every endpoint the app uses
        // (those need only isJwtAuthenticated). A genuinely stale token simply
        // surfaces as a normal API error when used.
        _initNotifications()

        CommunityService.listAll(Config.baseUrl,
            function (list) {
                Config.iconByDns = CommunityService.iconMap(list);
                Config.allowPostByDns = CommunityService.allowPostMap(list);
            },
            function (err) { /* keep globe fallback */ });

        // A persisted session only carries token + username (see Session.qml);
        // refetch the avatar so optimistic local comments can show it.
        if (Session.isLoggedIn) {
            AccountService.profile(Config.baseUrl, Session.username, Session.token,
                function (user) { Session.avatarUrl = user.profileUrl; },
                function (err) { /* keep letter-fallback avatar */ });
        }
        _syncBlockedUsers();
    }

    // Keep the local blocked-users set (used to filter feeds) in step with the
    // server's authoritative list — on launch and whenever the session changes.
    function _syncBlockedUsers() {
        if (!Session.isLoggedIn) { BlockedUsers.replaceAll([]); return; }
        AccountService.listBlocked(Config.baseUrl, Session.token,
            function (list) { BlockedUsers.replaceAll(list); },
            function (err) { /* offline / failed — keep last-known local set */ });
    }

    // ── Push / local notification handles (created dynamically) ─────────────
    property var  sysNotif:   null   // Lomiri.Notifications Notification
    property var  pushClient: null   // Ubuntu.PushNotifications PushClient
    property string pushToken: ""
    property int  lastUnreadCount: -1
    property var  notifSound: null

    function _showNotif(body) {
        // Play sound
        if (root.notifSound) root.notifSound.play()

        // System notification (lock screen / indicator)
        if (root.sysNotif) {
            root.sysNotif.body = body
            root.sysNotif.show()
        }

        // In-app toast (always works)
        Toast.show(body)
    }

    function _registerPushToken(pt) {
        NotificationService.registerPushToken(Config.baseUrl, Session.token, pt,
            function () { /* fire-and-forget */ },
            function ()  { /* silent — retry on next app launch */ })
    }

    function _initNotifications() {
        // Notification sound (QtMultimedia Audio for ogg support)
        try {
            root.notifSound = Qt.createQmlObject(
                'import QtMultimedia 5.6; Audio { source: "/usr/share/sounds/lomiri/notifications/Xylo.ogg"; autoPlay: false }',
                root, "notifSound")
        } catch (e) { /* QtMultimedia not available — silent */ }

        // System notification (indicator + lock screen)
        try {
            root.sysNotif = Qt.createQmlObject(
                'import Lomiri.Notifications 1.0; Notification { summary: "Serey" }',
                root, "sysNotif")
        } catch (e) { /* Lomiri.Notifications not available on desktop — expected */ }

        // Push client for background delivery
        try {
            root.pushClient = Qt.createQmlObject(
                'import Ubuntu.PushNotifications 0.1; PushClient {' +
                '  appId: "serey.ubuntu_serey"; }',
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
                        ? i18n.tr("You have 1 new notification")
                        : i18n.tr("You have %1 new notifications").arg(notifs.length)
                    root._showNotif(msg)
                    root.lastUnreadCount = -1
                    root.pushClient.clearAll()
                }
            })
        } catch (e) { console.warn("Push: PushClient failed to create:", e) }
    }

    // Poll every 60 s while logged in
    Timer {
        id: notifPoller
        interval: 30000
        repeat: true
        running: Session.isLoggedIn && Session.pushEnabled
        triggeredOnStart: true
        onTriggered: {
            if (!Session.isLoggedIn || !Session.pushEnabled) return
            NotificationService.listSerey(Config.baseUrl, Session.token, 50, 0,
                function (items) {
                    var count = 0
                    for (var i = 0; i < items.length; i++) {
                        if (!items[i].is_read) count++
                    }
                    if (root.lastUnreadCount < 0) { root.lastUnreadCount = count; return }
                    if (count > root.lastUnreadCount) {
                        var diff = count - root.lastUnreadCount
                        root._showNotif(diff === 1
                            ? i18n.tr("You have 1 new notification")
                            : i18n.tr("You have %1 new notifications").arg(diff))
                    }
                    root.lastUnreadCount = count
                },
                function (err) { /* silent */ })
        }
    }

    Connections {
        target: Session
        // The blocked set is per-account; resync (or clear) it whenever the auth
        // token changes. Keying off the token (not isLoggedIn) means switching
        // accounts reloads the new account's blocks even if the token is swapped
        // directly, so one account's blocks never leak into another's feed.
        function onTokenChanged() { root._syncBlockedUsers() }
        function onIsLoggedInChanged() {
            // Blocked-set sync is handled by onTokenChanged (token always changes
            // on login/logout/switch), so it isn't repeated here.
            if (!Session.isLoggedIn) {
                root.lastUnreadCount = -1
            } else if (root.pushToken !== "") {
                root._registerPushToken(root.pushToken)
            }
        }
    }

    // A page requested a tab switch (e.g. signup success → Homepage). Switch
    // tabs and unwind the Settings stack the auth flow was pushed onto, so we
    // don't leave the signup pages behind it.
    Connections {
        target: Nav
        function onGoToTab(tab) {
            root.currentTab = tab;
            while (settingsStack.depth > 1)
                settingsStack.pop();
        }
    }

    // --- Global header (community pill + logo) ----------------------------
    AppHeader {
        id: appHeader
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: root.showHeader ? units.gu(6) : 0
        visible: root.showHeader
        onCommunityButtonClicked: communityPicker.open()

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacingS

            // Compose (News tab only) — Lomiri header action, replacing the old
            // Material floating button. Reloads the feed once a post is saved.
            AbstractButton {
                id: composeBtn
                visible: Session.isLoggedIn && root.currentTab === 1
                anchors.verticalCenter: parent.verticalCenter
                width: units.gu(4); height: width
                onClicked: {
                    var np = newsStack.currentPage;
                    var ed = newsStack.push(Qt.resolvedUrl("pages/CreatePostPage.qml"));
                    if (ed && ed.saved && np && np.reload) ed.saved.connect(np.reload);
                }
                Icon {
                    anchors.centerIn: parent
                    width: units.gu(2.8); height: width
                    name: "edit"
                    color: Style.brand
                }
            }

            // Upload video (Video tab only) — Lomiri header action, replacing the
            // old Material floating button on VideoPage.
            AbstractButton {
                id: uploadBtn
                // Only when the selected community allows posting (is_allow_post);
                // hidden for Global and owner-only communities.
                visible: Session.isLoggedIn && root.currentTab === 2 && Config.canPostCurrent
                anchors.verticalCenter: parent.verticalCenter
                width: units.gu(4); height: width
                onClicked: {
                    var vp = videoStack.currentPage;
                    var ed = videoStack.push(Qt.resolvedUrl("pages/CreateVideoPage.qml"));
                    if (ed && ed.saved && vp && vp.reload) ed.saved.connect(vp.reload);
                }
                Icon {
                    anchors.centerIn: parent
                    width: units.gu(2.8); height: width
                    name: "add"
                    color: Style.brand
                }
            }

            AbstractButton {
                id: feedBtn
                visible: Session.isLoggedIn
                anchors.verticalCenter: parent.verticalCenter
                width: units.gu(4); height: width
                onClicked: {
                    var stack = root.currentTab === 0 ? homeStack
                              : root.currentTab === 1 ? newsStack
                              : root.currentTab === 2 ? videoStack
                              : settingsStack;
                    stack.push(Qt.resolvedUrl("pages/FeedPage.qml"));
                }
                Image {
                    anchors.centerIn: parent
                    width: units.gu(3.5); height: width
                    source: Qt.resolvedUrl("../assets/iconFeed.png")
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
            }
        }
    }

    // --- Content area: four stacks, only the active one visible ----------
    Item {
        id: body
        anchors {
            left: parent.left
            right: parent.right
            top: appHeader.bottom
            bottom: root.showNavBar ? navBar.top : parent.bottom
        }

        PageStack {
            id: homeStack
            anchors.fill: parent
            visible: root.currentTab === 0
            Component.onCompleted: push(Qt.resolvedUrl("pages/HomepagePage.qml"))
        }
        PageStack {
            id: newsStack
            anchors.fill: parent
            visible: root.currentTab === 1
            Component.onCompleted: push(Qt.resolvedUrl("pages/NewsPage.qml"))
        }
        PageStack {
            id: videoStack
            anchors.fill: parent
            visible: root.currentTab === 2
            Component.onCompleted: push(Qt.resolvedUrl("pages/VideoPage.qml"))
        }
        PageStack {
            id: settingsStack
            anchors.fill: parent
            visible: root.currentTab === 3
            Component.onCompleted: push(Qt.resolvedUrl("pages/SettingsPage.qml"))
        }
    }

    // --- Bottom navigation ------------------------------------------------
    Rectangle {
        id: navBar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: root.showNavBar ? units.gu(7) : 0
        visible: root.showNavBar
        color: Style.surface

        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: units.dp(1)
            color: Style.divider
        }

        Row {
            anchors.fill: parent

            Repeater {
                model: [
                    { label: i18n.tr("Homepage"), icon: "home" },
                    { label: i18n.tr("News"),     icon: "stock_note" },
                    { label: i18n.tr("Video"),    icon: "camcorder" },
                    { label: i18n.tr("Settings"), icon: "settings" }
                ]
                delegate: AbstractButton {
                    width: navBar.width / 4
                    height: navBar.height
                    property bool active: root.currentTab === index

                    Icon {
                        anchors.centerIn: parent
                        width: units.gu(3)
                        height: width
                        name: modelData.icon
                        color: active ? Style.brand : Style.textSecondary
                    }
                    onClicked: root.currentTab = index
                }
            }
        }
    }

    // --- Community / source selector (bottom sheet) overlay ---------------
    CommunityPicker { id: communityPicker }

    // --- Post actions (Report / Hide / Block) bottom sheet ----------------
    PostActionSheet { }

    // --- Transient notifications (snackbar) overlay -----------------------
    Toaster { }
}
