import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3 as Popups
import "../Theme"
import "../Session"
import "../components"
import "../services/PostService.js" as PostService
import "../services/CategoryService.js" as CategoryService

Page {
    id: page

    property bool submitting: false
    property string selectedCategory: ""
    // Optional sub-category under the selected main category, sent in `subcategories`.
    property string selectedSubCategory: ""
    property bool catSheetOpen: false
    // On-screen-keyboard height; the formatting toolbar rides above it so B/I/U stay reachable while typing.
    readonly property real kbHeight: Qt.inputMethod.visible ? Qt.inputMethod.keyboardRectangle.height : 0
    readonly property int titleMaxLength: 250
    readonly property real maxContentWidth: units.gu(72)
    property string coverImageUrl: ""
    property bool uploading: false
    // The body as a sequence of blocks: {type:"text", html:"..."} or {type:"image", url:"..."}.
    // Lomiri's TextArea can't render <img> tags (Qt bug QTBUG-27071, confirmed in the component's
    // own source), so images can't live inside a single rich-text document here; instead each image
    // is its own real Image item, stacked between editable text segments inside the same bordered box.
    property var bodyParts: [{ type: "text", html: "" }]
    // Which bodyParts text segment currently has keyboard focus; formatting/link/image-insert act on it.
    property int activeTextIndex: 0
    // Bumped by every text segment's onTextChanged so canPublish/placeholder stay reactive
    // (a plain function call into a Repeater delegate's .text isn't tracked as a binding dependency).
    property int _bodyRev: 0
    // True while any bodyParts text segment has focus (focus itself lives on whichever child TextArea is active).
    property bool bodyFocused: false
    // Set right before a fresh text segment is created (e.g. after inserting an image) so its
    // Loader can focus it once instantiated; Loader.onLoaded fires only once per delegate creation.
    property int _pendingFocusIndex: -1
    // "Post on the blockchain": on = broadcast on-chain (default), off = save to the Serey DB only (no voting/rewards).
    property bool postToBlockchain: true

    function _anyBodyPartFocused() {
        for (var i = 0; i < page.bodyParts.length; i++) {
            var l = bodyRepeater.itemAt(i);
            if (l && l.item && l.item.activeFocus) return true;
        }
        return false;
    }

    // Single writer into the real bodyParts array (by index, so it actually persists).
    function _setPartHtml(idx, html) {
        if (idx < 0 || idx >= page.bodyParts.length) return;
        if (page.bodyParts[idx].type !== "text") return;
        page.bodyParts[idx].html = html;
        page._bodyRev++;
    }

    function _bodyHasContent() {
        for (var i = 0; i < page.bodyParts.length; i++) {
            var p = page.bodyParts[i];
            if (p.type === "image" || p.type === "embed") return true;
            if (p.type === "text" && (p.html || "").trim().length > 0) return true;
        }
        return false;
    }

    readonly property bool canPublish: !page.submitting
        && titleField.text.trim().length > 0
        && page._bodyRev >= 0 && page._bodyHasContent()

    // Chosen in PostCommunityPicker before this page opens; unset = post into the browsed source
    property var targetCommunity: null
    readonly property int postCommunityId: page.isEdit ? Number((page.editPost && page.editPost.communityId) || 0)
                                         : page.targetCommunity ? Number(page.targetCommunity.id)
                                                                : Config.communityId
    // Categories key by the selected sub-community; the post itself by its top-level source.
    // An edit can't move a post between communities, so its categories come from the community it
    // was posted in: keying them off the browsed source offered categories it could never use.
    readonly property string catCommunityName: page.isEdit ? ((page.editPost && page.editPost.community) || Config.currentCommunityName)
                                             : page.targetCommunity ? page.targetCommunity.name
                                                                    : Config.currentCommunityName
    // Cached record for the edited post's platform, for its logo in the row below.
    readonly property var editCommunityInfo: page.isEdit && page.editPost && page.editPost.communityId
                                             ? Config.communityInfoFor(page.editPost.communityId) : null
    readonly property string editCommunityIcon: page.editCommunityInfo
                                                ? (page.editCommunityInfo.icon || "")
                                                : (page.catCommunityName === Config.currentCommunityName
                                                   ? Config.currentCommunityIconUrl : "")

    readonly property string postCommunityName: page.targetCommunity ? page.targetCommunity.name
                                                                     : Config.communityName

    // When set, this page edits an existing post (sends its permlink to update in place) instead of creating a new one.
    property var editPost: null
    readonly property bool isEdit: !!editPost

    // isNew: feed jumps to Latest only when there's actually a new post to show
    signal saved(bool isNew)

    // Categories are per-community, loaded from the backend for the currently-selected source rather than hardcoded.
    property var categories: []
    // Map of main-category name -> array of its sub-category names
    property var subcatsByCat: ({})
    property bool categoriesLoading: false
    property int catEpoch: 0

    // Sub-categories for whichever main category is currently selected.
    function subsForSelected() {
        var s = page.subcatsByCat[page.selectedCategory];
        return (s && s.length) ? s : [];
    }

    // Case-insensitive lookup that returns the list's own spelling, or "" when absent.
    function _matchName(list, want) {
        if (!want || !list) return "";
        var w = String(want).toLowerCase();
        for (var i = 0; i < list.length; i++)
            if (String(list[i]).toLowerCase() === w) return list[i];
        return "";
    }

    function loadCategories() {
        var epoch = ++page.catEpoch;
        var prev = page.selectedCategory;
        page.categoriesLoading = true;
        // catCommunityName/postCommunityId already resolve targetCommunity > Config.
        CategoryService.listByCommunity(Config.baseUrl, page.catCommunityName, page.postCommunityId, Session.token,
            function (names, raw) {
                if (epoch !== page.catEpoch) return;   // stale community switch
                page.categoriesLoading = false;
                page.categories = names;
                // Build the main -> [sub names] map from the raw records.
                var map = {};
                for (var i = 0; i < (raw ? raw.length : 0); i++) {
                    var subsRaw = raw[i].sub_categories || raw[i].sub || [];
                    if (!Array.isArray(subsRaw)) subsRaw = [];
                    var subs = [];
                    for (var j = 0; j < subsRaw.length; j++) {
                        var nm = (subsRaw[j] && (typeof subsRaw[j] === "string" ? subsRaw[j] : subsRaw[j].name) || "").trim();
                        if (nm.length > 0) subs.push(nm);
                    }
                    map[raw[i].name || ""] = subs;
                }
                page.subcatsByCat = map;
                // Keep what the post was filed under. The API's category names don't always match
                // the post's copy exactly (case differs), and a strict compare dropped an edit back
                // to "Select category" even though the post already had one.
                var keep = page._matchName(names, prev);
                page.selectedCategory = keep;
                page.selectedSubCategory = (keep.length === 0) ? ""
                    : page._matchName(map[keep] || [], page.selectedSubCategory);
            },
            function () {
                if (epoch !== page.catEpoch) return;
                page.categoriesLoading = false;
                page.categories = [];
                page.subcatsByCat = ({});
            });
    }

    Component.onCompleted: {
        if (page.editPost) {
            titleField.text = page.editPost.title || "";
            var b = page.editPost.body || "";
            // Older posts baked their cover image in as a leading <img>; strip it only when it actually
            // matches this post's own thumbnail (restored separately below), never a genuine first body
            // image the user actually typed there.
            var thumb = page.editPost.thumbnail || "";
            if (thumb.length > 0) {
                var leadMatch = b.match(/^\s*<img[^>]*src=["']([^"']*)["'][^>]*>\s*/i);
                if (leadMatch && leadMatch[1] === thumb) b = b.substring(leadMatch[0].length);
            }
            // Split the body into alternating text/image blocks, one real Image item per <img>.
            var parts = [];
            var lastIndex = 0;
            var imgRe = /<img[^>]*src=["']([^"']*)["'][^>]*\/?>/gi;
            var m;
            while ((m = imgRe.exec(b)) !== null) {
                parts.push({ type: "text", html: b.substring(lastIndex, m.index) });
                parts.push({ type: "image", url: m[1] });
                lastIndex = imgRe.lastIndex;
            }
            parts.push({ type: "text", html: b.substring(lastIndex) });
            page.bodyParts = parts;
            // A thumbnail that is still one of the body's own images was auto-derived, not a cover the
            // user picked. Re-sending it as `images` turned it into a real cover, so deleting that image
            // from the body made it reappear on top of the article.
            var thumbIsBodyImage = false;
            for (var pi = 0; pi < parts.length; pi++) {
                if (parts[pi].type === "image" && parts[pi].url === thumb) { thumbIsBodyImage = true; break; }
            }
            page.coverImageUrl = thumbIsBodyImage ? "" : thumb;
            // primaryCategory is a scalar since the categories array is wrapped by the feed ListModel and loses [] indexing.
            page.selectedCategory = page.editPost.primaryCategory || "";
            // Best-effort sub-category prefill (field name varies across sources).
            var eSub = page.editPost.subCategory || page.editPost.subcategory || "";
            if (!eSub) {
                var eSubs = page.editPost.subCategories || page.editPost.subcategories;
                if (eSubs && eSubs.length) eSub = (typeof eSubs[0] === "string") ? eSubs[0] : (eSubs[0] && eSubs[0].name) || "";
            }
            page.selectedSubCategory = eSub || "";
            // Prefill the toggle from the saved post (default on if absent).
            page.postToBlockchain = (page.editPost.postToBlockchain !== false);
            // Some list endpoints (e.g. list-by-author, used by the Profile page) don't return
            // community_id/community_title per row, so editPost can arrive with neither set.
            // publish() then falls back to Config.communityName, which can be a different
            // community than the one this post actually lives in -> backend rejects the save
            // with "invalid community". Re-fetch the authoritative values from the post's own
            // detail endpoint whenever they're missing, regardless of which page opened the editor.
            if (!(page.editPost.communityId > 0) || !page.editPost.community) {
                var author = page.editPost.author || "";
                var permlink = page.editPost.permlink || "";
                if (author && permlink) {
                    PostService.detail(Config.baseUrl, author, permlink, Session.token,
                        function (result) {
                            var p = result && result.post;
                            if (!p || !page.editPost) return;
                            page.editPost = Object.assign({}, page.editPost, {
                                communityId: p.communityId || page.editPost.communityId,
                                community: p.community || page.editPost.community
                            });
                        },
                        function (err) { /* best-effort; publish() still has its old fallback */ });
                }
            }
        }
        loadCategories();   // captures selectedCategory above as the kept value
    }
    // React to source changes, unless a specific target community was chosen via the picker
    Connections {
        target: Config
        function onCommunityIdChanged() { if (!page.targetCommunity && !page.isEdit) page.loadCategories() }
    }

    header: Item { height: 0 }

    // Custom header drawn as a sibling so Lomiri's Page doesn't clip it
    Rectangle {
        id: hdr
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: units.gu(6)
        color: Style.surface
        z: 10

        AbstractButton {
            anchors { left: parent.left; leftMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
            width: units.gu(4); height: width
            onClicked: page.pageStack.pop()
            Icon {
                anchors.centerIn: parent
                width: units.gu(2.5); height: width
                name: "close"
                color: Style.textPrimary
            }
        }

        Label {
            anchors.centerIn: parent
            text: page.isEdit ? Lang.tr("Edit Post") : Lang.tr("Create Post")
            font.pixelSize: Style.fontMedium
            font.weight: Font.DemiBold
            color: Style.textPrimary
        }

        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: units.dp(1); color: Style.divider
        }
    }

    // Where the next picked image goes: cover slot or inline body; one shared picker/uploader serves both.
    property string imageTarget: "cover"

    function pickCoverImage() {
        page.imageTarget = "cover";
        Popups.PopupUtils.open(pickerComp);
    }
    function pickBodyImage() {
        // Force the keyboard to commit any word still mid-composition (predictive text only lands in
        // the field's real .text at a word boundary) before this segment loses focus to the picker,
        // else that text never makes it into partData.html and gets lost when the image lands.
        Qt.inputMethod.commit();
        page.imageTarget = "body";
        Popups.PopupUtils.open(pickerComp);
    }

    Component {
        id: pickerComp
        PhotoPicker {
            onPicked: imgUploader.upload(fileUrl)
            onCancelled: { /* nothing to do */ }
        }
    }

    // Downscales + uploads the picked image; keeps the spinner honest.
    PhotoUploader {
        id: imgUploader
        onUploadingChanged: page.uploading = uploading
        onUploaded: {
            if (page.imageTarget === "body") {
                page._insertBodyImage(url);
                Toast.success(Lang.tr("Image added"));
            } else {
                page.coverImageUrl = url;
                Toast.success(Lang.tr("Cover image uploaded"));
            }
        }
        onFailed: Toast.error(message)
    }

    // Inserts a new image block right after the currently-focused text segment (splitting mid-paragraph
    // would need real HTML document surgery QML doesn't expose, so images land as their own block instead,
    // same as most block-based editors). Always leaves a fresh empty text segment after it to keep typing in.
    function _insertBodyImage(url) {
        Qt.inputMethod.commit();
        var parts = page.bodyParts.slice();
        var afterIdx = page.activeTextIndex;
        if (afterIdx < 0 || afterIdx >= parts.length || parts[afterIdx].type !== "text")
            afterIdx = parts.length - 1;
        // Belt and braces: pull the segment's true current text straight off its live TextArea rather
        // than trusting partData.html, in case onTextChanged hasn't caught up with the commit above yet.
        var activeLoader = bodyRepeater.itemAt(afterIdx);
        if (activeLoader && activeLoader.item)
            parts[afterIdx] = { type: "text", html: activeLoader.item.text };
        parts.splice(afterIdx + 1, 0, { type: "image", url: url }, { type: "text", html: "" });
        page.bodyParts = parts;
        page.activeTextIndex = afterIdx + 2;
        page._pendingFocusIndex = afterIdx + 2;
        page._bodyRev++;
    }

    // Removes one image block; if that leaves two text segments touching, merges them into one
    // so the user isn't left staring at a pointless split.
    function _removeBodyPart(idx) {
        Qt.inputMethod.commit();
        // Pull every segment's true current text off its live TextArea first, else any segment still
        // mid-composition (or just not yet caught by onTextChanged) reverts to its stale array copy.
        var parts = page.bodyParts.map(function (p, i) {
            if (p.type !== "text") return p;
            var l = bodyRepeater.itemAt(i);
            return (l && l.item) ? { type: "text", html: l.item.text } : p;
        });
        parts.splice(idx, 1);
        if (idx > 0 && idx < parts.length && parts[idx - 1].type === "text" && parts[idx].type === "text") {
            parts[idx - 1] = { type: "text", html: parts[idx - 1].html + parts[idx].html };
            parts.splice(idx, 1);
        }
        if (parts.length === 0) parts = [{ type: "text", html: "" }];
        page.bodyParts = parts;
        page.activeTextIndex = Math.min(page.activeTextIndex, parts.length - 1);
        page._bodyRev++;
    }

    // The only tags an article body may publish. Everything else Qt's serializer emits is layout
    // scaffolding for the editor, not content.
    readonly property var _allowedBodyTags: ({
        p: 1, br: 1, b: 1, strong: 1, i: 1, em: 1, u: 1, s: 1,
        a: 1, ul: 1, ol: 1, li: 1, blockquote: 1, img: 1,
        h1: 1, h2: 1, h3: 1
    })

    // Qt's RichText re-serializes formatting as style spans; collapse back to <b>/<i>/<s> tags
    function _richHtmlToSimple(html) {
        var t = html || "";
        var bodyMatch = t.match(/<body[^>]*>([\s\S]*)<\/body>/i);
        if (bodyMatch) t = bodyMatch[1];
        t = t.replace(/<!DOCTYPE[^>]*>/gi, "").replace(/<\/?html[^>]*>/gi, "")
             .replace(/<head>[\s\S]*?<\/head>/gi, "");
        // One pass per span so combined styles (e.g. bold+underline) collapse into nested tags
        // instead of needing every attribute to line up with a separate regex.
        t = t.replace(/<span([^>]*)>([\s\S]*?)<\/span>/gi, function (m, attrs, inner) {
            var styleMatch = attrs.match(/style="([^"]*)"/i);
            var style = styleMatch ? styleMatch[1] : "";
            var open = "", close = "";
            if (/font-weight:\s*(?:[6-9]00|bold)/i.test(style)) { open += "<b>"; close = "</b>" + close; }
            if (/font-style:\s*italic/i.test(style)) { open += "<i>"; close = "</i>" + close; }
            if (/text-decoration[^:]*:[^;"]*underline/i.test(style)) { open += "<u>"; close = "</u>" + close; }
            if (/text-decoration[^:]*:[^;"]*line-through/i.test(style)) { open += "<s>"; close = "</s>" + close; }
            return open.length > 0 ? open + inner + close : m;
        });
        // Qt's export is a full HTML document whose every tag carries the editor's own runtime font
        // (font-size in pt, font-family, -qt-* hints). On the web those inline styles beat the article
        // CSS and the post renders far bigger than the surrounding text. Chasing each declaration is a
        // losing game across Qt versions, so keep only the tags an article needs and drop every
        // attribute but a link's href and an image's src.
        t = t.replace(/<(\/?)([a-zA-Z0-9]+)([^>]*)>/g, function (m, slash, tag, attrs) {
            var name = tag.toLowerCase();
            if (!page._allowedBodyTags[name]) return "";
            if (slash.length > 0) return "</" + name + ">";
            if (name === "br") return "<br/>";
            if (name === "a") {
                var href = attrs.match(/href=["']([^"']*)["']/i);
                return href ? '<a href="' + href[1] + '">' : "";
            }
            if (name === "img") {
                var src = attrs.match(/src=["']([^"']*)["']/i);
                return src ? '<img src="' + src[1] + '" style="max-width:100%;height:auto;" />' : "";
            }
            return "<" + name + ">";
        });
        // Qt writes a paragraph per blank line; a run of them is a gap the web renders at its own
        // (much larger) paragraph spacing, so collapse each run to a single break.
        t = t.replace(/(?:<p>(?:\s|<br\/>|&nbsp;)*<\/p>\s*){2,}/gi, "<p></p>");
        return t;
    }

    // Strips doctype/html/head, keeps body fragment only
    function _bodyFragment(html) {
        var t = html || "";
        var bodyMatch = t.match(/<body[^>]*>([\s\S]*)<\/body>/i);
        if (bodyMatch) t = bodyMatch[1];
        return t.replace(/<!DOCTYPE[^>]*>/gi, "").replace(/<\/?html[^>]*>/gi, "")
                .replace(/<head>[\s\S]*?<\/head>/gi, "");
    }

    // Wraps bare pasted URLs in <a>; whitelisted TLDs avoid linkifying "e.g." or "Mr. Smith"
    function _autoLinkify(html) {
        // "co" dropped: prefix of "com", would link early mid-word
        var tlds = "com|net|org|io|gov|edu|info|biz|dev|app|me|tv|xyz|ai|to|gg|link|shop";
        var urlBody = "https?://[^\\s<]+|www\\.[^\\s<]+"
            + "|\\b[a-z0-9-]+(?:\\.[a-z0-9-]+)*\\.(?:" + tlds + ")(?:\\.[a-z]{2,3})?(?:/[^\\s<]*)?\\b";
        var urlRe = new RegExp("(" + urlBody + ")", "gi");
        var fullUrlRe = new RegExp("^(?:" + urlBody + ")$", "i");
        var parts = page._bodyFragment(html).split(/(<a\b[^>]*>[\s\S]*?<\/a>)/gi);
        for (var i = 0; i < parts.length; i++) {
            var aMatch = parts[i].match(/^<a\b[^>]*>([\s\S]*)<\/a>$/i);
            if (aMatch) {
                // re-sync href to current text; unwrap if no longer a URL
                var inner = aMatch[1];
                if (fullUrlRe.test(inner)) {
                    var innerHref = /^https?:\/\//i.test(inner) ? inner : "https://" + inner;
                    parts[i] = '<a href="' + innerHref + '">' + inner + '</a>';
                } else {
                    parts[i] = inner;
                }
                continue;
            }
            parts[i] = parts[i].replace(urlRe, function (m) {
                var href = /^https?:\/\//i.test(m) ? m : "https://" + m;
                return '<a href="' + href + '">' + m + '</a>';
            });
        }
        return parts.join("");
    }

    function publish() {
        if (!Session.isLoggedIn) {
            Toast.error(Lang.tr("Please log in first."));
            return;
        }
        // Assemble the body from its text/image blocks; pull each text segment's live content off
        // its actual delegate rather than the (possibly stale) bodyParts copy.
        var body = "";
        for (var i = 0; i < page.bodyParts.length; i++) {
            var part = page.bodyParts[i];
            if (part.type === "image") {
                body += '<img src="' + part.url + '" style="max-width:100%;height:auto;" />';
            } else if (part.type === "embed") {
                // Matches PostDetailPage's embed detection
                body += '<p><a href="' + part.url + '">' + part.url + '</a></p>';
            } else {
                var loader = bodyRepeater.itemAt(i);
                var html = loader && loader.item ? loader.item.text : (part.html || "");
                body += page._richHtmlToSimple(html);
            }
        }
        body = body.trim();
        // Cover image is NOT prepended into the body: it's sent below via `images`, which is what
        // both the API/web thumbnail and PostDetailPage's own cover frame derive from. Baking it
        // into the body too just duplicated it inline above the article text.
        page.submitting = true;
        PostService.createPost(Config.baseUrl, {
            title: titleField.text.trim(),
            body: body,
            communityId: page.postCommunityId,
            communityName: page.isEdit ? (page.editPost.community || Config.communityName)
                                       : page.postCommunityName,
            categories: page.selectedCategory || "general",
            subcategories: page.selectedSubCategory.length > 0 ? [page.selectedSubCategory] : [],
            postToBlockchain: page.postToBlockchain,
            permlink: page.isEdit ? (page.editPost.permlink || "") : "",
            // Also send in `images` (json_meta.image) since the web derives the card thumbnail from that field, not from the body <img>.
            images: page.coverImageUrl.length > 0 ? [page.coverImageUrl] : []
        }, Session.token,
        function (data) {
            page.submitting = false;
            Toast.success(page.isEdit ? Lang.tr("Post updated!") : Lang.tr("Post published!"));
            page.saved(!page.isEdit);
            page.pageStack.pop();
        },
        function (err) {
            page.submitting = false;
            Toast.error((err && err.message) ? err.message
                                             : (page.isEdit ? Lang.tr("Couldn't update post.")
                                                            : Lang.tr("Couldn't publish post.")));
        });
    }

    // The Loader delegate for the focused text segment; .item is the actual TextArea.
    function _activeTextArea() {
        var loader = bodyRepeater.itemAt(page.activeTextIndex);
        return loader ? loader.item : null;
    }

    // Requires a selection: plain TextEdit has no "current format" state to toggle
    function wrapSelection(tagOpen, tagClose) {
        var ta = page._activeTextArea();
        if (!ta) return;
        var start = ta.selectionStart;
        var end = ta.selectionEnd;
        if (start === end) {
            Toast.show(Lang.tr("Select some text first"));
            return;
        }
        var sel = ta.selectedText;
        ta.remove(start, end);
        ta.insert(start, tagOpen + sel + tagClose);
        ta.forceActiveFocus();
    }

    property string _pendingLinkText: ""
    property string _pendingLinkHref: ""
    property int _pendingLinkStart: 0
    property int _pendingLinkEnd: 0

    // Prefill dialog with existing href, if any
    function _existingHrefFor(html, selectedText) {
        if (!selectedText) return "";
        var esc = selectedText.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        var re = new RegExp('<a\\s+[^>]*href="([^"]*)"[^>]*>\\s*' + esc + '\\s*</a>', "i");
        var m = re.exec(html || "");
        return m ? m[1] : "";
    }

    function promptLink() {
        var ta = page._activeTextArea();
        if (!ta || ta.selectionStart === ta.selectionEnd) {
            Toast.show(Lang.tr("Select some text first"));
            return;
        }
        page._pendingLinkText = ta.selectedText;
        page._pendingLinkStart = ta.selectionStart;
        page._pendingLinkEnd = ta.selectionEnd;
        page._pendingLinkHref = page._existingHrefFor(ta.text, ta.selectedText);
        Popups.PopupUtils.open(linkDialog);
    }

    function applyLink(url) {
        // The field is seeded with the scheme, so an untouched dialog reads as "https://", not empty.
        if (url.length === 0 || /^https?:\/\/$/i.test(url)) return;
        var ta = page._activeTextArea();
        if (!ta) return;
        ta.remove(page._pendingLinkStart, page._pendingLinkEnd);
        ta.insert(page._pendingLinkStart, '<a href="' + url + '">' + page._pendingLinkText + '</a>');
        ta.forceActiveFocus();
    }

    // Same providers the article reader knows how to render as a live player.
    function _isEmbeddableVideoUrl(url) {
        return /(?:youtube\.com\/(?:watch\?|embed\/|shorts\/)|youtu\.be\/)/i.test(url || "");
    }

    function promptEmbed() {
        Popups.PopupUtils.open(embedDialog);
    }

    function applyEmbed(url) {
        if (url.length === 0) return;
        if (!page._isEmbeddableVideoUrl(url)) {
            Toast.error(Lang.tr("Paste a YouTube link to embed a video."));
            return;
        }
        page._insertBodyEmbed(url);
    }

    // Same shape as _insertBodyImage
    function _insertBodyEmbed(url) {
        Qt.inputMethod.commit();
        var parts = page.bodyParts.slice();
        var afterIdx = page.activeTextIndex;
        if (afterIdx < 0 || afterIdx >= parts.length || parts[afterIdx].type !== "text")
            afterIdx = parts.length - 1;
        var activeLoader = bodyRepeater.itemAt(afterIdx);
        if (activeLoader && activeLoader.item)
            parts[afterIdx] = { type: "text", html: activeLoader.item.text };
        parts.splice(afterIdx + 1, 0, { type: "embed", url: url }, { type: "text", html: "" });
        page.bodyParts = parts;
        page.activeTextIndex = afterIdx + 2;
        page._pendingFocusIndex = afterIdx + 2;
        page._bodyRev++;
    }

    Component {
        id: embedDialog
        Popups.Dialog {
            id: edlg
            title: Lang.tr("Embed video")
            TextField {
                id: embedUrlField
                placeholderText: "https://www.youtube.com/watch?v=…"
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoPredictiveText
                // Needed for paste to work
                Component.onCompleted: embedUrlField.forceActiveFocus()
            }
            Button {
                text: Lang.tr("Insert")
                color: Style.brand
                onClicked: { Popups.PopupUtils.close(edlg); page.applyEmbed(embedUrlField.text.trim()); }
            }
            Button {
                text: Lang.tr("Cancel")
                onClicked: Popups.PopupUtils.close(edlg)
            }
        }
    }

    Component {
        id: linkDialog
        Popups.Dialog {
            id: ldlg
            title: Lang.tr("Add link")
            TextField {
                id: linkUrlField
                text: page._pendingLinkHref
                placeholderText: "https://"
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoPredictiveText
                Component.onCompleted: {
                    // Real text rather than a placeholder, with the caret after it, so typing carries
                    // on from the scheme. Still ordinary text: it can be selected or cleared as usual.
                    if (linkUrlField.text.length === 0)
                        linkUrlField.text = "https://";
                    linkUrlField.cursorPosition = linkUrlField.text.length;
                    linkUrlField.forceActiveFocus();
                }
            }
            Button {
                text: Lang.tr("Insert")
                color: Style.brand
                onClicked: { Popups.PopupUtils.close(ldlg); page.applyLink(linkUrlField.text.trim()); }
            }
            Button {
                text: Lang.tr("Cancel")
                onClicked: Popups.PopupUtils.close(ldlg)
            }
        }
    }

    // Move active focus onto a neutral item so the on-screen keyboard drops on tapping any empty area of the form.
    Item { id: focusSink }
    function dismissKeyboard() {
        focusSink.forceActiveFocus();
        Qt.inputMethod.hide();
    }

    Flickable {
        id: scroll
        anchors { top: hdr.bottom; bottom: Config.wideMode ? parent.bottom : toolbar.top; horizontalCenter: parent.horizontalCenter }
        width: Math.min(parent.width, page.maxContentWidth)
        contentHeight: col.height + Style.spacingL
        clip: true
        opacity: 0
        NumberAnimation on opacity { from: 0; to: 1; duration: 250; easing.type: Easing.OutQuad }

        // Sits behind the form (z -1); taps that miss a field dismiss the keyboard, while a tap still flicks since Flickable steals drag gestures.
        MouseArea {
            width: scroll.width
            height: Math.max(scroll.height, col.height + Style.spacingL)
            z: -1
            onClicked: page.dismissKeyboard()
        }

        Column {
            id: col
            width: parent.width - Style.spacingM * 2
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.spacingM

            Item { width: 1; height: Style.spacingS }

            Rectangle {
                width: parent.width
                height: titleField.height + Style.spacingM * 2 + counterLabel.height + Style.spacingXs
                radius: Style.cardRadius
                color: "transparent"
                border.width: units.dp(1.5)
                border.color: titleField.activeFocus ? Style.brand : Style.divider

                // Declared FIRST so it sits under the input, catching taps in the dead space
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        titleField.forceActiveFocus();
                        titleField.cursorPosition = titleField.length;
                        Qt.inputMethod.show();
                    }
                }

                // Lomiri TextField (not plain TextInput): only the styled component wires up native long-press selection + Cut/Copy/Paste.
                TextField {
                    id: titleField
                    anchors {
                        top: parent.top; topMargin: Style.spacingM
                        left: parent.left; right: parent.right
                        leftMargin: Style.spacingM; rightMargin: Style.spacingM
                    }
                    font.pixelSize: Style.fontMedium
                    font.family: Style.fontFor(text)
                    color: Style.textPrimary
                    clip: true
                    maximumLength: page.titleMaxLength
                    hasClearButton: false
                    StyleHints {
                        backgroundColor: "transparent"
                        borderColor: "transparent"
                        frameSpacing: 0
                        overlaySpacing: 0
                    }
                }

                Label {
                    anchors {
                        left: parent.left; top: parent.top
                        leftMargin: Style.spacingM; topMargin: Style.spacingM
                    }
                    visible: titleField.text.length === 0 && !titleField.activeFocus && !Qt.inputMethod.visible
                    text: Lang.tr("Enter title")
                    color: Style.textSecondary
                    font.pixelSize: Style.fontMedium
                    font.family: Style.fontFor(text)
                }

                Label {
                    id: counterLabel
                    anchors {
                        right: parent.right; bottom: parent.bottom
                        rightMargin: Style.spacingM; bottomMargin: Style.spacingS
                    }
                    text: titleField.text.length + "/" + page.titleMaxLength
                    font.pixelSize: Style.fontXSmall
                    color: titleField.text.length >= page.titleMaxLength ? Style.danger : Style.textSecondary
                }
            }

            // Body: a bordered box holding a stack of text segments and real inline Image blocks
            // (toolbar docks inside on desktop, above OSK on phone).
            Rectangle {
                id: bodyBox
                readonly property real toolbarH: Config.wideMode ? units.gu(5.5) : 0
                width: parent.width
                height: Math.max(units.gu(25), partsCol.height + Style.spacingM * 2) + toolbarH
                radius: Style.cardRadius
                color: "transparent"
                clip: true
                border.width: units.dp(1.5)
                border.color: page.bodyFocused ? Style.brand : Style.divider

                // Same as the title: declared FIRST so it catches taps below the content, focusing
                // the last segment (always text, by construction: every image insert appends a fresh one).
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        var loader = bodyRepeater.itemAt(page.bodyParts.length - 1);
                        var ta = loader ? loader.item : null;
                        if (ta) { ta.forceActiveFocus(); ta.cursorPosition = ta.length; }
                        Qt.inputMethod.show();
                    }
                }

                Column {
                    id: partsCol
                    x: Style.spacingM; y: Style.spacingM
                    width: parent.width - Style.spacingM * 2
                    spacing: Style.spacingS

                    Repeater {
                        id: bodyRepeater
                        model: page.bodyParts
                        delegate: Loader {
                            width: partsCol.width
                            property var partData: modelData
                            property int partIndex: index
                            sourceComponent: partData.type === "image" ? bodyImagePartComp
                                            : partData.type === "embed" ? bodyEmbedPartComp
                                            : bodyTextPartComp
                            onLoaded: {
                                if (partIndex === page._pendingFocusIndex) {
                                    item.forceActiveFocus();
                                    item.cursorPosition = item.length;
                                    page._pendingFocusIndex = -1;
                                }
                            }
                        }
                    }
                }

                Label {
                    anchors {
                        left: parent.left; top: parent.top
                        leftMargin: Style.spacingM; topMargin: Style.spacingM
                    }
                    visible: page.bodyParts.length === 1 && page._bodyRev >= 0 && !page._bodyHasContent()
                             && !page.bodyFocused && !Qt.inputMethod.visible
                    text: Lang.tr("Write your article here...")
                    color: Style.textSecondary
                    font.pixelSize: Style.fontRegular
                    font.family: Style.fontFor(text)
                }

                Rectangle {
                    visible: Config.wideMode
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: bodyBox.toolbarH
                    color: Style.iconBackground

                    Rectangle {
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        height: units.dp(1); color: Style.divider
                    }

                    Loader {
                        anchors { left: parent.left; leftMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
                        sourceComponent: parent.visible ? formatButtonsComp : undefined
                    }
                }
            }

            // One editable rich-text segment. Lomiri TextArea (not plain TextEdit): only the styled
            // component wires up native long-press selection + Cut/Copy/Paste.
            Component {
                id: bodyTextPartComp
                TextArea {
                    id: partArea
                    textFormat: Text.RichText
                    selectByMouse: true
                    persistentSelection: true
                    selectionColor: Style.brand
                    font.family: Style.fontFor(text)
                    font.pixelSize: Style.fontRegular
                    color: Style.textPrimary
                    // Wrap (not WordWrap): a run with no spaces (URL, pasted blob) must still break instead of overflowing the box.
                    wrapMode: Text.Wrap
                    // Auto-expand to fit content; the Column sizes off each segment's real height.
                    autoSize: true
                    maximumLineCount: 0
                    Component.onCompleted: { text = partData.html; partArea._prevText = text; Qt.callLater(_fitHeight); }
                    property string _prevText: ""
                    property bool _linkifyBusy: false
                    Timer {
                        id: linkifyTimer
                        interval: 500
                        onTriggered: partArea._autoLinkifyPasted()
                    }
                    function _autoLinkifyPasted() {
                        // skip while IME is mid-word
                        if (partArea.inputMethodComposing) return;
                        var oldFragment = page._bodyFragment(text);
                        var linked = page._autoLinkify(text);
                        if (linked === oldFragment) return;
                        // cursorPosition is a plain-text offset; linkifying only adds markup, not visible chars.
                        var cp = cursorPosition;
                        partArea._linkifyBusy = true;
                        text = linked;
                        cursorPosition = Math.min(cp, text.length);
                        partArea._prevText = text;
                        partArea._linkifyBusy = false;
                    }
                    // autoSize's internal line-count estimate under-measures wrapped/rich text, leaving the
                    // editor's own height too short so its inner Flickable scrolls instead of the box growing.
                    // Force it to the true painted height, same fix as the read-only article body.
                    onPaintedHeightChanged: Qt.callLater(_fitHeight)
                    onLineCountChanged: Qt.callLater(_fitHeight)
                    onCursorPositionChanged: Qt.callLater(_fitHeight)
                    function _fitHeight() {
                        if (height < paintedHeight) height = paintedHeight;
                        // Lomiri's own InputHandler scrolls the internal Flickable to keep the caret
                        // visible using the height *before* the grow above lands, and never scrolls it
                        // back — leaving text pushed up out of view with dead space below it. Since this
                        // segment always grows to fit (never scrolls internally), force that back to 0.
                        if (__rightScrollbar && __rightScrollbar.flickableItem)
                            __rightScrollbar.flickableItem.contentY = 0;
                    }
                    // Write through partIndex, NOT partData.html: a JS-array model hands the delegate a
                    // QVariantMap *copy*, so mutating partData never reaches page.bodyParts and the text
                    // is lost the moment the Repeater rebuilds (e.g. when an image is inserted).
                    onTextChanged: {
                        page._setPartHtml(partIndex, text);
                        if (!partArea._linkifyBusy) {
                            linkifyTimer.restart();
                            partArea._prevText = text;
                        }
                    }
                    onActiveFocusChanged: {
                        if (activeFocus) { page.activeTextIndex = partIndex; page.bodyFocused = true; }
                        else Qt.callLater(function () { page.bodyFocused = page._anyBodyPartFocused(); });
                    }
                    StyleHints {
                        backgroundColor: "transparent"
                        borderColor: "transparent"
                        frameSpacing: 0
                        overlaySpacing: 0
                    }
                }
            }

            // One inline image block: a real, fully rendered image, not a "[image N]" placeholder.
            Component {
                id: bodyImagePartComp
                Item {
                    width: parent.width
                    height: img.height

                    Image {
                        id: img
                        width: parent.width
                        fillMode: Image.PreserveAspectFit
                        source: partData.url
                        asynchronous: true
                        autoTransform: true
                        height: (status === Image.Ready && implicitWidth > 0)
                                ? width * implicitHeight / implicitWidth
                                : units.gu(20)

                        Rectangle {
                            anchors.fill: parent
                            radius: Style.thumbRadius
                            color: Style.iconBackground
                            visible: parent.status !== Image.Ready
                            z: -1
                        }
                    }

                    AbstractButton {
                        anchors { top: parent.top; right: parent.right; margins: units.dp(6) }
                        width: units.gu(3.2); height: width
                        onClicked: page._removeBodyPart(partIndex)
                        Rectangle { anchors.fill: parent; radius: width / 2; color: Qt.rgba(0, 0, 0, 0.55) }
                        Icon { anchors.centerIn: parent; width: units.gu(2); height: width; name: "close"; color: "white" }
                    }
                }
            }

            // One inline video embed block: live preview, same player the article reader shows.
            Component {
                id: bodyEmbedPartComp
                Rectangle {
                    width: parent.width
                    height: width * 9 / 16
                    radius: Style.thumbRadius
                    color: "black"
                    clip: true

                    VideoWebView {
                        anchors.fill: parent
                        wrap: true
                        embedUrl: partData.url
                    }

                    AbstractButton {
                        anchors { top: parent.top; right: parent.right; margins: units.dp(6) }
                        width: units.gu(3.2); height: width
                        onClicked: page._removeBodyPart(partIndex)
                        Rectangle { anchors.fill: parent; radius: width / 2; color: Qt.rgba(0, 0, 0, 0.55) }
                        Icon { anchors.centerIn: parent; width: units.gu(2); height: width; name: "close"; color: "white" }
                    }
                }
            }

            // Editing keeps the post where it is, so name the platform it lives in: the categories
            // below come from it, and there is nothing else on this page that says so.
            Item {
                width: parent.width
                height: units.gu(6)
                visible: page.isEdit && page.catCommunityName.length > 0

                Rectangle {
                    anchors.fill: parent
                    radius: Style.cardRadius
                    color: Style.iconBackground
                }
                Label {
                    id: editCommunityCaption
                    anchors { left: parent.left; leftMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                    text: Lang.tr("Platform")
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                }
                // Logo and name read as one unit, so they stay together at the end of the row
                // rather than the logo drifting into the gap after the caption.
                Row {
                    anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                    spacing: Style.spacingXs
                    readonly property real avail: parent.width - Style.spacingM * 2
                                                  - editCommunityCaption.width - Style.spacingS

                    Item {
                        id: editCommunityLogo
                        anchors.verticalCenter: parent.verticalCenter
                        width: visible ? units.gu(3) : 0
                        height: width
                        visible: page.editCommunityIcon.length > 0

                        CircleImage {
                            anchors.fill: parent
                            source: page.editCommunityIcon
                        }
                        // Same hairline ring as the header pill, so a pale logo keeps its edge.
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"
                            border.width: units.dp(1)
                            border.color: Style.divider
                        }
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth,
                                        parent.avail - editCommunityLogo.width - parent.spacing)
                        elide: Text.ElideRight
                        text: page.catCommunityName
                        font.pixelSize: Style.fontRegular
                        font.weight: Font.DemiBold
                        font.family: Style.fontFor(text)
                        color: Style.textPrimary
                    }
                }
            }

            // Category selector hidden for communities that haven't defined any categories yet (publish() falls back to "general").
            AbstractButton {
                width: parent.width
                height: units.gu(6)
                visible: page.categories.length > 0
                onClicked: page.catSheetOpen = true

                Rectangle {
                    anchors.fill: parent
                    radius: Style.cardRadius
                    color: "transparent"
                    border.width: units.dp(1.5)
                    border.color: Style.divider
                }

                Row {
                    anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }

                    Label {
                        width: parent.width - catChevron.width
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.selectedCategory.length > 0
                            ? (page.selectedSubCategory.length > 0
                               ? (page.selectedCategory + "  ›  " + page.selectedSubCategory)
                               : page.selectedCategory)
                            : Lang.tr("Select category")
                        font.pixelSize: Style.fontRegular
                        font.family: Style.fontFor(text)
                        color: page.selectedCategory.length > 0 ? Style.textPrimary : Style.textSecondary
                    }
                    Icon {
                        id: catChevron
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(2); height: width
                        name: "next"
                        color: Style.textSecondary
                    }
                }
            }

            // Bare row, no card: the toggle reads as a form setting rather than a section.
            Item {
                width: parent.width
                height: chainRow.implicitHeight

                Row {
                    id: chainRow
                    anchors { left: parent.left; right: parent.right }
                    spacing: Style.spacingM

                    Column {
                        width: parent.width - chainSwitch.width - Style.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: units.dp(2)

                        Label {
                            text: Lang.tr("Post on the blockchain")
                            font.pixelSize: Style.fontRegular
                            font.weight: Font.DemiBold
                            font.family: Style.fontFor(text)
                            color: Style.textPrimary
                        }
                        Label {
                            width: parent.width
                            text: page.postToBlockchain ? Lang.tr("Can earn votes and rewards.")
                                                        : Lang.tr("Serey only, no votes or rewards.")
                            font.pixelSize: Style.fontXSmall
                            font.family: Style.fontFor(text)
                            color: Style.textSecondary
                            wrapMode: Text.WordWrap
                        }
                    }

                    Switch {
                        id: chainSwitch
                        anchors.verticalCenter: parent.verticalCenter
                        checked: page.postToBlockchain
                        onClicked: page.postToBlockchain = !page.postToBlockchain
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: units.gu(20)
                radius: Style.thumbRadius
                // Outlined while empty, filled once an image sits behind it.
                color: page.coverImageUrl.length > 0 ? Style.iconBackground : "transparent"
                border.width: page.coverImageUrl.length > 0 ? 0 : units.dp(1.5)
                border.color: Style.divider
                clip: true

                Image {
                    anchors.fill: parent
                    source: page.coverImageUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    autoTransform: true     // honour EXIF orientation
                    visible: page.coverImageUrl.length > 0
                }

                AbstractButton {
                    visible: page.coverImageUrl.length > 0
                    anchors {
                        top: parent.top; right: parent.right
                        topMargin: Style.spacingS; rightMargin: Style.spacingS
                    }
                    width: units.gu(4); height: width
                    z: 2
                    onClicked: page.coverImageUrl = ""

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Qt.rgba(0, 0, 0, 0.5)
                    }
                    Icon {
                        anchors.centerIn: parent
                        width: units.gu(2); height: width
                        name: "close"
                        color: Style.textOnBrand
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(1, 1, 1, 0.7)
                    visible: page.uploading

                    ActivityIndicator {
                        anchors.centerIn: parent
                        running: page.uploading
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: Style.spacingS
                    visible: page.coverImageUrl.length === 0 && !page.uploading

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: units.gu(5); height: width
                        radius: width / 2
                        color: Style.iconBackground

                        Icon {
                            anchors.centerIn: parent
                            width: units.gu(2.5); height: width
                            name: "add"
                            color: Style.textPrimary
                        }
                    }

                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Lang.tr("Add thumbnail")
                        font.pixelSize: Style.fontSmall
                        color: Style.textSecondary
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !page.uploading && page.coverImageUrl.length === 0
                    onClicked: page.pickCoverImage()
                }
            }

            PrimaryButton {
                width: parent.width
                enabled: page.canPublish
                busy: page.submitting
                text: page.submitting ? (page.isEdit ? Lang.tr("Saving…") : Lang.tr("Posting…"))
                                      : (page.isEdit ? Lang.tr("Save") : Lang.tr("Publish"))
                onClicked: page.publish()
            }

            Item { width: 1; height: Style.spacingM }
        }
    }

    // Shared formatting-button row, reused by the phone bottom dock and the desktop inline toolbar.
    Component {
        id: formatButtonsComp
        Row {
            spacing: 0

            Repeater {
                model: [
                    { label: "B", tag: "<b>", close: "</b>", bold: true },
                    { label: "I", tag: "<i>", close: "</i>", italic: true },
                    { label: "S", tag: "<s>", close: "</s>", strike: true },
                    { label: "U", tag: "<u>", close: "</u>", underline: true }
                ]

                delegate: AbstractButton {
                    width: units.gu(5); height: units.gu(4.5)
                    onClicked: page.wrapSelection(modelData.tag, modelData.close)

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: units.dp(4)
                        radius: Style.cardRadius
                        color: "transparent"
                        border.width: units.dp(1)
                        border.color: Style.divider
                    }

                    Label {
                        anchors.centerIn: parent
                        text: modelData.label
                        font.pixelSize: Style.fontMedium
                        font.bold: modelData.bold || false
                        font.italic: modelData.italic || false
                        font.strikeout: modelData.strike || false
                        font.underline: modelData.underline || false
                        color: Style.textPrimary
                    }
                }
            }

            AbstractButton {
                width: units.gu(5); height: units.gu(4.5)
                onClicked: page.promptLink()
                Rectangle {
                    anchors.fill: parent; anchors.margins: units.dp(4)
                    radius: Style.cardRadius; color: "transparent"
                    border.width: units.dp(1); border.color: Style.divider
                }
                Icon {
                    anchors.centerIn: parent
                    width: units.gu(2.2); height: width
                    name: "stock_link"
                    color: Style.textPrimary
                }
            }

            AbstractButton {
                width: units.gu(5); height: units.gu(4.5)
                onClicked: page.promptEmbed()
                Rectangle {
                    anchors.fill: parent; anchors.margins: units.dp(4)
                    radius: Style.cardRadius; color: "transparent"
                    border.width: units.dp(1); border.color: Style.divider
                }
                Icon {
                    anchors.centerIn: parent
                    width: units.gu(2.2); height: width
                    name: "media-playback-start"
                    color: Style.textPrimary
                }
            }

            AbstractButton {
                width: units.gu(5); height: units.gu(4.5)
                onClicked: page.pickBodyImage()
                Rectangle {
                    anchors.fill: parent; anchors.margins: units.dp(4)
                    radius: Style.cardRadius; color: "transparent"
                    border.width: units.dp(1); border.color: Style.divider
                }
                Icon {
                    anchors.centerIn: parent
                    width: units.gu(2.2); height: width
                    name: "image-x-generic-symbolic"
                    color: Style.textPrimary
                }
            }
        }
    }

    // Phone: docked above the OSK. Desktop has no OSK; an inline copy sits under the body field
    Rectangle {
        id: toolbar
        visible: !Config.wideMode
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.bottomMargin: page.kbHeight
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
        height: units.gu(5.5)
        color: Style.surface

        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: units.dp(1); color: Style.divider
        }

        Loader {
            anchors { left: parent.left; leftMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
            sourceComponent: toolbar.visible ? formatButtonsComp : undefined
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(1, 1, 1, 0.7)
        visible: page.submitting
        z: 100
        ActivityIndicator { anchors.centerIn: parent; running: page.submitting }
    }

    // --- Category picker bottom sheet ----------------------------------------
    Item {
        id: catSheet
        anchors.fill: parent
        visible: page.catSheetOpen
        z: 200
        onVisibleChanged: if (visible) { catBdFade.start(); catSlideAnim.start(); }
        function closeAnimated() { catBdFadeOut.start(); catSlideOut.start(); }

        Rectangle {
            id: catBd
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.4)
            opacity: 0
            MouseArea { anchors.fill: parent; onClicked: catSheet.closeAnimated() }
        }
        NumberAnimation { id: catBdFade; target: catBd; property: "opacity"; from: 0; to: 1; duration: 200 }
        NumberAnimation { id: catBdFadeOut; target: catBd; property: "opacity"; to: 0; duration: 200 }

        Rectangle {
            id: catSheetRect
            // Full-width sheet on phone, centered width-capped card on desktop
            readonly property bool wide: Config.wideMode
            // Centered + explicit width avoids mixing left/right/horizontalCenter, which QML warns on
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: catSheetRect.wide ? units.gu(4) : 0
            }
            width: catSheetRect.wide ? Math.min(parent.width - units.gu(4), units.gu(45)) : parent.width
            height: catSheetCol.height + units.gu(4)
            radius: units.gu(1)
            color: Style.surface
            transform: Translate { id: catSlideT; y: 0 }
            NumberAnimation { id: catSlideAnim; target: catSlideT; property: "y"; from: catSheetRect.height; to: 0; duration: 300; easing.type: Easing.OutCubic }
            NumberAnimation { id: catSlideOut; target: catSlideT; property: "y"; to: catSheetRect.height; duration: 250; easing.type: Easing.InCubic; onStopped: page.catSheetOpen = false }

            Rectangle {
                anchors { top: parent.top; topMargin: Style.spacingS; horizontalCenter: parent.horizontalCenter }
                width: units.gu(4.5); height: units.dp(4); radius: units.dp(2)
                color: Style.lightGray
            }

            Column {
                id: catSheetCol
                anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: Style.spacingL }
                spacing: 0

                Item {
                    width: parent.width; height: units.gu(5)
                    Label {
                        anchors.centerIn: parent
                        text: Lang.tr("Select Category")
                        font.pixelSize: Style.fontMedium
                        font.weight: Font.DemiBold
                        color: Style.textPrimary
                    }
                    AbstractButton {
                        anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                        width: units.gu(3.5); height: units.gu(3.5)
                        onClicked: catSheet.closeAnimated()
                        Icon { anchors.centerIn: parent; width: units.gu(2.2); height: width; name: "close"; color: Style.textPrimary }
                    }
                }

                Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

                // Scrollable list: caps sheet height so long sub-category lists scroll, not overflow
                Flickable {
                    id: catListFlick
                    width: parent.width
                    height: Math.min(catListCol.height, catSheet.height * 0.65)
                    contentHeight: catListCol.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: catListCol
                        width: parent.width
                        spacing: 0

                // Loading / empty state while categories fetch for this community.
                Item {
                    width: parent.width
                    height: units.gu(8)
                    visible: page.categories.length === 0
                    ActivityIndicator {
                        anchors.centerIn: parent
                        running: page.categoriesLoading
                        visible: running
                    }
                    Label {
                        anchors.centerIn: parent
                        visible: !page.categoriesLoading
                        text: Lang.tr("No categories for this platform")
                        font.pixelSize: Style.fontSmall
                        color: Style.textSecondary
                    }
                }

                Repeater {
                    model: page.categories

                    // Main category + (when expanded via the arrow) its sub-categories.
                    delegate: Column {
                        id: catRow
                        width: catSheetCol.width
                        readonly property string catName: modelData
                        readonly property var subs: {
                            var s = page.subcatsByCat[catName]
                            return (s && s.length) ? s : []
                        }
                        readonly property bool isSelected: page.selectedCategory === catName
                        // Sub list expands on arrow tap, or by default if already-selected category has a sub chosen
                        property bool expanded: catRow.isSelected && page.selectedSubCategory.length > 0

                        // Main row picks the MAIN category and closes; only the arrow expands subs
                        Item {
                            width: parent.width
                            height: units.gu(6)

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    page.selectedCategory = catRow.catName
                                    page.selectedSubCategory = ""
                                    catSheet.closeAnimated()
                                }
                            }
                            Row {
                                anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                                spacing: Style.spacingM
                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - checkIcon.width - (catRow.subs.length > 0 ? subCount.width + Style.spacingM : 0)
                                    text: catRow.catName.charAt(0).toUpperCase() + catRow.catName.slice(1)
                                    elide: Text.ElideRight
                                    font.pixelSize: Style.fontRegular
                                    color: catRow.isSelected ? Style.brand : Style.textPrimary
                                    font.weight: catRow.isSelected ? Font.DemiBold : Font.Normal
                                }
                                Label {
                                    id: subCount
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: catRow.subs.length > 0
                                    text: catRow.subs.length + ""
                                    font.pixelSize: Style.fontSmall
                                    color: Style.textSecondary
                                }
                                Icon {
                                    id: checkIcon
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(2.5); height: width
                                    name: catRow.subs.length > 0 ? (catRow.expanded ? "go-down" : "go-next") : "tick"
                                    color: catRow.subs.length > 0 ? Style.textSecondary : Style.brand
                                    visible: (catRow.isSelected && page.selectedSubCategory.length === 0) || catRow.subs.length > 0
                                }
                            }
                            // Arrow hit area: expands/collapses the sub list without selecting or closing
                            MouseArea {
                                visible: catRow.subs.length > 0
                                enabled: visible
                                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                                width: units.gu(7)
                                onClicked: catRow.expanded = !catRow.expanded
                            }
                            Rectangle {
                                anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                                height: units.dp(1); color: Style.divider
                            }
                        }

                        // Sub-category rows (indented), shown only when expanded via the arrow.
                        Column {
                            width: parent.width
                            visible: catRow.expanded && catRow.subs.length > 0

                            // "No sub-category": post under the main category only.
                            AbstractButton {
                                width: parent.width
                                height: units.gu(5.5)
                                onClicked: {
                                    page.selectedCategory = catRow.catName
                                    page.selectedSubCategory = ""
                                    catSheet.closeAnimated()
                                }
                                Label {
                                    anchors { left: parent.left; leftMargin: Style.spacingM + units.gu(3); verticalCenter: parent.verticalCenter }
                                    text: Lang.tr("No sub-category")
                                    font.pixelSize: Style.fontSmall
                                    font.italic: true
                                    color: page.selectedSubCategory === "" ? Style.brand : Style.textSecondary
                                }
                                Icon {
                                    anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                                    width: units.gu(2.2); height: width; name: "tick"; color: Style.brand
                                    visible: page.selectedSubCategory === ""
                                }
                            }

                            Repeater {
                                model: catRow.subs
                                delegate: AbstractButton {
                                    width: catRow.width
                                    height: units.gu(5.5)
                                    readonly property string subName: modelData
                                    onClicked: {
                                        page.selectedCategory = catRow.catName
                                        page.selectedSubCategory = subName
                                        catSheet.closeAnimated()
                                    }
                                    Label {
                                        anchors { left: parent.left; leftMargin: Style.spacingM + units.gu(3); right: subTick.left; rightMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
                                        text: subName.charAt(0).toUpperCase() + subName.slice(1)
                                        elide: Text.ElideRight
                                        font.pixelSize: Style.fontRegular
                                        color: page.selectedSubCategory === subName ? Style.brand : Style.textPrimary
                                        font.weight: page.selectedSubCategory === subName ? Font.DemiBold : Font.Normal
                                    }
                                    Icon {
                                        id: subTick
                                        anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                                        width: units.gu(2.2); height: width; name: "tick"; color: Style.brand
                                        visible: page.selectedSubCategory === subName
                                    }
                                }
                            }
                            Rectangle {
                                width: parent.width; height: units.dp(1); color: Style.divider
                            }
                        }
                    }
                }

                        Item { width: 1; height: Style.spacingM }
                    }   // catListCol
                }       // catListFlick
            }
        }
    }
}
