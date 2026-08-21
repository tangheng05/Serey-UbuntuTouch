import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/PostService.js" as PostService
import "../services/VideoService.js" as VideoService

// Editing a video's title/description used to be a step inside PostActionSheet. A text editor in a
// bottom sheet fights the toolkit: the field ends up nested in the sheet's own flick, and Lomiri's
// selection handles compensate for scrolling only through the input's internal flickable, so
// selecting across a scrolling field never worked. A plain page is the environment the toolkit is
// built for, and it also gets a real back button instead of a tap-outside that discards the edit.
Page {
    id: page

    // The video being edited (a view-model row from any feed).
    property var post: null

    property bool saving: false

    // Same caps CreateVideoPage enforces on new videos.
    readonly property int titleMaxLength: 100
    readonly property int descMaxLength: 2500

    readonly property string origTitle: post ? (post.title || "") : ""
    readonly property string origBody: post ? page._htmlToPlain(post.body || "") : ""
    readonly property bool dirty: titleField.text !== origTitle || descField.text !== origBody

    header: PageHeader {
        title: Lang.tr("Edit caption")
        leadingActionBar.actions: [
            Action { iconName: "back"; text: Lang.tr("Back"); onTriggered: page.pageStack.pop() }
        ]
    }

    // The API stores the description as HTML; the editor is plain text.
    function _htmlToPlain(html) {
        return (html || "")
            .replace(/<\/p>\s*<p[^>]*>/gi, "\n")
            .replace(/<br\s*\/?>/gi, "\n")
            .replace(/<[^>]+>/g, "")
            .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
            .replace(/&quot;/g, "\"").replace(/&#39;/g, "'").replace(/&nbsp;/g, " ")
            .trim();
    }
    function _plainToHtml(text) {
        var lines = (text || "").split(/\n+/);
        var out = [];
        for (var i = 0; i < lines.length; i++) {
            var t = lines[i].trim();
            if (t.length === 0) continue;
            t = t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
            out.push("<p>" + t + "</p>");
        }
        return out.join("");
    }

    // Reuses create-or-update with the existing permlink; every other field is resent unchanged.
    function save() {
        if (!post || page.saving) return;
        var newTitle = titleField.text.trim();
        if (newTitle.length === 0) { Toast.error(Lang.tr("Title can't be empty.")); return; }
        var newBody = page._plainToHtml(descField.text);
        page.saving = true;
        PostService.createVideoPost(Config.baseUrl, {
            title: newTitle,
            desc: newBody,
            permlink: post.permlink || "",
            videoUrl: post.videoLink || "",
            thumbUrl: post.thumbnail || "",
            communityId: post.communityId || 0,
            communityName: post.community || "",
            postToBlockchain: post.postToBlockchain !== false
        }, Session.token,
            function () {
                page.saving = false;
                PostActions.postUpdated(post.author || "", post.permlink || "", newTitle, newBody);
                Toast.success(Lang.tr("Post updated!"));
                page.pageStack.pop();
            },
            function (err) {
                page.saving = false;
                Toast.error((err && err.message) ? err.message : Lang.tr("Couldn't update post."));
            });
    }

    Component.onCompleted: {
        if (page.post) {
            page.post = {
                author: page.post.author || "",
                permlink: page.post.permlink || "",
                title: page.post.title || "",
                body: page.post.body || "",
                thumbnail: page.post.thumbnail || "",
                videoLink: page.post.videoLink || "",
                community: page.post.community || "",
                communityId: page.post.communityId || 0,
                postToBlockchain: page.post.postToBlockchain !== false
            };
        }
        titleField.text = page.origTitle;
        descField.text = page.origBody;
        titleField.forceActiveFocus();
        if (page.post && (!(page.post.communityId > 0) || !page.post.community)) {
            var author = page.post.author || "";
            var permlink = page.post.permlink || "";
            if (author && permlink) {
                VideoService.detail(Config.baseUrl, author, permlink, Session.token,
                    function (v) {
                        if (!v || !page.post) return;
                        page.post = Object.assign({}, page.post, {
                            communityId: v.communityId || page.post.communityId,
                            community: v.community || page.post.community,
                            postToBlockchain: v.postToBlockchain
                        });
                    },
                    function (err) { /* best-effort; save() still has its old fallback */ });
            }
        }
    }

    // Only the form scrolls; the description keeps its own scrolling so the toolkit's selection
    // handles and their auto-scroll operate on the flickable they were written against.
    Flickable {
        id: form
        anchors { top: page.header.bottom; bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
        width: Math.min(parent.width, units.gu(60))
        contentHeight: col.height
        clip: true
        interactive: contentHeight > height
        // Keep the caret clear of the on-screen keyboard.
        bottomMargin: Qt.inputMethod.visible ? Qt.inputMethod.keyboardRectangle.height : 0

        Column {
            id: col
            width: parent.width
            spacing: 0

            Item { width: 1; height: Style.spacingM }

            // Shows which community this edit will be saved into, so a mismatch is visible
            // before hitting Save instead of only surfacing as a backend rejection.
            Label {
                x: Style.spacingM
                width: parent.width - Style.spacingM * 2
                text: Lang.tr("Community: %1 (#%2)").arg((page.post && page.post.community) || "?")
                                                      .arg((page.post && page.post.communityId) || 0)
                font.pixelSize: Style.fontXSmall
                color: Style.textSecondary
                elide: Text.ElideRight
            }
            Item { width: 1; height: Style.spacingXs }

            Label {
                x: Style.spacingM
                text: Lang.tr("Title")
                font.pixelSize: Style.fontSmall
                font.weight: Font.DemiBold
                font.family: Style.fontFor(text)
                color: Style.textSecondary
            }
            Item { width: 1; height: Style.spacingXs }
            TextField {
                id: titleField
                width: parent.width - Style.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                enabled: !page.saving
                placeholderText: Lang.tr("Title")
                font.family: Style.fontFor(text)
                maximumLength: page.titleMaxLength
                onAccepted: descField.forceActiveFocus()
            }
            Label {
                x: Style.spacingM
                width: parent.width - Style.spacingM * 2
                horizontalAlignment: Text.AlignRight
                text: titleField.text.length + "/" + page.titleMaxLength
                font.pixelSize: Style.fontXSmall
                color: titleField.text.length >= page.titleMaxLength ? Style.danger : Style.textSecondary
            }

            Item { width: 1; height: Style.spacingM }

            Label {
                x: Style.spacingM
                text: Lang.tr("Description")
                font.pixelSize: Style.fontSmall
                font.weight: Font.DemiBold
                font.family: Style.fontFor(text)
                color: Style.textSecondary
            }
            Item { width: 1; height: Style.spacingXs }
            TextArea {
                id: descField
                width: parent.width - Style.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                enabled: !page.saving
                placeholderText: Lang.tr("Description")
                wrapMode: Text.Wrap
                font.family: Style.fontFor(text)
                // Fills the page rather than a fixed few lines: the taller the box, the less of the
                // caption sits outside it, which is what made selecting across it painful.
                height: Math.max(units.gu(14), form.height - form.bottomMargin - units.gu(32))
                // TextArea has no native maximumLength (unlike TextField)
                onTextChanged: if (text.length > page.descMaxLength) {
                    var cp = cursorPosition;
                    text = text.substring(0, page.descMaxLength);
                    cursorPosition = Math.min(cp, text.length);
                }
            }
            Label {
                x: Style.spacingM
                width: parent.width - Style.spacingM * 2
                horizontalAlignment: Text.AlignRight
                text: descField.text.length + "/" + page.descMaxLength
                font.pixelSize: Style.fontXSmall
                color: descField.text.length >= page.descMaxLength ? Style.danger : Style.textSecondary
            }

            Item { width: 1; height: Style.spacingL }

            AbstractButton {
                width: parent.width - Style.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                height: units.gu(6)
                enabled: !page.saving && page.dirty
                onClicked: page.save()

                Rectangle {
                    anchors.fill: parent
                    radius: Style.cardRadius
                    color: Style.brand
                    opacity: parent.enabled ? 1 : 0.5
                }
                Label {
                    anchors.centerIn: parent
                    text: page.saving ? Lang.tr("Saving…") : Lang.tr("Save")
                    font.pixelSize: Style.fontMedium
                    font.weight: Font.DemiBold
                    font.family: Style.fontFor(text)
                    color: Style.textOnBrand
                }
            }

            Item { width: 1; height: Style.spacingL }
        }
    }
}
