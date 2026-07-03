import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../Theme"
import "../Session"
import "../components"

/*
 * Saved articles: blog/news posts saved via the ★ button on PostDetailPage.
 * Reachable from Settings. Tapping a row opens PostDetailPage with the saved
 * view-model (preloadedPost), so it renders instantly and reads offline. Swipe
 * a row (or use the ••• action) to remove.
 */
Page {
    id: page

    header: Item { height: 0 }

    property string _pendingRemove: ""

    Component {
        id: removeDialog
        Dialog {
            id: rdlg
            title: Lang.tr("Remove saved article?")
            text: Lang.tr("It will no longer be available offline.")
            Button {
                text: Lang.tr("Remove")
                color: Style.danger
                onClicked: { PopupUtils.close(rdlg); SavedPosts.remove(page._pendingRemove); }
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
            text: Lang.tr("Saved articles")
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

    function open(modelData) {
        page.pageStack.push(Qt.resolvedUrl("PostDetailPage.qml"),
            { author: modelData.author, permlink: modelData.permlink,
              title: modelData.title, preloadedPost: modelData });
    }

    ListView {
        id: list
        anchors { top: topBar.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: true
        model: SavedPosts.items
        cacheBuffer: units.gu(20)

        delegate: ListItem {
            width: list.width
            height: row.height + Style.spacingM * 2
            onClicked: page.open(modelData)

            leadingActions: ListItemActions {
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

            trailingActions: ListItemActions {
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

            Row {
                id: row
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
                        wrapMode: Text.WordWrap
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
        anchors.fill: list
        visible: SavedPosts.items.length === 0
        iconName: "save"
        message: Lang.tr("No saved articles yet")
    }
}
