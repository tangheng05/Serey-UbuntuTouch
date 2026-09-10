import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/PlatformService.js" as PlatformService
import "../services/AccountService.js" as AccountService

// "Create your platform" wizard; gated on an active subscription (GET /subscription/active)
Page {
    id: page

    header: PageHeader {
        title: Lang.tr("Create Platform")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.pageStack.pop() }
        ]
    }

    // --- Plan gate: "checking" while /subscription/active runs -> "ok" | "noplan" | "error" ---
    property string gate: "checking"
    property string gateError: ""

    // --- Wizard state ---
    property int step: 0                 // 0..2 form steps, 3 = success
    readonly property int stepCount: 3

    // Step 0 - name + subdomain
    property string subStatus: "idle"    // idle|invalid|checking|free|taken
    property string subProblem: ""       // message when invalid
    property int subEpoch: 0             // drops stale availability responses

    // Step 1 - location
    property var countries: []
    property bool countriesLoading: false
    property bool countriesFailed: false
    property var categories: []
    property bool independent: false   // country is the standard path; independent is opt-in
    property var country: null           // { id, name, iconUrl } | null
    property int categoryId: 0           // 0 = none (server defaults to Other)
    property bool countryPickerOpen: false

    // Step 2 - branding
    // Used when the owner skips upload, so the community isn't left without any icon/logo
    readonly property string defaultBrandUrl: "https://upload.serey.io/images/e5129a31-2868-428c-a4ea-8d9a0dcb62dc-1788508734703.png"
    property string iconUrl: ""
    property string logoUrl: ""
    property string footerUrl: ""
    property string pickTarget: ""       // which slot the picked photo fills
    property string uploadingTarget: ""
    property bool creating: false

    // Step 3 - success
    property string createdDns: ""

    readonly property string nameText: nameField.text.trim()
    // Server rule: letters, digits and spaces only (community_schema regex).
    readonly property bool nameValid: nameText.length >= 2
                                      && /^[a-zA-Z0-9 ]+$/.test(nameText)
    readonly property bool canContinue:
        step === 0 ? (nameValid && subStatus === "free")
        // Web-wizard parity: category required once a country is chosen (unless list failed to load)
      : step === 1 ? (independent || (country !== null
                                      && (categoryId > 0 || categories.length === 0)))
      : !creating && uploadingTarget === ""

    Component.onCompleted: checkGate()

    function checkGate() {
        gate = "checking";
        PlatformService.getActiveSubscription(Config.baseUrl, Session.token,
            function (sub) {
                gate = sub.hasActive ? "ok" : "noplan";
                if (sub.hasActive) loadLists();
            },
            function (err) {
                gate = "error";
                gateError = (err && err.message) || Lang.tr("Something went wrong.");
            });
    }

    function loadLists() {
        countriesLoading = true;
        countriesFailed = false;
        PlatformService.getCountries(Config.baseUrl,
            function (rows) { countriesLoading = false; countries = rows; },
            function () { countriesLoading = false; countriesFailed = true; });
        PlatformService.getCategories(Config.baseUrl,
            function (rows) { categories = rows; },
            function () { /* optional; the server defaults to "Other" */ });
    }

    // --- Subdomain availability: 1-54 chars [a-z0-9-], no leading/trailing hyphen, not numeric-only, no dots ---
    function slugProblem(s) {
        if (s.length === 0) return "";
        if (s.length > 54) return Lang.tr("Address is too long (max 54 characters).");
        if (!/^[a-z0-9-]+$/.test(s)) return Lang.tr("Use only lowercase letters, numbers and hyphens.");
        if (s.charAt(0) === "-" || s.charAt(s.length - 1) === "-")
            return Lang.tr("Address can't start or end with a hyphen.");
        if (/^[0-9]+$/.test(s)) return Lang.tr("Address can't be numbers only.");
        return "";
    }

    function onSlugEdited() {
        subEpoch++;                       // any in-flight check is now stale
        var s = subField.text;
        if (s.length === 0) { subStatus = "idle"; subProblem = ""; return; }
        subProblem = slugProblem(s);
        if (subProblem !== "") { subStatus = "invalid"; subDebounce.stop(); return; }
        subStatus = "checking";
        subDebounce.restart();
    }

    Timer {
        id: subDebounce
        interval: 600
        onTriggered: {
            var epoch = ++page.subEpoch;
            var s = subField.text;
            PlatformService.checkSubdomain(Config.baseUrl, s,
                function (taken) {
                    if (epoch !== page.subEpoch) return;
                    page.subStatus = taken ? "taken" : "free";
                },
                function () {
                    if (epoch !== page.subEpoch) return;
                    // Couldn't verify; let the user retry by editing (server checks again on create)
                    page.subStatus = "idle";
                });
        }
    }

    // Routed through page-level functions: imported JS is unreliable inside delegate handlers
    function selectCountry(c) {
        country = { id: c.id, name: c.name, iconUrl: c.iconUrl };
        independent = false;
        countryPickerOpen = false;
        countrySearchField.text = "";
    }
    function selectCategory(id) {
        categoryId = id;
    }

    // --- Branding uploads ---
    function pickImage(target) {
        if (uploadingTarget !== "") return;
        pickTarget = target;
        PopupUtils.open(photoPickerComponent);
    }
    function onPhotoPicked(fileUrl) {
        uploadingTarget = pickTarget;
        imgUploader.upload(fileUrl);
    }

    PhotoUploader {
        id: imgUploader
        onUploaded: {
            if (page.uploadingTarget === "icon") page.iconUrl = url;
            else if (page.uploadingTarget === "logo") page.logoUrl = url;
            else if (page.uploadingTarget === "footer") page.footerUrl = url;
            page.uploadingTarget = "";
        }
        onFailed: {
            page.uploadingTarget = "";
            Toast.error(message);
        }
    }

    Component {
        id: photoPickerComponent
        PhotoPicker {
            onPicked: page.onPhotoPicked(fileUrl)
            onCancelled: page.pickTarget = ""
        }
    }

    // --- Create ---
    function create() {
        if (creating) return;
        creating = true;
        var slug = subField.text;
        PlatformService.createCommunity(Config.baseUrl, Session.token, {
            name: nameText,
            slug: slug,
            independent: independent,
            countryId: country ? country.id : null,
            categoryId: categoryId,
            iconUrl: iconUrl || page.defaultBrandUrl,
            logoUrl: logoUrl || page.defaultBrandUrl,
            footerLogoUrl: footerUrl
        }, function (res) {
            page.creating = false;
            page.createdDns = res.dns || (slug + ".serey.io");
            page.step = 3;
            Toast.success(Lang.tr("Your platform has been created!"));
            // Rebuild the community picker so the new platform shows without a restart
            Nav.refreshCommunities();
            // Seed the in-session cache: another API instance can serve a stale list for up to 60s
            if (res.id) {
                Config.addOrUpdateCommunity({
                    id: res.id,
                    title: res.title || page.nameText,
                    dns: page.createdDns,
                    icon: res.iconUrl || iconUrl || logoUrl || page.defaultBrandUrl,
                    allowPost: false,
                    videoAllowPost: false
                });
            }
            // Owner may now post to their own community, so refresh the owned-communities set
            AccountService.ownedCommunityIds(Config.baseUrl, Session.token,
                function (ids) {
                    var set = {};
                    for (var i = 0; i < ids.length; i++) set[ids[i]] = true;
                    if (res.id) set[res.id] = true;   // ensure managedCommunityId resolves now
                    Config.ownedCommunityIdSet = set;
                    // Pin the CMS hub to the just-created community (deterministic if owns several)
                    if (res.id) Config.overrideManagedCommunityId = res.id;
                }, function () {
                    if (res.id) {
                        var s = Object.assign({}, Config.ownedCommunityIdSet);
                        s[res.id] = true;
                        Config.ownedCommunityIdSet = s;
                        Config.overrideManagedCommunityId = res.id;
                    }
                });
        }, function (err) {
            page.creating = false;
            Toast.error((err && err.message) || Lang.tr("Couldn't create the platform."));
        });
    }

    function next() {
        if (!canContinue) return;
        if (step === 2) create();
        else { step++; dismissKeyboard(); }
    }

    Item { id: focusSink }
    function dismissKeyboard() { focusSink.forceActiveFocus(); Qt.inputMethod.hide(); }

    // --- Gate states ---
    ActivityIndicator {
        anchors.centerIn: parent
        running: page.gate === "checking"
        visible: running
    }

    // Load failure (offline included) gets the app-wide error/offline panel.
    ErrorState {
        anchors { top: page.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: page.gate === "error"
        message: page.gateError
        onRetry: page.checkGate()
    }

    Column {
        visible: page.gate === "noplan"
        anchors.centerIn: parent
        // Convergence: cap the width so the CTA doesn't stretch on desktop.
        width: Math.min(parent.width - Style.spacingL * 2, units.gu(45))
        spacing: Style.spacingM

        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "system-lock-screen"
            width: units.gu(6); height: width
            color: Style.textSecondary
        }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: Lang.tr("Subscription required")
            font.pixelSize: Style.fontLarge
            font.weight: Font.DemiBold
            font.family: Style.fontFor(text)
            color: Style.textTitle
        }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: Lang.tr("You need an active subscription plan to create your own platform. Choose a plan on the Homepage to get started.")
            font.pixelSize: Style.fontRegular
            font.family: Style.fontFor(text)
            color: Style.textSecondary
        }
        PrimaryButton {
            text: Lang.tr("View plans")
            onClicked: {
                page.pageStack.pop();
                Nav.goToTab(0);
            }
        }
    }

    // --- Wizard ---
    KeyboardAwareFlickable {
        anchors { top: page.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: page.gate === "ok"
        contentWidth: width
        contentHeight: form.height + Style.spacingL * 2
        clip: true

        Column {
            id: form
            // Convergence: adapt, not scale — desktop centers the form instead of stretching fields
            anchors { top: parent.top; topMargin: Style.spacingL; horizontalCenter: parent.horizontalCenter }
            width: Math.min(parent.width - Style.spacingM * 2, units.gu(60))
            spacing: Style.spacingM

            // --- Step indicator ---
            Column {
                visible: page.step < 3
                width: parent.width
                spacing: Style.spacingS

                Row {
                    width: parent.width
                    spacing: Style.spacingXs
                    Repeater {
                        model: page.stepCount
                        Rectangle {
                            width: (form.width - Style.spacingXs * (page.stepCount - 1)) / page.stepCount
                            height: units.dp(3)
                            radius: height / 2
                            color: index <= page.step ? Style.brand : Style.divider
                        }
                    }
                }
                Label {
                    text: Lang.tr("Step %1 of %2").arg(page.step + 1).arg(page.stepCount)
                    font.pixelSize: Style.fontXSmall
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                }
            }

            // --- Step 0 - Name + web address ---
            Column {
                visible: page.step === 0
                width: parent.width
                spacing: Style.spacingM

                Label {
                    text: Lang.tr("Name your platform")
                    font.pixelSize: Style.fontLarge
                    font.weight: Font.DemiBold
                    font.family: Style.fontFor(text)
                    color: Style.textTitle
                }

                // Platform name (Lomiri underline input).
                Item {
                    width: parent.width
                    height: Math.max(units.gu(5), nameField.contentHeight + Style.spacingM)

                    TextEdit {
                        id: nameField
                        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: Style.spacingS }
                        font.family: Style.fontFor(text)
                        font.pixelSize: Style.fontRegular
                        color: Style.textPrimary
                        wrapMode: Text.WordWrap
                        onTextChanged: if (text.length > 60) text = text.substring(0, 60)
                    }
                    Label {
                        anchors { left: nameField.left; top: nameField.top }
                        visible: nameField.text.length === 0 && !nameField.activeFocus
                        text: Lang.tr("Platform name")
                        color: Style.textSecondary
                        font.pixelSize: Style.fontRegular
                        font.family: Style.fontFor(text)
                    }
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: nameField.activeFocus ? units.dp(2) : units.dp(1)
                        color: nameField.activeFocus ? Style.brand : Style.divider
                    }
                }
                Label {
                    visible: nameField.text.trim().length > 0 && !page.nameValid
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: Lang.tr("Use letters, numbers and spaces only.")
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
                    color: Style.danger
                }

                // Subdomain slug, forced lowercase; fixed ".serey.io" suffix sits inside the field
                Item {
                    width: parent.width
                    height: units.gu(5)

                    Label {
                        id: subSuffix
                        anchors { right: parent.right; verticalCenter: subField.verticalCenter }
                        text: ".serey.io"
                        color: Style.textSecondary
                        font.pixelSize: Style.fontRegular
                        font.family: Style.fontFamily
                    }
                    TextInput {
                        id: subField
                        anchors {
                            left: parent.left
                            right: subSuffix.left; rightMargin: Style.spacingXs
                            top: parent.top; topMargin: Style.spacingS
                        }
                        font.family: Style.fontFamily
                        font.pixelSize: Style.fontRegular
                        color: Style.textPrimary
                        clip: true
                        inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhPreferLowercase
                        onTextChanged: {
                            var lower = text.toLowerCase();
                            if (lower !== text) { text = lower; return; }  // re-fires once
                            page.onSlugEdited();
                        }
                    }
                    Label {
                        anchors { left: subField.left; top: subField.top }
                        visible: subField.text.length === 0 && !subField.activeFocus
                        text: Lang.tr("Web address")
                        color: Style.textSecondary
                        font.pixelSize: Style.fontRegular
                        font.family: Style.fontFor(text)
                    }
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: subField.activeFocus ? units.dp(2) : units.dp(1)
                        color: subField.activeFocus ? Style.brand : Style.divider
                    }
                }
                Row {
                    visible: page.subStatus !== "idle"
                    spacing: Style.spacingXs

                    ActivityIndicator {
                        anchors.verticalCenter: parent.verticalCenter
                        running: page.subStatus === "checking"
                        visible: running
                        implicitWidth: units.gu(2); implicitHeight: units.gu(2)
                    }
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: page.subStatus === "free" || page.subStatus === "taken" || page.subStatus === "invalid"
                        name: page.subStatus === "free" ? "tick" : "close"
                        width: units.gu(2); height: width
                        color: page.subStatus === "free" ? Style.success : Style.danger
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.subStatus === "checking" ? Lang.tr("Checking availability…")
                            : page.subStatus === "free"     ? Lang.tr("This address is available.")
                            : page.subStatus === "taken"    ? Lang.tr("This address is already taken.")
                            : page.subProblem
                        font.pixelSize: Style.fontSmall
                        font.family: Style.fontFor(text)
                        color: page.subStatus === "free" ? Style.success
                             : page.subStatus === "checking" ? Style.textSecondary
                             : Style.danger
                    }
                }
            }

            // --- Step 1 - Location ---
            Column {
                visible: page.step === 1
                width: parent.width
                spacing: 0

                Label {
                    text: Lang.tr("Choose a country")
                    font.pixelSize: Style.fontLarge
                    font.weight: Font.DemiBold
                    font.family: Style.fontFor(text)
                    color: Style.textTitle
                }
                Item { width: 1; height: Style.spacingXs }
                Label {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: Lang.tr("Pick the country where most of your audience is based. Your platform will be found under it on Serey.")
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                }
                Item { width: 1; height: Style.spacingM }

                // Country row: pressed wash and divider run full-bleed per Lomiri list-item reference
                Item {
                    visible: !page.independent
                    width: parent.width
                    height: units.gu(8)

                    Rectangle {
                        x: -Style.spacingM; width: parent.width + Style.spacingM * 2
                        height: parent.height
                        color: ctryTap.pressed ? Style.pressed : "transparent"
                    }
                    Column {
                        anchors { left: parent.left; right: chevron.left; rightMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
                        spacing: units.dp(2)
                        Label {
                            text: Lang.tr("Country")
                            font.pixelSize: Style.fontRegular
                            font.family: Style.fontFor(text)
                            color: Style.textPrimary
                        }
                        Label {
                            width: parent.width
                            text: page.country ? page.country.name : Lang.tr("Choose a country")
                            wrapMode: Text.WordWrap
                            font.pixelSize: Style.fontSmall
                            font.family: Style.fontFor(text)
                            color: page.country ? Style.brand : Style.textSecondary
                        }
                    }
                    Icon {
                        id: chevron
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        name: "next"
                        width: units.gu(2); height: width
                        color: Style.textSecondary
                    }
                    MouseArea {
                        id: ctryTap
                        anchors.fill: parent
                        onClicked: {
                            page.dismissKeyboard();
                            if (page.countriesFailed) page.loadLists();
                            page.countryPickerOpen = true;
                        }
                    }
                }
                Rectangle {
                    visible: !page.independent
                    x: -Style.spacingM; width: parent.width + Style.spacingM * 2
                    height: units.dp(1); color: Style.divider
                }

                // Independent mode notice (shown only after opting in below).
                Column {
                    visible: page.independent
                    width: parent.width
                    spacing: units.dp(2)
                    Label {
                        text: Lang.tr("Independent")
                        font.pixelSize: Style.fontRegular
                        font.family: Style.fontFor(text)
                        color: Style.textPrimary
                    }
                    Label {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: Lang.tr("A standalone platform, listed under Global.")
                        font.pixelSize: Style.fontSmall
                        font.family: Style.fontFor(text)
                        color: Style.textSecondary
                    }
                }

                // Category (required once a country is picked, like the web wizard).
                Column {
                    visible: !page.independent && page.country !== null && page.categories.length > 0
                    width: parent.width
                    spacing: 0

                    Item { width: 1; height: Style.spacingM }
                    Label {
                        text: Lang.tr("Category")
                        font.pixelSize: Style.fontSmall
                        font.weight: Font.DemiBold
                        font.family: Style.fontFor(text)
                        color: Style.textSecondary
                    }
                    Item { width: 1; height: Style.spacingS }

                    Repeater {
                        model: page.categories
                        Column {
                            width: form.width
                            Item {
                                width: parent.width
                                height: units.gu(6)
                                Rectangle {
                                    x: -Style.spacingM; width: parent.width + Style.spacingM * 2
                                    height: parent.height
                                    color: catTap.pressed ? Style.pressed : "transparent"
                                }
                                Label {
                                    anchors { left: parent.left; right: catTick.left; rightMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
                                    text: modelData.name
                                    elide: Text.ElideRight
                                    font.pixelSize: Style.fontRegular
                                    font.family: Style.fontFor(text)
                                    color: Style.textPrimary
                                }
                                Icon {
                                    id: catTick
                                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                    visible: page.categoryId === modelData.id
                                    name: "tick"
                                    width: units.gu(2.5); height: width
                                    color: Style.success
                                }
                                MouseArea { id: catTap; anchors.fill: parent; onClicked: page.selectCategory(modelData.id) }
                            }
                            Rectangle { x: -Style.spacingM; width: parent.width + Style.spacingM * 2; height: units.dp(1); color: Style.divider }
                        }
                    }
                }

                // Quiet opt-in/out link: independent stays available but isn't the standard path
                Item { width: 1; height: Style.spacingS }
                LinkButton {
                    label: page.independent ? Lang.tr("Choose a country instead")
                                            : Lang.tr("Make it independent instead")
                    onClicked: page.independent = !page.independent
                }
            }

            // --- Step 2 - Branding + create ---
            Column {
                visible: page.step === 2
                width: parent.width
                spacing: Style.spacingM

                Label {
                    text: Lang.tr("Branding")
                    font.pixelSize: Style.fontLarge
                    font.weight: Font.DemiBold
                    font.family: Style.fontFor(text)
                    color: Style.textTitle
                }
                Label {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: Lang.tr("Optional. You can change these later from your platform's dashboard.")
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                }

                Repeater {
                    model: [
                        { key: "icon",   label: Lang.tr("Icon"),        hint: Lang.tr("Square, shown in lists and tabs.") },
                        { key: "logo",   label: Lang.tr("Logo"),        hint: Lang.tr("Shown in your site's header.") },
                        { key: "footer", label: Lang.tr("Footer logo"), hint: Lang.tr("Shown in your site's footer.") }
                    ]
                    Item {
                        width: form.width
                        height: units.gu(9)

                        // Flat square preview with a hairline border (Lomiri image tiles are unrounded)
                        Rectangle {
                            id: preview
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            width: units.gu(6.5); height: width
                            color: Style.iconBackground
                            border.width: units.dp(1)
                            border.color: Style.divider

                            property string slotUrl: modelData.key === "icon" ? page.iconUrl
                                                    : modelData.key === "logo" ? page.logoUrl
                                                    : page.footerUrl
                            Image {
                                anchors.fill: parent
                                anchors.margins: units.dp(1)
                                visible: parent.slotUrl !== ""
                                source: parent.slotUrl
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: 256
                                sourceSize.height: 256
                                clip: true
                            }
                            Icon {
                                anchors.centerIn: parent
                                visible: parent.slotUrl === "" && page.uploadingTarget !== modelData.key
                                name: "insert-image"
                                width: units.gu(3); height: width
                                color: Style.textSecondary
                            }
                            ActivityIndicator {
                                anchors.centerIn: parent
                                running: page.uploadingTarget === modelData.key
                                visible: running
                            }
                        }
                        Column {
                            anchors { left: preview.right; leftMargin: Style.spacingM; right: chooseBtn.left; rightMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
                            spacing: units.dp(2)
                            Label {
                                text: modelData.label
                                font.pixelSize: Style.fontRegular
                                font.family: Style.fontFor(text)
                                color: Style.textPrimary
                            }
                            Label {
                                width: parent.width
                                text: modelData.hint
                                wrapMode: Text.WordWrap
                                font.pixelSize: Style.fontSmall
                                font.family: Style.fontFor(text)
                                color: Style.textSecondary
                            }
                        }
                        AbstractButton {
                            id: chooseBtn
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            width: units.gu(9); height: units.gu(4)
                            enabled: page.uploadingTarget === ""
                            onClicked: page.pickImage(modelData.key)
                            Rectangle {
                                anchors.fill: parent
                                radius: Style.cardRadius
                                color: chooseBtn.pressed ? Style.pressed : Style.iconBackground
                                Label {
                                    anchors.centerIn: parent
                                    text: Lang.tr("Choose")
                                    font.pixelSize: Style.fontSmall
                                    font.weight: Font.DemiBold
                                    font.family: Style.fontFor(text)
                                    color: Style.textPrimary
                                }
                            }
                        }
                    }
                }

                Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

                // Summary before the irreversible step.
                Column {
                    width: parent.width
                    spacing: units.dp(4)
                    Label {
                        width: parent.width
                        elide: Text.ElideRight
                        text: page.nameText
                        font.pixelSize: Style.fontMedium
                        font.weight: Font.DemiBold
                        font.family: Style.fontFor(text)
                        color: Style.textTitle
                    }
                    Label {
                        width: parent.width
                        elide: Text.ElideRight
                        text: "https://" + subField.text + ".serey.io"
                        font.pixelSize: Style.fontSmall
                        font.family: Style.fontFamily
                        color: Style.textSecondary
                    }
                    Label {
                        width: parent.width
                        text: page.independent ? Lang.tr("Independent")
                                               : (page.country ? page.country.name : "")
                        font.pixelSize: Style.fontSmall
                        font.family: Style.fontFor(text)
                        color: Style.textSecondary
                    }
                }
            }

            // --- Step 3 - Success ---
            Column {
                visible: page.step === 3
                width: parent.width
                spacing: Style.spacingM

                Item { width: 1; height: Style.spacingL }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: units.gu(9); height: width; radius: width / 2
                    color: Qt.rgba(0, 0.51, 0.98, 0.10)
                    Icon {
                        anchors.centerIn: parent
                        name: "tick"
                        width: units.gu(5); height: width
                        color: Style.brand
                    }
                }
                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Lang.tr("Your platform is live!")
                    font.pixelSize: Style.fontTitle
                    font.weight: Font.DemiBold
                    font.family: Style.fontFor(text)
                    color: Style.textTitle
                }
                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                    text: "https://" + page.createdDns
                    font.pixelSize: Style.fontRegular
                    font.family: Style.fontFamily
                    color: Style.textSecondary
                }
                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: Lang.tr("Manage your site, menus and landing page from your platform's dashboard.")
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                }
                Item { width: 1; height: Style.spacingS }
                // CMS hub manages the platform natively; ownedCommunityIdSet already refreshed
                PrimaryButton {
                    text: Lang.tr("Manage my platform")
                    onClicked: {
                        page.pageStack.pop();
                        page.pageStack.push(Qt.resolvedUrl("PlatformAdminPage.qml"));
                    }
                }
                // Live site is its own subdomain; Homepage tab is a fixed site, so needs a browser
                LinkButton {
                    label: Lang.tr("View live site")
                    onClicked: Qt.openUrlExternally("https://" + page.createdDns)
                }
                LinkButton {
                    label: Lang.tr("Done")
                    onClicked: page.pageStack.pop()
                }
            }

            // --- Wizard navigation ---
            Column {
                visible: page.step < 3
                width: parent.width
                spacing: Style.spacingS

                Item { width: 1; height: Style.spacingS }
                PrimaryButton {
                    enabled: page.canContinue
                    busy: page.creating
                    text: page.step === 2
                          ? (page.creating ? Lang.tr("Creating…") : Lang.tr("Create platform"))
                          : Lang.tr("Continue")
                    onClicked: page.next()
                }
                LinkButton {
                    visible: page.step > 0
                    label: Lang.tr("Back")
                    onClicked: { if (!page.creating) page.step-- }
                }
            }
        }
    }

    // --- Country picker (overlay sheet) ---
    Rectangle {
        visible: page.countryPickerOpen
        anchors { top: page.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        color: Style.surface
        z: 10

        // Swallow clicks under the sheet.
        MouseArea { anchors.fill: parent }

        // Lomiri header-search pattern: back chevron + rounded search field in one header row
        Item {
            id: pickerHeader
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: units.gu(7)

            AbstractButton {
                id: pickerBack
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: units.gu(6)
                onClicked: page.countryPickerOpen = false
                Icon {
                    anchors.centerIn: parent
                    name: "back"
                    width: units.gu(2.5); height: width
                    color: Style.textPrimary
                }
            }
            Rectangle {
                anchors {
                    left: pickerBack.right
                    right: parent.right; rightMargin: Style.spacingM
                    verticalCenter: parent.verticalCenter
                }
                height: units.gu(4.5)
                radius: Style.cardRadius
                color: "transparent"
                border.width: units.dp(1)
                border.color: countrySearchField.activeFocus ? Style.brand : Style.divider

                TextInput {
                    id: countrySearchField
                    anchors {
                        left: parent.left; leftMargin: Style.spacingM
                        right: parent.right; rightMargin: Style.spacingM
                        verticalCenter: parent.verticalCenter
                    }
                    font.family: Style.fontFamily
                    font.pixelSize: Style.fontRegular
                    color: Style.textPrimary
                    inputMethodHints: Qt.ImhNoPredictiveText
                }
                Label {
                    anchors { left: countrySearchField.left; verticalCenter: parent.verticalCenter }
                    visible: countrySearchField.text.length === 0 && !countrySearchField.inputMethodComposing
                    text: Lang.tr("Search countries")
                    color: Style.textSecondary
                    font.pixelSize: Style.fontRegular
                    font.family: Style.fontFor(text)
                }
            }
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: units.dp(1)
                color: Style.divider
            }
        }

        ActivityIndicator {
            anchors.centerIn: parent
            running: page.countryPickerOpen && page.countriesLoading
            visible: running
        }
        Column {
            visible: page.countryPickerOpen && page.countriesFailed
            anchors.centerIn: parent
            width: Math.min(parent.width - Style.spacingL * 2, units.gu(45))
            spacing: Style.spacingM
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: Lang.tr("Couldn't load countries.")
                font.pixelSize: Style.fontRegular
                font.family: Style.fontFor(text)
                color: Style.textSecondary
            }
            SecondaryButton {
                text: Lang.tr("Retry")
                onClicked: page.loadLists()
            }
        }

        ListView {
            anchors { top: pickerHeader.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
            // Keep the last rows reachable while the search keyboard is up.
            bottomMargin: Qt.inputMethod.visible ? Qt.inputMethod.keyboardRectangle.height : 0
            clip: true
            model: {
                var q = countrySearchField.text.toLowerCase();
                if (q.length === 0) return page.countries;
                var out = [];
                for (var i = 0; i < page.countries.length; i++)
                    if (page.countries[i].name.toLowerCase().indexOf(q) >= 0)
                        out.push(page.countries[i]);
                return out;
            }
            delegate: Item {
                width: ListView.view.width
                height: units.gu(6)

                Rectangle {
                    anchors.fill: parent
                    color: rowTap.pressed ? Style.pressed : "transparent"
                }
                Image {
                    id: flag
                    anchors { left: parent.left; leftMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                    width: units.gu(3); height: units.gu(3)
                    visible: modelData.iconUrl !== ""
                    source: modelData.iconUrl
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: 64
                    sourceSize.height: 64
                }
                Label {
                    anchors {
                        left: parent.left
                        leftMargin: Style.spacingM + units.gu(4)
                        right: rowTick.left; rightMargin: Style.spacingS
                        verticalCenter: parent.verticalCenter
                    }
                    text: modelData.name
                    elide: Text.ElideRight
                    font.pixelSize: Style.fontRegular
                    font.family: Style.fontFor(text)
                    color: Style.textPrimary
                }
                Icon {
                    id: rowTick
                    anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                    visible: page.country !== null && page.country.id === modelData.id
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
                    id: rowTap
                    anchors.fill: parent
                    onClicked: page.selectCountry(modelData)
                }
            }
        }
    }
}
