import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../services/AccountService.js" as AccountService
import "../services/DeviceService.js" as DeviceService

// Settings "Account status" right rail
Rectangle {
    id: panel

    property var profile: null
    // Row-nav / focus-back target
    property var pageStack: null

    property int rowIndex: -1
    readonly property int _rowCount: 4

    // Active-sessions device count
    property int deviceCount: -1   // -1 = not loaded yet
    // Two-factor status
    property int twoFaEnabled: -1   // -1 = not loaded yet, 0 = off, 1 = on
    function _loadDeviceCount() {
        if (!Session.isLoggedIn) { panel.deviceCount = -1; return; }
        DeviceService.list(Config.baseUrl, Session.token,
            function (devices) { panel.deviceCount = devices.length; },
            function (err) { panel.deviceCount = -1; })
    }
    function _loadTwoFaStatus() {
        if (!Session.isLoggedIn) { panel.twoFaEnabled = -1; return; }
        AccountService.get2faStatus(Config.baseUrl, Session.token,
            function (st) { panel.twoFaEnabled = st.enabled ? 1 : 0; },
            function (err) { panel.twoFaEnabled = -1; })
    }
    onVisibleChanged: if (visible) { panel._loadDeviceCount(); panel._loadTwoFaStatus(); }
    Connections {
        target: Session
        function onTokenChanged() { panel._loadDeviceCount(); panel._loadTwoFaStatus(); }
    }

    function _rows() {
        return [emailRow, twoFaRow, passwordRow, sessionsRow];
    }
    function focusPanel() {
        panelFlick.forceActiveFocus();
        panel.rowIndex = 0;
    }
    function _activate() {
        var rows = panel._rows();
        if (panel.rowIndex < 0 || panel.rowIndex >= rows.length) return;
        rows[panel.rowIndex].clicked();
    }
    function _returnFocus() {
        panel.rowIndex = -1;
        if (panel.pageStack && panel.pageStack.depth > 1) Nav.focusDetail();
        else Nav.focusMaster();
    }

    // Mouse press clears keyboard ring
    Component.onCompleted: {
        var rows = panel._rows();
        for (var i = 0; i < rows.length; i++) {
            rows[i].pressedChanged.connect((function (row) {
                return function () { if (row.pressed) panel.rowIndex = -1; };
            })(rows[i]));
        }
        panel._loadDeviceCount();
        panel._loadTwoFaStatus();
    }

    color: Style.surface

    // No border here: Main.qml's accountPanelDivider is the single vertical line
    // (drawing one on both sides doubled it, see PostDetailPage's sidePanel).

    Label {
        id: header
        anchors { top: parent.top; left: parent.left; leftMargin: Style.spacingM; topMargin: Style.spacingM }
        text: Lang.tr("Account status")
        font.pixelSize: Style.fontLarge
        font.weight: Font.DemiBold
        font.family: Style.fontFor(text)
        color: Style.textPrimary
    }

    Flickable {
        id: panelFlick
        anchors { top: header.bottom; topMargin: Style.spacingM; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentWidth: width
        contentHeight: col.height
        clip: true
        activeFocusOnTab: true

        function _revealSelected() {
            var it = panel._rows()[panel.rowIndex];
            if (!it) return;
            var top = it.mapToItem(panelFlick.contentItem, 0, 0).y;
            var bottom = top + it.height;
            if (bottom > panelFlick.contentY + panelFlick.height)
                panelFlick.contentY = bottom - panelFlick.height;
            else if (top < panelFlick.contentY)
                panelFlick.contentY = top;
        }
        Keys.onPressed: {
            if (event.key === Qt.Key_Down) {
                panel.rowIndex = Math.min(panel._rowCount - 1, panel.rowIndex + 1);
                panelFlick._revealSelected(); event.accepted = true;
            } else if (event.key === Qt.Key_Up) {
                if (panel.rowIndex <= 0) panel._returnFocus();
                else { panel.rowIndex = panel.rowIndex - 1; panelFlick._revealSelected(); }
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                panel._activate(); event.accepted = true;
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Escape) {
                panel._returnFocus(); event.accepted = true;
            }
        }

        // Mouse click grabs keyboard focus
        MouseArea {
            anchors.fill: parent
            propagateComposedEvents: true
            onPressed: { panelFlick.forceActiveFocus(); mouse.accepted = false; }
        }

        Column {
            id: col
            width: panelFlick.width

            SettingsStatusRow {
                id: emailRow
                iconName: "contact"
                title: Lang.tr("Email address")
                status: (panel.profile && panel.profile.email) ? panel.profile.email : Lang.tr("Not set")
                statusColor: (panel.profile && panel.profile.email) ? Style.brand : Style.textSecondary
                highlighted: panel.rowIndex === 0
                onClicked: if (Session.isLoggedIn && panel.pageStack) panel.pageStack.push(Qt.resolvedUrl("../pages/EditProfilePage.qml"), { initial: panel.profile })
            }
            SettingsStatusRow {
                id: twoFaRow
                iconName: "system-lock-screen"
                title: Lang.tr("Two-step verification")
                status: panel.twoFaEnabled < 0 ? Lang.tr("Loading…")
                        : panel.twoFaEnabled === 1 ? Lang.tr("Enabled") : Lang.tr("Disabled")
                statusColor: panel.twoFaEnabled === 1 ? Style.brand : Style.textSecondary
                highlighted: panel.rowIndex === 1
                onClicked: if (Session.isLoggedIn && panel.pageStack) panel.pageStack.push(Qt.resolvedUrl("../pages/TwoFactorPage.qml"), { initialEmail: (panel.profile && panel.profile.email) || "" })
            }
            SettingsStatusRow {
                id: passwordRow
                iconName: "system-lock-screen"
                title: Lang.tr("Password")
                status: Lang.tr("Manage password")
                statusColor: Style.brand
                highlighted: panel.rowIndex === 2
                onClicked: if (Session.isLoggedIn && panel.pageStack) panel.pageStack.push(Qt.resolvedUrl("../pages/ChangePasswordPage.qml"))
            }
            SettingsStatusRow {
                id: sessionsRow
                iconName: "computer-symbolic"
                title: Lang.tr("Active sessions")
                status: panel.deviceCount < 0 ? Lang.tr("Loading…")
                        : panel.deviceCount === 1 ? Lang.tr("1 device")
                        : Lang.tr("%1 devices").arg(panel.deviceCount)
                statusColor: Style.textSecondary
                showDivider: false
                highlighted: panel.rowIndex === 3
                onClicked: if (Session.isLoggedIn && panel.pageStack) panel.pageStack.push(Qt.resolvedUrl("../pages/ActiveSessionsPage.qml"))
            }
        }
    }
}
