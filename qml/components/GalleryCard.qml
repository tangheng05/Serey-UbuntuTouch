import QtQuick 2.7
import QtQuick.Layouts 1.3
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../services/VoteService.js" as VoteService

/*
 * Gallery feed card (serey-ubutu GalleryCard style): avatar + author + time,
 * a swipeable image carousel (with page dots) cropped to a rounded square-ish
 * frame, a live action row (VoteBar) and a caption. Tapping the image opens
 * the post detail; the action row votes/comments inline.
 */
Item {
    id: root

    property var post: ({})
    readonly property var p: post ? post : ({})
    // Computed once per bind — _images() splits a string / walks the model and
    // was previously re-run 3–4× per card inside bindings.
    readonly property var imgs: _images()
    // Shared, reactive follow state (see Theme/FollowStore.qml).
    readonly property bool isFollowing: FollowStore.isFollowing(p.author)

    signal clicked()
    signal requireLogin()
    signal moreClicked()
    signal authorClicked()

    property bool showFollow: true

    onPChanged: {
        if (Session.isLoggedIn && p.author && p.author !== Session.username)
            FollowStore.load(Config.baseUrl, Session.username, p.author);

        if (galVoteBar) {
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
            }
        }
    }

    function toggleFollow() {
        if (!Session.isLoggedIn) {
            Toast.error(i18n.tr("Please log in first."));
            root.requireLogin();
            return;
        }
        var now = FollowStore.toggle(Config.baseUrl, p.author, Session.token);
        Toast.show(now ? i18n.tr("Following") : i18n.tr("Unfollowed"));
    }

    function _len(v) {
        if (!v) return 0;
        if (typeof v.length === "number") return v.length;
        if (typeof v.count === "number") return v.count;
        return 0;
    }
    function _inList(v, name) {
        if (!v || !name) return false;
        if (typeof v.indexOf === "function") return v.indexOf(name) >= 0;
        if (typeof v.count === "number") {
            for (var i = 0; i < v.count; i++) {
                var item = v.get(i);
                if (!item) continue;
                if (item === name) return true;
                if (item.modelData === name) return true;
                if (item.value === name) return true;
                var keys = Object.keys(item);
                for (var k = 0; k < keys.length; k++) {
                    if (item[keys[k]] === name) return true;
                }
            }
        }
        return false;
    }
    // images may arrive as a plain JS array (fresh map) or a wrapped
    // ListModel (dynamicRoles re-binding); normalise to a plain array.
    function _images() {
        // Prefer the scalar `imagesStr` — a dynamicRoles ListModel destroys the
        // wrapped `images` array (its .get(i) returns empty objects, not URLs),
        // whereas the joined string survives intact.
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

                    MouseArea { anchors.fill: parent; onClicked: root.authorClicked() }
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
                        MouseArea { anchors.fill: parent; onClicked: root.authorClicked() }
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
                    radius: height / 2
                    color: root.isFollowing ? Style.surface : Style.brand
                    border.width: root.isFollowing ? units.dp(1.5) : 0
                    border.color: Style.brand

                    Label {
                        id: galFollowLabel
                        anchors.centerIn: parent
                        text: root.isFollowing ? i18n.tr("Following") : i18n.tr("Follow")
                        font.pixelSize: Style.fontXSmall
                        font.weight: Font.DemiBold
                        color: root.isFollowing ? Style.brand : Style.textOnBrand
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.toggleFollow()
                    }
                }

                // More button
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

        // Cover: feed cards show only the first image (a SwipeView per recycled
        // delegate is expensive); the swipeable carousel lives on the detail page.
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
                // Showcase photo in a square crop — decode at 2× display width so
                // PreserveAspectCrop downsamples (sharp) instead of upscaling (blur).
                sourceSize.width: cover.width * 2
                Behavior on opacity { NumberAnimation { duration: 200 } }
                opacity: status === Image.Ready ? 1.0 : 0.0
            }

            MouseArea { anchors.fill: parent; onClicked: root.clicked() }

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
            votes: p.votes || 0
            flaggers: root._len(p.flaggers)
            comments: p.comments || 0
            payout: p.payout || ""
            onRequireLogin: root.requireLogin()
            onCommentRequested: root.clicked()
        }

        // Caption (Lomiri Label has no top/bottomPadding in Components 1.3,
        // so spacing is provided by visible-gated spacer Items — the Column
        // positioner skips invisible children.)
        Item { width: 1; height: Style.spacingXs; visible: (p.caption || "") !== "" }

        Label {
            visible: (p.caption || "") !== ""
            width: parent.width - Style.spacingM * 2
            x: Style.spacingM
            text: p.caption || ""
            font.pixelSize: Style.fontRegular
            font.family: Style.fontFamily
            color: Style.textPrimary
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
        Item { width: 1; height: Style.spacingS; visible: (p.caption || "") !== "" }

        Item { width: 1; height: Style.spacingS }

        Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }
    }
}
