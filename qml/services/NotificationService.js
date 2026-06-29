.pragma library
.import "Http.js" as Http

var NOTIF_BASE = "https://notification.serey.io"
var SERVICE_USER = "mobile"
var SERVICE_PASS = "&_3W!nEv'}5cq}XX"

function _serviceLogin(onOk, onErr) {
    Http.post(NOTIF_BASE, "/api/notification/user/login",
              { username: SERVICE_USER, password: SERVICE_PASS, rememberMe: true },
              null, function (data) {
        var token = data && data.data && data.data.token
        if (token) onOk(token)
        else onErr({ message: "No service token in response" })
    }, onErr)
}

function registerPushToken(username, pushToken, onOk, onErr) {
    _serviceLogin(function (svcToken) {
        Http.postForm(NOTIF_BASE, "/api/notification/user/createToken",
            "username=" + encodeURIComponent(username) +
            "&token=" + encodeURIComponent(pushToken) +
            "&deviceType=UBUNTU_TOUCH&platformType=SEREY_WEB",
            svcToken, function (data) {
                var code = data && data.status && data.status.responseCode
                if (code === 1) {
                    Http.postForm(NOTIF_BASE, "/api/notification/user/updateToken",
                        "username=" + encodeURIComponent(username) +
                        "&newToken=" + encodeURIComponent(pushToken) +
                        "&platformType=SEREY_WEB",
                        svcToken, onOk, onErr)
                } else {
                    onOk(data)
                }
            }, onErr)
    }, onErr)
}

function removeToken(username, onOk, onErr) {
    _serviceLogin(function (svcToken) {
        Http.postForm(NOTIF_BASE, "/api/notification/user/removeToken",
            "username=" + encodeURIComponent(username),
            svcToken, onOk, onErr)
    }, onErr)
}

function listSerey(baseUrl, token, limit, offset, onOk, onErr) {
    Http.get(baseUrl, "/notification/list-by-current-user-for-serey",
             { limit: limit, offset: offset }, token, function (data) {
        var d = data && data.data
        var items = Array.isArray(d) ? d
                  : (d && d.notifications) || []
        onOk(items)
    }, onErr)
}

function countUnread(baseUrl, token, onOk, onErr) {
    Http.get(baseUrl, "/notification/list-by-current-user-for-serey",
             { limit: 50, offset: 0 }, token, function (data) {
        var d = data && data.data
        var items = Array.isArray(d) ? d
                  : (d && d.notifications) || []
        var count = 0
        for (var i = 0; i < items.length; i++) {
            if (!items[i].is_read) count++
        }
        onOk(count)
    }, onErr)
}

function markAllRead(baseUrl, token, onOk, onErr) {
    Http.put(baseUrl, "/notification/update-read-all-for-serey", {}, token, onOk, onErr)
}

function markOneRead(baseUrl, token, id, onOk, onErr) {
    Http.put(baseUrl, "/notification/update-read-by-id/" + id, {}, token, onOk, onErr)
}
