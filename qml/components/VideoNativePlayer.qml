import QtQuick 2.7
import QtMultimedia 5.12
import Lomiri.Components 1.3
import "../Theme"

Item {
    id: root
    property string source: ""

    // True only on a real user pause — media-hub reports buffering pre-roll
    // as "paused" too, so playbackState alone can't tell them apart.
    property bool _userPaused: false

    // GStreamer decode error or watchdog timeout — caller retries via Chromium <video>
    signal failed()

    onSourceChanged: {
        // Explicit assign (not binding + autoPlay) so the file loads exactly
        // once — both together raced a load against this handler's stop().
        player.stop();
        root._userPaused = false;
        if (source.length > 0) {
            player.source = source;
            watchdog.restart();
            player.play();
        } else {
            player.source = "";
            watchdog.stop();
        }
    }

    // Tear down the GStreamer pipeline on deactivate/pop — else it keeps buffering
    Component.onDestruction: player.stop()

    MediaPlayer {
        id: player
        onError: {
            watchdog.stop();
            root.failed();
        }
        // Stop the watchdog once playback actually starts / buffers.
        onPlaybackStateChanged: if (playbackState === MediaPlayer.PlayingState) watchdog.stop()
        onStatusChanged: if (status === MediaPlayer.Buffered) watchdog.stop()
    }

    // Stalled/unreachable-file watchdog — stops and emits failed() if nothing's
    // playing/buffered after a timeout, instead of freezing on a spinner.
    Timer {
        id: watchdog
        // Generous: non-faststart .mov streams buffer ~7-10s on media-hub, and
        // the Chromium fallback can't render .mov at all — worse than waiting.
        interval: 20000
        repeat: false
        onTriggered: {
            if (player.playbackState !== MediaPlayer.PlayingState
                && player.status !== MediaPlayer.Buffered
                && player.status !== MediaPlayer.EndOfMedia) {
                player.stop();
                root.failed();
            }
        }
    }

    VideoOutput {
        anchors.fill: parent
        source: player
        fillMode: VideoOutput.PreserveAspectFit
    }

    // Tap to toggle play / pause. Track an *explicit* user pause so the overlay
    // can tell it apart from media-hub's buffering "paused".
    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (player.playbackState === MediaPlayer.PlayingState) {
                player.pause();
                root._userPaused = true;
            } else {
                player.play();
                root._userPaused = false;
            }
        }
    }

    // Loading spinner: shown for the whole "play requested but no frames yet"
    // window — including media-hub's buffering pre-roll, which reports as paused.
    // Hidden only once actually playing, ended, or deliberately paused by the user.
    ActivityIndicator {
        anchors.centerIn: parent
        running: root.source.length > 0
                 && !root._userPaused
                 && player.playbackState !== MediaPlayer.PlayingState
                 && player.status !== MediaPlayer.EndOfMedia
                 && player.status !== MediaPlayer.InvalidMedia
        visible: running
    }

    // Centre play glyph: only on a real user pause (or at end for replay) — never
    // over the loading frame, where the spinner owns the stage.
    Icon {
        anchors.centerIn: parent
        width: units.gu(7)
        height: width
        name: "media-playback-start"
        color: Style.textOnBrand
        visible: root._userPaused || player.status === MediaPlayer.EndOfMedia
        MouseArea {
            anchors.fill: parent
            onClicked: { player.play(); root._userPaused = false; }
        }
    }
}
