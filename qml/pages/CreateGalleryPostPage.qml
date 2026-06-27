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
    property bool uploading: false
    property string selectedCategory: ""
    property var imageUrls: []
    property bool catSheetOpen: false
    readonly property int maxImages: 10

    readonly property var categories: [
        "general", "breaking & news", "entertainment", "creativity",
        "digital art", "culture", "environment", "society",
        "philosophy", "football", "crypto", "general knowledge"
    ]

    header: Item { height: 0 }

    // Custom header
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
            text: i18n.tr("Create Gallery Post")
            font.pixelSize: Style.fontMedium
            font.weight: Font.DemiBold
            color: Style.textPrimary
        }

        AbstractButton {
            anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
            width: galPostLabel.implicitWidth + Style.spacingM * 2
            height: units.gu(4)
            enabled: !page.submitting && captionField.text.trim().length > 0
            onClicked: page.publish()

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: parent.enabled ? Style.brand : Style.iconBackground
            }
            Label {
                id: galPostLabel
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

    function publish() {
        if (!Session.isLoggedIn) {
            Toast.error(i18n.tr("Please log in first."));
            return;
        }
        page.submitting = true;
        PostService.createPost(Config.baseUrl, {
            title: captionField.text.trim(),
            body: captionField.text.trim(),
            communityId: Config.communityId,
            category: page.selectedCategory
        }, Session.token,
        function (data) {
            page.submitting = false;
            Toast.success(i18n.tr("Gallery post published!"));
            page.pageStack.pop();
        },
        function (err) {
            page.submitting = false;
            Toast.error((err && err.message) ? err.message : i18n.tr("Couldn't publish post."));
        });
    }

    function addImage() {
        if (page.imageUrls.length >= page.maxImages) {
            Toast.show(i18n.tr("Maximum %1 images allowed").arg(page.maxImages));
            return;
        }
        if (page.uploading) return;
        var dlg = Popups.PopupUtils.open(photoPickerComp);
        dlg.picked.connect(function (fileUrl) {
            page.uploading = true;
            Uploads.uploadImage(Config.uploadUrl, Config.uploadSecret, fileUrl,
                function (url) {
                    page.uploading = false;
                    var copy = page.imageUrls.slice();
                    copy.push(url);
                    page.imageUrls = copy;
                    Toast.success(i18n.tr("Photo uploaded"));
                },
                function (err) {
                    page.uploading = false;
                    Toast.error((err && err.message) ? err.message : i18n.tr("Upload failed."));
                });
        });
    }

    Component {
        id: photoPickerComp
        PhotoPicker { }
    }

    function removeImage(idx) {
        var copy = [];
        for (var i = 0; i < page.imageUrls.length; i++) {
            if (i !== idx) copy.push(page.imageUrls[i]);
        }
        page.imageUrls = copy;
    }

    Flickable {
        anchors { top: hdr.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
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

            // Caption field — outlined rounded box
            Rectangle {
                width: parent.width
                height: Math.max(units.gu(12), captionField.contentHeight + Style.spacingM * 2)
                radius: units.dp(8)
                color: "transparent"
                border.width: units.dp(1.5)
                border.color: captionField.activeFocus ? Style.brand : Style.divider

                TextEdit {
                    id: captionField
                    anchors { fill: parent; margins: Style.spacingM }
                    font.family: Style.fontFamily
                    font.pixelSize: Style.fontRegular
                    color: Style.textPrimary
                    wrapMode: Text.WordWrap
                }

                Label {
                    anchors { left: parent.left; top: parent.top; leftMargin: Style.spacingM; topMargin: Style.spacingM }
                    visible: captionField.text.length === 0 && !captionField.activeFocus
                    text: i18n.tr("Write a caption...")
                    color: Style.textSecondary
                    font.pixelSize: Style.fontRegular
                    font.family: Style.fontFamily
                }
            }

            // Photos header
            Label {
                text: i18n.tr("Photos (%1/%2)").arg(page.imageUrls.length).arg(page.maxImages)
                font.pixelSize: Style.fontSmall
                font.weight: Font.DemiBold
                color: Style.textPrimary
            }

            // Image grid
            Flow {
                width: parent.width
                spacing: Style.spacingS

                Repeater {
                    model: page.imageUrls
                    delegate: Item {
                        width: (parent.width - Style.spacingS * 2) / 3
                        height: width

                        Rectangle {
                            anchors.fill: parent
                            radius: units.dp(10)
                            color: Style.iconBackground
                            clip: true
                            Image {
                                anchors.fill: parent
                                source: modelData
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                        }

                        AbstractButton {
                            anchors { top: parent.top; right: parent.right; topMargin: units.dp(4); rightMargin: units.dp(4) }
                            width: units.gu(2.5); height: width
                            onClicked: page.removeImage(index)
                            Rectangle {
                                anchors.fill: parent; radius: width / 2
                                color: Qt.rgba(0, 0, 0, 0.5)
                            }
                            Icon {
                                anchors.centerIn: parent
                                width: units.gu(1.5); height: width
                                name: "close"
                                color: "white"
                            }
                        }
                    }
                }

                // Add photo button / upload spinner
                Item {
                    visible: page.imageUrls.length < page.maxImages
                    width: (parent.width - Style.spacingS * 2) / 3
                    height: width

                    AbstractButton {
                        anchors.fill: parent
                        enabled: !page.uploading
                        onClicked: page.addImage()

                        Rectangle {
                            anchors.fill: parent
                            radius: units.dp(10)
                            color: Style.iconBackground
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: Style.spacingXs
                            visible: !page.uploading

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: units.gu(4.5); height: width
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
                                text: i18n.tr("Add photo")
                                font.pixelSize: Style.fontXSmall
                                color: Style.textSecondary
                            }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: Style.spacingXs
                            visible: page.uploading
                            ActivityIndicator { anchors.horizontalCenter: parent.horizontalCenter; running: page.uploading }
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: i18n.tr("Uploading…")
                                font.pixelSize: Style.fontXSmall
                                color: Style.textSecondary
                            }
                        }
                    }
                }
            }

            Item { width: 1; height: Style.spacingL }
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
        id: galCatSheet
        anchors.fill: parent
        visible: page.catSheetOpen
        z: 200
        onVisibleChanged: if (visible) { galCatBdFade.start(); galCatSlideAnim.start(); }
        function closeAnimated() { galCatBdFadeOut.start(); galCatSlideOut.start(); }

        Rectangle {
            id: galCatBd
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.4)
            opacity: 0
            MouseArea { anchors.fill: parent; onClicked: galCatSheet.closeAnimated() }
        }
        NumberAnimation { id: galCatBdFade; target: galCatBd; property: "opacity"; from: 0; to: 1; duration: 200 }
        NumberAnimation { id: galCatBdFadeOut; target: galCatBd; property: "opacity"; to: 0; duration: 200 }

        Rectangle {
            id: galCatSheetRect
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: galCatSheetCol.height + units.gu(4)
            radius: units.dp(16)
            color: Style.surface
            transform: Translate { id: galCatSlideT; y: 0 }
            NumberAnimation { id: galCatSlideAnim; target: galCatSlideT; property: "y"; from: galCatSheetRect.height; to: 0; duration: 300; easing.type: Easing.OutCubic }
            NumberAnimation { id: galCatSlideOut; target: galCatSlideT; property: "y"; to: galCatSheetRect.height; duration: 250; easing.type: Easing.InCubic; onStopped: page.catSheetOpen = false }

            Rectangle {
                anchors { top: parent.top; topMargin: Style.spacingS; horizontalCenter: parent.horizontalCenter }
                width: units.gu(4.5); height: units.dp(4); radius: units.dp(2)
                color: Style.lightGray
            }

            Column {
                id: galCatSheetCol
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
                        onClicked: galCatSheet.closeAnimated()
                        Icon { anchors.centerIn: parent; width: units.gu(2.2); height: width; name: "close"; color: Style.textPrimary }
                    }
                }

                Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

                Repeater {
                    model: page.categories
                    delegate: AbstractButton {
                        width: galCatSheetCol.width
                        height: units.gu(6)
                        onClicked: {
                            page.selectedCategory = modelData;
                            galCatSheet.closeAnimated();
                        }

                        Row {
                            anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                            spacing: Style.spacingM
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - galCheckIcon.width
                                text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                                font.pixelSize: Style.fontRegular
                                color: page.selectedCategory === modelData ? Style.brand : Style.textPrimary
                                font.weight: page.selectedCategory === modelData ? Font.DemiBold : Font.Normal
                            }
                            Icon {
                                id: galCheckIcon
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
