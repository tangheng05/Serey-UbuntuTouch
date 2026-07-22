pragma Singleton
import QtQuick 2.7

QtObject {
    id: nav

    // tab to switch to (0 = Homepage)
    signal goToTab(int tab)

    // buy-plan -> create-platform funnel
    signal createPlatform()

    // master-detail keyboard focus (split windows)
    signal focusMaster()
    signal focusDetail()

    // focus tab nav itself (rail / bottom bar)
    signal focusNav()

    // focus active tab's content, after community picker change
    signal focusContent()

    // tapped a post's category badge
    signal filterCategory(string category, var community)
    property string pendingCategory: ""

    // rebuild Config.sources after platform create/delete
    signal refreshCommunities()

    // login/signup at a primary entry point, land on My Feed
    signal goToFeed()

    function home() { goToTab(0); }
}
