import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../services/PaymentService.js" as PaymentService

/*
 * Native crypto (NOWPayments) buy-plan sheet; state in Theme/Payments.qml.
 * Only "finished" is terminal: the backend activates the plan there, no webhook.
 */
Item {
    id: sheet
    anchors.fill: parent
    visible: Payments.cryptoOpen
    z: 1500

    // 0 = currency picker, 1 = pay screen, 2 = success, 3 = fatal error
    property int step: 0
    property bool busy: false               // currencies fetch or create-payment in flight
    property var currencies: []          // full sorted list from the API
    property int preferredCount: 0       // how many of them are "recommended"
    property bool showAllCurrencies: false
    property bool currenciesLoaded: false
    property string errorMsg: ""
    property var payment: null              // view-model from PaymentService.createCryptoPayment
    property string payStatus: "waiting"
    property int secondsLeft: 0

    onVisibleChanged: {
        if (visible) {
            step = 0; errorMsg = ""; payment = null; payStatus = "waiting"; busy = false;
            showAllCurrencies = false;
            backdropFade.start(); sheetSlide.start();
            if (!currenciesLoaded) _loadCurrencies();
        } else {
            pollTimer.stop(); countdownTimer.stop();
        }
    }

    function closeSheet() {
        backdropFadeOut.start();
        sheetSlideOut.start();
    }

    // Recommended options (mirrors the web's smart default, usdttrc20 first),
    // shown at the top; everything else follows alphabetically.
    readonly property var preferredCurrencies: [
        "usdttrc20", "usdterc20", "usdtmatic", "usdtbsc",
        "usdc", "usdcmatic", "btc", "eth", "sol", "bnb"
    ]
    function _sortCurrencies(list) {
        var head = [], tail = [];
        for (var i = 0; i < list.length; i++) {
            if (sheet.preferredCurrencies.indexOf(list[i]) !== -1) head.push(list[i]);
            else tail.push(list[i]);
        }
        head.sort(function (a, b) {
            return sheet.preferredCurrencies.indexOf(a) - sheet.preferredCurrencies.indexOf(b);
        });
        tail.sort();
        sheet.preferredCount = head.length;
        return head.concat(tail);
    }

    // Only the recommended currencies at first; "More currencies" expands to
    // everything NOWPayments offers. If none of the preferred ones are
    // available there's nothing sensible to collapse to, so show all.
    readonly property var visibleCurrencies:
        (showAllCurrencies || preferredCount === 0) ? currencies
                                                    : currencies.slice(0, preferredCount)

    function _loadCurrencies() {
        sheet.busy = true;
        PaymentService.getCurrencies(Config.baseUrl,
            function (list) {
                sheet.busy = false;
                sheet.currencies = sheet._sortCurrencies(list);
                sheet.currenciesLoaded = list.length > 0;   // empty list: retry next open
            },
            function (err) {
                sheet.busy = false;
                sheet.errorMsg = (err && err.message) ? err.message
                                 : Lang.tr("Couldn't load payment currencies.");
            });
    }

    // NOWPayments codes are lowercase with the network glued on; show the
    // common stablecoin variants with a readable network suffix.
    function prettyCurrency(code) {
        var known = {
            usdttrc20: "USDT (TRC20)", usdterc20: "USDT (ERC20)",
            usdtmatic: "USDT (Polygon)", usdtbsc: "USDT (BSC)", usdtsol: "USDT (Solana)",
            usdcmatic: "USDC (Polygon)", usdcbsc: "USDC (BSC)", usdcsol: "USDC (Solana)"
        };
        return known[code] || String(code).toUpperCase();
    }

    // What the user picked. The backend reuses a still-valid pending payment for the
    // plan regardless of requested currency (no cancel endpoint), so the response can
    // come back in a different coin; surface that instead of showing it silently.
    property string requestedCode: ""
    readonly property bool currencyMismatch: payment !== null && requestedCode !== ""
        && payment.payCurrency.toLowerCase() !== requestedCode.toLowerCase()

    // Called from the currency list delegate; must live at root level because
    // imported JS services are null inside delegate handlers.
    function selectCurrency(code) {
        if (sheet.busy) return;
        sheet.busy = true;
        sheet.errorMsg = "";
        sheet.requestedCode = code;
        PaymentService.createCryptoPayment(Config.baseUrl, Session.token,
            Payments.planId, code,
            function (pm) {
                sheet.busy = false;
                sheet.payment = pm;
                // Persist it: if the user pays after closing the sheet (or the
                // app), Main.qml's background check still activates the plan
                // (crypto has no webhook fallback).
                Payments.setPendingCrypto(pm.paymentId, Payments.planId, pm.expiresAt);
                sheet.payStatus = "waiting";
                sheet._startCountdown(pm.expiresAt);
                pollTimer.restart();
                sheet.step = 1;
            },
            function (err) {
                sheet.busy = false;
                sheet.errorMsg = (err && err.message) ? err.message
                                 : Lang.tr("Failed to create payment.");
            });
    }

    function _startCountdown(expiresAt) {
        var end = expiresAt ? Date.parse(expiresAt) : NaN;
        if (isNaN(end)) end = Date.now() + 15 * 60 * 1000;  // web frontend's fallback
        sheet._expiryMs = end;
        sheet._tickCountdown();
        countdownTimer.restart();
    }
    property double _expiryMs: 0
    function _tickCountdown() {
        var left = Math.max(0, Math.round((sheet._expiryMs - Date.now()) / 1000));
        sheet.secondsLeft = left;
        if (left === 0 && sheet.step === 1) {
            countdownTimer.stop(); pollTimer.stop();
            sheet.errorMsg = Lang.tr("Payment expired. Please start again.");
            sheet.step = 3;
        }
    }
    function _fmtCountdown(s) {
        var m = Math.floor(s / 60), r = s % 60;
        return (m < 10 ? "0" : "") + m + ":" + (r < 10 ? "0" : "") + r;
    }

    function _pollStatus() {
        if (!sheet.payment) return;
        PaymentService.checkCryptoStatus(Config.baseUrl, Session.token, sheet.payment.paymentId,
            function (status) {
                sheet.payStatus = status;
                // Only "finished" is terminal: the backend activates the plan inside
                // check-status (no webhook), so keep polling until it flips.
                if (status === "finished") {
                    pollTimer.stop(); countdownTimer.stop();
                    Payments.clearPendingCrypto();
                    sheet.step = 2;
                    Toast.success(Lang.tr("Payment confirmed!"));
                    Payments.paymentSucceeded();
                } else if (status === "failed" || status === "refunded" || status === "expired") {
                    pollTimer.stop(); countdownTimer.stop();
                    Payments.clearPendingCrypto();
                    sheet.errorMsg = status === "expired"
                        ? Lang.tr("Payment expired. Please start again.")
                        : Lang.tr("Payment failed. Please try again.");
                    sheet.step = 3;
                }
            },
            function () { /* transient poll errors are ignored; next tick retries */ });
    }

    Timer { id: pollTimer;      interval: 10000; repeat: true; onTriggered: sheet._pollStatus() }
    Timer { id: countdownTimer; interval: 1000;  repeat: true; onTriggered: sheet._tickCountdown() }

    // While waiting for a payment a stray tap must not dismiss the sheet
    // (losing the address mid-payment), so step 1 ignores backdrop taps.
    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.4)
        opacity: 0
        MouseArea { anchors.fill: parent; onClicked: if (sheet.step !== 1) sheet.closeSheet() }
    }
    NumberAnimation { id: backdropFade;    target: backdrop; property: "opacity"; from: 0; to: 1; duration: 200 }
    NumberAnimation { id: backdropFadeOut; target: backdrop; property: "opacity"; to: 0; duration: 200 }

    Rectangle {
        id: sheetRect
        // Convergence: centered, gu-capped panel on wide windows.
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
        width: Math.min(parent.width, Config.sheetMaxWidth)
        height: (sheet.step === 0 ? pickCol.height
                 : sheet.step === 1 ? payCol.height
                 : sheet.step === 2 ? doneCol.height
                 : errCol.height) + units.gu(4)
        radius: units.dp(16)
        color: Style.surface

        transform: Translate { id: sheetTranslate; y: 0 }
        NumberAnimation { id: sheetSlide;    target: sheetTranslate; property: "y"; from: sheetRect.height + units.gu(4); to: 0; duration: 300; easing.type: Easing.OutCubic }
        NumberAnimation { id: sheetSlideOut; target: sheetTranslate; property: "y"; to: sheetRect.height + units.gu(4); duration: 250; easing.type: Easing.InCubic; onStopped: Payments.closeCrypto() }
        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }

        Rectangle {
            anchors { top: parent.top; topMargin: Style.spacingS; horizontalCenter: parent.horizontalCenter }
            width: units.gu(4.5); height: units.dp(4); radius: units.dp(2)
            color: Style.lightGray
        }

        // ===================== Step 0: choose currency =====================
        Column {
            id: pickCol
            anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: Style.spacingL }
            spacing: 0
            visible: sheet.step === 0

            Item { width: 1; height: Style.spacingS }
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Lang.tr("Pay with crypto")
                font.pixelSize: Style.fontLarge; font.weight: Font.DemiBold
                font.family: Style.fontFamily
                color: Style.textPrimary
            }
            Item { width: 1; height: Style.spacingXs }
            Label {
                width: parent.width - Style.spacingL * 2
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: Lang.tr("Choose the currency you want to pay with")
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFamily
                color: Style.textSecondary
            }
            Item { width: 1; height: Style.spacingM }

            Item {
                visible: sheet.busy
                width: pickCol.width; height: units.gu(8)
                ActivityIndicator { anchors.centerIn: parent; running: parent.visible }
            }

            Label {
                visible: !sheet.busy && sheet.errorMsg.length > 0
                width: pickCol.width - Style.spacingM * 2
                x: Style.spacingM
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: sheet.errorMsg
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFamily
                color: Style.danger
            }

            ListView {
                id: currencyList
                width: pickCol.width
                height: Math.min(contentHeight, units.gu(32))
                clip: true
                visible: !sheet.busy && sheet.currencies.length > 0
                model: sheet.visibleCurrencies

                delegate: AbstractButton {
                    width: currencyList.width; height: units.gu(6)
                    onClicked: sheet.selectCurrency(modelData)
                    Label {
                        anchors { left: parent.left; leftMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                        text: sheet.prettyCurrency(modelData)
                        font.pixelSize: Style.fontRegular
                        color: Style.textPrimary
                    }
                    Icon {
                        anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                        width: units.gu(2); height: width
                        name: "next"; color: Style.textSecondary
                    }
                    Rectangle {
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                        height: units.dp(1); color: Style.divider
                    }
                }
            }

            LinkButton {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !sheet.busy && !sheet.showAllCurrencies
                         && sheet.currencies.length > sheet.visibleCurrencies.length
                label: Lang.tr("More currencies")
                onClicked: sheet.showAllCurrencies = true
            }

            Item { width: 1; height: Style.spacingM }
        }

        // ===================== Step 1: pay =====================
        Column {
            id: payCol
            anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: Style.spacingL }
            spacing: 0
            visible: sheet.step === 1

            // Pending-payment notice: the backend returned an earlier, still
            // valid payment in a different currency than the one just picked.
            Label {
                visible: sheet.currencyMismatch
                width: parent.width - Style.spacingL * 2
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: sheet.payment
                      ? Lang.tr("You already have a pending payment in %1. Complete it below, or let it expire to pay with another currency.").arg(sheet.prettyCurrency(sheet.payment.payCurrency.toLowerCase()))
                      : ""
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFamily
                color: Style.brand
            }
            Item { width: 1; height: sheet.currencyMismatch ? Style.spacingM : Style.spacingS }
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Lang.tr("Send exactly")
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFamily
                color: Style.textSecondary
            }
            Item { width: 1; height: Style.spacingXs }
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: sheet.payment ? (sheet.payment.payAmount + " " + sheet.prettyCurrency(sheet.payment.payCurrency.toLowerCase())) : ""
                font.pixelSize: Style.fontTitle
                font.weight: Font.DemiBold
                color: Style.textPrimary
            }
            Item { width: 1; height: Style.spacingM }

            // QR of the deposit address, on a white card so it scans in dark mode.
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: units.gu(22); height: width
                radius: units.dp(10)
                color: "#FFFFFF"
                QrCode {
                    anchors { fill: parent; margins: units.gu(1) }
                    text: sheet.payment ? sheet.payment.payAddress : ""
                }
            }
            Item { width: 1; height: Style.spacingM }

            AbstractButton {
                width: parent.width - Style.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                height: addrLabel.height + Style.spacingM * 2
                onClicked: {
                    if (!sheet.payment) return;
                    Clipboard.push(sheet.payment.payAddress);
                    Toast.show(Lang.tr("Address copied"));
                }
                Rectangle {
                    anchors.fill: parent
                    radius: units.dp(10)
                    color: Style.iconBackground
                }
                Label {
                    id: addrLabel
                    anchors { left: parent.left; right: copyIcon.left; leftMargin: Style.spacingM; rightMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
                    text: sheet.payment ? sheet.payment.payAddress : ""
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
            Item { width: 1; height: Style.spacingM }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.spacingS
                ActivityIndicator {
                    anchors.verticalCenter: parent.verticalCenter
                    running: sheet.step === 1
                    width: units.gu(2); height: width
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (sheet.payStatus === "waiting"
                           ? Lang.tr("Waiting for payment…")
                           : Lang.tr("Confirming payment…"))
                          + "  " + sheet._fmtCountdown(sheet.secondsLeft)
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFamily
                    color: Style.textSecondary
                }
            }
            Item { width: 1; height: Style.spacingM }

            AbstractButton {
                width: parent.width - Style.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                height: units.gu(6)
                onClicked: sheet.closeSheet()
                Rectangle {
                    anchors.fill: parent; radius: Style.cardRadius
                    color: "transparent"
                    border.width: units.dp(1.5); border.color: Style.divider
                }
                Label {
                    anchors.centerIn: parent
                    text: Lang.tr("Cancel")
                    font.pixelSize: Style.fontMedium; font.weight: Font.DemiBold
                    font.family: Style.fontFamily
                    color: Style.textPrimary
                }
            }
            Item { width: 1; height: Style.spacingM }
        }

        // ===================== Step 2: success =====================
        Column {
            id: doneCol
            anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: Style.spacingL }
            spacing: 0
            visible: sheet.step === 2

            Item { width: 1; height: Style.spacingM }
            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                width: units.gu(6); height: width
                name: "tick"; color: Style.success
            }
            Item { width: 1; height: Style.spacingM }
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Lang.tr("Payment confirmed!")
                font.pixelSize: Style.fontLarge; font.weight: Font.DemiBold
                font.family: Style.fontFamily
                color: Style.textPrimary
            }
            Item { width: 1; height: Style.spacingXs }
            Label {
                width: parent.width - Style.spacingL * 2
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: Lang.tr("Your plan is now active.")
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFamily
                color: Style.textSecondary
            }
            Item { width: 1; height: Style.spacingL }
            AbstractButton {
                width: parent.width - Style.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                height: units.gu(6)
                onClicked: {
                    // Plan is active; funnel straight into creating the
                    // platform, unless the user already owns one.
                    var owns = false;
                    for (var k in Config.ownedCommunityIdSet) { owns = true; break; }
                    sheet.closeSheet();
                    if (!owns) Nav.createPlatform();
                }
                Rectangle { anchors.fill: parent; radius: Style.cardRadius; color: Style.brand }
                Label {
                    anchors.centerIn: parent
                    text: Lang.tr("Done")
                    font.pixelSize: Style.fontMedium; font.weight: Font.DemiBold
                    font.family: Style.fontFamily
                    color: Style.textOnBrand
                }
            }
            Item { width: 1; height: Style.spacingM }
        }

        // ===================== Step 3: fatal error =====================
        Column {
            id: errCol
            anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: Style.spacingL }
            spacing: 0
            visible: sheet.step === 3

            Item { width: 1; height: Style.spacingM }
            Label {
                width: parent.width - Style.spacingL * 2
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: sheet.errorMsg
                font.pixelSize: Style.fontMedium
                font.family: Style.fontFamily
                color: Style.danger
            }
            Item { width: 1; height: Style.spacingL }
            AbstractButton {
                width: parent.width - Style.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                height: units.gu(6)
                onClicked: { sheet.errorMsg = ""; sheet.payment = null; sheet.step = 0 }
                Rectangle { anchors.fill: parent; radius: Style.cardRadius; color: Style.brand }
                Label {
                    anchors.centerIn: parent
                    text: Lang.tr("Try again")
                    font.pixelSize: Style.fontMedium; font.weight: Font.DemiBold
                    font.family: Style.fontFamily
                    color: Style.textOnBrand
                }
            }
            Item { width: 1; height: Style.spacingS }
            AbstractButton {
                width: parent.width - Style.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                height: units.gu(6)
                onClicked: sheet.closeSheet()
                Rectangle {
                    anchors.fill: parent; radius: Style.cardRadius
                    color: "transparent"
                    border.width: units.dp(1.5); border.color: Style.divider
                }
                Label {
                    anchors.centerIn: parent
                    text: Lang.tr("Cancel")
                    font.pixelSize: Style.fontMedium; font.weight: Font.DemiBold
                    font.family: Style.fontFamily
                    color: Style.textPrimary
                }
            }
            Item { width: 1; height: Style.spacingM }
        }
    }
}
