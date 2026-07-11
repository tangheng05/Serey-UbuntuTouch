import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/PostService.js" as PostService

/*
 * Moderation list for the current community's blog posts (post_route.js
 * /serey-web). Lists via search-advanced, deletes via the admin endpoint
 * (numeric id, not limited to the caller's own posts like the regular
 * delete-post-or-comment). Blog show/hide-on-site lives on the CMS hub
 * (PlatformAdminPage.qml), not here.
 */
Page {
    id: page

    property bool loading: false
    property string errorMsg: ""

    header: PageHeader {
        title: Lang.tr("Blog Posts")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.pageStack.pop() }
        ]
    }

    ListModel { id: postModel; dynamicRoles: true }

    function load() {
        page.loading = true
        page.errorMsg = ""
        postModel.clear()
        PostService.listAdvancedSearch(Config.baseUrl,
            { community_id: Config.managedCommunityId, limit: Config.pageSize, offset: 0 }, Session.token,
            function (posts) {
                page.loading = false
                for (var i = 0; i < posts.length; i++) postModel.append(posts[i])
            },
            function (err) {
                page.loading = false
                page.errorMsg = err.message || Lang.tr("Failed to load posts.")
            })
    }

    function remove(index) {
        var item = postModel.get(index)
        PostService.adminDeletePost(Config.baseUrl, item.id, Session.token,
            function () {
                postModel.remove(index)
                Toast.show(Lang.tr("Post deleted."))
            },
            function (err) { Toast.error(err.message || Lang.tr("Failed to delete.")) })
    }

    Component.onCompleted: page.load()

    ListView {
        id: list
        anchors { top: page.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        model: postModel
        clip: true

        delegate: Item {
            width: list.width
            height: units.gu(9)

            MouseArea {
                anchors.fill: parent
                anchors.rightMargin: units.gu(6)
                onClicked: page.pageStack.push(Qt.resolvedUrl("PostDetailPage.qml"),
                               { author: model.author, permlink: model.permlink })
            }

            Column {
                anchors {
                    left: parent.left; leftMargin: Style.spacingM
                    right: parent.right; rightMargin: units.gu(6) + Style.spacingM
                    verticalCenter: parent.verticalCenter
                }
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
                    text: "@" + (model.author || "") + " · " + (model.date || "")
                    width: parent.width
                    elide: Text.ElideRight
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                }
            }

            AbstractButton {
                anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                width: units.gu(4); height: units.gu(4)
                onClicked: page.remove(index)
                Icon { anchors.centerIn: parent; width: units.gu(2.2); height: width; name: "delete"; color: Style.danger }
            }

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: units.gu(2) }
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
        anchors { top: list.top; left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: !page.loading && page.errorMsg === "" && postModel.count === 0
        iconName: "stock_note"
        message: Lang.tr("No posts yet")
    }

    ErrorState {
        anchors { top: list.top; left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: page.errorMsg !== "" && postModel.count === 0
        message: page.errorMsg
        onRetry: page.load()
    }
}
