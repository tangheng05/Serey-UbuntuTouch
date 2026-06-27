import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

AbstractButton {
    id: root

    property bool overlay: false
    property color bgColor: overlay ? Qt.rgba(0, 0, 0, 0.4) : "white"
    property color arrowColor: overlay ? "white" : Style.textPrimary

    width: units.gu(3.5)
    height: units.gu(3.5)

    Rectangle {
        anchors.fill: parent
        radius: units.dp(8)
        color: root.bgColor
    }

    Canvas {
        anchors.centerIn: parent
        width: units.gu(1); height: units.gu(1.5)
        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            ctx.strokeStyle = root.arrowColor;
            ctx.lineWidth = units.dp(2);
            ctx.lineCap = "round";
            ctx.lineJoin = "round";
            ctx.beginPath();
            ctx.moveTo(width * 0.85, 0);
            ctx.lineTo(width * 0.15, height * 0.5);
            ctx.lineTo(width * 0.85, height);
            ctx.stroke();
        }
    }
}
