import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

// Title-on-top / status-below row (Account status panel)
AbstractButton {
    id: root

    property string iconName: ""
    property string title: ""
    property string status: ""
    property color statusColor: Style.textSecondary
    property bool showDivider: true
    property bool highlighted: false

    width: parent ? parent.width : units.gu(40)
    height: units.gu(9)

    Rectangle {
        anchors.fill: parent
        color: (root.pressed && root.enabled) ? Style.pressed : "transparent"
    }

    // Keyboard cursor ring
    Rectangle {
        anchors.fill: parent
        anchors.margins: units.dp(2)
        radius: units.dp(6)
        color: "transparent"
        border.width: units.dp(2)
        border.color: Style.brand
        visible: root.highlighted
    }

    Icon {
        id: rowIcon
        anchors { left: parent.left; leftMargin: Style.spacingM; top: parent.top; topMargin: units.gu(2) }
        width: units.gu(2.2); height: width
        name: root.iconName
        color: Style.textSecondary
        visible: root.iconName.length > 0
    }

    Column {
        anchors {
            left: rowIcon.visible ? rowIcon.right : parent.left
            leftMargin: rowIcon.visible ? Style.spacingS : Style.spacingM
            right: parent.right; rightMargin: Style.spacingM
            verticalCenter: parent.verticalCenter
        }
        spacing: units.dp(4)

        Label {
            width: parent.width
            text: root.title
            font.pixelSize: Style.fontRegular
            font.weight: Font.DemiBold
            font.family: Style.fontFor(text)
            color: Style.textPrimary
            elide: Text.ElideRight
        }
        Label {
            width: parent.width
            text: root.status
            font.pixelSize: Style.fontSmall
            font.family: Style.fontFor(text)
            color: root.statusColor
            elide: Text.ElideRight
        }
    }

    Rectangle {
        visible: root.showDivider
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: units.dp(1)
        color: Style.divider
    }
}
