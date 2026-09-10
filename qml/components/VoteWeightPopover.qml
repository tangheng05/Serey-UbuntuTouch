import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../Theme"
import "../Session"

// Vote weight picked next to the button that asked for it, not in a centred modal that
// hides the post. Lomiri's Popover handles placement and the pointer; callers open it with
// PopupUtils.open(url, callerButton) and listen for accepted().
Popover {
    id: pop

    property int weight: 100
    signal accepted(int weight)

    // Popover defaults to a near-full-width panel; this is a compact inline control.
    contentWidth: units.gu(24)
    contentHeight: layout.height

    // Popover's own surface is the same white as the page behind it, so the panel needs
    // its own edge or it reads as text floating on the article.
    Rectangle {
        anchors.fill: layout
        color: Style.surface
        radius: units.gu(0.8)
        border.width: units.dp(1)
        border.color: Style.dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.18)
    }

    Column {
        id: layout
        anchors { left: parent.left; right: parent.right }
        spacing: Style.spacingXs

        Item { width: 1; height: Style.spacingS }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.spacingS

            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: Lang.tr("Up Vote")
                font.pixelSize: Style.fontSmall
                font.weight: Font.DemiBold
                color: Style.textPrimary
            }
            // Dark chip carries the live value, so the slider needs no separate readout
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(units.gu(3.2), weightLabel.width + Style.spacingS * 2)
                height: units.gu(2.4)
                radius: units.gu(0.4)
                color: Style.textPrimary
                Label {
                    id: weightLabel
                    anchors.centerIn: parent
                    text: pop.weight
                    font.pixelSize: Style.fontSmall
                    font.weight: Font.DemiBold
                    color: Style.surface
                }
            }
        }

        // Plain track, not Lomiri's Slider: that one floats a value bubble over the title
        // while dragging and offers no way to suppress it. The chip above is the readout.
        Item {
            id: track
            anchors { left: parent.left; right: parent.right; margins: Style.spacingM }
            height: units.gu(3)

            readonly property int minWeight: 1
            readonly property int maxWeight: 100
            function setFromX(x) {
                var span = Math.max(1, width - knob.width);
                var p = Math.min(1, Math.max(0, (x - knob.width / 2) / span));
                pop.weight = Math.round(minWeight + p * (maxWeight - minWeight));
            }

            Rectangle {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                height: units.dp(3); radius: height / 2
                color: Style.divider
            }
            Rectangle {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: knob.x + knob.width / 2
                height: units.dp(3); radius: height / 2
                color: Style.brand
            }
            Rectangle {
                id: knob
                anchors.verticalCenter: parent.verticalCenter
                x: (pop.weight - track.minWeight) / (track.maxWeight - track.minWeight)
                   * (track.width - width)
                width: units.gu(1.8); height: width; radius: width / 2
                color: Style.surface
                border.width: units.dp(2)
                border.color: Style.brand
            }
            MouseArea {
                anchors.fill: parent
                onPressed: track.setFromX(mouse.x)
                onPositionChanged: if (pressed) track.setFromX(mouse.x)
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.spacingS

            AbstractButton {
                width: units.gu(7.5); height: units.gu(3.2)
                onClicked: PopupUtils.close(pop)
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: "transparent"
                    border.width: units.dp(1)
                    border.color: Style.divider
                }
                Label {
                    anchors.centerIn: parent
                    text: Lang.tr("Close")
                    font.pixelSize: Style.fontSmall
                    color: Style.textSecondary
                }
            }
            AbstractButton {
                width: units.gu(7.5); height: units.gu(3.2)
                onClicked: {
                    PopupUtils.close(pop);
                    pop.accepted(pop.weight);
                }
                Rectangle { anchors.fill: parent; radius: height / 2; color: Style.brand }
                Label {
                    anchors.centerIn: parent
                    text: Lang.tr("OK")
                    font.pixelSize: Style.fontSmall
                    font.weight: Font.DemiBold
                    color: Style.textOnBrand
                }
            }
        }

        Item { width: 1; height: Style.spacingS }
    }
}
