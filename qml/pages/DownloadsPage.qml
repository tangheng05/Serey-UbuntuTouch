import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../Theme"
import "../Session"
import "../components"

Page {
    id: page

    header: Item { height: 0 }

    property string _pendingRemove: ""
    readonly property real maxContentWidth: units.gu(60)

    Component {
        id: removeDialog
        Dialog {
            id: rdlg
            title: Lang.tr("Remove download?")
            text: Lang.tr("This video will no longer be available offline.")
            Button {
                text: Lang.tr("Remove")
                color: Style.danger
                onClicked: { PopupUtils.close(rdlg); Downloads.remove(page._pendingRemove); }
            }
            Button {
                text: Lang.tr("Cancel")
                onClicked: PopupUtils.close(rdlg)
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
            text: Lang.tr("Offline videos")
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

    ListView {
        id: list
        anchors { top: topBar.bottom; bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
        width: Math.min(parent.width, page.maxContentWidth)
        clip: true
        model: Downloads.items
        cacheBuffer: units.gu(16)

        delegate: ListItem {
            width: list.width
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
                onClicked: page.pageStack.push(Qt.resolvedUrl("VideoDetailPage.qml"), { video: modelData })
                onAuthorClicked: page.pageStack.push(Qt.resolvedUrl("ProfileViewPage.qml"),
                    { username: modelData.author })
                onMoreClicked: { page._pendingRemove = modelData.permlink || ""; PopupUtils.open(removeDialog); }
            }
        }
    }

    EmptyState {
        anchors.fill: list
        visible: Downloads.items.length === 0
        iconName: "save"
        message: Lang.tr("No downloaded videos yet")
    }
}
