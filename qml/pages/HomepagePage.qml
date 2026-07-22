import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"

Page {
    id: page

    // skip redirect, go straight to resolved route
    function siteUrl() {
        return Config.homeLandingPageUrl + "/" + Config.communityId
             + "?community_id=" + Config.communityId;
    }

    // Zero-height header: the global AppHeader is the real top bar.
    header: Item { height: 0 }

    // focus web view on tab arrival
    property Item keyboardFocusItem: webApp
    onVisibleChanged: if (visible) webApp.forceActiveFocus()
    // deferred: load is deferred too, so focus needs callLater
    Component.onCompleted: if (visible) Qt.callLater(webApp.forceActiveFocus)

    // adopt community change from web side
    function applyCommunity(communityId) {
        if (String(communityId) === String(Config.communityId)) return;
        Config.selectCommunityById(communityId);
    }

    WebAppView {
        id: webApp
        anchors.fill: parent
        // freeze renderer when tab hidden
        suspended: Config.currentTab !== 0
        url: page.siteUrl()
        authToken: Session.token
        username: Session.username
        apiBaseV2: Config.baseUrl
        communityId: String(Config.communityId)
        communityName: Config.communityName
        onOpenCommunityRequested: page.applyCommunity(communityId)
        // sync community from site nav
        onSiteNavigated: page.applyCommunity(Config.communityIdForUrl(url))

        // route buy-plan to native payment flow
        onBuyPlanRequested: {
            if (params.method === "crypto") Payments.openCrypto(params.subscription_plan_id);
            else Payments.openStripe(params.subscription_plan_id);
        }
        onStripeCheckoutIntercepted: Payments.openStripeUrl(url)
    }

    // After a confirmed payment, reload the site so it reflects the new plan.
    Connections {
        target: Payments
        function onPaymentSucceeded() { webApp.reload(); }
    }

    // Persistent cookies otherwise survive a native logout/account switch
    Connections {
        target: Session
        function onTokenChanged() {
            webApp.clearSession();
            webApp.reload();
        }
    }
}
