import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/LandingPageService.js" as LandingPageService

/*
 * "Platform Setting" card from the Serey CMS hub: premium/paid community
 * settings (premium_community_setting_route.js /premium-community-setting)
 * for the current community.
 */
Page {
    id: page

    property bool loading: false
    property bool savingFee: false
    property string errorMsg: ""

    header: PageHeader {
        title: Lang.tr("Platform Setting")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.pageStack.pop() }
        ]
    }

    function load() {
        page.loading = true
        page.errorMsg = ""
        LandingPageService.getPremiumSetting(Config.baseUrl, Config.managedCommunityId, Session.token,
            function (data) {
                page.loading = false
                feeField.text = data.fee !== undefined ? String(data.fee) : ""
                publishSwitch.checked = !!data.is_published
            },
            function (err) {
                page.loading = false
                // Non-fatal: community may not have premium settings configured yet.
            })
    }

    function saveFee() {
        page.savingFee = true
        LandingPageService.savePremiumFee(Config.baseUrl, {
            community_id: Config.managedCommunityId,
            fee: Number(feeField.text) || 0
        }, Session.token,
            function () {
                page.savingFee = false
                Toast.success(Lang.tr("Premium fee saved."))
            },
            function (err) {
                page.savingFee = false
                Toast.error(err.message || Lang.tr("Failed to save fee."))
            })
    }

    function togglePublish(checked) {
        publishSwitch.checked = checked
        LandingPageService.publishPremiumSetting(Config.baseUrl, {
            community_id: Config.managedCommunityId,
            is_published: checked
        }, Session.token,
            function () { Toast.success(checked ? Lang.tr("Premium settings published.") : Lang.tr("Premium settings unpublished.")) },
            function (err) {
                publishSwitch.checked = !checked
                Toast.error(err.message || Lang.tr("Failed to update."))
            })
    }

    Component.onCompleted: page.load()

    KeyboardAwareFlickable {
        anchors { top: page.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentWidth: width
        contentHeight: form.height + Style.spacingL * 2
        clip: true

        Column {
            id: form
            width: Math.min(parent.width - Style.spacingL * 2, units.gu(50))
            anchors.horizontalCenter: parent.horizontalCenter
            y: Style.spacingL
            spacing: Style.spacingM

            Label {
                text: Lang.tr("Subscription fee")
                font.pixelSize: Style.fontSmall; font.family: Style.fontFor(text); color: Style.textSecondary
            }
            FormField {
                id: feeField
                width: parent.width
                placeholder: Lang.tr("Fee")
                inputMethodHints: Qt.ImhDigitsOnly
            }
            PrimaryButton {
                width: parent.width
                busy: page.savingFee
                enabled: !page.savingFee
                text: page.savingFee ? Lang.tr("Saving…") : Lang.tr("Save fee")
                onClicked: page.saveFee()
            }

            SettingsRow {
                id: publishRow
                width: parent.width
                iconName: "share"
                label: Lang.tr("Publish premium settings")
                showSwitch: true
                switchChecked: publishSwitch.checked
                onSwitchToggled: page.togglePublish(checked)
            }
            // Hidden state holder backing publishRow's switch (SettingsRow has no
            // named alias for its own switch state).
            Item {
                id: publishSwitch
                property bool checked: false
            }

            Item { width: 1; height: Style.spacingL }
        }
    }

    ActivityIndicator {
        anchors.centerIn: parent
        running: page.loading
        visible: running
    }
}
