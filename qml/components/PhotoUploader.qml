import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../services/Uploads.js" as Uploads

Item {
    id: root
    width: 0; height: 0

    property int maxDimension: 1600    // longest side after downscale (px)
    property int timeoutMs: 60000      // hard ceiling — QML XHR ignores `timeout`
    property bool uploading: false

    signal uploaded(string url)
    signal failed(string message)

    // Bumped per upload so a callback from a superseded/timed-out attempt (e.g. a
    // grab that resolves after the watchdog fired) can't fire a second result.
    property int _gen: 0

    function upload(fileUrl) {
        if (root.uploading)
            return;
        root.uploading = true;
        root._gen++;
        watchdog.restart();
        // Reassign even if the same file is re-picked so onStatusChanged fires.
        resizer.source = "";
        resizer.source = fileUrl;
    }

    function _finishOk(url) { watchdog.stop(); root.uploading = false; resizer.source = ""; root.uploaded(url); }
    function _finishErr(msg) { watchdog.stop(); root.uploading = false; resizer.source = ""; root.failed(msg); }

    function _uploadFile(fileUrl, gen) {
        Uploads.uploadImage(Config.uploadUrl, Config.uploadSecret, fileUrl,
            function (url) { if (gen === root._gen) root._finishOk(url); },
            function (err) { if (gen === root._gen) root._finishErr((err && err.message) || Lang.tr("Upload failed.")); });
    }

    function _onDecoded() {
        var gen = root._gen;
        var w = resizer.implicitWidth;
        var h = resizer.implicitHeight;
        if (w <= 0 || h <= 0) {            // couldn't measure — send original
            root._uploadFile(String(resizer.source), gen);
            return;
        }
        resizer.width = w;
        resizer.height = h;
        var src = String(resizer.source);
        var dir = src.substring(0, src.lastIndexOf("/")).replace(/^file:\/\//, "");
        var outLocal = dir + "/serey_up_" + Date.now() + ".jpg";
        resizer.grabToImage(function (result) {
            if (gen !== root._gen)            // superseded or timed out — drop it
                return;
            if (result && result.saveToFile(outLocal))
                root._uploadFile("file://" + outLocal, gen);
            else
                root._uploadFile(src, gen);   // fall back to original
        }, Qt.size(w, h));
    }

    // QML XMLHttpRequest does not honour its own `timeout`, so this is the only
    // reliable ceiling: abort the request and report a timeout.
    Timer {
        id: watchdog
        interval: root.timeoutMs
        onTriggered: {
            Uploads.abort();
            root._finishErr(Lang.tr("Upload timed out. Try a smaller image or check your connection."));
        }
    }

    // Off-screen decoder. Kept at opacity 0 (NOT visible:false, which would drop
    // it from the scene graph and make grabToImage return nothing) and sized to
    // the capped decode size so the grab is a clean downscaled bitmap.
    Image {
        id: resizer
        opacity: 0
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
        // Apply the EXIF orientation when decoding. Camera photos carry an
        // orientation tag rather than rotated pixels; without this the grabbed +
        // re-saved JPEG keeps the raw (sideways) pixels and uploads rotated.
        autoTransform: true
        fillMode: Image.PreserveAspectFit
        sourceSize.width: root.maxDimension
        sourceSize.height: root.maxDimension
        onStatusChanged: {
            if (status === Image.Ready)
                root._onDecoded();
            else if (status === Image.Error)
                root._uploadFile(String(resizer.source), root._gen);   // upload original bytes
        }
    }
}
