import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

// keyboard reachability for tap-only chrome; makes host a Tab stop
Item {
    id: area
    anchors.fill: parent
    activeFocusOnTab: true

    signal activated()
    // optional arrow-key hooks for spatial movement
    signal leftPressed()
    signal rightPressed()
    signal upPressed()
    signal downPressed()
    // off for hosts with their own focus visual
    property bool showRing: true

    // fires on key release, not press; avoids double-activation on focus change
    property bool _armed: false
    function _isActivateKey(k) { return k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space; }

    Keys.onPressed: {
        if (_isActivateKey(event.key)) {
            area._armed = true;
            event.accepted = true;
        } else if (event.key === Qt.Key_Left)  { area.leftPressed();  event.accepted = true; }
        else if (event.key === Qt.Key_Right)   { area.rightPressed(); event.accepted = true; }
        else if (event.key === Qt.Key_Up)      { area.upPressed();    event.accepted = true; }
        else if (event.key === Qt.Key_Down)    { area.downPressed();  event.accepted = true; }
    }
    Keys.onReleased: {
        if (_isActivateKey(event.key) && area._armed) {
            area._armed = false;
            area.activated();
            event.accepted = true;
        }
    }

    // same ring as ContextActionArea / PostActionSheet
    Rectangle {
        anchors.fill: parent
        anchors.margins: units.dp(2)
        radius: units.dp(8)
        color: "transparent"
        border.width: units.dp(2)
        border.color: Style.brand
        visible: area.activeFocus && area.showRing
    }
}
