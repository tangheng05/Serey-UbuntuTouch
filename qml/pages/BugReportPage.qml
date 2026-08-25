import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/BugReportService.js" as BugReportService

Page {
    id: page

    property bool submitting: false
    property bool uploading: false
    property bool loading: false
    property string errorMsg: ""
    property var imageUrls: []

    readonly property int maxImages: 5
    readonly property int maxChars: 2000
    readonly property real maxContentWidth: units.gu(60)

    // Kept at every width, like the other settings sub-pages: a wide window still needs
    // a visible way back, and the panel beside it is a list, not a back affordance.
    header: PageHeader {
        title: Lang.tr("Report Improvement")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.pageStack.pop() }
        ]
    }

    // Without this the pushed page leaves active focus on the header's back action, and
    // Suru paints its focus underline over the header divider (reads as a broken hairline).
    property Item keyboardFocusItem: scroll
    Keys.onEscapePressed: Nav.focusMaster()
    onVisibleChanged: if (visible) scroll.forceActiveFocus()

    ListModel { id: reportsModel; dynamicRoles: true }

    Component.onCompleted: {
        page.load();
        scroll.forceActiveFocus();
    }

    function load() {
        if (!Session.isLoggedIn)
            return;
        page.loading = true;
        page.errorMsg = "";
        BugReportService.myReports(Config.baseUrl, Session.token,
            function (list) {
                page.loading = false;
                reportsModel.clear();
                for (var i = 0; i < list.length; i++)
                    reportsModel.append(list[i]);
            },
            function (err) {
                page.loading = false;
                // A failed history fetch must not block the form, so it only shows above the list.
                page.errorMsg = (err && err.message) || Lang.tr("Couldn't load your reports.");
            });
    }

    // What triage needs to reproduce a report: build and platform, nothing identifying.
    function deviceInfo() {
        return {
            app: "Ubuntu Touch",
            app_version: Config.appVersion,
            platform: Qt.platform.os,
            language: Session.language || "en",
            screen: Math.round(page.width) + "x" + Math.round(page.height)
        };
    }

    function submit() {
        var text = descField.text.trim();
        if (text.length === 0) {
            Toast.error(Lang.tr("Describe the problem first."));
            return;
        }
        page.submitting = true;
        BugReportService.submit(Config.baseUrl, Session.token,
            { description: text, imageUrls: page.imageUrls, deviceInfo: page.deviceInfo() },
            function () {
                page.submitting = false;
                Toast.success(Lang.tr("Thanks! Your report has been sent."));
                page.resetForm();
                page.load();
            },
            function (err) { page._fail(err, Lang.tr("Couldn't send the report.")); });
    }

    function confirmDelete(index) {
        PopupUtils.open(deleteDialog, page, { rowIndex: index });
    }

    function removeReport(index) {
        var r = reportsModel.get(index);
        if (!r) return;
        var id = String(r.id);
        BugReportService.removeOwn(Config.baseUrl, Session.token, id,
            function () {
                reportsModel.remove(index);
                Toast.show(Lang.tr("Report deleted"));
            },
            function (err) {
                if (err && err.status === 401) return;
                Toast.error((err && err.message) || Lang.tr("Couldn't delete the report."));
            });
    }

    // A 401 is already toasted by the global handler; don't show it twice.
    function _fail(err, fallback) {
        page.submitting = false;
        if (err && err.status === 401)
            return;
        Toast.error((err && err.message) || fallback);
    }

    function resetForm() {
        descField.text = "";
        page.imageUrls = [];
        page.dismissKeyboard();
    }

    function addImage() {
        if (page.imageUrls.length >= page.maxImages) {
            Toast.show(Lang.tr("Maximum %1 images allowed").arg(page.maxImages));
            return;
        }
        if (page.uploading) return;
        PopupUtils.open(photoPickerComp);
    }

    function removeImage(idx) {
        var copy = [];
        for (var i = 0; i < page.imageUrls.length; i++)
            if (i !== idx) copy.push(page.imageUrls[i]);
        page.imageUrls = copy;
    }

    Component {
        id: photoPickerComp
        PhotoPicker { onPicked: shotUploader.upload(fileUrl) }
    }

    Component {
        id: deleteDialog
        Dialog {
            id: dlg
            property int rowIndex: -1
            title: Lang.tr("Delete report?")
            text: Lang.tr("This report will be removed for good.")
            Button {
                text: Lang.tr("Delete")
                color: Style.danger
                onClicked: { PopupUtils.close(dlg); page.removeReport(dlg.rowIndex); }
            }
            Button {
                text: Lang.tr("Cancel")
                onClicked: PopupUtils.close(dlg)
            }
        }
    }

    // Downscales and uploads each picked screenshot, then keeps the hosted URL.
    PhotoUploader {
        id: shotUploader
        onUploadingChanged: page.uploading = uploading
        onUploaded: {
            var copy = page.imageUrls.slice();
            copy.push(url);
            page.imageUrls = copy;
            Toast.success(Lang.tr("Screenshot attached"));
        }
        onFailed: Toast.error(message)
    }

    // Neutral focus target so tapping empty space drops the on-screen keyboard.
    Item { id: focusSink }
    function dismissKeyboard() {
        focusSink.forceActiveFocus();
        Qt.inputMethod.hide();
    }

    Flickable {
        id: scroll
        anchors { top: page.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        // Shrink above the OSK so the whole form stays reachable while typing.
        anchors.bottomMargin: Qt.inputMethod.visible ? Qt.inputMethod.keyboardRectangle.height : 0
        contentWidth: width
        contentHeight: form.height + Style.spacingL * 2
        clip: true

        // Behind the form: taps that miss a field dismiss the keyboard, drags still flick.
        MouseArea {
            width: scroll.width
            height: Math.max(scroll.height, form.height + Style.spacingL * 2)
            z: -1
            onClicked: page.dismissKeyboard()
        }

        Column {
            id: form
            // Centred at the same width as the other settings panes.
            width: Math.min(parent.width - Style.spacingM * 2, units.gu(50))
            x: (parent.width - width) / 2
            y: Style.spacingL
            spacing: Style.spacingM

            Item { width: 1; height: Style.spacingS }

            Label {
                width: parent.width
                wrapMode: Text.WordWrap
                text: Lang.tr("Found a bug or have an idea? Tell us what happened and we will look into it.")
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFor(text)
                color: Style.textSecondary
            }

            MultilineField {
                id: descField
                width: parent.width
                height: Math.max(units.gu(14), descField.input.contentHeight + Style.spacingM * 2)
                maximumLength: page.maxChars
                placeholder: Lang.tr("Describe the problem, what you expected, and how to reproduce it…")
            }

            Label {
                anchors.right: parent.right
                text: descField.length + "/" + page.maxChars
                font.pixelSize: Style.fontXSmall
                color: descField.length >= page.maxChars ? Style.danger : Style.textSecondary
            }

            Label {
                text: Lang.tr("Screenshots (%1/%2)").arg(page.imageUrls.length).arg(page.maxImages)
                font.pixelSize: Style.fontSmall
                font.weight: Font.DemiBold
                font.family: Style.fontFor(text)
                color: Style.textPrimary
            }

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
                                autoTransform: true          // honour EXIF orientation
                                sourceSize.width: units.gu(20)
                            }
                        }

                        AbstractButton {
                            anchors { top: parent.top; right: parent.right; topMargin: units.dp(4); rightMargin: units.dp(4) }
                            width: units.gu(2.5); height: width
                            onClicked: page.removeImage(index)
                            Rectangle { anchors.fill: parent; radius: width / 2; color: Qt.rgba(0, 0, 0, 0.5) }
                            Icon {
                                anchors.centerIn: parent
                                width: units.gu(1.5); height: width
                                name: "close"; color: "white"
                            }
                        }
                    }
                }

                Item {
                    id: addTile
                    visible: page.imageUrls.length < page.maxImages
                    width: (parent.width - Style.spacingS * 2) / 3
                    height: width

                    AbstractButton {
                        anchors.fill: parent
                        enabled: !page.uploading
                        onClicked: page.addImage()

                        Rectangle { anchors.fill: parent; radius: Style.cardRadius; color: Style.iconBackground }

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
                                    name: "add"; color: Style.textOnBrand
                                }
                            }
                            // Bounded to the tile: translations run much longer than "Add image".
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: addTile.width - Style.spacingS
                                text: Lang.tr("Add image")
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                font.pixelSize: Style.fontXSmall
                                font.family: Style.fontFor(text)
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
                                width: addTile.width - Style.spacingS
                                text: Lang.tr("Uploading…")
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                font.pixelSize: Style.fontXSmall
                                font.family: Style.fontFor(text)
                                color: Style.textSecondary
                            }
                        }
                    }
                }
            }

            PrimaryButton {
                width: parent.width
                busy: page.submitting
                enabled: !page.submitting && !page.uploading && descField.text.trim().length > 0
                text: page.submitting ? Lang.tr("Sending…") : Lang.tr("Send report")
                onClicked: page.submit()
            }

            Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

            Label {
                text: Lang.tr("Your reports")
                font.pixelSize: Style.fontMedium
                font.weight: Font.DemiBold
                font.family: Style.fontFor(text)
                color: Style.textPrimary
            }

            ActivityIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: page.loading
                visible: running
            }

            Label {
                width: parent.width
                wrapMode: Text.WordWrap
                visible: !page.loading && page.errorMsg !== ""
                text: page.errorMsg
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFor(text)
                color: Style.danger
            }

            Label {
                width: parent.width
                wrapMode: Text.WordWrap
                visible: !page.loading && page.errorMsg === "" && reportsModel.count === 0
                text: Lang.tr("Nothing reported yet.")
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFor(text)
                color: Style.textSecondary
            }

            Repeater {
                model: reportsModel
                delegate: Rectangle {
                    id: reportCard
                    // imagesStr is joined at the mapper; a ListModel would wrap the array itself.
                    readonly property var shots: (model.imagesStr || "").split("\n").filter(function (s) { return s.length > 0; })

                    width: form.width
                    height: cardCol.height + Style.spacingM * 2
                    radius: Style.cardRadius
                    color: Style.card
                    border.width: units.dp(1)
                    border.color: Style.divider

                    Column {
                        id: cardCol
                        anchors {
                            left: parent.left; right: parent.right; top: parent.top
                            margins: Style.spacingM
                        }
                        spacing: Style.spacingXs

                        Label {
                            text: Style.formatTimeAgo(model.createdAt)
                            font.pixelSize: Style.fontXSmall
                            color: Style.textSecondary
                        }

                        Label {
                            width: parent.width
                            text: model.description
                            wrapMode: Text.WordWrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                            font.pixelSize: Style.fontSmall
                            font.family: Style.fontFor(text)
                            color: Style.textPrimary
                        }

                        Row {
                            spacing: Style.spacingS
                            visible: reportCard.shots.length > 0
                            Repeater {
                                model: reportCard.shots
                                delegate: Rectangle {
                                    width: units.gu(7); height: width
                                    radius: Style.cardRadius
                                    color: Style.iconBackground
                                    clip: true
                                    Image {
                                        anchors.fill: parent
                                        source: modelData
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        sourceSize.width: units.gu(14)
                                    }
                                }
                            }
                        }

                        Item { width: 1; height: Style.spacingXs }

                        AbstractButton {
                            width: delRow.width
                            height: units.gu(3)
                            onClicked: page.confirmDelete(index)
                            Row {
                                id: delRow
                                spacing: Style.spacingXs
                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(2); height: width
                                    name: "delete"; color: Style.danger
                                }
                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Lang.tr("Delete")
                                    font.pixelSize: Style.fontXSmall
                                    font.family: Style.fontFor(text)
                                    color: Style.danger
                                }
                            }
                        }
                    }
                }
            }

            Item { width: 1; height: Style.spacingL }
        }
    }
}
