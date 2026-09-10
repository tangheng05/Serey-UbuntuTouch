.pragma library
.import "Http.js" as Http

// Navbar/menu management; shared with the web CMS's custom_menu table (platform_type=WEB).

var DEFAULT_WEBSITE = "SEREY";
var PLATFORM_TYPE = 1; // PLATFORM_TYPE.WEB — see backend constants.js

function listByWebsiteAndCommunity(baseUrl, params, token, onOk, onErr) {
    var query = Object.assign({ website: DEFAULT_WEBSITE, platform_type: PLATFORM_TYPE }, params || {});
    Http.get(baseUrl, "/custom-menu/list-by-website-and-community", query, token, function (data) {
        onOk(data.data || data.menus || []);
    }, onErr);
}

function detail(baseUrl, id, token, onOk, onErr) {
    Http.get(baseUrl, "/custom-menu/detail-by-id", { id: id }, token, function (data) {
        onOk(data.data || data.menu || {});
    }, onErr);
}

function createOrUpdate(baseUrl, body, token, onOk, onErr) {
    var payload = Object.assign({ website: DEFAULT_WEBSITE, platform_type: PLATFORM_TYPE }, body || {});
    Http.post(baseUrl, "/custom-menu/create-or-update-menu", payload, token,
        function (data) { onOk(data || {}); }, onErr);
}

function updatePositions(baseUrl, orderedIds, token, onOk, onErr) {
    Http.post(baseUrl, "/custom-menu/update-positions", { ids: orderedIds }, token,
        function (data) { onOk(data || {}); }, onErr);
}

function updateDescription(baseUrl, id, description, token, onOk, onErr) {
    Http.post(baseUrl, "/custom-menu/update-description", { id: id, description: description }, token,
        function (data) { onOk(data || {}); }, onErr);
}

function updateLayout(baseUrl, id, layout, token, onOk, onErr) {
    Http.post(baseUrl, "/custom-menu/update-layout", { id: id, layout: layout }, token,
        function (data) { onOk(data || {}); }, onErr);
}

// DELETE only, no POST alias; send id as query param not body
function deleteMenu(baseUrl, id, token, onOk, onErr) {
    Http.del(baseUrl, "/custom-menu/delete-menu" + Http.buildQuery({ id: id }), token,
        function (data) { onOk(data || {}); }, onErr);
}

// v2 only.
function listIcons(baseUrl, token, onOk, onErr) {
    Http.get(baseUrl, "/custom-menu/list-icons", {}, token, function (data) {
        onOk(data.data || data.icons || []);
    }, onErr);
}
