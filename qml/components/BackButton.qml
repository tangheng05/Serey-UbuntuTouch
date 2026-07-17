import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

/*
 * Back chevron for custom headers, matching Lomiri's own PageHeader leading
 * action: the themed "back" suru icon, no background chip. The old version drew
 * its own arrow on a hardcoded white Rectangle — in dark mode that rendered a
 * white square with a near-white arrow (Style.textPrimary), i.e. invisible.
 *
 * overlay: for buttons floating over media (Reels, profile cover) — a dark
 * scrim circle with a white icon, readable on any photo in either theme.
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
