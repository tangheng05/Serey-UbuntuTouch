pragma Singleton
import QtQuick 2.7

/*
 * App-wide configuration. Flip `useLocalDev` to point the whole app at a
 * locally-running serey-api instead of production. (A physical device cannot
 * reach `localhost` without `clickable` port-forwarding — see README.)
 *
 * Regional source: the app filters native feeds by a Serey community
 * (`community_id`, recursive incl. children). `sourceIndex` is the currently
 * selected source; it's read by News/Video and drives the Homepage WebView.
 */
QtObject {
    id: config

    readonly property string prodBase: "https://global-api.serey.io/api/v2"
    readonly property string devBase: "http://localhost:5050/api/v2"

    readonly property bool showDevOptions: false   // set true locally to expose dev tools
    property bool useLocalDev: false

    readonly property string baseUrl: useLocalDev ? devBase : prodBase

    // Default page size for paginated lists.
    readonly property int pageSize: 10

    // Upstream media host used to normalise some relative asset paths.
    readonly property string uploadHost: "https://upload.serey.io"

    // Image upload endpoint + key (the same public key shipped in the web
    // bundle as NEXT_PUBLIC_UPLOAD_SECRET_KEY — not a private secret). Avatars
    // POST a multipart image here and get back a hosted URL.
    readonly property string uploadUrl: "https://upload.serey.io/uploads/upload_image"
    readonly property string uploadSecret: "5876aafc87185dc0521afcqceo87185dc058718affc7b382730e89s"

    // Homepage mini-app: a single fixed site (matches serey-ubutu), filtered
    // client-side via a `community_id` query param rather than switching
    // domains per source.
    readonly property string homeLandingPageUrl: "https://khmer.serey.io"

    // --- Regional sources (verified community IDs) -----------------------
    // Three communities. "Global" (id 0) applies no community filter, so its
    // News/Video feeds combine content from every community. Keep `sourceNames`
    // in the same order as `sources`.
    readonly property var sources: [
        { "name": "Global",        "id": 0,  "dns": "serey.io",             "icon": "view-grid-symbolic" },
        { "name": "Netherlands",   "id": 99, "dns": "netherlands.serey.io", "icon": "" },
        { "name": "United States", "id": 26, "dns": "us.serey.io",          "icon": "" }
    ]
    readonly property var sourceNames: ["Global", "Netherlands", "United States"]

    property int sourceIndex: 0
    // Set when user picks a sub-community from the picker; null = use top-level source.
    property var selectedSubCommunity: null

    readonly property int communityId: selectedSubCommunity
                                       ? selectedSubCommunity.id
                                       : sources[sourceIndex].id

    // These two drive the AppHeader pill — they reflect the sub-community
    // when one is selected, otherwise fall back to the top-level source.
    readonly property string currentCommunityName: selectedSubCommunity
                                                   ? selectedSubCommunity.name
                                                   : communityName
    readonly property string currentCommunityIconUrl: selectedSubCommunity
                                                      ? (selectedSubCommunity.icon || "")
                                                      : communityIcon(communityDns)
    readonly property string communityDns: sources[sourceIndex].dns
    readonly property string communityName: sources[sourceIndex].name

    // Map of community dns -> icon URL, fetched from the backend at startup
    // (see Main.qml) so the source switcher shows each country's real icon.
    property var iconByDns: ({})

    function communityIcon(dns) {
        // Global uses a bundled multi-flag globe icon instead of the backend logo.
        if (dns === sources[0].dns)
            return Qt.resolvedUrl("../../assets/global.png");
        var u = iconByDns[dns];
        return u ? u : "";
    }
}
