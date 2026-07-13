import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"

Rectangle {
    id: badge

    property bool onChain: true

    visible: !onChain
    implicitWidth: row.implicitWidth + Style.spacingS * 2
    implicitHeight: units.gu(2.4)
    width: implicitWidth
    height: implicitHeight
    radius: Style.chipRadius
    color: Style.iconBackground

    Row {
        id: row
        anchors.centerIn: parent
        spacing: units.dp(3)

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            width: units.gu(1.6); height: width
            name: "save"
            color: Style.textSecondary
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: Lang.tr("Off-chain")
            font.pixelSize: Style.fontXSmall
            font.family: Style.fontFor(text)
            color: Style.textSecondary
        }
    }
}
