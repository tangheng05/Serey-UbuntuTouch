pragma Singleton
import QtQuick 2.7
import QtWebEngine 1.10

// One profile shared by every video view. Each VideoWebView used to build its own
// off-the-record profile, which died with the view: nothing survived a reel swipe or
// a second visit, so every play refetched the whole file. Cookies still never reach
// disk, only the byte cache does, and Chromium bounds it for us.
WebEngineProfile {
    // Mobile identity: YouTube serves the desktop player to anything else.
    readonly property string mobileUA: "Mozilla/5.0 (Linux; Android 13; Pixel 3a) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"

    httpUserAgent: mobileUA
    storageName: "SereyVideo"
    offTheRecord: false
    persistentCookiesPolicy: WebEngineProfile.NoPersistentCookies
    httpCacheType: WebEngineProfile.DiskHttpCache
    // Reels are short clips; this holds a browsing session's worth of them.
    httpCacheMaximumSize: 128 * 1024 * 1024
}
