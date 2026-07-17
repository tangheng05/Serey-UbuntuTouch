import QtQuick 2.7
import QtGraphicalEffects 1.0
import Lomiri.Components 1.3
import "../Theme"
import "../Session"

AbstractButton {
    id: root
    property var video: ({})
    readonly property var v: video ? video : ({})
    // Off in a grid — divider is for vertical-list usage only
    property bool showDivider: true

    signal authorClicked()
    signal moreClicked()

    // Primes the shared follow-state store so a swiped-open Follow action (VideoPage's
    // trailing ListItemActions) can render its already-following color immediately.
    onVChanged: {
        if (Session.isLoggedIn && v.author && v.author !== Session.username)
            FollowStore.load(Config.baseUrl, Session.username, v.author);
    }

    // Keyboard: VideoCard IS the focus owner (an AbstractButton / FocusScope), so
    // make it the single tab-stop — its own ring then shows. Its ContextActionArea
    // child is set non-focusable below (its activeFocus doesn't propagate through
    // this FocusScope the way it does inside PostCard's plain Item, which is why
    // the ring was invisible here). Enter activates natively (-> clicked); MENU
    // opens the ••• context menu.
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

        // Thumbnail — large rounded, no play overlay
        Item {
            width: parent.width
            height: width * 0.56

            Rectangle {
                id: thumbBg
                anchors.fill: parent
                radius: Style.thumbRadius
                color: Style.iconBackground
            }

            // Double-buffered like PostCard's cover: the hidden loader fetches the
            // new source while thumbImg keeps the last-good frame (dimmed), so a
            // row-content swap (tab/community switch) never blanks to black while
            // the phone re-downloads an evicted image.
            Image {
                id: thumbLoader
                anchors.fill: parent
                source: v.localThumb || v.thumbnail || ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                // HIG scaling: snap the decode size to a breakpoint instead of `width * N` so the image isn't re-rasterized on every width change.
                sourceSize.width: root.width > units.gu(70) ? units.gu(90) : units.gu(45)
                visible: false
                onStatusChanged: {
                    if (status === Image.Ready) thumbImg.source = source;
                    else if (status === Image.Error || String(source).length === 0) thumbImg.source = "";
                }
            }
            Image {
                id: thumbImg
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: thumbLoader.sourceSize.width
                visible: false
                // Fade fully out while the loader replaces a stale frame — a dimmed
                // ghost of the previous content read as the wrong thumbnail (see
                // PostCard). The smooth fade is what distinguishes this from the
                // original instant-cut-to-black bug.
                readonly property bool transitioning:
                    thumbLoader.status === Image.Loading && status === Image.Ready
                Behavior on opacity { NumberAnimation { duration: 200 } }
                opacity: status === Image.Ready ? (transitioning ? 0.0 : 1.0) : 0.0
            }

            Rectangle {
                id: thumbMask
                anchors.fill: parent
                radius: Style.thumbRadius
                visible: false
            }

            OpacityMask {
                anchors.fill: parent
                source: thumbImg
                maskSource: thumbMask
                opacity: thumbImg.opacity
            }

            Rectangle {
                // categories is ListModel-wrapped here — use the mapper's scalar copy instead.
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

        // Info: avatar + title/author
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

            // Downloaded-for-offline indicator.
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
                onClicked: root.moreClicked()

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
    }

    // Divider between cards
    Rectangle {
        visible: root.showDivider
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: units.dp(1)
        color: Style.divider
    }

    // Pointer parity: right-click opens the ••• context menu. Keyboard focus +
    // Enter/MENU are handled by the AbstractButton root above (single focus
    // owner), so this must NOT be a tab-stop or it competes and hides the ring.
    ContextActionArea {
        activeFocusOnTab: false
        onTriggered: root.moreClicked()
    }

    // Keyboard-focus ring. VideoCard is an AbstractButton (a FocusScope), so it
    // takes focus itself instead of letting its child show a ring like PostCard
    // (a plain Item) does — draw the ring here so keyboard focus is visible and
    // matches the blog card. root.activeFocus is true whether the button or its
    // ContextActionArea child holds focus.
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
}
