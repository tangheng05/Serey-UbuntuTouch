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
    // Maps editor placeholder "[image N]" -> uploaded URL; publish() swaps them back to <img>
    property var bodyImages: []
    // "Post to blockchain": on = broadcast on-chain (default), off = save to the Serey DB only (no voting/rewards).
    property bool postToBlockchain: true

    // Bound by the publish button; bodyArea lives further down the file.
    readonly property bool canPublish: !page.submitting
        && titleField.text.trim().length > 0
        && bodyArea.getText(0, bodyArea.length).trim().length > 0

    // Chosen in PostCommunityPicker before this page opens; unset = post into the browsed source
    property var targetCommunity: null
    readonly property int postCommunityId: page.targetCommunity ? Number(page.targetCommunity.id)
                                                                : Config.communityId
    // Categories key by the selected sub-community; the post itself by its top-level source
    readonly property string catCommunityName: page.targetCommunity ? page.targetCommunity.name
                                                                    : Config.currentCommunityName
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
                if (names.indexOf(prev) < 0) { page.selectedCategory = ""; page.selectedSubCategory = ""; }
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
            // Strip the leading cover <img> we prepend on publish so it isn't duplicated; the cover is restored from the post's thumbnail.
            var b = (page.editPost.body || "").replace(/^\s*<img[^>]*>\s*/i, "");
            // Turn remaining inline images into "[image N]" placeholders so the editor shows readable text; publish() restores them.
            var imgs = [];
            b = b.replace(/<img[^>]*src=["']([^"']*)["'][^>]*\/?>/gi, function (m, src) {
                imgs.push(src);
                return "[image " + imgs.length + "]";
            });
            page.bodyImages = imgs;
            bodyArea.text = b;
            page.coverImageUrl = page.editPost.thumbnail || "";
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
        }
        loadCategories();   // captures selectedCategory above as the kept value
    }
    // React to source changes, unless a specific target community was chosen via the picker
    Connections {
        target: Config
        function onCommunityIdChanged() { if (!page.targetCommunity) page.loadCategories() }
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
                page.bodyImages = page.bodyImages.concat([url]);
                var snippet = "[image " + page.bodyImages.length + "]";
                var pos = bodyArea.cursorPosition;
                bodyArea.insert(pos, snippet);
                bodyArea.cursorPosition = pos + snippet.length;
                Toast.success(Lang.tr("Image added"));
            } else {
                page.coverImageUrl = url;
                Toast.success(Lang.tr("Cover image uploaded"));
            }
        }
        onFailed: Toast.error(message)
    }

    // Qt's RichText re-serializes formatting as style spans; collapse back to <b>/<i>/<s> tags
    function _richHtmlToSimple(html) {
        var t = html || "";
        var bodyMatch = t.match(/<body[^>]*>([\s\S]*)<\/body>/i);
        if (bodyMatch) t = bodyMatch[1];
        t = t.replace(/<!DOCTYPE[^>]*>/gi, "").replace(/<\/?html[^>]*>/gi, "")
             .replace(/<head>[\s\S]*?<\/head>/gi, "");
        t = t.replace(/<span[^>]*style="[^"]*font-weight:\s*(?:600|700|bold)[^"]*"[^>]*>([\s\S]*?)<\/span>/gi, "<b>$1</b>");
        t = t.replace(/<span[^>]*style="[^"]*font-style:\s*italic[^"]*"[^>]*>([\s\S]*?)<\/span>/gi, "<i>$1</i>");
        t = t.replace(/<span[^>]*style="[^"]*text-decoration:[^"]*line-through[^"]*"[^>]*>([\s\S]*?)<\/span>/gi, "<s>$1</s>");
        t = t.replace(/<p[^>]*>/gi, "<p>");
        t = t.replace(/<a\s+[^>]*href="([^"]*)"[^>]*>/gi, '<a href="$1">');
        return t;
    }

    function publish() {
        if (!Session.isLoggedIn) {
            Toast.error(Lang.tr("Please log in first."));
            return;
        }
        var body = page._richHtmlToSimple(bodyArea.text).trim();
        // Swap "[image N]" placeholders back into real <img> tags; unknown numbers are left as typed.
        var imgs = page.bodyImages || [];
        body = body.replace(/\[image (\d+)\]/gi, function (m, n) {
            var u = imgs[parseInt(n, 10) - 1];
            return u ? '<img src="' + u + '" style="max-width:100%;height:auto;" />' : m;
        });
        if (page.coverImageUrl.length > 0) {
            body = '<img src="' + page.coverImageUrl + '" style="max-width:100%;height:auto;" />\n' + body;
        }
        page.submitting = true;
        PostService.createPost(Config.baseUrl, {
            title: titleField.text.trim(),
            body: body,
            // On edit, keep the post in its own community (resolve by its title) rather than the currently-selected source.
            communityId: page.isEdit ? 0 : page.postCommunityId,
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

    // Requires a selection: plain TextEdit has no "current format" state to toggle
    function wrapSelection(tagOpen, tagClose) {
        var start = bodyArea.selectionStart;
        var end = bodyArea.selectionEnd;
        if (start === end) {
            Toast.show(Lang.tr("Select some text first"));
            return;
        }
        var sel = bodyArea.selectedText;
        bodyArea.remove(start, end);
        bodyArea.insert(start, tagOpen + sel + tagClose);
        bodyArea.forceActiveFocus();
    }

    property string _pendingLinkText: ""
    property int _pendingLinkStart: 0
    property int _pendingLinkEnd: 0

    function promptLink() {
        if (bodyArea.selectionStart === bodyArea.selectionEnd) {
            Toast.show(Lang.tr("Select some text first"));
            return;
        }
        page._pendingLinkText = bodyArea.selectedText;
        page._pendingLinkStart = bodyArea.selectionStart;
        page._pendingLinkEnd = bodyArea.selectionEnd;
        Popups.PopupUtils.open(linkDialog);
    }

    function applyLink(url) {
        if (url.length === 0) return;
        bodyArea.remove(page._pendingLinkStart, page._pendingLinkEnd);
        bodyArea.insert(page._pendingLinkStart, '<a href="' + url + '">' + page._pendingLinkText + '</a>');
        bodyArea.forceActiveFocus();
    }

    Component {
        id: linkDialog
        Popups.Dialog {
            id: ldlg
            title: Lang.tr("Add link")
            TextField {
                id: linkUrlField
                placeholderText: "https://"
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoPredictiveText
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

                TextInput {
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

            // Body text area; toolbar docks inside on desktop, above OSK on phone
            Rectangle {
                id: bodyBox
                readonly property real toolbarH: Config.wideMode ? units.gu(5.5) : 0
                width: parent.width
                height: Math.max(units.gu(25), bodyArea.contentHeight + Style.spacingM * 2) + toolbarH
                radius: Style.cardRadius
                color: "transparent"
                clip: true
                border.width: units.dp(1.5)
                border.color: bodyArea.activeFocus ? Style.brand : Style.divider

                // Same as the title: declared FIRST so it catches taps below the text
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        bodyArea.forceActiveFocus();
                        bodyArea.cursorPosition = bodyArea.length;
                        Qt.inputMethod.show();
                    }
                }

                TextEdit {
                    id: bodyArea
                    anchors {
                        left: parent.left; right: parent.right; top: parent.top
                        margins: Style.spacingM
                    }
                    textFormat: Text.RichText
                    selectByMouse: true
                    persistentSelection: true
                    selectionColor: Style.brand
                    font.family: Style.fontFor(text)
                    font.pixelSize: Style.fontRegular
                    color: Style.textPrimary
                    wrapMode: Text.WordWrap
                }

                Label {
                    anchors {
                        left: parent.left; top: parent.top
                        leftMargin: Style.spacingM; topMargin: Style.spacingM
                    }
                    visible: bodyArea.getText(0, bodyArea.length).length === 0 && !bodyArea.activeFocus && !Qt.inputMethod.visible
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
                            text: Lang.tr("Post to blockchain")
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
