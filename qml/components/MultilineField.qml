import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

/*
 * Multi-line branded text box — the FormField look (rounded cardRadius border
 * that turns brand-blue on focus) but with a wrapping, growing TextEdit. Used
 * for the profile bio. `maximumLength` caps input; `length` exposes the count.
 */
Rectangle {
    id: root

    property alias text: input.text
    property alias input: input
    property string placeholder: ""
    property int maximumLength: 0          // 0 = no limit
    readonly property int length: input.text.length

    width: parent ? parent.width : units.gu(40)
    height: Math.max(units.gu(10), input.contentHeight + Style.spacingM * 2)
    radius: Style.cardRadius
    color: Style.surface
    border.width: units.dp(1.5)
    border.color: input.activeFocus ? Style.brand : Style.divider
    Behavior on border.color { ColorAnimation { duration: 120 } }

    TextEdit {
        id: input
        anchors.fill: parent
        anchors.margins: Style.spacingM
        wrapMode: TextEdit.Wrap
        clip: true
        font.pixelSize: Style.fontRegular
        font.family: Style.fontFamily
        color: Style.textPrimary
        selectionColor: Style.brand
        selectedTextColor: Style.textOnBrand
        selectByMouse: true
        inputMethodHints: Qt.ImhNoAutoUppercase
        onTextChanged: {
            if (root.maximumLength > 0 && text.length > root.maximumLength)
                text = text.substring(0, root.maximumLength);
        }

        Label {
            anchors.fill: parent
            text: root.placeholder
            visible: input.text.length === 0 && !input.inputMethodComposing && !input.activeFocus && !Qt.inputMethod.visible
            wrapMode: Text.WordWrap
            font.pixelSize: Style.fontRegular
            font.family: Style.fontFamily
            color: Style.textSecondary
            opacity: 0.7
        }
    }

    // Match FormField: tap focuses + positions the cursor; press-and-hold pastes.
    MouseArea {
        anchors.fill: parent
        onClicked: {
            input.forceActiveFocus();
            input.cursorPosition = input.positionAt(mouse.x - input.x, mouse.y - input.y);
        }
        onPressAndHold: { input.forceActiveFocus(); input.paste(); }
    }
}
