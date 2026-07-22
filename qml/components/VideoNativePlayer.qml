import QtQuick 2.7
import QtMultimedia 5.12
import Lomiri.Components 1.3
import "../Theme"

Item {
    id: root
    property string source: ""

    // True only on a real user pause
    property bool _userPaused: false

    // GStreamer decode error or watchdog timeout — caller retries via Chromium <video>
    signal failed()

    onSourceChanged: {
        // explicit assign avoids double-load race
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

    // tear down pipeline on deactivate
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

    // stalled/unreachable-file watchdog
    Timer {
        id: watchdog
        // generous timeout for slow buffering
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

    // toggle play/pause; tracks user-pause for overlay
    function togglePause() {
        if (player.playbackState === MediaPlayer.PlayingState) {
            player.pause();
            root._userPaused = true;
        } else {
            player.play();
            root._userPaused = false;
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.togglePause()
    }

    // loading spinner until playing
    ActivityIndicator {
        anchors.centerIn: parent
        running: root.source.length > 0
                 && !root._userPaused
                 && player.playbackState !== MediaPlayer.PlayingState
                 && player.status !== MediaPlayer.EndOfMedia
                 && player.status !== MediaPlayer.InvalidMedia
        visible: running
    }

    // play glyph on pause/end
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
