import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

Rectangle {
    id: coin

    property string value: ""

    visible: value.length > 0
    implicitWidth: row.width + Style.spacingM
    implicitHeight: units.gu(3)
    radius: Style.pillRadius
    color: Style.iconBackground

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Style.spacingXs

        Image {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.coinIconSize
            height: Style.coinIconSize
            source: Qt.resolvedUrl("../../assets/serey-currency.png")
            // Cap decoded size (renders on every card/action bar) per the app-wide image-memory convention; 2x the box for crisp hiDPI.
            sourceSize.width: Style.coinIconSize * 2
            sourceSize.height: Style.coinIconSize * 2
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: coin.value
            font.pixelSize: Style.fontSmall
            font.weight: Font.DemiBold
            color: Style.textPrimary
        }
    }
}
