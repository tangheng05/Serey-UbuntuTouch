.pragma library

function toInt(v) {
    var n = parseInt(v, 10);
    return isNaN(n) ? 0 : n;
}

// Default true (on-chain); only an explicit false/"false"/0 means DB-only
function onChainFlag(raw) {
    return raw.post_to_blockchain !== false
        && raw.post_to_blockchain !== "false"
        && raw.post_to_blockchain !== 0;
}

function parseList(val) {
    if (!val)
        return [];
    if (Array.isArray(val))
        return val;
    if (typeof val !== "string")
        return [];
    var s = val.trim();
    if (s === "" || s === "None" || s === "[]")
        return [];
    s = s.replace(/^\[/, "").replace(/\]$/, "");
    var parts = s.split(",");
    var out = [];
    for (var i = 0; i < parts.length; i++) {
        var p = parts[i].trim().replace(/^['"]/, "").replace(/['"]$/, "").trim();
        if (p && p !== "None")
            out.push(p);
    }
    return out;
}

var _entities = { "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">" };

// Called once per row per page, on the UI thread, against the full article body.
// The four entity rules were four separate full-string passes; one alternation
// does the same work in a single scan. Three passes now: tags, entities, spaces.
function stripHtml(html, max) {
    if (!html)
        return "";
    var text = String(html)
        .replace(/<[^>]+>/g, " ")
        .replace(/&nbsp;|&amp;|&lt;|&gt;/g, function (e) { return _entities[e]; })
        .replace(/\s+/g, " ")
        .trim();
    if (max && text.length > max)
        text = text.substring(0, max).trim() + "…";
    return text;
}

// YouTube's maxresdefault.jpg is missing for many videos (404); hqdefault.jpg always exists, so prefer it.
function fixThumb(url) {
    if (url && url.indexOf("img.youtube.com") >= 0)
        return url.replace("maxresdefault", "hqdefault");
    return url;
}

// Pick a thumbnail for a post: explicit list field, else first <img> in the body.
function firstImage(raw) {
    var imgs = parseList(raw.image_url);
    if (imgs.length)
        return fixThumb(imgs[0]);
    if (raw.thumbnail_url)
        return fixThumb(raw.thumbnail_url);
    var desc = raw.description || raw.post_description || "";
    var m = /<img[^>]+src=["']([^"']+)["']/i.exec(desc);
    return m ? fixThumb(m[1]) : "";
}

// Normalise a voters/flaggers list to plain usernames; the API sends either ["alice"] or [{voter:"alice"}] depending on endpoint.
function voterNames(arr) {
    if (!arr || !Array.isArray(arr))
        return [];
    var out = [];
    for (var i = 0; i < arr.length; i++) {
        var v = arr[i];
        if (typeof v === "string")
            out.push(v);
        else if (v && v.voter)
            out.push(v.voter);
    }
    return out;
}

function toPost(raw) {
    raw = raw || {};
    // Each of these was recomputed per field below (categories parsed 4x, each
    // voter list walked twice) for every row of every page. Same values, built once.
    var cats = parseList(raw.categories);
    var voters = voterNames(raw.voters);
    var flaggers = voterNames(raw.flaggers);
    return {
        id: raw.id,
        author: raw.author || "",
        permlink: raw.permlink || "",
        title: raw.title || "(untitled)",
        body: raw.description || "",
        excerpt: stripHtml(raw.short_desc || raw.description || "", 180),
        thumbnail: firstImage(raw),
        authorImage: raw.author_image_url || "",
        date: raw.publish_date || "",
        votes: toInt(raw.voter_count),
        comments: toInt(raw.answer_count),
        payout: raw.serey_value || "",
        categories: cats,
        // Scalar copy of the first category since a dynamicRoles ListModel wraps the `categories` array (losing [] indexing); edit-prefill reads this.
        primaryCategory: cats[0] || "",
        // The post's tag list is [mainCategory, ...subcategories]; everything after
        // the first is a sub-category. Scalar copy of the first for the same
        // ListModel-wrapping reason as primaryCategory.
        subCategories: cats.slice(1),
        primarySubCategory: cats[1] || "",
        voters: voters,
        voterStr: "," + voters.join(",") + ",",
        flaggers: flaggers,
        flaggerStr: "," + flaggers.join(",") + ",",
        community: raw.community_title || "",
        communityId: toInt(raw.community_id),
        checkmark: raw.checkmark_icon || "",
        postToBlockchain: onChainFlag(raw)
    };
}

// Like toPost, but keeps every image (not just the cover) for the carousel
function toGalleryPost(raw) {
    raw = raw || {};
    var imgs = parseList(raw.image_url).map(fixThumb);
    return {
        id: raw.id,
        author: raw.author || "",
        permlink: raw.permlink || "",
        authorImage: raw.author_image_url || "",
        date: raw.publish_date || "",
        images: imgs,
        // A dynamicRoles ListModel wraps `images` and loses the bare URL strings; the feed card reads this scalar instead.
        imagesStr: imgs.join("\n"),
        caption: raw.title || "",
        votes: toInt(raw.voter_count),
        flaggers: voterNames(raw.flaggers),
        comments: toInt(raw.answer_count),
        payout: raw.serey_value || "",
        voters: voterNames(raw.voters),
        voterStr: "," + voterNames(raw.voters).join(",") + ",",
        categories: parseList(raw.categories),
        primaryCategory: parseList(raw.categories)[0] || "",
        // Post's own community title, so editing keeps it in place.
        community: raw.community_title || "",
        checkmark: raw.checkmark_icon || "",
        postToBlockchain: onChainFlag(raw)
    };
}

function toComment(raw) {
    raw = raw || {};
    var kids = [];
    if (raw.replies && raw.replies.length) {
        for (var i = 0; i < raw.replies.length; i++)
            kids.push(toComment(raw.replies[i]));
    }
    return {
        author: raw.author || "",
        permlink: raw.permlink || "",
        // Needed to resubmit create-or-update-comment when editing, since it always requires the parent it's attached to, not just its own permlink.
        parentAuthor: raw.parent_author || "",
        parentPermlink: raw.parent_permlink || "",
        body: stripHtml(raw.description || raw.body || ""),
        date: raw.publish_date || "",
        votes: toInt(raw.voter_count),
        voters: voterNames(raw.voters),
        voterStr: "," + voterNames(raw.voters).join(",") + ",",
        flaggers: voterNames(raw.flaggers),
        flaggerStr: "," + voterNames(raw.flaggers).join(",") + ",",
        authorImage: raw.author_image_url || "",
        replies: kids
    };
}

function toVideo(raw) {
    raw = raw || {};
    return {
        id: raw.id,
        author: raw.username || raw.author || "",
        permlink: raw.permlink || "",
        title: raw.title || "(untitled)",
        body: raw.description || raw.post_description || "",
        excerpt: stripHtml(raw.description || raw.post_description || "", 180),
        thumbnail: fixThumb(raw.thumbnail_url || ""),
        authorImage: raw.author_image_url || raw.post_author_image_url || "",
        date: raw.publish_date || "",
        votes: toInt(raw.voter_count),
        comments: toInt(raw.answer_count || raw.comment_count),
        voters: voterNames(raw.voters),
        voterStr: "," + voterNames(raw.voters).join(",") + ",",
        payout: raw.serey_value || "",
        embedUrl: raw.embed_video || "",
        videoLink: raw.video_link || "",
        videoId: raw.video_id || "",
        platform: raw.platform_type || "",
        dimensions: raw.dimensions || "16:9",
        categories: parseList(raw.categories),
        primaryCategory: parseList(raw.categories)[0] || "",
        community: raw.community_title || "",
        communityId: toInt(raw.community_id),
        postToBlockchain: onChainFlag(raw)
    };
}

function toCommunity(raw) {
    raw = raw || {};
    return {
        id: raw.id,
        title: raw.title || "",
        dns: raw.dns || "",
        icon: raw.icon_url || raw.logo_url || "",
        country: raw.country || "",
        description: raw.meta_description || "",   // owner-set blurb, often empty
        level: toInt(raw.level),
        // is_allow_post=true means anyone may post, false means owner/managers only; drives whether the compose buttons are shown for this community.
        allowPost: !!raw.is_allow_post,
        // video_is_allow_post gates the Video upload FAB independently of the blog flag (true = anyone, false = owner/managers only).
        videoAllowPost: !!raw.video_is_allow_post,
        // Number of sub-communities under this one, used to hide empty countries from the picker.
        childCount: Array.isArray(raw.child_communities) ? raw.child_communities.length : 0
    };
}

function toUser(username, raw) {
    raw = raw || {};
    // `full_name` is an object { first_name, last_name } (the DB `name` column); flatten it, falling back to the blockchain account `name` string.
    var fn = "", ln = "";
    if (raw.full_name && typeof raw.full_name === "object") {
        fn = raw.full_name.first_name || "";
        ln = raw.full_name.last_name || "";
    } else if (typeof raw.full_name === "string") {
        fn = raw.full_name;
    }
    var full = (fn + " " + ln).trim();
    if (!full && typeof raw.name === "string")
        full = raw.name;
    // `phone` can be a scalar or an object { primary, secondary }.
    var phone = raw.phone;
    if (phone && typeof phone === "object")
        phone = phone.primary || phone.secondary || "";
    return {
        username: username,
        firstName: fn,
        lastName: ln,
        fullName: full || username,
        // Trim: stored bios often carry trailing newlines/spaces, which a word-wrapped Label renders as a blank gap below it.
        bioHtml: (raw.bio || "").trim(),
        bio: (raw.bio || "").replace(/<\/p>\s*<p[^>]*>/gi, "\n").replace(/<br\s*\/?>/gi, "\n").replace(/<[^>]+>/g, "").trim(),
        gender: raw.gender_title || "",
        dob: raw.dob || "",
        reputation: raw.reputation,
        postCount: toInt(raw.post_count),
        commentCount: toInt(raw.comment_count),
        followers: toInt(raw.followers_count),
        following: toInt(raw.following_count),
        balance: raw.balance || "",
        sereyPower: raw.sereypower || "",
        joinDate: raw.join_date || "",
        profileUrl: raw.profile_url || "",
        coverUrl: raw.cover_image_url || "",
        checkmark: raw.checkmark_icon || "",
        email: raw.email || "",
        phone: phone || ""
    };
}

// The web client posts a literal "Unknown" when it has no geo; blank it so the
// UI drops the line instead of printing "Unknown, Unknown".
function devicePlace(v) {
    var s = (v || "").trim();
    return (s === "Unknown" || s === "None" || s === "null") ? "" : s;
}

function toDevice(raw) {
    return {
        id: toInt(raw.id),
        deviceName: devicePlace(raw.device_name),
        city: devicePlace(raw.city_name),
        country: devicePlace(raw.country_name),
        lastActiveAt: raw.last_active_at || ""
    };
}
