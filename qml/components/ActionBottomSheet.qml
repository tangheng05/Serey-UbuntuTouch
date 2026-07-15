import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

// Lightweight bottom sheet for a short, page-local action list (e.g. the •••
// menu on a saved/downloaded article row). Call show([{iconName, text, danger,
// onTriggered}, ...]) to slide it up; tapping a row runs onTriggered and closes.
// For a post's full options menu use PostActionSheet/PostActions instead — this
// is for pages that just need Remove/Share without the ownership logic.
Item {
    id: sheet
    anchors.fill: parent
    z: 1500
    visible: _open

    property bool _open: false
    property var model: []

    function show(items) {
        sheet.model = items || [];
        sheet._open = true;
        backdropFade.start();
        sheetSlide.start();
    }
    function hide() {
        backdropFadeOut.start();
        sheetSlideOut.start();
    }

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.4)
        opacity: 0
        MouseArea { anchors.fill: parent; onClicked: sheet.hide() }
    }
    NumberAnimation { id: backdropFade; target: backdrop; property: "opacity"; from: 0; to: 1; duration: 200 }
    NumberAnimation { id: backdropFadeOut; target: backdrop; property: "opacity"; to: 0; duration: 200 }

    Rectangle {
        id: sheetRect
        readonly property bool wide: Config.wideMode
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: sheetRect.wide ? units.gu(4) : 0
        }
        width: sheetRect.wide ? Math.min(parent.width - units.gu(4), units.gu(45)) : parent.width
        height: col.height + units.gu(3)
        radius: units.dp(16)
        color: Style.surface

        transform: Translate { id: sheetTranslate; y: 0 }
        NumberAnimation { id: sheetSlide; target: sheetTranslate; property: "y"; from: sheetRect.height + units.gu(4); to: 0; duration: 300; easing.type: Easing.OutCubic }
        NumberAnimation { id: sheetSlideOut; target: sheetTranslate; property: "y"; to: sheetRect.height + units.gu(4); duration: 250; easing.type: Easing.InCubic; onStopped: sheet._open = false }

        Rectangle {
            anchors { top: parent.top; topMargin: Style.spacingS; horizontalCenter: parent.horizontalCenter }
            width: units.gu(4.5)
            height: units.dp(4)
            radius: units.dp(2)
            color: Style.lightGray
        }

        Column {
            id: col
            anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: Style.spacingL }
            spacing: 0

            Repeater {
                model: sheet.model
                delegate: AbstractButton {
                    width: col.width
                    height: units.gu(7)
                    onClicked: {
                        sheet.hide();
                        if (modelData.onTriggered) modelData.onTriggered();
                    }
                    Row {
                        anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                        spacing: Style.spacingM
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: units.gu(2.4); height: width
                            name: modelData.iconName || ""
                            color: modelData.danger ? Style.danger : Style.textPrimary
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.text || ""
                            font.pixelSize: Style.fontMedium
                            font.weight: Font.DemiBold
                            color: modelData.danger ? Style.danger : Style.textPrimary
                        }
                    }
                }
            }

            Item { width: 1; height: Style.spacingM }
        }
    }
}
