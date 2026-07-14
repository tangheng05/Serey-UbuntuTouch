pragma Singleton
import QtQuick 2.7
import QtQuick.LocalStorage 2.0

/*
 * App-wide buy-plan payment state. Same state-vs-renderer split as
 * Toast/PostActions/Share: the mini app (via the WebAppView `buyPlan` bridge
 * or the checkout.stripe.com navigation intercept) calls open*(); the
 * renderers — PaymentSheet (native crypto flow) and StripeCheckoutSheet
 * (in-app Stripe checkout WebView) — are mounted once in Main.qml.
 *
 * `stripeOpen` matters beyond visibility: HomepagePage ORs it into the mini
 * app's `suspended` binding so the Homepage Chromium is frozen while the
 * checkout WebEngineView is alive (two live Chromium views SIGSEGV the
 * Pixel 3a — see dual-Chromium memory). The crypto sheet is pure QML.
 */
QtObject {
    id: payments

    // Crypto (NOWPayments) sheet.
    property bool cryptoOpen: false
    property int planId: 0

    // Stripe checkout sheet. `stripeUrl` empty => the sheet creates the
    // checkout session itself from `planId`; non-empty (interception path) =>
    // it loads the URL directly.
    property bool stripeOpen: false
    property string stripeUrl: ""

    // Fired on a confirmed payment (either method); HomepagePage reloads the
    // mini app so the site reflects the new plan.
    signal paymentSucceeded()

    function openCrypto(id) {
        planId = parseInt(id) || 0;
        if (planId > 0) cryptoOpen = true;
    }
    function openStripe(id) {
        planId = parseInt(id) || 0;
        stripeUrl = "";
        if (planId > 0) stripeOpen = true;
    }
    function openStripeUrl(url) {
        stripeUrl = url || "";
        planId = 0;
        if (stripeUrl.length > 0) stripeOpen = true;
    }
    function closeCrypto() { cryptoOpen = false; }
    function closeStripe() { stripeOpen = false; stripeUrl = ""; }

    // ---- Pending crypto payment, persisted across app restarts ------------
    // Crypto activation only happens when OUR client pings check-status (no
    // webhook reliance), so a payment made after the user closed the sheet or
    // the app would never activate unless we remember it and keep checking.
    // Main.qml runs the background check (a singleton QtObject can't own a
    // Timer); null = nothing pending. { paymentId, planId, expiresAt }.
    property var pendingCrypto: null

    function _db() {
        return LocalStorage.openDatabaseSync("SereyPayments", "1.0", "Pending payments", 10000);
    }
    function loadPendingCrypto() {
        _db().transaction(function (tx) {
            tx.executeSql("CREATE TABLE IF NOT EXISTS pending_crypto (payment_id TEXT PRIMARY KEY, plan_id INTEGER, expires_at TEXT)");
            var rs = tx.executeSql("SELECT * FROM pending_crypto LIMIT 1");
            pendingCrypto = rs.rows.length > 0
                ? { paymentId: rs.rows.item(0).payment_id,
                    planId: rs.rows.item(0).plan_id,
                    expiresAt: rs.rows.item(0).expires_at }
                : null;
        });
    }
    function setPendingCrypto(paymentId, planId, expiresAt) {
        _db().transaction(function (tx) {
            tx.executeSql("CREATE TABLE IF NOT EXISTS pending_crypto (payment_id TEXT PRIMARY KEY, plan_id INTEGER, expires_at TEXT)");
            tx.executeSql("DELETE FROM pending_crypto");   // only ever one pending payment
            tx.executeSql("INSERT INTO pending_crypto VALUES (?, ?, ?)",
                          [String(paymentId), parseInt(planId) || 0, expiresAt || ""]);
        });
        pendingCrypto = { paymentId: String(paymentId), planId: parseInt(planId) || 0, expiresAt: expiresAt || "" };
    }
    function clearPendingCrypto() {
        _db().transaction(function (tx) {
            tx.executeSql("CREATE TABLE IF NOT EXISTS pending_crypto (payment_id TEXT PRIMARY KEY, plan_id INTEGER, expires_at TEXT)");
            tx.executeSql("DELETE FROM pending_crypto");
        });
        pendingCrypto = null;
    }

    Component.onCompleted: loadPendingCrypto()
}
