import QtQuick 2.7
import QtQuick.Layouts 1.3
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../services/VoteService.js" as VoteService

Item {
    id: root

    property var post: ({})
    readonly property var p: post ? post : ({})
    // computed once per bind, not re-run inside every binding
    readonly property var imgs: _images()
    // shared reactive follow state
    readonly property bool isFollowing: FollowStore.isFollowing(p.author)

    signal clicked()
    signal requireLogin()
    signal moreClicked()
    signal authorClicked()

    property bool showFollow: true

    onPChanged: {
        if (Session.isLoggedIn && p.author && p.author !== Session.username)
            FollowStore.load(Config.baseUrl, Session.username, p.author);
        _syncVoteBar();
    }

    // onPChanged doesn't fire on in-place ListModel.set() row swaps
    readonly property int _pVotes: p.votes || 0
    readonly property string _pPayout: p.payout || ""
    readonly property string _pPermlink: p.permlink || ""
    on_PVotesChanged: _syncVoteBar()
    on_PPayoutChanged: _syncVoteBar()
    on_PPermlinkChanged: _syncVoteBar()

    Component.onCompleted: _syncVoteBar()

    function _syncVoteBar() {
        if (!galVoteBar) return;
        var cached = VoteService.getCached(p.author || "", p.permlink || "");
        if (cached) {
            galVoteBar.upvoted = cached.upvoted;
            galVoteBar.flagged = cached.flagged;
            galVoteBar.votes = cached.votes;
            if (cached.payout) galVoteBar.payout = cached.payout;
        } else {
            var me = Session.username || "";
            galVoteBar.upvoted = me.length > 0 && (p.voterStr || "").indexOf("," + me + ",") >= 0;
            galVoteBar.flagged = me.length > 0 && (p.flaggerStr || "").indexOf("," + me + ",") >= 0;
            // re-assert imperatively; recycled delegate breaks the binding
            galVoteBar.votes = p.votes || 0;
            galVoteBar.payout = p.payout || "";
        }
    }

    function toggleFollow() {
        if (!Session.isLoggedIn) {
            Toast.error(Lang.tr("Please log in first."));
            root.requireLogin();
            return;
        }
        var now = FollowStore.toggle(Config.baseUrl, p.author, Session.token);
        Toast.show(now ? Lang.tr("Following") : Lang.tr("Unfollowed"));
    }

    function _len(v) {
        if (!v) return 0;
        if (typeof v.length === "number") return v.length;
        if (typeof v.count === "number") return v.count;
        return 0;
    }
    // normalise images to a plain array (may arrive as ListModel)
    function _images() {
        // prefer imagesStr; dynamicRoles ListModel destroys the images array
        if (typeof p.imagesStr === "string" && p.imagesStr.length > 0)
            return p.imagesStr.split("\n");
        var v = p.images;
        if (!v) return [];
        if (typeof v.length === "number") return v;
        return [];
    }

    width: parent ? parent.width : units.gu(45)
    implicitHeight: col.height

    Column {
        id: col
        width: parent.width

        Item { width: 1; height: Style.spacingS }

        // Header: avatar + author + time
        Item {
            width: parent.width
            height: units.gu(6)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.spacingM
                anchors.rightMargin: Style.spacingM
                spacing: Style.spacingS

                Item {
                    id: galAvatar
                    Layout.preferredWidth: units.gu(4.25)
                    Layout.preferredHeight: units.gu(4.25)
                    Layout.fillHeight: false
                    Layout.alignment: Qt.AlignVCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Style.avatarTint(p.author || "")
                        visible: (p.authorImage || "") === ""

                        Label {
                            anchors.centerIn: parent
                            text: (p.author || "?").charAt(0).toUpperCase()
                            font.pixelSize: Style.fontMedium
                            font.bold: true
                            color: Style.brand
                        }
                    }

                    CircleImage {
                        anchors.fill: parent
                        source: p.authorImage || ""
                        decode: units.gu(9)
                        visible: (p.authorImage || "") !== ""
                    }

                    MouseArea { anchors.fill: parent; onClicked: root.authorClicked(); onPressAndHold: root.moreClicked() }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0
                    Label {
                        Layout.fillWidth: true
                        text: p.author || ""
                        font.pixelSize: Style.fontSmall
                        font.weight: Font.DemiBold
                        color: Style.textPrimary
                        elide: Text.ElideRight
                        MouseArea { anchors.fill: parent; onClicked: root.authorClicked(); onPressAndHold: root.moreClicked() }
                    }
                    Label {
                        text: Style.formatTimeAgo(p.date || "")
                        font.pixelSize: Style.fontXSmall
                        color: Style.textSecondary
                    }
                }

                // Follow pill
                Rectangle {
                    visible: root.showFollow && (p.author || "") !== "" && p.author !== Session.username
                    Layout.preferredWidth: galFollowLabel.width + units.gu(3)
                    Layout.preferredHeight: units.gu(3.75)
                    Layout.fillHeight: false
                    Layout.alignment: Qt.AlignVCenter
                    radius: Style.pillRadius
                    color: root.isFollowing ? Style.surface : Style.brand
                    border.width: root.isFollowing ? units.dp(1.5) : 0
                    border.color: Style.brand

                    Label {
                        id: galFollowLabel
                        anchors.centerIn: parent
                        text: root.isFollowing ? Lang.tr("Following") : Lang.tr("Follow")
                        font.pixelSize: Style.fontXSmall
                        font.weight: Font.DemiBold
                        color: root.isFollowing ? Style.brand : Style.textOnBrand
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.toggleFollow()
                    }
                }

                // Downloaded-for-offline indicator.
                Rectangle {
                    Layout.preferredWidth: dlLabel.width + Style.spacingM
                    Layout.preferredHeight: units.gu(2.6)
                    Layout.alignment: Qt.AlignVCenter
                    visible: (SavedPosts.rev, Downloads.rev, SavedPosts.isSaved(p.permlink) || Downloads.isSaved(p.permlink))
                    radius: Style.pillRadius
                    color: Style.iconBackground
                    border.width: units.dp(1)
                    border.color: Style.textSecondary

                    Label {
                        id: dlLabel
                        anchors.centerIn: parent
                        text: Lang.tr("Downloaded")
                        font.pixelSize: Style.fontXSmall
                        font.weight: Font.DemiBold
                        color: Style.textSecondary
                    }
                }

                // More button — owner sees Edit/Delete, others moderation.
                AbstractButton {
                    Layout.preferredWidth: units.gu(3.5)
                    Layout.preferredHeight: units.gu(3.5)
                    Layout.fillHeight: false
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: root.moreClicked()

                    Label {
                        anchors.centerIn: parent
                        text: "•••"
                        font.pixelSize: Style.fontLarge
                        font.weight: Font.Bold
                        color: Style.textSecondary
                    }
                }
            }
        }

        // shows first image only; carousel lives on detail page
        Item {
            id: cover
            width: parent.width
            height: width

            Rectangle { anchors.fill: parent; color: Style.iconBackground }

            Image {
                id: coverImg
                anchors.fill: parent
                source: root.imgs.length > 0 ? root.imgs[0] : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                autoTransform: true     // honour EXIF orientation (camera photos)
                // Showcase photo decodes at 2x display width so PreserveAspectCrop downsamples (sharp) instead of upscaling (blur).
                sourceSize.width: cover.width * 2
                Behavior on opacity { NumberAnimation { duration: 200 } }
                opacity: status === Image.Ready ? 1.0 : 0.0
            }

            MouseArea { anchors.fill: parent; onClicked: root.clicked(); onPressAndHold: root.moreClicked() }

            // category tag — top-left ("+N" badge is top-right)
            Rectangle {
                visible: (p.primaryCategory || "") !== ""
                anchors { top: parent.top; left: parent.left; topMargin: Style.spacingS; leftMargin: Style.spacingS }
                width: galCatLabel.width + Style.spacingM
                height: units.gu(3)
                radius: Style.pillRadius
                color: Style.accentRed
                Label {
                    id: galCatLabel
                    anchors.centerIn: parent
                    text: p.primaryCategory || ""
                    font.pixelSize: Style.fontSmall
                    font.weight: Font.DemiBold
                    color: Style.textOnBrand
                }
            }

            // "+N" badge when the post has multiple photos.
            Rectangle {
                visible: root.imgs.length > 1
                anchors { top: parent.top; right: parent.right; topMargin: Style.spacingS; rightMargin: Style.spacingS }
                width: moreLabel.width + Style.spacingS
                height: units.gu(2.5)
                radius: units.dp(4)
                color: Qt.rgba(0, 0, 0, 0.6)
                Label {
                    id: moreLabel
                    anchors.centerIn: parent
                    text: "+" + (root.imgs.length - 1)
                    font.pixelSize: Style.fontXSmall
                    font.weight: Font.DemiBold
                    color: Style.textOnBrand
                }
            }
        }

        Item { width: 1; height: Style.spacingS }

        // Action row (live voting)
        VoteBar {
            id: galVoteBar
            width: parent.width - Style.spacingM * 2
            x: Style.spacingM
            author: p.author || ""
            permlink: p.permlink || ""
            voteType: "post"
            onChain: p.postToBlockchain !== false
            votes: p.votes || 0
            // voterStr scalar; ListModel mangles string arrays
            voters: (p.voterStr || "").split(",").filter(function (n) { return n.length > 0; })
            flaggers: root._len(p.flaggers)
            comments: p.comments || 0
            payout: p.payout || ""
            onRequireLogin: root.requireLogin()
            onCommentRequested: root.clicked()
        }

        // spacer Items for caption; Label has no top/bottomPadding
        Item { width: 1; height: Style.spacingXs; visible: (p.caption || "") !== "" }

        Label {
            visible: (p.caption || "") !== ""
            width: parent.width - Style.spacingM * 2
            x: Style.spacingM
            text: p.caption || ""
            font.pixelSize: Style.fontRegular
            font.family: Style.fontFor(text)
            color: Style.textPrimary
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
        Item { width: 1; height: Style.spacingS; visible: (p.caption || "") !== "" }

        Item { width: 1; height: Style.spacingS }

        Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }
    }

    // right-click/MENU opens ••• menu; Enter opens post
    ContextActionArea {
        onTriggered: root.moreClicked()
        onActivated: root.clicked()
    }
}
