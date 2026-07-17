import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../services/CommunitySubscriberService.js" as SubscriberService

// My Feed's empty state. A new account subscribes to nothing and follows nobody,
// so the feed is empty by definition — this offers the action that fills it.
//
// Suggesting communities only works because My Feed reads
// /serey-web/list-by-feed-mixed (follows OR community subscriptions). If that
// ever reverts to list-by-feed-following, subscribing here would leave the feed
// just as empty and this screen becomes a lie — keep the two in step.
//
// Suggestions are ranked by subscriber count ("active") and come from the
// community tree Main.qml already fetched at startup, so there's no extra
// get-communities round-trip.
Item {
    id: root

    // Emitted after a subscribe, so the feed can refetch.
    signal followed()
    signal writePostRequested()

    property var candidates: []
    property var counts: ({})       // id (string) -> subscriber count
    property int pendingCounts: 0
    property var suggested: []
    readonly property int maxSuggestions: 5

    property var subscribedMap: ({})
    property int subscribedRev: 0

    Component.onCompleted: {
        _buildCandidates();
        if (Session.isLoggedIn)
            SubscriberService.fetchSubscribed(Config.baseUrl, Session.token,
                function (map) { root.subscribedMap = map; root.subscribedRev++ },
                function () { /* rows just start unsubscribed */ });
    }

    function _buildCandidates() {
        var out = [];
        var seen = {};
        for (var k in Config.communityById) {
            var c = Config.communityById[k];
            // Skip country hubs: they hold children, you don't post in them.
            if (!c || !c.dns || c.childCount > 0 || seen[c.dns]) continue;
            // Honour the Global feed's exclude_home rule: the hidden community
            // and its descendants are filtered out of every feed server-side, so
            // suggesting them would subscribe the user to content they'd never
            // see. Also why Cambodia's 35 children dominated this list.
            if (Config.hiddenCommunityIds[String(c.id)]) continue;
            seen[c.dns] = true;
            out.push(c);
        }
        // Cap the pool before fetching counts so a large tree can't fire a
        // request per community.
        var pool = out.slice(0, 20);
        root.candidates = pool;
        if (pool.length === 0) return;
        root.pendingCounts = pool.length;
        for (var i = 0; i < pool.length; i++) _fetchCount(pool[i]);
    }

    function _fetchCount(c) {
        SubscriberService.subscriberCount(Config.baseUrl, c.id,
            function (n) { root._onCount(c.id, n); },
            function () { root._onCount(c.id, 0); });
    }

    function _onCount(id, n) {
        var m = {};
        for (var k in root.counts) m[k] = root.counts[k];
        m[String(id)] = n;
        root.counts = m;
        root.pendingCounts -= 1;
        if (root.pendingCounts <= 0) _rank();
    }

    // Most subscribers first ("active"), capped.
    function _rank() {
        var list = root.candidates.slice();
        list.sort(function (a, b) {
            return (root.counts[String(b.id)] || 0) - (root.counts[String(a.id)] || 0);
        });
        root.suggested = list.slice(0, root.maxSuggestions);
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
                    text: Lang.tr("Subscribe to a community to see its posts here.")
                    font.pixelSize: Style.fontRegular
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                    wrapMode: Text.WordWrap
                }
            }

            ActivityIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: root.suggested.length === 0 && root.candidates.length > 0
                visible: running
            }

            // --- Suggested communities ---------------------------------------
            Column {
                width: parent.width
                spacing: 0
                visible: root.suggested.length > 0

                Label {
                    width: parent.width
                    text: Lang.tr("Active communities")
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

                            property string commId: String(modelData.id)
                            property bool subscribed: root.subscribedRev >= 0 && !!root.subscribedMap[row.commId]

                            Row {
                                anchors.fill: parent
                                spacing: Style.spacingM

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(4.5); height: width; radius: width / 2
                                    color: Style.iconBackground
                                    CircleImage {
                                        anchors { fill: parent; margins: units.dp(2) }
                                        source: modelData.icon || ""
                                        decode: units.gu(5)
                                    }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - units.gu(4.5) - subBtn.width - Style.spacingM * 2
                                    spacing: units.dp(2)
                                    Label {
                                        width: parent.width
                                        text: modelData.title
                                        font.pixelSize: Style.fontRegular
                                        font.weight: Font.DemiBold
                                        font.family: Style.fontFor(text)
                                        color: Style.textPrimary
                                        elide: Text.ElideRight
                                    }
                                    Label {
                                        width: parent.width
                                        text: Lang.tr("%1 subscribers").arg(root.counts[row.commId] || 0)
                                        font.pixelSize: Style.fontSmall
                                        font.family: Style.fontFor(text)
                                        color: Style.textSecondary
                                        elide: Text.ElideRight
                                    }
                                }

                                AbstractButton {
                                    id: subBtn
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(12); height: units.gu(4)
                                    onClicked: root._toggleSubscribe(row.commId, row.subscribed)

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Style.pillRadius
                                        color: row.subscribed ? "transparent"
                                             : subBtn.pressed ? Style.brandDark : Style.brand
                                        border.width: row.subscribed ? units.dp(1.5) : 0
                                        border.color: Style.divider
                                        Behavior on color { ColorAnimation { duration: 120 } }

                                        Label {
                                            anchors.centerIn: parent
                                            text: row.subscribed ? Lang.tr("Subscribed") : Lang.tr("Subscribe")
                                            font.pixelSize: Style.fontSmall
                                            font.weight: Font.DemiBold
                                            font.family: Style.fontFor(text)
                                            color: row.subscribed ? Style.textSecondary : Style.textOnBrand
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
