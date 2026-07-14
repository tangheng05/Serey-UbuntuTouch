import QtQuick 2.7
import Lomiri.Components 1.3
import QtWebEngine 1.10
import "../Theme"

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

    // When true (Homepage tab hidden), freeze the Chromium renderer since two live Chromium views exhausted shared memory and SIGSEGV'd the app.
    property bool suspended: false
    // UT's QtWebEngine doesn't expose LifecycleState enum names to QML
    readonly property int _lcActive: 0
    readonly property int _lcFrozen: 1
    // Freezing is only legal once `visible` has settled hidden, so defer it; resuming to Active is always legal.
    onSuspendedChanged: {
        if (suspended) {
            freezeTimer.restart();
        } else {
            freezeTimer.stop();
            webView.lifecycleState = webAppView._lcActive;
        }
    }

    // Also freeze on app suspend — avoids a SIGBUS-on-resume
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
    readonly property string desktopUA: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    // Above this width, stop pretending to be a 412px phone
    readonly property bool desktopMode: webAppView.width >= 800
    onDesktopModeChanged: reload()

    signal getUserInfoRequested()
    // Never wire this to Session.setAuth — the web side's identity comes from its own persistent cookies and can be stale, silently switching accounts.
    signal authTokenReceived(string token, string username)
    signal openCommunityRequested(string communityId)
    signal openExternalBrowserRequested(string url)

    WebEngineProfile {
        id: mobileProfile
        storageName: "SereyMiniApp"
        httpUserAgent: webAppView.desktopMode ? webAppView.desktopUA : webAppView.mobileUA
        offTheRecord: false
    }

    WebEngineView {
        id: webView
        anchors.fill: parent
        // `visible` inherits normally; onAppActiveChanged toggles it imperatively on background/foreground so the Active->Frozen transition becomes legal.
        profile: mobileProfile
        zoomFactor: webAppView.desktopMode ? 1.0
            : (webAppView.width > 0 ? webAppView.width / 412 : 1.0)
        settings.showScrollBars: false

        userScripts: [
            WebEngineScript {
                injectionPoint: WebEngineScript.DocumentCreation
                worldId: WebEngineScript.MainWorld
                runOnSubframes: true
                sourceCode: webAppView.desktopMode ? "" : ("" +
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
                    "(document.head || document.documentElement).appendChild(meta);")
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

    // Apply the Frozen state once the view has had a moment to become hidden, guarded on `suspended` in case the tab was re-activated within the delay.
    Timer {
        id: freezeTimer
        interval: 300
        repeat: false
        onTriggered: if (webAppView.suspended) webView.lifecycleState = webAppView._lcFrozen
    }

    // App-suspend counterpart: freeze once the view has been hidden, guarded in case the app was re-activated within the delay.
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

    // Drops the web side's login since the persistent profile keeps the previous account's cookies across a native logout/switch; cookieStore may be missing on older QtWebEngine.
    function clearSession() {
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
