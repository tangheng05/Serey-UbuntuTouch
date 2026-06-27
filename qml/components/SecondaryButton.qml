import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

/*
 * Outlined brand button — the iOS "Self Custody" style. Same size/rounding as
 * PrimaryButton but transparent with a brand border, for secondary actions.
 */
AbstractButton {
    id: root

    property string text: ""
    property bool busy: false

    width: parent ? parent.width : units.gu(40)
    height: units.gu(6)
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
            font.family: Style.fontFamily
            color: Style.brand
        }
    }
}
