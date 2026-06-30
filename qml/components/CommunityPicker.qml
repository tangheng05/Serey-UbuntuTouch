import QtQuick 2.7
import Lomiri.Components 1.3
import QtGraphicalEffects 1.0
import "../Theme"
import "../Session"
import "../services/CommunitySubscriberService.js" as SubscriberService

/*
 * Bottom-sheet community picker. Each top-level source (Global / NL / US) has
 * a chevron that expands to show sub-communities fetched from
 * GET /community/categories/list?community_id=X, grouped by category.
 * Sub-community results are cached per source so we only fetch once.
 */
Item {
    id: picker
    anchors.fill: parent
    visible: false
    z: 1500

    // Which source row is currently expanded (-1 = none).
    property int expandedIndex: -1
    // Per-source cache: null = not fetched yet, [] = fetched but empty, [...] = data.
    property var cache: [null, null, null, null]
    property int loadingIndex: -1
    // Map of communityId (string) → true for communities the user is subscribed to.
    property var subscribedMap: ({})
    property int subscribedRev: 0
    property bool subscriptionsLoaded: false

    function open() {
        picker.visible = true
        cpBackdropFade.start()
        cpSlide.start()
        if (Session.isLoggedIn && !subscriptionsLoaded) _loadSubscriptions()
    }
    function close()         { picker.visible = false }
    function closeAnimated() { cpBackdropFadeOut.start(); cpSlideOut.start() }

    function _loadSubscriptions() {
        picker.subscriptionsLoaded = true  // mark before call so retries don't stack
        SubscriberService.fetchSubscribed(Config.baseUrl, Session.token,
            function (map) { picker.subscribedMap = map; picker.subscribedRev++ },
            function () { /* silent — picker still works without subscription data */ })
    }

    function _toggleSubscribe(commId, currentlySubscribed) {
        if (!Session.isLoggedIn) { Toast.show(i18n.tr("Log in to subscribe")); return }
        var id = String(commId)
        function _newMap(add) {
            var m = {}
            for (var k in picker.subscribedMap) m[k] = true
            if (add) m[id] = true
            else delete m[id]
            return m   // new object → QML detects the change and re-evaluates bindings
        }

        if (currentlySubscribed) {
            SubscriberService.unsubscribe(Config.baseUrl, Session.token, id,
                function () { picker.subscribedMap = _newMap(false); picker.subscribedRev++; Toast.show(i18n.tr("Unsubscribed")) },
                function (err) { Toast.show(err.message || i18n.tr("Failed to unsubscribe")) })
        } else {
            SubscriberService.subscribe(Config.baseUrl, Session.token, id,
                function () { picker.subscribedMap = _newMap(true); picker.subscribedRev++; Toast.show(i18n.tr("Subscribed!")) },
                function (err) { Toast.show(err.message || i18n.tr("Failed to subscribe")) })
        }
    }

    function _fetch(srcIndex) {
        if (picker.cache[srcIndex] !== null) return
        picker.loadingIndex = srcIndex

        // All sources: step 1 — fetch the correct communities for this source,
        // step 2 — fetch categories list and build id→categoryName map,
        // step 3 — group step-1 communities by their category.
        // Global (srcIndex 0) uses categories/list directly since list-by-parent-id/1
        // returns only the top-level regional hubs, not the individual communities.

        var apiId = Config.sources[srcIndex].id
        if (apiId === 0) apiId = 1

        function _parseCategoryList(raw) {
            // raw is the top-level parsed JSON; handle every known shape
            var arr = raw.communities || raw.results || raw.items
                      || (Array.isArray(raw.data) ? raw.data
                          : (raw.data && (raw.data.communities || raw.data.results || raw.data.items)))
                      || []
            return arr
        }

        function _catMeta(cat, i) {
            return {
                name:  cat.category_name || cat.name || cat.title || cat.label || ("Category " + (i + 1)),
                icon:  cat.icon || cat.icon_url || cat.image_url || "",
                color: cat.color || cat.color_code || cat.background_color || "#17A77E"
            }
        }

        function _sortCats(cats) {
            // Move any category named "OTHERS" (case-insensitive) to the bottom
            var others = [], rest = []
            for (var i = 0; i < cats.length; i++) {
                if (cats[i].name.toUpperCase() === "OTHERS") others.push(cats[i])
                else rest.push(cats[i])
            }
            return rest.concat(others)
        }

        function _buildFromCategoryList(arr) {
            var cats = []
            for (var i = 0; i < arr.length; i++) {
                var cat = arr[i]
                var subs = cat.communities || cat.sub_communities || cat.children || cat.items || cat.results || []
                if (subs.length === 0) continue
                var meta = _catMeta(cat, i)
                cats.push({ name: meta.name, icon: meta.icon, color: meta.color, communities: subs })
            }
            return _sortCats(cats)
        }

        function _applyCategories(sourceComms, catArr) {
            // Build community_category_id → {name, icon, color} map
            // Communities from list-by-parent-id carry community_category_id;
            // categories from categories/list also carry community_category_id.
            var catMap = {}
            for (var i = 0; i < catArr.length; i++) {
                var meta = _catMeta(catArr[i], i)
                var catId = String(catArr[i].community_category_id || catArr[i].id || catArr[i]._id || "")
                if (catId) catMap[catId] = meta
            }
            var groups = {}, order = [], metaByKey = {}
            for (var k = 0; k < sourceComms.length; k++) {
                var comm = sourceComms[k]
                var catId = String(comm.community_category_id || "")
                var m = catMap[catId] || { name: "", icon: "", color: "" }
                var key = m.name
                if (!groups[key]) { groups[key] = []; order.push(key); metaByKey[key] = m }
                groups[key].push(comm)
            }
            var cats = []
            for (var n = 0; n < order.length; n++) {
                var k2 = order[n]
                cats.push({ name: k2, icon: metaByKey[k2].icon, color: metaByKey[k2].color, communities: groups[k2] })
            }
            return _sortCats(cats)
        }

        function _store(si, cats) {
            var nc = []
            for (var i = 0; i < picker.cache.length; i++) nc.push(picker.cache[i])
            nc[si] = cats
            picker.cache = nc
            picker.loadingIndex = -1
        }

        if (srcIndex === 0) {
            // Global: fetch both Netherlands (99) and US (26) and combine
            var regionalIds = []
            for (var ri = 1; ri < Config.sources.length; ri++)
                regionalIds.push(Config.sources[ri].id)
            var allComms = [], pending = regionalIds.length

            function _onRegionalDone() {
                pending--
                if (pending > 0) return
                if (allComms.length === 0) { _store(0, []); return }
                var xhrCat = new XMLHttpRequest()
                xhrCat.open("GET", Config.baseUrl + "/community/categories/list?limit=100")
                xhrCat.setRequestHeader("Accept", "application/json")
                xhrCat.timeout = 15000
                xhrCat.onreadystatechange = function () {
                    if (xhrCat.readyState !== XMLHttpRequest.DONE) return
                    var cats = []
                    try {
                        var arr = _parseCategoryList(JSON.parse(xhrCat.responseText))
                        cats = _applyCategories(allComms, arr)
                    } catch (e) { }
                    cats = cats.filter(function(c) { return c.name.length > 0 })
                    if (cats.length === 0) cats = [{ name: "", icon: "", color: "", communities: allComms }]
                    _store(0, cats)
                }
                xhrCat.send(null)
            }

            for (var gi = 0; gi < regionalIds.length; gi++) {
                (function(rid) {
                    var xhr = new XMLHttpRequest()
                    xhr.open("GET", Config.baseUrl + "/community/list-by-parent-id/" + rid)
                    xhr.setRequestHeader("Accept", "application/json")
                    xhr.timeout = 15000
                    xhr.onreadystatechange = function () {
                        if (xhr.readyState !== XMLHttpRequest.DONE) return
                        try {
                            var d = JSON.parse(xhr.responseText)
                            var comms = d.data || d.communities || d.results || []
                            for (var c = 0; c < comms.length; c++) allComms.push(comms[c])
                        } catch (e) { }
                        _onRegionalDone()
                    }
                    xhr.send(null)
                })(regionalIds[gi])
            }

        } else {
            // Netherlands / US: step 1 — get communities for this source
            var xhrP = new XMLHttpRequest()
            xhrP.open("GET", Config.baseUrl + "/community/list-by-parent-id/" + apiId)
            xhrP.setRequestHeader("Accept", "application/json")
            xhrP.timeout = 15000
            xhrP.onreadystatechange = function () {
                if (xhrP.readyState !== XMLHttpRequest.DONE) return
                var sourceComms = []
                try {
                    var d = JSON.parse(xhrP.responseText)
                    sourceComms = d.data || d.communities || d.results || []
                } catch (e) { }

                if (sourceComms.length === 0) { _store(srcIndex, []); return }

                // Step 2 — fetch categories to try to group them
                var xhrC = new XMLHttpRequest()
                xhrC.open("GET", Config.baseUrl + "/community/categories/list?limit=100")
                xhrC.setRequestHeader("Accept", "application/json")
                xhrC.timeout = 15000
                xhrC.onreadystatechange = function () {
                    if (xhrC.readyState !== XMLHttpRequest.DONE) return
                    var cats = []
                    try {
                        var arr = _parseCategoryList(JSON.parse(xhrC.responseText))
                        cats = _applyCategories(sourceComms, arr)
                    } catch (e) { }
                    // Remove uncategorised group (empty name) — only show properly categorised communities.
                    cats = cats.filter(function(c) { return c.name.length > 0 })
                    // Fallback: if nothing matched any category, show flat without header
                    if (cats.length === 0) cats = [{ name: "", icon: "", color: "", communities: sourceComms }]
                    _store(srcIndex, cats)
                }
                xhrC.send(null)
            }
            xhrP.send(null)
        }
    }

    // ── Backdrop ─────────────────────────────────────────────────────────────
    Rectangle {
        id: cpBackdrop
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.4)
        opacity: 0
        MouseArea { anchors.fill: parent; onClicked: picker.closeAnimated() }
    }
    NumberAnimation { id: cpBackdropFade;    target: cpBackdrop; property: "opacity"; from: 0; to: 1;  duration: 200 }
    NumberAnimation { id: cpBackdropFadeOut; target: cpBackdrop; property: "opacity"; to: 0;            duration: 200 }

    // ── Sheet ─────────────────────────────────────────────────────────────────
    Rectangle {
        id: sheet
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: Math.min(sheetContent.height + units.gu(4), picker.height * 0.82)
        radius: units.dp(16)
        color: Style.surface
        clip: true

        transform: Translate { id: cpTranslate; y: 0 }
        NumberAnimation { id: cpSlide;    target: cpTranslate; property: "y"; from: sheet.height + units.gu(4); to: 0;              duration: 300; easing.type: Easing.OutCubic }
        NumberAnimation { id: cpSlideOut; target: cpTranslate; property: "y"; to: sheet.height + units.gu(4); duration: 250; easing.type: Easing.InCubic; onStopped: picker.close() }

        // Grabber
        Rectangle {
            anchors { top: parent.top; topMargin: Style.spacingS; horizontalCenter: parent.horizontalCenter }
            width: units.gu(4.5); height: units.dp(4); radius: units.dp(2)
            color: Style.lightGray
        }

        // Scrollable content
        Flickable {
            id: flickable
            anchors { fill: parent; topMargin: units.gu(1) }
            contentWidth: width
            contentHeight: sheetContent.height
            clip: true

            Column {
                id: sheetContent
                width: flickable.width

                // ── Header ───────────────────────────────────────────────
                Item { width: 1; height: Style.spacingL }
                Row {
                    width: parent.width - Style.spacingM * 2
                    x: Style.spacingM
                    Label {
                        width: parent.width - units.gu(4)
                        text: i18n.tr("Choose community")
                        font.pixelSize: units.dp(17)
                        font.weight: Font.DemiBold
                        color: Style.textTitle
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    AbstractButton {
                        width: units.gu(3.5); height: units.gu(3.5)
                        onClicked: picker.closeAnimated()
                        Icon { anchors.centerIn: parent; width: units.gu(2.5); height: width; name: "close"; color: Style.textTitle }
                    }
                }
                Item { width: 1; height: Style.spacingM }

                // ── Source rows ──────────────────────────────────────────
                Repeater {
                    model: Config.sources

                    delegate: Column {
                        id: sourceCol
                        width: sheetContent.width
                        property int srcIndex: index
                        property bool isExpanded: picker.expandedIndex === index
                        property var cats: picker.cache[index] || []

                        // Parent row
                        AbstractButton {
                            width: parent.width
                            height: units.gu(7)
                            onClicked: {
                                if (sourceCol.srcIndex === 0) {
                                    // Global: select directly and close — no sub-community dropdown
                                    Config.sourceIndex = 0
                                    Config.selectedSubCommunity = null
                                    picker.expandedIndex = -1
                                    picker.closeAnimated()
                                } else if (picker.expandedIndex === sourceCol.srcIndex) {
                                    picker.expandedIndex = -1
                                } else {
                                    picker.expandedIndex = sourceCol.srcIndex
                                    picker._fetch(sourceCol.srcIndex)
                                    Config.sourceIndex = sourceCol.srcIndex
                                    Config.selectedSubCommunity = null
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: sourceCol.isExpanded ? Style.iconBackground : "transparent"
                            }

                            Row {
                                anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                                spacing: Style.spacingM

                                // Flag / icon
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(5); height: width; radius: width / 2
                                    color: Style.iconBackground
                                    border.width: Config.sourceIndex === index && !Config.selectedSubCommunity ? units.dp(2) : 0
                                    border.color: Style.brand

                                    CircleImage {
                                        id: srcIcon
                                        anchors { fill: parent; margins: units.dp(2) }
                                        source: Config.communityIcon(modelData.dns)
                                    }
                                    Icon {
                                        anchors.centerIn: parent
                                        width: units.gu(2.5); height: width
                                        name: "language-chooser"
                                        color: Config.sourceIndex === index ? Style.brand : Style.textSecondary
                                        visible: !srcIcon.loaded
                                    }
                                }

                                // Name
                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - units.gu(5) - units.gu(3) - Style.spacingM * 2
                                    text: modelData.name
                                    font.pixelSize: Style.fontMedium
                                    font.weight: sourceCol.isExpanded ? Font.DemiBold : Font.Medium
                                    color: sourceCol.isExpanded ? Style.brand : Style.textPrimary
                                    elide: Text.ElideRight
                                }

                                // Chevron (hidden for Global — it selects directly)
                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(2.5); height: width
                                    name: sourceCol.isExpanded ? "go-up" : "go-down"
                                    color: sourceCol.isExpanded ? Style.brand : Style.textSecondary
                                    visible: sourceCol.srcIndex !== 0
                                }
                            }

                            // Bottom divider
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width; height: units.dp(1)
                                color: Style.divider
                            }
                        }

                        // Loading indicator
                        Item {
                            visible: sourceCol.isExpanded && picker.loadingIndex === sourceCol.srcIndex
                            width: parent.width; height: units.gu(5)
                            ActivityIndicator {
                                anchors.centerIn: parent
                                running: parent.visible
                            }
                        }

                        // Sub-communities grouped by category
                        Column {
                            visible: sourceCol.isExpanded && picker.loadingIndex !== sourceCol.srcIndex
                            width: parent.width

                            // Empty state
                            Item {
                                visible: sourceCol.cats.length === 0 && picker.cache[sourceCol.srcIndex] !== null
                                width: parent.width; height: units.gu(5)
                                Label {
                                    anchors.centerIn: parent
                                    text: i18n.tr("No communities found")
                                    font.pixelSize: Style.fontSmall
                                    color: Style.textSecondary
                                }
                            }

                            Repeater {
                                model: sourceCol.cats

                                delegate: Column {
                                    width: sheetContent.width
                                    property var catData: modelData

                                    // Category header pill (hidden when no category name)
                                    Item {
                                        width: parent.width
                                        height: catData.name.length > 0 ? units.gu(5) : 0
                                        visible: catData.name.length > 0

                                        Row {
                                            anchors {
                                                left: parent.left
                                                leftMargin: Style.spacingM
                                                verticalCenter: parent.verticalCenter
                                            }
                                            spacing: 0

                                            // Pill background
                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                height: units.gu(3.2)
                                                width: pillContent.width + units.gu(2)
                                                radius: height / 2
                                                color: {
                                                    var hex = (catData.color && catData.color.length === 7) ? catData.color : "#17A77E"
                                                    return Qt.rgba(
                                                        parseInt(hex.slice(1,3), 16) / 255,
                                                        parseInt(hex.slice(3,5), 16) / 255,
                                                        parseInt(hex.slice(5,7), 16) / 255,
                                                        0.15)
                                                }

                                                Row {
                                                    id: pillContent
                                                    anchors.centerIn: parent
                                                    spacing: units.gu(0.5)

                                                    // Category icon — backend image if available, fallback icon otherwise
                                                    Item {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: units.gu(2); height: width

                                                        // Backend icon with color tint
                                                        Image {
                                                            id: catIconImg
                                                            anchors.fill: parent
                                                            source: catData.icon || ""
                                                            fillMode: Image.PreserveAspectFit
                                                            asynchronous: true
                                                            visible: false
                                                        }
                                                        ColorOverlay {
                                                            anchors.fill: catIconImg
                                                            source: catIconImg
                                                            color: (catData.color && catData.color.length > 0)
                                                                   ? catData.color : "#17A77E"
                                                            visible: catIconImg.status === Image.Ready
                                                        }

                                                        // Fallback when no backend icon
                                                        Icon {
                                                            anchors.fill: parent
                                                            name: "view-grid-symbolic"
                                                            color: (catData.color && catData.color.length > 0)
                                                                   ? catData.color : "#17A77E"
                                                            visible: catIconImg.status !== Image.Ready
                                                        }
                                                    }

                                                    Label {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: catData.name.toUpperCase()
                                                        font.pixelSize: Style.fontXSmall
                                                        font.weight: Font.Bold
                                                        font.family: Style.fontFamily
                                                        font.letterSpacing: units.dp(0.6)
                                                        color: catData.color.length > 0 ? catData.color : Style.brand
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Community rows
                                    Repeater {
                                        model: catData.communities

                                        delegate: Item {
                                            id: commBtn
                                            width: sheetContent.width
                                            height: units.gu(8.5)

                                            property string commId:   String(modelData.id   || modelData._id  || "")
                                            property string commName: modelData.title || modelData.name || ""
                                            property string commIcon: modelData.icon_url || modelData.logo_url || modelData.profile_image || ""
                                            property bool isSelected: Config.selectedSubCommunity
                                                                      && Config.selectedSubCommunity.id === commBtn.commId
                                            property bool subscribed: picker.subscribedRev >= 0 && !!picker.subscribedMap[commBtn.commId]

                                            // Card
                                            Rectangle {
                                                anchors {
                                                    fill: parent
                                                    leftMargin: Style.spacingM
                                                    rightMargin: Style.spacingM
                                                    topMargin: units.dp(4)
                                                    bottomMargin: units.dp(4)
                                                }
                                                radius: units.gu(1.5)
                                                color: Style.surface
                                                border.width: commBtn.isSelected ? units.dp(2) : units.dp(1)
                                                border.color: commBtn.isSelected ? Style.brand : Style.divider

                                                // Navigate on card tap (behind the row so Subscribe button wins)
                                                MouseArea {
                                                    anchors.fill: parent
                                                    onClicked: {
                                                        Config.selectedSubCommunity = {
                                                            id: commBtn.commId,
                                                            name: commBtn.commName,
                                                            icon: commBtn.commIcon
                                                        }
                                                        picker.closeAnimated()
                                                    }
                                                }

                                                Row {
                                                    anchors {
                                                        fill: parent
                                                        leftMargin: Style.spacingM
                                                        rightMargin: Style.spacingM
                                                    }
                                                    spacing: Style.spacingM

                                                    // Community icon
                                                    Rectangle {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: units.gu(5.5); height: width; radius: width / 2
                                                        color: Style.iconBackground

                                                        CircleImage {
                                                            id: subIcon
                                                            anchors { fill: parent; margins: units.dp(2) }
                                                            source: commBtn.commIcon
                                                        }
                                                    }

                                                    // Name
                                                    Label {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: parent.width - units.gu(5.5) - subBtn.width - Style.spacingM * 2
                                                        text: commBtn.commName
                                                        font.pixelSize: Style.fontRegular
                                                        font.weight: commBtn.isSelected ? Font.DemiBold : Font.Normal
                                                        font.family: Style.fontFamily
                                                        color: commBtn.isSelected ? Style.brand : Style.textPrimary
                                                        elide: Text.ElideRight
                                                    }

                                                    // Subscribe button — defined last so it renders on top of the navigate MouseArea
                                                    Rectangle {
                                                        id: subBtn
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: subLbl.width + units.gu(3)
                                                        height: units.gu(4)
                                                        radius: height / 2
                                                        color: commBtn.subscribed ? Style.surface : Style.brand
                                                        border.width: commBtn.subscribed ? units.dp(1.5) : 0
                                                        border.color: Style.brand

                                                        Label {
                                                            id: subLbl
                                                            anchors.centerIn: parent
                                                            text: commBtn.subscribed ? i18n.tr("Subscribed") : i18n.tr("Subscribe")
                                                            font.pixelSize: Style.fontSmall
                                                            font.weight: Font.DemiBold
                                                            font.family: Style.fontFamily
                                                            color: commBtn.subscribed ? Style.brand : Style.textOnBrand
                                                        }

                                                        MouseArea {
                                                            anchors.fill: parent
                                                            onClicked: picker._toggleSubscribe(commBtn.commId, commBtn.subscribed)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Item { width: 1; height: Style.spacingL }
            }
        }
    }
}
