import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"

// Error placeholder with a Retry action. Connect onRetry to re-run the fetch.
// While the phone has no network it swaps to offline copy: the server message
// ("Request failed", a timeout) explains nothing the user can act on there.
Item {
    id: root
    property string message: Lang.tr("Something went wrong")
    readonly property bool offline: !Net.online
    signal retry()

    // Coming back online only swapped the offline copy for the stale server message and then
    // waited for a tap. Re-run the page's fetch instead, deferred if the panel is off screen.
    // Feeds reload themselves (they also resume paging), so they opt out to avoid a double fetch.
    property bool autoRetry: true
    property bool _retryPending: false
    onVisibleChanged: if (visible && root._retryPending) { root._retryPending = false; root.retry(); }
    Connections {
        target: Net
        function onOnlineChanged() {
            if (!Net.online || !root.autoRetry) return;
            if (root.visible) root.retry(); else root._retryPending = true;
        }
    }

    // The one offline surface, inherited by every page that already shows an error.
    OfflineState {
        anchors.fill: parent
        visible: root.offline
        onRetry: root.retry()
    }

    Column {
        visible: !root.offline
        anchors.centerIn: parent
        width: parent.width - Style.spacingL * 2
        spacing: Style.spacingM

        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            width: units.gu(6)
            height: width
            name: "dialog-warning-symbolic"
            color: Style.danger
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            // Server messages arrive in English; tr() passes unknown ones straight through.
            text: Lang.tr(root.message)
            font.family: Style.fontFor(text)
            color: Style.textSecondary
        }
        Button {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Lang.tr("Retry")
            color: Style.brand
            onClicked: root.retry()
        }
    }
}
