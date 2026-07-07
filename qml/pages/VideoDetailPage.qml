import QtQuick 2.7
import QtQuick.Layouts 1.3
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/VideoService.js" as VideoService
import "../services/PostService.js" as PostService
import "../services/CommentService.js" as CommentService
import "../services/FollowService.js" as FollowService
import "../services/YouTube.js" as YouTube
import "../services/VoteService.js" as VoteService

Page {
    id: page

    property var video: ({})
    property bool playing: false
    property bool nativeMode: false     // QtMultimedia (efficient, mp4/webm/m4v)
    property bool webVideoMode: false   // Chromium HTML5 <video> (mov / native fallback)
    property bool isFullscreen: false   // player reparented to fill the whole screen
    property bool isFollowing: false
    property bool descSheetOpen: false

    // Vote state
    property int  voteCount:  0
    property bool upvoted:    false
    property bool flagged:    false
    property bool voteBusy:   false
    property string payout:   ""
    // Off-chain (DB-only) videos have no curation weight/rewards: the like/dislike
    // stay (as a plain 100% like — see doUpvote), but the weight popover is skipped
    // and the award is not shown. Default on-chain unless the saved video says so.
    readonly property bool onChain: !page.video || page.video.postToBlockchain !== false
    property bool commentSheetOpen: false
    // YouTube stream extraction is in flight (resolving a direct URL before the
    // download daemon can fetch it). Drives the download button's spinner.
    property bool ytExtracting: false

    property var comments: []
    property int commentCount: video ? (video.comments || 0) : 0
    property bool posting: false
    property var replyTarget: null
    // On-screen-keyboard height; the comment composer rides above it.
    readonly property real kbHeight: Qt.inputMethod.visible ? Qt.inputMethod.keyboardRectangle.height : 0

    // "More Videos" feed
    property var moreVideos: []

    // A caption edit elsewhere (action sheet) changed this video's title or
    // description — swap in a fresh object so bindings re-evaluate. The player
    // source strings are unchanged, so playback isn't disturbed.
    Connections {
        target: PostActions
        function onPostUpdated(author, permlink, title, body) {
            if (page.video && page.video.permlink === permlink)
                page.video = Object.assign({}, page.video, { title: title, body: body });
        }
    }

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

    // The 11-char YouTube id, from the backend's video_id or parsed out of the
    // embed/watch URL. Empty for non-YouTube videos.
    function youtubeId() {
        var v = page.video;
        if (v.platform === "YOUTUBE" && (v.videoId || "").length === 11) return v.videoId;
        var s = (v.embedUrl || "") + " " + (v.videoLink || "");
        var m = s.match(/(?:youtube\.com\/(?:embed\/|watch\?v=)|youtu\.be\/)([A-Za-z0-9_-]{11})/);
        return m ? m[1] : "";
    }

    // YouTube videos have no direct file URL up front (so remoteDirectUrl() is
    // empty), but they're still downloadable via InnerTube extraction.
    function isYouTube() {
        return page.video && page.video.platform === "YOUTUBE" && youtubeId().length > 0;
    }

    // Resolve a YouTube clip to a direct stream URL, then hand it to the same
    // offline-download path as Serey files. Extraction is async; ytExtracting
    // gates the button so repeat taps and the post-extract handoff don't race.
    function downloadYouTube() {
        if (page.ytExtracting) return;
        var id = youtubeId();
        if (id.length === 0) { Toast.error("Couldn't read the YouTube video."); return; }
        page.ytExtracting = true;
        Toast.show("Preparing download…");
        YouTube.extract(id, function (result, errMsg) {
            page.ytExtracting = false;
            if (result && result.url) {
                Downloads.start(page.video, result.url);
            } else {
                Toast.error("This YouTube video can't be downloaded.");
                console.log("YouTube extract failed: " + (errMsg || "unknown"));
            }
        });
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
            Toast.error(Lang.tr("Please log in first."));
            page.pageStack.push(Qt.resolvedUrl("LoginPage.qml"));
            return;
        }
        var was = page.isFollowing;
        page.isFollowing = !was;
        FollowService.toggle(Config.baseUrl, video.author, was, Session.token,
            function (nowFollowing) {
                page.isFollowing = nowFollowing;
                Toast.show(nowFollowing ? Lang.tr("Following") : Lang.tr("Unfollowed"));
            },
            function (err) {
                page.isFollowing = was;
                Toast.error((err && err.message) ? err.message : Lang.tr("Action failed."));
            });
    }

    function _voteCache() {
        VoteService._updateCache(page.video.author, page.video.permlink, page.upvoted, page.flagged, page.voteCount, page.payout);
    }
    function _voteApply(r) {
        page.voteBusy = false;
        if (r.payout) page.payout = r.payout;
    }
    function _voteFail(e) {
        page.voteBusy = false;
        var msg = (e && e.message) ? e.message.toLowerCase() : "";
        if (msg.indexOf("already") >= 0) {
            if (!page.upvoted) { page.voteCount++; page.upvoted = true; page._voteCache(); }
            return;
        }
        Toast.error((e && e.message) ? e.message : Lang.tr("Action failed."));
    }
    function _sendUpvote(weight) {
        page.voteBusy = true;
        VoteService.upvote(Config.baseUrl, page.video.author, page.video.permlink, "post", weight, Session.token,
            function (r) {
                if (!page.upvoted) page.voteCount++;
                page.upvoted = true; page.flagged = false;
                page._voteApply(r); page._voteCache();
                Toast.success(Lang.tr("Upvoted %1%").arg(weight));
            }, page._voteFail);
    }
    function doUpvote() {
        if (!Session.isLoggedIn) { Toast.error(Lang.tr("Please log in first.")); return; }
        if (page.voteBusy) return;
        if (page.upvoted) {
            page.voteBusy = true;
            VoteService.removeVote(Config.baseUrl, page.video.author, page.video.permlink, "post", Session.token,
                function (r) { page.upvoted = false; page.voteCount = Math.max(0, page.voteCount - 1); page._voteApply(r); page._voteCache(); Toast.show(Lang.tr("Vote removed")); },
                page._voteFail);
        } else if (!page.onChain) {
            // Off-chain (DB-only) video: plain one-tap like, no weight popover
            // (matches fe-serey-web's simpleVote).
            page._sendUpvote(100);
        } else {
            PopupUtils.open(voteWeightDialog);
        }
    }
    function doFlag() {
        if (!Session.isLoggedIn) { Toast.error(Lang.tr("Please log in first.")); return; }
        if (page.voteBusy) return;
        page.voteBusy = true;
        if (page.flagged) {
            VoteService.removeVote(Config.baseUrl, page.video.author, page.video.permlink, "post", Session.token,
                function (r) { page.flagged = false; page._voteApply(r); page._voteCache(); Toast.show(Lang.tr("Vote removed")); },
                page._voteFail);
        } else {
            VoteService.flag(Config.baseUrl, page.video.author, page.video.permlink, "post", Session.token,
                function (r) {
                    if (page.upvoted) page.voteCount = Math.max(0, page.voteCount - 1);
                    page.flagged = true; page.upvoted = false;
                    page._voteApply(r); page._voteCache(); Toast.show(Lang.tr("Flagged"));
                }, page._voteFail);
        }
    }

    Component {
        id: voteWeightDialog
        Dialog {
            id: vwDlg
            title: Lang.tr("Vote Weight")
            property int selectedWeight: 100
            Label {
                width: parent.width
                text: vwDlg.selectedWeight + "%"
                font.pixelSize: Style.fontTitle
                font.weight: Font.Bold
                color: Style.brand
                horizontalAlignment: Text.AlignHCenter
            }
            Slider {
                id: vwSlider
                width: parent.width
                minimumValue: 1; maximumValue: 100; value: 100; live: true
                onValueChanged: vwDlg.selectedWeight = Math.round(value)
                function formatValue(v) { return Math.round(v) + "%" }
            }
            Row {
                width: parent.width
                spacing: Style.spacingS
                Repeater {
                    model: [25, 50, 75, 100]
                    delegate: AbstractButton {
                        width: (parent.width - Style.spacingS * 3) / 4
                        height: units.gu(4)
                        onClicked: { vwSlider.value = modelData; vwDlg.selectedWeight = modelData; }
                        Rectangle { anchors.fill: parent; radius: Style.cardRadius; color: vwDlg.selectedWeight === modelData ? Style.brand : Style.iconBackground }
                        Label { anchors.centerIn: parent; text: modelData + "%"; font.pixelSize: Style.fontSmall; font.weight: Font.DemiBold; color: vwDlg.selectedWeight === modelData ? Style.textOnBrand : Style.textPrimary }
                    }
                }
            }
            Row {
                width: parent.width
                spacing: Style.spacingM
                Button { width: (parent.width - Style.spacingM) / 2; text: Lang.tr("Cancel"); onClicked: PopupUtils.close(vwDlg) }
                Button { width: (parent.width - Style.spacingM) / 2; text: Lang.tr("Vote"); color: Style.brand; onClicked: { PopupUtils.close(vwDlg); page._sendUpvote(vwDlg.selectedWeight); } }
            }
        }
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
                var replies, serverCount, voters, me2;
                replies = result.replies || [];
                page.comments = replies;
                // The backend's answer_count can be stale; trust the actual
                // replies array when it's larger. (result.post can be absent if
                // the detail fetch came back empty — guard it.)
                serverCount = (result.post && result.post.comments) || 0;
                page.commentCount = Math.max(serverCount, replies.length);
                // Confirm upvoted from the authoritative voters list when no
                // session-cache entry exists. Only set true — never override to
                // false, since the detail API may return an incomplete voters list.
                if (!VoteService.getCached(video.author, video.permlink) && !page.upvoted) {
                    voters = (result.post && result.post.voters) || [];
                    me2 = Session.username || "";
                    if (me2.length > 0 && voters.indexOf(me2) >= 0)
                        page.upvoted = true;
                }
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
        Toast.success(Lang.tr("Comment deleted"));
        // Server delete must run in this page-level scope: the CommentService JS
        // import resolves to null inside the Repeater delegate's inline handler
        // (and inside Loader-created nested reply rows), so calling it there threw
        // "Cannot call method 'remove' of null" and the delete never reached the
        // server. Here in the page root the import is valid.
        CommentService.remove(Config.baseUrl, permlinkToRemove, Session.username, Session.token,
            function () {},
            function (err) {
                Toast.error((err && err.message) ? err.message : Lang.tr("Couldn't delete comment."));
            });
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

    function editComment(permlinkToEdit, newBody, parentAuthor, parentPermlink) {
        page.comments = page._editIn(page.comments, permlinkToEdit, newBody);
        Toast.success(Lang.tr("Comment updated"));
        // Server update runs in this page-level scope, not in CommentItem: its
        // CommentService import is null inside Loader-created reply rows (see
        // removeComment). Passing the existing permlink updates that comment.
        CommentService.create(Config.baseUrl,
            { parentAuthor: parentAuthor, parentPermlink: parentPermlink,
              body: newBody, permlink: permlinkToEdit },
            Session.token,
            function () {},
            function (err) {
                Toast.error((err && err.message) ? err.message : Lang.tr("Couldn't update comment."));
            });
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

    function startReply(comment) { page.replyTarget = comment; composer.forceActiveFocus(); Qt.inputMethod.show(); }
    function cancelReply() { page.replyTarget = null; }

    function submitComment() {
        var text = composer.text.trim();
        if (text.length === 0) return;
        if (!Session.isLoggedIn) {
            Toast.error(Lang.tr("Please log in first."));
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
                             date: Lang.tr("just now"), votes: 0, voters: [], replies: [],
                             authorImage: Session.avatarUrl };
                if (target)
                    page.comments = page._appendReply(page.comments, target.permlink, mine);
                else
                    page.comments = [mine].concat(page.comments);
                page.commentCount = page.commentCount + 1;
                page.replyTarget = null;
                Toast.success(Lang.tr("Comment posted"));
                page.loadComments();
            },
            function (err) {
                page.posting = false;
                Toast.error((err && err.message) ? err.message : Lang.tr("Couldn't post comment."));
            });
    }

    Component.onCompleted: {
        // Check follow status
        if (Session.isLoggedIn && video.author && video.author !== Session.username) {
            FollowService.status(Config.baseUrl, Session.username, video.author,
                function (following) { page.isFollowing = following; },
                function (err) { /* keep false */ });
        }
        // Init vote state
        var cached = VoteService.getCached(page.video.author || "", page.video.permlink || "")
        var me, saved
        if (cached) {
            page.voteCount = cached.votes
            page.upvoted   = cached.upvoted
            page.flagged   = cached.flagged || false
            page.payout    = cached.payout  || ""
        } else {
            me = Session.username || ""
            page.voteCount = page.video.votes || 0
            page.upvoted   = me.length > 0 && (page.video.voterStr   || "").indexOf("," + me + ",") >= 0
            page.flagged   = me.length > 0 && (page.video.flaggerStr || "").indexOf("," + me + ",") >= 0
            page.payout    = page.video.payout || ""
            // SQLite fallback for cross-session persistence
            saved = Session.loadVote(page.video.author || "", page.video.permlink || "")
            if (saved) {
                page.upvoted   = saved.upvoted
                page.flagged   = saved.flagged
                page.voteCount = saved.votes
            }
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
            // Title carries the video name so the dialog reads clearly on its own
            // (HIG "drop-the-title test"). Falls back when the title is missing.
            title: (page.video && page.video.title)
                   ? Lang.tr("Remove “%1”?").arg(page.video.title)
                   : Lang.tr("Remove download?")
            text: Lang.tr("This video will no longer be available offline.")
            Button {
                text: Lang.tr("Remove")
                color: Style.danger
                onClicked: { PopupUtils.close(rdlg); Downloads.remove((page.video && page.video.permlink) || ""); }
            }
            Button {
                text: Lang.tr("Cancel")
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
                font.family: Style.fontFor(text)
                color: Style.textPrimary
                wrapMode: Text.Wrap
            }

            OffChainBadge {
                x: Style.spacingM
                onChain: page.onChain
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
                            visible: !authorAvatar.loaded
                            Label {
                                anchors.centerIn: parent
                                text: (page.video.author || "?").charAt(0).toUpperCase()
                                font.pixelSize: Style.fontSmall
                                font.bold: true
                                color: Style.brand
                            }
                        }
                        CircleImage {
                            id: authorAvatar
                            anchors.fill: parent
                            source: page.video.authorImage || ""
                            decode: units.gu(7)
                            visible: loaded
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
                        text: Lang.tr("...more")
                        font.pixelSize: Style.fontSmall
                        color: Style.textSecondary
                    }
                }
            }

            Item { width: 1; height: Style.spacingS }

            // Single action row: Upvote | Downvote | Follow | ··· | Share | Download
            RowLayout {
                x: Style.spacingM
                width: parent.width - Style.spacingM * 2
                height: units.gu(4.5)
                spacing: Style.spacingS

                // Upvote
                AbstractButton {
                    Layout.preferredHeight: units.gu(4.5)
                    Layout.preferredWidth: upvoteInner.implicitWidth + Style.spacingM
                    enabled: !page.voteBusy
                    onClicked: page.doUpvote()
                    Row {
                        id: upvoteInner
                        anchors.centerIn: parent
                        spacing: Style.spacingXs
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: units.gu(2.5); height: width
                            name: "thumb-up"
                            color: page.upvoted ? Style.brand : Style.textSecondary
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.voteCount
                            font.pixelSize: Style.fontRegular
                            color: page.upvoted ? Style.brand : Style.textPrimary
                        }
                    }
                }

                // Downvote / flag
                AbstractButton {
                    Layout.preferredHeight: units.gu(4.5)
                    Layout.preferredWidth: units.gu(3.5)
                    enabled: !page.voteBusy
                    onClicked: page.doFlag()
                    Icon {
                        anchors.centerIn: parent
                        width: units.gu(2.5); height: width
                        name: "thumb-down"
                        color: page.flagged ? Style.danger : Style.textSecondary
                    }
                }

                // Busy spinner while voting
                ActivityIndicator {
                    visible: page.voteBusy
                    running: page.voteBusy
                    Layout.preferredHeight: units.gu(2.5)
                    Layout.preferredWidth: units.gu(2.5)
                }

                Item { Layout.fillWidth: true }

                // Follow — pill with icon + Follow/Following text
                AbstractButton {
                    visible: (page.video.author || "") !== "" && page.video.author !== Session.username
                    Layout.preferredHeight: units.gu(4.5)
                    Layout.preferredWidth: followInner.implicitWidth + Style.spacingM * 2
                    onClicked: page.toggleFollow()
                    Rectangle {
                        anchors.fill: parent
                        radius: Style.pillRadius
                        color: page.isFollowing ? Style.surface : Style.brand
                        border.width: page.isFollowing ? units.dp(1.5) : 0
                        border.color: Style.brand
                    }
                    Row {
                        id: followInner
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
                            text: page.isFollowing ? Lang.tr("Following") : Lang.tr("Follow")
                            font.pixelSize: Style.fontSmall
                            font.weight: Font.DemiBold
                            color: page.isFollowing ? Style.brand : Style.textOnBrand
                        }
                    }
                }

                // Share — icon only with border
                AbstractButton {
                    visible: (page.video.author || "").length > 0 && (page.video.permlink || "").length > 0
                    Layout.preferredHeight: units.gu(4.5)
                    Layout.preferredWidth: units.gu(4.5)
                    onClicked: Share.open("https://serey.io/video-component/watch?author=" + page.video.author + "&permalink=" + page.video.permlink)
                    Rectangle {
                        anchors.fill: parent
                        radius: Style.pillRadius
                        color: "transparent"
                        border.width: units.dp(1.5)
                        border.color: Style.divider
                    }
                    Icon {
                        anchors.centerIn: parent
                        width: units.gu(2.5); height: width
                        name: "share"
                        color: Style.textPrimary
                    }
                }

                // Download — icon with border; spinner + percentage while downloading,
                // tick when saved.
                AbstractButton {
                    id: dlBtn
                    visible: page.remoteDirectUrl().length > 0 || page.isYouTube()
                    readonly property string _pl: (page.video && page.video.permlink) || ""
                    readonly property var _active: (Downloads.rev, Downloads.activeFor(_pl))
                    readonly property bool _saved: (Downloads.rev, Downloads.isSaved(_pl))
                    readonly property bool _busy: !!_active || page.ytExtracting
                    readonly property int _pct: _active ? Math.round(_active.progress || 0) : 0
                    Layout.preferredHeight: units.gu(4.5)
                    Layout.preferredWidth: _busy ? dlBusyRow.implicitWidth + Style.spacingM : units.gu(4.5)
                    onClicked: {
                        if (_busy) return;
                        if (_saved) PopupUtils.open(removeDialog);
                        else if (page.remoteDirectUrl().length > 0) Downloads.start(page.video, page.remoteDirectUrl());
                        else if (page.isYouTube()) page.downloadYouTube();
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: Style.pillRadius
                        color: dlBtn._saved ? Style.brand : "transparent"
                        border.width: dlBtn._saved ? 0 : units.dp(1.5)
                        border.color: Style.divider
                    }
                    Row {
                        id: dlBusyRow
                        anchors.centerIn: parent
                        spacing: Style.spacingXs
                        visible: dlBtn._busy
                        ActivityIndicator {
                            anchors.verticalCenter: parent.verticalCenter
                            width: units.gu(2.5); height: width
                            running: dlBtn._busy
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !!dlBtn._active
                            text: dlBtn._pct + "%"
                            font.pixelSize: Style.fontSmall
                            font.weight: Font.DemiBold
                            color: Style.textPrimary
                        }
                    }
                    Icon {
                        anchors.centerIn: parent
                        width: units.gu(2.5); height: width
                        name: dlBtn._saved ? "tick" : "save"
                        color: dlBtn._saved ? Style.textOnBrand : Style.textPrimary
                        visible: !dlBtn._busy
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
                        text: Lang.tr("Comments (%1)").arg(page.commentCount)
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
                        text: Lang.tr("View all")
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
                text: Lang.tr("More Videos")
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
            radius: units.gu(1)
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
                    text: Lang.tr("Comments")
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
                        text: Lang.tr("No comments yet. Be the first!")
                        textSize: Label.Small
                        color: Style.textSecondary
                    }

                    Repeater {
                        model: page.comments
                        delegate: CommentItem {
                            width: cmtCol.width
                            comment: modelData
                            onDeleted: page.removeComment(permlink)
                            onEdited: page.editComment(permlink, newBody, parentAuthor, parentPermlink)
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
                        text: page.replyTarget ? Lang.tr("Replying to @%1").arg(page.replyTarget.author) : ""
                        font.pixelSize: Style.fontSmall
                        color: Style.textSecondary
                    }
                    AbstractButton {
                        width: cmtCancelLabel.implicitWidth
                        height: cmtCancelLabel.implicitHeight
                        onClicked: page.cancelReply()
                        Label {
                            id: cmtCancelLabel
                            text: Lang.tr("Cancel")
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

                    // Lomiri TextField (not a raw TextInput): only the styled
                    // component wires up the native long-press selection +
                    // Cut/Copy/Paste popover. StyleHints keep the gray-pill look.
                    TextField {
                        id: composer
                        width: parent.width - cmtSendBtn.width - Style.spacingS
                        height: units.gu(5)
                        StyleHints {
                            backgroundColor: Style.iconBackground
                            borderColor: "transparent"
                            color: Style.textPrimary
                        }
                        hasClearButton: false
                        placeholderText: Session.isLoggedIn ? Lang.tr("Post a comment…") : Lang.tr("Log in to comment…")
                        font.family: Style.fontFor(text)
                        font.pixelSize: Style.fontRegular
                        onAccepted: page.submitComment()
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
            radius: units.gu(1)
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
                    text: Lang.tr("Description")
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
                        font.family: Style.fontFor(text)
                        color: Style.textPrimary
                        wrapMode: Text.Wrap
                    }

                    // Stats row: Likes | Comments | Date
                    Row {
                        x: Style.spacingM
                        width: parent.width - Style.spacingM * 2
                        spacing: Style.spacingS

                        Rectangle {
                            width: (parent.width - Style.spacingS * 2) / 3
                            height: units.gu(7)
                            radius: Style.cardRadius
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
                                    text: Lang.tr("Likes")
                                    font.pixelSize: Style.fontSmall
                                    color: Style.textSecondary
                                }
                            }
                        }

                        Rectangle {
                            width: (parent.width - Style.spacingS * 2) / 3
                            height: units.gu(7)
                            radius: Style.cardRadius
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
                                    text: Lang.tr("Comments")
                                    font.pixelSize: Style.fontSmall
                                    color: Style.textSecondary
                                }
                            }
                        }

                        Rectangle {
                            width: (parent.width - Style.spacingS * 2) / 3
                            height: units.gu(7)
                            radius: Style.cardRadius
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
                                    text: Lang.tr("Date")
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
                        radius: Style.cardRadius
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
                                // Decode numeric entities (smart quotes etc.) that
                                // StyledText can't render; keep &,<,> encoded.
                                t = t.replace(/&#(\d+);/g, function (mm, n) {
                                    var code = parseInt(n, 10);
                                    return (code === 38 || code === 60 || code === 62) ? mm : String.fromCharCode(code);
                                });
                                t = t.replace(/&#x([0-9a-fA-F]+);/gi, function (mm, n) {
                                    var code = parseInt(n, 16);
                                    return (code === 38 || code === 60 || code === 62) ? mm : String.fromCharCode(code);
                                });
                                t = t.replace(/\n{3,}/g, "\n\n");
                                return t.trim();
                            }
                            font.pixelSize: Style.fontRegular
                            font.family: Style.fontFor(text)
                            color: Style.textPrimary
                            wrapMode: Text.Wrap
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
