import QtQuick 2.7
import Lomiri.DownloadManager 1.2

Item {
    id: dl

    property string url: ""
    property string title: ""
    property bool showInIndicator: true

    signal progress(real pct)        // 0..100
    signal finished(string path)     // absolute path on disk
    signal failed(string message)

    function start(u) {
        if (u && u.length > 0)
            dl.url = u;
        stall.restart();
        single.download(dl.url);
    }

    SingleDownload {
        id: single
        // autoStart (default true): download() begins immediately. With it false
        // the transfer is created but never started — which left the button stuck
        // at 0%.
        autoStart: true
        allowMobileDownload: true
        metadata: Metadata { showInIndicator: dl.showInIndicator; title: dl.title }

        onProgressChanged: {
            stall.restart();           // real progress — reset the stall watchdog
            dl.progress(progress);
        }
        onFinished: { stall.stop(); dl.finished(path); }
        onErrorChanged: if (errorMessage && errorMessage.length > 0) { stall.stop(); dl.failed(errorMessage); }
    }

    // If nothing moves for a while — no download daemon (the desktop preview) or a
    // dead stall — give up so the UI resets instead of sitting at 0% forever.
    Timer {
        id: stall
        interval: 30000
        repeat: false
        onTriggered: dl.failed("Download timed out")
    }
}
