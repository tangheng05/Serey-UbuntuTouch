import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/AnonymousInviteService.js" as InviteService

Page {
    id: page

    // Go straight to the resolved route; `/` only redirects here anyway, and
    // that hop cost a remount plus a wait on the bridge before anything painted.
    function siteUrl() {
        return Config.homeLandingPageUrl + "/" + Config.communityId
             + "?community_id=" + Config.communityId;
    }

    // Zero-height header: the global AppHeader is the real top bar.
    header: Item { height: 0 }

    // Keyboard parity on arrival (see NewsPage): hand key focus to the web view
    // whenever this tab is shown, so the site scrolls with arrows immediately.
    // Nav.focusMaster (Right from the nav rail) targets the same item.
    property Item keyboardFocusItem: webApp
    onVisibleChanged: if (visible) webApp.forceActiveFocus()
    // Deferred: the web view's load is itself deferred, so grabbing focus straight
    // from onCompleted lands on nothing (measured: activeFocus stayed false and the
    // window had no focus item at all), leaving the site unscrollable until a click.
    Component.onCompleted: if (visible) Qt.callLater(webApp.forceActiveFocus)

    // Adopt a community the web side moved to, at any depth. Config.communityId
    // then re-points siteUrl(), so a bridge-only request (a superhub card, which
    // doesn't navigate itself) takes the web view along too.
    function applyCommunity(communityId) {
        if (String(communityId) === String(Config.communityId)) return;
        Config.selectCommunityById(communityId);
    }

    WebAppView {
        id: webApp
        anchors.fill: parent
        // Freeze this Chromium renderer while another tab is showing so it doesn't compete for GPU/shared memory with the video player's WebView.
        suspended: Config.currentTab !== 0
        url: page.siteUrl()
        authToken: Session.token
        username: Session.username
        apiBaseV2: Config.baseUrl
        communityId: String(Config.communityId)
        communityName: Config.communityName
        onOpenCommunityRequested: page.applyCommunity(communityId)
        // Same for card taps the site handles itself. Ignoring the already-selected
        // community is what stops our own siteUrl() hops from looping.
        onSiteNavigated: page.applyCommunity(Config.communityIdForUrl(url))

        // Buy-plan: bridge calls and intercepted Stripe redirects both land in
        // the native payment flow (PaymentSheet / StripeCheckoutSheet).
        onBuyPlanRequested: {
            if (params.method === "crypto") Payments.openCrypto(params.subscription_plan_id);
            else Payments.openStripe(params.subscription_plan_id);
        }
        onStripeCheckoutIntercepted: Payments.openStripeUrl(url)
        // Invite link tapped in the mini app: redeem it natively.
        onInviteRedeemIntercepted: {
            var code = InviteService.codeFromUrl(url);
            if (code.length > 0) Nav.redeemInvite(code);
        }
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
