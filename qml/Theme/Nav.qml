pragma Singleton
import QtQuick 2.7

QtObject {
    id: nav

    // Tab index to switch to (0 = Homepage); Main listens and also clears the stack the auth flow was pushed onto.
    signal goToTab(int tab)

    // Buy-plan → create-platform funnel: emitted by the payment sheets after a
    // successful purchase; Main switches to Settings and pushes the wizard.
    signal createPlatform()

    function home() { goToTab(0); }
}
