import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"

// Error placeholder with a Retry action. Connect onRetry to re-run the fetch.
Item {
    id: root
    property string message: Lang.tr("Something went wrong")
    signal retry()

    Column {
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
            text: root.message
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
