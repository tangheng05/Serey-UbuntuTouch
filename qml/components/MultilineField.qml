import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

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
    border.width: units.dp(1)
    border.color: input.activeFocus ? Style.brand : Style.divider
    Behavior on border.color { ColorAnimation { duration: 120 } }

    TextEdit {
        id: input
        anchors.fill: parent
        anchors.margins: Style.spacingM
        wrapMode: TextEdit.Wrap
        clip: true
        font.pixelSize: Style.fontRegular
        font.family: Style.fontFor(text)
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
            // Per-field only, not Qt.inputMethod.visible, which would blank every other field's placeholder while any one is focused.
            // Stays up while focused, like Suru's own field; it only clears once there's text.
            visible: input.text.length === 0 && !input.inputMethodComposing
            wrapMode: Text.Wrap
            font.pixelSize: Style.fontRegular
            font.family: Style.fontFor(text)
            color: Style.textSecondary
            opacity: input.activeFocus ? 0.8 : 0.6
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
