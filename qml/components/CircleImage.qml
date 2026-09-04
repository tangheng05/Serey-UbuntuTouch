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
        // Decode near the drawn size: uncapped, Qt scaled a 500-2560px logo straight to ~30px
        // and curved edges went to mush (flat flags survived, so only some icons looked soft).
        // 0 until the item has a size, or the first decode is 1px and flashes on re-decode.
        sourceSize.width: root.decode > 0 ? root.decode
                        : (root.width > 0 ? Math.ceil(root.width * 2) : 0)
        sourceSize.height: root.decode > 0 ? root.decode
                         : (root.height > 0 ? Math.ceil(root.height * 2) : 0)
        // Proper downsampling when the source is still much larger than the circle.
        mipmap: true
        // Honour the EXIF Orientation tag; without autoTransform, camera-captured avatars render sideways.
        autoTransform: true
        layer.enabled: true
        layer.effect: OpacityMask { maskSource: mask }
    }
}
