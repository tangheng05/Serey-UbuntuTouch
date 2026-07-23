import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/PlatformService.js" as PlatformService

// "Edit Platform Information": platform name, parent country, category and SEO description (update-community-* endpoints)
Page {
    id: page

    // Filled from a fresh get-communities walk in loadContext; the startup cache
    // can be stale right after creating a platform (used to render "Global").
    property string platformNameValue: Config.communityInfoFor(Config.managedCommunityId)
        ? Config.communityInfoFor(Config.managedCommunityId).title : ""
    // Parent is structural in the get-communities tree (no `country` field on
    // the node); resolved by loadContext's tree walk.
    property string parentCountryName: ""
    property string parentCountryId: ""
    property string categoryName: ""
    property int categoryId: 0
    property var categoryOptions: []   // [{ id, name }], community_category taxonomy
    property var countryOptions: []    // [{ id, name }], id is the UUID update-community-country needs
    property bool saving: false

    // Initial values captured on load; Save only sends what actually changed.
    property string _initialName: ""
    property string _initialCountryId: ""
    property int _initialCategoryId: 0
    property string _initialSeo: ""

    // categoryId (from the community) and categoryOptions (from the taxonomy)
    // arrive from two async calls in either order; sync whenever both are in.
    function _syncCategoryName() {
        for (var i = 0; i < page.categoryOptions.length; i++) {
            if (page.categoryOptions[i].id === page.categoryId) {
                page.categoryName = page.categoryOptions[i].name
                return
            }
        }
    }

    // The tree may only give the parent's TITLE; resolve its serey-countries
    // UUID by name match once the country list is in (either call order).
    function _syncCountryId() {
        if (page.parentCountryId.length > 0 || page.parentCountryName.length === 0) return
        for (var i = 0; i < page.countryOptions.length; i++) {
            if (page.countryOptions[i].name.toLowerCase() === page.parentCountryName.toLowerCase()) {
                page.parentCountryId = page.countryOptions[i].id
                page._initialCountryId = page.countryOptions[i].id
                return
            }
        }
    }

    function loadCategories() {
        PlatformService.getCategories(Config.baseUrl,
            function (rows) {
                page.categoryOptions = rows
                page._syncCategoryName()
            },
            function () { /* non-fatal: picker just stays empty */ })
    }

    // Prefer Config's cache (kept fresh by updateCommunityFields) over ctx here;
    // get-communities is cached server-side and can be stale right after a save.
    function loadContext() {
        PlatformService.getCommunityContext(Config.baseUrl, Config.managedCommunityId,
            function (ctx) {
                var cached = Config.communityInfoFor(Config.managedCommunityId)
                page.parentCountryName = (cached && cached.parentCountryName !== undefined) ? cached.parentCountryName : ctx.parentCountry
                page.parentCountryId = (cached && cached.countryId !== undefined) ? cached.countryId : ctx.countryId
                page.categoryId = (cached && cached.categoryId !== undefined) ? cached.categoryId : ctx.categoryId
                seoField.text = (cached && cached.metaDescription !== undefined) ? cached.metaDescription : ctx.metaDescription
                page._initialName = page.platformNameValue
                page._initialCountryId = page.parentCountryId
                page._initialCategoryId = page.categoryId
                page._initialSeo = seoField.text
                page._syncCategoryName()
                page._syncCountryId()
            },
            function () { /* non-fatal: pickers just stay unset */ })
    }

    function loadCountries() {
        // Country table rows with uuid ids, the country_id update-community-country
        // needs (serey-countries only returns { icon_url, country_name }, no id).
        PlatformService.getCountries(Config.baseUrl,
            function (list) {
                page.countryOptions = list
                page._syncCountryId()
            },
            function () { /* non-fatal: picker just stays empty */ })
    }

    Component.onCompleted: { page.loadCategories(); page.loadCountries(); page.loadContext() }

    // Fires one update per changed field in parallel; reports once all land.
    function save() {
        if (page.saving) return
        var id = Config.managedCommunityId
        var name = nameField.text.trim()
        var seo = seoField.text.trim()
        var pending = 0
        var failed = []
        function done(label, err) {
            if (err) failed.push(label)
            pending--
            if (pending > 0) return
            page.saving = false
            if (failed.length === 0) {
                var fields = {}
                if (name.length > 0 && name !== page._initialName) fields.title = name
                if (page.parentCountryId.length > 0 && page.parentCountryId !== page._initialCountryId) {
                    fields.countryId = page.parentCountryId
                    fields.parentCountryName = page.parentCountryName
                }
                if (page.categoryId > 0 && page.categoryId !== page._initialCategoryId) {
                    fields.categoryId = page.categoryId
                    fields.categoryName = page.categoryName
                }
                if (seo !== page._initialSeo) fields.metaDescription = seo
                if (Object.keys(fields).length > 0) Config.updateCommunityFields(id, fields)
                Toast.success(Lang.tr("Platform info updated."))
                page.pageStack.pop()
            } else {
                Toast.error(Lang.tr("Failed to update: %1").arg(failed.join(", ")))
            }
        }
        var calls = []
        if (name.length > 0 && name !== page._initialName)
            calls.push(function () { PlatformService.updateCommunityName(Config.baseUrl, Session.token, id, name,
                function () { done() }, function (e) { done(Lang.tr("name"), e) }) })
        if (page.parentCountryId.length > 0 && page.parentCountryId !== page._initialCountryId)
            calls.push(function () { PlatformService.updateCommunityCountry(Config.baseUrl, Session.token, id, page.parentCountryId,
                function () { done() }, function (e) { done(Lang.tr("country"), e) }) })
        if (page.categoryId > 0 && page.categoryId !== page._initialCategoryId)
            calls.push(function () { PlatformService.updateCommunityCategory(Config.baseUrl, Session.token, id, page.categoryId,
                function () { done() }, function (e) { done(Lang.tr("category"), e) }) })
        if (seo !== page._initialSeo)
            calls.push(function () { PlatformService.updateCommunityMetaDescription(Config.baseUrl, Session.token, id, seo,
                function () { done() }, function (e) { done(Lang.tr("SEO description"), e) }) })
        if (calls.length === 0) {
            Toast.show(Lang.tr("No changes to save."))
            return
        }
        page.saving = true
        pending = calls.length
        for (var i = 0; i < calls.length; i++) calls[i]()
    }

    header: PageHeader {
        title: Lang.tr("Edit Platform Information")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.pageStack.pop() }
        ]
    }

    KeyboardAwareFlickable {
        anchors { top: page.header.bottom; left: parent.left; right: parent.right; bottom: footer.top }
        contentWidth: width
        contentHeight: form.height + Style.spacingL * 2
        clip: true

        Column {
            id: form
            width: Math.min(parent.width - Style.spacingL * 2, units.gu(50))
            anchors.horizontalCenter: parent.horizontalCenter
            y: Style.spacingL
            spacing: Style.spacingM

            Label {
                text: Lang.tr("Platform Name:")
                font.pixelSize: Style.fontSmall; font.weight: Font.DemiBold
                font.family: Style.fontFor(text); color: Style.textPrimary
            }
            FormField { id: nameField; width: parent.width; text: page.platformNameValue; placeholder: Lang.tr("Platform name") }

            Label {
                text: Lang.tr("Parent Country:")
                font.pixelSize: Style.fontSmall; font.weight: Font.DemiBold
                font.family: Style.fontFor(text); color: Style.textPrimary
            }
            AbstractButton {
                width: parent.width
                height: units.gu(6)
                onClicked: PopupUtils.open(parentCountryDialog)
                Rectangle {
                    anchors.fill: parent
                    radius: Style.cardRadius
                    color: Style.iconBackground
                    border.width: units.dp(1); border.color: Style.divider
                    Label {
                        anchors { left: parent.left; right: chevron.left; leftMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                        text: page.parentCountryName.length > 0 ? page.parentCountryName : Lang.tr("Select parent country")
                        elide: Text.ElideRight
                        font.pixelSize: Style.fontRegular
                        font.family: Style.fontFor(text)
                        color: page.parentCountryName.length > 0 ? Style.textPrimary : Style.textSecondary
                    }
                    Icon {
                        id: chevron
                        anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                        width: units.gu(1.6); height: width
                        name: "down"; color: Style.textSecondary
                    }
                }
            }

            Label {
                text: Lang.tr("Category:")
                font.pixelSize: Style.fontSmall; font.weight: Font.DemiBold
                font.family: Style.fontFor(text); color: Style.textPrimary
            }
            AbstractButton {
                width: parent.width
                height: units.gu(6)
                onClicked: page.categoryOptions.length > 0
                    ? PopupUtils.open(categoryDialog)
                    : Toast.show(Lang.tr("Category list not available yet."))
                Rectangle {
                    anchors.fill: parent
                    radius: Style.cardRadius
                    color: Style.iconBackground
                    border.width: units.dp(1); border.color: Style.divider
                    Label {
                        anchors { left: parent.left; right: catChevron.left; leftMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                        text: page.categoryName.length > 0 ? page.categoryName : Lang.tr("Select category")
                        elide: Text.ElideRight
                        font.pixelSize: Style.fontRegular
                        font.family: Style.fontFor(text)
                        color: page.categoryName.length > 0 ? Style.textPrimary : Style.textSecondary
                    }
                    Icon {
                        id: catChevron
                        anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                        width: units.gu(1.6); height: width
                        name: "down"; color: Style.textSecondary
                    }
                }
            }

            Item {
                width: parent.width
                height: seoTitle.implicitHeight
                Label {
                    id: seoTitle
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: Lang.tr("Google SEO Description")
                    font.pixelSize: Style.fontSmall; font.weight: Font.DemiBold
                    font.family: Style.fontFor(text); color: Style.textPrimary
                }
                Label {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: seoField.length + " / 160"
                    font.pixelSize: Style.fontXSmall
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                }
            }
            MultilineField {
                id: seoField
                width: parent.width
                maximumLength: 160
                placeholder: Lang.tr("Describe your platform for Google search results (120-160 characters recommended)")
            }

            Item { width: 1; height: Style.spacingXs }
        }
    }

    Rectangle {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: units.gu(9)
        color: Style.surface
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: units.dp(1)
            color: Style.divider
        }

        Row {
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: Style.spacingM }
            spacing: Style.spacingM
            SecondaryButton {
                width: (parent.width - Style.spacingM) / 2
                text: Lang.tr("Cancel")
                onClicked: page.pageStack.pop()
            }
            PrimaryButton {
                width: (parent.width - Style.spacingM) / 2
                text: page.saving ? Lang.tr("Saving…") : Lang.tr("Save Changes")
                busy: page.saving
                onClicked: page.save()
            }
        }
    }

    Component {
        id: parentCountryDialog
        Dialog {
            id: dlg
            title: Lang.tr("Parent Country")
            Repeater {
                model: page.countryOptions
                delegate: Button {
                    width: parent.width
                    text: modelData.name
                    color: page.parentCountryId === modelData.id ? Style.brand : Style.iconBackground
                    onClicked: {
                        page.parentCountryId = modelData.id
                        page.parentCountryName = modelData.name
                        PopupUtils.close(dlg)
                    }
                }
            }
            Button {
                text: Lang.tr("Cancel")
                onClicked: PopupUtils.close(dlg)
            }
        }
    }

    Component {
        id: categoryDialog
        Dialog {
            id: catDlg
            title: Lang.tr("Category")
            Repeater {
                model: page.categoryOptions
                delegate: Button {
                    width: parent.width
                    text: modelData.name
                    color: page.categoryId === modelData.id ? Style.brand : Style.iconBackground
                    onClicked: {
                        page.categoryId = modelData.id
                        page.categoryName = modelData.name
                        PopupUtils.close(catDlg)
                    }
                }
            }
            Button {
                text: Lang.tr("Cancel")
                onClicked: PopupUtils.close(catDlg)
            }
        }
    }
}
