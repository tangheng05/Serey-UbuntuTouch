.pragma library
.import "Http.js" as Http

function getReportTypes(baseUrl, onOk, onErr) {
    Http.get(baseUrl, "/general/report-types", null, null, function (data) {
        var arr = (data && (data.report_types || data.data || data.results)) || [];
        if (!Array.isArray(arr)) arr = [];
        onOk(arr);
    }, onErr);
}

function submitReport(baseUrl, token, postId, reportTypeId, description, onOk, onErr) {
    Http.post(baseUrl, "/general/report-post", {
        post_id: String(postId),
        report_type_id: String(reportTypeId),
        description: description || ""
    }, token, onOk, onErr);
}
