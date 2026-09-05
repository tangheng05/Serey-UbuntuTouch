import QtQuick 2.7
import QtQuick.Window 2.2
import Lomiri.Components 1.3
import QtWebEngine 1.10
import "../Theme"

// FocusScope so forceActiveFocus() lands on the Chromium view for scroll keys
FocusScope {
    id: webAppView

    property string url: ""
    property bool loading: true
    // The site didn't load at all (no network, DNS, server down) - the shell shows its own panel
    property bool loadFailed: false
    property string communityId: ""
    property string communityName: ""
    property string apiBaseV1: Config.baseUrlV1
    property string apiBaseV2: Config.baseUrl
    property string authToken: ""
    property string username: ""

    // When true (Homepage tab hidden), freeze the Chromium renderer since two live Chromium views exhausted shared memory and SIGSEGV'd the app.
    property bool suspended: false
    // UT's QtWebEngine doesn't expose LifecycleState enum names to QML
    readonly property int _lcActive: 0
    readonly property int _lcFrozen: 1
    // Freezing is only legal once `visible` has settled hidden, so defer it; resuming to Active is always legal.
    onSuspendedChanged: {
        webAppView._log("[lifecycle] suspended -> " + suspended);
        if (suspended) {
            // Active->Frozen is rejected while visible; an overlay can leave it visible, so hide explicitly
            webView.visible = false;
            freezeTimer.restart();
        } else {
            freezeTimer.stop();
            if (!webAppView.appAway) webView.visible = true;
            webView.lifecycleState = webAppView._lcActive;
            webAppView._log("[lifecycle] resumed -> Active");
            webAppView._applyDeferredNav();
        }
    }

    // Also freeze on app suspend; unfocused alone doesn't freeze (side-by-side blanked it)
    readonly property bool _windowShown: Window.visibility !== Window.Hidden
                                         && Window.visibility !== Window.Minimized
    property bool appAway: Qt.application.state === Qt.ApplicationSuspended
                           || (Qt.application.state !== Qt.ApplicationActive && !_windowShown)
    onAppAwayChanged: {
        webAppView._log("[lifecycle] appAway -> " + appAway);
        if (appAway) {
            webView.visible = false;
            appFreezeTimer.restart();
        } else {
            appFreezeTimer.stop();
            webView.visible = true;
            if (!webAppView.suspended)
                webView.lifecycleState = webAppView._lcActive;
            webAppView._applyDeferredNav();
        }
    }

    readonly property string mobileUA: "Mozilla/5.0 (Linux; Android 13; Pixel 3a) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
    readonly property string desktopUA: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    // Grid units, not raw pixels; a phone's native resolution can exceed a flat px threshold
    readonly property bool desktopMode: webAppView.width >= Config.convergenceBreakpoint
    onDesktopModeChanged: reload()

    signal getUserInfoRequested()
    // Never wire this to Session.setAuth; the web side's identity comes from its own persistent cookies and can be stale, silently switching accounts.
    signal authTokenReceived(string token, string username)
    signal openCommunityRequested(string communityId)
    // The mini app also switches community without the bridge; the shell must follow
    signal siteNavigated(string url)
    signal openExternalBrowserRequested(string url)
    // Mini app tapped a blog card: open it in the native reader instead of its own modal
    signal openPostRequested(var params)
    // params: { subscription_plan_id, method: "crypto"|"stripe" }
    signal buyPlanRequested(var params)
    signal stripeCheckoutIntercepted(string url)
    // An anonymous-invite link was opened; redeem it natively instead of on the web.
    signal inviteRedeemIntercepted(string url)

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
                // documentElement is null this early; defer anything needing an element
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

                // UA is an Android spoof, so the site gates its cheap-render path on this class instead
                readonly property string nativeMarker: "" +
                    "window.__sereyWhenDocumentReady(function() {" +
                    "  document.documentElement.classList.add('serey-native');" +
                    "});"

                // Decorative effects the rasteriser can't afford; kept here so later pages get them too
                readonly property string perfCss: "" +
                    "window.__sereyWhenDocumentReady(function() {" +
                    "  if (document.getElementById('serey-native-perf')) return;" +
                    "  var s = document.createElement('style');" +
                    "  s.id = 'serey-native-perf';" +
                    "  s.textContent = " + JSON.stringify(
                        // Frosted glass reads back everything behind it, every frame.
                        "*, *::before, *::after {"
                        + " backdrop-filter: none !important;"
                        + " -webkit-backdrop-filter: none !important; }"
                        // A fixed background repaints as the page scrolls under it.
                        + "* { background-attachment: scroll !important; }"
                    ) + ";" +
                    "  (document.head || document.documentElement).appendChild(s);" +
                    "});"

                // Viewport spoofing is mobile-only; in desktop mode the page uses its own real navigator/screen
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

        // Fires for real loads and for the SPA's own pushState hops alike.
        onUrlChanged: {
            var u = webView.url.toString();
            if (u === "") return;
            webAppView._loadedUrl = u;
            webAppView.siteNavigated(u);
        }

        onLoadingChanged: {
            if (loadRequest.status === WebEngineLoadRequest.LoadSucceededStatus) {
                webAppView.loading = false;
                webAppView.loadFailed = false;
                webAppView._pageReady = true;
                // Don't claim we're back purely on a load succeeding: Chromium can serve the
                // page from its disk cache while still offline, which flipped Net online and
                // hid the offline panel until the next probe. Verify against the API instead.
                if (!Net.online) Net.probe();
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
                // -3 is ERR_ABORTED: our own Stripe/invite intercepts cancel a nav, that's not a failure.
                webAppView.loadFailed = loadRequest.errorCode !== -3;
                // Chromium hits the dead network long before any of our XHRs time out. Without
                // this, Net still believed it was online, and switching to News/Video showed a
                // screenful of cached cards before the offline panel caught up.
                // Nothing on screen is usable, so retry the moment the network returns rather
                // than waiting on the shell's slow retry timer.
                if (webAppView.loadFailed) { webAppView._deferredNav = true; Net.report(false); }
                webAppView._log("full load FAILED: " + loadRequest.errorString
                                + " (" + loadRequest.url + ")");
            }
        }

        // A discarded/crashed renderer loses page state, looking like content vanishing on its own
        onRenderProcessTerminated: {
            console.log("WebAppView: [lifecycle] RENDERER TERMINATED status="
                        + terminationStatus + " exit=" + exitCode);
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

        // Stripe Checkout opens in the native sheet instead; raw value 255 = IgnoreRequest
        onNavigationRequested: {
            var u = request.url.toString();
            if (u.indexOf("https://checkout.stripe.com") === 0) {
                request.action = 255;
                webAppView.stripeCheckoutIntercepted(u);
            } else if (u.indexOf("/invite/anonymous") !== -1) {
                // Cancel the web load and hand the code to the native redeem flow.
                request.action = 255;
                webAppView.inviteRedeemIntercepted(u);
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
    // Where that page actually is; community subdomains could route to the wrong host
    property string _loadedUrl: ""

    // Re-pointing `url` reloads the whole app; once loaded, hand it the route as an SPA in-place nav
    property double _navStartedAt: 0
    function _log(msg) {
        if (Config.debugWebApp) console.log("WebAppView: " + msg);
    }

    // Covers the view through an in-place hop so the old route doesn't flash before repaint
    property bool _hopping: false

    // A route (or a failed load) the site never got. Applied as a fresh load once we can
    // actually do one, which needs both a network and an unfrozen renderer.
    property bool _deferredNav: false
    function _deferNav(why) {
        navTimer.stop(); navVerify.stop(); hopSettle.stop(); hopWatchdog.stop(); loadTimer.stop();
        webAppView._hopping = false;
        webAppView.loading = false;
        webAppView._deferredNav = true;
        webAppView._log("nav deferred (" + why + "): " + webAppView.url);
    }
    function _applyDeferredNav() {
        if (!webAppView._deferredNav || !Net.online) return;
        // A frozen renderer runs no JS and starts no navigation, so wait for the tab.
        if (webAppView.suspended || webAppView.appAway) return;
        webAppView._deferredNav = false;
        webAppView._log("applying deferred nav");
        webAppView.reload();
    }

    Connections {
        target: Net
        function onOnlineChanged() {
            if (Net.online) { webAppView._applyDeferredNav(); return; }
            // Anything in flight is dead; drop the spinner instead of waiting out Chromium's
            // own (minutes-long) timeout, and reload once we're back since the site's own
            // failed fetches never retry themselves.
            if (webAppView.loading || webAppView._hopping || !webAppView.suspended)
                webAppView._deferNav("network lost");
        }
    }

    onUrlChanged: {
        if (url === "") return;
        _navStartedAt = Date.now();
        // Offline, an in-place hop lands the SPA on a route whose fetches never answer, so it
        // spins forever with no load failure for us to notice; a full load would just fail.
        // Park the route and apply it when the network is back.
        if (!Net.online) { _deferNav("offline"); return; }
        if (_pageReady && _samePagePath(url) !== "" && _samePagePath(_loadedUrl) !== "") {
            _log("url -> " + url + " | in-place hop queued");
            _hopping = true;
            navTimer.restart();   // coalesce; see below
        } else {
            _log("url -> " + url + " | full load"
                 + (_pageReady ? " (cross-origin)" : " (no page loaded yet)"));
            loadTimer.restart();
        }
    }
    Component.onCompleted: if (url !== "") loadTimer.start()

    // Flicking through the picker changes `url` repeatedly; wait for it to settle before acting
    Timer {
        id: navTimer
        interval: 150
        repeat: false
        onTriggered: {
            var path = webAppView._samePagePath(webAppView.url);
            if (path === "") { webAppView._hopping = false; loadTimer.restart(); return; }
            webAppView._log("in-place hop -> " + path);
            hopWatchdog.restart();
            webView.runJavaScript(
                "(function(){ if (typeof window.__sereyNavigate !== 'function') return false;" +
                "  try { window.__sereyNavigate(" + JSON.stringify(path) + "); return true; }" +
                "  catch (e) { return false; } })()",
                function (handled) {
                    hopWatchdog.stop();
                    if (handled) {
                        webAppView._log("in-place hop accepted after "
                                        + (Date.now() - webAppView._navStartedAt) + "ms");
                        hopSettle.tries = 0;
                        hopSettle.restart();
                        navVerify.restart();
                    } else {
                        webAppView._log("in-place hop refused (site has no __sereyNavigate) — full load");
                        webAppView._hopping = false;
                        loadTimer.restart();
                    }
                });
        }
    }

    // runJavaScript's callback never arrives if the renderer was frozen or the page is gone,
    // and the cover is only lifted from inside it, so time the hop out here too.
    Timer {
        id: hopWatchdog
        interval: 4000
        repeat: false
        onTriggered: {
            if (!webAppView._hopping) return;
            // A frozen renderer hasn't refused the hop, it just hasn't run it yet; the callback
            // arrives on resume. Keep waiting rather than forcing a reload behind a hidden tab.
            if (webAppView.suspended || webAppView.appAway) { hopWatchdog.restart(); return; }
            webAppView._log("in-place hop never answered");
            webAppView._hopping = false;
            if (Net.online) loadTimer.restart(); else webAppView._deferNav("hop timed out offline");
        }
    }

    // Uncover once the router reports the new path; try cap stops a rejected hop hanging forever
    Timer {
        id: hopSettle
        property int tries: 0
        interval: 120
        repeat: true
        onTriggered: {
            var want = webAppView._samePagePath(webAppView.url).split("?")[0];
            if (want === "" || ++tries > 12) { stop(); webAppView._hopping = false; return; }
            webView.runJavaScript("window.location.pathname", function (got) {
                if (got !== want) return;
                hopSettle.stop();
                webAppView._hopping = false;
            });
        }
    }

    // The router can silently reject the push; confirm the page moved or fall back to a real load
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

    // Apply the Frozen state once the view has had a moment to become hidden, guarded on `suspended` in case the tab was re-activated within the delay.
    Timer {
        id: freezeTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (!webAppView.suspended) return;
            webView.lifecycleState = webAppView._lcFrozen;
            webAppView._log("[lifecycle] tab-hidden freeze -> " + webView.lifecycleState);
        }
    }

    // App-suspend counterpart: freeze once the view has been hidden, guarded in case the app was re-activated within the delay.
    Timer {
        id: appFreezeTimer
        interval: 300
        repeat: false
        onTriggered: if (webAppView.appAway) webView.lifecycleState = webAppView._lcFrozen
    }

    Rectangle {
        id: cover
        anchors.fill: parent
        color: Style.surface
        visible: webAppView.loading || webAppView._hopping
        ActivityIndicator {
            anchors.centerIn: parent
            running: cover.visible
            visible: cover.visible
        }
    }

    function reload() {
        navTimer.stop(); navVerify.stop(); hopSettle.stop(); hopWatchdog.stop();
        _hopping = false; _deferredNav = false;
        webView.url = "";
        loadTimer.restart();
    }

    // Drops the web side's login since the persistent profile keeps the previous account's cookies across a native logout/switch; cookieStore may be missing on older QtWebEngine.
    function clearSession() {
        if (mobileProfile && mobileProfile.cookieStore
                && typeof mobileProfile.cookieStore.deleteAllCookies === "function") {
            mobileProfile.cookieStore.deleteAllCookies();
        }
    }

    // Debug-only profiler; works on the deployed site too, so it can measure production
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
            // Passive scroll-jank meter: gap between scroll events IS the felt stall
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
            // If this never fires while swiping, the document isn't the thing scrolling
            "  window.addEventListener('touchstart', function(){" +
            "    console.log('SEREY_PROF: touchstart y=' + Math.round(window.scrollY));" +
            "  }, {passive:true});" +
            "  window.sereyKillAnimations = function(){" +
            "    var s = document.createElement('style');" +
            "    s.textContent = '*,*::before,*::after{animation:none !important;transition:none !important;}';" +
            "    document.head.appendChild(s);" +
            "    console.log('SEREY_PROF: animations disabled');" +
            "  };" +
            // Percentiles, not an average; jank lives in the tail.
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
            // Which element actually scrolls? Non-document scrollers behave differently on touch
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
            // Not auto-run normally; it'd fight the user.
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
                // Only claim the purchase with a native session; rejecting falls back to the web flow
                if (!webAppView.authToken) {
                    _sendError(id, "No native session");
                } else if (!params.subscription_plan_id) {
                    _sendError(id, "Missing subscription_plan_id");
                } else {
                    webAppView.buyPlanRequested(params);
                    _sendResponse(id, { status: "ok", message: "Handled natively" });
                }
                break;
            case "openPost":
                if (params.author && params.permlink) {
                    webAppView.openPostRequested(params);
                    _sendResponse(id, { status: "ok", message: "Post opened" });
                } else {
                    _sendError(id, "Missing author or permlink");
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
