import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

/*
 * Global top bar, Lomiri-style: a flat surface with a LEFT-ALIGNED title that
 * doubles as the community selector (icon + name + caret), an optional trailing
 * action slot on the right, and a bottom hairline. This replaces the previous
 * centered-logo + gray-pill (iOS-ish) header — Lomiri headers put the title on
 * the left and never center an app logo.
 *
 * Public API unchanged: `communityName`, the `trailing` default slot, and the
 * `communityButtonClicked()` signal, so Main.qml is unaffected.
 */
Rectangle {
    id: appHeader

    property string communityName: Config.currentCommunityName
    default property alias trailing: trailingSlot.data

    signal communityButtonClicked()

    height: units.gu(6)
    color: Style.surface

    // Left: title acts as the community selector (Lomiri "title with dropdown").
    AbstractButton {
        id: titleBtn
        anchors {
            left: parent.left
            leftMargin: Style.spacingM
            right: trailingSlot.left
            rightMargin: Style.spacingS
            verticalCenter: parent.verticalCenter
        }
        height: units.gu(5)
        onClicked: appHeader.communityButtonClicked()

        Row {
            id: titleRow
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            spacing: Style.spacingXs

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: units.gu(2.8); height: width
                CircleImage {
                    id: cIcon
                    anchors.fill: parent
                    source: Config.currentCommunityIconUrl
                }
                Icon {
                    anchors.centerIn: parent
                    width: units.gu(2.4); height: width
                    name: "language-chooser"
                    color: Style.textSecondary
                    visible: !cIcon.loaded
                }
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, titleRow.width - units.gu(5))
                text: appHeader.communityName
                font.pixelSize: Style.fontTitle
                font.weight: Font.Normal
                font.family: Style.fontFor(text)
                color: Style.textPrimary
                elide: Text.ElideRight
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: "▾"
                font.pixelSize: Style.fontMedium
                color: Style.textSecondary
            }
        }
    }

    // Right: trailing action slot (e.g. the feed shortcut from Main.qml).
    Item {
        id: trailingSlot
        anchors {
            right: parent.right
            rightMargin: Style.spacingM
            verticalCenter: parent.verticalCenter
        }
        width: childrenRect.width
        height: parent.height
    }

    // Bottom hairline
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: units.dp(1)
        color: Style.divider
    }
}
