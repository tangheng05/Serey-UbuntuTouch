pragma Singleton
import QtQuick 2.7
import Lomiri.Components 1.3

/*
 * Central design tokens — single source of truth for colour, type, spacing and
 * shape. Ported from the serey-ubutu design system (flat, hairline-divider look,
 * blue brand). Colours are explicit for deterministic rendering across the light
 * Ambiance theme. Spacing uses grid units (`units.gu`); type and radii use device
 * pixels (`units.dp`) to match the reference's px-based scale.
 */
QtObject {
    id: style

    // --- Brand ----------------------------------------------------------------
    readonly property color brand: "#0083FA"        // primary blue
    readonly property color brandDark: "#0067C8"
    readonly property color accentRed: "#D30020"     // category badge / downvote
    readonly property color danger: "#C7162B"        // destructive (delete)
    readonly property color dangerTint: "#FBEAEC"     // danger background wash
    readonly property color success: "#52C41A"       // satisfied rule / positive

    // --- Text -----------------------------------------------------------------
    readonly property color textPrimary: "#262626"
    readonly property color textTitle: "#373737"
    readonly property color textSecondary: "#5F5F5F"
    readonly property color textOnBrand: "#FFFFFF"

    // --- Surfaces -------------------------------------------------------------
    readonly property color surface: "#FFFFFF"
    readonly property color card: "#FFFFFF"
    readonly property color navigationBg: "#FFFFFF"
    readonly property color divider: "#E4E4E4"        // neutral Suru hairline
    readonly property color iconBackground: "#F3F3F3" // pills, chips, avatar bg
    readonly property color pressed: "#F0F0F0"
    readonly property color dotInactive: "#CECECE"
    readonly property color lightGray: "#D3D3D3"      // image placeholder
    readonly property color skeleton: "#E0E0E0"       // shimmer base
    readonly property color toastBg: "#323232"
    readonly property color videoStage: "#000000"

    // --- Spacing (grid units) -------------------------------------------------
    readonly property real spacingXs: units.gu(0.5)
    readonly property real spacingS: units.gu(1)
    readonly property real spacingM: units.gu(2)
    readonly property real spacingL: units.gu(3)
    readonly property real cellPadding: units.gu(2)

    // --- Type scale (device px) ----------------------------------------------
    readonly property int fontXSmall: units.dp(11)
    readonly property int fontSmall: units.dp(12)
    readonly property int fontRegular: units.dp(14)
    readonly property int fontMedium: units.dp(15)
    readonly property int fontLarge: units.dp(16)
    readonly property int fontTitle: units.dp(22)

    // --- Radii ----------------------------------------------------------------
    // Lomiri/Suru is low-radius and flat — small, consistent rounding instead of
    // the iOS pill/card look. Full pills (radius: height/2) are avoided in favour
    // of these subtle rounded-rectangles.
    readonly property real radius: units.gu(0.6)
    readonly property real thumbRadius: units.gu(0.8)
    readonly property real cardRadius: units.gu(0.6)
    readonly property real pillRadius: units.gu(0.6)
    readonly property real chipRadius: units.gu(0.6)
    readonly property real fabRadius: units.gu(0.6)
    readonly property real durationBadgeRadius: units.dp(3)

    // --- Sizes ----------------------------------------------------------------
    readonly property real thumbSize: units.gu(13)   // compact list thumbnail
    readonly property real avatarSize: units.gu(4)
    readonly property real avatarSmall: units.gu(3)
    readonly property real coinIconSize: units.dp(16)
    readonly property real fabSize: units.gu(7)

    // --- Typography / fonts ---------------------------------------------------
    // The bundled Noto Sans Khmer covers Khmer (and Latin) but has NO CJK glyphs,
    // and the bundled Noto Sans SC covers Chinese (and Latin) but not Khmer. Qt's
    // automatic glyph fallback ignores app-added fonts on fontconfig platforms, so
    // a missing glyph does NOT silently borrow from the other bundled font — it
    // renders as tofu (□). The device has no system CJK font to fall back to
    // either. So a single `font.family` string can only cover one of the two
    // non-Latin scripts; pick the right one per label via `fontFor(text)` below.
    // Content labels (post/comment/video text, inputs) use `font.family:
    // Style.fontFor(text)`; pure-Latin chrome may still use `Style.fontFamily`.
    property FontLoader fontLoader: FontLoader {
        source: Qt.resolvedUrl("../../assets/fonts/NotoSansKhmer-Regular.ttf")
    }
    readonly property string fontFamily: fontLoader.status === FontLoader.Ready
                                         ? fontLoader.name : "Ubuntu"

    // Simplified-Chinese (+ Latin) face, used only when a string actually
    // contains CJK. ~8 MB — the reason it isn't the default family (most content
    // is Latin/Khmer). Noto Sans SC also covers Latin, so a mixed "Malaysia
    // Healthcare 马来西亚…" title renders entirely from this one face.
    property FontLoader cjkFontLoader: FontLoader {
        source: Qt.resolvedUrl("../../assets/fonts/NotoSansSC-Regular.otf")
    }
    readonly property string cjkFamily: cjkFontLoader.status === FontLoader.Ready
                                        ? cjkFontLoader.name : fontFamily

    // Choose the correct bundled face for a run of text: the CJK face when the
    // string contains any CJK codepoint (ideographs, kana, fullwidth, compat),
    // otherwise the Khmer/Latin face. Cheap enough to bind directly on labels
    // (re-runs only when the text changes). A label mixing Khmer AND Chinese —
    // very rare here — gets CJK and tofus the Khmer run; single-script and
    // Latin-mixed labels (the common cases) all resolve correctly.
    function fontFor(text) {
        if (text && /[⺀-鿿豈-﫿＀-￯]/.test(text))
            return cjkFamily;
        return fontFamily;
    }

    // --- Helpers --------------------------------------------------------------
    // Relative timestamp: "just now / Xm / Xh / Xd ago / DD Mon [YYYY]".
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
