import QtQuick 2.7
import QtQuick.Window 2.2
import Lomiri.Components 1.3

Flickable {
    id: flick

    // True only when the focused input lives inside this flickable; a docked composer is focused but outside the scroll, handled by lifting the bar itself.
    property var activeFocusTarget: Window.activeFocusItem
    readonly property bool focusInside: !!activeFocusTarget && _contains(activeFocusTarget)

    readonly property real keyboardHeight: (Qt.inputMethod.visible && focusInside)
        ? Qt.inputMethod.keyboardRectangle.height : 0

    // Extra scrollable room so even the bottom field can rise above the keyboard.
    bottomMargin: keyboardHeight

    function _contains(it) {
        var p = it;
        while (p) { if (p === flick.contentItem) return true; p = p.parent; }
        return false;
    }

    function _ensureFocusedVisible() {
        if (!Qt.inputMethod.visible || !flick.contentItem || !flick.focusInside)
            return;
        // Never fight an active manual scroll; that's what caused the flicker.
        if (flick.dragging || flick.flicking)
            return;
        var item = Window.activeFocusItem;
        // Only act on text inputs (they expose cursorPosition); ignore anything else.
        if (!item || item.cursorPosition === undefined)
            return;

        var p = item.mapToItem(flick.contentItem, 0, 0);
        var itemTop = p.y;
        var itemBottom = p.y + item.height;
        var margin = units.gu(2);
        var visibleHeight = flick.height - flick.keyboardHeight;   // not covered by OSK
        var viewTop = flick.contentY;
        var viewBottom = flick.contentY + visibleHeight;
        var maxY = Math.max(0, flick.contentHeight - flick.height + flick.bottomMargin);

        if (itemBottom + margin > viewBottom)
            flick.contentY = Math.min(maxY, itemBottom + margin - visibleHeight);
        else if (itemTop - margin < viewTop)
            flick.contentY = Math.max(0, itemTop - margin);
    }

    // Re-scroll only on keyboard animation or focus change, not cursorRectangleChanged, since that also fires during manual scroll and caused flicker.
    onActiveFocusTargetChanged: Qt.callLater(flick._ensureFocusedVisible)

    Connections {
        target: Qt.inputMethod
        function onKeyboardRectangleChanged() { Qt.callLater(flick._ensureFocusedVisible); }
        function onVisibleChanged() { Qt.callLater(flick._ensureFocusedVisible); }
    }
}
