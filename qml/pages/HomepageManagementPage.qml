import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/HomepageService.js" as HomepageService

// Homepage nav-bar visibility
Page {
    id: page

    readonly property real maxContentWidth: units.gu(60)

    // A platform with no homepage of its own keeps the tab hidden until the owner
    // either builds one or flips this switch on; resolved for the managed platform,
    // which is not always the one currently being browsed.
    property bool noHomepage: false
    Component.onCompleted: {
        var id = Config.managedCommunityId;
        HomepageService.hasHomepage(Config.baseUrl, id, function (has) {
            if (id !== Config.managedCommunityId) return;
            page.noHomepage = !has;
        });
    }

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
            defaultHidden: page.noHomepage
        }
        Label {
            visible: page.noHomepage
            width: parent.width
            leftPadding: Style.spacingM
            rightPadding: Style.spacingM
            topPadding: Style.spacingS
            bottomPadding: Style.spacingM
            wrapMode: Text.WordWrap
            text: Lang.tr("This platform has no homepage of its own yet, so the tab stays hidden and the app opens on News. Build one in the CMS, or switch it on here to show the default Serey page.")
            font.pixelSize: Style.fontSmall
            font.family: Style.fontFor(text)
            color: Style.textSecondary
        }
    }
}
