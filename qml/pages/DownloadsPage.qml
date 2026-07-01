import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../Theme"
import "../Session"
import "../components"

/*
 * Offline library: videos saved via the Download button on VideoDetailPage.
 * Reachable from the Video tab header and from Settings. Tapping a row opens
 * VideoDetailPage, which plays the local copy (VideoDetailPage.directUrl()
 * prefers Downloads.pathFor()). The "•••" button removes a download.
 */
Page {
    id: page

    // Zero-height header: this is a pushed sub-page, so the global AppHeader is
    // collapsed and topBar below is the real bar (same as FeedPage).
    header: Item { height: 0 }

    property string _pendingRemove: ""

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
            font.family: Style.fontFamily
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
        anchors { top: topBar.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: true
        model: Downloads.items
        cacheBuffer: units.gu(16)

        delegate: VideoCard {
            width: list.width
            video: modelData
            onClicked: page.pageStack.push(Qt.resolvedUrl("VideoDetailPage.qml"), { video: modelData })
            onAuthorClicked: page.pageStack.push(Qt.resolvedUrl("ProfileViewPage.qml"),
                { username: modelData.author })
            onMoreClicked: { page._pendingRemove = modelData.permlink || ""; PopupUtils.open(removeDialog); }
        }
    }

    EmptyState {
        anchors.fill: list
        visible: Downloads.items.length === 0
        iconName: "save"
        message: Lang.tr("No downloaded videos yet")
    }
}
