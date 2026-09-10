import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

// Makes tap-only chrome a Tab stop: Enter/Space fires activated(), brand ring shows on focus
Item {
    id: area
    anchors.fill: parent
    activeFocusOnTab: true

    signal activated()
    // Optional arrow-key hooks so hosts can wire spatial movement
    signal leftPressed()
    signal rightPressed()
    signal upPressed()
    signal downPressed()
    // Hosts with their own focus visual turn the generic ring off to avoid clashing
    property bool showRing: true

    // Activate on key RELEASE, not press: press-driven focus moves caused wrong-item release
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

    // Same ring as ContextActionArea/PostActionSheet; touch/pointer users never see it
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
