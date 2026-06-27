import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

/*
 * Primary call-to-action button in the brand-blue, rounded (cardRadius) style —
 * the same fill/rounding the Follow pill and feed actions use. Shows an inline
 * spinner while `busy`; disabled state dims the fill.
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
        color: !root.enabled ? Qt.rgba(0, 0.51, 0.98, 0.45)
              : root.pressed  ? Style.brandDark
              : Style.brand
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
                font.family: Style.fontFamily
                color: Style.textOnBrand
            }
        }
    }
}
