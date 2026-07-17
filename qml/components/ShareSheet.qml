import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Content 1.3
import "../Theme"
import "../Session"

Item {
    id: sheet
    anchors.fill: parent
    visible: Share.visible
    z: 1600

    // Keep the outgoing transfer referenced until ContentHub picks it up.
    property var activeTransfer: null

    onVisibleChanged: {
        if (visible && !Config.wideMode) { backdropFade.start(); slideIn.start(); }
    }

    function closeSheet() {
        if (Config.wideMode) { Share.close(); return; }
        backdropFadeOut.start();
        slideOut.start();
    }

    Component { id: linkItemComp; ContentItem {} }

    // ── Wide mode: compact dropdown ──────────────────────────────────────────
    Item {
        visible: Config.wideMode
        anchors.fill: parent

        // Dismiss on outside click
        MouseArea {
            anchors.fill: parent
            onClicked: Share.close()
        }

        Rectangle {
            id: dropdown
            readonly property real dropW: units.gu(26)
            // Anchors under the button that opened it; falls back to centered if none passed.
            readonly property var _anchor: Share.anchorItem
            readonly property var _anchorPos: dropdown._anchor
                ? dropdown._anchor.mapToItem(sheet, 0, dropdown._anchor.height)
                : null
            x: dropdown._anchorPos
                ? Math.max(Style.spacingM, Math.min(parent.width - dropdown.dropW - Style.spacingM,
                    dropdown._anchorPos.x + dropdown._anchor.width - dropdown.dropW))
                : (parent.width - dropdown.dropW) / 2
            y: dropdown._anchorPos
                ? dropdown._anchorPos.y + Style.spacingXs
                : (parent.height - dropdown.height) / 2
            width: dropW
            height: dropCol.height
            radius: units.dp(8)
            color: Style.surface
            border.width: units.dp(1)
            border.color: Style.divider

            // Subtle elevation: a slightly larger same-colour rect behind
            Rectangle {
                anchors { fill: parent; margins: -units.dp(1) }
                radius: parent.radius + units.dp(1)
                color: "transparent"
                border.width: units.dp(1)
                border.color: Qt.rgba(0, 0, 0, 0.06)
                z: -1
            }

            Column {
                id: dropCol
                width: parent.width

                AbstractButton {
                    width: parent.width; height: units.gu(6)
                    onClicked: {
                        var url = Share.url;
                        Share.close();
                        Clipboard.push(url);
                        Toast.success(Lang.tr("Link copied"));
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: units.dp(8)
                        color: parent.pressed ? Style.divider : "transparent"
                    }
                    Row {
                        anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                        spacing: Style.spacingM
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: units.gu(2.2); height: width
                            name: "edit-copy"
                            color: Style.textPrimary
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Lang.tr("Copy link")
                            font.pixelSize: Style.fontRegular
                            color: Style.textPrimary
                        }
                    }
                }

                Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

                AbstractButton {
                    width: parent.width; height: units.gu(6)
                    onClicked: {
                        var url = Share.url;
                        Share.close();
                        Qt.openUrlExternally(url);
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: units.dp(8)
                        color: parent.pressed ? Style.divider : "transparent"
                    }
                    Row {
                        anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                        spacing: Style.spacingM
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: units.gu(2.2); height: width
                            name: "external-link"
                            color: Style.textPrimary
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Lang.tr("Open in browser")
                            font.pixelSize: Style.fontRegular
                            color: Style.textPrimary
                        }
                    }
                }
            }
        }
    }

    // ── Narrow mode: full bottom sheet ───────────────────────────────────────
    Item {
        visible: !Config.wideMode
        anchors.fill: parent

        Rectangle {
            id: backdrop
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.4)
            opacity: 0
            MouseArea { anchors.fill: parent; onClicked: sheet.closeSheet() }
        }
        NumberAnimation { id: backdropFade; target: backdrop; property: "opacity"; from: 0; to: 1; duration: 200 }
        NumberAnimation { id: backdropFadeOut; target: backdrop; property: "opacity"; to: 0; duration: 200 }

        Rectangle {
            id: panel
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
            width: Math.min(parent.width, Config.sheetMaxWidth)
            height: Math.min(sheet.height * 0.75, units.gu(58))
            radius: units.dp(16)
            color: Style.surface

            transform: Translate { id: panelTranslate; y: 0 }
            NumberAnimation { id: slideIn; target: panelTranslate; property: "y"; from: panel.height + units.gu(4); to: 0; duration: 300; easing.type: Easing.OutCubic }
            NumberAnimation { id: slideOut; target: panelTranslate; property: "y"; to: panel.height + units.gu(4); duration: 250; easing.type: Easing.InCubic; onStopped: Share.close() }

            // Grabber
            Rectangle {
                anchors { top: parent.top; topMargin: Style.spacingS; horizontalCenter: parent.horizontalCenter }
                width: units.gu(4.5)
                height: units.dp(4)
                radius: units.dp(2)
                color: Style.lightGray
            }

            Label {
                id: shareTitle
                anchors { top: parent.top; left: parent.left; topMargin: Style.spacingL + Style.spacingS; leftMargin: Style.spacingM }
                text: Lang.tr("Share")
                font.pixelSize: Style.fontLarge
                font.weight: Font.DemiBold
                color: Style.textPrimary
            }

            // App grid host — the picker anchor-fills this plain Item.
            Item {
                id: pickerHost
                anchors { top: shareTitle.bottom; left: parent.left; right: parent.right; bottom: bottomRows.top; topMargin: Style.spacingS }
                clip: true

                ContentPeerPicker {
                    anchors.fill: parent
                    contentType: ContentType.Links
                    handler: ContentHandler.Share
                    showTitle: false
                    visible: sheet.visible && !Config.wideMode
                    onPeerSelected: {
                        var transfer = peer.request();
                        transfer.items = [ linkItemComp.createObject(sheet, { url: Share.url }) ];
                        transfer.state = ContentTransfer.Charged;
                        sheet.activeTransfer = transfer;
                        sheet.closeSheet();
                    }
                    onCancelPressed: sheet.closeSheet()
                }
            }

            Column {
                id: bottomRows
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: Style.spacingM }
                spacing: 0

                Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

                // Copy link
                AbstractButton {
                    width: parent.width; height: units.gu(7)
                    onClicked: {
                        Clipboard.push(Share.url);
                        sheet.closeSheet();
                        Toast.success(Lang.tr("Link copied"));
                    }
                    Row {
                        anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                        spacing: Style.spacingM
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: units.gu(2.8); height: width
                            name: "edit-copy"
                            color: Style.textPrimary
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Lang.tr("Copy link")
                            font.pixelSize: Style.fontMedium
                            color: Style.textPrimary
                        }
                    }
                }

                Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

                // Open in browser
                AbstractButton {
                    width: parent.width; height: units.gu(7)
                    onClicked: {
                        sheet.closeSheet();
                        Qt.openUrlExternally(Share.url);
                    }
                    Row {
                        anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                        spacing: Style.spacingM
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: units.gu(2.8); height: width
                            name: "external-link"
                            color: Style.textPrimary
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Lang.tr("Open in browser")
                            font.pixelSize: Style.fontMedium
                            color: Style.textPrimary
                        }
                    }
                }
            }
        }
    }
}
