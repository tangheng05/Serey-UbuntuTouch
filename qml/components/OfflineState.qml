import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"

// Offline placeholder: names what is still readable on this device and opens the library.
Item {
    id: root

    property int articleCount: SavedPosts.items.length
    property int videoCount: Downloads.items.length
    readonly property bool hasContent: articleCount + videoCount > 0

    signal retry()

    // A failed retry changes nothing on screen, so the tap needs an answer of its own:
    // spin while the probe runs, with a floor so it registers as a check that happened.
    property bool checking: false
    function _retry() {
        root.checking = true;
        checkFloor.restart();
        Net.probe();          // confirms reachability even if the caller's reload is silent
        root.retry();
    }
    Timer {
        id: checkFloor
        interval: 1600
        repeat: false
        onTriggered: root.checking = false
    }

    function _articles() {
        return articleCount === 1 ? Lang.tr("1 article")
                                  : Lang.tr("%1 articles").arg(articleCount);
    }
    function _videos() {
        return videoCount === 1 ? Lang.tr("1 video")
                                : Lang.tr("%1 videos").arg(videoCount);
    }
    // Only name the kinds that are actually there, so "0 videos" never shows up.
    function _inventory() {
        if (articleCount > 0 && videoCount > 0)
            return Lang.tr("%1 and %2").arg(_articles()).arg(_videos());
        return articleCount > 0 ? _articles() : _videos();
    }

    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.spacingL * 2, units.gu(45))
        spacing: Style.spacingM

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            // Big enough to read as an illustration, not an icon; capped so it stays
            // sane in the narrow detail panel of a split window.
            width: Math.min(parent.width * 0.62, units.gu(24)); height: width
            // One illustration for both themes: it reads on light and dark alike.
            source: Qt.resolvedUrl("../../assets/offline-camp.png")
            fillMode: Image.PreserveAspectFit
            sourceSize.width: units.gu(24)
            asynchronous: true

            // Slow, shallow breathing: at illustration size a 12% pulse read as a throb,
            // so it's 3% over a 7s cycle, on a sine so there is no beat at the turns.
            SequentialAnimation on scale {
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 1.03; duration: 3500; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1.03; to: 1.0; duration: 3500; easing.type: Easing.InOutSine }
            }
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.hasContent
                  ? Lang.tr("No network right now, but your library is ready.")
                  : Lang.tr("There is currently no network connection.")
            font.pixelSize: Style.fontLarge
            font.weight: Font.DemiBold
            font.family: Style.fontFor(text)
            color: Style.textPrimary
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.hasContent
                  ? Lang.tr("You have %1 on this device.").arg(root._inventory())
                    + " " + Lang.tr("They stay with you, even without a connection.")
                  : Lang.tr("Check your connection and try again.")
            font.pixelSize: Style.fontSmall
            font.family: Style.fontFor(text)
            color: Style.textSecondary
        }

        Item { width: 1; height: Style.spacingS }

        PrimaryButton {
            width: parent.width
            visible: root.hasContent
            text: Lang.tr("Open your library")
            onClicked: Nav.openLibrary()
        }

        SecondaryButton {
            width: parent.width
            busy: root.checking
            text: root.checking ? Lang.tr("Checking…") : Lang.tr("Try again")
            onClicked: root._retry()
        }
    }
}
