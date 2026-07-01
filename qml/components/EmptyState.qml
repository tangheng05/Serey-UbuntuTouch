import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"

// Friendly placeholder when a list returns no items.
Item {
    id: root
    property string iconName: "info"
    property string message: Lang.tr("Nothing here yet")

    Column {
        anchors.centerIn: parent
        width: parent.width - Style.spacingL * 2
        spacing: Style.spacingM

        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            width: units.gu(6)
            height: width
            name: root.iconName
            color: Style.textSecondary
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.message
            color: Style.textSecondary
        }
    }
}
