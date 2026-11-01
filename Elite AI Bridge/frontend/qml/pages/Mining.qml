// MINING (page 13). 2026-10-25, first version, built from real mining runs.
// RING MINING: the last prospector results with a MINE / MAYBE / SKIP call (value per ton of rock
// from the best nearby sell price), this run's haul, hold + limpets + kit check, where to sell what's
// in the hold, and the rings you know about with any hotspots you mapped.
// SURFACE: room for SRV / planetary mining later.
import QtQuick
import "../skin"

Item {
    id: mn
    property var app
    property bool demo: false
    signal denied(string title, string reason)
    signal notice(string title, string detail, string level)
    // ? tour highlight targets (help page 13)
    readonly property Item rockTarget: prospPlate
    readonly property Item tilesTarget: tileBox
    readonly property Item haulTarget: runPlate
    readonly property Item sellTarget: sellPlate
    readonly property Item ringsTarget: ringPlate
    readonly property Item deckTarget: deck
    readonly property Item rhinoTarget: rhinoPlate
    // the tour switches to the view its step points at (RHINO is on the second view)
    onTourStepChanged: { if (tourStep >= 0 && tourStep <= 4) view = 0; else if (tourStep === 5) view = 1 }

    readonly property real s: Theme.s
    readonly property real g: Math.max(8, 14 * s)
    property int view: 0                    // 0 ring mining, 1 surface

    function up(x) { x = String(x === undefined || x === null ? "-" : x); return x === "" ? "-" : x.toUpperCase() }
    function num(v) { return Math.round(Number(v) || 0).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",") }
    function compact(v) {
        v = Number(v) || 0
        var a = Math.abs(v)
        if (a >= 1e9) return (v / 1e9).toFixed(2) + " B"
        if (a >= 1e6) return (v / 1e6).toFixed(2) + " M"
        if (a >= 1e4) return Math.round(v / 1e3) + " K"
        return num(v)
    }
    function ago(sec) { sec = Number(sec) || 0; return sec < 60 ? "JUST NOW" : (sec < 3600 ? Math.floor(sec / 60) + " MIN AGO" : Math.floor(sec / 3600) + " HR AGO") }
    function verdictColor(v) { return v === "MINE" ? Theme.ok : (v === "CORE" ? Theme.t("#fff27a") : (v === "MAYBE" ? Theme.info : Theme.dimText)) }

    // ---------- data (swap only when the content changes; the bridge resends every 250 ms)
    readonly property var live: bridge.mining || ({})
    property var m: ({})
    property string mKey: ""
    onLiveChanged: { var k = JSON.stringify(live); if (k !== mKey) { mKey = k; m = live } }
    // ---------- ? tour examples: while a tour step points at an empty panel, that panel shows a
    // dimmed sample under an amber EXAMPLE stamp. Gone on the next step, on close, or once real
    // data arrives. Made-up names only, never the player's.
    readonly property int tourStep: bridge.pageHelpActive && Number(bridge.pageHelpPage) === 13 ? Number(bridge.pageHelpStep) : -1
    readonly property bool exRocks: (tourStep === 0 || tourStep === 1) && (m.rocks || []).length === 0
    readonly property bool exHaul: tourStep === 2 && (m.haul || []).length === 0
    readonly property bool exSell: tourStep === 3 && (m.sell || []).length === 0
    readonly property bool exRings: tourStep === 4 && (m.rings || []).length === 0
    readonly property var sample: ({
        rocks: [
            { seq: -1, age: 20, verdict: "MINE", score: 61000, content: "HIGH", remaining: 100, motherlode: "", wanted: false,
              materials: [{ name: "Platinum", pct: 31.4, price: 220000 }, { name: "Bauxite", pct: 18.2, price: 4100 }, { name: "Silver", pct: 9.6, price: 39000 }] },
            { seq: -2, age: 140, verdict: "CORE", score: 0, content: "HIGH", remaining: 100, motherlode: "Painite", wanted: false,
              materials: [{ name: "Bertrandite", pct: 12.0, price: 14000 }] },
            { seq: -3, age: 260, verdict: "MAYBE", score: 9800, content: "MEDIUM", remaining: 100, motherlode: "", wanted: false,
              materials: [{ name: "Gold", pct: 14.1, price: 41000 }, { name: "Indite", pct: 11.0, price: 6200 }] },
            { seq: -4, age: 380, verdict: "SKIP", score: 900, content: "LOW", remaining: 100, motherlode: "", wanted: false,
              materials: [{ name: "Bauxite", pct: 22.5, price: 4100 }] }
        ],
        haul: [{ name: "Platinum", tons: 46, value: 10120000 }, { name: "Silver", tons: 8, value: 312000 }],
        haulTons: 54, haulValue: 10432000, perHour: 21000000,
        sell: [{ name: "Platinum", tons: 46, price: 224000, station: "Example Station", system: "Example System", ly: 18.4, pad: "L" },
               { name: "Silver", tons: 8, price: 41000, station: "Sample Port", system: "Sample System", ly: 9.2, pad: "M" }],
        rings: [{ ring: "Example System 3 A Ring", reserve: "PRISTINE", cls: "METAL RICH", ly: 12.6, here: false, mapped: true,
                  hotspots: "2 PLATINUM  1 PAINITE", wanted: false, system: "Example System", ls: 1840 },
                { ring: "Sample System 1 B Ring", reserve: "MAJOR", cls: "ICY", ly: 21.0, here: false, mapped: false,
                  hotspots: "", wanted: false, system: "Sample System", ls: 640 }]
    })
    readonly property var rocks: exRocks ? sample.rocks : (m.rocks || [])
    readonly property var haulData: exHaul ? sample.haul : (m.haul || [])
    readonly property real haulTons: exHaul ? sample.haulTons : Number(m.haulTons || 0)
    readonly property real haulValue: exHaul ? sample.haulValue : Number(m.haulValue || 0)
    readonly property real perHour: exHaul ? sample.perHour : Number(m.perHour || 0)
    readonly property var sellData: exSell ? sample.sell : (m.sell || [])
    readonly property var ringData: exRings ? sample.rings : (m.rings || [])
    // amber stamp over a panel showing example data (amber, not red: red means danger)
    component ExampleStamp: Item {
        id: stamp
        property string note: ""
        anchors.fill: parent
        z: 50
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.32) }
        Column {
            anchors.centerIn: parent
            spacing: 20 * mn.s
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: exT.implicitWidth + 44 * mn.s; height: exT.implicitHeight + 14 * mn.s
                rotation: -6; color: Qt.rgba(Theme.info.r, Theme.info.g, Theme.info.b, 0.12)
                border.color: Theme.info; border.width: 3 * mn.s; radius: 4 * mn.s
                Text { id: exT; anchors.centerIn: parent; text: "EXAMPLE"; color: Theme.info; font.family: Theme.crtFont
                       font.pixelSize: Math.max(22, 64 * mn.s); font.letterSpacing: 10 * mn.s; font.bold: true }
            }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: stamp.note; color: Theme.info
                   font.family: Theme.crtFont; font.pixelSize: Math.max(10, 18 * mn.s); font.letterSpacing: 2 * mn.s }
        }
    }
    property int pick: -1               // a tapped ROCKS CHECKED tile; -1 = the latest rock
    readonly property var rock: rocks.length > 0 ? rocks[Math.max(0, Math.min(pick, rocks.length - 1))] : null
    // ROCKS CHECKED tiles: best first (CORE, then MINE by value, MAYBE, unknown, SKIP), newest first
    // within each group. Each entry keeps its index in rocks so a tap can show it.
    readonly property var rankedRocks: {
        var order = { CORE: 0, MINE: 1, MAYBE: 2, "?": 3, SKIP: 4 }
        var out = []
        for (var i = 0; i < rocks.length; i++)
            out.push({ i: i, r: rocks[i] })
        out.sort(function (a, b) {
            var oa = order[a.r.verdict] === undefined ? 3 : order[a.r.verdict]
            var ob = order[b.r.verdict] === undefined ? 3 : order[b.r.verdict]
            if (oa !== ob) return oa - ob
            if (oa <= 1 && Number(b.r.score) !== Number(a.r.score)) return Number(b.r.score) - Number(a.r.score)
            return a.i - b.i
        })
        return out
    }
    // One tile per material (motherlodes by their core material): the best rock of that material
    // gives the tile its colour and is what a tap shows; count = rocks of it this run.
    // Order follows rankedRocks, so the best materials come first.
    readonly property var materialTiles: {
        var groups = {}, out = []
        for (var k = 0; k < rankedRocks.length; k++) {
            var e = rankedRocks[k], r = e.r
            var name = r.motherlode ? String(r.motherlode) : (r.materials.length ? String(r.materials[0].name) : "ROCK")
            var key = (r.motherlode ? "ML:" : "") + name.toUpperCase()
            var g = groups[key]
            if (!g) {
                g = groups[key] = { key: key, name: name, best: e.i, r: r, count: 0, idx: [] }
                out.push(g)
            }
            g.count += 1
            g.idx.push(e.i)
        }
        return out
    }
    readonly property int shownIndex: pick < 0 ? 0 : pick

    // LOOKING FOR (up to 3 commodities). Kept locally so a tap shows at once; saved as a setting.
    property var wantedLocal: null
    readonly property var wanted: wantedLocal !== null ? wantedLocal : (m.wanted || [])
    property bool pickerOpen: false
    // COLLECTOR setup (asked once): which fire group and trigger launch collectors
    property bool collectorSetupOpen: false
    property string csGroup: "A"
    property string csFire: "SECONDARY"
    function openCollectorSetup() {
        csGroup = String(m.collectorGroup || "A"); csFire = String(m.collectorFire || "SECONDARY")
        collectorSetupOpen = true
    }
    function isWanted(name) {
        var k = String(name).toUpperCase()
        for (var i = 0; i < wanted.length; i++) if (String(wanted[i]).toUpperCase() === k) return true
        return false
    }
    function toggleWanted(name) {
        var list = wanted.slice(), k = String(name).toUpperCase(), out = [], removed = false
        for (var i = 0; i < list.length; i++) {
            if (String(list[i]).toUpperCase() === k) removed = true
            else out.push(list[i])
        }
        if (!removed) {
            if (out.length >= 3) { notice("LOOKING FOR IS FULL", "TAKE ONE OFF FIRST (3 AT MOST)", "info"); return }
            out.push(name)
        }
        wantedLocal = out
        bridge.setSetupValue("mining_wanted", out.join(","))
    }
    readonly property var commonMaterials: ["Platinum", "Painite", "Osmium", "Palladium", "Gold", "Silver", "Low Temperature Diamonds",
        "Void Opals", "Monazite", "Musgravite", "Grandidierite", "Alexandrite", "Benitoite", "Serendibite", "Rhodplumsite",
        "Bromellite", "Tritium", "Bauxite", "Bertrandite", "Coltan", "Gallite", "Indite", "Lepidolite", "Uraninite",
        "Praseodymium", "Samarium", "Cobalt", "Lithium Hydroxide", "Methane Clathrate", "Methanol Monohydrate Crystals",
        "Hydrogen Peroxide", "Liquid oxygen", "Water", "Rutile", "Cryolite", "Goslarite", "Jadeite", "Taaffeite",
        "Haematite", "Moissanite", "Pyrophyllite", "Lanthanum", "Thorium", "Thallium", "Bismuth", "Beryllium"]
    readonly property var pickList: {
        var seen = {}, out = []
        function add(n) { var k = String(n).toUpperCase(); if (!seen[k] && n) { seen[k] = true; out.push(String(n)) } }
        for (var i = 0; i < wanted.length; i++) add(wanted[i])
        var real = m.rocks || []
        for (var r = 0; r < real.length; r++) for (var j = 0; j < real[r].materials.length; j++) add(real[r].materials[j].name)
        var rest = commonMaterials.slice().sort()
        for (var c = 0; c < rest.length; c++) add(rest[c])
        return out
    }
    readonly property int latestSeq: rocks.length > 0 ? Number(rocks[0].seq || 0) : 0
    onLatestSeqChanged: pick = -1
    onExRocksChanged: pick = -1

    readonly property string bstate: String(bridge.bridgeState || "").toUpperCase()
    readonly property bool inControl: bridge.controlOwner !== "NONE" && bridge.controlOwner !== ""
    readonly property bool bindsReady: bridge.eliteControlsReady
    readonly property string bindsReason: String(bridge.eliteControlReason || "") !== "" ? String(bridge.eliteControlReason).toUpperCase() : "ELITE KEY BINDS NOT FOUND // SEE SETUP > CONTROLS"

    // ---------- layout
    readonly property real deckH: height * 0.175
    readonly property real deckY: height - deckH
    readonly property real bodyH: deckY - g
    readonly property real leftW: width * 0.585
    readonly property real rightX: leftW + g
    readonly property real rightW: width - rightX
    readonly property real prospH: bodyH * 0.585
    readonly property real runH: bodyH * 0.34
    readonly property real holdH: bodyH * 0.29

    component Caption: Text {
        color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: Math.max(8, 13 * mn.s); font.letterSpacing: 3 * mn.s
    }
    component Crt: Text { color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: Math.max(11, 22 * mn.s) }

    // ================================================================= RING MINING
    Item {
        id: spaceView
        visible: mn.view === 0
        anchors.fill: parent

        // ---------------------------------------------------------- PROSPECTOR
        Plate {
            id: prospPlate
            x: 0; y: 0; width: mn.leftW; height: mn.prospH
            screwSize: 13 * mn.s
            Dymo { id: pDymo; x: 26 * mn.s; y: 14 * mn.s; text: "LAST ROCK" }
            Caption { x: pDymo.x + pDymo.width + 20 * mn.s; anchors.verticalCenter: pDymo.verticalCenter
                      width: parent.width - x - 26 * mn.s; elide: Text.ElideRight
                      text: !mn.rock ? "FIRE A PROSPECTOR AT A ROCK"
                            : (mn.pick > 0 ? "AN EARLIER ROCK, SCANNED " + mn.ago(mn.rock.age) + "  //  TAP IT AGAIN FOR THE LATEST"
                                           : "SCANNED " + mn.ago(mn.rock.age) + "  //  FROM YOUR LAST PROSPECTOR") }
            Bezel {
                id: pBezel
                x: 16 * mn.s; y: 50 * mn.s; width: parent.width - 32 * mn.s; height: parent.height - 66 * mn.s
                pad: 12 * mn.s
                readonly property real fs: Math.max(11, 22 * mn.s)
                readonly property real iw: width - pad * 2
                readonly property real ih: height - pad * 2

                // latest rock
                Item {
                    id: latest
                    visible: mn.rock !== null
                    x: 18 * mn.s; y: 12 * mn.s; width: pBezel.iw * 0.56 - 24 * mn.s; height: pBezel.ih - 24 * mn.s
                    Crt { id: vText; text: mn.rock ? (mn.rock.verdict === "?" ? "CHECKING" : mn.rock.verdict) : ""
                          color: mn.rock ? mn.verdictColor(mn.rock.verdict) : Theme.phosphor
                          font.pixelSize: Math.max(30, 96 * mn.s); font.letterSpacing: 6 * mn.s }
                    Crt { anchors.left: vText.right; anchors.leftMargin: 22 * mn.s; anchors.top: vText.top; anchors.topMargin: 16 * mn.s
                          width: parent.width - x; elide: Text.ElideRight
                          text: !mn.rock ? "" : (mn.rock.verdict === "CORE" ? "MOTHERLODE: " + mn.up(mn.rock.motherlode)
                                : (mn.rock.score > 0 ? "WORTH ABOUT " + mn.compact(mn.rock.score) + " PER TON YOU MINE" : "CHECKING PRICES"))
                          color: Theme.dimText; font.pixelSize: pBezel.fs * 0.95 }
                    Crt { anchors.left: vText.right; anchors.leftMargin: 22 * mn.s; anchors.bottom: vText.bottom; anchors.bottomMargin: 18 * mn.s
                          text: !mn.rock ? "" : mn.rock.content + " CONTENT  //  "
                                + (mn.rock.verdict === "CORE" ? "CRACK IT" : "LASER ANYWHERE ON IT")
                                + (Number(mn.rock.remaining) < 99.5 ? "  //  ALREADY MINED, " + Math.round(mn.rock.remaining) + "% LEFT" : "")
                          color: Theme.phosphor; font.pixelSize: pBezel.fs * 0.95 }
                    Asteroid {
                        id: rockArt
                        readonly property real topY: vText.y + vText.height + 4 * mn.s
                        width: Math.min(parent.height - topY, parent.width * 0.34); height: width
                        anchors.right: parent.right; y: topY + (parent.height - topY - height) / 2
                        verdict: mn.rock ? (mn.rock.verdict === "?" ? "" : mn.rock.verdict) : ""
                        checking: mn.rock !== null && mn.rock.verdict === "?"
                        seq: mn.rock ? Number(mn.rock.seq || 0) : 0
                        running: mn.visible && mn.view === 0
                    }
                    Column {
                        y: vText.y + vText.height + 10 * mn.s; width: parent.width - rockArt.width * 1.12 - 18 * mn.s
                        spacing: 8 * mn.s
                        Repeater {
                            model: mn.rock ? mn.rock.materials : []
                            Item {
                                required property var modelData
                                width: parent.width; height: pBezel.fs * 1.55
                                Crt { width: parent.width * 0.36; elide: Text.ElideRight; text: mn.up(modelData.name)
                                      anchors.verticalCenter: parent.verticalCenter; color: Number(modelData.price) >= 30000 ? Theme.ok : Theme.phosphor }
                                BlockBar { x: parent.width * 0.37; width: parent.width * 0.33; height: pBezel.fs * 0.55; anchors.verticalCenter: parent.verticalCenter
                                           segments: 20; value: Math.min(1, Number(modelData.pct) / 60)
                                           color: Number(modelData.price) >= 30000 ? Theme.ok : Theme.info }
                                Crt { x: parent.width * 0.72; anchors.verticalCenter: parent.verticalCenter; text: Number(modelData.pct).toFixed(1) + "%" }
                                Crt { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                      text: Number(modelData.price) > 0 ? mn.compact(modelData.price) : "?"; color: Theme.dimText }
                            }
                        }
                    }
                }
                ExampleStamp { visible: mn.exRocks; note: "YOURS SHOWS HERE AFTER YOUR FIRST PROSPECTOR" }
                // 2026-10-28: the asteroid is always there; with no rock yet it idles in scanner green
                Asteroid {
                    visible: mn.rock === null
                    width: Math.min(pBezel.ih - 70 * mn.s, pBezel.iw * 0.34); height: width
                    x: pBezel.iw * 0.04; y: (pBezel.ih - 50 * mn.s - height) / 2
                    verdict: ""
                    running: visible && mn.visible && mn.view === 0
                }
                Crt { visible: mn.rock === null; x: pBezel.iw * 0.42; width: pBezel.iw * 0.52
                      y: (pBezel.ih - 50 * mn.s - height) / 2
                      horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; color: Theme.dimText; font.pixelSize: pBezel.fs * 1.1
                      text: "NO ROCKS PROSPECTED YET // FIRE A PROSPECTOR LIMPET AT A ROCK AND THE VERDICT SHOWS UP HERE" }

                // LOOKING FOR chips (bottom left)
                Row {
                    id: wantRow
                    x: 18 * mn.s; anchors.bottom: parent.bottom; anchors.bottomMargin: 10 * mn.s
                    spacing: 10 * mn.s
                    Crt { anchors.verticalCenter: parent.verticalCenter; text: "LOOKING FOR"; color: Theme.dimText
                          font.pixelSize: pBezel.fs * 0.8; font.letterSpacing: 2 * mn.s }
                    Repeater {
                        model: mn.wanted
                        Rectangle {
                            required property var modelData
                            height: pBezel.fs * 1.5; width: wl.implicitWidth + 30 * mn.s; radius: 3 * mn.s
                            color: Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.14); border.color: Theme.ok; border.width: 1
                            Crt { id: wl; anchors.centerIn: parent; text: mn.up(parent.modelData) + "  x"; color: Theme.ok; font.pixelSize: pBezel.fs * 0.85 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: mn.toggleWanted(parent.modelData) }
                        }
                    }
                    Rectangle {
                        height: pBezel.fs * 1.5; width: al.implicitWidth + 30 * mn.s; radius: 3 * mn.s
                        visible: mn.wanted.length < 3
                        color: "transparent"; border.color: Theme.dimText; border.width: 1
                        Crt { id: al; anchors.centerIn: parent; text: mn.wanted.length ? "+ ADD" : "+ PICK A MATERIAL"; color: Theme.dimText; font.pixelSize: pBezel.fs * 0.85 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: mn.pickerOpen = true }
                    }
                }

                // ROCKS CHECKED: one tile per prospected rock, newest first, coloured by verdict.
                // Tap a tile to show that rock on the left; tap it again for the latest.
                Rectangle { visible: mn.rocks.length > 0; x: pBezel.iw * 0.56; y: 14 * mn.s; width: 1; height: pBezel.ih - 28 * mn.s; color: Theme.t("#337dff9c") }
                Item {
                    id: tileBox
                    visible: mn.rocks.length > 0
                    x: pBezel.iw * 0.56 + 18 * mn.s; y: 12 * mn.s; width: pBezel.iw * 0.44 - 40 * mn.s; height: pBezel.ih - 24 * mn.s
                    readonly property int checked: Math.max(Number(mn.m.checked || 0), mn.rocks.length)
                    readonly property int worth: mn.rocks.filter(function (r) { return r.verdict === "MINE" || r.verdict === "CORE" }).length
                    readonly property int hidden: Math.max(0, mn.materialTiles.length - 9)
                    Crt { id: tHead; width: parent.width; elide: Text.ElideRight
                          text: "ROCKS CHECKED  " + tileBox.checked + "   //   " + (tileBox.worth > 0 ? tileBox.worth + " WORTH MINING" : "NONE WORTH MINING YET")
                          color: tileBox.worth > 0 ? Theme.ok : Theme.dimText; font.pixelSize: pBezel.fs * 0.95; font.letterSpacing: 2 * mn.s }
                    Grid {
                        id: tiles
                        y: tHead.height + 14 * mn.s
                        columns: 3; columnSpacing: 12 * mn.s; rowSpacing: 12 * mn.s
                        readonly property real tw: (tileBox.width - columnSpacing * 2) / 3
                        readonly property real th: Math.min(tw * 0.5, (tileBox.height - y - rowSpacing * 2 - pBezel.fs * 1.3) / 3)
                        Repeater {
                            model: mn.materialTiles.slice(0, 9)
                            Rectangle {
                                id: tile
                                required property var modelData
                                readonly property var rk: modelData.r                   // best rock of this material
                                readonly property int index: modelData.best             // its position in mn.rocks (0 = newest)
                                readonly property bool hasNewest: modelData.idx.indexOf(0) >= 0
                                readonly property string v: rk.verdict
                                readonly property color vc: v === "?" ? Theme.phosphor : (v === "SKIP" ? Theme.dimText : mn.verdictColor(v))
                                readonly property bool shown: modelData.idx.indexOf(mn.shownIndex) >= 0
                                width: tiles.tw; height: tiles.th; radius: 4 * mn.s
                                color: Qt.rgba(vc.r, vc.g, vc.b, shown ? 0.24 : (v === "SKIP" ? 0.04 : (v === "CORE" ? 0.20 : 0.10)))
                                border.color: vc; border.width: shown ? 3 * mn.s : (v === "CORE" ? 2 * mn.s : 1)
                                opacity: v === "SKIP" && !shown ? 0.6 : 1
                                Crt { anchors.centerIn: parent; width: parent.width - 16 * mn.s; horizontalAlignment: Text.AlignHCenter
                                      fontSizeMode: Text.HorizontalFit; minimumPixelSize: Math.max(9, pBezel.fs * 0.7)
                                      color: tile.vc; font.pixelSize: pBezel.fs * 1.15
                                      text: (tile.rk.motherlode ? "CORE " : "") + mn.up(tile.modelData.name)
                                            + (tile.modelData.count > 1 ? "  x" + tile.modelData.count : "") }
                                Crt { anchors.left: parent.left; anchors.leftMargin: 6 * mn.s; anchors.top: parent.top; anchors.topMargin: 2 * mn.s
                                      visible: !!tile.rk.wanted; text: "ON YOUR LIST"; color: tile.vc; opacity: 0.8; font.pixelSize: pBezel.fs * 0.6 }
                                Crt { anchors.right: parent.right; anchors.rightMargin: 6 * mn.s; anchors.top: parent.top; anchors.topMargin: 2 * mn.s
                                      visible: tile.hasNewest; text: "NEW"; color: tile.vc; opacity: 0.7; font.pixelSize: pBezel.fs * 0.6 }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: mn.pick = (mn.shownIndex === tile.index) ? -1 : (tile.index === 0 ? -1 : tile.index) }
                            }
                        }
                    }
                    Crt { visible: tileBox.hidden > 0; y: tiles.y + tiles.height + 8 * mn.s
                          width: parent.width; horizontalAlignment: Text.AlignRight; color: Theme.dimText; font.pixelSize: pBezel.fs * 0.75
                          text: "+" + tileBox.hidden + " MORE MATERIALS, ALL " + (mn.materialTiles.slice(9).some(function (x) { return x.r.verdict === "MAYBE" || x.r.verdict === "?" }) ? "MAYBE OR SKIP" : "SKIP") }
                }
            }
        }

        // ---------------------------------------------------------- RINGS
        Plate {
            id: ringPlate
            x: 0; y: mn.prospH + mn.g; width: mn.leftW; height: mn.bodyH - y
            screwSize: 13 * mn.s
            Dymo { id: rDymo; x: 26 * mn.s; y: 14 * mn.s; text: "RINGS NEAR YOU" }
            Caption { x: rDymo.x + rDymo.width + 20 * mn.s; anchors.verticalCenter: rDymo.verticalCenter
                      width: parent.width - x - 26 * mn.s; elide: Text.ElideRight
                      text: mn.wanted.length ? "RINGS WITH YOUR LOOKING FOR HOTSPOTS COME FIRST  //  PLOT TAKES YOU THERE  //  SAY \"FIND ME A PLATINUM HOTSPOT\""
                                             : "FROM YOUR SCANS  //  HOTSPOTS SHOW ONCE YOU MAP A RING WITH THE SURFACE SCANNER  //  PLOT TAKES YOU THERE" }
            Bezel {
                id: rBezel
                x: 16 * mn.s; y: 50 * mn.s; width: parent.width - 32 * mn.s; height: parent.height - 66 * mn.s
                pad: 12 * mn.s
                readonly property real fs: Math.max(11, 20 * mn.s)
                PhosphorList {
                    id: ringList
                    x: 14 * mn.s; y: 8 * mn.s; width: rBezel.width - rBezel.pad * 2 - 28 * mn.s; height: rBezel.height - rBezel.pad * 2 - 16 * mn.s
                    fontSize: rBezel.fs * 0.8
                    model: mn.ringData
                    delegate: Item {
                        id: ringRow
                        required property var modelData
                        required property int index
                        readonly property bool hasPlot: !modelData.here
                        width: ringList.list.width - (ringList.overflow ? 0 : 26 * mn.s); height: rBezel.fs * 2.4
                        // rings with hotspots for your LOOKING FOR list come first, with a green bar
                        Rectangle { visible: !!ringRow.modelData.wanted; anchors.fill: parent; anchors.bottomMargin: 4 * mn.s
                                    radius: 3 * mn.s; color: Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.10) }
                        readonly property real textW: width - plotKey.width - 14 * mn.s
                        Crt { y: 2 * mn.s; width: ringRow.textW * 0.5; elide: Text.ElideRight; text: mn.up(ringRow.modelData.ring); font.pixelSize: rBezel.fs
                              color: ringRow.modelData.mapped ? Theme.ok : Theme.phosphor }
                        Crt { x: ringRow.textW * 0.5; y: 2 * mn.s; width: ringRow.textW * 0.3; elide: Text.ElideRight; font.pixelSize: rBezel.fs
                              text: (ringRow.modelData.reserve ? ringRow.modelData.reserve + " " : "") + ringRow.modelData.cls
                              color: ringRow.modelData.reserve === "PRISTINE" ? Theme.ok : Theme.phosphor }
                        Crt { x: ringRow.textW - width; y: 2 * mn.s; font.pixelSize: rBezel.fs * 0.9; color: Theme.dimText
                              text: Number(ringRow.modelData.ly) <= 0 || ringRow.modelData.here ? "THIS SYSTEM" : Number(ringRow.modelData.ly).toFixed(1) + " LY" }
                        Crt { y: rBezel.fs * 1.1; width: ringRow.textW; elide: Text.ElideRight; font.pixelSize: rBezel.fs * 0.78
                              color: ringRow.modelData.wanted ? Theme.ok : (ringRow.modelData.mapped ? Theme.info : Theme.dimText)
                              text: (ringRow.modelData.wanted ? "ON YOUR LIST  " + ringRow.modelData.wantedHot + "  //  "
                                     : (ringRow.modelData.mapped ? "HOTSPOTS  " + ringRow.modelData.hotspots + "  //  " : "NOT MAPPED  //  "))
                                    + mn.up(ringRow.modelData.system) + (Number(ringRow.modelData.ls) > 0 ? "  //  " + mn.num(ringRow.modelData.ls) + " LS" : "") }
                        Rectangle {
                            id: plotKey
                            visible: ringRow.hasPlot && !mn.exRings
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            width: 92 * mn.s; height: rBezel.fs * 1.6; radius: 3 * mn.s
                            color: "transparent"; border.color: ringRow.modelData.wanted ? Theme.ok : Theme.t("#557dff9c"); border.width: 1
                            Crt { anchors.centerIn: parent; text: "PLOT"; font.pixelSize: rBezel.fs * 0.85
                                  color: ringRow.modelData.wanted ? Theme.ok : Theme.phosphor }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: { bridge.plotMiningRing(ringRow.index); mn.notice("ROUTE", "PLOTTING TO " + mn.up(ringRow.modelData.system), "info") } }
                        }
                        Rectangle { anchors.bottom: parent.bottom; anchors.bottomMargin: 2 * mn.s; width: parent.width; height: 1; color: Theme.t("#227dff9c") }
                    }
                }
                ExampleStamp { visible: mn.exRings; note: "YOURS SHOW UP AS YOU SCAN SYSTEMS" }
                Crt { visible: mn.ringData.length === 0; anchors.centerIn: parent; width: rBezel.width * 0.8
                      horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; color: Theme.dimText
                      text: "NO RINGS FOUND IN YOUR SCANS YET // HONK A SYSTEM AND RINGS SHOW UP HERE" }
            }
        }

        // ---------------------------------------------------------- THIS RUN
        Plate {
            id: runPlate
            x: mn.rightX; y: 0; width: mn.rightW; height: mn.runH
            screwSize: 13 * mn.s
            Dymo { id: hDymo; x: 26 * mn.s; y: 14 * mn.s; text: "HAUL" }
            Caption { x: hDymo.x + hDymo.width + 20 * mn.s; anchors.verticalCenter: hDymo.verticalCenter
                      text: "SINCE YOU LOADED THE GAME" + (Number(mn.m.runMinutes) > 0 ? "  //  " + mn.m.runMinutes + " MIN MINING" : "") }
            Bezel {
                id: hBezel
                x: 16 * mn.s; y: 50 * mn.s; width: parent.width - 32 * mn.s; height: parent.height - 66 * mn.s
                pad: 12 * mn.s
                readonly property real fs: Math.max(11, 20 * mn.s)
                Row {
                    id: bigRow
                    x: 18 * mn.s; y: 8 * mn.s; spacing: 34 * mn.s
                    Repeater {
                        model: [["REFINED", mn.num(mn.haulTons) + " T"], ["WORTH ABOUT", mn.compact(mn.haulValue) + " CR"],
                                ["PER HOUR", mn.perHour > 0 ? mn.compact(mn.perHour) : "-"]]
                        Column {
                            required property var modelData
                            Crt { text: modelData[0]; color: Theme.dimText; font.pixelSize: hBezel.fs * 0.8; font.letterSpacing: 2 * mn.s }
                            Crt { text: modelData[1]; color: Theme.ok; font.pixelSize: hBezel.fs * 1.9 }
                        }
                    }
                }
                PhosphorList {
                    id: haulList
                    x: 18 * mn.s; y: bigRow.y + bigRow.height + 10 * mn.s
                    width: hBezel.width - hBezel.pad * 2 - 36 * mn.s; height: hBezel.height - hBezel.pad * 2 - y - 8 * mn.s
                    fontSize: hBezel.fs * 0.8
                    model: mn.haulData
                    delegate: Item {
                        required property var modelData
                        width: haulList.list.width - (haulList.overflow ? 0 : 26 * mn.s); height: hBezel.fs * 1.35
                        Crt { width: parent.width * 0.42; elide: Text.ElideRight; text: mn.up(modelData.name); font.pixelSize: hBezel.fs }
                        Crt { x: parent.width * 0.44; text: modelData.tons + " T"; font.pixelSize: hBezel.fs }
                        Crt { anchors.right: parent.right; font.pixelSize: hBezel.fs; color: Theme.dimText
                              text: Number(modelData.value) > 0 ? mn.compact(modelData.value) + " CR" : "?" }
                    }
                }
                ExampleStamp { visible: mn.exHaul; note: "YOURS FILLS IN AS THE REFINERY WORKS" }
                Crt { visible: mn.haulData.length === 0; x: 18 * mn.s; y: bigRow.y + bigRow.height + 14 * mn.s
                      width: hBezel.width - hBezel.pad * 2 - 36 * mn.s; wrapMode: Text.WordWrap; color: Theme.dimText; font.pixelSize: hBezel.fs * 0.9
                      text: "NOTHING REFINED YET THIS GAME" }
            }
        }

        // ---------------------------------------------------------- HOLD + KIT
        Plate {
            id: holdPlate
            x: mn.rightX; y: mn.runH + mn.g; width: mn.rightW; height: mn.holdH
            screwSize: 13 * mn.s
            Dymo { id: kDymo; x: 26 * mn.s; y: 14 * mn.s; text: "HOLD + KIT" }
            Bezel {
                id: kBezel
                x: 16 * mn.s; y: 50 * mn.s; width: parent.width - 32 * mn.s; height: parent.height - 66 * mn.s
                pad: 12 * mn.s
                readonly property real fs: Math.max(11, 20 * mn.s)
                readonly property int cap: bridge.cargoCapacity > 0 ? bridge.cargoCapacity : 0
                readonly property int used: Math.max(0, bridge.cargoUsed)
                Crt { id: cLbl; x: 18 * mn.s; y: 8 * mn.s; text: "CARGO"; color: Theme.dimText; font.pixelSize: kBezel.fs * 0.85; font.letterSpacing: 2 * mn.s }
                Crt { anchors.right: parent.right; anchors.rightMargin: 18 * mn.s; y: 8 * mn.s; font.pixelSize: kBezel.fs
                      text: kBezel.cap > 0 ? kBezel.used + " / " + kBezel.cap + " T" : "-" }
                BlockBar { x: 18 * mn.s; y: cLbl.y + cLbl.height + 4 * mn.s; width: kBezel.width - kBezel.pad * 2 - 36 * mn.s; height: kBezel.fs * 0.7
                           segments: 30; known: kBezel.cap > 0; value: kBezel.cap > 0 ? kBezel.used / kBezel.cap : 0
                           color: kBezel.cap > 0 && kBezel.used / kBezel.cap > 0.9 ? Theme.info : Theme.ok }
                Crt { id: lLine; x: 18 * mn.s; y: cLbl.y + cLbl.height + kBezel.fs * 1.2; font.pixelSize: kBezel.fs
                      readonly property int n: Number(mn.m.limpets === undefined ? -1 : mn.m.limpets)
                      text: "LIMPETS  " + (n >= 0 ? n : "-") + "    //    USED THIS GAME  " + (mn.m.prospectors || 0) + " PROSPECT  " + (mn.m.collectors || 0) + " COLLECT"
                      color: n === 0 ? Theme.bad : (n > 0 && n < 6 ? Theme.info : Theme.phosphor) }
                Grid {
                    x: 18 * mn.s; y: lLine.y + lLine.height + 10 * mn.s
                    columns: 4; columnSpacing: 22 * mn.s; rowSpacing: 6 * mn.s
                    Repeater {
                        model: mn.m.kit || []
                        Row {
                            required property var modelData
                            spacing: 8 * mn.s
                            Rectangle { width: kBezel.fs * 0.5; height: width; radius: width / 2; anchors.verticalCenter: parent.verticalCenter
                                        color: modelData.ok ? Theme.ok : "transparent"; border.color: modelData.ok ? Theme.ok : Theme.info; border.width: 2 }
                            Crt { text: modelData.label; font.pixelSize: kBezel.fs * 0.82; color: modelData.ok ? Theme.phosphor : Theme.info }
                        }
                    }
                }
            }
        }

        // ---------------------------------------------------------- SELL
        Plate {
            id: sellPlate
            x: mn.rightX; y: mn.runH + mn.holdH + mn.g * 2; width: mn.rightW; height: mn.bodyH - y
            screwSize: 13 * mn.s
            Dymo { id: sDymo; x: 26 * mn.s; y: 14 * mn.s; text: "WHERE TO SELL" }
            Caption { x: sDymo.x + sDymo.width + 20 * mn.s; anchors.verticalCenter: sDymo.verticalCenter
                      width: parent.width - x - 26 * mn.s; elide: Text.ElideRight
                      text: (mn.m.pricing ? "CHECKING MARKETS...  //  " : "") + "BEST PRICE WITHIN " + (mn.m.sellLy || 60) + " LY // CHECK PAD SIZE" }
            Bezel {
                id: sBezel
                x: 16 * mn.s; y: 50 * mn.s; width: parent.width - 32 * mn.s; height: parent.height - 66 * mn.s
                pad: 12 * mn.s
                readonly property real fs: Math.max(11, 20 * mn.s)
                PhosphorList {
                    id: sellList
                    x: 14 * mn.s; y: 8 * mn.s; width: sBezel.width - sBezel.pad * 2 - 28 * mn.s; height: sBezel.height - sBezel.pad * 2 - 16 * mn.s
                    fontSize: sBezel.fs * 0.8
                    model: mn.sellData
                    delegate: Item {
                        required property var modelData
                        width: sellList.list.width - (sellList.overflow ? 0 : 26 * mn.s); height: sBezel.fs * 2.4
                        Crt { y: 2 * mn.s; width: parent.width * 0.45; elide: Text.ElideRight; font.pixelSize: sBezel.fs
                              text: mn.up(modelData.name) + "  " + modelData.tons + " T" }
                        Crt { anchors.right: parent.right; y: 2 * mn.s; font.pixelSize: sBezel.fs; color: Theme.ok
                              text: Number(modelData.price) > 0 ? mn.compact(modelData.price * modelData.tons) + " CR" : "?" }
                        Crt { y: sBezel.fs * 1.1; width: parent.width; elide: Text.ElideRight; font.pixelSize: sBezel.fs * 0.78; color: Theme.dimText
                              text: Number(modelData.price) > 0
                                    ? mn.num(modelData.price) + " CR/T AT " + mn.up(modelData.station) + " // " + mn.up(modelData.system)
                                      + (Number(modelData.ly) >= 0 ? " // " + Number(modelData.ly).toFixed(1) + " LY" : "") + (modelData.pad ? " // PAD " + modelData.pad : "")
                                    : "NO BUYER FOUND YET" }
                        Rectangle { anchors.bottom: parent.bottom; anchors.bottomMargin: 2 * mn.s; width: parent.width; height: 1; color: Theme.t("#227dff9c") }
                    }
                }
                ExampleStamp { visible: mn.exSell; note: "YOURS SHOWS WHEN THERE IS ORE IN THE HOLD" }
                Crt { visible: mn.sellData.length === 0; anchors.centerIn: parent; width: sBezel.width * 0.8
                      horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; color: Theme.dimText
                      text: "HOLD IS EMPTY // MINED GOODS SHOW UP HERE WITH THE BEST PLACE TO SELL THEM" }
            }
        }
    }

    // ================================================================= SURFACE + RAW MATERIALS
    // Raw engineering materials against the game's storage caps (grade 1: 300, 2: 250, 3: 200,
    // 4: 150). Counts come from the game's material list at login plus every pickup, trade,
    // synthesis and engineer use since. The ship voice says when one is full.
    readonly property var raws: bridge.raws || []
    // RAW TARGETS (2026-10-28): tap a raw to set how many you want; a tick marks it on the bar and
    // the ship says when you get there. Kept locally so a tap shows at once; saved as a setting.
    property var rawTargetsLocal: null
    readonly property var rawTargets: {
        if (rawTargetsLocal !== null) return rawTargetsLocal
        var t = {}
        for (var i = 0; i < raws.length; i++) if (Number(raws[i].target) > 0) t[raws[i].name] = Number(raws[i].target)
        return t
    }
    property string rawPick: ""
    property int rawPickCap: 0
    function setRawTarget(name, n) {
        var t = {}, k
        for (k in rawTargets) t[k] = rawTargets[k]
        if (n > 0) t[name] = n; else delete t[name]
        rawTargetsLocal = t
        var parts = []
        for (k in t) parts.push(k + ":" + t[k])
        bridge.setSetupValue("raw_targets", parts.join(","))
    }
    // RHINO (2026-10-27): surface mining from the journal. The game logs no rig events, so a rig
    // collection is a quick burst of refined tons while driving. Only facts the game reports.
    readonly property var srv: mn.m.srv || ({})
    readonly property bool srvIn: !!srv.in
    onSrvInChanged: if (srvIn) mn.view = 1          // climbing into an SRV shows this view
    readonly property real rhinoH: mn.bodyH * 0.40
    Plate {
        id: rhinoPlate
        visible: mn.view === 1
        x: 0; y: 0; width: mn.width; height: mn.rhinoH
        screwSize: 13 * mn.s
        Dymo { id: rhDymo; x: 26 * mn.s; y: 14 * mn.s; text: "RHINO" }
        Caption { x: rhDymo.x + rhDymo.width + 20 * mn.s; anchors.verticalCenter: rhDymo.verticalCenter
                  width: parent.width - x - 26 * mn.s; elide: Text.ElideRight
                  text: "SURFACE MINING SINCE YOU LOADED THE GAME  //  MAP A BODY WITH THE SURFACE SCANNER TO FIND MINING LOCATIONS  //  RECOVER YOUR RIGS BEFORE YOU BOARD" }
        Bezel {
            id: rhBezel
            x: 16 * mn.s; y: 50 * mn.s; width: parent.width - 32 * mn.s; height: parent.height - 66 * mn.s
            pad: 12 * mn.s
            readonly property real fs: Math.max(11, 21 * mn.s)
            readonly property real iw: width - pad * 2
            readonly property bool any: Number(mn.srv.count || 0) > 0 || mn.srvIn || (mn.srv.locs || []).length > 0
            Crt { visible: !rhBezel.any; x: rhBezel.iw * 0.34; width: rhBezel.iw * 0.62; anchors.verticalCenter: parent.verticalCenter
                  horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; color: Theme.dimText; font.pixelSize: rhBezel.fs * 1.05
                  text: "NO SURFACE RUN YET // MAP A BODY WITH THE SURFACE SCANNER, DROP THE RHINO AT A MINING LOCATION AND COLLECT A RIG. IT SHOWS UP HERE." }
            // left: the endless drive (2026-10-28), with where you are + the Rhino's hold over its sky
            Terrain {
                id: rhTerrain
                x: 6 * mn.s; y: 6 * mn.s; width: rhBezel.iw * 0.30 - 12 * mn.s; height: rhBezel.height - rhBezel.pad * 2 - 12 * mn.s
                running: mn.visible && mn.view === 1
            }
            Column {
                visible: rhBezel.any
                x: 18 * mn.s; y: 12 * mn.s; width: rhBezel.iw * 0.30 * 0.62; spacing: 6 * mn.s
                Crt { text: mn.srvIn ? "IN THE " + (mn.srv.name || "SRV") : "IN THE SHIP"
                      color: mn.srvIn ? Theme.ok : Theme.phosphor; font.pixelSize: rhBezel.fs * 1.5; font.letterSpacing: 3 * mn.s }
                Crt { visible: mn.srvIn && Number(mn.srv.hold) > 0; text: "RHINO HOLD  " + Number(mn.srv.cargo || 0) + " / " + mn.srv.hold + " T"
                      font.pixelSize: rhBezel.fs; color: Number(mn.srv.cargo) >= Number(mn.srv.hold) ? Theme.info : Theme.phosphor }
                BlockBar { visible: mn.srvIn && Number(mn.srv.hold) > 0; width: parent.width; height: rhBezel.fs * 0.6; segments: 24
                           value: Math.min(1, Number(mn.srv.cargo || 0) / Math.max(1, Number(mn.srv.hold || 72)))
                           color: Number(mn.srv.cargo) >= Number(mn.srv.hold) ? Theme.info : Theme.ok }

                Crt { visible: Number(mn.srv.locsHere || 0) > 0; color: Theme.ok; font.pixelSize: rhBezel.fs
                      text: mn.srv.locsHere + " MINING LOCATIONS ON THIS BODY" }
            }
            Rectangle { visible: rhBezel.any; x: rhBezel.iw * 0.30; y: 12 * mn.s; width: 1; height: rhBezel.height - rhBezel.pad * 2 - 24 * mn.s; color: Theme.t("#337dff9c") }
            // middle: this run's numbers
            Column {
                visible: rhBezel.any
                x: rhBezel.iw * 0.30 + 24 * mn.s; y: 8 * mn.s; width: rhBezel.iw * 0.36 - 40 * mn.s; spacing: 10 * mn.s
                Row {
                    spacing: 30 * mn.s
                    Repeater {
                        model: [["MINED", mn.num(mn.srv.tons || 0) + " T"], ["WORTH ABOUT", mn.compact(mn.srv.value || 0) + " CR"],
                                ["PER HOUR", Number(mn.srv.perHour) > 0 ? mn.compact(mn.srv.perHour) : "-"], ["RIGS", String(mn.srv.count || 0)]]
                        Column {
                            required property var modelData
                            Crt { text: modelData[0]; color: Theme.dimText; font.pixelSize: rhBezel.fs * 0.8; font.letterSpacing: 2 * mn.s }
                            Crt { text: modelData[1]; color: Theme.ok; font.pixelSize: rhBezel.fs * 1.7 }
                        }
                    }
                }
                Crt { width: parent.width; elide: Text.ElideRight; font.pixelSize: rhBezel.fs * 0.85; color: Theme.phosphor
                      text: (mn.srv.haul || []).map(function (h) { return mn.up(h.name) + " " + h.tons + " T" }).join("   ") }
                Crt { visible: !!mn.srv.raws; width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                      font.pixelSize: rhBezel.fs * 0.8; color: Theme.dimText; text: "RAWS PICKED UP  " + (mn.srv.raws || "") }
            }
            Rectangle { visible: rhBezel.any; x: rhBezel.iw * 0.66; y: 12 * mn.s; width: 1; height: rhBezel.height - rhBezel.pad * 2 - 24 * mn.s; color: Theme.t("#337dff9c") }
            // right: rig collections, newest first, then mining locations in this system
            Column {
                visible: rhBezel.any
                x: rhBezel.iw * 0.66 + 24 * mn.s; y: 8 * mn.s; width: rhBezel.iw * 0.34 - 40 * mn.s; spacing: 6 * mn.s
                Crt { text: "RIG COLLECTIONS"; color: Theme.dimText; font.pixelSize: rhBezel.fs * 0.8; font.letterSpacing: 2 * mn.s }
                Crt { visible: (mn.srv.collections || []).length === 0; text: "NONE YET"; color: Theme.dimText; font.pixelSize: rhBezel.fs * 0.9 }
                Repeater {
                    model: (mn.srv.collections || []).slice(0, 3)
                    Item {
                        required property var modelData
                        width: parent.width; height: rhBezel.fs * 1.3
                        Crt { width: parent.width * 0.68; elide: Text.ElideRight; font.pixelSize: rhBezel.fs * 0.9; text: mn.up(modelData.what) }
                        Crt { anchors.right: parent.right; font.pixelSize: rhBezel.fs * 0.8; color: Theme.dimText; text: mn.ago(modelData.age) }
                    }
                }
                Item { width: 1; height: 4 * mn.s }
                Crt { visible: (mn.srv.locs || []).length > 0; text: "MINING LOCATIONS IN THIS SYSTEM"; color: Theme.dimText
                      font.pixelSize: rhBezel.fs * 0.8; font.letterSpacing: 2 * mn.s }
                Repeater {
                    model: (mn.srv.locs || []).slice(0, 3)
                    Crt {
                        required property var modelData
                        width: parent.width; elide: Text.ElideRight; font.pixelSize: rhBezel.fs * 0.9
                        color: modelData.here ? Theme.ok : Theme.phosphor
                        text: mn.up(modelData.body) + "  //  " + modelData.count + (modelData.here ? "  //  YOU ARE HERE" : "")
                    }
                }
            }
        }
    }
    Plate {
        visible: mn.view === 1
        x: 0; y: mn.rhinoH + mn.g; width: mn.width; height: mn.bodyH - y
        screwSize: 13 * mn.s
        Dymo { id: rawDymo; x: 26 * mn.s; y: 14 * mn.s; text: "RAW MATERIALS" }
        Caption { x: rawDymo.x + rawDymo.width + 20 * mn.s; anchors.verticalCenter: rawDymo.verticalCenter
                  width: parent.width - x - 26 * mn.s; elide: Text.ElideRight
                  text: "FOR ENGINEERING  //  TAP ONE TO SET A TARGET  //  THE SHIP SAYS WHEN YOU HIT A TARGET OR ONE IS FULL" }
        Bezel {
            id: rawBezel
            x: 16 * mn.s; y: 50 * mn.s; width: parent.width - 32 * mn.s; height: parent.height - 66 * mn.s
            pad: 12 * mn.s
            readonly property real fs: Math.max(9, Math.min(21 * mn.s, (height - 130 * mn.s) / 7 / 2.5))   // smaller when the RHINO panel shares the view
            readonly property real colW: (width - pad * 2 - 110 * mn.s - 3 * 40 * mn.s) / 4
            readonly property real rowH: Math.min(fs * 3.6, (height - pad * 2 - 30 * mn.s - fs * 2.2) / 7)
            Crt { visible: mn.raws.length > 0 && !mn.raws[0].known; anchors.centerIn: parent; color: Theme.dimText
                  text: "WAITING FOR THE GAME'S MATERIAL LIST // IT ARRIVES WHEN YOU LOAD INTO THE GAME" }
            Row {
                visible: mn.raws.length > 0 && mn.raws[0].known
                x: 55 * mn.s; y: 16 * mn.s; spacing: 40 * mn.s
                Repeater {
                    model: [1, 2, 3, 4]
                    Column {
                        required property int modelData
                        width: rawBezel.colW; spacing: 6 * mn.s
                        Crt { text: "GRADE " + parent.modelData + "  //  MAX " + [0, 300, 250, 200, 150][parent.modelData]
                              color: Theme.dimText; font.pixelSize: rawBezel.fs * 0.85; font.letterSpacing: 2 * mn.s }
                        Item { width: 1; height: 6 * mn.s }
                        Repeater {
                            model: mn.raws.filter(function (r) { return r.grade === parent.modelData })
                            Item {
                                id: rawRow
                                required property var modelData
                                readonly property real f: Math.min(1, Number(modelData.count) / Math.max(1, Number(modelData.cap)))
                                readonly property int target: Number(mn.rawTargets[modelData.name] || 0)
                                readonly property bool reached: target > 0 && Number(modelData.count) >= target
                                readonly property color c: f >= 1 ? Theme.info : (reached ? Theme.ok : (modelData.count > 0 ? Theme.phosphor : Theme.dimText))
                                width: rawBezel.colW; height: rawBezel.rowH
                                Crt { id: rawName; y: 0; text: mn.up(parent.modelData.name); color: parent.c; font.pixelSize: rawBezel.fs }
                                Crt { anchors.left: rawName.right; anchors.leftMargin: 10 * mn.s; anchors.baseline: rawName.baseline
                                      visible: rawRow.target > 0; color: rawRow.reached ? Theme.ok : Theme.info; font.pixelSize: rawBezel.fs * 0.75
                                      text: rawRow.reached ? "TARGET MET" : "TARGET " + rawRow.target }
                                Crt { anchors.right: parent.right; y: 0; font.pixelSize: rawBezel.fs
                                      text: parent.f >= 1 ? "FULL" : parent.modelData.count + " / " + parent.modelData.cap; color: parent.c }
                                BlockBar { id: rawBar; y: rawBezel.fs * 1.35; width: parent.width; height: rawBezel.fs * 0.6
                                           segments: 24; value: parent.f; color: parent.f >= 1 ? Theme.info : Theme.ok }
                                Rectangle { visible: rawRow.target > 0; color: Theme.info
                                            x: rawBar.width * rawRow.target / Math.max(1, Number(rawRow.modelData.cap)) - width / 2
                                            y: rawBar.y - 3 * mn.s; width: Math.max(2, 3 * mn.s); height: rawBar.height + 6 * mn.s }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: { mn.rawPick = rawRow.modelData.name; mn.rawPickCap = Number(rawRow.modelData.cap) } }
                            }
                        }
                    }
                }
            }
        }
    }

    // ================================================================= ACTION DECK
    component Groove: Item {
        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 4 * mn.s; height: parent.height; radius: 2 * mn.s; color: "#0b0b0a"; border.color: "#3e3b32"; border.width: 1 }
    }
    Plate {
        id: deck
        dark: true
        screwSize: 13 * mn.s
        x: 0; y: mn.deckY; width: mn.width; height: mn.deckH
        readonly property real keyH: Math.min(height - 66 * mn.s, 150 * mn.s)
        readonly property real keyY: 52 * mn.s + (height - 66 * mn.s - keyH) / 2
        readonly property real cancelW: 270 * mn.s
        readonly property real divW: 40 * mn.s
        readonly property real keyGap: 14 * mn.s
        readonly property real keyW: (width - 26 * mn.s - cancelW - 40 * mn.s - 44 * mn.s - divW * 2 - keyGap * 10 - 420 * mn.s) / 8.3
        Dymo { x: 26 * mn.s; y: 14 * mn.s; text: "ACTIONS // MINING" }
        SelectorRow {
            x: deck.width - deck.cancelW - 40 * mn.s - width - 40 * mn.s; y: deck.keyY + (deck.keyH - height) / 2
            options: ["RING MINING", "RHINO + RAW"]
            buttonWidth: 170 * mn.s; buttonHeight: 44 * mn.s
            currentIndex: mn.view
            onPicked: (i) => mn.view = i
        }
        Row {
            id: dRow
            x: 26 * mn.s; y: deck.keyY
            spacing: deck.keyGap
            Repeater {
                id: fgKeys
                model: ["A", "B", "C", "D", "E"]
                DeckKey {
                    required property var modelData
                    required property int index
                    width: deck.keyW * 0.8; height: deck.keyH
                    title: modelData; legend: "FIRE GROUP"
                    keyState: mn.bindsReady ? "ready" : "unavailable"
                    unavailableReason: mn.bindsReason
                    tooltip: "SELECT FIRE GROUP " + modelData; tooltipDetail: "SAME AS CTRL+ALT+SHIFT+F" + (index + 1)
                    onActivated: bridge.requestCommand("mining_fg_" + modelData.toLowerCase())
                    onDenied: (r) => mn.denied("FIRE GROUP UNAVAILABLE", r)
                }
            }
            Groove { width: deck.divW; height: deck.keyH }
            DeckKey {
                id: leaveKey
                width: deck.keyW * 1.25; height: deck.keyH
                title: "CLEAR + JUMP"
                readonly property bool run: mn.bstate.indexOf("CLEAR STATION") === 0
                legend: run ? bridge.bridgeMessage : "STOW + SUPERCRUISE"
                keyState: run ? "running" : (mn.bindsReady ? "ready" : "unavailable")
                unavailableReason: mn.bindsReason
                tooltip: "LEAVE THE RING"; tooltipDetail: "CLOSES THE SCOOP, STOWS TOOLS, BOOSTS CLEAR, SUPERCRUISE"
                onActivated: bridge.requestCommand("clear")
                onDenied: (r) => mn.denied("CLEAR + JUMP UNAVAILABLE", r)
            }
            DeckKey {
                id: collectorKey
                width: deck.keyW * 1.05; height: deck.keyH
                title: "COLLECTOR"
                legend: mn.m.collectorConfirmed ? "GROUP " + (mn.m.collectorGroup || "A") + " // " + String(mn.m.collectorFire || "SECONDARY").slice(0, 3)
                                                : "TAP TO SET UP"
                keyState: mn.bindsReady ? "ready" : "unavailable"
                unavailableReason: mn.bindsReason
                tooltip: "LAUNCH ONE COLLECTOR"; tooltipDetail: "SWITCHES TO THE COLLECTOR FIRE GROUP AND FIRES IT ONCE // SAY \"DEPLOY COLLECTOR\""
                onActivated: { if (mn.m.collectorConfirmed) bridge.requestCommand("mining_collector"); else mn.openCollectorSetup() }
                onDenied: (r) => mn.denied("COLLECTOR UNAVAILABLE", r)
            }
            Groove { width: deck.divW; height: deck.keyH }
            DeckKey {
                id: resetKey
                width: deck.keyW * 1.05; height: deck.keyH
                title: "NEW RUN"; legend: "RESET THIS RUN"
                keyState: "ready"
                tooltip: "START A NEW RUN"; tooltipDetail: "CLEARS REFINED TONS AND ROCKS"
                onActivated: { bridge.requestCommand("mining_reset"); mn.notice("NEW RUN", "REFINED TONS AND ROCKS CLEARED", "info") }
            }
        }
        Caption { x: dRow.x + (deck.keyW * 0.8 * 5 + deck.keyGap * 4) / 2 - width / 2
                  y: deck.keyY - height - 6 * mn.s; text: "FIRE GROUPS" }
        // small "CHANGE" above the COLLECTOR key, once it's set up
        Caption {
            visible: !!mn.m.collectorConfirmed
            x: dRow.x + collectorKey.x + collectorKey.width / 2 - width / 2
            y: deck.keyY - height - 6 * mn.s; text: "CHANGE"
            MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: mn.openCollectorSetup() }
        }
        Item {
            x: deck.width - deck.cancelW - 40 * mn.s; y: deck.keyY; width: deck.cancelW; height: deck.keyH
            Glow { target: ck; color: "#ff5040"; spread: 34 * mn.s; radius: 8 * mn.s; intensity: mn.inControl ? 0.8 : 0 }
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

    // LOOKING FOR picker: tap materials to add or remove (3 at most). Materials seen this run first.
    Rectangle {
        id: picker
        visible: mn.pickerOpen
        z: 50
        x: 0; y: 0; width: mn.leftW; height: mn.bodyH
        color: "#fa070d09"; border.color: Theme.ok; border.width: 2; radius: 6 * mn.s
        MouseArea { anchors.fill: parent }            // keeps clicks off the page underneath
        readonly property real fs: Math.max(11, 20 * mn.s)
        Crt { id: pkHead; x: 26 * mn.s; y: 20 * mn.s; text: "LOOKING FOR  //  PICK UP TO 3"; color: Theme.ok
              font.pixelSize: picker.fs * 1.2; font.letterSpacing: 3 * mn.s }
        Crt { x: 26 * mn.s; y: pkHead.y + pkHead.height + 6 * mn.s; width: parent.width - 52 * mn.s; wrapMode: Text.WordWrap
              color: Theme.dimText; font.pixelSize: picker.fs * 0.8
              text: "WHEN A PROSPECTOR FINDS ONE OF THESE AT 5% OR MORE, THE ROCK IS MARKED MINE AND THE SHIP SAYS SO, WHATEVER IT SELLS FOR." }
        Flickable {
            x: 26 * mn.s; y: pkHead.y + pkHead.height + picker.fs * 3.2
            width: parent.width - 52 * mn.s; height: parent.height - y - doneKey.height - 40 * mn.s
            contentHeight: flow.height; clip: true
            Flow {
                id: flow
                width: parent.width; spacing: 10 * mn.s
                Repeater {
                    model: mn.pickList
                    Rectangle {
                        required property var modelData
                        readonly property bool on: mn.isWanted(modelData)
                        height: picker.fs * 1.9; width: pl.implicitWidth + 34 * mn.s; radius: 3 * mn.s
                        color: on ? Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.22) : "transparent"
                        border.color: on ? Theme.ok : Theme.t("#557dff9c"); border.width: on ? 2 : 1
                        Crt { id: pl; anchors.centerIn: parent; text: mn.up(parent.modelData); color: parent.on ? Theme.ok : Theme.phosphor
                              font.pixelSize: picker.fs * 0.9 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: mn.toggleWanted(parent.modelData) }
                    }
                }
            }
        }
        Rectangle {
            id: doneKey
            anchors.right: parent.right; anchors.rightMargin: 26 * mn.s; anchors.bottom: parent.bottom; anchors.bottomMargin: 20 * mn.s
            width: 200 * mn.s; height: picker.fs * 2.2; radius: 4 * mn.s
            color: Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.18); border.color: Theme.ok; border.width: 2
            Crt { anchors.centerIn: parent; text: "DONE"; color: Theme.ok; font.pixelSize: picker.fs * 1.1; font.letterSpacing: 3 * mn.s }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: mn.pickerOpen = false }
        }
    }

    // RAW TARGET picker
    Rectangle {
        id: rawSetup
        visible: mn.rawPick !== ""
        z: 60
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.6, 1100 * mn.s); height: 330 * mn.s
        color: "#fa070d09"; border.color: Theme.info; border.width: 2; radius: 6 * mn.s
        MouseArea { anchors.fill: parent }
        readonly property real fs: Math.max(11, 22 * mn.s)
        readonly property int current: Number(mn.rawTargets[mn.rawPick] || 0)
        component TPick: Rectangle {
            id: tp
            property string label
            property bool on
            signal picked()
            height: rawSetup.fs * 2.2; width: Math.max(rawSetup.fs * 3.2, tpt.implicitWidth + 36 * mn.s); radius: 3 * mn.s
            color: on ? Qt.rgba(Theme.info.r, Theme.info.g, Theme.info.b, 0.22) : "transparent"
            border.color: on ? Theme.info : Theme.t("#557dff9c"); border.width: on ? 2 : 1
            Crt { id: tpt; anchors.centerIn: parent; text: tp.label; color: tp.on ? Theme.info : Theme.phosphor; font.pixelSize: rawSetup.fs }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tp.picked() }
        }
        Column {
            x: 40 * mn.s; y: 30 * mn.s; width: parent.width - 80 * mn.s; spacing: 18 * mn.s
            Crt { text: "HOW MUCH " + mn.up(mn.rawPick) + " DO YOU WANT?"; color: Theme.info; font.pixelSize: rawSetup.fs * 1.25; font.letterSpacing: 3 * mn.s }
            Crt { width: parent.width; wrapMode: Text.WordWrap; color: Theme.dimText; font.pixelSize: rawSetup.fs * 0.8
                  text: "A TICK MARKS IT ON THE BAR AND THE SHIP TELLS YOU WHEN YOU GET THERE. STORAGE HOLDS " + mn.rawPickCap + "." }
            Row {
                spacing: 12 * mn.s
                Repeater {
                    model: [25, 50, 100, 150, 200, 250].filter(function (n) { return n < mn.rawPickCap })
                    TPick { required property var modelData; label: String(modelData); on: rawSetup.current === modelData
                            onPicked: { mn.setRawTarget(mn.rawPick, modelData); mn.rawPick = "" } }
                }
                TPick { label: "NO TARGET"; on: rawSetup.current === 0; onPicked: { mn.setRawTarget(mn.rawPick, 0); mn.rawPick = "" } }
            }
        }
        TPick { anchors.right: parent.right; anchors.rightMargin: 40 * mn.s; anchors.bottom: parent.bottom; anchors.bottomMargin: 26 * mn.s
                label: "CLOSE"; on: false; onPicked: mn.rawPick = "" }
    }

    // COLLECTOR setup: asked the first time COLLECTOR is pressed, CHANGE above the key reopens it.
    Rectangle {
        id: collSetup
        visible: mn.collectorSetupOpen
        z: 60
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.6, 1100 * mn.s); height: 420 * mn.s
        color: "#fa070d09"; border.color: Theme.ok; border.width: 2; radius: 6 * mn.s
        MouseArea { anchors.fill: parent }
        readonly property real fs: Math.max(11, 22 * mn.s)
        component Pick: Rectangle {
            id: pk
            property string label
            property bool on
            signal picked()
            height: collSetup.fs * 2.2; width: Math.max(collSetup.fs * 2.6, pkt.implicitWidth + 36 * mn.s); radius: 3 * mn.s
            color: on ? Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.22) : "transparent"
            border.color: on ? Theme.ok : Theme.t("#557dff9c"); border.width: on ? 2 : 1
            Crt { id: pkt; anchors.centerIn: parent; text: pk.label; color: pk.on ? Theme.ok : Theme.phosphor; font.pixelSize: collSetup.fs }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: pk.picked() }
        }
        Column {
            x: 40 * mn.s; y: 30 * mn.s; width: parent.width - 80 * mn.s; spacing: 18 * mn.s
            Crt { text: "WHERE ARE YOUR COLLECTOR LIMPETS?"; color: Theme.ok; font.pixelSize: collSetup.fs * 1.25; font.letterSpacing: 3 * mn.s }
            Crt { width: parent.width; wrapMode: Text.WordWrap; color: Theme.dimText; font.pixelSize: collSetup.fs * 0.8
                  text: "THE GAME DOESN'T TELL THE BRIDGE THIS. PICK THE FIRE GROUP YOUR COLLECTOR CONTROLLER IS IN, AND WHICH TRIGGER FIRES IT. THE COLLECTOR KEY AND \"DEPLOY COLLECTOR\" THEN SWITCH TO THAT GROUP AND FIRE ONCE." }
            Row {
                spacing: 12 * mn.s
                Crt { anchors.verticalCenter: parent.verticalCenter; width: 200 * mn.s; text: "FIRE GROUP"; color: Theme.phosphor; font.pixelSize: collSetup.fs }
                Repeater {
                    model: ["A", "B", "C", "D", "E", "F", "G", "H"]
                    Pick { required property var modelData; label: modelData; on: mn.csGroup === modelData; onPicked: mn.csGroup = modelData }
                }
            }
            Row {
                spacing: 12 * mn.s
                Crt { anchors.verticalCenter: parent.verticalCenter; width: 200 * mn.s; text: "TRIGGER"; color: Theme.phosphor; font.pixelSize: collSetup.fs }
                Pick { label: "PRIMARY FIRE"; on: mn.csFire === "PRIMARY"; onPicked: mn.csFire = "PRIMARY" }
                Pick { label: "SECONDARY FIRE"; on: mn.csFire === "SECONDARY"; onPicked: mn.csFire = "SECONDARY" }
            }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 40 * mn.s; anchors.bottom: parent.bottom; anchors.bottomMargin: 26 * mn.s
            spacing: 16 * mn.s
            Pick { label: "CANCEL"; on: false; onPicked: mn.collectorSetupOpen = false }
            Pick {
                label: "SAVE"; on: true
                onPicked: {
                    bridge.setSetupValue("collector_group", mn.csGroup)
                    bridge.setSetupValue("collector_fire", mn.csFire)
                    bridge.setSetupBool("collector_confirmed", true)
                    mn.collectorSetupOpen = false
                    mn.notice("COLLECTOR KEY SET", "GROUP " + mn.csGroup + " // " + mn.csFire + " FIRE", "info")
                }
            }
        }
    }
}
