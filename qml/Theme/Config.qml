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
    readonly property string prodBaseV1: "https://global-api.serey.io/api/v1"
    readonly property string devBaseV1: "http://localhost:5050/api/v1"

    readonly property bool showDevOptions: false   // set true locally to expose dev tools
    property bool useLocalDev: false

    readonly property string baseUrl: useLocalDev ? devBase : prodBase
    readonly property string baseUrlV1: useLocalDev ? devBaseV1 : prodBaseV1

    // Default page size for paginated lists.
    readonly property int pageSize: 10

    // Upstream media host used to normalise some relative asset paths.
    readonly property string uploadHost: "https://upload.serey.io"

    // Image upload endpoint + key (the same public key shipped in the web
    // bundle as NEXT_PUBLIC_UPLOAD_SECRET_KEY — not a private secret). Avatars
    // POST a multipart image here and get back a hosted URL.
    readonly property string uploadUrl: "https://upload.serey.io/uploads/upload_image"
    readonly property string uploadSecret: "5876aafc87185dc0521afcqceo87185dc058718affc7b382730e89s"

    // Dedicated video storage API (tus resumable uploads + server-side
    // processing). Uploads go in 50 MB chunks — each request must stay under
    // Cloudflare's 100 MB proxy cap — then the server remuxes to a faststart
    // MP4 and returns the public URL. Key is the shared upload key from the
    // storage API's .env (same one the web frontend ships).
    readonly property string storageApiUrl: "https://storage.serey.io"
    readonly property string storageUploadKey: "aeb004760bc557962d2623c2d296df835c16a03ea1b1b41dca429f908fd2fc0b"

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

    // The active bottom-nav tab (mirrored from Main.currentTab). Read by
    // HomepagePage to suspend its WebView's Chromium renderer while another tab
    // is showing, so it doesn't compete for GPU/shared memory with the video
    // player's WebView (two live Chromium views crashed the app — see device log).
    property int currentTab: 0

    property int sourceIndex: 1  // default to Netherlands; Global is hidden from the picker
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

    // Map of community dns -> is_allow_post (bool), fetched alongside iconByDns.
    // Backend rule: is_allow_post=true → anyone may post; false → owner/managers
    // only. Used to gate the compose buttons (e.g. the Video upload FAB).
    property var allowPostByDns: ({})

    // Whether the *currently selected* community allows the signed-in user to
    // post. Global (sentinel id 0, no filter) is never postable. A picked
    // sub-community carries its own allowPost flag; otherwise fall back to the
    // top-level source's flag keyed by dns. (Owner/manager overrides aren't
    // resolved client-side — managers of an owner-only community post via web.)
    readonly property bool canPostCurrent: communityId > 0
        && (selectedSubCommunity ? !!selectedSubCommunity.allowPost
                                 : !!allowPostByDns[communityDns])

    function communityIcon(dns) {
        // Global uses a bundled multi-flag globe icon instead of the backend logo.
        if (dns === sources[0].dns)
            return Qt.resolvedUrl("../../assets/global.png");
        var u = iconByDns[dns];
        return u ? u : "";
    }
}
