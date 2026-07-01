import QtQuick 2.7
import QtWebEngine 1.10

/*
 * In-app video web view, on QtWebEngine (same engine the Homepage mini-app uses),
 * in three modes:
 *  - Direct top-level (wrap=false, directVideo=false): load `embedUrl` as a
 *    top-level page.
 *  - Iframe wrap (wrap=true): embed `embedUrl` inside a minimal full-bleed HTML
 *    <iframe> document. Used for third-party players (YouTube / TikTok /
 *    Facebook), which render a black frame when pointed at directly on device.
 *  - Direct video (directVideo=true): render `embedUrl` (a direct media file —
 *    e.g. a Serey-hosted .mp4, local or remote) inside an HTML5 <video> element.
 *
 * Mobile identity: QtWebEngine's default UA is desktop ("X11; Linux"), so
 * YouTube serves the PC player. We force mobile exactly like WebAppView — a
 * mobile `httpUserAgent` on the profile (fixes the server-side embed) AND a
 * document-creation user script that overrides navigator.* in every frame,
 * including the cross-origin YouTube iframe (fixes client-side sniffing).
 *
 * `fullscreenToggled(on)` is emitted when the <video> control or the YouTube
 * iframe requests fullscreen; the host (VideoDetailPage) makes the view fill the
 * screen.
 */
Item {
    id: root
    property string embedUrl: ""
    property bool wrap: false
    property bool directVideo: false
    // Direct-video chrome. Detail playback wants the native <video> controls;
    // the reels viewer hides them (controls:false) and loops (loop:true) for an
    // immersive, TikTok-style surface.
    property bool controls: true
    property bool loop: false
    // True once the inner page has finished loading (the <video> exists and is
    // starting). Hosts fade the surface in on this so the WebView's blank first
    // frame never flashes (the reels scroll-in flicker).
    property bool ready: false
    property bool paused: false
    signal fullscreenToggled(bool on)

<<<<<<< Updated upstream
    // Freeze the Chromium renderer when the whole app is backgrounded/suspended —
    // a live WebEngineView left Active across a long OS suspend loses its GPU/
    // shared-memory context and SIGBUSes on resume. (Same lifecycleState int trap
    // as WebAppView: enum names aren't exposed on UT, so use the ints.) Frozen is
    // only legal while hidden, so wv binds `visible` to appActive and we defer the
    // freeze a tick; resuming to Active is always legal.
    readonly property int _lcActive: 0
    readonly property int _lcFrozen: 1
    // Imperative (only on an actual state change, never at startup) so a quirky
    // initial application state can't leave the player blank.
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
=======
    function togglePause() {
        if (root.paused) {
            wv.runJavaScript("document.querySelector('video').play();");
            root.paused = false;
        } else {
            wv.runJavaScript("document.querySelector('video').pause();");
            root.paused = true;
        }
    }
>>>>>>> Stashed changes

    readonly property string mobileUA: "Mozilla/5.0 (Linux; Android 13; Pixel 3a) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"

    onEmbedUrlChanged: _load()
    onWrapChanged: _load()
    onDirectVideoChanged: _load()
    onControlsChanged: _load()
    onLoopChanged: _load()
    Component.onCompleted: _load()

    // Off-the-record: a transient player shouldn't persist streamed-video HTTP
    // cache/cookies to the phone's disk. (The Homepage profile is non-OTR because
    // it needs persistent login; video doesn't.)
    WebEngineProfile {
        id: videoProfile
        httpUserAgent: root.mobileUA
        offTheRecord: true
    }

    WebEngineView {
        id: wv
        anchors.fill: parent
        // `visible` is toggled imperatively in onAppActiveChanged on app
        // background/foreground so the Active->Frozen transition (rejected while
        // visible) becomes legal — not a declarative binding, to avoid blanking
        // the player if the initial application state is ever reported non-active.
        profile: videoProfile

        // Autoplay without an in-page tap (our overlay tap is the gesture);
        // fullscreen support must be enabled for fullScreenRequested to fire;
        // local-file access lets an offline file:// <video> load from a file://
        // wrapper document.
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

        // LoadSucceededStatus == 2. (Enum names aren't reliably exposed to QML on
        // UT's QtWebEngine — same trap as lifecycleState — so compare the int.)
        // For directVideo we wait for the <video>'s first decoded frame instead
        // (the __SEREY_READY__ console sentinel below), because page-load fires
        // before the frame paints — fading the surface in then flashes black.
        onLoadingChanged: function (loadRequest) {
            if (loadRequest.status === 2 && !root.directVideo)
                root.ready = true;
        }

        // The direct-video page logs __SEREY_READY__ once its <video> has a frame
        // (loadeddata/playing); flip ready then so the host reveals a painted
        // surface, not the WebView's blank first frame.
        onJavaScriptConsoleMessage: function (level, message, lineNumber, sourceID) {
            if (root.directVideo && message.indexOf("__SEREY_READY__") >= 0)
                root.ready = true;
        }
    }

    // The wrapper document is "served from" serey.io so an embedded player sees a
    // normal site origin/referrer (basing it on youtube.com trips YouTube's embed
    // referrer check). An offline copy is a local file:// URL — base the wrapper
    // on the file's own directory so the <video src> is same-origin.
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
