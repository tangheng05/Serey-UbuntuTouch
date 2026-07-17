import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../services/PostService.js" as PostService
import "../services/BlockedUsers.js" as BlockedUsers

// My Feed's empty state. A new account follows nobody, so the feed is empty by
// definition — this offers the one action that fills it.
//
// It suggests PEOPLE, not communities: /serey-web/list-by-feed-following keys
// strictly on the `follows` table and explicitly excludes community-subscription
// posts, so subscribing to a community would leave the feed just as empty.
// There's no "who to follow" endpoint, so active authors are derived from
// trending posts.
Item {
    id: root

    // Emitted after a follow, so the feed can refetch.
    signal followed()
    signal writePostRequested()

    property var suggested: []      // [{ author, authorImage }]
    property bool loading: true
    readonly property int maxSuggestions: 5

    Component.onCompleted: _load()

    function _load() {
        var p = { limit: 40, offset: 0 };
        if (Config.communityId > 0) p.community_id = Config.communityId;
        PostService.listTrending(Config.baseUrl, p, Session.token,
            function (posts) { root._pickAuthors(posts); },
            function () { root.loading = false; });
    }

    // Distinct authors from the trending set, minus yourself and anyone blocked.
    function _pickAuthors(posts) {
        var blocked = BlockedUsers.loadAll();
        var seen = {};
        var out = [];
        for (var i = 0; i < posts.length && out.length < root.maxSuggestions; i++) {
            var a = posts[i].author || "";
            if (!a || seen[a] || blocked[a] || a === Session.username) continue;
            seen[a] = true;
            out.push({ author: a, authorImage: posts[i].authorImage || "" });
            // Seed each button's state from the server (FollowStore is the
            // app-wide source of truth, so these stay in sync with feed cards).
            FollowStore.load(Config.baseUrl, Session.username, a);
        }
        root.suggested = out;
        root.loading = false;
    }

    function _toggleFollow(author) {
        if (!Session.isLoggedIn) return;
        var nowFollowing = FollowStore.toggle(Config.baseUrl, author, Session.token);
        if (nowFollowing) root.followed();
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.height + Style.spacingL * 2
        clip: true

        Column {
            id: col
            width: Math.min(parent.width - Style.spacingL * 2, units.gu(50))
            anchors.horizontalCenter: parent.horizontalCenter
            y: Style.spacingL
            spacing: Style.spacingL

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width * 0.6, units.gu(20))
                height: width * (434 / 398)
                source: Qt.resolvedUrl("../../assets/onboarding.svg")
                sourceSize.width: width
                sourceSize.height: height
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }

            Column {
                width: parent.width
                spacing: Style.spacingXs
                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Lang.tr("Your feed is empty")
                    font.pixelSize: Style.fontLarge
                    font.weight: Font.DemiBold
                    font.family: Style.fontFor(text)
                    color: Style.textTitle
                    wrapMode: Text.WordWrap
                }
                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Lang.tr("Follow someone to see their posts here.")
                    font.pixelSize: Style.fontRegular
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                    wrapMode: Text.WordWrap
                }
            }

            ActivityIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: root.loading
                visible: running
            }

            // --- Suggested people --------------------------------------------
            Column {
                width: parent.width
                spacing: 0
                visible: root.suggested.length > 0

                Label {
                    width: parent.width
                    text: Lang.tr("Active on Serey right now")
                    font.pixelSize: Style.fontSmall
                    font.weight: Font.DemiBold
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                }
                Item { width: 1; height: Style.spacingS }

                Repeater {
                    model: root.suggested

                    delegate: Column {
                        width: col.width

                        Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

                        Item {
                            id: row
                            width: parent.width
                            height: units.gu(7)

                            property string author: modelData.author
                            property bool following: FollowStore.isFollowing(row.author)

                            Row {
                                anchors.fill: parent
                                spacing: Style.spacingM

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(4.5); height: width; radius: width / 2
                                    color: Style.avatarTint(row.author)

                                    Label {
                                        anchors.centerIn: parent
                                        visible: (modelData.authorImage || "") === ""
                                        text: (row.author || "?").charAt(0).toUpperCase()
                                        font.pixelSize: Style.fontMedium
                                        font.bold: true
                                        color: Style.brand
                                    }
                                    CircleImage {
                                        anchors.fill: parent
                                        source: modelData.authorImage || ""
                                        decode: units.gu(5)
                                    }
                                }

                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - units.gu(4.5) - followBtn.width - Style.spacingM * 2
                                    text: row.author
                                    font.pixelSize: Style.fontRegular
                                    font.weight: Font.DemiBold
                                    font.family: Style.fontFor(text)
                                    color: Style.textPrimary
                                    elide: Text.ElideRight
                                }

                                AbstractButton {
                                    id: followBtn
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(11); height: units.gu(4)
                                    onClicked: root._toggleFollow(row.author)

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Style.pillRadius
                                        color: row.following ? "transparent"
                                             : followBtn.pressed ? Style.brandDark : Style.brand
                                        border.width: row.following ? units.dp(1.5) : 0
                                        border.color: Style.divider
                                        Behavior on color { ColorAnimation { duration: 120 } }

                                        Label {
                                            anchors.centerIn: parent
                                            text: row.following ? Lang.tr("Following") : Lang.tr("Follow")
                                            font.pixelSize: Style.fontSmall
                                            font.weight: Font.DemiBold
                                            font.family: Style.fontFor(text)
                                            color: row.following ? Style.textSecondary : Style.textOnBrand
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }
            }

            SecondaryButton {
                width: parent.width
                text: Lang.tr("Write your first post")
                onClicked: root.writePostRequested()
            }
        }
    }
}
