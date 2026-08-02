import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/AccountService.js" as AccountService

Page {
    id: page

    // Prefills the enable-email field (Settings passes the account's profile email).
    property string initialEmail: ""

    property bool loading: true
    property bool statusEnabled: false
    property string statusEmail: ""
    property string errorMsg: ""
    property bool busy: false
    property int resendSeconds: 0

    // "status" | "enableEmail" | "enableOtp" | "disableEmail" | "disableOtp"
    property string mode: "status"
    property string pendingEmail: ""

    header: PageHeader {
        title: Lang.tr("Two-step verification")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.goBack() }
        ]
    }

    function goBack() {
        if (page.mode !== "status") { page.errorMsg = ""; page.mode = "status"; return; }
        page.pageStack.pop();
    }
    Keys.onEscapePressed: page.goBack()

    function load() {
        page.loading = true;
        AccountService.get2faStatus(Config.baseUrl, Session.token,
            function (st) {
                page.loading = false;
                page.statusEnabled = st.enabled;
                page.statusEmail = st.email;
            },
            function (err) {
                page.loading = false;
                page.errorMsg = err.message || Lang.tr("Failed to load status.");
            });
    }
    Component.onCompleted: page.load()

    function startEnable() {
        page.errorMsg = "";
        enableEmailField.text = page.initialEmail;
        page.mode = "enableEmail";
    }
    function startDisable() {
        page.errorMsg = "";
        disableEmailField.text = "";
        page.mode = "disableEmail";
    }

    function sendEnableOtp() {
        if (page.busy) return;
        var em = enableEmailField.text.trim();
        if (em.length === 0 || em.indexOf("@") < 1) {
            page.errorMsg = Lang.tr("Please enter a valid email address."); return;
        }
        page.errorMsg = "";
        page.busy = true;
        page.pendingEmail = em;
        AccountService.request2faEnable(Config.baseUrl, Session.token, em,
            function () { page.busy = false; page.resendSeconds = 90; page.mode = "enableOtp"; },
            function (err) { page.busy = false; page.errorMsg = err.message || Lang.tr("Failed to send code."); });
    }
    function confirmEnable() {
        if (page.busy) return;
        if (enableOtpField.text.length < 6) {
            page.errorMsg = Lang.tr("Please enter the 6-digit code."); return;
        }
        page.errorMsg = "";
        page.busy = true;
        AccountService.confirm2faEnable(Config.baseUrl, Session.token, enableOtpField.text,
            function () {
                page.busy = false;
                Toast.show(Lang.tr("Two-factor authentication enabled."));
                page.mode = "status";
                page.load();
            },
            function (err) { page.busy = false; page.errorMsg = err.message || Lang.tr("Invalid or expired code."); });
    }

    function sendDisableOtp() {
        if (page.busy) return;
        var em = disableEmailField.text.trim();
        if (em.length === 0) {
            page.errorMsg = Lang.tr("Please enter your two-factor email."); return;
        }
        page.errorMsg = "";
        page.busy = true;
        page.pendingEmail = em;
        AccountService.request2faDisable(Config.baseUrl, Session.token, em,
            function () { page.busy = false; page.resendSeconds = 90; page.mode = "disableOtp"; },
            function (err) { page.busy = false; page.errorMsg = err.message || Lang.tr("Failed to send code."); });
    }
    function confirmDisable() {
        if (page.busy) return;
        if (disableOtpField.text.length < 6) {
            page.errorMsg = Lang.tr("Please enter the 6-digit code."); return;
        }
        page.errorMsg = "";
        page.busy = true;
        AccountService.disable2fa(Config.baseUrl, Session.token, disableOtpField.text,
            function () {
                page.busy = false;
                Toast.show(Lang.tr("Two-factor authentication disabled."));
                page.mode = "status";
                page.load();
            },
            function (err) { page.busy = false; page.errorMsg = err.message || Lang.tr("Invalid or expired code."); });
    }

    function resend() {
        if (page.busy || page.resendSeconds > 0) return;
        page.errorMsg = "";
        page.busy = true;
        var onOk = function () { page.busy = false; page.resendSeconds = 90; Toast.show(Lang.tr("New code sent.")); };
        var onErr = function (err) { page.busy = false; page.errorMsg = err.message || Lang.tr("Failed to send code."); };
        if (page.mode === "enableOtp") AccountService.request2faEnable(Config.baseUrl, Session.token, page.pendingEmail, onOk, onErr);
        else if (page.mode === "disableOtp") AccountService.request2faDisable(Config.baseUrl, Session.token, page.pendingEmail, onOk, onErr);
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
        visible: !page.loading

        Column {
            id: form
            width: Math.min(parent.width - Style.spacingL * 2, units.gu(50))
            anchors.horizontalCenter: parent.horizontalCenter
            y: Style.spacingL
            spacing: Style.spacingM

            // --- status view ---
            Column {
                visible: page.mode === "status"
                width: parent.width
                spacing: Style.spacingM

                Row {
                    width: parent.width
                    spacing: Style.spacingS
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(3); height: width
                        name: "system-lock-screen"
                        color: page.statusEnabled ? Style.brand : Style.textSecondary
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.statusEnabled ? Lang.tr("Enabled") : Lang.tr("Disabled")
                        font.pixelSize: Style.fontLarge
                        font.weight: Font.DemiBold
                        color: page.statusEnabled ? Style.brand : Style.textPrimary
                    }
                }
                Label {
                    width: parent.width
                    visible: page.statusEnabled && page.statusEmail.length > 0
                    text: Lang.tr("Codes are sent to %1.").arg(page.statusEmail)
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                    wrapMode: Text.WordWrap
                }
                Label {
                    width: parent.width
                    visible: !page.statusEnabled
                    text: Lang.tr("Add an extra layer of security: after your password, we'll email you a one-time code to finish signing in.")
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                    wrapMode: Text.WordWrap
                }

                Item { width: 1; height: Style.spacingXs }

                PrimaryButton {
                    width: parent.width
                    visible: !page.statusEnabled
                    text: Lang.tr("Enable two-step verification")
                    onClicked: page.startEnable()
                }
                SecondaryButton {
                    width: parent.width
                    visible: page.statusEnabled
                    text: Lang.tr("Disable two-step verification")
                    onClicked: page.startDisable()
                }
            }

            // --- enable: email step ---
            Column {
                visible: page.mode === "enableEmail"
                width: parent.width
                spacing: Style.spacingM

                Label {
                    width: parent.width
                    text: Lang.tr("Enter the email we'll send your codes to.")
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                    wrapMode: Text.WordWrap
                }
                FormField {
                    id: enableEmailField
                    width: parent.width
                    placeholder: Lang.tr("Email address")
                    inputMethodHints: Qt.ImhEmailCharactersOnly
                    onAccepted: page.sendEnableOtp()
                }
            }

            // --- enable: OTP step ---
            Column {
                visible: page.mode === "enableOtp"
                width: parent.width
                spacing: Style.spacingM

                Label {
                    width: parent.width
                    text: Lang.tr("We sent a verification code to %1.").arg(page.pendingEmail)
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                    wrapMode: Text.WordWrap
                }
                OtpInput {
                    id: enableOtpField
                    width: parent.width
                    onAccepted: page.confirmEnable()
                }
            }

            // --- disable: email confirm step ---
            Column {
                visible: page.mode === "disableEmail"
                width: parent.width
                spacing: Style.spacingM

                Label {
                    width: parent.width
                    text: page.statusEmail.length > 0
                        ? Lang.tr("Confirm your two-factor email (%1) to continue.").arg(page.statusEmail)
                        : Lang.tr("Confirm your two-factor email to continue.")
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                    wrapMode: Text.WordWrap
                }
                FormField {
                    id: disableEmailField
                    width: parent.width
                    placeholder: Lang.tr("Email address")
                    inputMethodHints: Qt.ImhEmailCharactersOnly
                    onAccepted: page.sendDisableOtp()
                }
            }

            // --- disable: OTP step ---
            Column {
                visible: page.mode === "disableOtp"
                width: parent.width
                spacing: Style.spacingM

                Label {
                    width: parent.width
                    text: Lang.tr("We sent a verification code to %1.").arg(page.pendingEmail)
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                    wrapMode: Text.WordWrap
                }
                OtpInput {
                    id: disableOtpField
                    width: parent.width
                    onAccepted: page.confirmDisable()
                }
            }

            // --- shared: resend (OTP steps only) ---
            Item {
                visible: page.mode === "enableOtp" || page.mode === "disableOtp"
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
                    onClicked: page.resend()
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

            Label {
                width: parent.width
                visible: page.errorMsg.length > 0
                text: page.errorMsg
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFor(text)
                color: Style.danger
                wrapMode: Text.WordWrap
            }

            PrimaryButton {
                width: parent.width
                visible: page.mode !== "status"
                busy: page.busy
                text: {
                    if (page.mode === "enableEmail") return Lang.tr("Send code");
                    if (page.mode === "enableOtp") return Lang.tr("Enable");
                    if (page.mode === "disableEmail") return Lang.tr("Send code");
                    if (page.mode === "disableOtp") return Lang.tr("Disable");
                    return "";
                }
                onClicked: {
                    if (page.mode === "enableEmail") page.sendEnableOtp();
                    else if (page.mode === "enableOtp") page.confirmEnable();
                    else if (page.mode === "disableEmail") page.sendDisableOtp();
                    else if (page.mode === "disableOtp") page.confirmDisable();
                }
            }

            Item { width: 1; height: Style.spacingL }
        }
    }

    ActivityIndicator {
        anchors.centerIn: parent
        running: page.loading
        visible: running
    }
}
