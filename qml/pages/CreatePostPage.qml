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
    // optional sub-category, sent in `subcategories`
    property string selectedSubCategory: ""
    property bool catSheetOpen: false
    // keyboard height, keeps toolbar reachable
    readonly property real kbHeight: Qt.inputMethod.visible ? Qt.inputMethod.keyboardRectangle.height : 0
    readonly property int titleMaxLength: 250
    readonly property real maxContentWidth: units.gu(60)
    property string coverImageUrl: ""
    property bool uploading: false
    // "[image N]" placeholder -> uploaded URL
    property var bodyImages: []
    // on = broadcast on-chain, off = Serey DB only
    property bool postToBlockchain: true

    // set when entry point isn't tied to a single source
    property bool pickPlatform: false
    property var targetPlatform: null       // {id, title, icon} from Config.communityById
    property bool platformSheetOpen: false
    // set by compose flow's community-picker step
    property var targetCommunity: null
    readonly property int postCommunityId: page.targetPlatform ? Number(page.targetPlatform.id)
                                           : (page.targetCommunity ? Number(page.targetCommunity.id) : Config.communityId)
    // categories keyed by sub-community, post by top-level source
    readonly property string catCommunityName: page.targetPlatform ? page.targetPlatform.title
                                               : (page.targetCommunity ? page.targetCommunity.name : Config.currentCommunityName)
    readonly property string postCommunityName: page.targetPlatform ? page.targetPlatform.title
                                                : (page.targetCommunity ? page.targetCommunity.name : Config.communityName)

    // real platforms the user may post in, excludes containers
    readonly property var platformOptions: {
        var out = [];
        for (var k in Config.communityById) {
            var c = Config.communityById[k];
            if (!c || !c.dns || c.childCount > 0) continue;
            if (Config.topLevelCommunityIds[String(c.id)]) continue;
            if (Config.hiddenCommunityIds[String(c.id)]) continue;
            if (!c.allowPost && !Config.ownedCommunityIdSet[c.id]) continue;
            out.push(c);
        }
        out.sort(function (a, b) { return (a.title || "").localeCompare(b.title || ""); });
        return out;
    }

    // set to edit an existing post in place
    property var editPost: null
    readonly property bool isEdit: !!editPost

    // isNew: false for in-place edit
    signal saved(bool isNew)

    // per-community categories loaded from backend
    property var categories: []
    // main-category name -> array of sub-category names
    property var subcatsByCat: ({})
    property bool categoriesLoading: false
    property int catEpoch: 0

    // sub-categories for the selected main category
    function subsForSelected() {
        var s = page.subcatsByCat[page.selectedCategory];
        return (s && s.length) ? s : [];
    }

    function loadCategories() {
        var epoch = ++page.catEpoch;
        var prev = page.selectedCategory;
        // nothing to fetch until a platform is picked
        if (page.pickPlatform && !page.targetPlatform) {
            page.categoriesLoading = false;
            page.categories = [];
            page.subcatsByCat = ({});
            return;
        }
        page.categoriesLoading = true;
        CategoryService.listByCommunity(Config.baseUrl, page.catCommunityName, page.postCommunityId, Session.token,
            function (names, raw) {
                if (epoch !== page.catEpoch) return;   // stale community switch
                page.categoriesLoading = false;
                page.categories = names;
                // build main -> [sub names] map
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
            // strip leading cover <img>, restored from thumbnail
            var b = (page.editPost.body || "").replace(/^\s*<img[^>]*>\s*/i, "");
            // inline images -> "[image N]" placeholders
            var imgs = [];
            b = b.replace(/<img[^>]*src=["']([^"']*)["'][^>]*\/?>/gi, function (m, src) {
                imgs.push(src);
                return "[image " + imgs.length + "]";
            });
            page.bodyImages = imgs;
            bodyArea.text = b;
            page.coverImageUrl = page.editPost.thumbnail || "";
            page.selectedCategory = page.editPost.primaryCategory || "";
            // sub-category field name varies across sources
            var eSub = page.editPost.subCategory || page.editPost.subcategory || "";
            if (!eSub) {
                var eSubs = page.editPost.subCategories || page.editPost.subcategories;
                if (eSubs && eSubs.length) eSub = (typeof eSubs[0] === "string") ? eSubs[0] : (eSubs[0] && eSubs[0].name) || "";
            }
            page.selectedSubCategory = eSub || "";
            page.postToBlockchain = (page.editPost.postToBlockchain !== false);
        }
        loadCategories();
    }
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

        AbstractButton {
            anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
            width: postPillLabel.implicitWidth + Style.spacingM * 2
            height: units.gu(4)
            enabled: !page.submitting && titleField.text.trim().length > 0 && bodyArea.getText(0, bodyArea.length).trim().length > 0
                     && (!page.pickPlatform || !!page.targetPlatform)
            onClicked: page.publish()

            Rectangle {
                anchors.fill: parent
                radius: Style.cardRadius
                color: parent.enabled ? Style.brand : Style.iconBackground
            }
            Label {
                id: postPillLabel
                anchors.centerIn: parent
                text: page.submitting ? (page.isEdit ? Lang.tr("Saving…") : Lang.tr("Posting…"))
                                      : (page.isEdit ? Lang.tr("Save") : Lang.tr("Publish"))
                font.pixelSize: Style.fontSmall
                font.weight: Font.DemiBold
                color: parent.enabled ? Style.textOnBrand : Style.textSecondary
            }
        }

        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: units.dp(1); color: Style.divider
        }
    }

    // where the next picked image goes: cover or body
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

    // downscales + uploads picked image
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

    // collapse RichText style spans back to <b>/<i>/<s>
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
        if (page.pickPlatform && !page.targetPlatform) {
            Toast.error(Lang.tr("Select a platform first"));
            return;
        }
        var body = page._richHtmlToSimple(bodyArea.text).trim();
        // swap placeholders back to <img> tags
        var imgs = page.bodyImages || [];
        body = body.replace(/\[image (\d+)\]/gi, function (m, n) {
            var u = imgs[parseInt(n, 10) - 1];
            return u ? '<img src="' + u + '" style="max-width:100%;height:auto;" />' : m;
        });
        // prepend cover image
        if (page.coverImageUrl.length > 0) {
            body = '<img src="' + page.coverImageUrl + '" style="max-width:100%;height:auto;" />\n' + body;
        }
        page.submitting = true;
        PostService.createPost(Config.baseUrl, {
            title: titleField.text.trim(),
            body: body,
            // on edit, keep post in its own community
            communityId: page.isEdit ? 0 : page.postCommunityId,
            communityName: page.isEdit ? (page.editPost.community || Config.communityName)
                                       : page.postCommunityName,
            categories: page.selectedCategory || "general",
            subcategories: page.selectedSubCategory.length > 0 ? [page.selectedSubCategory] : [],
            postToBlockchain: page.postToBlockchain,
            permlink: page.isEdit ? (page.editPost.permlink || "") : "",
            // web derives card thumbnail from json_meta.image
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

    // applies formatting to the selection
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

    // dismiss keyboard by shifting focus
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

        // tap outside a field dismisses keyboard
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

            // Title field — outlined rounded box with inline character counter
            Rectangle {
                width: parent.width
                height: titleField.height + Style.spacingM * 2 + counterLabel.height + Style.spacingXs
                radius: Style.cardRadius
                color: "transparent"
                border.width: units.dp(1.5)
                border.color: titleField.activeFocus ? Style.brand : Style.divider

                // catches taps on the surrounding gap, not just the input line
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

            // Body text area — toolbar docks inside on desktop, above OSK on phone
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

                // catches taps in blank area below the text
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

            // platform selector, pickPlatform path only
            AbstractButton {
                width: parent.width
                height: units.gu(6)
                visible: page.pickPlatform
                onClicked: page.platformSheetOpen = true

                Rectangle {
                    anchors.fill: parent
                    radius: Style.cardRadius
                    color: "transparent"
                    border.width: units.dp(1.5)
                    border.color: Style.divider
                }

                Row {
                    anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                    spacing: Style.spacingS

                    CircleImage {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(3.5); height: width
                        visible: !!page.targetPlatform
                        source: page.targetPlatform ? (page.targetPlatform.icon || "") : ""
                        decode: units.gu(4)
                    }
                    Label {
                        width: parent.width - platChevron.width - Style.spacingS
                               - (page.targetPlatform ? units.gu(3.5) + Style.spacingS : 0)
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.targetPlatform ? page.targetPlatform.title : Lang.tr("Select platform")
                        elide: Text.ElideRight
                        font.pixelSize: Style.fontRegular
                        font.family: Style.fontFor(text)
                        color: page.targetPlatform ? Style.textPrimary : Style.textSecondary
                    }
                    Icon {
                        id: platChevron
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(2); height: width
                        name: "next"
                        color: Style.textSecondary
                    }
                }
            }

            // hidden if community has no categories
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

            // Post to blockchain toggle
            Rectangle {
                width: parent.width
                height: chainRow.implicitHeight + Style.spacingM * 2
                radius: Style.cardRadius
                color: "transparent"
                border.width: units.dp(1.5)
                border.color: Style.divider

                Row {
                    id: chainRow
                    anchors {
                        left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                        leftMargin: Style.spacingM; rightMargin: Style.spacingM
                    }
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
                            text: page.postToBlockchain
                                ? Lang.tr("Permanent, tamper proof storage on the blockchain. Proves authorship and earns SRY rewards")
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

            // Cover image area
            Rectangle {
                width: parent.width
                height: units.gu(20)
                radius: Style.thumbRadius
                color: Style.iconBackground
                clip: true

                // Show uploaded image preview
                Image {
                    anchors.fill: parent
                    source: page.coverImageUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    autoTransform: true     // honour EXIF orientation
                    visible: page.coverImageUrl.length > 0
                }

                // Remove button (top-right, shown when image is set)
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

                // Upload spinner overlay
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(1, 1, 1, 0.7)
                    visible: page.uploading

                    ActivityIndicator {
                        anchors.centerIn: parent
                        running: page.uploading
                    }
                }

                // Empty state: + button + label (shown when no image set and not uploading)
                Column {
                    anchors.centerIn: parent
                    spacing: Style.spacingS
                    visible: page.coverImageUrl.length === 0 && !page.uploading

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: units.gu(5); height: width
                        radius: width / 2
                        color: Style.brand

                        Icon {
                            anchors.centerIn: parent
                            width: units.gu(2.5); height: width
                            name: "add"
                            color: Style.textOnBrand
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

            Item { width: 1; height: Style.spacingM }
        }
    }

    // shared formatting-button row
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

    // phone: docked above the OSK
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

    // Loading overlay
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
            // full-width on phone, capped card on desktop
            readonly property bool wide: Config.wideMode
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

                // caps sheet height, scrolls instead of overflowing
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

                // loading / empty state
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

                    // main category + expandable sub-categories
                    delegate: Column {
                        id: catRow
                        width: catSheetCol.width
                        readonly property string catName: modelData
                        readonly property var subs: {
                            var s = page.subcatsByCat[catName]
                            return (s && s.length) ? s : []
                        }
                        readonly property bool isSelected: page.selectedCategory === catName
                        // expanded by default if already selected with a sub chosen
                        property bool expanded: catRow.isSelected && page.selectedSubCategory.length > 0

                        // tapping row picks main category; arrow expands subs
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
                            // expands/collapses sub list without selecting
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

                        // sub-category rows, shown when expanded
                        Column {
                            width: parent.width
                            visible: catRow.expanded && catRow.subs.length > 0

                            // post under main category only
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

    // --- Platform picker bottom sheet (pickPlatform path only) ----------------
    Item {
        id: platSheet
        anchors.fill: parent
        visible: page.platformSheetOpen
        z: 210
        onVisibleChanged: if (visible) { platBdFade.start(); platSlideAnim.start(); }
        function closeAnimated() { platBdFadeOut.start(); platSlideOut.start(); }

        Rectangle {
            id: platBd
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.4)
            opacity: 0
            MouseArea { anchors.fill: parent; onClicked: platSheet.closeAnimated() }
        }
        NumberAnimation { id: platBdFade; target: platBd; property: "opacity"; from: 0; to: 1; duration: 200 }
        NumberAnimation { id: platBdFadeOut; target: platBd; property: "opacity"; to: 0; duration: 200 }

        Rectangle {
            id: platSheetRect
            readonly property bool wide: Config.wideMode
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: platSheetRect.wide ? units.gu(4) : 0
            }
            width: platSheetRect.wide ? Math.min(parent.width - units.gu(4), Config.sheetMaxWidth) : parent.width
            height: platSheetCol.height + units.gu(4)
            radius: units.gu(1)
            color: Style.surface
            transform: Translate { id: platSlideT; y: 0 }
            NumberAnimation { id: platSlideAnim; target: platSlideT; property: "y"; from: platSheetRect.height; to: 0; duration: 300; easing.type: Easing.OutCubic }
            NumberAnimation { id: platSlideOut; target: platSlideT; property: "y"; to: platSheetRect.height; duration: 250; easing.type: Easing.InCubic; onStopped: page.platformSheetOpen = false }

            Rectangle {
                anchors { top: parent.top; topMargin: Style.spacingS; horizontalCenter: parent.horizontalCenter }
                width: units.gu(4.5); height: units.dp(4); radius: units.dp(2)
                color: Style.lightGray
            }

            Column {
                id: platSheetCol
                anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: Style.spacingL }
                spacing: 0

                Item {
                    width: parent.width; height: units.gu(5)
                    Label {
                        anchors.centerIn: parent
                        text: Lang.tr("Select platform")
                        font.pixelSize: Style.fontMedium
                        font.weight: Font.DemiBold
                        color: Style.textPrimary
                    }
                    AbstractButton {
                        anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                        width: units.gu(3.5); height: units.gu(3.5)
                        onClicked: platSheet.closeAnimated()
                        Icon { anchors.centerIn: parent; width: units.gu(2.2); height: width; name: "close"; color: Style.textPrimary }
                    }
                }

                Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

                Flickable {
                    width: parent.width
                    height: Math.min(platListCol.height, platSheet.height * 0.65)
                    contentHeight: platListCol.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: platListCol
                        width: parent.width
                        spacing: 0

                        // empty if nothing postable was found
                        Item {
                            width: parent.width
                            height: units.gu(8)
                            visible: page.platformOptions.length === 0
                            Label {
                                anchors.centerIn: parent
                                text: Lang.tr("No platforms you can post in")
                                font.pixelSize: Style.fontSmall
                                color: Style.textSecondary
                            }
                        }

                        Repeater {
                            model: page.platformOptions

                            delegate: AbstractButton {
                                width: platSheetCol.width
                                height: units.gu(6.5)
                                readonly property bool isSelected: page.targetPlatform
                                                                   && String(page.targetPlatform.id) === String(modelData.id)
                                onClicked: {
                                    page.targetPlatform = modelData;
                                    page.selectedCategory = "";
                                    page.selectedSubCategory = "";
                                    page.loadCategories();
                                    platSheet.closeAnimated();
                                }

                                Row {
                                    anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                                    spacing: Style.spacingM

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: units.gu(4.5); height: width; radius: width / 2
                                        color: Style.iconBackground
                                        CircleImage {
                                            anchors { fill: parent; margins: units.dp(2) }
                                            source: modelData.icon || ""
                                            decode: units.gu(5)
                                        }
                                    }
                                    Label {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - units.gu(4.5) - platTick.width - Style.spacingM * 2
                                        text: modelData.title
                                        elide: Text.ElideRight
                                        font.pixelSize: Style.fontRegular
                                        font.family: Style.fontFor(text)
                                        color: isSelected ? Style.brand : Style.textPrimary
                                        font.weight: isSelected ? Font.DemiBold : Font.Normal
                                    }
                                    Icon {
                                        id: platTick
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: units.gu(2.2); height: width
                                        name: "tick"; color: Style.brand
                                        visible: isSelected
                                    }
                                }

                                Rectangle {
                                    anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                                    height: units.dp(1); color: Style.divider
                                }
                            }
                        }

                        Item { width: 1; height: Style.spacingM }
                    }
                }
            }
        }
    }
}
