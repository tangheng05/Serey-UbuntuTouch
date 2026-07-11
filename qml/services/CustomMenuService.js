.pragma library
.import "Http.js" as Http

/*
 * Navbar/menu management under /custom-menu (custom_menu_route.js). The
 * `website` column (custom_menu.js) is a free-text field, but the only place
 * the backend itself sets one (the auto-injected "Premium" menu row in
 * premium_community_setting_service.js) hardcodes the platform-wide literal
 * "SEREY" — not a per-community value — so that's used as the default here.
 * Confirmed via a live 400 ("Invalid parameter") that list-by-website-and-community
 * requires BOTH `website` and `community_id`.
 */

var DEFAULT_WEBSITE = "SEREY";

function listByWebsiteAndCommunity(baseUrl, params, token, onOk, onErr) {
    var query = Object.assign({ website: DEFAULT_WEBSITE }, params || {});
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
    var payload = Object.assign({ website: DEFAULT_WEBSITE }, body || {});
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

// Documented as DELETE only (no POST alias, unlike delete-post-or-comment),
// so send id as a query param rather than a body.
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
