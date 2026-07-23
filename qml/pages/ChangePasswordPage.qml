import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/AccountService.js" as AccountService

Page {
    id: page

    property bool busy: false
    property string errorMsg: ""

    header: PageHeader {
        title: Lang.tr("Password & Security")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.pageStack.pop() }
        ]
    }

    // Keyboard nav: focus lands on the first field when opened from settings
    // (Tab/Enter then move through the fields); Escape returns to the settings list.
    property Item keyboardFocusItem: currentPassField.input
    Keys.onEscapePressed: Nav.focusMaster()

    readonly property bool newPasswordValid:
        AccountService.isValidPassword(newPassField.text)
    readonly property bool canSubmit:
        currentPassField.text.length > 0 &&
        newPasswordValid &&
        newPassField.text === confirmPassField.text &&
        !busy

    function submit() {
        if (!canSubmit) return
        busy = true
        errorMsg = ""
        AccountService.changePassword(
            Config.baseUrl, Session.token,
            currentPassField.text, newPassField.text,
            function () {
                busy = false
                Toast.show(Lang.tr("Password changed successfully"))
                page.pageStack.pop()
            },
            function (err) {
                busy = false
                errorMsg = err.message || Lang.tr("Failed to change password.")
            }
        )
    }

    KeyboardAwareFlickable {
        anchors.fill: parent

        Column {
            width: Math.min(parent.width - Style.spacingM * 2, units.gu(50))
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.spacingM
            topPadding: Style.spacingL

            // --- Change password ---
            Label {
                width: parent.width
                text: Lang.tr("Change password")
                font.pixelSize: Style.fontLarge
                font.weight: Font.DemiBold
                font.family: Style.fontFor(text)
                color: Style.textTitle
            }

            Item { width: 1; height: Style.spacingXs }

            Column {
                width: parent.width
                spacing: units.dp(4)

                FormField {
                    id: currentPassField
                    width: parent.width
                    placeholder: Lang.tr("Current password")
                    echoMode: TextInput.Password
                    onAccepted: newPassField.input.forceActiveFocus()
                }

                Label {
                    anchors.right: parent.right
                    text: Lang.tr("Forgot password?")
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
                    color: Style.brand
                    MouseArea {
                        anchors.fill: parent
                        onClicked: page.pageStack.push(Qt.resolvedUrl("ForgotPasswordPage.qml"),
                                                       { prefillUsername: Session.username })
                    }
                }
            }

            FormField {
                id: newPassField
                width: parent.width
                placeholder: Lang.tr("New password")
                echoMode: TextInput.Password
                onAccepted: confirmPassField.input.forceActiveFocus()
            }

            FormField {
                id: confirmPassField
                width: parent.width
                placeholder: Lang.tr("Confirm new password")
                echoMode: TextInput.Password
                onAccepted: page.submit()
            }

            Label {
                width: parent.width
                visible: confirmPassField.text.length > 0 &&
                         newPassField.text !== confirmPassField.text
                text: Lang.tr("Passwords do not match")
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFor(text)
                color: Style.danger
            }

            PasswordChecklist {
                width: parent.width
                password: newPassField.text
            }

            Label {
                width: parent.width
                visible: errorMsg.length > 0
                text: errorMsg
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFor(text)
                color: Style.danger
                wrapMode: Text.WordWrap
            }

            PrimaryButton {
                width: parent.width
                text: Lang.tr("Change password")
                busy: page.busy
                enabled: page.canSubmit
                onClicked: page.submit()
            }

            Item { width: 1; height: Style.spacingL }
        }
    }
}
