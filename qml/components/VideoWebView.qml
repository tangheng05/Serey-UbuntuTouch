import QtQuick 2.7
import QtWebEngine 1.10

Item {
    id: root
    property string embedUrl: ""
    property bool wrap: false
    property bool directVideo: false
    // Detail playback shows native controls; reels hide them + loop
    property bool controls: true
    property bool loop: false
    // True once the <video> has a decoded frame — hosts fade in on this so
    // the WebView's blank first frame never flashes
    property bool ready: false
    property bool paused: false
    signal fullscreenToggled(bool on)

    // Freeze the Chromium renderer on app background/suspend — same
    // SIGBUS-on-resume issue and lifecycleState int trap as WebAppView.
    readonly property int _lcActive: 0
    readonly property int _lcFrozen: 1
    property bool appActive: Qt.application.state === Qt.ApplicationActive
    onAppActiveChanged: {
        if (appActive) {
            vwFreezeTimer.stop();
            wv.visible = true;
            wv.lifecycleState = root._lcActive;
        } else {
            wv.visible = false;
            vwFreezeTimer.restart();
        }
    }
    Timer {
        id: vwFreezeTimer
        interval: 300
        onTriggered: if (!root.appActive) wv.lifecycleState = root._lcFrozen
    }

    // Toggle play/pause of the direct <video> (used by the reels viewer's tap).
    function togglePause() {
        if (root.paused) {
            wv.runJavaScript("document.querySelector('video').play();");
            root.paused = false;
        } else {
            wv.runJavaScript("document.querySelector('video').pause();");
            root.paused = true;
        }
    }

    readonly property string mobileUA: "Mozilla/5.0 (Linux; Android 13; Pixel 3a) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"

    onEmbedUrlChanged: _load()
    onWrapChanged: _load()
    onDirectVideoChanged: _load()
    onControlsChanged: _load()
    onLoopChanged: _load()
    Component.onCompleted: _load()

    // Off-the-record: unlike the Homepage profile, video doesn't need persistent login
    WebEngineProfile {
        id: videoProfile
        httpUserAgent: root.mobileUA
        offTheRecord: true
    }

    WebEngineView {
        id: wv
        anchors.fill: parent
        profile: videoProfile

        // Autoplay without a user gesture (our overlay tap is the gesture);
        // local-file access lets an offline file:// <video> load from its wrapper.
        settings.playbackRequiresUserGesture: false
        settings.fullScreenSupportEnabled: true
        settings.localContentCanAccessFileUrls: true
        settings.localContentCanAccessRemoteUrls: true

        // Make every frame (runOnSubframes — reaches the YouTube iframe) report a
        // mobile navigator, defeating client-side desktop sniffing.
        userScripts: [
            WebEngineScript {
                injectionPoint: WebEngineScript.DocumentCreation
                worldId: WebEngineScript.MainWorld
                runOnSubframes: true
                sourceCode: "" +
                    "Object.defineProperty(navigator,'userAgent',{get:function(){return '" + root.mobileUA + "';},configurable:true});" +
                    "Object.defineProperty(navigator,'platform',{get:function(){return 'Linux armv8l';},configurable:true});" +
                    "Object.defineProperty(navigator,'maxTouchPoints',{get:function(){return 5;},configurable:true});"
            }
        ]

        onFullScreenRequested: function (request) {
            request.accept();
            root.fullscreenToggled(request.toggleOn);
        }

        // LoadSucceededStatus == 2 (same enum-not-exposed trap). directVideo
        // waits for the __SEREY_READY__ sentinel instead — page-load fires
        // before the first frame paints, which would flash black.
        onLoadingChanged: function (loadRequest) {
            if (loadRequest.status === 2 && !root.directVideo)
                root.ready = true;
        }

        onJavaScriptConsoleMessage: function (level, message, lineNumber, sourceID) {
            if (root.directVideo && message.indexOf("__SEREY_READY__") >= 0)
                root.ready = true;
        }
    }

    // Wrapper is "served from" serey.io so embeds see a normal referrer
    // (youtube.com trips YouTube's embed check); offline copies base on the
    // file's own directory so <video src> is same-origin.
    readonly property string _origin: "https://serey.io"
    function _baseUrl() {
        if (directVideo && embedUrl.indexOf("file://") === 0) {
            var i = embedUrl.lastIndexOf("/");
            return i > 6 ? embedUrl.substring(0, i + 1) : embedUrl;
        }
        return _origin + "/";
    }

    function _iframeHtml() {
        return '<!DOCTYPE html><html><head>' +
               '<meta name="viewport" content="width=device-width, initial-scale=1">' +
               '<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}' +
               'iframe{border:0;width:100%;height:100%}</style></head>' +
               '<body><iframe src="' + embedUrl + '" ' +
               'allow="autoplay; encrypted-media; fullscreen; picture-in-picture">' +
               '</iframe></body></html>';
    }

    function _videoHtml() {
        var attrs = 'autoplay playsinline webkit-playsinline preload="auto"';
        if (controls) attrs += ' controls';
        if (loop) attrs += ' loop';
        return '<!DOCTYPE html><html><head>' +
               '<meta name="viewport" content="width=device-width, initial-scale=1">' +
               '<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}' +
               'video{width:100%;height:100%;object-fit:contain;background:#000}</style></head>' +
               '<body><video src="' + embedUrl + '" ' + attrs + '></video>' +
               '<script>(function(){var v=document.querySelector("video");' +
               'function r(){console.log("__SEREY_READY__");}' +
               'v.addEventListener("loadeddata",r);v.addEventListener("playing",r);})();</script>' +
               '</body></html>';
    }

    function _load() {
        if (embedUrl.length === 0)
            return;
        root.ready = false;
        if (directVideo)
            wv.loadHtml(_videoHtml(), _baseUrl());
        else if (wrap)
            wv.loadHtml(_iframeHtml(), _baseUrl());
        else
            wv.url = embedUrl;
    }
}
