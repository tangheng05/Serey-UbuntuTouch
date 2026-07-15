import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import Lomiri.Components.Popups 1.3 as Popups
import "../services/PlatformService.js" as PlatformService
import "../services/AccountService.js" as AccountService

// "Platform Setting" card from the CMS hub: subscription, banned users, delete platform
Page {
    id: page

    // Filled from a fresh get-communities walk (loadName). The startup community
    // cache can be stale right after creating a platform, and the old fallback to
    // the SELECTED source name rendered "Delete Global" here.
    property string managedTitle: Config.communityInfoFor(Config.managedCommunityId)
        ? Config.communityInfoFor(Config.managedCommunityId).title : Lang.tr("this platform")
    function loadName() {
        PlatformService.getCommunityContext(Config.baseUrl, Config.managedCommunityId,
            function (ctx) { if (ctx.name && ctx.name.length > 0) page.managedTitle = ctx.name },
            function () { /* keep the fallback */ })
    }

    // My Subscription (GET /subscription/active — resolved from the JWT, not per-community)
    property string subscriptionText: ""
    property var subscription: null       // full mapped object from getActiveSubscription, or null
    property var latestPayment: null      // { amount, currency, date } from payment-history, or null
    function loadSubscription() {
        PlatformService.getActiveSubscription(Config.baseUrl, Session.token,
            function (sub) {
                page.subscription = sub
                page.subscriptionText = sub.hasActive
                    ? (sub.planName || sub.planType || Lang.tr("Active"))
                    : Lang.tr("None")
                if (sub.hasActive)
                    PlatformService.getLatestPayment(Config.baseUrl, Session.token,
                        function (p) { page.latestPayment = p },
                        function () { /* non-fatal: amount tile just stays blank */ })
            },
            function () { page.subscriptionText = "" })
    }

    // Delete platform (soft delete server-side)
    property bool deleting: false

    function _finishDeleted() {
        var gone = Config.managedCommunityId
        var set = {}
        for (var k in Config.ownedCommunityIdSet)
            if (Number(k) !== gone) set[k] = true
        Config.ownedCommunityIdSet = set
        Config.overrideManagedCommunityId = 0
        Toast.success(Lang.tr("Platform deleted."))
        Nav.goToTab(3)
    }

    // Not-found means the delete landed: treat it as deleted, not a failure.
    function _isGone(err) {
        if (!err) return false
        if (err.status === 404) return true
        return String(err.message || "").toLowerCase().indexOf("not found") >= 0
    }

    function deletePlatform() {
        if (page.deleting) return
        page.deleting = true
        PlatformService.deleteCommunity(Config.baseUrl, Session.token, Config.managedCommunityId,
            function () {
                page.deleting = false
                page._finishDeleted()
            },
            function (err) {
                page.deleting = false
                if (page._isGone(err)) { page._finishDeleted(); return }
                Toast.error((err && err.message) || Lang.tr("Failed to delete platform."))
            })
    }

    header: PageHeader {
        title: Lang.tr("Platform Setting")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.pageStack.pop() }
        ]
    }

    Component.onCompleted: { page.loadSubscription(); page.loadName() }

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
            spacing: Style.spacingS

            SettingsSectionHeader { text: Lang.tr("Subscription") }
            SettingsRow {
                width: parent.width
                iconName: "starred"
                label: Lang.tr("My Subscription")
                valueText: page.subscriptionText
                showChevron: page.subscription !== null && page.subscription.hasActive
                onClicked: if (page.subscription && page.subscription.hasActive) page.pageStack.push(subscriptionPage)
            }

            SettingsSectionHeader { text: Lang.tr("Moderation") }
            SettingsRow {
                width: parent.width
                iconName: "system-shutdown"
                label: Lang.tr("Banned Users")
                showChevron: true
                onClicked: page.pageStack.push(bannedUsersPage)
            }

            SettingsSectionHeader { text: Lang.tr("Danger zone") }
            SettingsRow {
                width: parent.width
                iconName: "delete"
                label: Lang.tr("Delete %1").arg(page.managedTitle)
                danger: true
                onClicked: Popups.PopupUtils.open(deleteDialog)
            }

            Item { width: 1; height: Style.spacingL }
        }
    }

    // My Subscription detail — plan, dates, days left, amount paid, status badges.
    Component {
        id: subscriptionPage
        Page {
            id: subPage
            readonly property var sub: page.subscription || ({})

            header: PageHeader {
                title: Lang.tr("My Subscription")
                leadingActionBar.actions: [
                    Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.pageStack.pop() }
                ]
            }

            Flickable {
                anchors { top: subPage.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
                contentWidth: width
                contentHeight: col.height + Style.spacingL * 2
                clip: true

                Column {
                    id: col
                    width: Math.min(parent.width - Style.spacingL * 2, units.gu(50))
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Style.spacingL
                    spacing: Style.spacingM

                    Label {
                        width: parent.width
                        text: subPage.sub.planName || subPage.sub.planType || Lang.tr("Subscription")
                        font.pixelSize: Style.fontTitle
                        font.weight: Font.DemiBold
                        font.family: Style.fontFor(text)
                        color: Style.textPrimary
                    }

                    // Status pills — trial / auto-renew / cancelling / past due.
                    Row {
                        width: parent.width
                        spacing: Style.spacingS
                        Repeater {
                            model: {
                                var pills = []
                                if (subPage.sub.isTrial) pills.push({ text: Lang.tr("Trial"), color: Style.brand })
                                if (subPage.sub.isPastDue) pills.push({ text: Lang.tr("Past due"), color: Style.danger })
                                if (subPage.sub.isCancelling) pills.push({ text: Lang.tr("Cancelling"), color: Style.danger })
                                else if (subPage.sub.autoRenew) pills.push({ text: Lang.tr("Auto-renews"), color: Style.success })
                                return pills
                            }
                            delegate: Rectangle {
                                width: pillLabel.implicitWidth + Style.spacingM * 2
                                height: units.gu(3.2)
                                radius: Style.pillRadius
                                color: Qt.rgba(modelData.color.r, modelData.color.g, modelData.color.b, 0.12)
                                Label {
                                    id: pillLabel
                                    anchors.centerIn: parent
                                    text: modelData.text
                                    font.pixelSize: Style.fontSmall
                                    font.weight: Font.DemiBold
                                    font.family: Style.fontFor(text)
                                    color: modelData.color
                                }
                            }
                        }
                    }

                    Item { width: 1; height: Style.spacingS }

                    // Tiles: Amount Paid / Days Left, matching the CMS reference layout.
                    Row {
                        width: parent.width
                        spacing: Style.spacingM

                        Rectangle {
                            width: (parent.width - Style.spacingM) / 2
                            height: units.gu(9)
                            radius: Style.cardRadius
                            color: Style.iconBackground
                            Column {
                                anchors.centerIn: parent
                                spacing: units.dp(2)
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: page.latestPayment && page.latestPayment.amount !== null
                                        ? (page.latestPayment.amount + (page.latestPayment.currency || "$"))
                                        : "—"
                                    font.pixelSize: Style.fontLarge
                                    font.weight: Font.DemiBold
                                    color: Style.textPrimary
                                }
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Lang.tr("Amount Paid")
                                    font.pixelSize: Style.fontSmall
                                    font.family: Style.fontFor(text)
                                    color: Style.textSecondary
                                }
                            }
                        }
                        Rectangle {
                            width: (parent.width - Style.spacingM) / 2
                            height: units.gu(9)
                            radius: Style.cardRadius
                            color: Style.iconBackground
                            Column {
                                anchors.centerIn: parent
                                spacing: units.dp(2)
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: subPage.sub.daysUntilExpiry !== null && subPage.sub.daysUntilExpiry !== undefined
                                        ? Lang.tr("%1 day(s)").arg(subPage.sub.daysUntilExpiry) : "—"
                                    font.pixelSize: Style.fontLarge
                                    font.weight: Font.DemiBold
                                    color: Style.textPrimary
                                }
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Lang.tr("Days Left")
                                    font.pixelSize: Style.fontSmall
                                    font.family: Style.fontFor(text)
                                    color: Style.textSecondary
                                }
                            }
                        }
                    }

                    Item { width: 1; height: Style.spacingS }

                    SettingsRow {
                        width: parent.width
                        iconName: "calendar"
                        label: Lang.tr("Start Date")
                        valueText: subPage.sub.validStartDate || "—"
                    }
                    SettingsRow {
                        width: parent.width
                        iconName: "calendar"
                        label: Lang.tr("Expiry Date")
                        valueText: subPage.sub.validEndDate || "—"
                    }

                    Item { width: 1; height: Style.spacingL }
                }
            }
        }
    }

    // Confirm before the (soft) delete.
    Component {
        id: deleteDialog
        Popups.Dialog {
            id: ddlg
            title: Lang.tr("Delete “%1”?").arg(page.managedTitle)
            text: Lang.tr("Your platform will be removed from Serey. This cannot be undone from the app.")
            Button {
                text: page.deleting ? Lang.tr("Deleting…") : Lang.tr("Delete platform")
                color: Style.danger
                enabled: !page.deleting
                onClicked: {
                    Popups.PopupUtils.close(ddlg)
                    page.deletePlatform()
                }
            }
            Button {
                text: Lang.tr("Cancel")
                onClicked: Popups.PopupUtils.close(ddlg)
            }
        }
    }

    // Banned users state — lives on THIS page (not the pushed sub-page) since
    // JS imports can resolve to null inside dynamically created components.
    ListModel { id: bannedModel; dynamicRoles: true }
    property bool banLoading: false
    property bool banning: false

    function loadBanned() {
        page.banLoading = true
        PlatformService.listBannedUsers(Config.baseUrl, page.managedTitle, Session.token,
            function (users) {
                page.banLoading = false
                bannedModel.clear()
                for (var i = 0; i < users.length; i++) bannedModel.append(users[i])
            },
            function (err) {
                page.banLoading = false
                Toast.error((err && err.message) || Lang.tr("Failed to load banned users."))
            })
    }

    function banUser(rawName, onDone) {
        var username = (rawName || "").trim().replace(/^@/, "")
        if (username.length === 0 || page.banning) return
        page.banning = true
        PlatformService.banUser(Config.baseUrl, Session.token, page.managedTitle, username, "",
            function () {
                page.banning = false
                page.loadBanned()
                Toast.success(Lang.tr("@%1 banned.").arg(username))
                if (onDone) onDone()
            },
            function (err) {
                page.banning = false
                Toast.error((err && err.message) || Lang.tr("Failed to ban user."))
            })
    }

    function unbanUser(index) {
        var username = bannedModel.get(index).username
        PlatformService.unbanUser(Config.baseUrl, Session.token, page.managedTitle, username,
            function () {
                bannedModel.remove(index)
                Toast.show(Lang.tr("@%1 unbanned.").arg(username))
            },
            function (err) { Toast.error((err && err.message) || Lang.tr("Failed to unban user.")) })
    }

    // Banned users — list, ban and unban. `community` is the TITLE string.
    Component {
        id: bannedUsersPage
        Page {
            id: banPage

            header: PageHeader {
                title: Lang.tr("Banned Users")
                leadingActionBar.actions: [
                    Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.pageStack.pop() }
                ]
            }

            Component.onCompleted: page.loadBanned()

            property bool banSearching: false
            property bool banSearchOpen: false
            property int banSearchGeneration: 0
            // Bridges a search-result tap (banSearchListView's delegate) into banField/banSearchDebounce,
            // which live in banList's `header:` — a separate id scope that delegate can't reach directly.
            property string pendingFillUsername: ""
            ListModel { id: banSearchModel }

            function doBanSearch(query) {
                var q = query.trim()
                if (q.length < 2) { banSearchModel.clear(); banPage.banSearchOpen = false; return }
                banPage.banSearching = true
                banPage.banSearchOpen = true
                var gen = ++banPage.banSearchGeneration
                AccountService.searchUser(Config.baseUrl, Session.token, q,
                    function (users) {
                        if (gen !== banPage.banSearchGeneration) return
                        banPage.banSearching = false
                        banSearchModel.clear()
                        for (var i = 0; i < users.length; i++) banSearchModel.append({ username: users[i].username, profileUrl: "" })
                        for (var j = 0; j < users.length; j++) {
                            (function (capturedGen, uname) {
                                AccountService.profile(Config.baseUrl, uname, Session.token,
                                    function (u) {
                                        if (capturedGen !== banPage.banSearchGeneration) return
                                        for (var k = 0; k < banSearchModel.count; k++) {
                                            if (banSearchModel.get(k).username === uname) {
                                                banSearchModel.setProperty(k, "profileUrl", u.profileUrl || "")
                                                break
                                            }
                                        }
                                    },
                                    function () { /* avatar optional */ })
                            })(gen, users[j].username)
                        }
                    },
                    function (err) {
                        if (gen !== banPage.banSearchGeneration) return
                        banPage.banSearching = false
                        banSearchModel.clear()
                        Toast.error((err && err.message) || Lang.tr("User search failed."))
                    })
            }
            function closeBanSearch() {
                banSearchModel.clear()
                banPage.banSearchOpen = false
                banPage.banSearchGeneration++
            }

            ListView {
                id: banList
                anchors { top: banPage.header.bottom; bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                width: Math.min(parent.width, units.gu(60))
                model: bannedModel
                clip: true

                header: Item {
                    width: banList.width
                    height: units.gu(7)

                    Item {
                        anchors { left: parent.left; leftMargin: Style.spacingM; right: banBtn.left; rightMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
                        height: units.gu(4)

                        // A plain TextInput, not Lomiri's TextField — matches SettingsPage's
                        // user search, which fires onTextChanged live per keystroke.
                        TextInput {
                            id: banField
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            font.pixelSize: Style.fontRegular
                            font.family: Style.fontFor(text)
                            color: Style.textPrimary
                            clip: true
                            enabled: !page.banning
                            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                            onTextChanged: {
                                if (text.trim().length < 2) { banSearchModel.clear(); banPage.banSearchOpen = false }
                                banSearchDebounce.restart()
                            }
                            Keys.onReturnPressed: { banPage.closeBanSearch(); page.banUser(text, function () { banField.text = "" }) }
                        }
                        Label {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: Lang.tr("Username to ban")
                            font.pixelSize: Style.fontRegular
                            font.family: Style.fontFor(text)
                            color: Style.textSecondary
                            visible: banField.text.length === 0
                        }
                    }
                    AbstractButton {
                        id: banBtn
                        anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                        width: units.gu(4); height: units.gu(4)
                        enabled: !page.banning && banField.text.trim().length > 0
                        onClicked: { banPage.closeBanSearch(); page.banUser(banField.text, function () { banField.text = "" }) }
                        Icon { anchors.centerIn: parent; width: units.gu(2.4); height: width; name: "add"; color: enabled ? Style.danger : Style.textSecondary }
                    }

                    // Lives inside the same header component as banField — a Timer declared
                    // outside ListView.header (a separate implicit Component) can't see it.
                    Timer { id: banSearchDebounce; interval: 250; onTriggered: banPage.doBanSearch(banField.text) }

                    // Picks up a search-result tap relayed via banPage.pendingFillUsername (see banSearchListView's
                    // delegate) — that delegate is a sibling Component and can't reach banField/banSearchDebounce directly.
                    Connections {
                        target: banPage
                        function onPendingFillUsernameChanged() {
                            if (banPage.pendingFillUsername === "") return
                            banSearchDebounce.stop()
                            banField.text = banPage.pendingFillUsername
                            banPage.pendingFillUsername = ""
                        }
                    }
                }

                delegate: Item {
                    width: banList.width
                    height: units.gu(7)

                    Column {
                        anchors { left: parent.left; leftMargin: Style.spacingM; right: unbanBtn.left; rightMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
                        spacing: units.dp(2)
                        Label {
                            width: parent.width
                            text: "@" + model.username
                            elide: Text.ElideRight
                            font.pixelSize: Style.fontRegular
                            font.weight: Font.DemiBold
                            font.family: Style.fontFor(text)
                            color: Style.textPrimary
                        }
                        Label {
                            width: parent.width
                            visible: (model.reason || "").length > 0
                            text: model.reason || ""
                            elide: Text.ElideRight
                            font.pixelSize: Style.fontSmall
                            font.family: Style.fontFor(text)
                            color: Style.textSecondary
                        }
                    }

                    Item {
                        id: unbanBtn
                        anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                        width: unbanLabel.implicitWidth + Style.spacingM * 2
                        height: units.gu(4)

                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: "transparent"
                            border.width: units.dp(1.5)
                            border.color: Style.divider
                        }
                        Label {
                            id: unbanLabel
                            anchors.centerIn: parent
                            text: Lang.tr("Unban")
                            font.pixelSize: Style.fontSmall
                            font.weight: Font.DemiBold
                            font.family: Style.fontFor(text)
                            color: Style.textPrimary
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: page.unbanUser(index)
                        }
                    }

                    Rectangle {
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: units.gu(2) }
                        height: units.dp(1)
                        color: Style.divider
                    }
                }
            }

            ActivityIndicator {
                anchors.centerIn: parent
                running: page.banLoading
                visible: running
            }

            Label {
                anchors.centerIn: parent
                visible: !page.banLoading && bannedModel.count === 0
                text: Lang.tr("No banned users")
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFor(text)
                color: Style.textSecondary
            }

            Rectangle {
                id: banSearchOverlay
                visible: banPage.banSearchOpen && (banSearchModel.count > 0 || banPage.banSearching)
                anchors { top: banPage.header.bottom; topMargin: units.gu(7); left: banList.left; right: banList.right }
                height: banSearchModel.count > 0 ? Math.min(banSearchModel.count * units.gu(6), units.gu(30)) : units.gu(8)
                radius: units.gu(1)
                color: Style.surface
                clip: true
                z: 50

                Rectangle {
                    anchors { fill: parent; margins: -units.dp(1) }
                    radius: parent.radius + units.dp(1)
                    color: "transparent"
                    border.width: units.dp(1)
                    border.color: Style.divider
                    z: -1
                }

                ActivityIndicator {
                    anchors.centerIn: parent
                    running: banPage.banSearching && banSearchModel.count === 0
                    visible: running
                }

                ListView {
                    id: banSearchListView
                    anchors.fill: parent
                    model: banSearchModel
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: AbstractButton {
                        width: banSearchListView.width
                        height: units.gu(6)
                        // banField/banSearchDebounce live in banList's `header:` — a separate id scope
                        // this delegate can't reach — so relay the pick via banPage.pendingFillUsername instead.
                        onClicked: { banPage.pendingFillUsername = model.username; banPage.closeBanSearch() }

                        Row {
                            anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                            spacing: Style.spacingM
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: units.gu(4); height: width; radius: width / 2
                                color: Style.iconBackground

                                CircleImage {
                                    id: banResultAvatar
                                    anchors { fill: parent; margins: units.dp(2) }
                                    source: model.profileUrl || ""
                                }
                                Label {
                                    anchors.centerIn: parent
                                    text: (model.username || "?").charAt(0).toUpperCase()
                                    font.pixelSize: Style.fontSmall
                                    font.bold: true
                                    color: Style.brand
                                    visible: !banResultAvatar.loaded
                                }
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "@" + (model.username || "")
                                font.pixelSize: Style.fontRegular
                                font.family: Style.fontFor(text)
                                color: Style.textPrimary
                            }
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: banSearchOverlay.visible
                z: 49
                propagateComposedEvents: true
                onClicked: { banField.focus = false; banPage.closeBanSearch(); mouse.accepted = false }
            }
        }
    }
}
