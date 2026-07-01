import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

/*
 * Branded text input matching the app's design tokens: a white field with a
 * rounded (cardRadius) hairline border that turns brand-blue on focus — the
 * same rounding/divider language as the feed cards. Used by the auth pages.
 */
Rectangle {
    id: root

    property alias text: input.text
    property alias input: input
    property alias readOnly: input.readOnly
    property string placeholder: ""
    property int echoMode: TextInput.Normal
    property int inputMethodHints: Qt.ImhNone

    signal accepted()

    width: parent ? parent.width : units.gu(40)
    height: units.gu(6)
    radius: Style.cardRadius
    color: Style.surface
    border.width: units.dp(1.5)
    border.color: input.activeFocus ? Style.brand : Style.divider
    Behavior on border.color { ColorAnimation { duration: 120 } }

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: Style.spacingM
        anchors.rightMargin: Style.spacingM
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        font.pixelSize: Style.fontRegular
        font.family: Style.fontFor(text)
        color: Style.textPrimary
        selectionColor: Style.brand
        selectedTextColor: Style.textOnBrand
        selectByMouse: true
        echoMode: root.echoMode
        inputMethodHints: root.inputMethodHints
        onAccepted: root.accepted()

        Label {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            text: root.placeholder
            // Per-field only: NOT Qt.inputMethod.visible (a global singleton that
            // would blank every other field's placeholder while any one is focused).
            visible: input.text.length === 0 && !input.inputMethodComposing && !input.activeFocus
            elide: Text.ElideRight
            font.pixelSize: Style.fontRegular
            font.family: Style.fontFor(text)
            color: Style.textSecondary
            opacity: 0.7
        }
    }

    // A raw TextInput has no native long-press copy/paste popover on touch, so
    // we add it ourselves: tap focuses and positions the cursor; press-and-hold
    // pastes into an editable field (or copies a read-only one, e.g. the saved
    // private key) — this is what lets users paste a copied key to log in.
    MouseArea {
        anchors.fill: parent
        onClicked: {
            input.forceActiveFocus();
            input.cursorPosition = input.positionAt(mouse.x - input.x, input.height / 2);
        }
        onPressAndHold: {
            input.forceActiveFocus();
            if (input.readOnly) {
                input.selectAll();
                input.copy();
            } else {
                input.paste();
            }
        }
    }
}
