import QtQuick 2.7
import QtQuick.Window 2.2
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../services/PostService.js" as PostService
import "../services/AccountService.js" as AccountService
import "../services/ReportService.js" as ReportService
import "../services/HiddenPosts.js" as HiddenPosts
import "../services/BlockedUsers.js" as BlockedUsers
import "../services/YouTube.js" as YouTube

Item {
    id: sheet
    anchors.fill: parent
    visible: PostActions.visible
    z: 1500

    readonly property string authorName: PostActions.post ? (PostActions.post.author || "") : ""
    // The viewer owns this post, so show Edit/Delete instead of moderation actions (you can't report or block yourself).
    readonly property bool isOwn: Session.isLoggedIn && authorName !== "" && authorName === Session.username
    // No video editor exists, so Edit is offered for blog/gallery only.
    readonly property bool canEdit: isOwn && PostActions.kind !== "video"
    // Opened straight at a sub-step (report/delete/block), bypassing the main menu
    readonly property bool openedDirectly: PostActions.startStep !== 0
    property bool deleting: false
    property bool blocking: false
    property bool reporting: false
    property var reportTypes: []
    property bool reportTypesLoaded: false
    property bool reportTypesLoading: false
    property string selectedReportTypeId: ""
    // 0 = main menu, 1 = report reasons, 2 = delete confirm, 3 = block confirm, 4 = edit video caption.
    property int step: 0
    property bool savingCaption: false

    // Lift the sheet above the OSK (the edit-caption step has text inputs).
    readonly property real kbHeight: Qt.inputMethod.visible ? Qt.inputMethod.keyboardRectangle.height : 0

    // Keyboard nav: Up/Down/Tab move a highlight, Enter/Space activates, Escape backs out
    property var navRows: []
    property int navIndex: -1
    readonly property Item navCurrent: (navIndex >= 0 && navIndex < navRows.length) ? navRows[navIndex] : null
    // Whatever held keyboard focus before the sheet opened (e.g. the focused card); restored on close.
    property var _prevFocus: null

    function _rebuildNav() {
        if (!visible) { navRows = []; navIndex = -1; return; }
        var rows = [];
        if (step === 0) {
            var candidates = [saveOfflineBtn, saveVideoBtn, editPostBtn, editCaptionBtn, deletePostBtn,
                              hidePostBtn, reportPostBtn, blockUserBtn];
            for (var i = 0; i < candidates.length; i++)
                if (candidates[i].visible) rows.push(candidates[i]);
        } else if (step === 1) {
            for (var j = 0; j < reportRepeater.count; j++) {
                var it = reportRepeater.itemAt(j);
                if (it) rows.push(it);
            }
        } else if (step === 2) {
            rows = [deleteConfirmBtn, deleteCancelBtn];
        } else if (step === 3) {
            rows = [blockConfirmBtn, blockCancelBtn];
        }
        navRows = rows;
        navIndex = -1;
    }

    function _navMove(delta) {
        if (navRows.length === 0) return;
        navIndex = (navIndex < 0)
            ? (delta > 0 ? 0 : navRows.length - 1)
            : (navIndex + delta + navRows.length) % navRows.length;
    }

    Keys.onPressed: {
        var busy = (step === 1 && reporting) || (step === 2 && deleting)
                || (step === 3 && blocking) || (step === 4 && savingCaption);
        if (event.key === Qt.Key_Escape) {
            if (!busy) { if (step === 0) closeSheet(); else step = 0; }
            event.accepted = true;
        } else if (step === 4) {
            // Text-entry step: trap Tab between the two fields so focus can't tunnel to the page
            if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                if (captionTitleField.activeFocus) captionDescField.forceActiveFocus();
                else captionTitleField.forceActiveFocus();
                event.accepted = true;
            }
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
            _navMove(1); event.accepted = true;
        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
            _navMove(-1); event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            if (navCurrent && navCurrent.visible && navCurrent.enabled) navCurrent.clicked();
            event.accepted = true;
        }
    }

    onStepChanged: {
        if (step !== 4) {
            Qt.inputMethod.hide();
            // Reclaim key events from the caption fields when leaving the edit step.
            if (visible) sheet.forceActiveFocus();
        }
        Qt.callLater(_rebuildNav);
    }

    // Report reasons arrive async; refresh the arrow-key row list when they land.
    onReportTypesChanged: if (step === 1) Qt.callLater(_rebuildNav)

    onVisibleChanged: {
        if (!visible) {
            step = 0;
            selectedReportTypeId = "";
            // Clear in-flight busy flags so a sheet dismissed mid-request doesn't reopen stuck on "Blocking..."/disabled rows.
            reporting = false;
            blocking = false;
            navRows = []; navIndex = -1;
            // Hand keyboard focus back so the card's focus ring / arrow keys keep working.
            if (_prevFocus) {
                try { if (_prevFocus.visible) _prevFocus.forceActiveFocus(); } catch (e) { /* item destroyed since */ }
                _prevFocus = null;
            }
        } else {
            step = PostActions.startStep;
            backdropFade.start();
            if (sheetRect.wide) { sheetFadeIn.start(); sheetScaleIn.start(); }
            else sheetSlide.start();
            // Guard on !reportTypesLoading too, so reopening before the first fetch resolves doesn't fire a duplicate concurrent request.
            if (!reportTypesLoaded && !reportTypesLoading) _loadReportTypes();
            _prevFocus = Window.activeFocusItem;
            sheet.forceActiveFocus();
            Qt.callLater(_rebuildNav);
        }
    }

    function _loadReportTypes() {
        sheet.reportTypesLoading = true;
        ReportService.getReportTypes(Config.baseUrl,
            function (arr) {
                sheet.reportTypesLoading = false;
                sheet.reportTypes = arr || [];
                // Only latch as "loaded" on a non-empty result; an empty list means try again next open rather than showing a dead panel.
                sheet.reportTypesLoaded = sheet.reportTypes.length > 0;
            },
            function (err) {
                // Leave reportTypesLoaded false so reopening the sheet retries; no hardcoded fallback, the backend owns the ids.
                sheet.reportTypesLoading = false;
                sheet.reportTypesLoaded = false;
                Toast.error((err && err.message) ? err.message
                            : Lang.tr("Couldn't load report reasons. Please try again."));
            });
    }

    function closeSheet() {
        backdropFadeOut.start();
        if (sheetRect.wide) sheetFadeOut.start();
        else sheetSlideOut.start();
    }

    function submitReport(typeId, typeName) {
        if (typeId === "" || typeId === undefined || typeId === null) {
            Toast.error(Lang.tr("Couldn't submit this report reason."));
            return;
        }
        if (!Session.isLoggedIn) { Toast.error(Lang.tr("Please log in to report.")); return; }
        var p = PostActions.post;
        if (!p) return;
        // Backend expects the post id; fall back to permlink only if present.
        var postId = (p.id !== undefined && p.id !== null) ? p.id : (p.permlink || "");
        if (postId === "" || postId === null || postId === undefined) {
            Toast.error(Lang.tr("Failed to submit report."));
            return;
        }
        sheet.reporting = true;
        ReportService.submitReport(Config.baseUrl, Session.token,
            postId, typeId, typeName || "Report",
            function () {
                sheet.reporting = false;
                sheet.closeSheet();
                Toast.show(Lang.tr("Thanks for your report"));
            },
            function (err) {
                sheet.reporting = false;
                Toast.error((err && err.message) ? err.message : Lang.tr("Failed to submit report."));
            });
    }

    function doBlock() {
        var username = sheet.authorName;
        if (!username) return;
        sheet.blocking = true;
        AccountService.toggleBlock(Config.baseUrl, Session.token, username, "ADD",
            function () {
                sheet.blocking = false;
                BlockedUsers.add(username);   // persist so feeds stay filtered on reload
                PostActions.userBlocked(username);
                sheet.closeSheet();
                Toast.show(Lang.tr("%1 blocked").arg(username));
            },
            function (err) {
                sheet.blocking = false;
                Toast.error((err && err.message) ? err.message : Lang.tr("Failed to block user."));
            });
    }

    // The stored description is HTML; strip tags for editing and rebuild <p> paragraphs (text re-escaped) when saving.
    function _htmlToPlain(html) {
        return (html || "")
            .replace(/<\/p>\s*<p[^>]*>/gi, "\n")
            .replace(/<br\s*\/?>/gi, "\n")
            .replace(/<[^>]+>/g, "")
            .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
            .replace(/&quot;/g, "\"").replace(/&#39;/g, "'").replace(/&nbsp;/g, " ")
            .trim();
    }
    function _plainToHtml(text) {
        var lines = (text || "").split(/\n+/);
        var out = [];
        for (var i = 0; i < lines.length; i++) {
            var t = lines[i].trim();
            if (t.length === 0) continue;
            t = t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
            out.push("<p>" + t + "</p>");
        }
        return out.join("");
    }

    // Update a video post's caption in place by reusing the create-or-update endpoint with the existing permlink; other fields resent unchanged.
    function doSaveCaption() {
        var p = PostActions.post;
        if (!p || sheet.savingCaption) return;
        var newTitle = captionTitleField.text.trim();
        if (newTitle.length === 0) { Toast.error(Lang.tr("Title can't be empty.")); return; }
        var newBody = sheet._plainToHtml(captionDescField.text);
        sheet.savingCaption = true;
        PostService.createVideoPost(Config.baseUrl, {
            title: newTitle,
            desc: newBody,
            permlink: p.permlink || "",
            videoUrl: p.videoLink || "",
            thumbUrl: p.thumbnail || "",
            communityId: p.communityId || 0,
            communityName: p.community || "",
            postToBlockchain: p.postToBlockchain !== false
        }, Session.token,
            function () {
                sheet.savingCaption = false;
                PostActions.postUpdated(p.author || "", p.permlink || "", newTitle, newBody);
                sheet.closeSheet();
                Toast.success(Lang.tr("Post updated!"));
            },
            function (err) {
                sheet.savingCaption = false;
                Toast.error((err && err.message) ? err.message : Lang.tr("Couldn't update post."));
            });
    }

    // Video offline download: direct-file downloads as-is, YouTube resolves via InnerTube first
    function _isDirectFile(u) {
        return /\.(mp4|webm|m4v|mov)(\?|$)/i.test(u || "");
    }
    function _videoRemoteUrl(v) {
        if (!v) return "";
        if (v.platform === "SEREY") return v.videoLink || v.embedUrl || "";
        if (_isDirectFile(v.videoLink)) return v.videoLink;
        if (_isDirectFile(v.embedUrl)) return v.embedUrl;
        return "";
    }
    function _videoYoutubeId(v) {
        if (!v) return "";
        if (v.platform === "YOUTUBE" && (v.videoId || "").length === 11) return v.videoId;
        var s = (v.embedUrl || "") + " " + (v.videoLink || "");
        var m = s.match(/(?:youtube\.com\/(?:embed\/|watch\?v=)|youtu\.be\/)([A-Za-z0-9_-]{11})/);
        return m ? m[1] : "";
    }
    function _videoIsYouTube(v) {
        return v && v.platform === "YOUTUBE" && _videoYoutubeId(v).length > 0;
    }
    function _videoCanDownload(v) {
        return _videoRemoteUrl(v).length > 0 || _videoIsYouTube(v);
    }
    function doVideoDownloadToggle() {
        var p = PostActions.post;
        if (!p || saveVideoBtn._busy) return;
        var pl = p.permlink || "";
        if (pl.length === 0) return;
        if (saveVideoBtn._saved) { Downloads.remove(pl); sheet.closeSheet(); return; }
        var direct = sheet._videoRemoteUrl(p);
        if (direct.length > 0) {
            Downloads.start(p, direct);
            Toast.show(Lang.tr("Downloading video…"));
            sheet.closeSheet();
            return;
        }
        if (sheet._videoIsYouTube(p)) {
            var id = sheet._videoYoutubeId(p);
            saveVideoBtn._extracting = true;
            Toast.show(Lang.tr("Preparing download…"));
            YouTube.extract(id, function (result, errMsg) {
                saveVideoBtn._extracting = false;
                if (result && result.url) {
                    Downloads.start(p, result.url);
                    Toast.show(Lang.tr("Downloading video…"));
                } else {
                    Toast.error(Lang.tr("This YouTube video can't be downloaded."));
                }
                sheet.closeSheet();
            });
        }
    }

    // Delete the viewer's own post, then ask feed pages to prune the row.
    function doDelete() {
        var p = PostActions.post;
        if (!p) return;
        sheet.deleting = true;
        PostService.deletePost(Config.baseUrl, Session.username, p.permlink || "", Session.token,
            function () {
                sheet.deleting = false;
                PostActions.postDeleted(p.author || "", p.permlink || "");
                sheet.closeSheet();
                Toast.success(Lang.tr("Post deleted."));
            },
            function (err) {
                sheet.deleting = false;
                Toast.error((err && err.message) ? err.message : Lang.tr("Couldn't delete the post."));
            });
    }

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.4)
        opacity: 0
        MouseArea { anchors.fill: parent; onClicked: sheet.closeSheet() }
    }
    NumberAnimation { id: backdropFade; target: backdrop; property: "opacity"; from: 0; to: 1; duration: 200 }
    NumberAnimation { id: backdropFadeOut; target: backdrop; property: "opacity"; to: 0; duration: 200 }

    // Bottom sheet on phone; true centered modal on desktop, no drag handle (not swipe-dismiss)
    Rectangle {
        id: sheetRect
        readonly property bool wide: Config.wideMode
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: sheetRect.wide ? undefined : parent.bottom
            verticalCenter: sheetRect.wide ? parent.verticalCenter : undefined
            bottomMargin: sheetRect.wide ? 0 : sheet.kbHeight
        }
        width: sheetRect.wide ? Math.min(parent.width - units.gu(4), units.gu(60)) : parent.width
        height: (sheet.step === 0 ? mainCol.height
                 : sheet.step === 1 ? reportCol.height
                 : sheet.step === 2 ? deleteCol.height
                 : sheet.step === 4 ? editCol.height
                 : blockCol.height) + units.gu(4)
        radius: units.dp(16)
        color: Style.surface

        // Phone: slides up from the bottom.
        transform: Translate { id: sheetTranslate; y: sheetRect.wide ? 0 : sheetTranslate.y }
        NumberAnimation { id: sheetSlide; target: sheetTranslate; property: "y"; from: sheetRect.height + units.gu(4); to: 0; duration: 300; easing.type: Easing.OutCubic }
        NumberAnimation { id: sheetSlideOut; target: sheetTranslate; property: "y"; to: sheetRect.height + units.gu(4); duration: 250; easing.type: Easing.InCubic; onStopped: PostActions.close() }

        // Desktop: fades and scales in centered, like a standard modal dialog.
        scale: 1
        opacity: 1
        NumberAnimation { id: sheetFadeIn; target: sheetRect; property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutQuad }
        NumberAnimation { id: sheetScaleIn; target: sheetRect; property: "scale"; from: 0.94; to: 1; duration: 200; easing.type: Easing.OutQuad }
        NumberAnimation { id: sheetFadeOut; target: sheetRect; property: "opacity"; to: 0; duration: 150; easing.type: Easing.InQuad; onStopped: PostActions.close() }

        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }

        Rectangle {
            visible: !sheetRect.wide
            anchors { top: parent.top; topMargin: Style.spacingS; horizontalCenter: parent.horizontalCenter }
            width: units.gu(4.5)
            height: units.dp(4)
            radius: units.dp(2)
            color: Style.lightGray
        }

        // ===================== Step 0: Main menu =====================
        Column {
            id: mainCol
            anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: Style.spacingL }
            spacing: 0
            visible: sheet.step === 0

            Item { width: 1; height: Style.spacingS }
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: sheet.isOwn
                text: Lang.tr("Post options")
                font.pixelSize: Style.fontLarge
                font.weight: Font.DemiBold
                color: Style.textPrimary
            }
            Item { width: 1; height: Style.spacingL }

            // Save for offline (blog only) fetches the full article first since the feed view-model only carries an excerpt, then persists it; toggles to "Remove from saved" when already saved.
            AbstractButton {
                id: saveOfflineBtn
                width: parent.width; height: units.gu(8)
                visible: PostActions.kind === "blog" && saveOfflineBtn._pl.length > 0
                readonly property string _pl: PostActions.post ? (PostActions.post.permlink || "") : ""
                readonly property bool _saved: (SavedPosts.rev, SavedPosts.isSaved(saveOfflineBtn._pl))
                property bool _saving: false
                onClicked: {
                    if (saveOfflineBtn._saving) return;   // ignore rapid double-taps mid-fetch
                    var p = PostActions.post;
                    if (!p || saveOfflineBtn._pl.length === 0) return;
                    if (saveOfflineBtn._saved) { SavedPosts.remove(saveOfflineBtn._pl); sheet.closeSheet(); return; }
                    saveOfflineBtn._saving = true;
                    PostService.detail(Config.baseUrl, p.author, saveOfflineBtn._pl, Session.token,
                        function (result) {
                            saveOfflineBtn._saving = false;
                            if (result && result.post) SavedPosts.save(result.post);
                            sheet.closeSheet();
                        },
                        function (err) {
                            saveOfflineBtn._saving = false;
                            Toast.error((err && err.message) ? err.message : Lang.tr("Couldn't save for offline."));
                            sheet.closeSheet();
                        });
                }
                Row {
                    anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                    spacing: Style.spacingM
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(4.5); height: width; radius: width / 2
                        color: Style.iconBackground
                        Icon { anchors.centerIn: parent; width: units.gu(2.2); height: width
                               name: saveOfflineBtn._saved ? "tick" : "save"
                               color: saveOfflineBtn._saved ? Style.brand : Style.textPrimary }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter; spacing: units.dp(2)
                        Label { text: saveOfflineBtn._saving ? Lang.tr("Saving…")
                                      : (saveOfflineBtn._saved ? Lang.tr("Remove from saved") : Lang.tr("Save for offline"))
                                font.pixelSize: Style.fontMedium; font.weight: Font.DemiBold; color: Style.textPrimary }
                        Label { text: saveOfflineBtn._saved ? Lang.tr("Available offline")
                                      : Lang.tr("Read this article without a connection")
                                font.pixelSize: Style.fontSmall; color: Style.textSecondary }
                    }
                }
            }

            // Save video offline; toggles to "Remove download" when already saved
            AbstractButton {
                id: saveVideoBtn
                width: parent.width; height: units.gu(8)
                readonly property string _pl: PostActions.post ? (PostActions.post.permlink || "") : ""
                visible: PostActions.kind === "video" && _pl.length > 0
                         && sheet._videoCanDownload(PostActions.post)
                readonly property bool _saved: (Downloads.rev, Downloads.isSaved(saveVideoBtn._pl))
                readonly property var _active: (Downloads.rev, Downloads.activeFor(saveVideoBtn._pl))
                property bool _extracting: false
                readonly property bool _busy: !!saveVideoBtn._active || saveVideoBtn._extracting
                onClicked: sheet.doVideoDownloadToggle()
                Row {
                    anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                    spacing: Style.spacingM
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(4.5); height: width; radius: width / 2
                        color: Style.iconBackground
                        Icon {
                            anchors.centerIn: parent; width: units.gu(2.2); height: width
                            visible: !saveVideoBtn._busy
                            name: saveVideoBtn._saved ? "tick" : "save"
                            color: saveVideoBtn._saved ? Style.brand : Style.textPrimary
                        }
                        ActivityIndicator {
                            anchors.centerIn: parent; width: units.gu(2.2); height: width
                            visible: saveVideoBtn._busy; running: saveVideoBtn._busy
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter; spacing: units.dp(2)
                        Label { text: saveVideoBtn._busy ? Lang.tr("Downloading…")
                                      : (saveVideoBtn._saved ? Lang.tr("Remove download") : Lang.tr("Save video offline"))
                                font.pixelSize: Style.fontMedium; font.weight: Font.DemiBold; color: Style.textPrimary }
                        Label { text: saveVideoBtn._saved ? Lang.tr("Available offline")
                                      : Lang.tr("Watch this video without a connection")
                                font.pixelSize: Style.fontSmall; color: Style.textSecondary }
                    }
                }
            }

            // Separates utility actions (Save) from owner/moderation actions below.
            // Full-width dp(1) hairline like every other divider; it used to be an
            // inset dp(2) in lightGray, which read as a heavier rule than the rest.
            Rectangle {
                width: parent.width
                height: units.dp(1)
                color: Style.divider
                visible: saveOfflineBtn.visible || saveVideoBtn.visible
            }
            Item { width: 1; height: Style.spacingS; visible: saveOfflineBtn.visible || saveVideoBtn.visible }

            // ----- Owner actions (your own post): Edit (blog/gallery only, no video editor) / Delete -----
            AbstractButton {
                id: editPostBtn
                width: parent.width; height: units.gu(8)
                visible: sheet.canEdit
                onClicked: {
                    var p = PostActions.post;
                    sheet.closeSheet();
                    if (p) PostActions.editRequested(p);
                }
                Row {
                    anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                    spacing: Style.spacingM
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(4.5); height: width; radius: width / 2
                        color: Style.iconBackground
                        Icon { anchors.centerIn: parent; width: units.gu(2.2); height: width; name: "edit"; color: Style.textPrimary }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter; spacing: units.dp(2)
                        Label { text: Lang.tr("Edit post"); font.pixelSize: Style.fontMedium; font.weight: Font.DemiBold; color: Style.textPrimary }
                        Label { text: Lang.tr("Update your post"); font.pixelSize: Style.fontSmall; color: Style.textSecondary }
                    }
                }
            }

            // Edit caption (own video, title/description only; the media itself can't be re-uploaded).
            AbstractButton {
                id: editCaptionBtn
                width: parent.width; height: units.gu(8)
                visible: sheet.isOwn && PostActions.kind === "video"
                onClicked: {
                    var p = PostActions.post;
                    captionTitleField.text = (p && p.title) || "";
                    captionDescField.text = sheet._htmlToPlain((p && p.body) || "");
                    sheet.step = 4;
                }
                Row {
                    anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                    spacing: Style.spacingM
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(4.5); height: width; radius: width / 2
                        color: Style.iconBackground
                        Icon { anchors.centerIn: parent; width: units.gu(2.2); height: width; name: "edit"; color: Style.textPrimary }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter; spacing: units.dp(2)
                        Label { text: Lang.tr("Edit caption"); font.pixelSize: Style.fontMedium; font.weight: Font.DemiBold; color: Style.textPrimary }
                        Label { text: Lang.tr("Change the title and description"); font.pixelSize: Style.fontSmall; color: Style.textSecondary }
                    }
                }
            }

            AbstractButton {
                id: deletePostBtn
                width: parent.width; height: units.gu(8)
                visible: sheet.isOwn
                onClicked: sheet.step = 2
                Row {
                    anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                    spacing: Style.spacingM
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(4.5); height: width; radius: width / 2
                        color: Style.iconBackground
                        Icon { anchors.centerIn: parent; width: units.gu(2.2); height: width; name: "delete"; color: Style.danger }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter; spacing: units.dp(2)
                        Label { text: Lang.tr("Delete post"); font.pixelSize: Style.fontMedium; font.weight: Font.DemiBold; color: Style.danger }
                        Label { text: Lang.tr("Permanently remove this post"); font.pixelSize: Style.fontSmall; color: Style.textSecondary }
                    }
                }
            }

            AbstractButton {
                id: hidePostBtn
                width: parent.width; height: units.gu(8)
                visible: !sheet.isOwn
                onClicked: {
                    var p = PostActions.post;
                    sheet.closeSheet();
                    if (p) {
                        HiddenPosts.hide(p.permlink || "");
                        PostActions.hideRequested(p.author || "", p.permlink || "");
                    }
                }
                Row {
                    anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                    spacing: Style.spacingM
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(4.5); height: width; radius: width / 2
                        color: Style.iconBackground
                        Icon { anchors.centerIn: parent; width: units.gu(2.2); height: width; name: "close"; color: Style.textPrimary }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter; spacing: units.dp(2)
                        Label { text: Lang.tr("Hide this post"); font.pixelSize: Style.fontMedium; font.weight: Font.DemiBold; color: Style.textPrimary }
                        Label { text: Lang.tr("I'm not feeling good seeing this post"); font.pixelSize: Style.fontSmall; color: Style.textSecondary }
                    }
                }
            }

            AbstractButton {
                id: reportPostBtn
                width: parent.width; height: units.gu(8)
                visible: !sheet.isOwn
                onClicked: sheet.step = 1
                Row {
                    anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                    spacing: Style.spacingM
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(4.5); height: width; radius: width / 2
                        color: Style.iconBackground
                        Icon { anchors.centerIn: parent; width: units.gu(2.2); height: width; name: "dialog-warning-symbolic"; color: Style.textPrimary }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter; spacing: units.dp(2)
                        Label { text: Lang.tr("Report Post"); font.pixelSize: Style.fontMedium; font.weight: Font.DemiBold; color: Style.textPrimary }
                        Label { text: Lang.tr("I'm concerned about this post"); font.pixelSize: Style.fontSmall; color: Style.textSecondary }
                    }
                }
            }

            AbstractButton {
                id: blockUserBtn
                width: parent.width; height: units.gu(8)
                visible: !sheet.isOwn
                onClicked: sheet.step = 3
                Row {
                    anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                    spacing: Style.spacingM
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(4.5); height: width; radius: width / 2
                        color: Style.iconBackground
                        // No "block" icon in the Suru theme, so draw one (circle + diagonal bar)
                        Item {
                            anchors.centerIn: parent
                            width: units.gu(2.2); height: width
                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: "transparent"
                                border.width: units.dp(1.8)
                                border.color: Style.danger
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width * 0.7; height: units.dp(1.8)
                                color: Style.danger
                                rotation: 45
                            }
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter; spacing: units.dp(2)
                        Label { text: Lang.tr("Block %1").arg(sheet.authorName); font.pixelSize: Style.fontMedium; font.weight: Font.DemiBold; color: Style.danger }
                        Label { text: Lang.tr("You won't be able to see any posts from this person"); font.pixelSize: Style.fontSmall; color: Style.textSecondary }
                    }
                }
            }

            Item { width: 1; height: Style.spacingM }
        }

        // ===================== Step 1: Report reasons =====================
        Column {
            id: reportCol
            anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: Style.spacingL }
            spacing: 0
            visible: sheet.step === 1

            Item {
                width: parent.width; height: units.gu(5)

                AbstractButton {
                    // Opened directly at the report step: no main menu underneath to go back to
                    visible: !sheet.openedDirectly
                    anchors { left: parent.left; leftMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                    width: units.gu(3.5); height: units.gu(3.5)
                    onClicked: sheet.step = 0
                    Icon { anchors.centerIn: parent; width: units.gu(2.2); height: width; name: "back"; color: Style.textPrimary }
                }

                Label {
                    anchors.centerIn: parent
                    text: Lang.tr("Report")
                    font.pixelSize: Style.fontMedium
                    font.weight: Font.DemiBold
                    color: Style.textPrimary
                }

                AbstractButton {
                    anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                    width: units.gu(3.5); height: units.gu(3.5)
                    onClicked: sheet.closeSheet()
                    Icon { anchors.centerIn: parent; width: units.gu(2.2); height: width; name: "close"; color: Style.textPrimary }
                }
            }

            Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

            Item { width: 1; height: Style.spacingS }

            Label {
                x: Style.spacingM
                text: Lang.tr("Why are you reporting this post?")
                font.pixelSize: Style.fontRegular
                color: Style.textSecondary
            }

            Item { width: 1; height: Style.spacingS }

            // Loading spinner while fetching report types driven by the loading flag, not array length, so a failed/empty fetch doesn't spin forever.
            Item {
                visible: sheet.reportTypesLoading
                width: reportCol.width; height: units.gu(6)
                ActivityIndicator { anchors.centerIn: parent; running: parent.visible }
            }

            // Empty / failed state; reopening the sheet retries the fetch.
            Label {
                visible: !sheet.reportTypesLoading && sheet.reportTypes.length === 0
                width: reportCol.width - Style.spacingM * 2
                x: Style.spacingM
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: Lang.tr("Couldn't load report reasons. Close and try again.")
                font.pixelSize: Style.fontSmall
                color: Style.textSecondary
            }

            Repeater {
                id: reportRepeater
                model: sheet.reportTypes

                delegate: AbstractButton {
                    width: reportCol.width; height: units.gu(5.5)
                    enabled: !sheet.reporting
                    property int delegateIndex: index

                    onClicked: {
                        var item = sheet.reportTypes[delegateIndex] || {}
                        var typeId = (item.id !== undefined)             ? item.id
                                   : (item._id !== undefined)            ? item._id
                                   : (item.report_type_id !== undefined) ? item.report_type_id
                                   : (item.type_id !== undefined)        ? item.type_id
                                   : ""
                        var typeName = item.name || item.title || item.report_type || item.type || "Report"
                        sheet.submitReport(String(typeId), typeName)
                    }

                    Row {
                        anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                        spacing: Style.spacingM

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                var item = sheet.reportTypes[index] || {}
                                return item.name || item.title || item.report_type || item.type || ""
                            }
                            font.pixelSize: Style.fontRegular
                            color: sheet.reporting ? Style.textSecondary : Style.textPrimary
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

        // ===================== Step 3: Block confirmation =====================
        Column {
            id: blockCol
            anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: Style.spacingL }
            spacing: 0
            visible: sheet.step === 3

            Item { width: 1; height: Style.spacingS }
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Lang.tr("Block %1?").arg(sheet.authorName)
                font.pixelSize: Style.fontLarge
                font.weight: Font.DemiBold
                color: Style.textPrimary
            }
            Item { width: 1; height: Style.spacingS }
            Label {
                width: parent.width - Style.spacingL * 2
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: Lang.tr("Their posts will be hidden from your feeds.")
                font.pixelSize: Style.fontSmall
                color: Style.textSecondary
            }
            Item { width: 1; height: Style.spacingL }

            AbstractButton {
                id: blockConfirmBtn
                width: parent.width - Style.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                height: units.gu(6)
                enabled: !sheet.blocking
                onClicked: sheet.doBlock()
                Rectangle {
                    anchors.fill: parent; radius: units.dp(10)
                    color: Style.danger; opacity: sheet.blocking ? 0.6 : 1
                }
                Label {
                    anchors.centerIn: parent
                    text: sheet.blocking ? Lang.tr("Blocking…") : Lang.tr("Block")
                    font.pixelSize: Style.fontMedium; font.weight: Font.DemiBold
                    color: Style.textOnBrand
                }
            }

            Item { width: 1; height: Style.spacingS }

            AbstractButton {
                id: blockCancelBtn
                width: parent.width - Style.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                height: units.gu(6)
                enabled: !sheet.blocking
                onClicked: sheet.step = 0
                Rectangle {
                    anchors.fill: parent; radius: units.dp(10)
                    color: "transparent"
                    border.width: units.dp(1.5); border.color: Style.divider
                }
                Label {
                    anchors.centerIn: parent
                    text: Lang.tr("Cancel")
                    font.pixelSize: Style.fontMedium; font.weight: Font.DemiBold
                    color: Style.textPrimary
                }
            }

            Item { width: 1; height: Style.spacingM }
        }

        // ===================== Step 2: Delete confirmation =====================
        Column {
            id: deleteCol
            anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: Style.spacingL }
            spacing: 0
            visible: sheet.step === 2

            Item { width: 1; height: Style.spacingS }
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Lang.tr("Delete this post?")
                font.pixelSize: Style.fontLarge
                font.weight: Font.DemiBold
                color: Style.textPrimary
            }
            Item { width: 1; height: Style.spacingS }
            Label {
                width: parent.width - Style.spacingL * 2
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: Lang.tr("This permanently removes the post and can't be undone.")
                font.pixelSize: Style.fontSmall
                color: Style.textSecondary
            }
            Item { width: 1; height: Style.spacingL }

            AbstractButton {
                id: deleteConfirmBtn
                width: parent.width - Style.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                height: units.gu(6)
                enabled: !sheet.deleting
                onClicked: sheet.doDelete()
                Rectangle {
                    anchors.fill: parent
                    radius: Style.cardRadius
                    color: Style.danger
                    opacity: sheet.deleting ? 0.6 : 1
                }
                Label {
                    anchors.centerIn: parent
                    text: sheet.deleting ? Lang.tr("Deleting…") : Lang.tr("Delete post")
                    font.pixelSize: Style.fontMedium
                    font.weight: Font.DemiBold
                    color: Style.textOnBrand
                }
            }

            Item { width: 1; height: Style.spacingS }

            AbstractButton {
                id: deleteCancelBtn
                width: parent.width - Style.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                height: units.gu(6)
                enabled: !sheet.deleting
                onClicked: sheet.step = 0
                Rectangle {
                    anchors.fill: parent
                    radius: Style.cardRadius
                    color: "transparent"
                    border.width: units.dp(1.5)
                    border.color: Style.divider
                }
                Label {
                    anchors.centerIn: parent
                    text: Lang.tr("Cancel")
                    font.pixelSize: Style.fontMedium
                    font.weight: Font.DemiBold
                    color: Style.textPrimary
                }
            }

            Item { width: 1; height: Style.spacingM }
        }

        // ===================== Step 4: Edit video caption =====================
        Column {
            id: editCol
            anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: Style.spacingL }
            spacing: 0
            visible: sheet.step === 4

            Item {
                width: parent.width; height: units.gu(5)

                AbstractButton {
                    anchors { left: parent.left; leftMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                    width: units.gu(3.5); height: units.gu(3.5)
                    enabled: !sheet.savingCaption
                    onClicked: sheet.step = 0
                    Icon { anchors.centerIn: parent; width: units.gu(2.2); height: width; name: "back"; color: Style.textPrimary }
                }

                Label {
                    anchors.centerIn: parent
                    text: Lang.tr("Edit caption")
                    font.pixelSize: Style.fontMedium
                    font.weight: Font.DemiBold
                    color: Style.textPrimary
                }
            }

            Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

            Item { width: 1; height: Style.spacingM }

            Label {
                x: Style.spacingM
                text: Lang.tr("Title")
                font.pixelSize: Style.fontSmall
                font.weight: Font.DemiBold
                color: Style.textSecondary
            }
            Item { width: 1; height: Style.spacingXs }
            TextField {
                id: captionTitleField
                width: parent.width - Style.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                enabled: !sheet.savingCaption
                placeholderText: Lang.tr("Title")
            }

            Item { width: 1; height: Style.spacingM }

            Label {
                x: Style.spacingM
                text: Lang.tr("Description")
                font.pixelSize: Style.fontSmall
                font.weight: Font.DemiBold
                color: Style.textSecondary
            }
            Item { width: 1; height: Style.spacingXs }
            TextArea {
                id: captionDescField
                width: parent.width - Style.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                height: units.gu(10)
                enabled: !sheet.savingCaption
                placeholderText: Lang.tr("Description")
            }

            Item { width: 1; height: Style.spacingL }

            AbstractButton {
                width: parent.width - Style.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                height: units.gu(6)
                enabled: !sheet.savingCaption
                onClicked: sheet.doSaveCaption()
                Rectangle {
                    anchors.fill: parent
                    radius: Style.cardRadius
                    color: Style.brand
                    opacity: sheet.savingCaption ? 0.6 : 1
                }
                Label {
                    anchors.centerIn: parent
                    text: sheet.savingCaption ? Lang.tr("Saving…") : Lang.tr("Save")
                    font.pixelSize: Style.fontMedium
                    font.weight: Font.DemiBold
                    color: Style.textOnBrand
                }
            }

            Item { width: 1; height: Style.spacingM }
        }

        // Keyboard-highlight ring: reparented into whichever row is arrow-key selected
        Rectangle {
            parent: sheet.navCurrent ? sheet.navCurrent : sheetRect
            anchors.fill: parent
            anchors.margins: units.dp(3)
            radius: units.dp(10)
            color: "transparent"
            border.width: units.dp(2)
            border.color: Style.brand
            visible: sheet.navCurrent !== null
            z: 10
        }
    }
}
