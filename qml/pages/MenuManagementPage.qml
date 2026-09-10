import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/CustomMenuService.js" as CustomMenuService

// CRUD for the current community's navbar/menu items (/custom-menu)
Page {
    id: page

    property bool loading: false
    property string errorMsg: ""

    header: PageHeader {
        title: Lang.tr("Menu / Navbar")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.pageStack.pop() }
        ]
        trailingActionBar.actions: [
            Action { iconName: "add"; text: Lang.tr("Add"); onTriggered: page.openEditor(null) }
        ]
    }

    ListModel { id: menuModel; dynamicRoles: true }

    function load() {
        page.loading = true
        page.errorMsg = ""
        menuModel.clear()
        CustomMenuService.listByWebsiteAndCommunity(Config.baseUrl,
            { community_id: Config.managedCommunityId }, Session.token,
            function (list) {
                page.loading = false
                for (var i = 0; i < list.length; i++)
                    menuModel.append(list[i])
            },
            function (err) {
                page.loading = false
                page.errorMsg = err.message || Lang.tr("Failed to load menu items.")
            })
    }

    function move(index, direction) {
        var ids = []
        for (var i = 0; i < menuModel.count; i++) ids.push(menuModel.get(i).id)
        var target = direction === "up" ? index - 1 : index + 1
        if (target < 0 || target >= ids.length) return
        var tmp = ids[index]; ids[index] = ids[target]; ids[target] = tmp
        CustomMenuService.updatePositions(Config.baseUrl, ids, Session.token,
            function () { page.load() },
            function (err) { Toast.error(err.message || Lang.tr("Failed to reorder.")) })
    }

    function remove(index) {
        var item = menuModel.get(index)
        CustomMenuService.deleteMenu(Config.baseUrl, item.id, Session.token,
            function () {
                menuModel.remove(index)
                Toast.show(Lang.tr("Menu item deleted."))
            },
            function (err) { Toast.error(err.message || Lang.tr("Failed to delete.")) })
    }

    function openEditor(item) {
        var dlg = PopupUtils.open(editorDialog)
        dlg.setInitial(item)
    }

    Component.onCompleted: page.load()

    ListView {
        id: list
        anchors { top: page.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        model: menuModel
        clip: true

        delegate: SettingsRow {
            width: list.width
            iconName: model.icon || "external-link"
            label: model.title || model.name || ""
            showChevron: true
            onClicked: page.openEditor(model)

            Row {
                anchors { right: parent.right; rightMargin: units.gu(5); verticalCenter: parent.verticalCenter }
                spacing: Style.spacingS
                AbstractButton {
                    width: units.gu(3); height: units.gu(3)
                    onClicked: page.move(index, "up")
                    Icon { anchors.centerIn: parent; width: units.gu(2); height: width; name: "up"; color: Style.textSecondary }
                }
                AbstractButton {
                    width: units.gu(3); height: units.gu(3)
                    onClicked: page.move(index, "down")
                    Icon { anchors.centerIn: parent; width: units.gu(2); height: width; name: "down"; color: Style.textSecondary }
                }
                AbstractButton {
                    width: units.gu(3); height: units.gu(3)
                    onClicked: page.remove(index)
                    Icon { anchors.centerIn: parent; width: units.gu(2); height: width; name: "delete"; color: Style.danger }
                }
            }
        }
    }

    ActivityIndicator {
        anchors.centerIn: parent
        running: page.loading
        visible: running
    }

    EmptyState {
        anchors { top: page.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: !page.loading && page.errorMsg === "" && menuModel.count === 0
        iconName: "edit"
        message: Lang.tr("No menu items yet")
    }

    ErrorState {
        anchors { top: page.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: page.errorMsg !== "" && menuModel.count === 0
        message: page.errorMsg
        onRetry: page.load()
    }

    Component {
        id: editorDialog
        Dialog {
            id: dlg
            title: titleField.text.length === 0 ? Lang.tr("New menu item") : Lang.tr("Edit menu item")
            property var editing: null
            property bool saving: false

            function setInitial(item) {
                editing = item
                titleField.text = item ? (item.title || item.name || "") : ""
                urlField.text = item ? (item.url || "") : ""
                iconField.text = item ? (item.icon || "") : ""
            }

            FormField { id: titleField; width: parent.width; placeholder: Lang.tr("Title") }
            FormField { id: urlField; width: parent.width; placeholder: Lang.tr("URL") }
            FormField { id: iconField; width: parent.width; placeholder: Lang.tr("Icon name (optional)") }

            Label {
                width: parent.width
                wrapMode: Text.WordWrap
                color: Style.danger
                text: dlg.errorMsg || ""
                visible: text.length > 0
            }

            property string errorMsg: ""

            Row {
                width: parent.width
                spacing: Style.spacingS
                Button {
                    width: (parent.width - Style.spacingS) / 2
                    text: Lang.tr("Cancel")
                    onClicked: PopupUtils.close(dlg)
                }
                Button {
                    width: (parent.width - Style.spacingS) / 2
                    text: dlg.saving ? Lang.tr("Saving…") : Lang.tr("Save")
                    color: Style.brand
                    enabled: !dlg.saving && titleField.text.length > 0
                    onClicked: {
                        dlg.saving = true
                        dlg.errorMsg = ""
                        var body = {
                            title: titleField.text,
                            url: urlField.text,
                            icon: iconField.text,
                            community_id: Config.managedCommunityId
                        }
                        if (dlg.editing && dlg.editing.id) body.id = dlg.editing.id
                        CustomMenuService.createOrUpdate(Config.baseUrl, body, Session.token,
                            function () {
                                dlg.saving = false
                                PopupUtils.close(dlg)
                                Toast.success(Lang.tr("Menu item saved."))
                                page.load()
                            },
                            function (err) {
                                dlg.saving = false
                                dlg.errorMsg = err.message || Lang.tr("Failed to save.")
                            })
                    }
                }
            }
        }
    }
}
