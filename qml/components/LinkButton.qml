import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

AbstractButton {
    id: root

    property string label: ""
    property int horizontalAlignment: Text.AlignHCenter

    width: parent ? parent.width : units.gu(20)
    height: units.gu(4.5)

    Label {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: root.horizontalAlignment === Text.AlignLeft ? parent.left : undefined
        anchors.right: root.horizontalAlignment === Text.AlignRight ? parent.right : undefined
        anchors.horizontalCenter: root.horizontalAlignment === Text.AlignHCenter ? parent.horizontalCenter : undefined
        text: root.label
        font.pixelSize: Style.fontSmall
        font.weight: Font.DemiBold
        font.family: Style.fontFor(text)
        color: root.pressed ? Style.brandDark : Style.brand
    }
}
