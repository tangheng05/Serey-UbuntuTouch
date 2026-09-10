.pragma library
.import "Http.js" as Http

// Landing page and premium community settings; field names inferred from docs, not schema

function getByCommunity(baseUrl, communityId, token, onOk, onErr) {
    Http.get(baseUrl, "/landing-page/get-by-community/" + communityId, {}, token, function (data) {
        onOk(data.data || data.landingPage || {});
    }, onErr);
}

function createOrUpdate(baseUrl, body, token, onOk, onErr) {
    Http.post(baseUrl, "/landing-page/create-or-update", body, token,
              function (data) { onOk(data || {}); }, onErr);
}

function deleteConfig(baseUrl, communityId, token, onOk, onErr) {
    Http.del(baseUrl, "/landing-page/delete/" + communityId, token,
             function (data) { onOk(data || {}); }, onErr);
}

// Kit (ConvertKit) embed settings for the subscription section.
function saveKitSettings(baseUrl, body, token, onOk, onErr) {
    Http.post(baseUrl, "/landing-page/kit-settings", body, token,
              function (data) { onOk(data || {}); }, onErr);
}

// --- Premium/paid community settings ---------------------------------------

function getPremiumSetting(baseUrl, communityId, token, onOk, onErr) {
    Http.get(baseUrl, "/premium-community-setting/get-by-community-id/" + communityId, {}, token, function (data) {
        onOk(data.data || data || {});
    }, onErr);
}

function savePremiumFee(baseUrl, body, token, onOk, onErr) {
    Http.post(baseUrl, "/premium-community-setting/create-or-update-setting-fee", body, token,
              function (data) { onOk(data || {}); }, onErr);
}

function publishPremiumSetting(baseUrl, body, token, onOk, onErr) {
    Http.post(baseUrl, "/premium-community-setting/publish-or-unpublish-setting", body, token,
              function (data) { onOk(data || {}); }, onErr);
}
