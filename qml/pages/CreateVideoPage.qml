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

    // Local picked file + hosted results.
    property string videoFileUrl: ""   // file:// of the picked video
    property string videoUrl: ""       // hosted video URL (upload done)
    property string videoId: ""        // storage API id (for delete on discard)
    property string thumbUrl: ""       // hosted thumbnail URL (best-effort)
    property bool uploadingVideo: false
    property int uploadPercent: 0      // chunked-upload progress (0-100)
    property bool grabbingThumb: false
    // on = broadcast on-chain, off = Serey DB only
    property bool postToBlockchain: true

    readonly property bool hasCommunity: Config.communityId > 0
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
        // upload and thumbnail capture run in parallel
        page.uploadingVideo = true;
        page.uploadPercent = 0;
        Uploads.uploadVideo(Config.storageCreateUploadUrl, Session.token, fileUrl,
            function (url, job) {
                page.uploadingVideo = false;
                page.videoUrl = url;
                page.videoId = (job && job.id) ? job.id : "";
                // server-side thumbnail fallback
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
        // clean up orphaned upload on discard
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
            communityId: Config.communityId,
            communityName: Config.communityName
        }, Session.token,
        function (data) {
            page.submitting = false;
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

    // drives delay between status polls
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

    // reads slices from disk, avoids loading whole video into RAM
    FileUtils.FileChunkReader { id: chunkReader }

    // survives app restarts, resumes upload
    Settings {
        id: uploadResumeStore
        category: "VideoUpload"
        property string pendingUpload: ""
    }

    Component.onCompleted: {
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

    // grabs a frame as thumbnail; failure leaves thumbUrl empty
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

            // Community gate notice.
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

            // Title field (Lomiri underline input — bottom border, no box).
            Item {
                width: parent.width
                height: Math.max(units.gu(5), titleField.contentHeight + Style.spacingM)

                // catches taps on the surrounding gap
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
                    wrapMode: Text.WordWrap
                }
                Label {
                    anchors { left: titleField.left; top: titleField.top }
                    visible: titleField.text.length === 0 && !titleField.activeFocus
                    text: Lang.tr("Video title")
                    color: Style.textSecondary
                    font.pixelSize: Style.fontRegular
                    font.family: Style.fontFor(text)
                }
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: titleField.activeFocus ? units.dp(2) : units.dp(1)
                    color: titleField.activeFocus ? Style.brand : Style.divider
                }
            }

            // Description field (Lomiri underline input).
            Item {
                width: parent.width
                height: Math.max(units.gu(10), descField.contentHeight + Style.spacingM)

                // catches taps below the one-line editor
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        descField.forceActiveFocus();
                        descField.cursorPosition = descField.length;
                        Qt.inputMethod.show();
                    }
                }

                TextEdit {
                    id: descField
                    anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: Style.spacingS }
                    font.family: Style.fontFor(text)
                    font.pixelSize: Style.fontRegular
                    color: Style.textPrimary
                    wrapMode: Text.WordWrap
                }
                Label {
                    anchors { left: descField.left; top: descField.top }
                    visible: descField.text.length === 0 && !descField.activeFocus
                    text: Lang.tr("Describe your video...")
                    color: Style.textSecondary
                    font.pixelSize: Style.fontRegular
                    font.family: Style.fontFor(text)
                }
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: descField.activeFocus ? units.dp(2) : units.dp(1)
                    color: descField.activeFocus ? Style.brand : Style.divider
                }
            }

            // Post to blockchain toggle
            Row {
                width: parent.width
                spacing: Style.spacingM

                Column {
                    width: parent.width - vidChainSwitch.width - Style.spacingM
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
                    id: vidChainSwitch
                    anchors.verticalCenter: parent.verticalCenter
                    checked: page.postToBlockchain
                    onClicked: page.postToBlockchain = !page.postToBlockchain
                }
            }

            Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

            Label {
                text: Lang.tr("Video")
                font.pixelSize: Style.fontSmall
                font.weight: Font.DemiBold
                color: Style.textPrimary
            }

            // Empty state: pick a video.
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

            // Picked state: thumbnail preview + status.
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

                // Center status: spinner while uploading / capturing, check when done.
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
                        // 100% = server validating/remuxing
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

                // Remove button.
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

    // Submit overlay.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(1, 1, 1, 0.7)
        visible: page.submitting
        z: 100
        ActivityIndicator { anchors.centerIn: parent; running: page.submitting }
    }
}
