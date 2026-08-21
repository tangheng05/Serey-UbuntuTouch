import QtQuick 2.7
import QtQuick.Window 2.2
import Lomiri.Components 1.3
import QtGraphicalEffects 1.0
import "../Theme"
import "../Session"
import "../services/CommunitySubscriberService.js" as SubscriberService

Item {
    id: picker
    anchors.fill: parent
    visible: false
    z: 1500

    // Which source row is currently expanded (-1 = none).
    property int expandedIndex: -1
    // Per-source cache: undefined = not fetched, [] = empty, [...] = data
    property var cache: ({})
    property int loadingIndex: -1

    // Keyed by row index, so they go stale when Config.sources is rebuilt; drop and re-fetch
    property Connections _sourcesWatcher: Connections {
        target: Config
        function onSourcesChanged() {
            picker.cache = ({})
            picker.expandedIndex = -1
            picker.loadingIndex = -1
        }
    }
    // Geo hint: hoist detected country to top, expanded; reorders the VIEW ONLY, state stays keyed by `_realIndex`
    readonly property int detectedIndex: Config.indexForCountryCode(Config.detectedCountryCode)
    property bool showAll: false
    readonly property var displaySources: picker._buildDisplaySources()

    function _buildDisplaySources() {
        var out = []
        for (var i = 0; i < Config.sources.length; i++) {
            var row = {}
            var s = Config.sources[i]
            for (var k in s) row[k] = s[k]
            row._realIndex = i          // index into Config.sources, NOT the display position
            out.push(row)
        }
        var di = picker.detectedIndex
        if (di < 0) return out          // undetected: today's list, untouched

        // Global stays pinned at top (default combined feed); geo hint slots in BELOW it
        var mine = out.splice(di, 1)[0]
        out.splice(1, 0, mine)
        // Collapsed: Global + the user's country. The rest are one tap away.
        return picker.showAll ? out : [out[0], mine]
    }

    // Map of communityId (string) -> true for communities the user is subscribed to.
    property var subscribedMap: ({})
    property int subscribedRev: 0
    property bool subscriptionsLoaded: false

    // Desktop anchors a dropdown under the header pill; a modal is slower to
    // dismiss and hides the page you're choosing for. Touch keeps the sheet.
    property Item anchorItem: null
    readonly property bool asDropdown: Config.desktopMode && !!anchorItem
    readonly property real dropWidth: units.gu(50)
    property real _dropX: 0
    property real _dropY: 0

    function open() {
        picker._closing = false
        closeGuard.stop()
        picker.visible = true
        // mapToItem can't be a live binding, so resolve the anchor at open time.
        if (picker.asDropdown) {
            var p = picker.anchorItem.mapToItem(picker, 0, picker.anchorItem.height)
            picker._dropX = Math.max(Style.spacingS,
                                     Math.min(p.x, picker.width - picker.dropWidth - Style.spacingS))
            picker._dropY = p.y + Style.spacingXs
        }
        sheet.opacity = 1; sheet.scale = 1
        // A prior sheet-mode close leaves cpTranslate.y at its slide-out offset (cpDropIn never
        // touches it), so a dropdown-mode open right after would render the panel pushed way down.
        cpTranslate.y = 0
        cpBackdropFade.start()
        if (picker.asDropdown) cpDropIn.start(); else cpSlide.start()
        if (Session.isLoggedIn && !subscriptionsLoaded) _loadSubscriptions()
        // Geo-detected country opens expanded, unless the user already expanded something
        if (picker.detectedIndex > 0 && picker.expandedIndex === -1)
            picker._toggleExpand(picker.detectedIndex)
        // Own the keys while open so Escape dismisses and Tab can't tunnel to the page below
        picker._prevFocus = Window.activeFocusItem
        picker.forceActiveFocus()
        // Cursor starts on the active source; the ring only shows once a key is pressed.
        picker.navSrc = Config.sourceIndex; picker.navCat = -1; picker.navCom = -1
        picker.navActive = false
    }
    function close()         { picker._closing = false; closeGuard.stop(); picker.visible = false }

    // Closing but visible until cpSlideOut finishes; backdrop hit-tests at opacity 0 so disable it
    property bool _closing: false

    function closeAnimated() {
        if (picker._closing) return
        picker._closing = true
        cpBackdropFadeOut.start()
        if (picker.asDropdown) cpDropOut.start(); else cpSlideOut.start()
        closeGuard.restart()
    }

    // onStopped isn't guaranteed to fire; close anyway.
    Timer {
        id: closeGuard
        interval: 400   // comfortably past cpSlideOut's 250ms
        repeat: false
        onTriggered: if (picker.visible) picker.close()
    }

    // Cursor is data coordinates, not Items, so it survives delegate recreation; cat/com -1 = source row
    property int navSrc: -1
    property int navCat: -1
    property int navCom: -1
    property bool navActive: false

    // Walks displaySources, not Config.sources, so cursor visits what's on screen; `src` stays REAL index
    function _navEntries() {
        var out = [], srcs = picker.displaySources || []
        for (var d = 0; d < srcs.length; d++) {
            var i = srcs[d]._realIndex
            out.push({ src: i, cat: -1, com: -1 })
            if (picker.expandedIndex !== i) continue
            var cats = picker.cache[i] || []
            for (var j = 0; j < cats.length; j++) {
                var coms = cats[j].communities || []
                for (var k = 0; k < coms.length; k++) out.push({ src: i, cat: j, com: k })
            }
        }
        return out
    }
    function _navMove(delta) {
        var e = _navEntries()
        if (e.length === 0) return
        var cur = -1
        for (var i = 0; i < e.length; i++)
            if (e[i].src === picker.navSrc && e[i].cat === picker.navCat && e[i].com === picker.navCom) { cur = i; break }
        var n = (cur < 0) ? (delta > 0 ? 0 : e.length - 1)
                          : Math.max(0, Math.min(e.length - 1, cur + delta))
        picker.navSrc = e[n].src; picker.navCat = e[n].cat; picker.navCom = e[n].com
        picker.navActive = true
    }
    function _navActivate() {
        if (picker.navSrc < 0) return
        if (picker.navCat < 0) { picker._selectSource(picker.navSrc); return }
        var cats = picker.cache[picker.navSrc] || []
        var coms = cats[picker.navCat] ? (cats[picker.navCat].communities || []) : []
        if (coms[picker.navCom]) picker._selectCommunity(coms[picker.navCom])
    }
    // Rows call this when they become the cursor, so it never leaves the viewport.
    function _ensureVisible(it) {
        var y = it.mapToItem(sheetContent, 0, 0).y
        if (y < flickable.contentY) flickable.contentY = Math.max(0, y)
        else if (y + it.height > flickable.contentY + flickable.height)
            flickable.contentY = y + it.height - flickable.height
    }

    // Banned: gray the row out and toast instead of navigating.
    function _isBanned(id, title) { return Config.isBannedFromCommunity(id, title) }
    function _warnBanned() { Toast.error(Lang.tr("You're banned from this community.")) }

    // Shared by pointer and keyboard so the two paths can't drift.
    function _selectSource(i) {
        var s = Config.sources[i]
        if (picker._isBanned(s.id, s.name)) { picker._warnBanned(); return }
        Config.sourceIndex = i
        Config.selectedSubCommunity = null
        picker.expandedIndex = -1
        picker._chose = true
        picker.closeAnimated()
    }
    function _toggleExpand(i) {
        if (picker.expandedIndex === i) picker.expandedIndex = -1
        else { picker.expandedIndex = i; picker._fetch(i) }
    }
    function _selectCommunity(m) {
        var id = String(m.id || m._id || "")
        if (picker._isBanned(id, m.title || m.name)) { picker._warnBanned(); return }
        Config.selectedSubCommunity = {
            id: String(m.id || m._id || ""),
            name: m.title || m.name || "",
            icon: m.icon_url || m.logo_url || m.profile_image || "",
            // Posting permissions for this sub-community gate the compose buttons; modelData is a raw list-by-parent-id object using the API's snake_case names.
            allowPost: !!m.is_allow_post,
            videoAllowPost: !!m.video_is_allow_post
        }
        picker._chose = true
        picker.closeAnimated()
    }

    // Whatever held keyboard focus before the picker opened; restored on close.
    property var _prevFocus: null
    // True when a platform was chosen (vs. cancel/Escape); focus then goes to the reloaded feed
    property bool _chose: false
    onVisibleChanged: {
        if (visible) return
        var prev = _prevFocus, chose = _chose
        _prevFocus = null; _chose = false
        // Deferred: a synchronous grab mid-teardown lands nowhere, leaving keyboard dead
        Qt.callLater(function () {
            if (chose) { Nav.focusContent(); return }
            try { if (prev && prev.visible) prev.forceActiveFocus() } catch (e) { /* item destroyed since */ }
        })
    }
    Keys.onPressed: {
        if (event.key === Qt.Key_Escape) { picker.closeAnimated(); event.accepted = true }
        else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) event.accepted = true
        else if (event.key === Qt.Key_Down)  { picker._navMove(1);  event.accepted = true }
        else if (event.key === Qt.Key_Up)    { picker._navMove(-1); event.accepted = true }
        // Right opens a country's sub-communities (Global, index 0, has none).
        else if (event.key === Qt.Key_Right) {
            if (picker.navCat < 0 && picker.navSrc > 0) { picker._toggleExpand(picker.navSrc); picker.navActive = true }
            event.accepted = true
        }
        // Left steps back up to the parent row, then collapses it.
        else if (event.key === Qt.Key_Left) {
            if (picker.navCat >= 0) { picker.navCat = -1; picker.navCom = -1 }
            else if (picker.expandedIndex === picker.navSrc) picker.expandedIndex = -1
            picker.navActive = true
            event.accepted = true
        }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            picker._navActivate(); event.accepted = true
        }
    }

    function _loadSubscriptions() {
        picker.subscriptionsLoaded = true  // mark before call so retries don't stack
        SubscriberService.fetchSubscribed(Config.baseUrl, Session.token,
            function (map) { picker.subscribedMap = map; picker.subscribedRev++ },
            function () { /* silent; picker still works without subscription data */ })
    }

    function _toggleSubscribe(commId, currentlySubscribed) {
        if (!Session.isLoggedIn) { Toast.show(Lang.tr("Log in to subscribe")); return }
        var id = String(commId)
        function _newMap(add) {
            var m = {}
            for (var k in picker.subscribedMap) m[k] = true
            if (add) m[id] = true
            else delete m[id]
            return m   // new object so QML detects the change and re-evaluates bindings
        }

        if (currentlySubscribed) {
            SubscriberService.unsubscribe(Config.baseUrl, Session.token, id,
                function () { picker.subscribedMap = _newMap(false); picker.subscribedRev++; Toast.show(Lang.tr("Unsubscribed")) },
                function (err) { Toast.show(err.message || Lang.tr("Failed to unsubscribe")) })
        } else {
            SubscriberService.subscribe(Config.baseUrl, Session.token, id,
                function () { picker.subscribedMap = _newMap(true); picker.subscribedRev++; Toast.show(Lang.tr("Subscribed!")) },
                function (err) { Toast.show(err.message || Lang.tr("Failed to subscribe")) })
        }
    }

    function _fetch(srcIndex) {
        if (picker.cache[srcIndex] !== undefined) return
        picker.loadingIndex = srcIndex

        // Fetch communities, then categories, then group the former by the latter; Global uses categories/list directly since list-by-parent-id/1 returns only hubs.

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
            // Build community_category_id -> {name, icon, color} map from both communities and categories, which both carry community_category_id.
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
            var nc = {}
            for (var k in picker.cache) nc[k] = picker.cache[k]
            nc[si] = cats
            picker.cache = nc
            picker.loadingIndex = -1
        }

        // Offline, every request "returns" an empty list. Caching that left the row stuck on
        // "No platforms found" for the rest of the session, so a failure stays uncached and
        // the next expand tries again.
        function _abandon() { picker.loadingIndex = -1 }
        function _ok(xhr) { return xhr.status >= 200 && xhr.status < 300 }

        if (srcIndex === 0) {
            // Global: fetch both Netherlands (99) and US (26) and combine
            var regionalIds = []
            for (var ri = 1; ri < Config.sources.length; ri++)
                regionalIds.push(Config.sources[ri].id)
            var allComms = [], pending = regionalIds.length
            var anyRegionalFailed = false

            function _onRegionalDone() {
                pending--
                if (pending > 0) return
                // Don't cache a network failure as "Global has no platforms".
                if (anyRegionalFailed && allComms.length === 0) { _abandon(); return }
                if (allComms.length === 0) { _store(0, []); return }
                var xhrCat = new XMLHttpRequest()
                xhrCat.open("GET", Config.baseUrl + "/community/categories/list?limit=100")
                xhrCat.setRequestHeader("Accept", "application/json")
                xhrCat.timeout = 15000
                xhrCat.onreadystatechange = function () {
                    if (xhrCat.readyState !== XMLHttpRequest.DONE) return
                    if (!_ok(xhrCat)) { _abandon(); return }
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
                        if (!_ok(xhr)) { anyRegionalFailed = true }
                        else try {
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
            // Netherlands / US: step 1, get communities for this source
            var xhrP = new XMLHttpRequest()
            xhrP.open("GET", Config.baseUrl + "/community/list-by-parent-id/" + apiId)
            xhrP.setRequestHeader("Accept", "application/json")
            xhrP.timeout = 15000
            xhrP.onreadystatechange = function () {
                if (xhrP.readyState !== XMLHttpRequest.DONE) return
                if (!_ok(xhrP)) { _abandon(); return }
                var sourceComms = []
                try {
                    var d = JSON.parse(xhrP.responseText)
                    sourceComms = d.data || d.communities || d.results || []
                } catch (e) { }

                if (sourceComms.length === 0) { _store(srcIndex, []); return }

                // Step 2: fetch categories to try to group them
                var xhrC = new XMLHttpRequest()
                xhrC.open("GET", Config.baseUrl + "/community/categories/list?limit=100")
                xhrC.setRequestHeader("Accept", "application/json")
                xhrC.timeout = 15000
                xhrC.onreadystatechange = function () {
                    if (xhrC.readyState !== XMLHttpRequest.DONE) return
                    if (!_ok(xhrC)) { _abandon(); return }
                    var cats = []
                    try {
                        var arr = _parseCategoryList(JSON.parse(xhrC.responseText))
                        cats = _applyCategories(sourceComms, arr)
                    } catch (e) { }
                    // Remove the uncategorised group (empty name); only show categorised communities.
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

    Rectangle {
        id: cpBackdrop
        anchors.fill: parent
        // A dropdown doesn't dim the page; the backdrop stays only to catch the
        // click-outside and swallow wheel events.
        color: picker.asDropdown ? "transparent" : Qt.rgba(0, 0, 0, 0.4)
        opacity: 0
        // enabled gate: see picker._closing
        MouseArea {
            anchors.fill: parent
            enabled: !picker._closing
            onClicked: picker.closeAnimated()
            onWheel: wheel.accepted = true   // don't let scroll fall through to the page below
        }
    }
    NumberAnimation { id: cpBackdropFade;    target: cpBackdrop; property: "opacity"; from: 0; to: 1;  duration: 200 }
    NumberAnimation { id: cpBackdropFadeOut; target: cpBackdrop; property: "opacity"; to: 0;            duration: 200 }

    // Soft elevation so the dropdown reads as floating above the page (the full-width
    // sheet already sits on a dimmed backdrop and doesn't need it).
    DropShadow {
        anchors.fill: sheet
        visible: picker.asDropdown && sheet.opacity > 0
        source: sheet
        radius: 16
        samples: 33
        horizontalOffset: 0
        verticalOffset: 6
        color: Qt.rgba(0, 0, 0, 0.22)
        transparentBorder: true
        cached: true
    }

    Rectangle {
        id: sheet
        readonly property bool wide: Config.wideMode
        // x/y rather than anchors: anchors can't be conditionally unset from a
        // ternary in this codebase, and the two modes place the panel differently.
        x: picker.asDropdown ? picker._dropX : (parent.width - width) / 2
        y: picker.asDropdown ? picker._dropY
                             : parent.height - height - (sheet.wide ? units.gu(4) : 0)
        width: picker.asDropdown ? picker.dropWidth
             : sheet.wide ? Math.min(parent.width - units.gu(4), units.gu(60))
             : parent.width
        // The sheet's gu(4) pads the drag handle and title; a dropdown has neither,
        // so the same padding just left a dead band under the last row.
        height: Math.min(sheetContent.height + (picker.asDropdown ? units.gu(1) : units.gu(4)),
                         picker.asDropdown
                           ? Math.max(units.gu(20), picker.height - picker._dropY - Style.spacingM)
                           : picker.height * 0.82)
        // Match the header dropdown in VideoDetailPage, not the sheet.
        radius: picker.asDropdown ? Style.cardRadius : units.gu(1)
        color: Style.surface
        // Without a dimmed backdrop the panel needs its own edge to sit on the page.
        border.width: picker.asDropdown ? units.dp(1) : 0
        border.color: Style.divider
        clip: true
        transformOrigin: Item.TopLeft

        transform: Translate { id: cpTranslate; y: 0 }
        NumberAnimation { id: cpSlide;    target: cpTranslate; property: "y"; from: sheet.height + units.gu(4); to: 0;              duration: 300; easing.type: Easing.OutCubic }
        NumberAnimation { id: cpSlideOut; target: cpTranslate; property: "y"; to: sheet.height + units.gu(4); duration: 250; easing.type: Easing.InCubic; onStopped: picker.close() }

        // Dropdowns snap open from their anchor; a 300ms slide would feel slow.
        ParallelAnimation {
            id: cpDropIn
            NumberAnimation { target: sheet; property: "opacity"; from: 0; to: 1; duration: 120; easing.type: Easing.OutQuad }
            NumberAnimation { target: sheet; property: "scale";   from: 0.97; to: 1; duration: 120; easing.type: Easing.OutQuad }
        }
        ParallelAnimation {
            id: cpDropOut
            onStopped: picker.close()
            NumberAnimation { target: sheet; property: "opacity"; to: 0; duration: 100; easing.type: Easing.InQuad }
        }

        Rectangle {
            visible: !picker.asDropdown
            anchors { top: parent.top; topMargin: Style.spacingS; horizontalCenter: parent.horizontalCenter }
            width: units.gu(4.5); height: units.dp(4); radius: units.dp(2)
            color: Style.lightGray
        }

        Flickable {
            id: flickable
            anchors { fill: parent; topMargin: units.gu(1) }
            contentWidth: width
            contentHeight: sheetContent.height
            clip: true

            Column {
                id: sheetContent
                width: flickable.width

                // Title + close are modal furniture; a dropdown is labelled by the
                // pill it hangs from and closes on click-outside or Escape.
                Item { width: 1; height: Style.spacingL; visible: !picker.asDropdown }
                Row {
                    visible: !picker.asDropdown
                    width: parent.width - Style.spacingM * 2
                    x: Style.spacingM
                    Label {
                        width: parent.width - units.gu(4)
                        text: Lang.tr("Choose platform")
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
                Item { width: 1; height: Style.spacingM; visible: !picker.asDropdown }
                Item { width: 1; height: Style.spacingS;  visible: picker.asDropdown }

                Repeater {
                    // Display order may differ from Config.sources when geo-detected; srcIndex is real index
                    model: picker.displaySources

                    delegate: Column {
                        id: sourceCol
                        width: sheetContent.width
                        // Global (index 0) applies no community filter and is shown as a plain selectable row with no chevron (no sub-communities).
                        visible: true
                        property int srcIndex: modelData._realIndex
                        property bool isExpanded: picker.expandedIndex === sourceCol.srcIndex
                        property var cats: picker.cache[sourceCol.srcIndex] || []
                        readonly property bool isBanned: picker._isBanned(modelData.id, modelData.name)

                        Item {
                            id: sourceRow
                            width: parent.width
                            height: units.gu(7)
                            // Chevron touch target width, used to split the two hit areas.
                            readonly property int chevronW: sourceCol.srcIndex !== 0 ? units.gu(7) : 0

                            readonly property bool isCursor: picker.navActive
                                && picker.navSrc === sourceCol.srcIndex && picker.navCat < 0
                            onIsCursorChanged: if (isCursor) picker._ensureVisible(sourceRow)

                            Rectangle {
                                anchors.fill: parent
                                color: sourceCol.isExpanded ? Style.iconBackground : "transparent"
                            }

                            Row {
                                anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                                spacing: Style.spacingM
                                opacity: sourceCol.isBanned ? 0.4 : 1

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(5); height: width; radius: width / 2
                                    color: Style.iconBackground
                                    border.width: Config.sourceIndex === sourceCol.srcIndex && !Config.selectedSubCommunity ? units.dp(2) : 0
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
                                        color: Config.sourceIndex === sourceCol.srcIndex ? Style.brand : Style.textSecondary
                                        visible: !srcIcon.loaded
                                    }
                                }

                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - units.gu(5) - sourceRow.chevronW - Style.spacingM * 2
                                    text: modelData.name
                                    font.pixelSize: Style.fontMedium
                                    font.weight: sourceCol.isExpanded ? Font.DemiBold : Font.Medium
                                    color: sourceCol.isExpanded ? Style.brand : Style.textPrimary
                                    elide: Text.ElideRight
                                }
                            }

                            // Anchored to the tap zone directly since it previously sat left of the zone, so arrow taps selected the source instead.
                            Icon {
                                anchors { right: parent.right; rightMargin: Style.spacingM
                                          verticalCenter: parent.verticalCenter }
                                width: units.gu(2.5); height: width
                                name: sourceCol.isExpanded ? "go-up" : "go-down"
                                color: sourceCol.isExpanded ? Style.brand : Style.textSecondary
                                visible: sourceCol.srcIndex !== 0
                            }

                            // Left zone (flag + name): select this source and close
                            MouseArea {
                                anchors {
                                    left: parent.left; top: parent.top; bottom: parent.bottom
                                    right: parent.right; rightMargin: sourceRow.chevronW
                                }
                                onClicked: picker._selectSource(sourceCol.srcIndex)
                            }

                            // Right zone (chevron): toggle dropdown (NL/US only)
                            MouseArea {
                                anchors {
                                    right: parent.right; top: parent.top; bottom: parent.bottom
                                }
                                width: sourceRow.chevronW
                                visible: sourceCol.srcIndex !== 0
                                onClicked: picker._toggleExpand(sourceCol.srcIndex)
                            }

                            // Keyboard cursor ring (pointer users never see it).
                            Rectangle {
                                anchors { fill: parent; margins: units.dp(2) }
                                radius: units.dp(6)
                                color: "transparent"
                                border.width: units.dp(2)
                                border.color: Style.brand
                                visible: sourceRow.isCursor
                                z: 5
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width; height: units.dp(1)
                                color: Style.divider
                            }
                        }

                        Item {
                            visible: sourceCol.isExpanded && picker.loadingIndex === sourceCol.srcIndex
                            width: parent.width; height: units.gu(5)
                            ActivityIndicator {
                                anchors.centerIn: parent
                                running: parent.visible
                            }
                        }

                        Column {
                            visible: sourceCol.isExpanded && picker.loadingIndex !== sourceCol.srcIndex
                            width: parent.width

                            Item {
                                visible: sourceCol.cats.length === 0 && picker.cache[sourceCol.srcIndex] !== undefined
                                width: parent.width; height: units.gu(5)
                                Label {
                                    anchors.centerIn: parent
                                    text: Lang.tr("No platforms found")
                                    font.pixelSize: Style.fontSmall
                                    color: Style.textSecondary
                                }
                            }

                            // Fetch failed, so nothing is cached: say so and let the row retry,
                            // rather than leaving an expanded row that is simply blank.
                            Item {
                                visible: picker.cache[sourceCol.srcIndex] === undefined
                                width: parent.width; height: units.gu(5)
                                Label {
                                    anchors.centerIn: parent
                                    text: Net.online ? Lang.tr("Couldn't load. Tap to try again.")
                                                     : Lang.tr("You're offline. Tap to try again.")
                                    font.pixelSize: Style.fontSmall
                                    color: Style.textSecondary
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: picker._fetch(sourceCol.srcIndex)
                                }
                            }

                            Repeater {
                                model: sourceCol.cats

                                delegate: Column {
                                    id: catCol
                                    width: sheetContent.width
                                    property var catData: modelData
                                    // Captured for the keyboard cursor: the inner community Repeater shadows `index`.
                                    property int catIndex: index

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

                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                height: units.gu(3.2)
                                                width: pillContent.width + units.gu(2)
                                                radius: Style.pillRadius
                                                color: Qt.rgba(
                                                    Style.brand.r, Style.brand.g, Style.brand.b, 0.15)

                                                Row {
                                                    id: pillContent
                                                    anchors.centerIn: parent
                                                    spacing: units.gu(0.5)

                                                    Item {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: units.gu(2); height: width

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
                                                            color: Style.brand
                                                            visible: catIconImg.status === Image.Ready
                                                        }

                                                        Icon {
                                                            anchors.fill: parent
                                                            name: "view-grid-symbolic"
                                                            color: Style.brand
                                                            visible: catIconImg.status !== Image.Ready
                                                        }
                                                    }

                                                    Label {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: catData.name.toUpperCase()
                                                        font.pixelSize: Style.fontXSmall
                                                        font.weight: Font.Bold
                                                        font.family: Style.fontFor(text)
                                                        font.letterSpacing: units.dp(0.6)
                                                        color: Style.brand
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Repeater {
                                        model: catData.communities

                                        delegate: Column {
                                            width: sheetContent.width

                                            Item {
                                            id: commBtn
                                            width: sheetContent.width
                                            height: units.gu(8.5)

                                            property string commId:   String(modelData.id   || modelData._id  || "")
                                            property string commName: modelData.title || modelData.name || ""
                                            property string commIcon: modelData.icon_url || modelData.logo_url || modelData.profile_image || ""
                                            property bool isSelected: Config.selectedSubCommunity
                                                                      && Config.selectedSubCommunity.id === commBtn.commId
                                            property bool subscribed: picker.subscribedRev >= 0 && !!picker.subscribedMap[commBtn.commId]
                                            readonly property bool isCursor: picker.navActive
                                                && picker.navSrc === sourceCol.srcIndex
                                                && picker.navCat === catCol.catIndex
                                                && picker.navCom === index
                                            onIsCursorChanged: if (isCursor) picker._ensureVisible(commBtn)
                                            // A superhub is a platform that itself contains child platforms.
                                            property bool isSuperhub: !!(modelData.is_superhub)
                                            property var hubChildren: commBtn.isSuperhub
                                                                      ? (Config.superhubChildrenById[commBtn.commId] || [])
                                                                      : []
                                            readonly property bool isBanned: picker._isBanned(commBtn.commId, commBtn.commName)

                                            Rectangle {
                                                anchors {
                                                    fill: parent
                                                    leftMargin: Style.spacingM
                                                    rightMargin: Style.spacingM
                                                    topMargin: units.dp(4)
                                                    bottomMargin: units.dp(4)
                                                }
                                                radius: Style.cardRadius
                                                color: Style.surface
                                                opacity: commBtn.isBanned ? 0.45 : 1
                                                border.width: commBtn.isSelected ? units.dp(2) : units.dp(1)
                                                border.color: commBtn.isSelected ? Style.brand : Style.divider

                                                // Navigate on card tap (behind the row so Subscribe button wins)
                                                MouseArea {
                                                    anchors.fill: parent
                                                    onClicked: picker._selectCommunity(modelData)
                                                }

                                                // Keyboard cursor ring (pointer users never see it).
                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: Style.cardRadius
                                                    color: "transparent"
                                                    border.width: units.dp(2)
                                                    border.color: Style.brand
                                                    visible: commBtn.isCursor
                                                    z: 5
                                                }

                                                Row {
                                                    anchors {
                                                        fill: parent
                                                        leftMargin: Style.spacingM
                                                        rightMargin: Style.spacingM
                                                    }
                                                    spacing: Style.spacingM

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

                                                    Label {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: parent.width - units.gu(5.5) - subBtn.width
                                                               - (hubBadge.visible ? hubBadge.width + Style.spacingM : 0)
                                                               - (ownerBadge.visible ? ownerBadge.width + Style.spacingM : 0)
                                                               - Style.spacingM * 2
                                                        text: commBtn.commName
                                                        font.pixelSize: Style.fontRegular
                                                        font.weight: commBtn.isSelected ? Font.DemiBold : Font.Normal
                                                        font.family: Style.fontFor(text)
                                                        color: commBtn.isSelected ? Style.brand : Style.textPrimary
                                                        elide: Text.ElideRight
                                                    }

                                                    // HUB badge: marks a superhub platform
                                                    Rectangle {
                                                        id: hubBadge
                                                        visible: commBtn.isSuperhub
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: hubLbl.width + units.gu(1.6)
                                                        height: units.gu(2.6)
                                                        radius: Style.pillRadius
                                                        color: Qt.rgba(Style.brand.r, Style.brand.g, Style.brand.b, 0.14)

                                                        Label {
                                                            id: hubLbl
                                                            anchors.centerIn: parent
                                                            text: "HUB"
                                                            font.pixelSize: Style.fontXSmall
                                                            font.weight: Font.Bold
                                                            font.letterSpacing: units.dp(0.5)
                                                            color: Style.brand
                                                        }
                                                    }

                                                    // Owner badge: you manage this community.
                                                    Rectangle {
                                                        id: ownerBadge
                                                        visible: !!Config.ownedCommunityIdSet[commBtn.commId]
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: ownerLbl.width + units.gu(1.6)
                                                        height: units.gu(2.6)
                                                        radius: Style.pillRadius
                                                        color: "#FCE7F3"

                                                        Label {
                                                            id: ownerLbl
                                                            anchors.centerIn: parent
                                                            text: Lang.tr("Owner")
                                                            font.pixelSize: Style.fontXSmall
                                                            font.weight: Font.Bold
                                                            font.family: Style.fontFor(text)
                                                            font.letterSpacing: units.dp(0.5)
                                                            color: "#DB2777"
                                                        }
                                                    }

                                                    // Subscribe button: defined last so it renders on top of the navigate MouseArea
                                                    Rectangle {
                                                        id: subBtn
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: subLbl.width + units.gu(3)
                                                        height: units.gu(4)
                                                        radius: Style.pillRadius
                                                        color: commBtn.subscribed ? Style.surface : Style.brand
                                                        border.width: commBtn.subscribed ? units.dp(1.5) : 0
                                                        border.color: Style.brand

                                                        Label {
                                                            id: subLbl
                                                            anchors.centerIn: parent
                                                            text: commBtn.subscribed ? Lang.tr("Subscribed") : Lang.tr("Subscribe")
                                                            font.pixelSize: Style.fontSmall
                                                            font.weight: Font.DemiBold
                                                            font.family: Style.fontFor(text)
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

                                            // Superhub children: indented, with a connector line.
                                            Repeater {
                                                model: commBtn.hubChildren

                                                delegate: Item {
                                                    id: childBtn
                                                    width: sheetContent.width
                                                    height: units.gu(7.5)

                                                    property string cId:   String(modelData.id || "")
                                                    property string cName: modelData.title || modelData.name || ""
                                                    property string cIcon: modelData.icon || modelData.icon_url || modelData.logo_url || ""
                                                    property bool cSelected: Config.selectedSubCommunity
                                                                             && Config.selectedSubCommunity.id === childBtn.cId
                                                    property bool cSubscribed: picker.subscribedRev >= 0 && !!picker.subscribedMap[childBtn.cId]
                                                    readonly property bool isBanned: picker._isBanned(childBtn.cId, childBtn.cName)

                                                    // Connector: vertical line down the indent gutter + short elbow into the card
                                                    Rectangle {
                                                        x: Style.spacingM + units.gu(1.6)
                                                        y: 0
                                                        width: units.dp(1.5)
                                                        height: parent.height / 2
                                                        color: Style.divider
                                                    }
                                                    Rectangle {
                                                        x: Style.spacingM + units.gu(1.6)
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: units.gu(1.4); height: units.dp(1.5)
                                                        color: Style.divider
                                                    }

                                                    Rectangle {
                                                        anchors {
                                                            fill: parent
                                                            leftMargin: Style.spacingM + units.gu(3.2)
                                                            rightMargin: Style.spacingM
                                                            topMargin: units.dp(3)
                                                            bottomMargin: units.dp(3)
                                                        }
                                                        radius: Style.cardRadius
                                                        color: Style.surface
                                                        opacity: childBtn.isBanned ? 0.45 : 1
                                                        border.width: childBtn.cSelected ? units.dp(2) : units.dp(1)
                                                        border.color: childBtn.cSelected ? Style.brand : Style.divider

                                                        MouseArea {
                                                            anchors.fill: parent
                                                            onClicked: {
                                                                if (picker._isBanned(childBtn.cId, childBtn.cName)) { picker._warnBanned(); return }
                                                                Config.selectedSubCommunity = {
                                                                    id: childBtn.cId,
                                                                    name: childBtn.cName,
                                                                    icon: childBtn.cIcon,
                                                                    // modelData is a mapped superhub child (M.toCommunity), so the fields use the mapper's camelCase names.
                                                                    allowPost: !!modelData.allowPost,
                                                                    videoAllowPost: !!modelData.videoAllowPost
                                                                }
                                                                picker.closeAnimated()
                                                            }
                                                        }

                                                        Row {
                                                            anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                                                            spacing: Style.spacingM

                                                            Rectangle {
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                width: units.gu(4.5); height: width; radius: width / 2
                                                                color: Style.iconBackground
                                                                CircleImage {
                                                                    anchors { fill: parent; margins: units.dp(2) }
                                                                    source: childBtn.cIcon
                                                                }
                                                            }

                                                            Label {
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                width: parent.width - units.gu(4.5) - childSubBtn.width - Style.spacingM * 2
                                                                       - (childOwnerBadge.visible ? childOwnerBadge.width + Style.spacingM : 0)
                                                                text: childBtn.cName
                                                                font.pixelSize: Style.fontRegular
                                                                font.weight: childBtn.cSelected ? Font.DemiBold : Font.Normal
                                                                font.family: Style.fontFor(text)
                                                                color: childBtn.cSelected ? Style.brand : Style.textPrimary
                                                                elide: Text.ElideRight
                                                            }

                                                            // Owner badge: you manage this community.
                                                            Rectangle {
                                                                id: childOwnerBadge
                                                                visible: !!Config.ownedCommunityIdSet[childBtn.cId]
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                width: childOwnerLbl.width + units.gu(1.6)
                                                                height: units.gu(2.4)
                                                                radius: Style.pillRadius
                                                                color: "#FCE7F3"
                                                                Label {
                                                                    id: childOwnerLbl
                                                                    anchors.centerIn: parent
                                                                    text: Lang.tr("Owner")
                                                                    font.pixelSize: Style.fontXSmall
                                                                    font.weight: Font.Bold
                                                                    font.family: Style.fontFor(text)
                                                                    font.letterSpacing: units.dp(0.5)
                                                                    color: "#DB2777"
                                                                }
                                                            }

                                                            Rectangle {
                                                                id: childSubBtn
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                width: childSubLbl.width + units.gu(3)
                                                                height: units.gu(3.6)
                                                                radius: Style.pillRadius
                                                                color: childBtn.cSubscribed ? Style.surface : Style.brand
                                                                border.width: childBtn.cSubscribed ? units.dp(1.5) : 0
                                                                border.color: Style.brand

                                                                Label {
                                                                    id: childSubLbl
                                                                    anchors.centerIn: parent
                                                                    text: childBtn.cSubscribed ? Lang.tr("Subscribed") : Lang.tr("Subscribe")
                                                                    font.pixelSize: Style.fontSmall
                                                                    font.weight: Font.DemiBold
                                                                    font.family: Style.fontFor(text)
                                                                    color: childBtn.cSubscribed ? Style.brand : Style.textOnBrand
                                                                }

                                                                MouseArea {
                                                                    anchors.fill: parent
                                                                    onClicked: picker._toggleSubscribe(childBtn.cId, childBtn.cSubscribed)
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
                    }
                }

                // See more: shown only while geo hint collapses the list; expanding is one-way
                AbstractButton {
                    id: seeMoreBtn
                    visible: picker.detectedIndex >= 0 && !picker.showAll
                    width: sheetContent.width
                    height: visible ? units.gu(6) : 0
                    onClicked: picker.showAll = true

                    Rectangle {
                        anchors.fill: parent
                        color: seeMoreBtn.pressed ? Style.pressed : "transparent"
                    }
                    Rectangle {
                        anchors { top: parent.top; left: parent.left; right: parent.right }
                        height: units.dp(1)
                        color: Style.divider
                    }
                    Row {
                        anchors.centerIn: parent
                        spacing: Style.spacingS
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Lang.tr("See more")
                            font.pixelSize: Style.fontRegular
                            font.weight: Font.DemiBold
                            font.family: Style.fontFor(text)
                            color: Style.brand
                        }
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: units.gu(2); height: width
                            name: "go-down"
                            color: Style.brand
                        }
                    }
                    KeyTapArea { onActivated: seeMoreBtn.clicked() }
                }

                Item { width: 1; height: Style.spacingL }
            }
        }
    }
}
