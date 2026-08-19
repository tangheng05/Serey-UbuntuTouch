pragma Singleton
import QtQuick 2.7
import Lomiri.Components 1.3

QtObject {
    id: style

    // Single light/dark switch bound to system theme; brand tokens stay fixed
    property bool dark: false

    // --- Brand (fixed across themes) ------------------------------------------
    readonly property color brand: "#0083FA"        // primary blue
    readonly property color brandDark: "#0067C8"
    readonly property color accentRed: "#D30020"     // category badge / downvote

    // --- Semantic state roles (mirror theme.palette normal.positive/negative/focus)
    readonly property color negative: dark ? "#ED3146" : "#C7162B"   // Suru Red / Light Red
    readonly property color positive: dark ? "#3EB34F" : "#0E8420"   // Suru Green / Light Green
    readonly property color focus:    dark ? "#19B6EE" : "#335280"   // Suru Blue / Light Blue (selection/neutral)
    readonly property color danger: negative          // destructive (delete), alias to the negative role
    readonly property color dangerTint: dark ? "#3A1519" : "#FBEAEC"  // danger background wash
    readonly property color success: dark ? "#3EB34F" : "#52C41A"     // positive accent (keeps the app's green in light)

    readonly property color textPrimary: dark ? "#F7F7F7" : "#262626"    // Porcelain / near-Jet
    readonly property color textTitle:   dark ? "#FFFFFF" : "#373737"
    readonly property color textSecondary: dark ? "#ABABAB" : "#5F5F5F"  // Ash / Slate
    readonly property color textOnBrand: "#FFFFFF"                        // on the blue button (fixed)

    readonly property color surface: dark ? "#111111" : "#FFFFFF"        // Jet / White
    readonly property color card:    dark ? "#1B1B1B" : "#FFFFFF"
    readonly property color navigationBg: dark ? "#161616" : "#FFFFFF"
    readonly property color divider: dark ? "#2E2E2E" : "#E4E4E4"        // neutral Suru hairline
    readonly property color iconBackground: dark ? "#262626" : "#F3F3F3" // pills, chips, avatar bg
    readonly property color pressed: dark ? "#2A2A2A" : "#F0F0F0"
    readonly property color dotInactive: dark ? "#4D4D4D" : "#CECECE"
    readonly property color lightGray: dark ? "#3B3B3B" : "#D3D3D3"      // image placeholder
    readonly property color skeleton: dark ? "#2A2A2A" : "#E0E0E0"       // shimmer base
    readonly property color toastBg: "#323232"                           // dark chip (both themes)
    readonly property color videoStage: "#000000"                        // video stage (both themes)

    readonly property real spacingXs: units.gu(0.5)
    readonly property real spacingS: units.gu(1)
    readonly property real spacingM: units.gu(2)
    readonly property real spacingL: units.gu(3)
    readonly property real cellPadding: units.gu(2)

    // Grid-unit type scale; gu(n) == dp(8n), matches old dp() values pixel-for-pixel
    readonly property int fontXSmall: units.gu(1.375) // ~x-small
    readonly property int fontSmall:  units.gu(1.5)   // small
    readonly property int fontRegular: units.gu(1.75) // medium
    readonly property int fontMedium: units.gu(1.875)
    readonly property int fontLarge:  units.gu(2)
    readonly property int fontTitle:  units.gu(2.75)

    // Radii: Lomiri/Suru is low-radius and flat; subtle rounding, not iOS-style pills.
    readonly property real radius: units.gu(0.6)
    readonly property real thumbRadius: units.gu(0.8)
    readonly property real cardRadius: units.gu(0.6)
    readonly property real pillRadius: units.gu(0.6)
    readonly property real chipRadius: units.gu(0.6)
    readonly property real fabRadius: units.gu(0.6)
    readonly property real durationBadgeRadius: units.dp(3)

    readonly property real thumbSize: units.gu(13)   // compact list thumbnail
    readonly property real avatarSize: units.gu(4)
    readonly property real avatarSmall: units.gu(3)
    readonly property real coinIconSize: units.dp(16)
    readonly property real fabSize: units.gu(7)

    // Bundled fonts don't cover each other's glyphs; pick right face via fontFor() to avoid tofu boxes
    property FontLoader fontLoader: FontLoader {
        source: Qt.resolvedUrl("../../assets/fonts/NotoSansKhmer-Regular.ttf")
    }
    readonly property string fontFamily: fontLoader.status === FontLoader.Ready
                                         ? fontLoader.name : "Ubuntu"

    // CJK face (~8 MB, so not the default); also covers Latin, so mixed Latin/Chinese titles render from one face.
    property FontLoader cjkFontLoader: FontLoader {
        source: Qt.resolvedUrl("../../assets/fonts/NotoSansSC-Regular.otf")
    }
    readonly property string cjkFamily: cjkFontLoader.status === FontLoader.Ready
                                        ? cjkFontLoader.name : fontFamily

    property FontLoader bengaliFontLoader: FontLoader {
        source: Qt.resolvedUrl("../../assets/fonts/NotoSansBengali-Regular.ttf")
    }
    readonly property string bengaliFamily: bengaliFontLoader.status === FontLoader.Ready
                                            ? bengaliFontLoader.name : fontFamily

    // Emoji only, never returned by fontFor(); registered so Qt's glyph fallback can find it
    property FontLoader emojiFontLoader: FontLoader {
        source: Qt.resolvedUrl("../../assets/fonts/NotoEmoji-Regular.ttf")
    }

    // Script face by codepoint, else Khmer/Latin default.
    function fontFor(text) {
        if (text && /[⺀-鿿豈-﫿＀-￯]/.test(text))
            return cjkFamily;
        if (text && /[ঀ-৿]/.test(text))
            return bengaliFamily;
        return fontFamily;
    }

    // Khmer combining vowel signs can ink past their advance-width box, so wrapped text needs this margin subtracted to avoid clipping.
    readonly property real wrapSafeMargin: units.gu(0.5)

    // Uppercases the first letter only, the way a keyboard's auto-shift would. Leaves the rest
    // of the string alone, and anything that doesn't start with a letter untouched.
    function sentenceCase(s) {
        if (!s || s.length === 0) return s;
        var first = s.charAt(0);
        var up = first.toUpperCase();
        return up === first ? s : up + s.substring(1);
    }

    // Helpers: relative timestamp formatted as "just now / Xm / Xh / Xd ago / DD Mon [YYYY]".
    function formatTimeAgo(dateStr) {
        if (!dateStr)
            return "";
        var diff = (Date.now() - new Date(dateStr).getTime()) / 1000;
        if (isNaN(diff))
            return dateStr;
        if (diff < 60) return qsTr("just now");
        if (diff < 3600) return Math.floor(diff / 60) + qsTr("m ago");
        if (diff < 86400) return Math.floor(diff / 3600) + qsTr("h ago");
        var days = Math.floor(diff / 86400);
        if (days < 7) return days + qsTr("d ago");
        var d = new Date(dateStr);
        var months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
        var sameYear = d.getFullYear() === new Date().getFullYear();
        if (sameYear) return d.getDate() + " " + months[d.getMonth()];
        return d.getDate() + " " + months[d.getMonth()] + " " + d.getFullYear();
    }

    // Blue-tinted avatar fallback background derived from a username.
    function avatarTint(name) {
        return Qt.rgba(0, 0.51, 0.98, 0.12);
    }
}
