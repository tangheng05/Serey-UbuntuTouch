import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/PlatformService.js" as PlatformService
import "../services/CategoryService.js" as CategoryService

// Blog posting permission + category management for the managed community
Page {
    id: page

    // Adapt, not scale: caps to a centered column on wide windows
    readonly property real maxContentWidth: units.gu(60)

    header: PageHeader {
        title: Lang.tr("Blog Posts")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.pageStack.pop() }
        ]
    }

    // ── Posting permission (only_me | everyone | custom) ──────────────────
    property string blogMode: "only_me"
    property bool permBusy: false

    function modeLabel(mode) {
        return mode === "everyone" ? Lang.tr("Everyone")
             : mode === "custom"   ? Lang.tr("Custom")
             : Lang.tr("Only me");
    }
    readonly property var permOptions: [
        { mode: "only_me",  label: Lang.tr("Only me"),  desc: Lang.tr("Only you and your managers can post.") },
        { mode: "everyone", label: Lang.tr("Everyone"), desc: Lang.tr("Anyone can post articles.") },
        { mode: "custom",   label: Lang.tr("Custom"),   desc: Lang.tr("Only members you pick can post. Manage members in the web dashboard.") }
    ]

    // is_allow_post=true → everyone; false + poster members → custom; false alone → only me (web-dashboard parity).
    function loadPostingPermission() {
        var info = Config.communityInfoFor(Config.managedCommunityId)
        PlatformService.hasPosterMembers(Config.baseUrl, Config.managedCommunityId,
            function (has) { page.blogMode = (info && info.allowPost) ? "everyone" : (has ? "custom" : "only_me") },
            function () { page.blogMode = (info && info.allowPost) ? "everyone" : "only_me" })
    }

    // Radio modes only change on server success — a failed call just leaves the previous selection lit.
    function setBlogMode(mode) {
        if (permBusy || mode === blogMode) return
        permBusy = true
        var allow = (mode === "everyone")   // custom and only_me both store false
        PlatformService.updateAllowPost(Config.baseUrl, Session.token, Config.managedCommunityId, allow,
            function () {
                page.permBusy = false
                page.blogMode = mode
                if (mode === "custom")
                    Toast.show(Lang.tr("Add poster members from the web dashboard."))
                else
                    Toast.success(Lang.tr("Posting permission updated."))
            },
            function (err) {
                page.permBusy = false
                Toast.error((err && err.message) || Lang.tr("Action failed."))
            })
    }

    // ── Category management ────────────────────────────────────────────────
    ListModel { id: categoryModel; dynamicRoles: true }
    property bool categoriesLoading: false
    property bool categorySaving: false

    function loadCategories() {
        page.categoriesLoading = true
        var info = Config.communityInfoFor(Config.managedCommunityId)
        CategoryService.listByCommunity(Config.baseUrl, info ? info.title : "", Session.token,
            function (names, raw) {
                page.categoriesLoading = false
                categoryModel.clear()
                for (var i = 0; i < raw.length; i++)
                    categoryModel.append({ id: raw[i].id, name: raw[i].name || "" })
            },
            function (err) {
                page.categoriesLoading = false
                Toast.error((err && err.message) || Lang.tr("Failed to load categories."))
            })
    }

    function addCategory(name) {
        var trimmed = (name || "").trim()
        if (trimmed.length === 0 || page.categorySaving) return
        page.categorySaving = true
        CategoryService.createOrUpdate(Config.baseUrl, Session.token,
            { communityId: Config.managedCommunityId, name: trimmed },
            function () {
                page.categorySaving = false
                page.loadCategories()
                Toast.success(Lang.tr("Category added."))
            },
            function (err) {
                page.categorySaving = false
                Toast.error((err && err.message) || Lang.tr("Failed to add category."))
            })
    }

    function deleteCategory(index) {
        var item = categoryModel.get(index)
        CategoryService.remove(Config.baseUrl, Session.token, item.id,
            function () {
                categoryModel.remove(index)
                Toast.show(Lang.tr("Category deleted."))
            },
            function (err) { Toast.error((err && err.message) || Lang.tr("Failed to delete category.")) })
    }

    Component.onCompleted: {
        page.loadPostingPermission()
        page.loadCategories()
    }

    Component {
        id: permPickerPage
        Page {
            id: permPage
            header: PageHeader {
                title: Lang.tr("Article posting")
                leadingActionBar.actions: [
                    Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.pageStack.pop() }
                ]
            }

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
                        Rectangle {
                            id: permOptRadio
                            anchors { left: parent.left; leftMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                            width: units.gu(2.5); height: width; radius: width / 2
                            color: page.blogMode === modelData.mode ? Style.success : "transparent"
                            border.width: page.blogMode === modelData.mode ? 0 : units.dp(1.5)
                            border.color: Style.dotInactive
                            Rectangle {
                                anchors.centerIn: parent
                                visible: page.blogMode === modelData.mode
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
                            onClicked: page.setBlogMode(modelData.mode)
                        }
                    }
                }
            }
        }
    }

    Flickable {
        id: list
        anchors { top: page.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentWidth: width
        contentHeight: contentCol.height
        clip: true

        Column {
            id: contentCol
            width: Math.min(list.width, page.maxContentWidth)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 0

            SettingsSectionHeader { text: Lang.tr("Posting") }
            Item {
                width: parent.width
                height: units.gu(6.5)

                Rectangle {
                    anchors.fill: parent
                    color: postingRowTap.pressed ? Style.pressed : "transparent"
                }
                Label {
                    anchors { left: parent.left; leftMargin: Style.spacingM; right: postingValue.left; rightMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
                    text: Lang.tr("Article posting")
                    elide: Text.ElideRight
                    font.pixelSize: Style.fontRegular
                    font.family: Style.fontFor(text)
                    color: Style.textPrimary
                }
                Row {
                    id: postingValue
                    anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                    spacing: Style.spacingS
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.modeLabel(page.blogMode)
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
                    anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: units.gu(2) }
                    height: units.dp(1); color: Style.divider
                }
                MouseArea {
                    id: postingRowTap
                    anchors.fill: parent
                    onClicked: page.pageStack.push(permPickerPage)
                }
            }

            Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }

            SettingsSectionHeader { text: Lang.tr("Categories") }

            // Add-category row
            Item {
                width: parent.width
                height: units.gu(6.5)

                TextField {
                    id: newCategoryField
                    anchors { left: parent.left; leftMargin: Style.spacingM; right: addCategoryBtn.left; rightMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
                    placeholderText: Lang.tr("New category name")
                    enabled: !page.categorySaving
                    onAccepted: { page.addCategory(text); text = "" }
                }
                AbstractButton {
                    id: addCategoryBtn
                    anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                    width: units.gu(4); height: units.gu(4)
                    enabled: !page.categorySaving && newCategoryField.text.trim().length > 0
                    onClicked: { page.addCategory(newCategoryField.text); newCategoryField.text = "" }
                    Icon { anchors.centerIn: parent; width: units.gu(2.4); height: width; name: "add"; color: enabled ? Style.brand : Style.textSecondary }
                }
            }

            ActivityIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: page.categoriesLoading
                visible: running
            }

            Repeater {
                model: categoryModel
                delegate: Item {
                    width: contentCol.width
                    height: units.gu(6)

                    Label {
                        anchors { left: parent.left; leftMargin: Style.spacingM; right: deleteCatBtn.left; rightMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
                        text: model.name || ""
                        elide: Text.ElideRight
                        font.pixelSize: Style.fontRegular
                        font.family: Style.fontFor(text)
                        color: Style.textPrimary
                    }
                    AbstractButton {
                        id: deleteCatBtn
                        anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                        width: units.gu(3.5); height: units.gu(3.5)
                        onClicked: page.deleteCategory(index)
                        Icon { anchors.centerIn: parent; width: units.gu(2); height: width; name: "delete"; color: Style.danger }
                    }
                    Rectangle {
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: units.gu(2) }
                        height: units.dp(1)
                        color: Style.divider
                    }
                }
            }

            Label {
                visible: !page.categoriesLoading && categoryModel.count === 0
                anchors.horizontalCenter: parent.horizontalCenter
                text: Lang.tr("No categories yet")
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFor(text)
                color: Style.textSecondary
            }

            Item { width: 1; height: Style.spacingL }
        }
    }
}
