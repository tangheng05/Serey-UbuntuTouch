import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/VideoService.js" as VideoService
import "../services/VoteService.js" as VoteService
import "../services/HiddenPosts.js" as HiddenPosts
import "../services/BlockedUsers.js" as BlockedUsers

Page {
    id: page

    // Keyboard equivalent of swipe-between-reels
    focus: true
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape && page.menuOpen) {
            page.menuOpen = false;
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && !page.wideReels && commentSheet.visible) {
            commentSheet.close();
            event.accepted = true;
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_PageDown) {
            pager.incrementCurrentIndex();
            event.accepted = true;
        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_PageUp) {
            pager.decrementCurrentIndex();
            event.accepted = true;
        // Same as every other detail page: hand focus back to the list on the left.
        // Wide mode never closes the docked panel here, since nothing could reopen it.
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Escape) {
            Nav.focusMaster();
            event.accepted = true;
        }
    }

    property var reels: []
    property bool loading: true
    property string errorMsg: ""
    property int startIndex: 0

    // Pushed into the detail column, the list keeps focus by app convention (Right steps in).
    // Reels are arrow-driven, so the opener asks for focus here instead.
    property bool focusOnOpen: false
    property Item keyboardFocusItem: page

    // Pending vote, set by the delegate before opening the weight dialog.
    property var    _voteReel:    null
    property string _voteAuthor:  ""
    property string _votePermlink: ""

    // One-line plain-text preview of an HTML description
    function _descPreview(body) {
        var t = (body || "");
        t = t.replace(/<br\s*\/?>/gi, " ").replace(/<\/p>/gi, " ").replace(/<[^>]+>/g, "");
        t = t.replace(/&nbsp;/g, " ").replace(/&amp;/g, "&");
        t = t.replace(/&#(\d+);/g, function (m, n) { return String.fromCharCode(parseInt(n, 10)); });
        return t.replace(/\s+/g, " ").trim();
    }

    // Full plain-text description with paragraph breaks preserved
    function _descFull(body) {
        var t = (body || "");
        t = t.replace(/<br\s*\/?>/gi, "\n").replace(/<\/p>/gi, "\n").replace(/<[^>]+>/g, "");
        t = t.replace(/&nbsp;/g, " ").replace(/&amp;/g, "&");
        t = t.replace(/&#(\d+);/g, function (m, n) { return String.fromCharCode(parseInt(n, 10)); });
        return t.replace(/\n{3,}/g, "\n\n").trim();
    }

    // Wide windows: center a portrait stage and put the rail (and the comments panel) next to it.
    // Full-width delegates left the video floating between black bars with the rail on the window edge.
    // Desktop only, like VideoDetailPage's side panel: a tablet split has no room for the
    // rail and the reel, so it keeps the phone layout with the modal comment sheet.
    readonly property bool wideReels: Config.desktopMode
    readonly property real railWidth: units.gu(7)
    readonly property real reelGap: Style.spacingS
    // Same width and drag-to-resize behaviour as VideoDetailPage's side panel, so the two
    // rails match. Always on when wide: it's furniture, not a popup.
    property real commentsPanelWidth: units.gu(34)
    readonly property real _minCommentsW: units.gu(26)
    readonly property real _maxCommentsW: Math.max(_minCommentsW,
        Math.min(page.width * 0.5, page.width - units.gu(40)))
    readonly property real commentsWidth: page.wideReels
        ? Math.max(_minCommentsW, Math.min(_maxCommentsW, page.commentsPanelWidth)) : 0
    readonly property var currentReel: (pager.currentIndex >= 0 && pager.currentIndex < page.reels.length)
        ? page.reels[pager.currentIndex] : null
    // Space left for the video once the rail is docked; the stage centers inside it.
    readonly property real stageArea: page.width - page.commentsWidth
    readonly property real stageWidth: {
        if (!page.wideReels) return page.width;
        var taken = page.railWidth + page.reelGap + Style.spacingM * 2;
        // Reels are shot 9:16, so height is what limits the column on a desktop window.
        return Math.max(units.gu(20), Math.min(page.height * 9 / 16, page.stageArea - taken));
    }
    readonly property real stageX: {
        if (!page.wideReels) return 0;
        var group = page.stageWidth + page.reelGap + page.railWidth;
        return Math.max(Style.spacingM, (page.stageArea - group) / 2);
    }

    // One clip ahead only: enough to cover a swipe, cheap enough not to hog the radio.
    function nextReelUrl(i) {
        var n = i + 1;
        if (n < 0 || n >= page.reels.length) return "";
        return page.reels[n].videoLink || "";
    }

    // Wide: the rail is docked and permanent, so a swipe reloads it for the new reel
    // instead of opening/closing it.
    function syncDockedPanel() {
        if (!page.wideReels) return;
        var v = page.currentReel;
        if (!v) return;
        if (commentSheet.visible && commentSheet.permlink === (v.permlink || "")) return;
        page._commentSheetPermlink = v.permlink || "";
        commentSheet.open(v.author || "", v.permlink || "");
    }
    onWideReelsChanged: {
        if (page.wideReels) page.syncDockedPanel();
        else if (commentSheet.visible) commentSheet.close();
    }

    // Desktop gets the anchored dropdown the cards use; phone/tablet keep the full bottom sheet.
    property var _menuVideo: null
    property bool menuOpen: false
    // Button rect in page coords: the menu opens beside the rail, so it needs the left edge and the bottom.
    property point _menuAnchorTL: Qt.point(0, 0)
    property point _menuAnchorBR: Qt.point(0, 0)

    function openReelMenu(video, btn) {
        if (!Config.desktopMode) { PostActions.open(video, "video"); return; }
        page._menuVideo = video;
        page._menuAnchorTL = btn.mapToItem(page, 0, 0);
        page._menuAnchorBR = btn.mapToItem(page, btn.width, btn.height);
        page.menuOpen = true;
    }

    function reelMenuItems() {
        var v = page._menuVideo || {};
        var own = Session.isLoggedIn && !!v.author && v.author === Session.username;
        var saved = (Downloads.rev, Downloads.isSaved(v.permlink || ""));
        var items = [];
        // Reels are Serey-hosted only (see load()), so videoLink is always a direct file
        if ((v.videoLink || "").length > 0) {
            items.push({ icon: saved ? "tick" : "save",
                         label: saved ? Lang.tr("Remove download") : Lang.tr("Save video offline"),
                         action: "toggleDownload" });
            items.push({ divider: true });
        }
        if (own) {
            items.push({ icon: "edit", label: Lang.tr("Edit caption"), action: "editCaption" });
            items.push({ icon: "delete", label: Lang.tr("Delete video"), danger: true, action: "delete" });
        } else {
            items.push({ icon: "close", label: Lang.tr("Hide this video"), action: "hide" });
            items.push({ icon: "dialog-warning-symbolic", label: Lang.tr("Report video"), action: "report" });
        }
        return items;
    }

    function runReelMenuAction(action) {
        var v = page._menuVideo;
        if (!v) return;
        if (action === "toggleDownload") {
            var pl = v.permlink || "";
            if (Downloads.isSaved(pl)) { Downloads.remove(pl); return; }
            Downloads.start(v, v.videoLink || "");
        }
        else if (action === "editCaption") PostActions.open(v, "video", 4);
        else if (action === "delete") PostActions.open(v, "video", 2);
        else if (action === "hide") {
            HiddenPosts.hide(v.permlink || "");
            PostActions.hideRequested(v.author || "", v.permlink || "");
        }
        else if (action === "report") PostActions.open(v, "video", 1);
    }

    function _sendUpvote(weight) {
        var reel = page._voteReel;
        if (!reel) return;
        reel.busy = true;
        VoteService.upvote(Config.baseUrl, page._voteAuthor, page._votePermlink, "post", weight, Session.token,
            function (r) {
                if (!reel.upvoted) reel.votes = reel.votes + 1;
                reel.upvoted = true; reel.flagged = false; reel.busy = false;
                VoteService._updateCache(page._voteAuthor, page._votePermlink, true, false, reel.votes, "");
                Toast.success(Lang.tr("Thanks for your vote!"));
            },
            function (e) {
                reel.busy = false;
                Toast.error(Lang.tr(VoteService.friendlyError(e)));
            });
    }

    header: Item { height: 0 }

    Component.onCompleted: {
        load();
        // After the push settles, else the detail stack hands focus back to the list.
        if (page.focusOnOpen) Qt.callLater(function () { page.forceActiveFocus(); });
    }

    function load() {
        page.loading = true;
        page.errorMsg = "";
        var params = { limit: 50, offset: 0 };
        if (Config.communityId > 0)
            params.community_id = Config.communityId;
        else
            params.exclude_home = 1;   // Global feed hides the Cambodia community + children
        VideoService.listVideos(Config.baseUrl, params, Session.token,
            function (result) {
                if (!page) return;          // popped mid-load, page destroyed
                // Same filters as the shelf that launched us (VideoPage._applyRows), so the
                // startIndex we were handed still points at the reel the reader tapped.
                var hidden = HiddenPosts.loadAll();
                var blocked = BlockedUsers.loadAll();
                var seen = {};
                page.reels = result.filter(function (v) {
                    var pl = v.permlink || "";
                    if (v.platform !== "SEREY" || (v.videoLink || "").length === 0) return false;
                    if (hidden[pl] || blocked[v.author || ""] || seen[pl]) return false;
                    seen[pl] = true;
                    return true;
                });
                if (page.reels.length > 0) {
                    var idx = Math.max(0, Math.min(page.startIndex, page.reels.length - 1));
                    pager.positionViewAtIndex(idx, ListView.Beginning);
                    pager.currentIndex = idx;
                }
                page.loading = false;
                page.syncDockedPanel();
            },
            function (err) {
                if (!page) return;
                page.loading = false;
                page.errorMsg = (err && err.message) ? err.message : Lang.tr("Couldn't load Serey Shorts.");
            });
    }

    // Model is a plain JS array: reassign (not mutate) to refresh delegates, and restore pager position; the current reel remounts.
    Connections {
        target: PostActions
        function onPostUpdated(author, permlink, title, body) {
            var idx = -1;
            var rows = page.reels.slice();
            for (var i = 0; i < rows.length; i++) {
                if (rows[i].permlink === permlink) {
                    rows[i] = Object.assign({}, rows[i], { title: title, body: body });
                    idx = i;
                }
            }
            if (idx < 0) return;
            var keep = pager.currentIndex;
            page.reels = rows;
            pager.positionViewAtIndex(keep, ListView.Beginning);
            pager.currentIndex = keep;
        }
        // Hiding, deleting or blocking from the reel's own menu has to take the reel off
        // screen; the list pages behind us already drop it.
        function onHideRequested(author, permlink) {
            page._dropReels(function (v) { return (v.permlink || "") === permlink; });
        }
        function onPostDeleted(author, permlink) {
            page._dropReels(function (v) { return (v.permlink || "") === permlink; });
        }
        function onUserBlocked(username) {
            page._dropReels(function (v) { return (v.author || "") === username; });
        }
    }

    function _dropReels(matches) {
        var rows = [];
        for (var i = 0; i < page.reels.length; i++)
            if (!matches(page.reels[i])) rows.push(page.reels[i]);
        if (rows.length === page.reels.length) return;
        var keep = Math.min(pager.currentIndex, Math.max(0, rows.length - 1));
        page.reels = rows;
        if (rows.length === 0) return;
        pager.positionViewAtIndex(keep, ListView.Beginning);
        pager.currentIndex = keep;
        page.syncDockedPanel();
    }

    // Reel the comment sheet is currently open for
    property string _commentSheetPermlink: ""

    // Keep the comment-rail count in sync with the sheet
    Connections {
        target: commentSheet
        function onCountChanged(delta) {
            var permlink = page._commentSheetPermlink;
            if (permlink === "") return;
            var idx = -1;
            var rows = page.reels.slice();
            for (var i = 0; i < rows.length; i++) {
                if (rows[i].permlink === permlink) {
                    rows[i] = Object.assign({}, rows[i], { comments: Math.max(0, (rows[i].comments || 0) + delta) });
                    idx = i;
                }
            }
            if (idx < 0) return;
            var keep = pager.currentIndex;
            page.reels = rows;
            pager.positionViewAtIndex(keep, ListView.Beginning);
            pager.currentIndex = keep;
        }
    }

    Rectangle { anchors.fill: parent; color: "black" }

    // One reel per page; only the current page plays.
    Component {
        id: playerComp
        // Immersive reel surface: no native <video> control bar, auto-loop.
        VideoWebView { directVideo: true; controls: false; loop: true }
    }

    ListView {
        id: pager
        anchors.fill: parent
        model: page.reels
        orientation: ListView.Vertical
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        highlightMoveDuration: 130          // snappier page-snap (was 200)
        maximumFlickVelocity: units.gu(700) // let a flick page promptly
        boundsBehavior: Flickable.StopAtBounds
        // Pre-creates neighbouring delegates so posters decode ahead of scroll (only the current reel mounts a WebView).
        cacheBuffer: pager.height
        clip: true

        // Menu and comments belong to one reel; swiping away would leave them on the old video
        onCurrentIndexChanged: {
            page.menuOpen = false;
            if (page.wideReels) page.syncDockedPanel();
            else if (commentSheet.visible) commentSheet.close();
        }

        // End-of-feed hint: dragging up past the last reel reveals this, then the pager snaps back (StrictlyEnforceRange keeps the last reel in range).
        footer: Item {
            width: pager.width
            height: units.gu(12)
            visible: !page.loading && page.reels.length > 0
            Column {
                // Centered on the video column, not the window: the footer belongs to the reel.
                anchors.verticalCenter: parent.verticalCenter
                x: page.stageX + (page.stageWidth - width) / 2
                spacing: units.dp(4)
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Lang.tr("You're all caught up")
                    color: "white"
                    font.pixelSize: Style.fontMedium
                    font.weight: Font.DemiBold
                    font.family: Style.fontFor(text)
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Lang.tr("No more Serey Shorts for now")
                    color: Qt.rgba(1, 1, 1, 0.6)
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
                }
            }
        }

        delegate: Item {
            id: reel
            width: pager.width
            height: pager.height
            readonly property bool current: ListView.isCurrentItem
            // caption expands over the video, not a modal
            property bool descExpanded: false

            // Vote state prefers the session cache (reflects votes cast this session), falling back to the voters list the API returned.
            readonly property var _vc: VoteService.getCached(modelData.author || "", modelData.permlink || "")
            property bool upvoted: _vc ? _vc.upvoted : (modelData.voters || []).indexOf(Session.username) >= 0
            property bool flagged: _vc ? _vc.flagged : false
            property int  votes:   _vc ? _vc.votes : (modelData.votes || 0)
            property bool busy: false

            function _vguard() {
                if (!Session.isLoggedIn) { Toast.error(Lang.tr("Please log in first.")); return false; }
                return !reel.busy;
            }
            function _vcache() {
                VoteService._updateCache(modelData.author, modelData.permlink,
                                         reel.upvoted, reel.flagged, reel.votes, modelData.payout || "");
            }
            // Optimistic: flip icon/count immediately since the async broadcast lags a couple seconds, revert only if the request fails.
            function _revert(wasUp, wasFlag, prevVotes, e) {
                reel.upvoted = wasUp; reel.flagged = wasFlag; reel.votes = prevVotes;
                reel.busy = false; reel._vcache();
                Toast.error(Lang.tr(VoteService.friendlyError(e)));
            }
            // caller anchors the weight popover to the rail's vote button
            function toggleUpvote(caller) {
                if (!_vguard()) return;
                if (reel.upvoted) {
                    var wasUp = reel.upvoted, wasFlag = reel.flagged, prevVotes = reel.votes;
                    reel.busy = true;
                    reel.upvoted = false; reel.votes = Math.max(0, reel.votes - 1); reel._vcache();
                    VoteService.removeVote(Config.baseUrl, modelData.author, modelData.permlink, "post", Session.token,
                        function (r) { reel.busy = false; },
                        function (e) { reel._revert(wasUp, wasFlag, prevVotes, e); });
                } else {
                    page._voteReel     = reel;
                    page._voteAuthor   = modelData.author   || "";
                    page._votePermlink = modelData.permlink || "";
                    var p = PopupUtils.open(Qt.resolvedUrl("../components/VoteWeightPopover.qml"), caller);
                    if (p) p.accepted.connect(page._sendUpvote);
                }
            }
            function toggleFlag() {
                if (!_vguard()) return;
                var wasUp = reel.upvoted, wasFlag = reel.flagged, prevVotes = reel.votes;
                reel.busy = true;
                if (wasFlag) {
                    reel.flagged = false; reel._vcache();
                    VoteService.removeVote(Config.baseUrl, modelData.author, modelData.permlink, "post", Session.token,
                        function (r) { reel.busy = false; },
                        function (e) { reel._revert(wasUp, wasFlag, prevVotes, e); });
                } else {
                    reel.flagged = true;
                    if (reel.upvoted) { reel.upvoted = false; reel.votes = Math.max(0, reel.votes - 1); }
                    reel._vcache();
                    VoteService.flag(Config.baseUrl, modelData.author, modelData.permlink, "post", Session.token,
                        function (r) { reel.busy = false; },
                        function (e) { reel._revert(wasUp, wasFlag, prevVotes, e); });
                }
            }

            // Geometry-only: the video column everything else anchors to. Full width on a phone,
            // a centered portrait column on a wide window.
            Item {
                id: stage
                x: page.stageX
                y: 0
                width: page.stageWidth
                height: reel.height
            }

            // Stays mounted under the player, which fades in once loaded, so the WebView's initial blank frame never shows.
            Image {
                anchors.fill: stage
                source: modelData.thumbnail || ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                // Cap decode size to a breakpoint instead of native resolution
                sourceSize.width: pager.width > units.gu(70) ? units.gu(90) : units.gu(50)
            }

            // Warm the next clip once this one is actually playing, so the prefetch never
            // competes with the video the reader is waiting on.
            Timer {
                interval: 1500
                running: reel.current && playerLoader.item !== null && playerLoader.item.ready
                         && page.nextReelUrl(index) !== ""
                onTriggered: if (playerLoader.item) playerLoader.item.prewarm(page.nextReelUrl(index))
            }

            Loader {
                id: playerLoader
                anchors.fill: stage
                active: current
                sourceComponent: playerComp
                onLoaded: item.embedUrl = modelData.videoLink
                // Poster IS the loading state (no spinner); cross-fade once ready
                opacity: (item && item.ready) ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }

            // Tap-to-pause overlay sits above the video but below the action rail and caption so taps on those still reach their targets.
            MouseArea {
                anchors.fill: stage
                z: 1
                onClicked: {
                    if (playerLoader.item) {
                        playerLoader.item.togglePause();
                        pauseIcon.opacity = 1;
                        pauseIconTimer.restart();
                    }
                }
            }

            // Brief play/pause icon flash on tap.
            Rectangle {
                id: pauseIcon
                anchors.centerIn: stage
                z: 2
                width: units.gu(8); height: width
                radius: width / 2
                color: Qt.rgba(0, 0, 0, 0.5)
                opacity: 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
                Icon {
                    anchors.centerIn: parent
                    width: units.gu(4); height: width
                    name: (playerLoader.item && playerLoader.item.paused) ? "media-playback-start" : "media-playback-pause"
                    color: "white"
                }
                Timer {
                    id: pauseIconTimer
                    interval: 800
                    onTriggered: pauseIcon.opacity = 0
                }
            }

            Rectangle {
                anchors { left: stage.left; right: stage.right; bottom: stage.bottom }
                height: reel.descExpanded ? Math.min(stage.height * 0.7, captionCol.height + units.gu(6)) : units.gu(14)
                Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: reel.descExpanded ? 0.25 : 0.0; color: Qt.rgba(0, 0, 0, 0.6) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.6) }
                }
            }
            // Caption uses Lomiri author treatment (avatar disc + name), mirroring VideoCard's author row, not a bare TikTok @handle.
            Row {
                // Right margin, not an anchor to the rail: on a wide window the rail is outside the stage.
                anchors { left: stage.left; right: stage.right; bottom: stage.bottom
                          leftMargin: Style.spacingM
                          rightMargin: page.wideReels ? Style.spacingM : (page.railWidth + Style.spacingS)
                          bottomMargin: Style.spacingM }
                spacing: Style.spacingS
                z: 3 // above the tap-to-pause overlay (z:1) and pause icon (z:2)

                Item {
                    width: units.gu(4.5); height: width
                    // Level with username, not title
                    anchors.top: parent.top

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Style.avatarTint(modelData.author || "")
                        visible: !reelAvatar.loaded
                        Label {
                            anchors.centerIn: parent
                            text: (modelData.author || "?").charAt(0).toUpperCase()
                            font.pixelSize: Style.fontMedium
                            font.bold: true
                            color: Style.brand
                        }
                    }
                    CircleImage {
                        id: reelAvatar
                        anchors.fill: parent
                        source: modelData.authorImage || ""
                        decode: units.gu(9)
                        visible: loaded
                    }
                }

                Column {
                    id: captionCol
                    width: parent.width - units.gu(4.5) - Style.spacingS
                    anchors.bottom: parent.bottom
                    spacing: units.dp(3)
                    Label {
                        width: parent.width
                        text: {
                            var handle = "@" + (modelData.author || "");
                            var d = modelData.date ? new Date(modelData.date) : null;
                            if (!d || isNaN(d.getTime())) return handle;
                            var diff = (Date.now() - d.getTime()) / 1000;
                            var rel;
                            if      (diff < 60)       rel = Math.floor(diff) + "s";
                            else if (diff < 3600)     rel = Math.floor(diff / 60) + "m";
                            else if (diff < 86400)    rel = Math.floor(diff / 3600) + "h";
                            else if (diff < 2592000)  rel = Math.floor(diff / 86400) + "d";
                            else if (diff < 31536000) rel = Math.floor(diff / 2592000) + "mo";
                            else                      rel = Math.floor(diff / 31536000) + "y";
                            return handle + "  ·  " + rel;
                        }
                        color: "white"
                        font.pixelSize: Style.fontRegular
                        font.weight: Font.DemiBold
                        font.family: Style.fontFor(text)
                        elide: Text.ElideRight
                    }
                    Label {
                        width: parent.width
                        text: modelData.title || ""
                        color: "white"
                        font.pixelSize: Style.fontRegular
                        font.weight: Font.DemiBold
                        font.family: Style.fontFor(text)
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    // collapsed: one-line preview + "more"
                    Row {
                        width: parent.width
                        spacing: units.dp(4)
                        visible: !reel.descExpanded && page._descPreview(modelData.body || "").length > 0

                        Label {
                            id: descPreviewLabel
                            // Always reserve "more" slot; depending on moreLabel.visible would loop
                            width: parent.width - moreLabel.width - units.dp(4)
                            text: page._descPreview(modelData.body || "")
                            color: Qt.rgba(1, 1, 1, 0.85)
                            font.pixelSize: Style.fontSmall
                            font.family: Style.fontFor(text)
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        AbstractButton {
                            id: moreLabel
                            visible: descPreviewLabel.truncated
                            width: moreLabelText.implicitWidth
                            height: moreLabelText.implicitHeight
                            onClicked: reel.descExpanded = true
                            Label {
                                id: moreLabelText
                                text: Lang.tr("more")
                                color: "white"
                                font.pixelSize: Style.fontSmall
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    // Expanded: full caption, scrollable if it runs long, still overlaid on the video.
                    Column {
                        width: parent.width
                        visible: reel.descExpanded
                        spacing: units.dp(4)

                        Flickable {
                            width: parent.width
                            height: Math.min(expandedBodyLabel.implicitHeight, stage.height * 0.5)
                            contentWidth: width
                            contentHeight: expandedBodyLabel.implicitHeight
                            clip: true
                            Label {
                                id: expandedBodyLabel
                                width: parent.width
                                text: page._descFull(modelData.body || "")
                                color: Qt.rgba(1, 1, 1, 0.85)
                                font.pixelSize: Style.fontSmall
                                font.family: Style.fontFor(text)
                                wrapMode: Text.Wrap
                            }
                        }

                        AbstractButton {
                            width: lessLabelText.implicitWidth
                            height: lessLabelText.implicitHeight
                            onClicked: reel.descExpanded = false
                            Label {
                                id: lessLabelText
                                text: Lang.tr("less")
                                color: "white"
                                font.pixelSize: Style.fontSmall
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }
            }

            // Comment/share open in the system browser; a second WebView over this live reel would trip the dual-Chromium crash.
            Rectangle {
                id: actionRail
                // Beside the stage on a wide window, overlaid on the video on a phone.
                x: page.wideReels ? (stage.x + stage.width + page.reelGap)
                                  : (stage.x + stage.width - width - Style.spacingS)
                anchors { bottom: stage.bottom; bottomMargin: units.gu(3) }
                width: page.railWidth
                height: railCol.height + units.gu(2)
                radius: units.gu(2)
                // The scrim only earns its keep over the video; beside it, it's a grey smudge on black.
                color: page.wideReels ? "transparent" : Qt.rgba(0, 0, 0, 0.4)
                z: 5

                Column {
                    id: railCol
                    anchors { top: parent.top; topMargin: units.gu(1)
                              horizontalCenter: parent.horizontalCenter }
                    spacing: units.gu(0.5)

                    AbstractButton {
                        id: reelUpvoteBtn
                        width: units.gu(7); height: units.gu(7)
                        enabled: !reel.busy
                        onClicked: reel.toggleUpvote(reelUpvoteBtn)
                        Column {
                            anchors.centerIn: parent
                            spacing: units.dp(2)
                            Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: units.gu(3.4); height: width
                                name: "thumb-up"
                                color: reel.upvoted ? Style.brand : "white"
                            }
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: reel.votes
                                color: "white"
                                font.pixelSize: Style.fontSmall
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    AbstractButton {
                        width: units.gu(7); height: units.gu(7)
                        enabled: !reel.busy
                        onClicked: reel.toggleFlag()
                        Icon {
                            anchors.centerIn: parent
                            width: units.gu(3.4); height: width
                            name: "thumb-down"
                            color: reel.flagged ? Style.accentRed : "white"
                        }
                    }

                    AbstractButton {
                        // Wide windows keep the comments panel open beside the reel, so there's
                        // nothing for this button to open.
                        visible: !page.wideReels
                        width: units.gu(7); height: units.gu(7)
                        onClicked: {
                            page._commentSheetPermlink = modelData.permlink || "";
                            commentSheet.open(modelData.author || "", modelData.permlink || "");
                        }
                        Column {
                            anchors.centerIn: parent
                            spacing: units.dp(2)
                            Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: units.gu(3.4); height: width
                                name: "message"
                                color: "white"
                            }
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.comments || 0
                                color: "white"
                                font.pixelSize: Style.fontSmall
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    AbstractButton {
                        id: reelShareBtn
                        width: units.gu(7); height: units.gu(7)
                        onClicked: Share.open(
                            "https://serey.io/video-component/watch?author=" + (modelData.author || "") + "&permalink=" + (modelData.permlink || ""),
                            reelShareBtn)
                        Icon {
                            anchors.centerIn: parent
                            width: units.gu(3.4); height: width
                            name: "share"
                            color: "white"
                        }
                    }

                    AbstractButton {
                        id: reelMoreBtn
                        width: units.gu(7); height: units.gu(7)
                        onClicked: page.openReelMenu(modelData, reelMoreBtn)
                        Column {
                            anchors.centerIn: parent
                            spacing: units.dp(3)
                            Repeater {
                                model: 3
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: units.dp(4); height: width
                                    radius: width / 2
                                    color: "white"
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Dismiss the dropdown on outside click; above the docked panel (z 2000), which the
    // wide-mode "..." lives in, else the menu would open behind it.
    MouseArea {
        anchors.fill: parent
        visible: page.menuOpen
        z: 2400
        onClicked: page.menuOpen = false
    }

    // Compact anchored dropdown, same shape as VideoCard's cardMenu
    Rectangle {
        id: reelMenu
        visible: page.menuOpen
        z: 2500
        // Opens beside the rail, bottom-aligned with the "..." button, so it never covers the buttons it belongs to.
        x: Math.max(Style.spacingXs, page._menuAnchorTL.x - width - Style.spacingS)
        y: Math.max(Style.spacingXs,
                    Math.min(page._menuAnchorBR.y - height, page.height - height - Style.spacingXs))
        width: Math.min(units.gu(30), page.width - Style.spacingM * 2)
        height: reelMenuCol.height
        radius: Style.cardRadius
        color: Style.surface
        border.width: units.dp(1)
        border.color: Style.divider

        Column {
            id: reelMenuCol
            width: parent.width

            Repeater {
                // {divider:true} | {icon, label, danger, action}
                model: page.reelMenuItems()
                delegate: Item {
                    width: reelMenuCol.width
                    height: modelData.divider ? units.dp(1) : units.gu(5.5)

                    Rectangle {
                        visible: !!modelData.divider
                        anchors.fill: parent
                        color: Style.divider
                    }

                    AbstractButton {
                        visible: !modelData.divider
                        anchors.fill: parent
                        onClicked: { page.menuOpen = false; page.runReelMenuAction(modelData.action); }
                        Row {
                            anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                            spacing: Style.spacingM
                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                width: units.gu(2.2); height: width
                                name: modelData.icon || ""
                                color: modelData.danger ? Style.danger : Style.textPrimary
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(0, parent.width - units.gu(2.2) - parent.spacing)
                                elide: Text.ElideRight
                                text: modelData.label || ""
                                font.pixelSize: Style.fontSmall
                                font.family: Style.fontFor(text)
                                color: modelData.danger ? Style.danger : Style.textPrimary
                            }
                        }
                    }
                }
            }

            // Block: no "block" glyph in the Suru set, so draw one (same as VideoCard/PostCard)
            Rectangle { visible: !reelMenu._isOwn; width: parent.width; height: units.dp(1); color: Style.divider }
            AbstractButton {
                visible: !reelMenu._isOwn
                width: parent.width
                height: units.gu(5.5)
                onClicked: { page.menuOpen = false; PostActions.open(page._menuVideo, "video", 3); }
                Row {
                    anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                    spacing: Style.spacingM
                    Item {
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
                        width: Math.max(0, parent.width - units.gu(2.2) - parent.spacing)
                        elide: Text.ElideRight
                        text: Lang.tr("Block %1").arg(page._menuVideo ? (page._menuVideo.author || "") : "")
                        font.pixelSize: Style.fontSmall
                        font.family: Style.fontFor(text)
                        color: Style.danger
                    }
                }
            }
        }

        readonly property bool _isOwn: page._menuVideo && Session.isLoggedIn
                                       && page._menuVideo.author === Session.username
    }

    // Mouse-wheel equivalent of swipe/keyboard reel navigation
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        z: 10
        property bool cooling: false
        onWheel: (wheel) => {
            if (!cooling) {
                if (wheel.angleDelta.y < 0) pager.incrementCurrentIndex();
                else if (wheel.angleDelta.y > 0) pager.decrementCurrentIndex();
                cooling = true;
                wheelCooldown.restart();
            }
            wheel.accepted = true;
        }
        Timer { id: wheelCooldown; interval: 350; onTriggered: parent.cooling = false }
    }

    // Back button (the app header/nav are hidden on this pushed page).
    BackButton {
        anchors { left: parent.left; top: parent.top; leftMargin: Style.spacingS; topMargin: Style.spacingS }
        z: 100
        overlay: true
        onClicked: page.pageStack.pop()
    }

    // In-app comment thread (no WebView, safe to overlay the live reel player).
    // Wide windows dock it beside the rail instead of covering the reel with a modal.
    CommentsSheet {
        id: commentSheet
        docked: page.wideReels
        // Flush right rail, full height: the same shape as the video detail side panel.
        dockRect: Qt.rect(page.width - page.commentsWidth, 0, page.commentsWidth, page.height)
    }

    // Splitter: hairline that lights up on hover, with a wider invisible grab strip over it.
    // Above the panel's own z 2000, else the rail paints over both.
    Rectangle {
        visible: page.wideReels
        anchors { top: parent.top; bottom: parent.bottom }
        x: page.width - page.commentsWidth - width
        width: units.dp(1)
        z: 2050
        color: (commentsDragArea.containsMouse || commentsDragArea.pressed) ? Style.brand : Style.divider
    }
    MouseArea {
        id: commentsDragArea
        visible: page.wideReels
        anchors { top: parent.top; bottom: parent.bottom }
        x: page.width - page.commentsWidth - width / 2
        width: units.gu(1.5)
        z: 2051
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.SplitHCursor
        onPositionChanged: {
            if (!pressed) return;
            var pagePointX = mapToItem(page, mouse.x, 0).x;
            page.commentsPanelWidth = Math.max(page._minCommentsW,
                Math.min(page._maxCommentsW, page.width - pagePointX));
        }
    }

    // The rail only becomes visible once a reel exists to load comments for, so hold its
    // space with the panel background: otherwise the whole window is black while loading
    // and the splitter floats over nothing.
    Rectangle {
        visible: page.wideReels && !commentSheet.visible
        x: page.width - page.commentsWidth
        width: page.commentsWidth
        anchors { top: parent.top; bottom: parent.bottom }
        z: 1900
        color: Style.surface
    }

    // Centered on the video column, not the window: the rail is not part of the stage.
    ActivityIndicator {
        anchors.verticalCenter: parent.verticalCenter
        x: (page.stageArea - width) / 2
        running: page.loading
        visible: running
    }

    EmptyState {
        anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
        width: page.stageArea
        visible: !page.loading && page.reels.length === 0
        iconName: "camcorder"
        message: page.errorMsg !== "" ? page.errorMsg : Lang.tr("No Serey Shorts yet")
    }
}
