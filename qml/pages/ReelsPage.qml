import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/VideoService.js" as VideoService
import "../services/VoteService.js" as VoteService

Page {
    id: page

    // Keyboard equivalent of swipe-between-reels
    focus: true
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Down || event.key === Qt.Key_PageDown) {
            pager.incrementCurrentIndex();
            event.accepted = true;
        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_PageUp) {
            pager.decrementCurrentIndex();
            event.accepted = true;
        }
    }

    property var reels: []
    property bool loading: true
    property string errorMsg: ""
    property int startIndex: 0

    // Pending vote — set by the delegate before opening the weight dialog.
    property var    _voteReel:    null
    property string _voteAuthor:  ""
    property string _votePermlink: ""

    // Full-description sheet — set by whichever reel's "more" was tapped
    property string _descTitle: ""
    property string _descBody: ""
    property bool descSheetOpen: false

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

    function _sendUpvote(weight) {
        var reel = page._voteReel;
        if (!reel) return;
        reel.busy = true;
        VoteService.upvote(Config.baseUrl, page._voteAuthor, page._votePermlink, "post", weight, Session.token,
            function (r) {
                if (!reel.upvoted) reel.votes = reel.votes + 1;
                reel.upvoted = true; reel.flagged = false; reel.busy = false;
                VoteService._updateCache(page._voteAuthor, page._votePermlink, true, false, reel.votes, "");
                Toast.success(Lang.tr("Upvoted %1%").arg(weight));
            },
            function (e) {
                reel.busy = false;
                Toast.error((e && e.message) ? e.message : Lang.tr("Action failed."));
            });
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

    header: Item { height: 0 }

    Component.onCompleted: load()

    function load() {
        page.loading = true;
        page.errorMsg = "";
        var params = { limit: 50, offset: 0 };
        if (Config.communityId > 0)
            params.community_id = Config.communityId;
        VideoService.listVideos(Config.baseUrl, params, Session.token,
            function (result) {
                if (!page) return;          // popped mid-load — page destroyed
                page.reels = result.filter(function (v) {
                    return v.platform === "SEREY" && (v.videoLink || "").length > 0;
                });
                if (page.reels.length > 0) {
                    var idx = Math.max(0, Math.min(page.startIndex, page.reels.length - 1));
                    pager.positionViewAtIndex(idx, ListView.Beginning);
                    pager.currentIndex = idx;
                }
                page.loading = false;
            },
            function (err) {
                if (!page) return;
                page.loading = false;
                page.errorMsg = (err && err.message) ? err.message : Lang.tr("Couldn't load reels.");
            });
    }

    // Model is a plain JS array — reassign (not mutate) to refresh delegates, and restore pager position; the current reel remounts.
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

        // End-of-feed hint: dragging up past the last reel reveals this, then the pager snaps back (StrictlyEnforceRange keeps the last reel in range).
        footer: Item {
            width: pager.width
            height: units.gu(12)
            visible: !page.loading && page.reels.length > 0
            Column {
                anchors.centerIn: parent
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
                    text: Lang.tr("No more reels for now")
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
                Toast.error((e && e.message) ? e.message : Lang.tr("Action failed."));
            }
            function toggleUpvote() {
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
                    PopupUtils.open(voteWeightDialog);
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

            // Stays mounted under the player, which fades in once loaded, so the WebView's initial blank frame never shows.
            Image {
                anchors.fill: parent
                source: modelData.thumbnail || ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                // Cap decode size to a breakpoint instead of native resolution
                sourceSize.width: pager.width > units.gu(70) ? units.gu(90) : units.gu(50)
            }

            Loader {
                id: playerLoader
                anchors.fill: parent
                active: current
                sourceComponent: playerComp
                onLoaded: item.embedUrl = modelData.videoLink
                // Poster IS the loading state (no spinner) — cross-fade once ready
                opacity: (item && item.ready) ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }

            // Tap-to-pause overlay sits above the video but below the action rail and caption so taps on those still reach their targets.
            MouseArea {
                anchors.fill: parent
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
                anchors.centerIn: parent
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

            // Bottom gradient + caption.
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: units.gu(14)
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.6) }
                }
            }
            // Caption uses Lomiri author treatment (avatar disc + name), mirroring VideoCard's author row, not a bare TikTok @handle.
            Row {
                anchors { left: parent.left; right: actionRail.left; bottom: parent.bottom
                          leftMargin: Style.spacingM; rightMargin: Style.spacingS; bottomMargin: Style.spacingM }
                spacing: Style.spacingS
                z: 3 // above the tap-to-pause overlay (z:1) and pause icon (z:2)

                Item {
                    width: units.gu(4.5); height: width
                    anchors.bottom: parent.bottom

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

                    Row {
                        width: parent.width
                        spacing: units.dp(4)
                        visible: page._descPreview(modelData.body || "").length > 0

                        Label {
                            id: descPreviewLabel
                            // Always reserve the "more" slot. Making the width depend on
                            // moreLabel.visible looped: visible <- this.truncated <- this.width.
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
                            onClicked: {
                                page._descTitle = modelData.title || "";
                                page._descBody = modelData.body || "";
                                page.descSheetOpen = true;
                            }
                            Label {
                                id: moreLabelText
                                text: Lang.tr("more")
                                color: "white"
                                font.pixelSize: Style.fontSmall
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }
            }

            // Comment/share open in the system browser — a second WebView over this live reel would trip the dual-Chromium crash.
            Rectangle {
                id: actionRail
                anchors { right: parent.right; rightMargin: Style.spacingS
                          bottom: parent.bottom; bottomMargin: units.gu(3) }
                width: units.gu(7)
                height: railCol.height + units.gu(2)
                radius: units.gu(2)
                color: Qt.rgba(0, 0, 0, 0.4)
                z: 5

                Column {
                    id: railCol
                    anchors { top: parent.top; topMargin: units.gu(1)
                              horizontalCenter: parent.horizontalCenter }
                    spacing: units.gu(0.5)

                    // Upvote
                    AbstractButton {
                        width: units.gu(7); height: units.gu(7)
                        enabled: !reel.busy
                        onClicked: reel.toggleUpvote()
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

                    // Downvote
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

                    // Comment
                    AbstractButton {
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

                    // Share
                    AbstractButton {
                        width: units.gu(7); height: units.gu(7)
                        onClicked: Share.open(
                            "https://serey.io/video-component/watch?author=" + (modelData.author || "") + "&permalink=" + (modelData.permlink || ""))
                        Icon {
                            anchors.centerIn: parent
                            width: units.gu(3.4); height: width
                            name: "share"
                            color: "white"
                        }
                    }

                    // More (3-dot)
                    AbstractButton {
                        width: units.gu(7); height: units.gu(7)
                        onClicked: PostActions.open(modelData, "video")
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

    // In-app comment thread (no WebView — safe to overlay the live reel player).
    CommentsSheet { id: commentSheet }

    // Full-description bottom sheet, opened from a reel's "more" tap
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
                        text: page._descTitle
                        font.pixelSize: Style.fontLarge
                        font.weight: Font.DemiBold
                        font.family: Style.fontFor(text)
                        color: Style.textPrimary
                        wrapMode: Text.Wrap
                    }

                    Label {
                        width: parent.width - Style.spacingM * 2
                        x: Style.spacingM
                        text: page._descFull(page._descBody)
                        font.pixelSize: Style.fontRegular
                        font.family: Style.fontFor(text)
                        color: Style.textPrimary
                        wrapMode: Text.Wrap
                    }

                    Item { width: 1; height: Style.spacingL }
                }
            }
        }
    }

    ActivityIndicator {
        anchors.centerIn: parent
        running: page.loading
        visible: running
    }

    EmptyState {
        anchors.fill: parent
        visible: !page.loading && page.reels.length === 0
        iconName: "camcorder"
        message: page.errorMsg !== "" ? page.errorMsg : Lang.tr("No reels yet")
    }
}
