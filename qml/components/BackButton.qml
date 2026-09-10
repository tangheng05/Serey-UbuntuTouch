import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

// Back chevron matching Lomiri's PageHeader; overlay mode adds a scrim for media buttons
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
