pragma Singleton
import QtQuick 2.7

QtObject {
    id: nav

    // Tab index to switch to (0 = Homepage); Main listens and also clears the stack the auth flow was pushed onto.
    signal goToTab(int tab)

    function home() { goToTab(0); }
}
