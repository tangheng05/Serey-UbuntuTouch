import QtQuick 2.7
import QtQuick.Window 2.2
import QtQuick.Layouts 1.3
import QtGraphicalEffects 1.0
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
import "../services/HiddenPosts.js" as HiddenPosts
import "../services/BlockedUsers.js" as BlockedUsers

Page {
    id: page

    property var video: ({})
    // Caps the title/author/action-row block on wide windows
    readonly property real maxContentWidth: units.gu(60)
    property bool playing: false
    property bool nativeMode: false     // QtMultimedia (efficient, mp4/webm/m4v)
    property bool webVideoMode: false   // Chromium HTML5 <video> (mov / native fallback)
    property bool isFullscreen: false   // player reparented to fill the whole screen
    property bool isFollowing: false
    property bool descSheetOpen: false

    property int  voteCount:  0
    property bool upvoted:    false
    property bool flagged:    false
    property bool voteBusy:   false
    property string payout:   ""
    // Off-chain videos skip the vote-weight popover/award (see doUpvote)
    readonly property bool onChain: !page.video || page.video.postToBlockchain !== false

    // Download state, shared by the header action and the in-content download button.
    readonly property string dlPermlink: (page.video && page.video.permlink) || ""
    readonly property var dlActive: (Downloads.rev, Downloads.activeFor(page.dlPermlink))
    readonly property bool dlSaved: (Downloads.rev, Downloads.isSaved(page.dlPermlink))
    readonly property bool dlBusy: !!page.dlActive || page.ytExtracting
    readonly property int dlPct: page.dlActive ? Math.round(page.dlActive.progress || 0) : 0
    readonly property bool canDownload: page.remoteDirectUrl().length > 0 || page.isYouTube()
    property bool commentSheetOpen: false
    // YouTube stream extraction is in flight, resolving a direct URL before the download daemon can fetch it; drives the download button's spinner.
    property bool ytExtracting: false

    property var comments: []
    property int commentCount: video ? (video.comments || 0) : 0
    property bool posting: false
    property var replyTarget: null
    // On-screen-keyboard height; the comment composer rides above it.
    readonly property real kbHeight: Qt.inputMethod.visible ? Qt.inputMethod.keyboardRectangle.height : 0

    property var moreVideos: []
    // Gates the rail's empty state so it can't flash while the request is in flight
    property bool relatedLoading: false

    // Desktop-only "•••" dropdown in the header (see videoMoreHeaderBtn).
    property bool headerMenuOpen: false
    property int headerMenuIndex: -1

    readonly property string shareUrl: (page.video && page.video.author && page.video.permlink)
        ? ("https://serey.io/video-component/watch?author=" + page.video.author + "&permalink=" + page.video.permlink) : ""
    readonly property bool isOwn: Session.isLoggedIn && !!(page.video && page.video.author) && page.video.author === Session.username

    // Category tag; "video" is a routing tag, not a topic, so never the label
    function _realCategories() {
        var c = (page.video && page.video.categories) || [];
        var out = [];
        for (var i = 0; i < c.length; i++)
            if (String(c[i]).toLowerCase() !== "video") out.push(c[i]);
        return out;
    }
    function maincategory() { return page._realCategories()[0] || ""; }
    function subcategories() { return page._realCategories().slice(1); }

    // Row data for the desktop "•••" dropdown; report/delete/block/edit-caption stay on the mobile sheet
    function headerMenuItems() {
        var items = [
            { icon: "stock_link", label: Lang.tr("Copy link"), action: "copyLink" },
            { icon: "external-link", label: Lang.tr("Open in browser"), action: "openBrowser" }
        ];
        if (page.canDownload) {
            items.push({ icon: page.dlSaved ? "tick" : "save",
                         label: page.dlSaved ? Lang.tr("Remove download") : Lang.tr("Save video offline"),
                         action: "toggleDownload" });
        }
        // The one divider in this menu: things you do with the video above,
        // things you do against it below. Don't fence single items off.
        items.push({ divider: true });
        if (page.isOwn) {
            items.push({ icon: "edit", label: Lang.tr("Edit caption"), action: "editCaption" });
            items.push({ icon: "delete", label: Lang.tr("Delete video"), danger: true, action: "delete" });
        } else {
            items.push({ icon: "close", label: Lang.tr("Hide this video"), action: "hide" });
            items.push({ icon: "dialog-warning-symbolic", label: Lang.tr("Report video"), action: "report" });
        }
        return items;
    }
    function runHeaderMenuAction(action) {
        if (action === "copyLink") { Clipboard.push(page.shareUrl); Toast.show(Lang.tr("Link copied")); }
        else if (action === "openBrowser") Qt.openUrlExternally(page.shareUrl);
        else if (action === "toggleDownload") page.doDownloadToggle();
        else if (action === "editCaption") PostActions.open(page.video, "video", 4);
        else if (action === "delete") PostActions.open(page.video, "video", 2);
        else if (action === "hide") {
            HiddenPosts.hide(page.video.permlink || "");
            PostActions.hideRequested(page.video.author || "", page.video.permlink || "");
            page.pageStack.pop();
        }
        else if (action === "report") PostActions.open(page.video, "video", 1);
    }
    // Flattened, keyboard-navigable rows for headerMenu, Block appended last.
    // No divider: Block belongs with Hide/Report in the negative group.
    function headerMenuRows() {
        var items = page.headerMenuItems();
        if (!page.isOwn)
            items.push({ icon: "", label: Lang.tr("Block %1").arg(page.video.author || ""), danger: true, action: "block", custom: "block" });
        return items;
    }
    function headerMenuMove(delta) {
        var rows = page.headerMenuRows();
        var i = page.headerMenuIndex;
        for (var n = 0; n < rows.length; n++) {
            i = (i + delta + rows.length) % rows.length;
            if (!rows[i].divider) { page.headerMenuIndex = i; return; }
        }
    }
    function headerMenuActivate() {
        var rows = page.headerMenuRows();
        if (page.headerMenuIndex < 0 || page.headerMenuIndex >= rows.length) return;
        var row = rows[page.headerMenuIndex];
        page.headerMenuOpen = false;
        if (row.action === "block") PostActions.open(page.video, "video", 3);
        else page.runHeaderMenuAction(row.action);
    }

    // Opened inside a stack that already owns a third column (Settings > Downloaded
    // Content): its rail would make a fourth, and related videos are the wrong offer
    // next to a download you saved to watch offline.
    property bool allowSidePanel: true

    // Right rail (related/vote/comments): desktop only, tablet has no room for it
    readonly property bool showSidePanel: Config.desktopMode && page.allowSidePanel
                                          && !!(page.video && page.video.permlink)
    // Resizable via the drag handle below; clamped so the article column always keeps a sane minimum width.
    property real sidePanelWidth: units.gu(34)
    readonly property real _minSidePanelW: units.gu(26)
    readonly property real _maxSidePanelW: Math.max(_minSidePanelW, Math.min(page.width * 0.5, page.width - units.gu(40)))
    readonly property real _sidePanelW: Math.max(_minSidePanelW, Math.min(_maxSidePanelW, sidePanelWidth))

    // Keyboard: Right enters side panel, Down/Up walk related/vote/downvote/composer
    function focusSidePanel() {
        if (!page.showSidePanel) return;
        sidePanelFlick.forceActiveFocus();
        page.sidePanelIndex = 0;
    }
    property int sidePanelIndex: -1
    readonly property int _voteUpIdx: page.moreVideos.length
    readonly property int _voteDownIdx: page.moreVideos.length + 1
    readonly property int _sidePanelItemCount: page.moreVideos.length + 2
    function openRelatedVideo(v) {
        page.pageStack.push(Qt.resolvedUrl("VideoDetailPage.qml"), { video: v });
    }
    function sidePanelActivate() {
        if (page.sidePanelIndex < 0) return;
        if (page.sidePanelIndex < page.moreVideos.length) page.openRelatedVideo(page.moreVideos[page.sidePanelIndex]);
        else if (page.sidePanelIndex === page._voteUpIdx) page.doUpvote();
        else if (page.sidePanelIndex === page._voteDownIdx) page.doFlag();
    }
    // Down past the last item (downvote) hands off to the comment composer for typing.
    function sidePanelFocusComposer() {
        page.sidePanelIndex = -1;
        panelComposer.forceActiveFocus();
    }

    // Caption edited elsewhere; swap in a fresh object so bindings re-evaluate
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

    // Remote direct media URL (empty for embeds; also the download-button gate)
    function remoteDirectUrl() {
        var v = page.video;
        if (v.platform === "SEREY") return v.videoLink || v.embedUrl || "";
        if (isDirectFile(v.videoLink)) return v.videoLink;
        if (isDirectFile(v.embedUrl)) return v.embedUrl;
        return "";
    }

    // The 11-char YouTube id, from the backend's video_id or parsed out of the embed/watch URL; empty for non-YouTube videos.
    function youtubeId() {
        var v = page.video;
        if (v.platform === "YOUTUBE" && (v.videoId || "").length === 11) return v.videoId;
        var s = (v.embedUrl || "") + " " + (v.videoLink || "");
        var m = s.match(/(?:youtube\.com\/(?:embed\/|watch\?v=)|youtu\.be\/)([A-Za-z0-9_-]{11})/);
        return m ? m[1] : "";
    }

    // YouTube videos have no direct file URL up front, but they're still downloadable via InnerTube extraction.
    function isYouTube() {
        return page.video && page.video.platform === "YOUTUBE" && youtubeId().length > 0;
    }

    // Resolves a YouTube clip to a direct URL, then reuses the Serey download path; ytExtracting gates the button against repeat taps.
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

    // Shared by the header action and the in-content download button.
    function doDownloadToggle() {
        if (page.dlBusy) return;
        if (page.dlSaved) PopupUtils.open(removeDialog);
        else if (page.remoteDirectUrl().length > 0) Downloads.start(page.video, page.remoteDirectUrl());
        else if (page.isYouTube()) page.downloadYouTube();
    }

    // Saved offline copy if one exists, else the remote file; startPlay()'s extension routing still applies since the local path keeps its extension.
    function directUrl() {
        var local = Downloads.pathFor((page.video && page.video.permlink) || "");
        return local.length > 0 ? local : page.remoteDirectUrl();
    }

    // Playable embed URL augments YouTube with params it needs to play inline on mobile (a bare embed URL renders a black frame).
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
                // Remote .mov: Chromium's <video> decodes audio but not the video track; media-hub/GStreamer renders it fine, and the AppArmor block below only applies to local files.
                page.nativeMode = true;
                page.webVideoMode = false;
            } else {
                // Local files and remote mp4/webm/m4v use Chromium <video>, not QtMultimedia, since media-hub's AppArmor profile can't read our download-manager file (SIGSEGV via 0x0 surface).
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

    // Reparents the player Loader into the fullscreen host or back to the inline stage; webLoader's anchors.fill follows whichever it lands in.
    function setFullscreen(on) {
        page.isFullscreen = on;
        webLoader.parent = on ? fsHost : stage;
        // Reparenting drops focus. Hand it back to the player, which owns the shortcuts;
        // only the native (.mov) player, which has none, falls back to the QML key handler.
        var it = webLoader.item;
        if (it && it.focusWeb) it.focusWeb();
        else if (on) fsKeys.forceActiveFocus();
    }

    // Space-bar: starts playback or toggles pause. YouTube answers too now that it runs
    // through the IFrame API; other embeds (TikTok/Facebook) stay cross-origin and ignore it.
    function togglePlayPause() {
        if (!page.playing) { page.startPlay(); return; }
        var it = webLoader.item;
        if (it && typeof it.togglePause === "function")
            it.togglePause();
    }

    // Native (.mov) player failed: retry via Chromium's <video> before falling back to the system handler.
    function onNativeFailed() {
        if (page.webVideoMode) {
            // Even Chromium failed; last resort is the system handler.
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
                Toast.success(Lang.tr("Thanks for your vote!"));
            }, page._voteFail);
    }
    // caller = the button to anchor the weight popover to; keyboard activation has none,
    // so it falls back to the inline vote button.
    function doUpvote(caller) {
        if (!Session.isLoggedIn) { Toast.error(Lang.tr("Please log in first.")); return; }
        if (page.voteBusy) return;
        if (page.upvoted) {
            page.voteBusy = true;
            VoteService.removeVote(Config.baseUrl, page.video.author, page.video.permlink, "post", Session.token,
                function (r) { page.upvoted = false; page.voteCount = Math.max(0, page.voteCount - 1); page._voteApply(r); page._voteCache(); Toast.show(Lang.tr("Vote removed")); },
                page._voteFail);
        } else if (!page.onChain) {
            // Off-chain (DB-only) video: plain one-tap like, no weight popover, matching fe-serey-web's simpleVote.
            page._sendUpvote(100);
        } else {
            var p = PopupUtils.open(Qt.resolvedUrl("../components/VoteWeightPopover.qml"),
                                    caller || videoUpvoteBtn);
            if (p) p.accepted.connect(page._sendUpvote);
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
                    page._voteApply(r); page._voteCache(); Toast.show(Lang.tr("Thanks for your feedback!"));
                }, page._voteFail);
        }
    }

    header: Item { height: 0 }

    Rectangle {
        id: videoDetailHeader
        // Only the article column: the right rail gets its own header row (below).
        anchors { top: parent.top; left: parent.left; right: page.showSidePanel ? sidePanel.left : parent.right }
        height: units.gu(6) + units.dp(1)
        color: Style.surface
        z: 10

        AbstractButton {
            id: videoBackBtn
            anchors { left: parent.left; leftMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
            width: units.gu(4); height: width
            onClicked: page.pageStack.pop()
            Icon { anchors.centerIn: parent; width: units.gu(2.4); height: width; name: "back"; color: Style.textPrimary }
        }

        Label {
            anchors { left: videoBackBtn.right; leftMargin: Style.spacingS; right: videoHeaderActions.left; rightMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
            text: Lang.tr("Video")
            font.pixelSize: Style.fontLarge
            font.weight: Font.Light
            color: Style.textPrimary
            elide: Text.ElideRight
        }

        // Same shape as PostDetailPage's header; tablet promotes bookmark + open-in-browser
        Row {
            id: videoHeaderActions
            anchors { right: parent.right; rightMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
            spacing: Style.spacingXs

            AbstractButton {
                id: videoSaveHeaderBtn
                visible: Config.tabletMode && page.canDownload
                width: units.gu(4); height: units.gu(4)
                onClicked: page.runHeaderMenuAction("toggleDownload")
                Icon {
                    anchors.centerIn: parent
                    width: units.gu(2.2); height: width
                    // Same save/tick pair the "..." menu and action sheet use; a
                    // bookmark glyph here read as a different action than the row below it.
                    name: page.dlSaved ? "tick" : "save"
                    color: page.dlSaved ? Style.brand : Style.textPrimary
                }
            }

            AbstractButton {
                id: videoBrowserHeaderBtn
                visible: Config.tabletMode && page.shareUrl.length > 0
                width: units.gu(4); height: units.gu(4)
                onClicked: Qt.openUrlExternally(page.shareUrl)
                Icon { anchors.centerIn: parent; width: units.gu(2.2); height: width; name: "external-link"; color: Style.textPrimary }
            }

            AbstractButton {
                id: videoShareHeaderBtn
                visible: !Config.wideMode
                width: units.gu(4); height: units.gu(4)
                enabled: !!(page.video && page.video.author && page.video.permlink)
                onClicked: Share.open(page.shareUrl, videoShareHeaderBtn)
                Icon { anchors.centerIn: parent; width: units.gu(2.2); height: width; name: "share"; color: Style.textPrimary }
            }

            AbstractButton {
                id: videoMoreHeaderBtn
                width: units.gu(4); height: units.gu(4)
                // Desktop: compact dropdown. Phone: full sheet (needs more room than a dropdown row)
                onClicked: Config.wideMode ? (page.headerMenuOpen = !page.headerMenuOpen) : PostActions.open(page.video, "video")
                Column {
                    anchors.centerIn: parent
                    spacing: units.dp(3)
                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            width: units.dp(4); height: units.dp(4)
                            radius: width / 2
                            color: Style.textSecondary
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }
            }
        }

        // ----- Desktop dropdown menu; Down/Up/Enter/Escape drive keyboard nav -----
        Rectangle {
            id: headerMenu
            visible: page.headerMenuOpen
            z: 20
            // Anchored to the Row (not button): "..." is its last item, edges coincide
            anchors { top: videoHeaderActions.bottom; right: videoHeaderActions.right; topMargin: Style.spacingXs }
            // gu(24) fit the English labels only; translations run longer.
            width: units.gu(30)
            height: headerMenuCol.height
            radius: Style.cardRadius
            color: Style.surface
            border.width: units.dp(1)
            border.color: Style.divider

            activeFocusOnTab: true
            Keys.onEscapePressed: page.headerMenuOpen = false
            Keys.onDownPressed: page.headerMenuMove(1)
            Keys.onUpPressed: page.headerMenuMove(-1)
            Keys.onReturnPressed: page.headerMenuActivate()
            Keys.onEnterPressed: page.headerMenuActivate()
            onVisibleChanged: if (visible) { page.headerMenuIndex = -1; headerMenu.forceActiveFocus(); }

            Column {
                id: headerMenuCol
                width: parent.width

                Repeater {
                    // {divider:true} | {icon, label, danger, action, custom}
                    model: page.headerMenuRows()
                    delegate: Item {
                        width: headerMenuCol.width
                        height: modelData.divider ? units.dp(1) : units.gu(5.5)

                        Rectangle {
                            visible: !!modelData.divider
                            anchors.fill: parent
                            color: Style.divider
                        }

                        Rectangle {
                            visible: !modelData.divider && index === page.headerMenuIndex
                            anchors.fill: parent
                            color: Style.iconBackground
                        }

                        AbstractButton {
                            visible: !modelData.divider
                            anchors.fill: parent
                            onClicked: {
                                page.headerMenuOpen = false;
                                if (modelData.action === "block") PostActions.open(page.video, "video", 3);
                                else page.runHeaderMenuAction(modelData.action);
                            }
                            Row {
                                anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                                spacing: Style.spacingM
                                // No "block" glyph in the Suru icon set (same reason PostActionSheet draws its own).
                                Icon {
                                    visible: modelData.custom !== "block"
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(2.2); height: width
                                    name: modelData.icon || ""
                                    color: modelData.danger ? Style.danger : Style.textPrimary
                                }
                                Item {
                                    visible: modelData.custom === "block"
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(2.2); height: width
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: width / 2
                                        color: "transparent"
                                        border.width: units.dp(1.5)
                                        border.color: Style.danger
                                    }
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width * 0.7; height: units.dp(1.5)
                                        color: Style.danger
                                        rotation: 45
                                    }
                                }
                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    // Bounded + elided so no translation can spill past the panel.
                                    width: Math.max(0, parent.width - units.gu(2.2) - parent.spacing)
                                    elide: Text.ElideRight
                                    text: modelData.label || ""
                                    font.pixelSize: Style.fontSmall
                                    font.family: Style.fontFor(text)   // labels carry usernames
                                    color: modelData.danger ? Style.danger : Style.textPrimary
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Dismiss header dropdown on outside click; page-level so it catches clicks anywhere
    MouseArea {
        visible: page.headerMenuOpen
        z: 9
        anchors.fill: parent
        onClicked: page.headerMenuOpen = false
    }

    // Single full-width divider avoids a mismatched double line at the header seam
    Rectangle {
        z: 9
        anchors {
            top: parent.top
            topMargin: videoDetailHeader.height
            left: parent.left
            right: page.showSidePanel ? sidePanel.left : parent.right
        }
        height: units.dp(1)
        color: Style.divider
    }

    function loadComments() {
        PostService.detail(Config.baseUrl, video.author, video.permlink, Session.token,
            function (result) {
                if (!result) return;   // empty/failed detail fetch, keep current state
                var replies, serverCount, voters, me2;
                replies = result.replies || [];
                page.comments = replies;
                // answer_count can be stale; trust replies.length when larger
                serverCount = (result.post && result.post.comments) || 0;
                page.commentCount = Math.max(serverCount, replies.length);
                // Only ever set upvoted true from voters: the API's list can be incomplete, so never use it to override an already-true state.
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
        // Must run in this page-level scope: the CommentService import resolves to null inside Loader-created reply row delegates.
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
        // Same page-level-scope reason as removeComment; existing permlink = update
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

    function startReply(comment) {
        page.replyTarget = comment;
        (page.showSidePanel ? panelComposer : composer).forceActiveFocus();
        Qt.inputMethod.show();
    }
    function cancelReply() { page.replyTarget = null; }

    function submitComment() {
        var activeComposer = page.showSidePanel ? panelComposer : composer;
        var text = activeComposer.text.trim();
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
                activeComposer.text = "";
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

    function _initVideoState() {
        page.isFollowing = false;
        if (Session.isLoggedIn && video.author && video.author !== Session.username) {
            FollowService.status(Config.baseUrl, Session.username, video.author,
                function (following) { page.isFollowing = following; },
                function (err) { /* keep false */ });
        }
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
        page.commentCount = page.video.comments || 0;
        page.comments = [];
        page.replyTarget = null;
        page.loadComments();
    }

    // Shared by mobile description sheet and wide-mode block; strips unsupported markup
    function formatVideoBody() {
        var t = page.video.body || "";
        t = t.replace(/<br\s*\/?>/gi, "\n");
        t = t.replace(/<\/p>/gi, "\n");
        t = t.replace(/<(?!\/?(?:b|i|u|a)\b)[^>]+>/g, "");
        t = t.replace(/&nbsp;/g, " ");
        t = t.replace(/&amp;/g, "&");
        // Decode numeric entities (smart quotes etc.) that StyledText can't render; keep &,<,> encoded.
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

    // Topic of a video row. categories[0] is often the "video" routing tag, not a
    // topic; use the mapper's scalar since `categories` is ListModel-wrapped here.
    function _topicOf(v) {
        var c = String((v && v.primaryCategory) || "");
        return c.toLowerCase() === "video" ? "" : c;
    }

    readonly property int _relatedWanted: 3

    // Same topic first, then anything else from the pool, so the rail is rarely empty.
    function _fillRelated(pool, cat, out, seen, hidden, blocked, sameCatOnly) {
        for (var i = 0; i < pool.length && out.length < page._relatedWanted; i++) {
            var v = pool[i];
            if (!v || !v.permlink || seen[v.permlink]) continue;
            if (hidden[v.permlink] || blocked[v.author || ""]) continue;
            if (sameCatOnly && cat !== "" && page._topicOf(v) !== cat) continue;
            seen[v.permlink] = true;
            out.push(v);
        }
    }

    // Right rail. Cache first (the video feed the viewer came from is already in FeedCache),
    // network only when that isn't enough. It used to be the 3 newest videos site-wide,
    // which is why an unrelated Khmer upload sat under a Russian post.
    function _loadMoreVideos() {
        // Only desktop renders the rail; elsewhere this would be a request nobody sees
        if (!page.allowSidePanel || !Config.desktopMode) return;
        var me = page.video || {};
        var cat = page._topicOf(me);
        var hidden = HiddenPosts.loadAll();
        var blocked = BlockedUsers.loadAll();
        var out = [];
        var seen = {};
        seen[me.permlink || ""] = true;
        var key = "relatedvid:" + (me.communityId || 0) + ":"
                  + (Session.isLoggedIn && Session.username ? Session.username : "__guest__");

        // The video feed cache describes the community being browsed, so only trust it when
        // that matches this video (Global carries everything, so it always does).
        var pool = [];
        if (Config.communityId === 0 || Config.communityId === (me.communityId || 0))
            pool = FeedCache.peek(FeedCache.videoKey(Config.communityId)) || [];
        var prev = FeedCache.peek(key);      // an earlier video already paid for this one
        if (prev) pool = pool.concat(prev);

        page._fillRelated(pool, cat, out, seen, hidden, blocked, true);
        if (out.length < page._relatedWanted)
            page._fillRelated(pool, cat, out, seen, hidden, blocked, false);
        if (out.length > 0) page.moreVideos = out;
        if (out.length >= page._relatedWanted) return;

        page.relatedLoading = true;
        var p = { limit: 12, offset: 0 };
        if (me.communityId > 0) p.community_id = me.communityId;
        else p.exclude_home = 1;
        FeedCache.request(key,
            function (ok, err) { return VideoService.listVideos(Config.baseUrl, p, Session.token, ok, err); },
            function (result) {
                if (!page) return;   // page torn down before the response arrived
                page.relatedLoading = false;
                page._fillRelated(result, cat, out, seen, hidden, blocked, true);
                if (out.length < page._relatedWanted)
                    page._fillRelated(result, cat, out, seen, hidden, blocked, false);
                page.moreVideos = out;
            },
            function (err) { if (page) page.relatedLoading = false; });
    }

    Component.onCompleted: {
        page._initVideoState();
        page._loadMoreVideos();
    }

    // Confirm before forgetting an offline download.
    Component {
        id: removeDialog
        Dialog {
            id: rdlg
            // Title carries the video name so the dialog reads clearly on its own (HIG drop-the-title test); falls back when the title is missing.
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

    // Scroll view owns arrow-key focus; AdaptiveStack.focusDetail() targets this
    property Item keyboardFocusItem: scroll

    Flickable {
        id: scroll
        anchors { top: videoDetailHeader.bottom; left: parent.left; right: page.showSidePanel ? sidePanel.left : parent.right; bottom: parent.bottom }
        contentWidth: width
        contentHeight: contentCol.height
        clip: true
        opacity: 0
        NumberAnimation on opacity { from: 0; to: 1; duration: 250; easing.type: Easing.OutQuad }

        // Same reading keys as PostDetailPage, but Space/Enter = play-pause here
        activeFocusOnTab: true
        function _kbScroll(dy) {
            var maxY = Math.max(0, scroll.contentHeight - scroll.height);
            scroll.contentY = Math.max(0, Math.min(maxY, scroll.contentY + dy));
        }
        Keys.onPressed: {
            var pageStep = scroll.height * 0.9;
            var lineStep = units.gu(6);
            if (event.key === Qt.Key_Down)          { scroll._kbScroll(lineStep);  event.accepted = true; }
            else if (event.key === Qt.Key_Up)       { scroll._kbScroll(-lineStep); event.accepted = true; }
            else if (event.key === Qt.Key_PageDown) { scroll._kbScroll(pageStep);  event.accepted = true; }
            else if (event.key === Qt.Key_PageUp)   { scroll._kbScroll(-pageStep); event.accepted = true; }
            else if (event.key === Qt.Key_Home)     { scroll.contentY = 0; event.accepted = true; }
            else if (event.key === Qt.Key_End)      { scroll._kbScroll(scroll.contentHeight); event.accepted = true; }
            else if (event.key === Qt.Key_Space
                  || event.key === Qt.Key_Return
                  || event.key === Qt.Key_Enter)    { page.togglePlayPause(); event.accepted = true; }
            // Escape leaves fullscreen first, else Left/Escape hand focus back to the master list
            else if (event.key === Qt.Key_Escape && page.isFullscreen) { page.setFullscreen(false); event.accepted = true; }
            else if (event.key === Qt.Key_Left || event.key === Qt.Key_Escape) { Nav.focusMaster(); event.accepted = true; }
            // Right steps into the side panel (related videos/vote/comments).
            else if (event.key === Qt.Key_Right && page.showSidePanel) { page.focusSidePanel(); event.accepted = true; }
        }
        // No auto-focus-on-load: used to steal focus even for mouse opens (see keyboardFocusItem)

        Column {
            id: contentCol
            width: scroll.width

            // Stage caps at viewport height so title/vote row stay above the fold on wide windows
            Item {
                id: stageWrap
                width: parent.width
                height: stage.height

                Rectangle {
                    id: stage
                    anchors.horizontalCenter: parent.horizontalCenter
                    // Height-cap keeps title/description above the fold; gives back 50% side padding
                    readonly property real _capW: Math.min(stageWrap.width, scroll.height * 0.5 * 16 / 9)
                    width: _capW + (stageWrap.width - _capW) * 0.5
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
                    // Native player only for nativeMode; webVideoMode and embed playback both use the WebView (HTML5 <video> vs iframe).
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
                        // Both WebView modes (<video> + YouTube iframe) can request fullscreen; the native player can't.
                        if (!page.nativeMode) {
                            item.fullscreenToggled.connect(page.setFullscreen);
                            // Play was a click on the poster, so the shortcuts should work
                            // straight away without a second click into the video.
                            item.focusWeb();
                        }
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
            }

            Item { width: 1; height: Style.spacingM }

            Item {
                id: metaBlock
                width: parent.width
                height: metaCol.height

            Column {
                id: metaCol
                width: parent.width
                spacing: 0

            // Category tag above the title, same as PostDetailPage.
            Row {
                visible: page.maincategory().length > 0
                x: Style.spacingM
                spacing: Style.spacingXs

                Rectangle {
                    width: units.dp(10); height: units.dp(10)
                    radius: units.dp(2)
                    color: Style.accentRed
                    anchors.verticalCenter: parent.verticalCenter
                }
                Label {
                    text: page.maincategory().toUpperCase()
                    font.pixelSize: Style.fontSmall
                    font.weight: Font.Bold
                    font.family: Style.fontFor(text)
                    color: Style.accentRed
                    anchors.verticalCenter: parent.verticalCenter
                }
                Label {
                    visible: text.length > 0
                    text: page.subcategories().length > 0
                          ? ("› " + page.subcategories().join(" · ").toUpperCase()) : ""
                    font.pixelSize: Style.fontSmall
                    font.weight: Font.Bold
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Item { width: 1; height: Style.spacingXs; visible: page.maincategory().length > 0 }

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

            Item { width: 1; height: Style.spacingS }

            Item {
                width: parent.width
                height: units.gu(7)

                Row {
                    id: authorRow
                    anchors {
                        left: parent.left
                        leftMargin: Style.spacingM
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: Style.spacingS

                    Item {
                        width: units.gu(5.5); height: width
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: Style.avatarTint(page.video.author || "")
                            visible: !authorAvatar.loaded
                            Label {
                                anchors.centerIn: parent
                                text: (page.video.author || "?").charAt(0).toUpperCase()
                                font.pixelSize: Style.fontMedium
                                font.bold: true
                                color: Style.brand
                            }
                        }
                        CircleImage {
                            id: authorAvatar
                            anchors.fill: parent
                            source: page.video.authorImage || ""
                            decode: units.gu(11)
                            visible: loaded
                        }
                    }

                    // Name above, timestamp below, instead of the date sitting off on the trailing edge.
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: units.dp(2)

                        Label {
                            text: page.video.author || ""
                            font.pixelSize: Style.fontSmall
                            font.weight: Font.DemiBold
                            color: Style.textPrimary
                        }
                        Label {
                            id: dateLabel
                            text: Style.formatTimeAgo(page.video.date || "")
                            font.pixelSize: Style.fontSmall
                            color: Style.textSecondary
                        }
                    }
                }

                // Hugs the row's actual rendered content, not the full width up to moreBtn, else the dead space in between wrongly opens the profile on tap.
                MouseArea {
                    anchors { left: authorRow.left; top: parent.top; bottom: parent.bottom }
                    width: authorRow.width
                    onClicked: page.openProfile()
                }

                AbstractButton {
                    id: moreBtn
                    visible: !Config.wideMode
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

                // Follow sits beside the name, outside authorRow (its MouseArea would swallow the tap)
                AbstractButton {
                    id: followBtn
                    visible: (page.video.author || "") !== "" && page.video.author !== Session.username
                    anchors { left: authorRow.right; leftMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                    width: followInner.implicitWidth + Style.spacingM * 2
                    height: units.gu(4)
                    onClicked: page.toggleFollow()

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: page.isFollowing ? Style.iconBackground : Style.brand
                    }
                    Row {
                        id: followInner
                        anchors.centerIn: parent
                        spacing: Style.spacingXs
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: units.gu(1.8); height: width
                            name: "contact"
                            color: page.isFollowing ? Style.textSecondary : Style.textOnBrand
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.isFollowing ? Lang.tr("Following") : Lang.tr("Follow")
                            font.pixelSize: Style.fontSmall
                            font.weight: Font.DemiBold
                            color: page.isFollowing ? Style.textSecondary : Style.textOnBrand
                        }
                    }
                }
            }

            Item { width: 1; height: Style.spacingS }

            // Vote row (video actions); Share/Download in header, Follow on author row above
            RowLayout {
                visible: !page.showSidePanel
                x: Style.spacingM
                width: parent.width - Style.spacingM * 2
                height: units.gu(4.5)
                spacing: Style.spacingS

                AbstractButton {
                    id: videoUpvoteBtn
                    Layout.preferredHeight: units.gu(4.5)
                    Layout.preferredWidth: upvoteInner.implicitWidth + Style.spacingM
                    enabled: !page.voteBusy
                    onClicked: page.doUpvote(videoUpvoteBtn)
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

                ActivityIndicator {
                    visible: page.voteBusy
                    running: page.voteBusy
                    Layout.preferredHeight: units.gu(2.5)
                    Layout.preferredWidth: units.gu(2.5)
                }

                Item { Layout.fillWidth: true }

                CoinValue { visible: page.onChain && page.payout.length > 0; value: page.payout }
            }

            Item { width: 1; height: Style.spacingM }

            // Narrow only: here it separates the vote row from the comments header. In wide
            // mode the description follows, and its own card already delimits it.
            Rectangle {
                visible: !Config.wideMode
                width: parent.width; height: units.dp(1); color: Style.divider
            }

            // Wide mode: description always visible here instead of behind the "...more" sheet
            Column {
                visible: Config.wideMode
                width: parent.width
                spacing: Style.spacingM

                Item { width: 1; height: Style.spacingM }

                Label {
                    x: Style.spacingM
                    text: Lang.tr("Description")
                    font.pixelSize: Style.fontMedium
                    font.weight: Font.DemiBold
                    color: Style.textPrimary
                }

                Rectangle {
                    visible: (page.video.body || "").length > 0
                    width: parent.width - Style.spacingM * 2
                    x: Style.spacingM
                    height: inlineBodyLabel.height + Style.spacingM * 2
                    radius: Style.cardRadius
                    color: Style.iconBackground

                    Label {
                        id: inlineBodyLabel
                        anchors {
                            left: parent.left; right: parent.right
                            top: parent.top
                            margins: Style.spacingM
                        }
                        text: page.formatVideoBody()
                        font.pixelSize: Style.fontRegular
                        font.family: Style.fontFor(text)
                        color: Style.textPrimary
                        wrapMode: Text.Wrap
                        textFormat: Text.StyledText
                        onLinkActivated: Qt.openUrlExternally(link)
                    }
                }

                Item { width: 1; height: Style.spacingS }

                Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }
            }

            Item { width: 1; height: Style.spacingS }

            // Comments header opens the sheet; wide mode shows the panel's list instead
            AbstractButton {
                visible: !page.showSidePanel
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

            } // metaCol
            } // metaBlock

            Item { width: 1; height: Style.spacingL }
        }
    }

    // Draggable splitter; runs full page height so both header rows sit side by side
    Rectangle {
        id: sidePanelDivider
        z: 11
        anchors { top: parent.top; bottom: parent.bottom; right: sidePanel.left }
        // Hairline, same as PostDetailPage's splitter; the gu(1.5) drag area below is the grab target
        width: units.dp(1)
        visible: page.showSidePanel
        color: sidePanelDragArea.containsMouse || sidePanelDragArea.pressed ? Style.brand : Style.divider
    }
    MouseArea {
        id: sidePanelDragArea
        visible: page.showSidePanel
        anchors { top: parent.top; bottom: parent.bottom }
        x: sidePanel.x - width / 2
        width: units.gu(1.5)
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.SplitHCursor
        onPositionChanged: {
            if (!pressed) return;
            var pagePointX = mapToItem(page, mouse.x, 0).x;
            page.sidePanelWidth = Math.max(page._minSidePanelW, Math.min(page._maxSidePanelW, page.width - pagePointX));
        }
    }

    // --- Right rail (wide mode): related videos, upvote/downvote, comments, composer ---
    Rectangle {
        id: sidePanel
        anchors { top: parent.top; right: parent.right; bottom: parent.bottom }
        width: page.showSidePanel ? page._sidePanelW : 0
        visible: page.showSidePanel
        clip: true
        color: Style.surface

        Rectangle {
            id: sidePanelHeader
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: videoDetailHeader.height
            color: Style.surface

            Label {
                anchors { left: parent.left; leftMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                text: Lang.tr("Related")
                font.pixelSize: Style.fontSmall
                font.weight: Font.Bold
                color: Style.textSecondary
            }
        }

        // Keyboard focus ring; must live inside sidePanel, since anchors only reach a
        // parent or sibling and the page-scope copy could never resolve the flick.
        Rectangle {
            anchors.fill: sidePanelFlick
            visible: page.showSidePanel && sidePanelFlick.activeFocus
            color: "transparent"
            border.width: units.dp(2)
            border.color: Style.brand
            z: 12
        }

        Flickable {
            id: sidePanelFlick
            anchors { top: sidePanelHeader.bottom; left: parent.left; right: parent.right; bottom: sideComposerBar.top }
            contentWidth: width
            contentHeight: sidePanelCol.height + Style.spacingM * 2
            clip: true

            activeFocusOnTab: true
            function _kbScroll(dy) {
                var maxY = Math.max(0, sidePanelFlick.contentHeight - sidePanelFlick.height);
                sidePanelFlick.contentY = Math.max(0, Math.min(maxY, sidePanelFlick.contentY + dy));
            }
            // Scrolls the highlighted item (related-video row or the vote row) into view.
            function _revealSelected() {
                var it = page.sidePanelIndex < page.moreVideos.length
                    ? relatedRepeater.itemAt(page.sidePanelIndex) : sidePanelVoteRow;
                if (!it) return;
                var top = it.mapToItem(sidePanelFlick.contentItem, 0, 0).y;
                var bottom = top + it.height;
                if (bottom > sidePanelFlick.contentY + sidePanelFlick.height)
                    sidePanelFlick.contentY = bottom - sidePanelFlick.height;
                else if (top < sidePanelFlick.contentY)
                    sidePanelFlick.contentY = top;
            }
            Keys.onPressed: {
                var pageStep = sidePanelFlick.height * 0.9;
                if (event.key === Qt.Key_Down) {
                    if (page.sidePanelIndex < page._sidePanelItemCount - 1) {
                        page.sidePanelIndex = page.sidePanelIndex + 1;
                        sidePanelFlick._revealSelected();
                    } else {
                        page.sidePanelFocusComposer();
                    }
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up && page.sidePanelIndex > 0) {
                    page.sidePanelIndex = page.sidePanelIndex - 1;
                    sidePanelFlick._revealSelected(); event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    page.sidePanelActivate(); event.accepted = true;
                } else if (event.key === Qt.Key_PageDown) { sidePanelFlick._kbScroll(pageStep);  event.accepted = true; }
                else if (event.key === Qt.Key_PageUp)   { sidePanelFlick._kbScroll(-pageStep); event.accepted = true; }
                else if (event.key === Qt.Key_Home)     { sidePanelFlick.contentY = 0; event.accepted = true; }
                else if (event.key === Qt.Key_End)      { sidePanelFlick._kbScroll(sidePanelFlick.contentHeight); event.accepted = true; }
                else if (event.key === Qt.Key_Left || event.key === Qt.Key_Escape) { page.sidePanelIndex = -1; scroll.forceActiveFocus(); event.accepted = true; }
            }

            Column {
                id: sidePanelCol
                x: Style.spacingM
                y: Style.spacingM
                width: parent.width - Style.spacingM * 2
                spacing: Style.spacingM

                Repeater {
                    id: relatedRepeater
                    model: page.moreVideos
                    delegate: AbstractButton {
                        id: relatedBtn
                        width: sidePanelCol.width
                        height: units.gu(7)
                        onClicked: page.openRelatedVideo(modelData)

                        Rectangle {
                            anchors.fill: parent
                            radius: Style.cardRadius
                            color: (index === page.sidePanelIndex || relatedHover.containsMouse) ? Style.iconBackground : "transparent"
                            border.width: index === page.sidePanelIndex ? units.dp(2) : 0
                            border.color: Style.brand
                        }
                        MouseArea {
                            id: relatedHover
                            anchors.fill: parent
                            hoverEnabled: true
                            propagateComposedEvents: true
                            onClicked: (mouse) => { mouse.accepted = false; }
                        }

                        Row {
                            anchors.fill: parent
                            anchors.margins: units.dp(4)
                            spacing: Style.spacingS

                            Item {
                                anchors.verticalCenter: parent.verticalCenter
                                width: units.gu(9); height: units.gu(6.5)
                                Rectangle { anchors.fill: parent; radius: Style.thumbRadius; color: Style.iconBackground }
                                Image {
                                    id: relatedThumbImg
                                    anchors.fill: parent
                                    source: modelData.thumbnail || ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    // Cap the decode: these are gu(9) thumbs, not full-size covers
                                    sourceSize.width: units.gu(18)
                                    visible: false
                                }
                                Rectangle {
                                    id: relatedThumbMask
                                    anchors.fill: parent
                                    radius: Style.thumbRadius
                                    visible: false
                                }
                                OpacityMask {
                                    anchors.fill: parent
                                    source: relatedThumbImg
                                    maskSource: relatedThumbMask
                                    visible: (modelData.thumbnail || "") !== ""
                                }
                                Icon {
                                    anchors.centerIn: parent
                                    width: units.gu(2); height: width
                                    name: "media-playback-start"
                                    color: Qt.rgba(1, 1, 1, 0.85)
                                    visible: (modelData.thumbnail || "") === ""
                                }
                            }
                            Label {
                                width: parent.width - units.gu(9) - Style.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.title || ""
                                font.pixelSize: Style.fontSmall
                                font.weight: Font.DemiBold
                                font.family: Style.fontFor(text)
                                color: Style.textPrimary
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                RelatedSkeleton {
                    width: sidePanelCol.width
                    // showSidePanel too: an invisible ancestor doesn't stop the pulse animations
                    visible: page.showSidePanel && page.moreVideos.length === 0 && page.relatedLoading
                    thumbWidth: units.gu(9)
                }

                Label {
                    width: sidePanelCol.width
                    visible: !page.relatedLoading && page.moreVideos.length === 0
                    text: Lang.tr("No related videos yet")
                    font.pixelSize: Style.fontSmall
                    color: Style.textSecondary
                    wrapMode: Text.Wrap
                }

                // Upvote/downvote, mirroring the main vote row but living here in wide mode
                RowLayout {
                    id: sidePanelVoteRow
                    width: sidePanelCol.width
                    height: units.gu(4.5)
                    spacing: Style.spacingS

                    AbstractButton {
                        id: panelUpvoteBtn
                        Layout.preferredHeight: units.gu(4.5)
                        Layout.preferredWidth: panelUpvoteInner.implicitWidth + Style.spacingM
                        enabled: !page.voteBusy
                        onClicked: page.doUpvote(panelUpvoteBtn)
                        Rectangle {
                            anchors.fill: parent
                            radius: Style.cardRadius
                            color: "transparent"
                            border.width: page.sidePanelIndex === page._voteUpIdx ? units.dp(2) : 0
                            border.color: Style.brand
                        }
                        Row {
                            id: panelUpvoteInner
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

                    AbstractButton {
                        Layout.preferredHeight: units.gu(4.5)
                        Layout.preferredWidth: units.gu(3.5)
                        enabled: !page.voteBusy
                        onClicked: page.doFlag()
                        Rectangle {
                            anchors.fill: parent
                            radius: Style.cardRadius
                            color: "transparent"
                            border.width: page.sidePanelIndex === page._voteDownIdx ? units.dp(2) : 0
                            border.color: Style.brand
                        }
                        Icon {
                            anchors.centerIn: parent
                            width: units.gu(2.5); height: width
                            name: "thumb-down"
                            color: page.flagged ? Style.danger : Style.textSecondary
                        }
                    }

                    ActivityIndicator {
                        visible: page.voteBusy
                        running: page.voteBusy
                        Layout.preferredHeight: units.gu(2.5)
                        Layout.preferredWidth: units.gu(2.5)
                    }

                    Item { Layout.fillWidth: true }

                    CoinValue { visible: page.onChain && page.payout.length > 0; value: page.payout }
                }

                Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

                Label {
                    width: parent.width
                    text: Lang.tr("COMMENTS (%1)").arg(page.commentCount)
                    font.pixelSize: Style.fontSmall
                    font.weight: Font.Bold
                    color: Style.textSecondary
                }

                Label {
                    width: parent.width
                    visible: page.comments.length === 0
                    text: Lang.tr("No comments yet. Be the first!")
                    textSize: Label.Small
                    color: Style.textSecondary
                }

                Repeater {
                    model: page.comments
                    // Wrapper carries the between-comments rule; a flush-left body needs
                    // the separation that the avatar indent used to provide.
                    delegate: Column {
                        width: sidePanelCol.width
                        spacing: Style.spacingS

                        Rectangle {
                            visible: index > 0
                            width: parent.width
                            height: units.dp(1)
                            color: Style.divider
                        }

                        CommentItem {
                            width: parent.width
                            compact: true
                            comment: modelData
                            onDeleted: page.removeComment(permlink)
                            onEdited: page.editComment(permlink, newBody, parentAuthor, parentPermlink)
                            onReplyRequested: page.startReply(comment)
                            onAuthorClicked: page.pageStack.push(Qt.resolvedUrl("ProfileViewPage.qml"), { username: author })
                        }
                    }
                }
            }
        }

        // Click anywhere grabs keyboard focus; press passes through unaccepted for buttons below
        MouseArea {
            anchors.fill: sidePanelFlick
            propagateComposedEvents: true
            onPressed: { sidePanelFlick.forceActiveFocus(); mouse.accepted = false; }
        }

        // Sticky comment composer, pinned to the bottom of the panel.
        Rectangle {
            id: sideComposerBar
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            anchors.bottomMargin: page.kbHeight
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
            height: panelComposerArea.height + Style.spacingS * 2
            color: Style.surface

            Rectangle {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: units.dp(1)
                color: Style.divider
            }
            Rectangle {
                anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                width: units.dp(1)
                color: Style.divider
            }

            Column {
                id: panelComposerArea
                x: Style.spacingS
                y: Style.spacingS
                width: parent.width - Style.spacingS * 2
                spacing: units.dp(4)

                Row {
                    visible: page.replyTarget !== null
                    width: parent.width
                    spacing: Style.spacingS

                    Label {
                        text: page.replyTarget ? Lang.tr("Replying to @%1").arg(page.replyTarget.author) : ""
                        font.pixelSize: Style.fontSmall
                        color: Style.textSecondary
                    }
                    AbstractButton {
                        width: panelCancelLabel.implicitWidth
                        height: panelCancelLabel.implicitHeight
                        onClicked: page.cancelReply()
                        Label {
                            id: panelCancelLabel
                            text: Lang.tr("Cancel")
                            font.pixelSize: Style.fontSmall
                            font.weight: Font.DemiBold
                            color: Style.brand
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: units.gu(5)

                    Rectangle {
                        anchors.fill: parent
                        radius: Style.cardRadius
                        color: Style.iconBackground
                        border.width: units.dp(1)
                        border.color: Style.divider
                    }

                    TextField {
                        id: panelComposer
                        anchors { left: parent.left; leftMargin: Style.spacingM; right: panelSendButton.left; rightMargin: Style.spacingXs; verticalCenter: parent.verticalCenter }
                        height: parent.height - units.dp(2)
                        StyleHints {
                            backgroundColor: "transparent"
                            borderColor: "transparent"
                            color: Style.textPrimary
                        }
                        hasClearButton: false
                        placeholderText: Session.isLoggedIn ? Lang.tr("Post a comment…") : Lang.tr("Log in to comment…")
                        font.family: Style.fontFor(text)
                        font.pixelSize: Style.fontRegular
                        onAccepted: page.submitComment()
                        // Up steps back to the downvote button; Escape returns to the video.
                        Keys.onUpPressed: {
                            if (page.showSidePanel) {
                                page.sidePanelIndex = page._voteDownIdx;
                                sidePanelFlick.forceActiveFocus();
                                sidePanelFlick._revealSelected();
                            }
                        }
                        Keys.onEscapePressed: { page.sidePanelIndex = -1; scroll.forceActiveFocus(); }
                    }

                    AbstractButton {
                        id: panelSendButton
                        anchors { right: parent.right; rightMargin: units.dp(3); verticalCenter: parent.verticalCenter }
                        width: units.gu(3.8); height: width
                        enabled: !page.posting && panelComposer.text.trim().length > 0
                        onClicked: page.submitComment()

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: panelSendButton.enabled ? Style.brand : "transparent"
                        }
                        Icon {
                            anchors.centerIn: parent
                            width: units.gu(2.2); height: width
                            name: "send"
                            color: panelSendButton.enabled ? Style.textOnBrand : Style.textSecondary
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.fill: scroll
        visible: scroll.activeFocus
        color: "transparent"
        border.width: units.dp(2)
        border.color: Style.brand
        // Above sidePanelDivider's z:11, else the divider paints over this border's right edge.
        z: 12
    }
    // Fullscreen host: setFullscreen() reparents the player Loader in here to fill the screen, above content and bottom sheets (z 1500).
    Item {
        id: fsHost
        parent: (page.isFullscreen && Window.contentItem) ? Window.contentItem : page
        anchors.fill: parent
        z: 2000
        visible: page.isFullscreen
        Rectangle { anchors.fill: parent; color: "black" }

        // Fallback only (native player): never given focus while a web player holds it,
        // since taking it would disable that player's own shortcuts.
        Item {
            id: fsKeys
            anchors.fill: parent
            Keys.onPressed: {
                if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back) {
                    page.setFullscreen(false);
                    event.accepted = true;
                }
            }
        }

        // Native way out: YouTube's own exit control only renders at some player sizes, and QtWebEngine never exits on Escape by itself.
        AbstractButton {
            anchors { left: parent.left; top: parent.top; margins: units.gu(1.5) }
            width: units.gu(5); height: width
            z: 10
            onClicked: page.setFullscreen(false)
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Qt.rgba(0, 0, 0, 0.55)
                Icon {
                    anchors.centerIn: parent
                    width: units.gu(2.5); height: width
                    name: "view-restore"
                    color: "white"
                }
            }
        }
    }

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

            Rectangle {
                anchors { top: parent.top; topMargin: Style.spacingS; horizontalCenter: parent.horizontalCenter }
                width: units.gu(4.5); height: units.dp(4); radius: units.dp(2)
                color: Style.lightGray
                z: 2
            }

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

            Column {
                id: cmtFooter
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                // Ride above the on-screen keyboard; the comment list above is anchored to cmtFooter.top and shrinks to keep both visible.
                anchors.bottomMargin: page.kbHeight
                Behavior on anchors.bottomMargin { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

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

                    // Lomiri TextField (not a raw TextInput): only the styled component wires up native long-press selection + Cut/Copy/Paste; StyleHints keep the gray-pill look.
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

            Rectangle {
                anchors { top: parent.top; topMargin: Style.spacingS; horizontalCenter: parent.horizontalCenter }
                width: units.gu(4.5); height: units.dp(4); radius: units.dp(2)
                color: Style.lightGray
            }

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
                            text: page.formatVideoBody()
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
