import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/AccountService.js" as AccountService
import "../services/PostService.js" as PostService
import "../services/VideoService.js" as VideoService
import "../services/BlockedUsers.js" as BlockedUsers

Page {
    id: page

    property string username: ""
    property var profile: null
    property bool profileLoading: false
    // Wider reading column on desktop/tablet so the profile doesn't sit as a thin
    // strip in the detail panel; phones stay full-width (parent.width wins the min).
    readonly property real maxContentWidth: Config.wideMode ? units.gu(72) : units.gu(60)

    // `st` is mutated in place, so `rev` is bumped to make `cur*` bindings re-evaluate
    property int tab: 0          // 0 posts, 1 gallery, 2 video
    property int rev: 0
    property var st: ({
        0: { offset: 0, loading: false, end: false, loaded: false },
        1: { offset: 0, loading: false, end: false, loaded: false },
        2: { offset: 0, loading: false, end: false, loaded: false }
    })

    readonly property bool isSelf: Session.isLoggedIn && username === Session.username
    property bool isBlocked: false
    property bool blockLoading: false
    readonly property var curModel: tab === 0 ? m0 : tab === 1 ? m1 : m2
    readonly property bool curLoading: rev >= 0 && st[tab].loading
    readonly property bool curEnd: rev >= 0 && st[tab].end
    readonly property bool curLoaded: rev >= 0 && st[tab].loaded

    header: Item { height: 0 }

    ListModel { id: m0; dynamicRoles: true }   // posts
    ListModel { id: m1; dynamicRoles: true }   // gallery
    ListModel { id: m2; dynamicRoles: true }   // video

    function modelFor(t) { return t === 0 ? m0 : t === 1 ? m1 : m2; }

    function loadProfile() {
        page.profileLoading = true;
        AccountService.profile(Config.baseUrl, username, Session.token,
            function (user) { page.profileLoading = false; page.profile = user; },
            function (err) { page.profileLoading = false; /* header falls back to @username */ });
    }

    function loadFollow() {
        if (!Session.isLoggedIn || isSelf) return;
        FollowStore.load(Config.baseUrl, Session.username, username);
    }

    function loadBlockStatus() {
        if (!Session.isLoggedIn || isSelf) return;
        AccountService.listBlocked(Config.baseUrl, Session.token, function (list) {
            for (var i = 0; i < list.length; i++) {
                if (list[i] === page.username) { page.isBlocked = true; return; }
            }
            page.isBlocked = false;
        }, function (err) { /* silent */ });
    }

    function toggleBlock() {
        if (!Session.isLoggedIn) { page.pageStack.push(Qt.resolvedUrl("LoginPage.qml")); return; }
        if (page.blockLoading) return;   // ignore a second tap while in flight
        page.blockLoading = true;
        var action = page.isBlocked ? "REMOVE" : "ADD"
        AccountService.toggleBlock(Config.baseUrl, Session.token, page.username, action,
            function () {
                page.blockLoading = false;
                page.isBlocked = !page.isBlocked;
                Toast.show(page.isBlocked
                    ? Lang.tr("@%1 blocked.").arg(page.username)
                    : Lang.tr("@%1 unblocked.").arg(page.username));
                if (page.isBlocked) { BlockedUsers.add(page.username); PostActions.userBlocked(page.username); }
                else { BlockedUsers.remove(page.username); PostActions.userUnblocked(page.username); }
            },
            function (err) {
                page.blockLoading = false;
                Toast.error((err && err.message) ? err.message : Lang.tr("Failed to update block."));
            });
    }

    function toggleFollow() {
        if (!Session.isLoggedIn) { page.pageStack.push(Qt.resolvedUrl("LoginPage.qml")); return; }
        var now = FollowStore.toggle(Config.baseUrl, username, Session.token);
        Toast.show(now ? Lang.tr("Following") : Lang.tr("Unfollowed"));
        if (page.profile) {
            var pr = page.profile;
            pr.followers = Math.max(0, (pr.followers || 0) + (now ? 1 : -1));
            page.profile = pr;   // reassign so the bound stats update
        }
    }

    function selectTab(t) {
        if (t === page.tab) return;
        page.tab = t;
        var s = st[t];
        if (!s.loaded && !s.loading) loadTab(t);
    }

    // Fetch the next page for tab `t` (lazily; safe to call repeatedly).
    function loadTab(t) {
        var s = st[t];
        if (s.loading || s.end) return;
        s.loading = true; rev++;
        var mdl = modelFor(t);
        function ok(items, rawCount) {
            s.loading = false; s.loaded = true;
            for (var i = 0; i < items.length; i++) mdl.append(items[i]);
            s.offset += rawCount;
            if (rawCount < Config.pageSize) s.end = true;
            rev++;
        }
        function err(e) { s.loading = false; s.loaded = true; rev++; }

        if (t === 0)
            PostService.listByAuthor(Config.baseUrl, username,
                { limit: Config.pageSize, offset: s.offset }, Session.token, ok, err);
        else if (t === 1)
            PostService.listGalleryByAuthor(Config.baseUrl, username,
                { limit: Config.pageSize, offset: s.offset }, Session.token, ok, err);
        else
            VideoService.listVideos(Config.baseUrl,
                { author: username, limit: Config.pageSize, offset: s.offset }, Session.token, ok, err);
    }

    // Reset and reload a tab from scratch (after an edit changed its content).
    function refreshTab(t) {
        var s = st[t];
        s.offset = 0; s.loading = false; s.end = false; s.loaded = false;
        modelFor(t).clear();
        rev++;
        loadTab(t);
    }

    function openPost(p) { page.pageStack.push(Qt.resolvedUrl("PostDetailPage.qml"), { author: p.author, permlink: p.permlink, title: p.title }); }
    function openGallery(p) { page.pageStack.push(Qt.resolvedUrl("GalleryDetailPage.qml"), { author: p.author, permlink: p.permlink }); }
    function openVideo(v) { page.pageStack.push(Qt.resolvedUrl("VideoDetailPage.qml"), { video: v }); }

    // Remove a hidden post from whichever tab holds it (the action sheet is shared).
    function removeRow(permlink) {
        var models = [m0, m1, m2];
        for (var k = 0; k < models.length; k++) {
            var mdl = models[k];
            for (var i = 0; i < mdl.count; i++) {
                if (mdl.get(i).permlink === permlink) { mdl.remove(i); break; }
            }
        }
    }

    Connections {
        target: PostActions
        function onHideRequested(author, permlink) { page.removeRow(permlink); }
        function onPostDeleted(author, permlink) { page.removeRow(permlink); }
        function onCommentCountChanged(permlink, count) {
            var models = [m0, m1, m2];
            for (var k = 0; k < models.length; k++)
                for (var i = 0; i < models[k].count; i++)
                    if (models[k].get(i).permlink === permlink) { models[k].setProperty(i, "comments", count); return; }
        }
        function onPostUpdated(author, permlink, title, body) {
            var models = [m0, m1, m2];
            for (var k = 0; k < models.length; k++) {
                var mdl = models[k];
                for (var i = 0; i < mdl.count; i++) {
                    if (mdl.get(i).permlink === permlink) {
                        mdl.setProperty(i, "title", title);
                        mdl.setProperty(i, "body", body);
                        break;
                    }
                }
            }
        }
        // Sync if blocked/unblocked elsewhere, or a stale state re-sends a duplicate block the backend rejects with a 400.
        function onUserBlocked(username) { if (username === page.username) page.isBlocked = true; }
        function onUserUnblocked(username) { if (username === page.username) page.isBlocked = false; }
        function onEditRequested(post) {
            if (!page.visible) return;
            var t = page.tab;
            var url = t === 1 ? "CreateGalleryPostPage.qml" : "CreatePostPage.qml";
            var ed = page.pageStack.push(Qt.resolvedUrl(url), { editPost: post });
            if (ed && ed.saved) ed.saved.connect(function () { page.refreshTab(t); });
        }
    }

    Component.onCompleted: { loadProfile(); loadFollow(); loadBlockStatus(); loadTab(0); }

    Component {
        id: blockDialog
        Dialog {
            id: dlg
            title: page.isBlocked ? Lang.tr("Unblock user?") : Lang.tr("Block user?")
            text: page.isBlocked
                ? Lang.tr("@%1 will be able to see your posts and interact with you again.").arg(page.username)
                : Lang.tr("@%1 will no longer be able to see your posts or interact with you.").arg(page.username)

            Button {
                text: page.isBlocked ? Lang.tr("Unblock") : Lang.tr("Block")
                color: Style.danger
                onClicked: { PopupUtils.close(dlg); page.toggleBlock(); }
            }
            Button {
                text: Lang.tr("Cancel")
                onClicked: PopupUtils.close(dlg)
            }
        }
    }

    ListView {
        id: list
        anchors { top: parent.top; bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
        width: Math.min(parent.width, page.maxContentWidth)
        clip: true
        model: page.curModel
        cacheBuffer: units.gu(12)

        header: Item {
            width: list.width
            height: headerCol.height

            Column {
                id: headerCol
                width: parent.width

                // --- Cover banner ----------------------------------------
                Item {
                    width: parent.width
                    height: units.gu(20)
                    clip: true

                    Rectangle {           // brand fallback when no cover
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Style.brand }
                            GradientStop { position: 1.0; color: Style.brandDark }
                        }
                    }
                    Image {
                        anchors.fill: parent
                        source: page.profile && page.profile.coverUrl ? page.profile.coverUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        autoTransform: true
                        sourceSize.width: list.width
                        visible: status === Image.Ready
                    }

                    // Block button — top-right corner of cover
                    AbstractButton {
                        visible: !page.isSelf && !!page.profile
                        enabled: !page.blockLoading
                        anchors {
                            top: parent.top
                            right: parent.right
                            topMargin: Style.spacingS
                            rightMargin: Style.spacingS
                        }
                        width: units.gu(4); height: units.gu(4)
                        z: 10
                        onClicked: PopupUtils.open(blockDialog)

                        // Scrim disc so the control stays legible over any cover
                        // photo and in both themes: dark by default, solid red
                        // once the user is blocked.
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: page.isBlocked
                                ? Qt.rgba(Style.danger.r, Style.danger.g, Style.danger.b, 0.92)
                                : Qt.rgba(0, 0, 0, 0.38)
                        }
                        // Prohibition / "no entry" mark — drawn as a vector (the
                        // Suru theme has no "block" icon; this is the same shape
                        // PostActionSheet uses), dropping the custom PNG asset.
                        // White so it reads on the dark/red scrim.
                        Item {
                            anchors.centerIn: parent
                            width: units.gu(2.4); height: width
                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: "transparent"
                                border.width: units.dp(2)
                                border.color: "white"
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width * 0.7; height: units.dp(2)
                                color: "white"
                                rotation: 45
                            }
                        }
                    }
                }

                // --- Avatar (overlaps the cover) -------------------------
                Item {
                    width: parent.width
                    height: units.gu(6)            // reserves the avatar's lower half

                    Item {
                        id: avatarHolder
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: -units.gu(5.8)
                        width: units.gu(11.6); height: width

                        Rectangle {                // white ring
                            anchors.fill: parent
                            radius: width / 2
                            color: Style.surface
                        }
                        Rectangle {                // letter fallback
                            anchors.fill: parent
                            anchors.margins: units.gu(0.3)
                            radius: width / 2
                            color: Style.avatarTint("")
                            visible: !(page.profile && page.profile.profileUrl)
                            Label {
                                anchors.centerIn: parent
                                text: (page.username || "?").charAt(0).toUpperCase()
                                font.pixelSize: units.gu(5)
                                font.bold: true
                                color: Style.brand
                            }
                        }
                        CircleImage {
                            anchors.fill: parent
                            anchors.margins: units.gu(0.3)
                            source: page.profile && page.profile.profileUrl ? page.profile.profileUrl : ""
                            decode: units.gu(23)
                            visible: !!(page.profile && page.profile.profileUrl)
                        }
                    }
                }

                Item { width: 1; height: Style.spacingS }

                // --- Name / @username / bio ------------------------------
                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: page.profile && page.profile.fullName ? page.profile.fullName : page.username
                    font.pixelSize: Style.fontLarge
                    font.weight: Font.DemiBold
                    font.family: Style.fontFor(text)
                    color: Style.textTitle
                    elide: Text.ElideRight
                }
                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "@" + page.username
                    font.pixelSize: Style.fontSmall
                    font.family: Style.fontFor(text)
                    color: Style.brand
                }
                Item { width: 1; height: Style.spacingXs; visible: bioLabel.visible }
                Text {
                    id: bioLabel
                    width: Math.min(parent.width - Style.spacingL * 2, units.gu(50))
                    anchors.horizontalCenter: parent.horizontalCenter
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.RichText
                    text: {
                        var html = page.profile ? (page.profile.bioHtml || page.profile.bio || "") : ""
                        return html.replace(/((?:<a\s[^>]*>[\s\S]*?<\/a>)|https?:\/\/[^\s<>"]+)/g,
                            function(match) {
                                if (match.charAt(0) === '<') return match
                                return '<a href="' + match + '" style="color:' + Style.brand + ';">' + match + '</a>'
                            })
                    }
                    visible: page.profile && (page.profile.bio || "").length > 0
                    font.pixelSize: Style.fontRegular
                    font.family: Style.fontFor(text)
                    color: Style.textSecondary
                    wrapMode: Text.Wrap
                    onLinkActivated: Qt.openUrlExternally(link)
                }

                Item { width: 1; height: Style.spacingM }

                // --- Stats skeleton (while loading) ----------------------
                Row {
                    width: Math.min(parent.width, units.gu(45))
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !page.profile && page.profileLoading
                    Repeater {
                        model: 3
                        delegate: Column {
                            width: parent.width / 3
                            spacing: units.dp(4)
                            SequentialAnimation on opacity {
                                running: true; loops: Animation.Infinite
                                NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                            }
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: units.gu(5); height: units.gu(2.5)
                                radius: units.dp(4); color: Style.divider
                            }
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: units.gu(4); height: units.gu(1.5)
                                radius: units.dp(4); color: Style.divider
                            }
                        }
                    }
                }

                // --- Stats -----------------------------------------------
                Row {
                    width: Math.min(parent.width, units.gu(45))
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !!page.profile
                    Repeater {
                        model: page.profile ? [
                            { label: Lang.tr("Posts"),     value: "" + page.profile.postCount },
                            { label: Lang.tr("Followers"), value: "" + page.profile.followers },
                            { label: Lang.tr("Following"), value: "" + page.profile.following }
                        ] : []
                        delegate: Column {
                            width: parent.width / 3
                            spacing: units.dp(2)
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.value
                                font.pixelSize: Style.fontLarge
                                font.weight: Font.DemiBold
                                font.family: Style.fontFor(text)
                                color: Style.textPrimary
                            }
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.label
                                font.pixelSize: Style.fontXSmall
                                font.family: Style.fontFor(text)
                                color: Style.textSecondary
                            }
                        }
                    }
                }

                Item { width: 1; height: Style.spacingM }

                // --- Follow button skeleton ------------------------------
                Rectangle {
                    visible: !page.isSelf && !page.profile && page.profileLoading
                    width: Math.min(parent.width - Style.spacingL * 2, units.gu(50))
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: units.gu(5); radius: Style.cardRadius
                    color: Style.divider
                    SequentialAnimation on opacity {
                        running: true; loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                    }
                }

                // --- Follow button (hidden on own profile or while loading) ---
                PrimaryButton {
                    visible: !page.isSelf && !!page.profile
                    width: Math.min(parent.width - Style.spacingL * 2, units.gu(50))
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: FollowStore.isFollowing(page.username) ? Lang.tr("Following") : Lang.tr("Follow")
                    onClicked: page.toggleFollow()
                }

                Item { width: 1; height: Style.spacingM }

                // --- Content tabs ----------------------------------------
                SectionTabs {
                    width: parent.width
                    model: [Lang.tr("Posts"), Lang.tr("Gallery"), Lang.tr("Video")]
                    currentIndex: page.tab
                    onSelected: page.selectTab(index)
                }
            }
        }

        // One delegate that becomes the right card for the active tab.
        delegate: Loader {
            width: list.width
            height: item ? item.implicitHeight : 0
            property var rowData: page.curModel.get(index)
            sourceComponent: page.tab === 0 ? cPost : page.tab === 1 ? cGallery : cVideo
        }

        footer: Item {
            width: list.width
            height: units.gu(7)
            ActivityIndicator {
                anchors.centerIn: parent
                running: page.curLoading && page.curModel.count > 0
                visible: running
            }
            Label {
                anchors.centerIn: parent
                visible: page.curLoaded && page.curModel.count === 0 && !page.curLoading
                text: page.tab === 0 ? Lang.tr("No posts yet")
                    : page.tab === 1 ? Lang.tr("No gallery posts yet")
                    : Lang.tr("No videos yet")
                font.family: Style.fontFor(text)
                color: Style.textSecondary
            }
        }

        onAtYEndChanged: {
            if (atYEnd && !page.curLoading && !page.curEnd && page.curModel.count > 0)
                page.loadTab(page.tab);
        }

        // Prefetch ~2 screens early (see NewsPage) — atYEnd stays as fallback.
        onContentYChanged: {
            if (!page.curLoading && !page.curEnd && page.curModel.count > 0
                    && contentHeight > height
                    && contentY + height >= contentHeight - height * 2)
                page.loadTab(page.tab);
        }
    }

    // --- Card components, picked per tab by the delegate Loader --------------
    Component {
        id: cPost
        PostCard {
            width: parent ? parent.width : list.width
            post: rowData
            onClicked: page.openPost(rowData)
            onMoreClicked: PostActions.open(rowData, "blog")
            onRequireLogin: page.pageStack.push(Qt.resolvedUrl("LoginPage.qml"))
        }
    }
    Component {
        id: cGallery
        GalleryCard {
            width: parent ? parent.width : list.width
            post: rowData
            showFollow: false       // redundant on this user's own profile
            onClicked: page.openGallery(rowData)
            onMoreClicked: PostActions.open(rowData, "gallery")
            onRequireLogin: page.pageStack.push(Qt.resolvedUrl("LoginPage.qml"))
        }
    }
    Component {
        id: cVideo
        VideoCard {
            width: parent ? parent.width : list.width
            video: rowData
            onClicked: page.openVideo(rowData)
            onMoreClicked: PostActions.open(rowData, "video")
        }
    }


    // Fixed overlay (not in the scrolling header) so it's always visible
    BackButton {
        anchors { left: parent.left; top: parent.top; leftMargin: Style.spacingS; topMargin: Style.spacingS }
        z: 100
        overlay: true
        onClicked: page.pageStack.pop()
    }
}
