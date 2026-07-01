import QtQuick 2.7
import QtQuick.Layouts 1.3
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../Theme"
import "../Session"
import "../services/VoteService.js" as VoteService

/*
 * Upvote / downvote / comment / share action row for a post, video or comment.
 * Self-contained: gates on login, posts to VoteService, updates its own counts
 * optimistically and reports outcome via Toast. `voteType` is "post" (default)
 * or "comment" (a like-toggle; flagging is disabled by the backend).
 *
 * Emits requireLogin() when an action needs auth, and commentRequested() when
 * the comment affordance is tapped. Styling follows the serey-ubutu action bar:
 * Suru icons + counts, right-aligned SEREY coin pill.
 */
RowLayout {
    id: bar

    property string author: ""
    property string permlink: ""
    property string voteType: "post"

    property int votes: 0
    property int flaggers: 0
    property int comments: 0
    property string payout: ""

    property bool upvoted: false
    property bool flagged: false
    property bool busy: false
    property bool showComments: true
    property bool showShare: true
    property bool showVotersLabel: false

    readonly property bool allowFlag: true
    readonly property string shareUrl: (author.length > 0 && permlink.length > 0)
        ? ("https://serey.io/authors/@" + author + "/" + permlink) : ""

    signal requireLogin()
    signal commentRequested()

    spacing: Style.spacingM

    function _guard() {
        if (!Session.isLoggedIn) {
            Toast.error(i18n.tr("Please log in first."));
            bar.requireLogin();
            return false;
        }
        return !bar.busy;
    }
    // NOTE: the vote count is updated OPTIMISTICALLY by each action below, not
    // from r.voterCount. Serey signs/broadcasts the vote to the chain async, so
    // the immediate response still carries the pre-vote count — trusting it left
    // the icon blue while the number never moved. The authoritative count comes
    // back on the next feed/detail reload.
    function _apply(r) {
        bar.busy = false;
        bar.flaggers = r.flaggerCount;
        if (r.payout)
            bar.payout = r.payout;
    }
    function _cache() {
        VoteService._updateCache(bar.author, bar.permlink, bar.upvoted, bar.flagged, bar.votes, bar.payout);
    }
    function _fail(e) {
        bar.busy = false;
        var msg = (e && e.message) ? e.message.toLowerCase() : "";
        if (msg.indexOf("already") >= 0) {
            // UI was out of sync — silently correct it
            if (!bar.upvoted) { bar.votes = bar.votes + 1; bar.upvoted = true; bar._cache(); }
            return;
        }
        Toast.error((e && e.message) ? e.message : i18n.tr("Action failed."));
    }

    function doUpvote() {
        if (!_guard())
            return;
        if (bar.upvoted) {
            bar.busy = true;
            VoteService.removeVote(Config.baseUrl, author, permlink, voteType, Session.token,
                function (r) { bar.upvoted = false; bar.votes = Math.max(0, bar.votes - 1); _apply(r); bar._cache(); Toast.show(i18n.tr("Vote removed")); }, _fail);
        } else if (bar.voteType === "comment") {
            bar._sendUpvote(100);
        } else {
            PopupUtils.open(voteWeightDialog);
        }
    }

    function _sendUpvote(weight) {
        bar.busy = true;
        VoteService.upvote(Config.baseUrl, author, permlink, voteType, weight, Session.token,
            function (r) { if (!bar.upvoted) bar.votes = bar.votes + 1;   // count this vote now
                           bar.upvoted = true; bar.flagged = false; _apply(r); bar._cache();
                           Toast.success(bar.voteType === "comment" ? i18n.tr("Liked") : i18n.tr("Upvoted %1%").arg(weight)); }, _fail);
    }

    Component {
        id: voteWeightDialog
        Dialog {
            id: dialog
            title: i18n.tr("Vote Weight")

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
                    text: i18n.tr("Cancel")
                    onClicked: PopupUtils.close(dialog)
                }
                Button {
                    width: (parent.width - Style.spacingM) / 2
                    text: i18n.tr("Vote")
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
        bar.busy = true;
        if (bar.flagged) {
            VoteService.removeVote(Config.baseUrl, author, permlink, voteType, Session.token,
                function (r) { bar.flagged = false; _apply(r); bar._cache(); Toast.show(i18n.tr("Vote removed")); }, _fail);
        } else {
            VoteService.flag(Config.baseUrl, author, permlink, voteType, Session.token,
                function (r) { if (bar.upvoted) bar.votes = Math.max(0, bar.votes - 1);   // flag clears the upvote
                               bar.flagged = true; bar.upvoted = false; _apply(r); bar._cache(); Toast.show(i18n.tr("Flagged")); }, _fail);
        }
    }

    // Upvote / like — hollow outline heart when not voted, filled blue when voted.
    AbstractButton {
        Layout.preferredHeight: units.gu(3.5)
        Layout.preferredWidth: upRow.implicitWidth
        enabled: !bar.busy
        onClicked: bar.doUpvote()
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
    }

    AbstractButton {
        Layout.preferredHeight: units.gu(3.5)
        Layout.preferredWidth: downRow.implicitWidth
        enabled: !bar.busy
        onClicked: bar.doFlag()
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

    // "Voters" caption (used on the post-detail summary bar, in place of a
    // redundant comment-count icon that's already covered by the Comments
    // section above it)
    Label {
        visible: bar.showVotersLabel
        Layout.alignment: Qt.AlignVCenter
        text: i18n.tr("Voters")
        font.pixelSize: Style.fontRegular
        color: Style.textPrimary
    }

    // Comments
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

    // Share
    AbstractButton {
        visible: bar.showShare && bar.shareUrl.length > 0
        Layout.preferredHeight: units.gu(3.5)
        Layout.preferredWidth: units.gu(3)
        onClicked: Qt.openUrlExternally(bar.shareUrl)
        Icon {
            anchors.centerIn: parent
            width: units.gu(2.5); height: width
            name: "share"
            color: Style.textPrimary
        }
    }

    Item { Layout.fillWidth: true }

    // Busy indicator / payout pill
    ActivityIndicator {
        running: bar.busy
        visible: bar.busy
        Layout.preferredHeight: units.gu(2.5)
        Layout.preferredWidth: units.gu(2.5)
    }
    CoinValue {
        visible: !bar.busy && bar.payout.length > 0 && bar.voteType !== "comment"
        value: bar.payout
    }
}
