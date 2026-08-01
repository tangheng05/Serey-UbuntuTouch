import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../services/CommunitySubscriberService.js" as SubscriberService

// My Feed's empty state: a new account follows nothing, so offer subscriptions to fill it.
// Only valid because My Feed reads /serey-web/list-by-feed-mixed (follows OR community
// subscriptions); if that reverts to list-by-feed-following, subscribing here won't fill it.
Item {
    id: root

    // Emitted after a subscribe, so the feed can refetch.
    signal followed()
    signal writePostRequested()
    // Card tapped outside the Subscribe pill: open that platform.
    signal communityRequested(var community)

    property var suggested: []      // [{id, title, dns, icon, subscribers}]
    property bool suggestionsLoading: true
    // Enough rows to fill a 3-4 column grid on a desktop window; the phone just scrolls.
    readonly property int maxSuggestions: 12

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

    Component.onCompleted: {
        SubscriberService.suggestedCommunities(Config.baseUrl, root.maxSuggestions,
            function (list) { root.suggested = list; root.suggestionsLoading = false; },
            function () { root.suggestionsLoading = false; });
        if (Session.isLoggedIn)
            SubscriberService.fetchSubscribed(Config.baseUrl, Session.token,
                function (map) { root.subscribedMap = map; root.subscribedRev++ },
                function () { /* rows just start unsubscribed */ });
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

                // Host for the cards when there is no detail pane to put them in.
                Item {
                    id: narrowHost
                    width: parent.width
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
                onClicked: root.writePostRequested()
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

    // One card grid, hosted by whichever column is active (only one is visible at a time).
    Item {
        id: discover
        parent: root.split ? wideHost : narrowHost
        width: parent ? parent.width : 0
        height: grid.height
        visible: root.suggested.length > 0

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
                            visible: !card.compact
                            width: parent.width
                            subscribed: card.subscribed
                            onClicked: root._toggleSubscribe(card.commId, card.subscribed)
                        }
                    }
                }
            }
        }
    }
}
