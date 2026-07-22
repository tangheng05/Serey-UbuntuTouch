import QtQuick 2.7
import QtQuick.Window 2.2
import Lomiri.Components 1.3
import QtWebEngine 1.10
import "../Theme"

// forceActiveFocus() routes keys to Chromium
FocusScope {
    id: webAppView

    property string url: ""
    property bool loading: true
    property string communityId: ""
    property string communityName: ""
    property string apiBaseV1: Config.baseUrlV1
    property string apiBaseV2: Config.baseUrl
    property string authToken: ""
    property string username: ""

    // freeze renderer when tab hidden
    property bool suspended: false
    // UT's QtWebEngine doesn't expose LifecycleState enum names to QML
    readonly property int _lcActive: 0
    readonly property int _lcFrozen: 1
    // defer freeze until hidden
    onSuspendedChanged: {
        if (suspended) {
            // hide explicitly; overlay can leave view visible
            webView.visible = false;
            freezeTimer.restart();
        } else {
            freezeTimer.stop();
            if (!webAppView.appAway) webView.visible = true;
            webView.lifecycleState = webAppView._lcActive;
        }
    }

    // freeze on app suspend, not just unfocused
    readonly property bool _windowShown: Window.visibility !== Window.Hidden
                                         && Window.visibility !== Window.Minimized
    property bool appAway: Qt.application.state === Qt.ApplicationSuspended
                           || (Qt.application.state !== Qt.ApplicationActive && !_windowShown)
    onAppAwayChanged: {
        if (appAway) {
            webView.visible = false;
            appFreezeTimer.restart();
        } else {
            appFreezeTimer.stop();
            webView.visible = true;
            if (!webAppView.suspended)
                webView.lifecycleState = webAppView._lcActive;
        }
    }

    readonly property string mobileUA: "Mozilla/5.0 (Linux; Android 13; Pixel 3a) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
    readonly property string desktopUA: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    // grid units, not raw pixels
    readonly property bool desktopMode: webAppView.width >= Config.convergenceBreakpoint
    onDesktopModeChanged: reload()

    signal getUserInfoRequested()
    // web identity is its own cookies, may be stale
    signal authTokenReceived(string token, string username)
    signal openCommunityRequested(string communityId)
    // mini app can switch community without bridge
    signal siteNavigated(string url)
    signal openExternalBrowserRequested(string url)
    // params: { subscription_plan_id, method: "crypto"|"stripe" }
    signal buyPlanRequested(var params)
    signal stripeCheckoutIntercepted(string url)

    WebEngineProfile {
        id: mobileProfile
        storageName: "SereyMiniApp"
        httpUserAgent: webAppView.desktopMode ? webAppView.desktopUA : webAppView.mobileUA
        offTheRecord: false
    }

    WebEngineView {
        id: webView
        anchors.fill: parent
        focus: true
        zoomFactor: webAppView.desktopMode ? 1.0 : (webAppView.width > 0 ? webAppView.width / 412 : 1.0)
        settings.showScrollBars: false

        userScripts: [
            WebEngineScript {
                injectionPoint: WebEngineScript.DocumentCreation
                worldId: WebEngineScript.MainWorld
                runOnSubframes: true
                // defer until documentElement exists
                readonly property string preamble: "" +
                    "window.__SEREY_NATIVE__ = 'ubuntu';" +
                    (Config.debugWebApp ? "window.__SEREY_DEBUG__ = true;" : "") +
                    "window.__sereyWhenDocumentReady = function(fn) {" +
                    "  var run = function() {" +
                    "    if (!document.documentElement) return false;" +
                    "    try { fn(); } catch (e) { console.log('serey-native init failed: ' + e); }" +
                    "    return true;" +
                    "  };" +
                    "  if (!run()) {" +
                    "    document.addEventListener('readystatechange', run);" +
                    "    document.addEventListener('DOMContentLoaded', run);" +
                    "  }" +
                    "};"

                // UA spoof gates site's cheap-render path
                readonly property string nativeMarker: "" +
                    "window.__sereyWhenDocumentReady(function() {" +
                    "  document.documentElement.classList.add('serey-native');" +
                    "});"

                // disable effects the device can't afford
                readonly property string perfCss: "" +
                    "window.__sereyWhenDocumentReady(function() {" +
                    "  if (document.getElementById('serey-native-perf')) return;" +
                    "  var s = document.createElement('style');" +
                    "  s.id = 'serey-native-perf';" +
                    "  s.textContent = " + JSON.stringify(
                        // disable backdrop-filter
                        "*, *::before, *::after {"
                        + " backdrop-filter: none !important;"
                        + " -webkit-backdrop-filter: none !important; }"
                        // disable fixed background repaint
                        + "* { background-attachment: scroll !important; }"
                    ) + ";" +
                    "  (document.head || document.documentElement).appendChild(s);" +
                    "});"

                // viewport spoof is mobile-only
                readonly property string mobileSpoof: "" +
                    "Object.defineProperty(navigator, 'userAgent', { get: function() { return '" + webAppView.mobileUA + "'; }, configurable: true });" +
                    "Object.defineProperty(navigator, 'platform', { get: function() { return 'Linux armv8l'; }, configurable: true });" +
                    "Object.defineProperty(navigator, 'maxTouchPoints', { get: function() { return 5; }, configurable: true });" +
                    "Object.defineProperty(window, 'innerWidth', { get: function() { return 412; }, configurable: true });" +
                    "Object.defineProperty(window, 'outerWidth', { get: function() { return 412; }, configurable: true });" +
                    "Object.defineProperty(screen, 'width', { get: function() { return 412; }, configurable: true });" +
                    "Object.defineProperty(screen, 'availWidth', { get: function() { return 412; }, configurable: true });" +
                    "window.__sereyWhenDocumentReady(function() {" +
                    "  Object.defineProperty(document.documentElement, 'clientWidth', { get: function() { return 412; }, configurable: true });" +
                    "  var meta = document.createElement('meta'); meta.name = 'viewport';" +
                    "  meta.content = 'width=412, initial-scale=1, maximum-scale=1, user-scalable=no';" +
                    "  (document.head || document.documentElement).appendChild(meta);" +
                    "});"

                sourceCode: preamble + nativeMarker + perfCss
                            + (webAppView.desktopMode ? "" : mobileSpoof)
            }
        ]

        // fires for full loads and pushState hops
        onUrlChanged: {
            var u = webView.url.toString();
            if (u === "") return;
            webAppView._loadedUrl = u;
            webAppView.siteNavigated(u);
        }

        onLoadingChanged: {
            if (loadRequest.status === WebEngineLoadRequest.LoadSucceededStatus) {
                webAppView.loading = false;
                webAppView._pageReady = true;
                webAppView._injectBridge();
                webAppView._injectProfiler();
                webAppView._log("full load succeeded after "
                                + (Date.now() - webAppView._navStartedAt) + "ms");
            } else if (loadRequest.status === WebEngineLoadRequest.LoadStartedStatus) {
                webAppView.loading = true;
                webAppView._pageReady = false;
                webAppView._log("full load started: " + loadRequest.url);
            } else if (loadRequest.status === WebEngineLoadRequest.LoadFailedStatus) {
                webAppView.loading = false;
                webAppView._pageReady = false;
                webAppView._log("full load FAILED: " + loadRequest.errorString
                                + " (" + loadRequest.url + ")");
            }
        }

        onJavaScriptConsoleMessage: {
            if (message.indexOf("UBUNTU_BRIDGE:") === 0) {
                webAppView._handleBridgeMessage(message.substring(14));
                return;
            }
            // Otherwise the page's own errors are invisible on device.
            if (Config.debugWebApp)
                console.log("WebAppView[page]: " + message
                            + " (" + sourceID + ":" + lineNumber + ")");
        }

        // intercept Stripe redirect; raw enum 255 = IgnoreRequest
        onNavigationRequested: {
            var u = request.url.toString();
            if (u.indexOf("https://checkout.stripe.com") === 0) {
                request.action = 255;
                webAppView.stripeCheckoutIntercepted(u);
            }
        }
    }

    // Defer the load slightly so the profile/web view are ready first.
    Timer {
        id: loadTimer
        interval: 100
        repeat: false
        onTriggered: { navTimer.stop(); navVerify.stop(); webView.url = webAppView.url; }
    }

    // Is there a loaded page to hand a route change to?
    property bool _pageReady: false
    // loaded page's actual location
    property string _loadedUrl: ""

    // in-place route hop avoids full reload spinner
    property double _navStartedAt: 0
    function _log(msg) {
        if (Config.debugWebApp) console.log("WebAppView: " + msg);
    }

    onUrlChanged: {
        if (url === "") return;
        _navStartedAt = Date.now();
        if (_pageReady && _samePagePath(url) !== "" && _samePagePath(_loadedUrl) !== "") {
            _log("url -> " + url + " | in-place hop queued");
            navTimer.restart();   // coalesce; see below
        } else {
            _log("url -> " + url + " | full load"
                 + (_pageReady ? " (cross-origin)" : " (no page loaded yet)"));
            loadTimer.restart();
        }
    }
    Component.onCompleted: if (url !== "") loadTimer.start()

    // debounce community picker flicks
    Timer {
        id: navTimer
        interval: 150
        repeat: false
        onTriggered: {
            var path = webAppView._samePagePath(webAppView.url);
            if (path === "") { loadTimer.restart(); return; }
            webAppView._log("in-place hop -> " + path);
            webView.runJavaScript(
                "(function(){ if (typeof window.__sereyNavigate !== 'function') return false;" +
                "  try { window.__sereyNavigate(" + JSON.stringify(path) + "); return true; }" +
                "  catch (e) { return false; } })()",
                function (handled) {
                    if (handled) {
                        webAppView._log("in-place hop accepted after "
                                        + (Date.now() - webAppView._navStartedAt) + "ms");
                        navVerify.restart();
                    } else {
                        webAppView._log("in-place hop refused (site has no __sereyNavigate) — full load");
                        loadTimer.restart();
                    }
                });
        }
    }

    // verify route actually changed, fallback if not
    Timer {
        id: navVerify
        interval: 1500
        repeat: false
        onTriggered: {
            var want = webAppView._samePagePath(webAppView.url).split("?")[0];
            if (want === "") return;
            webView.runJavaScript("window.location.pathname", function (got) {
                if (got === want) {
                    webAppView._log("in-place hop landed at " + got);
                } else {
                    webAppView._log("in-place hop did NOT land (at " + got
                                    + ", wanted " + want + ") — falling back to full load");
                    loadTimer.restart();
                }
            });
        }
    }

    // path+query if `u` is on the site we already have loaded, else "".
    function _samePagePath(u) {
        var origin = Config.homeLandingPageUrl;
        if (u.indexOf(origin) !== 0) return "";
        var rest = u.substring(origin.length);
        return rest === "" ? "/" : rest;
    }

    // apply Frozen state once hidden
    Timer {
        id: freezeTimer
        interval: 300
        repeat: false
        onTriggered: if (webAppView.suspended) webView.lifecycleState = webAppView._lcFrozen
    }

    // freeze once app-suspended view is hidden
    Timer {
        id: appFreezeTimer
        interval: 300
        repeat: false
        onTriggered: if (webAppView.appAway) webView.lifecycleState = webAppView._lcFrozen
    }

    Rectangle {
        anchors.fill: parent
        color: Style.surface
        visible: webAppView.loading
        ActivityIndicator {
            anchors.centerIn: parent
            running: webAppView.loading
            visible: webAppView.loading
        }
    }

    function reload() {
        navTimer.stop(); navVerify.stop();   // a pending hop is moot once we reload
        webView.url = "";
        loadTimer.restart();
    }

    // clear web login cookies
    function clearSession() {
        if (mobileProfile && mobileProfile.cookieStore
                && typeof mobileProfile.cookieStore.deleteAllCookies === "function") {
            mobileProfile.cookieStore.deleteAllCookies();
        }
    }

    // debug-only profiler
    function _injectProfiler() {
        if (!Config.debugWebApp) return;
        webView.runJavaScript(
            "(function(){" +
            "  if (window.__sereyProfiler) return; window.__sereyProfiler = true;" +
            "  try {" +
            "    new PerformanceObserver(function(l){" +
            "      l.getEntries().forEach(function(e){" +
            "        if (e.duration >= 50) console.log('SEREY_PROF: longtask ' + Math.round(e.duration) + 'ms');" +
            "      });" +
            "    }).observe({entryTypes:['longtask']});" +
            "  } catch (e) { console.log('SEREY_PROF: no longtask support'); }" +
            // scroll-jank meter
            "  var lastEvt = 0, worstGap = 0, evts = 0, startY = 0, tmr = null;" +
            "  window.addEventListener('scroll', function(){" +
            "    var now = performance.now();" +
            "    if (!evts) startY = window.scrollY;" +
            "    if (lastEvt) { var gap = now - lastEvt; if (gap > worstGap) worstGap = gap; }" +
            "    lastEvt = now; evts++;" +
            "    clearTimeout(tmr);" +
            "    tmr = setTimeout(function(){" +
            "      console.log('SEREY_PROF: scrolled ' + Math.round(window.scrollY - startY) + 'px'" +
            "        + ' events=' + evts + ' worstGap=' + Math.round(worstGap) + 'ms'" +
            "        + ' y=' + Math.round(window.scrollY));" +
            "      lastEvt = 0; worstGap = 0; evts = 0;" +
            "    }, 400);" +
            "  }, {passive:true});" +
            // verify document is actually scrolling
            "  window.addEventListener('touchstart', function(){" +
            "    console.log('SEREY_PROF: touchstart y=' + Math.round(window.scrollY));" +
            "  }, {passive:true});" +
            "  window.sereyKillAnimations = function(){" +
            "    var s = document.createElement('style');" +
            "    s.textContent = '*,*::before,*::after{animation:none !important;transition:none !important;}';" +
            "    document.head.appendChild(s);" +
            "    console.log('SEREY_PROF: animations disabled');" +
            "  };" +
            // Percentiles, not an average — jank lives in the tail.
            "  window.sereyScrollTest = function(label){" +
            "    return new Promise(function(res){" +
            "      window.scrollTo(0,0);" +
            "      var f = [], last = performance.now(), t0 = last;" +
            "      function step(){" +
            "        var n = performance.now(); f.push(n - last); last = n;" +
            "        window.scrollBy(0, 14);" +
            "        if (n - t0 < 4000) requestAnimationFrame(step);" +
            "        else {" +
            "          f.sort(function(a,b){return a-b;});" +
            "          var q = function(p){ return f[Math.min(f.length-1, Math.floor(f.length*p))].toFixed(1); };" +
            "          console.log('SEREY_PROF: scroll[' + label + '] frames=' + f.length" +
            "            + ' p50=' + q(0.5) + ' p90=' + q(0.9) + ' p99=' + q(0.99)" +
            "            + ' max=' + f[f.length-1].toFixed(1) + ' scrollY=' + window.scrollY" +
            "            + ' height=' + document.body.scrollHeight);" +
            "          res();" +
            "        }" +
            "      }" +
            "      requestAnimationFrame(step);" +
            "    });" +
            "  };" +
            // find which element actually scrolls
            "  window.sereyFindScrollers = function(){" +
            "    var de = document.documentElement, b = document.body;" +
            "    console.log('SEREY_PROF: doc scrollH=' + de.scrollHeight + ' clientH=' + de.clientHeight" +
            "      + ' bodyScrollH=' + b.scrollHeight + ' bodyClientH=' + b.clientHeight" +
            "      + ' htmlOverflowY=' + getComputedStyle(de).overflowY" +
            "      + ' bodyOverflowY=' + getComputedStyle(b).overflowY" +
            "      + ' bodyPos=' + getComputedStyle(b).position" +
            "      + ' scrollingElement=' + (document.scrollingElement === de ? 'html' : (document.scrollingElement === b ? 'body' : 'other')));" +
            "    var all = document.getElementsByTagName('*'), hits = 0;" +
            "    for (var i = 0; i < all.length && hits < 6; i++) {" +
            "      var el = all[i], cs = getComputedStyle(el);" +
            "      if (el === de || el === b) continue;" +
            "      if (el.scrollHeight - el.clientHeight > 40 && /auto|scroll/.test(cs.overflowY)) {" +
            "        hits++;" +
            "        console.log('SEREY_PROF: inner scroller <' + el.tagName.toLowerCase() + ' class=\"'" +
            "          + (el.className || '').toString().slice(0,70) + '\"> scrollH=' + el.scrollHeight" +
            "          + ' clientH=' + el.clientHeight + ' overflowY=' + cs.overflowY + ' height=' + cs.height);" +
            "      }" +
            "    }" +
            "    if (!hits) console.log('SEREY_PROF: no inner scrollers found');" +
            "  };" +
            // Not auto-run normally — it'd fight the user.
            (Config.debugScrollTest
                ? "  setTimeout(function(){ window.sereyScrollTest('auto'); }, 6000);"
                : "") +
            "  setTimeout(function(){" +
            "    var m = (performance && performance.memory)" +
            "      ? ' jsHeap=' + Math.round(performance.memory.usedJSHeapSize/1048576) + 'MB' : '';" +
            "    console.log('SEREY_PROF: imgs=' + document.images.length" +
            "      + ' nodes=' + document.getElementsByTagName('*').length" +
            "      + ' height=' + document.body.scrollHeight" +
            "      + ' dpr=' + window.devicePixelRatio" +
            "      + ' vw=' + window.innerWidth + 'x' + window.innerHeight" +
            "      + ' native=' + (document.documentElement.classList.contains('serey-native') ? 'yes' : 'NO')" +
            "      + m);" +
            "    window.sereyFindScrollers();" +
            "  }, 2500);" +
            "  console.log('SEREY_PROF: profiler installed');" +
            "})();");
    }

    function _injectBridge() {
        var bridgeScript = "" +
            "(function() {" +
            "  if (window.__ubuntuBridgeInjected) return;" +
            "  window.__ubuntuBridgeInjected = true;" +
            "  var callbackRegistry = {}; var requestId = 0;" +
            "  window.messageHandler = function(method, params) {" +
            "    return new Promise(function(resolve, reject) {" +
            "      var id = 'req_' + (requestId++);" +
            "      callbackRegistry[id] = { resolve: resolve, reject: reject };" +
            "      console.log('UBUNTU_BRIDGE:' + JSON.stringify({ id: id, method: method, params: params || {} }));" +
            "    });" +
            "  };" +
            "  window.receiveResponse = function(response) {" +
            "    var cb = callbackRegistry[response.id];" +
            "    if (cb) {" +
            "      if (response.error) cb.reject(new Error(response.error)); else cb.resolve(response.result);" +
            "      delete callbackRegistry[response.id];" +
            "    }" +
            "  };" +
            "  if (!window.webkit) window.webkit = {};" +
            "  if (!window.webkit.messageHandlers) window.webkit.messageHandlers = {};" +
            "  window.webkit.messageHandlers.iOSBridge = { postMessage: function(msg) { console.log('UBUNTU_BRIDGE:' + msg); } };" +
            "})();";
        webView.runJavaScript(bridgeScript);
    }

    function _handleBridgeMessage(msgStr) {
        try {
            var msg = JSON.parse(msgStr);
            var id = msg.id;
            var method = msg.method;
            var params = msg.params || {};

            switch (method) {
            case "getDeviceInfo":
                _sendResponse(id, {
                    os: "UbuntuTouch",
                    version: Config.appVersion,
                    apiData: { baseUrlV1: webAppView.apiBaseV1, baseUrlV2: webAppView.apiBaseV2 }
                });
                break;
            case "getUserInfo":
                _sendResponse(id, {
                    token: webAppView.authToken,
                    username: webAppView.username,
                    community_id: webAppView.communityId,
                    community_name: webAppView.communityName
                });
                webAppView.getUserInfoRequested();
                break;
            case "setAuthToken":
                if (params.token) {
                    webAppView.authToken = params.token;
                    webAppView.authTokenReceived(params.token, params.username || "");
                }
                _sendResponse(id, {});
                break;
            case "openCommunity":
                if (params.community_id)
                    webAppView.openCommunityRequested(String(params.community_id));
                _sendResponse(id, { status: "ok", message: "Community opened" });
                break;
            case "buyPlan":
                // only claim purchase if native session exists
                if (!webAppView.authToken) {
                    _sendError(id, "No native session");
                } else if (!params.subscription_plan_id) {
                    _sendError(id, "Missing subscription_plan_id");
                } else {
                    webAppView.buyPlanRequested(params);
                    _sendResponse(id, { status: "ok", message: "Handled natively" });
                }
                break;
            case "openExternalBrowser":
                if (params.url) {
                    Qt.openUrlExternally(params.url);
                    webAppView.openExternalBrowserRequested(params.url);
                }
                _sendResponse(id, { status: "ok", message: "URL opened" });
                break;
            default:
                _sendError(id, "Unknown method: " + method);
            }
        } catch (e) {
            console.warn("WebAppView bridge parse error: " + e);
        }
    }

    function _sendResponse(id, result) {
        webView.runJavaScript("receiveResponse(" + JSON.stringify({ id: id, result: result }) + ");");
    }
    function _sendError(id, errorMsg) {
        webView.runJavaScript("receiveResponse(" + JSON.stringify({ id: id, error: errorMsg }) + ");");
    }
}
