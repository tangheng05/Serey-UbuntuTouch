pragma Singleton
import QtQuick 2.7

QtObject {
    id: config

    // App version shown in Settings and reported to the web bridge. Keep in
    // sync with manifest.json.in "version" on every release.
    readonly property string appVersion: "1.0.0"

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

    // Dedicated video storage API (tus resumable uploads) — see Uploads.js
    // for the scoped-token upload flow.
    readonly property string storageCreateUploadUrl: "https://serey.io/api/storage/create-upload"
    readonly property string storageDeleteUploadUrl: "https://serey.io/api/storage/delete-upload"

    // Homepage mini-app: a single fixed site (matches serey-ubutu), filtered
    // client-side via a `community_id` query param rather than switching
    // domains per source.
    readonly property string homeLandingPageUrl: "https://khmer.serey.io"

    // --- Regional sources (verified community IDs) -----------------------
    // The three fixed rows shown at the top of the community picker, in this
    // order. "Global" (id 0) applies no community filter, so its News/Video
    // feeds combine content from every community.
    readonly property var baseSources: [
        { "name": "Global",        "id": 0,  "dns": "serey.io",             "icon": "view-grid-symbolic" },
        { "name": "Netherlands",   "id": 99, "dns": "netherlands.serey.io", "icon": "" },
        { "name": "United States", "id": 26, "dns": "us.serey.io",          "icon": "" }
    ]

    // The live source list. Seeded with baseSources; Main.qml appends every
    // other top-level country from GET /general/get-communities below them at
    // startup (see appendCountries). Indexed by sourceIndex everywhere.
    property var sources: baseSources

    // Append backend countries below the fixed three, skipping any dns already
    // present. `extra` is a list of { name, id, dns, icon }.
    function appendCountries(extra) {
        var seen = {};
        for (var i = 0; i < baseSources.length; i++) seen[baseSources[i].dns] = true;
        var out = baseSources.slice();
        for (var j = 0; j < extra.length; j++) {
            var e = extra[j];
            if (e.dns && !seen[e.dns]) { seen[e.dns] = true; out.push(e); }
        }
        sources = out;
    }

    // Mirrored from Main.currentTab — HomepagePage reads it to suspend its
    // WebView while another tab is showing (two live Chromium views crashed the app).
    property int currentTab: 0

    // Mirrored from Main.wideMode
    property bool wideMode: false

    property int sourceIndex: 0  // default to Global (combined feed, no community filter)
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

    // Map of superhub community id (string) -> its child communities, built from
    // the get-communities tree at startup. The picker nests these under a hub row
    // (list-by-parent-id/<country> returns the hub but not its children).
    property var superhubChildrenById: ({})

    // Map of community dns -> is_allow_post (bool), fetched alongside iconByDns.
    // Backend rule: is_allow_post=true → anyone may post; false → owner/managers
    // only. Used to gate the compose buttons (e.g. the Video upload FAB).
    property var allowPostByDns: ({})

    // Community ids the signed-in user owns/manages, fetched from
    // /user-permission/permission-by-current-user (see Main.qml). Stored as a map
    // { id: true } for O(1) lookup; empty ({}) when logged out.
    property var ownedCommunityIdSet: ({})

    // Whether the signed-in user owns/manages the currently selected community.
    // An owner/manager may post even when the community is set to owner-only, so
    // this is OR-ed into the compose gates below.
    readonly property bool isOwnerCurrent: communityId > 0
                                           && !!ownedCommunityIdSet[communityId]

    // Can the signed-in user post to the currently selected community?
    // Global (id 0) never postable; owners/managers always can.
    readonly property bool canPostCurrent: communityId > 0
        && (isOwnerCurrent
            || (selectedSubCommunity ? !!selectedSubCommunity.allowPost
                                     : !!allowPostByDns[communityDns]))

    // Same as allowPostByDns, for video posting
    property var videoAllowPostByDns: ({})

    // Same as canPostCurrent, gates the Video upload FAB
    readonly property bool canPostVideoCurrent: communityId > 0
        && (isOwnerCurrent
            || (selectedSubCommunity ? !!selectedSubCommunity.videoAllowPost
                                     : !!videoAllowPostByDns[communityDns]))

    function communityIcon(dns) {
        // Global uses a bundled multi-flag globe icon instead of the backend logo.
        if (dns === sources[0].dns)
            return Qt.resolvedUrl("../../assets/global.png");
        var u = iconByDns[dns];
        return u ? u : "";
    }
}
