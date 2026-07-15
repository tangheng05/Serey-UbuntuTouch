import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

/*
 * Keyboard reachability for tap-only chrome (nav tabs, header actions):
 * drop inside any AbstractButton to make it a Tab stop — the shared brand
 * focus ring shows while it holds keyboard focus, and Enter/Space fires
 * `activated()` (wire that to the button's own clicked()). Companion to
 * ContextActionArea, which covers list rows; per the UBports HIG input
 * parity rule, no control may be touch-only.
 */
Item {
    id: area
    anchors.fill: parent
    activeFocusOnTab: true

    signal activated()
    // Optional arrow-key hooks so hosts can wire spatial movement (e.g. the
    // section strip moves focus left/right and hands Down back to its list).
    signal leftPressed()
    signal rightPressed()
    signal upPressed()
    signal downPressed()
    // Hosts with their own focus visual (e.g. SectionTabs' tinted pill) turn the
    // generic ring off — it clashed with the active-tab underline.
    property bool showRing: true

    // Activation fires on key RELEASE, not press: activating on press moved
    // focus (tab switch -> list) while Enter was still held, and the release
    // then landed on the newly focused ListItem, which treated it as its own
    // activation and opened the first article. `_armed` ensures we only act on
    // a release whose press we saw (focus can arrive mid-press from elsewhere).
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

    // Same ring as ContextActionArea / PostActionSheet, so keyboard users see
    // one consistent affordance. Touch/pointer users never see it.
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
