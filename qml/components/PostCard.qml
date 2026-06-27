import QtQuick 2.7
import QtQuick.Layouts 1.3
import QtGraphicalEffects 1.0
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../services/VoteService.js" as VoteService

/*
 * Feed post card (serey-ubutu FeedCard style): avatar + author + relative time
 * + Follow pill + ••• menu, title, rounded cover image with a red category
 * badge, then a live action row (VoteBar) and a hairline divider. Tapping the
 * title or image opens the detail page; the action row votes/comments inline.
 *
 * Consumes the Mappers.toPost view-model. Emits clicked() to open detail, and
 * re-exposes the VoteBar's requireLogin() so the page can route to login.
 */
Item {
    id: root

    property var post: ({})
    // Guard: the delegate may rebind `post` to undefined while the model is
    // cleared/recycled. `p` is always a safe object to read from.
    readonly property var p: post ? post : ({})

    // Shared, reactive follow state — every button for this author stays in sync.
    readonly property bool isFollowing: FollowStore.isFollowing(p.author)
    property bool showFollow: true

    signal clicked()
    signal requireLogin()
    signal moreClicked()
    signal authorClicked()

    width: parent ? parent.width : units.gu(45)
    implicitHeight: col.height

    // The feed ListModel (dynamicRoles) wraps array fields as nested ListModels,
    // which have `count` but no `indexOf`/`length`. These helpers read either a
    // plain JS array (detail view-models) or a wrapped ListModel safely.
    function _len(v) {
        if (!v) return 0;
        if (typeof v.length === "number") return v.length;
        if (typeof v.count === "number") return v.count;
        return 0;
    }
    function _inList(v, name) {
        if (!v || !name) return false;
        if (typeof v.indexOf === "function") return v.indexOf(name) >= 0;
        // ListModel-wrapped arrays (dynamicRoles) have .count/.get() but no
        // .indexOf(). Each wrapped string element is stored as an object; the
        // actual value lives in .modelData, .value, or the first own property.
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

    // Ensure the shared store knows this author's state (queries once).
    // Also refresh vote state from session cache or model voters.
    onPChanged: {
        if (Session.isLoggedIn && p.author && p.author !== Session.username)
            FollowStore.load(Config.baseUrl, Session.username, p.author);

        // Vote state: check session cache first (survives navigation), then
        // fall back to the model's voters array. Set imperatively (no binding)
        // so VoteBar's own state changes aren't overridden later.
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

    Column {
        id: col
        width: parent.width

        Item { width: 1; height: Style.spacingS }

        // Header: avatar + author/time + Follow + more
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
                Layout.preferredWidth: followLabel.width + units.gu(3)
                Layout.preferredHeight: units.gu(3.75)
                Layout.fillHeight: false
                Layout.alignment: Qt.AlignVCenter
                radius: height / 2
                color: root.isFollowing ? Style.surface : Style.brand
                border.width: root.isFollowing ? units.dp(1.5) : 0
                border.color: Style.brand

                Label {
                    id: followLabel
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

            // More button — owner sees Edit/Delete, others see moderation
            // actions (the sheet branches on ownership).
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

        // Title
        Label {
            visible: (p.title || "") !== ""
            width: parent.width - Style.spacingM * 2
            x: Style.spacingM
            text: p.title || ""
            font.pixelSize: Style.fontMedium
            font.family: Style.fontFamily
            color: Style.textPrimary
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
            MouseArea { anchors.fill: parent; onClicked: root.clicked() }
        }

        Item { width: 1; height: Style.spacingS }

        // Cover image with category badge
        Item {
            id: cover
            visible: (p.thumbnail || "") !== ""
            width: parent.width - Style.spacingM * 2
            x: Style.spacingM
            height: visible ? width * 0.56 : 0

            // Rectangle.clip only clips to the bounding box (not rounded
            // corners), so the Image is masked against a rounded Rectangle
            // instead, for a true rounded crop.
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

            MouseArea { anchors.fill: parent; onClicked: root.clicked() }
        }

        // Excerpt (shown when there is no cover image)
        Label {
            visible: (p.thumbnail || "") === "" && (p.excerpt || "") !== ""
            width: parent.width - Style.spacingM * 2
            x: Style.spacingM
            text: p.excerpt || ""
            font.pixelSize: Style.fontRegular
            font.family: Style.fontFamily
            color: Style.textSecondary
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            MouseArea { anchors.fill: parent; onClicked: root.clicked() }
        }

        Item { width: 1; height: Style.spacingS }

        // Action row (live voting)
        VoteBar {
            id: cardVoteBar
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

        Item { width: 1; height: Style.spacingS }

        Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }
    }
}
