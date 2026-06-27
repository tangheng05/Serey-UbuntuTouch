import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

/*
 * Small grey section eyebrow above a group of SettingsRows.
 */
Item {
    id: root

    property string text: ""

    width: parent ? parent.width : 0
    height: units.gu(5)

    Label {
        anchors {
            left: parent.left; leftMargin: Style.spacingM
            bottom: parent.bottom; bottomMargin: Style.spacingS
        }
        text: root.text
        font.pixelSize: Style.fontSmall
        font.weight: Font.DemiBold
        font.family: Style.fontFamily
        color: Style.textSecondary
    }
}
