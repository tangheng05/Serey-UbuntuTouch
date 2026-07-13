import QtQuick 2.7
import Lomiri.Components 1.3
import QtWebEngine 1.10
import "../Theme"

/*
 * Embedded "mini app" web view (ported from serey-ubutu). Loads a Serey web
 * surface (e.g. a community site) in QtWebEngine with a forced mobile viewport,
 * and exposes a small JS bridge so the page can talk to the native shell:
 *
 *   window.messageHandler(method, params) -> Promise
 *     getDeviceInfo  -> { os, version, apiData:{ baseUrlV1, baseUrlV2 } }
 *     getUserInfo    -> { token, username, community_id, community_name }
 *     setAuthToken   -> stores a token pushed from the web side
 *     openCommunity  -> asks the shell to switch community
 *     openExternalBrowser -> opens a URL in the system browser
 *     buyPlan        -> hands a plan purchase to the native payment flow
 *                       ({ subscription_plan_id, method: "crypto"|"stripe" });
 *                       rejected when there's no native session, so the site
 *                       falls back to its own web payment flow
 *
 * Navigation to checkout.stripe.com is intercepted (onNavigationRequested)
 * and re-routed to the native StripeCheckoutSheet — works against the
 * production site even before it adopts the buyPlan bridge, and stops the
 * mini app navigating away from the plan page.
 *
 * The page posts requests via `console.log("UBUNTU_BRIDGE:" + json)`, which we
 * intercept in onJavaScriptConsoleMessage and answer with receiveResponse().
 *
 * Cleanups vs the reference: the bridge handlers read real component properties
 * (apiBaseV1/V2, authToken, username, communityName) instead of an undefined
 * `root.*`, and a single persistent WebEngineProfile is reused for caching.
 */
Item {
    id: webAppView

    property string url: ""
    property bool loading: true
    property string communityId: ""
    property string communityName: ""
    property string apiBaseV1: Config.baseUrlV1
    property string apiBaseV2: Config.baseUrl
    property string authToken: ""
    property string username: ""

    // When true (the Homepage tab is hidden) the WebEngineView's Chromium
    // renderer is moved to the Frozen lifecycle state: it stops background
    // timers/rendering and lets Chromium reclaim memory, so it no longer
    // competes for GPU/shared memory with the video player's separate WebView.
    // Two live Chromium views on the Pixel 3a exhausted shared memory and
    // SIGSEGV'd the app (see device log). Frozen keeps the DOM, so returning to
    // the tab resumes instantly without reloading the site or losing the session.
    property bool suspended: false
    // WebEngineView.LifecycleState values. UT's QtWebEngine doesn't expose the
    // enum names to QML (WebEngineView.Frozen reads as undefined), but the
    // lifecycleState property accepts the underlying ints: Active=0, Frozen=1.
    readonly property int _lcActive: 0
    readonly property int _lcFrozen: 1
    // Freezing is only legal once the view is actually hidden, and `visible`
    // settles a tick after the tab switch — so defer the freeze, but resume
    // immediately (Active is always legal).
    onSuspendedChanged: {
        if (suspended) {
            // Active->Frozen is rejected while the page is visible. On a tab
            // switch the parent stack hides us anyway, but when `suspended`
            // comes from an overlay (the Stripe checkout sheet covering this
            // tab) the view is still visible — hide it explicitly or the
            // freeze silently fails and both Chromiums stay live.
            webView.visible = false;
            freezeTimer.restart();
        } else {
            freezeTimer.stop();
            if (webAppView.appActive) webView.visible = true;
            webView.lifecycleState = webAppView._lcActive;
        }
    }

    // Also freeze on whole-app background/suspend, not just tab-hide: a live
    // WebEngineView left Active across a long OS suspend loses its GPU/shared-mem
    // context and SIGBUSes on resume (device log: status=7/BUS moments after a
    // 54-min suspend). QtWebEngine rejects Active->Frozen while the page is
    // visible, so hide the view first. This is done IMPERATIVELY and only on an
    // actual state change — never at startup — so a quirky initial state can't
    // leave the Homepage blank.
    property bool appActive: Qt.application.state === Qt.ApplicationActive
    onAppActiveChanged: {
        if (!appActive) {
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

    signal getUserInfoRequested()
    // NOTE: never wire this to Session.setAuth — the web side's identity comes
    // from its own persistent cookies and can be stale (a previous account);
    // letting it write the native session would silently switch accounts.
    signal authTokenReceived(string token, string username)
    signal openCommunityRequested(string communityId)
    signal openExternalBrowserRequested(string url)
    // params: { subscription_plan_id, method: "crypto"|"stripe" }
    signal buyPlanRequested(var params)
    signal stripeCheckoutIntercepted(string url)

    WebEngineProfile {
        id: mobileProfile
        storageName: "SereyMiniApp"
        httpUserAgent: webAppView.mobileUA
        offTheRecord: false
    }

    WebEngineView {
        id: webView
        anchors.fill: parent
        // `visible` is left to inherit normally; onAppActiveChanged toggles it
        // imperatively on app background/foreground so the Active->Frozen
        // transition (rejected while visible) becomes legal.
        profile: mobileProfile
        zoomFactor: webAppView.width > 0 ? webAppView.width / 412 : 1.0
        settings.showScrollBars: false

        userScripts: [
            WebEngineScript {
                injectionPoint: WebEngineScript.DocumentCreation
                worldId: WebEngineScript.MainWorld
                runOnSubframes: true
                sourceCode: "" +
                    "Object.defineProperty(navigator, 'userAgent', { get: function() { return '" + webAppView.mobileUA + "'; }, configurable: true });" +
                    "Object.defineProperty(navigator, 'platform', { get: function() { return 'Linux armv8l'; }, configurable: true });" +
                    "Object.defineProperty(navigator, 'maxTouchPoints', { get: function() { return 5; }, configurable: true });" +
                    "Object.defineProperty(window, 'innerWidth', { get: function() { return 412; }, configurable: true });" +
                    "Object.defineProperty(window, 'outerWidth', { get: function() { return 412; }, configurable: true });" +
                    "Object.defineProperty(document.documentElement, 'clientWidth', { get: function() { return 412; }, configurable: true });" +
                    "Object.defineProperty(screen, 'width', { get: function() { return 412; }, configurable: true });" +
                    "Object.defineProperty(screen, 'availWidth', { get: function() { return 412; }, configurable: true });" +
                    "var meta = document.createElement('meta'); meta.name = 'viewport';" +
                    "meta.content = 'width=412, initial-scale=1, maximum-scale=1, user-scalable=no';" +
                    "(document.head || document.documentElement).appendChild(meta);"
            }
        ]

        onLoadingChanged: {
            if (loadRequest.status === WebEngineLoadRequest.LoadSucceededStatus) {
                webAppView.loading = false;
                webAppView._injectBridge();
            } else if (loadRequest.status === WebEngineLoadRequest.LoadStartedStatus) {
                webAppView.loading = true;
            } else if (loadRequest.status === WebEngineLoadRequest.LoadFailedStatus) {
                webAppView.loading = false;
            }
        }

        onJavaScriptConsoleMessage: {
            if (message.indexOf("UBUNTU_BRIDGE:") === 0)
                webAppView._handleBridgeMessage(message.substring(14));
        }

        // Keep the mini app on the plan page when the site redirects to Stripe
        // Checkout — the shell shows it in the native StripeCheckoutSheet
        // instead. Enum names can be undefined on UT's QtWebEngine (see the
        // lifecycleState ints above), so use the raw value: IgnoreRequest=255.
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
        onTriggered: webView.url = webAppView.url
    }

    onUrlChanged: if (url !== "") loadTimer.restart()
    Component.onCompleted: if (url !== "") loadTimer.start()

    // Apply the Frozen state once the view has had a moment to become hidden.
    // Guarded on `suspended` in case the tab was re-activated within the delay.
    Timer {
        id: freezeTimer
        interval: 300
        repeat: false
        onTriggered: if (webAppView.suspended) webView.lifecycleState = webAppView._lcFrozen
    }

    // App-suspend counterpart: freeze once the view has been hidden (see
    // onAppActiveChanged), guarded in case the app was re-activated within the delay.
    Timer {
        id: appFreezeTimer
        interval: 300
        repeat: false
        onTriggered: if (!webAppView.appActive) webView.lifecycleState = webAppView._lcFrozen
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
        webView.url = "";
        loadTimer.restart();
    }

    // Drop the web side's login. The profile is persistent (offTheRecord:false),
    // so without this the site keeps the PREVIOUS account's cookie session across
    // a native logout/switch and the Homepage shows the old account. Guarded:
    // cookieStore may be missing on older QtWebEngine — the caller's reload()
    // still refreshes the page either way.
    function clearSession() {
        // cookieStore is missing on older QtWebEngine — guard rather than let the
        // call throw (which logged "deleteAllCookies of undefined" on every
        // logout). The caller's reload() still refreshes the page either way.
        if (mobileProfile && mobileProfile.cookieStore
                && typeof mobileProfile.cookieStore.deleteAllCookies === "function") {
            mobileProfile.cookieStore.deleteAllCookies();
        }
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
                // Only claim the purchase when a native session exists — the
                // payment endpoints need the native JWT. Rejecting makes the
                // site's Promise fail so it falls back to its web flow.
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
