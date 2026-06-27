import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/AccountService.js" as AccountService

/*
 * Settings, in the iOS Serey app's grouped style: a welcome/identity header, then
 * sections (Account · Preferences · About) of rows, each with a circular icon
 * badge, label, and a trailing control/value/chevron. Signed out shows Log in /
 * Sign up; signed in shows the profile identity + stats and a Log out row.
 */
Page {
    id: page

    property var profile: null
    property bool loading: false
    property string errorMsg: ""

    // Zero-height header: the global AppHeader is the real top bar.
    header: Item { height: 0 }

    function refreshProfile() {
        if (!Session.isLoggedIn) { profile = null; return; }
        loading = true;
        errorMsg = "";
        AccountService.profile(Config.baseUrl, Session.username, Session.token,
            function (user) { loading = false; page.profile = user; },
            function (err) { loading = false; page.errorMsg = err.message; });
    }

    function doLogout() {
        if (Session.token.length > 0)
            AccountService.logout(Config.baseUrl, Session.token, function () {}, function () {});
        Session.clear();
        FollowStore.reset();
        page.profile = null;
    }

    Component.onCompleted: refreshProfile()

    // Re-fetch every time the Settings tab becomes active. The profile (incl. the
    // following/followers counts) is held in memory, and following someone happens
    // on another tab — so without this the count stays stale until something else
    // (token change, sub-page pop) forces a refresh. The backend invalidates the
    // profile cache on follow, so this re-fetch returns the up-to-date counts.
    onVisibleChanged: if (visible) refreshProfile()

    Connections {
        target: Session
        function onTokenChanged() { page.refreshProfile(); }
    }

    // Re-fetch when returning from a pushed sub-page (e.g. Edit profile) so the
    // header avatar/name reflect any just-saved changes.
    Connections {
        target: page.pageStack
        function onDepthChanged() {
            if (page.pageStack && page.pageStack.depth === 1)
                page.refreshProfile();
        }
    }

    // Confirm before logging out (logout is otherwise instant and unannounced).
    Component {
        id: logoutDialog
        Dialog {
            id: dlg
            title: i18n.tr("Log out?")
            text: i18n.tr("You'll need to sign in again to vote, comment, or follow.")

            Button {
                text: i18n.tr("Log out")
                color: Style.danger
                onClicked: { PopupUtils.close(dlg); page.doLogout(); }
            }
            Button {
                text: i18n.tr("Cancel")
                onClicked: PopupUtils.close(dlg)
            }
        }
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.height
        clip: true

        Column {
            id: col
            width: parent.width

            // ===== Cover banner + overlapping avatar (iOS style) ==========
            Item {
                width: parent.width
                height: Session.isLoggedIn ? units.gu(22) : units.gu(13)

                // Cover image
                Rectangle {
                    id: coverBanner
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    height: units.gu(16)
                    visible: Session.isLoggedIn
                    clip: true

                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Style.brand }
                            GradientStop { position: 1.0; color: Style.brandDark }
                        }
                    }
                    Image {
                        anchors.fill: parent
                        source: page.profile && page.profile.coverUrl ? page.profile.coverUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        autoTransform: true
                        sourceSize.width: parent.width
                        visible: status === Image.Ready
                    }
                }

                // Avatar overlapping cover bottom-left
                AbstractButton {
                    id: avatarBtn
                    anchors {
                        left: parent.left
                        leftMargin: Style.spacingM
                        bottom: coverBanner.bottom
                        bottomMargin: units.gu(-3)
                    }
                    width: units.gu(9); height: width
                    visible: Session.isLoggedIn
                    onClicked: page.pageStack.push(Qt.resolvedUrl("EditProfilePage.qml"), { initial: page.profile })

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Style.surface
                        border.width: units.dp(3)
                        border.color: Style.surface
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: units.dp(3)
                        radius: width / 2
                        color: Style.avatarTint("")
                        visible: !(page.profile && page.profile.profileUrl)

                        Label {
                            anchors.centerIn: parent
                            text: (page.profile && page.profile.username
                                   ? page.profile.username : "?").charAt(0).toUpperCase()
                            font.pixelSize: Style.fontTitle
                            font.bold: true
                            color: Style.brand
                        }
                    }
                    Item {
                        anchors.fill: parent
                        anchors.margins: units.dp(3)
                        visible: !!(page.profile && page.profile.profileUrl)
                        CircleImage {
                            anchors.fill: parent
                            source: page.profile && page.profile.profileUrl ? page.profile.profileUrl : ""
                            decode: units.gu(18)
                        }
                    }

                    // Camera cue badge
                    Rectangle {
                        anchors { right: parent.right; bottom: parent.bottom; bottomMargin: units.dp(2); rightMargin: units.dp(2) }
                        width: units.gu(2.6); height: width
                        radius: width / 2
                        color: Style.brand
                        border.width: units.dp(1.5); border.color: Style.surface
                        Icon {
                            anchors.centerIn: parent
                            width: units.gu(1.5); height: width
                            name: "camera-symbolic"
                            color: Style.textOnBrand
                        }
                    }
                }

                // Signed-out: simple welcome row
                Row {
                    visible: !Session.isLoggedIn
                    anchors {
                        left: parent.left; right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: Style.spacingM; rightMargin: Style.spacingM
                    }
                    spacing: Style.spacingM

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(7); height: width
                        radius: Style.cardRadius
                        color: Style.brand
                        Icon {
                            anchors.centerIn: parent
                            width: units.gu(3.5); height: width
                            name: "account"
                            color: Style.textOnBrand
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: units.dp(3)
                        Label {
                            text: i18n.tr("Welcome to Serey")
                            font.pixelSize: Style.fontLarge
                            font.weight: Font.DemiBold
                            font.family: Style.fontFamily
                            color: Style.textTitle
                        }
                        Row {
                            spacing: Style.spacingS
                            AbstractButton {
                                width: loginLbl.width; height: loginLbl.height
                                onClicked: page.pageStack.push(Qt.resolvedUrl("LoginPage.qml"))
                                Label {
                                    id: loginLbl
                                    text: i18n.tr("Log in")
                                    font.pixelSize: Style.fontRegular
                                    font.weight: Font.DemiBold
                                    color: Style.brand
                                }
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "·"
                                color: Style.textSecondary
                            }
                            AbstractButton {
                                width: signupLbl.width; height: signupLbl.height
                                onClicked: page.pageStack.push(Qt.resolvedUrl("CreateAccountPage.qml"))
                                Label {
                                    id: signupLbl
                                    text: i18n.tr("Sign up")
                                    font.pixelSize: Style.fontRegular
                                    font.weight: Font.DemiBold
                                    color: Style.brand
                                }
                            }
                        }
                    }
                }
            }

            // Name + @username (below avatar, signed-in only)
            Column {
                visible: Session.isLoggedIn
                width: parent.width - Style.spacingM * 2
                x: Style.spacingM
                spacing: units.dp(2)

                Label {
                    width: parent.width
                    text: (page.profile && page.profile.fullName) ? page.profile.fullName
                          : (page.profile ? page.profile.username : Session.username)
                    font.pixelSize: Style.fontLarge
                    font.weight: Font.DemiBold
                    font.family: Style.fontFamily
                    color: Style.textTitle
                    elide: Text.ElideRight
                }
                Label {
                    width: parent.width
                    text: page.profile ? ("@" + page.profile.username) : ("@" + Session.username)
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFamily
                    color: Style.textSecondary
                    elide: Text.ElideRight
                }
            }

            Item { width: 1; height: Style.spacingS; visible: Session.isLoggedIn }

            // Stats strip: Posts · Followers · Following
            Rectangle { width: parent.width; height: units.dp(1); color: Style.divider; visible: Session.isLoggedIn && page.profile !== null }
            Row {
                width: parent.width
                height: units.gu(7)
                visible: Session.isLoggedIn && page.profile !== null
                Repeater {
                    model: page.profile ? [
                        { label: i18n.tr("Posts"),     value: "" + page.profile.postCount },
                        { label: i18n.tr("Followers"), value: "" + page.profile.followers },
                        { label: i18n.tr("Following"), value: "" + page.profile.following }
                    ] : []
                    delegate: Column {
                        width: parent.width / 3
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: units.dp(2)
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.value
                            font.pixelSize: Style.fontLarge
                            font.weight: Font.DemiBold
                            font.family: Style.fontFamily
                            color: Style.textPrimary
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.label
                            font.pixelSize: Style.fontXSmall
                            font.family: Style.fontFamily
                            color: Style.textSecondary
                        }
                    }
                }
            }

            // ===== Preferences ============================================
            SettingsSectionHeader { text: i18n.tr("Preferences") }

            SettingsRow {
                iconName: "settings"
                label: i18n.tr("Use local dev server")
                showSwitch: true
                switchChecked: Config.useLocalDev
                onSwitchToggled: Config.useLocalDev = checked
            }
            Item {
                width: parent.width
                height: units.gu(4)
                Label {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                              leftMargin: units.gu(8); rightMargin: Style.spacingM }
                    text: Config.baseUrl
                    font.pixelSize: Style.fontXSmall
                    font.family: Style.fontFamily
                    color: Style.textSecondary
                    elide: Text.ElideRight
                }
            }

            // ===== About ==================================================
            SettingsSectionHeader { text: i18n.tr("About") }

            SettingsRow {
                iconName: "info"
                label: i18n.tr("Version")
                valueText: "0.1.0"
            }
            SettingsRow {
                iconName: "external-link"
                label: i18n.tr("Serey website")
                showChevron: true
                onClicked: Qt.openUrlExternally("https://serey.io")
            }

            // ===== Account ================================================
            SettingsSectionHeader { text: i18n.tr("Account"); visible: Session.isLoggedIn }
            SettingsRow {
                visible: Session.isLoggedIn
                iconName: "edit"
                label: i18n.tr("Edit profile")
                showChevron: true
                onClicked: page.pageStack.push(Qt.resolvedUrl("EditProfilePage.qml"), { initial: page.profile })
            }
            SettingsRow {
                visible: Session.isLoggedIn
                iconName: "system-log-out"
                label: i18n.tr("Log out")
                danger: true
                onClicked: PopupUtils.open(logoutDialog)
            }

            Item { width: 1; height: Style.spacingL }
        }
    }

    ActivityIndicator {
        anchors.centerIn: parent
        running: page.loading && page.profile === null
        visible: running
    }
}
