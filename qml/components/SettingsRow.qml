import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

/*
 * One iOS-style settings row: a circular icon badge, a label, and an optional
 * trailing element (value text, a switch, or a chevron). Tappable via clicked().
 * A hairline divider is inset to start after the icon badge.
 */
AbstractButton {
    id: root

    property string iconName: ""
    property string label: ""
    property string valueText: ""
    property bool showChevron: false
    property bool showSwitch: false
    property bool switchChecked: false
    property bool danger: false
    signal switchToggled(bool checked)

    width: parent ? parent.width : units.gu(40)
    height: units.gu(7)

    Rectangle {
        anchors.fill: parent
        color: (root.pressed && root.enabled) ? Style.pressed : "transparent"
    }

    Rectangle {
        id: badge
        anchors { left: parent.left; leftMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
        width: units.gu(4.25); height: width
        radius: width / 2
        color: root.danger ? Qt.rgba(0.78, 0.09, 0.17, 0.10) : Style.iconBackground
        Icon {
            anchors.centerIn: parent
            width: units.gu(2.4); height: width
            name: root.iconName
            color: root.danger ? Style.danger : Style.textSecondary
        }
    }

    Label {
        anchors {
            left: badge.right; leftMargin: Style.spacingM
            right: trailing.left; rightMargin: Style.spacingS
            verticalCenter: parent.verticalCenter
        }
        text: root.label
        elide: Text.ElideRight
        font.pixelSize: Style.fontRegular
        font.family: Style.fontFamily
        color: root.danger ? Style.danger : Style.textPrimary
    }

    // A Row sizes to its single visible child intrinsically (invisible children
    // are excluded), so there's no childrenRect/right-anchor feedback loop.
    Row {
        id: trailing
        anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
        height: root.height

        Label {
            visible: root.valueText.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: root.valueText
            font.pixelSize: Style.fontRegular
            font.family: Style.fontFamily
            color: Style.textSecondary
        }
        Icon {
            visible: root.showChevron
            anchors.verticalCenter: parent.verticalCenter
            width: units.gu(2); height: width
            name: "next"
            color: Style.textSecondary
        }
        Switch {
            visible: root.showSwitch
            anchors.verticalCenter: parent.verticalCenter
            checked: root.switchChecked
            onCheckedChanged: if (checked !== root.switchChecked) root.switchToggled(checked)
        }
    }

    Rectangle {
        anchors { left: badge.right; leftMargin: Style.spacingM; right: parent.right; bottom: parent.bottom }
        height: units.dp(1)
        color: Style.divider
    }
}
