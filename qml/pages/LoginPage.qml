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
    // After a successful login: "" (default) pops back to wherever the login-gate
    // interrupted; "feed" goes to the feed (Settings log-in, fresh signup).
    property string afterSuccess: ""

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
                // Clear -> set, never overwrite in place, so account B never inherits anything cached from account A.
                Session.clear();
                FollowStore.reset();
                Session.setAuth(auth.token, usernameField.text);
                AccountService.profile(Config.baseUrl, usernameField.text, auth.token,
                    function (user) { Session.avatarUrl = user.profileUrl; },
                    function (err) { /* keep letter-fallback avatar */ });
                if (page.afterSuccess === "feed") Nav.goToFeed();
                else page.pageStack.pop();
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
            // Gaps use explicit Item spacers below, not uniform spacing
            spacing: 0

            // Logo hero
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

            Item { width: 1; height: Style.spacingL }

            FormField {
                id: usernameField
                width: parent.width
                placeholder: Lang.tr("Username")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                onAccepted: passwordField.input.forceActiveFocus()
            }

            Item { width: 1; height: Style.spacingM }

            FormField {
                id: passwordField
                width: parent.width
                placeholder: Lang.tr("Password")
                echoMode: TextInput.Password
                onAccepted: page.submit()
            }

            Item { width: 1; height: Style.spacingXs }

            LinkButton {
                width: parent.width
                label: Lang.tr("Forgot password?")
                horizontalAlignment: Text.AlignRight
                onClicked: page.pageStack.push(Qt.resolvedUrl("ForgotPasswordPage.qml"))
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
                text: page.busy ? Lang.tr("Signing in…") : Lang.tr("Log in")
                busy: page.busy
                onClicked: page.submit()
            }

            Item { width: 1; height: Style.spacingXs }

            SecondaryButton {
                width: parent.width
                text: Lang.tr("Sign up")
                onClicked: page.pageStack.push(Qt.resolvedUrl("CreateAccountPage.qml"))
            }
        }
    }
}
