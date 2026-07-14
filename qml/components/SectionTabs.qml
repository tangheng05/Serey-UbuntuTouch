import QtQuick 2.7
import QtQuick.Layouts 1.3
import Lomiri.Components 1.3
import "../Theme"

Item {
    id: root
    property var model: []
    property int currentIndex: 0
    signal selected(int index)

    implicitHeight: units.gu(5.5)

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 0

        Repeater {
            model: root.model
            delegate: AbstractButton {
                id: tab
                Layout.fillWidth: true
                Layout.fillHeight: true
                property bool active: index === root.currentIndex
                // Controlled component: only emit; the parent updates the property that
                // `currentIndex` is bound to. Writing currentIndex here would break that
                // binding, so a later programmatic change (e.g. showLatest -> feedIndex=1)
                // would reload the data but leave the highlight stuck on the old tab.
                onClicked: root.selected(index)

                Label {
                    id: tabLabel
                    anchors.centerIn: parent
                    text: modelData
                    font.pixelSize: Style.fontMedium
                    font.weight: tab.active ? Font.DemiBold : Font.Normal
                    color: tab.active ? Style.brand : Style.textSecondary
                }

                // Active underline
                Rectangle {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                    width: tabLabel.implicitWidth + units.gu(2)
                    height: units.dp(3)
                    radius: units.dp(1.5)
                    color: Style.brand
                    visible: tab.active
                }
            }
        }
    }

    // Baseline hairline
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: units.dp(1)
        color: Style.divider
    }
}
