import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../components"
import "../services/AccountService.js" as AccountService

/*
 * Password reset for standard (custodial) accounts, mirroring the web flow:
 *   step 0 — username; we fetch the account's MASKED contact hint from the API
 *   step 1 — show the hint (e.g. ****ith@gmail.com), pick email/phone if both,
 *            enter the contact → sends an OTP
 *   step 2 — OTP + new password
 * The masked hint comes from GET /accounts/contact-hint. The header steps back
 * through the wizard; the OTP step has a resend countdown.
 */
Page {
    id: page

    property int step: 0
    property bool busy: false
    property string errorMsg: ""
    property int resendSeconds: 0

    property string username: ""
    // Masked hints from the backend (either may be empty).
    property string hintEmail: ""
    property string hintPhone: ""
    // The method actually used to send the OTP ("email" | "phone") + its value,
    // kept for resend.
    property string method: "email"
    property string sentContact: ""

    readonly property bool hasBoth: hintEmail.length > 0 && hintPhone.length > 0

    header: PageHeader {
        title: i18n.tr("Reset password")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: i18n.tr("Back"); onTriggered: page.goBack() }
        ]
    }

    function goBack() {
        if (page.step > 0) { page.errorMsg = ""; page.step -= 1; }
        else page.pageStack.pop();
    }

    function fail(err) { busy = false; page.errorMsg = err.message; }

    Component.onCompleted: usernameField.input.forceActiveFocus()

    onStepChanged: {
        if (step === 0) usernameField.input.forceActiveFocus();
        else if (step === 1) (method === "email" ? emailMasked.input : phoneField.input).forceActiveFocus();
        else if (step === 2) otpField.input.forceActiveFocus();
        else if (step === 3) passwordField.input.forceActiveFocus();
    }

    // step 2 -> 3: there is no standalone verify endpoint, so we just check the
    // code is the right length here; correctness is confirmed when the new
    // password is submitted (a bad code sends the user back to this step).
    function verifyCode() {
        if (busy) return;
        errorMsg = "";
        if (otpField.text.length < 6) {
            errorMsg = i18n.tr("Please enter the 6-digit code.");
            return;
        }
        step = 3;
    }

    // step 0 -> 1: fetch the masked contact hint for this username.
    function lookupHint() {
        if (busy) return;
        errorMsg = "";
        if (usernameField.text.length === 0) {
            errorMsg = i18n.tr("Please enter your username.");
            return;
        }
        username = usernameField.text;
        busy = true;
        AccountService.getContactHint(Config.baseUrl, username,
            function (resp) {
                busy = false;
                var d = (resp && resp.data) ? resp.data : {};
                page.hintEmail = d.email || "";
                page.hintPhone = d.phone || "";
                page.method = page.hintEmail.length > 0 ? "email" : "phone";
                page.step = 1;
            },
            fail);
    }

    // step 1 -> 2: send the OTP to the entered contact.
    function sendOtp() {
        if (busy) return;
        errorMsg = "";
        var contact = {};
        if (method === "email") {
            if (!emailMasked.complete) {
                errorMsg = i18n.tr("Please fill in the hidden part of your email.");
                return;
            }
            contact.email = emailMasked.value;
            sentContact = emailMasked.value;
        } else {
            if (phoneField.text.replace(/\D/g, "").length < 6) {
                errorMsg = i18n.tr("Please enter the phone number on your account.");
                return;
            }
            contact.phone = phoneField.text;
            sentContact = phoneField.text;
        }
        busy = true;
        AccountService.requestPasswordReset(Config.baseUrl, username, contact,
            function () { busy = false; resendSeconds = 90; step = 2; },
            fail);
    }

    // Re-send the OTP to the same contact once the countdown reaches zero.
    function resend() {
        if (busy || resendSeconds > 0) return;
        errorMsg = "";
        var contact = method === "email" ? { email: sentContact } : { phone: sentContact };
        busy = true;
        AccountService.requestPasswordReset(Config.baseUrl, username, contact,
            function () { busy = false; resendSeconds = 90; Toast.show(i18n.tr("New code sent.")); },
            fail);
    }

    // step 3: set the new password (this is also where the OTP is actually
    // verified server-side). On a bad/expired code, send the user back to step 2.
    function submitReset() {
        if (busy) return;
        errorMsg = "";
        if (!AccountService.isValidPassword(passwordField.text)) {
            errorMsg = i18n.tr("Password must be 8–16 characters and include an uppercase letter, a lowercase letter and a number.");
            return;
        }
        if (passwordField.text !== confirmField.text) {
            errorMsg = i18n.tr("Passwords do not match.");
            return;
        }
        busy = true;
        AccountService.resetPassword(Config.baseUrl, username, otpField.text, passwordField.text,
            function () {
                busy = false;
                Toast.success(i18n.tr("Password reset. Please log in."));
                page.pageStack.pop();
            },
            function (err) {
                busy = false;
                page.errorMsg = err.message;
                if (err.message && /otp|code/i.test(err.message))
                    page.step = 2;   // bad code — go re-enter it
            });
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
                anchors.horizontalCenter: parent.horizontalCenter
                width: units.gu(9); height: width
                source: Qt.resolvedUrl("../../assets/serey-logo.png")
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }

            // Step dots (3 steps)
            Row {
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
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                font.family: Style.fontFamily
                text: page.step === 0 ? i18n.tr("Find your account")
                    : page.step === 1 ? i18n.tr("Verify your identity")
                    : page.step === 2 ? i18n.tr("Enter your code")
                    : i18n.tr("Create a new password")
                font.pixelSize: Style.fontTitle
                font.weight: Font.DemiBold
                color: Style.textTitle
                wrapMode: Text.WordWrap
            }

            Item { width: 1; height: Style.spacingXs }

            // --- Step 0: username -------------------------------------------
            FormField {
                id: usernameField
                visible: page.step === 0
                width: parent.width
                placeholder: i18n.tr("Username")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                onAccepted: page.lookupHint()
            }

            // --- Step 1: hint + contact -------------------------------------
            Label {
                visible: page.step === 1
                width: parent.width
                font.family: Style.fontFamily
                font.pixelSize: Style.fontSmall
                color: Style.textSecondary
                wrapMode: Text.WordWrap
                text: page.method === "email"
                      ? i18n.tr("Fill in the hidden part of your email to receive a code.")
                      : i18n.tr("We'll send a code to your phone %1.").arg(page.hintPhone)
            }
            // Method toggle (only when the account has both an email and a phone)
            Row {
                visible: page.step === 1 && page.hasBoth
                width: parent.width
                spacing: Style.spacingS
                Repeater {
                    model: [ { m: "email", label: i18n.tr("Email") }, { m: "phone", label: i18n.tr("Phone") } ]
                    delegate: AbstractButton {
                        width: (parent.width - Style.spacingS) / 2
                        height: units.gu(5)
                        onClicked: { page.method = modelData.m; page.errorMsg = ""; emailMasked.input.text = ""; phoneField.text = ""; }
                        Rectangle {
                            anchors.fill: parent
                            radius: Style.cardRadius
                            color: page.method === modelData.m ? Style.brand : Style.surface
                            border.width: units.dp(1.5)
                            border.color: page.method === modelData.m ? Style.brand : Style.divider
                            Label {
                                anchors.centerIn: parent
                                text: modelData.label
                                font.pixelSize: Style.fontRegular
                                font.weight: Font.DemiBold
                                font.family: Style.fontFamily
                                color: page.method === modelData.m ? Style.textOnBrand : Style.textPrimary
                            }
                        }
                    }
                }
            }
            // Email: masked-retype input (fill the hidden front; suffix revealed).
            MaskedContactInput {
                id: emailMasked
                visible: page.step === 1 && page.method === "email"
                width: parent.width
                maskedEmail: page.hintEmail
                onAccepted: page.sendOtp()
            }
            // Phone: plain entry (the masked hint is shown in the line above).
            FormField {
                id: phoneField
                visible: page.step === 1 && page.method === "phone"
                width: parent.width
                placeholder: i18n.tr("Phone on your account")
                inputMethodHints: Qt.ImhDigitsOnly
                onAccepted: page.sendOtp()
            }

            // --- Step 2: enter the code -------------------------------------
            Label {
                visible: page.step === 2
                width: parent.width
                font.family: Style.fontFamily
                font.pixelSize: Style.fontSmall
                color: Style.textSecondary
                wrapMode: Text.WordWrap
                text: i18n.tr("We sent a verification code to %1.").arg(page.sentContact)
            }
            OtpInput {
                id: otpField
                visible: page.step === 2
                width: parent.width
                onAccepted: page.verifyCode()
            }
            Item {
                visible: page.step === 2
                width: parent.width
                height: units.gu(3)
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: page.resendSeconds > 0
                    text: i18n.tr("Resend code in %1s").arg(page.resendSeconds)
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFamily
                    color: Style.textSecondary
                }
                AbstractButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: page.resendSeconds === 0
                    width: fpResendLbl.width; height: fpResendLbl.height
                    onClicked: page.resend()
                    Label {
                        id: fpResendLbl
                        text: i18n.tr("Resend code")
                        font.pixelSize: Style.fontSmall
                        font.weight: Font.DemiBold
                        font.family: Style.fontFamily
                        color: Style.brand
                    }
                }
            }
            // --- Step 3: new password --------------------------------------
            FormField {
                id: passwordField
                visible: page.step === 3
                width: parent.width
                placeholder: i18n.tr("New password")
                echoMode: TextInput.Password
            }
            PasswordChecklist {
                visible: page.step === 3
                width: parent.width
                password: passwordField.text
            }
            FormField {
                id: confirmField
                visible: page.step === 3
                width: parent.width
                placeholder: i18n.tr("Confirm new password")
                echoMode: TextInput.Password
                onAccepted: page.submitReset()
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
                text: page.busy ? i18n.tr("Please wait…")
                    : page.step === 0 ? i18n.tr("Continue")
                    : page.step === 1 ? i18n.tr("Send code")
                    : page.step === 2 ? i18n.tr("Next")
                    : i18n.tr("Reset password")
                onClicked: {
                    if (page.step === 0) page.lookupHint();
                    else if (page.step === 1) page.sendOtp();
                    else if (page.step === 2) page.verifyCode();
                    else page.submitReset();
                }
            }
        }
    }
}
