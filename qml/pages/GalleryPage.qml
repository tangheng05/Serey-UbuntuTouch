import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"
import "../components"
import "../services/PostService.js" as PostService

/*
 * Gallery feed: image-only posts from the selected regional source
 * (community_id from Config), rendered as swipeable carousels via
 * GalleryCard. Mirrors NewsPage's pagination/reload pattern.
 */
Page {
    id: page

    property int offset: 0
    property bool loading: false
    property bool endReached: false
    property string errorMsg: ""
    // Request generation: bumped on reload() so a late response from a previous
    // community can't append stale rows into the freshly-cleared model.
    property int reqEpoch: 0
    property var inflight: null

    header: Item { height: 0 }

    ListModel { id: galleryModel; dynamicRoles: true }

    Connections {
        target: Config
        function onSourceIndexChanged() { page.reload(); }
    }

    Connections {
        target: PostActions
        function onHideRequested(author, permlink) {
            for (var i = 0; i < galleryModel.count; i++) {
                if (galleryModel.get(i).permlink === permlink) {
                    galleryModel.remove(i);
                    Toast.show(i18n.tr("Post hidden"));
                    return;
                }
            }
        }
    }

    function reload() {
        page.reqEpoch++;
        if (inflight) { inflight.abort(); inflight = null; }
        offset = 0;
        endReached = false;
        loading = false;
        errorMsg = "";
        galleryModel.clear();
        loadMore();
    }

    function loadMore() {
        if (loading || endReached) return;
        loading = true;
        errorMsg = "";
        var epoch = page.reqEpoch;
        var params = { limit: Config.pageSize, offset: page.offset };
        if (Config.communityId > 0)
            params.community_id = Config.communityId;
        inflight = PostService.listGallery(Config.baseUrl, params, Session.token,
            function (result, rawCount) {
                if (epoch !== page.reqEpoch) return;   // stale response — ignore
                inflight = null;
                loading = false;
                for (var i = 0; i < result.length; i++)
                    galleryModel.append(result[i]);
                // Advance by RAW server count (not the image-filtered length) so
                // the next page doesn't re-request already-seen rows.
                page.offset += rawCount;
                if (rawCount < Config.pageSize) page.endReached = true;
            },
            function (err) {
                if (epoch !== page.reqEpoch) return;
                inflight = null;
                loading = false;
                page.errorMsg = err.message;
            });
    }

    Component.onCompleted: loadMore()

    ListView {
        id: list
        anchors.fill: parent
        clip: true
        model: galleryModel
        cacheBuffer: units.gu(12)

        delegate: GalleryCard {
            width: list.width
            post: galleryModel.get(index)
            onClicked: {
                var p = galleryModel.get(index);
                page.pageStack.push(Qt.resolvedUrl("GalleryDetailPage.qml"),
                    { author: p.author, permlink: p.permlink });
            }
            onAuthorClicked: page.pageStack.push(Qt.resolvedUrl("ProfileViewPage.qml"),
                { username: galleryModel.get(index).author })
            onRequireLogin: page.pageStack.push(Qt.resolvedUrl("LoginPage.qml"))
            onMoreClicked: PostActions.open(galleryModel.get(index))
        }

        // Constant-height footer: a conditional height feeds back into
        // contentHeight/atYEnd and trips a "height" binding loop.
        footer: Item {
            width: list.width
            height: units.gu(6)
            ActivityIndicator {
                anchors.centerIn: parent
                running: page.loading && galleryModel.count > 0
                visible: running
            }
        }

        onAtYEndChanged: {
            if (atYEnd && !page.loading && !page.endReached && galleryModel.count > 0)
                page.loadMore();
        }
    }

    LoadingState {
        anchors.fill: list
        visible: page.loading && galleryModel.count === 0
    }
    ErrorState {
        anchors.fill: list
        visible: page.errorMsg !== "" && galleryModel.count === 0
        message: page.errorMsg
        onRetry: page.reload()
    }
    EmptyState {
        anchors.fill: list
        visible: !page.loading && page.errorMsg === "" && galleryModel.count === 0
        iconName: "image-x-generic-symbolic"
        message: i18n.tr("No gallery posts in %1").arg(Config.communityName)
    }

    // Floating compose button
    AbstractButton {
        visible: Session.isLoggedIn
        anchors {
            right: parent.right
            bottom: parent.bottom
            rightMargin: Style.spacingM
            bottomMargin: Style.spacingM
        }
        width: units.gu(5.5); height: width
        z: 10
        onClicked: {
            page.pageStack.push(Qt.resolvedUrl("CreateGalleryPostPage.qml"))
        }

        Rectangle {
            anchors.fill: parent
            radius: units.dp(14)
            color: Style.brand
        }
        Icon {
            anchors.centerIn: parent
            width: units.gu(2.5); height: width
            name: "edit"
            color: Style.textOnBrand
        }
    }
}
