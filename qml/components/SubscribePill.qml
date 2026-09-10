import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"

// Subscribe / Subscribed toggle button. Filled while unsubscribed, outlined once joined.
AbstractButton {
    id: pill

    property bool subscribed: false

    height: units.gu(4.5)

    Rectangle {
        anchors.fill: parent
        radius: Style.pillRadius
        color: pill.subscribed ? "transparent"
             : pill.pressed ? Style.brandDark : Style.brand
        border.width: pill.subscribed ? units.dp(1.5) : 0
        border.color: Style.divider
        Behavior on color { ColorAnimation { duration: 120 } }

        Label {
            anchors.centerIn: parent
            text: pill.subscribed ? Lang.tr("Subscribed") : Lang.tr("Subscribe")
            font.pixelSize: Style.fontSmall
            font.weight: Font.DemiBold
            font.family: Style.fontFor(text)
            color: pill.subscribed ? Style.textSecondary : Style.textOnBrand
        }
    }
}
