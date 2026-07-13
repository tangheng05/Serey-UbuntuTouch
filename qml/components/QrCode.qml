import QtQuick 2.7
import "../services/QrCodeGen.js" as QrGen

/*
 * QR code rendered locally on a Canvas from the vendored qrcode-generator lib
 * (services/QrCodeGen.js). Local generation is deliberate: the main use is
 * crypto payment addresses (PaymentSheet), which must not round-trip through a
 * third-party QR image service.
 */
Canvas {
    id: qr

    // Encode + paint off the UI thread — the synchronous paint froze a frame
    // for seconds (see "[PERFORMANCE]: Last frame took 3305 ms" in the logs).
    renderStrategy: Canvas.Threaded

    property string text: ""
    property color foreground: "#000000"
    property color background: "#FFFFFF"
    // Quiet zone around the code, in modules (QR spec asks for 4; 2 is fine
    // on-screen where the sheet already provides white padding).
    property int quietZone: 2

    onTextChanged: requestPaint()
    onForegroundChanged: requestPaint()
    onBackgroundChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.fillStyle = background;
        ctx.fillRect(0, 0, width, height);
        if (!text || text.length === 0)
            return;

        var q;
        try {
            q = QrGen.qrcode(0, "M");   // typeNumber 0 = auto-size for the data
            q.addData(text);
            q.make();
        } catch (e) {
            console.warn("QrCode: failed to encode: " + e);
            return;
        }

        var n = q.getModuleCount();
        var total = n + quietZone * 2;
        var cell = Math.min(width, height) / total;
        var ox = (width - cell * total) / 2 + quietZone * cell;
        var oy = (height - cell * total) / 2 + quietZone * cell;

        ctx.fillStyle = foreground;
        for (var r = 0; r < n; r++) {
            for (var c = 0; c < n; c++) {
                if (!q.isDark(r, c))
                    continue;
                // +0.5px overlap hides hairline seams between adjacent modules
                // at fractional cell sizes.
                ctx.fillRect(ox + c * cell, oy + r * cell, cell + 0.5, cell + 0.5);
            }
        }
    }
}
