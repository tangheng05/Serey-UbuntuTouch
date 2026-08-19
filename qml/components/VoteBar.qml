import QtQuick 2.7
import QtQuick.Layouts 1.3
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../Theme"
import "../Session"
import "../services/VoteService.js" as VoteService

RowLayout {
    id: bar

    property string author: ""
    property string permlink: ""
    property string voteType: "post"

    property int votes: 0
    property int flaggers: 0
    property int comments: 0
    property string payout: ""
    // Usernames who upvoted (Mappers.js's `voters` array); backs the hover/press-and-hold "who upvoted" popover.
    property var voters: []

    property bool upvoted: false
    property bool flagged: false
    property bool busy: false
    // Off-chain (DB-only) posts: like/dislike stay, but weight popover and payout pill are suppressed, mirroring the web's simpleVote/showCoins.
    property bool onChain: true
    property bool showComments: true
    property bool showShare: true
    property bool showVotersLabel: false
    // Cluster everything to the left instead of pushing the coin pill to the bar's far edge.
    property bool compact: false
    // Keyboard nav highlight, set by a host page's arrow-key handling: 0 = upvote, 1 = downvote, -1 = none.
    property int keyboardHighlight: -1

    readonly property bool allowFlag: author !== Session.username
    readonly property string shareUrl: (author.length > 0 && permlink.length > 0)
        ? ("https://serey.io/authors/" + author + "/" + permlink) : ""

    signal requireLogin()
    signal commentRequested()

    spacing: Style.spacingM

    // "alice, bob and 4 more" summary; `voters` may be a plain array or a wrapped ListModel
    function _votersText() {
        var v = bar.voters;
        if (!v) return "";
        var n = (typeof v.length === "number") ? v.length : (typeof v.count === "number" ? v.count : 0);
        if (n === 0) return "";
        var shown = [];
        var limit = Math.min(n, 6);
        for (var i = 0; i < limit; i++) {
            var item = (typeof v.get === "function") ? v.get(i) : v[i];
            var name = (item && item.modelData !== undefined) ? item.modelData : item;
            // Only accept real usernames; a ListModel-wrapped entry stringifies as garbage
            if (typeof name === "string" && name.length > 0) shown.push("@" + name);
        }
        if (shown.length === 0) return "";
        var text = shown.join(", ");
        var extra = n - limit;
        return extra > 0 ? text + " " + Lang.tr("and %1 more").arg(extra) : text;
    }

    function _guard() {
        if (!Session.isLoggedIn) {
            Toast.error(Lang.tr("Please log in first."));
            bar.requireLogin();
            return false;
        }
        // Offline, the vote would sit out the whole broadcast timeout with the button dimmed.
        if (!Net.online) {
            Toast.error(Lang.tr("You're offline. Try again once you're back on a network."));
            return false;
        }
        // An on-chain broadcast can take 20s+; without a word the button reads as broken.
        // Once per busy period, so repeated taps don't stack toasts.
        if (bar.busy) {
            if (!bar._blockedNoticeShown) {
                bar._blockedNoticeShown = true;
                Toast.show(Lang.tr("Still sending your last vote..."));
            }
            return false;
        }
        return true;
    }
    property bool _blockedNoticeShown: false

    // A ListView recycles this bar onto another row mid-request. `busy` is imperative state
    // that must not ride along, or the new row's button is dead until the old post's vote
    // returns (observed: a 24s remove-vote killing upvote on two unrelated posts).
    function _rebound() {
        bar.busy = false;
        bar._replayTap = false;
    }
    onBusyChanged: if (!busy) bar._blockedNoticeShown = false
    onAuthorChanged: bar._rebound()
    onPermlinkChanged: bar._rebound()

    // Identifies the post a request was sent for; a reply arriving after recycling belongs
    // to a post this bar no longer shows, so it must not write payout/flaggers into it.
    function _reqKey() { return bar.author + "/" + bar.permlink; }
    function _stale(key) { return key !== bar._reqKey(); }
    // A tap that arrived mid-broadcast, replayed once this one lands.
    property bool _replayTap: false
    function _finishBusy() {
        bar.busy = false;
        if (bar._replayTap) {
            bar._replayTap = false;
            bar.doUpvote();
        }
    }
    // Reconcile server-confirmed fields; count isn't taken from r.voterCount, which lags the broadcast
    function _apply(r) {
        bar.flaggers = r.flaggerCount;
        if (r.payout)
            bar.payout = r.payout;
        bar._finishBusy();
    }
    // Snapshot / restore for optimistic rollback when an on-chain broadcast fails.
    function _snapshot() {
        return { upvoted: bar.upvoted, flagged: bar.flagged, votes: bar.votes, payout: bar.payout };
    }
    function _rollback(s) {
        bar.upvoted = s.upvoted; bar.flagged = s.flagged;
        bar.votes = s.votes; bar.payout = s.payout;
        bar._cache();
    }
    function _cache() {
        VoteService._updateCache(bar.author, bar.permlink, bar.upvoted, bar.flagged, bar.votes, bar.payout);
        Session.saveVote(bar.author, bar.permlink, bar.upvoted, bar.flagged, bar.votes);
    }

    function loadPersisted() {
        var saved = Session.loadVote(bar.author, bar.permlink);
        if (saved) {
            bar.upvoted = saved.upvoted;
            bar.flagged = saved.flagged;
            bar.votes   = saved.votes;
        }
    }
    // A 401 is already surfaced by Http.js's global unauthorized handler; don't double-toast
    function _isHandledAuthFailure(e) {
        return !!e && e.status === 401;
    }
    // Shared failure handler: undo the optimistic change, surface error unless it's a 401
    function _failReverting(e, snap) {
        // A timeout means we stopped waiting, not that the vote was refused: the chain
        // broadcast is usually still landing. Rolling back and shouting about it was the
        // "couldn't record that vote" toast users saw for votes that went through.
        if (e && e.timeout) { bar._finishBusy(); return; }
        bar.busy = false;
        bar._replayTap = false;   // the state the queued tap assumed just got rolled back
        _rollback(snap);
        if (_isHandledAuthFailure(e))
            return;
        Toast.error(Lang.tr(VoteService.friendlyError(e)));
    }
    // "You have already removed vote" is the server agreeing the vote is gone, so our
    // optimistic un-vote is right. Reverting it put the row back to blue with the old
    // count, which is the opposite of what happened on chain.
    function _failRemove(e, snap) {
        var msg = (e && e.message) ? e.message.toLowerCase() : "";
        if (!_isHandledAuthFailure(e) && msg.indexOf("already") >= 0) {
            bar._cache();
            bar._finishBusy();
            return;
        }
        bar._failReverting(e, snap);
    }
    // "Already voted" means our optimistic upvote is already correct: keep it, no rollback
    function _failUpvote(e, snap) {
        var msg = (e && e.message) ? e.message.toLowerCase() : "";
        if (!_isHandledAuthFailure(e) && msg.indexOf("already") >= 0) {
            bar._finishBusy();   // our optimistic upvote stands, so a queued undo is still valid
            return;
        }
        bar._failReverting(e, snap);
    }

    // Same deal for the flag direction: "already voted in a similar way" is the
    // server confirming the flag is on chain, even when the feed's flaggers list
    // (server-cached) hasn't caught up. Reverting turned the icon grey again a
    // second after the tap.
    function _failFlag(e, snap) {
        var msg = (e && e.message) ? e.message.toLowerCase() : "";
        if (!_isHandledAuthFailure(e) && msg.indexOf("already") >= 0) {
            bar._finishBusy();
            return;
        }
        bar._failReverting(e, snap);
    }

    function doUpvote() {
        // Tapping again during a broadcast almost always means "undo that". Refusing for the
        // 20s+ a chain write can take reads as a broken button, so queue it and replay on
        // completion. Only the direct remove path: replaying a first-time upvote would pop
        // the weight popover long after the tap that asked for it.
        if (Session.isLoggedIn && bar.busy) {
            if (bar.upvoted && !bar._replayTap) {
                bar._replayTap = true;
                Toast.show(Lang.tr("Will apply once your current vote finishes."));
            }
            return;
        }
        if (!_guard())
            return;
        if (bar.upvoted) {
            bar._sendRemoveVote();
        } else if (bar.voteType === "comment" || !bar.onChain) {
            // Comments and off-chain posts: simple one-tap like, no weight popover
            bar._sendUpvote(100);
        } else {
            // Anchored to the button, so the post stays visible while you pick a weight
            var p = PopupUtils.open(Qt.resolvedUrl("VoteWeightPopover.qml"), upvoteBtn);
            if (p) p.accepted.connect(bar._sendUpvote);
        }
    }

    // Optimistic un-vote: drop the vote and toast now, broadcast in the background.
    function _sendRemoveVote() {
        var snap = _snapshot();
        bar.upvoted = false;
        bar.votes = Math.max(0, bar.votes - 1);
        bar._cache();
        Toast.show(Lang.tr("Vote removed"));
        bar.busy = true;
        var key = bar._reqKey();
        VoteService.removeVote(Config.baseUrl, author, permlink, voteType, Session.token,
            function (r) { if (bar._stale(key)) return; _apply(r); bar._cache(); },
            function (e) { if (bar._stale(key)) return; bar._failRemove(e, snap); });
    }

    // Optimistic upvote: count and toast immediately, broadcast runs in the background
    function _sendUpvote(weight) {
        var snap = _snapshot();
        if (!bar.upvoted) bar.votes = bar.votes + 1;
        bar.upvoted = true;
        bar.flagged = false;
        bar._cache();
        Toast.success(bar.voteType === "comment" ? Lang.tr("Liked") : Lang.tr("Thanks for your vote!"));
        bar.busy = true;
        var key = bar._reqKey();
        VoteService.upvote(Config.baseUrl, author, permlink, voteType, weight, Session.token,
            function (r) { if (bar._stale(key)) return; _apply(r); bar._cache(); },
            function (e) { if (bar._stale(key)) return; bar._failUpvote(e, snap); });
    }

    function doFlag() {
        if (!allowFlag || !_guard())
            return;
        var snap = _snapshot();
        var key = bar._reqKey();
        if (bar.flagged) {
            // Optimistic un-flag.
            bar.flagged = false;
            bar._cache();
            Toast.show(Lang.tr("Vote removed"));
            bar.busy = true;
            VoteService.removeVote(Config.baseUrl, author, permlink, voteType, Session.token,
                function (r) { if (bar._stale(key)) return; _apply(r); bar._cache(); },
                function (e) { if (bar._stale(key)) return; bar._failRemove(e, snap); });
        } else {
            // Optimistic flag; a flag clears any existing upvote.
            if (bar.upvoted) bar.votes = Math.max(0, bar.votes - 1);
            bar.flagged = true;
            bar.upvoted = false;
            bar._cache();
            Toast.show(Lang.tr("Thanks for your feedback!"));
            bar.busy = true;
            VoteService.flag(Config.baseUrl, author, permlink, voteType, Session.token,
                function (r) { if (bar._stale(key)) return; _apply(r); bar._cache(); },
                function (e) { if (bar._stale(key)) return; bar._failFlag(e, snap); });
        }
    }

    // Upvote / like: hollow outline when not voted, filled blue when voted.
    AbstractButton {
        id: upvoteBtn
        Layout.preferredHeight: units.gu(3.5)
        Layout.preferredWidth: upRow.implicitWidth
        // Dimmed while the broadcast is out: taps are refused, and a solid button lies about that
        opacity: bar.busy ? 0.45 : 1
        Behavior on opacity { NumberAnimation { duration: 120 } }
        onClicked: bar.doUpvote()
        Rectangle {
            anchors.fill: parent
            radius: Style.cardRadius
            color: "transparent"
            border.width: bar.keyboardHighlight === 0 ? units.dp(2) : 0
            border.color: Style.brand
        }
        Row {
            id: upRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacingXs

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: units.gu(2.5); height: width
                name: "thumb-up"
                color: bar.upvoted ? Style.brand : Style.textSecondary
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: bar.votes
                font.pixelSize: Style.fontRegular
                color: bar.upvoted ? Style.brand : Style.textPrimary
            }
        }

        // Hover/press-and-hold reveals who upvoted; short taps fall through to upvoteBtn's click
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            propagateComposedEvents: true
            onEntered: if (bar._votersText().length > 0) votersHoverTimer.restart()
            onExited: { votersHoverTimer.stop(); votersPopup.visible = false }
            onPressAndHold: (mouse) => { if (bar._votersText().length > 0) votersPopup.visible = true; }
            onReleased: votersPopup.visible = false
            onClicked: (mouse) => { mouse.accepted = false; }
        }

        Timer { id: votersHoverTimer; interval: 500; onTriggered: votersPopup.visible = true }

        Rectangle {
            id: votersPopup
            visible: false
            anchors { bottom: parent.top; bottomMargin: Style.spacingXs }
            // Centered on the button but clamped inside the bar so a long list can't run off-screen
            x: {
                var centered = (upvoteBtn.width - width) / 2;
                var minX = -upvoteBtn.x;
                var maxX = bar.width - upvoteBtn.x - width;
                return Math.max(minX, Math.min(centered, maxX));
            }
            width: votersLabel.width + Style.spacingM * 2
            height: votersLabel.height + Style.spacingS * 2
            radius: Style.cardRadius
            color: Style.toastBg
            z: 1000
            Label {
                id: votersLabel
                anchors.centerIn: parent
                // Wrap once the list is wider than the bar.
                width: Math.min(implicitWidth, bar.width - Style.spacingM * 2)
                wrapMode: Text.Wrap
                text: bar._votersText()
                color: "white"
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFor(text)
            }
        }
    }

    AbstractButton {
        id: downvoteBtn
        Layout.preferredHeight: units.gu(3.5)
        Layout.preferredWidth: downRow.implicitWidth
        visible: bar.allowFlag
        opacity: bar.busy ? 0.45 : 1
        Behavior on opacity { NumberAnimation { duration: 120 } }
        onClicked: bar.doFlag()
        Rectangle {
            anchors.fill: parent
            radius: Style.cardRadius
            color: "transparent"
            border.width: bar.keyboardHighlight === 1 ? units.dp(2) : 0
            border.color: Style.brand
        }
        Row {
            id: downRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacingXs
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: units.gu(2.5); height: width
                name: "thumb-down"
                color: bar.flagged ? Style.accentRed : Style.textSecondary
            }
        }
    }

    // "Voters" caption used on the post-detail summary bar in place of a redundant comment-count icon already covered above.
    Label {
        visible: bar.showVotersLabel
        Layout.alignment: Qt.AlignVCenter
        text: Lang.tr("Voters")
        font.pixelSize: Style.fontRegular
        color: Style.textPrimary
    }

    AbstractButton {
        visible: bar.showComments
        Layout.preferredHeight: units.gu(3.5)
        Layout.preferredWidth: cmtRow.implicitWidth
        onClicked: bar.commentRequested()
        Row {
            id: cmtRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacingXs
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: units.gu(2.5); height: width
                name: "message"
                color: Style.textPrimary
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: bar.comments
                font.pixelSize: Style.fontRegular
                color: Style.textPrimary
            }
        }
    }

    AbstractButton {
        id: shareBtn
        visible: bar.showShare && bar.shareUrl.length > 0
        Layout.preferredHeight: units.gu(3.5)
        Layout.preferredWidth: units.gu(3)
        onClicked: Share.open(bar.shareUrl, shareBtn)
        Icon {
            anchors.centerIn: parent
            width: units.gu(2.5); height: width
            name: "share"
            color: Style.textPrimary
        }
    }

    // Excluded from the layout (not just shrunk) when compact, so no leftover gap remains
    Item { visible: !bar.compact; Layout.fillWidth: true }

    CoinValue {
        visible: bar.onChain && bar.payout.length > 0 && bar.voteType !== "comment"
        value: bar.payout
    }

    // gap after the pill, non-compact mode
    Item { visible: !bar.compact; width: Style.spacingXs; height: 1 }

    // Compact mode: soak up leftover width instead of letting the pill stretch flush to the edge
    Item { visible: bar.compact; Layout.fillWidth: true }
}
