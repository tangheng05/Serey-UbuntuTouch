pragma Singleton
import QtQuick 2.7
import "../services/Flags.js" as Flags

QtObject {
    id: config

    // App version shown in Settings and reported to the web bridge; keep in sync with manifest.json.in "version" on every release.
    readonly property string appVersion: "1.1.7"

    // Single source of truth for the convergence breakpoint, shared by Main.qml and AdaptiveStack.qml so the two never drift out of sync.
    readonly property real convergenceBreakpoint: units.gu(80)
    // Second tier: desktop is where a THIRD column fits (nav 20 + list 46 + article 50 + panel 34)
    readonly property real desktopBreakpoint: units.gu(150)

    // Convergence readability caps: reading/detail columns cap at readingMaxWidth, sheets at sheetMaxWidth
    readonly property real readingMaxWidth: units.gu(80)
    readonly property real sheetMaxWidth: units.gu(50)

    readonly property string prodBase: "https://global-api.serey.io/api/v2"
    readonly property string devBase: "http://localhost:5050/api/v2"
    readonly property string prodBaseV1: "https://global-api.serey.io/api/v1"
    readonly property string devBaseV1: "http://localhost:5050/api/v1"

    readonly property bool showDevOptions: false   // set true locally to expose dev tools

    // Homepage web-view tracing + console forwarding; chatty, off for release
    readonly property bool debugWebApp: false
    // Scroll benchmark once per load; scrolls the page, needs debugWebApp on too
    readonly property bool debugScrollTest: false
    property bool useLocalDev: false

    readonly property string baseUrl: useLocalDev ? devBase : prodBase
    readonly property string baseUrlV1: useLocalDev ? devBaseV1 : prodBaseV1

    // Default page size for paginated lists.
    readonly property int pageSize: 10

    // Upstream media host used to normalise some relative asset paths.
    readonly property string uploadHost: "https://upload.serey.io"

    // Image upload endpoint + key (same public key shipped in the web bundle, not a private secret); avatars POST here and get a hosted URL back.
    readonly property string uploadUrl: "https://upload.serey.io/uploads/upload_image"
    readonly property string uploadSecret: "5876aafc87185dc0521afcqceo87185dc058718affc7b382730e89s"

    // Dedicated video storage API (tus resumable uploads); see Uploads.js for the scoped-token upload flow.
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

    // Rebuild sources; re-pin selection by dns, fall back to Global if it disappeared
    function appendCountries(extra) {
        var currentDns = sources[sourceIndex] ? sources[sourceIndex].dns : "";
        var seen = {};
        for (var i = 0; i < baseSources.length; i++) seen[baseSources[i].dns] = true;
        var out = baseSources.slice();
        for (var j = 0; j < extra.length; j++) {
            var e = extra[j];
            if (e.dns && !seen[e.dns]) { seen[e.dns] = true; out.push(e); }
        }
        var newIndex = 0;
        for (var k = 0; k < out.length; k++)
            if (out[k].dns === currentDns) { newIndex = k; break; }
        sources = out;
        if (sourceIndex !== newIndex) sourceIndex = newIndex;
    }

    // Mirrored from Main.currentTab; HomepagePage reads it to suspend its WebView while another tab shows (two live Chromium views crashed the app).
    property int currentTab: 0

    // Mirrored from Main.wideMode
    property bool wideMode: false
    // Mirrored from Main.desktopMode
    property bool desktopMode: false
    // Split view, but not a full desktop window.
    readonly property bool tabletMode: wideMode && !desktopMode

    property int sourceIndex: 0  // default to Global (combined feed, no community filter)
    // Set when user picks a sub-community from the picker; null = use top-level source.
    property var selectedSubCommunity: null

    // selectedSubCommunity.id arrives as a string; coerce explicitly.
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

    // ISO-3166 alpha-2 from Cloudflare's edge; "" = not detected, treat as no hint
    property string detectedCountryCode: ""

    // sources row for an ISO-3166 alpha-2 code, or -1; skips row 0 (Global)
    function indexForCountryCode(code) {
        if (!code) return -1;
        var want = String(code).toLowerCase();
        for (var i = 1; i < sources.length; i++) {
            if (Flags.flagCodeFromTitle(sources[i].name || "") === want) return i;
        }
        return -1;
    }

    // Map of community dns -> icon URL, fetched from the backend at startup so the source switcher shows each country's real icon.
    property var iconByDns: ({})

    // Map of superhub community id -> its child communities, built from the get-communities tree so the picker can nest them under a hub row.
    property var superhubChildrenById: ({})

    // Map of every community (string id -> {id,title,dns,icon,...}) at any nesting depth, unlike superhubChildrenById
    property var communityById: ({})

    // { id: true } for country hubs (tree top level), not postable; childCount alone can't tell
    property var topLevelCommunityIds: ({})

    // { id: true } for the community the Global feed hides plus descendants
    property var hiddenCommunityIds: ({})

    // child community id (string) -> parent id, from the same get-communities tree.
    property var parentCommunityById: ({})

    // Select any community by id at any depth; false when not in cached tree
    function selectCommunityById(id) {
        var idStr = String(id);
        if (idStr === "" || idStr === "undefined" || idStr === "null") return false;
        for (var i = 0; i < sources.length; i++) {
            if (String(sources[i].id) === idStr) {
                sourceIndex = i;
                selectedSubCommunity = null;
                return true;
            }
        }
        var c = communityById[idStr];
        if (!c) return false;
        // Point top-level row at this community's country so the picker opens correctly
        var ancestor = idStr, guard = 0;
        while (parentCommunityById[ancestor] !== undefined && guard++ < 12)
            ancestor = parentCommunityById[ancestor];
        for (var j = 0; j < sources.length; j++)
            if (String(sources[j].id) === ancestor) { sourceIndex = j; break; }
        selectedSubCommunity = {
            id: idStr,
            name: c.title || "",
            icon: c.icon || "",
            allowPost: !!c.allowPost,
            videoAllowPost: !!c.videoAllowPost
        };
        return true;
    }

    // Community id for a URL the mini app landed on, or "" if it names none
    function communityIdForUrl(u) {
        if (!u) return "";
        var m = String(u).match(/^https?:\/\/([^\/?#]+)([^?#]*)/);
        if (!m) return "";
        // Path first: landing host can itself be a community dns
        var seg = (m[2] || "").split("/")[1] || "";
        if (/^[0-9]+$/.test(seg)) return seg;
        var host = m[1].toLowerCase();
        for (var k in communityById) {
            var d = (communityById[k].dns || "").toLowerCase();
            if (d && d === host) return k;
        }
        return "";
    }

    // Looks up a community's {title, icon, dns, ...} by id from the cached tree, or null if unknown
    function communityInfoFor(id) {
        var c = communityById[String(id)];
        return c || null;
    }

    // Patches fields into cache in place instead of re-fetching (server cache is stale after write)
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

    // Insert/merge a community into cache; used right after creating a platform
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

    // Whether the signed-in user owns/manages the selected community; OR-ed into the compose gates since an owner may post even when owner-only.
    readonly property bool isOwnerCurrent: communityId > 0
                                           && !!ownedCommunityIdSet[communityId]

    // Owns/manages any community at all; drives the "Manage your platform" entry point in Settings
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
