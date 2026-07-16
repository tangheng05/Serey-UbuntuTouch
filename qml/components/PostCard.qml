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
    // Guard: the delegate may rebind `post` to undefined while the model is cleared/recycled — `p` is always a safe object to read from.
    readonly property var p: post ? post : ({})

    signal clicked()
    signal requireLogin()
    signal moreClicked()
    signal authorClicked()

    width: parent ? parent.width : units.gu(45)
    implicitHeight: col.height

    // The feed ListModel (dynamicRoles) wraps array fields as nested ListModels with `count` but no indexOf/length; these helpers read either shape safely.
    function _len(v) {
        if (!v) return 0;
        if (typeof v.length === "number") return v.length;
        if (typeof v.count === "number") return v.count;
        return 0;
    }

    // Ensure the shared store knows this author's state, then refresh vote state from session cache or model voters.
    onPChanged: {
        if (Session.isLoggedIn && p.author && p.author !== Session.username)
            FollowStore.load(Config.baseUrl, Session.username, p.author);

        // Vote state checks session cache first (survives navigation), falling back to the model's voters array; set imperatively so VoteBar's own changes aren't overridden.
        if (cardVoteBar) {
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
                // Re-assert count/payout imperatively since a prior cached assignment breaks the QML binding on this pooled delegate when recycled.
                cardVoteBar.votes = p.votes || 0;
                cardVoteBar.payout = p.payout || "";
            }
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

            // Rectangle.clip only clips to the bounding box, so the Image is masked against a rounded Rectangle instead for a true rounded crop.
            Rectangle {
                anchors.fill: parent
                radius: Style.thumbRadius
                color: Style.iconBackground
            }
            Image {
                id: coverImg
                anchors.fill: parent
                source: p.thumbnail || ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                autoTransform: true     // honour EXIF orientation
                sourceSize.width: cover.width
                visible: false
                Behavior on opacity { NumberAnimation { duration: 200 } }
                opacity: status === Image.Ready ? 1.0 : 0.0
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
                visible: !!(p.categories && p.categories.length > 0)
                anchors { top: parent.top; right: parent.right; topMargin: Style.spacingS; rightMargin: Style.spacingS }
                width: catLabel.width + Style.spacingS
                height: units.gu(2.5)
                radius: units.dp(4)
                color: Style.accentRed
                Label {
                    id: catLabel
                    anchors.centerIn: parent
                    text: (p.categories && p.categories.length > 0) ? p.categories[0] : ""
                    font.pixelSize: Style.fontXSmall
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

        // Vote/comment/share row shown narrow mode only — wide mode shows these in the detail column instead.
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
            // Rebuilt from the voterStr scalar: the feed's dynamicRoles ListModel
            // wraps the `voters` string array into a nested model whose entries
            // stringify as QML objects (the popover showed "@QQmlDM..." garbage).
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

    // Pointer/keyboard parity: right-click or MENU opens the ••• context menu;
    // Enter opens the post (same as a tap). See ContextActionArea.
    ContextActionArea {
        onTriggered: root.moreClicked()
        onActivated: root.clicked()
    }
}
