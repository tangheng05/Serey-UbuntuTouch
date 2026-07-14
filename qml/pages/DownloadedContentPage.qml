import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../Theme"
import "../Session"
import "../components"

Page {
    id: page

    header: Item { height: 0 }

    property int tabIndex: 0
    property string _pendingRemoveVideo: ""
    property string _pendingRemoveArticle: ""
    readonly property real maxContentWidth: units.gu(60)

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

    Rectangle {
        id: topBar
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: units.gu(6)
        color: Style.navigationBg
        z: 10

        BackButton {
            anchors { left: parent.left; leftMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
            onClicked: page.pageStack.pop()
        }

        Label {
            anchors.centerIn: parent
            text: Lang.tr("Downloaded Content")
            font.pixelSize: Style.fontMedium
            font.weight: Font.DemiBold
            font.family: Style.fontFor(text)
            color: Style.textPrimary
        }

        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: units.dp(1)
            color: Style.divider
        }
    }

    SectionTabs {
        id: tabs
        anchors { top: topBar.bottom; left: parent.left; right: parent.right }
        model: [Lang.tr("Video"), Lang.tr("Articles")]
        currentIndex: page.tabIndex
        onSelected: page.tabIndex = index
    }

    ListView {
        id: videoList
        anchors { top: tabs.bottom; bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
        width: Math.min(parent.width, page.maxContentWidth)
        clip: true
        visible: page.tabIndex === 0
        model: Downloads.items
        cacheBuffer: units.gu(16)

        delegate: ListItem {
            width: videoList.width
            height: videoCard.implicitHeight

            // Lomiri HIG (Presenting data): leading = negative/destructive, trailing = positive/confirming.
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
                        color: "black"
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

        delegate: ListItem {
            width: articleList.width
            height: articleRow.height + Style.spacingM * 2
            onClicked: page.pageStack.push(Qt.resolvedUrl("PostDetailPage.qml"),
                { author: modelData.author, permlink: modelData.permlink,
                  title: modelData.title, preloadedPost: modelData })

            // Lomiri HIG (Presenting data): leading = negative/destructive, trailing = positive/confirming.
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
                        color: "black"
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
                    width: parent.width - units.gu(10) - Style.spacingM
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
            }
        }
    }

    EmptyState {
        anchors.fill: articleList
        visible: page.tabIndex === 1 && SavedPosts.items.length === 0
        iconName: "save"
        message: Lang.tr("No saved articles yet")
    }
}
