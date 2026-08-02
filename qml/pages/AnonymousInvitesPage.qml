import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/AnonymousInviteService.js" as InviteService

// Creator side of anonymous invites: mint/copy/revoke codes; mirrors web SocialMediaOwner CMS panel.
Page {
    id: page

    readonly property real maxContentWidth: units.gu(50)

    property bool loading: true
    property bool eligible: false
    property bool busy: false
    property var codes: []
    property var quota: ({ used_slots: 0, max: 0, remaining: 0 })
    property string _pendingRevoke: ""

    header: PageHeader {
        title: Lang.tr("Anonymous Invites")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.pageStack.pop() }
        ]
    }

    Component.onCompleted: load()

    function load() {
        page.loading = true;
        InviteService.listInvites(Config.baseUrl, Session.token,
            function (r) {
                page.loading = false;
                page.eligible = r.eligible;
                page.quota = r.quota;
                // Revoked codes are hidden; their slot is already back in the quota.
                page.codes = r.codes.filter(function (c) { return c.status !== "revoked"; });
            },
            function (err) {
                page.loading = false;
                if (!(err && err.status === 401))
                    Toast.error((err && err.message) || Lang.tr("Couldn't load your invites."));
            });
    }

    function generate() {
        if (page.busy) return;
        page.busy = true;
        InviteService.generateInvite(Config.baseUrl, Session.token,
            function () { page.busy = false; Toast.success(Lang.tr("Invite link created.")); page.load(); },
            function (err) {
                page.busy = false;
                if (!(err && err.status === 401))
                    Toast.error((err && err.message) || Lang.tr("Couldn't create a code."));
            });
    }

    // JS services resolve to null in Repeater delegates, so route through page-level functions
    function shareCode(code) { Share.open(InviteService.inviteLink(code)); }

    function revoke(code) {
        InviteService.revokeInvite(Config.baseUrl, Session.token, code,
            function () { Toast.success(Lang.tr("Code revoked, slot freed.")); page.load(); },
            function (err) {
                if (!(err && err.status === 401))
                    Toast.error((err && err.message) || Lang.tr("Couldn't revoke the code."));
            });
    }

    Component {
        id: revokeDialog
        Dialog {
            id: rdlg
            // Title carries the code (dialog shouldn't read as incomplete without one)
            title: Lang.tr("Revoke %1?").arg(page._pendingRevoke)
            text: Lang.tr("The invite link stops working and the slot goes back to your quota.")
            Button {
                text: Lang.tr("Revoke")
                color: Style.danger
                onClicked: { PopupUtils.close(rdlg); page.revoke(page._pendingRevoke); }
            }
            Button {
                text: Lang.tr("Cancel")
                onClicked: PopupUtils.close(rdlg)
            }
        }
    }

    ActivityIndicator {
        anchors.centerIn: parent
        running: page.loading
        visible: running
    }

    // Not on an invite-granting plan: explain and stop.
    Column {
        anchors { centerIn: parent }
        width: Math.min(parent.width - Style.spacingL * 2, page.maxContentWidth)
        spacing: Style.spacingM
        visible: !page.loading && !page.eligible

        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            width: units.gu(6); height: width
            name: "contact"
            color: Style.textSecondary
        }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: Lang.tr("Your plan doesn't include free invites")
            font.pixelSize: Style.fontLarge
            font.weight: Font.DemiBold
            font.family: Style.fontFor(text)
            color: Style.textTitle
            wrapMode: Text.WordWrap
        }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: Lang.tr("Upgrade to a platform plan to unlock them.")
            font.pixelSize: Style.fontRegular
            font.family: Style.fontFor(text)
            color: Style.textSecondary
            wrapMode: Text.WordWrap
        }
    }

    // Real ListView (not Repeater-in-Column) so swipe actions align to the capped list width
    ListView {
        id: list
        anchors { top: page.header.bottom; bottom: footer.top; horizontalCenter: parent.horizontalCenter }
        width: Math.min(parent.width, page.maxContentWidth + Style.spacingM * 2)
        visible: !page.loading && page.eligible
        clip: true
        model: page.codes
        cacheBuffer: units.gu(40)

        // Empty state (no codes yet) sits below the header card.
        footer: Item {
            width: list.width
            height: page.codes.length === 0 ? emptyLbl.implicitHeight + Style.spacingL * 2 : Style.spacingL
            Label {
                id: emptyLbl
                visible: page.codes.length === 0
                anchors { top: parent.top; left: parent.left; right: parent.right
                          topMargin: Style.spacingL; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                horizontalAlignment: Text.AlignHCenter
                text: Lang.tr("No invite codes yet. Generate one below.")
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFor(text)
                color: Style.textSecondary
                wrapMode: Text.WordWrap
            }
        }

        // Quota card + intro + section label scroll with the list.
        header: Column {
            width: list.width
            spacing: Style.spacingM
            bottomPadding: Style.spacingS

            Item { width: 1; height: Style.spacingL }

            Rectangle {
                width: parent.width - Style.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                height: quotaCol.height + Style.spacingM * 2
                radius: Style.cardRadius
                color: Style.iconBackground
                Column {
                    id: quotaCol
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                              leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                    spacing: units.dp(2)
                    Label {
                        text: String(page.quota.remaining)
                        font.pixelSize: Style.fontTitle
                        font.weight: Font.DemiBold
                        color: Style.textTitle
                    }
                    Label {
                        text: Lang.tr("invites left · %1 of %2 used").arg(page.quota.used_slots).arg(page.quota.max)
                        font.pixelSize: Style.fontSmall
                        font.family: Style.fontFor(text)
                        color: Style.textSecondary
                    }
                }
            }

            Label {
                width: parent.width - Style.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                text: Lang.tr("Share a link and let someone join Serey right away. No email or phone number needed, so they sign up completely anonymously. Each code works once.")
                font.pixelSize: Style.fontSmall
                font.family: Style.fontFor(text)
                color: Style.textSecondary
                wrapMode: Text.WordWrap
            }

            Label {
                width: parent.width - Style.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                text: Lang.tr("Your codes")
                font.pixelSize: Style.fontSmall
                font.weight: Font.DemiBold
                font.family: Style.fontFor(text)
                color: Style.textSecondary
                visible: page.codes.length > 0
            }
        }

        // Swipe HIG polarity: LEADING = red revoke, TRAILING = share; only active codes act
        delegate: ListItem {
            width: list.width
            height: rowInner.height + Style.spacingM * 2

            property bool isUnused: modelData.status === "unused"

            leadingActions: isUnused ? revokeActions : null
            trailingActions: isUnused ? shareActions : null

            ListItemActions {
                id: revokeActions
                delegate: Rectangle {
                    width: units.gu(7); height: parent ? parent.height : units.gu(6)
                    color: Style.danger
                    Icon { anchors.centerIn: parent; width: units.gu(2.5); height: width
                           name: action.iconName; color: "white" }
                }
                actions: [
                    Action {
                        iconName: "delete"
                        text: Lang.tr("Revoke")
                        onTriggered: { page._pendingRevoke = modelData.code; PopupUtils.open(revokeDialog); }
                    }
                ]
            }
            ListItemActions {
                id: shareActions
                delegate: Item {
                    width: units.gu(7); height: parent ? parent.height : units.gu(6)
                    Icon { anchors.centerIn: parent; width: units.gu(2.5); height: width
                           name: action.iconName; color: Style.textPrimary }
                }
                actions: [
                    Action {
                        iconName: "share"
                        text: Lang.tr("Share")
                        onTriggered: page.shareCode(modelData.code)
                    }
                ]
            }

            Column {
                id: rowInner
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                          leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                spacing: units.dp(3)
                Label {
                    width: parent.width
                    text: modelData.code
                    font.pixelSize: Style.fontRegular
                    font.weight: Font.DemiBold
                    font.family: "Ubuntu Mono"
                    color: Style.textPrimary
                    elide: Text.ElideRight
                }
                Label {
                    width: parent.width
                    text: isUnused ? Lang.tr("Active") : Lang.tr("Redeemed")
                    font.pixelSize: Style.fontXSmall
                    font.family: Style.fontFor(text)
                    color: isUnused ? Style.success : Style.textSecondary
                    elide: Text.ElideRight
                }
            }
        }
    }

    // Pinned generate action.
    Rectangle {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: page.eligible && !page.loading ? genBtn.height + Style.spacingM * 2 : 0
        visible: page.eligible && !page.loading
        color: Style.surface

        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: units.dp(1); color: Style.divider
        }

        PrimaryButton {
            id: genBtn
            anchors { verticalCenter: parent.verticalCenter; horizontalCenter: parent.horizontalCenter }
            width: Math.min(parent.width - Style.spacingL * 2, page.maxContentWidth)
            busy: page.busy
            enabled: !page.busy && page.quota.remaining > 0
            text: page.quota.remaining > 0 ? Lang.tr("Generate invite link")
                                           : Lang.tr("No invites left")
            onClicked: page.generate()
        }
    }
}
