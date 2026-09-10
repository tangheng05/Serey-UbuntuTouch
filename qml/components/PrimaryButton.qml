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
    opacity: enabled ? 1.0 : 0.5    // Suru dims the whole control rather than washing the fill

    Rectangle {
        anchors.fill: parent
        radius: Style.cardRadius
        color: root.pressed ? Style.brandDark : Style.brand
        Behavior on color { ColorAnimation { duration: 120 } }

        Row {
            anchors.centerIn: parent
            spacing: Style.spacingS

            ActivityIndicator {
                anchors.verticalCenter: parent.verticalCenter
                running: root.busy
                visible: root.busy
                implicitWidth: units.gu(2.5)
                implicitHeight: units.gu(2.5)
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: root.text
                font.pixelSize: Style.fontMedium
                font.weight: Font.DemiBold
                font.family: Style.fontFor(text)
                color: Style.textOnBrand
            }
        }
    }
}
