import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/PlatformService.js" as PlatformService

// Video posting permission for the managed community
Page {
    id: page

    // Adapt, not scale: caps to a centered column on wide windows
    readonly property real maxContentWidth: units.gu(60)

    header: PageHeader {
        title: Lang.tr("Videos")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.pageStack.pop() }
        ]
    }

    // --- Posting permission (only_me | everyone) ---
    property string videoMode: "only_me"
    property bool permBusy: false

    function modeLabel(mode) { return mode === "everyone" ? Lang.tr("Everyone") : Lang.tr("Only me") }
    readonly property var permOptions: [
        { mode: "only_me",  label: Lang.tr("Only me"),  desc: Lang.tr("Only you and your managers can post.") },
        { mode: "everyone", label: Lang.tr("Everyone"), desc: Lang.tr("Anyone can post videos.") }
    ]

    function loadPostingPermission() {
        var info = Config.communityInfoFor(Config.managedCommunityId)
        page.videoMode = (info && info.videoAllowPost) ? "everyone" : "only_me"
    }

    function setVideoMode(mode) {
        if (permBusy || mode === videoMode) return
        permBusy = true
        var allow = (mode === "everyone")
        PlatformService.updateVideoAllowPost(Config.baseUrl, Session.token, Config.managedCommunityId, allow,
            function () {
                page.permBusy = false
                page.videoMode = mode
                Toast.success(Lang.tr("Posting permission updated."))
            },
            function (err) {
                page.permBusy = false
                Toast.error((err && err.message) || Lang.tr("Action failed."))
            })
    }

    Component.onCompleted: {
        page.loadPostingPermission()
    }

    Component {
        id: permPickerPage
        Page {
            id: permPage
            header: PageHeader {
                title: Lang.tr("Video posting")
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
                            color: page.videoMode === modelData.mode ? Style.success : "transparent"
                            border.width: page.videoMode === modelData.mode ? 0 : units.dp(1.5)
                            border.color: Style.dotInactive
                            Rectangle {
                                anchors.centerIn: parent
                                visible: page.videoMode === modelData.mode
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
                            onClicked: page.setVideoMode(modelData.mode)
                        }
                    }
                }
            }
        }
    }

    ListView {
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
                    text: Lang.tr("Video posting")
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
                        text: page.modeLabel(page.videoMode)
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

            Item { width: 1; height: Style.spacingL }
        }
    }
}
