import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/AccountService.js" as AccountService

Page {
    id: page

    property int step: 0
    property bool busy: false
    property string errorMsg: ""

    property string username: ""
    property string email: ""
    property string masterKey: ""
    property bool keySaved: false
    property int resendSeconds: 0

    header: PageHeader {
        title: Lang.tr("Self-custody")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.goBack() }
        ]
    }

    // Steps 1-2 go back within the wizard; step 0 and the post-creation key screen (3) leave the page so back can't re-trigger account creation.
    function goBack() {
        if (page.step === 1 || page.step === 2) { page.errorMsg = ""; page.step -= 1; }
        else page.pageStack.pop();
    }

    function fail(err) { busy = false; page.errorMsg = err.message; }

    Component.onCompleted: usernameField.input.forceActiveFocus()

    onStepChanged: {
        if (step === 0) usernameField.input.forceActiveFocus();
        else if (step === 1) emailField.input.forceActiveFocus();
        else if (step === 2) otpField.input.forceActiveFocus();
    }

    // Re-send the OTP once the countdown reaches zero.
    function resend() {
        if (busy || resendSeconds > 0) return;
        errorMsg = "";
        busy = true;
        AccountService.sendSignupOtp(Config.baseUrl, username, email,
            function () { busy = false; resendSeconds = 90; Toast.show(Lang.tr("New code sent.")); },
            fail);
    }

    // step 0 -> 1
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

    // step 1 -> 2: send the OTP.
    function sendOtp() {
        if (busy) return;
        errorMsg = "";
        if (emailField.text.indexOf("@") < 0) {
            errorMsg = Lang.tr("Please enter a valid email address.");
            return;
        }
        email = emailField.text;
        busy = true;
        AccountService.sendSignupOtp(Config.baseUrl, username, email,
            function () { busy = false; resendSeconds = 90; step = 2; },
            fail);
    }

    // step 2: generate keys on-device, then create the account.
    function createAccount() {
        if (busy) return;
        errorMsg = "";
        if (otpField.text.length === 0) {
            errorMsg = Lang.tr("Please enter the verification code.");
            return;
        }
        busy = true;
        keygen.generate(username,
            function (keys) {
                AccountService.createSelfCustodyAccount(Config.baseUrl, username, email,
                    otpField.text, keys,
                    function () {
                        busy = false;
                        page.masterKey = keys.master_password;
                        step = 3;
                    },
                    fail);
            },
            function (msg) { busy = false; page.errorMsg = msg; });
    }

    KeygenBridge { id: keygen }

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

            Image {
                visible: page.step < 3
                anchors.horizontalCenter: parent.horizontalCenter
                width: units.gu(9); height: width
                source: Qt.resolvedUrl("../../assets/serey-logo.png")
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }

            Row {
                visible: page.step < 3
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.spacingS
                Repeater {
                    model: 4
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
                font.family: Style.fontFor(text)
                text: page.step === 0 ? Lang.tr("Choose a username")
                    : page.step === 1 ? Lang.tr("Add your email")
                    : page.step === 2 ? Lang.tr("Enter the code we emailed you")
                    : Lang.tr("Save your private key")
                font.pixelSize: Style.fontTitle
                font.weight: Font.DemiBold
                color: Style.textTitle
                wrapMode: Text.WordWrap
            }

            Item { width: 1; height: Style.spacingXs }

            // --- Step 0: username ------------------------------------------
            FormField {
                id: usernameField
                visible: page.step === 0
                width: parent.width
                placeholder: Lang.tr("Username")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                onAccepted: page.checkUsername()
            }

            // --- Step 1: email ---------------------------------------------
            FormField {
                id: emailField
                visible: page.step === 1
                width: parent.width
                placeholder: Lang.tr("Email")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhEmailCharactersOnly
                onAccepted: page.sendOtp()
            }

            // --- Step 2: OTP -----------------------------------------------
            Label {
                visible: page.step === 2
                width: parent.width
                font.family: Style.fontFor(text)
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
            Item {
                visible: page.step === 2
                width: parent.width
                height: units.gu(3)
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: page.resendSeconds > 0
                    text: Lang.tr("Resend code in %1s").arg(page.resendSeconds)
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                }
                AbstractButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: page.resendSeconds === 0
                    width: scResendLbl.width; height: scResendLbl.height
                    onClicked: page.resend()
                    Label {
                        id: scResendLbl
                        text: Lang.tr("Resend code")
                        font.pixelSize: Style.fontSmall
                        font.weight: Font.DemiBold
                        font.family: Style.fontFor(text)
                        color: Style.brand
                    }
                }
            }

            // --- Step 3: celebration + save the key ------------------------
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
                text: Lang.tr("Account created!")
                font.pixelSize: Style.fontTitle
                font.weight: Font.DemiBold
                font.family: Style.fontFor(text)
                color: Style.textTitle
            }
            Rectangle {
                visible: page.step === 3
                width: parent.width
                height: warn.height + Style.spacingM * 2
                radius: Style.cardRadius
                color: Style.dangerTint
                Label {
                    id: warn
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                              leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                    text: Lang.tr("This key is the only way into your account. Save it somewhere safe. It can't be recovered if you lose it.")
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
                    color: Style.danger
                    wrapMode: Text.WordWrap
                }
            }
            FormField {
                id: keyField
                visible: page.step === 3
                width: parent.width
                readOnly: true
                text: page.masterKey
            }
            SecondaryButton {
                visible: page.step === 3
                width: parent.width
                text: page.keySaved ? Lang.tr("Copied ✓") : Lang.tr("Copy key")
                onClicked: {
                    keyField.input.selectAll();
                    keyField.input.copy();
                    keyField.input.deselect();
                    page.keySaved = true;
                    Toast.success(Lang.tr("Key copied. Store it somewhere safe."));
                }
            }

            Label {
                width: parent.width
                font.family: Style.fontFor(text)
                font.pixelSize: Style.fontSmall
                text: page.errorMsg
                color: Style.danger
                wrapMode: Text.WordWrap
                visible: text.length > 0
            }

            // Primary action (varies by step)
            PrimaryButton {
                width: parent.width
                busy: page.busy
                enabled: !page.busy && (page.step !== 3 || page.keySaved)
                text: page.busy ? Lang.tr("Please wait…")
                    : page.step === 0 ? Lang.tr("Continue")
                    : page.step === 1 ? Lang.tr("Send code")
                    : page.step === 2 ? Lang.tr("Create account")
                    : Lang.tr("I've saved my key")
                onClicked: {
                    if (page.step === 0) page.checkUsername();
                    else if (page.step === 1) page.sendOtp();
                    else if (page.step === 2) page.createAccount();
                    else {
                        // Drop the self-custody page + the chooser beneath it, then land on the login page to sign in with the saved key.
                        var stack = page.pageStack;
                        Toast.success(Lang.tr("Account created. Log in with your key."));
                        stack.pop();   // this self-custody page
                        stack.pop();   // the Create Account chooser
                        stack.push(Qt.resolvedUrl("LoginPage.qml"), { afterSuccess: "feed" });
                    }
                }
            }
        }
    }
}
