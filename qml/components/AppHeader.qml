import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

/*
 * Global top bar, Lomiri-style: a flat surface with a LEFT-ALIGNED button that
 * doubles as the community selector (icon + caret only, no name), an optional
 * trailing action slot on the right, and a bottom hairline. This replaces the
 * previous centered-logo + gray-pill (iOS-ish) header — Lomiri headers put the
 * title on the left and never center an app logo.
 *
 * Public API: `communityName`, the `trailing` default slot (right side), the
 * `center` slot (horizontally centered, e.g. the "My feed" shortcut), and the
 * `communityButtonClicked()` signal.
 */
Rectangle {
    id: appHeader

    property string communityName: Config.currentCommunityName
    default property alias trailing: trailingSlot.data
    property alias center: centerSlot.data

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
                text: "▾"
                font.pixelSize: Style.fontMedium
                color: Style.textSecondary
            }
        }
    }

    // Center: horizontally centered action slot (e.g. the "My feed" shortcut).
    // Fixed width (not childrenRect-based) — a child anchored via centerIn to
    // this Item would otherwise create a width binding loop.
    Item {
        id: centerSlot
        anchors {
            horizontalCenter: parent.horizontalCenter
            verticalCenter: parent.verticalCenter
        }
        width: units.gu(4)
        height: parent.height
    }

    // Right: trailing action slot (e.g. the compose/upload shortcut from Main.qml).
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
