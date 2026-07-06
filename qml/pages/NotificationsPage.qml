import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/NotificationService.js" as NotificationService
import "../services/PostService.js" as PostService

Page {
    id: page

    property int offset: 0
    property bool loading: false
    property bool endReached: false
    property int unreadCount: 0
    property string errorMsg: ""
    property var inflight: null
    property int retryCount: 0
    property bool markingAllRead: false

    header: PageHeader {
        id: pageHeader
        title: Lang.tr("Notifications")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.pageStack.pop() }
        ]
        trailingActionBar.actions: page.unreadCount > 0 ? [markAllReadAction] : []

        extension: Item {
            anchors { left: parent.left; right: parent.right }
            height: units.gu(5)

            Row {
                anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                spacing: Style.spacingS

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: units.gu(2.2); height: width
                    name: Session.pushEnabled ? "notification" : "reminder-snooze"
                    color: Session.pushEnabled ? Style.brand : Style.textSecondary
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Lang.tr("Background notifications")
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
                    color: Style.textPrimary
                    width: parent.width - pushSwitch.width - units.gu(2.2) - Style.spacingS * 2
                }
                Switch {
                    id: pushSwitch
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Session.pushEnabled
                    onClicked: Session.setPushEnabled(!Session.pushEnabled)
                }
            }

            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: units.dp(1); color: Style.divider
            }
        }
    }

    Action {
        id: markAllReadAction
        iconName: "select"
        text: page.markingAllRead ? Lang.tr("Marking…") : Lang.tr("Mark all read")
        enabled: !page.markingAllRead
        onTriggered: page.markAllRead()
    }

    ListModel { id: notifModel; dynamicRoles: true }

    // Auto-retry once on 500 — the notifications endpoint is occasionally flaky.
    Timer {
        id: retryTimer
        interval: 2000
        onTriggered: page.loadPage()
    }

    function reload() {
        if (page.inflight) { page.inflight.abort(); page.inflight = null; }
        retryTimer.stop()
        notifModel.clear()
        page.offset = 0
        page.endReached = false
        page.errorMsg = ""
        page.retryCount = 0
        page.unreadCount = 0
        page.loadPage()
    }

    function loadPage() {
        if (page.loading || page.endReached) return
        page.loading = true
        page.inflight = NotificationService.listSerey(
            Config.baseUrl, Session.token, 20, page.offset,
            function (items) {
                page.loading = false
                page.inflight = null
                if (items.length === 0) { page.endReached = true; return }
                for (var i = 0; i < items.length; i++) {
                    var n = items[i]
                    var info = n.information || {}
                    var ntype = n.type || n.notification_type || ""
                    var postAuthor   = info.post_author || info.voted_on_author || info.commented_on_author || ""
                    var postPermlink = info.post_permlink || info.voted_on_permlink || info.commented_on_permlink || ""
                    var scrollPermlink = (ntype === "REPLY" || ntype === "COMMENT")
                                        ? (info.commented_on_permlink || "")
                                        : ""
                    var isRead = !!(n.is_read || n.read || false)
                    if (!isRead) page.unreadCount++
                    notifModel.append({
                        nid:            String(n.id || n._id || ""),
                        message:        n.actor + " " + (info.description || n.message || n.content || ""),
                        actorName:      n.actor || n.actor_name || n.from_user || "",
                        actorIcon:      n.actor_image_url || n.actor_image || "",
                        timeAgo:        Style.formatTimeAgo(n.created_at || n.createdAt || ""),
                        isRead:         isRead,
                        ntype:          ntype,
                        postAuthor:     postAuthor,
                        postPermlink:   postPermlink,
                        scrollPermlink: scrollPermlink
                    })
                }
                page.offset += items.length
            },
            function (err) {
                page.loading = false
                page.inflight = null
                // Auto-retry once on server errors (500) before showing the error state.
                if (err.status >= 500 && page.retryCount < 1) {
                    page.retryCount++
                    retryTimer.start()
                } else {
                    page.errorMsg = err.message || Lang.tr("Failed to load notifications.")
                }
            }
        )
    }

    function markAllRead() {
        page.markingAllRead = true
        NotificationService.markAllRead(Config.baseUrl, Session.token,
            function () {
                page.markingAllRead = false
                page.unreadCount = 0
                NotificationState.unread = 0
                for (var i = 0; i < notifModel.count; i++)
                    notifModel.setProperty(i, "isRead", true)
                Toast.show(Lang.tr("All notifications marked as read"))
            },
            function (err) {
                page.markingAllRead = false
                Toast.show(err.message || Lang.tr("Failed to mark as read"))
            })
    }

    function markOneRead(index, nid) {
        if (notifModel.get(index).isRead) return
        NotificationService.markOneRead(Config.baseUrl, Session.token, nid,
            function () {
                notifModel.setProperty(index, "isRead", true)
                if (page.unreadCount > 0) {
                    page.unreadCount--
                    NotificationState.unread = page.unreadCount
                }
            },
            function (err) { /* silent */ })
    }

    Component.onCompleted: page.reload()

    // ── Content ──────────────────────────────────────────────────────────────
    ListView {
        id: list
        anchors { top: parent.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        opacity: page.markingAllRead ? 0.4 : 1
        Behavior on opacity { NumberAnimation { duration: 150 } }
        model: notifModel
        clip: true
        spacing: 0

        delegate: Item {
            width: list.width
            height: contentRow.height + units.gu(2)

            Rectangle {
                anchors.fill: parent
                color: model.isRead ? "transparent" : Qt.rgba(0, 0.51, 0.98, 0.04)
            }

            Rectangle {
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: units.dp(3)
                color: Style.brand
                visible: !model.isRead
                radius: units.dp(1)
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    page.markOneRead(index, model.nid)
                    if (model.ntype === "FOLLOW") {
                        page.pageStack.push(Qt.resolvedUrl("ProfileViewPage.qml"),
                            { username: model.actorName })
                    } else if (model.postAuthor !== "" && model.postPermlink !== "") {
                        var capturedAuthor   = model.postAuthor
                        var capturedPermlink = model.postPermlink
                        var capturedScroll   = model.scrollPermlink
                        PostService.detail(Config.baseUrl, capturedAuthor, capturedPermlink,
                            Session.token,
                            function (result) {
                                var cats = (result.post && result.post.categories) || []
                                var isGallery = false
                                for (var c = 0; c < cats.length; c++) {
                                    if (cats[c].toLowerCase() === "gallery") { isGallery = true; break }
                                }
                                if (isGallery) {
                                    page.pageStack.push(Qt.resolvedUrl("GalleryDetailPage.qml"), {
                                        author:   capturedAuthor,
                                        permlink: capturedPermlink
                                    })
                                } else {
                                    page.pageStack.push(Qt.resolvedUrl("PostDetailPage.qml"), {
                                        author:                  capturedAuthor,
                                        permlink:                capturedPermlink,
                                        scrollToCommentPermlink: capturedScroll
                                    })
                                }
                            },
                            function (err) {
                                // Fallback to blog detail if fetch fails
                                page.pageStack.push(Qt.resolvedUrl("PostDetailPage.qml"), {
                                    author:   capturedAuthor,
                                    permlink: capturedPermlink
                                })
                            })
                    }
                }
            }

            Row {
                id: contentRow
                anchors {
                    left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                    leftMargin: Style.spacingM; rightMargin: Style.spacingM
                }
                spacing: Style.spacingM

                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: units.gu(5.5); height: width

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Style.iconBackground
                    }
                    CircleImage {
                        id: actorImg
                        anchors { fill: parent; margins: units.dp(2) }
                        source: model.actorIcon
                    }
                    Label {
                        anchors.centerIn: parent
                        text: model.actorName.length > 0 ? model.actorName.charAt(0).toUpperCase() : "?"
                        font.pixelSize: Style.fontMedium
                        font.bold: true
                        color: Style.brand
                        visible: !actorImg.loaded
                    }

                    Rectangle {
                        anchors { right: parent.right; bottom: parent.bottom; rightMargin: -units.dp(1); bottomMargin: -units.dp(1) }
                        width: units.gu(2.4); height: width; radius: width / 2
                        color: Style.surface
                        Rectangle {
                            anchors { fill: parent; margins: units.dp(2) }
                            radius: width / 2
                            color: model.ntype === "FOLLOW" ? Style.brand
                                 : model.ntype === "VOTE" ? Style.success
                                 : model.ntype === "REPLY" || model.ntype === "COMMENT" ? "#6C63FF"
                                 : model.ntype === "BAN" || model.ntype === "BANNED" ? Style.danger
                                 : Style.brand
                            Icon {
                                anchors.centerIn: parent
                                width: units.gu(1.4); height: width
                                color: "white"
                                name: model.ntype === "FOLLOW" ? "contact-new"
                                    : model.ntype === "VOTE" ? "like"
                                    : model.ntype === "REPLY" || model.ntype === "COMMENT" ? "message"
                                    : model.ntype === "BAN" || model.ntype === "BANNED" ? "dialog-warning-symbolic"
                                    : "notification"
                            }
                        }
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - units.gu(5.5) - parent.spacing
                    spacing: units.dp(4)

                    Text {
                        width: parent.width
                        textFormat: Text.RichText
                        text: "<span style='font-weight:600; color:" + Style.textPrimary + ";'>" +
                              (model.actorName || "") + "</span> <span style='color:" +
                              (model.isRead ? Style.textSecondary : Style.textPrimary) + ";'>" +
                              ((model.message || "").replace(model.actorName + " ", "")) + "</span>"
                        font.pixelSize: Style.fontSmall
                        font.family: Style.fontFor(text)
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    Row {
                        spacing: units.dp(6)
                        Label {
                            text: model.timeAgo
                            font.pixelSize: Style.fontXSmall
                            font.family: Style.fontFor(text)
                            color: Style.textSecondary
                        }
                        Label {
                            visible: !model.isRead
                            text: "• " + Lang.tr("New")
                            font.pixelSize: Style.fontXSmall
                            font.family: Style.fontFor(text)
                            font.weight: Font.DemiBold
                            color: Style.brand
                        }
                    }
                }
            }

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: units.gu(8) }
                height: units.dp(1)
                color: Style.divider
            }
        }

        // Load more on scroll to bottom
        onAtYEndChanged: {
            if (atYEnd && !page.loading && !page.endReached)
                page.loadPage()
        }

        // Empty state
        Label {
            anchors.centerIn: parent
            visible: notifModel.count === 0 && !page.loading && page.errorMsg === ""
            text: Lang.tr("No notifications yet")
            font.pixelSize: Style.fontLarge
            font.family: Style.fontFor(text)
            color: Style.textSecondary
        }

        // Error state
        Column {
            anchors.centerIn: parent
            visible: page.errorMsg.length > 0 && notifModel.count === 0
            spacing: Style.spacingM

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.errorMsg
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFor(text)
                color: Style.danger
                wrapMode: Text.Wrap
                width: list.width - Style.spacingM * 2
                horizontalAlignment: Text.AlignHCenter
            }
            PrimaryButton {
                anchors.horizontalCenter: parent.horizontalCenter
                width: units.gu(20)
                text: Lang.tr("Retry")
                onClicked: page.reload()
            }
        }

        // Footer spinner
        footer: Item {
            width: list.width
            height: page.loading ? units.gu(6) : 0
            visible: page.loading
            ActivityIndicator {
                anchors.centerIn: parent
                running: page.loading
            }
        }
    }

    // Overlay spinner while marking all as read
    Item {
        anchors { top: parent.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: page.markingAllRead
        ActivityIndicator {
            anchors.centerIn: parent
            running: page.markingAllRead
        }
    }

}
