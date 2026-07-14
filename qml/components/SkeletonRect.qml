import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

Rectangle {
    id: skeleton

    property bool loading: true
    property color baseColor: Style.skeleton
    property string glyph: ""

    color: baseColor
    visible: loading
    radius: Style.durationBadgeRadius

    Icon {
        anchors.centerIn: parent
        width: units.gu(4.5); height: width
        name: skeleton.glyph
        color: Qt.rgba(0, 0, 0, 0.09)
        visible: skeleton.glyph !== ""
    }

    // A slow, shallow breathe — calm rather than a fast flash.
    SequentialAnimation on opacity {
        running: skeleton.loading
        loops: Animation.Infinite
        NumberAnimation { from: 1.0; to: 0.7; duration: 1100; easing.type: Easing.InOutSine }
        NumberAnimation { from: 0.7; to: 1.0; duration: 1100; easing.type: Easing.InOutSine }
    }
}
