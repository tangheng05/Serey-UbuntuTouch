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

    // Left: community selector — a flag chip with a caret (Lomiri "title with
    // dropdown"). Flat by default; a soft pill only surfaces on press for touch
    // feedback, so it reads as one control without permanent header chrome.
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

        // Press-state backdrop: appears only while held, hugging the flag + caret.
        Rectangle {
            anchors {
                verticalCenter: parent.verticalCenter
                left: titleRow.left
                leftMargin: -Style.spacingS
            }
            width: titleRow.width + Style.spacingS * 2
            height: units.gu(4)
            radius: height / 2
            color: Style.iconBackground
            opacity: titleBtn.pressed ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
        }

        Row {
            id: titleRow
            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
            }
            spacing: Style.spacingXs

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: units.gu(3.5); height: width   // match the "My feed" logo size

                CircleImage {
                    id: cIcon
                    anchors.fill: parent
                    source: Config.currentCommunityIconUrl
                }
                Icon {
                    anchors.centerIn: parent
                    width: units.gu(3); height: width
                    name: "language-chooser"
                    color: Style.textSecondary
                    visible: !cIcon.loaded
                }
                // Hairline ring so a light-edged flag (e.g. the Dutch white
                // stripe) stays crisp against the white header instead of bleeding.
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: units.dp(1)
                    border.color: Style.divider
                }
            }

            // Real vector caret — the old "▾" glyph rendered chunky and off-baseline.
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: units.gu(1.5); height: width
                name: "down"
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
