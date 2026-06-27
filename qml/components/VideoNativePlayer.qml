import QtQuick 2.7
import QtMultimedia 5.12
import Lomiri.Components 1.3
import "../Theme"

/*
 * Native player for Serey-hosted videos (platform_type === "SEREY"), whose
 * `video_link` is a direct media file (mp4 on s3.serey.io / upload.serey.io /
 * fsgw.sabay.com). Third-party embeds use VideoWebView instead. Loaded lazily by
 * VideoDetailPage. On a playback error it opens the file externally (system
 * player / browser) via `fallbackUrl`.
 */
Item {
    id: root
    property string source: ""
    property string fallbackUrl: ""

    onSourceChanged: {
        player.stop();
        if (source.length > 0) {
            watchdog.restart();
            player.play();
        } else {
            watchdog.stop();
        }
    }

    // Ensure the GStreamer pipeline is torn down when the Loader deactivates or
    // the detail page is popped — otherwise it can keep buffering in background.
    Component.onDestruction: player.stop()

    MediaPlayer {
        id: player
        source: root.source
        autoPlay: true
        onError: {
            watchdog.stop();
            if (root.fallbackUrl.length > 0)
                Qt.openUrlExternally(root.fallbackUrl);
        }
        // Stop the watchdog once playback actually starts / buffers.
        onPlaybackStateChanged: if (playbackState === MediaPlayer.PlayingState) watchdog.stop()
        onStatusChanged: if (status === MediaPlayer.Buffered) watchdog.stop()
    }

    // Watchdog for unreachable files (e.g. SEREY .mov returning 504): if nothing
    // is playing/buffered after a few seconds, stop and hand off to the browser
    // instead of leaving the UI frozen on a spinner.
    Timer {
        id: watchdog
        interval: 6000
        repeat: false
        onTriggered: {
            if (player.playbackState !== MediaPlayer.PlayingState
                && player.status !== MediaPlayer.Buffered
                && player.status !== MediaPlayer.EndOfMedia) {
                player.stop();
                if (root.fallbackUrl.length > 0)
                    Qt.openUrlExternally(root.fallbackUrl);
            }
        }
    }

    VideoOutput {
        anchors.fill: parent
        source: player
        fillMode: VideoOutput.PreserveAspectFit
    }

    // Tap to toggle play / pause.
    MouseArea {
        anchors.fill: parent
        onClicked: player.playbackState === MediaPlayer.PlayingState
                   ? player.pause() : player.play()
    }

    // Buffering / loading spinner.
    ActivityIndicator {
        anchors.centerIn: parent
        running: player.status === MediaPlayer.Loading
                 || player.status === MediaPlayer.Buffering
        visible: running
    }

    // Centre play glyph while paused.
    Icon {
        anchors.centerIn: parent
        width: units.gu(7)
        height: width
        name: "media-playback-start"
        color: Style.textOnBrand
        visible: player.playbackState !== MediaPlayer.PlayingState
                 && player.status !== MediaPlayer.Loading
                 && player.status !== MediaPlayer.Buffering
        MouseArea { anchors.fill: parent; onClicked: player.play() }
    }
}
