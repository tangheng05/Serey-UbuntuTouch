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
        var count = (typeof d === "number") ? d
                  : (d && (d.count || d.subscriber_count || 0)) || 0
        onOk(parseInt(count, 10) || 0)
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
