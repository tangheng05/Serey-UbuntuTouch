pragma Singleton
import QtQuick 2.7

QtObject {
    id: nav

    // Tab index to switch to (0 = Homepage); Main listens and also clears the stack the auth flow was pushed onto.
    signal goToTab(int tab)

    // Buy-plan -> create-platform funnel; Main switches to Settings and pushes the wizard
    signal createPlatform()

    // Master-detail keyboard focus: detail emits focusMaster() back to list, list emits focusDetail()
    signal focusMaster()
    signal focusDetail()

    // Focus the tab nav itself, emitted by a list's Left key and the F6 shortcut
    signal focusNav()

    // Focus a persistent right rail outside a tab's AdaptiveStack (Settings)
    signal focusRightPanel()

    // Focus active tab's content; emitted after community picker changes source
    signal focusContent()

    // Tapped a category badge: jump to blog tab filtered in that community
    signal filterCategory(string category, var community)
    property string pendingCategory: ""

    // Re-fetch communities and rebuild Config.sources after create/delete platform
    signal refreshCommunities()

    // After login/signup at a primary entry point, land on My Feed; session-only
    signal goToFeed()

    // Deep link: invite URL opened inside app; Main pushes RedeemInvitePage prefilled
    signal redeemInvite(string code)

    // Any offline panel can offer the on-device library without knowing its own stack
    signal openLibrary()

    // Edit a video's caption: emitted from feed cards, the reel menu and the action sheet, none of
    // which know their own stack. Main pushes the editor onto whichever tab is active.
    signal editCaption(var post)

    // Nav tab show/hide was just changed; Main reloads its cache
    signal navMenuChanged()

    function home() { goToTab(0); }
}
