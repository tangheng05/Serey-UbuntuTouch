import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

/*
 * Back chevron matching Lomiri's PageHeader leading action: themed "back" icon, no chip
 * (the old self-drawn arrow on a white Rectangle was invisible in dark mode).
 * overlay: dark scrim circle + white icon for buttons floating over media.
 */
AbstractButton {
    id: root

    property bool overlay: false

    width: units.gu(4)
    height: units.gu(4)

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Qt.rgba(0, 0, 0, 0.4)
        visible: root.overlay
    }

    Icon {
        anchors.centerIn: parent
        width: units.gu(2.5)
        height: width
        name: "back"
        color: root.overlay ? "white" : Style.textPrimary
    }
}
