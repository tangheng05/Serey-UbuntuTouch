import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

// A settings-list row whose trailing slot is a form control instead of a value
// or chevron: label in the text column, control in the value column, full-width
// divider. Narrow rows stack the label above the control.
// Children are the control; give them `width: parent.width`.
Item {
    id: root

    property string label: ""
    property bool showDivider: true

    default property alias content: holder.data

    width: parent ? parent.width : units.gu(40)

    // Geometry only, so a narrow detail pane stacks even in a wide window.
    readonly property bool stacked: width < units.gu(56)
    readonly property real _labelWidth: units.gu(20)
    readonly property real _controlX: stacked ? Style.spacingM
                                              : Style.spacingM + _labelWidth + Style.spacingM
    // Fills the row in both modes. The page caps and centres the whole column,
    // so widening here doesn't produce an absurdly long field.
    readonly property real _controlWidth:
        Math.max(units.gu(12), width - _controlX - Style.spacingM)

    // Stacked rows carry two lines, so they take tighter padding to stay a
    // normal list-row height instead of eating a phone screen.
    readonly property real _padV: stacked ? Style.spacingS : Style.spacingM
    readonly property real _labelGap: Style.spacingXs

    implicitHeight: stacked
        ? _padV + lbl.height + _labelGap + holder.height + _padV
        : Math.max(units.gu(8), holder.height + Style.spacingM * 2, lbl.height + Style.spacingM * 2)
    height: implicitHeight

    Label {
        id: lbl
        x: Style.spacingM
        // Side by side, sit level with the middle of a standard gu(5) control.
        y: root.stacked ? root._padV
                        : holder.y + Math.max(0, (units.gu(5) - height) / 2)
        width: root.stacked ? root.width - Style.spacingM * 2 : root._labelWidth
        text: root.label
        wrapMode: Text.WordWrap
        font.pixelSize: Style.fontRegular
        font.family: Style.fontFor(text)
        color: Style.textSecondary
    }

    Item {
        id: holder
        x: root._controlX
        y: root.stacked ? lbl.y + lbl.height + root._labelGap : Style.spacingM
        width: root._controlWidth
        height: childrenRect.height
    }

    // Full-width hairline, matching SettingsRow.
    Rectangle {
        visible: root.showDivider
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: units.dp(1)
        color: Style.divider
    }
}
