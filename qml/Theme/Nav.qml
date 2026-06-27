pragma Singleton
import QtQuick 2.7

/*
 * Cross-page navigation intents. Pages live inside per-tab PageStacks and can't
 * reach the shell's `currentTab` directly, so they emit a request here and
 * Main.qml acts on it (switches tab + resets the auth stack). Used by the signup
 * success screen's "Continue" to land the new user on the Homepage.
 */
QtObject {
    id: nav

    // tab index to switch to (0 = Homepage). Main listens and also clears the
    // stack the auth flow was pushed onto.
    signal goToTab(int tab)

    function home() { goToTab(0); }
}
