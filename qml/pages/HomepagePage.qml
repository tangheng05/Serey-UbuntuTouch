import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/AnonymousInviteService.js" as InviteService

Page {
    id: page

    // Go straight to the resolved route; `/` redirect cost a remount + bridge wait
    function siteUrl() {
        return Config.homeLandingPageUrl + "/" + Config.communityId
             + "?community_id=" + Config.communityId;
    }

    // Zero-height header: the global AppHeader is the real top bar.
    header: Item { height: 0 }

    // never split
    readonly property bool neverSplitOverride: true

    // Keyboard parity on arrival (see NewsPage): hand focus to web view when shown
    property Item keyboardFocusItem: webApp
    onVisibleChanged: if (visible) webApp.forceActiveFocus()
    // Web view load is itself deferred; grabbing focus from onCompleted lands on nothing
    Component.onCompleted: if (visible) Qt.callLater(webApp.forceActiveFocus)

    // Adopt a community the web side moved to; re-points siteUrl() for bridge-only requests
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
        // Ignoring the already-selected community stops our own siteUrl() hops from looping
        onSiteNavigated: page.applyCommunity(Config.communityIdForUrl(url))

        // Buy-plan: bridge calls and Stripe redirects both land in the native payment flow
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

    // The site failing to load is the offline signal; cover it with the native panel
    // rather than let Chromium's own error page through.
    Rectangle {
        id: offlineCover
        anchors.fill: parent
        // Matches the News/Video covers: fade in rather than cut.
        opacity: webApp.loadFailed ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }
        color: Style.surface

        OfflineState {
            anchors.fill: parent
            onRetry: webApp.reload()
        }
    }

    // Walk back into coverage and the site comes back on its own; the cover hides the reload.
    Timer {
        interval: 20000
        repeat: true
        running: offlineCover.visible && Config.currentTab === 0
        onTriggered: webApp.reload()
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
