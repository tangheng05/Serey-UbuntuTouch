.pragma library
.import "Http.js" as Http
.import "Mappers.js" as M

// onOk receives (posts, rawCount); rawCount is the pre-filter server count so callers paginate against the true offset, not a filtered length.
function _list(baseUrl, path, params, token, onOk, onErr) {
    return Http.get(baseUrl, path, params, token, function (data) {
        var raw = data.posts || [];
        onOk(raw.map(M.toPost), raw.length);
    }, onErr);
}

// Only posts from authors the user follows, excluding community-subscription posts; same params/response shape.
function listFeedFollowing(baseUrl, params, token, onOk, onErr) {
    return _list(baseUrl, "/serey-web/list-by-feed-following", params, token, onOk, onErr);
}

// Posts from followed authors OR subscribed communities; what My Feed uses
function listFeedMixed(baseUrl, params, token, onOk, onErr) {
    return _list(baseUrl, "/serey-web/list-by-feed-mixed", params, token, onOk, onErr);
}

function listDrumFeed(baseUrl, params, token, onOk, onErr) {
    return _list(baseUrl, "/serey-web/list-drum-post-by-feed", params, token, onOk, onErr);
}

function listGalleryFeed(baseUrl, params, token, onOk, onErr) {
    return Http.get(baseUrl, "/serey-web/list-gallery-post-by-feed", params, token, function (data) {
        var raw = data.posts || [];
        var posts = raw.map(M.toGalleryPost).filter(function (p) {
            return p.images.length > 0;
        });
        onOk(posts, raw.length);
    }, onErr);
}

function listTrending(baseUrl, params, token, onOk, onErr) {
    return _list(baseUrl, "/serey-web/list-by-trending", params, token, onOk, onErr);
}

function listHot(baseUrl, params, token, onOk, onErr) {
    return _list(baseUrl, "/serey-web/list-by-hot", params, token, onOk, onErr);
}

function listNew(baseUrl, params, token, onOk, onErr) {
    return _list(baseUrl, "/serey-web/list-by-new", params, token, onOk, onErr);
}

// The dedicated image-post feed; auth is optional (personalises voters/flaggers), mapped via toGalleryPost for this endpoint's field shape.
function listGallery(baseUrl, params, token, onOk, onErr) {
    return Http.get(baseUrl, "/serey-web/list-gallery-post-by-new", params, token, function (data) {
        var raw = data.posts || [];
        var posts = raw.map(M.toGalleryPost).filter(function (p) {
            return p.images.length > 0;
        });
        // Raw count, not filtered length, else the offset shrinks and re-requests rows
        onOk(posts, raw.length);
    }, onErr);
}

// Returns the xhr so callers can abort a stale request (My Feed does).
function listByAuthor(baseUrl, author, params, token, onOk, onErr) {
    var p = params || {};
    p.author = author;
    return _list(baseUrl, "/serey-web/list-by-author", p, token, onOk, onErr);
}

// An author's gallery posts; mirrors listGallery's filtering + pagination
function listGalleryByAuthor(baseUrl, author, params, token, onOk, onErr) {
    var p = params || {};
    p.author = author;
    return Http.get(baseUrl, "/serey-web/list-gallery-post-by-author", p, token, function (data) {
        var raw = data.posts || data.data || [];
        var posts = raw.map(M.toGalleryPost).filter(function (g) { return g.images.length > 0; });
        onOk(posts, raw.length);
    }, onErr);
}

function detail(baseUrl, author, permlink, token, onOk, onErr) {
    Http.get(baseUrl, "/serey-web/details-by-permlink-and-author",
             { author: author, permlink: permlink }, token, function (data) {
        var content = data.content || {};
        var replies = (data.replies || []).map(M.toComment);
        onOk({ post: M.toPost(content), replies: replies });
    }, onErr);
}

// Same endpoint as detail(), mapped via toGalleryPost so the carousel keeps every image, not just the cover, for GalleryDetailPage's Instagram-style view.
function detailGallery(baseUrl, author, permlink, token, onOk, onErr) {
    Http.get(baseUrl, "/serey-web/details-by-permlink-and-author",
             { author: author, permlink: permlink }, token, function (data) {
        var content = data.content || {};
        var replies = (data.replies || []).map(M.toComment);
        onOk({ post: M.toGalleryPost(content), replies: replies });
    }, onErr);
}

// POST /serey-web/create-or-update-post contract: categories is required ("gallery" routes to the gallery), subcategories must be an array (unconditional .forEach, or it 500s), community_id must be a real >0 number, images is the gallery's hosted URLs.
function createPost(baseUrl, params, token, onOk, onErr) {
    var body = {
        title: params.title,
        body: params.body || "",
        categories: params.categories || "general",
        subcategories: params.subcategories || [],
        images: params.images || []
    };
    // Sending permlink makes the backend update in place instead of creating new
    if (params.permlink)
        body.permlink = params.permlink;
    // Explicit bool so an edit can flip it either way; omitting it defaults true
    body.post_to_blockchain = (params.postToBlockchain !== false);
    // Publishing scope: the ceiling community, null for everywhere. Only sent for
    // a real community - Global is the combined feed, so capping there would just
    // hide the post from the one feed it was posted to.
    if (params.communityId)
        body.publish_scope_community_id = Number(params.publishCeilingId) > 0
                                          ? Number(params.publishCeilingId) : null;
    // Always send the post's own community_id, on create AND edit, so an edit keeps the post in
    // the same community it was originally posted to. Never send country_name alongside a real
    // id - only as a fallback when id is unknown (0/missing) - since sending both together was
    // getting rejected as "Invalid community".
    if (params.communityId) {
        body.community_id = Number(params.communityId);
    } else if (params.communityName) {
        body.country_name = params.communityName;
    }
    Http.post(baseUrl, "/serey-web/create-or-update-post", body,
              token, function (data) { onOk(data || {}); }, onErr);
}

// POST /serey-web/create-or-update-post for video: categories must be literal "video", subcategories must be an array, community_id must be a real >0 community (Global/id 0 rejected), videos is [hostedVideoUrl] on a Serey upload host, images is [thumbnailUrl], rate-limited to 10 videos/48h per author.
function createVideoPost(baseUrl, params, token, onOk, onErr) {
    var body = {
        title: params.title,
        desc: params.desc || "",
        body: params.body || params.desc || "",
        videos: [params.videoUrl],
        // Backend only persists a SEREY thumbnail when images.length > 1 (a single entry is dropped), so send the captured thumbnail twice.
        images: params.thumbUrl ? [params.thumbUrl, params.thumbUrl] : [],
        categories: "video",
        subcategories: [],
        is_video_component_only: true,
        is_post_video_component: true,
        is_ai_generated: false,
        site_credit: '<p>This was posted using <a href="https://serey.io" rel="nofollow noopener">Serey.io</a></p>'
    };
    // "Post on the blockchain" toggle (see createPost): explicit bool, false = DB-only.
    body.post_to_blockchain = (params.postToBlockchain !== false);
    // Publishing scope, same contract as createPost.
    if (params.communityId)
        body.publish_scope_community_id = Number(params.publishCeilingId) > 0
                                          ? Number(params.publishCeilingId) : null;
    // Editing an existing video post: sending its permlink makes the backend update in place (same contract as createPost).
    if (params.permlink)
        body.permlink = params.permlink;
    // Always send the post's own community_id, on create AND edit - see createPost() for why
    // country_name is never sent alongside a real id.
    if (params.communityId) {
        body.community_id = Number(params.communityId);
    } else if (params.communityName) {
        body.country_name = params.communityName;
    }
    Http.post(baseUrl, "/serey-web/create-or-update-post", body,
              token, function (data) { onOk(data || {}); }, onErr);
}

// POST alias since QML's XMLHttpRequest can't send a DELETE body; backend authorizes by the token's username so only your own content can be deleted.
function deletePost(baseUrl, username, permlink, token, onOk, onErr) {
    Http.post(baseUrl, "/serey-web/delete-post-or-comment",
              { username: username, permlink: permlink }, token,
              function (data) { onOk(data || {}); }, onErr);
}

// --- Admin/CMS moderation (requires an owner/manager token) ----------------

// Moderator delete by numeric row id, unlike deletePost not limited to own username
function adminDeletePost(baseUrl, id, token, onOk, onErr) {
    Http.del(baseUrl, "/serey-web/admin-delete-post-or-comment/" + id, token,
             function (data) { onOk(data || {}); }, onErr);
}

// Needs a JSON body (list of ids), so uses Http.delWithBody not bodiless del()
function adminBulkDeletePosts(baseUrl, ids, token, onOk, onErr) {
    Http.delWithBody(baseUrl, "/serey-web/admin-bulk-delete-posts", { ids: ids }, token,
                      function (data) { onOk(data || {}); }, onErr);
}

// Response shape differs from other list endpoints: { new_posts, trending_posts, feed_posts }
function searchAdvanced(baseUrl, params, token, onOk, onErr) {
    return Http.get(baseUrl, "/serey-web/search-advanced", params, token, function (data) {
        var buckets = (data.new_posts || []).concat(data.trending_posts || [], data.feed_posts || []);
        onOk(buckets.map(M.toPost));
    }, onErr);
}

// Fires search_title + search_username in parallel, merges+dedupes by id
function searchPosts(baseUrl, query, extraParams, token, onOk, onErr) {
    var pending = 2;
    var byId = {};
    var order = [];
    var lastErr = null;
    function record(posts) {
        for (var i = 0; i < posts.length; i++) {
            var p = posts[i];
            var key = p.id !== undefined ? String(p.id) : (p.author + "/" + p.permlink);
            if (byId[key]) continue;
            byId[key] = true;
            order.push(p);
        }
    }
    function done(err) {
        if (err) lastErr = err;
        if (--pending > 0) return;
        if (order.length === 0 && lastErr) { onErr(lastErr); return; }
        onOk(order);
    }
    var titleParams = Object.assign({}, extraParams, { search_title: query });
    var userParams = Object.assign({}, extraParams, { search_username: query });
    var t1 = searchAdvanced(baseUrl, titleParams, token, function (posts) { record(posts); done(null); }, function (err) { done(err); });
    var t2 = searchAdvanced(baseUrl, userParams, token, function (posts) { record(posts); done(null); }, function (err) { done(err); });
    return { abort: function () { t1.abort(); t2.abort(); } };
}
