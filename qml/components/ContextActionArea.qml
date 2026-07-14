import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../Theme"

/*
 * Input-method parity (UBports HIG, Other design considerations >
 * Convergence & Accessibility): the context actions a touch user reaches by
 * swiping or long-pressing a list item MUST also be reachable by POINTER
 * (right-click) and KEYBOARD (the MENU key / Shift+F10), so no action is
 * touch-only.
 *
 * Two ways to wire it, depending on the card/row:
 *   - `triggered()`   — for rows that already have a single "context menu"
 *                       affordance (the ••• overflow / PostActions sheet).
 *                       Right-click / MENU just fires it.
 *   - `menuActions`   — for rows whose only context actions are swipe actions
 *                       (Remove / Share …). Set this to an ActionList and
 *                       right-click / MENU opens a Lomiri ActionSelectionPopover
 *                       listing exactly those actions (never a bare destructive
 *                       trigger — a right-click must present a menu, not delete).
 *
 * It listens for the RIGHT button only, so left-clicks, taps, and the enclosing
 * Lomiri ListItem swipe fall straight through to the row's own handlers. A thin
 * brand outline marks the row when it holds keyboard focus.
 */
Item {
    id: area
    anchors.fill: parent

    signal triggered()
    // Emitted when the focused row is activated by keyboard (Enter/Return) — wire
    // it to the row's primary "open" action so keyboard users can enter an item,
    // matching a tap/left-click.
    signal activated()
    // Optional ActionList presented as a context menu (see above).
    property var menuActions: null

    function _invoke() {
        if (area.menuActions) PopupUtils.open(menuComp, area);
        else area.triggered();
    }

    // Pointer: right-click anywhere on the row.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: area._invoke()
    }

    // Keyboard: focus the row (Tab), then the platform "open context menu" keys.
    activeFocusOnTab: true
    Keys.onPressed: {
        if (event.key === Qt.Key_Menu ||
            (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
            area._invoke();
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            area.activated();
            event.accepted = true;
        }
    }

    // Lomiri-native context menu, built from the row's own actions.
    Component {
        id: menuComp
        ActionSelectionPopover { actions: area.menuActions }
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
