.pragma library
.import "Http.js" as Http

function subscribe(baseUrl, token, communityId, onOk, onErr) {
    Http.post(baseUrl, "/community-subscriber/subscribe",
              { community_id: parseInt(communityId) }, token, onOk, onErr);
}

function unsubscribe(baseUrl, token, communityId, onOk, onErr) {
    Http.post(baseUrl, "/community-subscriber/unsubscribe",
              { community_id: parseInt(communityId) }, token, onOk, onErr);
}

function fetchSubscribed(baseUrl, token, onOk, onErr) {
    Http.get(baseUrl, "/community-subscriber/list-by-current-user",
             {}, token, function (data) {
        var list = (data && data.community_subscribers)
                || (data && data.data && data.data.community_subscribers)
                || []
        if (!Array.isArray(list)) list = []
        var map = {};
        for (var i = 0; i < list.length; i++) {
            var id = String(list[i].community_id || list[i].id || "");
            if (id) map[id] = true;
        }
        onOk(map);
    }, onErr);
}

function subscriberCount(baseUrl, communityId, onOk, onErr) {
    Http.get(baseUrl, "/community-subscriber/subscriber-count",
             { community_id: communityId }, null, function (data) {
        var d = data && data.data
        // The server field is `total_subscribers` — `count`/`subscriber_count`
        // never existed, so this silently returned 0 for every community
        // (PlatformAdmin showed 0 subscribers; My Feed's "active" ranking sorted
        // all-zeros). Real names first, guesses kept as fallbacks.
        var count = (typeof d === "number") ? d
                  : (d && (d.total_subscribers || d.count || d.subscriber_count || 0)) || 0
        onOk(parseInt(count, 10) || 0)
    }, onErr);
}

// GET /community-subscriber/suggested-communities — leaf communities ranked by
// subscriber count, hidden (exclude_home) subtree already filtered server-side.
// One request; replaces the old get-communities + N x subscriberCount fan-out.
function suggestedCommunities(baseUrl, limit, onOk, onErr) {
    Http.get(baseUrl, "/community-subscriber/suggested-communities",
             { limit: limit }, null, function (data) {
        var d = data && data.data
        var rows = (d && d.communities) || []
        if (!Array.isArray(rows)) rows = []
        var out = [];
        for (var i = 0; i < rows.length; i++) {
            var r = rows[i] || {};
            out.push({
                id: r.id,
                title: r.title || "",
                dns: r.dns || "",
                icon: r.icon_url || r.logo_url || "",
                subscribers: parseInt(r.total_subscribers, 10) || 0
            });
        }
        onOk(out);
    }, onErr);
}

function listSubscribers(baseUrl, communityId, limit, offset, onOk, onErr) {
    Http.get(baseUrl, "/community-subscriber/pagination/" + encodeURIComponent(communityId),
             { limit: limit, offset: offset }, null, function (data) {
        var d = data && data.data
        var list = Array.isArray(d) ? d
                 : (d && (d.subscribers || d.community_subscribers || d.results)) || []
        if (!Array.isArray(list)) list = []
        onOk(list)
    }, onErr);
}
