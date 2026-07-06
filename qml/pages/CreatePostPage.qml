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
    property bool catSheetOpen: false
    // On-screen-keyboard height; the formatting toolbar rides above it (same as
    // the video comment composer) so B/I/U stay reachable while typing.
    readonly property real kbHeight: Qt.inputMethod.visible ? Qt.inputMethod.keyboardRectangle.height : 0
    readonly property int titleMaxLength: 250
    property string coverImageUrl: ""
    property bool uploading: false
    // Inline article images. The plain-text editor would show raw <img> HTML,
    // so the editor holds readable "[image N]" placeholders instead; this array
    // maps N (1-based) to the uploaded URL, and publish() swaps the tokens back
    // into real <img> tags. Deleting a token in the editor drops that image.
    property var bodyImages: []
    // "Post to blockchain": on = broadcast on-chain (default), off = save to the
    // Serey DB only (no on-chain record, so no voting/rewards). Sent per-save.
    property bool postToBlockchain: true

    // When set, this page edits an existing post (sends its permlink to update in
    // place) instead of creating a new one. `saved` lets the opener refresh.
    property var editPost: null
    readonly property bool isEdit: !!editPost
    signal saved()

    // Categories are per-community (each community defines its own set), loaded
    // from the backend for the currently-selected source rather than hardcoded.
    property var categories: []
    property bool categoriesLoading: false
    property int catEpoch: 0

    function loadCategories() {
        var epoch = ++page.catEpoch;
        var prev = page.selectedCategory;
        page.categoriesLoading = true;
        CategoryService.listByCommunity(Config.baseUrl, Config.currentCommunityName, Session.token,
            function (names) {
                if (epoch !== page.catEpoch) return;   // stale community switch
                page.categoriesLoading = false;
                page.categories = names;
                if (names.indexOf(prev) < 0) page.selectedCategory = "";
            },
            function () {
                if (epoch !== page.catEpoch) return;
                page.categoriesLoading = false;
                page.categories = [];
            });
    }

    Component.onCompleted: {
        if (page.editPost) {
            titleField.text = page.editPost.title || "";
            // Strip the leading cover <img> we prepend on publish so it isn't
            // duplicated; the cover is restored from the post's thumbnail.
            var b = (page.editPost.body || "").replace(/^\s*<img[^>]*>\s*/i, "");
            // Turn remaining inline images into "[image N]" placeholders so the
            // editor shows readable text, not raw HTML; publish() restores them.
            var imgs = [];
            b = b.replace(/<img[^>]*src=["']([^"']*)["'][^>]*\/?>/gi, function (m, src) {
                imgs.push(src);
                return "[image " + imgs.length + "]";
            });
            page.bodyImages = imgs;
            bodyArea.text = b;
            page.coverImageUrl = page.editPost.thumbnail || "";
            // primaryCategory is a scalar (the categories array is wrapped by the
            // feed ListModel and loses [] indexing).
            page.selectedCategory = page.editPost.primaryCategory || "";
            // Prefill the toggle from the saved post (default on if absent).
            page.postToBlockchain = (page.editPost.postToBlockchain !== false);
        }
        loadCategories();   // captures selectedCategory above as the kept value
    }
    // The community can't change while this page is up (header is collapsed), but
    // react anyway so the list is always correct for the active source.
    Connections {
        target: Config
        function onCommunityIdChanged() { page.loadCategories() }
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
            enabled: !page.submitting && titleField.text.trim().length > 0 && bodyArea.text.trim().length > 0
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

    // Where the next picked image goes: the cover slot, or inline into the
    // article body at the cursor (toolbar image button). One shared
    // picker/uploader serves both.
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
                var txt = bodyArea.text;
                bodyArea.text = txt.substring(0, pos) + snippet + txt.substring(pos);
                bodyArea.cursorPosition = pos + snippet.length;
                Toast.success(Lang.tr("Image added"));
            } else {
                page.coverImageUrl = url;
                Toast.success(Lang.tr("Cover image uploaded"));
            }
        }
        onFailed: Toast.error(message)
    }

    function publish() {
        if (!Session.isLoggedIn) {
            Toast.error(Lang.tr("Please log in first."));
            return;
        }
        var body = bodyArea.text.trim();
        // Swap "[image N]" placeholders back into real <img> tags (see
        // bodyImages). Unknown numbers are left as typed.
        var imgs = page.bodyImages || [];
        body = body.replace(/\[image (\d+)\]/gi, function (m, n) {
            var u = imgs[parseInt(n, 10) - 1];
            return u ? '<img src="' + u + '" style="max-width:100%;height:auto;" />' : m;
        });
        // Prepend cover image to body if one was uploaded
        if (page.coverImageUrl.length > 0) {
            body = '<img src="' + page.coverImageUrl + '" style="max-width:100%;height:auto;" />\n' + body;
        }
        page.submitting = true;
        PostService.createPost(Config.baseUrl, {
            title: titleField.text.trim(),
            body: body,
            // On edit, keep the post in its own community (resolve by its title)
            // rather than the currently-selected source.
            communityId: page.isEdit ? 0 : Config.communityId,
            communityName: page.isEdit ? (page.editPost.community || Config.communityName)
                                       : Config.communityName,
            categories: page.selectedCategory || "general",
            postToBlockchain: page.postToBlockchain,
            permlink: page.isEdit ? (page.editPost.permlink || "") : "",
            // Also send the cover in `images` (→ json_meta.image), not just the
            // body <img>. The web derives a post's thumbnail from json_meta.image,
            // so without this the cover only shows inside the article, never as
            // the card/thumbnail. (Our app body-scrapes as a fallback, which is
            // why it looked fine on mobile.) The detail view dedupes it.
            images: page.coverImageUrl.length > 0 ? [page.coverImageUrl] : []
        }, Session.token,
        function (data) {
            page.submitting = false;
            Toast.success(page.isEdit ? Lang.tr("Post updated!") : Lang.tr("Post published!"));
            page.saved();
            page.pageStack.pop();
        },
        function (err) {
            page.submitting = false;
            Toast.error((err && err.message) ? err.message
                                             : (page.isEdit ? Lang.tr("Couldn't update post.")
                                                            : Lang.tr("Couldn't publish post.")));
        });
    }

    function wrapSelection(tagOpen, tagClose) {
        var start = bodyArea.selectionStart;
        var end = bodyArea.selectionEnd;
        var txt = bodyArea.text;
        if (start === end) {
            bodyArea.text = txt.substring(0, start) + tagOpen + tagClose + txt.substring(start);
            bodyArea.cursorPosition = start + tagOpen.length;
        } else {
            var sel = txt.substring(start, end);
            bodyArea.text = txt.substring(0, start) + tagOpen + sel + tagClose + txt.substring(end);
            bodyArea.cursorPosition = end + tagOpen.length + tagClose.length;
        }
        bodyArea.forceActiveFocus();
    }

    // Move active focus onto a neutral item so the on-screen keyboard drops.
    // Tapping any empty area of the form calls this (see the background
    // MouseArea below) — previously only re-tapping a field would dismiss it.
    Item { id: focusSink }
    function dismissKeyboard() {
        focusSink.forceActiveFocus();
        Qt.inputMethod.hide();
    }

    Flickable {
        id: scroll
        anchors { top: hdr.bottom; left: parent.left; right: parent.right; bottom: toolbar.top }
        contentHeight: col.height + Style.spacingL
        clip: true
        opacity: 0
        NumberAnimation on opacity { from: 0; to: 1; duration: 250; easing.type: Easing.OutQuad }

        // Sits behind the form (z -1); taps that miss a field fall through here
        // and dismiss the keyboard. A plain tap still flicks fine because the
        // Flickable steals drag gestures from child MouseAreas.
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

            // Body text area — outlined rounded box, tall
            Rectangle {
                width: parent.width
                height: Math.max(units.gu(25), bodyArea.contentHeight + Style.spacingM * 2)
                radius: Style.cardRadius
                color: "transparent"
                border.width: units.dp(1.5)
                border.color: bodyArea.activeFocus ? Style.brand : Style.divider

                TextEdit {
                    id: bodyArea
                    anchors {
                        fill: parent
                        margins: Style.spacingM
                    }
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
                    visible: bodyArea.text.length === 0 && !bodyArea.activeFocus && !Qt.inputMethod.visible
                    text: Lang.tr("Write your article here...")
                    color: Style.textSecondary
                    font.pixelSize: Style.fontRegular
                    font.family: Style.fontFor(text)
                }
            }

            // Category selector — hidden for communities that haven't defined any
            // categories yet (publish() already falls back to "general" for them).
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
                            ? page.selectedCategory
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
                                ? Lang.tr("Can earn votes and rewards.")
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

    // Formatting toolbar — rides above the on-screen keyboard while typing.
    Rectangle {
        id: toolbar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.bottomMargin: page.kbHeight
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
        height: units.gu(5.5)
        color: Style.surface

        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: units.dp(1); color: Style.divider
        }

        Row {
            anchors { left: parent.left; leftMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
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
                onClicked: page.wrapSelection("<a href=\"\">", "</a>")
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
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
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
                        text: Lang.tr("No categories for this community")
                        font.pixelSize: Style.fontSmall
                        color: Style.textSecondary
                    }
                }

                Repeater {
                    model: page.categories

                    delegate: AbstractButton {
                        width: catSheetCol.width
                        height: units.gu(6)
                        onClicked: {
                            page.selectedCategory = modelData;
                            catSheet.closeAnimated();
                        }

                        Row {
                            anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                            spacing: Style.spacingM

                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - checkIcon.width
                                text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                                font.pixelSize: Style.fontRegular
                                color: page.selectedCategory === modelData ? Style.brand : Style.textPrimary
                                font.weight: page.selectedCategory === modelData ? Font.DemiBold : Font.Normal
                            }

                            Icon {
                                id: checkIcon
                                anchors.verticalCenter: parent.verticalCenter
                                width: units.gu(2.5); height: width
                                name: "tick"
                                color: Style.brand
                                visible: page.selectedCategory === modelData
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
