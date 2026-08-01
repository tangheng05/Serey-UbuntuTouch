.pragma library
.import "Http.js" as Http
.import "Mappers.js" as M

// Active login sessions ("devices"). Listing needs only a normal JWT, but
// /terminate is behind isDeviceJwtAuthenticated, which requires a non-expiring
// token: that's why AccountService.login() sends `device_name`.

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

// The server refuses to terminate the caller's own device (400) and tells you to
// sign out instead, so we never have to guess which row is the current one.
function terminate(baseUrl, token, ids, onOk, onErr) {
    return Http.put(baseUrl, "/user-device/terminate", { ids: ids }, token, onOk, onErr);
}
