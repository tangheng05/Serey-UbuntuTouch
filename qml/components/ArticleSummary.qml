import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"

// AI bullet summary above the article body; view only, page fires the request
Item {
    id: root

    property var bullets: []
    property int readMinutes: 0
    property bool loading: false
    property bool expanded: false
    // Why the drawer is empty; blank means the request simply came back with nothing.
    property string error: ""

    signal retryRequested()
    // The page fetches on first expand, so the request is only spent on readers who ask for it
    signal summaryNeeded()

    onExpandedChanged: {
        if (root.expanded && !root.loading && root.bullets.length === 0 && root.error === "")
            root.summaryNeeded();
    }

    // Shown as soon as reading time is known locally; bullets drop in when they arrive
    visible: readMinutes > 0
    height: visible ? box.height : 0

    Rectangle {
        id: box
        width: parent.width
        height: header.height + body.height + Style.spacingS * 2
        radius: Style.cardRadius
        // Tinted panel, not a card: it belongs to the article, not beside it.
        color: Style.dark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0.51, 0.98, 0.05)
        // No Behavior here on purpose: box.height follows body.height, which is already
        // animating. Easing both made the panel chase its own drawer and stutter.

        AbstractButton {
            id: header
            anchors {
                left: parent.left; right: parent.right; top: parent.top
                leftMargin: Style.spacingS; rightMargin: Style.spacingS
                topMargin: Style.spacingS
            }
            height: units.gu(3)
            onClicked: root.expanded = !root.expanded

            // Bounded by the toggle, not free-floating: a long translation used to run
            // straight under "Inklappen" on a phone.
            Row {
                id: metaRow
                anchors { left: parent.left; right: toggleRow.left; rightMargin: Style.spacingS
                          verticalCenter: parent.verticalCenter }
                spacing: Style.spacingXs

                Icon {
                    id: clockIcon
                    anchors.verticalCenter: parent.verticalCenter
                    width: units.gu(1.8); height: width
                    name: "clock"
                    color: Style.brand
                }
                // Fixed phrase: promises how long the SUMMARY takes, not the article
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    // The phrase yields first; the reading time is short and worth keeping whole.
                    width: Math.max(0, metaRow.width - clockIcon.width - metaRow.spacing
                                       - (readLabel.visible ? readLabel.implicitWidth + metaRow.spacing : 0))
                    elide: Text.ElideRight
                    text: Lang.tr("This article in one minute")
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
                    color: Style.brand
                }
                Label {
                    id: readLabel
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
                id: toggleRow
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

        // Clipped drawer: delegates stay alive so expanding mid-generation doesn't rebuild rows
        Item {
            id: body
            anchors {
                left: parent.left; right: parent.right; top: header.bottom
                leftMargin: Style.spacingS; rightMargin: Style.spacingS
            }
            height: root.expanded ? content.height + Style.spacingS : 0
            clip: true
            opacity: root.expanded ? 1 : 0
            // The single height animation in the component: opening, and the regrow when
            // bullets replace the spinner, both run through this one curve.
            Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 140 } }

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

                // Zero bullets used to expand into an empty box, which reads as broken.
                Column {
                    width: parent.width
                    visible: !root.loading && root.bullets.length === 0
                    spacing: Style.spacingXs
                    // Created up front, so fade on becoming visible rather than on creation
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }

                    Label {
                        width: parent.width
                        text: root.error !== "" ? root.error
                                                : Lang.tr("No summary for this article.")
                        font.pixelSize: Style.fontSmall
                        font.family: Style.fontFor(text)
                        color: Style.textSecondary
                        wrapMode: Text.WordWrap
                    }

                    AbstractButton {
                        visible: root.error !== ""
                        width: retryLabel.implicitWidth
                        height: units.gu(3)
                        onClicked: root.retryRequested()
                        Label {
                            id: retryLabel
                            anchors.verticalCenter: parent.verticalCenter
                            text: Lang.tr("Try again")
                            font.pixelSize: Style.fontSmall
                            font.weight: Font.DemiBold
                            color: Style.brand
                        }
                    }
                }

                Repeater {
                    model: root.bullets

                    delegate: Row {
                        width: content.width
                        spacing: Style.spacingS

                        // Bullets replace the spinner in one frame; fading them in line by
                        // line covers that cut while the drawer is still growing.
                        opacity: 0
                        SequentialAnimation on opacity {
                            PauseAnimation { duration: index * 60 }
                            NumberAnimation { from: 0; to: 1; duration: 200; easing.type: Easing.OutQuad }
                        }

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
