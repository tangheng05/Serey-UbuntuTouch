import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../services/PostService.js" as PostService

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
    // 0 = main menu, 1 = report reasons, 2 = delete confirm
    property int step: 0

    onVisibleChanged: {
        if (!visible) { step = 0; }
        else { backdropFade.start(); sheetSlide.start(); }
    }

    function closeSheet() {
        backdropFadeOut.start();
        sheetSlideOut.start();
    }

    function submitReport(reason) {
        sheet.closeSheet();
        Toast.show(i18n.tr("Report submitted. Thank you."));
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
                Toast.success(i18n.tr("Post deleted."));
            },
            function (err) {
                sheet.deleting = false;
                Toast.error((err && err.message) ? err.message : i18n.tr("Couldn't delete the post."));
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
                 : deleteCol.height) + units.gu(4)
        radius: units.gu(1)
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
                text: sheet.isOwn ? i18n.tr("Post options") : i18n.tr("How can we help?")
                font.pixelSize: Style.fontLarge
                font.weight: Font.DemiBold
                color: Style.textPrimary
            }
            Item { width: 1; height: Style.spacingL }

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
                        Label { text: i18n.tr("Edit post"); font.pixelSize: Style.fontMedium; font.weight: Font.DemiBold; color: Style.textPrimary }
                        Label { text: i18n.tr("Update your post"); font.pixelSize: Style.fontSmall; color: Style.textSecondary }
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
                        Label { text: i18n.tr("Delete post"); font.pixelSize: Style.fontMedium; font.weight: Font.DemiBold; color: Style.danger }
                        Label { text: i18n.tr("Permanently remove this post"); font.pixelSize: Style.fontSmall; color: Style.textSecondary }
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
                    if (p) PostActions.hideRequested(p.author || "", p.permlink || "");
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
                        Label { text: i18n.tr("Hide this post"); font.pixelSize: Style.fontMedium; font.weight: Font.DemiBold; color: Style.textPrimary }
                        Label { text: i18n.tr("I'm not feeling good seeing this post"); font.pixelSize: Style.fontSmall; color: Style.textSecondary }
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
                        Label { text: i18n.tr("Report Post"); font.pixelSize: Style.fontMedium; font.weight: Font.DemiBold; color: Style.textPrimary }
                        Label { text: i18n.tr("I'm concerned about this post"); font.pixelSize: Style.fontSmall; color: Style.textSecondary }
                    }
                }
            }

            // Block
            AbstractButton {
                width: parent.width; height: units.gu(8)
                visible: !sheet.isOwn
                onClicked: { sheet.closeSheet(); Toast.show(i18n.tr("User blocked.")); }
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
                        Label { text: i18n.tr("Block %1").arg(sheet.authorName); font.pixelSize: Style.fontMedium; font.weight: Font.DemiBold; color: Style.textPrimary }
                        Label { text: i18n.tr("You won't be able to see any posts from this person"); font.pixelSize: Style.fontSmall; color: Style.textSecondary }
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
                    text: i18n.tr("Report")
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
                text: i18n.tr("Why are you reporting this post?")
                font.pixelSize: Style.fontRegular
                color: Style.textSecondary
            }

            Item { width: 1; height: Style.spacingS }

            Repeater {
                model: [
                    i18n.tr("Spam"),
                    i18n.tr("Nudity or sexual activity"),
                    i18n.tr("Hate speech or symbols"),
                    i18n.tr("Violence or dangerous organizations"),
                    i18n.tr("Scam or fraud"),
                    i18n.tr("False information"),
                    i18n.tr("Bullying or harassment"),
                    i18n.tr("Other")
                ]

                delegate: AbstractButton {
                    width: reportCol.width; height: units.gu(5.5)
                    onClicked: sheet.submitReport(modelData)

                    Row {
                        anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                        spacing: Style.spacingM

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData
                            font.pixelSize: Style.fontRegular
                            color: Style.textPrimary
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
                text: i18n.tr("Delete this post?")
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
                text: i18n.tr("This permanently removes the post and can't be undone.")
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
                    text: sheet.deleting ? i18n.tr("Deleting…") : i18n.tr("Delete post")
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
                    text: i18n.tr("Cancel")
                    font.pixelSize: Style.fontMedium
                    font.weight: Font.DemiBold
                    color: Style.textPrimary
                }
            }

            Item { width: 1; height: Style.spacingM }
        }
    }
}
