import QtQuick 2.7
import Lomiri.Components 1.3
import QtWebEngine 1.10

/*
 * Best-effort, automatic thumbnail grabber for a locally-picked video.
 *
 * QtMultimedia/media-hub can't read the app's confined local files (→ 0x0
 * surface then SIGSEGV — see VideoDetailPage.startPlay), so we decode in-process
 * exactly like VideoWebView: load the file:// video into an in-app Chromium
 * <video> via loadHtml() based at the file's own directory (so the <video src>
 * is same-origin and the rendered frame is grabbable, not a tainted/blank
 * surface), seek to an early frame, then grab the rendered view to a JPEG.
 *
 * grab(fileUrl) → emits grabbed(localFileUrl) or failed(). The caller treats the
 * thumbnail as optional and must NEVER block the upload on it.
 */
Item {
    id: root

    // Kept on-screen at opacity 0 (NOT visible:false, which drops the item from
    // the scene graph and makes grabToImage return nothing — see PhotoUploader).
    opacity: 0
    width: units.gu(40); height: units.gu(22.5)

    signal grabbed(string fileUrl)
    signal failed()

    property string _srcDir: ""
    property bool _done: false

    function grab(fileUrl) {
        root._done = false;
        var src = String(fileUrl);
        var path = src.replace(/^file:\/\//, "");
        root._srcDir = path.substring(0, path.lastIndexOf("/") + 1);
        // Base the wrapper document at the file's directory so the <video src>
        // (an absolute file:// URL) is same-origin and the canvas/surface isn't
        // tainted — mirrors VideoWebView._baseUrl().
        var i = src.lastIndexOf("/");
        var base = i > 6 ? src.substring(0, i + 1) : src;
        watchdog.restart();
        wv.loadHtml(_html(src), base);
    }

    function _finishOk(u) { if (root._done) return; root._done = true; watchdog.stop(); poll.stop(); root.grabbed(u); }
    function _finishErr() { if (root._done) return; root._done = true; watchdog.stop(); poll.stop(); root.failed(); }

    function _html(src) {
        return '<!DOCTYPE html><html><head>' +
               '<meta name="viewport" content="width=device-width, initial-scale=1">' +
               '<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}' +
               'video{width:100%;height:100%;object-fit:contain;background:#000}</style></head>' +
               '<body><video id="v" src="' + src + '" muted autoplay playsinline preload="auto"></video>' +
               '<script>' +
               'var v=document.getElementById("v");window.__ready=0;v.muted=true;' +
               'v.addEventListener("loadeddata",function(){try{' +
               'v.currentTime=Math.min(1,(isFinite(v.duration)&&v.duration>0?v.duration:2)*0.1);' +
               '}catch(e){window.__ready=1;}});' +
               'v.addEventListener("seeked",function(){window.__ready=1;});' +
               'v.addEventListener("error",function(){window.__ready=-1;});' +
               '</script></body></html>';
    }

    function _doGrab() {
        var out = root._srcDir + "serey_thumb_" + Date.now() + ".jpg";
        wv.grabToImage(function (result) {
            if (result && result.saveToFile(out))
                root._finishOk("file://" + out);
            else
                root._finishErr();
        });
    }

    // Poll the page for "seeked" (frame ready) once it has loaded.
    Timer {
        id: poll
        interval: 250; repeat: true
        onTriggered: wv.runJavaScript("window.__ready||0", function (r) {
            if (r === 1) { poll.stop(); root._doGrab(); }
            else if (r === -1) root._finishErr();
        })
    }

    // Hard ceiling: a stuck decode/seek shouldn't leave the thumbnail pending.
    Timer { id: watchdog; interval: 8000; onTriggered: root._finishErr() }

    WebEngineProfile { id: grabProfile; offTheRecord: true }

    WebEngineView {
        id: wv
        anchors.fill: parent
        profile: grabProfile
        settings.playbackRequiresUserGesture: false
        settings.localContentCanAccessFileUrls: true
        settings.localContentCanAccessRemoteUrls: true
        onLoadingChanged: {
            if (loadRequest.status === WebEngineView.LoadSucceededStatus)
                poll.restart();
            else if (loadRequest.status === WebEngineView.LoadFailedStatus)
                root._finishErr();
        }
    }
}
