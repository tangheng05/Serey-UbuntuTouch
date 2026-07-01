import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

/*
 * Masked-retype email input, matching the web's reset-password ContactInput:
 * the backend reveals only the suffix (e.g. "*******oat@gmail.com"), and the
 * user fills the hidden front. The dots show how many characters are still
 * expected; `value` is the reconstructed full email (typed + visible suffix +
 * "@" + domain), which the backend then verifies against the account.
 */
Rectangle {
    id: root

    // Masked hint from the API, e.g. "*******oat@gmail.com".
    property string maskedEmail: ""
    property alias input: hidden
    signal accepted()

    readonly property int _at: maskedEmail.indexOf("@")
    readonly property string domain: _at >= 0 ? maskedEmail.substring(_at + 1) : ""
    readonly property string _local: _at >= 0 ? maskedEmail.substring(0, _at) : maskedEmail
    readonly property int _lastStar: _local.lastIndexOf("*")
    readonly property string visibleSuffix: _lastStar >= 0 ? _local.substring(_lastStar + 1) : _local
    readonly property int starCount: (_local.match(/\*/g) || []).length
    // Full email = what the user typed + the revealed suffix + domain.
    readonly property string value: hidden.text + visibleSuffix + (domain.length ? "@" + domain : "")
    readonly property bool complete: hidden.text.length >= starCount
    readonly property string _dots: {
        var n = starCount - hidden.text.length;
        return n > 0 ? Array(n + 1).join("•") : "";
    }

    width: parent ? parent.width : units.gu(40)
    height: units.gu(6)
    radius: Style.cardRadius
    color: Style.surface
    border.width: units.dp(1.5)
    border.color: hidden.activeFocus ? Style.brand : Style.divider
    Behavior on border.color { ColorAnimation { duration: 120 } }

    // Visible composed display: typed chars, remaining dots, then the revealed
    // suffix and domain. Sits behind the transparent input.
    Row {
        anchors {
            left: parent.left; leftMargin: Style.spacingM
            right: parent.right; rightMargin: Style.spacingM
            verticalCenter: parent.verticalCenter
        }
        spacing: 0
        clip: true
        Label { text: hidden.text;          font.pixelSize: Style.fontRegular; font.family: Style.fontFor(text); color: Style.textPrimary }
        Label { text: root._dots;           font.pixelSize: Style.fontRegular; font.family: Style.fontFor(text); color: Style.dotInactive }
        Label { text: root.visibleSuffix;   font.pixelSize: Style.fontRegular; font.family: Style.fontFor(text); color: Style.textPrimary }
        Label { text: root.domain.length ? "@" + root.domain : ""; font.pixelSize: Style.fontRegular; font.family: Style.fontFor(text); color: Style.textSecondary }
    }

    // Transparent capture field on top (its own glyphs are invisible; the Row
    // shows the composed value). A custom caret keeps the cursor visible.
    TextInput {
        id: hidden
        anchors {
            left: parent.left; leftMargin: Style.spacingM
            right: parent.right; rightMargin: Style.spacingM
            verticalCenter: parent.verticalCenter
        }
        color: "transparent"
        font.pixelSize: Style.fontRegular
        font.family: Style.fontFor(text)
        maximumLength: root.starCount
        inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
        onAccepted: root.accepted()
        cursorDelegate: Rectangle {
            width: units.dp(2)
            color: Style.brand
            visible: hidden.activeFocus
        }
    }
}
