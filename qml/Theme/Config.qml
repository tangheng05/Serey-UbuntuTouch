pragma Singleton
import QtQuick 2.7
import "../services/Flags.js" as Flags

QtObject {
    id: config

    // keep in sync with manifest.json.in
    readonly property string appVersion: "1.1.4"

    // shared by Main.qml and AdaptiveStack.qml
    readonly property real convergenceBreakpoint: units.gu(80)

    // readability caps: reading column vs sheet width
    readonly property real readingMaxWidth: units.gu(80)
    readonly property real sheetMaxWidth: units.gu(50)

    readonly property string prodBase: "https://global-api.serey.io/api/v2"
    readonly property string devBase: "http://localhost:5050/api/v2"
    readonly property string prodBaseV1: "https://global-api.serey.io/api/v1"
    readonly property string devBaseV1: "http://localhost:5050/api/v1"

    readonly property bool showDevOptions: false   // set true locally to expose dev tools

    // webview tracing + console forwarding
    readonly property bool debugWebApp: false
    // scroll benchmark, needs debugWebApp on
    readonly property bool debugScrollTest: false
    property bool useLocalDev: false

    readonly property string baseUrl: useLocalDev ? devBase : prodBase
    readonly property string baseUrlV1: useLocalDev ? devBaseV1 : prodBaseV1

    // page size for paginated lists
    readonly property int pageSize: 10

    // media host for relative asset paths
    readonly property string uploadHost: "https://upload.serey.io"

    // image upload endpoint + key, public (not secret)
    readonly property string uploadUrl: "https://upload.serey.io/uploads/upload_image"
    readonly property string uploadSecret: "5876aafc87185dc0521afcqceo87185dc058718affc7b382730e89s"

    // video storage API, see Uploads.js
    readonly property string storageCreateUploadUrl: "https://serey.io/api/storage/create-upload"
    readonly property string storageDeleteUploadUrl: "https://serey.io/api/storage/delete-upload"

    // single fixed mini-app site, filtered via community_id
    readonly property string homeLandingPageUrl: "https://khmer.serey.io"

    // fixed rows atop community picker; Global (id 0) = no filter
    readonly property var baseSources: [
        { "name": "Global",        "id": 0,  "dns": "serey.io",             "icon": "view-grid-symbolic" },
        { "name": "Netherlands",   "id": 99, "dns": "netherlands.serey.io", "icon": "" },
        { "name": "United States", "id": 26, "dns": "us.serey.io",          "icon": "" }
    ]

    // live source list, indexed by sourceIndex everywhere
    property var sources: baseSources

    // rebuild source list, keep selection pinned to its dns
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

    // mirrored from Main.currentTab, gates dual-WebView crash
    property int currentTab: 0

    // mirrored from Main.wideMode
    property bool wideMode: false

    property int sourceIndex: 0  // default to Global (combined feed, no community filter)
    // set when user picks a sub-community; null = use top-level source
    property var selectedSubCommunity: null

    // id arrives as string, coerce explicitly
    readonly property int communityId: selectedSubCommunity
                                       ? Number(selectedSubCommunity.id)
                                       : sources[sourceIndex].id

    // drive the AppHeader pill
    readonly property string currentCommunityName: selectedSubCommunity
                                                   ? selectedSubCommunity.name
                                                   : communityName
    readonly property string currentCommunityIconUrl: selectedSubCommunity
                                                      ? (selectedSubCommunity.icon || "")
                                                      : communityIcon(communityDns)
    readonly property string communityDns: sources[sourceIndex].dns
    readonly property string communityName: sources[sourceIndex].name

    // user's country code, resolved once at startup (see GeoService.js)
    property string detectedCountryCode: ""

    // sources row for a country code, or -1 if none (skips Global row 0)
    function indexForCountryCode(code) {
        if (!code) return -1;
        var want = String(code).toLowerCase();
        for (var i = 1; i < sources.length; i++) {
            if (Flags.flagCodeFromTitle(sources[i].name || "") === want) return i;
        }
        return -1;
    }

    // community dns -> icon URL, fetched at startup
    property var iconByDns: ({})

    // superhub community id -> its child communities
    property var superhubChildrenById: ({})

    // every community (string id -> {id,title,dns,icon,...}), any depth
    property var communityById: ({})

    // { id: true } for country hubs, top level of the tree
    property var topLevelCommunityIds: ({})

    // { id: true } for communities the Global feed hides + descendants
    property var hiddenCommunityIds: ({})

    // child community id -> parent id
    property var parentCommunityById: ({})

    // select any community by id, any depth; false if not in cached tree
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
        // point top-level row at this community's country
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

    // community id for a mini-app landing URL, or "" if none
    function communityIdForUrl(u) {
        if (!u) return "";
        var m = String(u).match(/^https?:\/\/([^\/?#]+)([^?#]*)/);
        if (!m) return "";
        // path first, landing host can itself be a community dns
        var seg = (m[2] || "").split("/")[1] || "";
        if (/^[0-9]+$/.test(seg)) return seg;
        var host = m[1].toLowerCase();
        for (var k in communityById) {
            var d = (communityById[k].dns || "").toLowerCase();
            if (d && d === host) return k;
        }
        return "";
    }

    // lookup community info by id, or null
    function communityInfoFor(id) {
        var c = communityById[String(id)];
        return c || null;
    }

    // patch cache in place, avoids stale server-cached re-fetch
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

    // insert/merge a just-created community not yet in server cache
    function addOrUpdateCommunity(entry) {
        if (!entry || entry.id === undefined || entry.id === null) return;
        var idStr = String(entry.id);
        var map = Object.assign({}, communityById);
        map[idStr] = Object.assign({}, map[idStr] || {}, entry);
        communityById = map;
    }

    // community dns -> is_allow_post, gates compose buttons
    property var allowPostByDns: ({})

    // community ids the signed-in user owns/manages
    property var ownedCommunityIdSet: ({})

    // owns/manages the selected community
    readonly property bool isOwnerCurrent: communityId > 0
                                           && !!ownedCommunityIdSet[communityId]

    // owns/manages any community, drives "Manage your platform"
    readonly property bool hasAnyOwnedCommunity: Object.keys(ownedCommunityIdSet).length > 0

    // explicit platform pick from CMS hub, 0 = no override
    property int overrideManagedCommunityId: 0

    // community CMS pages act on
    readonly property int managedCommunityId: (overrideManagedCommunityId > 0 && !!ownedCommunityIdSet[overrideManagedCommunityId])
        ? overrideManagedCommunityId
        : (isOwnerCurrent
            ? communityId
            : (hasAnyOwnedCommunity ? Number(Object.keys(ownedCommunityIdSet)[0]) : 0))

    // can post to currently selected community
    readonly property bool canPostCurrent: communityId > 0
        && (isOwnerCurrent
            || (selectedSubCommunity ? !!selectedSubCommunity.allowPost
                                     : !!allowPostByDns[communityDns]))

    // same as allowPostByDns, for video posting
    property var videoAllowPostByDns: ({})

    // same as canPostCurrent, gates Video upload FAB
    readonly property bool canPostVideoCurrent: communityId > 0
        && (isOwnerCurrent
            || (selectedSubCommunity ? !!selectedSubCommunity.videoAllowPost
                                     : !!videoAllowPostByDns[communityDns]))

    function communityIcon(dns) {
        // Global uses bundled multi-flag globe icon
        if (dns === sources[0].dns)
            return Qt.resolvedUrl("../../assets/global.png");
        var u = iconByDns[dns];
        return u ? u : "";
    }
}
