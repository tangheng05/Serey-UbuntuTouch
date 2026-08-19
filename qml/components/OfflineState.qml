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

        // Animated WebP, not a video: QtMultimedia would hand playback to media-hub, whose
        // AppArmor profile can't read our own files (see VideoDetailPage.startPlay). WebP over
        // GIF for the 8-bit alpha: GIF's 1-bit transparency left the circle's edge jagged.
        // Transparent outside the circle, so it needs no theme variant.
        AnimatedImage {
            anchors.horizontalCenter: parent.horizontalCenter
            // Big enough to read as an illustration, not an icon; capped so it stays
            // sane in the narrow detail panel of a split window.
            width: Math.min(parent.width * 0.62, units.gu(24)); height: width
            source: Qt.resolvedUrl("../../assets/offline-camp.webp")
            fillMode: Image.PreserveAspectFit
            // The file is already close to its drawn size; no sourceSize, or every frame
            // would be rescaled on the way out of the decoder.
            asynchronous: true
            // Nothing decodes while the panel is off-screen.
            playing: root.visible
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
