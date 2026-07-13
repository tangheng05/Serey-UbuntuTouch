import QtQuick 2.7
import QtGraphicalEffects 1.0

Item {
    id: root

    property url source: ""
    // Cap the decoded resolution (px). Remote avatars/icons are large; decoding
    // them at full size into a tiny circle wastes texture memory. 0 = uncapped.
    property int decode: 0
    readonly property bool loaded: img.status === Image.Ready && String(source) !== ""

    Rectangle {
        id: mask
        anchors.fill: parent
        radius: width / 2
        visible: false
    }

    Image {
        id: img
        anchors.fill: parent
        source: root.source
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: root.decode
        sourceSize.height: root.decode
        // Honour the EXIF Orientation tag. Phone cameras store photos in the
        // sensor's landscape orientation and flag the intended rotation in EXIF;
        // Qt's Image ignores it unless autoTransform is set, so camera-captured
        // avatars would otherwise render sideways (browsers apply it for free).
        autoTransform: true
        layer.enabled: true
        layer.effect: OpacityMask { maskSource: mask }
    }
}
