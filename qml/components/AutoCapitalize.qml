import QtQuick 2.7
import "../Theme"

// Capitalizes the first letter typed into a text field, standing in for the on-screen
// keyboard's auto-shift (Maliit does not do it here, and QML cannot set its shift state).
// Only the empty -> first character step is touched, so correcting it back, or anything
// typed later, is left alone.
Item {
    id: root
    property var field: null
    property int _prevLen: 0
    visible: false
    width: 0
    height: 0

    Connections {
        target: root.field
        function onTextChanged() {
            var f = root.field;
            if (!f) return;
            var t = f.text;
            var wasEmpty = root._prevLen === 0;
            root._prevLen = t.length;
            // Word prediction commits whole words, so the first keystroke can arrive as one:
            // capitalize whatever the field holds the first time it stops being empty.
            if (!wasEmpty || t.length === 0 || f.inputMethodComposing) return;
            var up = Style.sentenceCase(t);
            if (up === t) return;
            var c = f.cursorPosition;
            f.text = up;
            f.cursorPosition = c;
        }
    }
}
