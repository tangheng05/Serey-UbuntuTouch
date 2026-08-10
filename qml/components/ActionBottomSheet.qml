import QtQuick 2.7
import QtGraphicalEffects 1.0
import Lomiri.Components 1.3
import "../Theme"

// Lightweight page-local action sheet; for full post options use PostActionSheet instead
Item {
    id: sheet
    anchors.fill: parent
    z: 1500
    visible: _open

    property bool _open: false
    property var model: []

    // Desktop anchors a dropdown under the "..." button; touch keeps the bottom sheet.
    property Item anchorItem: null
    readonly property bool asDropdown: Config.desktopMode && !!anchorItem
    readonly property real dropWidth: units.gu(32)
    property real _dropX: 0
    property real _dropY: 0

    function show(items, anchor) {
        sheet.model = items || [];
        sheet.anchorItem = anchor || null;
        sheet._open = true;
        // mapToItem can't be a live binding, so resolve the anchor at open time.
        if (sheet.asDropdown) {
            var p = sheet.anchorItem.mapToItem(sheet, 0, sheet.anchorItem.height);
            sheet._dropX = Math.max(Style.spacingS,
                                    Math.min(p.x - sheet.dropWidth + sheet.anchorItem.width,
                                             sheet.width - sheet.dropWidth - Style.spacingS));
            sheet._dropY = p.y + Style.spacingXs;
        }
        // A prior sheet-mode close leaves sheetTranslate.y at its slide-out offset (sheetDropIn
        // never touches it), so a dropdown-mode open right after would render the panel pushed way down.
        sheetTranslate.y = 0;
        backdropFade.start();
        if (sheet.asDropdown) sheetDropIn.start(); else sheetSlide.start();
        sheet.forceActiveFocus();
    }
    function hide() {
        backdropFadeOut.start();
        if (sheet.asDropdown) sheetDropOut.start(); else sheetSlideOut.start();
    }
    Keys.onEscapePressed: sheet.hide()

    Rectangle {
        id: backdrop
        anchors.fill: parent
        // A dropdown doesn't dim the page; the backdrop stays only to catch the click-outside.
        color: sheet.asDropdown ? "transparent" : Qt.rgba(0, 0, 0, 0.4)
        opacity: 0
        MouseArea { anchors.fill: parent; onClicked: sheet.hide() }
    }
    NumberAnimation { id: backdropFade; target: backdrop; property: "opacity"; from: 0; to: 1; duration: 200 }
    NumberAnimation { id: backdropFadeOut; target: backdrop; property: "opacity"; to: 0; duration: 200 }

    // Soft elevation so the dropdown reads as floating above the page (the full-width
    // sheet already sits on a dimmed backdrop and doesn't need it).
    DropShadow {
        anchors.fill: sheetRect
        visible: sheet.asDropdown && sheetRect.opacity > 0
        source: sheetRect
        radius: 16
        samples: 33
        horizontalOffset: 0
        verticalOffset: 6
        color: Qt.rgba(0, 0, 0, 0.22)
        transparentBorder: true
        cached: true
    }

    Rectangle {
        id: sheetRect
        readonly property bool wide: Config.wideMode
        // x/y rather than anchors: anchors can't be conditionally unset from a ternary,
        // and the dropdown and sheet modes place the panel very differently.
        x: sheet.asDropdown ? sheet._dropX : (parent.width - width) / 2
        y: sheet.asDropdown ? sheet._dropY
                            : parent.height - height - (sheetRect.wide ? units.gu(4) : 0)
        width: sheet.asDropdown ? sheet.dropWidth
             : sheetRect.wide ? Math.min(parent.width - units.gu(4), units.gu(45)) : parent.width
        height: sheet.asDropdown ? col.height + units.gu(1) : col.height + units.gu(3)
        radius: sheet.asDropdown ? Style.cardRadius : units.dp(16)
        color: Style.surface
        border.width: sheet.asDropdown ? units.dp(1) : 0
        border.color: Style.divider
        clip: true
        transformOrigin: Item.TopRight

        transform: Translate { id: sheetTranslate; y: 0 }
        NumberAnimation { id: sheetSlide; target: sheetTranslate; property: "y"; from: sheetRect.height + units.gu(4); to: 0; duration: 300; easing.type: Easing.OutCubic }
        NumberAnimation { id: sheetSlideOut; target: sheetTranslate; property: "y"; to: sheetRect.height + units.gu(4); duration: 250; easing.type: Easing.InCubic; onStopped: sheet._open = false }

        // Dropdowns snap open from their anchor; a 300ms slide would feel slow.
        ParallelAnimation {
            id: sheetDropIn
            NumberAnimation { target: sheetRect; property: "opacity"; from: 0; to: 1; duration: 120; easing.type: Easing.OutQuad }
            NumberAnimation { target: sheetRect; property: "scale";   from: 0.97; to: 1; duration: 120; easing.type: Easing.OutQuad }
        }
        SequentialAnimation {
            id: sheetDropOut
            NumberAnimation { target: sheetRect; property: "opacity"; to: 0; duration: 100; easing.type: Easing.InQuad }
            ScriptAction { script: sheet._open = false }
        }

        Rectangle {
            visible: !sheet.asDropdown
            anchors { top: parent.top; topMargin: Style.spacingS; horizontalCenter: parent.horizontalCenter }
            width: units.gu(4.5)
            height: units.dp(4)
            radius: units.dp(2)
            color: Style.lightGray
        }

        Column {
            id: col
            anchors {
                top: parent.top; left: parent.left; right: parent.right
                topMargin: sheet.asDropdown ? Style.spacingXs : Style.spacingL
            }
            spacing: 0

            Repeater {
                model: sheet.model
                // Plain Item + MouseArea, not AbstractButton: matches CommunityPicker/PostActionSheet's
                // row pattern, which reliably takes taps inside this clipped, transformed dropdown.
                delegate: Item {
                    id: rowBtn
                    width: col.width
                    height: units.gu(7)
                    // Missing before: no pressed feedback meant a working click could look inert.
                    Rectangle {
                        anchors.fill: parent
                        color: rowMouse.pressed ? Style.pressed : "transparent"
                    }
                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        onClicked: {
                            sheet.hide();
                            if (modelData.onTriggered) modelData.onTriggered();
                        }
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

            Item { width: 1; height: Style.spacingM; visible: !sheet.asDropdown }
        }
    }
}
