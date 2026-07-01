import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/AccountService.js" as AccountService

/*
 * Username/password login. On success stores the JWT in Session and pops back
 * to Settings (which then loads the profile). Styled with the app's shared
 * design tokens (logo hero, branded FormField inputs, PrimaryButton).
 */
Page {
    id: page

    property bool busy: false
    property string errorMsg: ""

    header: PageHeader {
        title: Lang.tr("Log in")
    }

    Component.onCompleted: usernameField.input.forceActiveFocus()

    function submit() {
        if (busy) return;
        errorMsg = "";
        if (usernameField.text.length === 0 || passwordField.text.length === 0) {
            errorMsg = Lang.tr("Please enter your username and password.");
            return;
        }
        busy = true;
        AccountService.login(Config.baseUrl, usernameField.text, passwordField.text,
            function (auth) {
                busy = false;
                Session.setAuth(auth.token, usernameField.text);
                AccountService.profile(Config.baseUrl, usernameField.text, auth.token,
                    function (user) { Session.avatarUrl = user.profileUrl; },
                    function (err) { /* keep letter-fallback avatar */ });
                page.pageStack.pop();
            },
            function (err) {
                busy = false;
                page.errorMsg = err.message;
            });
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

            Column {
                width: parent.width
                spacing: Style.spacingXs
                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Lang.tr("Welcome back")
                    font.pixelSize: Style.fontTitle
                    font.weight: Font.DemiBold
                    font.family: Style.fontFor(text)
                    color: Style.textTitle
                }
                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Lang.tr("Sign in to your Serey account")
                    font.pixelSize: Style.fontRegular
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                    wrapMode: Text.WordWrap
                }
            }

            Item { width: 1; height: Style.spacingXs }

            FormField {
                id: usernameField
                width: parent.width
                placeholder: Lang.tr("Username")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                onAccepted: passwordField.input.forceActiveFocus()
            }

            FormField {
                id: passwordField
                width: parent.width
                placeholder: Lang.tr("Password")
                echoMode: TextInput.Password
                onAccepted: page.submit()
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

            PrimaryButton {
                width: parent.width
                text: page.busy ? Lang.tr("Signing in…") : Lang.tr("Log in")
                busy: page.busy
                onClicked: page.submit()
            }

            Item { width: 1; height: Style.spacingXs }

            LinkButton {
                width: parent.width
                label: Lang.tr("Forgot password?")
                onClicked: page.pageStack.push(Qt.resolvedUrl("ForgotPasswordPage.qml"))
            }

            LinkButton {
                width: parent.width
                label: Lang.tr("Sign up")
                onClicked: page.pageStack.push(Qt.resolvedUrl("CreateAccountPage.qml"))
            }
        }
    }
}
