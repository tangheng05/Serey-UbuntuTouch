import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

/*
 * One Lomiri-style list row: a bare (theme-colorable) Suru icon, a label, and an
 * optional trailing element (value text, a switch, or a chevron). Tappable via
 * clicked(). A hairline divider is inset to start after the icon.
 *
 * (Was an iOS-style row with a circular tinted icon badge — Lomiri list rows use
 * a plain icon, no disc.)
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
    property int unreadBadge: 0
    signal switchToggled(bool checked)

    width: parent ? parent.width : units.gu(40)
    height: units.gu(7)

    Rectangle {
        anchors.fill: parent
        color: (root.pressed && root.enabled) ? Style.pressed : "transparent"
    }

    Icon {
        id: rowIcon
        anchors { left: parent.left; leftMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
        width: units.gu(2.6); height: width
        name: root.iconName
        color: root.danger ? Style.danger : Style.textSecondary
        visible: root.iconName.length > 0
    }

    Label {
        anchors {
            left: rowIcon.visible ? rowIcon.right : parent.left
            leftMargin: Style.spacingM
            right: trailing.left; rightMargin: Style.spacingS
            verticalCenter: parent.verticalCenter
        }
        text: root.label
        elide: Text.ElideRight
        font.pixelSize: Style.fontRegular
        font.family: Style.fontFor(text)
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
            font.family: Style.fontFor(text)
            color: Style.textSecondary
        }
        Rectangle {
            visible: root.unreadBadge > 0
            anchors.verticalCenter: parent.verticalCenter
            width: badgeLabel.implicitWidth + units.gu(1)
            height: units.gu(2.2)
            radius: height / 2
            color: Style.danger
            Label {
                id: badgeLabel
                anchors.centerIn: parent
                text: root.unreadBadge > 99 ? "99+" : root.unreadBadge
                font.pixelSize: units.dp(10)
                font.weight: Font.Bold
                color: "white"
            }
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

    // Full-width hairline (Lomiri list dividers span edge-to-edge, not inset).
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: units.dp(1)
        color: Style.divider
    }
}
