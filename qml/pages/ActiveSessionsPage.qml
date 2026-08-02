import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/DeviceService.js" as DeviceService

Page {
    id: page

    property bool loading: false
    property string errorMsg: ""
    readonly property real maxContentWidth: units.gu(60)

    property bool _hasCurrent: false

    header: PageHeader {
        title: Lang.tr("Active sessions")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.pageStack.pop() }
        ]
        trailingActionBar.actions: [
            Action {
                iconName: "delete"
                text: Lang.tr("Terminate all")
                // Shown even if current device is unidentified: falls back to a per-device sweep
                visible: deviceModel.count > 1 && !page.loading
                onTriggered: PopupUtils.open(terminateAllDialog)
            }
        ]
    }

    ListModel { id: deviceModel; dynamicRoles: true }

    // Pre-deviceId logins: fall back to "only device = current"
    function _markCurrent() {
        var onlyOne = deviceModel.count === 1
        page._hasCurrent = false
        for (var i = 0; i < deviceModel.count; i++) {
            var cur = onlyOne || (Session.deviceId > 0 && deviceModel.get(i).deviceId === Session.deviceId)
            deviceModel.setProperty(i, "isCurrent", cur)
            if (cur) page._hasCurrent = true
        }
    }

    function load() {
        page.loading = true
        page.errorMsg = ""
        DeviceService.list(Config.baseUrl, Session.token,
            function (list) {
                page.loading = false
                deviceModel.clear()
                for (var i = 0; i < list.length; i++) {
                    var d = list[i]
                    deviceModel.append({ deviceId: d.id, deviceName: d.deviceName,
                                         city: d.city, country: d.country,
                                         lastActiveAt: d.lastActiveAt,
                                         isCurrent: false, busy: false })
                }
                page._markCurrent()
            },
            function (err) {
                page.loading = false
                // A 401 already logs out and toasts globally; don't double-report it.
                if (err.status !== 401)
                    page.errorMsg = err.message || Lang.tr("Failed to load sessions.")
            })
    }

    function _indexOfDevice(id) {
        for (var i = 0; i < deviceModel.count; i++)
            if (deviceModel.get(i).deviceId === id) return i
        return -1
    }

    // Keyed by id, not row index: the model can shift while the confirm dialog is up.
    function terminate(id) {
        var idx = page._indexOfDevice(id)
        if (idx < 0) return
        deviceModel.setProperty(idx, "busy", true)
        DeviceService.terminate(Config.baseUrl, Session.token, [id],
            function () {
                var i = page._indexOfDevice(id)
                if (i >= 0) deviceModel.remove(i)
                page._markCurrent()
                Toast.show(Lang.tr("Session terminated."))
            },
            function (err) {
                var i = page._indexOfDevice(id)
                if (i >= 0) deviceModel.setProperty(i, "busy", false)
                // 400 here means "that's your current device"; remember it.
                if (err.status === 400 && i >= 0) {
                    Session.setDeviceId(id)
                    page._markCurrent()
                }
                if (err.status !== 401)
                    Toast.error(err.message || Lang.tr("Failed to terminate session."))
            })
    }

    function terminateOthers() {
        if (page._hasCurrent) {
            var ids = []
            for (var i = 0; i < deviceModel.count; i++) {
                var it = deviceModel.get(i)
                if (!it.isCurrent) ids.push(it.deviceId)
            }
            if (ids.length === 0) return
            page.loading = true
            DeviceService.terminate(Config.baseUrl, Session.token, ids,
                function () {
                    Toast.show(ids.length === 1 ? Lang.tr("Session terminated.")
                                                : Lang.tr("%1 sessions terminated.").arg(ids.length))
                    page.load()
                },
                function (err) {
                    page.loading = false
                    if (err.status !== 401)
                        Toast.error(err.message || Lang.tr("Failed to terminate session."))
                })
            return
        }

        // Unknown current device: bulk call would 400 the batch, so sweep one at a time
        var allIds = []
        for (var j = 0; j < deviceModel.count; j++)
            allIds.push(deviceModel.get(j).deviceId)
        page.loading = true
        page._sweepIdx = 0
        page._sweepIds = allIds
        page._sweepNext()
    }

    property var _sweepIds: []
    property int _sweepIdx: 0

    function _sweepNext() {
        if (page._sweepIdx >= page._sweepIds.length) {
            page.loading = false
            Toast.show(Lang.tr("Other sessions terminated."))
            page.load()
            return
        }
        var id = page._sweepIds[page._sweepIdx]
        DeviceService.terminate(Config.baseUrl, Session.token, [id],
            function () {
                page._sweepIdx++
                page._sweepNext()
            },
            function (err) {
                if (err.status === 401) { page.loading = false; return }
                if (err.status === 400) Session.setDeviceId(id)
                page._sweepIdx++
                page._sweepNext()
            })
    }

    function _subtitle(m) {
        var place = [m.city, m.country].filter(function (s) { return s !== "" }).join(", ")
        var when = Style.formatTimeAgo(m.lastActiveAt)
        if (place === "") return when
        return when === "" ? place : place + "  •  " + when
    }

    Component.onCompleted: page.load()

    Component {
        id: terminateAllDialog
        Dialog {
            id: allDlg
            title: Lang.tr("Terminate all other sessions?")
            text: Lang.tr("The other devices will be signed out. This device stays signed in.")

            Button {
                text: Lang.tr("Terminate all")
                color: Style.danger
                onClicked: { PopupUtils.close(allDlg); page.terminateOthers(); }
            }
            Button {
                text: Lang.tr("Cancel")
                onClicked: PopupUtils.close(allDlg)
            }
        }
    }

    property int _pendingId: 0
    Component {
        id: terminateDialog
        Dialog {
            id: oneDlg
            title: Lang.tr("Terminate session?")
            text: Lang.tr("That device will be signed out and must sign in again.")

            Button {
                text: Lang.tr("Terminate")
                color: Style.danger
                onClicked: { PopupUtils.close(oneDlg); page.terminate(page._pendingId); }
            }
            Button {
                text: Lang.tr("Cancel")
                onClicked: PopupUtils.close(oneDlg)
            }
        }
    }

    // Keyboard nav: same contract as BlockedUsersPage (settings focuses this list).
    property Item keyboardFocusItem: list
    onVisibleChanged: if (visible) { list.kbEngaged = false; list.forceActiveFocus(); }

    ListView {
        id: list
        anchors { top: parent.header.bottom; bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
        width: Math.min(parent.width, page.maxContentWidth)
        model: deviceModel
        clip: true
        property bool kbEngaged: false
        Keys.onPressed: list.kbEngaged = true
        Keys.onLeftPressed: Nav.focusMaster()
        Keys.onEscapePressed: Nav.focusMaster()

        header: Item {
            width: list.width
            height: deviceModel.count > 0 ? countLabel.height + Style.spacingM * 2 : 0
            Label {
                id: countLabel
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                          leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                text: deviceModel.count === 1
                      ? Lang.tr("You are signed in on this device only.")
                      : Lang.tr("You are signed in on %1 devices.").arg(deviceModel.count)
                visible: deviceModel.count > 0
                wrapMode: Text.WordWrap
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFor(text)
                color: Style.textSecondary
            }
        }

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

            Item {
                id: rowIcon
                anchors { left: parent.left; leftMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                width: units.gu(5); height: width

                Rectangle {
                    anchors.fill: parent
                    radius: units.gu(1)
                    color: model.isCurrent ? Qt.rgba(0, 0.51, 0.98, 0.12) : Style.iconBackground
                }
                Icon {
                    anchors.centerIn: parent
                    width: units.gu(2.5); height: width
                    name: "computer-symbolic"
                    color: model.isCurrent ? Style.brand : Style.textSecondary
                }
            }

            Column {
                anchors {
                    left: rowIcon.right; leftMargin: Style.spacingM
                    right: parent.right; rightMargin: Style.spacingM + (model.isCurrent ? 0 : btnWidth + Style.spacingS)
                    verticalCenter: parent.verticalCenter
                }
                spacing: units.dp(3)

                Row {
                    spacing: Style.spacingS
                    width: parent.width

                    Label {
                        text: model.deviceName || Lang.tr("Unknown device")
                        font.pixelSize: Style.fontRegular
                        font.weight: Font.DemiBold
                        font.family: Style.fontFor(text)
                        color: Style.textPrimary
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        visible: model.isCurrent
                        width: currentTag.width + Style.spacingS * 2
                        height: currentTag.height + units.dp(4)
                        radius: height / 2
                        color: Qt.rgba(0, 0.51, 0.98, 0.12)
                        Label {
                            id: currentTag
                            anchors.centerIn: parent
                            text: Lang.tr("This device")
                            font.pixelSize: Style.fontXSmall
                            font.weight: Font.DemiBold
                            font.family: Style.fontFor(text)
                            color: Style.brand
                        }
                    }
                }
                Label {
                    text: page._subtitle(model)
                    visible: text !== ""
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                    elide: Text.ElideRight
                    width: parent.width
                }
            }

            Item {
                visible: !model.isCurrent
                anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                width: btnWidth; height: units.gu(4.5)
                z: 2

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: model.busy ? Style.iconBackground : Style.dangerTint
                    border.width: units.dp(1.5)
                    border.color: model.busy ? Style.divider : Style.danger
                }
                Label {
                    anchors.centerIn: parent
                    text: model.busy ? Lang.tr("Ending…") : Lang.tr("Terminate")
                    font.pixelSize: Style.fontSmall
                    font.weight: Font.DemiBold
                    font.family: Style.fontFor(text)
                    color: model.busy ? Style.textSecondary : Style.danger
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: !model.busy
                    onClicked: {
                        page._pendingId = model.deviceId
                        PopupUtils.open(terminateDialog)
                    }
                }
            }

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: units.gu(8) }
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
        visible: !page.loading && page.errorMsg === "" && deviceModel.count === 0
        iconName: "computer-symbolic"
        message: Lang.tr("No active sessions")
    }

    ErrorState {
        anchors { top: parent.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: page.errorMsg !== "" && deviceModel.count === 0
        message: page.errorMsg
        onRetry: page.load()
    }
}
