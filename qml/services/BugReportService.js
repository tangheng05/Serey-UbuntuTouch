.pragma library
.import "Http.js" as Http

// Bug / feedback / feature-request reports. All routes need a JWT.
// Backend: serey-api src/routes/bug_report_route.js, mounted at /bug-reports.

var BASE = "/bug-reports";

// The server derives the title from the description, so the form only sends text + images.
function submit(baseUrl, token, payload, onOk, onErr) {
    var body = { description: payload.description };
    if (payload.type) body.type = payload.type;
    if (payload.imageUrls && payload.imageUrls.length) body.image_urls = payload.imageUrls;
    if (payload.deviceInfo) body.device_info = payload.deviceInfo;
    Http.post(baseUrl, BASE, body, token,
              function (data) { onOk(mapReport(data && data.data)); }, onErr);
}

function myReports(baseUrl, token, onOk, onErr) {
    Http.get(baseUrl, BASE + "/mine", null, token, function (data) {
        var arr = (data && data.data) || [];
        if (!Array.isArray(arr)) arr = [];
        onOk(arr.map(mapReport));
    }, onErr);
}

// Owner-editable fields only; priority and admin notes stay admin-side.
function updateOwn(baseUrl, token, id, fields, onOk, onErr) {
    var body = {};
    if (fields.description !== undefined) body.description = fields.description;
    if (fields.status !== undefined) body.status = fields.status;
    if (fields.imageUrls !== undefined) body.image_urls = fields.imageUrls;
    Http.patch(baseUrl, BASE + "/" + id, body, token,
               function (data) { onOk(mapReport(data && data.data)); }, onErr);
}

function removeOwn(baseUrl, token, id, onOk, onErr) {
    Http.del(baseUrl, BASE + "/" + id, token, onOk, onErr);
}

function mapReport(r) {
    r = r || {};
    var imgs = r.image_urls;
    if (typeof imgs === "string") {
        try { imgs = JSON.parse(imgs); } catch (e) { imgs = []; }
    }
    if (!Array.isArray(imgs)) imgs = [];
    return {
        id: r.id,
        type: r.type || "bug",
        title: r.title || "",
        description: r.description || "",
        status: r.status || "open",
        priority: r.priority || "medium",
        adminNote: r.admin_note || "",
        images: imgs,
        // Joined for the ListModel: array fields come back wrapped and lose .length there.
        imagesStr: imgs.join("\n"),
        createdAt: r.created_at || r.createdAt || ""
    };
}
