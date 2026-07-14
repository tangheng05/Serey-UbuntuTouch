import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

/*
 * Input-method parity (UBports HIG, Other design considerations >
 * Convergence & Accessibility): the context actions a touch user reaches by
 * swiping or long-pressing a card MUST also be reachable by POINTER
 * (right-click) and KEYBOARD (the MENU key / Shift+F10), so no action is
 * touch-only. Drop this over a card and connect `triggered()` to whatever
 * opens the card's context menu (the ••• overflow / PostActions sheet).
 *
 * It listens for RIGHT button only, so left-clicks, taps, and the enclosing
 * Lomiri ListItem swipe fall straight through to the card's own handlers.
 * A thin brand outline marks the card when it holds keyboard focus.
 */
Item {
    id: area
    anchors.fill: parent

    signal triggered()

    // Pointer: right-click anywhere on the card.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: area.triggered()
    }

    // Keyboard: focus the card (Tab), then the platform "open context menu"
    // keys — the dedicated MENU key or Shift+F10.
    activeFocusOnTab: true
    Keys.onPressed: {
        if (event.key === Qt.Key_Menu ||
            (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
            area.triggered();
            event.accepted = true;
        }
    }

    // Keyboard-focus affordance (pointer/touch users never see it).
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        visible: area.activeFocus
        border.width: units.dp(2)
        border.color: Style.brand
        radius: units.gu(0.5)
    }
}
