import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"

Flow {
    id: root

    property string password: ""

    spacing: Style.spacingM
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
            spacing: Style.spacingXs
            Label {
                text: modelData.ok ? "✓" : "○"   // ✓ : ○
                textSize: Label.Small
                font.family: Style.fontFor(text)
                color: root.password.length === 0 ? Style.textSecondary
                                                  : modelData.ok ? Style.success : Style.danger
            }
            Label {
                text: modelData.label
                textSize: Label.Small
                font.family: Style.fontFor(text)
                color: root.password.length === 0 ? Style.textSecondary
                                                  : modelData.ok ? Style.success : Style.danger
            }
        }
    }
}
