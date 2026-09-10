import QtQuick 2.7
import Lomiri.Components 1.3
import QtWebEngine 1.10
import "../Theme"
import "../Session"
import "../services/PaymentService.js" as PaymentService

// In-app Stripe Checkout; two live Chromiums SIGSEGV the phone, so the Loader tears down on close
Item {
    id: sheet
    anchors.fill: parent
    visible: Payments.stripeOpen
    z: 1600

    property bool creating: false
    // Set once /subscription/return is seen so late redirects can't double-fire.
    property bool finished: false

    onVisibleChanged: {
        if (visible) {
            finished = false;
            if (Payments.stripeUrl.length > 0) {
                webLoader.checkoutUrl = Payments.stripeUrl;
            } else {
                webLoader.checkoutUrl = "";
                _createSession();
            }
        } else {
            webLoader.checkoutUrl = "";
            creating = false;
        }
    }

    function _createSession() {
        if (!Session.isLoggedIn) {
            Toast.error(Lang.tr("Log in to buy a plan."));
            Payments.closeStripe();
            return;
        }
        sheet.creating = true;
        PaymentService.createStripeCheckout(Config.baseUrl, Session.token, Payments.planId,
            function (url) {
                sheet.creating = false;
                if (Payments.stripeOpen) webLoader.checkoutUrl = url;
            },
            function (err) {
                sheet.creating = false;
                Toast.error((err && err.message) ? err.message : Lang.tr("Couldn't start checkout."));
                Payments.closeStripe();
            });
    }

    function _handleReturn(urlStr) {
        if (sheet.finished) return;
        sheet.finished = true;
        var success = urlStr.indexOf("success=true") !== -1;
        if (success) {
            // Webhook activates the plan; fire check-status too (not awaited) in case it lags
            var m = urlStr.match(/[?&]session_id=([^&#]+)/);
            if (m) {
                PaymentService.checkStripeStatus(Config.baseUrl, Session.token,
                    decodeURIComponent(m[1]), function () {}, function () {});
            }
        }
        Payments.closeStripe();
        if (success) {
            Toast.success(Lang.tr("Payment successful!"));
            Payments.paymentSucceeded();
            // Same funnel as the crypto sheet's Done: straight into creating a platform
            var owns = false;
            for (var k in Config.ownedCommunityIdSet) { owns = true; break; }
            if (!owns) Nav.createPlatform();
        } else {
            Toast.show(Lang.tr("Payment cancelled."));
        }
    }

    Rectangle { anchors.fill: parent; color: Style.surface }

    Item {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: units.gu(6)

        Label {
            anchors.centerIn: parent
            text: Lang.tr("Checkout")
            font.pixelSize: Style.fontMedium
            font.weight: Font.DemiBold
            font.family: Style.fontFamily
            color: Style.textPrimary
        }
        AbstractButton {
            anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
            width: units.gu(4); height: units.gu(4)
            onClicked: {
                // Leaving checkout mid-flow counts as a cancel; Stripe expires the session itself
                Payments.closeStripe();
                Toast.show(Lang.tr("Payment cancelled."));
            }
            Icon { anchors.centerIn: parent; width: units.gu(2.2); height: width; name: "close"; color: Style.textPrimary }
        }
    }
    Rectangle {
        anchors { top: header.bottom; left: parent.left; right: parent.right }
        height: units.dp(1); color: Style.divider
    }

    Loader {
        id: webLoader
        anchors { top: header.bottom; topMargin: units.dp(1); left: parent.left; right: parent.right; bottom: parent.bottom }
        // WebEngineView only exists while there is a URL; clearing tears the renderer down
        property string checkoutUrl: ""
        active: Payments.stripeOpen && checkoutUrl.length > 0
        sourceComponent: Component {
            WebEngineView {
                profile: WebEngineProfile {
                    storageName: "SereyCheckout"
                    offTheRecord: false
                    httpUserAgent: "Mozilla/5.0 (Linux; Android 13; Pixel 3a) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
                }
                zoomFactor: Math.max(1, units.gu(1) / 8)
                Component.onCompleted: url = webLoader.checkoutUrl
                onUrlChanged: {
                    var s = url.toString();
                    if (s.indexOf("/subscription/return") !== -1)
                        sheet._handleReturn(s);
                }
            }
        }
    }

    // Spinner while the checkout session is being created / first page loads.
    ActivityIndicator {
        anchors.centerIn: parent
        running: sheet.visible && (sheet.creating
                 || (webLoader.item !== null && webLoader.item.loading))
        visible: running
    }
}
