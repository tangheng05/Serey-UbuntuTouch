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

    // The active bottom-nav tab (mirrored from Main.currentTab). Read by
    // HomepagePage to suspend its WebView's Chromium renderer while another tab
    // is showing, so it doesn't compete for GPU/shared memory with the video
    // player's WebView (two live Chromium views crashed the app — see device log).
    property int currentTab: 0

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

    // Map of EVERY community (string id -> {id,title,dns,icon,...}) seen in the
    // get-communities tree at startup, at any nesting depth — unlike
    // superhubChildrenById (only superhub children), this covers every
    // community. Used to resolve an owned sub-community's real name/logo
    // (see communityInfoFor) since there's no dedicated "get community by id"
    // endpoint.
    property var communityById: ({})

    // Look up a community's {title, icon, dns, ...} by id from the cached
    // get-communities tree, or null if it isn't loaded/known yet.
    function communityInfoFor(id) {
        var c = communityById[String(id)];
        return c || null;
    }

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

    // Whether the user owns/manages ANY community at all (not necessarily the
    // one currently selected in the picker). Drives the "Manage your platform"
    // entry point in Settings — owners shouldn't have to first navigate to
    // their own community just to find the CMS.
    readonly property bool hasAnyOwnedCommunity: Object.keys(ownedCommunityIdSet).length > 0

    // Explicit pick from the CMS hub's "Switch Platform" control, for owners of
    // more than one community. 0 = no override, fall back to the default rule
    // below. Reset on logout (see ownedCommunityIdSet's clearer in Main.qml)
    // isn't needed since a stale id simply fails the ownedCommunityIdSet check
    // below and the default rule takes back over.
    property int overrideManagedCommunityId: 0

    // The community the CMS pages should act on: an explicit "Switch Platform"
    // pick if one is set and still owned, else the currently selected community
    // if the user owns it, else the first community they own/manage. This way
    // "Manage your platform" always targets a community the user can actually
    // administer, regardless of what's selected in the main picker.
    readonly property int managedCommunityId: (overrideManagedCommunityId > 0 && !!ownedCommunityIdSet[overrideManagedCommunityId])
        ? overrideManagedCommunityId
        : (isOwnerCurrent
            ? communityId
            : (hasAnyOwnedCommunity ? Number(Object.keys(ownedCommunityIdSet)[0]) : 0))

    // Whether the *currently selected* community allows the signed-in user to
    // post. Global (sentinel id 0, no filter) is never postable. A picked
    // sub-community carries its own allowPost flag; otherwise fall back to the
    // top-level source's flag keyed by dns. Owners/managers may always post
    // (isOwnerCurrent), even when the community is set to owner-only.
    readonly property bool canPostCurrent: communityId > 0
        && (isOwnerCurrent
            || (selectedSubCommunity ? !!selectedSubCommunity.allowPost
                                     : !!allowPostByDns[communityDns]))

    // Map of community dns -> video_is_allow_post (bool), fetched alongside
    // allowPostByDns. Backend rule: video_is_allow_post=true → anyone may post a
    // video; false → owner/managers only. Gates the Video upload FAB.
    property var videoAllowPostByDns: ({})

    // Whether the *currently selected* community lets the signed-in user post a
    // VIDEO. Same resolution as canPostCurrent but keyed off the video flag, so an
    // owner-only-video community hides the upload FAB even when its blog is open.
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
