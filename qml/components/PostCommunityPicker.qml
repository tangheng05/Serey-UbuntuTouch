import QtQuick 2.7
import QtGraphicalEffects 1.0
import Lomiri.Components 1.3
import "../Theme"
import "../Session"

// Bottom sheet asking which community a new post goes into; pre-selects the active one
Item {
    id: picker
    anchors.fill: parent
    visible: false
    z: 1500


    // Called back with the chosen target: { id, name, icon, allowPost, videoAllowPost }.
    property var _onChosen: null
    property var items: []           // [{ id, name, icon, allowPost, videoAllowPost, isParent }]
    property string selectedId: ""
    property bool loading: false
    // Set by openFor(): video posting has its own per-community permission, so rows that don't
    // allow it are shown (for browsing into their children) but can't be selected.
    property bool forVideo: false
    function _canPost(entry) { return !!entry && !!(picker.forVideo ? entry.videoAllowPost : entry.allowPost); }
    // Marks rows for communities the signed-in user owns/manages with the "Owner" pill.
    function _isOwned(entry) { return !!entry && !!entry.id && !!Config.ownedCommunityIdSet[entry.id]; }
    // True when `items` is the country list; only then can rows expand for children
    property bool topLevelIsCountries: false
    // country id (string) -> its fetched children, or undefined until expanded.
    property var childCache: ({})
    property string expandedId: ""
    property string childLoadingId: ""
    // Superhub row expanded within the open country (its children are the third level).
    property string expandedHubId: ""
    // Flat id -> entry lookup across `items` and every fetched child list
    property var _byId: ({})

    // Drops soft-deleted rows the backend still returns in these list endpoints.
    function _isDeleted(m) { return !!(m.deleted || m.deleted_at || m.is_deleted); }

    // Source id 0 is a filter sentinel; resolve the real postable "Global" community from the cache
    function _globalEntry() {
        var dns = Config.sources[0].dns;
        for (var k in Config.communityById) {
            var c = Config.communityById[k];
            if (!c || c.dns !== dns) continue;
            if (picker.forVideo ? !c.videoAllowPost : !c.allowPost) return null;
            return {
                id: String(c.id),
                name: c.title || Config.sources[0].name,
                icon: Config.communityIcon(dns),
                allowPost: true,
                videoAllowPost: !!c.videoAllowPost,
                isParent: true,
                expandable: false
            };
        }
        return null;
    }

    // Entry point: shows the picker only when there is a real choice, else calls back
    // immediately. `callerItem` (optional) anchors the panel to the button that opened it
    // on desktop, instead of a centred modal.
    function openFor(onChosen, callerItem) {
        picker._onChosen = onChosen;
        picker.caller = callerItem || null;
        picker.selectedId = Config.selectedSubCommunity ? String(Config.selectedSubCommunity.id) : "";
        picker.childCache = ({});
        picker.expandedId = "";
        picker.expandedHubId = "";
        picker._byId = ({});
        picker._fetch();
    }

    // Communities the user owns live anywhere in the tree, so browsing a different branch
    // would otherwise hide them; an owner may post to their own community regardless.
    function _ownedEntries(list) {
        var seen = {};
        for (var i = 0; i < list.length; i++) seen[list[i].id] = true;
        var out = [];
        var set = Config.ownedCommunityIdSet || ({});
        for (var id in set) {
            var c = Config.communityById[String(id)];
            if (!c || seen[String(c.id)]) continue;
            var e = {
                id: String(c.id),
                name: c.title || "",
                icon: Config.communityIcon(c.dns),
                allowPost: true,
                videoAllowPost: !!c.videoAllowPost,
                isParent: false,
                expandable: false,
                // Caption rides on the first row of the group only
                section: out.length === 0 ? Lang.tr("Your platforms") : ""
            };
            out.push(e);
            picker._byId[e.id] = e;
        }
        return out;
    }

    // One shared exit: no target -> current context, exactly one -> take it without a modal.
    function _present(list) {
        var full = picker._ownedEntries(list).concat(list);
        if (full.length === 0 || (full.length === 1 && !full[0].allowPost)) {
            var cb0 = picker._onChosen; picker._onChosen = null;
            if (cb0) cb0(null);
            return;
        }
        if (full.length === 1) {
            var cb1 = picker._onChosen; picker._onChosen = null;
            if (cb1) cb1(full[0]);
            return;
        }
        picker.items = full;
        picker._open();
    }

    function _mapCommunities(comms) {
        var out = [];
        for (var i = 0; i < comms.length; i++) {
            var m = comms[i];
            if (picker._isDeleted(m)) continue;
            var id = String(m.id || m._id || "");
            // list-by-parent-id doesn't reliably carry is_allow_post/video_is_allow_post for every
            // row; Config.communityById (built from the full community tree) is the source of truth
            // when it already knows this id, so cross-check it instead of trusting the raw fields blindly.
            var known = Config.communityById[id];
            var entry = {
                id: id,
                name: m.title || m.name || "",
                icon: m.icon_url || m.logo_url || m.profile_image || "",
                allowPost: known ? !!known.allowPost : !!m.is_allow_post,
                videoAllowPost: known ? !!known.videoAllowPost : !!m.video_is_allow_post,
                isParent: false,
                isSuperhub: !!m.is_superhub
            };
            out.push(entry);
            picker._byId[entry.id] = entry;
        }
        return out;
    }

    // Always the same shape regardless of what you're currently browsing: Global + every country,
    // each expandable into its own sub-communities. Whichever country is currently browsed gets
    // auto-expanded so its communities are visible inline without an extra click.
    function _fetch() {
        picker.topLevelIsCountries = true;

        // For Global, reuse curated Config.sources instead of the raw list-by-parent-id/1
        var out0 = [];
        // Global itself first, when its backend record allows posting.
        var globalEntry = picker._globalEntry();
        if (globalEntry) {
            out0.push(globalEntry);
            picker._byId[globalEntry.id] = globalEntry;
        }
        for (var s = 1; s < Config.sources.length; s++) {
            var src = Config.sources[s];
            var entry = {
                id: String(src.id),
                name: src.name,
                icon: Config.communityIcon(src.dns),
                allowPost: !!Config.allowPostByDns[src.dns],
                videoAllowPost: !!Config.videoAllowPostByDns[src.dns],
                isParent: false
            };
            out0.push(entry);
            picker._byId[entry.id] = entry;
        }
        // Browsing Global with no sub-community picked: pre-select the Global row
        if (picker.selectedId.length === 0 && globalEntry)
            picker.selectedId = globalEntry.id;
        if (out0.length > 1) {
            picker._autoExpandForSelection(out0);
            picker._autoExpandForOwnership(out0);
        }
        picker._present(out0);
    }

    // Fetches a country's own children into childCache, unless already cached
    function _loadChildren(id, onDone) {
        if (picker.childCache[id] !== undefined) {
            if (onDone) onDone(picker.childCache[id]);
            return;
        }

        picker.childLoadingId = id;
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Config.baseUrl + "/community/list-by-parent-id/" + id);
        xhr.setRequestHeader("Accept", "application/json");
        xhr.timeout = 15000;
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (picker.childLoadingId === id) picker.childLoadingId = "";
            var comms = [];
            try {
                var d = JSON.parse(xhr.responseText);
                comms = d.data || d.communities || d.results || [];
            } catch (e) { }
            var nc = {};
            for (var k in picker.childCache) nc[k] = picker.childCache[k];
            var kids = picker._mapCommunities(comms);
            nc[id] = kids;
            picker.childCache = nc;
            if (onDone) onDone(kids);
        };
        xhr.send(null);
    }

    // Expands/collapses a top-level country row, lazily loading its children.
    function _toggleExpand(id) {
        picker.expandedHubId = "";
        if (picker.expandedId === id) { picker.expandedId = ""; return; }
        picker.expandedId = id;
        picker._loadChildren(id);
    }

    // Expands/collapses a superhub child row; register children so _confirm() resolves
    function _toggleHub(hubId) {
        if (picker.expandedHubId === hubId) { picker.expandedHubId = ""; return; }
        picker.expandedHubId = hubId;
        var kids = Config.superhubChildrenById[hubId] || [];
        for (var i = 0; i < kids.length; i++) {
            var k = kids[i];
            var id = String(k.id || k._id || "");
            if (!id) continue;
            picker._byId[id] = {
                id: id,
                name: k.title || k.name || "",
                icon: k.icon || k.icon_url || k.logo_url || "",
                allowPost: !!k.allowPost,
                videoAllowPost: !!k.videoAllowPost,
                isParent: false
            };
        }
    }

    // Auto-expands the first top-level country that contains an owned community, so its "Owner"
    // badge is visible right away instead of only after manually expanding every country.
    function _autoExpandForOwnership(countryItems) {
        if (picker.expandedId.length > 0) return;
        var countryIds = {};
        for (var i = 0; i < countryItems.length; i++) countryIds[countryItems[i].id] = true;
        for (var ownedId in Config.ownedCommunityIdSet) {
            var walk = String(ownedId);
            var seen = {};
            while (walk && !countryIds[walk] && !seen[walk]) {
                seen[walk] = true;
                walk = Config.parentCommunityById[walk];
            }
            if (walk && countryIds[walk]) {
                picker.expandedId = walk;
                picker._loadChildren(walk);
                return;
            }
        }
    }

    // If the pre-selected sub-community belongs to a top-level country row, expand it up front
    function _autoExpandForSelection(countryItems) {
        if (picker.selectedId.length === 0) return;
        var target = picker.selectedId;
        // Already one of the top-level rows itself (rare, but possible); nothing to expand.
        for (var i = 0; i < countryItems.length; i++)
            if (countryItems[i].id === target) return;

        for (var j = 0; j < countryItems.length; j++) {
            (function (countryId) {
                picker._loadChildren(countryId, function (kids) {
                    for (var k = 0; k < kids.length; k++) {
                        if (kids[k].id === target) { picker.expandedId = countryId; return; }
                    }
                });
            })(countryItems[j].id);
        }
    }

    // The button that opened us, when the caller wants the panel anchored to it (desktop).
    property Item caller: null
    property real _callerCx: 0
    property real _callerTop: 0
    property real _callerBottom: 0
    readonly property bool anchored: Config.wideMode && caller !== null

    // The pre-selected row can sit far below the fold once its country auto-expands, so
    // scroll it into view. Rows announce themselves as they are created (children arrive
    // lazily); only the one matching _revealId acts, and only once.
    property string _revealId: ""
    property var _revealTarget: null
    function _queueReveal(item, id) {
        if (picker._revealId === "" || picker._revealId !== String(id)) return;
        picker._revealTarget = item;
        revealTimer.restart();
    }
    Timer {
        id: revealTimer
        interval: 60   // let the expanded rows lay out before measuring
        onTriggered: {
            var it = picker._revealTarget;
            picker._revealTarget = null;
            picker._revealId = "";
            if (!it) return;
            var y = it.mapToItem(sheetContent, 0, 0).y;
            var max = Math.max(0, flickable.contentHeight - flickable.height);
            flickable.contentY = Math.max(0, Math.min(max, y - flickable.height / 2 + it.height / 2));
        }
    }

    function _open() {
        picker._revealId = picker.selectedId;
        if (picker.caller) {
            var p = picker.caller.mapToItem(picker, 0, 0);
            picker._callerCx = p.x + picker.caller.width / 2;
            picker._callerTop = p.y;
            picker._callerBottom = p.y + picker.caller.height;
        }
        picker.visible = true;
        // A prior sheet-mode close leaves pcpTranslate.y at its slide-out offset (pcpDropIn never
        // touches it), so a dropdown-mode open right after would render the panel pushed way down.
        pcpTranslate.y = 0;
        pcpBackdropFade.start();
        if (picker.anchored) pcpDropIn.start(); else pcpSlide.start();
        picker.forceActiveFocus();
    }
    function closeAnimated() {
        pcpBackdropFadeOut.start();
        if (picker.anchored) pcpDropOut.start(); else pcpSlideOut.start();
    }
    Keys.onEscapePressed: picker.closeAnimated()

    function _confirm() {
        var chosen = picker._byId[picker.selectedId] || null;
        var cb = picker._onChosen; picker._onChosen = null;
        picker.closeAnimated();
        if (cb) cb(chosen);
    }

    Rectangle {
        id: pcpBackdrop
        anchors.fill: parent
        // Anchored to a button it is a dropdown, not a modal: catch clicks, don't dim the app.
        color: picker.anchored ? "transparent" : Qt.rgba(0, 0, 0, 0.4)
        opacity: 0
        MouseArea {
            anchors.fill: parent
            onClicked: picker.closeAnimated()
            onWheel: wheel.accepted = true   // don't let scroll fall through to the page below
        }
    }
    NumberAnimation { id: pcpBackdropFade;    target: pcpBackdrop; property: "opacity"; from: 0; to: 1; duration: 200 }
    NumberAnimation { id: pcpBackdropFadeOut; target: pcpBackdrop; property: "opacity"; to: 0;           duration: 200 }

    // Soft elevation so the dropdown reads as floating above the page (the full-width
    // sheet already sits on a dimmed backdrop and doesn't need it).
    DropShadow {
        anchors.fill: sheet
        visible: picker.anchored && sheet.opacity > 0
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
        readonly property real _margin: units.gu(1)
        // x/y instead of anchors: three placements (phone sheet, centred panel, anchored
        // drop-up) can't be expressed by toggling anchors off (see the AnchorChanges gotcha).
        width: sheet.wide ? Math.min(picker.width - units.gu(4), units.gu(50)) : picker.width
        height: Math.min(sheetContent.height + footerBar.height + units.gu(1), picker.height * 0.82)
        x: picker.anchored
           ? Math.max(_margin, Math.min(picker.width - width - _margin, picker._callerCx - width / 2))
           : (picker.width - width) / 2
        // Drops UP above the button when there is room, else falls below it.
        y: picker.anchored
           ? (picker._callerTop - height - _margin >= _margin
              ? picker._callerTop - height - _margin
              : Math.min(picker.height - height - _margin, picker._callerBottom + _margin))
           : picker.height - height - (sheet.wide ? units.gu(4) : 0)
        radius: units.gu(1)
        color: Style.surface
        // Undimmed background needs an edge of its own to read as a floating panel
        border.width: picker.anchored ? units.dp(1) : 0
        border.color: Style.divider
        clip: true
        transformOrigin: Item.TopRight

        // Anchored panels rise a short hop from the button; the sheet slides its full height.
        readonly property real _slideFrom: picker.anchored ? units.gu(2) : sheet.height + units.gu(4)
        transform: Translate { id: pcpTranslate; y: 0 }
        NumberAnimation { id: pcpSlide;    target: pcpTranslate; property: "y"; from: sheet._slideFrom; to: 0;               duration: picker.anchored ? 160 : 300; easing.type: Easing.OutCubic }
        NumberAnimation { id: pcpSlideOut; target: pcpTranslate; property: "y"; to: sheet._slideFrom; duration: picker.anchored ? 140 : 250; easing.type: Easing.InCubic; onStopped: picker.visible = false }

        // Dropdowns snap open from their anchor; a 300ms slide would feel slow.
        ParallelAnimation {
            id: pcpDropIn
            NumberAnimation { target: sheet; property: "opacity"; from: 0; to: 1; duration: 120; easing.type: Easing.OutQuad }
            NumberAnimation { target: sheet; property: "scale";   from: 0.97; to: 1; duration: 120; easing.type: Easing.OutQuad }
        }
        SequentialAnimation {
            id: pcpDropOut
            NumberAnimation { target: sheet; property: "opacity"; to: 0; duration: 100; easing.type: Easing.InQuad }
            ScriptAction { script: picker.visible = false }
        }

        Flickable {
            id: flickable
            anchors { top: parent.top; left: parent.left; right: parent.right; bottom: footerBar.top }
            contentWidth: width
            contentHeight: sheetContent.height
            clip: true

            Column {
                id: sheetContent
                width: flickable.width

                // Dropdown mode: anchored to the compose button, so a slim title suffices.
                Row {
                    visible: picker.anchored
                    width: parent.width - Style.spacingM * 2
                    x: Style.spacingM
                    height: picker.anchored ? units.gu(5) : 0
                    Label {
                        width: parent.width - units.gu(3.5)
                        anchors.verticalCenter: parent.verticalCenter
                        text: Lang.tr("Where should this post go?")
                        font.pixelSize: Style.fontMedium
                        font.weight: Font.DemiBold
                        color: Style.textTitle
                        elide: Text.ElideRight
                    }
                    AbstractButton {
                        width: units.gu(3.5); height: units.gu(3.5)
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: picker.closeAnimated()
                        Icon { anchors.centerIn: parent; width: units.gu(2.2); height: width; name: "close"; color: Style.textSecondary }
                    }
                }

                // Brand-tinted header band, distinct from the community switcher's plain header
                Rectangle {
                    visible: !picker.anchored
                    width: parent.width
                    height: headerCol.height + Style.spacingL * 2
                    color: Qt.rgba(Style.brand.r, Style.brand.g, Style.brand.b, 0.08)

                    AbstractButton {
                        anchors { right: parent.right; top: parent.top; rightMargin: Style.spacingM; topMargin: Style.spacingM }
                        width: units.gu(3.5); height: units.gu(3.5)
                        onClicked: picker.closeAnimated()
                        Icon { anchors.centerIn: parent; width: units.gu(2.2); height: width; name: "close"; color: Style.textSecondary }
                    }

                    Column {
                        id: headerCol
                        anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: Style.spacingL }
                        spacing: Style.spacingS

                        // A dropdown is already tied to its button; it needs neither the
                        // big glyph nor the explainer that a full-screen sheet does.
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: !picker.anchored
                            width: units.gu(5.5); height: width; radius: width / 2
                            color: Style.brand
                            Icon {
                                anchors.centerIn: parent
                                width: units.gu(2.6); height: width
                                name: "edit"
                                color: Style.textOnBrand
                            }
                        }

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Lang.tr("Where should this post go?")
                            font.pixelSize: units.dp(17)
                            font.weight: Font.DemiBold
                            color: Style.textTitle
                        }
                        Label {
                            width: parent.width - Style.spacingM * 4
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: !picker.anchored
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: Lang.tr("Pick the community this post will publish into. Your current browsing view won't change.")
                            font.pixelSize: Style.fontSmall
                            color: Style.textSecondary
                        }
                    }
                }

                Item { width: 1; height: Style.spacingS }

                // Flat radio list (no cards); from Global, each row is a country that can expand
                Repeater {
                    model: picker.items

                    delegate: Column {
                        id: rowCol
                        width: sheetContent.width
                        readonly property bool expandable: picker.topLevelIsCountries && modelData.expandable !== false
                        readonly property bool isExpanded: picker.expandedId === modelData.id
                        readonly property var children: picker.childCache[modelData.id] || []

                        // Group caption, carried by the first row of a section only
                        Item {
                            width: parent.width
                            visible: !!modelData.section
                            height: visible ? sectionLbl.height + Style.spacingM : 0
                            Label {
                                id: sectionLbl
                                x: Style.spacingM
                                anchors.bottom: parent.bottom
                                text: modelData.section || ""
                                font.pixelSize: Style.fontSmall
                                font.weight: Font.DemiBold
                                color: Style.textSecondary
                            }
                        }

                        Item {
                            id: row
                            width: parent.width
                            height: units.gu(7)
                            readonly property bool isSelected: picker.selectedId === modelData.id
                            readonly property int chevronW: rowCol.expandable ? units.gu(6) : 0
                            Component.onCompleted: picker._queueReveal(row, modelData.id)

                            // Left zone (radio + icon + name) selects this row; disabled (dimmed) when
                            // this community doesn't allow the content type being posted.
                            AbstractButton {
                                id: rowSelectBtn
                                anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: parent.right; rightMargin: row.chevronW }
                                enabled: picker._canPost(modelData)
                                opacity: enabled ? 1 : 0.45
                                onClicked: picker.selectedId = modelData.id

                                Row {
                                    anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                                    spacing: Style.spacingM

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: units.gu(2.4); height: width; radius: width / 2
                                        color: "transparent"
                                        border.width: units.dp(1.5)
                                        border.color: row.isSelected ? Style.brand : Style.divider
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: parent.width - units.dp(6); height: width; radius: width / 2
                                            color: Style.brand
                                            visible: row.isSelected
                                        }
                                    }

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: units.gu(4.4); height: width; radius: width / 2
                                        color: Style.iconBackground
                                        CircleImage {
                                            anchors { fill: parent; margins: units.dp(2) }
                                            source: modelData.icon
                                        }
                                    }

                                    Label {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - units.gu(2.4) - units.gu(4.4) - Style.spacingM * 2
                                               - (rowOwnerBadge.visible ? rowOwnerBadge.width + Style.spacingM : 0)
                                        text: rowSelectBtn.enabled ? modelData.name
                                            : (picker.forVideo ? Lang.tr("%1 (video not allowed)").arg(modelData.name)
                                                               : Lang.tr("%1 (posting not allowed)").arg(modelData.name))
                                        font.pixelSize: Style.fontRegular
                                        font.weight: row.isSelected ? Font.DemiBold : Font.Normal
                                        font.family: Style.fontFor(text)
                                        color: row.isSelected ? Style.brand : Style.textPrimary
                                        elide: Text.ElideRight
                                    }

                                    // Owner badge: you manage this community (matches the browse picker).
                                    Rectangle {
                                        id: rowOwnerBadge
                                        visible: picker._isOwned(modelData)
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: rowOwnerLbl.width + units.gu(1.6)
                                        height: units.gu(2.4)
                                        radius: Style.pillRadius
                                        color: "#FCE7F3"
                                        Label {
                                            id: rowOwnerLbl
                                            anchors.centerIn: parent
                                            text: Lang.tr("Owner")
                                            font.pixelSize: Style.fontXSmall
                                            font.weight: Font.Bold
                                            font.family: Style.fontFor(text)
                                            font.letterSpacing: units.dp(0.5)
                                            color: "#DB2777"
                                        }
                                    }
                                }
                            }

                            // Right zone (chevron) expands to load this country's own communities.
                            AbstractButton {
                                visible: rowCol.expandable
                                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                                width: row.chevronW
                                onClicked: picker._toggleExpand(modelData.id)

                                Icon {
                                    anchors.centerIn: parent
                                    width: units.gu(2.2); height: width
                                    name: rowCol.isExpanded ? "go-up" : "go-down"
                                    color: rowCol.isExpanded ? Style.brand : Style.textSecondary
                                }
                            }

                            Rectangle {
                                anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                                height: units.dp(1); color: Style.divider
                            }
                        }

                        // Loading indicator while this country's communities are fetched.
                        Item {
                            visible: rowCol.isExpanded && picker.childLoadingId === modelData.id
                            width: parent.width; height: units.gu(5)
                            ActivityIndicator { anchors.centerIn: parent; running: parent.visible }
                        }

                        // Empty state: country has no (non-deleted) communities of its own.
                        Item {
                            visible: rowCol.isExpanded && picker.childLoadingId !== modelData.id
                                     && picker.childCache[modelData.id] !== undefined && rowCol.children.length === 0
                            width: parent.width; height: units.gu(5)
                            Label {
                                anchors.centerIn: parent
                                text: Lang.tr("No communities found")
                                font.pixelSize: Style.fontSmall
                                color: Style.textSecondary
                            }
                        }

                        // Second level; a superhub row expands again to reveal a third level
                        Repeater {
                            model: rowCol.isExpanded && picker.childLoadingId !== modelData.id ? rowCol.children : []

                            delegate: Column {
                                id: childCol
                                width: rowCol.width
                                readonly property bool isHub: !!modelData.isSuperhub
                                readonly property bool hubExpanded: picker.expandedHubId === modelData.id
                                readonly property var hubKids: childCol.isHub ? (Config.superhubChildrenById[String(modelData.id)] || []) : []
                                // Only offer to expand a hub that actually has communities.
                                readonly property bool hubExpandable: childCol.isHub && childCol.hubKids.length > 0

                                Item {
                                    id: childRow
                                    width: parent.width
                                    height: units.gu(6.5)
                                    readonly property bool isSelected: picker.selectedId === modelData.id
                                    readonly property int chevronW: childCol.hubExpandable ? units.gu(6) : 0
                                    Component.onCompleted: picker._queueReveal(childRow, modelData.id)

                                    // Left zone selects this community; disabled (dimmed) when it
                                    // doesn't allow the content type being posted.
                                    AbstractButton {
                                        id: childSelectBtn
                                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: parent.right; rightMargin: childRow.chevronW }
                                        enabled: picker._canPost(modelData)
                                        opacity: enabled ? 1 : 0.45
                                        onClicked: picker.selectedId = modelData.id

                                        Row {
                                            anchors { fill: parent; leftMargin: Style.spacingM + units.gu(3.2); rightMargin: Style.spacingM }
                                            spacing: Style.spacingM

                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: units.gu(2.2); height: width; radius: width / 2
                                                color: "transparent"
                                                border.width: units.dp(1.5)
                                                border.color: childRow.isSelected ? Style.brand : Style.divider
                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: parent.width - units.dp(6); height: width; radius: width / 2
                                                    color: Style.brand
                                                    visible: childRow.isSelected
                                                }
                                            }

                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: units.gu(3.8); height: width; radius: width / 2
                                                color: Style.iconBackground
                                                CircleImage {
                                                    anchors { fill: parent; margins: units.dp(2) }
                                                    source: modelData.icon
                                                }
                                            }

                                            Label {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - units.gu(2.2) - units.gu(3.8) - Style.spacingM * 2
                                                       - (childCol.isHub ? hubBadge.width + Style.spacingM : 0)
                                                       - (childOwnerBadge.visible ? childOwnerBadge.width + Style.spacingM : 0)
                                                text: modelData.name
                                                font.pixelSize: Style.fontSmall
                                                font.weight: childRow.isSelected ? Font.DemiBold : Font.Normal
                                                font.family: Style.fontFor(text)
                                                color: childRow.isSelected ? Style.brand : Style.textPrimary
                                                elide: Text.ElideRight
                                            }

                                            // HUB badge: marks a superhub (matches the browse picker).
                                            Rectangle {
                                                id: hubBadge
                                                visible: childCol.isHub
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: hubLbl.width + units.gu(1.6)
                                                height: units.gu(2.4)
                                                radius: Style.pillRadius
                                                color: Qt.rgba(Style.brand.r, Style.brand.g, Style.brand.b, 0.14)
                                                Label {
                                                    id: hubLbl
                                                    anchors.centerIn: parent
                                                    text: "HUB"
                                                    font.pixelSize: Style.fontXSmall
                                                    font.weight: Font.Bold
                                                    font.family: Style.fontFamily
                                                    font.letterSpacing: units.dp(0.5)
                                                    color: Style.brand
                                                }
                                            }

                                            // Owner badge: you manage this community (matches the browse picker).
                                            Rectangle {
                                                id: childOwnerBadge
                                                visible: picker._isOwned(modelData)
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
                                        }
                                    }

                                    // Right zone: expand a hub that has communities.
                                    AbstractButton {
                                        visible: childCol.hubExpandable
                                        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                                        width: childRow.chevronW
                                        onClicked: picker._toggleHub(String(modelData.id))
                                        Icon {
                                            anchors.centerIn: parent
                                            width: units.gu(2); height: width
                                            name: childCol.hubExpanded ? "go-up" : "go-down"
                                            color: childCol.hubExpanded ? Style.brand : Style.textSecondary
                                        }
                                    }

                                    Rectangle {
                                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: Style.spacingM + units.gu(3.2); rightMargin: Style.spacingM }
                                        height: units.dp(1); color: Style.divider
                                    }
                                }

                                Item {
                                    visible: childCol.hubExpanded && childCol.hubKids.length === 0
                                    width: parent.width; height: units.gu(5)
                                    Label {
                                        anchors.centerIn: parent
                                        text: Lang.tr("No communities found")
                                        font.pixelSize: Style.fontSmall
                                        color: Style.textSecondary
                                    }
                                }

                                // Third level: the superhub's own communities.
                                Repeater {
                                    model: childCol.hubExpanded ? childCol.hubKids : []

                                    delegate: AbstractButton {
                                        id: gcRow
                                        width: childCol.width
                                        height: units.gu(6)
                                        readonly property string gcId: String(modelData.id || modelData._id || "")
                                        readonly property bool isSelected: picker.selectedId === gcRow.gcId
                                        enabled: picker._canPost(modelData)
                                        opacity: enabled ? 1 : 0.45
                                        onClicked: picker.selectedId = gcRow.gcId
                                        Component.onCompleted: picker._queueReveal(gcRow, gcRow.gcId)

                                        Row {
                                            anchors { fill: parent; leftMargin: Style.spacingM + units.gu(6.4); rightMargin: Style.spacingM }
                                            spacing: Style.spacingM

                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: units.gu(2.2); height: width; radius: width / 2
                                                color: "transparent"
                                                border.width: units.dp(1.5)
                                                border.color: gcRow.isSelected ? Style.brand : Style.divider
                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: parent.width - units.dp(6); height: width; radius: width / 2
                                                    color: Style.brand
                                                    visible: gcRow.isSelected
                                                }
                                            }

                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: units.gu(3.4); height: width; radius: width / 2
                                                color: Style.iconBackground
                                                CircleImage {
                                                    anchors { fill: parent; margins: units.dp(2) }
                                                    source: modelData.icon || modelData.icon_url || modelData.logo_url || ""
                                                }
                                            }

                                            Label {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - units.gu(2.2) - units.gu(3.4) - Style.spacingM * 2
                                                       - (gcOwnerBadge.visible ? gcOwnerBadge.width + Style.spacingM : 0)
                                                text: modelData.title || modelData.name || ""
                                                font.pixelSize: Style.fontSmall
                                                font.weight: gcRow.isSelected ? Font.DemiBold : Font.Normal
                                                font.family: Style.fontFor(text)
                                                color: gcRow.isSelected ? Style.brand : Style.textPrimary
                                                elide: Text.ElideRight
                                            }

                                            // Owner badge: you manage this community (matches the browse picker).
                                            Rectangle {
                                                id: gcOwnerBadge
                                                visible: !!Config.ownedCommunityIdSet[gcRow.gcId]
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: gcOwnerLbl.width + units.gu(1.6)
                                                height: units.gu(2.2)
                                                radius: Style.pillRadius
                                                color: "#FCE7F3"
                                                Label {
                                                    id: gcOwnerLbl
                                                    anchors.centerIn: parent
                                                    text: Lang.tr("Owner")
                                                    font.pixelSize: Style.fontXSmall
                                                    font.weight: Font.Bold
                                                    font.family: Style.fontFor(text)
                                                    font.letterSpacing: units.dp(0.5)
                                                    color: "#DB2777"
                                                }
                                            }
                                        }

                                        Rectangle {
                                            anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: Style.spacingM + units.gu(6.4); rightMargin: Style.spacingM }
                                            height: units.dp(1); color: Style.divider
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Item { width: 1; height: Style.spacingM }
            }
        }

        // Pinned directly under the list so it's always flush against it, never floating below the card.
        Rectangle {
            id: footerBar
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: continueBtn.height + Style.spacingM * 2
            // Rounded to match the sheet's own corners (clip only masks to the bounding box, not the
            // rounded shape, so a square-cornered footer would poke past the sheet's rounded bottom).
            radius: sheet.radius
            color: Style.surface

            // Squares the top back off so only the bottom corners stay rounded, matching the sheet.
            Rectangle {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: Math.min(parent.radius, parent.height / 2)
                color: Style.surface
            }

            // Swallow taps/scroll on the bar so nothing leaks to the page below.
            MouseArea { anchors.fill: parent; onWheel: wheel.accepted = true }

            Rectangle {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: units.dp(1); color: Style.divider
            }

            AbstractButton {
                id: continueBtn
                anchors { verticalCenter: parent.verticalCenter; horizontalCenter: parent.horizontalCenter }
                width: parent.width - Style.spacingM * 2
                height: units.gu(5.5)
                enabled: picker.selectedId.length > 0 && picker._canPost(picker._byId[picker.selectedId])
                onClicked: picker._confirm()

                Rectangle {
                    anchors.fill: parent
                    radius: Style.cardRadius
                    color: parent.enabled ? Style.brand : Style.iconBackground
                }
                Label {
                    anchors.centerIn: parent
                    text: Lang.tr("Continue")
                    font.pixelSize: Style.fontMedium
                    font.weight: Font.DemiBold
                    color: parent.enabled ? Style.textOnBrand : Style.textSecondary
                }
            }
        }
    }
}
