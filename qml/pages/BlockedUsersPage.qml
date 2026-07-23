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
    readonly property real maxContentWidth: units.gu(60)

    header: PageHeader {
        title: Lang.tr("Blocked Users")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.pageStack.pop() }
        ]
    }

    ListModel { id: blockedModel; dynamicRoles: true }

    // Fetches each user's profile (for a real avatar) after the block list itself loads
    function _fetchAvatar(index, username) {
        AccountService.profile(Config.baseUrl, username, Session.token,
            function (user) { blockedModel.setProperty(index, "avatarUrl", user.profileUrl || "") },
            function (err) { /* keep letter-fallback avatar */ })
    }

    function load() {
        page.loading = true
        page.errorMsg = ""
        blockedModel.clear()
        AccountService.listBlocked(Config.baseUrl, Session.token,
            function (list) {
                page.loading = false
                for (var i = 0; i < list.length; i++) {
                    if (list[i] !== "") {
                        blockedModel.append({ username: list[i], unblocking: false, avatarUrl: "" })
                        page._fetchAvatar(blockedModel.count - 1, list[i])
                    }
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

    // Keyboard nav: settings' Nav.focusDetail targets this list; Left/Escape
    // return to the settings list, arrows move the cursor, Enter opens a profile.
    property Item keyboardFocusItem: list
    onVisibleChanged: if (visible) { list.kbEngaged = false; list.forceActiveFocus(); }

    ListView {
        id: list
        anchors { top: parent.header.bottom; bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
        width: Math.min(parent.width, page.maxContentWidth)
        model: blockedModel
        clip: true
        // Gates the cursor ring: the page auto-focuses on show, but the ring
        // only appears after a real key press, never for touch/mouse users.
        property bool kbEngaged: false
        Keys.onPressed: list.kbEngaged = true
        Keys.onLeftPressed: Nav.focusMaster()
        Keys.onEscapePressed: Nav.focusMaster()
        Keys.onReturnPressed: {
            var it = blockedModel.get(list.currentIndex);
            if (it) page.pageStack.push(Qt.resolvedUrl("ProfileViewPage.qml"), { username: it.username });
        }
        // Keyboard cursor ring (the delegate is a plain Item, not a ListItem, so
        // there's no native focus frame; draw one on the current row).
        highlight: Rectangle {
            z: 5
            width: list.width
            height: list.currentItem ? list.currentItem.height : 0
            visible: list.activeFocus && list.kbEngaged
            color: "transparent"
            border.width: units.dp(2)
            border.color: Style.brand
            radius: units.gu(0.5)
        }
        highlightMoveDuration: 0

        delegate: Item {
            width: list.width
            height: units.gu(9)
            readonly property int btnWidth: units.gu(11)

            // Tap row
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
                    visible: (model.avatarUrl || "") === ""
                }
                Label {
                    anchors.centerIn: parent
                    visible: (model.avatarUrl || "") === ""
                    text: (model.username || "?").charAt(0).toUpperCase()
                    font.pixelSize: Style.fontLarge
                    font.bold: true
                    color: "white"
                }
                CircleImage {
                    anchors.fill: parent
                    source: model.avatarUrl || ""
                    decode: units.gu(12)
                    visible: (model.avatarUrl || "") !== ""
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
                    font.family: Style.fontFor(text)
                    color: Style.textPrimary
                    elide: Text.ElideRight
                    width: parent.width
                }
                Label {
                    text: "@" + (model.username || "")
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
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
                    font.family: Style.fontFor(text)
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
