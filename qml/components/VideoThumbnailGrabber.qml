import QtQuick 2.7
import Lomiri.Components 1.3
import QtWebEngine 1.10

Item {
    id: root

    // Kept on-screen at opacity 0 (NOT visible:false, which would drop the item
    // from the scene graph) so the WebEngineView actually renders/decodes.
    opacity: 0
    width: units.gu(40); height: units.gu(22.5)

    signal grabbed(string dataUrl)
    signal failed()

    property bool _done: false

    function grab(fileUrl) {
        root._done = false;
        var src = String(fileUrl);
        // Base the wrapper document at the file's directory so the <video src>
        // (an absolute file:// URL) is same-origin and the canvas isn't tainted —
        // mirrors VideoWebView._baseUrl().
        var i = src.lastIndexOf("/");
        var base = i > 6 ? src.substring(0, i + 1) : src;
        watchdog.restart();
        wv.loadHtml(_html(src), base);
    }

    function _finishOk(dataUrl) { if (root._done) return; root._done = true; watchdog.stop(); poll.stop(); root.grabbed(dataUrl); }
    function _finishErr() { if (root._done) return; root._done = true; watchdog.stop(); poll.stop(); root.failed(); }

    function _html(src) {
        return '<!DOCTYPE html><html><head>' +
               '<meta name="viewport" content="width=device-width, initial-scale=1">' +
               '<style>html,body{margin:0;background:#000}video{position:fixed;left:0;top:0;width:100%;height:100%;object-fit:contain}</style></head>' +
               '<body><video id="v" src="' + src + '" muted autoplay playsinline preload="auto"></video>' +
               '<canvas id="c" style="display:none"></canvas>' +
               '<script>(function(){' +
               'var v=document.getElementById("v"),c=document.getElementById("c");window.__t="";' +
               'function cap(){try{var w=v.videoWidth,h=v.videoHeight;if(!w||!h){window.__t="ERR";return;}' +
               'var s=Math.min(1,720/w);c.width=Math.round(w*s);c.height=Math.round(h*s);' +
               'c.getContext("2d").drawImage(v,0,0,c.width,c.height);window.__t=c.toDataURL("image/jpeg",0.82);}' +
               'catch(e){window.__t="ERR";}}' +
               'v.muted=true;' +
               'v.addEventListener("loadeddata",function(){try{v.currentTime=Math.min(1,(isFinite(v.duration)&&v.duration>0?v.duration:2)*0.1);}catch(e){cap();}});' +
               'v.addEventListener("seeked",function(){cap();});' +
               'v.addEventListener("error",function(){window.__t="ERR";});' +
               '})();</script></body></html>';
    }

    // Poll the page for the captured data URL once the document has loaded.
    Timer {
        id: poll
        interval: 250; repeat: true
        onTriggered: wv.runJavaScript("window.__t||''", function (s) {
            if (s === "ERR") root._finishErr();
            else if (s && s.indexOf("data:") === 0) root._finishOk(s);
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
