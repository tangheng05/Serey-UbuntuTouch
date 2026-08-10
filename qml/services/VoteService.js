.pragma library
.import "Http.js" as Http

// Session-level vote state cache, keyed by "author/permlink", so a post the user just upvoted still shows blue after navigating back.
var _cache = {};

function _key(author, permlink) { return author + "/" + permlink; }

function getCached(author, permlink) {
    // Optimistic local comments have an empty permlink; they'd all collapse to the key "author/" and bleed vote state into each other, so skip the cache.
    if (!permlink) return null;
    return _cache[_key(author, permlink)] || null;
}

function _updateCache(author, permlink, upvoted, flagged, votes, payout) {
    if (!permlink) return;
    _cache[_key(author, permlink)] = {
        upvoted: upvoted,
        flagged: flagged,
        votes: votes,
        payout: payout
    };
}

function _norm(data) {
    var d = (data && data.data) ? data.data : (data || {});
    return {
        voterCount: (d.voter_count !== undefined) ? d.voter_count
                  : (d.current_vote !== undefined ? d.current_vote : 0),
        flaggerCount: d.flagger_count || 0,
        voters: d.voters || [],
        flaggers: d.flaggers || [],
        payout: d.serey_value || ""
    };
}

function _send(baseUrl, path, body, token, onOk, onErr) {
    var t0 = Date.now();
    var what = path + " " + body.author + "/" + body.permlink
             + " type=" + (body.vote_type || "post")
             + (body.weight !== undefined ? " w=" + body.weight : "");
    console.log("[vote] -> " + what);
    Http.post(baseUrl, path, body, token, function (data) {
        console.log("[vote] OK " + path + " in " + (Date.now() - t0) + "ms");
        onOk(_norm(data));
    }, function (e) {
        console.log("[vote] FAIL " + path + " in " + (Date.now() - t0) + "ms"
                    + " status=" + (e && e.status) + " msg=" + (e && e.message));
        onErr(e);
    });
}

function upvote(baseUrl, author, permlink, voteType, weight, token, onOk, onErr) {
    _send(baseUrl, "/vote/vote",
          { author: author, permlink: permlink, weight: weight || 100, vote_type: voteType || "post" },
          token, onOk, onErr);
}

function flag(baseUrl, author, permlink, voteType, token, onOk, onErr) {
    _send(baseUrl, "/vote/flag",
          { author: author, permlink: permlink, weight: -100, vote_type: voteType || "post" },
          token, onOk, onErr);
}

function removeVote(baseUrl, author, permlink, voteType, token, onOk, onErr) {
    _send(baseUrl, "/vote/remove-vote",
          { author: author, permlink: permlink, vote_type: voteType || "post" },
          token, onOk, onErr);
}
