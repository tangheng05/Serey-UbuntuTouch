import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

Rectangle {
    id: appHeader

    property string communityName: Config.currentCommunityName
    default property alias trailing: trailingSlot.data
    property alias center: centerSlot.data
    // Bigger touch targets on desktop/tablet
    property bool wide: false

    signal communityButtonClicked()

    height: units.gu(6)
    color: Style.surface

    // Left: community selector, a flag chip with a caret; flat by default, soft pill on press for touch feedback.
    AbstractButton {
        id: titleBtn
        anchors {
            left: parent.left
            leftMargin: Style.spacingM
            verticalCenter: parent.verticalCenter
        }
        width: titleRow.width
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
                // match the "My feed" logo size
                width: appHeader.wide ? units.gu(4.5) : units.gu(3.5)
                height: width

                CircleImage {
                    id: cIcon
                    anchors.fill: parent
                    source: Config.currentCommunityIconUrl
                }
                Icon {
                    anchors.centerIn: parent
                    width: appHeader.wide ? units.gu(4) : units.gu(3); height: width
                    name: "language-chooser"
                    color: Style.textSecondary
                    visible: !cIcon.loaded
                }
                // Hairline ring so a light-edged flag (e.g. the Dutch white stripe) doesn't bleed into the white header.
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: units.dp(1)
                    border.color: Style.divider
                }
            }

            // Community name, shown beside the flag on wide windows only;
            // phones keep the compact icon-only chip.
            Label {
                anchors.verticalCenter: parent.verticalCenter
                visible: appHeader.wide && text !== ""
                text: appHeader.communityName
                font.pixelSize: Style.fontMedium
                font.weight: Font.DemiBold
                font.family: Style.fontFor(text)   // community names may be Khmer
                color: Style.textPrimary
                elide: Text.ElideRight
                width: Math.min(implicitWidth, units.gu(24))
            }

            // Real vector caret; the old text-glyph caret rendered chunky and off-baseline.
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: appHeader.wide ? units.gu(2) : units.gu(1.5); height: width
                name: "down"
                color: Style.textSecondary
            }
        }

        KeyTapArea { onActivated: titleBtn.clicked() }
    }

    // Center action slot uses a fixed width (not childrenRect) since a child anchored via centerIn would otherwise create a width binding loop.
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

    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: units.dp(1)
        color: Style.divider
    }
}
