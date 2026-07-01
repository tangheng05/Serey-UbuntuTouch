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
        title: i18n.tr("Password & Security")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: i18n.tr("Back"); onTriggered: page.pageStack.pop() }
        ]
    }

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
                Toast.show(i18n.tr("Password changed successfully"))
                page.pageStack.pop()
            },
            function (err) {
                busy = false
                errorMsg = err.message || i18n.tr("Failed to change password.")
            }
        )
    }

    KeyboardAwareFlickable {
        anchors.fill: parent

        Column {
            anchors {
                left: parent.left
                right: parent.right
                leftMargin: Style.spacingM
                rightMargin: Style.spacingM
            }
            spacing: Style.spacingM
            topPadding: Style.spacingL

            // ── Change password ──────────────────────────────────────────
            Label {
                width: parent.width
                text: i18n.tr("Change password")
                font.pixelSize: Style.fontLarge
                font.weight: Font.DemiBold
                font.family: Style.fontFamily
                color: Style.textTitle
            }

            Item { width: 1; height: Style.spacingXs }

            Column {
                width: parent.width
                spacing: units.dp(4)

                FormField {
                    id: currentPassField
                    width: parent.width
                    placeholder: i18n.tr("Current password")
                    echoMode: TextInput.Password
                    onAccepted: newPassField.input.forceActiveFocus()
                }

                Label {
                    anchors.right: parent.right
                    text: i18n.tr("Forgot password?")
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFamily
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
                placeholder: i18n.tr("New password")
                echoMode: TextInput.Password
                onAccepted: confirmPassField.input.forceActiveFocus()
            }

            FormField {
                id: confirmPassField
                width: parent.width
                placeholder: i18n.tr("Confirm new password")
                echoMode: TextInput.Password
                onAccepted: page.submit()
            }

            Label {
                width: parent.width
                visible: confirmPassField.text.length > 0 &&
                         newPassField.text !== confirmPassField.text
                text: i18n.tr("Passwords do not match")
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFamily
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
                font.family: Style.fontFamily
                color: Style.danger
                wrapMode: Text.WordWrap
            }

            PrimaryButton {
                width: parent.width
                text: i18n.tr("Change password")
                busy: page.busy
                enabled: page.canSubmit
                onClicked: page.submit()
            }

            Item { width: 1; height: Style.spacingL }
        }
    }
}
