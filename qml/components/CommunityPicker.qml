import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

/*
 * Bottom-sheet community/source selector. Lists the static Config.sources
 * (Global / regional). Selecting a row sets Config.sourceIndex, which the feeds
 * and videos already react to. Mounted once as a top-level overlay; toggle via
 * open() / close().
 */
Item {
    id: picker

    anchors.fill: parent
    visible: false
    z: 1500

    function open() { picker.visible = true; cpBackdropFade.start(); cpSlide.start(); }
    function close() { picker.visible = false; }
    function closeAnimated() { cpBackdropFadeOut.start(); cpSlideOut.start(); }

    // Backdrop
    Rectangle {
        id: cpBackdrop
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.4)
        opacity: 0
        MouseArea { anchors.fill: parent; onClicked: picker.closeAnimated() }
    }
    NumberAnimation { id: cpBackdropFade; target: cpBackdrop; property: "opacity"; from: 0; to: 1; duration: 200 }
    NumberAnimation { id: cpBackdropFadeOut; target: cpBackdrop; property: "opacity"; to: 0; duration: 200 }

    // Sheet
    Rectangle {
        id: sheet
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: header.height + list.contentHeight + units.gu(4)
        radius: units.dp(16)
        color: Style.surface

        transform: Translate { id: cpTranslate; y: 0 }
        NumberAnimation { id: cpSlide; target: cpTranslate; property: "y"; from: sheet.height + units.gu(4); to: 0; duration: 300; easing.type: Easing.OutCubic }
        NumberAnimation { id: cpSlideOut; target: cpTranslate; property: "y"; to: sheet.height + units.gu(4); duration: 250; easing.type: Easing.InCubic; onStopped: picker.close() }

        // Grabber
        Rectangle {
            anchors { top: parent.top; topMargin: Style.spacingS; horizontalCenter: parent.horizontalCenter }
            width: units.gu(4.5)
            height: units.dp(4)
            radius: units.dp(2)
            color: Style.lightGray
        }

        Column {
            id: header
            anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: Style.spacingL }

            Item { width: 1; height: Style.spacingS }
            Row {
                anchors { left: parent.left; right: parent.right; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                Label {
                    width: parent.width - units.gu(4)
                    text: i18n.tr("Choose community")
                    font.pixelSize: units.dp(17)
                    font.weight: Font.DemiBold
                    color: Style.textTitle
                    anchors.verticalCenter: parent.verticalCenter
                }
                AbstractButton {
                    width: units.gu(3.5); height: units.gu(3.5)
                    onClicked: picker.closeAnimated()
                    Icon {
                        anchors.centerIn: parent
                        width: units.gu(2.5); height: width
                        name: "close"; color: Style.textTitle
                    }
                }
            }
            Item { width: 1; height: Style.spacingS }
        }

        ListView {
            id: list
            anchors { top: header.bottom; left: parent.left; right: parent.right }
            height: contentHeight
            interactive: false
            model: Config.sources

            delegate: AbstractButton {
                width: list.width
                height: units.gu(6.5)
                onClicked: { Config.sourceIndex = index; picker.closeAnimated(); }

                Row {
                    anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                    spacing: Style.spacingM

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(5); height: width
                        radius: width / 2
                        color: Style.iconBackground
                        border.width: index === Config.sourceIndex ? units.dp(2) : 0
                        border.color: Style.brand

                        CircleImage {
                            id: commIcon
                            anchors.fill: parent
                            anchors.margins: units.dp(2)
                            source: Config.communityIcon(modelData.dns)
                        }
                        Icon {
                            anchors.centerIn: parent
                            width: units.gu(2.5); height: width
                            name: "language-chooser"
                            color: index === Config.sourceIndex ? Style.brand : Style.textSecondary
                            visible: !commIcon.loaded
                        }
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name
                        font.pixelSize: Style.fontMedium
                        font.weight: index === Config.sourceIndex ? Font.DemiBold : Font.Medium
                        color: index === Config.sourceIndex ? Style.brand : Style.textPrimary
                    }
                }

                Rectangle {
                    anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: units.gu(8) }
                    height: units.dp(1)
                    color: Style.divider
                    visible: index < Config.sources.length - 1
                }
            }
        }
    }
}
