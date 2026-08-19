import QtQuick 2.7
import QtQuick.Window 2.2
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../services/HiddenPosts.js" as HiddenPosts
import "../services/YouTube.js" as YouTube

AbstractButton {
    id: root
    property var video: ({})
    readonly property var v: video ? video : ({})
    // Off in a grid; divider is for vertical-list usage only
    property bool showDivider: true

    signal authorClicked()
    signal moreClicked()

    readonly property bool isOwn: Session.isLoggedIn && !!(v.author) && v.author === Session.username

    // Compact anchored dropdown (mirrors PostCard's cardMenu); desktop only, phone/tablet use the full sheet
    property bool compactMenu: Config.desktopMode
    property bool menuOpen: false
    Component.onDestruction: root.menuOpen = false

    function _isDirectFile(u) { return /\.(mp4|webm|m4v|mov)(\?|$)/i.test(u || ""); }
    readonly property string _remoteUrl: {
        if (v.platform === "SEREY") return v.videoLink || v.embedUrl || "";
        if (root._isDirectFile(v.videoLink)) return v.videoLink;
        if (root._isDirectFile(v.embedUrl)) return v.embedUrl;
        return "";
    }
    readonly property string _youtubeId: {
        if (v.platform === "YOUTUBE" && (v.videoId || "").length === 11) return v.videoId;
        var s = (v.embedUrl || "") + " " + (v.videoLink || "");
        var m = s.match(/(?:youtube\.com\/(?:embed\/|watch\?v=)|youtu\.be\/)([A-Za-z0-9_-]{11})/);
        return m ? m[1] : "";
    }
    readonly property bool _isYouTube: v.platform === "YOUTUBE" && root._youtubeId.length > 0
    readonly property bool _canDownload: root._remoteUrl.length > 0 || root._isYouTube
    readonly property bool _dlSaved: (Downloads.rev, Downloads.isSaved(v.permlink || ""))
    // this card's in-flight download
    readonly property var _dlActive: (Downloads.rev, Downloads.activeFor(v.permlink || ""))
    readonly property bool _dlBusy: !!root._dlActive || root._ytExtracting
    property bool _ytExtracting: false

    function toggleDownload() {
        var pl = v.permlink || "";
        if (pl.length === 0 || root._ytExtracting) return;
        if (root._dlSaved) { Downloads.remove(pl); return; }
        if (root._remoteUrl.length > 0) {
            Downloads.start(v, root._remoteUrl);
            return;
        }
        if (root._isYouTube) {
            root._ytExtracting = true;
            Toast.show(Lang.tr("Preparing download…"));
            YouTube.extract(root._youtubeId, function (result, errMsg) {
                root._ytExtracting = false;
                if (result && result.url) {
                    Downloads.start(v, result.url);
                } else {
                    Toast.error(Lang.tr("This YouTube video can't be downloaded."));
                }
            });
        }
    }

    // The "..." button, so a sheet opened from this card's menu drops under it.
    readonly property alias menuAnchor: moreBtn

    function menuItems() {
        var items = [];
        if (root._canDownload) {
            items.push({ icon: root._dlSaved ? "tick" : "save",
                         label: root._dlSaved ? Lang.tr("Remove download") : Lang.tr("Save video offline"),
                         action: "toggleDownload" });
            items.push({ divider: true });
        }
        if (root.isOwn) {
            items.push({ icon: "edit", label: Lang.tr("Edit caption"), action: "editCaption" });
            items.push({ icon: "delete", label: Lang.tr("Delete video"), danger: true, action: "delete" });
        } else {
            items.push({ icon: "close", label: Lang.tr("Hide this video"), action: "hide" });
            items.push({ icon: "dialog-warning-symbolic", label: Lang.tr("Report video"), action: "report" });
        }
        return items;
    }

    function runMenuAction(action) {
        if (action === "toggleDownload") root.toggleDownload();
        else if (action === "editCaption") PostActions.open(root.v, "video", 4);
        else if (action === "delete") PostActions.open(root.v, "video", 2);
        else if (action === "hide") {
            HiddenPosts.hide(v.permlink || "");
            PostActions.hideRequested(v.author || "", v.permlink || "");
        }
        else if (action === "report") PostActions.open(root.v, "video", 1);
    }

    // Reparent onto the window while open so the menu isn't clipped by the list row (see PostCard)
    readonly property Item _menuOverlayParent: (root.menuOpen && root.Window.window)
        ? root.Window.window.contentItem : root
    readonly property point _moreBtnBottomRight: (root.menuOpen && moreBtn)
        ? moreBtn.mapToItem(root._menuOverlayParent, moreBtn.width, moreBtn.height) : Qt.point(0, 0)

    // Priming moved to the swipe action itself: a card shows no follow state, so doing it here
    // cost a /follow/status request per author while scrolling.

    // VideoCard itself is the single tab-stop so its ring shows; child area is non-focusable
    activeFocusOnTab: true

    onPressAndHold: root.moreClicked()

    Keys.onPressed: {
        if (event.key === Qt.Key_Menu ||
            (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
            root.moreClicked();
            event.accepted = true;
        }
    }

    width: parent ? parent.width : units.gu(40)
    implicitHeight: column.height + Style.spacingM + Style.spacingS + (showDivider ? units.dp(1) : 0)
    height: implicitHeight

    Column {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: Style.spacingM
            rightMargin: Style.spacingM
            topMargin: Style.spacingM
        }
        spacing: Style.spacingS

        // Thumbnail: large rounded, no play overlay
        Item {
            width: parent.width
            height: width * 0.56

            RoundedThumb {
                anchors.fill: parent
                source: v.localThumb || v.thumbnail || ""
                decodeWidth: root.width > units.gu(70) ? units.gu(90) : units.gu(45)
            }

            Rectangle {
                // categories is ListModel-wrapped here; use the mapper's scalar copy instead.
                visible: (v.primaryCategory || "") !== ""
                anchors { top: parent.top; right: parent.right; topMargin: Style.spacingS; rightMargin: Style.spacingS }
                width: vidCatLabel.width + Style.spacingM
                height: units.gu(3)
                radius: Style.pillRadius
                color: Style.accentRed
                Label {
                    id: vidCatLabel
                    anchors.centerIn: parent
                    text: v.primaryCategory || ""
                    font.pixelSize: Style.fontSmall
                    font.weight: Font.DemiBold
                    color: Style.textOnBrand
                }
            }
        }

        Row {
            width: parent.width
            spacing: Style.spacingS

            Item {
                width: units.gu(4.5); height: width
                anchors.top: parent.top

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Style.avatarTint(v.author || "")
                    visible: (v.authorImage || "") === ""

                    Label {
                        anchors.centerIn: parent
                        text: (v.author || "?").charAt(0).toUpperCase()
                        font.pixelSize: Style.fontMedium
                        font.bold: true
                        color: Style.brand
                    }
                }

                CircleImage {
                    anchors.fill: parent
                    source: v.authorImage || ""
                    decode: units.gu(9)
                    visible: (v.authorImage || "") !== ""
                }

                MouseArea { anchors.fill: parent; onClicked: root.authorClicked(); onPressAndHold: root.moreClicked() }
            }

            Column {
                width: parent.width - units.gu(4.5) - Style.spacingS - moreBtn.width - Style.spacingS
                    - (downloadedIcon.visible ? downloadedIcon.width + Style.spacingS : 0)
                spacing: units.dp(2)

                Label {
                    width: parent.width
                    text: v.title || ""
                    font.pixelSize: Style.fontRegular
                    font.weight: Font.DemiBold
                    font.family: Style.fontFor(text)
                    color: Style.textPrimary
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
                Label {
                    width: parent.width
                    text: v.author || ""
                    font.pixelSize: Style.fontSmall
                    color: Style.textSecondary
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                id: downloadedIcon
                anchors.top: parent.top
                width: dlLabel.width + Style.spacingM
                height: units.gu(2.6)
                visible: (SavedPosts.rev, Downloads.rev, SavedPosts.isSaved(v.permlink) || Downloads.isSaved(v.permlink))
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
                anchors.top: parent.top
                width: units.gu(3.5); height: units.gu(3.5)
                onClicked: root.compactMenu ? (root.menuOpen = !root.menuOpen) : root.moreClicked()

                // dots -> progress ring while downloading
                CircularProgress {
                    anchors.centerIn: parent
                    visible: !!root._dlActive
                    value: root._dlActive ? root._dlActive.progress : 0
                }

                ActivityIndicator {
                    anchors.centerIn: parent
                    visible: root._ytExtracting
                    running: root._ytExtracting
                }

                Column {
                    anchors.centerIn: parent
                    visible: !root._dlBusy
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
    }

    Rectangle {
        visible: root.showDivider
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: units.dp(1)
        color: Style.divider
    }

    // Pointer parity: right-click opens context menu; must NOT be a tab-stop or it hides the ring
    ContextActionArea {
        activeFocusOnTab: false
        onTriggered: root.moreClicked()
    }

    // VideoCard is a FocusScope and takes focus itself, so draw the ring here (unlike PostCard)
    Rectangle {
        anchors.fill: parent
        anchors.margins: units.dp(1)
        color: "transparent"
        visible: root.activeFocus
        border.width: units.dp(2)
        border.color: Style.brand
        radius: units.gu(0.5)
        z: 100
    }

    // Dismiss on outside click; fills the whole window while open once reparented
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
        // Cap against the overlay, not the card: gu(20) truncated translated labels.
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

            Rectangle { visible: !root.isOwn; width: parent.width; height: units.dp(1); color: Style.divider }
            // No "block" glyph in the Suru icon set (same reason PostActionSheet draws its own).
            AbstractButton {
                visible: !root.isOwn
                width: parent.width
                height: units.gu(5.5)
                onClicked: { root.menuOpen = false; PostActions.open(root.v, "video", 3); }
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
                        text: Lang.tr("Block %1").arg(v.author || "")
                        font.pixelSize: Style.fontSmall
                        color: Style.danger
                    }
                }
            }
        }
    }
}
