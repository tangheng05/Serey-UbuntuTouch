import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

AbstractButton {
    id: root

    property string label: ""

    width: parent ? parent.width : units.gu(20)
    height: units.gu(4.5)

    Label {
        anchors.centerIn: parent
        text: root.label
        font.pixelSize: Style.fontSmall
        font.weight: Font.DemiBold
        font.family: Style.fontFor(text)
        color: root.pressed ? Style.brandDark : Style.brand
    }
}
