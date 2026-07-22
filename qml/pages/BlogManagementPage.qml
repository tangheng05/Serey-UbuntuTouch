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

    // maps allowPost/poster members to blog mode
    function loadPostingPermission() {
        var info = Config.communityInfoFor(Config.managedCommunityId)
        PlatformService.hasPosterMembers(Config.baseUrl, Config.managedCommunityId,
            function (has) { page.blogMode = (info && info.allowPost) ? "everyone" : (has ? "custom" : "only_me") },
            function () { page.blogMode = (info && info.allowPost) ? "everyone" : "only_me" })
    }

    // only update selection on server success
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
    // sub-categories kept as JSON string per row (subsJson)
    ListModel { id: categoryModel; dynamicRoles: true }
    property bool categoriesLoading: false
    property bool categorySaving: false
    // guards against duplicate in-flight requests per id
    property var _busyIds: ({})

    function _findIndexById(id) {
        for (var i = 0; i < categoryModel.count; i++)
            if (categoryModel.get(i).id === id) return i
        return -1
    }

    function loadCategories() {
        var info = Config.communityInfoFor(Config.managedCommunityId)
        var title = info ? info.title
                         : (Config.managedCommunityId === Config.communityId ? Config.currentCommunityName : "")
        // don't fall back to global category list
        if (!title || title.length === 0) {
            page.categoriesLoading = false
            categoryModel.clear()
            return
        }
        page.categoriesLoading = true
        CategoryService.listByCommunity(Config.baseUrl, title, Config.managedCommunityId, Session.token,
            function (names, raw) {
                page.categoriesLoading = false
                categoryModel.clear()
                for (var i = 0; i < raw.length; i++) {
                    var subs = raw[i].sub_categories || raw[i].sub || []
                    if (!Array.isArray(subs)) subs = []
                    // normalize subs to {name, position}
                    var norm = []
                    for (var j = 0; j < subs.length; j++) {
                        var nm = (subs[j] && (typeof subs[j] === "string" ? subs[j] : subs[j].name) || "").trim()
                        if (nm.length > 0) norm.push({ name: nm, position: norm.length + 1 })
                    }
                    categoryModel.append({
                        id: raw[i].id,
                        name: raw[i].name || "",
                        iconUrl: raw[i].icon_url || "",
                        color: raw[i].color || "",
                        subsJson: JSON.stringify(norm),
                        expanded: false
                    })
                }
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
        if (!item) return
        var id = item.id
        if (page._busyIds[id]) return          // guard rapid double-taps
        page._busyIds[id] = true
        // optimistic remove
        categoryModel.remove(index)
        CategoryService.remove(Config.baseUrl, Session.token, id,
            function () {
                delete page._busyIds[id]
                Toast.show(Lang.tr("Category deleted."))
            },
            function (err) {
                delete page._busyIds[id]
                // 404 means already deleted, treat as success
                if (err && err.status === 404) { Toast.show(Lang.tr("Category deleted.")); return }
                Toast.error((err && err.message) || Lang.tr("Failed to delete category."))
                page.loadCategories()          // restore the optimistically-removed row
            })
    }

    // saves category with new sub-category list
    function _saveSubs(index, subs, okMsg) {
        var item = categoryModel.get(index)
        if (!item) return
        var id = item.id
        if (page._busyIds[id]) return
        page._busyIds[id] = true
        categoryModel.setProperty(index, "subsJson", JSON.stringify(subs))   // optimistic
        CategoryService.createOrUpdate(Config.baseUrl, Session.token,
            { id: id, communityId: Config.managedCommunityId, name: item.name,
              iconUrl: item.iconUrl, color: item.color, subs: subs },
            function () {
                delete page._busyIds[id]
                if (okMsg) Toast.success(okMsg)
            },
            function (err) {
                delete page._busyIds[id]
                Toast.error((err && err.message) || Lang.tr("Action failed."))
                page.loadCategories()          // restore true state on failure
            })
    }

    function addSubCategory(index, name) {
        var trimmed = (name || "").trim()
        if (trimmed.length === 0) return
        var item = categoryModel.get(index)
        if (!item) return
        var subs = JSON.parse(item.subsJson || "[]")
        for (var i = 0; i < subs.length; i++)
            if ((subs[i].name || "").toLowerCase() === trimmed.toLowerCase()) {
                Toast.show(Lang.tr("That sub-category already exists.")); return
            }
        subs.push({ name: trimmed, position: subs.length + 1 })
        page._saveSubs(index, subs, Lang.tr("Sub-category added."))
    }

    function deleteSubCategory(index, subIndex) {
        var item = categoryModel.get(index)
        if (!item) return
        var subs = JSON.parse(item.subsJson || "[]")
        if (subIndex < 0 || subIndex >= subs.length) return
        subs.splice(subIndex, 1)
        for (var i = 0; i < subs.length; i++) subs[i].position = i + 1
        page._saveSubs(index, subs, Lang.tr("Sub-category removed."))
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

    // on-screen keyboard height
    readonly property real kbHeight: Qt.inputMethod.visible ? Qt.inputMethod.keyboardRectangle.height : 0
    property var _focusTarget: null

    // scroll item clear of keyboard
    function ensureVisible(item) {
        if (!item) return
        var top = item.mapToItem(list.contentItem, 0, 0).y
        var bottom = top + item.height + Style.spacingM
        var maxY = Math.max(0, list.contentHeight - list.height)
        if (bottom > list.contentY + list.height)
            list.contentY = Math.min(bottom - list.height, maxY)
        else if (top < list.contentY)
            list.contentY = Math.max(0, top)
    }
    // fires after keyboard animation settles
    Timer {
        id: scrollTimer
        interval: 350
        onTriggered: if (page._focusTarget && page._focusTarget.activeFocus) page.ensureVisible(page._focusTarget)
    }

    Flickable {
        id: list
        anchors { top: page.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: page.kbHeight }
        contentWidth: width
        contentHeight: contentCol.height
        clip: true

        Column {
            id: contentCol
            width: Math.min(list.width, page.maxContentWidth)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 0

            SettingsSectionHeader { text: Lang.tr("Posting Permissions") }
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
                Item {
                    id: addCategoryBtn
                    anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                    width: units.gu(4); height: units.gu(4)
                    Icon { anchors.centerIn: parent; width: units.gu(2.4); height: width; name: "add"; color: Style.brand }
                    MouseArea {
                        anchors.fill: parent
                        // always enabled; commit preedit before reading text
                        onPressed: {
                            Qt.inputMethod.commit()
                            page.addCategory(newCategoryField.text)
                            newCategoryField.text = ""
                            mouse.accepted = true
                        }
                    }
                }
            }

            ActivityIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: page.categoriesLoading
                visible: running
            }

            Repeater {
                model: categoryModel
                delegate: Column {
                    id: catDelegate
                    width: contentCol.width
                    // Captured because the inner sub-chip Repeater shadows `index`.
                    readonly property int catIndex: index
                    // Sub-categories parsed from the JSON string kept on the row.
                    readonly property var subs: {
                        try { return JSON.parse(model.subsJson || "[]") } catch (e) { return [] }
                    }

                    // Header row: expand toggle + name (+ sub count) + delete
                    Item {
                        width: parent.width
                        height: units.gu(6)

                        Rectangle {
                            anchors.fill: parent
                            color: catHeaderTap.pressed ? Style.pressed : "transparent"
                        }
                        Icon {
                            id: catChevron
                            anchors { left: parent.left; leftMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                            width: units.gu(2); height: width
                            name: model.expanded ? "go-down" : "go-next"
                            color: Style.textSecondary
                        }
                        Column {
                            anchors { left: catChevron.right; leftMargin: Style.spacingS; right: deleteCatBtn.left; rightMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
                            spacing: units.dp(1)
                            Label {
                                width: parent.width
                                text: model.name || ""
                                elide: Text.ElideRight
                                font.pixelSize: Style.fontRegular
                                font.family: Style.fontFor(text)
                                color: Style.textPrimary
                            }
                            Label {
                                text: catDelegate.subs.length === 0 ? Lang.tr("No sub-categories")
                                    : (catDelegate.subs.length === 1 ? Lang.tr("1 sub-category")
                                       : Lang.tr("%1 sub-categories").arg(catDelegate.subs.length))
                                font.pixelSize: Style.fontXSmall
                                font.family: Style.fontFor(text)
                                color: Style.textSecondary
                            }
                        }
                        AbstractButton {
                            id: deleteCatBtn
                            anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                            width: units.gu(3.5); height: units.gu(3.5)
                            onClicked: page.deleteCategory(index)
                            Icon { anchors.centerIn: parent; width: units.gu(2); height: width; name: "delete"; color: Style.danger }
                        }
                        MouseArea {
                            id: catHeaderTap
                            anchors { left: parent.left; right: deleteCatBtn.left; top: parent.top; bottom: parent.bottom }
                            onClicked: categoryModel.setProperty(index, "expanded", !model.expanded)
                        }
                        Rectangle {
                            anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: units.gu(2) }
                            height: units.dp(1)
                            color: Style.divider
                        }
                    }

                    // Expanded area: sub-category chips + add-sub row
                    Column {
                        width: parent.width
                        visible: model.expanded
                        spacing: Style.spacingS
                        topPadding: model.expanded ? Style.spacingS : 0
                        bottomPadding: model.expanded ? Style.spacingM : 0

                        Flow {
                            width: parent.width - Style.spacingM * 2 - units.gu(3)
                            x: Style.spacingM + units.gu(3)
                            spacing: Style.spacingS
                            visible: catDelegate.subs.length > 0
                            Repeater {
                                model: catDelegate.subs
                                delegate: Rectangle {
                                    height: units.gu(3.5)
                                    width: subRow.width + Style.spacingM
                                    radius: height / 2
                                    color: Style.iconBackground
                                    Row {
                                        id: subRow
                                        anchors.centerIn: parent
                                        spacing: units.dp(4)
                                        Label {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.name || ""
                                            font.pixelSize: Style.fontSmall
                                            font.family: Style.fontFor(text)
                                            color: Style.textPrimary
                                        }
                                        AbstractButton {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: units.gu(2.2); height: units.gu(2.2)
                                            onClicked: page.deleteSubCategory(catDelegate.catIndex, index)
                                            Icon { anchors.centerIn: parent; width: units.gu(1.6); height: width; name: "close"; color: Style.textSecondary }
                                        }
                                    }
                                }
                            }
                        }

                        // Add-sub-category input
                        Item {
                            width: parent.width - Style.spacingM * 2 - units.gu(3)
                            x: Style.spacingM + units.gu(3)
                            height: units.gu(5)
                            TextField {
                                id: newSubField
                                anchors { left: parent.left; right: addSubBtn.left; rightMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
                                placeholderText: Lang.tr("New sub-category")
                                onAccepted: { page.addSubCategory(index, text); text = "" }
                                onActiveFocusChanged: if (activeFocus) { page._focusTarget = newSubField; scrollTimer.restart() }
                            }
                            Item {
                                id: addSubBtn
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                width: units.gu(4); height: units.gu(4)
                                Icon { anchors.centerIn: parent; width: units.gu(2.2); height: width; name: "add"; color: Style.brand }
                                MouseArea {
                                    anchors.fill: parent
                                    // always enabled; commit preedit before reading text
                                    onPressed: {
                                        Qt.inputMethod.commit()
                                        page.addSubCategory(index, newSubField.text)
                                        newSubField.text = ""
                                        mouse.accepted = true
                                    }
                                }
                            }
                        }
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

            // extra room to scroll clear of keyboard
            Item { width: 1; height: units.gu(8) }
        }
    }
}
