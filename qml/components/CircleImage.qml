import QtQuick 2.7
import QtGraphicalEffects 1.0

Item {
    id: root

    property url source: ""
    // Cap the decoded resolution (px); remote avatars are large and decoding full-size into a tiny circle wastes texture memory. 0 = uncapped.
    property int decode: 0
    // PreserveAspectFit for non-square logos (wordmarks)
    property int fillMode: Image.PreserveAspectCrop
    readonly property bool loaded: img.status === Image.Ready && String(source) !== ""

    Rectangle {
        id: mask
        anchors.fill: parent
        radius: width / 2
        antialiasing: true
        visible: false
    }

    Image {
        id: img
        anchors.fill: parent
        source: root.source
        fillMode: root.fillMode
        asynchronous: true
        sourceSize.width: root.decode
        sourceSize.height: root.decode
        // Honour the EXIF Orientation tag; without autoTransform, camera-captured avatars render sideways.
        autoTransform: true
        layer.enabled: true
        layer.effect: OpacityMask { maskSource: mask }
    }
}
