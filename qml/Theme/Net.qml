pragma Singleton
import QtQuick 2.7

// App-wide reachability. Http reports every request outcome here (wired in Main.qml),
// so a dead network flips the whole UI to its offline face; while offline a slow probe
// keeps checking so the app recovers on its own once the phone is back on a network.
Item {
    id: net

    // Dev switch: flip to true to preview every offline surface without pulling the plug.
    // Ships false; nothing in the app sets it.
    property bool forceOffline: false

    readonly property bool online: !net.forceOffline && net._reachable
    property bool _reachable: true
    property bool _probing: false

    // status 0 from Http.js is "no response at all", but that also covers our own abort()
    // of a stale feed request, so a failure is confirmed with a probe before flipping.
    function report(reachable) {
        if (net.forceOffline) return;
        if (reachable) { net._reachable = true; return; }
        if (!net._reachable || net._probing) return;
        net.probe();
    }

    // Any HTTP answer proves connectivity, so the status code itself doesn't matter.
    function probe() {
        if (net.forceOffline || net._probing) return;
        net._probing = true;
        var xhr = new XMLHttpRequest();
        // A HEAD against the API answers in well under a second on any live connection, so
        // this only has to outlast a slow handshake. Every second here is a second the app
        // keeps spinning before it admits it's offline.
        xhr.timeout = 4000;
        xhr.ontimeout = function () { net._probing = false; net._reachable = false; };
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            net._probing = false;
            net._reachable = xhr.status !== 0;
        };
        try {
            xhr.open("HEAD", Config.baseUrl);
            xhr.send();
        } catch (e) {
            net._probing = false;
            net._reachable = false;
        }
    }

    Timer {
        interval: 15000
        repeat: true
        running: !net.online && !net.forceOffline
        onTriggered: net.probe()
    }

    // Requests currently waiting for an answer (fed by Http.setPendingHandler in Main.qml).
    property int pending: 0

    // A dropped connection otherwise stays invisible until a request hits its own 15s timeout,
    // so the spinner outlives the network. While anything is pending, probe: the probe answers
    // in well under a second on a live link, so a slow-but-alive network is left alone and only
    // a real outage flips us offline early.
    Timer {
        interval: 3000
        repeat: true
        running: net.pending > 0 && net._reachable && !net.forceOffline
        onTriggered: net.probe()
    }
}
