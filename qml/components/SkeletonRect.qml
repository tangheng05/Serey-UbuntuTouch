import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

/*
 * A loading placeholder block. It "breathes" with a gentle opacity pulse rather
 * than a sweeping highlight band — the band looked like a hard vertical seam
 * when caught mid-sweep, and a single animated opacity is much cheaper than a
 * clipped, moving child on every block of every card.
 *
 * `baseColor` lets a block sit at a different weight than the default text-bar
 * grey — covers use a lighter tone so the skeleton keeps the real card's
 * title-vs-photo hierarchy. `glyph` draws a faint centered photo placeholder so
 * an image region reads as one, not as a solid slab.
 */
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
