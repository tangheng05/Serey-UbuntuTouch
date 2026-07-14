.pragma library
.import "Http.js" as Http

/*
 * Landing page v2 (/landing-page-v2) — section-based CMS content model
 * (landing_page_v2_section.js). Response wrapper is `landing_page`, whose
 * `content` array holds every section row (every column present on every
 * row regardless of type — no per-type field stripping), ordered by `order`
 * ASC. The hero/header section — always first in that order — carries the
 * bg_image_url/bg_image_opacity that renders behind the platform logo; that's
 * separate from POST /community/update-logo, which only manages
 * logo_url/footer_logo_url/icon_url.
 */

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

// POST /landing-page-v2/create-or-update — upserts a single section row.
// Callers should pass the full section (spread from a previous get-by-community
// fetch, including its id/landing_page_id) with bg_image_url (and optionally
// bg_image_opacity) overridden, so the row's other columns aren't clobbered.
function saveSection(baseUrl, section, token, onOk, onErr) {
    Http.post(baseUrl, "/landing-page-v2/create-or-update", section, token,
              function (data) { onOk(data || {}); }, onErr);
}
