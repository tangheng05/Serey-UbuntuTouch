import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/CategoryService.js" as CategoryService
import "../services/CommunityService.js" as CommunityService

/*
 * "Edit Platform Information" — matches the web CMS modal: platform name,
 * parent country (+ "Move to Superhub"), category, and a Google SEO
 * description with a 160-char counter.
 *
 * NOT YET WIRED to a save endpoint — the community_route.js endpoint for
 * updating name/parent/category/SEO description hasn't been documented yet
 * (distinct from POST /community/update-logo, which only manages images, and
 * from landing_page_v2's per-section content). Fields are prefilled only from
 * data we actually have (the cached community name); parent/category/SEO are
 * left blank until their real data source is confirmed. Save currently shows
 * a "not available yet" toast instead of silently no-oping or guessing an
 * endpoint that could corrupt real data.
 */
Page {
    id: page

    property string platformNameValue: Config.communityInfoFor(Config.managedCommunityId)
        ? Config.communityInfoFor(Config.managedCommunityId).title : Config.currentCommunityName
    // Prefilled from the community's own `country` field (the cached
    // get-communities tree) — this is the community's actual parent, e.g.
    // "Cambodia" for Cambodia Book Club.
    property string parentCountryName: Config.communityInfoFor(Config.managedCommunityId)
        ? Config.communityInfoFor(Config.managedCommunityId).country : ""
    property string categoryName: ""
    property var categoryOptions: []
    // Full top-level country list for the picker. NOT Config.sources — that
    // list is curated for the app's region picker and deliberately excludes
    // Cambodia (see Main.qml), which would make a community's real parent
    // unselectable here.
    property var countryOptions: []

    function loadCategories() {
        CategoryService.listMarketplaceCategories(Config.baseUrl, Session.token,
            function (names) { page.categoryOptions = names },
            function () { /* non-fatal: picker just stays empty */ })
    }

    function loadCountries() {
        CommunityService.listAll(Config.baseUrl,
            function (list) {
                page.countryOptions = list
                    .map(function (c) { return c.title })
                    .filter(function (t) { return !!t })
            },
            function () { /* non-fatal: picker just stays empty */ })
    }

    Component.onCompleted: { page.loadCategories(); page.loadCountries() }

    header: Item { height: 0 }

    Rectangle {
        id: modalHeader
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: units.gu(9)
        color: Style.surface

        Column {
            anchors { left: parent.left; right: closeBtn.left; leftMargin: Style.spacingM; rightMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
            spacing: units.dp(2)
            Label {
                text: Lang.tr("Edit Platform Information")
                font.pixelSize: Style.fontLarge
                font.weight: Font.DemiBold
                font.family: Style.fontFor(text)
                color: Style.textPrimary
            }
            Label {
                text: Lang.tr("Update your platform name, country, category and SEO")
                width: parent.width
                wrapMode: Text.WordWrap
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFor(text)
                color: Style.textSecondary
            }
        }
        AbstractButton {
            id: closeBtn
            anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
            width: units.gu(4); height: units.gu(4)
            onClicked: page.pageStack.pop()
            Icon { anchors.centerIn: parent; width: units.gu(2.2); height: width; name: "close"; color: Style.textSecondary }
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: units.dp(1)
            color: Style.divider
        }
    }

    KeyboardAwareFlickable {
        anchors { top: modalHeader.bottom; left: parent.left; right: parent.right; bottom: footer.top }
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

            AbstractButton {
                width: parent.width
                height: units.gu(4)
                onClicked: Toast.show(Lang.tr("Not available yet."))
                Label {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: "› " + Lang.tr("Move to Superhub")
                    font.pixelSize: Style.fontSmall
                    font.weight: Font.DemiBold
                    font.family: Style.fontFor(text)
                    color: parent.pressed ? Style.brandDark : Style.brand
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
                text: Lang.tr("Save Changes")
                // Not wired yet — see file header comment.
                onClicked: Toast.show(Lang.tr("Saving platform info isn't available yet."))
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
                    text: modelData
                    color: page.parentCountryName === modelData ? Style.brand : Style.iconBackground
                    onClicked: {
                        page.parentCountryName = modelData
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
                    text: modelData
                    color: page.categoryName === modelData ? Style.brand : Style.iconBackground
                    onClicked: {
                        page.categoryName = modelData
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
