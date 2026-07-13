import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

AdaptivePageLayout {
    id: root

    // Async (the default) can leave push() seeing an unloaded page — force sync.
    asynchronous: false

    primaryPage: Page {
        visible: false
        header: Item { height: 0 }
    }

    // Stay single-column until something's actually pushed (opt-in per stack —
    // avoids a permanent blank detail column on tabs with no master-detail use).
    property bool singleColumnUntilPushed: false

    layouts: PageColumnsLayout {
        when: root.width >= units.gu(80) && (!root.singleColumnUntilPushed || root.depth > 1)
        PageColumn { minimumWidth: units.gu(30); maximumWidth: units.gu(60); preferredWidth: units.gu(40) }
        PageColumn { fillWidth: true }
    }

    // Optional empty-state placeholder for the detail column (set per-stack)
    property string emptyDetailIconName: ""
    property string emptyDetailMessage: ""

    // Approximates the column-0 boundary (no real API for it)
    Item {
        anchors { left: parent.left; leftMargin: units.gu(40); right: parent.right; top: parent.top; bottom: parent.bottom }
        visible: root.emptyDetailMessage !== "" && root.width >= units.gu(80) && root.depth <= 1

        Column {
            anchors.centerIn: parent
            spacing: units.gu(1)
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

    // Pushed page history (PageStack's push/pop/depth equivalent)
    property var _pages: []
    readonly property int depth: _pages.length
    property int _seq: 0

    // addPageToNextColumn/addPageToCurrentColumn's return value can't be
    // trusted — find the created page by a tag instead.
    function _findByObjectName(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        var kids = item.children || [];
        for (var i = 0; i < kids.length; i++) {
            var found = _findByObjectName(kids[i], name);
            if (found) return found;
        }
        return null;
    }

    function push(pageUrl, properties) {
        var isFirstPage = _pages.length === 0;
        var sourcePage = isFirstPage ? root.primaryPage : _pages[_pages.length - 1];
        if (!sourcePage) return null;
        var tag = "_adaptiveStackPage_" + (_seq++);
        var props = {};
        var given = properties || {};
        for (var k in given) props[k] = given[k];
        props.objectName = tag;

        // First push replaces the invisible placeholder's column instead of
        // adding beside it (the placeholder isn't a valid addPageToNextColumn source)
        if (isFirstPage)
            root.addPageToCurrentColumn(sourcePage, pageUrl, props);
        else
            root.addPageToNextColumn(sourcePage, pageUrl, props);
        var page = _findByObjectName(root, tag);
        if (!page) return null;
        _pages = _pages.concat([page]);
        return page;
    }

    function pop() {
        if (_pages.length === 0) return;
        var top = _pages[_pages.length - 1];
        root.removePages(top);
        _pages = _pages.slice(0, -1);
    }
}
