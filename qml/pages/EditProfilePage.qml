import QtQuick 2.7
import QtGraphicalEffects 1.0
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/AccountService.js" as AccountService

/*
 * Edit the signed-in user's profile: avatar (uploaded via Content Hub + the
 * media server), bio, name, email, gender and date of birth. Text fields save
 * in one call (`update-user-detail`); the avatar is uploaded + set active as
 * soon as it's picked. Prefilled from `initial` (the Settings profile) so it
 * opens populated with no reload flash.
 */
Page {
    id: page

    property var initial: null

    property bool busy: false          // saving text fields
    property bool uploading: false     // avatar upload in flight
    property bool coverUploading: false
    property string errorMsg: ""
    property string avatarUrl: initial ? (initial.profileUrl || "") : ""
    property string coverUrl: initial ? (initial.coverUrl || "") : ""
    property int genderId: 0           // 0 none, 1 male, 2 female
    property string pickTarget: "avatar"   // which image the picker is changing

    header: PageHeader {
        title: i18n.tr("Edit profile")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: i18n.tr("Back"); onTriggered: page.pageStack.pop() }
        ]
    }

    Component.onCompleted: {
        if (initial) {
            firstField.text = initial.firstName || "";
            lastField.text = initial.lastName || "";
            bioField.text = initial.bio || "";
            emailField.text = initial.email || "";
            dobField.text = initial.dob || "";
            genderId = initial.gender === "Male" ? 1 : (initial.gender === "Female" ? 2 : 0);
        }
    }

    function fail(err) { busy = false; uploading = false; coverUploading = false; page.errorMsg = err.message; }

    // The picker is shared between the avatar and the cover; route by pickTarget.
    function onPhotoPicked(fileUrl) {
        if (page.pickTarget === "cover") uploadCover(fileUrl);
        else uploadAvatar(fileUrl);
    }

    // Avatar + cover both downscale + upload through imgUploader, then set the
    // hosted URL active. pickTarget routes the post-upload step (see imgUploader).
    function uploadAvatar(fileUrl) { errorMsg = ""; uploading = true; imgUploader.upload(fileUrl); }
    function uploadCover(fileUrl)  { errorMsg = ""; coverUploading = true; imgUploader.upload(fileUrl); }

    PhotoUploader {
        id: imgUploader
        onUploaded: {
            if (page.pickTarget === "cover") {
                AccountService.setCoverPhoto(Config.baseUrl, Session.token, url,
                    function () {
                        page.coverUploading = false;
                        page.coverUrl = url;
                        Toast.success(i18n.tr("Cover updated."));
                    }, page.fail);
            } else {
                AccountService.setProfilePicture(Config.baseUrl, Session.token, url,
                    function () {
                        page.uploading = false;
                        page.avatarUrl = url;
                        Toast.success(i18n.tr("Photo updated."));
                    }, page.fail);
            }
        }
        onFailed: page.fail({ message: message })
    }

    // --- Save the editable detail fields ------------------------------------
    function save() {
        if (busy || uploading) return;
        errorMsg = "";
        if (emailField.text.length > 0 && emailField.text.indexOf("@") < 0) {
            errorMsg = i18n.tr("Please enter a valid email address.");
            return;
        }
        busy = true;
        AccountService.updateUserDetail(Config.baseUrl, Session.token, {
            firstname: firstField.text,
            lastname: lastField.text,
            email: emailField.text,
            gender_id: page.genderId || undefined,
            dob: dobField.text,
            bio: bioField.text
        }, function () {
            busy = false;
            Toast.success(i18n.tr("Profile updated."));
            page.pageStack.pop();
        }, fail);
    }

    KeyboardAwareFlickable {
        anchors { top: page.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentWidth: width
        contentHeight: form.height + Style.spacingL * 2
        clip: true

        Column {
            id: form
            width: Math.min(parent.width - Style.spacingL * 2, units.gu(50))
            anchors.horizontalCenter: parent.horizontalCenter
            y: Style.spacingL
            spacing: Style.spacingM

            // --- Cover banner -------------------------------------------------
            AbstractButton {
                width: parent.width
                height: units.gu(15)
                enabled: !page.coverUploading
                onClicked: { page.pickTarget = "cover"; PopupUtils.open(photoPickerComponent); }

                Rectangle {                 // brand fallback when no cover
                    anchors.fill: parent
                    radius: Style.cardRadius
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Style.brand }
                        GradientStop { position: 1.0; color: Style.brandDark }
                    }
                }
                Image {
                    anchors.fill: parent
                    source: page.coverUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    autoTransform: true
                    sourceSize.width: width
                    visible: page.coverUrl.length > 0
                    layer.enabled: true
                    layer.effect: OpacityMask { maskSource: coverMask }
                }
                Rectangle { id: coverMask; anchors.fill: parent; radius: Style.cardRadius; visible: false }

                // "Edit cover" chip
                Rectangle {
                    anchors { right: parent.right; bottom: parent.bottom; margins: Style.spacingS }
                    height: units.gu(3.4); width: coverHint.width + Style.spacingM; radius: height / 2
                    color: Qt.rgba(0, 0, 0, 0.45)
                    Row {
                        id: coverHint
                        anchors.centerIn: parent
                        spacing: units.gu(0.5)
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: units.gu(1.8); height: width
                            name: "camera-symbolic"; color: Style.textOnBrand
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: i18n.tr("Edit cover")
                            font.pixelSize: Style.fontXSmall; font.family: Style.fontFamily
                            color: Style.textOnBrand
                        }
                    }
                }
                Rectangle {                 // uploading overlay
                    anchors.fill: parent
                    radius: Style.cardRadius
                    color: Qt.rgba(0, 0, 0, 0.35)
                    visible: page.coverUploading
                    ActivityIndicator { anchors.centerIn: parent; running: page.coverUploading }
                }
            }

            // --- Avatar -------------------------------------------------------
            // AbstractButton (not a raw MouseArea) so the tap is reliable inside
            // the Flickable — matches how the rest of the app handles taps.
            AbstractButton {
                anchors.horizontalCenter: parent.horizontalCenter
                width: units.gu(12); height: width
                enabled: !page.uploading
                onClicked: { page.pickTarget = "avatar"; PopupUtils.open(photoPickerComponent); }

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: page.avatarUrl ? Style.iconBackground : Style.avatarTint("")
                    Label {
                        anchors.centerIn: parent
                        visible: !page.avatarUrl
                        text: (page.initial && page.initial.username ? page.initial.username : "?").charAt(0).toUpperCase()
                        font.pixelSize: units.gu(5)
                        font.bold: true
                        color: Style.brand
                    }
                }
                CircleImage {
                    anchors.fill: parent
                    source: page.avatarUrl
                    decode: units.gu(24)
                    visible: page.avatarUrl.length > 0
                }

                // Camera badge
                Rectangle {
                    anchors { right: parent.right; bottom: parent.bottom }
                    width: units.gu(3.6); height: width
                    radius: width / 2
                    color: Style.brand
                    border.width: units.dp(2); border.color: Style.surface
                    Icon {
                        anchors.centerIn: parent
                        width: units.gu(2); height: width
                        name: "camera-symbolic"
                        color: Style.textOnBrand
                    }
                }

                // Dim + spinner while uploading
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Qt.rgba(0, 0, 0, 0.35)
                    visible: page.uploading
                    ActivityIndicator { anchors.centerIn: parent; running: page.uploading }
                }
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: i18n.tr("Tap photo to change")
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFamily
                color: Style.textSecondary
            }

            Item { width: 1; height: Style.spacingXs }

            // --- Fields -------------------------------------------------------
            Label {
                text: i18n.tr("First name")
                font.pixelSize: Style.fontSmall; font.family: Style.fontFamily; color: Style.textSecondary
            }
            FormField {
                id: firstField
                width: parent.width
                placeholder: i18n.tr("First name")
            }

            Label {
                text: i18n.tr("Last name")
                font.pixelSize: Style.fontSmall; font.family: Style.fontFamily; color: Style.textSecondary
            }
            FormField {
                id: lastField
                width: parent.width
                placeholder: i18n.tr("Last name")
            }

            Label {
                text: i18n.tr("Bio")
                font.pixelSize: Style.fontSmall; font.family: Style.fontFamily; color: Style.textSecondary
            }
            MultilineField {
                id: bioField
                width: parent.width
                placeholder: i18n.tr("Tell people a little about yourself")
                maximumLength: 160
            }
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignRight
                text: bioField.length + "/160"
                font.pixelSize: Style.fontXSmall; font.family: Style.fontFamily; color: Style.textSecondary
            }

            Label {
                text: i18n.tr("Email")
                font.pixelSize: Style.fontSmall; font.family: Style.fontFamily; color: Style.textSecondary
            }
            FormField {
                id: emailField
                width: parent.width
                placeholder: i18n.tr("Email")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhEmailCharactersOnly
            }

            Label {
                text: i18n.tr("Gender")
                font.pixelSize: Style.fontSmall; font.family: Style.fontFamily; color: Style.textSecondary
            }
            Row {
                width: parent.width
                spacing: Style.spacingS
                Repeater {
                    model: [ { id: 1, label: i18n.tr("Male") }, { id: 2, label: i18n.tr("Female") } ]
                    delegate: AbstractButton {
                        width: (form.width - Style.spacingS) / 2
                        height: units.gu(5.5)
                        onClicked: page.genderId = modelData.id
                        Rectangle {
                            anchors.fill: parent
                            radius: Style.cardRadius
                            property bool sel: page.genderId === modelData.id
                            color: sel ? Style.brand : (parent.pressed ? Style.iconBackground : "transparent")
                            border.width: units.dp(1.5)
                            border.color: sel ? Style.brand : Style.divider
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Label {
                                anchors.centerIn: parent
                                text: modelData.label
                                font.pixelSize: Style.fontRegular
                                font.weight: Font.DemiBold
                                font.family: Style.fontFamily
                                color: parent.sel ? Style.textOnBrand : Style.textPrimary
                            }
                        }
                    }
                }
            }

            Label {
                text: i18n.tr("Date of birth")
                font.pixelSize: Style.fontSmall; font.family: Style.fontFamily; color: Style.textSecondary
            }
            FormField {
                id: dobField
                width: parent.width
                placeholder: i18n.tr("YYYY-MM-DD")
                inputMethodHints: Qt.ImhDate
            }

            Label {
                width: parent.width
                font.family: Style.fontFamily
                font.pixelSize: Style.fontSmall
                text: page.errorMsg
                color: Style.danger
                wrapMode: Text.WordWrap
                visible: text.length > 0
            }

            Item { width: 1; height: Style.spacingXs }

            PrimaryButton {
                width: parent.width
                busy: page.busy
                enabled: !page.busy && !page.uploading
                text: page.busy ? i18n.tr("Saving…") : i18n.tr("Save changes")
                onClicked: page.save()
            }
        }
    }

    // Opened on demand (PopupUtils.open) so the Content Hub picker is a proper
    // root-parented popup with a correct size — see PhotoPicker.qml.
    Component {
        id: photoPickerComponent
        PhotoPicker {
            onPicked: page.onPhotoPicked(fileUrl)
        }
    }
}
