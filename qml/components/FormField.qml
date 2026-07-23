import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

Rectangle {
    id: root

    property alias text: input.text
    property alias input: input
    property alias readOnly: input.readOnly
    property string placeholder: ""
    property int echoMode: TextInput.Normal
    property int inputMethodHints: Qt.ImhNone
    // Password fields get a show/hide eye toggle; revealed flips the live echoMode.
    readonly property bool isPasswordField: echoMode === TextInput.Password
    property bool revealed: false

    signal accepted()

    width: parent ? parent.width : units.gu(40)
    height: units.gu(6)
    radius: Style.cardRadius
    color: Style.surface
    border.width: units.dp(1.5)
    border.color: input.activeFocus ? Style.brand : Style.divider
    Behavior on border.color { ColorAnimation { duration: 120 } }

    TextField {
        id: input
        anchors.fill: parent
        anchors.leftMargin: Style.spacingM
        anchors.rightMargin: root.isPasswordField ? units.gu(5) : Style.spacingM
        // Hide the theme's own frame; the parent Rectangle is the visual.
        StyleHints {
            backgroundColor: "transparent"
            borderColor: "transparent"
            frameSpacing: 0
            color: Style.textPrimary
            selectionColor: Style.brand
            selectedTextColor: Style.textOnBrand
        }
        hasClearButton: false
        font.pixelSize: Style.fontRegular
        font.family: Style.fontFor(text)
        echoMode: root.isPasswordField && root.revealed ? TextInput.Normal : root.echoMode
        inputMethodHints: root.inputMethodHints
        onAccepted: root.accepted()
    }

    // Custom placeholder kept out of the TextField so its per-field visibility logic stays ours; TextField's own placeholderText is unused.
    Label {
        anchors {
            left: parent.left; leftMargin: Style.spacingM
            right: parent.right; rightMargin: root.isPasswordField ? units.gu(5) : Style.spacingM
            verticalCenter: parent.verticalCenter
        }
        text: root.placeholder
        visible: input.text.length === 0 && !input.activeFocus
        elide: Text.ElideRight
        font.pixelSize: Style.fontRegular
        font.family: Style.fontFor(text)
        color: Style.textSecondary
        opacity: 0.7
    }

    AbstractButton {
        visible: root.isPasswordField
        anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: Style.spacingS }
        width: units.gu(4); height: units.gu(4)
        onClicked: root.revealed = !root.revealed
        Icon {
            anchors.centerIn: parent
            width: units.gu(2.2); height: width
            name: root.revealed ? "view-off" : "view-on"
            color: Style.textSecondary
        }
    }
}
