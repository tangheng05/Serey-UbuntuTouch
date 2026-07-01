import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/AccountService.js" as AccountService

/*
 * Standard (custodial) account signup, mirroring the web's email flow:
 *   step 0 — choose a username (checked for availability)
 *   step 1 — enter email + password (sends an OTP)
 *   step 2 — enter the OTP to create the account
 * The header back steps within the wizard before leaving; the OTP step has a
 * resend countdown. On success the account is created, auto-logged-in, and we
 * pop back. Styled with the shared design tokens.
 */
Page {
    id: page

    property int step: 0
    property bool busy: false
    property string errorMsg: ""
    property int resendSeconds: 0

    // Carried across steps.
    property string username: ""
    property string email: ""
    property string password: ""

    header: PageHeader {
        title: Lang.tr("Create account")
        leadingActionBar.actions: [
            Action {
                iconName: "back"
                text: Lang.tr("Back")
                onTriggered: page.goBack()
            }
        ]
    }

    function goBack() {
        if (page.step === 3) { Nav.home(); return; }  // account already created
        if (page.step > 0) { page.errorMsg = ""; page.step -= 1; }
        else page.pageStack.pop();
    }

    Component.onCompleted: usernameField.input.forceActiveFocus()

    function fail(err) { busy = false; page.errorMsg = err.message; }

    // Focus the active step's first field as it appears.
    onStepChanged: {
        if (step === 0) usernameField.input.forceActiveFocus();
        else if (step === 1) emailField.input.forceActiveFocus();
        else if (step === 2) otpField.input.forceActiveFocus();
        else Qt.inputMethod.hide();   // success screen: dismiss keyboard
    }

    // step 0 -> 1: validate format, then confirm the username is free.
    function checkUsername() {
        if (busy) return;
        errorMsg = "";
        if (!AccountService.isValidUsername(usernameField.text)) {
            errorMsg = Lang.tr("Username must be 5–30 characters: lowercase letters, numbers or hyphens.");
            return;
        }
        busy = true;
        AccountService.checkUsernameAvailable(Config.baseUrl, usernameField.text,
            function () { busy = false; username = usernameField.text; step = 1; },
            fail);
    }

    // step 1 -> 2: validate, then request the OTP.
    function sendOtp() {
        if (busy) return;
        errorMsg = "";
        if (emailField.text.indexOf("@") < 0) {
            errorMsg = Lang.tr("Please enter a valid email address.");
            return;
        }
        if (!AccountService.isValidPassword(passwordField.text)) {
            errorMsg = Lang.tr("Password must be 8–16 characters and include an uppercase letter, a lowercase letter and a number.");
            return;
        }
        if (passwordField.text !== confirmField.text) {
            errorMsg = Lang.tr("Passwords do not match.");
            return;
        }
        email = emailField.text;
        password = passwordField.text;
        busy = true;
        AccountService.sendSignupOtp(Config.baseUrl, username, email,
            function () { busy = false; resendSeconds = 90; step = 2; },
            fail);
    }

    // Re-send the OTP (only once the countdown reaches zero).
    function resend() {
        if (busy || resendSeconds > 0) return;
        errorMsg = "";
        busy = true;
        AccountService.sendSignupOtp(Config.baseUrl, username, email,
            function () { busy = false; resendSeconds = 90; Toast.show(Lang.tr("New code sent.")); },
            fail);
    }

    // step 2: create the account (auto-logs in on success).
    function createAccount() {
        if (busy) return;
        errorMsg = "";
        if (otpField.text.length === 0) {
            errorMsg = Lang.tr("Please enter the verification code.");
            return;
        }
        busy = true;
        AccountService.createStandardAccount(Config.baseUrl, username, email,
            otpField.text, password,
            function (auth) {
                busy = false;
                Session.setAuth(auth.token, username);
                step = 3;   // celebration screen
            },
            fail);
    }

    Timer {
        interval: 1000; repeat: true
        running: page.step === 2 && page.resendSeconds > 0
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

            // Logo hero
            Image {
                visible: page.step < 3
                anchors.horizontalCenter: parent.horizontalCenter
                width: units.gu(9); height: width
                source: Qt.resolvedUrl("../../assets/serey-logo.png")
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }

            // Step indicator dots (3 steps)
            Row {
                visible: page.step < 3
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.spacingS
                Repeater {
                    model: 3
                    delegate: Rectangle {
                        width: units.gu(1); height: units.gu(1); radius: width / 2
                        color: index <= page.step ? Style.brand : Style.dotInactive
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }
            }

            Label {
                visible: page.step < 3
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                font.family: Style.fontFamily
                text: page.step === 0 ? Lang.tr("Choose a username")
                    : page.step === 1 ? Lang.tr("Set your email and password")
                    : Lang.tr("Enter the code we emailed you")
                font.pixelSize: Style.fontTitle
                font.weight: Font.DemiBold
                color: Style.textTitle
                wrapMode: Text.WordWrap
            }

            // --- Step 3: celebration ----------------------------------------
            SuccessBurst {
                visible: page.step === 3
                anchors.horizontalCenter: parent.horizontalCenter
                playing: page.step === 3
                accent: Style.success
            }
            Label {
                visible: page.step === 3
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Lang.tr("Welcome to Serey!")
                font.pixelSize: Style.fontTitle
                font.weight: Font.DemiBold
                font.family: Style.fontFamily
                color: Style.textTitle
            }
            Label {
                visible: page.step === 3
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Lang.tr("Your account is ready.")
                font.pixelSize: Style.fontRegular
                font.family: Style.fontFamily
                color: Style.textSecondary
                wrapMode: Text.WordWrap
            }

            Item { width: 1; height: Style.spacingXs }

            // --- Step 0: username -------------------------------------------
            FormField {
                id: usernameField
                visible: page.step === 0
                width: parent.width
                placeholder: Lang.tr("Username")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                onAccepted: page.checkUsername()
            }

            // --- Step 1: email + password -----------------------------------
            FormField {
                id: emailField
                visible: page.step === 1
                width: parent.width
                placeholder: Lang.tr("Email")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhEmailCharactersOnly
            }
            FormField {
                id: passwordField
                visible: page.step === 1
                width: parent.width
                placeholder: Lang.tr("Password")
                echoMode: TextInput.Password
            }
            FormField {
                id: confirmField
                visible: page.step === 1
                width: parent.width
                placeholder: Lang.tr("Confirm password")
                echoMode: TextInput.Password
                onAccepted: page.sendOtp()
            }
            PasswordChecklist {
                visible: page.step === 1
                width: parent.width
                password: passwordField.text
            }

            // --- Step 2: OTP ------------------------------------------------
            Label {
                visible: page.step === 2
                width: parent.width
                font.family: Style.fontFamily
                font.pixelSize: Style.fontSmall
                color: Style.textSecondary
                wrapMode: Text.WordWrap
                text: Lang.tr("We sent a verification code to %1.").arg(page.email)
            }
            OtpInput {
                id: otpField
                visible: page.step === 2
                width: parent.width
                onAccepted: page.createAccount()
            }
            // Resend: a live countdown, then a tappable link.
            Item {
                visible: page.step === 2
                width: parent.width
                height: units.gu(3)
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

            Label {
                width: parent.width
                font.family: Style.fontFamily
                font.pixelSize: Style.fontSmall
                text: page.errorMsg
                color: Style.danger
                wrapMode: Text.WordWrap
                visible: text.length > 0
            }

            PrimaryButton {
                width: parent.width
                busy: page.busy
                text: page.busy ? Lang.tr("Please wait…")
                    : page.step === 0 ? Lang.tr("Continue")
                    : page.step === 1 ? Lang.tr("Send code")
                    : page.step === 2 ? Lang.tr("Create account")
                    : Lang.tr("Start exploring")
                onClicked: {
                    if (page.step === 0) page.checkUsername();
                    else if (page.step === 1) page.sendOtp();
                    else if (page.step === 2) page.createAccount();
                    else Nav.home();
                }
            }
        }
    }
}
