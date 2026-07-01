import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/AccountService.js" as AccountService

Page {
    id: page

    property bool loading: false
    property string errorMsg: ""

    header: PageHeader {
        title: Lang.tr("Blocked Users")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.pageStack.pop() }
        ]
    }

    ListModel { id: blockedModel; dynamicRoles: true }

    function load() {
        page.loading = true
        page.errorMsg = ""
        blockedModel.clear()
        AccountService.listBlocked(Config.baseUrl, Session.token,
            function (list) {
                page.loading = false
                for (var i = 0; i < list.length; i++) {
                    if (list[i] !== "") blockedModel.append({ username: list[i], unblocking: false })
                }
            },
            function (err) {
                page.loading = false
                page.errorMsg = err.message || Lang.tr("Failed to load blocked users.")
            })
    }

    function unblock(index, username) {
        blockedModel.setProperty(index, "unblocking", true)
        AccountService.toggleBlock(Config.baseUrl, Session.token, username, "REMOVE",
            function () {
                blockedModel.remove(index)
                Toast.show(Lang.tr("@%1 unblocked.").arg(username))
            },
            function (err) {
                blockedModel.setProperty(index, "unblocking", false)
                Toast.error(err.message || Lang.tr("Failed to unblock."))
            })
    }

    Component.onCompleted: page.load()

    ListView {
        id: list
        anchors { top: parent.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        model: blockedModel
        clip: true

        delegate: Item {
            width: list.width
            height: units.gu(9)
            readonly property int btnWidth: units.gu(11)

            // Tap row → open profile (declared first = lowest z; button MouseArea sits above it)
            MouseArea {
                id: rowPress
                anchors.fill: parent
                onClicked: page.pageStack.push(Qt.resolvedUrl("ProfileViewPage.qml"),
                               { username: model.username })
            }

            // Row press highlight
            Rectangle {
                anchors.fill: parent
                color: rowPress.pressed ? Style.pressed : "transparent"
                z: 1
            }

            // Avatar
            Item {
                id: rowAvatar
                anchors { left: parent.left; leftMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                width: units.gu(6); height: width

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Style.avatarTint ? Style.avatarTint(model.username || "") : Style.brand
                }
                Label {
                    anchors.centerIn: parent
                    text: (model.username || "?").charAt(0).toUpperCase()
                    font.pixelSize: Style.fontLarge
                    font.bold: true
                    color: "white"
                }
            }

            // Username + @handle
            Column {
                anchors {
                    left: rowAvatar.right; leftMargin: Style.spacingM
                    right: parent.right; rightMargin: Style.spacingM + btnWidth + Style.spacingS
                    verticalCenter: parent.verticalCenter
                }
                spacing: units.dp(3)

                Label {
                    text: model.username || ""
                    font.pixelSize: Style.fontRegular
                    font.weight: Font.DemiBold
                    font.family: Style.fontFamily
                    color: Style.textPrimary
                    elide: Text.ElideRight
                    width: parent.width
                }
                Label {
                    text: "@" + (model.username || "")
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFamily
                    color: Style.textSecondary
                    elide: Text.ElideRight
                    width: parent.width
                }
            }

            // Unblock button
            Item {
                anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                width: btnWidth; height: units.gu(4.5)
                z: 2

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: model.unblocking ? Style.iconBackground : Qt.rgba(0.78, 0.09, 0.17, 0.08)
                    border.width: units.dp(1.5)
                    border.color: model.unblocking ? Style.divider : Style.danger
                }
                Label {
                    anchors.centerIn: parent
                    text: model.unblocking ? Lang.tr("Unblocking…") : Lang.tr("Unblock")
                    font.pixelSize: Style.fontSmall
                    font.weight: Font.DemiBold
                    font.family: Style.fontFamily
                    color: model.unblocking ? Style.textSecondary : Style.danger
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: !model.unblocking
                    onClicked: page.unblock(index, model.username)
                }
            }

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: units.gu(9) }
                height: units.dp(1)
                color: Style.divider
            }
        }
    }

    ActivityIndicator {
        anchors.centerIn: parent
        running: page.loading
        visible: running
    }

    EmptyState {
        anchors { top: parent.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: !page.loading && page.errorMsg === "" && blockedModel.count === 0
        iconName: "contact"
        message: Lang.tr("No blocked users")
    }

    ErrorState {
        anchors { top: parent.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: page.errorMsg !== "" && blockedModel.count === 0
        message: page.errorMsg
        onRetry: page.load()
    }
}
