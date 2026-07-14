import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import Lomiri.Components.Popups 1.3 as Popups
import "../services/PlatformService.js" as PlatformService

// "Platform Setting" card from the CMS hub: subscription, banned users, delete platform
Page {
    id: page

    readonly property string managedTitle: Config.communityInfoFor(Config.managedCommunityId)
        ? Config.communityInfoFor(Config.managedCommunityId).title : Config.currentCommunityName

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
    function deletePlatform() {
        if (page.deleting) return
        page.deleting = true
        PlatformService.deleteCommunity(Config.baseUrl, Session.token, Config.managedCommunityId,
            function () {
                page.deleting = false
                // Drop the deleted platform from the owned set so Settings flips back to "Create your platform".
                var set = {}
                for (var k in Config.ownedCommunityIdSet)
                    if (Number(k) !== Config.managedCommunityId) set[k] = true
                Config.ownedCommunityIdSet = set
                Config.overrideManagedCommunityId = 0
                Toast.success(Lang.tr("Platform deleted."))
                page.pageStack.pop()   // this page
                page.pageStack.pop()   // the CMS hub — its platform no longer exists
            },
            function (err) {
                page.deleting = false
                Toast.error((err && err.message) || Lang.tr("Failed to delete platform."))
            })
    }

    header: PageHeader {
        title: Lang.tr("Platform Setting")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.pageStack.pop() }
        ]
    }

    Component.onCompleted: page.loadSubscription()

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

            ListView {
                id: banList
                anchors { top: banPage.header.bottom; bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                width: Math.min(parent.width, units.gu(60))
                model: bannedModel
                clip: true

                header: Item {
                    width: banList.width
                    height: units.gu(7)

                    TextField {
                        id: banField
                        anchors { left: parent.left; leftMargin: Style.spacingM; right: banBtn.left; rightMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
                        placeholderText: Lang.tr("Username to ban")
                        inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                        enabled: !page.banning
                        onAccepted: page.banUser(text, function () { banField.text = "" })
                    }
                    AbstractButton {
                        id: banBtn
                        anchors { right: parent.right; rightMargin: Style.spacingM; verticalCenter: parent.verticalCenter }
                        width: units.gu(4); height: units.gu(4)
                        enabled: !page.banning && banField.text.trim().length > 0
                        onClicked: page.banUser(banField.text, function () { banField.text = "" })
                        Icon { anchors.centerIn: parent; width: units.gu(2.4); height: width; name: "add"; color: enabled ? Style.danger : Style.textSecondary }
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
        }
    }
}
