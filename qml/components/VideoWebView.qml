import QtQuick 2.7
import Morph.Web 0.1

/*
 * Morph WebView wrapper used in three modes:
 *  - Direct top-level (wrap=false, directVideo=false): load `embedUrl` as a
 *    top-level page. Used by the Homepage tab to show a community site (those
 *    sites set X-Frame-Options / frame-ancestors, so they MUST be loaded
 *    top-level, not iframed).
 *  - Iframe wrap (wrap=true): embed `embedUrl` inside a minimal full-bleed HTML
 *    <iframe> document. Used for third-party players (YouTube / TikTok /
 *    Facebook), which render a black frame when pointed at directly on device.
 *  - Direct video (directVideo=true): render `embedUrl` (a direct media file —
 *    e.g. a Serey-hosted .mov/.mp4) inside an HTML5 <video> element. Chromium's
 *    codec support is a superset of the device's GStreamer, so this plays files
 *    (notably .mov) that the native QtMultimedia player can't, and keeps the
 *    user in-app instead of bouncing out to the browser. Mirrors the web's
 *    SereyPlayer (<video controls autoplay playsinline>).
 *
 * If the engine is unavailable the Loader hosting this file fails and the
 * caller's "Open in browser" fallback takes over.
 */
WebView {
    id: wv
    property string embedUrl: ""
    property bool wrap: false
    property bool directVideo: false

    onEmbedUrlChanged: _load()
    onWrapChanged: _load()
    onDirectVideoChanged: _load()
    Component.onCompleted: { _enableAutoplay(); _load(); }

    // Allow the embedded player / <video> to autoplay without a tap *inside* the
    // web view, so a single tap on our play overlay both loads AND starts the
    // video (otherwise Chromium's autoplay policy needs a second tap on the
    // player's own play button). Guarded: if this Morph build doesn't expose the
    // WebEngineSettings property we silently keep the default behaviour.
    function _enableAutoplay() {
        try { wv.settings.playbackRequiresUserGesture = false; } catch (e) {}
    }

    // The wrapper document is "served from" serey.io so the embedded player sees
    // a normal site origin/referrer. Basing it on the platform's own domain
    // (youtube.com etc.) trips YouTube's embed referrer check ("Video
    // unavailable — Watch on YouTube", error 152). The web embeds from serey.io
    // and plays fine, so we mirror that origin.
    readonly property string _origin: "https://serey.io"
    function _baseUrl() { return _origin + "/"; }

    function _iframeHtml() {
        return '<!DOCTYPE html><html><head>' +
               '<meta name="viewport" content="width=device-width, initial-scale=1">' +
               '<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}' +
               'iframe{border:0;width:100%;height:100%}</style></head>' +
               '<body><iframe src="' + embedUrl + '" ' +
               'allow="autoplay; encrypted-media; fullscreen; picture-in-picture" ' +
               'allowfullscreen></iframe></body></html>';
    }

    function _videoHtml() {
        return '<!DOCTYPE html><html><head>' +
               '<meta name="viewport" content="width=device-width, initial-scale=1">' +
               '<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}' +
               'video{width:100%;height:100%;object-fit:contain;background:#000}</style></head>' +
               '<body><video src="' + embedUrl + '" controls autoplay playsinline ' +
               'webkit-playsinline preload="auto"></video></body></html>';
    }

    function _loadDoc(html, base) {
        if (typeof wv.loadHtml === "function")
            wv.loadHtml(html, base);
        else
            wv.url = "data:text/html;charset=utf-8," + encodeURIComponent(html);
    }

    function _load() {
        if (embedUrl.length === 0)
            return;
        if (directVideo) {
            _loadDoc(_videoHtml(), _baseUrl());
        } else if (wrap) {
            _loadDoc(_iframeHtml(), _baseUrl());
        } else {
            wv.url = embedUrl;
        }
    }
}
