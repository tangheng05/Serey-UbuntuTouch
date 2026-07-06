import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3 as Popups
import "../Theme"
import "../Session"
import "../components"
import "../services/PostService.js" as PostService

Page {
    id: page

    property bool submitting: false
    property bool uploading: false
    property var imageUrls: []
    readonly property int maxImages: 10

    // When set, edits an existing gallery post (updates in place via its permlink).
    property var editPost: null
    readonly property bool isEdit: !!editPost
    signal saved()

    Component.onCompleted: {
        if (page.editPost) {
            captionField.text = page.editPost.caption || "";
            // imagesStr is the newline-joined scalar (the images array is wrapped
            // by the feed ListModel and its URL strings don't survive .get()).
            page.imageUrls = (page.editPost.imagesStr || "")
                .split("\n").filter(function (s) { return s.length > 0; });
        }
    }

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
            text: page.isEdit ? Lang.tr("Edit Gallery Post") : Lang.tr("Create Gallery Post")
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
                radius: Style.cardRadius
                color: parent.enabled ? Style.brand : Style.iconBackground
            }
            Label {
                id: galPostLabel
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

    function publish() {
        if (!Session.isLoggedIn) {
            Toast.error(Lang.tr("Please log in first."));
            return;
        }
        if (page.imageUrls.length === 0) {
            Toast.error(Lang.tr("Add at least one photo."));
            return;
        }
        page.submitting = true;
        PostService.createPost(Config.baseUrl, {
            title: captionField.text.trim(),
            body: captionField.text.trim(),
            communityId: page.isEdit ? 0 : Config.communityId,
            communityName: page.isEdit ? (page.editPost.community || Config.communityName)
                                       : Config.communityName,
            categories: "gallery",
            permlink: page.isEdit ? (page.editPost.permlink || "") : "",
            images: page.imageUrls
        }, Session.token,
        function (data) {
            page.submitting = false;
            Toast.success(page.isEdit ? Lang.tr("Gallery post updated!") : Lang.tr("Gallery post published!"));
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

    function addImage() {
        if (page.imageUrls.length >= page.maxImages) {
            Toast.show(Lang.tr("Maximum %1 images allowed").arg(page.maxImages));
            return;
        }
        if (page.uploading) return;
        Popups.PopupUtils.open(photoPickerComp);
    }

    Component {
        id: photoPickerComp
        PhotoPicker {
            onPicked: imgUploader.upload(fileUrl)
        }
    }

    // Downscales + uploads each picked photo; appends the hosted URL.
    PhotoUploader {
        id: imgUploader
        onUploadingChanged: page.uploading = uploading
        onUploaded: {
            var copy = page.imageUrls.slice();
            copy.push(url);
            page.imageUrls = copy;
            Toast.success(Lang.tr("Photo uploaded"));
        }
        onFailed: Toast.error(message)
    }

    function removeImage(idx) {
        var copy = [];
        for (var i = 0; i < page.imageUrls.length; i++) {
            if (i !== idx) copy.push(page.imageUrls[i]);
        }
        page.imageUrls = copy;
    }

    // Move active focus onto a neutral item so the on-screen keyboard drops when
    // tapping any empty area of the form (see the background MouseArea below).
    Item { id: focusSink }
    function dismissKeyboard() {
        focusSink.forceActiveFocus();
        Qt.inputMethod.hide();
    }

    Flickable {
        id: scroll
        anchors { top: hdr.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        // Shrink above the OSK so the form stays scrollable while typing.
        anchors.bottomMargin: Qt.inputMethod.visible ? Qt.inputMethod.keyboardRectangle.height : 0
        contentHeight: col.height + Style.spacingL
        clip: true
        opacity: 0
        NumberAnimation on opacity { from: 0; to: 1; duration: 250; easing.type: Easing.OutQuad }

        // Sits behind the form (z -1); taps that miss the caption fall through
        // here and dismiss the keyboard. Drags still flick (the Flickable steals
        // drag gestures from child MouseAreas).
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

            // Caption field — outlined rounded box
            Rectangle {
                width: parent.width
                height: Math.max(units.gu(12), captionField.contentHeight + Style.spacingM * 2)
                radius: Style.cardRadius
                color: "transparent"
                border.width: units.dp(1.5)
                border.color: captionField.activeFocus ? Style.brand : Style.divider

                TextEdit {
                    id: captionField
                    anchors { fill: parent; margins: Style.spacingM }
                    font.family: Style.fontFor(text)
                    font.pixelSize: Style.fontRegular
                    color: Style.textPrimary
                    wrapMode: Text.WordWrap
                }

                Label {
                    anchors { left: parent.left; top: parent.top; leftMargin: Style.spacingM; topMargin: Style.spacingM }
                    visible: captionField.text.length === 0 && !captionField.activeFocus && !Qt.inputMethod.visible
                    text: Lang.tr("Write a caption...")
                    color: Style.textSecondary
                    font.pixelSize: Style.fontRegular
                    font.family: Style.fontFor(text)
                }
            }

            // Photos header
            Label {
                text: Lang.tr("Photos (%1/%2)").arg(page.imageUrls.length).arg(page.maxImages)
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
                            radius: Style.cardRadius
                            color: Style.iconBackground
                            clip: true
                            Image {
                                anchors.fill: parent
                                source: modelData
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                autoTransform: true     // honour EXIF orientation
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
                            radius: Style.cardRadius
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
                                text: Lang.tr("Add photo")
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
                                text: Lang.tr("Uploading…")
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
}
