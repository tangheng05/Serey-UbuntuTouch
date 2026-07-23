import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"

Page {
    id: page

    header: PageHeader {
        title: Lang.tr("Create account")
    }

    Flickable {
        anchors { top: page.header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentWidth: width
        contentHeight: form.height + Style.spacingL * 2
        clip: true

        Column {
            id: form
            width: Math.min(parent.width - Style.spacingL * 2, units.gu(50))
            anchors.horizontalCenter: parent.horizontalCenter
            y: Style.spacingL
            spacing: Style.spacingM

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: units.gu(9); height: width
                source: Qt.resolvedUrl("../../assets/serey-logo.png")
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }

            Column {
                width: parent.width
                spacing: Style.spacingXs
                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Lang.tr("Create account")
                    font.pixelSize: Style.fontTitle
                    font.weight: Font.DemiBold
                    font.family: Style.fontFor(text)
                    color: Style.textTitle
                }
                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Lang.tr("Choose how you'd like to sign up")
                    font.pixelSize: Style.fontRegular
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                    wrapMode: Text.WordWrap
                }
            }

            Item { width: 1; height: Style.spacingS }

            PrimaryButton {
                width: parent.width
                text: Lang.tr("Create Serey account")
                onClicked: page.pageStack.push(Qt.resolvedUrl("SignupPage.qml"))
            }
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Lang.tr("We keep your keys safe, sign in with a password.")
                font.pixelSize: Style.fontXSmall
                font.family: Style.fontFor(text)
                color: Style.textSecondary
                wrapMode: Text.WordWrap
            }

            Row {
                width: parent.width
                spacing: Style.spacingS
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: (parent.width - orLabel.width - Style.spacingS * 2) / 2; height: units.dp(1); color: Style.divider }
                Label {
                    id: orLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: Lang.tr("or")
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                }
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: (parent.width - orLabel.width - Style.spacingS * 2) / 2; height: units.dp(1); color: Style.divider }
            }

            SecondaryButton {
                width: parent.width
                text: Lang.tr("Self-custody")
                onClicked: page.pageStack.push(Qt.resolvedUrl("SelfCustodySignupPage.qml"))
            }
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Lang.tr("You hold your own private key. It can't be recovered if lost.")
                font.pixelSize: Style.fontXSmall
                font.family: Style.fontFor(text)
                color: Style.textSecondary
                wrapMode: Text.WordWrap
            }
        }
    }
}
