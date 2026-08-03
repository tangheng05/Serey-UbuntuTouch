import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

// Placeholder rows for a side rail's Related list: thumb plus two text lines.
Column {
    id: root

    property int count: 3
    property real thumbWidth: units.gu(6.5)
    property real thumbHeight: units.gu(6.5)

    spacing: Style.spacingM

    Repeater {
        // Gate on visibility so the pulse stops when the rail has real rows.
        model: root.visible ? root.count : 0
        delegate: Row {
            id: skelRow
            width: root.width
            spacing: Style.spacingS
            readonly property real textWidth: width - root.thumbWidth - Style.spacingS

            SkeletonRect {
                width: root.thumbWidth
                height: root.thumbHeight
                radius: Style.thumbRadius
                baseColor: Style.dark ? "#333333" : "#ECECEC"
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacingXs
                SkeletonRect { width: skelRow.textWidth; height: units.gu(1.5); radius: height / 2 }
                SkeletonRect { width: skelRow.textWidth * 0.6; height: units.gu(1.5); radius: height / 2 }
            }
        }
    }
}
