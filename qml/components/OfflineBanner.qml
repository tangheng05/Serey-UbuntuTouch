import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"

// App-wide strip under the header while the phone has no network. Collapses to zero
// height when online, so pages can just anchor below it instead of switching anchors.
Item {
    id: root

    // Set by the shell on screens that already say it themselves (the Homepage offline
    // panel, the library itself), so the same message isn't stacked twice.
    property bool suppressed: false

    readonly property bool offline: !Net.online && !suppressed
    readonly property bool hasLibrary: SavedPosts.items.length + Downloads.items.length > 0

    signal openLibrary()

    visible: offline
    height: offline ? units.gu(4.5) : 0
    Behavior on height { NumberAnimation { duration: 120 } }

    AbstractButton {
        anchors.fill: parent
        enabled: root.hasLibrary
        onClicked: root.openLibrary()

        Rectangle {
            anchors.fill: parent
            color: Style.iconBackground

            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: units.dp(1)
                color: Style.divider
            }

            Row {
                anchors {
                    left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                    leftMargin: Style.spacingM; rightMargin: Style.spacingM
                }
                spacing: Style.spacingS

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: units.gu(2); height: width
                    name: "info"
                    color: Style.textSecondary
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - units.gu(2) - parent.spacing * 2 - linkLabel.width)
                    text: Lang.tr("You're offline")
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                    elide: Text.ElideRight
                }
                Label {
                    id: linkLabel
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.hasLibrary
                    text: Lang.tr("Open your library")
                    font.pixelSize: Style.fontSmall
                    font.weight: Font.DemiBold
                    font.family: Style.fontFor(text)
                    color: Style.brand
                }
            }
        }
    }
}
