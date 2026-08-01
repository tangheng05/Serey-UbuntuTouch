import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"

// "This article in one minute": AI bullets above the article body. Collapsed by
// default so it costs one line until the reader wants it. The request is fired
// by the page (JS services are null inside components), so this is view only.
Item {
    id: root

    property var bullets: []
    property int readMinutes: 0
    property bool loading: false
    property bool expanded: false

    // Shown as soon as the reading time is known (computed locally), so the bar
    // never waits on the AI; the bullets drop in when they arrive.
    visible: readMinutes > 0
    height: visible ? box.height : 0

    Rectangle {
        id: box
        width: parent.width
        height: header.height + body.height + Style.spacingS * 2
        radius: Style.cardRadius
        // Tinted panel, not a card: it belongs to the article, not beside it.
        color: Style.dark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0.51, 0.98, 0.05)
        Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

        AbstractButton {
            id: header
            anchors {
                left: parent.left; right: parent.right; top: parent.top
                leftMargin: Style.spacingS; rightMargin: Style.spacingS
                topMargin: Style.spacingS
            }
            height: units.gu(3)
            onClicked: root.expanded = !root.expanded

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacingXs

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: units.gu(1.8); height: width
                    name: "clock"
                    color: Style.brand
                }
                // Fixed phrase: it promises how long the SUMMARY takes, not the
                // article. The article's own reading time follows it.
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Lang.tr("This article in one minute")
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
                    color: Style.brand
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.readMinutes > 0
                    text: Lang.tr("· %1 min read").arg(root.readMinutes)
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                }
            }

            // Word plus chevron: the chevron alone doesn't read as "tap me".
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: Style.spacingXs

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.expanded ? Lang.tr("Collapse") : Lang.tr("Expand")
                    font.pixelSize: Style.fontXSmall
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                }
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: units.gu(1.4); height: width
                    name: "down"
                    color: Style.textSecondary
                    rotation: root.expanded ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: 150 } }
                }
            }
        }

        // Clipped drawer: the delegates stay alive and the height animates, so
        // expanding while the bullets are still generating doesn't rebuild rows
        // underneath the animation.
        Item {
            id: body
            anchors {
                left: parent.left; right: parent.right; top: header.bottom
                leftMargin: Style.spacingS; rightMargin: Style.spacingS
            }
            height: root.expanded ? content.height + Style.spacingS : 0
            clip: true
            opacity: root.expanded ? 1 : 0
            Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
            Behavior on opacity { NumberAnimation { duration: 150 } }

            Column {
                id: content
                width: parent.width
                y: Style.spacingS
                spacing: Style.spacingS

                Row {
                    width: parent.width
                    spacing: Style.spacingS
                    visible: root.loading && root.bullets.length === 0

                    ActivityIndicator {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(2); height: width
                        running: parent.visible
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Lang.tr("Summarizing...")
                        font.pixelSize: Style.fontSmall
                        font.family: Style.fontFor(text)
                        color: Style.textSecondary
                    }
                }

                Repeater {
                    model: root.bullets

                    delegate: Row {
                        width: content.width
                        spacing: Style.spacingS

                        Rectangle {
                            y: units.gu(0.8)
                            width: units.gu(0.6); height: width; radius: width / 2
                            color: Style.brand
                        }
                        Label {
                            width: content.width - units.gu(0.6) - Style.spacingS
                            text: modelData
                            font.pixelSize: Style.fontRegular
                            font.family: Style.fontFor(text)
                            color: Style.textPrimary
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }
}
