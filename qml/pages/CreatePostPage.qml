import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3 as Popups
import "../Theme"
import "../Session"
import "../components"
import "../services/PostService.js" as PostService
import "../services/Uploads.js" as Uploads

Page {
    id: page

    property bool submitting: false
    property string selectedCategory: ""
    property bool catSheetOpen: false
    readonly property int titleMaxLength: 250
    property string coverImageUrl: ""
    property bool uploading: false

    readonly property var categories: [
        "general", "breaking & news", "entertainment", "creativity",
        "digital art", "culture", "environment", "society",
        "philosophy", "football", "crypto", "general knowledge"
    ]

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
            text: i18n.tr("Create Post")
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
                radius: height / 2
                color: parent.enabled ? Style.brand : Style.iconBackground
            }
            Label {
                id: postPillLabel
                anchors.centerIn: parent
                text: page.submitting ? i18n.tr("Posting…") : i18n.tr("Publish")
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

    function pickCoverImage() {
        Popups.PopupUtils.open(pickerComp);
    }

    Component {
        id: pickerComp
        PhotoPicker {
            onPicked: {
                page.uploading = true;
                Uploads.uploadImage(Config.uploadUrl, Config.uploadSecret, fileUrl,
                    function (url) {
                        page.uploading = false;
                        page.coverImageUrl = url;
                        Toast.success(i18n.tr("Cover image uploaded"));
                    },
                    function (err) {
                        page.uploading = false;
                        Toast.error((err && err.message) ? err.message : i18n.tr("Upload failed."));
                    });
            }
            onCancelled: { /* nothing to do */ }
        }
    }

    function publish() {
        if (!Session.isLoggedIn) {
            Toast.error(i18n.tr("Please log in first."));
            return;
        }
        // Prepend cover image to body if one was uploaded
        var body = bodyArea.text.trim();
        if (page.coverImageUrl.length > 0) {
            body = '<img src="' + page.coverImageUrl + '" style="max-width:100%;height:auto;" />\n' + body;
        }
        page.submitting = true;
        PostService.createPost(Config.baseUrl, {
            title: titleField.text.trim(),
            body: body,
            communityId: Config.communityId,
            category: page.selectedCategory
        }, Session.token,
        function (data) {
            page.submitting = false;
            Toast.success(i18n.tr("Post published!"));
            page.pageStack.pop();
        },
        function (err) {
            page.submitting = false;
            Toast.error((err && err.message) ? err.message : i18n.tr("Couldn't publish post."));
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

    Flickable {
        id: scroll
        anchors { top: hdr.bottom; left: parent.left; right: parent.right; bottom: toolbar.top }
        contentHeight: col.height + Style.spacingL
        clip: true
        opacity: 0
        NumberAnimation on opacity { from: 0; to: 1; duration: 250; easing.type: Easing.OutQuad }

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
                radius: units.dp(8)
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
                    font.family: Style.fontFamily
                    color: Style.textPrimary
                    clip: true
                    maximumLength: page.titleMaxLength
                }

                Label {
                    anchors {
                        left: parent.left; top: parent.top
                        leftMargin: Style.spacingM; topMargin: Style.spacingM
                    }
                    visible: titleField.text.length === 0 && !titleField.activeFocus
                    text: i18n.tr("Enter title")
                    color: Style.textSecondary
                    font.pixelSize: Style.fontMedium
                    font.family: Style.fontFamily
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
                radius: units.dp(8)
                color: "transparent"
                border.width: units.dp(1.5)
                border.color: bodyArea.activeFocus ? Style.brand : Style.divider

                TextEdit {
                    id: bodyArea
                    anchors {
                        fill: parent
                        margins: Style.spacingM
                    }
                    font.family: Style.fontFamily
                    font.pixelSize: Style.fontRegular
                    color: Style.textPrimary
                    wrapMode: Text.WordWrap
                }

                Label {
                    anchors {
                        left: parent.left; top: parent.top
                        leftMargin: Style.spacingM; topMargin: Style.spacingM
                    }
                    visible: bodyArea.text.length === 0 && !bodyArea.activeFocus
                    text: i18n.tr("Write your article here...")
                    color: Style.textSecondary
                    font.pixelSize: Style.fontRegular
                    font.family: Style.fontFamily
                }
            }

            // Category selector
            AbstractButton {
                width: parent.width
                height: units.gu(6)
                onClicked: page.catSheetOpen = true

                Rectangle {
                    anchors.fill: parent
                    radius: units.dp(8)
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
                            : i18n.tr("Select category")
                        font.pixelSize: Style.fontRegular
                        font.family: Style.fontFamily
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

            // Cover image area
            Rectangle {
                width: parent.width
                height: units.gu(20)
                radius: units.dp(12)
                color: Style.iconBackground
                clip: true

                // Show uploaded image preview
                Image {
                    anchors.fill: parent
                    source: page.coverImageUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
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
                        text: i18n.tr("Add cover image")
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

    // Formatting toolbar
    Rectangle {
        id: toolbar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
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
                        radius: units.dp(6)
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
                    radius: units.dp(6); color: "transparent"
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
                onClicked: page.pickCoverImage()
                Rectangle {
                    anchors.fill: parent; anchors.margins: units.dp(4)
                    radius: units.dp(6); color: "transparent"
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
            radius: units.dp(16)
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
                        text: i18n.tr("Select Category")
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
