import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.ListItems 1.3 as ListItems
import Lomiri.Components.Popups 1.3
import "../Theme"

// context actions reachable by right-click / MENU key, not just touch
Item {
    id: area
    anchors.fill: parent

    signal triggered()
    // fires row's primary open action on Enter/Return
    signal activated()
    // optional ActionList shown as context menu
    property var menuActions: null

    // keyboard-opened menu highlights first item; right-click doesn't
    function _invoke(byKeyboard) {
        if (!area.menuActions) { area.triggered(); return; }
        var p = PopupUtils.open(menuComp, area);
        if (p && byKeyboard) p.navFirst();
    }
    // lets a ••• button open the same menu
    function open() { area._invoke(false); }

    // right-click anywhere on the row
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: area._invoke(false)
    }

    // Tab to focus, MENU/Shift+F10 to open
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

    // context menu; adds arrow-key nav ActionSelectionPopover lacks
    Component {
        id: menuComp
        ActionSelectionPopover {
            id: popover
            actions: area.menuActions

            // highlighted action, matched by object (not Repeater index)
            property var navAction: null
            function navFirst() { var l = popover._navList(); popover.navAction = l.length ? l[0] : null; }
            function _navList() {
                var a = popover.actions;
                if (!a) return [];
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

            // zero-size grabber for keyboard focus (popups don't take it themselves)
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

            // default delegate plus keyboard highlight
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
