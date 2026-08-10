import QtQuick 2.7
import QtQuick.Window 2.2
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../Theme"
import "../Session"
import "../components"

Page {
    id: page

    header: PageHeader {
        title: Lang.tr("Downloaded Content")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.pageStack.pop() }
        ]
    }

    property int tabIndex: 0
    property string _pendingRemoveArticle: ""
    readonly property real maxContentWidth: units.gu(100)

    // Keyboard nav: active list owns arrow focus; Left/Escape returns to settings list
    property Item keyboardFocusItem: tabIndex === 0 ? videoList : articleList
    function _focusActiveList() { (tabIndex === 0 ? videoList : articleList).forceActiveFocus(); }
    onVisibleChanged: if (visible) _focusActiveList()

    Component {
        id: removeArticleDialog
        Dialog {
            id: radlg
            title: Lang.tr("Remove saved article?")
            text: Lang.tr("It will no longer be available offline.")
            Button {
                text: Lang.tr("Remove")
                color: Style.danger
                onClicked: { PopupUtils.close(radlg); SavedPosts.remove(page._pendingRemoveArticle); }
            }
            Button {
                text: Lang.tr("Cancel")
                onClicked: PopupUtils.close(radlg)
            }
        }
    }

    SectionTabs {
        id: tabs
        anchors { top: parent.header.bottom; left: parent.left; right: parent.right }
        model: [Lang.tr("Video"), Lang.tr("Articles")]
        currentIndex: page.tabIndex
        onSelected: { page.tabIndex = index; page._focusActiveList(); }
        onFocusList: page._focusActiveList()
    }

    ListView {
        id: videoList
        anchors { top: tabs.bottom; bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
        width: Math.min(parent.width, page.maxContentWidth)
        clip: true
        visible: page.tabIndex === 0
        model: Downloads.items
        cacheBuffer: units.gu(16)
        // Left/Escape return to the settings list; Up at top climbs to the strip.
        Keys.onLeftPressed: Nav.focusMaster()
        Keys.onEscapePressed: Nav.focusMaster()
        Keys.onUpPressed: {
            if (videoList.atYBeginning && videoList.currentIndex <= 0) { tabs.focusCurrent(); event.accepted = true; }
            else event.accepted = false;
        }

        delegate: ListItem {
            width: videoList.width
            height: videoCard.implicitHeight

            // HIG polarity: LEADING = negative (red trash), TRAILING = positive.
            leadingActions: ListItemActions {
                delegate: Rectangle {
                    width: units.gu(7)
                    height: parent ? parent.height : units.gu(6)
                    color: Style.danger
                    Icon {
                        anchors.centerIn: parent
                        width: units.gu(2.5); height: width
                        name: action.iconName
                        color: "white"
                    }
                }
                actions: [
                    Action {
                        iconName: "delete"
                        text: Lang.tr("Remove")
                        onTriggered: Downloads.remove(modelData.permlink)
                    }
                ]
            }

            trailingActions: ListItemActions {
                delegate: Item {
                    width: units.gu(7)
                    height: parent ? parent.height : units.gu(6)
                    Icon {
                        anchors.centerIn: parent
                        width: units.gu(2.5); height: width
                        name: action.iconName
                        color: Style.textPrimary
                    }
                }
                actions: [
                    Action {
                        iconName: "share"
                        text: Lang.tr("Share")
                        onTriggered: Share.open(
                            "https://serey.io/video-component/watch?author=" + modelData.author + "&permalink=" + modelData.permlink)
                    }
                ]
            }

            VideoCard {
                id: videoCard
                width: parent.width
                video: modelData
                // Same compact anchored dropdown as the blog cards (default compactMenu); this
                // page just swaps in its own Remove/Share actions instead of the generic ones.
                function menuItems() {
                    return [
                        { icon: "delete", label: Lang.tr("Remove"), danger: true, action: "remove" },
                        { icon: "share", label: Lang.tr("Share"), action: "share" }
                    ];
                }
                function runMenuAction(action) {
                    if (action === "remove") Downloads.remove(modelData.permlink);
                    else if (action === "share") Share.open("https://serey.io/video-component/watch?author=" + modelData.author + "&permalink=" + modelData.permlink);
                }
                // Settings already owns the third column here; no rail on the detail page
                onClicked: page.pageStack.push(Qt.resolvedUrl("VideoDetailPage.qml"),
                    { video: modelData, allowSidePanel: false })
                onAuthorClicked: page.pageStack.push(Qt.resolvedUrl("ProfileViewPage.qml"),
                    { username: modelData.author })
                // Phone width: compactMenu is off there, so "..." falls back to this bottom sheet.
                onMoreClicked: actionSheet.show([
                    { iconName: "delete", text: Lang.tr("Remove"), danger: true,
                      onTriggered: function () { Downloads.remove(modelData.permlink); } },
                    { iconName: "share", text: Lang.tr("Share"),
                      onTriggered: function () { Share.open("https://serey.io/video-component/watch?author=" + modelData.author + "&permalink=" + modelData.permlink); } }
                ], videoCard)
            }
        }
    }

    EmptyState {
        anchors.fill: videoList
        visible: page.tabIndex === 0 && Downloads.items.length === 0
        iconName: "save"
        message: Lang.tr("No downloaded videos yet")
    }

    ListView {
        id: articleList
        anchors { top: tabs.bottom; bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
        width: Math.min(parent.width, page.maxContentWidth)
        clip: true
        visible: page.tabIndex === 1
        model: SavedPosts.items
        cacheBuffer: units.gu(20)
        // Left/Escape return to the settings list; Up at top climbs to the strip.
        Keys.onLeftPressed: Nav.focusMaster()
        Keys.onEscapePressed: Nav.focusMaster()
        Keys.onUpPressed: {
            if (articleList.atYBeginning && articleList.currentIndex <= 0) { tabs.focusCurrent(); event.accepted = true; }
            else event.accepted = false;
        }

        delegate: ListItem {
            id: articleItem
            width: articleList.width
            height: articleRow.height + Style.spacingM * 2
            onClicked: page.pageStack.push(Qt.resolvedUrl("PostDetailPage.qml"),
                { author: modelData.author, permlink: modelData.permlink,
                  title: modelData.title, preloadedPost: modelData, allowSidePanel: false })

            // Same compact anchored dropdown as the video row/blog cards, rather than the full
            // ActionBottomSheet (which is the phone/touch fallback for those too).
            property bool menuOpen: false
            // cardMenu reparents onto the window while open, so force-close it before recycling
            Component.onDestruction: articleItem.menuOpen = false
            // Reparent onto the window while open so the menu isn't clipped by the list row.
            readonly property Item _menuOverlayParent: (articleItem.menuOpen && articleItem.Window.window)
                ? articleItem.Window.window.contentItem : articleItem
            readonly property point _moreBtnBottomRight: (articleItem.menuOpen && moreBtn)
                ? moreBtn.mapToItem(articleItem._menuOverlayParent, moreBtn.width, moreBtn.height) : Qt.point(0, 0)

            // HIG polarity: LEADING = negative (red trash), TRAILING = positive.
            leadingActions: ListItemActions {
                delegate: Rectangle {
                    width: units.gu(7)
                    height: parent ? parent.height : units.gu(6)
                    color: Style.danger
                    Icon {
                        anchors.centerIn: parent
                        width: units.gu(2.5); height: width
                        name: action.iconName
                        color: "white"
                    }
                }
                actions: [
                    Action {
                        iconName: "delete"
                        text: Lang.tr("Remove")
                        onTriggered: SavedPosts.remove(modelData.permlink)
                    }
                ]
            }

            trailingActions: ListItemActions {
                delegate: Item {
                    width: units.gu(7)
                    height: parent ? parent.height : units.gu(6)
                    Icon {
                        anchors.centerIn: parent
                        width: units.gu(2.5); height: width
                        name: action.iconName
                        color: Style.textPrimary
                    }
                }
                actions: [
                    Action {
                        iconName: "share"
                        text: Lang.tr("Share")
                        onTriggered: Share.open("https://serey.io/authors/" + modelData.author + "/" + modelData.permlink)
                    }
                ]
            }

            // Pointer/keyboard parity: right-click or MENU key opens the same actions as swipe
            ContextActionArea {
                id: contextArea
                onActivated: page.pageStack.push(Qt.resolvedUrl("PostDetailPage.qml"),
                    { author: modelData.author, permlink: modelData.permlink,
                      title: modelData.title, preloadedPost: modelData, allowSidePanel: false })
                menuActions: ActionList {
                    Action {
                        iconName: "delete"; text: Lang.tr("Remove")
                        onTriggered: SavedPosts.remove(modelData.permlink)
                    }
                    Action {
                        iconName: "share"; text: Lang.tr("Share")
                        onTriggered: Share.open("https://serey.io/authors/" + modelData.author + "/" + modelData.permlink)
                    }
                }
            }

            Row {
                id: articleRow
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                          leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                spacing: Style.spacingM

                Rectangle {
                    width: units.gu(10); height: units.gu(7)
                    radius: Style.thumbRadius
                    color: Style.iconBackground
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: modelData.thumbnail || ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: units.gu(20)
                    }
                    Icon {
                        anchors.centerIn: parent
                        width: units.gu(3); height: width
                        name: "text-x-generic-symbolic"
                        color: Style.textSecondary
                        visible: (modelData.thumbnail || "") === ""
                    }
                }

                Column {
                    width: parent.width - units.gu(10) - Style.spacingM - moreBtn.width - Style.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: units.dp(3)
                    Label {
                        width: parent.width
                        text: modelData.title || ""
                        font.pixelSize: Style.fontRegular
                        font.weight: Font.DemiBold
                        font.family: Style.fontFor(text)
                        color: Style.textPrimary
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    Label {
                        width: parent.width
                        text: "@" + (modelData.author || "")
                        font.pixelSize: Style.fontSmall
                        color: Style.textSecondary
                        elide: Text.ElideRight
                    }
                }

                AbstractButton {
                    id: moreBtn
                    anchors.verticalCenter: parent.verticalCenter
                    width: units.gu(3.5); height: units.gu(3.5)
                    // Desktop: compact anchored dropdown, same as the video row. Phone/tablet
                    // (compactMenu off there too): fall back to the full bottom sheet.
                    onClicked: {
                        if (Config.desktopMode) { articleItem.menuOpen = !articleItem.menuOpen; return; }
                        actionSheet.show([
                            { iconName: "delete", text: Lang.tr("Remove"), danger: true,
                              onTriggered: function () { SavedPosts.remove(modelData.permlink); } },
                            { iconName: "share", text: Lang.tr("Share"),
                              onTriggered: function () { Share.open("https://serey.io/authors/" + modelData.author + "/" + modelData.permlink); } }
                        ], moreBtn);
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: units.dp(3)
                        Repeater {
                            model: 3
                            delegate: Rectangle {
                                width: units.dp(4); height: units.dp(4)
                                radius: width / 2
                                color: Style.textSecondary
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }
                }
            }

            // Dismiss on outside click; fills the whole window while open once reparented
            MouseArea {
                parent: articleItem._menuOverlayParent
                visible: articleItem.menuOpen
                z: 999
                anchors.fill: parent
                onClicked: articleItem.menuOpen = false
            }

            Rectangle {
                id: articleCardMenu
                parent: articleItem._menuOverlayParent
                visible: articleItem.menuOpen
                z: 1000
                x: Math.min(articleItem._moreBtnBottomRight.x - width, articleItem._menuOverlayParent.width - width - Style.spacingXs)
                y: articleItem._moreBtnBottomRight.y + Style.spacingXs
                width: Math.min(units.gu(30), articleItem._menuOverlayParent.width - Style.spacingM * 2)
                height: articleCardMenuCol.height
                radius: Style.cardRadius
                color: Style.surface
                border.width: units.dp(1)
                border.color: Style.divider

                Column {
                    id: articleCardMenuCol
                    width: parent.width

                    AbstractButton {
                        width: articleCardMenuCol.width
                        height: units.gu(5.5)
                        onClicked: { articleItem.menuOpen = false; SavedPosts.remove(modelData.permlink); }
                        Row {
                            anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                            spacing: Style.spacingM
                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                width: units.gu(2.2); height: width
                                name: "delete"
                                color: Style.danger
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(0, parent.width - units.gu(2.2) - parent.spacing)
                                elide: Text.ElideRight
                                text: Lang.tr("Remove")
                                font.pixelSize: Style.fontSmall
                                color: Style.danger
                            }
                        }
                    }
                    AbstractButton {
                        width: articleCardMenuCol.width
                        height: units.gu(5.5)
                        onClicked: {
                            articleItem.menuOpen = false;
                            Share.open("https://serey.io/authors/" + modelData.author + "/" + modelData.permlink);
                        }
                        Row {
                            anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                            spacing: Style.spacingM
                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                width: units.gu(2.2); height: width
                                name: "share"
                                color: Style.textPrimary
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(0, parent.width - units.gu(2.2) - parent.spacing)
                                elide: Text.ElideRight
                                text: Lang.tr("Share")
                                font.pixelSize: Style.fontSmall
                                color: Style.textPrimary
                            }
                        }
                    }
                }
            }
        }
    }

    EmptyState {
        anchors.fill: articleList
        visible: page.tabIndex === 1 && SavedPosts.items.length === 0
        iconName: "save"
        message: Lang.tr("No saved articles yet")
    }

    ActionBottomSheet { id: actionSheet }
}
