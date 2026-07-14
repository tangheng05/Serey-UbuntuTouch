import QtQuick 2.7
import QtGraphicalEffects 1.0
import Lomiri.Components 1.3
import "../Theme"

AbstractButton {
    id: root
    property var video: ({})
    readonly property var v: video ? video : ({})
    // Off in a grid — divider is for vertical-list usage only
    property bool showDivider: true

    signal authorClicked()
    signal moreClicked()

    width: parent ? parent.width : units.gu(40)
    implicitHeight: column.height + Style.spacingM + Style.spacingS + (showDivider ? units.dp(1) : 0)
    height: implicitHeight

    Column {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: Style.spacingM
            rightMargin: Style.spacingM
            topMargin: Style.spacingM
        }
        spacing: Style.spacingS

        // Thumbnail — large rounded, no play overlay
        Item {
            width: parent.width
            height: width * 0.56

            Rectangle {
                id: thumbBg
                anchors.fill: parent
                radius: Style.thumbRadius
                color: Style.iconBackground
            }

            Image {
                id: thumbImg
                anchors.fill: parent
                source: v.localThumb || v.thumbnail || ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                // HIG scaling: snap the decode size to a breakpoint instead of `width * N` so the image isn't re-rasterized on every width change.
                sourceSize.width: root.width > units.gu(70) ? units.gu(90) : units.gu(45)
                visible: false
                Behavior on opacity { NumberAnimation { duration: 200 } }
                opacity: status === Image.Ready ? 1.0 : 0.0
            }

            Rectangle {
                id: thumbMask
                anchors.fill: parent
                radius: Style.thumbRadius
                visible: false
            }

            OpacityMask {
                anchors.fill: parent
                source: thumbImg
                maskSource: thumbMask
                opacity: thumbImg.opacity
            }
        }

        // Info: avatar + title/author + "•••" button
        Row {
            width: parent.width
            spacing: Style.spacingS

            Item {
                width: units.gu(4.5); height: width
                anchors.top: parent.top

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Style.avatarTint(v.author || "")
                    visible: (v.authorImage || "") === ""

                    Label {
                        anchors.centerIn: parent
                        text: (v.author || "?").charAt(0).toUpperCase()
                        font.pixelSize: Style.fontMedium
                        font.bold: true
                        color: Style.brand
                    }
                }

                CircleImage {
                    anchors.fill: parent
                    source: v.authorImage || ""
                    decode: units.gu(9)
                    visible: (v.authorImage || "") !== ""
                }

                MouseArea { anchors.fill: parent; onClicked: root.authorClicked() }
            }

            Column {
                width: parent.width - units.gu(4.5) - Style.spacingS - moreBtn.width - Style.spacingS
                spacing: units.dp(2)

                Label {
                    width: parent.width
                    text: v.title || ""
                    font.pixelSize: Style.fontRegular
                    font.weight: Font.DemiBold
                    font.family: Style.fontFor(text)
                    color: Style.textPrimary
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
                Label {
                    width: parent.width
                    text: v.author || ""
                    font.pixelSize: Style.fontSmall
                    color: Style.textSecondary
                    elide: Text.ElideRight
                }
                OffChainBadge {
                    onChain: v.postToBlockchain !== false
                }
            }

            AbstractButton {
                id: moreBtn
                anchors.top: parent.top
                width: units.gu(3.5); height: units.gu(3.5)
                onClicked: root.moreClicked()

                Column {
                    anchors.centerIn: parent
                    spacing: units.dp(3)
                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            width: units.dp(4); height: units.dp(4)
                            radius: width / 2
                            color: Style.textSecondary
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }
            }
        }
    }

    // Divider between cards
    Rectangle {
        visible: root.showDivider
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: units.dp(1)
        color: Style.divider
    }

    // Pointer/keyboard parity: right-click or the MENU key opens the same
    // context actions as swipe / the ••• overflow (see ContextActionArea).
    ContextActionArea { onTriggered: root.moreClicked() }
}
