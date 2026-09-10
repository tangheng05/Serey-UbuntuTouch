import QtQuick 2.7
import QtGraphicalEffects 1.0
import Lomiri.Components 1.3
import "../Theme"

// Rounded card thumbnail. `loader` fetches off-screen so `shown` can hold the
// last good frame across a delegate recycle, and a failed fetch is retried:
// Qt caches the failure, so one hiccup left the card blank until app restart.
Item {
    id: root

    property string source: ""
    property real radius: Style.thumbRadius
    property int decodeWidth: units.gu(45)
    property bool autoTransform: false      // honour EXIF orientation

    readonly property int _maxRetries: 3
    property int _attempt: 0
    // Retry needs a new URL string or Qt hands back the cached failure.
    readonly property string _url: {
        if (source.length === 0 || _attempt === 0) return source;
        if (source.indexOf("http") !== 0) return source;    // local file: nothing to re-fetch
        return source + (source.indexOf("?") >= 0 ? "&" : "?") + "retry=" + _attempt;
    }
    onSourceChanged: root._attempt = 0

    function _sync() {
        if (loader.status === Image.Ready) {
            shown.source = loader.source;
            retryTimer.stop();
        } else if (loader.status === Image.Error) {
            shown.source = "";      // don't keep showing the previous card's image
            if (root._attempt < root._maxRetries) retryTimer.restart();
        } else if (String(loader.source).length === 0) {
            shown.source = "";
        }
    }

    Timer {
        id: retryTimer
        interval: 3000 * (root._attempt + 1)
        onTriggered: root._attempt++
    }

    // Back online is the likeliest reason a retry will now succeed; don't wait out the timer.
    Connections {
        target: Net
        function onOnlineChanged() {
            if (Net.online && loader.status === Image.Error && root._attempt < root._maxRetries) {
                retryTimer.stop();
                root._attempt++;
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Style.iconBackground
    }

    Image {
        id: loader
        anchors.fill: parent
        source: root._url
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        autoTransform: root.autoTransform
        // Snap the decode size to a breakpoint instead of tracking width, which re-rasterized on every resize.
        sourceSize.width: root.decodeWidth
        visible: false
        onStatusChanged: root._sync()
        // A cached image goes Ready inside the assignment, with no status change
        // to react to, so re-check once the load has been kicked off.
        onSourceChanged: Qt.callLater(root._sync)
    }

    Image {
        id: shown
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        autoTransform: root.autoTransform
        sourceSize.width: loader.sourceSize.width
        visible: false
        // Fade the stale frame fully out; a dimmed ghost read as the wrong thumbnail
        readonly property bool transitioning: loader.status === Image.Loading && status === Image.Ready
        Behavior on opacity { NumberAnimation { duration: 200 } }
        opacity: status === Image.Ready ? (transitioning ? 0.0 : 1.0) : 0.0
    }

    // Rectangle.clip only clips to the bounding box, so mask against a rounded Rectangle for a true rounded crop.
    Rectangle {
        id: thumbMask
        anchors.fill: parent
        radius: root.radius
        visible: false
    }

    OpacityMask {
        anchors.fill: parent
        source: shown
        maskSource: thumbMask
        opacity: shown.opacity
    }
}
