import QtQuick 2.7
import Lomiri.Components 1.3
import "Theme"
import "Session"
import "components"
import "services/CommunityService.js" as CommunityService
import "services/AccountService.js" as AccountService

/*
 * Application shell: a persistent bottom tab bar with one PageStack per tab so
 * each section keeps its own navigation history. On launch we validate any
 * stored auth token in the background.
 */
MainView {
    id: root
    objectName: "mainView"
    applicationName: "serey.draxler"
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
                            : currentTab === 2 ? galleryStack.depth
                            : currentTab === 3 ? videoStack.depth
                            : settingsStack.depth
    readonly property bool showHeader: activeDepth <= 1 && currentTab !== 4
    readonly property bool showNavBar: activeDepth <= 1

    Component.onCompleted: {
        // NOTE: we deliberately do NOT validate the token via /auth/authenticated
        // on startup. That endpoint additionally requires a *device* JWT
        // (isDeviceJwtAuthenticated) which the native client never has, so it
        // always returns 401 — calling it would wrongly clear a perfectly valid
        // session on every launch (the original "logged out on reopen" bug). The
        // stored token is trusted; it works for every endpoint the app uses
        // (those need only isJwtAuthenticated). A genuinely stale token simply
        // surfaces as a normal API error when used.
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
            id: galleryStack
            anchors.fill: parent
            visible: root.currentTab === 2
            Component.onCompleted: push(Qt.resolvedUrl("pages/GalleryPage.qml"))
        }
        PageStack {
            id: videoStack
            anchors.fill: parent
            visible: root.currentTab === 3
            Component.onCompleted: push(Qt.resolvedUrl("pages/VideoPage.qml"))
        }
        PageStack {
            id: settingsStack
            anchors.fill: parent
            visible: root.currentTab === 4
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
                    { label: i18n.tr("Gallery"),  icon: "image-x-generic-symbolic" },
                    { label: i18n.tr("Video"),    icon: "camcorder" },
                    { label: i18n.tr("Settings"), icon: "settings" }
                ]
                delegate: AbstractButton {
                    width: navBar.width / 5
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
