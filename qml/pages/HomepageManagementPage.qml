import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"

// Homepage nav-bar visibility
Page {
    id: page

    readonly property real maxContentWidth: units.gu(60)

    header: PageHeader {
        title: Lang.tr("Homepage")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.pageStack.pop() }
        ]
    }

    Column {
        anchors { top: page.header.bottom; horizontalCenter: parent.horizontalCenter }
        width: Math.min(parent.width, page.maxContentWidth)

        SettingsSectionHeader { width: parent.width; text: Lang.tr("Navigation") }
        NavVisibilityToggle {
            width: parent.width
            navKey: "homepage"
            navLabel: Lang.tr("Homepage")
            navIcon: "home"
        }
    }
}
