import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/VideoService.js" as VideoService
import "../services/VoteService.js" as VoteService

/*
 * Vertical, full-screen reels viewer for short native (SEREY-platform) videos —
 * the mobile counterpart of the web's ReelPage. A snapping vertical ListView
 * pages through reels TikTok-style; only the current item mounts a VideoWebView
 * (directVideo), so at most ONE in-app Chromium surface is ever live (two live
 * WebViews crash the app — see the dual-Chromium memory note).
 *
 * Matching the web (ReelPage/filterByDuration): a reel is a native SEREY-platform
 * video AND duration <= 180s. Duration is probed in a hidden Chromium <video>
 * (VideoDurationProbe); clips whose duration can't be determined are excluded,
 * exactly like the web. Probing runs while `probing` is true, during which the
 * player WebView is NOT mounted, so only one Chromium surface is ever live.
 */
Page {
    id: page

    readonly property int maxReelSeconds: 180
    readonly property int maxCandidates: 30   // cap probing work on a phone

    property var reels: []
    property bool loading: true
    property bool probing: false
    property string errorMsg: ""

    property var _queue: []
    property var _accum: []

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
                var candidates = result
                    .filter(function (v) { return v.platform === "SEREY" && (v.videoLink || "").length > 0; })
                    .slice(0, page.maxCandidates);
                if (candidates.length === 0) { page.reels = []; page.loading = false; return; }
                page._queue = candidates;
                page._accum = [];
                page.probing = true;        // mounts the prober (player stays unmounted)
                page._probeNext();
            },
            function (err) {
                if (!page) return;
                page.loading = false;
                page.errorMsg = (err && err.message) ? err.message : i18n.tr("Couldn't load reels.");
            });
    }

    // Sequentially probe each candidate's duration; keep only shorts (<= 180s).
    function _probeNext() {
        if (!page) return;
        if (page._queue.length === 0) {
            page.reels = page._accum;
            page.probing = false;           // unmount prober before the player mounts
            page.loading = false;
            return;
        }
        var v = page._queue.shift();
        probeLoader.item.probe(v.videoLink, function (dur) {
            if (!page) return;
            if (dur > 0 && dur <= page.maxReelSeconds)
                page._accum.push(v);
            page._probeNext();
        });
    }

    // Mounted only while probing, so it never coexists with the player WebView.
    Loader {
        id: probeLoader
        active: page.probing
        sourceComponent: VideoDurationProbe {}
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
        cacheBuffer: 0            // never mount neighbouring WebViews
        clip: true

        delegate: Item {
            id: reel
            width: pager.width
            height: pager.height
            readonly property bool current: ListView.isCurrentItem

            // Vote state, seeded from the session vote cache (a reel the user
            // already upvoted stays blue across navigation). Voting is signed
            // server-side via XHR — no second Chromium surface — so it's safe to
            // do here, on top of the live reel WebView.
            readonly property var _vc: VoteService.getCached(modelData.author || "", modelData.permlink || "")
            property bool upvoted: _vc ? _vc.upvoted : false
            property bool flagged: _vc ? _vc.flagged : false
            property int  votes:   _vc ? _vc.votes : (modelData.votes || 0)
            property bool busy: false

            function _vguard() {
                if (!Session.isLoggedIn) { Toast.error(i18n.tr("Please log in first.")); return false; }
                return !reel.busy;
            }
            function _vcache() {
                VoteService._updateCache(modelData.author, modelData.permlink,
                                         reel.upvoted, reel.flagged, reel.votes, modelData.payout || "");
            }
            function _vfail(e) {
                reel.busy = false;
                Toast.error((e && e.message) ? e.message : i18n.tr("Action failed."));
            }
            function toggleUpvote() {
                if (!_vguard()) return;
                reel.busy = true;
                if (reel.upvoted) {
                    VoteService.removeVote(Config.baseUrl, modelData.author, modelData.permlink, "post", Session.token,
                        function (r) { reel.busy = false; reel.upvoted = false; reel.votes = Math.max(0, reel.votes - 1);
                                       reel._vcache(); Toast.show(i18n.tr("Vote removed")); }, _vfail);
                } else {
                    VoteService.upvote(Config.baseUrl, modelData.author, modelData.permlink, "post", 100, Session.token,
                        function (r) { reel.busy = false; reel.upvoted = true; reel.flagged = false; reel.votes = reel.votes + 1;
                                       reel._vcache(); Toast.success(i18n.tr("Upvoted")); }, _vfail);
                }
            }
            function toggleFlag() {
                if (!_vguard()) return;
                reel.busy = true;
                if (reel.flagged) {
                    VoteService.removeVote(Config.baseUrl, modelData.author, modelData.permlink, "post", Session.token,
                        function (r) { reel.busy = false; reel.flagged = false;
                                       reel._vcache(); Toast.show(i18n.tr("Vote removed")); }, _vfail);
                } else {
                    VoteService.flag(Config.baseUrl, modelData.author, modelData.permlink, "post", Session.token,
                        function (r) { reel.busy = false; reel.flagged = true;
                                       if (reel.upvoted) { reel.upvoted = false; reel.votes = Math.max(0, reel.votes - 1); }
                                       reel._vcache(); Toast.show(i18n.tr("Downvoted")); }, _vfail);
                }
            }

            // Poster — stays mounted UNDER the player the whole time. The player
            // fades in only once its page has loaded, so the WebView's initial
            // blank/black frame never shows (that was the scroll-in flicker).
            Image {
                anchors.fill: parent
                source: modelData.thumbnail || ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                // Cap the decode size — full-screen on a phone would otherwise
                // decode at the source's native resolution. Snap to a breakpoint
                // (docs/ubports-other-considerations/02-scaling-images.md).
                sourceSize.width: pager.width > units.gu(70) ? units.gu(90) : units.gu(50)
            }

            Loader {
                id: playerLoader
                anchors.fill: parent
                active: current && !page.probing
                sourceComponent: playerComp
                onLoaded: item.embedUrl = modelData.videoLink
                // Reveal over the poster only when the <video> page is up.
                opacity: (item && item.ready) ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 180 } }
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
            // Caption — Lomiri author treatment (avatar disc + name), mirroring
            // VideoCard's author row, not a bare TikTok @handle.
            Row {
                anchors { left: parent.left; right: actionRail.left; bottom: parent.bottom
                          leftMargin: Style.spacingM; rightMargin: Style.spacingS; bottomMargin: Style.spacingM }
                spacing: Style.spacingS

                Item {
                    width: units.gu(4.5); height: width
                    anchors.bottom: parent.bottom

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Style.avatarTint(modelData.author || "")
                        visible: (modelData.authorImage || "") === ""
                        Label {
                            anchors.centerIn: parent
                            text: (modelData.author || "?").charAt(0).toUpperCase()
                            font.pixelSize: Style.fontMedium
                            font.bold: true
                            color: Style.brand
                        }
                    }
                    CircleImage {
                        anchors.fill: parent
                        source: modelData.authorImage || ""
                        decode: units.gu(9)
                        visible: (modelData.authorImage || "") !== ""
                    }
                }

                Column {
                    width: parent.width - units.gu(4.5) - Style.spacingS
                    anchors.bottom: parent.bottom
                    spacing: units.dp(2)
                    Label {
                        text: "@" + (modelData.author || "")
                        color: "white"
                        font.pixelSize: Style.fontRegular
                        font.weight: Font.DemiBold
                        font.family: Style.fontFamily
                    }
                    Label {
                        width: parent.width
                        text: modelData.title || ""
                        color: "white"
                        font.pixelSize: Style.fontSmall
                        font.family: Style.fontFamily
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }
            }

            // TikTok-style vertical action rail. Upvote/downvote post signed
            // votes via XHR (no WebView). Comment/share open the thread in the
            // system browser (mounting the detail page's WebView over this live
            // reel would crash — see the dual-Chromium note).
            Column {
                id: actionRail
                anchors { right: parent.right; rightMargin: Style.spacingS
                          bottom: parent.bottom; bottomMargin: units.gu(3) }
                spacing: units.gu(2)

                // Upvote
                AbstractButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: units.gu(6); height: upCol.height
                    enabled: !reel.busy
                    onClicked: reel.toggleUpvote()
                    Column {
                        id: upCol
                        anchors.horizontalCenter: parent.horizontalCenter
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
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: units.gu(6); height: downIcon.height
                    enabled: !reel.busy
                    onClicked: reel.toggleFlag()
                    Icon {
                        id: downIcon
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: units.gu(3.4); height: width
                        name: "thumb-down"
                        color: reel.flagged ? Style.accentRed : "white"
                    }
                }

                // Comment (opens the thread externally)
                AbstractButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: units.gu(6); height: cmtCol.height
                    onClicked: Qt.openUrlExternally(
                        "https://serey.io/authors/@" + (modelData.author || "") + "/" + (modelData.permlink || ""))
                    Column {
                        id: cmtCol
                        anchors.horizontalCenter: parent.horizontalCenter
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
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: units.gu(6); height: units.gu(3.4)
                    onClicked: Qt.openUrlExternally(
                        "https://serey.io/authors/@" + (modelData.author || "") + "/" + (modelData.permlink || ""))
                    Icon {
                        anchors.centerIn: parent
                        width: units.gu(3.4); height: width
                        name: "share"
                        color: "white"
                    }
                }
            }
        }
    }

    // Back button (the app header/nav are hidden on this pushed page).
    AbstractButton {
        anchors { top: parent.top; left: parent.left; topMargin: Style.spacingM; leftMargin: Style.spacingM }
        width: units.gu(5); height: width
        z: 20
        onClicked: page.pageStack.pop()
        Rectangle { anchors.fill: parent; radius: width / 2; color: Qt.rgba(0, 0, 0, 0.45) }
        Icon { anchors.centerIn: parent; width: units.gu(2.5); height: width; name: "back"; color: "white" }
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
        message: page.errorMsg !== "" ? page.errorMsg : i18n.tr("No reels yet")
    }
}
