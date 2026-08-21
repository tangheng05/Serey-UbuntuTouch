import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/AccountService.js" as AccountService

Page {
    id: page

    property bool busy: false
    property string errorMsg: ""
    property int twoFaEnabled: -1     // -1 = not loaded yet
    property string twoFaEmail: ""

    // Kept at every width, like the other settings sub-pages: a wide window still needs
    // a visible way back, and the panel beside it is a list, not a back affordance.
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

    // Deferred so the .js import is resolved, and the callbacks guard `page`
    // because the reply can land after a pushed page has been destroyed.
    function loadTwoFa() {
        if (!Session.isLoggedIn) { page.twoFaEnabled = -1; return }
        if (typeof AccountService === "undefined" || !AccountService) return
        AccountService.get2faStatus(Config.baseUrl, Session.token,
            function (st) {
                if (!page || !st) return
                page.twoFaEnabled = st.enabled ? 1 : 0
                page.twoFaEmail = st.email || ""
            },
            function () { if (page) page.twoFaEnabled = -1 })
    }
    Component.onCompleted: Qt.callLater(page.loadTwoFa)
    onVisibleChanged: if (visible) Qt.callLater(page.loadTwoFa)

    // ---- Two-step verification, run in a dialog so the switch never navigates away.
    // Both directions need an emailed code, so it's a two-step flow either way.
    property bool twoFaEnabling: true
    property bool twoFaSent: false
    property bool twoFaBusy: false
    property string twoFaError: ""

    function openTwoFa(enabling) {
        page.twoFaEnabling = enabling
        page.twoFaSent = false
        page.twoFaError = ""
        PopupUtils.open(twoFaDialog)
    }
    function twoFaSendCode(email) {
        if (!email || email.length === 0) { page.twoFaError = Lang.tr("Enter your email address."); return }
        page.twoFaError = ""; page.twoFaBusy = true
        var ok  = function () { page.twoFaBusy = false; page.twoFaSent = true }
        var err = function (e) { page.twoFaBusy = false
                                 page.twoFaError = (e && e.message) || Lang.tr("Failed to send code.") }
        if (page.twoFaEnabling)
            AccountService.request2faEnable(Config.baseUrl, Session.token, email, ok, err)
        else
            AccountService.request2faDisable(Config.baseUrl, Session.token, email, ok, err)
    }
    function twoFaConfirm(otp, onDone) {
        page.twoFaError = ""; page.twoFaBusy = true
        var ok = function () {
            page.twoFaBusy = false
            page.twoFaEnabled = page.twoFaEnabling ? 1 : 0
            Toast.show(page.twoFaEnabling ? Lang.tr("Two-step verification enabled")
                                          : Lang.tr("Two-step verification disabled"))
            if (onDone) onDone()
            Qt.callLater(page.loadTwoFa)
        }
        var err = function (e) { page.twoFaBusy = false
                                 page.twoFaError = (e && e.message) || Lang.tr("Invalid or expired code.") }
        if (page.twoFaEnabling)
            AccountService.confirm2faEnable(Config.baseUrl, Session.token, otp, ok, err)
        else
            AccountService.disable2fa(Config.baseUrl, Session.token, otp, ok, err)
    }

    Component {
        id: twoFaDialog
        Dialog {
            id: dlg
            title: page.twoFaEnabling ? Lang.tr("Enable two-step verification")
                                      : Lang.tr("Disable two-step verification")
            text: page.twoFaSent ? Lang.tr("Enter the code we sent you.")
                                 : Lang.tr("We'll email you a verification code.")

            FormField {
                id: dlgEmail
                visible: !page.twoFaSent
                width: parent.width
                placeholder: Lang.tr("Email address")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhEmailCharactersOnly
                Component.onCompleted: text = page.twoFaEmail
            }
            OtpInput {
                id: dlgOtp
                visible: page.twoFaSent
                onAccepted: page.twoFaConfirm(dlgOtp.text, function () { PopupUtils.close(dlg) })
            }
            Label {
                visible: page.twoFaError.length > 0
                width: parent.width
                text: page.twoFaError
                wrapMode: Text.WordWrap
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFor(text)
                color: Style.negative
            }
            PrimaryButton {
                text: page.twoFaSent ? Lang.tr("Verify") : Lang.tr("Send code")
                busy: page.twoFaBusy
                enabled: !page.twoFaBusy
                onClicked: page.twoFaSent
                    ? page.twoFaConfirm(dlgOtp.text, function () { PopupUtils.close(dlg) })
                    : page.twoFaSendCode(dlgEmail.text)
            }
            SecondaryButton {
                text: Lang.tr("Cancel")
                onClicked: PopupUtils.close(dlg)
            }
        }
    }

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
        anchors { top: page.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentWidth: width
        contentHeight: form.height + Style.spacingL * 2
        clip: true

        Column {
            id: form
            // Centred, matching Active sessions and the other settings panes.
            // The mock left-aligns this; consistency across panes won that call.
            width: Math.min(parent.width - Style.spacingM * 2, units.gu(50))
            x: (parent.width - width) / 2
            y: Style.spacingL
            spacing: 0

            // Inputs run the full column so they line up with the section rules above and below.
            readonly property real fieldWidth: width

            // ---------- Subtitle (the title itself is in the header bar) ----------
            Label {
                width: parent.width
                text: Lang.tr("Manage your password and account security")
                wrapMode: Text.WordWrap
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFor(text)
                color: Style.textSecondary
            }
            Item { width: 1; height: Style.spacingM }
            Rectangle {
                width: parent.width; height: units.dp(1)
                color: Style.divider
            }
            Item { width: 1; height: Style.spacingL }

            // ---------- Change password ----------
            Label {
                text: Lang.tr("Change password")
                font.pixelSize: Style.fontSmall
                font.weight: Font.DemiBold
                font.family: Style.fontFor(text)
                color: Style.brand
            }
            Item { width: 1; height: Style.spacingM }

            Label {
                text: Lang.tr("Current password")
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFor(text)
                color: Style.textPrimary
            }
            Item { width: 1; height: Style.spacingXs }
            FormField {
                id: currentPassField
                width: form.fieldWidth
                placeholder: Lang.tr("Enter current password")
                echoMode: TextInput.Password
                onAccepted: newPassField.input.forceActiveFocus()
            }
            // Not in the design, but without it a forgotten password is a dead end.
            LinkButton {
                width: units.gu(20)
                label: Lang.tr("Forgot password?")
                horizontalAlignment: Text.AlignLeft
                onClicked: page.pageStack.push(Qt.resolvedUrl("ForgotPasswordPage.qml"),
                                               { prefillUsername: Session.username })
            }
            Item { width: 1; height: Style.spacingS }

            Label {
                text: Lang.tr("New password")
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFor(text)
                color: Style.textPrimary
            }
            Item { width: 1; height: Style.spacingXs }
            FormField {
                id: newPassField
                width: form.fieldWidth
                placeholder: Lang.tr("Enter new password")
                echoMode: TextInput.Password
                onAccepted: confirmPassField.input.forceActiveFocus()
            }
            // Design omits the rules; kept but only while typing, otherwise the
            // disabled submit button has no explanation.
            Item { width: 1; height: Style.spacingS; visible: newPassField.text.length > 0 }
            PasswordChecklist {
                width: form.fieldWidth
                visible: newPassField.text.length > 0
                password: newPassField.text
            }
            Item { width: 1; height: Style.spacingM }

            Label {
                text: Lang.tr("Confirm new password")
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFor(text)
                color: Style.textPrimary
            }
            Item { width: 1; height: Style.spacingXs }
            FormField {
                id: confirmPassField
                width: form.fieldWidth
                placeholder: Lang.tr("Confirm new password")
                echoMode: TextInput.Password
                // Only complain once there's something to compare against.
                errorText: (confirmPassField.text.length > 0 &&
                            newPassField.text !== confirmPassField.text)
                           ? Lang.tr("Passwords do not match") : ""
                onAccepted: page.submit()
            }

            Item { width: 1; height: Style.spacingS; visible: page.errorMsg.length > 0 }
            Label {
                width: form.fieldWidth
                visible: page.errorMsg.length > 0
                text: page.errorMsg
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFor(text)
                color: Style.negative
                wrapMode: Text.WordWrap
            }

            Item { width: 1; height: Style.spacingM }
            PrimaryButton {
                width: form.fieldWidth
                text: Lang.tr("Update password")
                busy: page.busy
                enabled: page.canSubmit
                onClicked: page.submit()
            }

            Item { width: 1; height: Style.spacingL }
            Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }
            Item { width: 1; height: Style.spacingL }

            // ---------- Two-step verification ----------
            Label {
                text: Lang.tr("Two-step verification")
                font.pixelSize: Style.fontSmall
                font.weight: Font.DemiBold
                font.family: Style.fontFor(text)
                color: Style.brand
            }
            Item { width: 1; height: Style.spacingS }
            Label {
                width: parent.width
                text: Lang.tr("Add an extra layer of security to your account.")
                wrapMode: Text.WordWrap
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFor(text)
                color: Style.textSecondary
            }
            Item { width: 1; height: Style.spacingM }

            Item {
                width: parent.width
                height: units.gu(5)

                Label {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: Lang.tr("Enable two-step verification")
                    font.pixelSize: Style.fontRegular
                    font.family: Style.fontFor(text)
                    color: Style.textPrimary
                }
                Switch {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    checked: page.twoFaEnabled === 1
                    enabled: page.twoFaEnabled >= 0
                    // Snap back to the real state; the dialog owns the change.
                    onClicked: {
                        var wasOn = page.twoFaEnabled === 1
                        checked = Qt.binding(function () { return page.twoFaEnabled === 1 })
                        page.openTwoFa(!wasOn)
                    }
                }
            }

            Item { width: 1; height: Style.spacingL }
        }
    }
}
