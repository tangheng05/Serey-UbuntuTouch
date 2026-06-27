import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

/*
 * Celebratory success animation: a brand check-badge that pops in, an expanding
 * ring, and a confetti burst. Plays when `playing` becomes true. Pure QML (no
 * Lottie module, which isn't guaranteed on the device).
 */
Item {
    id: root

    property bool playing: false
    property color accent: Style.brand   // badge + ring colour

    width: units.gu(18)
    height: units.gu(18)

    // Expanding ring
    Rectangle {
        id: ring
        anchors.centerIn: parent
        width: units.gu(7); height: width
        radius: width / 2
        color: "transparent"
        border.width: units.dp(2)
        border.color: root.accent
        opacity: 0
    }

    // Confetti
    Repeater {
        model: 12
        delegate: Item {
            anchors.centerIn: parent
            property real ang: (index / 12) * 2 * Math.PI
            property real dist: units.gu(6) + (index % 3) * units.gu(1.4)

            Rectangle {
                id: dot
                width: units.gu(0.9); height: width
                radius: width / 2
                x: -width / 2; y: -height / 2
                opacity: 0
                color: [Style.brand, Style.success, Style.accentRed, "#FFC107"][index % 4]
            }

            ParallelAnimation {
                running: root.playing
                NumberAnimation { target: dot; property: "x"; from: -dot.width / 2; to: Math.cos(ang) * dist - dot.width / 2; duration: 700; easing.type: Easing.OutQuad }
                NumberAnimation { target: dot; property: "y"; from: -dot.height / 2; to: Math.sin(ang) * dist - dot.height / 2; duration: 700; easing.type: Easing.OutQuad }
                SequentialAnimation {
                    NumberAnimation { target: dot; property: "opacity"; from: 0; to: 1; duration: 140 }
                    NumberAnimation { target: dot; property: "opacity"; to: 0; duration: 540 }
                }
            }
        }
    }

    // Check badge
    Rectangle {
        id: badge
        anchors.centerIn: parent
        width: units.gu(9); height: width
        radius: width / 2
        color: root.accent
        scale: 0
        Icon {
            anchors.centerIn: parent
            width: units.gu(4.5); height: width
            name: "tick"
            color: Style.textOnBrand
        }
    }

    onPlayingChanged: if (playing) burst.restart()

    SequentialAnimation {
        id: burst
        ParallelAnimation {
            NumberAnimation { target: badge; property: "scale"; from: 0; to: 1; duration: 440; easing.type: Easing.OutBack }
            NumberAnimation { target: ring; property: "width"; from: units.gu(7); to: units.gu(16); duration: 620; easing.type: Easing.OutQuad }
            NumberAnimation { target: ring; property: "opacity"; from: 0.5; to: 0; duration: 620; easing.type: Easing.OutQuad }
        }
    }
}
