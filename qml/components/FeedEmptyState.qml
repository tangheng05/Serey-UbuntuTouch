import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../services/CommunitySubscriberService.js" as SubscriberService
import "../services/PostService.js" as PostService
import "../services/VideoService.js" as VideoService
import "../services/HiddenPosts.js" as HiddenPosts

// My Feed empty state: offer subscriptions; relies on list-by-feed-mixed including them
Item {
    id: root

    // Emitted after a subscribe, so the feed can refetch.
    signal followed()
    // Carries the button so the community picker can anchor its dropdown to it on desktop.
    signal writePostRequested(var caller)
    // Card tapped outside the Subscribe pill: open that platform.
    signal communityRequested(var community)
    // A suggested article / video was tapped.
    signal postRequested(var post)
    signal videoRequested(var video)
    // A card's vote bar was used while logged out.
    signal loginRequested()

    property var suggested: []      // [{id, title, dns, icon, subscribers}]
    property bool suggestionsLoading: true
    // Three of each: enough to show what Serey is about, few enough that the
    // create-your-own-post action stays in reach on a phone screen.
    readonly property int maxSuggestions: 3
    readonly property int maxPosts: 3
    readonly property int maxVideos: 3

    property var suggestedPosts: []
    property var suggestedVideos: []
    // Blog and video in one list, newest first: the same mix list-by-feed-mixed serves
    // a reader who does have a feed. Videos carry _kind so the delegate can tell them apart.
    readonly property var suggestions: {
        var all = [];
        var i;
        for (i = 0; i < root.suggestedPosts.length; i++) all.push(root.suggestedPosts[i]);
        for (i = 0; i < root.suggestedVideos.length; i++) {
            var v = root.suggestedVideos[i];
            v._kind = "video";
            all.push(v);
        }
        all.sort(function (a, b) {
            return Date.parse(b.date || 0) - Date.parse(a.date || 0);
        });
        return all;
    }

    property var subscribedMap: ({})
    property int subscribedRev: 0

    // Suggestion rows may omit meta_description; the startup community tree has it.
    function descriptionFor(item) {
        if (!item) return "";
        if (item.description) return item.description;
        var c = Config.communityById[String(item.id)];
        return (c && c.description) || "";
    }

    // Most platforms have no blurb; reserve the two lines only if some do.
    readonly property bool anyDescription: {
        for (var i = 0; i < suggested.length; i++)
            if (root.descriptionFor(suggested[i])) return true;
        return false;
    }

    // > 0 = intro in a leading column of that width, cards in the pane beside it.
    property real leadingWidth: 0
    readonly property bool split: leadingWidth > 0

    // First Tab stop on this surface, claimed by the first Subscribe pill (or the
    // create-post button when there are no suggestions yet).
    property Item firstFocusItem: null

    // Called by FeedPage when keyboard nav lands on My Feed while this state is up:
    // focusing the hidden, empty feed list would look like the keyboard was dead.
    function focusFirst() {
        var it = root.firstFocusItem;
        if (!it || !it.visible) return false;
        // Drop focus first: Qt skips focusInEvent (and the key-nav reason) if already focused.
        it.focus = false;
        it.forceActiveFocus(Qt.TabFocusReason);
        return true;
    }

    // Readers with a feed never see this state, so nothing is fetched until it shows:
    // three requests on every My Feed open would only slow the feed down.
    property bool _loaded: false

    onVisibleChanged: if (visible && !root._loaded) root._load()

    function _load() {
        root._loaded = true;
        SubscriberService.suggestedCommunities(Config.baseUrl, root.maxSuggestions,
            function (list) { root.suggested = list; root.suggestionsLoading = false; },
            function () { root.suggestionsLoading = false; });
        if (Session.isLoggedIn)
            SubscriberService.fetchSubscribed(Config.baseUrl, Session.token,
                function (map) { root.subscribedMap = map; root.subscribedRev++ },
                function () { /* rows just start unsubscribed */ });

        // Scoped to the community in the header, which launch already set from the
        // reader's country (Global when their country isn't on Serey). community_id
        // filters recursively, so a country also covers the platforms under it.
        // All three run in parallel; each section paints as its own answer lands.
        PostService.listTrending(Config.baseUrl, root._scopeParams(root.maxPosts), Session.token,
            function (posts) { root.suggestedPosts = posts.slice(0, root.maxPosts); },
            function () { /* the section just stays hidden */ });

        VideoService.listVideos(Config.baseUrl, root._scopeParams(root.maxVideos), Session.token,
            function (videos) { root.suggestedVideos = videos.slice(0, root.maxVideos); },
            function () { /* the section just stays hidden */ });
    }

    function _hideSuggestion(entry) {
        if (!entry) return;
        var permlink = entry.permlink || "";
        HiddenPosts.hide(permlink);
        PostActions.hideRequested(entry.author || "", permlink);
        function drop(list) {
            var out = [];
            for (var i = 0; i < list.length; i++)
                if ((list[i].permlink || "") !== permlink) out.push(list[i]);
            return out;
        }
        root.suggestedPosts = drop(root.suggestedPosts);
        root.suggestedVideos = drop(root.suggestedVideos);
    }

    function _shareSuggestion(entry, caller) {
        if (!entry) return;
        Share.open(entry._kind === "video"
            ? ("https://serey.io/video-component/watch?author=" + entry.author + "&permalink=" + entry.permlink)
            : ("https://serey.io/authors/" + entry.author + "/" + entry.permlink), caller);
    }

    function _followSuggestion(entry) {
        if (!entry || !entry.author || entry.author === Session.username) return;
        if (!Session.isLoggedIn) { Toast.error(Lang.tr("Please log in first.")); return; }
        var now = FollowStore.toggle(Config.baseUrl, entry.author, Session.token);
        Toast.show(now ? Lang.tr("Following") : Lang.tr("Unfollowed"));
    }

    // Suggestions follow the header's community, so a Dutch reader gets Dutch
    // trending and everyone else falls back to the Global mix.
    function _scopeParams(limit) {
        var params = { limit: limit, offset: 0 };
        if (Config.communityId > 0) params.community_id = Config.communityId;
        else params.exclude_home = 1;   // Global hides the Cambodia community + children
        return params;
    }

    function _toggleSubscribe(commId, currentlySubscribed) {
        if (!Session.isLoggedIn) return;
        var id = String(commId);
        function newMap(add) {
            var m = {};
            for (var k in root.subscribedMap) m[k] = true;
            if (add) m[id] = true; else delete m[id];
            return m;
        }
        if (currentlySubscribed) {
            SubscriberService.unsubscribe(Config.baseUrl, Session.token, id,
                function () { root.subscribedMap = newMap(false); root.subscribedRev++; },
                function (err) { Toast.show(err.message || Lang.tr("Couldn't unsubscribe. Try again.")); });
        } else {
            SubscriberService.subscribe(Config.baseUrl, Session.token, id,
                function () { root.subscribedMap = newMap(true); root.subscribedRev++; root.followed(); },
                function (err) { Toast.show(err.message || Lang.tr("Couldn't subscribe. Try again.")); });
        }
    }

    // Leading column (or the whole surface when narrow): intro + create action.
    Item {
        id: leadPane
        anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
        width: root.split ? root.leadingWidth : root.width

        Flickable {
            id: flick
            anchors { top: parent.top; left: parent.left; right: parent.right; bottom: footer.top }
            contentWidth: width
            contentHeight: outer.height + Style.spacingL * 2
            clip: true

            Column {
                id: outer
                width: parent.width
                y: Style.spacingL
                spacing: Style.spacingL

                Column {
                    id: col
                    width: Math.min(parent.width - Style.spacingL * 2, units.gu(50))
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Style.spacingL

                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(col.width * (root.split ? 0.7 : 0.5), units.gu(16))
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
                            text: Lang.tr("Subscribe to a platform to fill it, or share the first post yourself.")
                            font.pixelSize: Style.fontRegular
                            font.family: Style.fontFor(text)
                            color: Style.textSecondary
                            wrapMode: Text.WordWrap
                        }
                    }

                    ActivityIndicator {
                        anchors.horizontalCenter: parent.horizontalCenter
                        running: root.suggestionsLoading && !root.split
                        visible: running
                    }

                }

                // Host for the cards when there is no detail pane to put them in: close to
                // the feed's own list width (gu(60) cap, centred), but inset so the cards
                // never run into the window edge the way a full-bleed list would.
                Item {
                    id: narrowHost
                    width: Math.min(parent.width - Style.spacingM * 2, units.gu(60))
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: root.split ? 0 : discover.height
                    visible: !root.split
                }
            }
        }

        // Pinned so the create action stays reachable no matter how long the list is.
        Rectangle {
            id: footer
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: footerBtn.height + Style.spacingM * 2
            color: Style.surface

            Rectangle {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: units.dp(1); color: Style.divider
            }

            SecondaryButton {
                id: footerBtn
                anchors { verticalCenter: parent.verticalCenter; horizontalCenter: parent.horizontalCenter }
                width: Math.min(parent.width - Style.spacingL * 2, units.gu(50))
                text: Lang.tr("Write your first post")
                onClicked: root.writePostRequested(footerBtn)

                KeyTapArea {
                    id: footerKeys
                    onActivated: root.writePostRequested(footerBtn)
                    // Nothing to subscribe to yet: this is then the only thing to focus.
                    Component.onCompleted: if (!root.firstFocusItem) root.firstFocusItem = this
                }
            }
        }
    }

    // Detail pane: the discover grid, opaque so it covers the "select a post" placeholder.
    Rectangle {
        id: discoverPane
        anchors { top: parent.top; bottom: parent.bottom; left: leadPane.right; right: parent.right }
        visible: root.split
        color: Style.surface

        Rectangle {
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
            width: units.dp(1); color: Style.divider
        }

        Flickable {
            anchors { fill: parent; margins: Style.spacingL }
            contentWidth: width
            contentHeight: wideCol.height
            clip: true

            Column {
                id: wideCol
                width: parent.width
                spacing: Style.spacingM

                Column {
                    width: parent.width
                    spacing: Style.spacingXs
                    Label {
                        width: parent.width
                        text: Lang.tr("Discover platforms to follow")
                        font.pixelSize: Style.fontTitle
                        font.weight: Font.DemiBold
                        font.family: Style.fontFor(text)
                        color: Style.textTitle
                        wrapMode: Text.WordWrap
                    }
                    Label {
                        width: parent.width
                        text: Lang.tr("Subscribe to platforms to see their posts in your feed.")
                        font.pixelSize: Style.fontRegular
                        font.family: Style.fontFor(text)
                        color: Style.textSecondary
                        wrapMode: Text.WordWrap
                    }
                }

                ActivityIndicator {
                    running: root.suggestionsLoading && root.split
                    visible: running
                }

                Item {
                    id: wideHost
                    width: parent.width
                    height: root.split ? discover.height : 0
                }
            }
        }
    }

    // One discover column (platforms, then articles, then videos), hosted by
    // whichever pane is active - only one of the two is visible at a time.
    Column {
        id: discover
        parent: root.split ? wideHost : narrowHost
        width: parent ? parent.width : 0
        spacing: Style.spacingL

        Grid {
            id: grid
            // Fill the pane: wider windows add columns rather than leaving dead space.
            width: parent.width
            columns: Math.max(1, Math.floor(width / units.gu(38)))
            spacing: columns === 1 ? Style.spacingS : Style.spacingM

            readonly property real cellWidth:
                (width - spacing * (columns - 1)) / columns

            Repeater {
                model: root.suggested

                delegate: Rectangle {
                    id: card
                    width: grid.cellWidth
                    height: cardCol.height + cardCol.anchors.margins * 2
                    radius: Style.cardRadius
                    color: cardTap.pressed ? Style.pressed : Style.card
                    border.width: units.dp(1)
                    border.color: Style.divider

                    // Declared before the content so the Subscribe pill still wins its taps.
                    MouseArea {
                        id: cardTap
                        anchors.fill: parent
                        onClicked: root.communityRequested(modelData)
                    }

                    property string commId: String(modelData.id)
                    property bool subscribed: root.subscribedRev >= 0 && !!root.subscribedMap[card.commId]
                    // One column = phone-sized: fold the card into a single scannable row.
                    readonly property bool compact: grid.columns === 1
                    readonly property real avatarW: compact ? units.gu(4) : units.gu(5)

                    Column {
                        id: cardCol
                        anchors {
                            left: parent.left; right: parent.right; top: parent.top
                            margins: card.compact ? Style.spacingS : Style.spacingM
                        }
                        spacing: Style.spacingS

                        Row {
                            width: parent.width
                            spacing: Style.spacingS

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: card.avatarW; height: width; radius: width / 2
                                color: Style.iconBackground
                                CircleImage {
                                    anchors { fill: parent; margins: units.dp(2) }
                                    source: modelData.icon || ""
                                    decode: units.gu(6)
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - card.avatarW - Style.spacingS
                                       - (card.compact ? inlineBtn.width + Style.spacingS : 0)
                                spacing: units.dp(2)

                                Label {
                                    width: parent.width
                                    text: modelData.title
                                    font.pixelSize: card.compact ? Style.fontRegular : Style.fontLarge
                                    font.weight: Font.DemiBold
                                    font.family: Style.fontFor(text)
                                    color: Style.textPrimary
                                    elide: Text.ElideRight
                                }
                                Label {
                                    width: parent.width
                                    visible: card.compact
                                    text: Lang.tr("%1 subscribers").arg(modelData.subscribers || 0)
                                    font.pixelSize: Style.fontSmall
                                    font.family: Style.fontFor(text)
                                    color: Style.textSecondary
                                    elide: Text.ElideRight
                                }
                            }

                            SubscribePill {
                                id: inlineBtn
                                anchors.verticalCenter: parent.verticalCenter
                                visible: card.compact
                                width: units.gu(12); height: units.gu(4)
                                subscribed: card.subscribed
                                onClicked: root._toggleSubscribe(card.commId, card.subscribed)

                                KeyTapArea {
                                    onActivated: root._toggleSubscribe(card.commId, card.subscribed)
                                    Component.onCompleted: if (index === 0 && card.compact) root.firstFocusItem = this
                                }
                            }
                        }

                        Label {
                            id: descLabel
                            width: parent.width
                            visible: !card.compact && root.anyDescription
                            // Fixed two lines: cards in a Grid row must end up the same height.
                            height: visible ? Math.ceil(font.pixelSize * 1.4) * 2 : 0
                            text: root.descriptionFor(modelData)
                            font.pixelSize: Style.fontSmall
                            font.family: Style.fontFor(text)
                            color: Style.textSecondary
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        Label {
                            width: parent.width
                            visible: !card.compact
                            text: Lang.tr("%1 subscribers").arg(modelData.subscribers || 0)
                            font.pixelSize: Style.fontRegular
                            font.family: Style.fontFor(text)
                            color: Style.textSecondary
                            elide: Text.ElideRight
                        }

                        SubscribePill {
                            id: wideBtn
                            visible: !card.compact
                            width: parent.width
                            subscribed: card.subscribed
                            onClicked: root._toggleSubscribe(card.commId, card.subscribed)

                            KeyTapArea {
                                onActivated: root._toggleSubscribe(card.commId, card.subscribed)
                                Component.onCompleted: if (index === 0 && !card.compact) root.firstFocusItem = this
                            }
                        }
                    }
                }
            }
        }

        // Something to read and watch right now, mixed like a real feed.
        Column {
            width: parent.width
            spacing: Style.spacingS
            visible: root.suggestions.length > 0

            Label {
                text: Lang.tr("Trending now")
                font.pixelSize: Style.fontRegular
                font.weight: Font.DemiBold
                font.family: Style.fontFor(text)
                color: Style.textTitle
            }

            // Rows sit flush like the feed's list: a gap between them would show the page
            // behind each card as soon as one is swiped.
            Column {
                width: parent.width
                spacing: 0

                Repeater {
                    model: root.suggestions

                    // Both card components live inside the delegate: loaded from outside it
                    // they could not see modelData (same reason FeedPage nests its two).
                    delegate: ListItem {
                        id: cardHost
                        width: discover.width
                        height: cardLoader.height
                        // Without these the row is transparent, so a swipe shows the page
                        // behind it and the toolkit's grey press highlight over the card.
                        color: Style.surface
                        highlightColor: Style.surface
                        divider.visible: false

                        readonly property var entry: modelData
                        readonly property bool isVideo: modelData && modelData._kind === "video"

                        onClicked: cardHost.isVideo ? root.videoRequested(cardHost.entry)
                                                    : root.postRequested(cardHost.entry)
                        onPressAndHold: PostActions.open(cardHost.entry, cardHost.isVideo ? "video" : "blog")

                        // Same split the feed uses: leading = negative (Hide), trailing = positive.
                        // Swipe is a touch affordance; desktop reaches these through the card menu.
                        leadingActions: Config.desktopMode ? null : hideActions
                        ListItemActions {
                            id: hideActions
                            delegate: Rectangle {
                                width: units.gu(7)
                                height: parent ? parent.height : units.gu(6)
                                color: Style.danger
                                Icon {
                                    anchors.centerIn: parent
                                    width: units.gu(2.5); height: width
                                    name: action.iconName
                                    color: "white"
                                }
                            }
                            actions: [
                                Action {
                                    iconName: "view-off"
                                    text: Lang.tr("Hide")
                                    onTriggered: root._hideSuggestion(cardHost.entry)
                                }
                            ]
                        }

                        trailingActions: Config.desktopMode ? null : shareActions
                        ListItemActions {
                            id: shareActions
                            delegate: Item {
                                width: units.gu(7)
                                height: parent ? parent.height : units.gu(6)
                                readonly property bool isFollowAction: action.iconName === "contact"
                                Icon {
                                    anchors.centerIn: parent
                                    width: units.gu(2.5); height: width
                                    name: action.iconName
                                    color: (parent.isFollowAction && cardHost.entry
                                            && FollowStore.isFollowing(cardHost.entry.author))
                                        ? Style.brand : Style.textPrimary
                                }
                            }
                            actions: [
                                Action {
                                    iconName: "contact"
                                    text: Lang.tr("Follow")
                                    onTriggered: root._followSuggestion(cardHost.entry)
                                },
                                Action {
                                    iconName: "share"
                                    text: Lang.tr("Share…")
                                    onTriggered: root._shareSuggestion(cardHost.entry, cardHost)
                                }
                            ]
                        }

                        Loader {
                            id: cardLoader
                            width: parent.width
                            height: item ? item.implicitHeight : 0
                            sourceComponent: cardHost.isVideo ? videoComp : postComp
                        }

                        Component {
                            id: postComp
                            PostCard {
                                width: cardLoader.width
                                post: cardHost.entry
                                onClicked: root.postRequested(cardHost.entry)
                                onAuthorClicked: root.postRequested(cardHost.entry)
                                onRequireLogin: root.loginRequested()
                                onMoreClicked: PostActions.open(cardHost.entry, "blog")
                            }
                        }

                        Component {
                            id: videoComp
                            VideoCard {
                                width: cardLoader.width
                                video: cardHost.entry
                                onClicked: root.videoRequested(cardHost.entry)
                                onAuthorClicked: root.videoRequested(cardHost.entry)
                                onMoreClicked: PostActions.open(cardHost.entry, "video")
                            }
                        }
                    }
                }
            }
        }
    }
}
