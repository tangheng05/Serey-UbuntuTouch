import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/AccountService.js" as AccountService

// Anonymous (Monero) signup. The posting key comes back only once, so step 2
// has to show it. Steps: 0 username, 1 pay, 2 save key + done, 3 error.
Page {
    id: page

    property int step: 0
    property bool busy: false
    property string errorMsg: ""

    // Carried across steps.
    property string username: ""
    property string createdUsername: ""
    property string postingKey: ""
    property bool keySaved: false

    // Payment state.
    property var payment: null            // { paymentId, payAddress, payAmount, expiresAt }
    property string payStatus: "waiting"
    property int secondsLeft: 0
    property double _expiryMs: 0

    header: PageHeader {
        title: Lang.tr("Anonymous")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.goBack() }
        ]
    }

    // From the pay screen, back just cancels and returns to the username step.
    function goBack() {
        if (page.step === 1) {
            _stopTimers();
            page.errorMsg = ""; page.payStatus = "waiting"; page.payment = null;
            page.step = 0;
            return;
        }
        page.pageStack.pop();
    }

    function fail(err) { page.busy = false; page.errorMsg = err.message; }

    // Don't auto-focus the username field; focus hides the placeholder.
    onStepChanged: if (step !== 0) Qt.inputMethod.hide();

    // step 0: validate + confirm the username is free, then create the payment.
    function checkUsername() {
        if (busy) return;
        errorMsg = "";
        if (!AccountService.isValidUsername(usernameField.text)) {
            errorMsg = Lang.tr("Username must be 5–30 characters: lowercase letters, numbers or hyphens.");
            return;
        }
        busy = true;
        AccountService.checkUsernameAvailable(Config.baseUrl, usernameField.text,
            function () { page.username = usernameField.text; page.startPayment(); },
            fail);
    }

    function startPayment() {
        page.busy = true;
        page.errorMsg = "";
        AccountService.createAnonymousPayment(Config.baseUrl, page.username,
            function (pm) {
                page.busy = false;
                page.payment = pm;
                page.payStatus = "waiting";
                page._startCountdown(pm.expiresAt);
                pollTimer.restart();
                page.step = 1;
            },
            function (err) {
                page.busy = false;
                page.errorMsg = (err && err.message) ? err.message : Lang.tr("Failed to create payment.");
            });
    }

    function _stopTimers() { pollTimer.stop(); countdownTimer.stop(); }

    function _startCountdown(expiresAt) {
        var end = expiresAt ? Date.parse(expiresAt) : NaN;
        if (isNaN(end)) end = Date.now() + 15 * 60 * 1000;   // web fallback
        page._expiryMs = end;
        page._tickCountdown();
        countdownTimer.restart();
    }
    function _tickCountdown() {
        var left = Math.max(0, Math.round((page._expiryMs - Date.now()) / 1000));
        page.secondsLeft = left;
        // Only expire while still waiting; a detected XMR tx keeps confirming past 0.
        if (left === 0 && page.step === 1 && page.payStatus === "waiting") {
            _stopTimers();
            page.errorMsg = Lang.tr("Payment expired. Please start again.");
            page.step = 3;
        }
    }
    function _fmtCountdown(s) {
        var m = Math.floor(s / 60), r = s % 60;
        return (m < 10 ? "0" : "") + m + ":" + (r < 10 ? "0" : "") + r;
    }

    function _pollStatus() {
        if (!page.payment) return;
        AccountService.checkAnonymousStatus(Config.baseUrl, page.payment.paymentId,
            function (r) {
                page.payStatus = r.status;
                if (r.status === "completed" || (r.accountCreated && r.postingPrivateKey)) {
                    _stopTimers();
                    if (r.postingPrivateKey) {
                        page.postingKey = r.postingPrivateKey;
                        page.createdUsername = r.username || page.username;
                        page.step = 2;
                        Toast.success(Lang.tr("Account created!"));
                    } else {
                        // Key already handed out (webhook likely beat us); nothing to show.
                        page.errorMsg = Lang.tr("Your account was created but the key was already retrieved. Please contact support.");
                        page.step = 3;
                    }
                } else if (r.status === "failed" || r.status === "refunded" || r.status === "expired") {
                    _stopTimers();
                    page.errorMsg = r.status === "expired"
                        ? Lang.tr("Payment expired. Please start again.")
                        : Lang.tr("Payment failed. Please try again.");
                    page.step = 3;
                }
            },
            function () { /* transient poll errors ignored; next tick retries */ });
    }

    // Log in with the posting key (Serey takes a WIF key in the password field).
    function finishAndLogin() {
        if (page.busy) return;
        page.busy = true;
        AccountService.login(Config.baseUrl, page.createdUsername, page.postingKey,
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
                // Account exists and the key is saved; fall back to the login page.
                page.busy = false;
                Toast.show(Lang.tr("Account ready. Please log in with your key."));
                var stack = page.pageStack;
                stack.pop();   // this page
                stack.pop();   // the Create Account chooser
                stack.push(Qt.resolvedUrl("LoginPage.qml"), { afterSuccess: "feed" });
            });
    }

    Timer { id: pollTimer;      interval: 10000; repeat: true; onTriggered: page._pollStatus() }
    Timer { id: countdownTimer; interval: 1000;  repeat: true; onTriggered: page._tickCountdown() }

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
                font.family: Style.fontFor(text)
                text: page.step === 0 ? Lang.tr("Choose a username")
                    : page.step === 1 ? Lang.tr("Pay with Monero")
                    : Lang.tr("Save your private key")
                font.pixelSize: Style.fontTitle
                font.weight: Font.DemiBold
                color: Style.textTitle
                wrapMode: Text.WordWrap
            }

            // ================= Step 0: username =================
            Label {
                visible: page.step === 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Lang.tr("Instant account, no email. A one-time $5 fee is paid in Monero (XMR).")
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFor(text)
                color: Style.textSecondary
                wrapMode: Text.WordWrap
            }
            FormField {
                id: usernameField
                visible: page.step === 0
                width: parent.width
                placeholder: Lang.tr("Username")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                onAccepted: page.checkUsername()
            }

            // ================= Step 1: pay (XMR) =================
            Label {
                visible: page.step === 1
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Lang.tr("Send exactly")
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFamily
                color: Style.textSecondary
            }
            Label {
                visible: page.step === 1
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: page.payment ? (page.payment.payAmount + " XMR") : ""
                font.pixelSize: Style.fontTitle
                font.weight: Font.DemiBold
                color: Style.textPrimary
            }

            // QR on a white card so it scans in dark mode.
            Rectangle {
                visible: page.step === 1 && page.payStatus === "waiting"
                anchors.horizontalCenter: parent.horizontalCenter
                width: units.gu(22); height: width
                radius: units.dp(10)
                color: "#FFFFFF"
                // Monero URI with the amount, so a scanning wallet auto-fills it
                // exactly (copy-address below stays plain for manual paste).
                QrCode {
                    anchors { fill: parent; margins: units.gu(1) }
                    text: page.payment
                          ? ("monero:" + page.payment.payAddress
                             + (page.payment.payAmount ? "?tx_amount=" + page.payment.payAmount : ""))
                          : ""
                }
            }

            AbstractButton {
                visible: page.step === 1 && page.payStatus === "waiting"
                width: parent.width
                height: addrLabel.height + Style.spacingM * 2
                onClicked: {
                    if (!page.payment) return;
                    Clipboard.push(page.payment.payAddress);
                    Toast.show(Lang.tr("Address copied"));
                }
                Rectangle { anchors.fill: parent; radius: units.dp(10); color: Style.iconBackground }
                Label {
                    id: addrLabel
                    anchors { left: parent.left; right: copyIcon.left; leftMargin: Style.spacingM; rightMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
                    text: page.payment ? page.payment.payAddress : ""
                    wrapMode: Text.WrapAnywhere
                    font.pixelSize: Style.fontSmall
                    color: Style.textPrimary
                }
                Icon {
                    id: copyIcon
                    anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                    width: units.gu(2.2); height: width
                    name: "edit-copy"; color: Style.brand
                }
            }

            // Waiting / confirming status.
            Row {
                visible: page.step === 1
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.spacingS
                ActivityIndicator {
                    anchors.verticalCenter: parent.verticalCenter
                    running: page.step === 1
                    width: units.gu(2); height: width
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: page.payStatus === "waiting"
                          ? (Lang.tr("Waiting for payment…") + "  " + page._fmtCountdown(page.secondsLeft))
                          : Lang.tr("Confirming payment…")
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFamily
                    color: Style.textSecondary
                }
            }
            Label {
                visible: page.step === 1 && page.payStatus !== "waiting"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Lang.tr("Payment detected. Monero can take 20–30 minutes to confirm. Keep this page open; your account is created automatically once confirmed.")
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFor(text)
                color: Style.textSecondary
                wrapMode: Text.WordWrap
            }

            // ================= Step 2: save key + done =================
            SuccessBurst {
                visible: page.step === 2
                anchors.horizontalCenter: parent.horizontalCenter
                playing: page.step === 2
                accent: Style.success
            }
            Label {
                visible: page.step === 2
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Lang.tr("Account created!")
                font.pixelSize: Style.fontTitle
                font.weight: Font.DemiBold
                font.family: Style.fontFor(text)
                color: Style.textTitle
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
            // Full key on a card; tapping copies it and unlocks the button below.
            AbstractButton {
                visible: page.step === 2
                width: parent.width
                height: keyBox.height
                onClicked: {
                    Clipboard.push(page.postingKey);
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
                            text: page.postingKey
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
                visible: page.step !== 1
                text: page.busy ? Lang.tr("Please wait…")
                    : page.step === 0 ? Lang.tr("Create account with Monero")
                    : page.step === 2 ? Lang.tr("I've saved my key")
                    : Lang.tr("Try again")
                onClicked: {
                    if (page.step === 0) page.checkUsername();
                    else if (page.step === 2) page.finishAndLogin();
                    else { page.errorMsg = ""; page.payment = null; page.payStatus = "waiting"; page.step = 0; }
                }
            }

            // Step 1 has no primary action (payment is polled); only a cancel.
            SecondaryButton {
                width: parent.width
                visible: page.step === 1
                text: Lang.tr("Cancel")
                onClicked: page.goBack()
            }
        }
    }
}
