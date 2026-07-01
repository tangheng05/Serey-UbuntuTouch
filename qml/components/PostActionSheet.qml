import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../services/PostService.js" as PostService
import "../services/AccountService.js" as AccountService
import "../services/ReportService.js" as ReportService
import "../services/HiddenPosts.js" as HiddenPosts
import "../services/BlockedUsers.js" as BlockedUsers

Item {
    id: sheet
    anchors.fill: parent
    visible: PostActions.visible
    z: 1500

    readonly property string authorName: PostActions.post ? (PostActions.post.author || "") : ""
    // The viewer owns this post → show Edit/Delete instead of moderation actions
    // (you can't report or block yourself).
    readonly property bool isOwn: Session.isLoggedIn && authorName !== "" && authorName === Session.username
    // No video editor exists, so Edit is offered for blog/gallery only.
    readonly property bool canEdit: isOwn && PostActions.kind !== "video"
    property bool deleting: false
    property bool blocking: false
    property bool reporting: false
    property var reportTypes: []
    property bool reportTypesLoaded: false
    property bool reportTypesLoading: false
    property string selectedReportTypeId: ""
    // 0 = main menu, 1 = report reasons, 2 = delete confirm, 3 = block confirm
    property int step: 0

    onVisibleChanged: {
        if (!visible) {
            step = 0;
            selectedReportTypeId = "";
            // Clear in-flight busy flags so a sheet dismissed mid-request doesn't
            // reopen stuck on "Blocking…" / disabled report rows.
            reporting = false;
            blocking = false;
        } else {
            backdropFade.start();
            sheetSlide.start();
            // Guard on !reportTypesLoading too, so reopening before the first
            // fetch resolves doesn't fire a duplicate concurrent request.
            if (!reportTypesLoaded && !reportTypesLoading) _loadReportTypes();
        }
    }

    function _loadReportTypes() {
        sheet.reportTypesLoading = true;
        ReportService.getReportTypes(Config.baseUrl,
            function (arr) {
                sheet.reportTypesLoading = false;
                sheet.reportTypes = arr || [];
                // Only latch as "loaded" on a non-empty result; an empty list
                // means try again next open rather than showing a dead panel.
                sheet.reportTypesLoaded = sheet.reportTypes.length > 0;
            },
            function (err) {
                // Leave reportTypesLoaded false so reopening the sheet retries
                // (there is no hardcoded fallback — the backend owns the ids).
                sheet.reportTypesLoading = false;
                sheet.reportTypesLoaded = false;
                Toast.error((err && err.message) ? err.message
                            : i18n.tr("Couldn't load report reasons. Please try again."));
            });
    }

    function closeSheet() {
        backdropFadeOut.start();
        sheetSlideOut.start();
    }

    function submitReport(typeId, typeName) {
<<<<<<< Updated upstream
        if (typeId === "" || typeId === undefined || typeId === null) {
            Toast.error(i18n.tr("Couldn't submit this report reason."));
            return;
        }
        if (!Session.isLoggedIn) { Toast.error(i18n.tr("Please log in to report.")); return; }
=======
        if (typeId === "" || typeId === undefined || typeId === null) return;
        if (!Session.isLoggedIn) { Toast.error(Lang.tr("Please log in to report.")); return; }
>>>>>>> Stashed changes
        var p = PostActions.post;
        if (!p) return;
        // Backend expects the post id; fall back to permlink only if present.
        var postId = (p.id !== undefined && p.id !== null) ? p.id : (p.permlink || "");
        if (postId === "" || postId === null || postId === undefined) {
            Toast.error(i18n.tr("Failed to submit report."));
            return;
        }
        sheet.reporting = true;
        ReportService.submitReport(Config.baseUrl, Session.token,
            postId, typeId, typeName || "Report",
            function () {
                sheet.reporting = false;
                sheet.closeSheet();
                Toast.show(Lang.tr("Report submitted. Thank you."));
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
                Toast.show(Lang.tr("@%1 blocked.").arg(username));
            },
            function (err) {
                sheet.blocking = false;
                Toast.error((err && err.message) ? err.message : Lang.tr("Failed to block user."));
            });
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

    // Backdrop
    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.4)
        opacity: 0
        MouseArea { anchors.fill: parent; onClicked: sheet.closeSheet() }
    }
    NumberAnimation { id: backdropFade; target: backdrop; property: "opacity"; from: 0; to: 1; duration: 200 }
    NumberAnimation { id: backdropFadeOut; target: backdrop; property: "opacity"; to: 0; duration: 200 }

    // Sheet
    Rectangle {
        id: sheetRect
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: (sheet.step === 0 ? mainCol.height
                 : sheet.step === 1 ? reportCol.height
                 : sheet.step === 2 ? deleteCol.height
                 : blockCol.height) + units.gu(4)
        radius: units.dp(16)
        color: Style.surface

        transform: Translate { id: sheetTranslate; y: 0 }
        NumberAnimation { id: sheetSlide; target: sheetTranslate; property: "y"; from: sheetRect.height + units.gu(4); to: 0; duration: 300; easing.type: Easing.OutCubic }
        NumberAnimation { id: sheetSlideOut; target: sheetTranslate; property: "y"; to: sheetRect.height + units.gu(4); duration: 250; easing.type: Easing.InCubic; onStopped: PostActions.close() }

        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }

        // Grabber
        Rectangle {
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

            // ----- Save for offline (blog articles only; video has its own
            // download, gallery reads in its own viewer). The feed view-model
            // carries only an excerpt, so we fetch the full article first, then
            // persist it. Toggles to "Remove from saved" when already saved.
            AbstractButton {
                id: saveOfflineBtn
                width: parent.width; height: units.gu(8)
                visible: PostActions.kind === "blog" && saveOfflineBtn._pl.length > 0
                readonly property string _pl: PostActions.post ? (PostActions.post.permlink || "") : ""
                readonly property bool _saved: (SavedPosts.rev, SavedPosts.isSaved(saveOfflineBtn._pl))
                property bool _saving: false
                onClicked: {
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
                        Icon { anchors.centerIn: parent; width: units.gu(2.2); height: width; name: "save"
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

            // ----- Owner actions (your own post): Edit / Delete -----
            // Edit (blog/gallery only — no video editor)
            AbstractButton {
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

            // Delete → confirm step
            AbstractButton {
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

            // Hide
            AbstractButton {
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

            // Report → go to step 1
            AbstractButton {
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

            // Block → confirm step
            AbstractButton {
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
                        Icon { anchors.centerIn: parent; width: units.gu(2.2); height: width; name: "contact"; color: Style.textPrimary }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter; spacing: units.dp(2)
                        Label { text: Lang.tr("Block %1").arg(sheet.authorName); font.pixelSize: Style.fontMedium; font.weight: Font.DemiBold; color: Style.textPrimary }
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

            // Header: back + title
            Item {
                width: parent.width; height: units.gu(5)

                AbstractButton {
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

            // Loading spinner while fetching report types (driven by the
            // loading flag, not array length, so a failed/empty fetch doesn't
            // spin forever).
            Item {
                visible: sheet.reportTypesLoading
                width: reportCol.width; height: units.gu(6)
                ActivityIndicator { anchors.centerIn: parent; running: parent.visible }
            }

            // Empty / failed state — reopening the sheet retries the fetch.
            Label {
                visible: !sheet.reportTypesLoading && sheet.reportTypes.length === 0
                width: reportCol.width - Style.spacingM * 2
                x: Style.spacingM
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: i18n.tr("Couldn't load report reasons. Close and try again.")
                font.pixelSize: Style.fontSmall
                color: Style.textSecondary
            }

            Repeater {
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
                text: Lang.tr("Block @%1?").arg(sheet.authorName)
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

            // Confirm delete (danger)
            AbstractButton {
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

            // Cancel → back to main menu
            AbstractButton {
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
    }
}
