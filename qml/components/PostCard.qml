import QtQuick 2.7
import QtQuick.Window 2.2
import QtQuick.Layouts 1.3
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../services/VoteService.js" as VoteService
import "../services/PostService.js" as PostService
import "../services/HiddenPosts.js" as HiddenPosts

Item {
    id: root

    property var post: ({})
    // Guard: the delegate may rebind `post` to undefined while the model is cleared/recycled; `p` is always a safe object to read from.
    readonly property var p: post ? post : ({})

    readonly property bool isOwnPost: Session.isLoggedIn && (p.author || "") !== "" && p.author === Session.username
    readonly property bool isSaved: (SavedPosts.rev, SavedPosts.isSaved(p.permlink || ""))
    readonly property string shareUrl: (p.author && p.permlink)
        ? ("https://serey.io/authors/" + p.author + "/" + p.permlink) : ""

    // Publishing platform, hidden once you've drilled into that same community
    // (redundant chrome on every card). Compared by id, never by name: our
    // "Global" source is the id-0 no-filter pseudo-source, while a real community
    // is also titled "Global" (id 1), so names collide and blank the whole feed.
    readonly property string platformName: {
        var c = p.community || "";
        if (c === "") return "";
        return (Config.communityId > 0 && Number(p.communityId) === Config.communityId) ? "" : c;
    }

    // Logo for the platform pill; "" drops it back to a letter avatar.
    readonly property string platformIcon: root.platformName === ""
                                           ? "" : Config.communityIconFor(p.communityId)

    // Global state, so the card switches Config itself instead of signalling the page.
    function openPlatform() {
        if (!Config.selectCommunityById(p.communityId))
            Toast.error(Lang.tr("That platform isn't available yet."));
    }

    // Feed rows only carry an excerpt, so saving offline needs the full post first
    function toggleSaved() {
        if (root.isSaved) { SavedPosts.remove(p.permlink); return; }
        var author = p.author, permlink = p.permlink;
        PostService.detail(Config.baseUrl, author, permlink, Session.token,
            function (result) { if (result && result.post) SavedPosts.save(result.post); },
            function (err) { Toast.error((err && err.message) ? err.message : Lang.tr("Couldn't save for offline.")); });
    }

    // moreBtn's compact dropdown; report/delete/block still route through PostActionSheet. Desktop only — phone/tablet use the full sheet.
    property bool compactMenu: Config.desktopMode
    property bool menuOpen: false

    // The "..." button, so a sheet opened from this card's menu drops under it.
    readonly property alias menuAnchor: moreBtn

    function menuItems() {
        var items = [
            { icon: "stock_link", label: Lang.tr("Copy link"), action: "copyLink" },
            { icon: "external-link", label: Lang.tr("Open in browser"), action: "openBrowser" },
            { icon: root.isSaved ? "tick" : "save",
              label: root.isSaved ? Lang.tr("Remove from saved") : Lang.tr("Save for offline"),
              action: "toggleSaved" },
            // Content actions above, negative ones below; matches VideoCard.
            { divider: true }
        ];
        if (root.isOwnPost) {
            items.push({ icon: "edit", label: Lang.tr("Edit post"), action: "edit" });
            items.push({ icon: "delete", label: Lang.tr("Delete post"), danger: true, action: "delete" });
        } else {
            items.push({ icon: "close", label: Lang.tr("Hide this post"), action: "hide" });
            items.push({ icon: "dialog-warning-symbolic", label: Lang.tr("Report post"), action: "report" });
        }
        return items;
    }

    function runMenuAction(action) {
        if (action === "copyLink") { Clipboard.push(root.shareUrl); Toast.show(Lang.tr("Link copied")); }
        else if (action === "openBrowser") Qt.openUrlExternally(root.shareUrl);
        else if (action === "toggleSaved") root.toggleSaved();
        else if (action === "edit") PostActions.editRequested(root.p);
        else if (action === "delete") PostActions.open(root.p, "blog", 2);
        else if (action === "hide") {
            HiddenPosts.hide(root.p.permlink || "");
            PostActions.hideRequested(root.p.author || "", root.p.permlink || "");
        }
        else if (action === "report") PostActions.open(root.p, "blog", 1);
    }

    // cardMenu reparents onto the window while open, so force-close it before recycling
    Component.onDestruction: root.menuOpen = false

    signal clicked()
    signal requireLogin()
    signal moreClicked()
    signal authorClicked()

    width: parent ? parent.width : units.gu(45)
    implicitHeight: col.height

    // The feed ListModel (dynamicRoles) wraps array fields as nested ListModels with `count` but no indexOf/length; these helpers read either shape safely.
    function _len(v) {
        if (!v) return 0;
        if (typeof v.length === "number") return v.length;
        if (typeof v.count === "number") return v.count;
        return 0;
    }

    // No follow priming here: the card shows no follow state, and doing it per delegate meant
    // a /follow/status request per author while scrolling. The swipe action primes itself.
    onPChanged: _syncVoteBar()

    // ListModel.set() mutates `p` in place so onPChanged never fires; watch values directly instead
    readonly property int _pVotes: p.votes || 0
    readonly property string _pPayout: p.payout || ""
    readonly property string _pPermlink: p.permlink || ""
    on_PVotesChanged: _syncVoteBar()
    on_PPayoutChanged: _syncVoteBar()
    on_PPermlinkChanged: _syncVoteBar()

    // Children exist by now, so a row whose values arrived before the bar was built still gets counts
    Component.onCompleted: _syncVoteBar()

    function _syncVoteBar() {
        if (!cardVoteBar) return;
        var cached = VoteService.getCached(p.author || "", p.permlink || "");
        if (cached) {
            cardVoteBar.upvoted = cached.upvoted;
            cardVoteBar.flagged = cached.flagged;
            cardVoteBar.votes = cached.votes;
            if (cached.payout) cardVoteBar.payout = cached.payout;
        } else {
            var me = Session.username || "";
            cardVoteBar.upvoted = me.length > 0 && (p.voterStr || "").indexOf("," + me + ",") >= 0;
            cardVoteBar.flagged = me.length > 0 && (p.flaggerStr || "").indexOf("," + me + ",") >= 0;
            // Re-assert count/payout imperatively since a prior cached assignment breaks the QML binding on this pooled delegate when recycled.
            cardVoteBar.votes = p.votes || 0;
            cardVoteBar.payout = p.payout || "";
        }
    }

    Column {
        id: col
        width: parent.width

        Item { width: 1; height: Style.spacingS }

        RowLayout {
            height: units.gu(6)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.spacingM
            anchors.rightMargin: Style.spacingM
            spacing: Style.spacingS

            Item {
                id: avatar
                Layout.preferredWidth: units.gu(4.25)
                Layout.preferredHeight: units.gu(4.25)
                Layout.fillHeight: false
                Layout.alignment: Qt.AlignVCenter

                // Letter fallback (shown whenever there's no author image)
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Style.avatarTint(p.author || "")
                    visible: (p.authorImage || "") === ""

                    Label {
                        anchors.centerIn: parent
                        text: (p.author || "?").charAt(0).toUpperCase()
                        font.pixelSize: Style.fontMedium
                        font.bold: true
                        color: Style.brand
                    }
                }

                // Photo, masked to a true circle (Rectangle.clip ignores radius).
                CircleImage {
                    anchors.fill: parent
                    source: p.authorImage || ""
                    decode: units.gu(9)
                    visible: (p.authorImage || "") !== ""
                }

                MouseArea { anchors.fill: parent; onClicked: root.authorClicked(); onPressAndHold: root.moreClicked() }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                Label {
                    Layout.fillWidth: true
                    text: p.author || ""
                    font.pixelSize: Style.fontSmall
                    font.weight: Font.DemiBold
                    color: Style.textPrimary
                    elide: Text.ElideRight
                    // Label stretches to fill the header, so tap only the painted name, not the blank space after it
                    MouseArea {
                        anchors.left: parent.left
                        height: parent.height
                        width: Math.min(parent.width, parent.implicitWidth)
                        onClicked: root.authorClicked()
                        onPressAndHold: root.moreClicked()
                    }
                }
                Row {
                    spacing: units.gu(0.75)

                    // Attribution reads as a badge rather than a second name, so it
                    // stays subordinate to the author on the line above.
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.platformName !== ""
                        width: platformRow.width + units.gu(1.25)
                        height: units.gu(2.25)
                        radius: height / 2
                        color: platformTap.pressed
                                 ? Qt.rgba(Style.brand.r, Style.brand.g, Style.brand.b, 0.16)
                                 : Style.iconBackground

                        Row {
                            id: platformRow
                            anchors.centerIn: parent
                            spacing: units.gu(0.5)

                            Item {
                                anchors.verticalCenter: parent.verticalCenter
                                width: units.gu(1.5); height: units.gu(1.5)

                                // Not every community has uploaded a logo; fall back to the
                                // initial, same letter-avatar convention as the author above.
                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: Style.avatarTint(root.platformName)
                                    visible: root.platformIcon === ""

                                    Label {
                                        anchors.centerIn: parent
                                        text: root.platformName.charAt(0).toUpperCase()
                                        font.pixelSize: units.gu(1)
                                        font.family: Style.fontFor(text)
                                        font.bold: true
                                        color: Style.brand
                                    }
                                }

                                CircleImage {
                                    anchors.fill: parent
                                    visible: root.platformIcon !== ""
                                    source: root.platformIcon
                                    decode: units.gu(3)
                                }
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                // Capped so a long platform name can't push the time off the row.
                                width: Math.min(implicitWidth, root.width / 3)
                                text: root.platformName
                                font.pixelSize: Style.fontXSmall
                                font.family: Style.fontFor(root.platformName)
                                font.weight: Font.DemiBold
                                color: Style.brand
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: platformTap
                            anchors.fill: parent
                            onClicked: root.openPlatform()
                        }
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Style.formatTimeAgo(p.date || "")
                        font.pixelSize: Style.fontXSmall
                        color: Style.textSecondary
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: dlLabel.width + Style.spacingM
                Layout.preferredHeight: units.gu(2.6)
                Layout.alignment: Qt.AlignVCenter
                visible: (SavedPosts.rev, Downloads.rev, SavedPosts.isSaved(p.permlink) || Downloads.isSaved(p.permlink))
                radius: Style.pillRadius
                color: Style.iconBackground
                border.width: units.dp(1)
                border.color: Style.textSecondary

                Label {
                    id: dlLabel
                    anchors.centerIn: parent
                    text: Lang.tr("Downloaded")
                    font.pixelSize: Style.fontXSmall
                    font.weight: Font.DemiBold
                    color: Style.textSecondary
                }
            }

            AbstractButton {
                id: moreBtn
                Layout.preferredWidth: units.gu(3.5)
                Layout.preferredHeight: units.gu(3.5)
                Layout.alignment: Qt.AlignVCenter
                onClicked: root.compactMenu ? (root.menuOpen = !root.menuOpen) : root.moreClicked()

                Column {
                    anchors.centerIn: parent
                    spacing: units.dp(3)
                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            width: units.dp(4); height: units.dp(4)
                            radius: width / 2
                            color: Style.textSecondary
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }
            }
        }

        // Title uses Text.Wrap, not WordWrap, since Khmer has no spaces between words and WordWrap can't find a break point.
        Label {
            visible: (p.title || "") !== ""
            width: parent.width - Style.spacingM * 2
            x: Style.spacingM
            text: p.title || ""
            font.pixelSize: Style.fontMedium
            font.family: Style.fontFor(text)
            color: Style.textPrimary
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            MouseArea { anchors.fill: parent; onClicked: root.clicked(); onPressAndHold: root.moreClicked() }
        }

        Item { width: 1; height: Style.spacingS }

        Item {
            id: cover
            visible: (p.thumbnail || "") !== ""
            width: parent.width - Style.spacingM * 2
            x: Style.spacingM
            height: visible ? width * 0.56 : 0

            RoundedThumb {
                anchors.fill: parent
                source: p.thumbnail || ""
                autoTransform: true
                decodeWidth: root.width > units.gu(70) ? units.gu(90) : units.gu(45)
            }

            Rectangle {
                // categories is ListModel-wrapped here; use the mapper's scalar copy instead.
                visible: (p.primaryCategory || "") !== ""
                anchors { top: parent.top; right: parent.right; topMargin: Style.spacingS; rightMargin: Style.spacingS }
                width: catLabel.width + Style.spacingM
                height: units.gu(3)
                radius: Style.pillRadius
                color: Style.accentRed
                Label {
                    id: catLabel
                    anchors.centerIn: parent
                    text: p.primaryCategory || ""
                    font.pixelSize: Style.fontSmall
                    font.weight: Font.DemiBold
                    color: Style.textOnBrand
                }
            }

            MouseArea { anchors.fill: parent; onClicked: root.clicked(); onPressAndHold: root.moreClicked() }
        }

        Label {
            visible: (p.thumbnail || "") === "" && (p.excerpt || "") !== ""
            width: parent.width - Style.spacingM * 2
            x: Style.spacingM
            text: p.excerpt || ""
            font.pixelSize: Style.fontRegular
            font.family: Style.fontFor(text)
            color: Style.textSecondary
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            MouseArea { anchors.fill: parent; onClicked: root.clicked(); onPressAndHold: root.moreClicked() }
        }

        // Bottom margin below the thumbnail (always visible, unlike the vote row)
        Item { width: 1; height: Style.spacingS }

        // Vote/comment/share row shown in narrow mode only; wide mode shows these in the detail column instead.
        VoteBar {
            id: cardVoteBar
            visible: !Config.wideMode
            width: parent.width - Style.spacingM * 2
            x: Style.spacingM
            author: p.author || ""
            permlink: p.permlink || ""
            voteType: "post"
            onChain: p.postToBlockchain !== false
            createdAt: p.date || ""
            votes: p.votes || 0
            // Rebuilt from voterStr scalar: dynamicRoles ListModel stringifies string arrays as garbage
            voters: (p.voterStr || "").split(",").filter(function (n) { return n.length > 0; })
            flaggers: root._len(p.flaggers)
            comments: p.comments || 0
            payout: p.payout || ""
            onRequireLogin: root.requireLogin()
            onCommentRequested: root.clicked()
        }

        Item { width: 1; height: Style.spacingS; visible: !Config.wideMode }

        Rectangle { width: parent.width; height: units.dp(1); color: Style.divider }
    }

    // Pointer/keyboard parity: right-click/MENU opens overflow context menu, Enter opens post
    ContextActionArea {
        onTriggered: root.moreClicked()
        onActivated: root.clicked()
    }

    // Compact anchored dropdown for moreBtn; reparent onto the window while open so the menu isn't clipped by the list row's stacking context
    readonly property Item _menuOverlayParent: (root.menuOpen && root.Window.window)
        ? root.Window.window.contentItem : root
    readonly property point _moreBtnBottomRight: (root.menuOpen && moreBtn)
        ? moreBtn.mapToItem(root._menuOverlayParent, moreBtn.width, moreBtn.height) : Qt.point(0, 0)

    // Dismiss on outside click; fills the whole window while open, not just this card
    MouseArea {
        parent: root._menuOverlayParent
        visible: root.menuOpen
        z: 999
        anchors.fill: parent
        onClicked: root.menuOpen = false
    }

    Rectangle {
        id: cardMenu
        parent: root._menuOverlayParent
        visible: root.menuOpen
        z: 1000
        x: Math.min(root._moreBtnBottomRight.x - width, root._menuOverlayParent.width - width - Style.spacingXs)
        y: root._moreBtnBottomRight.y + Style.spacingXs
        // Cap against the overlay, not the card: gu(20) truncated translated labels,
        // and a right-anchored menu may extend past the card without looking wrong.
        width: Math.min(units.gu(30), root._menuOverlayParent.width - Style.spacingM * 2)
        height: cardMenuCol.height
        radius: Style.cardRadius
        color: Style.surface
        border.width: units.dp(1)
        border.color: Style.divider

        Column {
            id: cardMenuCol
            width: parent.width

            Repeater {
                // {divider:true} | {icon, label, danger, action}
                model: root.menuItems()
                delegate: Item {
                    width: cardMenuCol.width
                    height: modelData.divider ? units.dp(1) : units.gu(5.5)

                    Rectangle {
                        visible: !!modelData.divider
                        anchors.fill: parent
                        color: Style.divider
                    }

                    AbstractButton {
                        visible: !modelData.divider
                        anchors.fill: parent
                        onClicked: { root.menuOpen = false; root.runMenuAction(modelData.action); }
                        Row {
                            anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                            spacing: Style.spacingM
                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                width: units.gu(2.2); height: width
                                name: modelData.icon || ""
                                color: modelData.danger ? Style.danger : Style.textPrimary
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                // Bounded + elided so no translation can spill past the panel.
                                width: Math.max(0, parent.width - units.gu(2.2) - parent.spacing)
                                elide: Text.ElideRight
                                text: modelData.label || ""
                                font.pixelSize: Style.fontSmall
                                font.family: Style.fontFor(text)   // labels carry usernames
                                color: modelData.danger ? Style.danger : Style.textPrimary
                            }
                        }
                    }
                }
            }

            Rectangle { visible: !root.isOwnPost; width: parent.width; height: units.dp(1); color: Style.divider }
            // No "block" glyph in the Suru icon set (same reason PostActionSheet draws its own).
            AbstractButton {
                visible: !root.isOwnPost
                width: parent.width
                height: units.gu(5.5)
                onClicked: { root.menuOpen = false; PostActions.open(root.p, "blog", 3); }
                Row {
                    anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                    spacing: Style.spacingM
                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(2.2); height: width
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"
                            border.width: units.dp(1.5)
                            border.color: Style.danger
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width * 0.7; height: units.dp(1.5)
                            color: Style.danger
                            rotation: 45
                        }
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Lang.tr("Block %1").arg(root.p.author || "")
                        font.pixelSize: Style.fontSmall
                        color: Style.danger
                    }
                }
            }
        }
    }

}
