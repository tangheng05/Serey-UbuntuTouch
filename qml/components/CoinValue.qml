import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"

Rectangle {
    id: coin

    property string value: ""
    // Narrow hosts (detail side rails) let the pill shorten itself when the row can't fit
    // the full string. Elsewhere the value is always rendered in full.
    property bool compact: false
    // What the host can spare for the pill; -1 means "unconstrained".
    property real availableWidth: -1

    // Icon plus both paddings; the label gets whatever is left of coin.width.
    readonly property real _chrome: Style.coinIconSize + Style.spacingXs + Style.spacingS * 2

    readonly property string _num: coin.value.replace(/\s*SEREY\s*$/i, "")
    readonly property string _unit: coin.value.length > coin._num.length
        ? coin.value.substring(coin._num.length) : ""

    // Truncates rather than rounds, so a shortened pill never reads higher than the payout.
    function _dp(n) {
        var dot = coin._num.indexOf(".");
        if (dot < 0) return coin._num;
        return n > 0 ? coin._num.substring(0, dot + 1 + n) : coin._num.substring(0, dot);
    }

    // Chosen rendering, written by _reselect(). Plain properties, not bindings: measuring
    // candidates re-enters any binding that reads TextMetrics.width, which Qt reports as a
    // binding loop even though the result is right.
    property string _text: coin.value
    property real _textWidth: 0

    // Rungs, widest first. Decimals go before the unit word does: "2683.3 SEREY" still says
    // what the number is, "2683.304" alone doesn't.
    function _reselect() {
        var rungs = coin.compact
            ? [ coin.value, coin._dp(2) + coin._unit, coin._dp(1) + coin._unit,
                coin._dp(0) + coin._unit, coin._num ]
            : [ coin.value ];
        // dp(2) of slack absorbs the layout's fractional rounding of the host's width,
        // which would otherwise cost a whole rung for nothing.
        var room = coin.availableWidth >= 0
            ? coin.availableWidth - coin._chrome + units.dp(2) : Number.MAX_VALUE;
        for (var i = 0; i < rungs.length; i++) {
            probe.text = rungs[i];
            if (probe.width <= room || i === rungs.length - 1) {
                coin._text = rungs[i];
                coin._textWidth = probe.width;
                return;
            }
        }
    }

    TextMetrics { id: probe; font: valueLabel.font }

    onValueChanged: _reselect()
    onCompactChanged: _reselect()
    onAvailableWidthChanged: _reselect()
    Component.onCompleted: _reselect()

    visible: value.length > 0
    implicitWidth: _chrome + Math.min(coin._textWidth, units.gu(14))
    implicitHeight: units.gu(3)
    radius: Style.pillRadius
    color: Style.iconBackground
    clip: true

    Row {
        id: row
        anchors { left: parent.left; leftMargin: Style.spacingS; verticalCenter: parent.verticalCenter }
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
            id: valueLabel
            anchors.verticalCenter: parent.verticalCenter
            // Elide rather than overflow-clip: the last rung can still be wider than a
            // pathologically narrow host allows.
            width: Math.max(units.gu(2),
                            Math.min(implicitWidth, coin.width - coin._chrome + units.dp(2)))
            elide: Text.ElideRight
            text: coin._text
            font.pixelSize: Style.fontSmall
            font.weight: Font.DemiBold
            color: Style.textPrimary
        }
    }
}
