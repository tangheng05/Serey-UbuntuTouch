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

// The chain rejects votes with raw C++ assert dumps. Turn the ones a user can act on into
// plain sentences; callers wrap the result in Lang.tr().
function friendlyError(e) {
    var msg = (e && e.message) ? String(e.message) : "";
    var low = msg.toLowerCase();
    if (low.indexOf("voting power") >= 0 || low.indexOf("weight is too small") >= 0
        || low.indexOf("dust") >= 0 || low.indexOf("steem power") >= 0)
        return "Your voting power is used up. It refills over the next few hours.";
    if (low.indexOf("bandwidth") >= 0 || low.indexOf("rate limit") >= 0)
        return "You're voting faster than the network allows. Try again in a few minutes.";
    if (low.indexOf("can only vote once every") >= 0 || low.indexOf("vote changed too many") >= 0)
        return "You just changed this vote. Wait a moment before changing it again.";
    // Http.js already words network failures and timeouts for humans
    if (e && e.status === 0 && msg.length > 0)
        return msg;
    // A raw assert dump or an empty 5xx body says nothing useful either way
    if (msg.length === 0 || low.indexOf("assert") >= 0 || (e && e.status >= 500))
        return "Serey couldn't record that vote right now. Please try again.";
    return msg;
}

// A vote is signed and broadcast to the chain server-side, which regularly outlives the
// default 15s HTTP wait. Timing out at 15s reported a failure (and rolled the button back)
// for votes that were still landing, so these get a broadcast-sized wait of their own.
var BROADCAST_TIMEOUT = 45000;

function _send(baseUrl, path, body, token, onOk, onErr) {
    Http.post(baseUrl, path, body, token, function (data) {
        onOk(_norm(data));
    }, onErr, BROADCAST_TIMEOUT);
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
