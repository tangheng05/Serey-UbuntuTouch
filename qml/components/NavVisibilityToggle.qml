import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../services/CustomMenuService.js" as CustomMenuService

// "Show in app menu" switch, backed by a custom_menu row (platform_type=WEB)
Item {
    id: root

    property string navKey: ""
    property string navLabel: ""
    property string navIcon: ""

    width: parent ? parent.width : units.gu(40)
    height: units.gu(6.5)

    // Row id, once known (create response carries none, reload to learn it)
    property var _rowId: null
    property bool hidden: false
    property bool busy: false

    function load() {
        root.busy = true
        CustomMenuService.listByWebsiteAndCommunity(Config.baseUrl,
            { community_id: Config.managedCommunityId }, Session.token,
            function (rows) {
                root.busy = false
                var row = null
                for (var i = 0; i < rows.length; i++)
                    if (rows[i].key === root.navKey) { row = rows[i]; break }
                root._rowId = row ? row.id : null
                root.hidden = !!(row && row.is_hidden)
            },
            function () { root.busy = false /* non-fatal: defaults to visible */ })
    }

    function _setHidden(newHidden) {
        var body = {
            key: root.navKey,
            name: root.navLabel,
            icon: root.navIcon,
            link: "",
            is_new_tab: false,
            is_hidden: newHidden,
            community_id: Config.managedCommunityId
        }
        if (root._rowId) body.id = root._rowId
        root.busy = true
        CustomMenuService.createOrUpdate(Config.baseUrl, body, Session.token,
            function () {
                root.load()
                Nav.navMenuChanged()
                Toast.success(newHidden ? Lang.tr("Hidden from the app menu.") : Lang.tr("Shown in the app menu."))
            },
            function (err) {
                root.busy = false
                toggleSwitch.checked = !newHidden   // revert: user's tap already broke the binding
                Toast.error((err && err.message) || Lang.tr("Failed to update visibility."))
            })
    }

    Component.onCompleted: root.load()

    Label {
        anchors { left: parent.left; leftMargin: Style.spacingM; right: toggleSwitch.left; rightMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
        text: Lang.tr("Show in app menu")
        elide: Text.ElideRight
        font.pixelSize: Style.fontRegular
        font.family: Style.fontFor(text)
        color: Style.textPrimary
    }

    Switch {
        id: toggleSwitch
        anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
        enabled: !root.busy
        checked: !root.hidden
        onCheckedChanged: {
            if (checked === !root.hidden) return
            root._setHidden(!checked)
        }
    }

    Rectangle {
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        height: units.dp(1)
        color: Style.divider
    }
}
