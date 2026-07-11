import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/VideoService.js" as VideoService

/*
 * Moderation list for the current community's videos
 * (youtube_component_route.js, /video-component). Reorder via up/down
 * buttons (up-or-down), pin/unpin and recommended/special toggles per row.
 */
Page {
    id: page

    property bool loading: false
    property string errorMsg: ""

    header: PageHeader {
        title: Lang.tr("Videos")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.pageStack.pop() }
        ]
    }

    ListModel { id: videoModel; dynamicRoles: true }

    function load() {
        page.loading = true
        page.errorMsg = ""
        videoModel.clear()
        VideoService.listVideos(Config.baseUrl, { community_id: Config.managedCommunityId }, Session.token,
            function (videos) {
                page.loading = false
                for (var i = 0; i < videos.length; i++) videoModel.append(videos[i])
            },
            function (err) {
                page.loading = false
                page.errorMsg = err.message || Lang.tr("Failed to load videos.")
            })
    }

    function move(index, direction) {
        var item = videoModel.get(index)
        VideoService.reorder(Config.baseUrl, item.id, direction, Session.token,
            function () { page.load() },
            function (err) { Toast.error(err.message || Lang.tr("Failed to reorder.")) })
    }

    function pinOrUnpin(index) {
        var item = videoModel.get(index)
        VideoService.pinOrUnpin(Config.baseUrl, item.id, Session.token,
            function () { page.load() },
            function (err) { Toast.error(err.message || Lang.tr("Failed to update.")) })
    }

    function toggleRecommended(index) {
        var item = videoModel.get(index)
        VideoService.toggleRecommended(Config.baseUrl, item.id, Session.token,
            function () { page.load() },
            function (err) { Toast.error(err.message || Lang.tr("Failed to update.")) })
    }

    function toggleSpecial(index) {
        var item = videoModel.get(index)
        VideoService.toggleSpecial(Config.baseUrl, item.id, Session.token,
            function () { page.load() },
            function (err) { Toast.error(err.message || Lang.tr("Failed to update.")) })
    }

    Component.onCompleted: page.load()

    ListView {
        id: list
        anchors { top: page.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        model: videoModel
        clip: true

        delegate: Item {
            width: list.width
            height: units.gu(14)

            Column {
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.spacingM }
                spacing: units.dp(3)
                Label {
                    text: model.title || ""
                    width: parent.width
                    elide: Text.ElideRight
                    font.pixelSize: Style.fontRegular
                    font.weight: Font.DemiBold
                    font.family: Style.fontFor(text)
                    color: Style.textPrimary
                }
                Label {
                    text: "@" + (model.author || "")
                    width: parent.width
                    elide: Text.ElideRight
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                }
            }

            Row {
                anchors { left: parent.left; leftMargin: Style.spacingM; bottom: parent.bottom; bottomMargin: Style.spacingS }
                spacing: Style.spacingM

                AbstractButton {
                    width: units.gu(3.5); height: units.gu(3.5)
                    onClicked: page.move(index, "up")
                    Icon { anchors.centerIn: parent; width: units.gu(2); height: width; name: "up"; color: Style.textSecondary }
                }
                AbstractButton {
                    width: units.gu(3.5); height: units.gu(3.5)
                    onClicked: page.move(index, "down")
                    Icon { anchors.centerIn: parent; width: units.gu(2); height: width; name: "down"; color: Style.textSecondary }
                }
                AbstractButton {
                    width: units.gu(3.5); height: units.gu(3.5)
                    onClicked: page.pinOrUnpin(index)
                    Icon { anchors.centerIn: parent; width: units.gu(2); height: width; name: "stock_lock"; color: Style.textSecondary }
                    Label {
                        anchors { top: parent.bottom; horizontalCenter: parent.horizontalCenter }
                        text: Lang.tr("Pin")
                        font.pixelSize: Style.fontXSmall
                        font.family: Style.fontFor(text)
                        color: Style.textSecondary
                    }
                }
                AbstractButton {
                    width: units.gu(3.5); height: units.gu(3.5)
                    onClicked: page.toggleRecommended(index)
                    Icon { anchors.centerIn: parent; width: units.gu(2); height: width; name: "starred"; color: Style.textSecondary }
                    Label {
                        anchors { top: parent.bottom; horizontalCenter: parent.horizontalCenter }
                        text: Lang.tr("Recommend")
                        font.pixelSize: Style.fontXSmall
                        font.family: Style.fontFor(text)
                        color: Style.textSecondary
                    }
                }
                AbstractButton {
                    width: units.gu(3.5); height: units.gu(3.5)
                    onClicked: page.toggleSpecial(index)
                    Icon { anchors.centerIn: parent; width: units.gu(2); height: width; name: "tag"; color: Style.textSecondary }
                    Label {
                        anchors { top: parent.bottom; horizontalCenter: parent.horizontalCenter }
                        text: Lang.tr("Special")
                        font.pixelSize: Style.fontXSmall
                        font.family: Style.fontFor(text)
                        color: Style.textSecondary
                    }
                }
            }

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: units.dp(1)
                color: Style.divider
            }
        }
    }

    ActivityIndicator {
        anchors.centerIn: parent
        running: page.loading
        visible: running
    }

    EmptyState {
        anchors { top: page.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: !page.loading && page.errorMsg === "" && videoModel.count === 0
        iconName: "camcorder"
        message: Lang.tr("No videos yet")
    }

    ErrorState {
        anchors { top: page.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: page.errorMsg !== "" && videoModel.count === 0
        message: page.errorMsg
        onRetry: page.load()
    }
}
