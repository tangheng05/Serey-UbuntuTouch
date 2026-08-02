.pragma library
.import "Http.js" as Http

// Section-based landing page CMS; hero section (always first) carries bg_image_url/opacity

function getByCommunity(baseUrl, communityId, token, onOk, onErr) {
    Http.get(baseUrl, "/landing-page-v2/get-by-community/" + communityId, {}, token, function (data) {
        var lp = data.landing_page || {};
        onOk(lp.content || []);
    }, onErr);
}

// Content already ordered by `order` ASC, hero is first entry
function findHeroSection(sections) {
    return (sections && sections.length) ? sections[0] : null;
}

// Pass the full section with changed fields overridden, or columns get clobbered
function saveSection(baseUrl, section, token, onOk, onErr) {
    Http.post(baseUrl, "/landing-page-v2/create-or-update", section, token,
              function (data) { onOk(data || {}); }, onErr);
}
