import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

/*
 * Loading placeholder shown while a list/detail is fetching. Renders a few
 * shimmer skeleton "cards" (serey-ubutu style) rather than a bare spinner.
 */
Item {
    id: root
    property string message: ""
    // Number of skeleton "cards" to render — 3 for a feed, 1 for a detail page.
    property int count: 3
    // Detail pages (PostDetailPage, GalleryDetailPage) show one full-bleed
    // square cover, matching their real layout, instead of the feed's inset
    // ~16:9 thumbnail.
    property bool fullBleedCover: false
    property real coverAspect: fullBleedCover ? 1.0 : 0.56

    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 0

        Repeater {
            model: root.count
            delegate: Column {
                width: root.width
                spacing: Style.spacingS

                Item { width: 1; height: Style.spacingM }

                // Header: avatar + two lines
                Row {
                    x: Style.spacingM
                    spacing: Style.spacingS
                    SkeletonRect { width: units.gu(4.25); height: width; radius: width / 2 }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.spacingXs
                        SkeletonRect { width: units.gu(18); height: units.gu(1.5) }
                        SkeletonRect { width: units.gu(10); height: units.gu(1.2) }
                    }
                }

                // Cover image block
                SkeletonRect {
                    x: root.fullBleedCover ? 0 : Style.spacingM
                    width: root.fullBleedCover ? root.width : root.width - Style.spacingM * 2
                    height: width * root.coverAspect
                    radius: root.fullBleedCover ? 0 : Style.thumbRadius
                }

                // Action line
                SkeletonRect {
                    x: Style.spacingM
                    width: units.gu(22); height: units.gu(2)
                }

                Item { width: 1; height: Style.spacingS }
                Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }
            }
        }
    }
}
