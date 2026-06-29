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
    onCurrentTabChanged: { body.opacity = 0; tabFadeIn.start(); }
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
            function (list) { Config.iconByDns = CommunityService.iconMap(list); },
            function (err) { /* keep globe fallback */ });

        // A persisted session only carries token + username (see Session.qml);
        // refetch the avatar so optimistic local comments can show it.
        if (Session.isLoggedIn) {
            AccountService.profile(Config.baseUrl, Session.username, Session.token,
                function (user) { Session.avatarUrl = user.profileUrl; },
                function (err) { /* keep letter-fallback avatar */ });
        }
    }

    // ── Push / local notification handles (created dynamically) ─────────────
    property var  sysNotif:   null   // Lomiri.Notifications Notification
    property var  pushClient: null   // Ubuntu.PushNotifications PushClient
    property string pushToken: ""
    property int  lastUnreadCount: 0

    function _showNotif(body) {
        if (!root.sysNotif) return
        root.sysNotif.body = body
        root.sysNotif.show()
    }

    function _registerPushToken(pt) {
        NotificationService.registerPushToken(Config.baseUrl, Session.token, pt,
            function () { /* fire-and-forget */ },
            function ()  { /* silent — retry on next app launch */ })
    }

    function _initNotifications() {
        // Local notification object
        try {
            root.sysNotif = Qt.createQmlObject(
                'import Lomiri.Notifications 1.0; Notification {' +
                '  summary: "Serey";' +
                '  icon: Qt.resolvedUrl("../assets/serey-logo.png"); }',
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
                    root.lastUnreadCount = 0   // force re-check on next poll
                    root.pushClient.clearAll()
                }
            })
        } catch (e) { /* Ubuntu.PushNotifications not available on desktop — expected */ }
    }

    // Poll every 60 s while logged in — fallback when push isn't available and
    // keeps the in-app badge up to date even on device.
    Timer {
        id: notifPoller
        interval: 60000
        repeat: true
        running: Session.isLoggedIn
        triggeredOnStart: true
        onTriggered: {
            if (!Session.isLoggedIn) return
            NotificationService.unreadCount(Config.baseUrl, Session.token,
                function (count) {
                    if (count > root.lastUnreadCount) {
                        var body = count === 1
                            ? i18n.tr("You have 1 new notification")
                            : i18n.tr("You have %1 new notifications").arg(count)
                        root._showNotif(body)
                    }
                    root.lastUnreadCount = count
                },
                function (err) { /* silent */ })
        }
    }

    Connections {
        target: Session
        function onIsLoggedInChanged() {
            if (!Session.isLoggedIn) {
                root.lastUnreadCount = 0
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
