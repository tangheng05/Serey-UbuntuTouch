import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/PlatformService.js" as PlatformService
import "../services/AccountService.js" as AccountService

/*
 * Basic native CMS for platform owners — the mobile subset of the web
 * dashboard (serey.io/social-media-owners). Deliberately small: rename the
 * platform, change its profile picture (icon), and set the article/video
 * posting permissions. Everything else links out to the full web dashboard.
 * All mutations are authorized server-side by CommunityManager membership,
 * so this page never has to prove ownership.
 */
Page {
    id: page

    header: PageHeader {
        title: Lang.tr("Manage Platform")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.pageStack.pop() }
        ]
    }

    // "loading" → "ready" | "none" (no managed community) | "error"
    property string state_: "loading"
    property string errorMsg: ""

    property var communities: []      // every community the user owns/manages
    property var community: null      // the one being managed right now
    property bool savingName: false

    // Posting modes (web-dashboard parity). Blog: only_me | everyone | custom
    // (custom = owner-picked poster members; the member list itself is managed
    // on the web). Video: only_me | everyone.
    property string blogMode: "only_me"
    property string videoMode: "only_me"
    property bool permBusy: false
    // Second layers are REAL pushed Pages (PageStack), not overlays — an
    // overlay under the main header shows two back chevrons at once, which is
    // exactly what the Lomiri header pattern avoids.
    property string permPickerKind: "blog"   // "blog" | "video"

    function modeLabel(mode) {
        return mode === "everyone" ? Lang.tr("Everyone")
             : mode === "custom"   ? Lang.tr("Custom")
             : Lang.tr("Only me");
    }
    // Options for the picker page, per kind (video has no custom mode).
    readonly property var permOptions: permPickerKind === "blog"
        ? [ { mode: "only_me",  label: Lang.tr("Only me"),  desc: Lang.tr("Only you and your managers can post.") },
            { mode: "everyone", label: Lang.tr("Everyone"), desc: Lang.tr("Anyone can post articles.") },
            { mode: "custom",   label: Lang.tr("Custom"),   desc: Lang.tr("Only members you pick can post. Manage members in the web dashboard.") } ]
        : [ { mode: "only_me",  label: Lang.tr("Only me"),  desc: Lang.tr("Only you and your managers can post.") },
            { mode: "everyone", label: Lang.tr("Everyone"), desc: Lang.tr("Anyone can post videos.") } ]
    readonly property string permCurrentMode: permPickerKind === "blog" ? blogMode : videoMode

    function setPermMode(mode) {
        if (permPickerKind === "blog") setBlogMode(mode);
        else setVideoMode(mode);
    }

    Component.onCompleted: load()

    function load() {
        state_ = "loading";
        // Refresh the managed-community ids first — Settings may route here
        // right after a create, before Main's startup sync ran.
        AccountService.ownedCommunityIds(Config.baseUrl, Session.token,
            function (ids) {
                if (ids.length === 0) { page.state_ = "none"; return; }
                var set = {};
                for (var i = 0; i < ids.length; i++) set[ids[i]] = true;
                Config.ownedCommunityIdSet = set;
                PlatformService.findManagedCommunities(Config.baseUrl, set,
                    function (list) {
                        if (list.length === 0) { page.state_ = "none"; return; }
                        page.communities = list;
                        page._select(list[0]);
                    },
                    function (err) { page._fail(err); });
            },
            function (err) { page._fail(err); });
    }

    // Point the whole page at one community (also the switcher's entry point).
    function _select(c) {
        state_ = "loading";
        community = c;
        nameField.text = c.title;
        videoMode = c.videoIsAllowPost ? "everyone" : "only_me";
        // Blog mode needs the member list: is_allow_post=true → everyone;
        // false + poster members → custom; false alone → only me (same
        // resolution the web dashboard uses).
        PlatformService.hasPosterMembers(Config.baseUrl, c.id,
            function (has) {
                page.blogMode = c.isAllowPost ? "everyone" : (has ? "custom" : "only_me");
                page.state_ = "ready";
            },
            function () {
                // Member list failing shouldn't block the page — fall back to
                // the two-state resolution.
                page.blogMode = c.isAllowPost ? "everyone" : "only_me";
                page.state_ = "ready";
            });
    }

    function _fail(err) {
        state_ = "error";
        errorMsg = (err && err.message) || Lang.tr("Something went wrong.");
    }

    // ── Mutations ────────────────────────────────────────────────────────────
    readonly property string nameText: nameField.text.trim()
    readonly property bool nameValid: nameText.length >= 2 && /^[a-zA-Z0-9 ]+$/.test(nameText)
    readonly property bool nameChanged: community !== null && nameText !== community.title

    function saveName() {
        if (savingName || !nameValid || !nameChanged) return;
        savingName = true;
        PlatformService.updateCommunityName(Config.baseUrl, Session.token,
            community.id, nameText,
            function () {
                page.savingName = false;
                var c = page.community; c.title = page.nameText; page.community = c;
                Toast.success(Lang.tr("Platform name updated."));
            },
            function (err) {
                page.savingName = false;
                Toast.error((err && err.message) || Lang.tr("Couldn't update the name."));
            });
    }

    // Radio modes only change on server success, so a failed call simply
    // leaves the previous selection lit — no revert dance needed.
    function setBlogMode(mode) {
        if (permBusy || mode === blogMode) return;
        permBusy = true;
        var allow = (mode === "everyone");   // custom and only_me both store false
        PlatformService.updateAllowPost(Config.baseUrl, Session.token, community.id, allow,
            function () {
                page.permBusy = false;
                page.blogMode = mode;
                community.isAllowPost = allow;
                if (mode === "custom")
                    Toast.show(Lang.tr("Add poster members from the web dashboard."));
                else
                    Toast.success(Lang.tr("Posting permission updated."));
            },
            function (err) {
                page.permBusy = false;
                Toast.error((err && err.message) || Lang.tr("Action failed."));
            });
    }
    function setVideoMode(mode) {
        if (permBusy || mode === videoMode) return;
        permBusy = true;
        var allow = (mode === "everyone");
        PlatformService.updateVideoAllowPost(Config.baseUrl, Session.token, community.id, allow,
            function () {
                page.permBusy = false;
                page.videoMode = mode;
                community.videoIsAllowPost = allow;
                Toast.success(Lang.tr("Posting permission updated."));
            },
            function (err) {
                page.permBusy = false;
                Toast.error((err && err.message) || Lang.tr("Action failed."));
            });
    }
    // ── Platform picture (icon_url) ─────────────────────────────────────────
    // Tap the avatar → ContentHub picker → downscale/upload → update-logo with
    // the current logo/footer echoed back (the schema requires them).
    property bool iconUploading: false

    function pickIcon() {
        if (iconUploading || community === null) return;
        PopupUtils.open(iconPickerComponent);
    }
    function onIconPicked(fileUrl) {
        iconUploading = true;
        iconUploader.upload(fileUrl);
    }

    PhotoUploader {
        id: iconUploader
        onUploaded: {
            PlatformService.updateCommunityIcon(Config.baseUrl, Session.token,
                page.community, url,
                function () {
                    page.iconUploading = false;
                    // Clone so the var-property change propagates to bindings.
                    var c = JSON.parse(JSON.stringify(page.community));
                    c.icon = url;
                    page.community = c;
                    for (var i = 0; i < page.communities.length; i++)
                        if (page.communities[i].id === c.id) { page.communities[i].icon = url; break; }
                    Toast.success(Lang.tr("Platform picture updated."));
                },
                function (err) {
                    page.iconUploading = false;
                    Toast.error((err && err.message) || Lang.tr("Couldn't update the picture."));
                });
        }
        onFailed: {
            page.iconUploading = false;
            Toast.error(message);
        }
    }
    Component {
        id: iconPickerComponent
        PhotoPicker {
            onPicked: page.onIconPicked(fileUrl)
        }
    }

    Item { id: focusSink }
    function dismissKeyboard() { focusSink.forceActiveFocus(); Qt.inputMethod.hide(); }

    // ═════════════════════ States ═════════════════════
    ActivityIndicator {
        anchors.centerIn: parent
        running: page.state_ === "loading"
        visible: running
    }

    Column {
        visible: page.state_ === "none" || page.state_ === "error"
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.spacingL * 2, units.gu(45))
        spacing: Style.spacingM

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: page.state_ === "none" ? Lang.tr("You don't manage a platform yet.")
                                         : page.errorMsg
            font.pixelSize: Style.fontRegular
            font.family: Style.fontFor(text)
            color: Style.textSecondary
        }
        SecondaryButton {
            visible: page.state_ === "error"
            text: Lang.tr("Retry")
            onClicked: page.load()
        }
    }

    // ═════════════════════ Content ═════════════════════
    KeyboardAwareFlickable {
        anchors { top: page.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: page.state_ === "ready"
        contentWidth: width
        contentHeight: contentCol.height + Style.spacingL
        clip: true

        Column {
            id: contentCol
            width: parent.width
            spacing: 0

            // ── Cover banner (profile-view style, brand-blue) + avatar ──
            Item {
                width: parent.width
                height: units.gu(14)
                clip: true

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Style.brand }
                        GradientStop { position: 1.0; color: Style.brandDark }
                    }
                }
            }
            Item {
                width: parent.width
                height: units.gu(5)          // reserves the avatar's lower half

                Item {
                    id: avatarHolder
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: -units.gu(4.6)
                    width: units.gu(9.6); height: width

                    Rectangle {              // white ring
                        anchors.fill: parent
                        radius: width / 2
                        color: Style.surface
                    }
                    Rectangle {              // letter fallback when no icon
                        anchors.fill: parent
                        anchors.margins: units.gu(0.3)
                        radius: width / 2
                        color: Style.avatarTint("")
                        visible: !(page.community && page.community.icon)
                        Label {
                            anchors.centerIn: parent
                            text: page.community ? (page.community.title || "?").charAt(0).toUpperCase() : "?"
                            font.pixelSize: units.gu(4)
                            font.bold: true
                            color: Style.brand
                        }
                    }
                    CircleImage {
                        anchors.fill: parent
                        anchors.margins: units.gu(0.3)
                        source: page.community && page.community.icon ? page.community.icon : ""
                        decode: units.gu(19)
                        visible: !!(page.community && page.community.icon)
                    }

                    // Dim + spinner while the new picture uploads.
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: units.gu(0.3)
                        radius: width / 2
                        color: Qt.rgba(0, 0, 0, 0.35)
                        visible: page.iconUploading
                        ActivityIndicator {
                            anchors.centerIn: parent
                            running: page.iconUploading
                        }
                    }

                    // Camera badge — the avatar is editable (Edit Profile pattern).
                    Rectangle {
                        anchors { right: parent.right; bottom: parent.bottom }
                        width: units.gu(3.2); height: width; radius: width / 2
                        color: Style.brand
                        border.width: units.dp(2)
                        border.color: Style.surface
                        Icon {
                            anchors.centerIn: parent
                            name: "camera-symbolic"
                            width: units.gu(1.8); height: width
                            color: "white"
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !page.iconUploading
                        onClicked: page.pickIcon()
                    }
                }
            }

            Item { width: 1; height: Style.spacingS }

            // ── Identity ──
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: page.community ? page.community.title : ""
                elide: Text.ElideRight
                font.pixelSize: Style.fontTitle
                font.weight: Font.DemiBold
                font.family: Style.fontFor(text)
                color: Style.textTitle
            }
            Item { width: 1; height: units.dp(2) }
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: page.community ? page.community.dns : ""
                elide: Text.ElideMiddle
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFamily
                color: Style.textSecondary
            }
            LinkButton {
                visible: page.communities.length > 1
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                label: Lang.tr("Switch platform")
                onClicked: { page.dismissKeyboard(); page.pageStack.push(switcherPage); }
            }
            Item { width: 1; height: Style.spacingM }

            Column {
            id: form
            // Convergence: centered gu-capped column on wide windows.
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width - Style.spacingM * 2, units.gu(60))
            spacing: 0

            // ── Platform name ──
            SettingsSectionHeader { text: Lang.tr("Platform name") }
            Item { width: 1; height: Style.spacingS }
            Item {
                width: parent.width
                height: units.gu(5)

                TextInput {
                    id: nameField
                    anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: Style.spacingS }
                    font.family: Style.fontFamily
                    font.pixelSize: Style.fontRegular
                    color: Style.textPrimary
                    clip: true
                    onTextChanged: if (text.length > 60) text = text.substring(0, 60)
                }
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: nameField.activeFocus ? units.dp(2) : units.dp(1)
                    color: nameField.activeFocus ? Style.brand : Style.divider
                }
            }
            Label {
                visible: page.nameText.length > 0 && !page.nameValid
                width: parent.width
                wrapMode: Text.WordWrap
                text: Lang.tr("Use letters, numbers and spaces only.")
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFor(text)
                color: Style.danger
            }
            Item { width: 1; height: Style.spacingS }
            PrimaryButton {
                visible: page.nameChanged
                enabled: page.nameValid && !page.savingName
                busy: page.savingName
                text: page.savingName ? Lang.tr("Saving…") : Lang.tr("Save name")
                onClicked: { page.dismissKeyboard(); page.saveName(); }
            }
            Item { width: 1; height: Style.spacingM }

            // ── Posting permissions — rows open a second-layer option list
            // (System Settings pattern: row shows the current value + chevron).
            SettingsSectionHeader { text: Lang.tr("Posting") }
            Repeater {
                model: [
                    { kind: "blog",  label: Lang.tr("Article posting") },
                    { kind: "video", label: Lang.tr("Video posting") }
                ]
                Item {
                    width: form.width
                    height: units.gu(7)

                    Rectangle {
                        x: -Style.spacingM; width: parent.width + Style.spacingM * 2
                        height: parent.height
                        color: permRowTap.pressed ? Style.pressed : "transparent"
                    }
                    Label {
                        anchors { left: parent.left; right: permValue.left; rightMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
                        text: modelData.label
                        elide: Text.ElideRight
                        font.pixelSize: Style.fontRegular
                        font.family: Style.fontFor(text)
                        color: Style.textPrimary
                    }
                    Row {
                        id: permValue
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        spacing: Style.spacingS
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.modeLabel(modelData.kind === "blog" ? page.blogMode : page.videoMode)
                            font.pixelSize: Style.fontRegular
                            font.family: Style.fontFor(text)
                            color: Style.textSecondary
                        }
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "next"
                            width: units.gu(2); height: width
                            color: Style.textSecondary
                        }
                    }
                    Rectangle {
                        x: -Style.spacingM; width: parent.width + Style.spacingM * 2
                        anchors.bottom: parent.bottom
                        height: units.dp(1); color: Style.divider
                    }
                    MouseArea {
                        id: permRowTap
                        anchors.fill: parent
                        onClicked: {
                            page.dismissKeyboard();
                            page.permPickerKind = modelData.kind;
                            page.pageStack.push(permPickerPage);
                        }
                    }
                }
            }
            Item { width: 1; height: Style.spacingM }

            Item { width: 1; height: Style.spacingL }

            // Everything else lives in the full web CMS.
            LinkButton {
                label: Lang.tr("Open full dashboard in browser")
                onClicked: Qt.openUrlExternally("https://serey.io/social-media-owners")
            }
            }
        }
    }

    // ═════════════════════ Second-layer pages (pushed, single header) ═══════
    // Real PageStack pushes: an overlay drawn under the main header shows two
    // back chevrons at once — Lomiri sub-views replace the header instead.

    Component {
        id: switcherPage
        Page {
            id: swPage
            header: PageHeader {
                title: Lang.tr("Switch platform")
                leadingActionBar.actions: [
                    Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.pageStack.pop() }
                ]
            }

        ListView {
            anchors { top: swPage.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
            clip: true
            model: page.communities
            delegate: Item {
                width: ListView.view.width
                height: units.gu(7)

                Rectangle {
                    anchors.fill: parent
                    color: swTap.pressed ? Style.pressed : "transparent"
                }
                CircleImage {
                    id: swIcon
                    anchors { left: parent.left; leftMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                    width: units.gu(4); height: width
                    source: modelData.icon || ""
                    decode: units.gu(8)
                    visible: !!modelData.icon
                }
                Rectangle {
                    anchors.fill: swIcon
                    radius: width / 2
                    color: Style.avatarTint("")
                    visible: !modelData.icon
                    Label {
                        anchors.centerIn: parent
                        text: (modelData.title || "?").charAt(0).toUpperCase()
                        font.bold: true
                        color: Style.brand
                    }
                }
                Column {
                    anchors {
                        left: parent.left; leftMargin: Style.spacingM + units.gu(5)
                        right: swTick.left; rightMargin: Style.spacingS
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: units.dp(2)
                    Label {
                        width: parent.width
                        text: modelData.title
                        elide: Text.ElideRight
                        font.pixelSize: Style.fontRegular
                        font.family: Style.fontFor(text)
                        color: Style.textPrimary
                    }
                    Label {
                        width: parent.width
                        text: modelData.dns
                        elide: Text.ElideMiddle
                        font.pixelSize: Style.fontXSmall
                        font.family: Style.fontFamily
                        color: Style.textSecondary
                    }
                }
                Icon {
                    id: swTick
                    anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                    visible: page.community !== null && page.community.id === modelData.id
                    name: "tick"
                    width: units.gu(2.5); height: width
                    color: Style.success
                }
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: units.dp(1)
                    color: Style.divider
                }
                MouseArea {
                    id: swTap
                    anchors.fill: parent
                    onClicked: { page._select(modelData); page.pageStack.pop(); }
                }
            }
        }
        }
    }

    Component {
        id: permPickerPage
        Page {
            id: permPage
            header: PageHeader {
                title: page.permPickerKind === "blog" ? Lang.tr("Article posting") : Lang.tr("Video posting")
                leadingActionBar.actions: [
                    Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.pageStack.pop() }
                ]
            }

            // Saving indicator while an option is being applied.
            ActivityIndicator {
                anchors { top: permPage.header.bottom; topMargin: Style.spacingM; right: parent.right; rightMargin: Style.spacingM }
                z: 2
                running: page.permBusy
                visible: running
                implicitWidth: units.gu(2.5); implicitHeight: units.gu(2.5)
            }

        Column {
            anchors { top: permPage.header.bottom; left: parent.left; right: parent.right }

            Repeater {
                model: page.permOptions
                Item {
                    width: parent.width
                    height: units.gu(9)

                    Rectangle {
                        anchors.fill: parent
                        color: permOptTap.pressed ? Style.pressed : "transparent"
                    }
                    Rectangle {   // Suru-green radio
                        id: permOptRadio
                        anchors { left: parent.left; leftMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                        width: units.gu(2.5); height: width; radius: width / 2
                        color: page.permCurrentMode === modelData.mode ? Style.success : "transparent"
                        border.width: page.permCurrentMode === modelData.mode ? 0 : units.dp(1.5)
                        border.color: Style.dotInactive
                        Rectangle {
                            anchors.centerIn: parent
                            visible: page.permCurrentMode === modelData.mode
                            width: units.gu(1); height: width; radius: width / 2
                            color: "white"
                        }
                    }
                    Column {
                        anchors {
                            left: permOptRadio.right; leftMargin: Style.spacingM
                            right: parent.right; rightMargin: Style.spacingM
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: units.dp(2)
                        Label {
                            text: modelData.label
                            font.pixelSize: Style.fontRegular
                            font.family: Style.fontFor(text)
                            color: Style.textPrimary
                        }
                        Label {
                            width: parent.width
                            text: modelData.desc
                            wrapMode: Text.WordWrap
                            font.pixelSize: Style.fontXSmall
                            font.family: Style.fontFor(text)
                            color: Style.textSecondary
                        }
                    }
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: units.dp(1)
                        color: Style.divider
                    }
                    MouseArea {
                        id: permOptTap
                        anchors.fill: parent
                        enabled: !page.permBusy
                        onClicked: page.setPermMode(modelData.mode)
                    }
                }
            }
        }
        }
    }

}
