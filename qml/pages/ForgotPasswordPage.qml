import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/AccountService.js" as AccountService

/*
 * Password reset — two modes:
 *
 * Logged-in (prefillUsername set by caller):
 *   step 0 — email → send OTP immediately (username already known)
 *   step 1 — enter OTP
 *   step 2 — new password
 *
 * Not logged-in (prefillUsername empty):
 *   step 0 — username → fetch masked email hint
 *   step 1 — fill masked email → send OTP
 *   step 2 — enter OTP
 *   step 3 — new password
 *
 * Phone support removed — email only.
 */
Page {
    id: page

    // Caller sets this when the user is already signed in so we can skip
    // the username lookup and go straight to the email entry step.
    property string prefillUsername: ""

    property int step: 0
    property bool busy: false
    property string errorMsg: ""
    property int resendSeconds: 0

    property string username: prefillUsername
    property string hintEmail: ""
    property string sentEmail: ""

    // In logged-in mode we have 3 steps (0=email, 1=OTP, 2=newPW).
    // In guest mode we have 4 (0=username, 1=maskedEmail, 2=OTP, 3=newPW).
    readonly property bool loggedInMode: prefillUsername.length > 0
    readonly property int totalSteps: loggedInMode ? 3 : 4

    header: PageHeader {
        title: Lang.tr("Reset password")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.goBack() }
        ]
    }

    function goBack() {
        if (page.step > 0) { page.errorMsg = ""; page.step -= 1; }
        else page.pageStack.pop();
    }

    function fail(err) { busy = false; page.errorMsg = err.message || Lang.tr("Something went wrong."); }

    Component.onCompleted: {
        if (loggedInMode) emailDirectField.input.forceActiveFocus();
        else              usernameField.input.forceActiveFocus();
    }

    onStepChanged: {
        page.errorMsg = "";
        if (loggedInMode) {
            if (step === 0) emailDirectField.input.forceActiveFocus();
            else if (step === 1) otpField.input.forceActiveFocus();
            else if (step === 2) passwordField.input.forceActiveFocus();
        } else {
            if (step === 0) usernameField.input.forceActiveFocus();
            else if (step === 1) emailMasked.input.forceActiveFocus();
            else if (step === 2) otpField.input.forceActiveFocus();
            else if (step === 3) passwordField.input.forceActiveFocus();
        }
    }

    // ── Guest mode: step 0 → 1 ──────────────────────────────────────────────
    function lookupHint() {
        if (busy) return;
        errorMsg = "";
        if (usernameField.text.length === 0) {
            errorMsg = Lang.tr("Please enter your username."); return;
        }
        username = usernameField.text;
        busy = true;
        AccountService.getContactHint(Config.baseUrl, username,
            function (resp) {
                busy = false;
                var d = (resp && resp.data) ? resp.data : {};
                page.hintEmail = d.email || "";
                if (page.hintEmail.length === 0) {
                    page.errorMsg = Lang.tr("No email address found for this account.");
                    return;
                }
                page.step = 1;
            }, fail);
    }

    // ── Guest mode: step 1 → 2  (send OTP to masked email) ─────────────────
    function sendOtpMasked() {
        if (busy) return;
        errorMsg = "";
        if (!emailMasked.complete) {
            errorMsg = Lang.tr("Please fill in the hidden part of your email."); return;
        }
        sentEmail = emailMasked.value;
        busy = true;
        AccountService.requestPasswordReset(Config.baseUrl, username, { email: sentEmail },
            function () { busy = false; resendSeconds = 90; step = 2; }, fail);
    }

    // ── Logged-in mode: step 0 → 1 (send OTP to typed email directly) ───────
    function sendOtpDirect() {
        if (busy) return;
        errorMsg = "";
        var em = emailDirectField.text.trim();
        if (em.length === 0 || em.indexOf("@") < 1) {
            errorMsg = Lang.tr("Please enter a valid email address."); return;
        }
        sentEmail = em;
        busy = true;
        AccountService.requestPasswordReset(Config.baseUrl, username, { email: sentEmail },
            function () { busy = false; resendSeconds = 90; step = 1; }, fail);
    }

    // ── Shared: verify OTP length ────────────────────────────────────────────
    function verifyCode() {
        if (busy) return;
        errorMsg = "";
        if (otpField.text.length < 6) {
            errorMsg = Lang.tr("Please enter the 6-digit code."); return;
        }
        step = loggedInMode ? 2 : 3;
    }

    // ── Shared: resend ───────────────────────────────────────────────────────
    function resend() {
        if (busy || resendSeconds > 0) return;
        errorMsg = "";
        busy = true;
        AccountService.requestPasswordReset(Config.baseUrl, username, { email: sentEmail },
            function () { busy = false; resendSeconds = 90; Toast.show(Lang.tr("New code sent.")); }, fail);
    }

    // ── Shared: final submit ─────────────────────────────────────────────────
    function submitReset() {
        if (busy) return;
        errorMsg = "";
        if (!AccountService.isValidPassword(passwordField.text)) {
            errorMsg = Lang.tr("Password must be 8–16 characters with uppercase, lowercase and a number."); return;
        }
        if (passwordField.text !== confirmField.text) {
            errorMsg = Lang.tr("Passwords do not match."); return;
        }
        busy = true;
        AccountService.resetPassword(Config.baseUrl, username, otpField.text, passwordField.text,
            function () {
                busy = false;
                Toast.show(Lang.tr("Password reset. Please log in."));
                page.pageStack.pop();
            },
            function (err) {
                busy = false;
                page.errorMsg = err.message;
                if (err.message && /otp|code/i.test(err.message))
                    page.step = loggedInMode ? 1 : 2;
            });
    }

    Timer {
        interval: 1000; repeat: true
        running: page.resendSeconds > 0
        onTriggered: page.resendSeconds = Math.max(0, page.resendSeconds - 1)
    }

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

            // Logo
            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: units.gu(9); height: width
                source: Qt.resolvedUrl("../../assets/serey-logo.png")
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }

            // Step dots
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.spacingS
                Repeater {
                    model: page.totalSteps
                    delegate: Rectangle {
                        width: units.gu(1); height: units.gu(1); radius: width / 2
                        color: index <= page.step ? Style.brand : Style.dotInactive
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }
            }

            // Step title
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                font.family: Style.fontFamily
                font.pixelSize: Style.fontTitle
                font.weight: Font.DemiBold
                color: Style.textTitle
                wrapMode: Text.WordWrap
                text: {
                    if (loggedInMode) {
                        if (page.step === 0) return Lang.tr("Enter your email")
                        if (page.step === 1) return Lang.tr("Enter your code")
                        return Lang.tr("Create a new password")
                    } else {
                        if (page.step === 0) return Lang.tr("Find your account")
                        if (page.step === 1) return Lang.tr("Verify your identity")
                        if (page.step === 2) return Lang.tr("Enter your code")
                        return Lang.tr("Create a new password")
                    }
                }
            }

            Item { width: 1; height: Style.spacingXs }

            // ── Logged-in mode step 0: direct email entry ──────────────────
            Label {
                visible: loggedInMode && page.step === 0
                width: parent.width
                font.family: Style.fontFamily
                font.pixelSize: Style.fontSmall
                color: Style.textSecondary
                wrapMode: Text.WordWrap
                text: Lang.tr("Enter the email address on your account. We'll send a verification code.")
            }
            FormField {
                id: emailDirectField
                visible: loggedInMode && page.step === 0
                width: parent.width
                placeholder: Lang.tr("Email address")
                inputMethodHints: Qt.ImhEmailCharactersOnly
                onAccepted: page.sendOtpDirect()
            }

            // ── Guest mode step 0: username ────────────────────────────────
            FormField {
                id: usernameField
                visible: !loggedInMode && page.step === 0
                width: parent.width
                placeholder: Lang.tr("Username")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                onAccepted: page.lookupHint()
            }

            // ── Guest mode step 1: masked email ────────────────────────────
            Label {
                visible: !loggedInMode && page.step === 1
                width: parent.width
                font.family: Style.fontFamily
                font.pixelSize: Style.fontSmall
                color: Style.textSecondary
                wrapMode: Text.WordWrap
                text: Lang.tr("Fill in the hidden part of your email to receive a code.")
            }
            MaskedContactInput {
                id: emailMasked
                visible: !loggedInMode && page.step === 1
                width: parent.width
                maskedEmail: page.hintEmail
                onAccepted: page.sendOtpMasked()
            }

            // ── Shared step: OTP ───────────────────────────────────────────
            Label {
                visible: (loggedInMode && page.step === 1) || (!loggedInMode && page.step === 2)
                width: parent.width
                font.family: Style.fontFamily
                font.pixelSize: Style.fontSmall
                color: Style.textSecondary
                wrapMode: Text.WordWrap
                text: Lang.tr("We sent a verification code to %1.").arg(page.sentEmail)
            }
            OtpInput {
                id: otpField
                visible: (loggedInMode && page.step === 1) || (!loggedInMode && page.step === 2)
                width: parent.width
                onAccepted: page.verifyCode()
            }
            Item {
                visible: (loggedInMode && page.step === 1) || (!loggedInMode && page.step === 2)
                width: parent.width; height: units.gu(3)
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: page.resendSeconds > 0
                    text: Lang.tr("Resend code in %1s").arg(page.resendSeconds)
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFamily
                    color: Style.textSecondary
                }
                AbstractButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: page.resendSeconds === 0
                    width: resendLbl.width; height: resendLbl.height
                    onClicked: page.resend()
                    Label {
                        id: resendLbl
                        text: Lang.tr("Resend code")
                        font.pixelSize: Style.fontSmall
                        font.weight: Font.DemiBold
                        font.family: Style.fontFamily
                        color: Style.brand
                    }
                }
            }

            // ── Shared step: new password ──────────────────────────────────
            FormField {
                id: passwordField
                visible: (loggedInMode && page.step === 2) || (!loggedInMode && page.step === 3)
                width: parent.width
                placeholder: Lang.tr("New password")
                echoMode: TextInput.Password
                onAccepted: confirmField.input.forceActiveFocus()
            }
            PasswordChecklist {
                visible: (loggedInMode && page.step === 2) || (!loggedInMode && page.step === 3)
                width: parent.width
                password: passwordField.text
            }
            FormField {
                id: confirmField
                visible: (loggedInMode && page.step === 2) || (!loggedInMode && page.step === 3)
                width: parent.width
                placeholder: Lang.tr("Confirm new password")
                echoMode: TextInput.Password
                onAccepted: page.submitReset()
            }

            // Error
            Label {
                width: parent.width
                font.family: Style.fontFamily
                font.pixelSize: Style.fontSmall
                text: page.errorMsg
                color: Style.danger
                wrapMode: Text.WordWrap
                visible: text.length > 0
            }

            // Primary action button
            PrimaryButton {
                width: parent.width
                busy: page.busy
                text: {
                    if (page.busy) return Lang.tr("Please wait…")
                    if (loggedInMode) {
                        if (page.step === 0) return Lang.tr("Send code")
                        if (page.step === 1) return Lang.tr("Next")
                        return Lang.tr("Reset password")
                    } else {
                        if (page.step === 0) return Lang.tr("Continue")
                        if (page.step === 1) return Lang.tr("Send code")
                        if (page.step === 2) return Lang.tr("Next")
                        return Lang.tr("Reset password")
                    }
                }
                onClicked: {
                    if (loggedInMode) {
                        if (page.step === 0) page.sendOtpDirect();
                        else if (page.step === 1) page.verifyCode();
                        else page.submitReset();
                    } else {
                        if (page.step === 0) page.lookupHint();
                        else if (page.step === 1) page.sendOtpMasked();
                        else if (page.step === 2) page.verifyCode();
                        else page.submitReset();
                    }
                }
            }
        }
    }
}
