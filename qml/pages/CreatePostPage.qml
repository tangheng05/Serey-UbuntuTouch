import QtQuick 2.7
import QtGraphicalEffects 1.0
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3 as Popups
import "../Theme"
import "../Session"
import "../components"
import "../services/PostService.js" as PostService
import "../services/CategoryService.js" as CategoryService
import "../services/Mappers.js" as Mappers

Page {
    id: page

    property bool submitting: false
    property string selectedCategory: ""
    // Optional sub-category under the selected main category, sent in `subcategories`.
    property string selectedSubCategory: ""
    property bool catSheetOpen: false
    // The category sheet opens at publish time, in one of three modes:
    // "loading" while the AI classifies, "suggested" once it answered, "choose" for the list.
    property string catSheetMode: "choose"
    // True once the AI actually returned a category, so the sheet can offer "Back" to it.
    property bool catSuggested: false
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
    // Publishing scope: the highest community this post may surface under (its
    // ceiling). 0 = no ceiling, i.e. everywhere including the Global feed.
    property int publishCeilingId: 0

    // Options are generated from the target's real ancestor chain, so a platform
    // under a SuperHub under a country gets a row per level with no hard-coded tiers.
    readonly property var scopeOptions: {
        var chain = Config.scopeChainFor(page.postCommunityId);   // nearest-first
        // Labels spell out the full path a post can surface in rather than
        // describing the scope, so the hint carries the explanation instead.
        var opts = [{ "id": 0,
                      "label": Config.scopePath(chain, -1),
                      "hint": Lang.tr("Also shown in the Global feed.") }];
        for (var i = chain.length - 1; i >= 0; i--) {
            var hint = chain[i].isRoot
                ? Lang.tr("Everywhere except the Global feed.")
                : (i === 0 ? Lang.tr("Only people browsing %1.").arg(chain[i].name)
                           : Lang.tr("%1 and the platforms under it.").arg(chain[i].name));
            // Nothing sits below the Global community, so posting straight into it
            // makes the ceiling's path read the same as no ceiling at all. The
            // only difference left is the unscoped feed, which a path can't show.
            var label = Config.scopePath(chain, i);
            if (label === opts[0].label) label = Lang.tr("Not on Global");
            opts.push({ "id": chain[i].id, "label": label, "hint": hint });
        }
        return opts;
    }
    readonly property string scopeLabel: {
        var o = page.scopeOptions;
        for (var i = 0; i < o.length; i++)
            if (o[i].id === page.publishCeilingId) return o[i].label;
        return o.length > 0 ? o[0].label : "";
    }
    // Plain-language line under the row: the label names the choice, this says what it does.
    readonly property string scopeHint: {
        var o = page.scopeOptions;
        for (var i = 0; i < o.length; i++)
            if (o[i].id === page.publishCeilingId) return o[i].hint;
        return "";
    }
    // New posts open on the last choice made for this community; an edit ignores it,
    // since the post's own saved ceiling is what the row must reflect.
    function _applyRememberedScope() {
        if (page.isEdit) return;
        var saved = Session.loadPostScope(page.postCommunityId);
        page.publishCeilingId = (saved === undefined) ? 0 : Number(saved);
    }
    onPostCommunityIdChanged: page._applyRememberedScope()

    function _scopeSheetItems() {
        var items = [];
        var opts = page.scopeOptions;
        for (var i = 0; i < opts.length; i++) {
            (function (id) {
                items.push({ "text": opts[i].label,
                             "iconName": (id === page.publishCeilingId) ? "tick" : "",
                             "onTriggered": function () { page.publishCeilingId = id; } });
            })(opts[i].id);
        }
        return items;
    }

    function _anyBodyPartFocused() {
        for (var i = 0; i < page.bodyParts.length; i++) {
            var l = bodyRepeater.itemAt(i);
            if (l && l.item && l.item.activeFocus) return true;
        }
        return false;
    }

    // Single writer into the real bodyParts array (by index, so it actually persists).
    // True once the author has actually changed the body. A late detail response must
    // not overwrite their typing, so the re-prefill below checks this first.
    property bool _bodyTouched: false
    // Set while prefilling: the segments' onTextChanged fires as they load, which would
    // otherwise read as the author typing.
    property bool _prefilling: false

    function _setPartHtml(idx, html) {
        if (idx < 0 || idx >= page.bodyParts.length) return;
        if (page.bodyParts[idx].type !== "text") return;
        page.bodyParts[idx].html = html;
        if (!page._prefilling) page._bodyTouched = true;
        page._bodyRev++;
    }

    // Body -> alternating text/image blocks, one real Image item per <img>.
    function _prefillBody(post) {
        var b = (post && post.body) || "";
        page._prefilling = true;
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
        page._bodyRev++;

        // `coverImage` is what the post actually stores; `thumbnail` may be a body image the
        // feed derived. Prefilling from the derived one re-published it as a real cover, so
        // an author could never take a cover off: save, reopen, and it was back.
        var stored = (post && post.coverImage !== undefined)
            ? (post.coverImage || "")
            : (post && post.thumbnail) || "";
        var storedIsBodyImage = false;
        for (var pi = 0; pi < parts.length; pi++) {
            if (parts[pi].type === "image" && parts[pi].url === stored) { storedIsBodyImage = true; break; }
        }
        page.coverImageUrl = storedIsBodyImage ? "" : stored;
        // No cover on the post means the author has none, not "derive one from the body":
        // treat the body's first picture as already dismissed so a save keeps it that way.
        if (page.isEdit && stored.length === 0) {
            var derived = "";
            for (var di = 0; di < parts.length; di++)
                if (parts[di].type === "image" && (parts[di].url || "").length > 0) { derived = parts[di].url; break; }
            page.coverDismissedUrls = derived.length > 0 ? [derived] : [];
        }
        Qt.callLater(function () { page._prefilling = false; });
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
    // Logo for the edited post's platform. communityIconFor(), not the cached record's raw
    // `icon`: that hands back the backend logo for Global (where the app shows its bundled
    // globe) and leaves site-relative paths unresolved.
    readonly property string editCommunityIcon: (page.isEdit && page.editPost && page.editPost.communityId)
                                                ? Config.communityIconFor(page.editPost.communityId)
                                                : (page.catCommunityName === Config.currentCommunityName
                                                   ? Config.currentCommunityIconUrl : "")

    readonly property string postCommunityName: page.targetCommunity ? page.targetCommunity.name
                                                                     : Config.communityName
    // Name shown in the publishing-scope row: whatever community the post lands in.
    readonly property string scopeCommunityName: page.isEdit
                                                 ? ((page.editPost && page.editPost.community) || page.catCommunityName)
                                                 : page.postCommunityName
    // Global is the combined feed, so "also publish to Global" is meaningless there.
    // Can't test the id: the postable Global record has a real backend id like any
    // other community (only the picker's synthetic source row is id 0). Its dns is
    // what identifies it, same as PostCommunityPicker._globalEntry().
    readonly property bool targetIsGlobal: {
        var id = page.postCommunityId;
        if (!(id > 0)) return true;
        var c = Config.communityInfoFor(id);
        return !!c && (c.dns || "") === Config.sources[0].dns;
    }

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
            // The body is taken as-is: this composer never bakes the cover into it.
            page._prefillBody(page.editPost);
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
            page.publishCeilingId = Number(page.editPost.publishCeilingId || 0);
            // Always re-read the post from its own detail endpoint. Feed rows carry a
            // SHORTENED body (and often no community_id/community_title), so editing from a
            // card used to open the editor with pictures and text the article really has
            // missing - and the next save wrote that truncated version back.
            var author = page.editPost.author || "";
            var permlink = page.editPost.permlink || "";
            if (author && permlink) {
                PostService.detail(Config.baseUrl, author, permlink, Session.token,
                    function (result) {
                        var p = result && result.post;
                        if (!p || !page.editPost) return;
                        page.editPost = Object.assign({}, page.editPost, {
                            communityId: p.communityId || page.editPost.communityId,
                            community: p.community || page.editPost.community,
                            body: p.body || page.editPost.body,
                            thumbnail: p.thumbnail || page.editPost.thumbnail
                        });
                        // Feed rows can omit the ceiling too; the detail
                        // response is authoritative, so re-prefill from it.
                        page.publishCeilingId = Number(p.publishCeilingId || 0);
                        // Only while the author hasn't started editing: their work wins over
                        // a response that arrived late.
                        if (!page._bodyTouched && (p.body || "") !== "")
                            page._prefillBody(page.editPost);
                    },
                    function (err) { /* best-effort; publish() still has its old fallback */ });
            }
        } else {
            page._applyRememberedScope();
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
                page.coverDismissedUrls = [];
                Toast.success(Lang.tr("Cover image uploaded"));
            }
        }
        onFailed: Toast.error(message)
    }

    // Inserts an image block AT THE CARET: the focused segment is split there, so a picture
    // dropped at the top of a paragraph lands at the top, not after the whole thing. The text
    // that followed the caret becomes the segment after the image, which is where typing resumes.
    function _insertBodyImage(url) {
        Qt.inputMethod.commit();
        var parts = page.bodyParts.slice();
        var afterIdx = page.activeTextIndex;
        if (afterIdx < 0 || afterIdx >= parts.length || parts[afterIdx].type !== "text")
            afterIdx = parts.length - 1;
        // Belt and braces: pull the segment's true current text straight off its live TextArea rather
        // than trusting partData.html, in case onTextChanged hasn't caught up with the commit above yet.
        var activeLoader = bodyRepeater.itemAt(afterIdx);
        var before = "";
        var after = "";
        if (activeLoader && activeLoader.item) {
            var ta = activeLoader.item;
            var cp = ta.cursorPosition;
            var len = ta.length !== undefined ? ta.length : ta.text.length;
            // getFormattedText keeps the bold/italic runs; plain slicing would drop them.
            before = cp > 0 ? ta.getFormattedText(0, cp) : "";
            after = cp < len ? ta.getFormattedText(cp, len) : "";
            parts[afterIdx] = { type: "text", html: before };
        }
        parts.splice(afterIdx + 1, 0, { type: "image", url: url }, { type: "text", html: after });
        page.bodyParts = parts;
        page.activeTextIndex = afterIdx + 2;
        page._pendingFocusIndex = afterIdx + 2;
        page._bodyTouched = true;
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
        page._bodyTouched = true;
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

    // Thumbnail fallback: an article with pictures but no cover picked uses its
    // first body image. Kept as a binding rather than written into coverImageUrl,
    // so it always tracks the body (delete that image and it re-derives or clears)
    // and stays distinguishable from a cover the user actually chose, which the
    // edit prefill above depends on.
    readonly property string derivedCoverUrl: {
        var parts = page.bodyParts;
        for (var i = 0; i < parts.length; i++)
            if (parts[i].type === "image" && (parts[i].url || "").length > 0)
                return parts[i].url;
        return "";
    }
    // Pictures the author dismissed from the slot, remembered by URL rather than as a
    // blanket "cleared" flag: clearing must not re-derive the same image, but adding a
    // NEW body picture afterwards should fill the empty slot again. Both the shown cover
    // and the body's current first image go in, because a stored cover is often a
    // re-upload of that same picture under a different URL - matching only the shown one
    // let clearing an edit's cover silently fall back to the body image and save it again.
    property var coverDismissedUrls: []

    function _dismissCover() {
        var list = page.coverDismissedUrls.slice();
        var shown = page.effectiveCoverUrl;
        var derived = page.derivedCoverUrl;
        if (shown.length > 0 && list.indexOf(shown) < 0) list.push(shown);
        if (derived.length > 0 && list.indexOf(derived) < 0) list.push(derived);
        page.coverDismissedUrls = list;
        page.coverImageUrl = "";
    }

    // What actually gets published, and what the thumbnail slot shows. A picked
    // cover always wins over the derived one.
    readonly property string effectiveCoverUrl: page.coverImageUrl.length > 0
        ? page.coverImageUrl
        : (page.coverDismissedUrls.indexOf(page.derivedCoverUrl) >= 0 ? "" : page.derivedCoverUrl)

    // Assemble the body from its text/image blocks; pull each text segment's live content off
    // its actual delegate rather than the (possibly stale) bodyParts copy.
    function _composeBody() {
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
        return body.trim();
    }

    property bool previewOpen: false
    // Snapshot of the body taken when the preview opens: the live text lives on the
    // segment delegates, which the preview's own Repeater can't read.
    property var previewParts: []
    // The cover is auto-derived from the body's first picture, so drawing both would
    // show the same image twice - PostDetailPage skips the cover for the same reason.
    property bool previewBodyHasImage: false

    function openPreview() {
        var parts = [];
        for (var i = 0; i < page.bodyParts.length; i++) {
            var part = page.bodyParts[i];
            if (part.type === "image" || part.type === "embed") {
                parts.push({ type: part.type, url: part.url, html: "" });
            } else {
                var loader = bodyRepeater.itemAt(i);
                var html = loader && loader.item ? loader.item.text : (part.html || "");
                parts.push({ type: "text", url: "", html: page._richHtmlToSimple(html) });
            }
        }
        var hasImage = false;
        for (var j = 0; j < parts.length; j++)
            if (parts[j].type === "image") { hasImage = true; break; }
        page.previewBodyHasImage = hasImage;
        page.previewParts = parts;
        page.previewOpen = true;
    }

    // Publish taps land here, mirroring the web: the AI proposes a category first and the
    // author confirms or overrides it. Nothing to propose (edit, or a community with no
    // categories) publishes straight away - publish() falls back to "general".
    function beginPublish() {
        if (!Session.isLoggedIn) {
            Toast.error(Lang.tr("Please log in first."));
            return;
        }
        if (page.isEdit || page.categories.length === 0) {
            page.publish();
            return;
        }
        page.catSuggested = false;
        page.catSheetMode = "loading";
        catSheet.open();
        CategoryService.categorize(Config.baseUrl, Session.token, {
            communityId: page.postCommunityId,
            communityName: page.catCommunityName,
            article: page._composeBody()
        },
        function (res) {
            if (!page.catSheetOpen) return;   // author closed the sheet while we waited
            // Match against the community's own names: the AI answers with the backend's
            // spelling, and publish() sends the name as-is.
            var cat = page._matchName(page.categories, res.category);
            if (cat.length > 0) {
                page.selectedCategory = cat;
                page.selectedSubCategory = page._matchName(page.subcatsByCat[cat] || [], res.subCategory);
                page.catSuggested = true;
                page.catSheetMode = "suggested";
            } else {
                page.catSheetMode = "choose";
            }
        },
        function (err) {
            if (!page.catSheetOpen) return;
            // A failed suggestion is not a failed publish: fall through to the manual list.
            page.catSheetMode = "choose";
        });
    }

    function publish() {
        if (!Session.isLoggedIn) {
            Toast.error(Lang.tr("Please log in first."));
            return;
        }
        var body = page._composeBody();
        // Cover image is NOT prepended into the body: it's sent below via `images`, which is what
        // both the API/web thumbnail and PostDetailPage's own cover frame derive from. Baking it
        // into the body too just duplicated it inline above the article text.
        var coverUrl = page.effectiveCoverUrl;
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
            // Never cap a post whose target IS Global: it would hide the post from
            // the only feed it was published to.
            publishCeilingId: page.targetIsGlobal ? 0 : page.publishCeilingId,
            permlink: page.isEdit ? (page.editPost.permlink || "") : "",
            // Also send in `images` (json_meta.image) since the web derives the card thumbnail from that field, not from the body <img>.
            images: coverUrl.length > 0 ? [coverUrl] : []
        }, Session.token,
        function (data) {
            page.submitting = false;
            // Remember the scope for this community so the next post here starts there.
            if (!page.targetIsGlobal)
                Session.savePostScope(page.postCommunityId, page.publishCeilingId);
            Toast.success(page.isEdit ? Lang.tr("Post updated!") : Lang.tr("Post published!"));

            // The API answers with the stored row; it carries the permlink the article
            // now lives at, which is what the detail page needs.
            var created = (data && (data.post || (data.data && data.data.db_data))) || null;
            var fresh = (!page.isEdit && created && created.permlink) ? Mappers.toPost(created) : null;

            // Browse where the post landed, so the feed behind the article is the one
            // holding it (Main also flips News to Latest off this signal).
            if (fresh && page.postCommunityId > 0)
                Config.selectCommunityById(page.postCommunityId);

            // pageStack goes stale for the popped page, so keep our own handle.
            var stack = page.pageStack;
            page.saved(!page.isEdit);
            stack.pop();
            // Straight into the published article; Back then lands on that feed.
            if (fresh)
                stack.push(Qt.resolvedUrl("PostDetailPage.qml"),
                           { author: fresh.author, permlink: fresh.permlink,
                             title: fresh.title, seedPost: fresh });
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

    // Same shape as _insertBodyImage, caret split included
    function _insertBodyEmbed(url) {
        Qt.inputMethod.commit();
        var parts = page.bodyParts.slice();
        var afterIdx = page.activeTextIndex;
        if (afterIdx < 0 || afterIdx >= parts.length || parts[afterIdx].type !== "text")
            afterIdx = parts.length - 1;
        var activeLoader = bodyRepeater.itemAt(afterIdx);
        var after = "";
        if (activeLoader && activeLoader.item) {
            var ta = activeLoader.item;
            var cp = ta.cursorPosition;
            var len = ta.length !== undefined ? ta.length : ta.text.length;
            parts[afterIdx] = { type: "text", html: cp > 0 ? ta.getFormattedText(0, cp) : "" };
            after = cp < len ? ta.getFormattedText(cp, len) : "";
        }
        parts.splice(afterIdx + 1, 0, { type: "embed", url: url }, { type: "text", html: after });
        page.bodyParts = parts;
        page.activeTextIndex = afterIdx + 2;
        page._pendingFocusIndex = afterIdx + 2;
        page._bodyTouched = true;
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

            // Title and thumbnail sit side by side: the cover slot is a small square beside the title.
            Row {
                id: titleRow
                width: parent.width
                spacing: Style.spacingS
                readonly property real thumbW: units.gu(12)

                Rectangle {
                    id: titleBox
                    width: parent.width - titleRow.thumbW - titleRow.spacing
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
                            titleField.cursorPosition = titleField.text.length;
                            Qt.inputMethod.show();
                        }
                    }

                    // Measured once, imperatively cheap: binding a TextMetrics to the live text
                    // would re-trigger itself (see the TextMetrics binding-loop note).
                    Label {
                        id: titleLineMetrics
                        visible: false
                        text: "Ag"
                        font.pixelSize: Style.fontMedium
                        font.family: Style.fontFor(text)
                    }

                    // TextArea, not TextField: a headline runs past one line and a field would
                    // scroll it sideways, hiding the start of the author's own title. Still one
                    // logical line - Return is swallowed and pasted newlines collapse to spaces.
                    TextArea {
                        id: titleField
                        anchors {
                            top: parent.top; topMargin: Style.spacingM
                            left: parent.left; right: parent.right
                            leftMargin: Style.spacingM; rightMargin: Style.spacingM
                        }
                        font.pixelSize: Style.fontMedium
                        font.family: Style.fontFor(text)
                        color: Style.textPrimary
                        selectByMouse: true
                        selectionColor: Style.brand
                        // Wrap (not WordWrap): a run with no spaces must still break instead of overflowing.
                        wrapMode: Text.Wrap
                        // Fixed at two lines rather than autoSize: autoSize settled a hair short of
                        // the second line, so a wrapped headline was clipped while padding sat unused
                        // below it. A constant height also stops the box jumping as the title grows.
                        height: titleLineMetrics.implicitHeight * 2 + units.gu(1)

                        Keys.onReturnPressed: event.accepted = true
                        Keys.onEnterPressed: event.accepted = true

                        // TextArea has no maximumLength, so the cap is enforced here. Both edits
                        // keep the caret where the author was typing.
                        onTextChanged: {
                            if (text.indexOf("\n") >= 0) {
                                var cp = cursorPosition;
                                text = text.replace(/\s*\n+\s*/g, " ");
                                cursorPosition = Math.min(cp, text.length);
                            }
                            if (text.length > page.titleMaxLength) {
                                var at = cursorPosition;
                                text = text.substring(0, page.titleMaxLength);
                                cursorPosition = Math.min(at, text.length);
                            }
                        }

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

                Rectangle {
                    width: titleRow.thumbW
                    // Exactly the title box: the two read as one pair, and the box no longer
                    // grows without bound now that the title is fixed at two lines.
                    height: titleBox.height
                    radius: Style.thumbRadius
                    // Outlined while empty, filled once an image sits behind it.
                    color: page.effectiveCoverUrl.length > 0 ? Style.iconBackground : "transparent"
                    border.width: page.effectiveCoverUrl.length > 0 ? 0 : units.dp(1.5)
                    border.color: Style.divider
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: page.effectiveCoverUrl
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        autoTransform: true     // honour EXIF orientation
                        visible: page.effectiveCoverUrl.length > 0
                    }

                    // Says why a picture is here that the author never picked. On a dark
                    // pill, not outlined text: the image behind it is arbitrary, so
                    // nothing else guarantees contrast.
                    Rectangle {
                        anchors {
                            left: parent.left; bottom: parent.bottom
                            leftMargin: Style.spacingS; bottomMargin: Style.spacingS
                        }
                        z: 2
                        // Keyed off what the slot is actually SHOWING: after the author clears
                        // the cover, effectiveCoverUrl is empty even though a body image still
                        // exists, and the pill was labelling an empty "Add thumbnail" slot.
                        visible: page.coverImageUrl.length === 0 && page.effectiveCoverUrl.length > 0
                        // Bounded by the slot: the pill used to run past its edge and get clipped.
                        width: Math.min(derivedHint.implicitWidth + Style.spacingM,
                                        parent.width - Style.spacingS * 2)
                        height: units.gu(2.5)
                        radius: Style.pillRadius
                        color: Qt.rgba(0, 0, 0, 0.65)

                        Label {
                            id: derivedHint
                            anchors.centerIn: parent
                            width: parent.width - Style.spacingXs * 2
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: Lang.tr("From article")
                            font.pixelSize: Style.fontXSmall
                            font.weight: Font.DemiBold
                            font.family: Style.fontFor(text)
                            color: "#FFFFFF"
                        }
                    }

                    AbstractButton {
                        visible: page.effectiveCoverUrl.length > 0
                        anchors {
                            top: parent.top; right: parent.right
                            topMargin: Style.spacingS; rightMargin: Style.spacingS
                        }
                        width: units.gu(3); height: width
                        z: 2
                        // Remember which pictures were dismissed, so only those stay gone.
                        onClicked: page._dismissCover()

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: Qt.rgba(0, 0, 0, 0.5)
                        }
                        Icon {
                            anchors.centerIn: parent
                            width: units.gu(1.5); height: width
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
                        visible: page.effectiveCoverUrl.length === 0 && !page.uploading

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: units.gu(3.5); height: width
                            radius: width / 2
                            color: Style.iconBackground

                            Icon {
                                anchors.centerIn: parent
                                width: units.gu(2); height: width
                                name: "add"
                                color: Style.textPrimary
                            }
                        }

                        Label {
                            width: titleRow.thumbW - Style.spacingS * 2
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: Lang.tr("Add thumbnail")
                            font.pixelSize: Style.fontXSmall
                            color: Style.textSecondary
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        // Keyed off the picked cover, not the effective one: a derived
                        // thumbnail must stay tappable so it can be replaced.
                        enabled: !page.uploading && page.coverImageUrl.length === 0
                        onClicked: page.pickCoverImage()
                    }
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
                                    item.cursorPosition = 0;
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
                    // Focus comes from the tap handler below, not from the press: pressing to
                    // scroll used to focus the segment and throw the keyboard up mid-flick.
                    activeFocusOnPress: false

                    // A drag makes the Flickable steal the grab, which cancels this handler, so
                    // clicked() only fires on a real tap. Disabled once focused so the toolkit's
                    // own selection handles and caret dragging work untouched.
                    MouseArea {
                        anchors.fill: parent
                        enabled: !partArea.activeFocus
                        onClicked: {
                            partArea.forceActiveFocus();
                            partArea.cursorPosition = partArea.positionAt(mouse.x, mouse.y);
                            Qt.inputMethod.show();
                        }
                    }
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

            // Publishing scope. Hidden on Global: that IS the combined feed, so
            // there is nothing to narrow the post down to. A dropdown rather than
            // a switch because the tree has more than two levels.
            Item {
                width: parent.width
                visible: !page.targetIsGlobal
                height: visible ? scopeCol.implicitHeight : 0

                Column {
                    id: scopeCol
                    anchors { left: parent.left; right: parent.right }
                    spacing: units.dp(2)

                    Label {
                        text: Lang.tr("Publish to")
                        font.pixelSize: Style.fontRegular
                        font.weight: Font.DemiBold
                        font.family: Style.fontFor(text)
                        color: Style.textPrimary
                    }

                    // Same row shape as the category picker, so the composer reads
                    // as one form rather than a switch plus a dropdown.
                    MouseArea {
                        id: scopeRow
                        width: parent.width
                        height: units.gu(5)
                        onClicked: scopeSheet.show(page._scopeSheetItems(), scopeRow)

                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            border.width: units.dp(1)
                            border.color: Style.divider
                            radius: Style.thumbRadius

                            Row {
                                anchors {
                                    left: parent.left; right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: Style.spacingM; rightMargin: Style.spacingM
                                }
                                spacing: Style.spacingS

                                Label {
                                    width: parent.width - scopeChevron.width - Style.spacingS
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: page.scopeLabel
                                    elide: Text.ElideRight
                                    font.pixelSize: Style.fontRegular
                                    font.family: Style.fontFor(text)
                                    color: Style.textPrimary
                                }
                                Icon {
                                    id: scopeChevron
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(2); height: width
                                    name: "down"
                                    color: Style.textSecondary
                                }
                            }
                        }
                    }

                    // The label names the choice; this says what it actually does.
                    Label {
                        width: parent.width
                        text: page.scopeHint
                        font.pixelSize: Style.fontXSmall
                        font.family: Style.fontFor(text)
                        color: Style.textSecondary
                        wrapMode: Text.WordWrap
                    }
                }
            }


            Row {
                width: parent.width
                spacing: Style.spacingS

                // Secondary: outlined, so only the publish action carries a fill.
                SecondaryButton {
                    id: previewBtn
                    width: (parent.width - Style.spacingS) * 0.36
                    // Nothing written yet is nothing to preview.
                    enabled: page.canPublish
                    text: Lang.tr("Preview")
                    onClicked: page.openPreview()
                }

                PrimaryButton {
                    width: parent.width - previewBtn.width - Style.spacingS
                    enabled: page.canPublish
                    busy: page.submitting
                    text: page.submitting ? (page.isEdit ? Lang.tr("Saving…") : Lang.tr("Posting…"))
                                          : (page.isEdit ? Lang.tr("Save") : Lang.tr("Publish"))
                    onClicked: page.beginPublish()
                }
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

    // --- Preview -------------------------------------------------------------
    // The article as a reader meets it: same cover frame, title and body blocks the
    // detail page draws, so what the author checks here is what gets published.
    Rectangle {
        id: preview
        anchors.fill: parent
        visible: page.previewOpen
        color: Style.surface
        z: 150

        // Swallows taps so nothing behind the preview reacts.
        MouseArea { anchors.fill: parent }

        Item {
            id: previewHeader
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: units.gu(6)

            Label {
                anchors.centerIn: parent
                text: Lang.tr("Preview")
                font.pixelSize: Style.fontMedium
                font.weight: Font.DemiBold
                font.family: Style.fontFor(text)
                color: Style.textPrimary
            }
            AbstractButton {
                anchors { left: parent.left; leftMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
                width: units.gu(4); height: width
                onClicked: page.previewOpen = false
                Icon {
                    anchors.centerIn: parent
                    width: units.gu(2.2); height: width
                    name: "close"
                    color: Style.textPrimary
                }
            }
            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: units.dp(1); color: Style.divider
            }
        }

        Flickable {
            anchors {
                top: previewHeader.bottom; left: parent.left; right: parent.right
                bottom: previewFooter.top
            }
            contentWidth: width
            contentHeight: previewCol.height + Style.spacingL * 2
            clip: true

            Column {
                id: previewCol
                width: Math.min(parent.width - Style.spacingM * 2, Config.readingMaxWidth)
                anchors.horizontalCenter: parent.horizontalCenter
                y: Style.spacingM
                spacing: Style.spacingM

                // Same order PostDetailPage reads in: category eyebrow, title, byline,
                // rule, then the article.
                Row {
                    visible: page.selectedCategory.length > 0
                    height: visible ? catEyebrow.height : 0
                    spacing: Style.spacingXs

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.dp(10); height: units.dp(10)
                        radius: units.dp(2)
                        color: Style.accentRed
                    }
                    Label {
                        id: catEyebrow
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.selectedCategory.toUpperCase()
                        font.pixelSize: Style.fontSmall
                        font.weight: Font.Bold
                        font.family: Style.fontFor(text)
                        color: Style.accentRed
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: page.selectedSubCategory.length > 0
                        text: "› " + page.selectedSubCategory.toUpperCase()
                        font.pixelSize: Style.fontSmall
                        font.weight: Font.Bold
                        font.family: Style.fontFor(text)
                        color: Style.textSecondary
                    }
                }

                Label {
                    width: parent.width
                    text: titleField.text.trim().length > 0 ? titleField.text.trim() : Lang.tr("Enter title")
                    font.pixelSize: Style.fontTitle
                    font.weight: Font.DemiBold
                    font.family: Style.fontFor(text)
                    color: Style.textPrimary
                    wrapMode: Text.Wrap
                }

                Row {
                    width: parent.width
                    spacing: Style.spacingS

                    Item {
                        id: previewAvatar
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(4.25); height: width

                        // Letter tint while the author has no picture, like the detail page.
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: Style.avatarTint(Session.username)
                            visible: Session.avatarUrl.length === 0

                            Label {
                                anchors.centerIn: parent
                                text: Session.username.length > 0
                                    ? Session.username.charAt(0).toUpperCase() : "?"
                                font.pixelSize: Style.fontMedium
                                font.bold: true
                                color: Style.brand
                            }
                        }

                        CircleImage {
                            anchors.fill: parent
                            visible: Session.avatarUrl.length > 0
                            source: Session.avatarUrl
                            decode: units.gu(6)
                        }
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Session.username + "  ·  " + Lang.tr("now")
                        font.pixelSize: Style.fontSmall
                        font.family: Style.fontFor(text)
                        color: Style.textSecondary
                    }
                }

                Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

                // Only when the author actually picked one: the detail page draws no
                // placeholder cover, so a stand-in banner here would preview a lie.
                RoundedThumb {
                    visible: page.effectiveCoverUrl.length > 0 && !page.previewBodyHasImage
                    width: parent.width
                    height: visible ? width * 0.56 : 0
                    source: page.effectiveCoverUrl
                    autoTransform: true
                    decodeWidth: units.gu(90)
                }

                Repeater {
                    model: page.previewParts

                    // Plain Item with both children rather than a Loader: a sized Loader
                    // resizes its item to itself, so measuring the Loader off the item was
                    // circular and every block collapsed onto the one above it.
                    delegate: Item {
                        id: blockRow
                        readonly property bool isImage: modelData.type === "image"
                        width: previewCol.width
                        height: blockRow.isImage ? blockImage.height : blockText.height

                        Label {
                            id: blockText
                            visible: !blockRow.isImage
                            width: parent.width
                            // The composer stores rich text; render it, don't show its tags.
                            textFormat: Text.RichText
                            text: !blockRow.isImage
                                ? (modelData.type === "embed"
                                   ? ('<a href="' + modelData.url + '">' + modelData.url + '</a>')
                                   : modelData.html)
                                : ""
                            font.pixelSize: Style.fontRegular
                            font.family: Style.fontFor(text)
                            color: Style.textPrimary
                            wrapMode: Text.Wrap
                            onLinkActivated: Qt.openUrlExternally(link)
                        }

                        Image {
                            id: blockImage
                            visible: blockRow.isImage
                            width: parent.width
                            // Ratio off implicitWidth/Height, like the editor's own image block:
                            // sourceSize.height stays 0 once sourceSize.width is set, so keying the
                            // height off it left every body image at zero height (invisible).
                            height: !blockRow.isImage ? 0
                                : (status === Image.Ready && implicitWidth > 0)
                                  ? width * implicitHeight / implicitWidth
                                  : units.gu(20)
                            source: blockRow.isImage ? modelData.url : ""
                            fillMode: Image.PreserveAspectFit
                            autoTransform: true
                            asynchronous: true
                        }
                    }
                }
            }
        }

        Rectangle {
            id: previewFooter
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: previewPublish.height + Style.spacingM * 2
            color: Style.surface

            Rectangle {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: units.dp(1); color: Style.divider
            }

            PrimaryButton {
                id: previewPublish
                anchors { verticalCenter: parent.verticalCenter; horizontalCenter: parent.horizontalCenter }
                width: Math.min(parent.width - Style.spacingM * 2, units.gu(60))
                enabled: page.canPublish
                busy: page.submitting
                text: page.isEdit ? Lang.tr("Save") : Lang.tr("Publish")
                onClicked: { page.previewOpen = false; page.beginPublish(); }
            }
        }
    }

    // --- Category picker bottom sheet ----------------------------------------
    Item {
        id: catSheet
        anchors.fill: parent
        visible: page.catSheetOpen
        z: 200

        // Pointer devices get the Lomiri dialog shape for this confirmation (centred,
        // modal, dimmed page); touch keeps the bottom sheet it can reach with a thumb.
        readonly property bool asDialog: Config.desktopMode

        function open() { page.catSheetOpen = true; }

        onVisibleChanged: {
            if (!visible) return;
            catBdFade.start();
            // A previous sheet-mode close leaves the slide offset in place; the dialog
            // never touches it, so clear it or the card opens pushed down the page.
            catSlideT.y = 0;
            if (catSheet.asDialog) catDialogIn.start(); else catSlideAnim.start();
        }
        function closeAnimated() {
            catBdFadeOut.start();
            if (catSheet.asDialog) catDialogOut.start(); else catSlideOut.start();
        }

        Rectangle {
            id: catBd
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.4)
            opacity: 0
            MouseArea { anchors.fill: parent; onClicked: catSheet.closeAnimated() }
        }
        NumberAnimation { id: catBdFade; target: catBd; property: "opacity"; from: 0; to: 1; duration: 200 }
        NumberAnimation { id: catBdFadeOut; target: catBd; property: "opacity"; to: 0; duration: 200 }

        // Soft elevation so the dialog card reads as lifted off the composer.
        DropShadow {
            anchors.fill: catSheetRect
            visible: catSheet.asDialog && catSheetRect.opacity > 0
            source: catSheetRect
            radius: 16
            samples: 33
            horizontalOffset: 0
            verticalOffset: 6
            color: Qt.rgba(0, 0, 0, 0.22)
            transparentBorder: true
            cached: true
        }

        Rectangle {
            id: catSheetRect
            // Full-width sheet on phone, centered width-capped card on desktop
            readonly property bool wide: Config.wideMode
            // x/y rather than anchors: anchors can't be conditionally unset from a ternary,
            // and the two modes place the card very differently. Both stay bindings so the
            // card re-places itself when a mode swap changes its height.
            x: (parent.width - width) / 2
            y: catSheet.asDialog
                ? Math.max(Style.spacingM, (catSheet.height - height) / 2)
                : parent.height - height - (catSheetRect.wide ? units.gu(4) : 0)
            width: catSheet.asDialog ? Math.min(parent.width - units.gu(8), units.gu(42))
                 : catSheetRect.wide ? Math.min(parent.width - units.gu(4), units.gu(45)) : parent.width
            height: catSheetCol.height + (catSheet.asDialog ? units.gu(2.5) : units.gu(4))
            radius: units.gu(1)
            color: Style.surface
            transform: Translate { id: catSlideT; y: 0 }
            NumberAnimation { id: catSlideAnim; target: catSlideT; property: "y"; from: catSheetRect.height; to: 0; duration: 300; easing.type: Easing.OutCubic }
            NumberAnimation { id: catSlideOut; target: catSlideT; property: "y"; to: catSheetRect.height; duration: 250; easing.type: Easing.InCubic; onStopped: page.catSheetOpen = false }

            // The dialog fades up in place; a 300ms slide belongs to the touch sheet.
            ParallelAnimation {
                id: catDialogIn
                NumberAnimation { target: catSheetRect; property: "opacity"; from: 0; to: 1; duration: 120; easing.type: Easing.OutQuad }
                NumberAnimation { target: catSheetRect; property: "scale"; from: 0.97; to: 1; duration: 120; easing.type: Easing.OutQuad }
            }
            SequentialAnimation {
                id: catDialogOut
                NumberAnimation { target: catSheetRect; property: "opacity"; to: 0; duration: 100; easing.type: Easing.InQuad }
                ScriptAction { script: page.catSheetOpen = false }
            }

            Rectangle {
                visible: !catSheet.asDialog
                anchors { top: parent.top; topMargin: Style.spacingS; horizontalCenter: parent.horizontalCenter }
                width: units.gu(4.5); height: units.dp(4); radius: units.dp(2)
                color: Style.lightGray
            }

            Column {
                id: catSheetCol
                anchors {
                    top: parent.top; left: parent.left; right: parent.right
                    topMargin: catSheet.asDialog ? Style.spacingS : Style.spacingL
                }
                spacing: 0

                Item {
                    width: parent.width; height: units.gu(5)
                    Label {
                        anchors.centerIn: parent
                        text: page.catSheetMode === "loading" ? Lang.tr("Preparing to publish")
                            : page.catSheetMode === "suggested" ? Lang.tr("Publish to %1?").arg(page.postCommunityName)
                            : Lang.tr("Select Category")
                        width: parent.width - units.gu(9)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
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

                Item {
                    width: parent.width
                    visible: page.catSheetMode === "choose"
                    height: visible ? hintLabel.implicitHeight + Style.spacingM * 2 : 0

                    Label {
                        id: hintLabel
                        anchors {
                            left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                            leftMargin: Style.spacingM; rightMargin: Style.spacingM
                        }
                        horizontalAlignment: Text.AlignHCenter
                        text: Lang.tr("Pick where this post belongs.")
                        font.pixelSize: Style.fontXSmall
                        font.family: Style.fontFor(text)
                        color: Style.textSecondary
                        wrapMode: Text.WordWrap
                    }
                }

                // While the AI classifies the article. Closing here posts nothing.
                Item {
                    width: parent.width
                    visible: page.catSheetMode === "loading"
                    height: visible ? units.gu(14) : 0

                    Column {
                        anchors.centerIn: parent
                        spacing: Style.spacingM

                        ActivityIndicator {
                            anchors.horizontalCenter: parent.horizontalCenter
                            running: page.catSheetMode === "loading"
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Lang.tr("Finding the right category…")
                            font.pixelSize: Style.fontSmall
                            font.family: Style.fontFor(text)
                            color: Style.textSecondary
                        }
                    }
                }

                // What the AI picked. One tap publishes; "Choose other category" opens the list.
                Item {
                    width: parent.width
                    visible: page.catSheetMode === "suggested"
                    height: visible ? suggestCol.implicitHeight + Style.spacingL * 2 : 0

                    Column {
                        id: suggestCol
                        anchors {
                            left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                            leftMargin: Style.spacingM; rightMargin: Style.spacingM
                        }
                        spacing: Style.spacingS

                        Label {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: Lang.tr("Category")
                            font.pixelSize: Style.fontSmall
                            font.family: Style.fontFor(text)
                            color: Style.textSecondary
                            wrapMode: Text.WordWrap
                        }
                        // The pick as a chip, not a line of text: it is the one thing in the
                        // card the author has to read before publishing.
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.min(parent.width, pickedLabel.implicitWidth + Style.spacingL)
                            height: units.gu(4.5)
                            radius: Style.pillRadius
                            color: Qt.rgba(Style.brand.r, Style.brand.g, Style.brand.b, 0.12)

                            Label {
                                id: pickedLabel
                                anchors.centerIn: parent
                                width: parent.width - Style.spacingM
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: page.selectedSubCategory.length > 0
                                    ? (page.selectedCategory + "  ›  " + page.selectedSubCategory)
                                    : page.selectedCategory
                                font.pixelSize: Style.fontMedium
                                font.weight: Font.DemiBold
                                font.family: Style.fontFor(text)
                                color: Style.brand
                            }
                        }
                    }
                }

                // Scrollable list: caps sheet height so long sub-category lists scroll, not overflow
                Flickable {
                    id: catListFlick
                    width: parent.width
                    visible: page.catSheetMode === "choose"
                    height: visible ? Math.min(catListCol.height,
                                               catSheet.asDialog ? units.gu(34) : catSheet.height * 0.5)
                                    : 0
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

                // Publishing happens from the sheet, the way the web modal does it.
                Column {
                    width: parent.width - Style.spacingM * 2
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: page.catSheetMode !== "loading"
                    spacing: Style.spacingS

                    Item { width: 1; height: Style.spacingS }

                    PrimaryButton {
                        width: parent.width
                        enabled: page.canPublish && page.selectedCategory.length > 0
                        busy: page.submitting
                        text: page.submitting ? Lang.tr("Posting…") : Lang.tr("Publish")
                        onClicked: {
                            page.catSheetOpen = false;
                            page.publish();
                        }
                    }

                    // Filled grey, stacked under the primary: the HIG's secondary action,
                    // same button shape as Publish so the pair reads as one stack.
                    AbstractButton {
                        id: altCatBtn
                        width: parent.width
                        height: units.gu(5)
                        // Back only exists when there is a suggestion to go back to.
                        visible: page.catSheetMode === "choose" ? page.catSuggested : true
                        onClicked: page.catSheetMode = (page.catSheetMode === "choose") ? "suggested" : "choose"

                        Rectangle {
                            anchors.fill: parent
                            radius: Style.cardRadius
                            color: altCatBtn.pressed ? Style.pressed : Style.iconBackground
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Label {
                                anchors.centerIn: parent
                                text: page.catSheetMode === "choose" ? Lang.tr("Back") : Lang.tr("Choose other category")
                                font.pixelSize: Style.fontMedium
                                font.weight: Font.DemiBold
                                font.family: Style.fontFor(text)
                                color: Style.textPrimary
                            }
                        }
                    }
                }
            }
        }
    }

    // Publishing-scope picker. ActionBottomSheet already renders as a dropdown
    // anchored to the row on desktop and a bottom sheet on touch.
    ActionBottomSheet { id: scopeSheet }
}
