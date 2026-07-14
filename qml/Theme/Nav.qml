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

    function home() { goToTab(0); }
}
