import QtQuick 2.7
import Lomiri.Components 1.3
import QtWebEngine 1.10

/*
 * Reads a remote video's duration the same way the web's getVideoDuration does:
 * a hidden Chromium <video preload="metadata">. We use Chromium (not
 * QtMultimedia) because non-faststart MP4s keep the moov atom at the tail, and
 * only the browser range-requests it to resolve duration without downloading the
 * whole file (media-hub would stall) — and because it stays in our own
 * confinement.
 *
 * probe(url, cb): cb(durationSeconds) — a positive Number, or -1 when the
 * duration can't be determined (error/timeout). Calls are serialised by the
 * caller (one probe at a time), and this view is mounted ONLY while probing, so
 * it never coexists with the reels player's WebView (two live WebViews crash the
 * app — see the dual-Chromium memory note).
 */
Item {
    id: root
    opacity: 0
    width: units.gu(2); height: units.gu(2)

    property var _cb: null
    property bool _busy: false

    function probe(url, cb) {
        root._cb = cb;
        root._busy = true;
        watchdog.restart();
        wv.loadHtml(_html(url), "https://serey.io/");
    }

    function _finish(dur) {
        if (!root._busy) return;
        root._busy = false;
        watchdog.stop();
        poll.stop();
        var cb = root._cb;
        root._cb = null;
        if (cb) cb(dur);
    }

    function _html(url) {
        return '<!DOCTYPE html><html><head><meta charset="utf-8"></head><body>' +
               '<video id="v" preload="metadata" muted crossorigin="anonymous" src="' + url + '"></video>' +
               '<script>var v=document.getElementById("v");window.__d=0;' +
               'v.addEventListener("loadedmetadata",function(){window.__d=(isFinite(v.duration)&&v.duration>0)?v.duration:-1;});' +
               'v.addEventListener("error",function(){window.__d=-1;});</script>' +
               '</body></html>';
    }

    // Poll the page for the resolved duration once the document has loaded.
    Timer {
        id: poll
        interval: 200; repeat: true
        onTriggered: wv.runJavaScript("window.__d||0", function (d) {
            if (d > 0) root._finish(d);
            else if (d < 0) root._finish(-1);
        })
    }

    // Bounds a stuck metadata fetch (web uses a 4 s budget; allow a little more
    // for a phone on mobile data). Unknown → caller excludes it from reels.
    Timer { id: watchdog; interval: 6000; onTriggered: root._finish(-1) }

    WebEngineProfile { id: probeProfile; offTheRecord: true }

    WebEngineView {
        id: wv
        anchors.fill: parent
        profile: probeProfile
        settings.localContentCanAccessRemoteUrls: true
        onLoadingChanged: {
            if (loadRequest.status === WebEngineView.LoadSucceededStatus)
                poll.restart();
            else if (loadRequest.status === WebEngineView.LoadFailedStatus)
                root._finish(-1);
        }
    }
}
