pragma Singleton
import QtQuick 2.7

// App-wide reachability. Http reports every request outcome here (wired in Main.qml),
// so a dead network flips the whole UI to its offline face; while offline a slow probe
// keeps checking so the app recovers on its own once the phone is back on a network.
Item {
    id: net

    property bool online: true
    property bool _probing: false

    // status 0 from Http.js is "no response at all", but that also covers our own abort()
    // of a stale feed request, so a failure is confirmed with a probe before flipping.
    function report(reachable) {
        if (reachable) { net.online = true; return; }
        if (!net.online || net._probing) return;
        net.probe();
    }

    // Any HTTP answer proves connectivity, so the status code itself doesn't matter.
    function probe() {
        if (net._probing) return;
        net._probing = true;
        var xhr = new XMLHttpRequest();
        xhr.timeout = 8000;
        xhr.ontimeout = function () { net._probing = false; net.online = false; };
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            net._probing = false;
            net.online = xhr.status !== 0;
        };
        try {
            xhr.open("HEAD", Config.baseUrl);
            xhr.send();
        } catch (e) {
            net._probing = false;
            net.online = false;
        }
    }

    Timer {
        interval: 15000
        repeat: true
        running: !net.online
        onTriggered: net.probe()
    }
}
