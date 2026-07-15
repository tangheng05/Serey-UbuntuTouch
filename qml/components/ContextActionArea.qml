import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.ListItems 1.3 as ListItems
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

    // byKeyboard: the HIG reference shows a keyboard-opened menu with its first
    // item already highlighted, while a right-click menu highlights nothing.
    function _invoke(byKeyboard) {
        if (!area.menuActions) { area.triggered(); return; }
        var p = PopupUtils.open(menuComp, area);
        if (p && byKeyboard) p.navFirst();
    }
    // Public: lets a visible ••• button open the same menu right-click/MENU does.
    function open() { area._invoke(false); }

    // Pointer: right-click anywhere on the row.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: area._invoke(false)
    }

    // Keyboard: focus the row (Tab), then the platform "open context menu" keys.
    activeFocusOnTab: true
    Keys.onPressed: {
        if (event.key === Qt.Key_Menu ||
            (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
            area._invoke(true);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            area.activated();
            event.accepted = true;
        }
    }

    // Lomiri-native context menu, built from the row's own actions. The toolkit's
    // ActionSelectionPopover ships no key handling at all (Popover only closes on
    // Escape), so the arrow cursor and highlight are supplied here.
    Component {
        id: menuComp
        ActionSelectionPopover {
            id: popover
            actions: area.menuActions

            // The highlighted action, matched by object: the delegate is loaded in
            // THIS file's scope, so it can't see the popover Repeater's `index`.
            property var navAction: null
            function navFirst() { var l = popover._navList(); popover.navAction = l.length ? l[0] : null; }
            function _navList() {
                var a = popover.actions;
                if (!a) return [];
                // Same shape check the toolkit's own Repeater model uses.
                var arr = a.hasOwnProperty("actions") ? a.children : a;
                var out = [];
                for (var i = 0; i < arr.length; i++)
                    if (arr[i] && arr[i].visible !== false && arr[i].enabled !== false) out.push(arr[i]);
                return out;
            }
            function _navMove(d) {
                var l = popover._navList();
                if (l.length === 0) return;
                var cur = l.indexOf(popover.navAction);
                popover.navAction = (cur < 0) ? (d > 0 ? l[0] : l[l.length - 1])
                                              : l[(cur + d + l.length) % l.length];
            }

            // Zero-size grabber: Lomiri popups never take keyboard focus themselves,
            // so without this the arrows keep driving the list behind the menu.
            Item {
                id: keyGrab
                width: 0; height: 0
                focus: true
                Component.onCompleted: Qt.callLater(keyGrab.forceActiveFocus)
                Keys.onPressed: {
                    if (event.key === Qt.Key_Down)        { popover._navMove(1);  event.accepted = true; }
                    else if (event.key === Qt.Key_Up)     { popover._navMove(-1); event.accepted = true; }
                    else if (event.key === Qt.Key_Escape) { popover.hide(); event.accepted = true; }
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                             || event.key === Qt.Key_Space) {
                        if (popover.navAction) { popover.navAction.trigger(); popover.hide(); }
                        event.accepted = true;
                    }
                }
            }

            // Mirrors the toolkit's default delegate, plus the keyboard highlight.
            delegate: ListItems.Empty {
                id: menuRow
                onTriggered: popover.hide()
                visible: enabled && ((action === undefined) || action.visible)
                height: visible ? implicitHeight : 0

                Label {
                    anchors { verticalCenter: parent.verticalCenter; horizontalCenter: parent.horizontalCenter }
                    text: menuRow.text
                    wrapMode: Text.Wrap
                    color: theme.palette.normal.overlayText
                }
                Rectangle {
                    anchors { fill: parent; margins: units.dp(2) }
                    radius: units.dp(4)
                    color: "transparent"
                    border.width: units.dp(2)
                    border.color: Style.brand
                    visible: popover.navAction !== null && popover.navAction === menuRow.action
                }
            }
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
