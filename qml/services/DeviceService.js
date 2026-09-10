.pragma library
.import "Http.js" as Http
.import "Mappers.js" as M

// /terminate needs a non-expiring token, hence login sends `device_name`

function list(baseUrl, token, onOk, onErr) {
    return Http.get(baseUrl, "/user-device/list-by-current-user", {}, token,
                    function (data) {
        var raw = (data && data.user_devices) || [];
        var out = [];
        for (var i = 0; i < raw.length; i++)
            out.push(M.toDevice(raw[i]));
        onOk(out);
    }, onErr);
}

// Server 400s an attempt to terminate your own device, so we never have to guess.
function terminate(baseUrl, token, ids, onOk, onErr) {
    return Http.put(baseUrl, "/user-device/terminate", { ids: ids }, token, onOk, onErr);
}
