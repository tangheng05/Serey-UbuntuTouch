pragma Singleton
import QtQuick 2.7

QtObject {
    id: nav

    // Tab index to switch to (0 = Homepage); Main listens and also clears the stack the auth flow was pushed onto.
    signal goToTab(int tab)

    // Buy-plan → create-platform funnel: emitted by the payment sheets after a
    // successful purchase; Main switches to Settings and pushes the wizard.
    signal createPlatform()

    // Master-detail keyboard focus (split windows): a detail page (e.g. an article)
    // emits focusMaster() to hand arrow-key focus back to the list; a list emits
    // focusDetail() to move into the open detail. The active, split AdaptiveStack acts.
    signal focusMaster()
    signal focusDetail()

    // Focus the tab navigation itself (side rail / bottom bar) — emitted by a
    // list's Left key (step out of content) and by the F6 shortcut; Main acts.
    signal focusNav()

    // Focus the active tab's content (the feed). Emitted after the community picker
    // changes source: the reloaded feed is where the user wants to be, and unlike
    // focusMaster this works on every tab, split or not. Main acts.
    signal focusContent()

    // Re-fetch get-communities and rebuild Config.sources — emitted after
    // creating or deleting a platform so the community picker reflects it
    // without an app restart. Main acts (it owns the fetch + icon mapping).
    signal refreshCommunities()

    function home() { goToTab(0); }
}
