.pragma library
.import "Http.js" as Http

// Anonymous invite codes; backend wraps every payload as {status, message, data:{...}}, so unwrap
function _payload(body) { return (body && body.data) ? body.data : (body || {}); }

// ── Creator (needs JWT) ─────────────────────────────────────────────────────

// List own codes + eligibility/quota. onOk gets the whole creator view-model.
function listInvites(baseUrl, token, onOk, onErr) {
    Http.get(baseUrl, "/anonymous-invites", null, token, function (body) {
        var d = _payload(body);
        onOk({
            eligible:    d.eligible === true,
            canPurchase: d.can_purchase === true,
            codes:       (d.codes || []).map(function (c) {
                return {
                    code:             c.code,
                    status:           c.status,              // unused|used|revoked
                    redeemedUsername: c.redeemed_username || "",
                    redeemedAt:       c.redeemed_at || "",
                    createdAt:        c.created_at || ""
                };
            }),
            quota:       d.quota || { used_slots: 0, max: 0, remaining: 0 },
            stats:       d.stats || { total_codes: 0, active_codes: 0, total_redemptions: 0 }
        });
    }, onErr);
}

// Mint one code; onOk gets { code, remaining, max }.
function generateInvite(baseUrl, token, onOk, onErr) {
    Http.post(baseUrl, "/anonymous-invites/generate", {}, token, function (body) {
        var d = _payload(body);
        if (!d.code) { onErr({ status: 200, message: (body && body.message) || "Couldn't generate a code." }); return; }
        onOk({ code: d.code, remaining: d.remaining, max: d.max });
    }, onErr);
}

// Revoke an unused code; frees the quota slot.
function revokeInvite(baseUrl, token, code, onOk, onErr) {
    Http.post(baseUrl, "/anonymous-invites/revoke", { code: code }, token, onOk, onErr);
}

// ── Public (no auth) ────────────────────────────────────────────────────────

// Preview a code before asking for a username; onOk gets { valid, invitedBy }.
function validateInvite(baseUrl, code, onOk, onErr) {
    Http.post(baseUrl, "/anonymous-invites/validate", { code: code }, null, function (body) {
        var d = _payload(body);
        onOk({ valid: d.valid === true, invitedBy: d.invited_by || "" });
    }, onErr);
}

// Redeem: creates account self-custodially; client sends keys, master password stays on device
function redeemInvite(baseUrl, code, username, keys, onOk, onErr) {
    Http.post(baseUrl, "/anonymous-invites/redeem",
              { code: code, username: username,
                owner_public_key: keys.owner_public_key,
                active_public_key: keys.active_public_key,
                posting_public_key: keys.posting_public_key,
                memo_public_key: keys.memo_public_key,
                posting_private_key: keys.posting_private_key }, null, function (body) {
        var d = _payload(body);
        if (d.account_created !== true && !d.posting_private_key) {
            onErr({ status: 200, message: (body && body.message) || "Couldn't create the account." });
            return;
        }
        onOk({ username: d.username || username, invitedBy: d.invited_by || "" });
    }, onErr);
}

// Shareable web link; app intercepts it (see WebAppView) to redeem natively
function inviteLink(code) { return "https://serey.io/invite/anonymous?code=" + encodeURIComponent(code); }

// Pull ?code= out of an invite URL (used by the in-app deep-link intercept).
function codeFromUrl(url) {
    var m = String(url || "").match(/[?&]code=([^&#]+)/);
    return m ? decodeURIComponent(m[1]) : "";
}
