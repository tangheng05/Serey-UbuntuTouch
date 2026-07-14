import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

/*
 * Convergent per-tab navigation container (HIG: adapt, not scale).
 *
 * Narrow windows keep the phone model: the root page fills the tab and pushed
 * pages cover it full-screen. Wide windows (>= Config.convergenceBreakpoint)
 * show the root page as a fixed-width leading panel and route pushed pages into
 * a detail panel on the right, master-detail style. Crossing the breakpoint is
 * a pure geometry change — nothing is reparented, so live WebViews/players
 * survive a resize.
 *
 * Internals are two REAL PageStacks (master + detail), NOT a shim over
 * AdaptivePageLayout. The shim desynced on push -> pop -> re-push (opening
 * Login, backing out, reopening threw "sourcePage must be added to the view"
 * and wedged navigation). Native PageStack push/pop can't desync.
 *
 * detailStack is seeded with an invisible placeholder page so the FIRST real
 * detail sits at detailStack.depth 2. Lomiri only auto-injects a PageHeader
 * back button when a page isn't the root of its PageStack, so without the
 * placeholder the first-pushed detail (e.g. Login) had no back button.
 *
 * Public API (push/pop/depth/columns/currentPage + singleColumnUntilPushed/
 * emptyDetail*) is unchanged, so Main.qml and every `pageStack.push()` call
 * site keep working untouched.
 */
Item {
    id: root

    // --- Public API --------------------------------------------------------
    property bool singleColumnUntilPushed: false
    // Never enter master-detail: the root fills the tab and every push covers it
    // full-screen (the Homepage web app is the panel — a 320gu master would
    // cram the full website and strand pushed pages beside it).
    property bool neverSplit: false
    property string emptyDetailIconName: ""
    property string emptyDetailMessage: ""

    // Resizable leading (master/list) panel: draggable when min != max.
    property real listWidth: units.gu(40)
    readonly property real _minListW: units.gu(30)
    readonly property real _maxListW: Math.max(_minListW, Math.min(width * 0.6, width - units.gu(45)))
    readonly property real _listW: Math.max(_minListW, Math.min(_maxListW, listWidth))

    // Real detail pages, excluding the invisible placeholder at detailStack[0].
    readonly property int _detailCount: Math.max(0, detailStack.depth - 1)

    readonly property bool split: !neverSplit && width >= Config.convergenceBreakpoint
                                  && (!singleColumnUntilPushed || _detailCount > 0)
    readonly property int columns: split ? 2 : 1

    // PageStack-compatible surface: the root page counts as depth 1.
    readonly property int depth: (rootStack.depth > 0 ? 1 : 0) + _detailCount
    readonly property var currentPage: _detailCount > 0 ? detailStack.currentPage
                                                        : rootStack.currentPage

    // Invisible seed page: keeps every real detail at detailStack.depth >= 2 so
    // Lomiri shows the native back button on the first-pushed detail too.
    Component {
        id: detailPlaceholder
        Page { visible: false; header: Item { height: 0 } }
    }

    // First push is the tab root (master column); every later push is a detail.
    // Only the root page's `pageStack` is re-pointed here, so ITS pushes land in
    // the detail column; detail pages keep pageStack == detailStack so Lomiri's
    // native back button and their own pop() operate on the real stack.
    function push(pageUrl, properties) {
        var props = properties || {};
        if (rootStack.depth === 0) {
            var pg = rootStack.push(pageUrl, props);
            if (pg) pg.pageStack = root;
            return pg;
        }
        if (detailStack.depth === 0)
            detailStack.push(detailPlaceholder);   // seed once, lazily
        return detailStack.push(pageUrl, props);
    }

    function pop() {
        if (_detailCount > 0) detailStack.pop();
        else if (rootStack.depth > 1) rootStack.pop();
    }

    // --- Leading (master) panel --------------------------------------------
    Item {
        id: listPane
        anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
        width: root.split ? root._listW : root.width
        visible: root.split || root._detailCount === 0
        clip: true
        PageStack { id: rootStack; anchors.fill: parent }
    }

    // Draggable hairline between panels (split only).
    Rectangle {
        id: paneDivider
        anchors { top: parent.top; bottom: parent.bottom; left: listPane.right }
        width: units.dp(1)
        color: dragHandle.containsMouse || dragHandle.pressed ? Style.brand : Style.divider
        visible: root.split
    }
    MouseArea {
        id: dragHandle
        visible: root.split
        anchors { top: parent.top; bottom: parent.bottom }
        x: listPane.width - width / 2
        width: units.gu(1.5)
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.SplitHCursor
        onPositionChanged: {
            if (!pressed) return;
            root.listWidth = Math.max(root._minListW,
                             Math.min(root._maxListW, mapToItem(root, mouse.x, 0).x));
        }
    }

    // --- Detail panel ------------------------------------------------------
    Item {
        id: detailPane
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
        width: root.split ? root.width - listPane.width - paneDivider.width : root.width
        visible: root.split || root._detailCount > 0

        Rectangle {
            anchors.fill: parent
            color: Style.surface
            visible: root.split || root._detailCount === 0

            Column {
                anchors.centerIn: parent
                spacing: units.gu(1)
                visible: root.split && root._detailCount === 0 && root.emptyDetailMessage !== ""
                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: units.gu(6); height: width
                    name: root.emptyDetailIconName
                    color: Style.textSecondary
                    opacity: 0.5
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.emptyDetailMessage
                    color: Style.textSecondary
                }
            }
        }

        PageStack { id: detailStack; anchors.fill: parent }
    }
}
