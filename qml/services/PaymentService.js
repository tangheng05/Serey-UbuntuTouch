.pragma library
.import "Http.js" as Http

// Buy-plan payments: NOWPayments crypto (/subscription/crypto/*, NOT
// /crypto-subscription/*) and Stripe Checkout (redirect fixed to
// /subscription/return). No KHQR by design. Field normalisation stays here.

// -> onOk([ "usdttrc20", "btc", ... ])  (lowercase NOWPayments currency codes)
function getCurrencies(baseUrl, onOk, onErr) {
    Http.get(baseUrl, "/subscription/crypto/currencies", {}, null, function (data) {
        var list = (data && data.currencies) || [];
        if (!Array.isArray(list)) list = [];
        onOk(list);
    }, onErr);
}

// -> onOk({ paymentId, payAddress, payAmount, payCurrency, expiresAt, paymentUrl, message })
// expiresAt may be "" (callers fall back to ~15 min). A reused still-valid payment
// can arrive without a pay_address; surfaced as an error so the sheet shows the message.
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

// Confirm (and server-side ACTIVATE) a completed Stripe session. Must be called
// after the success redirect; don't trust the webhook alone. onOk(data) on any 2xx.
function checkStripeStatus(baseUrl, token, sessionId, onOk, onErr) {
    Http.post(baseUrl, "/subscription/stripe/check-status",
              { session_id: sessionId }, token, onOk, onErr);
}

// -> onOk("https://checkout.stripe.com/...")
function createStripeCheckout(baseUrl, token, planId, onOk, onErr) {
    Http.post(baseUrl, "/subscription/stripe/create-checkout",
              { subscription_plan_id: parseInt(planId) }, token, function (data) {
        if (data && data.checkout_url) onOk(data.checkout_url);
        else onErr({ status: 200, message: (data && data.message) || "Failed to start checkout." });
    }, onErr);
}
