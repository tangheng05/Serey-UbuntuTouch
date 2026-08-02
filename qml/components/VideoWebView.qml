import QtQuick 2.7
import QtQuick.Window 2.2
import QtWebEngine 1.10
import Lomiri.Components 1.3

Item {
    id: root
    property string embedUrl: ""
    property bool wrap: false
    property bool directVideo: false
    // Detail playback shows native controls; reels hide them + loop
    property bool controls: true
    property bool loop: false

    // CSS pixel is a physical pixel here, so scale controls by the app's grid-unit ratio
    property real cssScale: Math.max(1, Math.round((units.gu(1) / 8) * 4) / 4)
    // True once the <video> has a decoded frame; hosts fade in on this so the WebView's blank first frame never flashes.
    property bool ready: false
    property bool paused: false
    signal fullscreenToggled(bool on)

    // Freeze the Chromium renderer on app background/suspend; same SIGBUS-on-resume issue and lifecycleState int trap as WebAppView.
    readonly property int _lcActive: 0
    readonly property int _lcFrozen: 1
    // Unfocused alone doesn't freeze it (side-by-side windows blanked a playing video)
    readonly property bool _windowShown: Window.visibility !== Window.Hidden
                                         && Window.visibility !== Window.Minimized
    property bool appAway: Qt.application.state === Qt.ApplicationSuspended
                           || (Qt.application.state !== Qt.ApplicationActive && !_windowShown)
    onAppAwayChanged: {
        if (!appAway) {
            vwFreezeTimer.stop();
            wv.visible = true;
            wv.lifecycleState = root._lcActive;
            vwRepaintTimer.restart();
        } else {
            wv.visible = false;
            vwFreezeTimer.restart();
        }
    }
    Timer {
        id: vwFreezeTimer
        interval: 300
        onTriggered: if (root.appAway) wv.lifecycleState = root._lcFrozen
    }
    // Thawing drops the compositor frame; re-seek forces a decode, opacity nudge covers iframes
    Timer {
        id: vwRepaintTimer
        interval: 150
        onTriggered: wv.runJavaScript(
            "(function(){var v=document.querySelector('video');" +
            "if(v){v.currentTime=v.currentTime;}" +
            "var b=document.body;if(b){b.style.opacity='0.999';" +
            "requestAnimationFrame(function(){b.style.opacity='';});}})();")
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
    onCssScaleChanged: _load()   // sizes are baked into the wrapper HTML
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

        // Autoplay without a user gesture (our overlay tap is the gesture); local-file access lets an offline file:// <video> load from its wrapper.
        settings.playbackRequiresUserGesture: false
        settings.fullScreenSupportEnabled: true
        settings.localContentCanAccessFileUrls: true
        settings.localContentCanAccessRemoteUrls: true

        // Make every frame report a mobile navigator, defeating client-side desktop sniffing.
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

        // LoadSucceededStatus == 2 (enum-not-exposed trap); directVideo waits for the __SEREY_READY__ sentinel instead of page-load, which fires before the first frame paints.
        onLoadingChanged: function (loadRequest) {
            if (loadRequest.status === 2 && !root.directVideo)
                root.ready = true;
        }

        onJavaScriptConsoleMessage: function (level, message, lineNumber, sourceID) {
            if (root.directVideo && message.indexOf("__SEREY_READY__") >= 0)
                root.ready = true;
        }
    }

    // Wrapper is served from serey.io so embeds see a normal referrer; offline copies base on the file's own directory so <video src> is same-origin.
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

    // Chromium's own timeline only seeks on touchmove and can't be patched, so render our own bar
    readonly property string _svgPlay: '<svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>'
    readonly property string _svgPause: '<svg viewBox="0 0 24 24"><path d="M6 5h4v14H6zM14 5h4v14h-4z"/></svg>'
    readonly property string _svgFull: '<svg viewBox="0 0 24 24"><path d="M7 14H5v5h5v-2H7v-3zm-2-4h2V7h3V5H5v5zm12 7h-3v2h5v-5h-2v3zM14 5v2h3v3h2V5h-5z"/></svg>'

    function _controlsHtml() {
        return '<div id="bar"><div id="row">' +
               '<div class="btn" id="pb">' + _svgPlay + '</div>' +
               '<div id="track"><div id="trk"></div><div id="fill"></div><div id="knob"></div></div>' +
               '<div id="t">0:00 / 0:00</div>' +
               '<div class="btn" id="fs">' + _svgFull + '</div>' +
               '</div></div>';
    }

    function _controlsJs() {
        return 'var bar=document.getElementById("bar"),trk=document.getElementById("track"),' +
               'fill=document.getElementById("fill"),knob=document.getElementById("knob"),' +
               'tl=document.getElementById("t"),pb=document.getElementById("pb"),' +
               'fs=document.getElementById("fs"),drag=false,hideT=null;' +
               'function f(s){s=Math.max(0,Math.floor(s||0));var m=Math.floor(s/60),x=s%60;' +
               'return m+":"+(x<10?"0":"")+x;}' +
               'function upd(){var d=v.duration||0,p=(d&&isFinite(d))?v.currentTime/d:0;' +
               'fill.style.width=(p*100)+"%";knob.style.left=(p*100)+"%";' +
               'tl.textContent=f(v.currentTime)+" / "+f(isFinite(d)?d:0);}' +
               'function icon(){pb.innerHTML=v.paused?PLAY:PAUSE;}' +
               'function poke(){bar.classList.remove("hide");clearTimeout(hideT);' +
               'hideT=setTimeout(function(){if(!v.paused&&!drag)bar.classList.add("hide");},3000);}' +
               'function seek(x){var b=trk.getBoundingClientRect();' +
               'var p=Math.min(1,Math.max(0,(x-b.left)/b.width));' +
               'if(v.duration&&isFinite(v.duration))v.currentTime=p*v.duration;upd();poke();}' +
               // Drag latch must be release-proof: QtWebEngine can drop pointerup after a tap
               'trk.addEventListener("pointerdown",function(e){drag=true;' +
               'try{trk.setPointerCapture(e.pointerId);}catch(_){}' +
               'seek(e.clientX);e.preventDefault();});' +
               'trk.addEventListener("pointermove",function(e){' +
               'if(!drag)return;' +
               'if(e.buttons===0){drag=false;poke();return;}' +
               'seek(e.clientX);});' +
               'trk.addEventListener("lostpointercapture",function(){drag=false;});' +
               'window.addEventListener("pointerup",function(){if(drag){drag=false;poke();}},true);' +
               'window.addEventListener("pointercancel",function(){drag=false;},true);' +
               'window.addEventListener("blur",function(){drag=false;});' +
               'pb.addEventListener("click",function(){if(v.paused){v.play();}else{v.pause();}});' +
               'fs.addEventListener("click",function(){if(document.fullscreenElement)' +
               '{document.exitFullscreen();}else{document.documentElement.requestFullscreen();}});' +
               'v.addEventListener("timeupdate",upd);v.addEventListener("durationchange",upd);' +
               'v.addEventListener("play",function(){icon();poke();});' +
               'v.addEventListener("pause",function(){icon();poke();});' +
               'document.addEventListener("pointermove",poke);' +
               'document.addEventListener("pointerdown",poke);' +
               'icon();upd();poke();';
    }

    function _videoHtml() {
        var attrs = 'autoplay playsinline webkit-playsinline preload="auto"';
        if (loop) attrs += ' loop';
        // Every control dimension multiplies by cssScale for consistent physical size across densities
        var s = root.cssScale;
        function px(v) { return Math.round(v * s) + 'px'; }
        return '<!DOCTYPE html><html><head>' +
               '<meta name="viewport" content="width=device-width, initial-scale=1">' +
               '<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}' +
               'video{width:100%;height:100%;object-fit:contain;background:#000}' +
               '#bar{position:fixed;left:0;right:0;bottom:0;' +
               'padding:' + px(6) + ' ' + px(10) + ' ' + px(8) + ';' +
               'background:linear-gradient(transparent,rgba(0,0,0,0.75));' +
               'font:' + px(12) + '/1 sans-serif;color:#fff;transition:opacity .2s;' +
               '-webkit-user-select:none;user-select:none}' +
               '#bar.hide{opacity:0;pointer-events:none}' +
               '#row{display:flex;align-items:center}' +
               '.btn{width:' + px(30) + ';height:' + px(30) + ';flex:none;fill:#fff;cursor:pointer}' +
               '.btn svg{width:100%;height:100%}' +
               // min-width keeps the track usable if buttons + time label crowd a narrow stage
               '#track{position:relative;flex:1;min-width:' + px(60) + ';height:' + px(30) + ';margin:0 ' + px(8) + ';' +
               'display:flex;align-items:center;touch-action:none;cursor:pointer}' +
               '#trk,#fill{position:absolute;height:' + px(4) + ';border-radius:' + px(2) + '}' +
               '#trk{left:0;right:0;background:rgba(255,255,255,0.35)}' +
               '#fill{left:0;width:0;background:#0083FA}' +
               '#knob{position:absolute;width:' + px(14) + ';height:' + px(14) + ';border-radius:' + px(7) + ';' +
               'background:#fff;left:0;margin-left:-' + px(7) + '}' +
               '#t{flex:none;padding-right:' + px(8) + ';font-variant-numeric:tabular-nums}' +
               '</style></head>' +
               '<body><video src="' + embedUrl + '" ' + attrs + '></video>' +
               (controls ? _controlsHtml() : '') +
               '<script>(function(){var v=document.querySelector("video");' +
               'var PLAY=' + JSON.stringify(_svgPlay) + ',PAUSE=' + JSON.stringify(_svgPause) + ';' +
               'function r(){console.log("__SEREY_READY__");}' +
               'v.addEventListener("loadeddata",r);v.addEventListener("playing",r);' +
               (controls ? _controlsJs() : '') +
               '})();</script>' +
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
