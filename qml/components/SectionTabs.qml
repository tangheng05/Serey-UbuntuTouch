import QtQuick 2.7
import QtQuick.Layouts 1.3
import Lomiri.Components 1.3
import "../Theme"

Item {
    id: root
    property var model: []
    property int currentIndex: 0
    signal selected(int index)
    // Down on strip moves focus to content list
    signal focusList()

    // focus active tab's key area
    function focusCurrent() { _focusTab(Math.max(0, currentIndex)) }
    function _focusTab(i) {
        var it = rep.itemAt(i);
        if (it) it.keyArea.forceActiveFocus();
    }

    // matches PageHeader height for split/wide layout alignment
    implicitHeight: units.gu(6) + units.dp(1)

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 0

        Repeater {
            id: rep
            model: root.model
            delegate: AbstractButton {
                id: tab
                Layout.fillWidth: true
                Layout.fillHeight: true
                property bool active: index === root.currentIndex
                property alias keyArea: keyTap

                // Keyboard-focus cue: a soft brand-tint pill hugging the label.
                // (KeyTapArea's boxy ring clashed with the active underline.)
                Rectangle {
                    anchors.centerIn: parent
                    width: tabLabel.implicitWidth + units.gu(3)
                    height: units.gu(4)
                    radius: height / 2
                    color: Style.brand
                    opacity: 0.12
                    visible: keyTap.activeFocus
                }
                // only emit; parent owns currentIndex binding
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

                KeyTapArea {
                    id: keyTap
                    showRing: false
                    onActivated: { root.selected(index); root.focusList(); }
                    onLeftPressed: root._focusTab(index - 1)
                    onRightPressed: root._focusTab(index + 1)
                    onDownPressed: root.focusList()
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
