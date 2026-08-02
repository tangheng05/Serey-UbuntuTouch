import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

Item {
    id: toaster
    anchors.fill: parent
    // Above every overlay sheet (up to 1600) since toasts fire while a sheet is open
    z: 2000

    Rectangle {
        id: bg
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: units.gu(11)
        }
        width: Math.min(toaster.width - units.gu(4), label.implicitWidth + units.gu(4))
        height: label.implicitHeight + units.gu(2)
        radius: units.gu(0.75)
        color: Toast.isError ? Style.danger : Style.toastBg
        opacity: 0
        visible: opacity > 0

        Label {
            id: label
            anchors.centerIn: parent
            width: Math.min(toaster.width - units.gu(8), implicitWidth)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            color: Style.textOnBrand
            font.family: Style.fontFor(text)
            text: Toast.message
        }
    }

    Timer {
        id: hideTimer
        interval: 2600
        onTriggered: fadeOut.start()
    }

    NumberAnimation { id: fadeIn; target: bg; property: "opacity"; to: 1.0; duration: 180 }
    NumberAnimation { id: fadeOut; target: bg; property: "opacity"; to: 0.0; duration: 300 }

    Connections {
        target: Toast
        function onSeqChanged() {
            fadeOut.stop();
            fadeIn.start();
            hideTimer.restart();
        }
    }
}
