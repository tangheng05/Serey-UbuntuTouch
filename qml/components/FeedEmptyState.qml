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

    property var suggested: []      // [{id, title, dns, icon, subscribers}]
    property bool suggestionsLoading: true
    readonly property int maxSuggestions: 5

    property var subscribedMap: ({})
    property int subscribedRev: 0

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
                    text: Lang.tr("Subscribe to a platform to see its posts here.")
                    font.pixelSize: Style.fontRegular
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                    wrapMode: Text.WordWrap
                }
            }

            ActivityIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: root.suggestionsLoading
                visible: running
            }

            // --- Suggested communities ---------------------------------------
            Column {
                width: parent.width
                spacing: 0
                visible: root.suggested.length > 0

                Label {
                    width: parent.width
                    text: Lang.tr("Active platforms")
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
                                        text: Lang.tr("%1 subscribers").arg(modelData.subscribers || 0)
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
