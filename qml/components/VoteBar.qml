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

    // "alice, bob, carol and 4 more" summary for the voters popover. `voters` may be
    // a plain array or a dynamicRoles-wrapped ListModel (.count/.get(i) instead of
    // .length/[i]); handle both shapes.
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
            // Only accept real usernames; a ListModel-wrapped entry is a QML
            // object that would stringify as "@QQmlDM..." garbage.
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
        return !bar.busy;
    }
    // Reconcile server-confirmed fields after an optimistic vote. Count isn't taken
    // from r.voterCount: the async chain broadcast means the immediate response still
    // carries the pre-vote count, so the optimistic +/-1 stands.
    function _apply(r) {
        bar.busy = false;
        bar.flaggers = r.flaggerCount;
        if (r.payout)
            bar.payout = r.payout;
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
    // A 401 is already surfaced (and the session cleared) by Http.js's global
    // unauthorized handler in Main.qml, so re-toasting it here would double up.
    // The server sends one for a rotated posting key, not just an expired token.
    function _isHandledAuthFailure(e) {
        return !!e && e.status === 401;
    }
    // Shared failure handler: undo the optimistic change, then surface the error
    // (unless it's the globally-handled 401).
    function _failReverting(e, snap) {
        bar.busy = false;
        _rollback(snap);
        if (_isHandledAuthFailure(e))
            return;
        Toast.error((e && e.message) ? e.message : Lang.tr("Action failed."));
    }
    // "Already voted" means the server already has our vote, so the optimistic
    // upvote is already correct: keep it, no rollback. Kept separate from
    // flag/removeVote so a failed unvote can't flip the UI to "liked".
    function _failUpvote(e, snap) {
        var msg = (e && e.message) ? e.message.toLowerCase() : "";
        if (!_isHandledAuthFailure(e) && msg.indexOf("already") >= 0) {
            bar.busy = false;
            return;
        }
        bar._failReverting(e, snap);
    }

    function doUpvote() {
        if (!_guard())
            return;
        if (bar.upvoted) {
            bar._sendRemoveVote();
        } else if (bar.voteType === "comment" || !bar.onChain) {
            // Comments and off-chain posts: simple one-tap like, no weight popover
            bar._sendUpvote(100);
        } else {
            PopupUtils.open(voteWeightDialog);
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
        VoteService.removeVote(Config.baseUrl, author, permlink, voteType, Session.token,
            function (r) { _apply(r); bar._cache(); },
            function (e) { bar._failReverting(e, snap); });
    }

    // Optimistic upvote: count it, turn blue, and toast immediately; the chain
    // broadcast runs in the background so the user never waits on confirmation.
    function _sendUpvote(weight) {
        var snap = _snapshot();
        if (!bar.upvoted) bar.votes = bar.votes + 1;
        bar.upvoted = true;
        bar.flagged = false;
        bar._cache();
        Toast.success(bar.voteType === "comment" ? Lang.tr("Liked") : Lang.tr("Thanks for your vote!"));
        bar.busy = true;
        VoteService.upvote(Config.baseUrl, author, permlink, voteType, weight, Session.token,
            function (r) { _apply(r); bar._cache(); },
            function (e) { bar._failUpvote(e, snap); });
    }

    Component {
        id: voteWeightDialog
        Dialog {
            id: dialog
            title: Lang.tr("Vote Weight")

            property int selectedWeight: 100

            Label {
                width: parent.width
                text: dialog.selectedWeight + "%"
                font.pixelSize: Style.fontTitle
                font.weight: Font.Bold
                color: Style.brand
                horizontalAlignment: Text.AlignHCenter
            }

            Slider {
                id: weightSlider
                width: parent.width
                minimumValue: 1
                maximumValue: 100
                value: 100
                live: true
                onValueChanged: dialog.selectedWeight = Math.round(value)

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
                        onClicked: {
                            weightSlider.value = modelData;
                            dialog.selectedWeight = modelData;
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: Style.cardRadius
                            color: dialog.selectedWeight === modelData ? Style.brand : Style.iconBackground
                        }
                        Label {
                            anchors.centerIn: parent
                            text: modelData + "%"
                            font.pixelSize: Style.fontSmall
                            font.weight: Font.DemiBold
                            color: dialog.selectedWeight === modelData ? Style.textOnBrand : Style.textPrimary
                        }
                    }
                }
            }

            Row {
                width: parent.width
                spacing: Style.spacingM

                Button {
                    width: (parent.width - Style.spacingM) / 2
                    text: Lang.tr("Cancel")
                    onClicked: PopupUtils.close(dialog)
                }
                Button {
                    width: (parent.width - Style.spacingM) / 2
                    text: Lang.tr("Vote")
                    color: Style.brand
                    onClicked: {
                        PopupUtils.close(dialog);
                        bar._sendUpvote(dialog.selectedWeight);
                    }
                }
            }
        }
    }
    function doFlag() {
        if (!allowFlag || !_guard())
            return;
        var snap = _snapshot();
        if (bar.flagged) {
            // Optimistic un-flag.
            bar.flagged = false;
            bar._cache();
            Toast.show(Lang.tr("Vote removed"));
            bar.busy = true;
            VoteService.removeVote(Config.baseUrl, author, permlink, voteType, Session.token,
                function (r) { _apply(r); bar._cache(); },
                function (e) { bar._failReverting(e, snap); });
        } else {
            // Optimistic flag; a flag clears any existing upvote.
            if (bar.upvoted) bar.votes = Math.max(0, bar.votes - 1);
            bar.flagged = true;
            bar.upvoted = false;
            bar._cache();
            Toast.show(Lang.tr("Thanks for your feedback!"));
            bar.busy = true;
            VoteService.flag(Config.baseUrl, author, permlink, voteType, Session.token,
                function (r) { _apply(r); bar._cache(); },
                function (e) { bar._failReverting(e, snap); });
        }
    }

    // Upvote / like: hollow outline when not voted, filled blue when voted.
    AbstractButton {
        id: upvoteBtn
        Layout.preferredHeight: units.gu(3.5)
        Layout.preferredWidth: upRow.implicitWidth
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

        // Mouse hover (desktop) or press-and-hold (touch) reveals who upvoted.
        // Topmost MouseArea gets the press first; a short tap is unaccepted so
        // it falls through to upvoteBtn's own click, only the hold is caught here.
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
            // Centered on the button but clamped inside the bar (a centered long list
            // would run off the screen's left edge). x is in upvoteBtn coordinates,
            // hence the -upvoteBtn.x offsets for the bar's own edges.
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
        visible: bar.showShare && bar.shareUrl.length > 0
        Layout.preferredHeight: units.gu(3.5)
        Layout.preferredWidth: units.gu(3)
        onClicked: Share.open(bar.shareUrl)
        Icon {
            anchors.centerIn: parent
            width: units.gu(2.5); height: width
            name: "share"
            color: Style.textPrimary
        }
    }

    // Excluded from the layout (not just shrunk) when compact, so no leftover
    // spacing gap remains around it and the coin pill sits close to the icons.
    Item { visible: !bar.compact; Layout.fillWidth: true }

    CoinValue {
        visible: bar.onChain && bar.payout.length > 0 && bar.voteType !== "comment"
        value: bar.payout
    }

    // Compact mode: soak up any leftover width after the coin pill instead of
    // letting it stretch flush to the bar's edge.
    Item { visible: bar.compact; Layout.fillWidth: true }
}
