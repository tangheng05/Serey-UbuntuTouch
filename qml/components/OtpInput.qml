import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

Item {
    id: root

    property int count: 6
    property alias text: hidden.text
    property alias input: hidden
    signal accepted()

    width: parent ? parent.width : units.gu(40)
    height: units.gu(6)

    // Hidden field that actually receives input; digits-only, capped at `count`.
    TextInput {
        id: hidden
        anchors.fill: parent
        opacity: 0
        focus: true
        inputMethodHints: Qt.ImhDigitsOnly
        maximumLength: root.count
        onTextChanged: {
            var clean = text.replace(/[^0-9]/g, "");
            if (clean !== text) text = clean;
        }
        onAccepted: root.accepted()
    }

    Row {
        id: boxes
        anchors.fill: parent
        spacing: Style.spacingS

        Repeater {
            model: root.count
            delegate: Rectangle {
                width: (boxes.width - (root.count - 1) * boxes.spacing) / root.count
                height: parent.height
                radius: Style.cardRadius
                color: Style.surface
                border.width: units.dp(1.5)
                border.color: (hidden.activeFocus && index === hidden.text.length)
                              ? Style.brand : Style.divider
                Behavior on border.color { ColorAnimation { duration: 120 } }

                Label {
                    anchors.centerIn: parent
                    text: index < hidden.text.length ? hidden.text.charAt(index) : ""
                    font.pixelSize: Style.fontTitle
                    font.weight: Font.DemiBold
                    font.family: Style.fontFor(text)
                    color: Style.textPrimary
                }
            }
        }
    }

    // Tapping anywhere on the boxes focuses the hidden field (opens the keyboard).
    MouseArea {
        anchors.fill: parent
        onClicked: hidden.forceActiveFocus()
    }
}
