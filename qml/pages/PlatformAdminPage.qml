import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/LandingPageService.js" as LandingPageService
import "../services/LandingPageV2Service.js" as LandingPageV2Service
import "../services/CommunitySubscriberService.js" as CommunitySubscriberService
import "../services/CommunityService.js" as CommunityService
import "../services/PlatformService.js" as PlatformService

// CMS hub for community owners/managers, trimmed from the web "Serey CMS" hub (see docs/cms-endpoints-navbar-blog-video-platform.md)
Page {
    id: page

    // Adapt, not scale: banner stays full-bleed, actionable content caps to a centered column on wide windows
    readonly property real maxContentWidth: units.gu(60)

    // Platform identity shown at the top of the hub — for the MANAGED
    // community (Config.managedCommunityId), not whatever happens to be
    // selected in the picker (those can differ, e.g. picker on "Global" while
    // you own a specific sub-community). Resolved from the cached
    // get-communities tree (Config.communityInfoFor); only if that community
    // truly is the one currently selected do we fall back to the picker's
    // name/icon. loadPlatformIdentity() below refines both from the backend.
    readonly property var _managedInfo: Config.communityInfoFor(Config.managedCommunityId)
    property string platformName: page._managedInfo ? page._managedInfo.title
        : (Config.managedCommunityId === Config.communityId ? Config.currentCommunityName : "")
    property string platformLogoUrl: page._managedInfo ? page._managedInfo.icon
        : (Config.managedCommunityId === Config.communityId ? Config.currentCommunityIconUrl : "")
    property int subscriberCount: 0
    property bool uploadingLogo: false
    // No banner (or hero section not loaded yet) falls back to a brand-colored
    // gradient rather than a blank strip. Read-only on mobile — the web CMS
    // owns editing it (see loadHeroBanner below for where it's fetched from).
    property string platformBannerUrl: ""

    // Inline rename (Settings > Edit Profile pattern)
    property bool savingName: false
    readonly property string nameText: nameField.text.trim()
    readonly property bool nameValid: nameText.length >= 2 && /^[a-zA-Z0-9 ]+$/.test(nameText)
    readonly property bool nameChanged: page.platformName.length > 0 && nameText !== page.platformName

    function saveName() {
        if (savingName || !nameValid || !nameChanged) return
        savingName = true
        PlatformService.updateCommunityName(Config.baseUrl, Session.token,
            Config.managedCommunityId, nameText,
            function () {
                page.savingName = false
                page.platformName = page.nameText
                Toast.success(Lang.tr("Platform name updated."))
            },
            function (err) {
                page.savingName = false
                Toast.error((err && err.message) || Lang.tr("Couldn't update the name."))
            })
    }

    header: PageHeader {
        title: Lang.tr("Manage your platform")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.pageStack.pop() }
        ]
    }

    function loadPlatformIdentity() {
        LandingPageService.getByCommunity(Config.baseUrl, Config.managedCommunityId, Session.token,
            function (data) {
                if (data.title || data.site_title) page.platformName = data.title || data.site_title
                var logo = data.logo || data.logo_url || data.icon_url || data.image
                if (logo) page.platformLogoUrl = logo
            },
            function () { /* non-fatal: keep the picker fallback */ })
        CommunitySubscriberService.subscriberCount(Config.baseUrl, Config.managedCommunityId,
            function (count) { page.subscriberCount = count },
            function () { /* non-fatal: keep 0 */ })
        page.loadHeroBanner()
    }

    // GET /landing-page-v2/get-by-community/:id — the hero section's photo
    // renders behind the logo (landing_page_v2_section.js). bg_image_url is a
    // separate background-overlay field that's commonly unset, so prefer the
    // section's actual image_url (confirmed via a live response: bg_image_url
    // was "" while image_url held the real hero photo). Read-only display —
    // editing the banner is left to the web CMS.
    function loadHeroBanner() {
        LandingPageV2Service.getByCommunity(Config.baseUrl, Config.managedCommunityId, Session.token,
            function (sections) {
                var hero = LandingPageV2Service.findHeroSection(sections)
                page.platformBannerUrl = (hero && (hero.bg_image_url || hero.image_url)) || ""
            },
            function () { /* non-fatal: no landing page v2 content yet — keep gradient */ })
    }

    // POST /community/update-logo (JWT). Uploads through the same
    // downscale-then-host flow as EditProfilePage's avatar/cover.
    function uploadLogo(fileUrl) {
        page.uploadingLogo = true
        logoUploader.upload(fileUrl)
    }

    // { id, title } for every community the user owns/manages, resolved from
    // the cached get-communities tree (Config.communityInfoFor). Backs the
    // "Switch Platform" picker, only shown when there's more than one.
    function ownedCommunitiesList() {
        var ids = Object.keys(Config.ownedCommunityIdSet)
        var out = []
        for (var i = 0; i < ids.length; i++) {
            var id = Number(ids[i])
            var info = Config.communityInfoFor(id)
            out.push({ id: id, title: info ? info.title : Lang.tr("Community #%1").arg(id) })
        }
        return out
    }

    function switchPlatform(id) {
        if (id === Config.managedCommunityId) return
        Config.overrideManagedCommunityId = id
        // Reset display state so the previous platform's data doesn't flash
        // while the new one's loads (platformName/platformLogoUrl/etc. were
        // already overwritten by loadPlatformIdentity's imperative assignment,
        // so their initial Config.communityInfoFor binding no longer applies).
        var info = Config.communityInfoFor(id)
        page.platformName = info ? info.title : ""
        page.platformLogoUrl = info ? info.icon : ""
        page.platformBannerUrl = ""
        page.subscriberCount = 0
        page.loadPlatformIdentity()
    }

    Component.onCompleted: page.loadPlatformIdentity()

    PhotoUploader {
        id: logoUploader
        onUploaded: {
            CommunityService.updateLogo(Config.baseUrl, Session.token, url,
                function () {
                    page.uploadingLogo = false
                    page.platformLogoUrl = url
                    Toast.success(Lang.tr("Logo updated."))
                },
                function (err) {
                    page.uploadingLogo = false
                    Toast.error(err.message || Lang.tr("Failed to update logo."))
                })
        }
        onFailed: {
            page.uploadingLogo = false
            Toast.error(message)
        }
    }

    Component {
        id: logoPickerComponent
        PhotoPicker {
            onPicked: page.uploadLogo(fileUrl)
        }
    }

    Component {
        id: switchPlatformDialog
        Dialog {
            id: dlg
            title: Lang.tr("Switch Platform")

            Repeater {
                model: page.ownedCommunitiesList()
                delegate: Button {
                    width: parent.width
                    text: modelData.title
                    color: modelData.id === Config.managedCommunityId ? Style.brand : Style.iconBackground
                    onClicked: {
                        PopupUtils.close(dlg)
                        page.switchPlatform(modelData.id)
                    }
                }
            }
            Button {
                text: Lang.tr("Cancel")
                onClicked: PopupUtils.close(dlg)
            }
        }
    }

    Flickable {
        anchors { top: page.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: column.height
        clip: true

        Column {
            id: column
            width: parent.width
            spacing: Style.spacingL
            bottomPadding: Style.spacingL

            // ===== Platform identity: banner + logo + name/switch/subscribers =====
            // Own Column (tight spacing) so the outer Style.spacingL section-gap
            // doesn't land between the logo and the name below it.
            Column {
                width: parent.width
                spacing: Style.spacingXs

                Item {
                    width: parent.width
                    height: bannerFallback.height + units.gu(4.5)   // banner + half the logo hanging below it

                    Rectangle {
                        id: bannerFallback
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        height: units.gu(14)
                        visible: bannerImg.status !== Image.Ready
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Style.brand }
                            GradientStop { position: 1.0; color: Style.brandDark }
                        }
                    }
                    Image {
                        id: bannerImg
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        height: bannerFallback.height
                        source: page.platformBannerUrl
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        clip: true
                        visible: status === Image.Ready
                    }

                    AbstractButton {
                        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: bannerFallback.height - units.gu(4.5) }
                        width: units.gu(9); height: width
                        enabled: !page.uploadingLogo
                        onClicked: PopupUtils.open(logoPickerComponent)

                        // White backing ring so the logo reads cleanly against the
                        // banner photo underneath (matches the web CMS reference).
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: Style.surface
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: Style.iconBackground
                            visible: !logoImage.loaded
                            Icon {
                                anchors.centerIn: parent
                                width: units.gu(4); height: width
                                name: "language-chooser"
                                color: Style.textSecondary
                            }
                        }
                        CircleImage {
                            id: logoImage
                            anchors.fill: parent
                            anchors.margins: units.dp(2)
                            source: page.platformLogoUrl
                            decode: units.gu(18)
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"
                            border.width: units.dp(1)
                            border.color: Style.divider
                        }

                        // "Manage Logo" camera badge (matches the web CMS hub).
                        Rectangle {
                            anchors { right: parent.right; bottom: parent.bottom }
                            width: units.gu(3.2); height: width
                            radius: width / 2
                            color: Style.brand
                            border.width: units.dp(2); border.color: Style.surface
                            Icon {
                                anchors.centerIn: parent
                                width: units.gu(1.8); height: width
                                name: "camera-symbolic"
                                color: Style.textOnBrand
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: Qt.rgba(0, 0, 0, 0.35)
                            visible: page.uploadingLogo
                            ActivityIndicator { anchors.centerIn: parent; running: page.uploadingLogo }
                        }
                    }
                }

                // Inline-editable platform name (tap to rename)
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: units.gu(30)
                    height: nameField.height

                    TextInput {
                        id: nameField
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: page.platformName
                        font.pixelSize: Style.fontLarge
                        font.weight: Font.DemiBold
                        font.family: Style.fontFor(text)
                        color: Style.textPrimary
                        onTextChanged: if (text.length > 60) text = text.substring(0, 60)
                        // Re-sync when platformName loads/changes from a switch, unless the user is mid-edit
                        Connections {
                            target: page
                            function onPlatformNameChanged() { if (!nameField.activeFocus) nameField.text = page.platformName }
                        }
                    }
                }
                Label {
                    visible: page.nameText.length > 0 && !page.nameValid
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: units.gu(30)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: Lang.tr("Use letters, numbers and spaces only.")
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
                    color: Style.danger
                }
                SecondaryButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: page.nameChanged
                    width: units.gu(30)
                    height: units.gu(4)
                    enabled: page.nameValid && !page.savingName
                    text: page.savingName ? Lang.tr("Saving…") : Lang.tr("Save name")
                    onClicked: page.saveName()
                }

                // "Switch Platform" — only shown when you own/manage more than one.
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: Object.keys(Config.ownedCommunityIdSet).length > 1
                    width: switchLabel.implicitWidth + Style.spacingM * 2
                    height: units.gu(3.2)
                    radius: Style.pillRadius
                    color: Style.iconBackground
                    border.width: units.dp(1)
                    border.color: Style.divider
                    AbstractButton {
                        anchors.fill: parent
                        onClicked: PopupUtils.open(switchPlatformDialog)
                        Label {
                            id: switchLabel
                            anchors.centerIn: parent
                            text: Lang.tr("Switch Platform")
                            font.pixelSize: Style.fontSmall
                            font.weight: Font.DemiBold
                            font.family: Style.fontFor(text)
                            color: Style.brand
                        }
                    }
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: subLabel.implicitWidth + Style.spacingM * 2
                    height: units.gu(3.2)
                    radius: Style.pillRadius
                    color: Style.iconBackground
                    Label {
                        id: subLabel
                        anchors.centerIn: parent
                        text: Lang.tr("%1 subscribers").arg(page.subscriberCount)
                        font.pixelSize: Style.fontSmall
                        font.family: Style.fontFor(text)
                        color: Style.textSecondary
                    }
                }
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Lang.tr("Manage and oversee your platform seamlessly from here")
                width: Math.min(parent.width, page.maxContentWidth) - Style.spacingL * 2
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.pixelSize: Style.fontRegular
                font.family: Style.fontFor(text)
                color: Style.textSecondary
            }

            // ===== Top cards: Platform Information / Platform Setting =======
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width, page.maxContentWidth) - Style.spacingL * 2
                spacing: Style.spacingM

                Rectangle {
                    width: (parent.width - Style.spacingM) / 2
                    height: units.gu(11)
                    radius: Style.cardRadius
                    color: Style.brand
                    AbstractButton {
                        anchors.fill: parent
                        onClicked: page.pageStack.push(Qt.resolvedUrl("PlatformInfoPage.qml"))
                        Column {
                            anchors.centerIn: parent
                            spacing: Style.spacingS
                            Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: units.gu(3); height: width
                                name: "edit"; color: Style.textOnBrand
                            }
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Lang.tr("Platform Information")
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                width: units.gu(14)
                                font.pixelSize: Style.fontSmall
                                font.weight: Font.DemiBold
                                font.family: Style.fontFor(text)
                                color: Style.textOnBrand
                            }
                        }
                    }
                }
                Rectangle {
                    width: (parent.width - Style.spacingM) / 2
                    height: units.gu(11)
                    radius: Style.cardRadius
                    color: Style.brandDark
                    AbstractButton {
                        anchors.fill: parent
                        onClicked: page.pageStack.push(Qt.resolvedUrl("PlatformSettingsPage.qml"))
                        Column {
                            anchors.centerIn: parent
                            spacing: Style.spacingS
                            Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: units.gu(3); height: width
                                name: "settings"; color: Style.textOnBrand
                            }
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Lang.tr("Platform Setting")
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                width: units.gu(14)
                                font.pixelSize: Style.fontSmall
                                font.weight: Font.DemiBold
                                font.family: Style.fontFor(text)
                                color: Style.textOnBrand
                            }
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

            // ===== Manage Navigation Bar: Blog + Video only ==================
            SettingsSectionHeader {
                text: Lang.tr("Manage Navigation Bar")
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width, page.maxContentWidth)
            }

            // Own Column (spacing 0) so the outer Style.spacingL section-gap
            // doesn't get inserted between the Blog and Video rows too.
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width, page.maxContentWidth)
                spacing: 0

                Repeater {
                    model: [
                        { key: "blog", label: Lang.tr("Blog"), icon: "stock_note", page: "BlogManagementPage.qml" },
                        { key: "video", label: Lang.tr("Video"), icon: "camcorder", page: "VideoManagementPage.qml" }
                    ]
                    delegate: Item {
                        width: parent.width
                        height: units.gu(6.5)

                        Row {
                            anchors { left: parent.left; leftMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                            spacing: Style.spacingM
                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                width: units.gu(2.6); height: width
                                name: modelData.icon
                                color: Style.textSecondary
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                font.pixelSize: Style.fontRegular
                                font.weight: Font.DemiBold
                                font.family: Style.fontFor(text)
                                color: Style.textPrimary
                            }
                        }

                        Rectangle {
                            anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                            width: manageLabel.implicitWidth + Style.spacingM * 2
                            height: units.gu(3.6)
                            radius: Style.pillRadius
                            color: Style.brand
                            AbstractButton {
                                anchors.fill: parent
                                onClicked: page.pageStack.push(Qt.resolvedUrl(modelData.page))
                                Label {
                                    id: manageLabel
                                    anchors.centerIn: parent
                                    text: Lang.tr("Manage")
                                    font.pixelSize: Style.fontSmall
                                    font.weight: Font.DemiBold
                                    font.family: Style.fontFor(text)
                                    color: Style.textOnBrand
                                }
                            }
                        }

                        Rectangle {
                            anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: units.gu(2) }
                            height: units.dp(1)
                            color: Style.divider
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

            // Everything else lives in the full web CMS.
            LinkButton {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width, page.maxContentWidth) - Style.spacingL * 2
                label: Lang.tr("Open full dashboard in browser")
                onClicked: Qt.openUrlExternally("https://serey.io/social-media-owners")
            }

            Item { width: 1; height: Style.spacingL }
        }
    }
}
