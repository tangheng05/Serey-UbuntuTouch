.pragma library
.import "Http.js" as Http

/*
 * Buy-plan payments. Two methods (the app deliberately has no KHQR):
 *
 *  - NOWPayments crypto, mounted at /subscription/crypto/* (see serey-api
 *    routes/index.js — NOT /crypto-subscription/*). create-payment returns a
 *    deposit address the user pays from an external wallet; check-status is
 *    polled until NOWPayments reports the payment finished.
 *  - Stripe Checkout: create-checkout returns a hosted checkout_url; the
 *    backend fixes the redirect to FRONTEND_ORIGIN/subscription/return
 *    (?success=true&session_id=… / ?cancel=true), which StripeCheckoutSheet
 *    watches for.
 *
 * Normalisation of the API's field quirks stays here (Mappers-style); the
 * QML sheets consume clean view-models.
 */

// -> onOk([ "usdttrc20", "btc", ... ])  (lowercase NOWPayments currency codes)
function getCurrencies(baseUrl, onOk, onErr) {
    Http.get(baseUrl, "/subscription/crypto/currencies", {}, null, function (data) {
        var list = (data && data.currencies) || [];
        if (!Array.isArray(list)) list = [];
        onOk(list);
    }, onErr);
}

// -> onOk({ paymentId, payAddress, payAmount, payCurrency, expiresAt, paymentUrl, message })
// `expiresAt` may be "" when the backend omits it (callers fall back to ~15 min,
// matching the web frontend). A reused still-valid payment can come back without
// a pay_address ("Payment still valid") — surfaced as an error so the sheet
// shows the message instead of a blank address.
function createCryptoPayment(baseUrl, token, planId, payCurrency, onOk, onErr) {
    Http.post(baseUrl, "/subscription/crypto/create-payment",
              { subscription_plan_id: parseInt(planId), pay_currency: payCurrency },
              token, function (data) {
        if (!data || !data.payment_id) {
            onErr({ status: 200, message: (data && data.message) || "Failed to create payment." });
            return;
        }
        if (!data.pay_address) {
            onErr({ status: 200, message: (data && data.message) || "Payment pending. Please try again shortly." });
            return;
        }
        onOk({
            paymentId:   String(data.payment_id),
            payAddress:  data.pay_address,
            payAmount:   String(data.pay_amount !== undefined && data.pay_amount !== null ? data.pay_amount : ""),
            payCurrency: (data.pay_currency || payCurrency || "").toUpperCase(),
            expiresAt:   data.expires_at || "",
            paymentUrl:  data.payment_url || data.invoice_url || "",
            message:     data.message || ""
        });
    }, onErr);
}

// -> onOk("waiting" | "confirming" | "confirmed" | "sending" | "finished"
//         | "partially_paid" | "failed" | "refunded" | "expired")
function checkCryptoStatus(baseUrl, token, paymentId, onOk, onErr) {
    Http.post(baseUrl, "/subscription/crypto/check-status",
              { payment_id: paymentId }, token, function (data) {
        onOk((data && data.payment_status) || "waiting");
    }, onErr);
}

// Confirm (and, server-side, ACTIVATE) a completed Stripe checkout session.
// The backend's check-status activates the subscription when the session is
// paid but not yet activated — the same belt-and-braces the web return page
// provides — so the app must call this after the success redirect instead of
// trusting the webhook alone. onOk(data) on any 2xx.
function checkStripeStatus(baseUrl, token, sessionId, onOk, onErr) {
    Http.post(baseUrl, "/subscription/stripe/check-status",
              { session_id: sessionId }, token, onOk, onErr);
}

// -> onOk("https://checkout.stripe.com/…")
function createStripeCheckout(baseUrl, token, planId, onOk, onErr) {
    Http.post(baseUrl, "/subscription/stripe/create-checkout",
              { subscription_plan_id: parseInt(planId) }, token, function (data) {
        if (data && data.checkout_url) onOk(data.checkout_url);
        else onErr({ status: 200, message: (data && data.message) || "Failed to start checkout." });
    }, onErr);
}
