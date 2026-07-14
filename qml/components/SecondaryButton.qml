import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

AbstractButton {
    id: root

    property string text: ""
    property bool busy: false

    width: parent ? parent.width : units.gu(40)
    height: units.gu(5)
    enabled: !busy

    Rectangle {
        anchors.fill: parent
        radius: Style.cardRadius
        color: root.pressed ? Style.iconBackground : "transparent"
        border.width: units.dp(1.5)
        border.color: Style.brand
        Behavior on color { ColorAnimation { duration: 120 } }

        Label {
            anchors.centerIn: parent
            text: root.text
            font.pixelSize: Style.fontMedium
            font.weight: Font.DemiBold
            font.family: Style.fontFor(text)
            color: Style.brand
        }
    }
}
