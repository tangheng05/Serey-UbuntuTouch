import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

Item {
    id: root
    property string message: ""
    // Number of skeleton "cards" to render — 3 for a feed, 1 for a detail page.
    property int count: 3
    // "post" | "gallery" | "video" — picks the card shape to imitate.
    property string variant: "post"
    // Detail pages (PostDetailPage, GalleryDetailPage) show one full-bleed cover.
    property bool fullBleedCover: false

    readonly property real inset: Style.spacingM
    readonly property real contentWidth: root.width - inset * 2
    // dark variant needed; light value glows on dark surface
    readonly property color coverTone: Style.dark ? "#333333" : "#ECECEC"
    readonly property string photoGlyph: "image-x-generic-symbolic"

    // Opaque card surface so the skeleton always reads cleanly on its own.
    Rectangle { anchors.fill: parent; color: Style.surface }

    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 0

        Repeater {
            // gated on visibility so pulse animations stop off-screen
            model: root.visible ? root.count : 0
            delegate: Column {
                width: root.width
                spacing: Style.spacingS

                Item { width: 1; height: Style.spacingM }

                // --- Video: thumbnail leads (inset 16:9) ---------------------
                SkeletonRect {
                    visible: root.variant === "video" && !root.fullBleedCover
                    x: root.inset
                    width: root.contentWidth
                    height: width * 0.56
                    radius: Style.thumbRadius
                    baseColor: root.coverTone
                    glyph: root.photoGlyph
                }

                // --- Header: avatar + name/time (post, gallery, detail) ------
                Row {
                    visible: root.variant !== "video" || root.fullBleedCover
                    x: root.inset
                    spacing: Style.spacingS
                    SkeletonRect { width: units.gu(4.25); height: width; radius: width / 2 }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.spacingXs
                        SkeletonRect { width: units.gu(17); height: units.gu(1.6); radius: height / 2 }
                        SkeletonRect { width: units.gu(9); height: units.gu(1.2); radius: height / 2 }
                    }
                }

                // --- Title lines (post only — two uneven lines) --------------
                Column {
                    visible: root.variant === "post" && !root.fullBleedCover
                    x: root.inset
                    spacing: Style.spacingXs
                    SkeletonRect { width: root.contentWidth; height: units.gu(1.9); radius: height / 2 }
                    SkeletonRect { width: root.contentWidth * 0.55; height: units.gu(1.9); radius: height / 2 }
                }

                // --- Post cover (inset 16:9) ---------------------------------
                SkeletonRect {
                    visible: root.variant === "post" && !root.fullBleedCover
                    x: root.inset
                    width: root.contentWidth
                    height: width * 0.56
                    radius: Style.thumbRadius
                    baseColor: root.coverTone
                    glyph: root.photoGlyph
                }

                // --- Gallery photo (full-bleed square) -----------------------
                SkeletonRect {
                    visible: root.variant === "gallery" && !root.fullBleedCover
                    width: root.width
                    height: width
                    radius: 0
                    baseColor: root.coverTone
                    glyph: root.photoGlyph
                }

                // --- Detail cover (full-bleed square) ------------------------
                SkeletonRect {
                    visible: root.fullBleedCover
                    width: root.width
                    height: width
                    radius: 0
                    baseColor: root.coverTone
                    glyph: root.photoGlyph
                }

                // --- Video info: avatar + two title lines (after thumbnail) --
                Row {
                    visible: root.variant === "video" && !root.fullBleedCover
                    x: root.inset
                    spacing: Style.spacingS
                    SkeletonRect { width: units.gu(4.5); height: width; radius: width / 2 }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.spacingXs
                        SkeletonRect { width: root.contentWidth * 0.8; height: units.gu(1.7); radius: height / 2 }
                        SkeletonRect { width: units.gu(12); height: units.gu(1.3); radius: height / 2 }
                    }
                }

                // --- Action chips: mirrors the VoteBar's left icon+count row -
                Row {
                    visible: root.variant !== "video"
                    x: root.inset
                    spacing: Style.spacingM
                    SkeletonRect { width: units.gu(5); height: units.gu(2); radius: height / 2 }
                    SkeletonRect { width: units.gu(3); height: units.gu(2); radius: height / 2 }
                    SkeletonRect { width: units.gu(5); height: units.gu(2); radius: height / 2 }
                }

                Item { width: 1; height: Style.spacingS }
                Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }
            }
        }
    }
}
