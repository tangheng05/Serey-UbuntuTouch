import QtQuick 2.7
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
    property string _pendingRemoveVideo: ""
    property string _pendingRemoveArticle: ""
    readonly property real maxContentWidth: units.gu(100)

    // Keyboard nav: active list owns arrow focus; Left/Escape returns to settings list
    property Item keyboardFocusItem: tabIndex === 0 ? videoList : articleList
    function _focusActiveList() { (tabIndex === 0 ? videoList : articleList).forceActiveFocus(); }
    onVisibleChanged: if (visible) _focusActiveList()

    Component {
        id: removeVideoDialog
        Dialog {
            id: rvdlg
            title: Lang.tr("Remove download?")
            text: Lang.tr("This video will no longer be available offline.")
            Button {
                text: Lang.tr("Remove")
                color: Style.danger
                onClicked: { PopupUtils.close(rvdlg); Downloads.remove(page._pendingRemoveVideo); }
            }
            Button {
                text: Lang.tr("Cancel")
                onClicked: PopupUtils.close(rvdlg)
            }
        }
    }

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
                compactMenu: false
                onClicked: page.pageStack.push(Qt.resolvedUrl("VideoDetailPage.qml"), { video: modelData })
                onAuthorClicked: page.pageStack.push(Qt.resolvedUrl("ProfileViewPage.qml"),
                    { username: modelData.author })
                onMoreClicked: { page._pendingRemoveVideo = modelData.permlink || ""; PopupUtils.open(removeVideoDialog); }
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
            width: articleList.width
            height: articleRow.height + Style.spacingM * 2
            onClicked: page.pageStack.push(Qt.resolvedUrl("PostDetailPage.qml"),
                { author: modelData.author, permlink: modelData.permlink,
                  title: modelData.title, preloadedPost: modelData })

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
                      title: modelData.title, preloadedPost: modelData })
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
                    onClicked: actionSheet.show([
                        { iconName: "delete", text: Lang.tr("Remove"), danger: true,
                          onTriggered: function () { SavedPosts.remove(modelData.permlink); } },
                        { iconName: "share", text: Lang.tr("Share"),
                          onTriggered: function () { Share.open("https://serey.io/authors/" + modelData.author + "/" + modelData.permlink); } }
                    ])

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
