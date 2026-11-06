// Holiday packs. One engine (skin/HolidayDecor.qml) draws every holiday; a pack only names
// its art (holidays/art/*.svg, made by make_holiday_art.py), its dates and a few numbers.
// To add a holiday: draw its art, add a pack here, add its name to ORDER (the Display page
// menu and AUTO both read ORDER) and to HOLIDAY_MODES in frontend/main.py.
//
//   label       name on the Display page menu
//   from / to   month-day range for AUTO (inclusive, may wrap the year), or
//   easter      [first, last] days counted from Easter Sunday (Easter moves every year)
//   lunar       [first, last] days counted from Lunar New Year's Day (table below)
//   sound       what a prop says when clicked (frontend/sounds/<name>.wav); the turkey gobbles
//   screen      screen colour while it's on (a Theme.qml palette; "" keeps the pilot's own theme)
//   garland     edge strings: "leaves" sway, "bulbs" hang and twinkle
//   fall        things drifting down the window: art, how many, size and speed ranges
//   column      what stands on the module column top edge ("turkey" is a built-in rig)
//   corner      what sits in the bottom corner of the module column
// Colours: holiday art keeps clear of alarm red (red means danger on the Bridge).
.pragma library

var PACKS = {
    "NEW_YEAR": {
        label: "NEW YEAR",
        from: [12, 31], to: [1, 2],
        sound: "noisemaker",
        screen: "GOLD",
        garland: { kind: "leaves", art: ["star_gold", "confetti_blue", "star_silver", "confetti_pink", "confetti_green"], step: 22, size: 22 },
        fall: { art: ["confetti_gold", "confetti_white", "confetti_blue", "confetti_green", "confetti_pink", "star_gold", "star_silver"],
                count: 28, size: [12, 22], speed: [40, 70], sway: [8, 22], spin: 220, flip: true, opacity: 0.8 },
        column: ["party_hat_blue", "party_hat_gold", "popper"],
        corner: ["popper", "party_hat_gold", "star_gold"]
    },
    "VALENTINES": {
        label: "VALENTINE'S DAY",
        from: [2, 10], to: [2, 14],
        sound: "harp",
        screen: "ROSE",
        garland: { kind: "leaves", art: ["heart_pink", "heart_white", "heart_rose", "heart_light"], step: 22, size: 22 },
        fall: { art: ["heart_pink", "heart_rose", "heart_light", "heart_white"],
                count: 14, size: [20, 34], speed: [22, 38], sway: [14, 30], spin: 30, flip: true, opacity: 0.72 },
        column: ["heart_box", "rose"],
        corner: ["rose", "heart_pink", "heart_light"]
    },
    "LUNAR_NEW_YEAR": {
        label: "LUNAR NEW YEAR",
        lunar: [-1, 6],
        sound: "gong",
        screen: "JADE",
        garland: { kind: "bulbs", art: ["lantern", "lantern_gold", "lantern"], step: 52, size: 36 },
        fall: { art: ["plum_blossom", "blossom_white", "plum_blossom", "gold_coin"],
                count: 14, size: [18, 30], speed: [20, 34], sway: [16, 34], spin: 50, flip: true, opacity: 0.72 },
        column: ["red_envelope", "mandarin", "mandarin"],
        corner: ["mandarin", "red_envelope", "gold_coin"]
    },
    "ST_PATRICKS": {
        label: "ST. PATRICK'S DAY",
        from: [3, 14], to: [3, 17],
        sound: "coins",
        screen: "EMERALD",
        garland: { kind: "leaves", art: ["shamrock", "shamrock_light", "gold_coin", "shamrock_light", "shamrock"], step: 22, size: 24 },
        fall: { art: ["shamrock", "shamrock_light", "shamrock", "shamrock_light", "gold_coin"],
                count: 14, size: [22, 34], speed: [24, 40], sway: [14, 32], spin: 60, flip: true, opacity: 0.72 },
        column: ["green_hat", "pot_of_gold"],
        corner: ["pot_of_gold", "gold_coin", "shamrock"]
    },
    "EASTER": {
        label: "EASTER",
        easter: [-7, 1],
        sound: "chirp",
        screen: "SKY",
        garland: { kind: "leaves", art: ["egg_blue", "egg_pink", "egg_yellow", "egg_green"], step: 24, size: 22 },
        fall: { art: ["blossom_pink", "blossom_white", "blossom_pink", "blossom_white"],
                count: 16, size: [18, 30], speed: [18, 32], sway: [16, 34], spin: 50, flip: true, opacity: 0.72 },
        column: ["chick", "egg_blue", "egg_pink"],
        corner: ["egg_yellow", "egg_green", "chick"]
    },
    "HALLOWEEN": {
        label: "HALLOWEEN",
        from: [10, 24], to: [10, 31],
        sound: "spooky",
        screen: "PURPLE",
        garland: { kind: "leaves", art: ["bat", "candy_corn", "maple_orange", "bat", "candy_corn"], step: 24, size: 24 },
        fall: { art: ["maple_orange", "maple_brown", "bat", "maple_gold", "bat", "oak_rust"],
                count: 12, size: [28, 42], speed: [26, 44], sway: [18, 40], spin: 50, flip: true, opacity: 0.7 },
        column: ["ghost", "jack_o_lantern"],
        corner: ["jack_o_lantern", "candy_corn", "candy_corn"]
    },
    "AUTUMN": {
        label: "AUTUMN",
        from: [11, 1], to: [11, 30],
        sound: "knock",
        screen: "COPPER",
        garland: { kind: "leaves", art: ["maple_red", "maple_orange", "maple_gold", "oak_brown", "maple_brown", "acorn", "oak_rust"], step: 20, size: 26 },
        fall: { art: ["maple_red", "maple_orange", "maple_gold", "maple_brown", "oak_brown", "oak_rust"],
                count: 12, size: [30, 46], speed: [26, 44], sway: [18, 40], spin: 60, flip: true, opacity: 0.68 },
        column: ["turkey", "pumpkin"],
        corner: ["pumpkin", "pumpkin", "acorn"]
    },
    "CHRISTMAS": {
        label: "CHRISTMAS",
        from: [12, 1], to: [12, 30],
        sound: "jingle",
        screen: "ICE",
        garland: { kind: "bulbs", art: ["bulb_gold", "bulb_white", "bulb_green", "bulb_blue", "bulb_red"], step: 34, size: 22 },
        fall: { art: ["flake_a", "flake_a", "flake_b", "flake_b", "flake_b"],
                count: 22, size: [12, 26], speed: [20, 38], sway: [10, 26], spin: 25, flip: false, opacity: 0.7 },
        column: ["present_red", "present_green", "present_gold"],
        corner: ["present_blue", "present_green", "present_gold"]
    }
}

// Secret pack: five taps on the ELITE AI BRIDGE title turn it on (this session only).
// Not in ORDER, so it's never on the menu and never picked by AUTO.
PACKS["LOST_CARGO"] = {
    label: "LOST CARGO", screen: "",
    garland: null,
    fall: { art: ["canister_a", "canister_b"], count: 9, size: [42, 60], speed: [30, 50], sway: [6, 14], spin: 40, flip: false, opacity: 0.85 },
    column: [], corner: []
}

// Menu order (roughly calendar order). Earlier entries win if two overlap: Valentine's
// (Feb 10 to 14) beats Lunar New Year in the years they meet, and St. Patrick's beats a
// very early Easter.
var ORDER = ["NEW_YEAR", "VALENTINES", "LUNAR_NEW_YEAR", "ST_PATRICKS", "EASTER", "HALLOWEEN", "AUTUMN", "CHRISTMAS"]

// Easter Sunday (Gregorian, anonymous algorithm) as a Date at local midnight.
function easterSunday(y) {
    var a = y % 19, b = Math.floor(y / 100), c = y % 100, d = Math.floor(b / 4), e = b % 4
    var f = Math.floor((b + 8) / 25), g = Math.floor((b - f + 1) / 3)
    var h = (19 * a + b - d - g + 15) % 30, i = Math.floor(c / 4), k = c % 4
    var l = (32 + 2 * e + 2 * i - h - k) % 7, m = Math.floor((a + 11 * h + 22 * l) / 451)
    var month = Math.floor((h + l - 7 * m + 114) / 31), day = ((h + l - 7 * m + 114) % 31) + 1
    return new Date(y, month - 1, day)
}

// Lunar New Year's Day, 2026 to 2045 (it follows the moon, so it's a table).
var LUNAR_DAYS = { 2026: [2, 17], 2027: [2, 6], 2028: [1, 26], 2029: [2, 13], 2030: [2, 3], 2031: [1, 23],
                   2032: [2, 11], 2033: [1, 31], 2034: [2, 19], 2035: [2, 8], 2036: [1, 28], 2037: [2, 15],
                   2038: [2, 4], 2039: [1, 24], 2040: [2, 12], 2041: [2, 1], 2042: [1, 22], 2043: [2, 10],
                   2044: [1, 30], 2045: [2, 17] }

function daysFrom(anchor, date) {
    var today = new Date(date.getFullYear(), date.getMonth(), date.getDate())
    return Math.round((today - anchor) / 86400000)
}

function isOn(p, date) {
    if (p.lunar) {
        var ld = LUNAR_DAYS[date.getFullYear()]
        if (!ld) return false
        var dl = daysFrom(new Date(date.getFullYear(), ld[0] - 1, ld[1]), date)
        return dl >= p.lunar[0] && dl <= p.lunar[1]
    }
    if (p.easter) {
        var diff = daysFrom(easterSunday(date.getFullYear()), date)
        return diff >= p.easter[0] && diff <= p.easter[1]
    }
    if (!p.from) return false
    var md = (date.getMonth() + 1) * 100 + date.getDate()
    var a = p.from[0] * 100 + p.from[1], b = p.to[0] * 100 + p.to[1]
    return a <= b ? (md >= a && md <= b) : (md >= a || md <= b)
}

// mode: "AUTO", "OFF" or a pack name. Returns the pack name to show, or "".
function active(mode, date) {
    mode = String(mode || "AUTO").toUpperCase()
    if (mode === "THANKSGIVING") mode = "AUTUMN"      // renamed 2026-11-06
    if (mode === "OFF") return ""
    if (PACKS[mode]) return mode
    for (var i = 0; i < ORDER.length; i++)
        if (isOn(PACKS[ORDER[i]], date)) return ORDER[i]
    return ""
}

// Menu entries for the Display page: [value, label] pairs.
function menu() {
    var out = [["AUTO", "ON"], ["OFF", "OFF"]]     // ON (stored as AUTO) = whichever holiday the date says
    for (var i = 0; i < ORDER.length; i++) out.push([ORDER[i], PACKS[ORDER[i]].label])
    return out
}
