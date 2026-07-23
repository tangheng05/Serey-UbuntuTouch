.pragma library
.import "Http.js" as Http

// Section-based landing page CMS. `landing_page.content` holds all section rows
// ordered by `order` ASC; the hero (always first) carries bg_image_url/opacity,
// which is separate from /community/update-logo's logo fields.

function getByCommunity(baseUrl, communityId, token, onOk, onErr) {
    Http.get(baseUrl, "/landing-page-v2/get-by-community/" + communityId, {}, token, function (data) {
        var lp = data.landing_page || {};
        onOk(lp.content || []);
    }, onErr);
}

// `content` is already ordered by `order` ASC and the hero/header section is
// always first in that order, so just take the first entry.
function findHeroSection(sections) {
    return (sections && sections.length) ? sections[0] : null;
}

// Upserts a single section row. Pass the full previously-fetched section with
// just the changed fields overridden, or the row's other columns get clobbered.
function saveSection(baseUrl, section, token, onOk, onErr) {
    Http.post(baseUrl, "/landing-page-v2/create-or-update", section, token,
              function (data) { onOk(data || {}); }, onErr);
}
