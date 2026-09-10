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
    // "" pops back to where login-gate interrupted; "feed" goes to the feed
    property string afterSuccess: ""

    // 2FA step, entered when login() reports the account requires it.
    property bool needs2fa: false
    property string twoFaEmailHint: ""
    property int resendSeconds: 0

    header: PageHeader {
        title: Lang.tr("Log in")
    }

    function completeLogin(auth) {
        page.busy = false;
        // Clear -> set, never overwrite in place, so account B never inherits anything cached from account A.
        Session.clear();
        FollowStore.reset();
        Session.setAuth(auth.token, usernameField.text, auth.deviceId);
        AccountService.profile(Config.baseUrl, usernameField.text, auth.token,
            function (user) { Session.avatarUrl = user.profileUrl; },
            function (err) { /* keep letter-fallback avatar */ });
        if (page.afterSuccess === "feed") Nav.goToFeed();
        else page.pageStack.pop();
    }

    function submit() {
        if (busy) return;
        errorMsg = "";
        if (usernameField.text.length === 0 || passwordField.text.length === 0) {
            errorMsg = Lang.tr("Please enter your username and password.");
            return;
        }
        busy = true;
        AccountService.login(Config.baseUrl, usernameField.text, passwordField.text,
            function (auth) { page.completeLogin(auth); },
            function (err) {
                busy = false;
                page.errorMsg = err.message;
            },
            function (emailHint) {
                busy = false;
                page.twoFaEmailHint = emailHint;
                page.needs2fa = true;
                page.resendSeconds = 90;
                otpField.input.forceActiveFocus();
            });
    }

    function verify2fa() {
        if (busy) return;
        errorMsg = "";
        if (otpField.text.length < 6) {
            errorMsg = Lang.tr("Please enter the 6-digit code.");
            return;
        }
        busy = true;
        AccountService.verifyLogin2fa(Config.baseUrl, usernameField.text, otpField.text,
            function (auth) { page.completeLogin(auth); },
            function (err) { busy = false; page.errorMsg = err.message; });
    }

    function resend2fa() {
        if (busy || resendSeconds > 0) return;
        errorMsg = "";
        busy = true;
        AccountService.login(Config.baseUrl, usernameField.text, passwordField.text,
            function (auth) { page.completeLogin(auth); },
            function (err) { busy = false; page.errorMsg = err.message; },
            function (emailHint) { busy = false; page.resendSeconds = 90; Toast.show(Lang.tr("New code sent.")); });
    }

    Timer {
        interval: 1000; repeat: true
        running: page.needs2fa && page.resendSeconds > 0
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
            // Gaps use explicit Item spacers below, not uniform spacing
            spacing: 0

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: units.gu(9); height: width
                source: Qt.resolvedUrl("../../assets/serey-logo.png")
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }

            Item { width: 1; height: Style.spacingM }

            Column {
                width: parent.width
                spacing: Style.spacingXs
                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: page.needs2fa ? Lang.tr("Enter your code") : Lang.tr("Welcome back")
                    font.pixelSize: Style.fontTitle
                    font.weight: Font.DemiBold
                    font.family: Style.fontFor(text)
                    color: Style.textTitle
                }
                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: page.needs2fa
                        ? Lang.tr("We sent a verification code to %1.").arg(page.twoFaEmailHint)
                        : Lang.tr("Sign in to your Serey account")
                    font.pixelSize: Style.fontRegular
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                    wrapMode: Text.WordWrap
                }
            }

            Item { width: 1; height: Style.spacingL }

            FormField {
                id: usernameField
                visible: !page.needs2fa
                width: parent.width
                placeholder: Lang.tr("Username")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                onAccepted: passwordField.input.forceActiveFocus()
            }

            Item { visible: !page.needs2fa; width: 1; height: Style.spacingM }

            FormField {
                id: passwordField
                visible: !page.needs2fa
                width: parent.width
                placeholder: Lang.tr("Password")
                echoMode: TextInput.Password
                onAccepted: page.submit()
            }

            Item { visible: !page.needs2fa; width: 1; height: Style.spacingXs }

            LinkButton {
                visible: !page.needs2fa
                width: parent.width
                label: Lang.tr("Forgot password?")
                horizontalAlignment: Text.AlignRight
                onClicked: page.pageStack.push(Qt.resolvedUrl("ForgotPasswordPage.qml"))
            }

            OtpInput {
                id: otpField
                visible: page.needs2fa
                width: parent.width
                onAccepted: page.verify2fa()
            }

            Item {
                visible: page.needs2fa
                width: parent.width; height: units.gu(3)
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
                    width: resendLbl.width; height: resendLbl.height
                    onClicked: page.resend2fa()
                    Label {
                        id: resendLbl
                        text: Lang.tr("Resend code")
                        font.pixelSize: Style.fontSmall
                        font.weight: Font.DemiBold
                        font.family: Style.fontFor(text)
                        color: Style.brand
                    }
                }
            }

            Item { width: 1; height: Style.spacingS }

            Label {
                width: parent.width
                font.family: Style.fontFor(text)
                font.pixelSize: Style.fontSmall
                text: page.errorMsg
                color: Style.danger
                wrapMode: Text.WordWrap
                visible: text.length > 0
            }

            Item { width: 1; height: page.errorMsg.length > 0 ? Style.spacingS : 0 }

            PrimaryButton {
                width: parent.width
                text: page.needs2fa
                    ? (page.busy ? Lang.tr("Verifying…") : Lang.tr("Verify"))
                    : (page.busy ? Lang.tr("Signing in…") : Lang.tr("Log in"))
                busy: page.busy
                onClicked: page.needs2fa ? page.verify2fa() : page.submit()
            }

            Item { width: 1; height: Style.spacingXs }

            LinkButton {
                visible: page.needs2fa
                width: parent.width
                label: Lang.tr("Use a different account")
                horizontalAlignment: Text.AlignHCenter
                onClicked: {
                    page.needs2fa = false;
                    page.errorMsg = "";
                    otpField.text = "";
                    usernameField.input.forceActiveFocus();
                }
            }

            SecondaryButton {
                visible: !page.needs2fa
                width: parent.width
                text: Lang.tr("Sign up")
                onClicked: page.pageStack.push(Qt.resolvedUrl("CreateAccountPage.qml"))
            }
        }
    }
}
