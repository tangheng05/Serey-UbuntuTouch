import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/AccountService.js" as AccountService
import "../services/AnonymousInviteService.js" as InviteService

// Redeem an invite code -> free anonymous account. Same key-save + auto-login as
// the paid Monero flow, minus payment. Steps: 0 code, 1 username, 2 save key.
Page {
    id: page

    // Deep links (WebAppView intercept) can prefill and skip straight to step 1.
    property string prefillCode: ""

    property int step: 0
    property bool busy: false
    property string errorMsg: ""

    property string code: ""
    property string invitedBy: ""
    property string username: ""
    property string createdUsername: ""
    property string masterKey: ""     // client-generated; shown to the user, never sent
    property bool keySaved: false

    KeygenBridge { id: keygen }

    header: PageHeader {
        title: Lang.tr("Redeem invite")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.goBack() }
        ]
    }

    Component.onCompleted: {
        if (prefillCode.length > 0) {
            codeField.text = prefillCode;
            page.checkCode();
        }
    }

    function goBack() {
        if (page.step === 1) { page.errorMsg = ""; page.step = 0; return; }
        page.pageStack.pop();
    }

    function fail(err) {
        page.busy = false;
        if (err && err.status === 401) return;   // already toasted globally
        page.errorMsg = (err && err.message) ? err.message : Lang.tr("Something went wrong.");
    }

    onStepChanged: if (step !== 1) Qt.inputMethod.hide();

    // step 0: validate the code, then move to username entry.
    function checkCode() {
        if (busy) return;
        errorMsg = "";
        var c = codeField.text.trim();
        if (c.length === 0) { errorMsg = Lang.tr("Enter your invite code."); return; }
        busy = true;
        InviteService.validateInvite(Config.baseUrl, c,
            function (r) {
                page.busy = false;
                if (!r.valid) {
                    page.errorMsg = Lang.tr("This invite is invalid, already used, or revoked. Ask your inviter for a new one.");
                    return;
                }
                page.code = c;
                page.invitedBy = r.invitedBy;
                page.step = 1;
            }, fail);
    }

    // step 1: generate keys on-device, then claim the account. The master password
    // never leaves the device; only the public keys + posting private key are sent.
    function redeem() {
        if (busy) return;
        errorMsg = "";
        if (!AccountService.isValidUsername(usernameField.text)) {
            errorMsg = Lang.tr("Username must be 5–30 characters: lowercase letters, numbers or hyphens.");
            return;
        }
        busy = true;
        var uname = usernameField.text;
        keygen.generate(uname,
            function (keys) {
                InviteService.redeemInvite(Config.baseUrl, page.code, uname, keys,
                    function (r) {
                        page.busy = false;
                        page.masterKey = keys.master_password;
                        page.createdUsername = r.username;
                        page.step = 2;
                        Toast.success(Lang.tr("Account created!"));
                    }, fail);
            },
            function (msg) { page.busy = false; page.errorMsg = msg; });
    }

    // Log in with the master password (owner-capable token, same as self-custody).
    function finishAndLogin() {
        if (page.busy) return;
        page.busy = true;
        AccountService.login(Config.baseUrl, page.createdUsername, page.masterKey,
            function (auth) {
                page.busy = false;
                Session.clear();
                FollowStore.reset();
                Session.setAuth(auth.token, page.createdUsername);
                AccountService.profile(Config.baseUrl, page.createdUsername, auth.token,
                    function (user) { Session.avatarUrl = user.profileUrl; },
                    function (err) { /* keep letter-fallback avatar */ });
                Nav.goToFeed();
            },
            function (err) {
                page.busy = false;
                Toast.show(Lang.tr("Account ready. Please log in with your key."));
                page.pageStack.pop();
                page.pageStack.push(Qt.resolvedUrl("LoginPage.qml"), { afterSuccess: "feed" });
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

            Image {
                visible: page.step === 0
                anchors.horizontalCenter: parent.horizontalCenter
                width: units.gu(9); height: width
                source: Qt.resolvedUrl("../../assets/serey-logo.png")
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }

            Row {
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
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                font.family: Style.fontFor(text)
                text: page.step === 0 ? Lang.tr("You're invited to Serey")
                    : page.step === 1 ? Lang.tr("Choose a username")
                    : Lang.tr("Save your private key")
                font.pixelSize: Style.fontTitle
                font.weight: Font.DemiBold
                color: Style.textTitle
                wrapMode: Text.WordWrap
            }

            // ================= Step 0: code =================
            Label {
                visible: page.step === 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Lang.tr("Enter your invite code to get a free account. No email, no payment.")
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFor(text)
                color: Style.textSecondary
                wrapMode: Text.WordWrap
            }
            FormField {
                id: codeField
                visible: page.step === 0
                width: parent.width
                placeholder: Lang.tr("Invite code (e.g. SEREY-XXXXXXXX)")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                onAccepted: page.checkCode()
            }

            // ================= Step 1: username =================
            Label {
                visible: page.step === 1 && page.invitedBy.length > 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Lang.tr("Invited by @%1").arg(page.invitedBy)
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFor(text)
                color: Style.textSecondary
                wrapMode: Text.WordWrap
            }
            FormField {
                id: usernameField
                visible: page.step === 1
                width: parent.width
                placeholder: Lang.tr("Username")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                onAccepted: page.redeem()
            }

            // ================= Step 2: save key =================
            SuccessBurst {
                visible: page.step === 2
                anchors.horizontalCenter: parent.horizontalCenter
                playing: page.step === 2
                accent: Style.success
            }
            Rectangle {
                visible: page.step === 2
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
            // Username above the key, so the user saves both together.
            Rectangle {
                visible: page.step === 2
                width: parent.width
                height: nameCol.height + Style.spacingM * 2
                radius: Style.cardRadius
                color: Style.iconBackground
                Column {
                    id: nameCol
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                              leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                    spacing: Style.spacingS
                    Label {
                        text: Lang.tr("Username")
                        font.pixelSize: Style.fontXSmall
                        font.weight: Font.DemiBold
                        font.family: Style.fontFamily
                        color: Style.textSecondary
                    }
                    Label {
                        width: parent.width
                        text: page.createdUsername
                        wrapMode: Text.WrapAnywhere
                        font.pixelSize: Style.fontRegular
                        font.family: "Ubuntu Mono"
                        color: Style.textPrimary
                    }
                }
            }
            // Full key on a card; tapping copies it and unlocks the button below.
            AbstractButton {
                visible: page.step === 2
                width: parent.width
                height: keyBox.height
                onClicked: {
                    Clipboard.push(page.masterKey);
                    page.keySaved = true;
                    Toast.success(Lang.tr("Key copied. Store it somewhere safe."));
                }
                Rectangle {
                    id: keyBox
                    width: parent.width
                    height: keyCol.height + Style.spacingM * 2
                    radius: Style.cardRadius
                    color: Style.iconBackground
                    border.width: units.dp(1.5)
                    border.color: page.keySaved ? Style.brand : Style.divider
                    Behavior on border.color { ColorAnimation { duration: 120 } }

                    Column {
                        id: keyCol
                        anchors { left: parent.left; right: parent.right; top: parent.top
                                  leftMargin: Style.spacingM; rightMargin: Style.spacingM; topMargin: Style.spacingM }
                        spacing: Style.spacingS

                        Item {
                            width: parent.width
                            height: Math.max(capLabel.height, copyIcn.height)
                            Label {
                                id: capLabel
                                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                text: Lang.tr("Private key")
                                font.pixelSize: Style.fontXSmall
                                font.weight: Font.DemiBold
                                font.family: Style.fontFamily
                                color: Style.textSecondary
                            }
                            Row {
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                spacing: Style.spacingXs
                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: page.keySaved ? Lang.tr("Copied") : Lang.tr("Tap to copy")
                                    font.pixelSize: Style.fontXSmall
                                    font.family: Style.fontFamily
                                    color: Style.brand
                                }
                                Icon {
                                    id: copyIcn
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(2); height: width
                                    name: page.keySaved ? "tick" : "edit-copy"
                                    color: Style.brand
                                }
                            }
                        }

                        Label {
                            width: parent.width
                            text: page.masterKey
                            wrapMode: Text.WrapAnywhere
                            font.pixelSize: Style.fontRegular
                            font.family: "Ubuntu Mono"
                            color: Style.textPrimary
                        }
                    }
                }
            }

            // ================= Shared: error + primary action =================
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
                busy: page.busy
                enabled: !page.busy && (page.step !== 2 || page.keySaved)
                text: page.busy ? Lang.tr("Please wait…")
                    : page.step === 0 ? Lang.tr("Continue")
                    : page.step === 1 ? Lang.tr("Create my account")
                    : Lang.tr("I've saved my key")
                onClicked: {
                    if (page.step === 0) page.checkCode();
                    else if (page.step === 1) page.redeem();
                    else page.finishAndLogin();
                }
            }
        }
    }
}
