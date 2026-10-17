// COMMANDER (page 5). Retro redesign, build step 11 (mockup commander_v1.png, approved "for now").
// Only what Elite itself reports: ranks + progress (Rank / Progress events), Elite's own career
// totals (Statistics, written at login), superpower reputation, the current ship, the full hold
// and this session's counts. No estimated commander values.
import QtQuick
import "../skin"

Item {
    id: cm
    property var app
    property bool demo: false
    signal denied(string title, string reason)
    signal notice(string title, string detail, string level)

    // tour highlight targets (Main.qml pageHelpTarget)
    readonly property Item ranksTarget: ranksPlate
    readonly property Item recordTarget: careerPlate
    readonly property Item shipTarget: shipPlate
    readonly property Item sessionTarget: sessionPlate
    readonly property Item cargoTarget: oddPlate   // tour step ODD STATS (was cargo)
    readonly property Item deckTarget: deck

    readonly property real s: Theme.s
    readonly property real g: Math.max(8, 14 * s)

    // ---------- helpers
    function up(x) { x = String(x === undefined || x === null ? "-" : x); return x === "" ? "-" : x.toUpperCase() }
    function num(v) { return Math.round(Number(v) || 0).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",") }
    function compact(v) {
        v = Number(v) || 0
        var a = Math.abs(v)
        if (a >= 1e9) return (v / 1e9).toFixed(2) + " B"
        if (a >= 1e6) return (v / 1e6).toFixed(1) + " M"
        return num(v)
    }

    // ---------- ranks (swap only when the content changes; the bridge resends every 250 ms)
    readonly property var liveRanks: bridge.commanderRanks || []
    property var ranks: []
    property string ranksKey: ""
    onLiveRanksChanged: {
        var k = JSON.stringify(liveRanks)
        if (k === ranksKey) return
        ranksKey = k
        ranks = liveRanks
    }
    // promotion: flash the tile and show the banner (not on the first value we see)
    property int promoSeen: -1
    property string promoKey: ""
    property string promoText: ""
    readonly property int livePromo: bridge.commanderPromotionSerial
    onLivePromoChanged: {
        if (promoSeen >= 0 && livePromo > promoSeen) {
            promoKey = String(bridge.commanderPromotionKey || "")
            promoText = String(bridge.commanderPromotionText || "")
            promoTimer.restart()
            Theme.cue("confirm")
        }
        promoSeen = livePromo
    }
    Component.onCompleted: promoSeen = livePromo
    Timer { id: promoTimer; interval: 7000; onTriggered: { cm.promoKey = ""; cm.promoText = "" } }

    // ---------- hold size (the ship panel's CARGO bar)
    readonly property int cap: bridge.cargoCapacity > 0 ? bridge.cargoCapacity : 0
    readonly property int used: Math.max(0, bridge.cargoUsed)

    // ---------- deck helpers
    // ---------- 2.0.2 FLEET: stored ships (swap only when the content changes, so scroll holds)
    property var fleet: []
    property string fleetKey: ""
    readonly property var liveFleet: bridge.commanderFleet || []
    onLiveFleetChanged: { var k = JSON.stringify(liveFleet); if (k !== fleetKey) { fleetKey = k; fleet = liveFleet } }
    property int fleetSel: -1                       // picked ShipID
    readonly property var fleetPick: {
        for (var i = 0; i < fleet.length; i++) if (Number(fleet[i].shipId) === fleetSel) return fleet[i]
        return null
    }
    function hereSys(sys) { return String(sys || "").toLowerCase() !== "" && String(sys || "").toLowerCase() === String(bridge.system || "").toLowerCase() }
    function mmss(sec) { sec = Math.max(0, Math.round(sec)); var h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60); return h > 0 ? h + " H " + m + " MIN" : m + " MIN" }

    readonly property string bstate: String(bridge.bridgeState || "").toUpperCase()
    readonly property bool inControl: bridge.controlOwner !== "NONE" && bridge.controlOwner !== ""
    readonly property bool bindsReady: bridge.eliteControlsReady
    readonly property string bindsReason: String(bridge.eliteControlReason || "") !== "" ? String(bridge.eliteControlReason).toUpperCase() : "ELITE KEY BINDS NOT FOUND // SEE SETUP > CONTROLS"

    // ---------- layout
    readonly property real deckH: height * 0.175
    readonly property real deckY: height - deckH
    readonly property real bodyH: deckY - g
    readonly property real leftW: width * 0.695
    readonly property real rightX: leftW + g
    readonly property real rightW: width - rightX
    readonly property real ranksH: bodyH * 0.655
    readonly property real lowY: ranksH + g
    readonly property real lowH: bodyH - lowY
    readonly property real shipH: bodyH * 0.47
    readonly property real cargoY: shipH + g
    readonly property real cargoH: bodyH - cargoY

    component Caption: Text {
        color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: Math.max(8, 13 * cm.s); font.letterSpacing: 3 * cm.s
    }

    // ================================================================= RANKS
    Plate {
        id: ranksPlate
        x: 0; y: 0; width: cm.leftW; height: cm.ranksH
        screwSize: 13 * cm.s
        Dymo { id: rDymo; x: 26 * cm.s; y: 14 * cm.s; text: "RANKS" }
        Caption {
            x: rDymo.x + rDymo.width + 30 * cm.s; anchors.verticalCenter: rDymo.verticalCenter
            width: parent.width - x - 30 * cm.s; elide: Text.ElideRight
            visible: cm.promoText === ""
            text: "FROM YOUR GAME JOURNAL // DIAL = PROGRESS TO NEXT RANK // AMBER PIP = WHERE YOU ARE // TALL PIPS = ELITE LEVELS"
        }
        Text {
            x: rDymo.x + rDymo.width + 30 * cm.s; anchors.verticalCenter: rDymo.verticalCenter
            visible: cm.promoText !== ""
            text: "PROMOTED: " + cm.promoText
            color: Theme.ok; font.family: Theme.labelFont; font.weight: Font.DemiBold; font.pixelSize: Math.max(10, 17 * cm.s); font.letterSpacing: 4 * cm.s
            SequentialAnimation on opacity { running: cm.promoText !== ""; loops: Animation.Infinite
                NumberAnimation { to: 0.35; duration: 450 } NumberAnimation { to: 1; duration: 450 } }
        }
        Grid {
            id: rankGrid
            x: 14 * cm.s; y: 48 * cm.s
            columns: 4; spacing: 12 * cm.s
            readonly property real tw: (ranksPlate.width - 28 * cm.s - spacing * 3) / 4
            readonly property real th: (ranksPlate.height - 62 * cm.s - spacing) / 2
            Repeater {
                model: cm.ranks
                RankTile { width: rankGrid.tw; height: rankGrid.th; r: modelData; promoted: cm.promoKey !== "" && cm.promoKey === modelData.key }
            }
        }
        Text {
            visible: !bridge.commanderRanksKnown
            anchors.centerIn: parent
            text: "WAITING FOR ELITE // RANKS ARRIVE WHEN YOU LOAD INTO THE GAME"
            color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(12, 24 * cm.s)
        }
    }

    component RankTile: Bezel {
        id: tile
        property var r: ({})
        property bool promoted: false
        pad: 9 * cm.s
        readonly property real iw: width - pad * 2
        readonly property real ih: height - pad * 2
        readonly property real u: ih / 200
        readonly property string st: String(r.state || "unknown")
        readonly property bool dim: st === "new" || st === "unknown"
        readonly property real fs: Math.max(10, 21 * u)
        property real flash: 0
        onPromotedChanged: if (promoted) flashAnim.restart()
        SequentialAnimation {
            id: flashAnim
            NumberAnimation { target: tile; property: "flash"; from: 0; to: 1; duration: 180 }
            NumberAnimation { target: tile; property: "flash"; to: 0; duration: 1400; easing.type: Easing.OutQuad }
        }
        Item {
            anchors.fill: parent
            opacity: tile.dim ? 0.55 : 1
            Text { x: 10 * tile.u; y: 8 * tile.u; text: String(tile.r.label || "-"); color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: tile.fs }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 10 * tile.u; y: 10 * tile.u
                text: "RANK " + Number(tile.r.rank || 0) + " OF " + Number(tile.r.top || 0)
                color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: tile.fs * 0.72
            }
            // dial
            Canvas {
                id: dial
                x: 12 * tile.u; y: 40 * tile.u
                width: Math.min(tile.iw * 0.36, 110 * tile.u); height: width
                readonly property real pct: Number(tile.r.pct || 0)
                readonly property color arc: tile.st === "max" ? Theme.ok : Theme.info
                onPctChanged: requestPaint()
                onArcChanged: requestPaint()
                Connections { target: tile; function onFlashChanged() { dial.requestPaint() } }
                onPaint: {
                    var c = getContext("2d"); c.reset()
                    var cx = width / 2, cy = height / 2, rr = width / 2 - 7 * tile.u
                    c.lineWidth = 9 * tile.u
                    c.strokeStyle = "#163222"
                    c.beginPath(); c.arc(cx, cy, rr, 0, Math.PI * 2); c.stroke()
                    // tick ring
                    c.lineWidth = 1; c.strokeStyle = "#2a5a3a"
                    for (var i = 0; i < 20; i++) {
                        var a = i / 20 * Math.PI * 2
                        c.beginPath(); c.moveTo(cx + Math.cos(a) * (rr - 9 * tile.u), cy + Math.sin(a) * (rr - 9 * tile.u))
                        c.lineTo(cx + Math.cos(a) * (rr - 13 * tile.u), cy + Math.sin(a) * (rr - 13 * tile.u)); c.stroke()
                    }
                    var p = tile.flash > 0 ? Math.max(pct, 100 * tile.flash) : pct
                    if (p > 0) {
                        c.lineWidth = 9 * tile.u
                        c.lineCap = "round"
                        c.strokeStyle = tile.flash > 0.05 ? Qt.tint(dial.arc, Qt.rgba(1, 1, 1, tile.flash * 0.85)) : dial.arc
                        c.beginPath(); c.arc(cx, cy, rr, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.min(1, p / 100)); c.stroke()
                    }
                }
                Glow { target: dial; color: tile.st === "max" ? "#46ff82" : "#ffb84d"; spread: 14 * tile.u; radius: dial.width / 2; intensity: tile.dim ? 0 : (0.25 + tile.flash * 0.6) }
                Text {
                    anchors.centerIn: parent
                    text: tile.st === "max" ? "MAX" : (Number(tile.r.pct || 0) + "%")
                    color: tile.st === "max" ? Theme.ok : Theme.info
                    font.family: Theme.crtFont; font.pixelSize: tile.fs * 1.05
                }
            }
            // rank name + next
            Column {
                x: dial.x + dial.width + 14 * tile.u; y: dial.y + 6 * tile.u
                width: tile.iw - x - 8 * tile.u
                spacing: 4 * tile.u
                Text {
                    width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 2
                    text: String(tile.r.name || "-")
                    color: tile.flash > 0.05 ? Theme.control : (tile.st === "max" ? Theme.ok : Theme.info)
                    font.family: Theme.crtFont; font.pixelSize: tile.fs * 1.15; lineHeight: 0.85
                }
                Text {
                    width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 3
                    text: tile.st === "max" ? "TOP OF THE LADDER"
                        : tile.st === "ready" ? "READY FOR PROMOTION // TAKE A NAVY PROMOTION MISSION"
                        : tile.st === "unknown" ? "WAITING FOR ELITE"
                        : ("NEXT: " + String(tile.r.next || "-") + (tile.st === "new" ? " // NOT STARTED" : ""))
                    color: tile.st === "ready" ? Theme.info : Theme.dimText
                    font.family: Theme.crtFont; font.pixelSize: tile.fs * 0.72; lineHeight: 0.9
                    SequentialAnimation on opacity { running: tile.st === "ready"; loops: Animation.Infinite
                        NumberAnimation { to: 0.45; duration: 900 } NumberAnimation { to: 1; duration: 900 } }
                }
                // superpower reputation (navy tiles)
                Item {
                    visible: tile.r.rep !== null && tile.r.rep !== undefined
                    width: parent.width; height: tile.fs * 0.9
                    Text { id: repLbl; anchors.verticalCenter: parent.verticalCenter; text: "REP " + Math.round(Number(tile.r.rep || 0))
                           color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: tile.fs * 0.7 }
                    Rectangle {
                        x: repLbl.width + 8 * tile.u; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x; height: 6 * tile.u; color: "#0a1a10"; border.color: "#337dff9c"; border.width: 1
                        // -100 .. +100, centre line at 0
                        Rectangle { x: parent.width / 2; width: 1; height: parent.height; color: "#557dff9c" }
                        Rectangle {
                            readonly property real v: Math.max(-100, Math.min(100, Number(tile.r.rep || 0))) / 100
                            x: v >= 0 ? parent.width / 2 : parent.width / 2 * (1 + v); y: 1; height: parent.height - 2
                            width: Math.abs(v) * parent.width / 2
                            color: v >= 0 ? Theme.ok : Theme.bad; opacity: 0.75
                        }
                    }
                }
            }
            // pip ladder
            Item {
                id: ladder
                x: 10 * tile.u; y: tile.ih - 44 * tile.u
                width: tile.iw - 20 * tile.u; height: 34 * tile.u
                readonly property int n: Number(tile.r.top || 0) + 1
                readonly property int ef: Number(tile.r.eliteFrom === undefined ? -1 : tile.r.eliteFrom)
                readonly property real gapW: ef > 0 ? 8 * tile.u : 0
                readonly property real pw: n > 0 ? (width - gapW - (n - 1) * 3 * tile.u) / n : 0
                Repeater {
                    model: ladder.n
                    Rectangle {
                        readonly property bool tall: ladder.ef > 0 && index > ladder.ef
                        readonly property int rk: Number(tile.r.rank || 0)
                        x: index * (ladder.pw + 3 * tile.u) + (ladder.ef > 0 && index > ladder.ef ? ladder.gapW : 0)
                        y: tall ? 0 : 6 * tile.u
                        width: ladder.pw; height: tall ? 16 * tile.u : 10 * tile.u
                        color: index < rk ? Theme.ok : (index === rk ? (tile.st === "max" ? Theme.ok : Theme.info) : "#163222")
                        opacity: index < rk ? 0.85 : 1
                        border.color: "#0a140d"; border.width: 1
                    }
                }
                Text { y: 19 * tile.u; text: String(tile.r.first || ""); color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: tile.fs * 0.55 }
                Text { anchors.right: parent.right; y: 19 * tile.u; text: String(tile.r.last || ""); color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: tile.fs * 0.55 }
            }
        }
    }

    // ================================================================= YOUR SHIP
    Plate {
        id: shipPlate
        x: cm.rightX; y: 0; width: cm.rightW; height: cm.shipH
        screwSize: 13 * cm.s
        Dymo { x: 26 * cm.s; y: 14 * cm.s; text: "YOUR SHIP" }
        Bezel {
            id: sBezel
            x: 16 * cm.s; y: 50 * cm.s
            width: parent.width - 32 * cm.s; height: parent.height - 66 * cm.s
            pad: 12 * cm.s
            readonly property real iw: width - pad * 2
            readonly property real ih: height - pad * 2
            readonly property real fs: Math.max(12, Math.min(26 * cm.s, ih / 11))
            // hologram stand + ship
            Item {
                id: holo
                x: 0; y: 0; width: sBezel.iw * 0.5; height: sBezel.ih
                Canvas {
                    id: stand
                    anchors.fill: parent
                    property real t: 0
                    onTChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        var c = getContext("2d"); c.reset()
                        var cx = width / 2, cy = height * 0.84
                        for (var i = 0; i < 3; i++) {
                            var rx = width * (0.42 - i * 0.11), ry = height * (0.075 - i * 0.02)
                            c.strokeStyle = Qt.rgba(0.49, 1, 0.61, 0.22 + 0.12 * i); c.lineWidth = 1.2
                            c.beginPath(); c.ellipse(cx - rx, cy - ry, rx * 2, ry * 2); c.stroke()
                        }
                        // beam lines up from the base, gently scrolling
                        for (var k = 0; k < 9; k++) {
                            var fx = (k - 4) / 4
                            var bx = cx + fx * width * 0.3
                            var g2 = c.createLinearGradient(bx, cy, bx, height * 0.1)
                            g2.addColorStop(0, Qt.rgba(0.49, 1, 0.61, 0.20))
                            g2.addColorStop(1, Qt.rgba(0.49, 1, 0.61, 0))
                            c.strokeStyle = g2; c.lineWidth = 1
                            c.beginPath(); c.moveTo(bx, cy); c.lineTo(cx + fx * width * 0.38, height * 0.1); c.stroke()
                        }
                        var sy = cy - ((t % 1) * height * 0.7)
                        c.strokeStyle = Qt.rgba(0.49, 1, 0.61, 0.18); c.lineWidth = 2
                        c.beginPath(); c.moveTo(width * 0.14, sy); c.lineTo(width * 0.86, sy); c.stroke()
                    }
                    Timer { interval: 66; repeat: true; running: cm.visible; onTriggered: stand.t = (Date.now() % 4000) / 4000 }
                }
                ShipArt {
                    readonly property var info: cm.app ? cm.app.shipClassInfo(bridge.shipModel) : null
                    x: parent.width * 0.06; y: parent.height * 0.04
                    width: parent.width * 0.88; height: parent.height * 0.80
                    visible: info !== null
                    source: info ? Qt.resolvedUrl("../" + cm.app.shipArtSource(bridge.shipModel)) : ""
                    motion: info ? info.size : ""
                }
                ContactScanner {
                    anchors.fill: parent
                    visible: !(cm.app && cm.app.shipClassInfo(bridge.shipModel))
                    centerAt: Qt.vector2d(0.5, 0.66); ringRadii: Qt.vector2d(0.40, 0.12)
                    fontScale: 0.7
                    blip: String(bridge.shipModel || "-") !== "-"
                    title: String(bridge.shipModel || "-") === "-" ? "NO SHIP DATA" : "NO SIGNATURE MATCH"
                    line2: String(bridge.shipModel || "-") === "-" ? "" : String(bridge.shipModel)
                    line3: String(bridge.shipModel || "-") === "-" ? "" : "CLASS NOT ON FILE"
                }
            }
            Column {
                x: sBezel.iw * 0.53; y: 6 * cm.s
                width: sBezel.iw * 0.45
                spacing: 6 * cm.s
                Text { width: parent.width; elide: Text.ElideRight
                       text: cm.up(String(bridge.shipName || "").trim() !== "" ? bridge.shipName : bridge.shipModel)
                       color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: sBezel.fs * 1.55 }
                Text { width: parent.width; elide: Text.ElideRight
                       text: cm.up(bridge.shipModel) + (String(bridge.shipIdent || "") !== "" ? "  //  ID " + bridge.shipIdent : "")
                       color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: sBezel.fs * 0.8 }
                Item { width: 1; height: 4 * cm.s }
                Repeater {
                    model: [
                        { label: "HULL", value: bridge.hullPercent, txt: bridge.hullPercent >= 0 ? bridge.hullPercent + "%" : "-" },
                        { label: "FUEL", value: bridge.fuelPercent, txt: bridge.fuelPercent >= 0 ? bridge.fuelPercent + "%" : "-" },
                        { label: "CARGO", value: cm.cap > 0 ? Math.round(cm.used / cm.cap * 100) : -1, txt: cm.cap > 0 ? cm.used + " / " + cm.cap + " T" : "-" }
                    ]
                    Column {
                        width: parent.width; spacing: 3 * cm.s
                        Item {
                            width: parent.width; height: sBezel.fs * 0.9
                            Text { text: modelData.label; color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: sBezel.fs * 0.8 }
                            Text { anchors.right: parent.right; text: modelData.txt
                                   color: modelData.label === "HULL" && modelData.value >= 0 && modelData.value < 50 ? Theme.bad
                                        : (modelData.label === "FUEL" && modelData.value >= 0 && modelData.value < 25 ? Theme.info : Theme.ok)
                                   font.family: Theme.crtFont; font.pixelSize: sBezel.fs * 0.8 }
                        }
                        BlockBar {
                            width: parent.width; height: sBezel.fs * 0.75; segments: 16
                            value: Math.max(0, Number(modelData.value)) / 100; known: Number(modelData.value) >= 0
                            color: modelData.label === "HULL" && modelData.value < 50 ? Theme.bad : Theme.ok
                        }
                    }
                }
                Item {
                    width: parent.width; height: sBezel.fs
                    Text { anchors.bottom: parent.bottom; text: "JUMP RANGE"; color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: sBezel.fs * 0.8 }
                    Text { anchors.right: parent.right; anchors.bottom: parent.bottom
                           text: bridge.shipJumpRange > 0 ? bridge.shipJumpRange.toFixed(1) + " LY" : "-"
                           color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: sBezel.fs * 0.8 }
                }
            }
        }
    }

    // ================================================================= CAREER
    Plate {
        id: careerPlate
        x: 0; y: cm.lowY; width: (cm.leftW - cm.g) / 2; height: cm.lowH
        screwSize: 13 * cm.s
        Dymo { id: cDymo; x: 26 * cm.s; y: 14 * cm.s; text: "CAREER" }
        Caption { x: cDymo.x + cDymo.width + 24 * cm.s; anchors.verticalCenter: cDymo.verticalCenter
                  width: parent.width - x - 24 * cm.s; elide: Text.ElideRight; text: "ELITE'S OWN TOTALS // UPDATED AT LOGIN" }
        Bezel {
            id: cBezel
            x: 16 * cm.s; y: 50 * cm.s
            width: parent.width - 32 * cm.s; height: parent.height - 66 * cm.s
            pad: 12 * cm.s
            readonly property real iw: width - pad * 2
            readonly property real ih: height - pad * 2
            readonly property real fs: Math.max(11, Math.min(24 * cm.s, ih / 9.5))
            // two big numbers
            Repeater {
                model: [
                    { label: "CREDITS // LAST KNOWN", value: bridge.commanderCredits },
                    { label: "TOTAL WORTH // AT LOGIN", value: bridge.commanderNetWorth }
                ]
                Item {
                    x: 14 * cm.s + index * (cBezel.iw - 28 * cm.s) / 2; y: 8 * cm.s
                    width: (cBezel.iw - 28 * cm.s) / 2 - 10 * cm.s; height: cBezel.fs * 3.0
                    Text { text: modelData.label; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: cBezel.fs * 0.75 }
                    Text {
                        y: cBezel.fs * 0.95; width: parent.width; height: cBezel.fs * 2.0
                        text: Number(modelData.value) >= 0 ? cm.num(modelData.value) + " CR" : "-"
                        color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: cBezel.fs * 2.0
                        fontSizeMode: Text.HorizontalFit; minimumPixelSize: cBezel.fs * 0.9
                    }
                }
            }
            Grid {
                id: careerGrid
                visible: bridge.commanderStatsKnown
                x: 14 * cm.s; y: cBezel.fs * 3.5
                columns: 4; columnSpacing: 10 * cm.s; rowSpacing: cBezel.fs * 0.35
                readonly property real cw: (cBezel.iw - 28 * cm.s - columnSpacing * 3) / 4
                Repeater {
                    model: bridge.commanderCareer
                    Column {
                        width: careerGrid.cw
                        Text { width: parent.width; elide: Text.ElideRight; text: modelData.label; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: cBezel.fs * 0.8 }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: modelData.value === null || modelData.value === undefined ? "-"
                                : (modelData.unit === "CR" ? cm.compact(modelData.value) + " CR"
                                   : (modelData.unit === "H" ? cm.num(modelData.value) + " H" : cm.num(modelData.value)))
                            color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: cBezel.fs * 1.2
                        }
                    }
                }
            }
            Text {
                visible: !bridge.commanderStatsKnown
                x: 14 * cm.s; y: cBezel.fs * 3.6; width: cBezel.iw - 28 * cm.s; wrapMode: Text.WordWrap
                text: "CAREER TOTALS ARRIVE WHEN YOU LOAD INTO ELITE"
                color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: cBezel.fs * 0.9
            }
            Text {
                x: 14 * cm.s; y: cBezel.ih - height - 8 * cm.s; width: cBezel.iw - 28 * cm.s; elide: Text.ElideRight
                // only when there's room under the totals (small windows hide it instead of overprinting)
                visible: !careerGrid.visible || y > careerGrid.y + careerGrid.height + 4 * cm.s
                text: String(bridge.commanderLine || "")
                color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: cBezel.fs * 0.8
            }
        }
    }

    // ================================================================= THIS SESSION
    Plate {
        id: sessionPlate
        x: careerPlate.width + cm.g; y: cm.lowY; width: (cm.leftW - cm.g) / 2; height: cm.lowH
        screwSize: 13 * cm.s
        Dymo { id: sDymo; x: 26 * cm.s; y: 14 * cm.s; text: "THIS SESSION" }
        Caption { x: sDymo.x + sDymo.width + 24 * cm.s; anchors.verticalCenter: sDymo.verticalCenter
                  width: parent.width - x - 24 * cm.s; elide: Text.ElideRight; text: "COUNTS START WHEN THE BRIDGE STARTS" }
        Bezel {
            id: ssBezel
            x: 16 * cm.s; y: 50 * cm.s
            width: parent.width - 32 * cm.s; height: parent.height - 66 * cm.s
            pad: 12 * cm.s
            readonly property real iw: width - pad * 2
            readonly property real ih: height - pad * 2
            readonly property real fs: Math.max(11, Math.min(24 * cm.s, ih / 7.5))
            Grid {
                id: sessGrid
                x: 14 * cm.s; y: ssBezel.fs * 0.5
                columns: 3; columnSpacing: 12 * cm.s; rowSpacing: ssBezel.fs * 0.6
                readonly property real cw: (ssBezel.iw - 28 * cm.s - columnSpacing * 2) / 3
                Repeater {
                    model: bridge.commanderSessionRows
                    Column {
                        width: sessGrid.cw
                        Text { width: parent.width; elide: Text.ElideRight; text: String(modelData.label).replace("BRIDGE START", "BRIDGE STARTED").replace("BOUNTY EVENTS", "BOUNTIES")
                               color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: ssBezel.fs * 0.8 }
                        Text { width: parent.width; elide: Text.ElideRight; text: String(modelData.value)
                               color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: ssBezel.fs * 1.9 }
                    }
                }
            }
        }
    }

    // ================================================================= ODD STATS
    // Step 27: cargo and loadout moved to the Flight Deck; this corner shows the
    // weird numbers instead. Elite's own records (Statistics, at login) plus a few the
    // Bridge counts this session. Shows what fits, then pages through the rest.
    Plate {
        id: oddPlate
        objectName: "commanderOddStats"
        x: cm.rightX; y: cm.cargoY; width: cm.rightW; height: cm.cargoH
        screwSize: 13 * cm.s
        readonly property var pool: bridge.commanderOddStats || []
        readonly property int per: Math.max(1, Math.floor((oBezel.ih - 16 * cm.s) / oBezel.rowH))
        readonly property int pages: Math.max(1, Math.ceil(pool.length / per))
        property int page: 0
        onPagesChanged: if (page >= pages) page = 0
        readonly property var shown: pool.slice(page * per, page * per + per)
        property int view: 0          // 2.0.2: 0 odd stats, 1 fleet (stored ships)
        Dymo { id: oDymo; x: 26 * cm.s; y: 14 * cm.s; text: oddPlate.view === 1 ? "FLEET" : "ODD STATS" }
        Caption { x: oDymo.x + oDymo.width + 20 * cm.s; anchors.verticalCenter: oDymo.verticalCenter
                  width: oddSel.x - x - 12 * cm.s; elide: Text.ElideRight
                  text: oddPlate.view === 1 ? (cm.fleet.length > 0 ? cm.fleet.length + " STORED" : "")
                        : (oddPlate.pages > 1 ? "PAGE " + (oddPlate.page + 1) + " OF " + oddPlate.pages : "") }
        SelectorRow {
            id: oddSel
            anchors.right: parent.right; anchors.rightMargin: 24 * cm.s; y: 10 * cm.s
            options: ["ODD STATS", "FLEET"]
            buttonWidth: 118 * cm.s; buttonHeight: 32 * cm.s
            currentIndex: oddPlate.view
            onPicked: (i) => oddPlate.view = i
        }
        Timer {
            interval: 9000; repeat: true
            running: oddPlate.visible && oddPlate.view === 0 && oddPlate.pages > 1
            onTriggered: oddFlip.restart()
        }
        SequentialAnimation {
            id: oddFlip
            NumberAnimation { target: oList; property: "opacity"; to: 0; duration: 220 }
            ScriptAction { script: oddPlate.page = (oddPlate.page + 1) % oddPlate.pages }
            NumberAnimation { target: oList; property: "opacity"; to: 1; duration: 260 }
        }
        Bezel {
            id: oBezel
            x: 16 * cm.s; y: 50 * cm.s
            width: parent.width - 32 * cm.s; height: parent.height - 66 * cm.s
            pad: 12 * cm.s
            readonly property real iw: width - pad * 2
            readonly property real ih: height - pad * 2
            readonly property real fs: Math.max(11, 20 * cm.s)
            readonly property real rowH: fs * 2.55
            Column {
                id: oList
                visible: oddPlate.view === 0
                x: 14 * cm.s; y: 8 * cm.s; width: oBezel.iw - 28 * cm.s
                Repeater {
                    model: oddPlate.shown
                    Item {
                        required property var modelData
                        width: oList.width; height: oBezel.rowH
                        Text { y: 2 * cm.s; width: parent.width * 0.62; elide: Text.ElideRight
                               text: String(modelData.label) + (modelData.session ? "  // THIS SESSION" : "")
                               color: modelData.session ? Theme.info : Theme.dimText; font.family: Theme.crtFont; font.pixelSize: oBezel.fs * 0.78 }
                        Text { anchors.right: parent.right; y: 0; width: parent.width * 0.5; horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft
                               text: String(modelData.value); color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: oBezel.fs * 1.35 }
                        Text { y: oBezel.fs * 1.15; width: parent.width; elide: Text.ElideRight
                               text: String(modelData.note || ""); color: Theme.phosphor; opacity: 0.6; font.family: Theme.crtFont; font.pixelSize: oBezel.fs * 0.75 }
                        Rectangle { anchors.bottom: parent.bottom; anchors.bottomMargin: 4 * cm.s; width: parent.width; height: 1; color: "#227dff9c" }
                    }
                }
            }
            Text { visible: oddPlate.view === 0 && oddPlate.pool.length === 0; anchors.centerIn: parent; width: oBezel.iw - 40 * cm.s
                   horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                   text: "THE ODD NUMBERS ARRIVE WHEN YOU LOAD INTO ELITE"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: oBezel.fs }

            // ---- FLEET: every stored ship, nearest first. Click a row, then PLOT: SHIP.
            Item {
                id: fleetView
                visible: oddPlate.view === 1
                x: 14 * cm.s; y: 8 * cm.s; width: oBezel.iw - 28 * cm.s; height: oBezel.ih - 16 * cm.s
                readonly property real rowH: oBezel.fs * 2.55
                PhosphorList {
                    id: fleetList
                    width: parent.width; height: parent.height - fleetFoot.height - 8 * cm.s
                    fontSize: oBezel.fs * 0.8
                    model: cm.fleet
                    delegate: Item {
                        id: frow
                        required property var modelData
                        required property int index
                        width: fleetList.list.width; height: fleetView.rowH
                        readonly property bool picked: Number(modelData.shipId) === cm.fleetSel
                        readonly property bool here: cm.hereSys(modelData.system)
                        readonly property bool transit: String(modelData.status) === "IN TRANSIT"
                        Rectangle { anchors.fill: parent; anchors.bottomMargin: 3 * cm.s; color: Theme.phosphor
                                    opacity: frow.picked ? 0.16 : (fHover.containsMouse ? 0.07 : 0) }
                        Text { x: 4 * cm.s; y: 2 * cm.s; text: frow.picked ? ">" : ""; color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: oBezel.fs }
                        Text { x: 22 * cm.s; y: 2 * cm.s; width: parent.width * 0.6 - x; elide: Text.ElideRight
                               text: cm.up(String(modelData.name || "") !== "" ? modelData.name : modelData.typeName)
                               color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: oBezel.fs }
                        Text { anchors.right: parent.right; anchors.rightMargin: 6 * cm.s; y: 2 * cm.s; horizontalAlignment: Text.AlignRight
                               width: parent.width * 0.4
                               text: frow.transit ? "ARRIVES IN " + cm.mmss(modelData.arriveIn)
                                     : (frow.here ? "IN THIS SYSTEM" : (Number(modelData.ly) >= 0 ? Number(modelData.ly).toFixed(1) + " LY" : "? LY"))
                               color: frow.transit ? Theme.info : (frow.here ? Theme.ok : Theme.phosphor)
                               font.family: Theme.crtFont; font.pixelSize: oBezel.fs * 0.85 }
                        Text { x: 22 * cm.s; y: oBezel.fs * 1.15; width: parent.width - x - 6 * cm.s; elide: Text.ElideRight
                               text: (String(modelData.name || "") !== "" ? cm.up(modelData.typeName) + " // " : "")
                                     + cm.up(modelData.station) + " // " + cm.up(modelData.system)
                                     + (Number(modelData.value) > 0 ? " // " + cm.compact(modelData.value) + " CR" : "")
                                     + (modelData.hot ? " // HOT" : "")
                               color: modelData.hot ? Theme.info : Theme.phosphor; opacity: 0.7
                               font.family: Theme.crtFont; font.pixelSize: oBezel.fs * 0.72 }
                        Rectangle { anchors.bottom: parent.bottom; anchors.bottomMargin: 2 * cm.s; width: parent.width; height: 1; color: "#227dff9c" }
                        MouseArea { id: fHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: cm.fleetSel = frow.picked ? -1 : Number(frow.modelData.shipId) }
                    }
                }
                Text { visible: cm.fleet.length === 0; anchors.centerIn: fleetList; width: parent.width - 40 * cm.s
                       horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                       text: String(bridge.commanderFleetStatus); color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: oBezel.fs }
                Text { id: fleetFoot; anchors.bottom: parent.bottom; width: parent.width; elide: Text.ElideRight
                       visible: cm.fleet.length > 0
                       text: String(bridge.commanderFleetStatus) + " // PICK A SHIP, THEN PLOT: SHIP"
                       color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: oBezel.fs * 0.68 }
            }
        }
    }

    // ================================================================= ACTION DECK
    component Groove: Item {
        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 4 * cm.s; height: parent.height; radius: 2 * cm.s; color: "#0b0b0a"; border.color: "#3e3b32"; border.width: 1 }
    }
    Plate {
        id: deck
        dark: true
        screwSize: 13 * cm.s
        x: 0; y: cm.deckY; width: cm.width; height: cm.deckH
        readonly property real keyH: Math.min(height - 66 * cm.s, 150 * cm.s)
        readonly property real keyY: 52 * cm.s + (height - 66 * cm.s - keyH) / 2
        readonly property real cancelW: 270 * cm.s
        readonly property real divW: 40 * cm.s
        readonly property real keyGap: 14 * cm.s
        readonly property real keyW: (width - 26 * cm.s - cancelW - 40 * cm.s - 44 * cm.s - divW * 2 - keyGap * 8) / 7
        Dymo { x: 26 * cm.s; y: 14 * cm.s; text: "ACTIONS // COMMANDER" }
        Row {
            id: dRow
            x: 26 * cm.s; y: deck.keyY
            spacing: deck.keyGap
            DeckKey {
                id: refreshKey
                width: deck.keyW; height: deck.keyH
                title: "REFRESH"; legend: "RE-READ JOURNAL"
                keyState: "ready"
                tooltip: "RE-READ YOUR RECORD"; tooltipDetail: "PICKS UP THE LATEST JOURNAL DETAILS"
                onActivated: { bridge.requestCommand("cmdr_refresh"); cm.notice("REFRESHING", "RE-READING YOUR RECORD", "info") }
            }
            Groove { width: deck.divW; height: deck.keyH }
            DeckKey {
                id: plotShip
                width: deck.keyW * 1.1; height: deck.keyH
                title: "PLOT: SHIP"
                readonly property string sys: cm.fleetPick ? String(cm.fleetPick.system || "") : ""
                legend: cm.fleetPick ? cm.up(cm.fleetPick.system) : "PICK A SHIP"
                keyState: sys === "" ? "unavailable" : (cm.bindsReady ? "ready" : "unavailable")
                unavailableReason: sys === "" ? "OPEN FLEET AND PICK A STORED SHIP FIRST" : cm.bindsReason
                tooltip: sys !== "" ? "PLOT A ROUTE TO " + cm.up(sys) : "PLOT A ROUTE TO A STORED SHIP"
                tooltipDetail: "THE ROUTE SHOWS UP ON NAVIGATION"
                onActivated: {
                    if (cm.hereSys(sys)) cm.notice("ALREADY HERE", "YOUR " + cm.up(cm.fleetPick.name || cm.fleetPick.typeName) + " IS IN THIS SYSTEM", "info")
                    bridge.plotRoute(sys)
                }
                onDenied: (r) => { if (sys === "") oddPlate.view = 1; cm.denied("PLOT: SHIP UNAVAILABLE", r) }
            }
            Groove { width: deck.divW; height: deck.keyH }
            DeckKey {
                id: dockKey
                width: deck.keyW; height: deck.keyH
                title: "DOCK"
                readonly property bool run: cm.bstate === "DOCKING PROTOCOL" || cm.bstate === "REQUEST DOCKING"
                legend: run ? bridge.bridgeMessage : "REQUEST DOCKING"
                keyState: run ? "running" : (cm.bindsReady ? "ready" : "unavailable")
                unavailableReason: cm.bindsReason
                tooltip: "REQUEST DOCKING"; tooltipDetail: "DOCKING PROTOCOL"
                onActivated: bridge.requestCommand("dock")
                onDenied: (r) => cm.denied("DOCK UNAVAILABLE", r)
            }
            DeckKey {
                id: launchKey
                width: deck.keyW; height: deck.keyH
                title: "LAUNCH"
                readonly property bool run: cm.bstate === "AUTO LAUNCH"
                legend: run ? bridge.bridgeMessage : "TAKE OFF"
                keyState: run ? "running" : (cm.bindsReady ? "ready" : "unavailable")
                unavailableReason: cm.bindsReason
                tooltip: "LAUNCH FROM THE PAD"; tooltipDetail: "AUTO LAUNCH SEQUENCE"
                onActivated: bridge.requestCommand("launch")
                onDenied: (r) => cm.denied("LAUNCH UNAVAILABLE", r)
            }
        }
        Caption { x: dRow.x + dockKey.x + (launchKey.x + launchKey.width - dockKey.x) / 2 - width / 2; y: deck.keyY - height - 6 * cm.s; text: "FLIGHT" }
        Caption { x: dRow.x + plotShip.x + plotShip.width / 2 - width / 2; y: deck.keyY - height - 6 * cm.s; text: "FLEET" }
        Item {
            x: deck.width - deck.cancelW - 40 * cm.s; y: deck.keyY; width: deck.cancelW; height: deck.keyH
            Glow { target: ck; color: "#ff5040"; spread: 34 * cm.s; radius: 8 * cm.s; intensity: cm.inControl ? 0.8 : 0 }
            DeckKey {
                id: ck
                anchors.fill: parent
                title: "CANCEL"; legend: "STOP ALL AUTOMATION"
                cap: "red"; hazard: true
                tooltip: "STOP ALL AUTOMATION"; tooltipDetail: "BRIDGE RELEASES YOUR CONTROLS"
                onActivated: bridge.requestCommand("cancel")
            }
        }
    }
}
