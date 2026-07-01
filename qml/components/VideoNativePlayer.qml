import QtQuick 2.7
import QtMultimedia 5.12
import Lomiri.Components 1.3
import "../Theme"

/*
 * QtMultimedia (media-hub) player. VideoDetailPage routes only *remote* .mov here
 * — Chromium's <video> decodes the QuickTime audio but not the video track, while
 * media-hub's GStreamer/qtdemux renders it. Everything else (mp4 and all local
 * downloads) plays in VideoWebView instead, because media-hub's AppArmor profile
 * can't read the app's downloaded files. On a playback error it emits `failed()`;
 * the caller then retries in the Chromium <video> as a last resort.
 */
Item {
    id: root
    property string source: ""

    // True only when the user tapped to pause. media-hub reports the initial
    // buffering pre-roll as "paused" too, so we can't tell loading from a real
    // pause by playbackState alone — without this flag the play glyph appears
    // over the loading frame and the user taps play twice.
    property bool _userPaused: false

    // Emitted when GStreamer can't play the file (decode error or watchdog
    // timeout). The caller retries in-app via a Chromium <video> rather than the
    // external browser.
    signal failed()

    onSourceChanged: {
        // Set the player source explicitly (not via a binding + autoPlay) so the
        // file is loaded exactly once. Doing both let autoPlay start a load that
        // this handler's stop() immediately killed, then play() restarted it —
        // doubling time-to-first-frame and leaving the stage black meanwhile.
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

    // Ensure the GStreamer pipeline is torn down when the Loader deactivates or
    // the detail page is popped — otherwise it can keep buffering in background.
    Component.onDestruction: player.stop()

    MediaPlayer {
        id: player
        // source is assigned in onSourceChanged (single load — see above), not
        // bound here, and autoPlay is off so it can't race that explicit load.
        onError: {
            watchdog.stop();
            root.failed();
        }
        // Stop the watchdog once playback actually starts / buffers.
        onPlaybackStateChanged: if (playbackState === MediaPlayer.PlayingState) watchdog.stop()
        onStatusChanged: if (status === MediaPlayer.Buffered) watchdog.stop()
    }

    // Watchdog for stalled/unreachable files: if nothing is playing/buffered
    // after a few seconds, stop and emit failed() so the caller can retry in-app
    // (Chromium <video>) instead of leaving the UI frozen on a spinner.
    Timer {
        id: watchdog
        // Generous: non-faststart .mov streams buffer ~7-10 s before the first
        // frame on media-hub. A short timeout would abort them into the Chromium
        // fallback, which can't render .mov at all — worse than waiting.
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
