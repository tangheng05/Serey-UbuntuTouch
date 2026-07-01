.pragma library

/*
 * Normalises raw Serey API JSON into stable view-models used by the QML.
 * All field-name quirks live here. The API sends several fields as Python-style
 * stringified lists, e.g. image_url = "['https://...']", categories = "['general']",
 * and "None" for nulls — parseList() handles those.
 */

function toInt(v) {
    var n = parseInt(v, 10);
    return isNaN(n) ? 0 : n;
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

function stripHtml(html, max) {
    if (!html)
        return "";
    var text = String(html)
        .replace(/<[^>]+>/g, " ")
        .replace(/&nbsp;/g, " ")
        .replace(/&amp;/g, "&")
        .replace(/&lt;/g, "<")
        .replace(/&gt;/g, ">")
        .replace(/\s+/g, " ")
        .trim();
    if (max && text.length > max)
        text = text.substring(0, max).trim() + "…";
    return text;
}

// YouTube's maxresdefault.jpg is missing for many videos (404). hqdefault.jpg
// always exists, so prefer it.
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

// Normalise a voters/flaggers list to plain usernames. The API sends either
// ["alice", ...] (detail content) or [{voter:"alice"}, ...] (some endpoints).
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
        categories: parseList(raw.categories),
        // Scalar copy of the first category: a dynamicRoles ListModel wraps the
        // `categories` array (losing [] indexing), so edit-prefill reads this.
        primaryCategory: parseList(raw.categories)[0] || "",
        voters: voterNames(raw.voters),
        voterStr: "," + voterNames(raw.voters).join(",") + ",",
        flaggers: voterNames(raw.flaggers),
        flaggerStr: "," + voterNames(raw.flaggers).join(",") + ",",
        community: raw.community_title || "",
        checkmark: raw.checkmark_icon || ""
    };
}

// A comment/reply node. Recurses into nested `replies` so the detail page can
// flatten the tree with indentation.
// Gallery post: like toPost, but keeps every image (not just the cover) for
// the swipeable carousel.
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
        // A dynamicRoles ListModel wraps the `images` array into a nested model
        // whose .get(i) loses the bare URL strings (returns empty objects), so
        // the feed card reads this newline-joined scalar instead — scalars
        // survive the ListModel intact. URLs never contain a raw newline.
        imagesStr: imgs.join("\n"),
        caption: raw.title || "",
        votes: toInt(raw.voter_count),
        flaggers: voterNames(raw.flaggers),
        comments: toInt(raw.answer_count),
        payout: raw.serey_value || "",
        voters: voterNames(raw.voters),
        voterStr: "," + voterNames(raw.voters).join(",") + ",",
        // Post's own community title, so editing keeps it in place.
        community: raw.community_title || "",
        checkmark: raw.checkmark_icon || ""
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
        // Needed to resubmit create-or-update-comment when editing (it always
        // requires the parent it's attached to, not just its own permlink).
        parentAuthor: raw.parent_author || "",
        parentPermlink: raw.parent_permlink || "",
        body: stripHtml(raw.description || raw.body || ""),
        date: raw.publish_date || "",
        votes: toInt(raw.voter_count),
        voters: voterNames(raw.voters),
        voterStr: "," + voterNames(raw.voters).join(",") + ",",
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
        comments: toInt(raw.answer_count),
        payout: raw.serey_value || "",
        embedUrl: raw.embed_video || "",
        videoLink: raw.video_link || "",
        videoId: raw.video_id || "",
        platform: raw.platform_type || "",
        dimensions: raw.dimensions || "16:9",
        community: raw.community_title || ""
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
        level: toInt(raw.level),
        // is_allow_post=true → anyone may post; false → owner/managers only.
        // Drives whether the compose buttons are shown for this community.
        allowPost: !!raw.is_allow_post
    };
}

function toUser(username, raw) {
    raw = raw || {};
    // `full_name` is an object { first_name, last_name } (it's the DB `name`
    // column); flatten it. Fall back to the blockchain account `name` string.
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
        // Trim: stored bios often carry trailing newlines/spaces, which a
        // word-wrapped Label renders as blank lines (a big empty gap below it).
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
