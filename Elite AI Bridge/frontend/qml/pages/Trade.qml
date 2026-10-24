// TRADE (page 3). Retro redesign, build step 8 (mockups trade_find_v2.png, trade_myrun_v2.png).
// Two views on the strip under the identity bar: FIND A ROUTE and MY RUN.
// Same bridge data and the same search / run commands as v1.0.1; only the presentation changed.
// The trip counters always run (RESET TRIP zeroes them). AUTO-PLOT (checked in the engine) watches your buys and sells, counts cycles,
// and after each trade plots the next leg once you are clear of the station. You fly, dock and trade.
import QtQuick
import "../skin"

Item {
    id: tr
    property var app
    property bool demo: false
    property int tradeView: 0                  // 0 find a route, 1 my run
    signal denied(string title, string reason)
    signal notice(string title, string detail, string level)

    // tour highlight targets (Main.qml pageHelpTarget)
    readonly property Item deckTarget: tradeView === 0 ? findDeck : runDeck
    readonly property Item viewTarget: viewStrip
    readonly property Item infoTarget: tradeView === 0 ? searchPlate : loopPanel
    readonly property Item listTarget: tradeView === 0 ? routesPlate : ledgerPanel
    readonly property Item findTarget: findKey
    // the tour always shows FIND A ROUTE (it ends on the FIND ROUTES key)
    readonly property bool tourOn: bridge.pageHelpActive && bridge.pageHelpPage === 3
    onTourOnChanged: if (tourOn) tradeView = 0

    readonly property real s: Theme.s
    readonly property real g: Math.max(8, 14 * s)

    // ---------- helpers
    function norm(x) { return String(x || "").toLowerCase().replace(/[^a-z0-9]/g, "") }
    function up(x) { x = String(x === undefined || x === null ? "-" : x); return x === "" ? "-" : x.toUpperCase() }
    function num(v) { return Math.round(Number(v) || 0).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",") }
    function cr(v) { return num(v) + " CR" }
    function lasts(n) { n = Number(n) || 0; return n >= 25 ? "25+" : String(n) }

    // ---------- loop state
    readonly property string commodity: String(bridge.tradeCommodity || "-")
    readonly property string buyStation: String(bridge.tradeBuyStation || "-")
    readonly property string buySystem: String(bridge.tradeBuySystem || "-")
    readonly property string sellStation: String(bridge.tradeSellStation || "-")
    readonly property string sellSystem: String(bridge.tradeSellSystem || "-")
    readonly property bool hasLoop: commodity !== "-" && buyStation !== "-" && sellStation !== "-"
    readonly property bool runActive: bridge.tradeLoopEnabled
    readonly property bool docked: String(bridge.gameState).toUpperCase() === "DOCKED"
    readonly property bool atBuy: hasLoop && docked && norm(bridge.station) === norm(buyStation)
    readonly property bool atSell: hasLoop && docked && norm(bridge.station) === norm(sellStation)
    readonly property int cap: bridge.cargoCapacity > 0 ? bridge.cargoCapacity : Math.max(0, bridge.tradePlannedCargo)
    readonly property int load: bridge.tradePlannedCargo > 0 ? bridge.tradePlannedCargo : cap
    readonly property int aboard: bridge.tradeAboard
    readonly property bool holdFull: cap > 0 && bridge.cargoUsed >= cap
    readonly property bool holdEmpty: bridge.cargoCapacity >= 0 && bridge.cargoUsed === 0
    readonly property bool searching: bridge.tradeBestBusy || bridge.tradeRouteBusy
    readonly property bool restricted: bridge.tradeStolenAboard > 0 || bridge.tradeActiveRestricted
    // same rule the engine uses: full load -> sell; partial load at the buy station -> keep buying
    readonly property string nextSide: aboard <= 0 ? "BUY" : (aboard >= load ? "SELL" : (atBuy ? "BUY" : "SELL"))
    readonly property int target: bridge.tradeRunTargetCycles
    readonly property int done: bridge.tradeRunCompletedCycles
    readonly property int tripCycles: bridge.tradeTripCycles
    readonly property string cycleText: !hasLoop ? "NO LOOP SET"
                                        : (runActive && target > 0 ? (done >= target ? "AUTO-PLOT DONE" : "CYCLE " + (done + 1) + " OF " + target)
                                                                  : "CYCLE " + (tripCycles + 1))
    readonly property string nextText: {
        if (!hasLoop) return "FIND A ROUTE TO START"
        if (atBuy && nextSide === "BUY") return "NEXT: BUY " + num(Math.max(0, load - aboard)) + " T " + up(commodity)
        if (atSell && aboard > 0) return "NEXT: SELL " + num(aboard) + " T " + up(commodity)
        return "NEXT: FLY TO " + up(nextSide === "SELL" ? sellStation : buyStation)
    }

    // ---------- auto-plot stop-after (shared by the STOP AFTER row, the AUTO-PLOT rocker and the saved profile)
    readonly property var runLengths: ["CONTINUOUS", "5 CYCLES", "10 CYCLES", "25 CYCLES", "50 CYCLES", "100 CYCLES"]
    readonly property var runLabels: ["NONSTOP", "5", "10", "25", "50", "100"]
    property int runLengthIndex: Math.max(0, runLengths.indexOf(String(bridge.tradeRunLength || "CONTINUOUS").toUpperCase()))
    function setRunLength(i) {
        runLengthIndex = i
        Theme.cue("tick")
        if (hasLoop) bridge.saveTradeProfile(commodity, String(load), buySystem, buyStation, sellSystem, sellStation, runLengths[i])
    }
    function startRun() {
        bridge.startTradeRun(commodity, String(load), buySystem, buyStation, sellSystem, sellStation, runLengths[runLengthIndex])
    }

    // ---------- search settings (kept while you switch views)
    property string haul: ""                    // "" = ANY // BEST OVERALL
    property int startIdx: 2
    property int legIdx: 2
    property int lsIdx: 2
    property int runsIdx: 2
    property bool legalOnly: true
    property bool rareGoods: false
    readonly property var lyValues: [25, 50, 100, 200]
    readonly property var lsValues: [1000, 2500, 5000, 10000]
    readonly property var runsValues: [1, 5, 10, 25]
    property string lastSearch: ""               // "best" or "route"
    property string shownHaul: ""                // commodity of the route search on screen
    readonly property string listMode: lastSearch !== "" ? lastSearch : ((bridge.tradeRouteRows || []).length > 0 && (bridge.tradeBestRows || []).length === 0 ? "route" : "best")
    readonly property var liveRows: listMode === "best" ? (bridge.tradeBestRows || []) : (bridge.tradeRouteRows || [])
    property var rows: []
    property string rowsKey: ""
    onLiveRowsChanged: { var k = listMode + JSON.stringify(liveRows); if (k !== rowsKey) { rowsKey = k; rows = liveRows } }
    readonly property var liveLedger: bridge.tradeLedgerRows || []
    property var ledgerRows: []
    property string ledgerKey: ""
    onLiveLedgerChanged: { var k = JSON.stringify(liveLedger); if (k !== ledgerKey) { ledgerKey = k; ledgerRows = liveLedger } }
    property int selected: -1
    property int hovered: -1
    readonly property var card: hovered >= 0 && hovered < rows.length ? rows[hovered] : (selected >= 0 && selected < rows.length ? rows[selected] : null)
    readonly property var chosen: selected >= 0 && selected < rows.length ? rows[selected] : null
    onRowsChanged: { if (selected >= rows.length) selected = rows.length > 0 ? 0 : -1; if (selected < 0 && rows.length > 0) selected = 0 }

    // matches for the typed commodity (known names only, so the search never gets a typo)
    function haulMatches(t) {
        t = String(t || "").trim().toLowerCase()
        if (t === "") return []
        var all = bridge.tradeCommodityOptions || [], starts = [], has = []
        for (var i = 0; i < all.length; i++) {
            var n = String(all[i]).toLowerCase()
            if (n === t) return [String(all[i])]
            if (n.indexOf(t) === 0) starts.push(String(all[i])); else if (n.indexOf(t) > 0) has.push(String(all[i]))
        }
        return starts.concat(has)
    }
    function commitHaul() {
        var t = String(haul).trim()
        if (t === "" || /^any$/i.test(t)) { haul = ""; haulInput.text = ""; return }
        var m = haulMatches(t)
        if (m.length > 0) haul = m[0]
        haulInput.text = haul
    }
    function findRoutes() {
        commitHaul()
        selected = -1; hovered = -1
        if (haul === "") {
            lastSearch = "best"
            bridge.searchBestTrade(String(lyValues[startIdx]), String(lyValues[legIdx]), String(lsValues[lsIdx]), String(runsValues[runsIdx]),
                                   legalOnly ? "LEGAL ONLY" : "ALLOW RESTRICTED", rareGoods ? "ALLOW" : "EXCLUDE")
        } else {
            lastSearch = "route"
            shownHaul = haul
            bridge.searchTradeRoutesLeg(haul, String(lyValues[startIdx]), String(lyValues[legIdx]), String(lsValues[lsIdx]), String(runsValues[runsIdx]))
        }
    }
    // Colonization hands a commodity over: show its supply search on FIND A ROUTE
    function showSupplySearch(name) {
        haul = String(name || ""); haulInput.text = haul
        lastSearch = "route"; shownHaul = haul; selected = -1; hovered = -1
        tradeView = 0
    }
    function useChosen() {
        if (listMode === "best") bridge.useBestTradeIndex(selected)
        else bridge.useTradeRouteIndex(selected)
    }
    Timer { id: plotAfterUse; interval: 450; onTriggered: bridge.requestCommand("trade_buy") }
    Timer { id: showRunAfterUse; interval: 650; onTriggered: tr.tradeView = 1 }

    // default view: MY RUN while a run is active, otherwise FIND A ROUTE
    Component.onCompleted: tradeView = runActive ? 1 : 0
    onVisibleChanged: if (!visible) tradeView = runActive ? 1 : 0
    onRunActiveChanged: if (!visible) tradeView = runActive ? 1 : 0

    // ---------- shared deck helpers
    readonly property string bstate: String(bridge.bridgeState || "").toUpperCase()
    readonly property bool inControl: bridge.controlOwner !== "NONE" && bridge.controlOwner !== ""
    readonly property bool bindsReady: bridge.eliteControlsReady
    readonly property string bindsReason: String(bridge.eliteControlReason || "") !== "" ? String(bridge.eliteControlReason).toUpperCase() : "ELITE KEY BINDS NOT FOUND // SEE SETUP > CONTROLS"

    // ---------- layout rows
    readonly property real stripH: 88 * s
    readonly property real bodyY: stripH + g
    readonly property real deckH: height * 0.175
    readonly property real deckY: height - deckH
    readonly property real bodyH: deckY - g - bodyY

    // ================================================================= VIEW STRIP + ANNUNCIATORS
    Plate {
        id: viewStrip
        x: 0; y: 0; width: tr.width; height: tr.stripH
        screwSize: 11 * tr.s
        Text {
            x: 26 * tr.s; anchors.verticalCenter: parent.verticalCenter
            text: "VIEW"; color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: Math.max(8, 13 * tr.s); font.letterSpacing: 3 * tr.s
        }
        Row {
            id: views
            x: 82 * tr.s; y: 8 * tr.s
            spacing: 12 * tr.s
            Repeater {
                model: ["FIND A ROUTE", "MY RUN"]
                LitButton {
                    width: 300 * tr.s; height: tr.stripH - 18 * tr.s
                    title: modelData
                    on: tr.tradeView === index
                    onActivated: tr.tradeView = index
                }
            }
        }
        StatusPanel {
            id: annun
            x: views.x + views.width + 30 * tr.s; y: 6 * tr.s
            width: viewStrip.width - x - 22 * tr.s; height: tr.stripH - 12 * tr.s
            items: [
                    ["AUTO-PLOT ON", tr.runActive ? "a" : ""],
                    ["HOLD FULL", tr.holdFull ? "a" : ""],
                    ["HOLD EMPTY", tr.holdEmpty ? "a" : ""],
                    ["AT BUY STATION", tr.atBuy ? "a" : ""],
                    ["AT SELL STATION", tr.atSell ? "a" : ""],
                    ["RESTRICTED CARGO", tr.restricted ? "r" : ""],
                    ["SEARCHING", tr.searching ? "a" : ""]
                ]
        }
    }

    // ================================================================= FIND A ROUTE
    Item {
        id: findView
        visible: tr.tradeView === 0
        x: 0; y: tr.bodyY; width: tr.width; height: tr.bodyH
        readonly property real searchH: height * 0.255
        readonly property real listW: width * 0.625

        // ---------------------------------------------------- SEARCH strip
        Plate {
            id: searchPlate
            x: 0; y: 0; width: findView.width; height: findView.searchH
            screwSize: 12 * tr.s
            Dymo { x: 26 * tr.s; y: 12 * tr.s; text: "SEARCH" }
            readonly property real lab: Math.max(8, 13 * tr.s)
            readonly property real bw: 66 * tr.s
            readonly property real bh: Math.min(56 * tr.s, height * 0.3)
            readonly property real rowY: height * 0.40

            // WHAT TO HAUL: the one field you type into
            Text { x: 26 * tr.s; y: searchPlate.rowY - height - 8 * tr.s; text: "WHAT TO HAUL"; color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: searchPlate.lab; font.letterSpacing: 2 * tr.s }
            Bezel {
                id: haulBezel
                x: 18 * tr.s; y: searchPlate.rowY - 8 * tr.s
                width: searchPlate.width * 0.205; height: searchPlate.bh + 44 * tr.s
                pad: 8 * tr.s
                readonly property real fs: Math.max(14, 30 * tr.s)
                Rectangle {
                    id: haulField
                    x: 6 * tr.s; y: 4 * tr.s
                    width: haulBezel.width - haulBezel.pad * 2 - 12 * tr.s; height: Math.max(26, 46 * tr.s)
                    color: Theme.t("#0a7dff9c"); border.color: haulInput.activeFocus ? Theme.t("#807dff9c") : Theme.t("#337dff9c"); border.width: 1
                    TextInput {
                        id: haulInput
                        objectName: "tradeHaulInput"
                        x: 10 * tr.s; width: parent.width - 20 * tr.s; height: parent.height
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.ok; selectionColor: Theme.t("#2f7a45"); selectedTextColor: Theme.control
                        font.family: Theme.crtFont; font.pixelSize: haulBezel.fs; font.letterSpacing: 1.5 * tr.s; font.capitalization: Font.AllUppercase
                        clip: true; selectByMouse: true
                        cursorDelegate: Rectangle {
                            width: Math.max(6, 12 * tr.s); color: Theme.ok
                            visible: haulInput.activeFocus
                            SequentialAnimation on opacity { loops: Animation.Infinite; running: haulInput.activeFocus
                                NumberAnimation { to: 0; duration: 0 } PauseAnimation { duration: 530 } NumberAnimation { to: 0.9; duration: 0 } PauseAnimation { duration: 530 } }
                        }
                        onTextEdited: tr.haul = /^any$/i.test(String(text).trim()) ? "" : String(text).trim()
                        function takeFirst() {
                            tr.commitHaul()
                            focus = false
                            Theme.cue("tick")
                        }
                        Keys.onReturnPressed: takeFirst()
                        Keys.onEnterPressed: takeFirst()
                        Keys.onEscapePressed: focus = false
                    }
                    Text {
                        visible: !haulInput.activeFocus && haulInput.text === ""
                        x: 10 * tr.s; anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.StyledText
                        text: "ANY <font color='" + Theme.dimText + "'>// BEST OVERALL</font>"
                        color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: haulBezel.fs
                    }
                }
                Text {
                    x: 8 * tr.s; y: haulField.y + haulField.height + 4 * tr.s
                    width: haulField.width; elide: Text.ElideRight
                    text: tr.haul === "" ? "OR TYPE ONE, E.G. GOLD" : "PRESS FIND ROUTES // CLEAR THE FIELD FOR ANY"
                    color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(10, 20 * tr.s)
                }
            }

            // selector rows
            Row {
                id: selRow
                x: haulBezel.x + haulBezel.width + 34 * tr.s
                y: searchPlate.rowY
                spacing: 30 * tr.s
                Repeater {
                    model: [
                        ["START WITHIN (LY)", ["25", "50", "100", "200"], "HOW FAR TO YOUR FIRST STOP", 0],
                        ["JUMP LEG (LY)", ["25", "50", "100", "200"], "BUY STATION TO SELL STATION", 1],
                        ["STATION DISTANCE (LS)", ["1K", "2.5K", "5K", "10K"], "FROM THE ARRIVAL STAR", 2],
                        ["LASTS AT LEAST (RUNS)", ["1", "5", "10", "25"], "BEFORE PRICES DROP", 3]
                    ]
                    Item {
                        width: sel.width; height: searchPlate.bh
                        Text { y: -height - 8 * tr.s; text: modelData[0]; color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: searchPlate.lab; font.letterSpacing: 2 * tr.s }
                        SelectorRow {
                            id: sel
                            options: modelData[1]
                            buttonWidth: searchPlate.bw; buttonHeight: searchPlate.bh
                            currentIndex: [tr.startIdx, tr.legIdx, tr.lsIdx, tr.runsIdx][modelData[3]]
                            onPicked: (i) => {
                                if (modelData[3] === 0) tr.startIdx = i
                                else if (modelData[3] === 1) tr.legIdx = i
                                else if (modelData[3] === 2) tr.lsIdx = i
                                else tr.runsIdx = i
                            }
                        }
                        Text { y: searchPlate.bh + 6 * tr.s; text: modelData[2]; color: Theme.dimText; font.family: Theme.labelFont; font.pixelSize: Math.max(7, 11 * tr.s); font.letterSpacing: 1.5 * tr.s }
                    }
                }
                // divider
                Rectangle { width: 4 * tr.s; height: searchPlate.bh + 30 * tr.s; y: -22 * tr.s; radius: 2 * tr.s; color: "#0b0b0a"; border.color: "#3e3b32"; border.width: 1 }
                Repeater {
                    model: [["LEGAL ONLY", "NO RESTRICTED GOODS", 0], ["RARE GOODS", "SPECIALS", 1]]
                    Item {
                        width: pair.width; height: searchPlate.bh
                        Text { y: -height - 8 * tr.s; text: modelData[0]; color: Theme.plateText; opacity: tr.haul === "" ? 1 : 0.45; font.family: Theme.labelFont; font.pixelSize: searchPlate.lab; font.letterSpacing: 2 * tr.s }
                        OnOffPair {
                            id: pair
                            buttonWidth: searchPlate.bw * 0.95; buttonHeight: searchPlate.bh
                            on: modelData[2] === 0 ? tr.legalOnly : tr.rareGoods
                            available: tr.haul === ""
                            unavailableReason: "ONLY FOR ANY // THESE PICK WHICH GOODS TO SEARCH, AND YOU CHOSE " + tr.up(tr.haul)
                            onChanged: (v) => { if (modelData[2] === 0) tr.legalOnly = v; else tr.rareGoods = v }
                            onDenied: (r) => tr.denied(modelData[0] + " NOT USED", r)
                        }
                        Text { y: searchPlate.bh + 6 * tr.s; text: modelData[1]; visible: tr.haul === ""; color: Theme.dimText; font.family: Theme.labelFont; font.pixelSize: Math.max(7, 11 * tr.s); font.letterSpacing: 1.5 * tr.s }
                    }
                }
            }
            // a typed commodity switches these two off: say so right under them
            Text {
                visible: tr.haul !== ""
                x: selRow.x + selRow.width - width; y: selRow.y + searchPlate.bh + 6 * tr.s
                text: "OFF FOR " + tr.up(tr.haul) + " // ONLY USED WHEN SEARCHING ANY"
                color: Theme.info; font.family: Theme.labelFont; font.pixelSize: Math.max(8, 12 * tr.s); font.letterSpacing: 1.5 * tr.s
            }
        }

        // ---------------------------------------------------- BEST ROUTES
        Plate {
            id: routesPlate
            x: 0; y: findView.searchH + tr.g; width: findView.listW; height: findView.height - y
            screwSize: 13 * tr.s
            Dymo { x: 26 * tr.s; y: 14 * tr.s; text: tr.listMode === "best" ? "BEST ROUTES // NEAREST GOOD MONEY FIRST" : "BEST ROUTES // " + tr.up(tr.shownHaul === "" ? "ONE COMMODITY" : tr.shownHaul) }
            Bezel {
                id: rBezel
                x: 16 * tr.s; y: 50 * tr.s
                width: parent.width - 32 * tr.s; height: parent.height - 66 * tr.s
                pad: 12 * tr.s
                readonly property real iw: width - pad * 2
                readonly property real ih: height - pad * 2
                readonly property real fs: Math.max(11, 23 * tr.s)
                // column edges (fractions): # | commodity | buy in | sell in | profit (right) | lasts (right) | leg (right)
                readonly property var cx: [0.0, 0.055, 0.34, 0.54, 0.83, 0.915, 1.0]
                Text {
                    x: 20 * tr.s; y: 10 * tr.s; width: rBezel.iw * 0.62; elide: Text.ElideRight
                    text: tr.searching ? "SEARCHING THE MARKETS NEAR YOU..." : tr.up(tr.listMode === "best" ? bridge.tradeBestStatus : bridge.tradeRouteStatus)
                    color: tr.searching ? Theme.info : Theme.ok
                    font.family: Theme.crtFont; font.pixelSize: rBezel.fs * 0.85
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 20 * tr.s; y: 10 * tr.s
                    text: "HOVER TO PREVIEW // CLICK TO PICK"; color: Theme.dimText
                    font.family: Theme.crtFont; font.pixelSize: rBezel.fs * 0.72
                }
                Item {
                    id: rHead
                    x: 20 * tr.s; y: 44 * tr.s; width: rBezel.iw - 40 * tr.s - 26 * tr.s; height: rBezel.fs
                    Repeater {
                        model: [["#", 0, 0], ["COMMODITY", 1, 0], ["BUY IN", 2, 0], ["SELL IN", 3, 0], ["PROFIT / LOAD", 4, 1], ["LASTS", 5, 1], ["LEG LY", 6, 1]]
                        Text {
                            x: modelData[2] === 0 ? rHead.width * rBezel.cx[modelData[1]] : rHead.width * rBezel.cx[modelData[1]] - width
                            text: modelData[0]; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: rBezel.fs * 0.72
                        }
                    }
                }
                PhosphorList {
                    id: routeList
                    x: 20 * tr.s; y: rHead.y + rHead.height + 6 * tr.s
                    width: rBezel.iw - 40 * tr.s; height: rBezel.ih - y - 6 * tr.s
                    fontSize: rBezel.fs
                    model: tr.rows
                    delegate: Item {
                        required property var modelData
                        required property int index
                        width: routeList.list.width - (routeList.overflow ? 0 : 26 * tr.s)
                        height: routeList.fontSize * 1.32
                        readonly property bool picked: index === tr.selected
                        readonly property bool bad: modelData.knownProhibited === true
                        readonly property string comm: tr.listMode === "best" ? String(modelData.commodity) : tr.shownHaul
                        Rectangle { anchors.fill: parent; visible: parent.picked || rowPress.containsMouse
                                    color: parent.picked ? Theme.t("#2a7dff9c") : Theme.t("#127dff9c"); border.color: parent.picked ? Theme.t("#807dff9c") : "transparent"; border.width: 1 }
                        Text { x: 4 * tr.s; anchors.verticalCenter: parent.verticalCenter; text: (parent.picked ? ">" : " ") + ("0" + (index + 1)).slice(-2); color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: routeList.fontSize }
                        Row {
                            x: parent.width * rBezel.cx[1]; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width * (rBezel.cx[2] - rBezel.cx[1]) - 10 * tr.s
                            spacing: 8 * tr.s
                            Text { width: Math.min(implicitWidth, parent.width - (badge.visible ? badge.width + 8 * tr.s : 0)); elide: Text.ElideRight
                                   text: tr.up(comm); color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: routeList.fontSize }
                            Text { id: badge; visible: bad; anchors.verticalCenter: parent.verticalCenter; text: modelData.rareGood ? "RARE // RESTRICTED" : "RESTRICTED"
                                   color: Theme.info; font.family: Theme.labelFont; font.pixelSize: routeList.fontSize * 0.55; font.letterSpacing: 1 * tr.s }
                        }
                        Text { x: parent.width * rBezel.cx[2]; width: parent.width * (rBezel.cx[3] - rBezel.cx[2]) - 10 * tr.s; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter
                               text: tr.up(modelData.buySystem); color: Theme.phosphor; opacity: 0.9; font.family: Theme.crtFont; font.pixelSize: routeList.fontSize }
                        Text { x: parent.width * rBezel.cx[3]; width: parent.width * (rBezel.cx[4] - rBezel.cx[3]) - 130 * tr.s; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter
                               text: tr.up(modelData.sellSystem); color: Theme.phosphor; opacity: 0.9; font.family: Theme.crtFont; font.pixelSize: routeList.fontSize }
                        Text { x: parent.width * rBezel.cx[4] - width; anchors.verticalCenter: parent.verticalCenter
                               text: tr.cr(modelData.profitPerLoad); color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: routeList.fontSize }
                        Text { x: parent.width * rBezel.cx[5] - width; anchors.verticalCenter: parent.verticalCenter
                               text: tr.lasts(modelData.sustainableLoads); color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: routeList.fontSize }
                        Text { anchors.right: parent.right; anchors.rightMargin: 6 * tr.s; anchors.verticalCenter: parent.verticalCenter
                               text: Number(modelData.legLy || 0).toFixed(1); color: Number(modelData.legLy) > tr.lyValues[tr.legIdx] ? Theme.info : Theme.phosphor
                               font.family: Theme.crtFont; font.pixelSize: routeList.fontSize }
                        PressArea { id: rowPress; anchors.fill: parent
                                    onContainsMouseChanged: tr.hovered = containsMouse ? index : (tr.hovered === index ? -1 : tr.hovered)
                                    onActivated: { Theme.cue("tick"); tr.selected = index } }
                    }
                }
                Text {
                    visible: tr.rows.length === 0
                    x: 20 * tr.s; y: routeList.y + routeList.height * 0.35; width: rBezel.iw - 40 * tr.s; horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: tr.searching ? "SEARCHING THE MARKETS NEAR YOU..." : "NO ROUTES YET // SET YOUR SEARCH ABOVE AND PRESS FIND ROUTES"
                    color: tr.searching ? Theme.info : Theme.dimText; font.family: Theme.crtFont; font.pixelSize: rBezel.fs * 1.1
                }
            }
        }

        // ---------------------------------------------------- ROUTE CARD
        Plate {
            id: cardPlate
            x: findView.listW + tr.g; y: routesPlate.y; width: findView.width - x; height: routesPlate.height
            screwSize: 13 * tr.s
            Dymo { x: 26 * tr.s; y: 14 * tr.s; text: "ROUTE CARD" }
            Bezel {
                id: cBezel
                x: 16 * tr.s; y: 50 * tr.s
                width: parent.width - 32 * tr.s; height: parent.height - 66 * tr.s
                pad: 12 * tr.s
                readonly property real iw: width - pad * 2
                readonly property real ih: height - pad * 2
                readonly property real fs: Math.max(11, 22 * tr.s)
                readonly property var c: tr.card
                readonly property string comm: c ? (tr.listMode === "best" ? String(c.commodity) : tr.shownHaul) : ""
                readonly property bool here: c !== null && tr.norm(bridge.station) === tr.norm(c.buyStation)
                readonly property bool hereSys: c !== null && tr.norm(bridge.system) === tr.norm(c.buySystem)
                Text {
                    visible: cBezel.c === null
                    anchors.centerIn: parent; width: cBezel.iw * 0.8; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                    text: "PICK A ROUTE IN THE LIST // ITS DETAILS SHOW HERE"
                    color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: cBezel.fs * 1.1
                }
                Column {
                    visible: cBezel.c !== null
                    x: 18 * tr.s; y: 10 * tr.s; width: cBezel.iw - 36 * tr.s
                    spacing: 6 * tr.s
                    Text {
                        text: cBezel.c ? tr.up(cBezel.comm) + "  //  ROUTE " + ("0" + ((tr.hovered >= 0 ? tr.hovered : tr.selected) + 1)).slice(-2) + (tr.hovered >= 0 && tr.hovered !== tr.selected ? "  //  PREVIEW" : "") : ""
                        color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: cBezel.fs * 0.8
                    }
                    // profit per load, the big number
                    Rectangle {
                        width: parent.width; height: profitTxt.height + 30 * tr.s
                        color: Theme.t("#0c7dff9c"); border.color: Theme.t("#337dff9c"); border.width: 1
                        Text { x: 12 * tr.s; y: 6 * tr.s; text: "PROFIT PER LOAD"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: cBezel.fs * 0.75 }
                        Text {
                            id: profitTxt
                            x: 12 * tr.s; y: 22 * tr.s
                            textFormat: Text.StyledText
                            text: cBezel.c ? tr.num(cBezel.c.profitPerLoad) + "<font size='2'> CR</font>" : ""
                            color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: cBezel.fs * 2.4
                        }
                    }
                    Row {
                        width: parent.width; spacing: 8 * tr.s
                        Repeater {
                            model: cBezel.c ? [
                                ["PER TON", tr.num(cBezel.c.profitPerT), Theme.phosphor],
                                ["LASTS", tr.lasts(cBezel.c.sustainableLoads) + " RUNS", Theme.ok],
                                ["LEGAL", cBezel.c.knownProhibited === true ? "NO" : (tr.listMode === "best" ? "YES" : "-"), cBezel.c.knownProhibited === true ? Theme.info : Theme.ok]
                            ] : []
                            Rectangle {
                                width: (parent.width - 16 * tr.s) / 3; height: cBezel.fs * 2.3
                                color: Theme.t("#087dff9c"); border.color: Theme.t("#2a7dff9c"); border.width: 1
                                Text { x: 8 * tr.s; y: 4 * tr.s; text: modelData[0]; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: cBezel.fs * 0.7 }
                                Text { x: 8 * tr.s; anchors.bottom: parent.bottom; anchors.bottomMargin: 4 * tr.s; text: modelData[1]; color: modelData[2]; font.family: Theme.crtFont; font.pixelSize: cBezel.fs * 1.05 }
                            }
                        }
                    }
                    Item { width: 1; height: 4 * tr.s }
                    // BUY stop
                    Item {
                        width: parent.width; height: cBezel.fs * 3.2
                        Text {
                            textFormat: Text.StyledText
                            text: "BUY" + (cBezel.here ? "  //  <font color='" + Theme.info + "'>YOU ARE HERE</font>" : (cBezel.hereSys ? "  //  IN THIS SYSTEM" : ""))
                            color: Theme.info; font.family: Theme.crtFont; font.pixelSize: cBezel.fs * 0.8
                        }
                        Text { anchors.right: parent.right; text: cBezel.c ? tr.up(cBezel.c.buySystem) : ""; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: cBezel.fs * 0.8 }
                        Text { y: cBezel.fs * 0.95; width: parent.width; elide: Text.ElideRight; text: cBezel.c ? tr.up(cBezel.c.buyStation) : ""; color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: cBezel.fs * 1.2 }
                        Text { y: cBezel.fs * 2.2; text: cBezel.c ? tr.num(cBezel.c.buyPrice) + " CR/T" : ""; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: cBezel.fs * 0.8 }
                        Text { anchors.right: parent.right; y: cBezel.fs * 2.2; text: cBezel.c ? "SUPPLY " + tr.num(cBezel.c.supply) + " T" : ""
                               color: cBezel.c && Number(cBezel.c.supply) < tr.load ? Theme.info : Theme.ok; font.family: Theme.crtFont; font.pixelSize: cBezel.fs * 0.85 }
                    }
                    // leg
                    Text {
                        x: 14 * tr.s
                        text: cBezel.c ? "▼ " + Number(cBezel.c.legLy || 0).toFixed(1) + " LY  //  BUY STATION " + tr.num(cBezel.c.buyLs) + " LS FROM STAR" : ""
                        color: Theme.phosphor; opacity: 0.85; font.family: Theme.crtFont; font.pixelSize: cBezel.fs * 0.82
                    }
                    // SELL stop
                    Item {
                        width: parent.width; height: cBezel.fs * 3.2
                        Text { text: "SELL"; color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: cBezel.fs * 0.8 }
                        Text { anchors.right: parent.right; text: cBezel.c ? tr.up(cBezel.c.sellSystem) : ""; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: cBezel.fs * 0.8 }
                        Text { y: cBezel.fs * 0.95; width: parent.width; elide: Text.ElideRight; text: cBezel.c ? tr.up(cBezel.c.sellStation) : ""; color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: cBezel.fs * 1.2 }
                        Text { y: cBezel.fs * 2.2; text: cBezel.c ? tr.num(cBezel.c.sellPrice) + " CR/T  //  " + tr.num(cBezel.c.sellLs) + " LS" : ""; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: cBezel.fs * 0.8 }
                        Text { anchors.right: parent.right; y: cBezel.fs * 2.2; text: cBezel.c ? "DEMAND " + tr.num(cBezel.c.demand) + " T" : ""
                               color: cBezel.c && Number(cBezel.c.demand) < tr.load ? Theme.info : Theme.ok; font.family: Theme.crtFont; font.pixelSize: cBezel.fs * 0.85 }
                    }
                }
            }
        }
    }

    // commodity pick-list under WHAT TO HAUL (on top of the route list while you type)
    Rectangle {
        id: haulPicks
        readonly property var matches: tr.haulMatches(haulInput.text)
        readonly property real fs: Math.max(12, 24 * tr.s)
        visible: findView.visible && haulInput.activeFocus && matches.length > 0 && !(matches.length === 1 && String(matches[0]).toLowerCase() === String(haulInput.text).trim().toLowerCase())
        z: 20
        x: haulBezel.x + 6 * tr.s; y: tr.bodyY + haulBezel.y + haulBezel.height - 6 * tr.s
        width: haulBezel.width * 1.15; height: pickCol.height + 12 * tr.s
        color: Theme.t("#f0060d08"); border.color: Theme.t("#807dff9c"); border.width: 1
        Column {
            id: pickCol
            x: 6 * tr.s; y: 6 * tr.s; width: parent.width - 12 * tr.s
            Repeater {
                model: haulPicks.matches.slice(0, 8)
                Rectangle {
                    width: pickCol.width; height: haulPicks.fs * 1.35
                    color: pickArea.containsMouse || index === 0 ? Theme.t("#227dff9c") : "transparent"
                    Text { x: 8 * tr.s; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 16 * tr.s; elide: Text.ElideRight
                           text: (index === 0 ? "> " : "  ") + tr.up(modelData); color: index === 0 ? Theme.ok : Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: haulPicks.fs }
                    PressArea { id: pickArea; anchors.fill: parent; onActivated: { tr.haul = modelData; haulInput.text = modelData; haulInput.focus = false; Theme.cue("tick") } }
                }
            }
            Text { visible: haulPicks.matches.length > 8; x: 8 * tr.s; text: "+" + (haulPicks.matches.length - 8) + " MORE // KEEP TYPING"
                   color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: haulPicks.fs * 0.8 }
        }
    }

    // ================================================================= MY RUN
    Item {
        id: runView
        visible: tr.tradeView === 1
        x: 0; y: tr.bodyY; width: tr.width; height: tr.bodyH
        readonly property real topH: height * 0.585
        readonly property real loopW: width * 0.64

        // ---------------------------------------------------- TRADE LOOP (cool factor)
        Plate {
            id: loopPanel
            x: 0; y: 0; width: runView.loopW; height: runView.topH
            screwSize: 13 * tr.s
            Dymo { x: 26 * tr.s; y: 14 * tr.s; text: tr.hasLoop ? "TRADE LOOP // " + tr.up(tr.commodity) : "TRADE LOOP" }
            Bezel {
                id: lBezel
                x: 16 * tr.s; y: 50 * tr.s
                width: parent.width - 32 * tr.s; height: parent.height - 66 * tr.s
                pad: 12 * tr.s
                readonly property real iw: width - pad * 2
                readonly property real ih: height - pad * 2
                readonly property real fs: Math.max(11, 22 * tr.s)
                readonly property real bx: iw * 0.2
                readonly property real sx: iw * 0.8
                readonly property real cy: ih * 0.44
                readonly property real r: Math.min(ih * 0.17, iw * 0.07)
                // which leg is live: outbound (to SELL) or return (to BUY)
                readonly property bool outbound: tr.atBuy ? true : (tr.atSell ? false : tr.nextSide === "SELL")
                readonly property bool transit: tr.hasLoop && !tr.atBuy && !tr.atSell
                property real march: 0
                NumberAnimation on march { from: 0; to: 1; duration: 1400; loops: Animation.Infinite; running: tr.visible && tr.tradeView === 1 && tr.hasLoop && tr.runActive }
                Canvas {
                    property bool themeAmber: Theme.amber   // LAB themes: repaint when the screen theme changes
                    onThemeAmberChanged: requestPaint()
                    id: loopCanvas
                    anchors.fill: parent
                    property real m: Math.floor(lBezel.march * 24) / 24
                    onMChanged: requestPaint()
                    onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
                    Connections { target: lBezel; function onOutboundChanged() { loopCanvas.requestPaint() } }
                    Connections { target: tr; function onHasLoopChanged() { loopCanvas.requestPaint() } }
                    onPaint: {
                        var c = getContext("2d"); c.reset()
                        var b = lBezel, x0 = b.bx + b.r * 1.25, x1 = b.sx - b.r * 1.25, y = b.cy
                        var top = b.ih * 0.02, bot = b.ih * 0.80
                        function leg(isOut) {
                            var live = tr.hasLoop && (isOut === b.outbound)
                            c.setLineDash(live ? [10 * tr.s, 8 * tr.s] : [5 * tr.s, 9 * tr.s])
                            c.lineDashOffset = live ? -b.march * 18 * tr.s : 0
                            c.strokeStyle = live ? "rgba(" + Theme.rgb("125,255,156") + ",0.9)" : "rgba(" + Theme.rgb("125,255,156") + ",0.38)"
                            c.lineWidth = live ? Math.max(2, 3 * tr.s) : Math.max(1, 2 * tr.s)
                            c.beginPath()
                            if (isOut) { c.moveTo(x0, y - b.r * 0.4); c.quadraticCurveTo((x0 + x1) / 2, top, x1, y - b.r * 0.4) }
                            else { c.moveTo(x1, y + b.r * 0.4); c.quadraticCurveTo((x0 + x1) / 2, bot, x0, y + b.r * 0.4) }
                            c.stroke()
                            // arrowhead at the far end
                            c.setLineDash([])
                            var ax = isOut ? x1 : x0, ay = isOut ? y - b.r * 0.4 : y + b.r * 0.4
                            var dir = isOut ? 1 : -1, k = 14 * tr.s
                            c.beginPath()
                            c.moveTo(ax - dir * k, ay + (isOut ? -k * 0.75 : k * 0.75))
                            c.lineTo(ax, ay)
                            c.lineTo(ax - dir * k * 1.15, ay + (isOut ? k * 0.15 : -k * 0.15))
                            c.stroke()
                        }
                        leg(true); leg(false)
                    }
                }
                Text {
                    x: lBezel.iw * 0.5 - width / 2; y: lBezel.ih * 0.075
                    text: (tr.hasLoop && bridge.tradeLegLy > 0 ? bridge.tradeLegLy.toFixed(1) + " LY  //  " : "") + "OUTBOUND LEG ▶"
                    color: lBezel.outbound && tr.hasLoop ? Theme.ok : Theme.dimText; font.family: Theme.crtFont; font.pixelSize: lBezel.fs
                }
                Text {
                    x: lBezel.iw * 0.5 - width / 2; y: lBezel.ih * 0.515
                    text: "◀ RETURN LEG"
                    color: !lBezel.outbound && tr.hasLoop ? Theme.ok : Theme.dimText; font.family: Theme.crtFont; font.pixelSize: lBezel.fs * 0.85
                }
                // stations
                StationGlyph { side: "BUY"; cx: lBezel.bx; name: tr.buyStation; sys: tr.buySystem; here: tr.atBuy }
                StationGlyph { side: "SELL"; cx: lBezel.sx; name: tr.sellStation; sys: tr.sellSystem; here: tr.atSell }
                // cargo pods: how full the hold is, riding with the ship
                Row {
                    id: pods
                    spacing: 5 * tr.s
                    readonly property int lit: tr.cap > 0 ? Math.round(Math.min(1, bridge.cargoUsed / tr.cap) * 4) : 0
                    readonly property real pw: lBezel.r * 0.42
                    visible: tr.hasLoop
                    x: lBezel.transit ? lBezel.iw * 0.5 - width / 2 : (tr.atSell ? lBezel.sx + lBezel.r * 1.75 : lBezel.bx - lBezel.r * 1.75 - width)
                    y: lBezel.transit ? (lBezel.outbound ? lBezel.ih * 0.17 : lBezel.ih * 0.585) : lBezel.cy - pw * 0.45
                    Behavior on x { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                    Repeater {
                        model: 4
                        Rectangle {
                            width: pods.pw; height: pods.pw * 0.9; radius: 2 * tr.s
                            readonly property bool on: (tr.atSell ? 3 - index : index) < pods.lit
                            color: on ? Theme.t("#9f7dff9c") : Theme.t("#147dff9c"); border.color: on ? Theme.ok : Theme.t("#447dff9c"); border.width: 1
                        }
                    }
                }
                // centre readout
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: lBezel.ih * 0.74
                    spacing: 2 * tr.s
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: tr.cycleText
                           color: tr.hasLoop ? Theme.ok : Theme.dimText; font.family: Theme.crtFont; font.pixelSize: lBezel.fs * 1.75; font.letterSpacing: 1.5 * tr.s }
                    Text { anchors.horizontalCenter: parent.horizontalCenter
                           text: tr.nextText
                           color: Theme.info; font.family: Theme.crtFont; font.pixelSize: lBezel.fs * 0.95 }
                }
            }
        }

        // ---------------------------------------------------- EARNINGS
        Plate {
            id: earnPanel
            x: runView.loopW + tr.g; y: 0; width: runView.width - x; height: runView.topH
            screwSize: 13 * tr.s
            Dymo { x: 26 * tr.s; y: 14 * tr.s; text: "EARNINGS" }
            readonly property real lab: Math.max(8, 13 * tr.s)
            readonly property real cellW: Math.min(52 * tr.s, (width - 120 * tr.s) / 8.6, (height * 0.56 - 120 * tr.s) / 2.6)
            Column {
                id: earnCol
                x: 26 * tr.s; y: 58 * tr.s
                spacing: 8 * tr.s
                Text { text: "MADE THIS TRIP  //  " + tr.up(bridge.tradeTripSince); color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: earnPanel.lab; font.letterSpacing: 2 * tr.s }
                Row {
                    spacing: 8 * tr.s
                    Odometer { value: bridge.tradeTripProfit; digits: 8; cellW: earnPanel.cellW }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "CR"; color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: earnPanel.cellW * 0.42 }
                }
                readonly property bool est: tr.runActive && tr.target > 0
                Text { text: earnCol.est ? "STILL TO EARN (EST.)" : "THIS TRIP"; color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: earnPanel.lab; font.letterSpacing: 2 * tr.s }
                Row {
                    spacing: 8 * tr.s
                    Odometer { visible: earnCol.est; value: bridge.tradeEstimatedRemainingProfit; digits: 8; cellW: earnPanel.cellW }
                    Text { visible: earnCol.est; anchors.verticalCenter: parent.verticalCenter; text: "CR"; color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: earnPanel.cellW * 0.42 }
                    Text { visible: !earnCol.est; height: earnPanel.cellW * 1.3; verticalAlignment: Text.AlignVCenter
                           text: bridge.tradeTripSales + (bridge.tradeTripSales === 1 ? " SALE" : " SALES") + "  //  " + tr.num(bridge.tradeTripTons) + " T SOLD  //  " + tr.tripCycles + (tr.tripCycles === 1 ? " CYCLE" : " CYCLES")
                           color: Theme.plateText; opacity: 0.85; font.family: Theme.labelFont; font.pixelSize: earnPanel.cellW * 0.44; font.letterSpacing: 2 * tr.s }
                }
            }
            Bezel {
                id: eBezel
                x: 16 * tr.s; y: earnCol.y + earnCol.height + 14 * tr.s
                width: parent.width - 32 * tr.s; height: parent.height - y - 16 * tr.s
                pad: 10 * tr.s
                readonly property real iw: width - pad * 2
                readonly property real ih: height - pad * 2
                readonly property real fs: Math.max(11, 22 * tr.s)
                Column {
                    x: 16 * tr.s; y: 8 * tr.s; width: eBezel.iw - 32 * tr.s
                    spacing: eBezel.ih * 0.04
                    Item { width: parent.width; height: eBezel.fs
                        Text { text: "PER CYCLE"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: eBezel.fs }
                        Text { anchors.right: parent.right; text: bridge.tradeEstimatedProfitCycle > 0 ? tr.cr(bridge.tradeEstimatedProfitCycle) : "AFTER YOUR FIRST BUY AND SELL"
                               color: bridge.tradeEstimatedProfitCycle > 0 ? Theme.ok : Theme.dimText; font.family: Theme.crtFont; font.pixelSize: eBezel.fs } }
                    Item { width: parent.width; height: eBezel.fs
                        Text { text: "CYCLES"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: eBezel.fs }
                        Text { anchors.right: parent.right; text: tr.runActive && tr.target > 0 ? "AUTO-PLOT " + tr.done + " OF " + tr.target : tr.tripCycles + " THIS TRIP"
                               color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: eBezel.fs } }
                    // cycle blocks
                    Row {
                        id: blocks
                        width: parent.width; height: eBezel.fs * 0.9
                        spacing: 3 * tr.s
                        readonly property bool auto: tr.runActive && tr.target > 0
                        readonly property int n: auto ? Math.min(tr.target, 25) : 10
                        readonly property int lit: auto ? Math.round(Math.min(tr.done, tr.target) * n / Math.max(1, tr.target)) : (tr.tripCycles % 10)
                        Repeater {
                            model: blocks.n
                            Rectangle {
                                width: (blocks.width - blocks.spacing * (blocks.n - 1)) / blocks.n; height: blocks.height
                                readonly property bool on: index < blocks.lit
                                readonly property bool now: tr.runActive && index === blocks.lit
                                color: on ? Theme.t("#a07dff9c") : (now ? Theme.t("#55ffb84d") : Theme.t("#127dff9c")); border.color: on ? Theme.ok : (now ? Theme.info : Theme.t("#337dff9c")); border.width: 1
                            }
                        }
                    }
                    Item { width: parent.width; height: eBezel.fs
                        Text { text: "LAST SALE"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: eBezel.fs }
                        Text { anchors.right: parent.right; text: tr.up(bridge.tradeLastSale)
                               color: String(bridge.tradeLastSale).charAt(0) === "+" ? Theme.ok : (String(bridge.tradeLastSale).charAt(0) === "-" && String(bridge.tradeLastSale) !== "-" ? Theme.bad : Theme.dimText)
                               font.family: Theme.crtFont; font.pixelSize: eBezel.fs } }
                }
            }
        }

        // ---------------------------------------------------- RUN SETTINGS
        Plate {
            id: settingsPanel
            x: 0; y: runView.topH + tr.g; width: runView.width * 0.275; height: runView.height - y
            screwSize: 12 * tr.s
            Dymo { x: 26 * tr.s; y: 14 * tr.s; text: "AUTO-PLOT" }
            readonly property real lab: Math.max(9, 14 * tr.s)
            readonly property real bw: Math.min(62 * tr.s, (width - 52 * tr.s - 30 * tr.s) / 6)
            readonly property real bh: Math.min(44 * tr.s, height * 0.16)
            Column {
                x: 26 * tr.s; y: 58 * tr.s; width: parent.width - 52 * tr.s
                spacing: 8 * tr.s
                Row {
                    spacing: 16 * tr.s
                    OnOffPair {
                        id: autoPlot
                        buttonWidth: settingsPanel.bw * 1.1; buttonHeight: settingsPanel.bh
                        on: tr.runActive
                        available: tr.hasLoop
                        unavailableReason: "NO LOOP SET // PICK ONE IN FIND A ROUTE"
                        onChanged: (v) => { if (v) tr.startRun(); else bridge.requestCommand("trade_pause") }
                        onDenied: (r) => tr.denied("AUTO-PLOT UNAVAILABLE", r)
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; width: settingsPanel.width - autoPlot.width - 90 * tr.s; wrapMode: Text.WordWrap
                           text: "PLOTS THE NEXT LEG ONCE YOU'RE CLEAR OF THE STATION"
                           color: Theme.plateText; opacity: 0.8; font.family: Theme.labelFont; font.pixelSize: settingsPanel.lab * 0.85; font.letterSpacing: 1 * tr.s }
                }
                Text { text: "STOP AUTO-PLOT AFTER (CYCLES)"; color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: settingsPanel.lab; font.letterSpacing: 2 * tr.s }
                SelectorRow {
                    options: tr.runLabels
                    buttonWidth: settingsPanel.bw; buttonHeight: settingsPanel.bh
                    currentIndex: tr.runLengthIndex
                    onPicked: (i) => tr.setRunLength(i)
                }
                Item { width: 1; height: 4 * tr.s }
                Text { text: "HOLD"; color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: settingsPanel.lab; font.letterSpacing: 2 * tr.s }
                Rectangle {
                    width: parent.width; height: 22 * tr.s
                    color: Theme.t("#060a07"); border.color: "#3e3b32"; border.width: 1
                    Rectangle {
                        x: 2; y: 2; height: parent.height - 4
                        width: tr.cap > 0 ? (parent.width - 4) * Math.min(1, bridge.cargoUsed / tr.cap) : 0
                        color: tr.holdFull ? Theme.ok : Theme.info; opacity: 0.85
                        Behavior on width { NumberAnimation { duration: 400 } }
                    }
                }
                Text { width: parent.width; elide: Text.ElideRight
                       text: tr.num(bridge.cargoUsed) + " / " + (tr.cap > 0 ? tr.num(tr.cap) : "?") + " T // " + (bridge.cargoCapacity > 0 ? "READ FROM YOUR SHIP" : "SHIP NOT REPORTING")
                       color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: settingsPanel.lab * 0.9; font.letterSpacing: 1 * tr.s }
            }
        }

        // ---------------------------------------------------- THIS MARKET
        Plate {
            id: marketPanel
            x: settingsPanel.width + tr.g; y: settingsPanel.y; width: runView.width * 0.29; height: settingsPanel.height
            screwSize: 12 * tr.s
            Dymo { x: 26 * tr.s; y: 14 * tr.s; text: "THIS MARKET" }
            Bezel {
                id: mBezel
                x: 16 * tr.s; y: 50 * tr.s
                width: parent.width - 32 * tr.s; height: parent.height - 66 * tr.s
                pad: 10 * tr.s
                readonly property real iw: width - pad * 2
                readonly property real fs: Math.max(11, 21 * tr.s)
                readonly property bool has: String(bridge.tradeMarketStation) !== "-"
                readonly property bool sellStop: tr.norm(bridge.tradeMarketStation) === tr.norm(tr.sellStation)
                readonly property bool buyStop: tr.norm(bridge.tradeMarketStation) === tr.norm(tr.buyStation)
                Text {
                    visible: !mBezel.has
                    anchors.centerIn: parent; width: mBezel.iw * 0.85; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                    text: "NO MARKET DATA YET // DOCK AND OPEN THE COMMODITIES MARKET"
                    color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: mBezel.fs
                }
                Column {
                    visible: mBezel.has
                    x: 14 * tr.s; y: 8 * tr.s; width: mBezel.iw - 28 * tr.s
                    spacing: 4 * tr.s
                    Text { width: parent.width; elide: Text.ElideRight
                           text: tr.up(bridge.tradeMarketStation) + (mBezel.buyStop ? "  //  BUY STOP" : (mBezel.sellStop ? "  //  SELL STOP" : ""))
                           color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: mBezel.fs * 0.82 }
                    Repeater {
                        model: [
                            [tr.up(tr.commodity === "-" ? "COMMODITY" : tr.commodity) + (mBezel.sellStop ? " SELLS FOR" : " PRICE"),
                             (mBezel.sellStop ? bridge.tradeMarketSell : bridge.tradeMarketBuy) > 0 ? tr.num(mBezel.sellStop ? bridge.tradeMarketSell : bridge.tradeMarketBuy) + " CR/T" : "NOT TRADED HERE", Theme.ok],
                            [mBezel.sellStop ? "DEMAND" : "STOCK", tr.num(mBezel.sellStop ? bridge.tradeMarketDemand : bridge.tradeMarketStock) + " T",
                             (mBezel.sellStop ? bridge.tradeMarketDemand : bridge.tradeMarketStock) < tr.load ? Theme.info : Theme.ok],
                            ["YOUR HOLD", tr.num(tr.aboard) + " / " + tr.num(tr.load) + " T" + (tr.atBuy && tr.aboard < tr.load ? "  //  BUY NOW" : (tr.atSell && tr.aboard > 0 ? "  //  SELL NOW" : "")),
                             (tr.atBuy && tr.aboard < tr.load) || (tr.atSell && tr.aboard > 0) ? Theme.info : Theme.phosphor]
                        ]
                        Item { width: parent.width; height: mBezel.fs * 1.45
                            Text { anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.5; elide: Text.ElideRight
                                   text: modelData[0]; color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: mBezel.fs * 1.05 }
                            Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                   text: modelData[1]; color: modelData[2]; font.family: Theme.crtFont; font.pixelSize: mBezel.fs * 1.05 } }
                    }
                }
            }
        }

        // ---------------------------------------------------- TRADE LEDGER
        Plate {
            id: ledgerPanel
            x: marketPanel.x + marketPanel.width + tr.g; y: settingsPanel.y; width: runView.width - x; height: settingsPanel.height
            screwSize: 12 * tr.s
            Dymo { x: 26 * tr.s; y: 14 * tr.s; text: "TRADE LEDGER" }
            Bezel {
                id: ldBezel
                x: 16 * tr.s; y: 50 * tr.s
                width: parent.width - 32 * tr.s; height: parent.height - 66 * tr.s
                pad: 10 * tr.s
                readonly property real iw: width - pad * 2
                readonly property real ih: height - pad * 2
                readonly property real fs: Math.max(11, 20 * tr.s)
                PhosphorList {
                    id: ledger
                    x: 12 * tr.s; y: 6 * tr.s
                    width: ldBezel.iw - 24 * tr.s; height: ldBezel.ih - 12 * tr.s
                    fontSize: ldBezel.fs
                    newestFirst: true
                    model: tr.ledgerRows
                    delegate: Item {
                        required property var modelData
                        required property int index
                        width: ledger.list.width - (ledger.overflow ? 0 : 26 * tr.s)
                        height: ledger.fontSize * 1.3
                        readonly property bool sell: String(modelData.type).toUpperCase() === "SELL"
                        readonly property real amount: sell ? Number(modelData.profit === null || modelData.profit === undefined ? 0 : modelData.profit) : -Number(modelData.qty) * Number(modelData.unit)
                        Text { x: 0; anchors.verticalCenter: parent.verticalCenter; text: tr.up(modelData.time); color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: ledger.fontSize }
                        Text { x: parent.width * 0.17; anchors.verticalCenter: parent.verticalCenter; text: tr.up(modelData.type); color: parent.sell ? Theme.ok : Theme.info; font.family: Theme.crtFont; font.pixelSize: ledger.fontSize }
                        Text { x: parent.width * 0.29; width: parent.width * 0.4; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter
                               text: tr.num(modelData.qty) + " T " + tr.up(modelData.commodity); color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: ledger.fontSize }
                        Text { anchors.right: parent.right; anchors.rightMargin: 4 * tr.s; anchors.verticalCenter: parent.verticalCenter
                               text: (parent.sell && (modelData.profit === null || modelData.profit === undefined)) ? "SOLD" : (parent.amount >= 0 ? "+" : "-") + tr.num(Math.abs(parent.amount))
                               color: parent.amount >= 0 ? Theme.ok : Theme.phosphor; opacity: parent.amount >= 0 ? 1 : 0.75; font.family: Theme.crtFont; font.pixelSize: ledger.fontSize }
                    }
                }
                Text {
                    visible: tr.ledgerRows.length === 0
                    anchors.centerIn: parent; width: ldBezel.iw * 0.85; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                    text: "NO TRADES YET // BUYS AND SELLS SHOW UP HERE AS YOU MAKE THEM"
                    color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: ldBezel.fs
                }
            }
        }
    }

    // ================================================================= STATION GLYPH (trade loop)
    component StationGlyph: Item {
        id: st
        property string side: "BUY"
        property real cx: 0
        property string name: "-"
        property string sys: "-"
        property bool here: false
        x: cx - lBezel.r * 1.6; y: lBezel.cy - lBezel.r * 1.6
        width: lBezel.r * 3.2; height: lBezel.r * 3.2
        // amber glow ring on the station you are docked at
        Rectangle { anchors.centerIn: parent; width: lBezel.r * 2.9; height: width; radius: width / 2; visible: st.here; color: Theme.t("#22ffb84d") }
        Rectangle {
            anchors.centerIn: parent; width: lBezel.r * 2.9; height: width; radius: width / 2
            color: "transparent"; border.color: Theme.info; border.width: Math.max(2, 5 * tr.s)
            visible: st.here
            SequentialAnimation on opacity { running: st.here && tr.visible; loops: Animation.Infinite
                NumberAnimation { from: 0.95; to: 0.35; duration: 1100; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.35; to: 0.95; duration: 1100; easing.type: Easing.InOutSine } }
        }
        Rectangle { anchors.centerIn: parent; width: lBezel.r * 2.2; height: width; radius: width / 2; color: "transparent"
                    border.color: tr.hasLoop ? Theme.ok : Theme.dimText; border.width: Math.max(2, 4 * tr.s) }
        Rectangle { anchors.centerIn: parent; width: lBezel.r * 1.5; height: width; radius: width / 2; color: Theme.t("#0c7dff9c")
                    border.color: tr.hasLoop ? Theme.t("#997dff9c") : Theme.t("#335f8a6c"); border.width: Math.max(1, 2 * tr.s) }
        Rectangle { anchors.centerIn: parent; width: lBezel.r * 0.72; height: lBezel.r * 0.22; radius: 2 * tr.s; color: tr.hasLoop ? Theme.ok : Theme.dimText }
        Column {
            anchors.horizontalCenter: parent.horizontalCenter; y: parent.height + 2 * tr.s
            spacing: 1 * tr.s
            Text { anchors.horizontalCenter: parent.horizontalCenter
                   text: st.side + (st.here ? " // YOU ARE HERE" : "")
                   color: st.here || st.side === "BUY" ? Theme.info : Theme.ok; font.family: Theme.crtFont; font.pixelSize: lBezel.fs * 0.82 }
            Text { anchors.horizontalCenter: parent.horizontalCenter; width: Math.min(implicitWidth, lBezel.iw * 0.34); elide: Text.ElideRight
                   horizontalAlignment: Text.AlignHCenter
                   text: tr.up(st.name); color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: lBezel.fs * 1.12 }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: tr.up(st.sys); color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: lBezel.fs * 0.78 }
        }
    }

    // ================================================================= ODOMETER (rolling drum digits)
    component Odometer: Row {
        id: odo
        property real value: 0
        property int digits: 8
        property real cellW: 50
        spacing: 3 * tr.s
        property real shown: value
        Behavior on shown { NumberAnimation { duration: 1800; easing.type: Easing.OutCubic } }
        Repeater {
            model: odo.digits
            Rectangle {
                id: cell
                width: odo.cellW; height: odo.cellW * 1.3
                color: lead ? "#b8b19e" : "#e9e4d4"; border.color: "#0b0b0a"; border.width: Math.max(1, 2 * tr.s); radius: 3 * tr.s
                clip: true
                readonly property real place: Math.pow(10, odo.digits - 1 - index)
                // continuous drum position: the last digit turns smoothly, higher digits flip as it carries
                readonly property real pos: {
                    var v = Math.max(0, odo.shown) / place
                    var d = Math.floor(v) % 10
                    var frac = v - Math.floor(v)
                    return index === odo.digits - 1 ? (d + frac) : (d + Math.max(0, (frac * place - (place - 1)) ))
                }
                readonly property bool lead: Math.max(0, odo.value) < place && index < odo.digits - 1
                Column {
                    y: -((cell.pos % 10)) * cell.height
                    Repeater {
                        model: 11
                        Text {
                            width: cell.width; height: cell.height
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            text: String(index % 10)
                            color: cell.lead ? "#9c957f" : "#1b1a17"; font.family: Theme.counterFont; font.pixelSize: cell.height * 0.72
                        }
                    }
                }
                Rectangle { anchors.fill: parent; radius: parent.radius
                            gradient: Gradient { GradientStop { position: 0; color: "#66000000" } GradientStop { position: 0.22; color: "#00000000" }
                                                 GradientStop { position: 0.78; color: "#00000000" } GradientStop { position: 1; color: "#66000000" } } }
            }
        }
    }

    // ================================================================= ACTION DECKS
    component DeckPlate: Plate {
        dark: true
        screwSize: 13 * tr.s
        readonly property real keyH: Math.min(height - 66 * tr.s, 150 * tr.s)
        readonly property real keyY: 52 * tr.s + (height - 66 * tr.s - keyH) / 2
        readonly property real cancelW: 270 * tr.s
        readonly property real divW: 40 * tr.s
        readonly property real keyGap: 14 * tr.s
    }
    component Groove: Item {
        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 4 * tr.s; height: parent.height; radius: 2 * tr.s; color: "#0b0b0a"; border.color: "#3e3b32"; border.width: 1 }
    }
    component CancelKey: Item {
        Glow { target: ck; color: "#ff5040"; spread: 34 * tr.s; radius: 8 * tr.s; intensity: tr.inControl ? 0.8 : 0 }
        DeckKey {
            id: ck
            anchors.fill: parent
            title: "CANCEL"; legend: "STOP ALL AUTOMATION"
            cap: "red"; hazard: true
            tooltip: "STOP ALL AUTOMATION"; tooltipDetail: "BRIDGE RELEASES YOUR CONTROLS"
            onActivated: bridge.requestCommand("cancel")
        }
    }
    component GroupLabel: Text {
        color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: Math.max(8, 13 * tr.s); font.letterSpacing: 3 * tr.s
    }

    // ---------------------------------------------------- FIND A ROUTE deck
    DeckPlate {
        id: findDeck
        visible: tr.tradeView === 0
        x: 0; y: tr.deckY; width: tr.width; height: tr.deckH
        Dymo { x: 26 * tr.s; y: 14 * tr.s; text: "ACTIONS // TRADE: FIND A ROUTE" }
        readonly property real keyW: (width - 26 * tr.s - cancelW - 40 * tr.s - 44 * tr.s - divW * 2 - keyGap * 10) / 8
        Row {
            id: findRow
            x: 26 * tr.s; y: findDeck.keyY
            spacing: findDeck.keyGap
            DeckKey {
                id: findKey
                width: findDeck.keyW * 1.15; height: findDeck.keyH
                title: "FIND ROUTES"
                legend: tr.searching ? "SEARCHING..." : (tr.haul === "" ? "ANY // BEST OVERALL" : tr.up(tr.haul))
                keyState: tr.searching ? "running" : "ready"
                tooltip: "FIND ROUTES"; tooltipDetail: tr.haul === "" ? "BEST COMMODITY AND LOOP NEAR YOU" : "BEST LOOPS FOR " + tr.up(tr.haul)
                onActivated: if (!tr.searching) tr.findRoutes()
            }
            Groove { width: findDeck.divW; height: findDeck.keyH }
            DeckKey {
                id: useKey
                width: findDeck.keyW * 1.15; height: findDeck.keyH
                title: "USE THIS ROUTE"
                legend: tr.chosen ? "SEND TO MY RUN" : "NO ROUTE PICKED"
                keyState: tr.chosen ? "ready" : "unavailable"
                unavailableReason: "PICK A ROUTE IN THE LIST FIRST"
                tooltip: "USE THIS ROUTE"; tooltipDetail: "SETS YOUR LOOP AND OPENS MY RUN"
                onActivated: { tr.useChosen(); tr.notice("ROUTE LOADED", tr.up(tr.chosen.buyStation) + " → " + tr.up(tr.chosen.sellStation), "ok"); showRunAfterUse.restart() }
                onDenied: (r) => tr.denied("USE THIS ROUTE UNAVAILABLE", r)
            }
            DeckKey {
                id: plotBuyFind
                width: findDeck.keyW * 1.15; height: findDeck.keyH
                title: "PLOT: BUY"
                legend: tr.chosen ? tr.up(tr.chosen.buyStation) : "NO ROUTE PICKED"
                keyState: !tr.chosen ? "unavailable" : (tr.bindsReady ? "ready" : "unavailable")
                unavailableReason: !tr.chosen ? "PICK A ROUTE IN THE LIST FIRST" : tr.bindsReason
                tooltip: tr.chosen ? "PLOT A ROUTE TO " + tr.up(tr.chosen.buySystem) : "PLOT A ROUTE TO THE BUY STATION"
                tooltipDetail: "USES THIS ROUTE, THEN PLOTS // THE ROUTE SHOWS UP ON NAVIGATION"
                onActivated: { tr.useChosen(); plotAfterUse.restart() }
                onDenied: (r) => tr.denied("PLOT: BUY UNAVAILABLE", r)
            }
        }
        GroupLabel { x: findRow.x + useKey.x + (plotBuyFind.x + plotBuyFind.width - useKey.x) / 2 - width / 2; y: findDeck.keyY - height - 6 * tr.s; text: "PICKED ROUTE" }
        CancelKey { x: findDeck.width - findDeck.cancelW - 40 * tr.s; y: findDeck.keyY; width: findDeck.cancelW; height: findDeck.keyH }
    }

    // ---------------------------------------------------- MY RUN deck
    DeckPlate {
        id: runDeck
        visible: tr.tradeView === 1
        x: 0; y: tr.deckY; width: tr.width; height: tr.deckH
        Dymo { x: 26 * tr.s; y: 14 * tr.s; text: "ACTIONS // TRADE: MY RUN" }
        readonly property real keyW: (width - 26 * tr.s - cancelW - 40 * tr.s - 44 * tr.s - divW * 2 - keyGap * 7) / 6
        readonly property string noLoop: "NO LOOP SET // PICK ONE IN FIND A ROUTE"
        Row {
            id: runRow
            x: 26 * tr.s; y: runDeck.keyY
            spacing: runDeck.keyGap
            DeckKey {
                id: resetKey
                width: runDeck.keyW; height: runDeck.keyH
                title: "RESET TRIP"
                legend: "ZERO THE COUNTERS"
                keyState: "ready"
                tooltip: "RESET TRIP"; tooltipDetail: "LIKE A TRIP ODOMETER // EARNINGS, SALES AND CYCLES START AGAIN FROM ZERO"
                onActivated: { bridge.requestCommand("trade_trip_reset"); tr.notice("TRIP RESET", "COUNTING FROM NOW", "ok") }
            }
            DeckKey {
                id: learnKey
                width: runDeck.keyW; height: runDeck.keyH
                title: "LEARN LOOP"
                legend: "FROM MY LAST TRADES"
                keyState: "ready"
                tooltip: "LEARN LOOP"; tooltipDetail: "SETS THE LOOP FROM YOUR LAST BUY AND SELL"
                onActivated: bridge.requestCommand("trade_learn_recent")
            }
            Groove { width: runDeck.divW; height: runDeck.keyH }
            Row {
                id: plotRow
                spacing: runDeck.keyGap
                Repeater {
                    model: [["PLOT: BUY", tr.buyStation, tr.buySystem, "trade_buy"], ["PLOT: SELL", tr.sellStation, tr.sellSystem, "trade_sell"]]
                    DeckKey {
                        width: runDeck.keyW; height: runDeck.keyH
                        title: modelData[0]
                        legend: tr.hasLoop ? tr.up(modelData[1]) : "NO LOOP SET"
                        keyState: !tr.hasLoop ? "unavailable" : (tr.bindsReady ? "ready" : "unavailable")
                        unavailableReason: !tr.hasLoop ? runDeck.noLoop : tr.bindsReason
                        tooltip: tr.hasLoop ? "PLOT A ROUTE TO " + tr.up(modelData[2]) : modelData[0]
                        tooltipDetail: "THE ROUTE SHOWS UP ON NAVIGATION"
                        onActivated: bridge.requestCommand(modelData[3])
                        onDenied: (r) => tr.denied(modelData[0] + " UNAVAILABLE", r)
                    }
                }
            }
            Groove { width: runDeck.divW; height: runDeck.keyH }
            DeckKey {
                id: dockKey
                width: runDeck.keyW; height: runDeck.keyH
                title: "DOCK"
                readonly property bool run: tr.bstate === "DOCKING PROTOCOL" || tr.bstate === "REQUEST DOCKING"
                legend: run ? bridge.bridgeMessage : "REQUEST DOCKING"
                keyState: run ? "running" : (tr.bindsReady ? "ready" : "unavailable")
                unavailableReason: tr.bindsReason
                tooltip: "REQUEST DOCKING"; tooltipDetail: "DOCKING PROTOCOL"
                onActivated: bridge.requestCommand("dock")
                onDenied: (r) => tr.denied("DOCK UNAVAILABLE", r)
            }
            DeckKey {
                id: launchKey
                width: runDeck.keyW; height: runDeck.keyH
                title: "LAUNCH"
                readonly property bool run: tr.bstate === "AUTO LAUNCH"
                legend: run ? bridge.bridgeMessage : "TAKE OFF"
                keyState: run ? "running" : (tr.bindsReady ? "ready" : "unavailable")
                unavailableReason: tr.bindsReason
                tooltip: "LAUNCH FROM THE PAD"; tooltipDetail: "AUTO LAUNCH SEQUENCE"
                onActivated: bridge.requestCommand("launch")
                onDenied: (r) => tr.denied("LAUNCH UNAVAILABLE", r)
            }
        }
        GroupLabel { x: runRow.x + plotRow.x + plotRow.width / 2 - width / 2; y: runDeck.keyY - height - 6 * tr.s; text: "PLOT ROUTE" }
        GroupLabel { x: runRow.x + dockKey.x + (launchKey.x + launchKey.width - dockKey.x) / 2 - width / 2; y: runDeck.keyY - height - 6 * tr.s; text: "FLIGHT" }
        CancelKey { x: runDeck.width - runDeck.cancelW - 40 * tr.s; y: runDeck.keyY; width: runDeck.cancelW; height: runDeck.keyH }
    }
}
