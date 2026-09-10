import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"

// Rules fill in with a green tick as they're met. Unmet is neutral, never red:
// a rule you haven't reached yet isn't an error, and `○` read as a radio button.
Column {
    id: root

    property string password: ""

    spacing: units.gu(0.75)
    width: parent ? parent.width : 0

    QtObject {
        id: d
        // [label, satisfied] for each rule, recomputed as `password` changes.
        readonly property var rules: [
            { "label": Lang.tr("8–16 characters"), "ok": root.password.length >= 8 && root.password.length <= 16 },
            { "label": Lang.tr("Uppercase"),       "ok": /[A-Z]/.test(root.password) },
            { "label": Lang.tr("Lowercase"),       "ok": /[a-z]/.test(root.password) },
            { "label": Lang.tr("Number"),          "ok": /\d/.test(root.password) }
        ]
    }

    Repeater {
        model: d.rules
        delegate: Row {
            spacing: Style.spacingS

            Item {
                width: units.gu(2); height: units.gu(2)
                anchors.verticalCenter: parent.verticalCenter

                Icon {
                    anchors.centerIn: parent
                    width: units.gu(1.6); height: width
                    name: "tick"
                    color: Style.positive
                    visible: modelData.ok
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: units.gu(0.6); height: width
                    radius: width / 2
                    color: Style.textSecondary
                    opacity: 0.4
                    visible: !modelData.ok
                }
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                textSize: Label.Small
                font.family: Style.fontFor(text)
                color: modelData.ok ? Style.positive : Style.textSecondary
            }
        }
    }
}
