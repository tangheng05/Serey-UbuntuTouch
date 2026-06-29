import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/VideoService.js" as VideoService
import "../services/PostService.js" as PostService
import "../services/CommentService.js" as CommentService
import "../services/FollowService.js" as FollowService

Page {
    id: page

    property var video: ({})
    property bool playing: false
    property bool nativeMode: false     // QtMultimedia (efficient, mp4/webm/m4v)
    property bool webVideoMode: false   // Chromium HTML5 <video> (mov / native fallback)
    property bool isFullscreen: false   // player reparented to fill the whole screen
    property bool isFollowing: false
    property bool descSheetOpen: false
    property bool commentSheetOpen: false

    property var comments: []
    property int commentCount: video ? (video.comments || 0) : 0
    property bool posting: false
    property var replyTarget: null
    // On-screen-keyboard height; the comment composer rides above it.
    readonly property real kbHeight: Qt.inputMethod.visible ? Qt.inputMethod.keyboardRectangle.height : 0

    // "More Videos" feed
    property var moreVideos: []

    function isDirectFile(u) {
        return /\.(mp4|webm|m4v|mov)(\?|$)/i.test(u || "");
    }

    // The remote direct media URL for a Serey-hosted clip (empty for third-party
    // embeds). This is also the "is this downloadable?" gate for the offline
    // download button — embeds return "" because there are no bytes to fetch.
    function remoteDirectUrl() {
        var v = page.video;
        if (v.platform === "SEREY") return v.videoLink || v.embedUrl || "";
        if (isDirectFile(v.videoLink)) return v.videoLink;
        if (isDirectFile(v.embedUrl)) return v.embedUrl;
        return "";
    }

    // The URL to actually play: a saved offline copy when one exists, otherwise
    // the remote file. Extension-based routing in startPlay() still applies (the
    // local path keeps the original extension), so offline .mp4 → native player
    // and offline .mov → Chromium <video>, exactly like the streamed case.
    function directUrl() {
        var local = Downloads.pathFor((page.video && page.video.permlink) || "");
        return local.length > 0 ? local : page.remoteDirectUrl();
    }

    // Build a playable third-party embed URL, mirroring the web's fallbackEmbedSrc:
    // prefer the backend's embed_video, compute it from video_id when missing, and
    // augment YouTube with the params it needs to actually play inline on mobile
    // (a bare youtube.com/embed/<id> renders a black, unresponsive frame).
    function embedSrc() {
        var v = page.video;
        var url = v.embedUrl || "";
        if (url.length === 0 && (v.videoId || "").length > 0) {
            if (v.platform === "YOUTUBE")
                url = "https://www.youtube.com/embed/" + v.videoId;
            else if (v.platform === "TIKTOK")
                url = "https://www.tiktok.com/embed/v2/" + v.videoId;
            else if (v.platform === "FACEBOOK")
                url = "https://www.facebook.com/plugins/video.php?href="
                    + encodeURIComponent("https://www.facebook.com/facebook/videos/" + v.videoId)
                    + "&show_text=false";
        }
        if (url.indexOf("youtube.com/embed/") >= 0)
            url += (url.indexOf("?") >= 0 ? "&" : "?")
                + "autoplay=1&playsinline=1&rel=0&modestbranding=1&origin=https://serey.io";
        return url;
    }

    function startPlay() {
        var v = page.video;
        var direct = page.directUrl();
        if (direct.length > 0) {
            var isLocal = direct.indexOf("file://") === 0;
            if (!isLocal && /\.mov(\?|$)/i.test(direct)) {
                // Remote QuickTime .mov: Chromium's <video> decodes the audio but
                // not the video track (black screen, stuttering). media-hub /
                // GStreamer (qtdemux) renders it, and the AppArmor block that broke
                // downloads only applies to *local* files — a remote stream is fine
                // on the native player.
                page.nativeMode = true;
                page.webVideoMode = false;
            } else {
                // All local downloads and remote mp4/webm/m4v → in-app Chromium
                // <video> (VideoWebView), NOT QtMultimedia. On Ubuntu Touch
                // QtMultimedia delegates to the out-of-process media-hub service,
                // whose AppArmor profile can't read our download-manager file
                // ("InsufficientAppArmorPermissions") → 0x0 surface then SIGSEGV.
                // Chromium decodes in our own confinement, so it reads the app's own
                // file, and for remote mp4 it range-requests the non-faststart moov
                // tail.
                page.nativeMode = false;
                page.webVideoMode = true;
            }
            page.playing = true;
        } else if (page.embedSrc().length > 0) {
            page.nativeMode = false;
            page.webVideoMode = false;
            page.playing = true;
        } else if ((v.videoLink || "").length > 0) {
            Qt.openUrlExternally(v.videoLink);
        }
    }

    // Reparent the player Loader into the fullscreen host (or back to the inline
    // stage). On this pushed page the app header and bottom nav are already hidden,
    // so filling the page is genuinely fullscreen. webLoader keeps anchors.fill:
    // parent, so it resizes to whichever container it lands in.
    function setFullscreen(on) {
        page.isFullscreen = on;
        webLoader.parent = on ? fsHost : stage;
    }

    // The native (.mov) player failed — retry in-app via Chromium's <video> rather
    // than dropping the user into an external browser. The mode change re-evaluates
    // the Loader's source. (Chromium can't render the .mov container, so this then
    // usually falls through to the system-handler last resort below.)
    function onNativeFailed() {
        if (page.webVideoMode) {
            // Even Chromium failed — last resort is the system handler.
            var link = page.directUrl() || page.video.videoLink || page.video.embedUrl;
            if ((link || "").length > 0) Qt.openUrlExternally(link);
            return;
        }
        page.nativeMode = false;
        page.webVideoMode = true;
    }

    function toggleFollow() {
        if (!Session.isLoggedIn) {
            Toast.error(i18n.tr("Please log in first."));
            page.pageStack.push(Qt.resolvedUrl("LoginPage.qml"));
            return;
        }
        var was = page.isFollowing;
        page.isFollowing = !was;
        FollowService.toggle(Config.baseUrl, video.author, was, Session.token,
            function (nowFollowing) {
                page.isFollowing = nowFollowing;
                Toast.show(nowFollowing ? i18n.tr("Following") : i18n.tr("Unfollowed"));
            },
            function (err) {
                page.isFollowing = was;
                Toast.error((err && err.message) ? err.message : i18n.tr("Action failed."));
            });
    }

    header: Rectangle {
        height: units.gu(6)
        color: Style.surface

        BackButton {
            anchors { left: parent.left; leftMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
            onClicked: page.pageStack.pop()
        }

        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: units.dp(1)
            color: Style.divider
        }
    }

    function loadComments() {
        PostService.detail(Config.baseUrl, video.author, video.permlink, Session.token,
            function (result) {
                if (!result) return;   // empty/failed detail fetch — keep current state
                var replies = result.replies || [];
                page.comments = replies;
                // The backend's answer_count can be stale; trust the actual
                // replies array when it's larger. (result.post can be absent if
                // the detail fetch came back empty — guard it.)
                var serverCount = (result.post && result.post.comments) || 0;
                page.commentCount = Math.max(serverCount, replies.length);
            },
            function (err) { /* keep empty */ });
    }

    function _removeFrom(list, permlinkToRemove) {
        var out = [];
        for (var i = 0; i < list.length; i++) {
            if (list[i].permlink === permlinkToRemove) continue;
            var node = list[i];
            if (node.replies && node.replies.length)
                node = Object.assign({}, node, { replies: page._removeFrom(node.replies, permlinkToRemove) });
            out.push(node);
        }
        return out;
    }

    function removeComment(permlinkToRemove) {
        page.comments = page._removeFrom(page.comments, permlinkToRemove);
        page.commentCount = Math.max(0, page.commentCount - 1);
        Toast.success(i18n.tr("Comment deleted"));
    }

    function _editIn(list, permlinkToEdit, newBody) {
        var out = [];
        for (var i = 0; i < list.length; i++) {
            var node = list[i];
            if (node.permlink === permlinkToEdit)
                node = Object.assign({}, node, { body: newBody });
            else if (node.replies && node.replies.length)
                node = Object.assign({}, node, { replies: page._editIn(node.replies, permlinkToEdit, newBody) });
            out.push(node);
        }
        return out;
    }

    function editComment(permlinkToEdit, newBody) {
        page.comments = page._editIn(page.comments, permlinkToEdit, newBody);
        Toast.success(i18n.tr("Comment updated"));
    }

    function _appendReply(list, parentPermlink, reply) {
        var out = [];
        for (var i = 0; i < list.length; i++) {
            var node = list[i];
            if (node.permlink === parentPermlink)
                node = Object.assign({}, node, { replies: [reply].concat(node.replies || []) });
            else if (node.replies && node.replies.length)
                node = Object.assign({}, node, { replies: page._appendReply(node.replies, parentPermlink, reply) });
            out.push(node);
        }
        return out;
    }

    function openProfile() {
        if (page.video.author)
            page.pageStack.push(Qt.resolvedUrl("ProfileViewPage.qml"), { username: page.video.author });
    }

    function startReply(comment) { page.replyTarget = comment; composer.forceActiveFocus(); }
    function cancelReply() { page.replyTarget = null; }

    function submitComment() {
        var text = composer.text.trim();
        if (text.length === 0) return;
        if (!Session.isLoggedIn) {
            Toast.error(i18n.tr("Please log in first."));
            page.pageStack.push(Qt.resolvedUrl("LoginPage.qml"));
            return;
        }
        var target = page.replyTarget;
        var parentAuthor = target ? target.author : page.video.author;
        var parentPermlink = target ? target.permlink : page.video.permlink;

        page.posting = true;
        CommentService.create(Config.baseUrl,
            { parentAuthor: parentAuthor, parentPermlink: parentPermlink, body: text },
            Session.token,
            function () {
                page.posting = false;
                composer.text = "";
                var mine = { author: Session.username, permlink: "", body: text,
                             parentAuthor: parentAuthor, parentPermlink: parentPermlink,
                             date: i18n.tr("just now"), votes: 0, voters: [], replies: [],
                             authorImage: Session.avatarUrl };
                if (target)
                    page.comments = page._appendReply(page.comments, target.permlink, mine);
                else
                    page.comments = [mine].concat(page.comments);
                page.commentCount = page.commentCount + 1;
                page.replyTarget = null;
                Toast.success(i18n.tr("Comment posted"));
                page.loadComments();
            },
            function (err) {
                page.posting = false;
                Toast.error((err && err.message) ? err.message : i18n.tr("Couldn't post comment."));
            });
    }

    Component.onCompleted: {
        // Check follow status
        if (Session.isLoggedIn && video.author && video.author !== Session.username) {
            FollowService.status(Config.baseUrl, Session.username, video.author,
                function (following) { page.isFollowing = following; },
                function (err) { /* keep false */ });
        }
        // Load comments
        page.loadComments();
        // Load more videos
        var myPermlink = page.video ? page.video.permlink : "";
        VideoService.listVideos(Config.baseUrl, { limit: 6, offset: 0 }, Session.token,
            function (result) {
                if (!page) return;   // page torn down before the response arrived
                var filtered = result.filter(function (v) {
                    return v.permlink !== myPermlink;
                });
                page.moreVideos = filtered.slice(0, 5);
            },
            function (err) { /* ignore */ });
    }

    // Confirm before forgetting an offline download.
    Component {
        id: removeDialog
        Dialog {
            id: rdlg
            title: i18n.tr("Remove download?")
            text: i18n.tr("This video will no longer be available offline.")
            Button {
                text: i18n.tr("Remove")
                color: Style.danger
                onClicked: { PopupUtils.close(rdlg); Downloads.remove((page.video && page.video.permlink) || ""); }
            }
            Button {
                text: i18n.tr("Cancel")
                onClicked: PopupUtils.close(rdlg)
            }
        }
    }

    Flickable {
        id: scroll
        anchors { top: page.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentWidth: width
        contentHeight: contentCol.height
        clip: true
        opacity: 0
        NumberAnimation on opacity { from: 0; to: 1; duration: 250; easing.type: Easing.OutQuad }

        Column {
            id: contentCol
            width: scroll.width

            // Player / thumbnail (full-bleed)
            Rectangle {
                id: stage
                width: parent.width
                height: width * 9 / 16
                color: Style.videoStage
                clip: true

                Image {
                    anchors.fill: parent
                    source: page.video.localThumb || page.video.thumbnail || ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: stage.width * 2
                    visible: !page.playing && status === Image.Ready
                }

                AbstractButton {
                    anchors.fill: parent
                    visible: !page.playing
                    onClicked: page.startPlay()
                    Rectangle {
                        anchors.centerIn: parent
                        width: units.gu(6); height: width
                        radius: width / 2
                        color: Qt.rgba(0, 0, 0, 0.5)
                        Icon {
                            anchors.centerIn: parent
                            width: units.gu(3.5); height: width
                            name: "media-playback-start"
                            color: Style.textOnBrand
                        }
                    }
                }

                Loader {
                    id: webLoader
                    anchors.fill: parent
                    active: page.playing
                    // Native player only for nativeMode; webVideoMode and embed
                    // playback both use the WebView (HTML5 <video> vs iframe).
                    source: page.playing
                        ? (page.nativeMode ? Qt.resolvedUrl("../components/VideoNativePlayer.qml")
                                           : Qt.resolvedUrl("../components/VideoWebView.qml"))
                        : ""
                    onLoaded: {
                        if (page.nativeMode) {
                            item.source = page.directUrl();
                            item.failed.connect(page.onNativeFailed);
                        } else if (page.webVideoMode) {
                            item.directVideo = true;
                            item.embedUrl = page.directUrl();
                        } else {
                            item.wrap = true;
                            item.embedUrl = page.embedSrc();
                        }
                        // Both WebView modes (<video> + YouTube iframe) can request
                        // fullscreen; the native player can't.
                        if (!page.nativeMode)
                            item.fullscreenToggled.connect(page.setFullscreen);
                    }
                    onStatusChanged: {
                        if (status === Loader.Error) {
                            page.playing = false;
                            var link = page.directUrl() || page.video.videoLink || page.video.embedUrl;
                            if ((link || "").length > 0)
                                Qt.openUrlExternally(link);
                        }
                    }
                }
            }

            Item { width: 1; height: Style.spacingM }

            // Title
            Label {
                width: parent.width - Style.spacingM * 2
                x: Style.spacingM
                text: page.video.title || ""
                font.pixelSize: Style.fontLarge
                font.weight: Font.DemiBold
                font.family: Style.fontFamily
                color: Style.textPrimary
                wrapMode: Text.WordWrap
            }

            Item { width: 1; height: Style.spacingS }

            // Author row: avatar + @name + date + "...more"
            Item {
                width: parent.width
                height: units.gu(5)

                MouseArea {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: moreBtn.left }
                    onClicked: page.openProfile()
                }

                Row {
                    anchors {
                        left: parent.left
                        right: moreBtn.left
                        leftMargin: Style.spacingM
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: Style.spacingS

                    Item {
                        width: units.gu(3.5); height: width
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: Style.avatarTint(page.video.author || "")
                            visible: (page.video.authorImage || "") === ""
                            Label {
                                anchors.centerIn: parent
                                text: (page.video.author || "?").charAt(0).toUpperCase()
                                font.pixelSize: Style.fontSmall
                                font.bold: true
                                color: Style.brand
                            }
                        }
                        CircleImage {
                            anchors.fill: parent
                            source: page.video.authorImage || ""
                            decode: units.gu(7)
                            visible: (page.video.authorImage || "") !== ""
                        }
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.video.author || ""
                        font.pixelSize: Style.fontSmall
                        font.weight: Font.DemiBold
                        color: Style.textPrimary
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "·  " + Style.formatTimeAgo(page.video.date || "")
                        font.pixelSize: Style.fontSmall
                        color: Style.textSecondary
                    }
                }

                AbstractButton {
                    id: moreBtn
                    anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                    width: moreLabel.implicitWidth
                    height: units.gu(4)
                    onClicked: page.descSheetOpen = true

                    Label {
                        id: moreLabel
                        anchors.centerIn: parent
                        text: i18n.tr("...more")
                        font.pixelSize: Style.fontSmall
                        color: Style.textSecondary
                    }
                }
            }

            Item { width: 1; height: Style.spacingS }

            // Action pills: Follow + Share
            Row {
                x: Style.spacingM
                spacing: Style.spacingS

                // Follow pill
                AbstractButton {
                    visible: (page.video.author || "") !== "" && page.video.author !== Session.username
                    width: followRow.width + Style.spacingM * 2
                    height: units.gu(4.5)
                    onClicked: page.toggleFollow()

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: page.isFollowing ? Style.surface : Style.brand
                        border.width: page.isFollowing ? units.dp(1.5) : 0
                        border.color: Style.brand
                    }
                    Row {
                        id: followRow
                        anchors.centerIn: parent
                        spacing: Style.spacingXs
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: units.gu(2); height: width
                            name: "contact"
                            color: page.isFollowing ? Style.brand : Style.textOnBrand
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.isFollowing ? i18n.tr("Following") : i18n.tr("Follow")
                            font.pixelSize: Style.fontSmall
                            font.weight: Font.DemiBold
                            color: page.isFollowing ? Style.brand : Style.textOnBrand
                        }
                    }
                }

                // Share pill
                AbstractButton {
                    visible: (page.video.author || "").length > 0 && (page.video.permlink || "").length > 0
                    width: shareRow.width + Style.spacingM * 2
                    height: units.gu(4.5)
                    onClicked: Qt.openUrlExternally("https://serey.io/authors/@" + page.video.author + "/" + page.video.permlink)

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: "transparent"
                        border.width: units.dp(1.5)
                        border.color: Style.divider
                    }
                    Row {
                        id: shareRow
                        anchors.centerIn: parent
                        spacing: Style.spacingXs
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: units.gu(2); height: width
                            name: "share"
                            color: Style.textPrimary
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: i18n.tr("Share")
                            font.pixelSize: Style.fontSmall
                            font.weight: Font.DemiBold
                            color: Style.textPrimary
                        }
                    }
                }

                // Download pill — Serey/direct files only (hidden for embeds, which
                // have no downloadable bytes). Tri-state: Download → progress% →
                // Saved. All reactivity is keyed off Downloads.rev.
                AbstractButton {
                    id: dlBtn
                    visible: page.remoteDirectUrl().length > 0
                    readonly property string _pl: (page.video && page.video.permlink) || ""
                    readonly property var _active: (Downloads.rev, Downloads.activeFor(_pl))
                    readonly property bool _saved: (Downloads.rev, Downloads.isSaved(_pl))
                    width: dlRow.width + Style.spacingM * 2
                    height: units.gu(4.5)
                    onClicked: {
                        if (_active) return;                  // in flight — ignore taps
                        if (_saved) PopupUtils.open(removeDialog);
                        else Downloads.start(page.video, page.remoteDirectUrl());
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: dlBtn._saved ? Style.brand : "transparent"
                        border.width: dlBtn._saved ? 0 : units.dp(1.5)
                        border.color: Style.divider
                    }
                    Row {
                        id: dlRow
                        anchors.centerIn: parent
                        spacing: Style.spacingXs
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: units.gu(2); height: width
                            name: dlBtn._saved ? "tick" : "save"
                            color: dlBtn._saved ? Style.textOnBrand : Style.textPrimary
                            visible: !dlBtn._active
                        }
                        ActivityIndicator {
                            anchors.verticalCenter: parent.verticalCenter
                            width: units.gu(2); height: width
                            running: !!dlBtn._active
                            visible: running
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: dlBtn._active
                                  ? (Math.round(dlBtn._active.progress) + "%")
                                  : (dlBtn._saved ? i18n.tr("Saved") : i18n.tr("Download"))
                            font.pixelSize: Style.fontSmall
                            font.weight: Font.DemiBold
                            color: dlBtn._saved ? Style.textOnBrand : Style.textPrimary
                        }
                    }
                }
            }

            Item { width: 1; height: Style.spacingM }

            Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

            Item { width: 1; height: Style.spacingS }

            // Comments header — tappable, opens comment sheet
            AbstractButton {
                width: parent.width
                height: units.gu(5)
                onClicked: page.commentSheetOpen = true

                Row {
                    anchors { left: parent.left; leftMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                    spacing: Style.spacingS
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(2.5); height: width
                        name: "message"
                        color: Style.textPrimary
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: i18n.tr("Comments (%1)").arg(page.commentCount)
                        font.pixelSize: Style.fontMedium
                        font.weight: Font.DemiBold
                        color: Style.textPrimary
                    }
                }

                Row {
                    anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                    spacing: Style.spacingXs
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: i18n.tr("View all")
                        font.pixelSize: Style.fontSmall
                        color: Style.textSecondary
                    }
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(1.6); height: width
                        name: "next"
                        color: Style.textSecondary
                    }
                }
            }

            Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

            Item { width: 1; height: Style.spacingM }

            // More Videos
            Label {
                x: Style.spacingM
                text: i18n.tr("More Videos")
                font.pixelSize: Style.fontMedium
                font.weight: Font.DemiBold
                color: Style.textPrimary
            }

            Item { width: 1; height: Style.spacingS }

            Repeater {
                model: page.moreVideos
                delegate: VideoCard {
                    width: contentCol.width
                    video: modelData
                    onClicked: page.pageStack.push(Qt.resolvedUrl("VideoDetailPage.qml"),
                        { video: modelData })
                }
            }

            Item { width: 1; height: Style.spacingL }
        }
    }

    // Fullscreen host: setFullscreen() reparents the player Loader in here to fill
    // the screen. Sits above the content and the bottom sheets (z 1500).
    Item {
        id: fsHost
        anchors.fill: parent
        z: 2000
        visible: page.isFullscreen
        Rectangle { anchors.fill: parent; color: "black" }
    }

    // --- Comment bottom sheet ------------------------------------------------
    Item {
        id: cmtSheet
        anchors.fill: parent
        visible: page.commentSheetOpen
        z: 1500
        onVisibleChanged: if (visible) { cmtBdFade.start(); cmtSlideAnim.start(); }
        function closeAnimated() { cmtBdFadeOut.start(); cmtSlideOut.start(); }

        Rectangle {
            id: cmtBd
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.4)
            opacity: 0
            MouseArea { anchors.fill: parent; onClicked: cmtSheet.closeAnimated() }
        }
        NumberAnimation { id: cmtBdFade; target: cmtBd; property: "opacity"; from: 0; to: 1; duration: 200 }
        NumberAnimation { id: cmtBdFadeOut; target: cmtBd; property: "opacity"; to: 0; duration: 200 }

        Rectangle {
            id: cmtSheetRect
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: parent.height * 0.8
            radius: units.dp(16)
            color: Style.surface
            clip: true
            transform: Translate { id: cmtSlideT; y: 0 }
            NumberAnimation { id: cmtSlideAnim; target: cmtSlideT; property: "y"; from: cmtSheetRect.height; to: 0; duration: 300; easing.type: Easing.OutCubic }
            NumberAnimation { id: cmtSlideOut; target: cmtSlideT; property: "y"; to: cmtSheetRect.height; duration: 250; easing.type: Easing.InCubic; onStopped: page.commentSheetOpen = false }

            // Grabber
            Rectangle {
                anchors { top: parent.top; topMargin: Style.spacingS; horizontalCenter: parent.horizontalCenter }
                width: units.gu(4.5); height: units.dp(4); radius: units.dp(2)
                color: Style.lightGray
                z: 2
            }

            // Header
            Item {
                id: cmtHeader
                anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: Style.spacingL }
                height: units.gu(5)
                z: 1

                Label {
                    anchors { left: parent.left; leftMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                    text: i18n.tr("Comments")
                    font.pixelSize: Style.fontMedium
                    font.weight: Font.DemiBold
                    color: Style.textPrimary
                }

                AbstractButton {
                    anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                    width: units.gu(3.5); height: units.gu(3.5)
                    onClicked: cmtSheet.closeAnimated()
                    Icon { anchors.centerIn: parent; width: units.gu(2.2); height: width; name: "close"; color: Style.textPrimary }
                }
            }

            Rectangle {
                id: cmtDivider
                anchors { top: cmtHeader.bottom; left: parent.left; right: parent.right }
                height: units.dp(1); color: Style.divider
            }

            // Comment list
            Flickable {
                id: cmtScroll
                anchors { top: cmtDivider.bottom; left: parent.left; right: parent.right; bottom: cmtFooter.top }
                contentWidth: width
                contentHeight: cmtCol.height
                clip: true

                Column {
                    id: cmtCol
                    width: cmtScroll.width

                    Item { width: 1; height: Style.spacingS }

                    Label {
                        visible: page.comments.length === 0
                        x: Style.spacingM
                        text: i18n.tr("No comments yet. Be the first!")
                        textSize: Label.Small
                        color: Style.textSecondary
                    }

                    Repeater {
                        model: page.comments
                        delegate: CommentItem {
                            width: cmtCol.width
                            comment: modelData
                            onDeleted: page.removeComment(permlink)
                            onEdited: page.editComment(permlink, newBody)
                            onReplyRequested: page.startReply(comment)
                        }
                    }

                    Item { width: 1; height: Style.spacingM }
                }
            }

            // Comment input footer inside sheet
            Column {
                id: cmtFooter
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                // Ride above the on-screen keyboard; the comment list above is
                // anchored to cmtFooter.top and shrinks to keep both visible.
                anchors.bottomMargin: page.kbHeight
                Behavior on anchors.bottomMargin { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

                // Replying-to banner
                Row {
                    visible: page.replyTarget !== null
                    width: parent.width - Style.spacingM * 2
                    x: Style.spacingM
                    spacing: Style.spacingS
                    Item { width: 1; height: units.gu(3) }

                    Label {
                        text: page.replyTarget ? i18n.tr("Replying to @%1").arg(page.replyTarget.author) : ""
                        font.pixelSize: Style.fontSmall
                        color: Style.textSecondary
                    }
                    AbstractButton {
                        width: cmtCancelLabel.implicitWidth
                        height: cmtCancelLabel.implicitHeight
                        onClicked: page.cancelReply()
                        Label {
                            id: cmtCancelLabel
                            text: i18n.tr("Cancel")
                            font.pixelSize: Style.fontSmall
                            font.weight: Font.DemiBold
                            color: Style.brand
                        }
                    }
                }

                Item { width: 1; height: Style.spacingS }

                Row {
                    width: parent.width - Style.spacingM * 2
                    x: Style.spacingM
                    spacing: Style.spacingS

                    Rectangle {
                        width: parent.width - cmtSendBtn.width - Style.spacingS
                        height: units.gu(5)
                        radius: height / 2
                        color: Style.iconBackground

                        Label {
                            anchors {
                                left: parent.left; right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: Style.spacingM; rightMargin: Style.spacingM
                            }
                            visible: composer.text.length === 0 && !composer.inputMethodComposing
                            text: Session.isLoggedIn ? i18n.tr("Post a comment…") : i18n.tr("Log in to comment…")
                            font.family: Style.fontFamily
                            color: Style.textSecondary
                            elide: Text.ElideRight
                        }

                        TextInput {
                            id: composer
                            anchors {
                                left: parent.left; right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: Style.spacingM; rightMargin: Style.spacingM
                            }
                            font.family: Style.fontFamily
                            font.pixelSize: Style.fontRegular
                            color: Style.textPrimary
                            clip: true
                            onAccepted: page.submitComment()
                        }
                    }

                    AbstractButton {
                        id: cmtSendBtn
                        width: units.gu(5); height: units.gu(5)
                        enabled: !page.posting && composer.text.trim().length > 0
                        onClicked: page.submitComment()

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: cmtSendBtn.enabled ? Style.brand : Style.iconBackground
                        }
                        Icon {
                            anchors.centerIn: parent
                            width: units.gu(2.4); height: width
                            name: "send"
                            color: cmtSendBtn.enabled ? Style.textOnBrand : Style.textSecondary
                        }
                    }
                }

                Item { width: 1; height: Style.spacingS }
            }
        }
    }

    // --- Description bottom sheet -------------------------------------------
    Item {
        id: descSheet
        anchors.fill: parent
        visible: page.descSheetOpen
        z: 1500
        onVisibleChanged: if (visible) { descBdFade.start(); descSlideAnim.start(); }
        function closeAnimated() { descBdFadeOut.start(); descSlideOut.start(); }

        Rectangle {
            id: descBd
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.4)
            opacity: 0
            MouseArea { anchors.fill: parent; onClicked: descSheet.closeAnimated() }
        }
        NumberAnimation { id: descBdFade; target: descBd; property: "opacity"; from: 0; to: 1; duration: 200 }
        NumberAnimation { id: descBdFadeOut; target: descBd; property: "opacity"; to: 0; duration: 200 }

        Rectangle {
            id: descSheetRect
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: Math.min(descCol.height + units.gu(4), parent.height * 0.75)
            radius: units.dp(16)
            color: Style.surface
            clip: true
            transform: Translate { id: descSlideT; y: 0 }
            NumberAnimation { id: descSlideAnim; target: descSlideT; property: "y"; from: descSheetRect.height; to: 0; duration: 300; easing.type: Easing.OutCubic }
            NumberAnimation { id: descSlideOut; target: descSlideT; property: "y"; to: descSheetRect.height; duration: 250; easing.type: Easing.InCubic; onStopped: page.descSheetOpen = false }

            // Grabber
            Rectangle {
                anchors { top: parent.top; topMargin: Style.spacingS; horizontalCenter: parent.horizontalCenter }
                width: units.gu(4.5); height: units.dp(4); radius: units.dp(2)
                color: Style.lightGray
            }

            // Header: "Description" + close
            Item {
                id: descHeader
                anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: Style.spacingL }
                height: units.gu(5)

                Label {
                    anchors.centerIn: parent
                    text: i18n.tr("Description")
                    font.pixelSize: Style.fontMedium
                    font.weight: Font.DemiBold
                    color: Style.textPrimary
                }

                AbstractButton {
                    anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                    width: units.gu(3.5); height: units.gu(3.5)
                    onClicked: descSheet.closeAnimated()
                    Icon {
                        anchors.centerIn: parent
                        width: units.gu(2.5); height: width
                        name: "close"
                        color: Style.textPrimary
                    }
                }
            }

            Rectangle {
                id: descDivider
                anchors { top: descHeader.bottom; left: parent.left; right: parent.right }
                height: units.dp(1); color: Style.divider
            }

            Flickable {
                anchors { top: descDivider.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
                contentWidth: width
                contentHeight: descCol.height
                clip: true

                Column {
                    id: descCol
                    width: parent.width
                    spacing: Style.spacingM

                    Item { width: 1; height: Style.spacingS }

                    // Title
                    Label {
                        width: parent.width - Style.spacingM * 2
                        x: Style.spacingM
                        text: page.video.title || ""
                        font.pixelSize: Style.fontLarge
                        font.weight: Font.DemiBold
                        font.family: Style.fontFamily
                        color: Style.textPrimary
                        wrapMode: Text.WordWrap
                    }

                    // Stats row: Likes | Comments | Date
                    Row {
                        x: Style.spacingM
                        width: parent.width - Style.spacingM * 2
                        spacing: Style.spacingS

                        Rectangle {
                            width: (parent.width - Style.spacingS * 2) / 3
                            height: units.gu(7)
                            radius: units.dp(8)
                            color: Style.iconBackground
                            Column {
                                anchors.centerIn: parent
                                spacing: units.dp(2)
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: page.video.votes || "0"
                                    font.pixelSize: Style.fontMedium
                                    font.weight: Font.DemiBold
                                    color: Style.textPrimary
                                }
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: i18n.tr("Likes")
                                    font.pixelSize: Style.fontSmall
                                    color: Style.textSecondary
                                }
                            }
                        }

                        Rectangle {
                            width: (parent.width - Style.spacingS * 2) / 3
                            height: units.gu(7)
                            radius: units.dp(8)
                            color: Style.iconBackground
                            Column {
                                anchors.centerIn: parent
                                spacing: units.dp(2)
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: page.video.comments || "0"
                                    font.pixelSize: Style.fontMedium
                                    font.weight: Font.DemiBold
                                    color: Style.textPrimary
                                }
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: i18n.tr("Comments")
                                    font.pixelSize: Style.fontSmall
                                    color: Style.textSecondary
                                }
                            }
                        }

                        Rectangle {
                            width: (parent.width - Style.spacingS * 2) / 3
                            height: units.gu(7)
                            radius: units.dp(8)
                            color: Style.iconBackground
                            Column {
                                anchors.centerIn: parent
                                spacing: units.dp(2)
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Style.formatTimeAgo(page.video.date || "")
                                    font.pixelSize: Style.fontMedium
                                    font.weight: Font.DemiBold
                                    color: Style.textPrimary
                                }
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: i18n.tr("Date")
                                    font.pixelSize: Style.fontSmall
                                    color: Style.textSecondary
                                }
                            }
                        }
                    }

                    // Body text
                    Rectangle {
                        visible: (page.video.body || "").length > 0
                        width: parent.width - Style.spacingM * 2
                        x: Style.spacingM
                        height: bodyLabel.height + Style.spacingM * 2
                        radius: units.dp(8)
                        color: Style.iconBackground

                        Label {
                            id: bodyLabel
                            anchors {
                                left: parent.left; right: parent.right
                                top: parent.top
                                margins: Style.spacingM
                            }
                            text: {
                                var t = page.video.body || "";
                                t = t.replace(/<br\s*\/?>/gi, "\n");
                                t = t.replace(/<\/p>/gi, "\n");
                                t = t.replace(/<(?!\/?(?:b|i|u|a)\b)[^>]+>/g, "");
                                t = t.replace(/&nbsp;/g, " ");
                                t = t.replace(/&amp;/g, "&");
                                t = t.replace(/\n{3,}/g, "\n\n");
                                return t.trim();
                            }
                            font.pixelSize: Style.fontRegular
                            font.family: Style.fontFamily
                            color: Style.textPrimary
                            wrapMode: Text.WordWrap
                            textFormat: Text.StyledText
                            onLinkActivated: Qt.openUrlExternally(link)
                        }
                    }

                    Item { width: 1; height: Style.spacingL }
                }
            }
        }
    }
}
