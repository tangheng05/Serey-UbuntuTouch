.pragma library
.import "Http.js" as Http
.import "Mappers.js" as M

function login(baseUrl, username, password, onOk, onErr) {
    // `device_name` mints a NON-expiring token (auth_service: hasExpired = !device_name); without it the token hard-expires in 24h.
    Http.post(baseUrl, "/auth/login",
              { username: username, password: password, device_name: "Ubuntu Touch" },
              null, function (data) {
        var token = data.data && data.data.token;
        if (!token) {
            onErr({ message: "Login succeeded but no token was returned." });
            return;
        }
        onOk({ token: token, userDeviceId: data.data.user_device_id });
    }, onErr);
}

// No startup token-verify: /auth/authenticated needs a device JWT the native client never has, so it always 401s. Calling it on launch would wrongly log out.

function logout(baseUrl, token, onOk, onErr) {
    Http.del(baseUrl, "/auth/logout", token, onOk, onErr);
}

function profile(baseUrl, username, token, onOk, onErr) {
    Http.get(baseUrl, "/accounts/details-by-username/" + encodeURIComponent(username),
             null, token, function (data) {
        onOk(M.toUser(username, data.account || {}));
    }, onErr);
}

// Community ids the user owns/manages, so an owner can post to an owner-only
// community. onOk gets an array of numeric ids (community_owner.community_ids).
function ownedCommunityIds(baseUrl, token, onOk, onErr) {
    Http.get(baseUrl, "/user-permission/permission-by-current-user", {}, token,
             function (data) {
        var owner = (data && data.community_owner) || {};
        onOk(owner.community_ids || []);
    }, onErr);
}

// Custodial signup + password reset, email OTP only (phone OTP is Cambodia-only).
// Server-enforced rules: password 8-16 chars with lower+upper+digit,
// username 5-30 chars [a-z0-9-].
var PASSWORD_RE = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)[A-Za-z\d@$!%*?#&^()[\]{}]{8,16}$/;
var USERNAME_RE = /^[a-z0-9-]{5,30}$/;

function isValidPassword(p) { return PASSWORD_RE.test(p || ""); }
function isValidUsername(u) { return USERNAME_RE.test(u || ""); }

// Backend returns HTTP 200 status:false when taken, which Http.js treats as a failure: onOk means available, onErr means taken (or a network error).
function checkUsernameAvailable(baseUrl, username, onOk, onErr) {
    Http.get(baseUrl, "/accounts/check-existing-username/" + encodeURIComponent(username),
             null, null, onOk, onErr);
}

// Step 1 of signup: send a verification OTP to the chosen email.
function sendSignupOtp(baseUrl, username, email, onOk, onErr) {
    Http.post(baseUrl, "/accounts/send-otp-standard",
              { username: username, email: email }, null, onOk, onErr);
}

// Step 2 of signup: create the account, then auto-login, since the create endpoint returns no token.
function createStandardAccount(baseUrl, username, email, otp, password, onOk, onErr) {
    Http.post(baseUrl, "/accounts/create-account-standard", {
        username: username,
        email: email,
        otp: otp,
        password: password,
        gender_id: 1,          // web defaults this silently; no picker is shown
        first_name: "",
        last_name: "",
        country_id: null,
        referral_code: ""
    }, null, function () {
        login(baseUrl, username, password, onOk, onErr);
    }, onErr);
}

// Self-custody: keypair generated on-device (KeygenBridge); server only receives public keys + posting private key, never the master password.
function createSelfCustodyAccount(baseUrl, username, email, otp, keys, onOk, onErr) {
    Http.post(baseUrl, "/accounts/create-account", {
        username: username,
        email: email,
        otp: otp,
        gender_id: 1,
        first_name: "",
        last_name: "",
        country_id: null,
        owner_public_key: keys.owner_public_key,
        active_public_key: keys.active_public_key,
        posting_public_key: keys.posting_public_key,
        memo_public_key: keys.memo_public_key,
        posting_private_key: keys.posting_private_key,
        auth_type: "normal",
        referral_code: ""
    }, null, onOk, onErr);
}

// Paid, email-less signup. XMR only. Envelope is {status,message,data}; a reused
// "Payment still valid" response nests the payload one level deeper.
function createAnonymousPayment(baseUrl, username, onOk, onErr) {
    Http.post(baseUrl, "/registration/anonymous/create-payment",
              { username: username, pay_currency: "xmr" }, null, function (data) {
        var body = data || {};
        var d = body.data || body;
        var pay = d.data || d;
        if (!pay || !pay.payment_id || !pay.pay_address) {
            onErr({ status: 200, message: (body.message || d.message) || "Failed to create payment. Please try again." });
            return;
        }
        onOk({
            paymentId:  String(pay.payment_id),
            payAddress: pay.pay_address,
            payAmount:  String(pay.pay_amount !== undefined && pay.pay_amount !== null ? pay.pay_amount : ""),
            expiresAt:  pay.expires_at || "",
            paymentUrl: pay.payment_url || ""
        });
    }, onErr);
}

// Poll status. Pending gives a NOWPayments code (waiting/confirming/...); once
// done status is "completed" and postingPrivateKey comes back just this once.
function checkAnonymousStatus(baseUrl, paymentId, onOk, onErr) {
    Http.post(baseUrl, "/registration/anonymous/check-status",
              { payment_id: paymentId }, null, function (data) {
        var body = data || {};
        var s = (body.data && body.data.data) || body.data || body;
        onOk({
            status:            s.payment_status || s.status || "waiting",
            accountCreated:    s.account_created === true,
            postingPrivateKey: s.posting_private_key || "",
            username:          s.username || ""
        });
    }, onErr);
}

// Empty optional fields are dropped, so a blank field never overwrites a value the user didn't touch.
function updateUserDetail(baseUrl, token, fields, onOk, onErr) {
    var body = {};
    var keys = ["firstname", "lastname", "email", "phone", "gender_id", "dob", "bio"];
    for (var i = 0; i < keys.length; i++) {
        var k = keys[i];
        var v = fields[k];
        if (v !== undefined && v !== null && v !== "")
            body[k] = v;
    }
    Http.post(baseUrl, "/accounts/update-user-detail", body, token, onOk, onErr);
}

// Sets the active profile picture from an already-uploaded URL (see Uploads.js)
function setProfilePicture(baseUrl, token, imageUrl, onOk, onErr) {
    Http.post(baseUrl, "/user-profile-picture/add", { image_url: imageUrl }, token, onOk, onErr);
}

function setCoverPhoto(baseUrl, token, imageUrl, onOk, onErr) {
    Http.post(baseUrl, "/user-cover-photo/add", { image_url: imageUrl }, token, onOk, onErr);
}

function searchUser(baseUrl, token, query, onOk, onErr) {
    Http.get(baseUrl, "/accounts/search-user", { search_text: query }, token, function (data) {
        var arr = Array.isArray(data) ? data : [];
        onOk(arr.map(function(u) { return { username: u, name: u }; }));
    }, onErr);
}

function changePassword(baseUrl, token, currentPassword, newPassword, onOk, onErr) {
    Http.post(baseUrl, "/accounts/change-password",
              { current_password: currentPassword, new_password: newPassword },
              token, onOk, onErr);
}

// Step 0 of password reset: look up the account's masked contact hint (data.data.{email,phone}) so the UI can tell the user where the code will go.
function getContactHint(baseUrl, username, onOk, onErr) {
    Http.get(baseUrl, "/accounts/contact-hint", { username: username }, null, onOk, onErr);
}

// Step 1 of password reset: send an OTP to the chosen contact ({email} or {phone}); the backend verifies it matches the account.
function requestPasswordReset(baseUrl, username, contact, onOk, onErr) {
    var body = { username: username };
    if (contact.email) body.email = contact.email;
    if (contact.phone) body.phone = contact.phone;
    Http.post(baseUrl, "/accounts/request-password-reset", body, null, onOk, onErr);
}

// Step 2 of password reset: verify the OTP and set the new password.
function resetPassword(baseUrl, username, otp, newPassword, onOk, onErr) {
    Http.post(baseUrl, "/accounts/reset-password",
              { username: username, otp: otp, new_password: newPassword },
              null, onOk, onErr);
}

// Block/unblock a user. actionType "ADD" blocks, "REMOVE" unblocks.
function toggleBlock(baseUrl, token, username, actionType, onOk, onErr) {
    Http.post(baseUrl, "/blocking-user/add-remove",
              { username: username, action_type: actionType }, token, onOk, onErr);
}

// Returns the list of usernames the current user has blocked: { blocking_users: [{ username, owner, ... }] }.
function listBlocked(baseUrl, token, onOk, onErr) {
    Http.get(baseUrl, "/blocking-user/list-by-current-user", null, token, function (data) {
        var arr = (data && data.blocking_users) || [];
        onOk(arr.map(function (u) { return u.username || ""; })
               .filter(function (u) { return u !== ""; }));
    }, onErr);
}
