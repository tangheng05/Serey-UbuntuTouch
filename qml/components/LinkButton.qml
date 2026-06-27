import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

/*
 * Centered, brand-coloured text link as a real AbstractButton — reliable to tap
 * inside a Flickable (unlike a rich-text <a> link, whose hit detection the
 * Flickable steals). Used for secondary navigation (Sign up, Forgot password).
 */
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
        font.family: Style.fontFamily
        color: root.pressed ? Style.brandDark : Style.brand
    }
}
