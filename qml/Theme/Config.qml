pragma Singleton
import QtQuick 2.7

QtObject {
    id: config

    // App version shown in Settings and reported to the web bridge — keep in sync with manifest.json.in "version" on every release.
    readonly property string appVersion: "1.1.2"

    // Single source of truth for the convergence breakpoint, shared by Main.qml and AdaptiveStack.qml so the two never drift out of sync.
    readonly property real convergenceBreakpoint: units.gu(80)

    // Convergence readability caps (HIG: adapt, not scale — don't let a column
    // stretch edge-to-edge on a desktop window). Long-form reading/detail columns
    // cap at readingMaxWidth centered; bottom sheets/pickers at sheetMaxWidth.
    readonly property real readingMaxWidth: units.gu(80)
    readonly property real sheetMaxWidth: units.gu(50)

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

    // Image upload endpoint + key (same public key shipped in the web bundle, not a private secret) — avatars POST here and get a hosted URL back.
    readonly property string uploadUrl: "https://upload.serey.io/uploads/upload_image"
    readonly property string uploadSecret: "5876aafc87185dc0521afcqceo87185dc058718affc7b382730e89s"

    // Dedicated video storage API (tus resumable uploads) — see Uploads.js for the scoped-token upload flow.
    readonly property string storageCreateUploadUrl: "https://serey.io/api/storage/create-upload"
    readonly property string storageDeleteUploadUrl: "https://serey.io/api/storage/delete-upload"

    // Homepage mini-app: a single fixed site, filtered client-side via a `community_id` query param rather than switching domains.
    readonly property string homeLandingPageUrl: "https://khmer.serey.io"

    // Regional sources: the three fixed rows at the top of the community picker; Global (id 0) applies no filter, combining every community's feed.
    readonly property var baseSources: [
        { "name": "Global",        "id": 0,  "dns": "serey.io",             "icon": "view-grid-symbolic" },
        { "name": "Netherlands",   "id": 99, "dns": "netherlands.serey.io", "icon": "" },
        { "name": "United States", "id": 26, "dns": "us.serey.io",          "icon": "" }
    ]

    // The live source list, seeded with baseSources; Main.qml appends every other top-level country from the backend at startup. Indexed by sourceIndex everywhere.
    property var sources: baseSources

    // Append backend countries below the fixed three, skipping any dns already present.
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

    // Mirrored from Main.currentTab — HomepagePage reads it to suspend its WebView while another tab shows (two live Chromium views crashed the app).
    property int currentTab: 0

    // Mirrored from Main.wideMode
    property bool wideMode: false

    property int sourceIndex: 0  // default to Global (combined feed, no community filter)
    // Set when user picks a sub-community from the picker; null = use top-level source.
    property var selectedSubCommunity: null

    // selectedSubCommunity.id arrives as a string — coerce explicitly.
    readonly property int communityId: selectedSubCommunity
                                       ? Number(selectedSubCommunity.id)
                                       : sources[sourceIndex].id

    // These two drive the AppHeader pill, reflecting the sub-community when selected, else the top-level source.
    readonly property string currentCommunityName: selectedSubCommunity
                                                   ? selectedSubCommunity.name
                                                   : communityName
    readonly property string currentCommunityIconUrl: selectedSubCommunity
                                                      ? (selectedSubCommunity.icon || "")
                                                      : communityIcon(communityDns)
    readonly property string communityDns: sources[sourceIndex].dns
    readonly property string communityName: sources[sourceIndex].name

    // Map of community dns -> icon URL, fetched from the backend at startup so the source switcher shows each country's real icon.
    property var iconByDns: ({})

    // Map of superhub community id -> its child communities, built from the get-communities tree so the picker can nest them under a hub row.
    property var superhubChildrenById: ({})

    // Map of every community (string id -> {id,title,dns,icon,...}) at any nesting depth, unlike superhubChildrenById
    property var communityById: ({})

    // Looks up a community's {title, icon, dns, ...} by id from the cached tree, or null if unknown
    function communityInfoFor(id) {
        var c = communityById[String(id)];
        return c || null;
    }

    // Patches edited fields into the cache in place (reassigning so bindings
    // notice) instead of re-fetching get-communities, which is cached
    // server-side and returns stale data for a bit right after a write.
    function updateCommunityFields(id, fields) {
        var idStr = String(id);
        var entry = communityById[idStr];
        if (entry) {
            var map = Object.assign({}, communityById);
            map[idStr] = Object.assign({}, entry, fields);
            communityById = map;
        }
        if (selectedSubCommunity && selectedSubCommunity.id === id && fields.title !== undefined)
            selectedSubCommunity = Object.assign({}, selectedSubCommunity, { name: fields.title });
    }
    function updateCommunityTitle(id, title) {
        updateCommunityFields(id, { title: title });
    }

    // Insert (or merge) a community into the cache. Used right after creating a
    // platform so the CMS hub resolves its name/logo/categories in the same
    // session — get-communities is server-cached and omits a just-created
    // community, so a re-fetch wouldn't help.
    function addOrUpdateCommunity(entry) {
        if (!entry || entry.id === undefined || entry.id === null) return;
        var idStr = String(entry.id);
        var map = Object.assign({}, communityById);
        map[idStr] = Object.assign({}, map[idStr] || {}, entry);
        communityById = map;
    }

    // Map of community dns -> is_allow_post, gating the compose buttons per backend rule (true = anyone may post, false = owner/managers only).
    property var allowPostByDns: ({})

    // Community ids the signed-in user owns/manages, fetched from /user-permission/permission-by-current-user; empty when logged out.
    property var ownedCommunityIdSet: ({})

    // Whether the signed-in user owns/manages the selected community — OR-ed into the compose gates since an owner may post even when owner-only.
    readonly property bool isOwnerCurrent: communityId > 0
                                           && !!ownedCommunityIdSet[communityId]

    // Owns/manages any community at all — drives the "Manage your platform" entry point in Settings
    readonly property bool hasAnyOwnedCommunity: Object.keys(ownedCommunityIdSet).length > 0

    // Explicit "Switch Platform" pick from the CMS hub for owners of more than one community; 0 = no override
    property int overrideManagedCommunityId: 0

    // The community CMS pages act on: override if still owned, else the selected community if owned, else the first owned one
    readonly property int managedCommunityId: (overrideManagedCommunityId > 0 && !!ownedCommunityIdSet[overrideManagedCommunityId])
        ? overrideManagedCommunityId
        : (isOwnerCurrent
            ? communityId
            : (hasAnyOwnedCommunity ? Number(Object.keys(ownedCommunityIdSet)[0]) : 0))

    // Can the signed-in user post to the currently selected community? Global (id 0) never postable; owners/managers always can.
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
