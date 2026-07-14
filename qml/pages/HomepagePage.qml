import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"

Page {
    id: page

    function siteUrl() { return Config.homeLandingPageUrl + "?community_id=" + Config.communityId; }

    // Zero-height header: the global AppHeader is the real top bar.
    header: Item { height: 0 }

    // Map a community id requested by the web side to one of our sources.
    function applyCommunity(communityId) {
        for (var i = 0; i < Config.sources.length; i++) {
            if (String(Config.sources[i].id) === String(communityId)) {
                Config.sourceIndex = i;
                return;
            }
        }
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
