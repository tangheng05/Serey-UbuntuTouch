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
