.pragma library
.import "Http.js" as Http
.import "Mappers.js" as M

/*
 * Post / feed endpoints under /serey-web. The list endpoints accept only
 * `limit` and `offset` (sending community_id is rejected with "Invalid parameter").
 * Responses come back as { posts: [...] }; detail as { content: {...}, replies: [...] }.
 */

// onOk receives (posts, rawCount). rawCount is the number of rows the server
// returned *before* any client-side filtering, so callers paginate/`endReached`
// against the true server offset rather than a filtered length.
function _list(baseUrl, path, params, token, onOk, onErr) {
    return Http.get(baseUrl, path, params, token, function (data) {
        var raw = data.posts || [];
        onOk(raw.map(M.toPost), raw.length);
    }, onErr);
}

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

// Gallery: the dedicated image-post feed. Takes limit + offset (offset=0 is
// sent as "0", which the backend accepts), and community_id to narrow by region
// exactly like the blog feeds. Requires only optional auth; the token, when
// present, personalises voters/flaggers state. Mapped via toGalleryPost, which
// already expects this endpoint's fields (image_url, voter_count, serey_value…).
function listGallery(baseUrl, params, token, onOk, onErr) {
    return Http.get(baseUrl, "/serey-web/list-gallery-post-by-new", params, token, function (data) {
        var raw = data.posts || [];
        var posts = raw.map(M.toGalleryPost).filter(function (p) {
            return p.images.length > 0;
        });
        // Pass the RAW server count, not the filtered length, so GalleryPage
        // advances offset correctly (filtering image-less rows must not shrink
        // the next page's offset or it re-requests the same rows forever).
        onOk(posts, raw.length);
    }, onErr);
}

function listByAuthor(baseUrl, author, params, token, onOk, onErr) {
    var p = params || {};
    p.author = author;
    _list(baseUrl, "/serey-web/list-by-author", p, token, onOk, onErr);
}

// A specific author's gallery (image) posts, mapped via toGalleryPost so the
// profile's Gallery tab shows the image carousel. Mirrors listGallery's
// image-less filtering + raw-count pagination.
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

// Same endpoint as detail(), mapped via toGalleryPost so the carousel keeps
// every image (not just the cover) for GalleryDetailPage's Instagram-style view.
function detailGallery(baseUrl, author, permlink, token, onOk, onErr) {
    Http.get(baseUrl, "/serey-web/details-by-permlink-and-author",
             { author: author, permlink: permlink }, token, function (data) {
        var content = data.content || {};
        var replies = (data.replies || []).map(M.toComment);
        onOk({ post: M.toGalleryPost(content), replies: replies });
    }, onErr);
}

// POST /serey-web/create-or-update-post — create a blog or gallery post.
//
// Backend contract (serey-api postSchema + createOrUpdatePost service):
//   - `categories` is a REQUIRED string. The literal "gallery" routes the post
//     into the community's gallery (governed by gallery_is_allow_post); any
//     other value is a normal blog category.
//   - `subcategories` MUST be an array — the service calls subcategories.forEach
//     unconditionally, so omitting it 500s the request.
//   - `community_id` is a NUMBER and must resolve to a real community. Note the
//     server treats 0 as falsy and then looks up by country_name, so a post
//     needs a concrete (>0) community id.
//   - `images` is an array of hosted image URLs (the gallery carousel; for a
//     blog post the cover lives in the body HTML).
function createPost(baseUrl, params, token, onOk, onErr) {
    var body = {
        title: params.title,
        body: params.body || "",
        categories: params.categories || "general",
        subcategories: params.subcategories || [],
        images: params.images || []
    };
    // Editing an existing post: sending its permlink makes the backend update in
    // place (isCreate=false) instead of creating a new post. Author is taken from
    // the token, so only your own post can be updated.
    if (params.permlink)
        body.permlink = params.permlink;
    // "Post to blockchain" toggle. Sent explicitly (as a bool) so an edit can
    // switch it either way — the backend re-evaluates it per save. Omitting it
    // would default to true on-chain, so only `false` changes behaviour.
    body.post_to_blockchain = (params.postToBlockchain !== false);
    if (params.communityId)            // omit when 0/empty so we don't post a falsy id
        body.community_id = Number(params.communityId);
    // The server resolves the target community by id when present, otherwise by
    // title (country_name). Sending the name lets "Global" (sentinel id 0) and
    // any source whose id we don't hold still resolve server-side.
    if (params.communityName)
        body.country_name = params.communityName;
    Http.post(baseUrl, "/serey-web/create-or-update-post", body,
              token, function (data) { onOk(data || {}); }, onErr);
}

// POST /serey-web/create-or-update-post — create a VIDEO post. A "video" is a
// normal Post carrying the uploaded media URL plus the video-component flags;
// the backend's createOrUpdatePost also creates the YoutubeComponent row (so it
// surfaces in the curated video feed) and broadcasts on-chain.
//
// Backend contract (verified against serey-api):
//   - `categories` MUST be the literal "video".
//   - `subcategories` MUST be an array (the service calls .forEach on it).
//   - `community_id` must resolve to a real community > 0 — "Global" (id 0) is
//     rejected for videos (it's also used to allocate the html_section_id), so
//     the caller must pick a concrete community first.
//   - `videos` is [hostedVideoUrl]; the URL must be on a Serey upload host or the
//     server can't classify it as platform SEREY.
//   - `images` is [thumbnailUrl] (optional; the post's card thumbnail).
//   - Rate limited to 10 videos / 48h per author (enforced server-side).
function createVideoPost(baseUrl, params, token, onOk, onErr) {
    var body = {
        title: params.title,
        desc: params.desc || "",
        body: params.body || params.desc || "",
        videos: [params.videoUrl],
        // The backend only persists a SEREY video's thumbnail when images.length
        // > 1 (createOrUpdatePost: `images.length > 1 ? images[0] : video_thumbnail_url`,
        // and video_thumbnail_url is undefined for SEREY). So send the captured
        // thumbnail twice — images[0] becomes the stored thumbnail_url; a single
        // entry would be dropped and the card would show blank.
        images: params.thumbUrl ? [params.thumbUrl, params.thumbUrl] : [],
        categories: "video",
        subcategories: [],
        is_video_component_only: true,
        is_post_video_component: true,
        is_ai_generated: false,
        site_credit: '<p>This was posted using <a href="https://serey.io" rel="nofollow noopener">Serey.io</a></p>'
    };
    // "Post to blockchain" toggle (see createPost): explicit bool, false = DB-only.
    body.post_to_blockchain = (params.postToBlockchain !== false);
    // Editing an existing video post: sending its permlink makes the backend
    // update in place (same contract as createPost).
    if (params.permlink)
        body.permlink = params.permlink;
    if (params.communityId)
        body.community_id = Number(params.communityId);
    if (params.communityName)
        body.country_name = params.communityName;
    Http.post(baseUrl, "/serey-web/create-or-update-post", body,
              token, function (data) { onOk(data || {}); }, onErr);
}

// Delete one of the signed-in user's own posts (blog, gallery or video — all are
// Posts server-side). Uses the POST alias of /serey-web/delete-post-or-comment
// (QML's XMLHttpRequest can't send a DELETE body). The backend authorises by the
// token's username, so this can only ever delete your own content; the `username`
// in the body is required by the schema but the author is taken from the token.
function deletePost(baseUrl, username, permlink, token, onOk, onErr) {
    Http.post(baseUrl, "/serey-web/delete-post-or-comment",
              { username: username, permlink: permlink }, token,
              function (data) { onOk(data || {}); }, onErr);
}
