import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

/*
 * Per-tab master-detail container: phones push full-screen, wide windows split list + detail.
 * Breakpoint crossings are pure geometry (no reparenting), so live WebViews survive resizes.
 * Two REAL PageStacks, not an AdaptivePageLayout shim (the shim desynced on push/pop/re-push).
 */
Item {
    id: root

    property bool singleColumnUntilPushed: false
    // Never enter master-detail: the root fills the tab and every push covers it
    // full-screen. Used by Homepage, where the web app itself is the panel.
    property bool neverSplit: false
    property string emptyDetailIconName: ""
    property string emptyDetailMessage: ""

    // Resizable leading (master/list) panel: draggable when min != max.
    property real listWidth: units.gu(46)
    readonly property real _minListW: units.gu(30)
    readonly property real _maxListW: Math.max(_minListW, Math.min(width * 0.6, width - units.gu(45)))
    readonly property real _listW: Math.max(_minListW, Math.min(_maxListW, listWidth))

    // Real detail pages, excluding the invisible placeholder at detailStack[0].
    readonly property int _detailCount: Math.max(0, detailStack.depth - 1)

    // Split on Config.wideMode (window width), not our own width: reading `width` here
    // created a binding loop (width -> nav-rail presence -> columns -> split -> width),
    // and wideMode aligns the split point with the nav rail's breakpoint.
    readonly property bool split: !neverSplit && Config.wideMode
                                  && (!singleColumnUntilPushed || _detailCount > 0)
    readonly property int columns: split ? 2 : 1

    // PageStack-compatible surface: the root page counts as depth 1.
    readonly property int depth: (rootStack.depth > 0 ? 1 : 0) + _detailCount
    readonly property var currentPage: _detailCount > 0 ? detailStack.currentPage
                                                        : rootStack.currentPage
    // The tab's master/root page, regardless of what's in the detail column.
    readonly property var rootPage: rootStack.currentPage

    // Invisible seed page: keeps every real detail at detailStack.depth >= 2 so
    // Lomiri shows the native back button on the first-pushed detail too.
    Component {
        id: detailPlaceholder
        Page { visible: false; header: Item { height: 0 } }
    }

    // First push is the tab root; later pushes land in the detail column. Only the root
    // page's pageStack points here, so a master-list push REPLACES the current detail;
    // navigation within a detail page uses detailStack directly and still stacks.
    function push(pageUrl, properties) {
        var props = properties || {};
        if (rootStack.depth === 0) {
            var pg = rootStack.push(pageUrl, props);
            if (pg) pg.pageStack = root;
            return pg;
        }
        if (detailStack.depth === 0)
            detailStack.push(detailPlaceholder);        // seed the invisible back-anchor
        else
            while (detailStack.depth > 1) detailStack.pop();   // clear prior selection
        return detailStack.push(pageUrl, props);
    }

    function pop() {
        if (_detailCount > 0) detailStack.pop();
        else if (rootStack.depth > 1) rootStack.pop();
    }

    // Keyboard master-detail: move focus between the two panels (split only). Pages
    // opt in by exposing `property Item keyboardFocusItem` (the list/flick that should
    // own arrow-key focus); otherwise the page itself is focused.
    function focusMaster() {
        var p = rootStack.currentPage;
        if (!p) return;
        // List pages need the key-nav focus reason for Lomiri to paint the row
        // cursor; plain forceActiveFocus leaves keyNavigationFocus false.
        if (p.focusListKeyNav) { p.focusListKeyNav(); return; }
        (p.keyboardFocusItem ? p.keyboardFocusItem : p).forceActiveFocus();
    }
    function focusDetail() {
        var p = detailStack.currentPage;
        if (!p) return;
        (p.keyboardFocusItem ? p.keyboardFocusItem : p).forceActiveFocus();
    }
    // Only the visible, split stack reacts (one tab is visible at a time). If the
    // open detail runs its OWN nested master-detail (My Feed), it exposes
    // `_ownsKeyboardNav` and handles these itself; defer so focus stays inside it.
    Connections {
        target: Nav
        function onFocusMaster() {
            if (!(root.visible && root.split)) return;
            var d = detailStack.currentPage;
            if (d && d._ownsKeyboardNav) return;
            root.focusMaster();
        }
        function onFocusDetail() {
            if (!(root.visible && root.split && root._detailCount > 0)) return;
            var d = detailStack.currentPage;
            if (d && d._ownsKeyboardNav) return;
            root.focusDetail();
        }
    }

    Item {
        id: listPane
        anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
        width: root.split ? root._listW : root.width
        visible: root.split || root._detailCount === 0
        clip: true
        PageStack { id: rootStack; anchors.fill: parent }
    }

    // Draggable separator between panels (split only). Thicker than a 1dp hairline
    // so it reads as a grabbable splitter rather than a plain divider.
    Rectangle {
        id: paneDivider
        anchors { top: parent.top; bottom: parent.bottom; left: listPane.right }
        width: units.dp(2)
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
