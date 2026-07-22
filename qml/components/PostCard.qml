import QtQuick 2.7
import QtQuick.Layouts 1.3
import QtGraphicalEffects 1.0
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../services/VoteService.js" as VoteService

Item {
    id: root

    property var post: ({})
    // safe fallback when post is undefined
    readonly property var p: post ? post : ({})

    signal clicked()
    signal requireLogin()
    signal moreClicked()
    signal authorClicked()

    width: parent ? parent.width : units.gu(45)
    implicitHeight: col.height

    // reads length from array or ListModel
    function _len(v) {
        if (!v) return 0;
        if (typeof v.length === "number") return v.length;
        if (typeof v.count === "number") return v.count;
        return 0;
    }

    // refresh follow state and vote bar
    onPChanged: {
        if (Session.isLoggedIn && p.author && p.author !== Session.username)
            FollowStore.load(Config.baseUrl, Session.username, p.author);
        _syncVoteBar();
    }

    // watch values since ListModel.set() mutates p in place
    readonly property int _pVotes: p.votes || 0
    readonly property string _pPayout: p.payout || ""
    readonly property string _pPermlink: p.permlink || ""
    on_PVotesChanged: _syncVoteBar()
    on_PPayoutChanged: _syncVoteBar()
    on_PPermlinkChanged: _syncVoteBar()

    // sync vote state: session cache, else model voters
    Component.onCompleted: _syncVoteBar()

    function _syncVoteBar() {
        if (!cardVoteBar) return;
        var cached = VoteService.getCached(p.author || "", p.permlink || "");
        if (cached) {
            cardVoteBar.upvoted = cached.upvoted;
            cardVoteBar.flagged = cached.flagged;
            cardVoteBar.votes = cached.votes;
            if (cached.payout) cardVoteBar.payout = cached.payout;
        } else {
            var me = Session.username || "";
            cardVoteBar.upvoted = me.length > 0 && (p.voterStr || "").indexOf("," + me + ",") >= 0;
            cardVoteBar.flagged = me.length > 0 && (p.flaggerStr || "").indexOf("," + me + ",") >= 0;
            // re-assert count/payout on recycled delegate
            cardVoteBar.votes = p.votes || 0;
            cardVoteBar.payout = p.payout || "";
        }
    }

    Column {
        id: col
        width: parent.width

        Item { width: 1; height: Style.spacingS }

        // Header: avatar + author/time + more
        RowLayout {
            height: units.gu(6)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.spacingM
            anchors.rightMargin: Style.spacingM
            spacing: Style.spacingS

            Item {
                id: avatar
                Layout.preferredWidth: units.gu(4.25)
                Layout.preferredHeight: units.gu(4.25)
                Layout.fillHeight: false
                Layout.alignment: Qt.AlignVCenter

                // Letter fallback (shown whenever there's no author image)
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

                // Photo, masked to a true circle (Rectangle.clip ignores radius).
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
                Row {
                    spacing: Style.spacingS
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Style.formatTimeAgo(p.date || "")
                        font.pixelSize: Style.fontXSmall
                        color: Style.textSecondary
                    }
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

            AbstractButton {
                id: moreBtn
                Layout.preferredWidth: units.gu(3.5)
                Layout.preferredHeight: units.gu(3.5)
                Layout.alignment: Qt.AlignVCenter
                onClicked: root.moreClicked()

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

        // Title uses Text.Wrap, not WordWrap, since Khmer has no spaces between words and WordWrap can't find a break point.
        Label {
            visible: (p.title || "") !== ""
            width: parent.width - Style.spacingM * 2
            x: Style.spacingM
            text: p.title || ""
            font.pixelSize: Style.fontMedium
            font.family: Style.fontFor(text)
            color: Style.textPrimary
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            MouseArea { anchors.fill: parent; onClicked: root.clicked(); onPressAndHold: root.moreClicked() }
        }

        Item { width: 1; height: Style.spacingS }

        // Cover image with category badge
        Item {
            id: cover
            visible: (p.thumbnail || "") !== ""
            width: parent.width - Style.spacingM * 2
            x: Style.spacingM
            height: visible ? width * 0.56 : 0

            // masked for true rounded crop
            Rectangle {
                anchors.fill: parent
                radius: Style.thumbRadius
                color: Style.iconBackground
            }
            // double-buffered cover to avoid black flash on swap
            Image {
                id: coverLoader
                anchors.fill: parent
                source: p.thumbnail || ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                autoTransform: true     // honour EXIF orientation
                // snap decode size to a breakpoint
                sourceSize.width: root.width > units.gu(70) ? units.gu(90) : units.gu(45)
                visible: false
                onStatusChanged: {
                    if (status === Image.Ready) {
                        coverImg.source = source;
                    } else if (status === Image.Error || String(source).length === 0) {
                        // clear stale cover
                        coverImg.source = "";
                    }
                }
            }
            Image {
                id: coverImg
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                autoTransform: true
                sourceSize.width: coverLoader.sourceSize.width
                visible: false
                // fade out fully during transition, not dim
                readonly property bool transitioning:
                    coverLoader.status === Image.Loading && status === Image.Ready
                Behavior on opacity { NumberAnimation { duration: 200 } }
                opacity: status === Image.Ready ? (transitioning ? 0.0 : 1.0) : 0.0
            }
            Rectangle {
                id: coverMask
                anchors.fill: parent
                radius: Style.thumbRadius
                visible: false
            }
            OpacityMask {
                anchors.fill: parent
                source: coverImg
                maskSource: coverMask
                opacity: coverImg.opacity
            }

            Rectangle {
                // use scalar copy, not ListModel
                visible: (p.primaryCategory || "") !== ""
                anchors { top: parent.top; right: parent.right; topMargin: Style.spacingS; rightMargin: Style.spacingS }
                width: catLabel.width + Style.spacingM
                height: units.gu(3)
                radius: Style.pillRadius
                color: Style.accentRed
                Label {
                    id: catLabel
                    anchors.centerIn: parent
                    text: p.primaryCategory || ""
                    font.pixelSize: Style.fontSmall
                    font.weight: Font.DemiBold
                    color: Style.textOnBrand
                }
            }

            MouseArea { anchors.fill: parent; onClicked: root.clicked(); onPressAndHold: root.moreClicked() }
        }

        // Excerpt (shown when there is no cover image)
        Label {
            visible: (p.thumbnail || "") === "" && (p.excerpt || "") !== ""
            width: parent.width - Style.spacingM * 2
            x: Style.spacingM
            text: p.excerpt || ""
            font.pixelSize: Style.fontRegular
            font.family: Style.fontFor(text)
            color: Style.textSecondary
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            MouseArea { anchors.fill: parent; onClicked: root.clicked(); onPressAndHold: root.moreClicked() }
        }

        // Bottom margin below the thumbnail (always visible, unlike the vote row)
        Item { width: 1; height: Style.spacingS }

        // narrow mode only; wide mode uses detail column
        VoteBar {
            id: cardVoteBar
            visible: !Config.wideMode
            width: parent.width - Style.spacingM * 2
            x: Style.spacingM
            author: p.author || ""
            permlink: p.permlink || ""
            voteType: "post"
            onChain: p.postToBlockchain !== false
            votes: p.votes || 0
            // rebuilt from voterStr scalar
            voters: (p.voterStr || "").split(",").filter(function (n) { return n.length > 0; })
            flaggers: root._len(p.flaggers)
            comments: p.comments || 0
            payout: p.payout || ""
            onRequireLogin: root.requireLogin()
            onCommentRequested: root.clicked()
        }

        Item { width: 1; height: Style.spacingS; visible: !Config.wideMode }

        Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }
    }

    // right-click/MENU opens ••• menu, Enter opens post
    ContextActionArea {
        onTriggered: root.moreClicked()
        onActivated: root.clicked()
    }
}
