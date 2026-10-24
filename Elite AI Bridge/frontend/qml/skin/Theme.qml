// Elite AI Bridge retro skin: one place for colours, fonts and the CRT levels.
// Colour language (all pages, overlay, wizard): green = good, amber = heads up,
// red = stop / danger, dim = off or unknown, white = Bridge in control.
pragma Singleton
import QtQuick

QtObject {
    id: theme

    // CRT screen levels (0..1). Setup > Display faders write these; both 0 = shader off.
    // UI scale (the Bridge sets this to its scaleUnit; 1.0 in the gallery)
    property real s: 1.0
    // CRT levels: from the Bridge's saved settings when it is running, gallery defaults otherwise
    readonly property bool _hasBridge: typeof bridge !== "undefined" && bridge !== null
    property real crtStatic: _hasBridge && bridge.crtStatic !== undefined ? bridge.crtStatic / 100 : 0.5
    property real crtScreenFx: _hasBridge && bridge.crtScreenFx !== undefined ? bridge.crtScreenFx / 100 : 0.8

    // ---------------------------------------------------------------- screen theme (LAB)
    // Setup > Display > THEME. GREEN is the default. OLD SCHOOL AMBER changes only the screen
    // colour (CRT text, glow, grain, lists, ship art, maps, halo); status colours keep their
    // meaning (green = good, red = danger) and heads-up amber turns yellow so it still stands
    // out against amber text. Hardware (keys, lamps, plates, LED clock) never changes.
    readonly property string screenTheme: _hasBridge && bridge.screenTheme !== undefined ? String(bridge.screenTheme) : "GREEN"
    readonly property bool amber: screenTheme === "AMBER"

    // t(c): the screen version of a colour. Green-family colours become amber, amber heads-up
    // colours become yellow; anything else (red, white, greys) comes back unchanged. Works on
    // "#RRGGBB", "#AARRGGBB" or a color. Bindings that call it update when the theme changes.
    function t(c) {
        if (!amber) return c
        var r, g, b, a = 1.0
        if (typeof c === "string") {
            var h = c.charAt(0) === "#" ? c.substr(1) : c
            if (h.length === 8) { a = parseInt(h.substr(0, 2), 16) / 255; h = h.substr(2) }
            if (h.length !== 6) return c
            r = parseInt(h.substr(0, 2), 16) / 255; g = parseInt(h.substr(2, 2), 16) / 255; b = parseInt(h.substr(4, 2), 16) / 255
        } else { r = c.r; g = c.g; b = c.b; a = c.a }
        var mx = Math.max(r, g, b), mn = Math.min(r, g, b)
        if (mx <= 0.0) return c
        if (g >= r && g >= b && g > mn) {
            // green family -> amber phosphor, same brightness; paler greens stay a little paler
            var k = Math.min(1.0, 0.35 + 1.3 * (mx - mn) / mx)
            return Qt.rgba(mx, mx * (0.957 * (1 - k) + 0.69 * k), mx * (0.878 * (1 - k) + 0.157 * k), a)
        }
        if (r >= g && g >= b && g / r >= 0.55 && g / r <= 0.9 && b / r < 0.45) {
            // amber heads-up -> yellow
            return Qt.rgba(mx, mx * 0.95, mx * 0.42, a)
        }
        return c
    }
    // "R,G,B" for canvas rgba() strings
    function rgb(s) {
        if (!amber) return s
        var p = String(s).split(",")
        var c = t(Qt.rgba(Number(p[0]) / 255, Number(p[1]) / 255, Number(p[2]) / 255, 1))
        return Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255)
    }

    // phosphor + status colours
    readonly property color phosphor: t("#9fdcb0")     // normal CRT text
    readonly property color screen: t("#7dff9c")       // screen accent (selection, art, halo); green in GREEN
    readonly property color ok: "#7dff9c"
    readonly property color info: t("#ffb84d")         // amber heads up (yellow on OLD SCHOOL AMBER)
    readonly property color bad: "#ff5a48"
    readonly property color control: "#e8f0ff"       // white: Bridge in control
    // shared activity colours (voice scope, overlay): green = yours, amber = talking / heads up,
    // white = Bridge flying, red = ship danger or a failed command
    function activityColor(a) {
        switch (String(a)) {
        case "LISTENING": case "DONE": return ok
        case "THINKING": case "FAULT": case "NOCREDITS": return info
        case "SPEAKING": return t("#ff9a3c")
        case "AUTOMATION": return control
        case "CRITICAL": case "FAILED": return bad
        default: return t("#5fae78")
        }
    }
    readonly property color dimText: t("#5f8a6c")
    readonly property color glassTop: t("#0d2416")
    readonly property color glassMid: t("#06140b")
    readonly property color glassEdge: t("#020703")

    // hardware colours
    readonly property color housing: "#2e302a"
    readonly property color plateText: "#e1d7be"
    readonly property color tapeText: "#eeeadf"
    readonly property color recess: "#121210"
    readonly property color keyCream: "#ddd4bb"
    readonly property color keyText: "#1b1a17"

    // fonts (all SIL Open Font License, files in skin/fonts)
    readonly property FontLoader _vt: FontLoader { source: "fonts/VT323-Regular.ttf" }
    readonly property FontLoader _osw: FontLoader { source: "fonts/Oswald.ttf" }
    readonly property FontLoader _stencil: FontLoader { source: "fonts/SairaStencilOne-Regular.ttf" }
    readonly property FontLoader _seg: FontLoader { source: "fonts/DSEG7Classic-Bold.ttf" }
    readonly property FontLoader _stm: FontLoader { source: "fonts/ShareTechMono-Regular.ttf" }
    readonly property string crtFont: _vt.status === FontLoader.Ready ? _vt.name : "Consolas"
    readonly property string labelFont: _osw.status === FontLoader.Ready ? _osw.name : "Segoe UI"
    readonly property string stencilFont: _stencil.status === FontLoader.Ready ? _stencil.name : labelFont
    readonly property string ledFont: _seg.status === FontLoader.Ready ? _seg.name : "Consolas"
    readonly property string counterFont: _stm.status === FontLoader.Ready ? _stm.name : "Consolas"

    // interaction timing (interaction-spec.md)
    readonly property int hoverInMs: 80
    readonly property int hoverOutMs: 120
    readonly property int pressMs: 40
    readonly property int releaseMs: 120
    readonly property int tooltipDelayMs: 600
    readonly property int repeatGuardMs: 300

    // one sound per visual change, through the Bridge's existing cue player when present.
    // The Bridge has three UI sounds (nav, confirm, warn); skin names map onto them.
    // Deck keys stay silent here because the command itself already gives its own feedback.
    readonly property var _cueMap: ({ click: "nav", nav: "nav", tick: "nav", toggle: "confirm",
                                      confirm: "confirm", denied: "warn", warn: "warn", key: "" })
    function cue(name) {
        var mapped = _cueMap[name] !== undefined ? _cueMap[name] : name
        if (mapped !== "" && _hasBridge && bridge.playUiCue)
            bridge.playUiCue(mapped)
    }
}
