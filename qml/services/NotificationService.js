.pragma library
.import "Http.js" as Http

function registerPushToken(baseUrl, token, pushToken, onOk, onErr) {
    Http.post(baseUrl, "/notification/register-push-token",
              { push_token: pushToken, platform: "ubuntu-touch" },
              token, onOk, onErr)
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

function markAllRead(baseUrl, token, onOk, onErr) {
    Http.put(baseUrl, "/notification/update-read-all-for-serey", {}, token, onOk, onErr)
}

function markOneRead(baseUrl, token, id, onOk, onErr) {
    Http.put(baseUrl, "/notification/update-read-by-id/" + id, {}, token, onOk, onErr)
}

// resolves a notification id to its full record
function getById(baseUrl, token, id, onOk, onErr) {
    Http.get(baseUrl, "/notification/get-by-id/" + id, {}, token, function (data) {
        onOk((data && data.notification) || null)
    }, onErr)
}
