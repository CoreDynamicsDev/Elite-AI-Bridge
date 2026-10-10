// COLONIZATION (page 4). Retro redesign, build step 9 (mockup colonization_v4.png, colonization_site_stacking.gif).
// Views: THIS PROJECT and MY SITES (every claimed system, read from the journals). Project data is the engine's own (ConstructionDepot /
// Contribution events + saved projects). WHERE TO BUY is a buy-side market search that stays on
// this page (colonization_supply_search); the old Trade handoff command is unchanged for mapped inputs.
import QtQuick
import "../skin"

Item {
    id: co
    property var app
    property bool demo: false
    property int view: 0                     // 0 this project, 1 my sites
    property int screen: 0                   // main screen: 0 shopping list, 1 where to buy
    signal denied(string title, string reason)
    signal notice(string title, string detail, string level)

    // tour highlight targets (Main.qml pageHelpTarget)
    readonly property Item viewTarget: viewStrip
    readonly property Item infoTarget: sitePanel
    readonly property Item listTarget: mainPanel
    readonly property Item deckTarget: deck

    readonly property real s: Theme.s
    readonly property real g: Math.max(8, 14 * s)

    // ---------- helpers
    function norm(x) { return String(x || "").toLowerCase().replace(/[^a-z0-9]/g, "") }
    function up(x) { x = String(x === undefined || x === null ? "-" : x); return x === "" ? "-" : x.toUpperCase() }
    function num(v) { return Math.round(Number(v) || 0).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",") }
    function ageColor(h) { return h < 0 ? Theme.dimText : (h < 1 ? Theme.ok : (h < 12 ? Theme.phosphor : (h < 24 ? Theme.info : Theme.bad))) }
    function ageText(a) { a = String(a || "?"); return a.replace(/(\d+)d/, "$1 DAY").replace(/(\d+)h/, "$1 HR").replace(/(\d+)m$/, "$1 MIN").replace(/(\d+)s$/, "NOW").toUpperCase() }

    // ---------- project
    readonly property bool hasProject: bridge.colonizationHasProject
    readonly property string status: String(bridge.colonizationStatus || "NO PROJECT")
    readonly property string siteStation: String(bridge.colonizationStation || "-")
    readonly property string siteSystem: String(bridge.colonizationSystem || "-")
    readonly property real progress: Math.max(0, Math.min(100, Number(bridge.colonizationProgressPercent) || 0))
    readonly property bool docked: String(bridge.gameState).toUpperCase() === "DOCKED"
    readonly property bool atSite: hasProject && docked && norm(bridge.station) === norm(siteStation)
    readonly property int cap: bridge.cargoCapacity > 0 ? bridge.cargoCapacity : 0

    // requirement rows only swap when their content changes (the bridge resends lists every 250 ms)
    readonly property var liveReq: bridge.colonizationRequirementRows || []
    property var req: []
    property string reqKey: ""
    onLiveReqChanged: {
        var k = JSON.stringify(liveReq)
        if (k === reqKey) return
        reqKey = k
        var open = [], done = []
        for (var i = 0; i < liveReq.length; i++) (Number(liveReq[i].remaining) > 0 ? open : done).push(liveReq[i])
        open.sort(function(a, b) { return Number(b.remaining) - Number(a.remaining) })
        req = open.concat(done)
    }
    property string pickedName: ""
    readonly property var active: {
        for (var i = 0; i < req.length; i++) if (pickedName !== "" && String(req[i].name) === pickedName && Number(req[i].remaining) > 0) return req[i]
        for (var j = 0; j < req.length; j++) if (Number(req[j].remaining) > 0) return req[j]
        return null
    }
    readonly property string activeName: active ? String(active.name) : ""
    readonly property int activeRemaining: active ? Number(active.remaining) : 0
    readonly property int activeAboard: active ? Number(active.aboard) : 0
    readonly property int loadSize: cap > 0 ? Math.min(cap, activeRemaining) : activeRemaining
    readonly property int loadsLeft: cap > 0 && activeRemaining > 0 ? Math.ceil(activeRemaining / cap) : 0
    readonly property bool cargoAboard: { for (var i = 0; i < req.length; i++) if (Number(req[i].aboard) > 0 && Number(req[i].remaining) > 0) return true; return false }

    // ---------- supply (WHERE TO BUY)
    readonly property var liveSupply: bridge.colonizationSupplyRows || []
    property var supply: []
    property string supplyKey: ""
    property int supplySel: -1
    onLiveSupplyChanged: {
        var k = JSON.stringify(liveSupply)
        if (k === supplyKey) return
        supplyKey = k
        supply = liveSupply
        // nearest suitable: large pad and enough stock for one load, else the nearest
        var pick = supply.length > 0 ? 0 : -1
        for (var i = 0; i < supply.length; i++) {
            if (String(supply[i].pad) === "L" && (Number(supply[i].stock) < 0 || Number(supply[i].stock) >= loadSize)) { pick = i; break }
        }
        supplySel = pick
    }
    readonly property string supplyFor: String(bridge.colonizationSupplyCommodity || "")
    readonly property bool supplyMatches: supplyFor !== "" && norm(supplyFor) === norm(activeName)
    readonly property var buyAt: supplyMatches && supplySel >= 0 && supplySel < supply.length ? supply[supplySel] : null
    readonly property bool atSupply: buyAt !== null && docked && norm(bridge.station) === norm(buyAt.station)
    readonly property bool searching: bridge.colonizationSupplyBusy
    // plot keys: the backend says "you're already in X" out loud; show it here too
    function plotTo(sys) {
        if (norm(sys) !== "" && norm(sys) === norm(bridge.system)) notice("ALREADY HERE", "YOU'RE ALREADY IN " + up(sys), "info")
        bridge.plotRoute(sys)
    }
    function findSupply() {
        if (activeName === "") return
        bridge.findColonySupply(activeName, Math.max(1, loadSize))
        screen = 1
    }

    // ---------- deliveries: "10:39 PM  Steel +64 t • Station / System"
    function parseDelivery(t) {
        var m = String(t || "").match(/^(.+?)\s{2,}(.+?) \+([\d,]+) t/)
        return m ? { time: m[1], name: m[2], tons: m[3] } : null
    }
    readonly property var liveLog: bridge.colonizationLogRows || []
    property var logRows: []
    property string logKey: ""
    property bool logPrimed: false
    onLiveLogChanged: {
        var k = JSON.stringify(liveLog)
        if (k === logKey) return
        var firstOld = logRows.length > 0 ? String(logRows[0].text) : ""
        logKey = k
        logRows = liveLog
        // a new delivery arrived: play the delivery animation once
        if (logPrimed && logRows.length > 0 && String(logRows[0].kind) === "DELIVERY" && String(logRows[0].text) !== firstOld) {
            var d = parseDelivery(logRows[0].text)
            if (d) site.deliver("+" + d.tons + " T " + up(d.name))
        }
        logPrimed = true
    }

    // ---------- projects
    readonly property var projects: bridge.colonizationProjectRows || []

    // ---------- MY SITES (journal scan; list only swaps when its content changes)
    readonly property var liveSites: bridge.colonizationMySites || []
    property var sites: []
    property string sitesKey: ""
    property string siteSelKey: ""
    onLiveSitesChanged: {
        var k = JSON.stringify(liveSites)
        if (k === sitesKey) return
        sitesKey = k
        sites = liveSites
        if (siteSelKey === "" && sites.length > 0) siteSelKey = siteKey(sites[0])
    }
    function siteKey(r) { return r ? norm(r.system) + "|" + String(r.marketId) : "" }
    readonly property var selSite: {
        for (var i = 0; i < sites.length; i++) if (siteKey(sites[i]) === siteSelKey) return sites[i]
        return null
    }
    // the engine project for the picked site (it has one once you've docked there with the Bridge running)
    readonly property int selProjectIndex: {
        if (!selSite || String(selSite.station) === "-") return -1
        for (var i = 0; i < projects.length; i++)
            if (norm(projects[i].station) === norm(selSite.station) && norm(projects[i].system) === norm(selSite.system)) return i
        for (var j = 0; j < projects.length; j++) if (norm(projects[j].station) === norm(selSite.station)) return j
        return -1
    }

    // ---------- deck helpers
    readonly property string bstate: String(bridge.bridgeState || "").toUpperCase()
    readonly property bool inControl: bridge.controlOwner !== "NONE" && bridge.controlOwner !== ""
    readonly property bool bindsReady: bridge.eliteControlsReady
    readonly property string bindsReason: String(bridge.eliteControlReason || "") !== "" ? String(bridge.eliteControlReason).toUpperCase() : "ELITE KEY BINDS NOT FOUND // SEE SETUP > CONTROLS"

    // ---------- layout
    readonly property real stripH: 88 * s
    readonly property real bodyY: stripH + g
    readonly property real deckH: height * 0.175
    readonly property real deckY: height - deckH
    readonly property real bodyH: deckY - g - bodyY

    onVisibleChanged: if (!visible) { view = 0 }

    // ================================================================= VIEW STRIP + STATUS
    Plate {
        id: viewStrip
        x: 0; y: 0; width: co.width; height: co.stripH
        screwSize: 11 * co.s
        Text {
            x: 26 * co.s; anchors.verticalCenter: parent.verticalCenter
            text: "VIEW"; color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: Math.max(8, 13 * co.s); font.letterSpacing: 3 * co.s
        }
        Row {
            id: views
            x: 82 * co.s; y: 8 * co.s
            spacing: 12 * co.s
            Repeater {
                model: ["THIS PROJECT", "MY SITES (" + co.sites.length + ")"]
                LitButton {
                    width: 300 * co.s; height: co.stripH - 18 * co.s
                    title: modelData
                    on: co.view === index
                    onActivated: co.view = index
                }
            }
        }
        StatusPanel {
            id: annun
            x: views.x + views.width + 30 * co.s; y: 6 * co.s
            width: viewStrip.width - x - 22 * co.s; height: co.stripH - 12 * co.s
            items: [
                ["AT BUILD SITE", co.atSite ? "a" : ""],
                ["AT SUPPLY STOP", co.atSupply ? "a" : ""],
                ["CARGO ABOARD", co.cargoAboard ? "a" : ""],
                ["WRONG CARGO", String(bridge.colonizationWrongCargo) !== "" ? "r" : ""],
                ["HOLD FULL", co.cap > 0 && bridge.cargoUsed >= co.cap ? "a" : ""],
                ["PROJECT DONE", co.status === "COMPLETE" ? "a" : ""],
                ["SEARCHING", co.searching ? "a" : ""]
            ]
        }
    }

    // ================================================================= THIS PROJECT
    Item {
        id: projectView
        visible: co.view === 0
        x: 0; y: co.bodyY; width: co.width; height: co.bodyH
        readonly property real leftW: width * 0.495
        readonly property real topH: height * 0.635

        // ---------------------------------------------------- CONSTRUCTION SITE (cool factor)
        Plate {
            id: sitePanel
            x: 0; y: 0; width: projectView.leftW; height: projectView.topH
            screwSize: 13 * co.s
            Dymo { x: 26 * co.s; y: 14 * co.s; text: "CONSTRUCTION SITE" }
            Bezel {
                id: sBezel
                x: 16 * co.s; y: 50 * co.s
                width: parent.width - 32 * co.s; height: parent.height - 66 * co.s
                pad: 12 * co.s
                readonly property real iw: width - pad * 2
                readonly property real ih: height - pad * 2
                readonly property real fs: Math.max(11, 22 * co.s)

                SiteWire {
                    id: site
                    x: 0; y: 0; width: sBezel.iw * 0.47; height: sBezel.ih
                    progress: co.progress / 100
                    present: co.hasProject
                }
                Column {
                    x: sBezel.iw * 0.5; y: 12 * co.s; width: sBezel.iw * 0.48
                    spacing: 4 * co.s
                    visible: co.hasProject
                    Text { text: "BUILDING  //  " + co.status; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: sBezel.fs * 0.8 }
                    Text { width: parent.width; elide: Text.ElideRight; text: co.up(co.siteStation); color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: sBezel.fs * 1.45; font.letterSpacing: 1 * co.s }
                    Text { width: parent.width; elide: Text.ElideRight; text: co.up(co.siteSystem); color: Theme.phosphor; opacity: 0.8; font.family: Theme.crtFont; font.pixelSize: sBezel.fs * 0.9 }
                    Item { width: 1; height: 6 * co.s }
                    Text {
                        textFormat: Text.StyledText
                        text: co.progress.toFixed(co.progress < 10 ? 1 : 0) + "<font size='4'>%</font>"
                        color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: sBezel.fs * 4.2
                    }
                    BlockBar {
                        width: parent.width; height: sBezel.fs * 1.0
                        value: co.progress / 100
                    }
                    Item { width: 1; height: 8 * co.s }
                    Repeater {
                        model: [
                            ["LEFT TO HAUL", co.num(bridge.colonizationRemainingTotal) + " T"],
                            ["LOADS" + (co.cap > 0 ? " (" + co.num(co.cap) + " T)" : ""), co.cap > 0 ? "≈ " + co.num(bridge.colonizationProjectLoads) : "-"],
                            ["ITEMS DONE", bridge.colonizationCompleteCount + " OF " + (bridge.colonizationCompleteCount + bridge.colonizationIncompleteCount)]
                        ]
                        Item { width: parent.width; height: sBezel.fs * 1.2
                            Text { text: modelData[0]; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: sBezel.fs }
                            Text { anchors.right: parent.right; text: modelData[1]; color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: sBezel.fs } }
                    }
                    Text { width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                           text: "YOUR PACE  //  " + co.up(bridge.colonizationPaceText); color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: sBezel.fs * 0.8 }
                }
                Text {
                    visible: !co.hasProject
                    x: sBezel.iw * 0.5; y: sBezel.ih * 0.32; width: sBezel.iw * 0.46; wrapMode: Text.WordWrap
                    text: "NO PROJECT YET // DOCK AT A CONSTRUCTION SITE AND THE BRIDGE PICKS IT UP FROM THE JOURNAL"
                    color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: sBezel.fs * 1.05
                }
            }
        }

        // ---------------------------------------------------- NEXT RUN
        Plate {
            id: nextPanel
            x: 0; y: projectView.topH + co.g; width: projectView.leftW * 0.58; height: projectView.height - y
            screwSize: 12 * co.s
            Dymo { x: 26 * co.s; y: 14 * co.s; text: "NEXT RUN" }
            Bezel {
                id: nBezel
                x: 16 * co.s; y: 50 * co.s
                width: parent.width - 32 * co.s; height: parent.height - 66 * co.s
                pad: 10 * co.s
                readonly property real iw: width - pad * 2
                readonly property real fs: Math.max(11, 20 * co.s)
                Column {
                    x: 12 * co.s; y: 6 * co.s; width: nBezel.iw - 24 * co.s
                    spacing: 3 * co.s
                    Text { width: parent.width; elide: Text.ElideRight
                           text: co.active ? "HAUL " + co.up(co.activeName) + "  //  " + co.num(co.loadSize) + " T LOAD  //  " + co.num(co.loadsLeft) + (co.loadsLeft === 1 ? " LOAD LEFT" : " LOADS LEFT") : (co.hasProject ? "NOTHING LEFT TO HAUL" : "NO PROJECT")
                           color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: nBezel.fs * 0.85 }
                    Text { text: "BUY AT"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: nBezel.fs * 0.8 }
                    Text { width: parent.width; elide: Text.ElideRight
                           text: co.buyAt ? co.up(co.buyAt.station) : (co.active ? "PRESS FIND SUPPLY" : "-")
                           color: co.buyAt ? Theme.ok : Theme.info; font.family: Theme.crtFont; font.pixelSize: nBezel.fs * 1.4 }
                    Item { width: parent.width; height: nBezel.fs * 1.1
                        Text { text: co.buyAt ? co.up(co.buyAt.system) + "  //  " + Number(co.buyAt.ly).toFixed(1) + " LY  //  PAD " + co.buyAt.pad : ""
                               color: Theme.phosphor; opacity: 0.8; font.family: Theme.crtFont; font.pixelSize: nBezel.fs * 0.85 }
                        Text { anchors.right: parent.right; text: co.buyAt ? (Number(co.buyAt.stock) < 0 ? "PLENTY" : co.num(co.buyAt.stock) + " T") : ""
                               color: co.buyAt && Number(co.buyAt.stock) >= 0 && Number(co.buyAt.stock) < co.loadSize ? Theme.info : Theme.ok; font.family: Theme.crtFont; font.pixelSize: nBezel.fs * 0.95 } }
                    Item { width: parent.width; height: nBezel.fs * 1.2
                        Text { text: "ABOARD"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: nBezel.fs * 0.85 }
                        Text { anchors.right: parent.right
                               text: !co.active ? "-" : co.num(co.activeAboard) + " T  //  " + (co.activeAboard >= co.loadSize && co.loadSize > 0 ? "DELIVER" : (co.atSupply ? "BUY NOW" : "GO BUY"))
                               color: Theme.info; font.family: Theme.crtFont; font.pixelSize: nBezel.fs } }
                }
            }
        }

        // ---------------------------------------------------- DELIVERIES
        Plate {
            id: logPanel
            x: nextPanel.width + co.g; y: nextPanel.y; width: projectView.leftW - x; height: nextPanel.height
            screwSize: 12 * co.s
            Dymo { x: 26 * co.s; y: 14 * co.s; text: "DELIVERIES" }
            Bezel {
                id: lBezel
                x: 16 * co.s; y: 50 * co.s
                width: parent.width - 32 * co.s; height: parent.height - 66 * co.s
                pad: 10 * co.s
                readonly property real iw: width - pad * 2
                readonly property real ih: height - pad * 2
                readonly property real fs: Math.max(10, 19 * co.s)
                PhosphorList {
                    id: dlist
                    x: 8 * co.s; y: 4 * co.s; width: lBezel.iw - 16 * co.s; height: lBezel.ih - 8 * co.s
                    fontSize: lBezel.fs
                    newestFirst: true
                    model: co.logRows
                    delegate: Item {
                        required property var modelData
                        required property int index
                        width: dlist.list.width - (dlist.overflow ? 0 : 22 * co.s)
                        height: dlist.fontSize * 1.3
                        readonly property var d: co.parseDelivery(modelData.text)
                        Text { visible: parent.d !== null; text: parent.d ? co.up(parent.d.time) : ""; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: dlist.fontSize; anchors.verticalCenter: parent.verticalCenter }
                        Text { visible: parent.d !== null; x: parent.width * 0.3; text: parent.d ? "+" + parent.d.tons + " T" : ""; color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: dlist.fontSize; anchors.verticalCenter: parent.verticalCenter }
                        Text { visible: parent.d !== null; x: parent.width * 0.55; width: parent.width * 0.45; elide: Text.ElideRight; text: parent.d ? co.up(parent.d.name) : ""
                               color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: dlist.fontSize; anchors.verticalCenter: parent.verticalCenter }
                        Text { visible: parent.d === null; width: parent.width; elide: Text.ElideRight; text: co.up(modelData.text)
                               color: String(modelData.kind) === "CLAIM" ? Theme.info : Theme.dimText; font.family: Theme.crtFont; font.pixelSize: dlist.fontSize * 0.9; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
                Text {
                    visible: co.logRows.length === 0
                    anchors.centerIn: parent; width: lBezel.iw * 0.85; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                    text: "NO DELIVERIES YET"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: lBezel.fs
                }
            }
        }

        // ---------------------------------------------------- SHOPPING LIST / WHERE TO BUY (main screen)
        Plate {
            id: mainPanel
            x: projectView.leftW + co.g; y: 0; width: projectView.width - x; height: projectView.height
            screwSize: 13 * co.s
            Row {
                id: screens
                x: 20 * co.s; y: 10 * co.s
                spacing: 10 * co.s
                LitButton {
                    width: 250 * co.s; height: 46 * co.s
                    title: "SHOPPING LIST"
                    on: co.screen === 0
                    onActivated: co.screen = 0
                }
                LitButton {
                    width: 400 * co.s; height: 46 * co.s
                    title: "WHERE TO BUY" + (co.activeName !== "" ? ": " + co.up(co.activeName) : "")
                    on: co.screen === 1
                    onActivated: co.screen = 1
                }
            }
            Text {
                anchors.left: screens.right; anchors.leftMargin: 18 * co.s; anchors.verticalCenter: screens.verticalCenter
                text: "SAME SCREEN // FIND SUPPLY SWITCHES IT HERE"; color: Theme.plateText; opacity: 0.75
                font.family: Theme.labelFont; font.pixelSize: Math.max(8, 12 * co.s); font.letterSpacing: 1.5 * co.s
            }
            Bezel {
                id: mBezel
                x: 16 * co.s; y: 66 * co.s
                width: parent.width - 32 * co.s; height: parent.height - 82 * co.s
                pad: 12 * co.s
                readonly property real iw: width - pad * 2
                readonly property real ih: height - pad * 2
                readonly property real fs: Math.max(11, 22 * co.s)

                // ---------- SHOPPING LIST
                Item {
                    id: shopping
                    anchors.fill: parent
                    visible: co.screen === 0
                    // columns: commodity | still needed (r) | loads (r) | progress bar | % (r) | aboard (r)
                    readonly property var cx: [0.0, 0.42, 0.52, 0.55, 0.86, 1.0]
                    Text {
                        x: 20 * co.s; y: 10 * co.s; width: mBezel.iw * 0.7; elide: Text.ElideRight
                        text: co.hasProject ? co.req.length + " MATERIALS  //  BIGGEST FIRST  //  CLICK ONE TO HAUL IT NEXT" : "NO PROJECT"
                        color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: mBezel.fs * 0.85
                    }
                    Item {
                        id: shHead
                        x: 20 * co.s; y: 44 * co.s; width: mBezel.iw - 40 * co.s - 26 * co.s; height: mBezel.fs
                        Repeater {
                            model: [["COMMODITY", 0, 0], ["STILL NEEDED", 1, 1], ["LOADS", 2, 1], ["PROGRESS", 3, 0], ["ABOARD", 5, 1]]
                            Text { x: modelData[2] === 0 ? shHead.width * shopping.cx[modelData[1]] : shHead.width * shopping.cx[modelData[1]] - width
                                   text: modelData[0]; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: mBezel.fs * 0.72 }
                        }
                    }
                    PhosphorList {
                        id: shList
                        x: 20 * co.s; y: shHead.y + shHead.height + 6 * co.s
                        width: mBezel.iw - 40 * co.s; height: mBezel.ih - y - 6 * co.s
                        fontSize: mBezel.fs
                        model: co.req
                        delegate: Item {
                            required property var modelData
                            required property int index
                            width: shList.list.width - (shList.overflow ? 0 : 26 * co.s)
                            height: shList.fontSize * 1.35
                            readonly property bool done: Number(modelData.remaining) <= 0
                            readonly property bool picked: !done && String(modelData.name) === co.activeName
                            readonly property real pct: Number(modelData.required) > 0 ? Math.min(1, Number(modelData.provided) / Number(modelData.required)) : 1
                            opacity: done ? 0.45 : 1
                            Rectangle { anchors.fill: parent; visible: parent.picked || shPress.containsMouse
                                        color: parent.picked ? "#2a7dff9c" : "#127dff9c"; border.color: parent.picked ? "#807dff9c" : "transparent"; border.width: 1 }
                            Text { x: 4 * co.s; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.4; elide: Text.ElideRight
                                   text: (parent.picked ? "> " : "  ") + co.up(modelData.name); color: parent.picked ? Theme.ok : Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: shList.fontSize }
                            Text { x: parent.width * shopping.cx[1] - width; anchors.verticalCenter: parent.verticalCenter
                                   text: parent.done ? "DONE" : co.num(modelData.remaining) + " T"; color: parent.done ? Theme.ok : Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: shList.fontSize }
                            Text { x: parent.width * shopping.cx[2] - width; anchors.verticalCenter: parent.verticalCenter
                                   text: parent.done || co.cap <= 0 ? "-" : String(Math.ceil(Number(modelData.remaining) / co.cap)); color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: shList.fontSize }
                            Rectangle {
                                x: parent.width * shopping.cx[3]; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width * (shopping.cx[4] - shopping.cx[3]) - 70 * co.s; height: shList.fontSize * 0.55
                                color: "#0a1a10"; border.color: "#337dff9c"; border.width: 1
                                Rectangle { x: 1; y: 1; height: parent.height - 2; width: (parent.width - 2) * parent.parent.pct; color: Theme.ok; opacity: 0.75 }
                            }
                            Text { x: parent.width * shopping.cx[4] - width; anchors.verticalCenter: parent.verticalCenter
                                   text: Math.round(parent.pct * 100) + "%"; color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: shList.fontSize * 0.9 }
                            Text { anchors.right: parent.right; anchors.rightMargin: 6 * co.s; anchors.verticalCenter: parent.verticalCenter
                                   text: Number(modelData.aboard) > 0 ? co.num(modelData.aboard) + " T" : "-"; color: Number(modelData.aboard) > 0 ? Theme.info : Theme.dimText
                                   font.family: Theme.crtFont; font.pixelSize: shList.fontSize }
                            PressArea { id: shPress; anchors.fill: parent; available: !parent.done; unavailableReason: "THIS ONE IS DONE"
                                        onActivated: { Theme.cue("tick"); co.pickedName = String(modelData.name) } }
                        }
                    }
                    Text {
                        visible: co.req.length === 0
                        anchors.centerIn: parent; width: mBezel.iw * 0.8; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                        text: "THE MATERIAL LIST SHOWS UP WHEN YOU DOCK AT THE CONSTRUCTION SITE"
                        color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: mBezel.fs * 1.1
                    }
                }

                // ---------- WHERE TO BUY
                Item {
                    id: buying
                    anchors.fill: parent
                    visible: co.screen === 1
                    // station | system | LY (r) | LS (r) | pad | stock (r) | price (r) | updated (r)
                    readonly property var cx: [0.0, 0.25, 0.47, 0.56, 0.6, 0.76, 0.87, 1.0]
                    readonly property var rowsShown: co.supplyMatches ? co.supply : []
                    Text {
                        x: 20 * co.s; y: 10 * co.s; width: mBezel.iw * 0.62; elide: Text.ElideRight
                        text: co.searching ? "SEARCHING MARKETS FOR " + co.up(co.supplyFor) + "..."
                              : (co.supplyMatches ? co.up(bridge.colonizationSupplyStatus) : (co.activeName !== "" ? "PRESS FIND SUPPLY TO SEARCH FOR " + co.up(co.activeName) : "PICK A MATERIAL FIRST"))
                        color: co.searching ? Theme.info : Theme.ok; font.family: Theme.crtFont; font.pixelSize: mBezel.fs * 0.85
                    }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: 20 * co.s; y: 10 * co.s
                        text: "CHECK THE AGE, DATA CAN BE STALE // CLICK TO PICK"; color: Theme.dimText
                        font.family: Theme.crtFont; font.pixelSize: mBezel.fs * 0.72
                    }
                    Item {
                        id: byHead
                        x: 20 * co.s; y: 44 * co.s; width: mBezel.iw - 40 * co.s - 26 * co.s; height: mBezel.fs
                        Repeater {
                            model: [["STATION", 0, 0], ["SYSTEM", 1, 0], ["LY", 2, 1], ["LS", 3, 1], ["PAD", 4, 0], ["STOCK", 5, 1], ["PRICE", 6, 1], ["UPDATED", 7, 1]]
                            Text { x: modelData[2] === 0 ? byHead.width * buying.cx[modelData[1]] : byHead.width * buying.cx[modelData[1]] - width
                                   text: modelData[0]; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: mBezel.fs * 0.72 }
                        }
                    }
                    PhosphorList {
                        id: byList
                        x: 20 * co.s; y: byHead.y + byHead.height + 6 * co.s
                        width: mBezel.iw - 40 * co.s; height: mBezel.ih - y - 6 * co.s
                        fontSize: mBezel.fs
                        model: buying.rowsShown
                        delegate: Item {
                            required property var modelData
                            required property int index
                            width: byList.list.width - (byList.overflow ? 0 : 26 * co.s)
                            height: byList.fontSize * 1.35
                            readonly property bool picked: index === co.supplySel
                            Rectangle { anchors.fill: parent; visible: parent.picked || byPress.containsMouse
                                        color: parent.picked ? "#2a7dff9c" : "#127dff9c"; border.color: parent.picked ? "#807dff9c" : "transparent"; border.width: 1 }
                            Text { x: 4 * co.s; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.24; elide: Text.ElideRight
                                   text: (parent.picked ? "> " : "  ") + co.up(modelData.station); color: parent.picked ? Theme.ok : Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: byList.fontSize }
                            Text { x: parent.width * buying.cx[1]; width: parent.width * 0.17; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter
                                   text: co.up(modelData.system); color: Theme.phosphor; opacity: 0.85; font.family: Theme.crtFont; font.pixelSize: byList.fontSize }
                            Text { x: parent.width * buying.cx[2] - width; anchors.verticalCenter: parent.verticalCenter
                                   text: Number(modelData.ly).toFixed(1); color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: byList.fontSize }
                            Text { x: parent.width * buying.cx[3] - width; anchors.verticalCenter: parent.verticalCenter
                                   text: Number(modelData.ls) < 0 ? "?" : co.num(modelData.ls); color: Number(modelData.ls) > 5000 ? Theme.info : Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: byList.fontSize }
                            Text { x: parent.width * buying.cx[4] + 10 * co.s; anchors.verticalCenter: parent.verticalCenter
                                   text: String(modelData.pad); color: String(modelData.pad) === "L" ? Theme.phosphor : Theme.info; font.family: Theme.crtFont; font.pixelSize: byList.fontSize }
                            Text { x: parent.width * buying.cx[5] - width; anchors.verticalCenter: parent.verticalCenter
                                   text: Number(modelData.stock) < 0 ? "PLENTY" : co.num(modelData.stock) + " T"
                                   color: Number(modelData.stock) >= 0 && Number(modelData.stock) < co.loadSize ? Theme.info : Theme.ok; font.family: Theme.crtFont; font.pixelSize: byList.fontSize }
                            Text { x: parent.width * buying.cx[6] - width; anchors.verticalCenter: parent.verticalCenter
                                   text: co.num(modelData.price); color: Theme.phosphor; opacity: 0.85; font.family: Theme.crtFont; font.pixelSize: byList.fontSize }
                            Text { anchors.right: parent.right; anchors.rightMargin: 6 * co.s; anchors.verticalCenter: parent.verticalCenter
                                   text: co.ageText(modelData.age); color: co.ageColor(Number(modelData.ageHours)); font.family: Theme.crtFont; font.pixelSize: byList.fontSize }
                            PressArea { id: byPress; anchors.fill: parent; onActivated: { Theme.cue("tick"); co.supplySel = index } }
                        }
                    }
                    Text {
                        visible: buying.rowsShown.length === 0 && !co.searching
                        anchors.centerIn: parent; width: mBezel.iw * 0.8; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                        text: co.activeName !== "" ? "NO SUPPLY LISTED YET // PRESS FIND SUPPLY TO SEARCH FOR " + co.up(co.activeName) : "PICK A MATERIAL IN THE SHOPPING LIST FIRST"
                        color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: mBezel.fs * 1.1
                    }
                }
            }
        }
    }

    // ================================================================= MY SITES
    // Every system you claimed and every construction site in them, read from your journals
    // at startup and followed live. Nothing saved by us; numbers are as of your last visit.
    Plate {
        id: allView
        visible: co.view === 1
        x: 0; y: co.bodyY; width: co.width; height: co.bodyH
        screwSize: 13 * co.s
        Dymo { x: 26 * co.s; y: 22 * co.s; text: "MY SITES // READ FROM YOUR JOURNALS" }
        LitButton {
            id: workKey
            anchors.right: parent.right; anchors.rightMargin: 30 * co.s
            y: 8 * co.s; width: 380 * co.s; height: 58 * co.s
            centered: true
            title: "WORK ON THIS SITE"
            tooltip: "OPEN THE PICKED SITE IN THIS PROJECT"
            available: co.selProjectIndex >= 0
            unavailableReason: co.selSite === null ? "PICK A SITE FIRST" : "DOCK AT THIS SITE ONCE TO LOAD ITS SHOPPING LIST"
            onActivated: { bridge.useColonizationProjectIndex(co.selProjectIndex); co.pickedName = ""; co.view = 0 }
            onDenied: (r) => co.denied("WORK ON THIS SITE", r)
        }
        Bezel {
            id: aBezel
            x: 16 * co.s; y: 74 * co.s
            width: parent.width - 32 * co.s; height: parent.height - 90 * co.s
            pad: 12 * co.s
            readonly property real iw: width - pad * 2
            readonly property real ih: height - pad * 2
            readonly property real fs: Math.max(12, 22 * co.s)
            //                           site  system dist  prog  pct   left  status seen(right)
            readonly property var cx: [0.0, 0.25, 0.43, 0.51, 0.63, 0.73, 0.76, 1.0]
            Item {
                id: aHead
                x: 20 * co.s; y: 14 * co.s; width: aBezel.iw - 40 * co.s - 26 * co.s; height: aBezel.fs
                Repeater {
                    model: [["SITE", 0, 0], ["SYSTEM", 1, 0], ["DIST", 3, 1], ["PROGRESS", 3, 0], ["LEFT", 5, 1], ["STATUS", 6, 0], ["LAST SEEN", 7, 1]]
                    Text { x: modelData[2] === 0 ? aHead.width * aBezel.cx[modelData[1]] + (modelData[1] === 3 ? 10 * co.s : 0) : aHead.width * aBezel.cx[modelData[1]] - width
                           text: modelData[0]; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: aBezel.fs * 0.72 }
                }
            }
            PhosphorList {
                id: pList
                x: 20 * co.s; y: aHead.y + aHead.height + 8 * co.s
                width: aBezel.iw - 40 * co.s; height: aBezel.ih - y - 60 * co.s
                fontSize: aBezel.fs
                model: co.sites
                delegate: Item {
                    required property var modelData
                    required property int index
                    width: pList.list.width - (pList.overflow ? 0 : 26 * co.s)
                    height: pList.fontSize * 1.5
                    readonly property bool sel: co.siteKey(modelData) === co.siteSelKey
                    readonly property string st: String(modelData.status)
                    readonly property color stColor: st === "COMPLETE" ? Theme.ok : (st === "FAILED" ? Theme.bad : (st === "CLAIMED" ? Theme.dimText : Theme.info))
                    Rectangle { anchors.fill: parent; visible: parent.sel || sPress.containsMouse
                                color: parent.sel ? "#2a7dff9c" : "#127dff9c"; border.color: parent.sel ? "#807dff9c" : "transparent"; border.width: 1 }
                    Text { x: 4 * co.s; anchors.verticalCenter: parent.verticalCenter; width: parent.width * (aBezel.cx[1] - 0.075); elide: Text.ElideRight
                           text: (parent.sel ? "> " : "  ") + (String(modelData.station) === "-" ? "NO SITE SEEN YET" : co.up(modelData.station))
                           color: parent.sel ? Theme.ok : (String(modelData.station) === "-" ? Theme.dimText : Theme.phosphor); font.family: Theme.crtFont; font.pixelSize: pList.fontSize }
                    Text { x: parent.width * aBezel.cx[1] - width - 14 * co.s; anchors.verticalCenter: parent.verticalCenter
                           text: String(modelData.kind) === "-" ? "" : String(modelData.kind)
                           color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: pList.fontSize * 0.75 }
                    Text { x: parent.width * aBezel.cx[1]; width: parent.width * (aBezel.cx[2] - aBezel.cx[1]) - 6 * co.s; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter
                           text: co.up(modelData.system); color: Theme.phosphor; opacity: 0.85; font.family: Theme.crtFont; font.pixelSize: pList.fontSize }
                    Text { x: parent.width * aBezel.cx[3] - width; anchors.verticalCenter: parent.verticalCenter
                           text: Number(modelData.ly) >= 0 ? Number(modelData.ly).toFixed(1) + " LY" : "? LY"; color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: pList.fontSize }
                    Rectangle {
                        visible: parent.st !== "CLAIMED"
                        x: parent.width * aBezel.cx[3] + 10 * co.s; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * (aBezel.cx[4] - aBezel.cx[3]) - 14 * co.s; height: pList.fontSize * 0.55
                        color: "#0a1a10"; border.color: "#337dff9c"; border.width: 1
                        Rectangle { x: 1; y: 1; height: parent.height - 2; width: (parent.width - 2) * Math.min(1, Number(modelData.progressPct) / 100); color: Theme.ok; opacity: 0.75 }
                    }
                    Text { visible: parent.st !== "CLAIMED"; x: parent.width * aBezel.cx[4]; anchors.verticalCenter: parent.verticalCenter
                           text: Number(modelData.progressPct).toFixed(0) + "%"; color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: pList.fontSize }
                    Text { x: parent.width * aBezel.cx[5] - width; anchors.verticalCenter: parent.verticalCenter
                           text: parent.st === "CLAIMED" ? "-" : co.num(modelData.left) + " T"
                           color: parent.st === "BUILDING" ? Theme.phosphor : Theme.dimText; font.family: Theme.crtFont; font.pixelSize: pList.fontSize }
                    Text { x: parent.width * aBezel.cx[6]; anchors.verticalCenter: parent.verticalCenter
                           text: parent.st; color: parent.stColor; font.family: Theme.crtFont; font.pixelSize: pList.fontSize }
                    Text { anchors.right: parent.right; anchors.rightMargin: 6 * co.s; anchors.verticalCenter: parent.verticalCenter
                           text: String(modelData.lastSeen).replace("CLAIMED ", ""); color: Number(modelData.ageHours) >= 0 && Number(modelData.ageHours) < 24 ? Theme.phosphor : Theme.dimText
                           font.family: Theme.crtFont; font.pixelSize: pList.fontSize * 0.85 }
                    PressArea { id: sPress; anchors.fill: parent
                                onActivated: { Theme.cue("tick"); co.siteSelKey = co.siteKey(modelData) } }
                }
            }
            Text {
                visible: co.sites.length === 0
                anchors.centerIn: parent; width: aBezel.iw * 0.7; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                text: String(bridge.colonizationMySitesStatus || ""); color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: aBezel.fs
            }
            Column {
                x: 20 * co.s; y: aBezel.ih - 54 * co.s; spacing: 2 * co.s
                width: aBezel.iw - 40 * co.s
                Text { width: parent.width; elide: Text.ElideRight
                       text: String(bridge.colonizationMySitesStatus || ""); color: Theme.phosphor; opacity: 0.8; font.family: Theme.crtFont; font.pixelSize: aBezel.fs * 0.75 }
                Text { width: parent.width; elide: Text.ElideRight
                       text: "EVERY BUILD SITE YOU HAVE DOCKED AT // PROGRESS IS AS OF YOUR LAST VISIT // PICK A ROW, THEN PLOT: SITE"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: aBezel.fs * 0.75 }
            }
        }
    }

    // ================================================================= CONSTRUCTION SITE WIREFRAME
    // Our own simplified drop-off: a round deck with pads, a tower of stacked sections and
    // lattice scaffolds. Built part solid and bright; unbuilt part a faint wireframe of the
    // finished tower. About one turn a minute from a continuous clock (never restarts).
    component SiteWire: Item {
        id: sw
        property real progress: 0
        property bool present: true
        property real theta: 0
        property real flyT: -1            // delivery animation 0..1, -1 idle
        property string flyText: ""
        readonly property var secR: [0.15, 0.13, 0.11, 0.09, 0.065]        // section radius (x width)
        readonly property var secH: [0.15, 0.14, 0.13, 0.12, 0.10]         // section height (x height)
        function deliver(t) { flyText = t; flyAnim.restart() }
        NumberAnimation { id: flyAnim; target: sw; property: "flyT"; from: 0; to: 1; duration: 1800; easing.type: Easing.InOutQuad
                          onStopped: sw.flyT = -1 }
        Timer {
            interval: 66; repeat: true; running: sw.visible && co.visible
            onTriggered: { sw.theta = (Date.now() % 60000) / 60000 * 2 * Math.PI; cv.requestPaint() }
        }
        // where the build top is (for the amber ring, % tag and the delivery target)
        readonly property real deckY: height * 0.8
        function topY(p) {
            var total = 0, i; for (i = 0; i < secH.length; i++) total += secH[i]
            var want = p * total, y = deckY, acc = 0
            for (i = 0; i < secH.length; i++) {
                var hh = secH[i] * height
                if (acc + secH[i] >= want) return y - (want - acc) * height
                acc += secH[i]; y -= hh
            }
            return y
        }
        function radiusAt(p) {
            var total = 0, i; for (i = 0; i < secH.length; i++) total += secH[i]
            var want = p * total, acc = 0
            for (i = 0; i < secH.length; i++) { if (acc + secH[i] >= want) return secR[i] * width; acc += secH[i] }
            return secR[secR.length - 1] * width
        }
        Canvas {
            id: cv
            anchors.fill: parent
            onPaint: {
                var c = getContext("2d"); c.reset()
                var w = width, h = height, cx = w / 2, th = sw.theta, p = sw.present ? sw.progress : 0
                var G = "125,255,156", A = "255,184,77"
                var tilt = 0.22                       // ellipse squash for the 3D look
                function ell(y, r, a, lw, front) {     // ring at height y, radius r
                    c.lineWidth = lw; c.strokeStyle = "rgba(" + G + "," + a + ")"
                    c.beginPath()
                    if (front === undefined) c.ellipse(cx - r, y - r * tilt, r * 2, r * tilt * 2)
                    else { for (var k = 0; k <= 24; k++) { var t = front ? Math.PI * k / 24 : Math.PI + Math.PI * k / 24
                           var x = cx + r * Math.cos(t), yy = y + r * tilt * Math.sin(t); if (k === 0) c.moveTo(x, yy); else c.lineTo(x, yy) } }
                    c.stroke()
                }
                // deck platform + pads
                var dy = sw.deckY, dr = w * 0.44
                ell(dy, dr, 0.55, 2); ell(dy + h * 0.025, dr, 0.25, 1)
                ell(dy, dr * 0.72, 0.22, 1)
                for (var i = 0; i < 6; i++) {
                    var a = th + i * Math.PI / 3, px = cx + dr * 0.86 * Math.cos(a), py = dy + dr * 0.86 * tilt * Math.sin(a)
                    var z = Math.sin(a), al = z > 0 ? 0.65 : 0.25
                    c.strokeStyle = "rgba(" + G + "," + al + ")"; c.lineWidth = 1
                    c.strokeRect(px - w * 0.03, py - h * 0.008, w * 0.06, h * 0.016)
                }
                // scaffolds (behind first, front after the tower)
                function scaffold(a, front) {
                    var z = Math.sin(a); if ((z > 0) !== front) return
                    var R = w * 0.36, sx = cx + R * Math.cos(a), sy = dy + R * tilt * z
                    var sh = h * 0.62, sw2 = w * 0.035, al = (front ? 0.55 : 0.22) * Math.max(0, 1 - Math.max(0, p - 0.95) * 20)
                    if (al <= 0.01) return
                    c.strokeStyle = "rgba(" + G + "," + al + ")"; c.lineWidth = 1
                    c.beginPath(); c.moveTo(sx - sw2, sy); c.lineTo(sx - sw2, sy - sh); c.moveTo(sx + sw2, sy); c.lineTo(sx + sw2, sy - sh); c.stroke()
                    c.beginPath()
                    var n = 12
                    for (var k = 0; k < n; k++) { var y0 = sy - sh * k / n, y1 = sy - sh * (k + 1) / n
                        c.moveTo(sx - sw2, y0); c.lineTo(sx + sw2, y1); c.moveTo(sx - sw2, y1); c.lineTo(sx + sw2, y1) }
                    c.stroke()
                }
                for (var q = 0; q < 3; q++) scaffold(th * 1.0 + q * 2 * Math.PI / 3 + 0.4, false)
                // tower sections
                var total = 0; for (i = 0; i < sw.secH.length; i++) total += sw.secH[i]
                var built = p * total, acc = 0, yb = dy
                for (i = 0; i < sw.secH.length; i++) {
                    var sh2 = sw.secH[i] * h, r = sw.secR[i] * w, yt = yb - sh2
                    var bf = Math.max(0, Math.min(1, (built - acc) / sw.secH[i]))    // built fraction of this section
                    // faint wireframe of the finished section
                    ell(yt, r, 0.16, 1); ell(yb, r, 0.12, 1, true)
                    c.strokeStyle = "rgba(" + G + ",0.14)"; c.lineWidth = 1
                    c.setLineDash([4, 5]); c.beginPath(); c.moveTo(cx - r, yb); c.lineTo(cx - r, yt); c.moveTo(cx + r, yb); c.lineTo(cx + r, yt); c.stroke(); c.setLineDash([])
                    if (bf > 0) {
                        var yf = yb - sh2 * bf
                        // solid built part
                        c.fillStyle = "rgba(" + G + ",0.10)"; c.fillRect(cx - r, yf, r * 2, yb - yf)
                        c.strokeStyle = "rgba(" + G + ",0.9)"; c.lineWidth = 2
                        c.beginPath(); c.moveTo(cx - r, yb); c.lineTo(cx - r, yf); c.moveTo(cx + r, yb); c.lineTo(cx + r, yf); c.stroke()
                        ell(yb, r, 0.85, 2, true)
                        // weld seams (slices)
                        for (var sl = 1; sl < 6; sl++) { var ys = yb - sh2 * sl / 6; if (ys < yf) break; ell(ys, r, 0.35, 1, true) }
                        // rotating seams on the side
                        for (var m = 0; m < 6; m++) { var ma = th * 2 + m * Math.PI / 3; if (Math.sin(ma) < 0) continue
                            var mx = cx + r * Math.cos(ma); c.strokeStyle = "rgba(" + G + ",0.35)"; c.lineWidth = 1
                            c.beginPath(); c.moveTo(mx, yb + r * tilt * Math.sin(ma)); c.lineTo(mx, yf + r * tilt * Math.sin(ma)); c.stroke() }
                        if (bf >= 1) {
                            ell(yt, r, 0.9, 2)
                            // running lights on finished sections
                            for (var l = 0; l < 4; l++) { var la = th * 1.5 + l * Math.PI / 2, lz = Math.sin(la)
                                var on = (Math.floor(Date.now() / 700) + l + i) % 2 === 0
                                c.fillStyle = "rgba(" + (on ? A : G) + "," + (lz > 0 ? 0.95 : 0.3) + ")"
                                c.beginPath(); c.arc(cx + r * Math.cos(la), yt + sh2 * 0.5 + r * tilt * lz, Math.max(1.5, w * 0.006), 0, 2 * Math.PI); c.fill() }
                        }
                    }
                    acc += sw.secH[i]; yb = yt
                }
                // spire + beacon at 100%
                c.strokeStyle = "rgba(" + G + "," + (p >= 1 ? 0.9 : 0.15) + ")"; c.lineWidth = 1
                c.beginPath(); c.moveTo(cx, yb); c.lineTo(cx, yb - h * 0.08); c.stroke()
                if (p >= 1) { var pulse = 0.5 + 0.5 * Math.sin(Date.now() / 300)
                    c.fillStyle = "rgba(255,255,255," + (0.5 + 0.5 * pulse) + ")"; c.beginPath(); c.arc(cx, yb - h * 0.08, Math.max(2, w * 0.012), 0, 2 * Math.PI); c.fill() }
                for (q = 0; q < 3; q++) scaffold(th + q * 2 * Math.PI / 3 + 0.4, true)
                // amber ring where the next slice goes
                if (p > 0 && p < 1) {
                    var ty = sw.topY(p), tr = sw.radiusAt(p) * 1.12
                    c.lineWidth = 2; c.strokeStyle = "rgba(" + A + ",0.95)"
                    c.beginPath(); c.ellipse(cx - tr, ty - tr * tilt, tr * 2, tr * tilt * 2); c.stroke()
                }
                // delivery: a glowing slice flies in on an arc and sets down on the ring
                if (sw.flyT >= 0 && p < 1) {
                    var f = sw.flyT, ty2 = sw.topY(p), rr = sw.radiusAt(p)
                    var fx = cx + (w * 0.55) * (1 - f), fy = ty2 - h * 0.35 * Math.sin(Math.PI * Math.min(1, f) * 0.5 + Math.PI * 0.5) * (1 - f) - (1 - f) * h * 0.05
                    if (f < 0.85) { c.fillStyle = "rgba(255,230,160,0.85)"; c.fillRect(fx - rr, fy - h * 0.008, rr * 2, h * 0.016) }
                    else { var flash = (f - 0.85) / 0.15; c.lineWidth = 3; c.strokeStyle = "rgba(255,255,255," + (1 - flash) + ")"
                           var fr = rr * (1.2 + flash * 0.8); c.beginPath(); c.ellipse(cx - fr, ty2 - fr * tilt, fr * 2, fr * tilt * 2); c.stroke() }
                }
            }
        }
        // % tag next to the amber ring
        Text {
            visible: sw.present && sw.progress > 0 && sw.progress < 1
            x: sw.width / 2 + sw.radiusAt(sw.progress) * 1.2 + 6 * co.s; y: sw.topY(sw.progress) - height / 2
            text: Math.round(sw.progress * 100) + "%"; color: Theme.info; font.family: Theme.crtFont; font.pixelSize: Math.max(10, 18 * co.s)
        }
        // "+64 T STEEL" floats up after the slice lands
        Text {
            visible: sw.flyT > 0.8
            x: sw.width / 2 - width / 2; y: sw.topY(sw.progress) - 30 * co.s - (sw.flyT - 0.8) * 120 * co.s
            opacity: sw.flyT < 0.9 ? 1 : (1 - sw.flyT) * 10
            text: sw.flyText; color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: Math.max(12, 24 * co.s)
        }
    }

    // ================================================================= ACTION DECK
    component Groove: Item {
        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 4 * co.s; height: parent.height; radius: 2 * co.s; color: "#0b0b0a"; border.color: "#3e3b32"; border.width: 1 }
    }
    component GroupLabel: Text {
        color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: Math.max(8, 13 * co.s); font.letterSpacing: 3 * co.s
    }
    Plate {
        id: deck
        dark: true
        screwSize: 13 * co.s
        x: 0; y: co.deckY; width: co.width; height: co.deckH
        readonly property real keyH: Math.min(height - 66 * co.s, 150 * co.s)
        readonly property real keyY: 52 * co.s + (height - 66 * co.s - keyH) / 2
        readonly property real cancelW: 270 * co.s
        readonly property real divW: 40 * co.s
        readonly property real keyGap: 14 * co.s
        readonly property real keyW: (width - 26 * co.s - cancelW - 40 * co.s - 44 * co.s - divW * 2 - keyGap * 8) / 7
        Dymo { x: 26 * co.s; y: 14 * co.s; text: "ACTIONS // COLONIZATION" }
        Row {
            id: dRow
            x: 26 * co.s; y: deck.keyY
            spacing: deck.keyGap
            Item {
                width: deck.keyW * 1.1; height: deck.keyH
                readonly property bool showing: co.screen === 1 && co.supplyMatches && co.supply.length > 0
                Rectangle { anchors.fill: parent; anchors.margins: -6 * co.s; anchors.bottomMargin: -2 * co.s; radius: 9 * co.s
                            color: "transparent"; border.color: Theme.ok; border.width: Math.max(1, 2 * co.s); opacity: 0.55; visible: parent.showing && !co.searching }
                DeckKey {
                    id: findKey
                    anchors.fill: parent
                    title: "FIND SUPPLY"
                    legend: co.searching ? "SEARCHING..." : (co.activeName === "" ? "NOTHING TO HAUL" : co.up(co.activeName) + (parent.showing ? " // SHOWING" : ""))
                    keyState: co.searching ? "running" : (co.activeName !== "" ? "ready" : "unavailable")
                    unavailableReason: co.hasProject ? "NOTHING LEFT TO HAUL" : "NO PROJECT // DOCK AT A CONSTRUCTION SITE FIRST"
                    tooltip: "FIND SUPPLY"; tooltipDetail: "STATIONS SELLING THIS MATERIAL, NEAREST FIRST, WITHIN " + 100 + " LY"
                    onActivated: if (!co.searching) co.findSupply()
                    onDenied: (r) => co.denied("FIND SUPPLY UNAVAILABLE", r)
                }
            }
            DeckKey {
                id: plotBuy
                width: deck.keyW * 1.1; height: deck.keyH
                title: "PLOT: BUY"
                legend: co.buyAt ? co.up(co.buyAt.station) : "NO STATION PICKED"
                keyState: co.buyAt === null ? "unavailable" : (co.bindsReady ? "ready" : "unavailable")
                unavailableReason: co.buyAt === null ? "FIND SUPPLY FIRST" : co.bindsReason
                tooltip: co.buyAt ? "PLOT A ROUTE TO " + co.up(co.buyAt.system) : "PLOT A ROUTE TO THE PICKED STATION"
                tooltipDetail: "THE ROUTE SHOWS UP ON NAVIGATION"
                onActivated: co.plotTo(String(co.buyAt.system))
                onDenied: (r) => co.denied("PLOT: BUY UNAVAILABLE", r)
            }
            DeckKey {
                id: plotSite
                width: deck.keyW * 1.1; height: deck.keyH
                title: "PLOT: SITE"
                readonly property bool mine: co.view === 1
                readonly property string sys: mine ? (co.selSite ? String(co.selSite.system) : "") : (co.hasProject ? co.siteSystem : "")
                legend: mine ? (co.selSite ? co.up(co.selSite.system) : "PICK A SITE")
                             : (co.hasProject ? "DELIVER TO " + co.up(co.siteStation) : "NO PROJECT")
                keyState: sys === "" ? "unavailable" : (co.bindsReady ? "ready" : "unavailable")
                unavailableReason: sys === "" ? (mine ? "PICK A SITE IN THE LIST FIRST" : "NO PROJECT // DOCK AT A CONSTRUCTION SITE FIRST") : co.bindsReason
                tooltip: sys !== "" ? "PLOT A ROUTE TO " + co.up(sys) : "PLOT A ROUTE TO THE BUILD SITE"
                tooltipDetail: "THE ROUTE SHOWS UP ON NAVIGATION"
                onActivated: co.plotTo(sys)
                onDenied: (r) => co.denied("PLOT: SITE UNAVAILABLE", r)
            }
            Groove { width: deck.divW; height: deck.keyH }
            DeckKey {
                id: dockKey
                width: deck.keyW; height: deck.keyH
                title: "DOCK"
                readonly property bool run: co.bstate === "DOCKING PROTOCOL" || co.bstate === "REQUEST DOCKING"
                legend: run ? bridge.bridgeMessage : "REQUEST DOCKING"
                keyState: run ? "running" : (co.bindsReady ? "ready" : "unavailable")
                unavailableReason: co.bindsReason
                tooltip: "REQUEST DOCKING"; tooltipDetail: "DOCKING PROTOCOL"
                onActivated: bridge.requestCommand("dock")
                onDenied: (r) => co.denied("DOCK UNAVAILABLE", r)
            }
            DeckKey {
                id: launchKey
                width: deck.keyW; height: deck.keyH
                title: "LAUNCH"
                readonly property bool run: co.bstate === "AUTO LAUNCH"
                legend: run ? bridge.bridgeMessage : "TAKE OFF"
                keyState: run ? "running" : (co.bindsReady ? "ready" : "unavailable")
                unavailableReason: co.bindsReason
                tooltip: "LAUNCH FROM THE PAD"; tooltipDetail: "AUTO LAUNCH SEQUENCE"
                onActivated: bridge.requestCommand("launch")
                onDenied: (r) => co.denied("LAUNCH UNAVAILABLE", r)
            }
        }
        GroupLabel { x: dRow.x + plotBuy.x + (plotSite.x + plotSite.width - plotBuy.x) / 2 - width / 2; y: deck.keyY - height - 6 * co.s; text: "HAUL" }
        GroupLabel { x: dRow.x + dockKey.x + (launchKey.x + launchKey.width - dockKey.x) / 2 - width / 2; y: deck.keyY - height - 6 * co.s; text: "FLIGHT" }
        Item {
            x: deck.width - deck.cancelW - 40 * co.s; y: deck.keyY; width: deck.cancelW; height: deck.keyH
            Glow { target: ck; color: "#ff5040"; spread: 34 * co.s; radius: 8 * co.s; intensity: co.inControl ? 0.8 : 0 }
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
