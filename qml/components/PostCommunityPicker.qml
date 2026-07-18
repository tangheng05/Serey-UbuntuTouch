import QtQuick 2.7
import Lomiri.Components 1.3
import "../Theme"
import "../Session"

// Bottom sheet asking which community a new blog post should go into.
// Opened from the compose button: if the current source (e.g. a parent
// community) has sub-communities, the user must pick one before the
// composer opens. If a sub-community was already the active context, it
// comes pre-selected — the user can still change it before continuing.
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
    // True when `items` is the country list (Global's root fetch) rather than a single
    // country's own sub-communities — only then can rows be expanded for their children.
    property bool topLevelIsCountries: false
    // country id (string) -> its fetched children, or undefined until expanded.
    property var childCache: ({})
    property string expandedId: ""
    property string childLoadingId: ""
    // Flat id -> entry lookup across both `items` and every fetched child list, so
    // _confirm() can resolve a selection made at either level.
    property var _byId: ({})

    // Drops soft-deleted rows the backend still returns in these list endpoints.
    function _isDeleted(m) { return !!(m.deleted || m.deleted_at || m.is_deleted); }

    // The Global feed (source id 0) is a filter sentinel, but the backend also
    // has a real, postable "Global" community record (dns serey.io) at the top
    // of the tree. Resolve it from the cached get-communities map so Global can
    // be offered as a direct post target; null while the tree hasn't loaded or
    // if that record isn't open for posting. Marked non-expandable: its
    // children in the raw tree are the countries, which already fill the list.
    function _globalEntry() {
        var dns = Config.sources[0].dns;
        for (var k in Config.communityById) {
            var c = Config.communityById[k];
            if (!c || c.dns !== dns) continue;
            if (!c.allowPost) return null;
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

    // Entry point: fetches the current source's sub-communities and, only if
    // there are any, shows the picker. Otherwise calls back immediately with
    // no override (the composer falls back to the current Config context).
    function openFor(onChosen) {
        picker._onChosen = onChosen;
        picker.selectedId = Config.selectedSubCommunity ? String(Config.selectedSubCommunity.id) : "";
        picker.childCache = ({});
        picker.expandedId = "";
        picker._byId = ({});
        picker._fetch();
    }

    function _mapCommunities(comms) {
        var out = [];
        for (var i = 0; i < comms.length; i++) {
            var m = comms[i];
            if (picker._isDeleted(m)) continue;
            var entry = {
                id: String(m.id || m._id || ""),
                name: m.title || m.name || "",
                icon: m.icon_url || m.logo_url || m.profile_image || "",
                allowPost: !!m.is_allow_post,
                videoAllowPost: !!m.video_is_allow_post,
                isParent: false
            };
            out.push(entry);
            picker._byId[entry.id] = entry;
        }
        return out;
    }

    function _fetch() {
        var apiId = Config.sources[Config.sourceIndex].id;
        picker.topLevelIsCountries = (apiId === 0);

        // Global (id 0) has no target of its own. Rather than hitting
        // list-by-parent-id/1 (the raw Country table — includes countries with
        // no real community, and deleted ones), reuse Config.sources: the same
        // curated, non-deleted country list the community switcher's rows show,
        // already fetched once at startup via CommunityService.listAll.
        if (picker.topLevelIsCountries) {
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
            if (out0.length === 0) {
                var cbG = picker._onChosen; picker._onChosen = null;
                if (cbG) cbG(null);
                return;
            }
            // Browsing Global with no sub-community picked: pre-select the
            // Global row so the current context is the default target.
            if (picker.selectedId.length === 0 && globalEntry)
                picker.selectedId = globalEntry.id;
            picker.items = out0;
            picker._autoExpandForSelection(out0);
            picker._open();
            return;
        }

        picker.loading = true;
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Config.baseUrl + "/community/list-by-parent-id/" + apiId);
        xhr.setRequestHeader("Accept", "application/json");
        xhr.timeout = 15000;
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            picker.loading = false;
            var comms = [];
            try {
                var d = JSON.parse(xhr.responseText);
                comms = d.data || d.communities || d.results || [];
            } catch (e) { }

            var mapped = picker._mapCommunities(comms);
            if (mapped.length === 0) {
                // Nothing to choose between — post straight into the current context.
                var cb = picker._onChosen; picker._onChosen = null;
                if (cb) cb(null);
                return;
            }

            var out = [];
            // The parent/source itself is only offered when it's directly postable.
            if (Config.allowPostByDns[Config.communityDns]) {
                var parentEntry = {
                    id: String(Config.sources[Config.sourceIndex].id),
                    name: Config.sources[Config.sourceIndex].name,
                    icon: Config.communityIcon(Config.communityDns),
                    allowPost: true,
                    videoAllowPost: !!Config.videoAllowPostByDns[Config.communityDns],
                    isParent: true
                };
                out.push(parentEntry);
                picker._byId[parentEntry.id] = parentEntry;
                // No sub-community active: pre-select the community being
                // browsed so the current context is the default target.
                if (picker.selectedId.length === 0)
                    picker.selectedId = parentEntry.id;
            }
            picker.items = out.concat(mapped);
            picker._open();
        };
        xhr.send(null);
    }

    // Fetches a country's own children into childCache, unless already cached.
    // onDone(childrenArray), if given, fires with the (possibly cached) result.
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
        if (picker.expandedId === id) { picker.expandedId = ""; return; }
        picker.expandedId = id;
        picker._loadChildren(id);
    }

    // If the pre-selected sub-community belongs to one of the top-level country
    // rows, expand that row up front so the auto-selected pick is visible right
    // when the sheet opens, instead of just silently highlighted off-screen.
    // Checks every country's actual children rather than trusting a `country`
    // name field on the community record, which nested records may not carry.
    function _autoExpandForSelection(countryItems) {
        if (picker.selectedId.length === 0) return;
        var target = picker.selectedId;
        // Already one of the top-level rows itself (rare, but possible) — nothing to expand.
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

    function _open() {
        picker.visible = true;
        pcpBackdropFade.start();
        pcpSlide.start();
    }
    function closeAnimated() { pcpBackdropFadeOut.start(); pcpSlideOut.start(); }

    function _confirm() {
        var chosen = picker._byId[picker.selectedId] || null;
        var cb = picker._onChosen; picker._onChosen = null;
        picker.closeAnimated();
        if (cb) cb(chosen);
    }

    Rectangle {
        id: pcpBackdrop
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.4)
        opacity: 0
        MouseArea { anchors.fill: parent; onClicked: picker.closeAnimated() }
    }
    NumberAnimation { id: pcpBackdropFade;    target: pcpBackdrop; property: "opacity"; from: 0; to: 1; duration: 200 }
    NumberAnimation { id: pcpBackdropFadeOut; target: pcpBackdrop; property: "opacity"; to: 0;           duration: 200 }

    Rectangle {
        id: sheet
        readonly property bool wide: Config.wideMode
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: sheet.wide ? units.gu(4) : 0
        }
        width: sheet.wide ? Math.min(parent.width - units.gu(4), units.gu(50)) : parent.width
        height: Math.min(sheetContent.height + units.gu(4), picker.height * 0.82)
        radius: units.gu(1)
        color: Style.surface
        clip: true

        transform: Translate { id: pcpTranslate; y: 0 }
        NumberAnimation { id: pcpSlide;    target: pcpTranslate; property: "y"; from: sheet.height + units.gu(4); to: 0;             duration: 300; easing.type: Easing.OutCubic }
        NumberAnimation { id: pcpSlideOut; target: pcpTranslate; property: "y"; to: sheet.height + units.gu(4); duration: 250; easing.type: Easing.InCubic; onStopped: picker.visible = false }

        Flickable {
            id: flickable
            anchors.fill: parent
            contentWidth: width
            contentHeight: sheetContent.height
            clip: true

            Column {
                id: sheetContent
                width: flickable.width

                // ── Brand-tinted header band — distinct from the plain grabber-bar
                // header the general community switcher uses, so the two sheets
                // don't get mistaken for one another at a glance.
                Rectangle {
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

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
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
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: Lang.tr("Pick the community this post will publish into. Your current browsing view won't change.")
                            font.pixelSize: Style.fontSmall
                            color: Style.textSecondary
                        }
                    }
                }

                Item { width: 1; height: Style.spacingS }

                // ── Flat radio list (no cards) — visually distinct from the
                // bordered platform cards in the community switcher. When browsing
                // from Global, each row is a country and can expand to reveal its
                // own communities so a target can be picked without leaving here.
                Repeater {
                    model: picker.items

                    delegate: Column {
                        id: rowCol
                        width: sheetContent.width
                        readonly property bool expandable: picker.topLevelIsCountries && modelData.expandable !== false
                        readonly property bool isExpanded: picker.expandedId === modelData.id
                        readonly property var children: picker.childCache[modelData.id] || []

                        Item {
                            id: row
                            width: parent.width
                            height: units.gu(7)
                            readonly property bool isSelected: picker.selectedId === modelData.id
                            readonly property int chevronW: rowCol.expandable ? units.gu(6) : 0

                            // Left zone (radio + icon + name) — selects this row.
                            AbstractButton {
                                anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: parent.right; rightMargin: row.chevronW }
                                onClicked: picker.selectedId = modelData.id

                                Row {
                                    anchors { fill: parent; leftMargin: Style.spacingM; rightMargin: Style.spacingM }
                                    spacing: Style.spacingM

                                    // Radio indicator
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
                                        text: modelData.name
                                        font.pixelSize: Style.fontRegular
                                        font.weight: row.isSelected ? Font.DemiBold : Font.Normal
                                        font.family: Style.fontFor(text)
                                        color: row.isSelected ? Style.brand : Style.textPrimary
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            // Right zone (chevron) — expands to load this country's own communities.
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

                        // Empty state — country has no (non-deleted) communities of its own.
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

                        // Indented child rows (this country's own communities).
                        Repeater {
                            model: rowCol.isExpanded && picker.childLoadingId !== modelData.id ? rowCol.children : []

                            delegate: AbstractButton {
                                id: childRow
                                width: rowCol.width
                                height: units.gu(6.5)
                                readonly property bool isSelected: picker.selectedId === modelData.id
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
                                        text: modelData.name
                                        font.pixelSize: Style.fontSmall
                                        font.weight: childRow.isSelected ? Font.DemiBold : Font.Normal
                                        font.family: Style.fontFor(text)
                                        color: childRow.isSelected ? Style.brand : Style.textPrimary
                                        elide: Text.ElideRight
                                    }
                                }

                                Rectangle {
                                    anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: Style.spacingM + units.gu(3.2); rightMargin: Style.spacingM }
                                    height: units.dp(1); color: Style.divider
                                }
                            }
                        }
                    }
                }

                Item { width: 1; height: Style.spacingM }

                AbstractButton {
                    width: parent.width - Style.spacingM * 2
                    x: Style.spacingM
                    height: units.gu(5.5)
                    enabled: picker.selectedId.length > 0
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

                Item { width: 1; height: Style.spacingL }
            }
        }
    }
}
