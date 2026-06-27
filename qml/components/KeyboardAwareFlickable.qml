import QtQuick 2.7
import QtQuick.Window 2.2
import Lomiri.Components 1.3

/*
 * A Flickable that stays clear of the on-screen keyboard. Lomiri does NOT shrink
 * the window when the OSK appears, and a plain Flickable neither reserves room
 * for it nor scrolls the focused field above it (our raw TextInput/TextEdit don't
 * integrate with the toolkit's auto-scroll). This drop-in replacement:
 *   - reserves extra bottom scroll room equal to the keyboard height, and
 *   - scrolls the focused input fully into the area above the keyboard.
 *
 * On Ubuntu Touch the QML scene and Qt.inputMethod.keyboardRectangle share the
 * same (physical) pixel space, so the height is used directly.
 */
Flickable {
    id: flick

    // True only when the focused input lives INSIDE this flickable. A docked
    // composer (e.g. the comment bar on the detail pages) is focused but lives
    // outside the scroll — it's handled by lifting the bar itself, so this
    // flickable must ignore it (otherwise it reserves room / scrolls for nothing).
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
        // Never fight an active manual scroll — that's what caused the flicker.
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

    // Re-scroll only when the keyboard animates in/out and when focus moves to a
    // different field. We deliberately do NOT react to cursorRectangleChanged: it
    // also fires while the user manually scrolls (the focused field moves on
    // screen), which yanked the content back and caused flicker. Window's
    // activeFocusItem changes only on a real focus change, not on scroll/typing.
    onActiveFocusTargetChanged: Qt.callLater(flick._ensureFocusedVisible)

    Connections {
        target: Qt.inputMethod
        function onKeyboardRectangleChanged() { Qt.callLater(flick._ensureFocusedVisible); }
        function onVisibleChanged() { Qt.callLater(flick._ensureFocusedVisible); }
    }
}
