import QtQuick 2.7
import Qt.labs.settings 1.0
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3 as Popups
import Serey.FileUtils 1.0 as FileUtils
import "../Theme"
import "../Session"
import "../components"
import "../services/PostService.js" as PostService
import "../services/Uploads.js" as Uploads

Page {
    id: page

    property bool submitting: false
    readonly property real maxContentWidth: units.gu(60)
    readonly property int titleMaxLength: 100
    readonly property int descMaxLength: 2500

    // Local picked file + hosted results.
    property string videoFileUrl: ""   // file:// of the picked video
    property string videoUrl: ""       // hosted video URL (upload done)
    property string videoId: ""        // storage API id (for delete on discard)
    property string thumbUrl: ""       // hosted thumbnail URL (best-effort)
    property bool uploadingVideo: false
    property int uploadPercent: 0      // chunked-upload progress (0-100)
    property bool grabbingThumb: false
    // "Post on the blockchain": on = broadcast on-chain (default), off = save to the Serey DB only (no voting/rewards).
    property bool postToBlockchain: true
    // Publishing scope: the highest community this video may surface under (its
    // ceiling). 0 = no ceiling, i.e. everywhere including the Global feed.
    property int publishCeilingId: 0

    // Generated from the target's real ancestor chain - see CreatePostPage.
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

    // Opens on the last choice made for this community (see Session.loadPostScope).
    function _applyRememberedScope() {
        var saved = Session.loadPostScope(page.postCommunityId);
        page.publishCeilingId = (saved === undefined) ? 0 : Number(saved);
    }
    onPostCommunityIdChanged: page._applyRememberedScope()

    // Chosen in PostCommunityPicker before this page opens; unset = post into the browsed source
    property var targetCommunity: null
    readonly property int postCommunityId: page.targetCommunity ? Number(page.targetCommunity.id)
                                                                 : Config.communityId
    readonly property string postCommunityName: page.targetCommunity ? page.targetCommunity.name
                                                                      : Config.communityName

    readonly property bool hasCommunity: page.postCommunityId > 0
    // See CreatePostPage: the postable Global record has a real id, so only its dns
    // identifies it. "Also publish to Global" makes no sense when Global is the target.
    readonly property bool targetIsGlobal: {
        var id = page.postCommunityId;
        if (!(id > 0)) return true;
        var c = Config.communityInfoFor(id);
        return !!c && (c.dns || "") === Config.sources[0].dns;
    }
    readonly property bool canPublish: !page.submitting && !page.uploadingVideo
                                       && page.videoUrl.length > 0
                                       && titleField.text.trim().length > 0
                                       && descField.text.trim().length > 0
                                       && page.hasCommunity

    signal saved()

    header: Item { height: 0 }

    // --- Actions -----------------------------------------------------------

    function pickVideo() {
        if (!Session.isLoggedIn) { Toast.error(Lang.tr("Please log in first.")); return; }
        if (!page.hasCommunity) {
            Toast.error(Lang.tr("Pick a platform (not Global) from the top bar first."));
            return;
        }
        if (page.uploadingVideo) return;
        Popups.PopupUtils.open(videoPickerComp);
    }

    function onVideoPicked(fileUrl) {
        page.videoFileUrl = fileUrl;
        page.videoUrl = "";
        page.videoId = "";
        page.thumbUrl = "";
        // Start the upload and the (optional) thumbnail capture in parallel.
        page.uploadingVideo = true;
        page.uploadPercent = 0;
        Uploads.uploadVideo(Config.storageCreateUploadUrl, Session.token, fileUrl,
            function (url, job) {
                page.uploadingVideo = false;
                page.videoUrl = url;
                page.videoId = (job && job.id) ? job.id : "";
                // Server-side thumbnail as fallback if the local frame grab failed or hasn't produced one.
                if (!page.thumbUrl && job && job.thumbnail_url)
                    page.thumbUrl = job.thumbnail_url;
                Toast.success(Lang.tr("Video uploaded"));
            },
            function (err) {
                page.uploadingVideo = false;
                page.videoFileUrl = "";
                Toast.error((err && err.message) ? err.message : Lang.tr("Video upload failed."));
            },
            function (percent) {
                page.uploadPercent = percent;
            });

        page.grabbingThumb = true;
        thumbGrabber.grab(fileUrl);
    }

    function clearVideo() {
        Uploads.abort();
        // Post-upload discard: delete the now-orphaned file from the storage server.
        if (page.videoId)
            Uploads.deleteVideo(Config.storageDeleteUploadUrl, Session.token, page.videoId);
        page.videoFileUrl = "";
        page.videoUrl = "";
        page.videoId = "";
        page.thumbUrl = "";
        page.uploadingVideo = false;
        page.uploadPercent = 0;
        page.grabbingThumb = false;
    }

    function publish() {
        if (!page.canPublish) return;
        page.submitting = true;
        PostService.createVideoPost(Config.baseUrl, {
            title: titleField.text.trim(),
            desc: descField.text.trim(),
            body: descField.text.trim(),
            videoUrl: page.videoUrl,
            thumbUrl: page.thumbUrl,
            postToBlockchain: page.postToBlockchain,
            publishCeilingId: page.targetIsGlobal ? 0 : page.publishCeilingId,
            communityId: page.postCommunityId,
            communityName: page.postCommunityName
        }, Session.token,
        function (data) {
            page.submitting = false;
            // Remember the scope for this community so the next upload starts there.
            if (!page.targetIsGlobal)
                Session.savePostScope(page.postCommunityId, page.publishCeilingId);
            Toast.success(Lang.tr("Video published!"));
            page.saved();
            page.pageStack.pop();
        },
        function (err) {
            page.submitting = false;
            Toast.error((err && err.message) ? err.message : Lang.tr("Couldn't publish video."));
        });
    }

    Item { id: focusSink }
    function dismissKeyboard() { focusSink.forceActiveFocus(); Qt.inputMethod.hide(); }

    // Uploads.js has no setTimeout (QML JS library); this Timer drives the delay between status polls.
    Timer {
        id: uploadDelayTimer
        repeat: false
        property var pending: null
        onTriggered: {
            var fn = pending;
            pending = null;
            if (fn) fn();
        }
    }

    // C++ streaming file reader: uploads read 25 MB slices from disk instead of loading the whole video into RAM (big files OOM-crashed phones).
    FileUtils.FileChunkReader { id: chunkReader }

    // Survives app restarts, letting Uploads.js resume a half-finished upload instead of re-sending from byte 0.
    Settings {
        id: uploadResumeStore
        category: "VideoUpload"
        property string pendingUpload: ""
    }

    Component.onCompleted: {
        page._applyRememberedScope();
        Uploads.setDelayHook(function (ms, fn) {
            uploadDelayTimer.pending = fn;
            uploadDelayTimer.interval = ms;
            uploadDelayTimer.restart();
        });
        Uploads.setFileReader(chunkReader);
        Uploads.setUploadStore({
            get: function () { return uploadResumeStore.pendingUpload; },
            set: function (v) { uploadResumeStore.pendingUpload = v; }
        });
    }

    // --- Picker + helpers --------------------------------------------------

    Component {
        id: videoPickerComp
        VideoPicker { onPicked: page.onVideoPicked(fileUrl) }
    }

    // Captures a frame from the picked local video as a JPEG data URL and uploads it as the thumbnail; failure just leaves thumbUrl empty.
    VideoThumbnailGrabber {
        id: thumbGrabber
        onGrabbed: Uploads.uploadImageData(Config.uploadUrl, Config.uploadSecret, dataUrl,
            function (url) { page.thumbUrl = url; page.grabbingThumb = false; },
            function () { page.grabbingThumb = false; })
        onFailed: page.grabbingThumb = false
    }

    // --- Header ------------------------------------------------------------

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
            Icon { anchors.centerIn: parent; width: units.gu(2.5); height: width; name: "close"; color: Style.textPrimary }
        }

        Label {
            anchors { left: parent.left; leftMargin: units.gu(7); right: pubBtn.left; rightMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
            text: Lang.tr("Upload Video")
            font.pixelSize: Style.fontLarge
            font.family: Style.fontFor(text)
            color: Style.textPrimary
            elide: Text.ElideRight
        }

        AbstractButton {
            id: pubBtn
            anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
            width: pubLabel.implicitWidth + Style.spacingM * 2
            height: units.gu(4)
            enabled: page.canPublish
            onClicked: page.publish()

            Rectangle {
                anchors.fill: parent
                radius: Style.cardRadius
                color: parent.enabled ? Style.brand : Style.iconBackground
            }
            Label {
                id: pubLabel
                anchors.centerIn: parent
                text: page.submitting ? Lang.tr("Posting…") : Lang.tr("Publish")
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

    // --- Form --------------------------------------------------------------

    Flickable {
        id: scroll
        anchors { top: hdr.bottom; bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
        width: Math.min(parent.width, page.maxContentWidth)
        contentHeight: col.height + Style.spacingL
        clip: true
        opacity: 0
        NumberAnimation on opacity { from: 0; to: 1; duration: 250; easing.type: Easing.OutQuad }

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
                visible: !page.hasCommunity
                height: gateLabel.implicitHeight + Style.spacingM * 2
                radius: Style.cardRadius
                color: Style.iconBackground
                Label {
                    id: gateLabel
                    anchors { fill: parent; margins: Style.spacingM }
                    text: Lang.tr("Pick a platform (not Global) from the top bar to post a video.")
                    wrapMode: Text.WordWrap
                    font.family: Style.fontFor(text)
                    font.pixelSize: Style.fontSmall
                    color: Style.textSecondary
                    verticalAlignment: Text.AlignVCenter
                }
            }

            // Title field (Lomiri underline input - bottom border, no box).
            Item {
                width: parent.width
                height: Math.max(units.gu(5), titleField.contentHeight + Style.spacingM + titleCountLabel.height)

                // Declared FIRST so it sits under the editor, catching taps on the padding gap
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        titleField.forceActiveFocus();
                        titleField.cursorPosition = titleField.length;
                        Qt.inputMethod.show();
                    }
                }

                TextEdit {
                    id: titleField
                    anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: Style.spacingS }
                    font.family: Style.fontFor(text)
                    font.pixelSize: Style.fontRegular
                    color: Style.textPrimary
                    wrapMode: Text.Wrap
                    // TextEdit has no native maximumLength (unlike TextField)
                    onTextChanged: if (text.length > page.titleMaxLength) {
                        var cp = cursorPosition;
                        text = text.substring(0, page.titleMaxLength);
                        cursorPosition = Math.min(cp, text.length);
                    }
                }
                Label {
                    anchors { left: titleField.left; top: titleField.top }
                    visible: titleField.text.length === 0 && !titleField.activeFocus
                    text: Lang.tr("Video title")
                    color: Style.textSecondary
                    font.pixelSize: Style.fontRegular
                    font.family: Style.fontFor(text)
                }
                Label {
                    id: titleCountLabel
                    anchors { right: parent.right; bottom: parent.bottom; bottomMargin: units.dp(2) }
                    visible: titleField.activeFocus || titleField.text.length > 0
                    readonly property int liveLength: titleField.text.length + titleField.preeditText.length
                    text: liveLength + "/" + page.titleMaxLength
                    font.pixelSize: Style.fontXSmall
                    color: liveLength >= page.titleMaxLength ? Style.danger : Style.textSecondary
                }
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: titleField.activeFocus ? units.dp(2) : units.dp(1)
                    color: titleField.activeFocus ? Style.brand : Style.divider
                }
            }

            // Description field. Lomiri TextArea (not plain TextEdit): only the styled component
            Item {
                width: parent.width
                height: descField.height + Style.spacingM + descCountLabel.height

                TextArea {
                    id: descField
                    anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: Style.spacingS }
                    height: units.gu(10)
                    wrapMode: Text.Wrap
                    font.family: Style.fontFor(text)
                    font.pixelSize: Style.fontRegular
                    color: Style.textPrimary
                    StyleHints {
                        backgroundColor: "transparent"
                        borderColor: "transparent"
                    }
                    // TextArea has no native maximumLength (unlike TextField)
                    onTextChanged: if (text.length > page.descMaxLength) {
                        var cp = cursorPosition;
                        text = text.substring(0, page.descMaxLength);
                        cursorPosition = Math.min(cp, text.length);
                    }

                    // Custom placeholder, grey, like FormField/MultilineField
                    Label {
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.spacingS }
                        text: Lang.tr("Describe your video...")
                        visible: descField.text.length === 0 && !descField.inputMethodComposing
                        wrapMode: Text.Wrap
                        font.pixelSize: Style.fontRegular
                        font.family: Style.fontFor(text)
                        color: Style.textSecondary
                        opacity: descField.activeFocus ? 0.8 : 0.6
                    }
                }
                Label {
                    id: descCountLabel
                    anchors { right: parent.right; bottom: parent.bottom; bottomMargin: units.dp(2) }
                    visible: descField.activeFocus || descField.text.length > 0
                    text: descField.text.length + "/" + page.descMaxLength
                    font.pixelSize: Style.fontXSmall
                    color: descField.text.length >= page.descMaxLength ? Style.danger : Style.textSecondary
                }
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: descField.activeFocus ? units.dp(2) : units.dp(1)
                    color: descField.activeFocus ? Style.brand : Style.divider
                }
            }

            Row {
                width: parent.width
                spacing: Style.spacingM

                Column {
                    width: parent.width - vidChainSwitch.width - Style.spacingM
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
                        text: page.postToBlockchain
                            ? Lang.tr("The title and the link are permanently recorded on the blockchain. This allows you to prove that you are the creator and receive SRY rewards. The video itself simply remains on a server.")
                            : Lang.tr("Serey only, no votes or rewards.")
                        font.pixelSize: Style.fontXSmall
                        font.family: Style.fontFor(text)
                        color: Style.textSecondary
                        wrapMode: Text.WordWrap
                    }
                }

                Switch {
                    id: vidChainSwitch
                    anchors.verticalCenter: parent.verticalCenter
                    checked: page.postToBlockchain
                    onClicked: page.postToBlockchain = !page.postToBlockchain
                }
            }

            // Publishing scope. Hidden on Global: that IS the combined feed, so
            // there is nothing to narrow the post down to. A dropdown rather than
            // a switch because the tree has more than two levels.
            Item {
                width: parent.width
                visible: !page.targetIsGlobal
                height: visible ? vidScopeCol.implicitHeight : 0

                Column {
                    id: vidScopeCol
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
                        id: vidScopeRow
                        width: parent.width
                        height: units.gu(5)
                        onClicked: vidScopeSheet.show(page._scopeSheetItems(), vidScopeRow)

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
                                    width: parent.width - vidScopeChevron.width - Style.spacingS
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: page.scopeLabel
                                    elide: Text.ElideRight
                                    font.pixelSize: Style.fontRegular
                                    font.family: Style.fontFor(text)
                                    color: Style.textPrimary
                                }
                                Icon {
                                    id: vidScopeChevron
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

            Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

            Label {
                text: Lang.tr("Video")
                font.pixelSize: Style.fontSmall
                font.weight: Font.DemiBold
                color: Style.textPrimary
            }

            AbstractButton {
                width: parent.width
                height: units.gu(16)
                visible: page.videoFileUrl.length === 0
                enabled: !page.uploadingVideo
                onClicked: page.pickVideo()

                Rectangle {
                    anchors.fill: parent
                    radius: Style.cardRadius
                    color: Style.iconBackground
                }
                Column {
                    anchors.centerIn: parent
                    spacing: Style.spacingXs
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: units.gu(5); height: width; radius: width / 2
                        color: Style.brand
                        Icon { anchors.centerIn: parent; width: units.gu(2.5); height: width; name: "add"; color: Style.textOnBrand }
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Lang.tr("Add video")
                        font.pixelSize: Style.fontSmall
                        color: Style.textSecondary
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Lang.tr("MP4, WEBM, MOV · up to 2 GB")
                        font.pixelSize: Style.fontXSmall
                        color: Style.textSecondary
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: units.gu(20)
                visible: page.videoFileUrl.length > 0
                radius: Style.cardRadius
                color: "black"
                clip: true

                Image {
                    anchors.fill: parent
                    source: page.thumbUrl
                    visible: page.thumbUrl.length > 0
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }

                Column {
                    anchors.centerIn: parent
                    spacing: Style.spacingXs
                    ActivityIndicator {
                        anchors.horizontalCenter: parent.horizontalCenter
                        running: page.uploadingVideo || (page.grabbingThumb && page.thumbUrl.length === 0)
                        visible: running
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: page.uploadingVideo
                        // 100% = all chunks sent; the server is then validating/remuxing before it returns the URL.
                        text: page.uploadPercent >= 100
                              ? Lang.tr("Processing video…")
                              : (page.uploadPercent > 0
                                 ? Lang.tr("Uploading video…") + " " + page.uploadPercent + "%"
                                 : Lang.tr("Uploading video…"))
                        font.pixelSize: Style.fontSmall
                        color: "white"
                    }
                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: !page.uploadingVideo && page.videoUrl.length > 0
                        width: units.gu(4); height: width
                        name: "tick"
                        color: "white"
                    }
                }

                AbstractButton {
                    anchors { top: parent.top; right: parent.right; topMargin: units.dp(6); rightMargin: units.dp(6) }
                    width: units.gu(3); height: width
                    enabled: !page.submitting
                    onClicked: page.clearVideo()
                    Rectangle { anchors.fill: parent; radius: width / 2; color: Qt.rgba(0, 0, 0, 0.6) }
                    Icon { anchors.centerIn: parent; width: units.gu(2); height: width; name: "close"; color: "white" }
                }
            }

            Item { width: 1; height: Style.spacingL }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(1, 1, 1, 0.7)
        visible: page.submitting
        z: 100
        ActivityIndicator { anchors.centerIn: parent; running: page.submitting }
    }

    // Publishing-scope picker (dropdown on desktop, bottom sheet on touch).
    ActionBottomSheet { id: vidScopeSheet }
}
