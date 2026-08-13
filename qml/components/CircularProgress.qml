import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

// Ring + centered percentage, used in place of a spinner wherever the actual
// progress fraction is known (download buttons, upload buttons, etc).
Item {
    id: root

    // 0..100
    property real value: 0
    property real thickness: units.dp(2.5)
    property color trackColor: Style.divider
    property color progressColor: Style.brand
    property bool showLabel: true

    width: units.gu(3.5); height: width

    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var cx = width / 2, cy = height / 2;
            var r = Math.min(width, height) / 2 - root.thickness / 2;
            var start = -Math.PI / 2;
            var frac = Math.max(0, Math.min(100, root.value)) / 100;

            ctx.lineWidth = root.thickness;
            ctx.lineCap = "round";

            ctx.strokeStyle = root.trackColor;
            ctx.beginPath();
            ctx.arc(cx, cy, r, 0, Math.PI * 2);
            ctx.stroke();

            if (frac > 0) {
                ctx.strokeStyle = root.progressColor;
                ctx.beginPath();
                ctx.arc(cx, cy, r, start, start + Math.PI * 2 * frac);
                ctx.stroke();
            }
        }
    }

    // Canvas doesn't auto-repaint on property changes; drive it explicitly.
    onValueChanged: canvas.requestPaint()
    onTrackColorChanged: canvas.requestPaint()
    onProgressColorChanged: canvas.requestPaint()
    Component.onCompleted: canvas.requestPaint()

    Label {
        anchors.centerIn: parent
        visible: root.showLabel
        text: Math.round(root.value)
        font.pixelSize: Style.fontXSmall
        font.weight: Font.DemiBold
        color: Style.textSecondary
    }
}
