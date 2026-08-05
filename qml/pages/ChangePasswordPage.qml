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

    // Keyboard nav: focus lands on first field; Escape returns to settings list
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

    // Built as a settings list, not a form on a blank page: full-bleed sections,
    // full-width dividers, label column / control column. Same grammar as the
    // settings list in the pane opposite.
    KeyboardAwareFlickable {
        anchors { top: page.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentWidth: width
        contentHeight: form.height
        clip: true

        Column {
            id: form
            width: parent.width

            SettingsSectionHeader { text: Lang.tr("Confirm it's you") }

            SettingsFormRow {
                label: Lang.tr("Current password")
                FormField {
                    id: currentPassField
                    width: parent.width
                    echoMode: TextInput.Password
                    onAccepted: newPassField.input.forceActiveFocus()
                }
            }

            SettingsRow {
                label: Lang.tr("Forgot password?")
                showChevron: true
                onClicked: page.pageStack.push(Qt.resolvedUrl("ForgotPasswordPage.qml"),
                                               { prefillUsername: Session.username })
            }

            SettingsSectionHeader { text: Lang.tr("Choose a new password") }

            SettingsFormRow {
                label: Lang.tr("New password")
                FormField {
                    id: newPassField
                    width: parent.width
                    echoMode: TextInput.Password
                    onAccepted: confirmPassField.input.forceActiveFocus()
                }
            }

            SettingsFormRow {
                label: Lang.tr("Requirements")
                PasswordChecklist {
                    width: parent.width
                    password: newPassField.text
                }
            }

            SettingsFormRow {
                label: Lang.tr("Confirm new password")
                FormField {
                    id: confirmPassField
                    width: parent.width
                    echoMode: TextInput.Password
                    // Only complain once there's something to compare against.
                    errorText: (confirmPassField.text.length > 0 &&
                                newPassField.text !== confirmPassField.text)
                               ? Lang.tr("Passwords do not match") : ""
                    onAccepted: page.submit()
                }
            }

            Item { width: 1; height: Style.spacingL }

            Label {
                x: Style.spacingM
                width: parent.width - Style.spacingM * 2
                visible: page.errorMsg.length > 0
                text: page.errorMsg
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFor(text)
                color: Style.negative
                wrapMode: Text.WordWrap
            }

            Item { width: 1; height: Style.spacingS; visible: page.errorMsg.length > 0 }

            PrimaryButton {
                x: Style.spacingM
                width: Math.min(parent.width - Style.spacingM * 2, units.gu(26))
                text: Lang.tr("Change password")
                busy: page.busy
                enabled: page.canSubmit
                onClicked: page.submit()
            }

            Item { width: 1; height: Style.spacingL }
        }
    }
}
