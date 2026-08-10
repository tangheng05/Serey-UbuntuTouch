import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

// Per-tab master-detail: phones push full-screen, wide windows split list + detail (two real PageStacks, not AdaptivePageLayout)
Item {
    id: root

    property bool singleColumnUntilPushed: false
    // Never enter master-detail: root fills the tab, every push covers full-screen
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

    // Split on Config.wideMode, not own width: reading `width` here caused a binding loop
    readonly property bool split: !neverSplit && Config.wideMode
                                  && (!singleColumnUntilPushed || _detailCount > 0)
    readonly property int columns: split ? 2 : 1

    // PageStack-compatible surface: the root page counts as depth 1.
    readonly property int depth: rootStack.depth + _detailCount
    readonly property var currentPage: _detailCount > 0 ? detailStack.currentPage
                                                        : rootStack.currentPage
    // The tab's master/root page, regardless of what's in the detail column.
    readonly property var rootPage: rootStack.currentPage

    // Invisible seed page: keeps detail depth >= 2 so Lomiri shows the native back button
    Component {
        id: detailPlaceholder
        Page { visible: false; header: Item { height: 0 } }
    }

    // First push is the tab root; later pushes land in detail and REPLACE the current one
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

    // A destination, not a detail: takes over the LEADING column (Lomiri's
    // addPageToCurrentColumn) and keeps the detail column for its own pushes. Without
    // this, a page that is itself master-detail (My Feed) splits inside the detail
    // column and you get two unrelated list columns side by side.
    function pushMaster(pageUrl, properties) {
        if (rootStack.depth === 0)
            return push(pageUrl, properties);
        while (detailStack.depth > 0) detailStack.pop();   // its selection, not ours
        var pg = rootStack.push(pageUrl, properties || {});
        // Lomiri sets pageStack to rootStack; re-point it so the page's pushes land in detail.
        if (pg) pg.pageStack = root;
        return pg;
    }
    // Leaving a destination drops the detail it opened along with it.
    function popMaster() {
        while (detailStack.depth > 0) detailStack.pop();
        if (rootStack.depth > 1) rootStack.pop();
    }

    function pop() {
        if (_detailCount > 0) detailStack.pop();
        else if (rootStack.depth > 1) rootStack.pop();
    }

    // Keyboard master-detail: move focus between panels; pages opt in via `keyboardFocusItem`
    function focusMaster() {
        var p = rootStack.currentPage;
        if (!p) return;
        // List pages need key-nav focus reason; plain forceActiveFocus leaves keyNavigationFocus false
        if (p.focusListKeyNav) { p.focusListKeyNav(); return; }
        (p.keyboardFocusItem ? p.keyboardFocusItem : p).forceActiveFocus();
    }
    function focusDetail() {
        var p = detailStack.currentPage;
        if (!p) return;
        (p.keyboardFocusItem ? p.keyboardFocusItem : p).forceActiveFocus();
    }
    // Only the visible, split stack reacts.
    Connections {
        target: Nav
        function onFocusMaster() {
            if (root.visible && root.split) root.focusMaster();
        }
        function onFocusDetail() {
            if (root.visible && root.split && root._detailCount > 0) root.focusDetail();
        }
    }

    // A destination in the leading column names its own detail placeholder.
    readonly property string _emptyIcon: (rootStack.currentPage && rootStack.currentPage.emptyDetailIconName)
                                         ? rootStack.currentPage.emptyDetailIconName : emptyDetailIconName
    readonly property string _emptyMessage: (rootStack.currentPage && rootStack.currentPage.emptyDetailMessage)
                                            ? rootStack.currentPage.emptyDetailMessage : emptyDetailMessage

    Item {
        id: listPane
        anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
        width: root.split ? root._listW : root.width
        visible: root.split || root._detailCount === 0
        clip: true
        PageStack { id: rootStack; anchors.fill: parent }
    }

    // Draggable separator between panels. Hairline like every other divider; the
    // gu(1.5) MouseArea below plus the hover highlight carry the grabbable cue.
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
                visible: root.split && root._detailCount === 0 && root._emptyMessage !== ""
                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: units.gu(6); height: width
                    name: root._emptyIcon
                    color: Style.textSecondary
                    opacity: 0.5
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root._emptyMessage
                    color: Style.textSecondary
                }
            }
        }

        PageStack { id: detailStack; anchors.fill: parent }
    }
}
