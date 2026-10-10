// FLIGHT DECK (page 0, formerly Overview). Retro redesign, build step 3.
// Same bridge data and the same commands as v1.0.1; only the presentation changed.
import QtQuick
import "../skin"

Item {
    id: deck
    property var app                          // main window: shipArtSource()
    property alias deckTarget: actionPanel    // setup wizard lights these
    property alias dockTarget: dockKey
    property alias cancelTarget: cancelKey
    readonly property Item shipTarget: shipPanel        // page tour (help page 12)
    readonly property Item logTarget: logPanel
    readonly property Item routeTarget: routePanel
    signal denied(string title, string reason)

    readonly property real s: Theme.s
    readonly property real g: Math.max(8, 14 * s)            // gap between panels
    readonly property bool eliteLive: bridge.eliteTelemetryState === "CONNECTED"
    // what the ship screen shows: "ship" (class art), "none" (no ship to show), "unmatched" (ship with no class on file)
    readonly property var shipInfo: app ? app.shipClassInfo(bridge.shipModel) : null
    readonly property string shipState: !eliteLive || String(bridge.pilotPlace) !== "SHIP" || String(bridge.shipModel || "-") === "-" ? "none"
                                       : (shipInfo ? "ship" : "unmatched")
    readonly property string shipTitle: (String(bridge.shipName || "").trim() !== "" && bridge.shipName !== "-") ? bridge.shipName : bridge.shipModel

    // ---------- small helpers
    function pct(v) { return Number(v) < 0 ? "--" : Math.round(Number(v)) + "%" }
    function pip(name) {
        var m = String(bridge.pips || "").match(new RegExp(name + "\\s*([0-9.]+)", "i"))
        return m ? Number(m[1]) : -1
    }
    function cellColor(kind, v) {
        var t = String(v || "").toUpperCase()
        if (!deck.eliteLive || t === "" || t === "-" || t === "UNKNOWN") return Theme.dimText
        if (kind === "FSD") return t.indexOf("READY") >= 0 || t.indexOf("CLEAR") >= 0 ? Theme.ok
                                 : (t.indexOf("LOCK") >= 0 || t.indexOf("COOL") >= 0 || t.indexOf("CHARG") >= 0) ? Theme.info : Theme.phosphor
        if (kind === "GEAR") return t.indexOf("DOWN") >= 0 || t.indexOf("DEPLOY") >= 0 ? Theme.info : Theme.phosphor
        if (kind === "HARDPOINTS") return t.indexOf("DEPLOY") >= 0 || t.indexOf("OUT") >= 0 ? Theme.info : Theme.phosphor
        return Theme.phosphor
    }
    // event name colour by meaning (green good, amber heads up, red bad, neutral otherwise)
    function eventColor(name) {
        var t = String(name || "").toUpperCase()
        if (/ATTACK|DESTROY|DIED|DAMAGE|HULL|OVERHEAT|SHIELDS DOWN|FAIL|HEAT WARNING/.test(t)) return Theme.bad
        if (/INTERDICT|JUMP|SCAN|MASS LOCK|DENIED|FINE|LOW FUEL|CHARG|WANTED|ROUTE|COMMS/.test(t)) return Theme.info
        if (/DOCKED|GRANTED|SCOOP|REFUEL|REPAIR|REARM|COMPLETE|SOLD|REWARD|BOUNTY/.test(t)) return Theme.ok
        return Theme.phosphor
    }

    // ---------- layout rows
    readonly property real topH: height * 0.555
    readonly property real routeH: height * 0.215
    readonly property real deckY: topH + routeH + g * 2

    // ================================================================= SHIP
    Plate {
        id: shipPanel
        x: 0; y: 0; width: deck.width * 0.52; height: deck.topH
        screwSize: 13 * deck.s
        Dymo { x: 26 * deck.s; y: 14 * deck.s; text: "SHIP" }
        Bezel {
            id: shipBezel
            x: 16 * deck.s; y: 50 * deck.s
            width: parent.width - 32 * deck.s; height: parent.height - 66 * deck.s
            pad: 12 * deck.s
            readonly property real iw: width - pad * 2
            readonly property real ih: height - pad * 2
            readonly property bool down: bridge.shieldState === "DOWN"

            // red wash inside the screen while shields are down
            Rectangle {
                anchors.fill: parent; visible: shipBezel.down
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#00ff3a20" }
                    GradientStop { position: 0.75; color: "#18ff3a20" }
                    GradientStop { position: 1.0; color: "#36ff3a20" }
                }
            }
            // your ship leads the panel: name, model // ident, class
            Column {
                id: ident
                x: 22 * deck.s; y: 8 * deck.s
                width: shipBezel.iw * 0.58
                spacing: 1 * deck.s
                visible: deck.shipState !== "none"
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: String(deck.shipTitle).toUpperCase()
                    color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: Math.max(18, 50 * deck.s); font.letterSpacing: 3 * deck.s
                }
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: String(bridge.shipModel).toUpperCase() + (String(bridge.shipIdent || "") !== "" ? "   //   " + String(bridge.shipIdent).toUpperCase() : "")
                    color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: Math.max(12, 26 * deck.s); font.letterSpacing: 2 * deck.s
                }
                Text {
                    text: "CLASS // " + (deck.shipInfo ? deck.shipInfo.tag : "NOT ON FILE")
                    color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(11, 20 * deck.s); font.letterSpacing: 2 * deck.s
                }
            }
            // ship art with the shield halo (back half behind, front half over)
            Item {
                id: artBox
                // smaller badge (2026-10-10): the class picture sits in its bubble; your loadout gets the room
                x: 14 * deck.s; y: ident.y + ident.height + 30 * deck.s
                width: shipBezel.iw * 0.22; height: Math.min(width * 0.95, shipBezel.ih - y - cells.height - 50 * deck.s)
                readonly property vector2d ringC: Qt.vector2d(0.5, 0.53)
                readonly property vector2d ringR: Qt.vector2d(0.40, 0.15)
                // taller dome and slightly smaller art so long hulls (Corvette, Cutter) sit inside the bubble
                // bubble hidden with no ship; dimmed for a ship with no class on file
                readonly property real haloOpacity: deck.shipState === "none" ? 0 : (deck.shipState === "unmatched" ? 0.35 : 1)
                ShieldHalo { anchors.fill: parent; shield: bridge.shieldState; frontHalf: false; centerAt: artBox.ringC; ringRadii: artBox.ringR; dome: 0.44
                             opacity: artBox.haloOpacity; visible: opacity > 0 }
                ShipArt {
                    // class art is a badge inside the bubble, not the hero
                    x: parent.width * 0.12; y: parent.height * 0.05
                    width: parent.width * 0.76; height: parent.height * 0.76
                    visible: deck.shipState === "ship"
                    source: deck.shipState === "ship" ? Qt.resolvedUrl("../" + deck.app.shipArtSource(bridge.shipModel)) : ""
                    motion: deck.shipInfo ? deck.shipInfo.size : ""
                    alarm: shipBezel.down ? 0.8 : 0
                }
                ContactScanner {
                    anchors.fill: parent
                    visible: deck.shipState !== "ship"
                    centerAt: artBox.ringC; ringRadii: artBox.ringR
                    fontScale: 0.5; textY: 0.04
                    blip: deck.shipState === "unmatched"
                    title: deck.shipState === "none" ? "NO SHIP DATA" : "NO SIGNATURE MATCH"
                    line2: deck.shipState === "none"
                           ? (!deck.eliteLive ? "ELITE NOT RUNNING" : (String(bridge.pilotPlace) === "FOOT" ? "ON FOOT" : (String(bridge.pilotPlace) === "SRV" ? "SRV DEPLOYED" : "WAITING FOR SHIP DATA")))
                           : "CLASS NOT ON FILE"
                    line3: ""
                }
                ShieldHalo { anchors.fill: parent; shield: bridge.shieldState; frontHalf: true; centerAt: artBox.ringC; ringRadii: artBox.ringR; dome: 0.44
                             opacity: artBox.haloOpacity; visible: opacity > 0 }
                Text {
                    id: shieldText
                    x: 4 * deck.s
                    y: parent.height + 14 * deck.s
                    property double downSince: 0
                    property string elapsed: ""
                    text: deck.shipState === "none" ? "SHIELDS // UNKNOWN"
                          : bridge.shieldState === "DOWN" ? "SHIELDS // DOWN  " + elapsed
                          : bridge.shieldState === "UP" ? "SHIELDS // UP" : "SHIELDS // UNKNOWN"
                    color: deck.shipState === "none" ? Theme.dimText : (bridge.shieldState === "UP" ? Theme.ok : (bridge.shieldState === "DOWN" ? Theme.bad : Theme.dimText))
                    font.family: Theme.crtFont; font.pixelSize: Math.max(12, 22 * deck.s); font.letterSpacing: 2 * deck.s
                    function tick() {
                        if (bridge.shieldState !== "DOWN") { downSince = 0; elapsed = ""; return }
                        if (downSince === 0) downSince = Date.now()
                        var sec = Math.floor((Date.now() - downSince) / 1000)
                        elapsed = Math.floor(sec / 60) + ":" + ("0" + (sec % 60)).slice(-2)
                    }
                    Connections { target: bridge; function onStateChanged() { shieldText.tick() } }
                    Timer { interval: 1000; repeat: true; running: bridge.shieldState === "DOWN"; onTriggered: shieldText.tick() }
                    Component.onCompleted: tick()
                }
            }

            // ---- middle: your loadout; while the FSD charges, a charge ring; while scooping, the scoop
            Item {
                id: mid
                x: shipBezel.iw * 0.245; y: ident.y + ident.height + 10 * deck.s
                width: shipBezel.iw * 0.345; height: shipBezel.ih - y - cells.height - 22 * deck.s
                readonly property string mode: !deck.eliteLive ? "loadout"
                                               : (bridge.shipScooping ? "scoop" : (String(bridge.fsdState) === "CHARGING" ? "charge" : "loadout"))
                // charge timing: Elite gives no countdown, so the ring runs from when charging starts
                property double chargeT0: 0
                property real chargeK: 0
                onModeChanged: { if (mode === "charge") { chargeT0 = Date.now(); chargeK = 0 } }
                Timer { interval: 50; repeat: true; running: mid.mode === "charge" && deck.visible
                        onTriggered: { mid.chargeK = Math.min(1, (Date.now() - mid.chargeT0) / 5000); ring.requestPaint() } }

                Column {
                    visible: mid.mode === "loadout"
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width; spacing: 8 * deck.s
                    Text { text: "LOADOUT"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(11, 20 * deck.s); font.letterSpacing: 2 * deck.s }
                    Repeater {
                        model: deck.eliteLive || bridge.shipLoadoutKey.length > 0 ? bridge.shipLoadoutKey : []
                        Item {
                            width: mid.width; height: 50 * deck.s
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#2a9dffb6" }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: String(modelData.name); color: Theme.phosphor
                                   font.family: Theme.crtFont; font.pixelSize: Math.max(13, 30 * deck.s); font.letterSpacing: 1.5 * deck.s }
                            Row {
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 10 * deck.s
                                Rectangle { visible: String(modelData.note || "") !== ""; anchors.verticalCenter: parent.verticalCenter
                                            width: tagT.width + 12 * deck.s; height: tagT.height + 2 * deck.s
                                            color: "transparent"; border.color: Theme.ok; border.width: 1; radius: 3 * deck.s
                                            Text { id: tagT; anchors.centerIn: parent; text: String(modelData.note || ""); color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: Math.max(11, 22 * deck.s) } }
                                Text { text: String(modelData.rating); color: String(modelData.rating) === "NONE" ? Theme.dimText : Theme.ok
                                       font.family: Theme.crtFont; font.pixelSize: Math.max(13, 30 * deck.s) }
                            }
                        }
                    }
                    Text { visible: bridge.shipLoadoutKey.length === 0; text: "WAITING FOR YOUR SHIP'S LOADOUT"; color: Theme.dimText
                           font.family: Theme.crtFont; font.pixelSize: Math.max(12, 24 * deck.s) }
                }
                Item {
                    visible: mid.mode === "charge"
                    anchors.fill: parent
                    Canvas {
                        id: ring
                        width: Math.min(parent.width, parent.height * 0.80); height: width
                        anchors.horizontalCenter: parent.horizontalCenter
                        onPaint: {
                            var c = getContext("2d"); c.reset(); var r = width / 2 - 10 * deck.s
                            c.lineWidth = 14 * deck.s; c.strokeStyle = "rgba(255,184,77,0.15)"
                            c.beginPath(); c.arc(width / 2, height / 2, r, 0, Math.PI * 2); c.stroke()
                            for (var i = 0; i < 40; i++) {
                                if (i / 40 >= mid.chargeK) break
                                c.strokeStyle = "rgba(255,184,77," + (0.4 + 0.6 * i / 40) + ")"
                                var a0 = -Math.PI / 2 + i / 40 * Math.PI * 2, a1 = a0 + Math.PI * 2 / 40 * 0.75
                                c.beginPath(); c.arc(width / 2, height / 2, r, a0, a1); c.stroke()
                            }
                        }
                    }
                    Column {
                        anchors.centerIn: ring
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: String(Math.max(1, Math.ceil(5 * (1 - mid.chargeK)))); color: Theme.info
                               font.family: Theme.crtFont; font.pixelSize: 110 * deck.s }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "FSD CHARGING"; color: Theme.info; font.family: Theme.crtFont; font.pixelSize: 26 * deck.s }
                    }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; width: parent.width
                           horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                           visible: String(bridge.fsdTarget || "-") !== "-"
                           text: "NEXT // " + String(bridge.fsdTarget).toUpperCase(); color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: Math.max(11, 22 * deck.s) }
                }
                Column {
                    visible: mid.mode === "scoop"
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width; spacing: 10 * deck.s
                    Text { text: "FUEL SCOOP // ACTIVE"; color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: Math.max(12, 28 * deck.s) }
                    Text { text: bridge.scoopRate > 0 ? "+" + bridge.scoopRate.toFixed(2) + " T / S" : "SCOOPING..."; color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: 72 * deck.s }
                    Row {
                        id: chev
                        spacing: 6 * deck.s
                        property int phase: 0
                        Timer { interval: 120; repeat: true; running: mid.mode === "scoop" && deck.visible; onTriggered: chev.phase = (chev.phase + 1) % 9 }
                        Repeater { model: 9
                            Text { text: ">"; color: Theme.ok; opacity: 0.25 + 0.75 * ((index - chev.phase + 9) % 9) / 9; font.family: Theme.crtFont; font.pixelSize: 44 * deck.s } }
                    }
                    Text { visible: bridge.scoopFullSec >= 0
                           text: "FULL IN " + Math.floor(bridge.scoopFullSec / 60) + ":" + ("0" + (bridge.scoopFullSec % 60)).slice(-2)
                           color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: Math.max(12, 30 * deck.s) }
                }
            }

            // gauges
            Column {
                id: gauges
                x: shipBezel.iw * 0.62; y: 22 * deck.s
                width: shipBezel.iw * 0.35
                spacing: 8 * deck.s
                Repeater {
                    model: [
                        { name: "HULL", v: bridge.hullPercent, amber: 70, red: 30 },
                        { name: "FUEL", v: bridge.fuelPercent, amber: 25, red: 10 }
                    ]
                    Column {
                        width: gauges.width; spacing: 6 * deck.s
                        readonly property color c: modelData.v < 0 ? Theme.dimText : (modelData.v < modelData.red ? Theme.bad : (modelData.v < modelData.amber ? Theme.info : Theme.ok))
                        Item {
                            width: parent.width; height: hl.height
                            Text { id: hl; text: modelData.name; color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: Math.max(13, 26 * deck.s); font.letterSpacing: 2 * deck.s }
                            Text { anchors.right: parent.right; text: deck.pct(modelData.v); color: parent.parent.c; font.family: Theme.crtFont; font.pixelSize: Math.max(13, 26 * deck.s) }
                        }
                        BlockBar { width: parent.width; height: 26 * deck.s; segments: 22; value: Math.max(0, modelData.v) / 100; known: modelData.v >= 0; color: parent.c }
                        Item { width: 1; height: 10 * deck.s }
                    }
                }
                Item {
                    width: parent.width; height: pl.height
                    Text { id: pl; text: "POWER"; color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: Math.max(13, 26 * deck.s); font.letterSpacing: 2 * deck.s }
                    Text {
                        anchors.right: parent.right
                        text: deck.pip("SYS") < 0 ? "-- / -- / --" : deck.pip("SYS") + " / " + deck.pip("ENG") + " / " + deck.pip("WEP")
                        color: deck.eliteLive ? Theme.phosphor : Theme.dimText
                        font.family: Theme.crtFont; font.pixelSize: Math.max(13, 26 * deck.s)
                    }
                }
                Repeater {
                    model: ["SYS", "ENG", "WEP"]
                    Row {
                        spacing: 12 * deck.s
                        Text { width: 54 * deck.s; text: modelData; color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: Math.max(12, 22 * deck.s) }
                        BlockBar {
                            anchors.verticalCenter: parent.verticalCenter
                            width: gauges.width - 66 * deck.s; height: 18 * deck.s
                            segments: 8; value: Math.max(0, deck.pip(modelData)) / 4; known: deck.pip(modelData) >= 0
                            color: Theme.ok
                        }
                    }
                }
                Item { width: 1; height: 12 * deck.s }
                Repeater {
                    model: [["JUMP RANGE", deck.eliteLive && bridge.shipJumpRange > 0 ? bridge.shipJumpRange.toFixed(1) + " LY" : "--"],
                            ["REBUY", deck.eliteLive && bridge.shipRebuy > 0 ? deck.app.fmtNumber(bridge.shipRebuy) + " CR" : "--"]]
                    Item {
                        required property var modelData
                        required property int index
                        // small windows (720 to 800 tall): no room for REBUY above the status cells
                        visible: index === 0 || deck.s > 0.62
                        width: gauges.width; height: jr.height + 6 * deck.s
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#2a9dffb6" }
                        Text { id: jr; text: modelData[0]; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(12, 22 * deck.s); font.letterSpacing: 2 * deck.s }
                        Text { anchors.right: parent.right; text: modelData[1]; color: modelData[1] === "--" ? Theme.dimText : Theme.ok; font.family: Theme.crtFont; font.pixelSize: Math.max(13, 28 * deck.s) }
                    }
                }
            }

            // status cells along the bottom of the screen
            Row {
                id: cells
                x: 14 * deck.s; y: shipBezel.ih - height - 12 * deck.s
                width: shipBezel.iw - 28 * deck.s; height: 70 * deck.s
                spacing: 10 * deck.s
                Repeater {
                    model: [
                        ["CARGO", bridge.cargoText, "CARGO"],
                        ["FSD", bridge.fsdState, "FSD"],
                        ["GEAR", bridge.gearState, "GEAR"],
                        ["HARDPOINTS", bridge.hardpointsState, "HARDPOINTS"]
                    ]
                    Rectangle {
                        width: (cells.width - cells.spacing * 3) / 4; height: cells.height
                        color: "#0a9dffb6"; border.color: "#2a9dffb6"; border.width: 1
                        Text { x: 12 * deck.s; y: 4 * deck.s; text: modelData[0]; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(10, 18 * deck.s); font.letterSpacing: 1.5 * deck.s }
                        Text {
                            x: 12 * deck.s; anchors.bottom: parent.bottom; anchors.bottomMargin: 4 * deck.s
                            width: parent.width - 20 * deck.s; elide: Text.ElideRight
                            text: String(modelData[1] || "-").toUpperCase()
                            color: deck.cellColor(modelData[2], modelData[1])
                            font.family: Theme.crtFont; font.pixelSize: Math.max(13, 30 * deck.s); font.letterSpacing: 1.5 * deck.s
                        }
                    }
                }
            }
        }
    }

    // ================================================================= EVENT LOG
    Plate {
        id: logPanel
        objectName: "flightLog"
        x: shipPanel.width + deck.g; y: 0
        width: deck.width - x; height: deck.topH
        screwSize: 13 * deck.s
        // step 27: cargo and loadout live here now (moved from Commander), one click away from the log
        property int view: 0          // 0 event log, 1 cargo hold, 2 loadout
        Dymo { x: 26 * deck.s; y: 14 * deck.s; text: ["EVENT LOG", "CARGO HOLD", "LOADOUT"][logPanel.view] }
        SelectorRow {
            anchors.right: parent.right; anchors.rightMargin: 24 * deck.s; y: 10 * deck.s
            options: ["EVENT LOG", "CARGO", "LOADOUT"]
            buttonWidth: 118 * deck.s; buttonHeight: 32 * deck.s
            currentIndex: logPanel.view
            onPicked: (i) => logPanel.view = i
        }
        HoldView {
            visible: logPanel.view > 0
            x: 16 * deck.s; y: 50 * deck.s
            width: parent.width - 32 * deck.s; height: parent.height - 66 * deck.s
            view: logPanel.view === 2 ? 1 : 0
        }
        Bezel {
            visible: logPanel.view === 0
            x: 16 * deck.s; y: 50 * deck.s
            width: parent.width - 32 * deck.s; height: parent.height - 66 * deck.s
            pad: 12 * deck.s
            PhosphorList {
                id: events
                anchors.fill: parent; anchors.margins: 18 * deck.s
                newestFirst: true
                fontSize: Math.max(14, 26 * deck.s)
                model: bridge.recentEvents
                delegate: LogRow {
                    required property var modelData
                    required property int index
                    width: events.list.width
                    opacity: Math.max(0.45, 1.0 - index * 0.05)
                    fontSize: events.fontSize
                    emphasize: index === 0
                    timeW: 0.17; eventW: 0.25
                    time: modelData.time
                    event: String(modelData.event || modelData.text || "")
                    detail: String(modelData.summary || "")
                    eventColor: deck.eventColor(modelData.event || modelData.text)
                }
            }
            Text {
                visible: events.list.count === 0
                anchors.centerIn: parent
                text: bridge.connected ? "WAITING FOR JOURNAL EVENTS" : "STARTING BRIDGE SYSTEMS"
                color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(14, 28 * deck.s)
            }
        }
    }

    // ================================================================= ROUTE
    Plate {
        id: routePanel
        x: 0; y: deck.topH + deck.g
        width: deck.width; height: deck.routeH
        screwSize: 13 * deck.s
        Dymo { x: 26 * deck.s; y: 14 * deck.s; text: "ROUTE // NEXT 5 JUMPS" }
        Bezel {
            id: routeBezel
            x: 16 * deck.s; y: 50 * deck.s
            width: parent.width - 32 * deck.s; height: parent.height - 66 * deck.s
            pad: 12 * deck.s
            readonly property var entries: bridge.navRouteEntries || []
            readonly property bool hasRoute: bridge.destination !== "NO ROUTE" && entries.length > 1
            // up to 6 star nodes (here + 5 jumps); an ELLIPSIS row becomes "+N TO <destination>"
            readonly property var nodes: {
                var out = [], more = 0, dest = ""
                for (var i = 0; i < entries.length; i++) {
                    var e = entries[i]
                    if (String(e.kind) === "ELLIPSIS") { more += Number(e.hiddenCount || 0); continue }
                    if (out.length < 6) out.push(e)
                    else { more += 1; dest = String(e.system) }
                }
                if (more > 0 && dest === "" && out.length > 0 && String(out[out.length - 1].kind) === "DESTINATION") dest = String(out[out.length - 1].system)
                return { list: out, more: more, dest: dest }
            }
            Text {
                x: 22 * deck.s; y: 10 * deck.s
                text: routeBezel.hasRoute
                      ? "DESTINATION // " + bridge.destination.toUpperCase() + (bridge.routeJumps >= 0 ? "     " + bridge.routeJumps + " JUMP" + (bridge.routeJumps === 1 ? "" : "S") : "")
                      : "NO ROUTE PLOTTED // PLOT ONE IN ELITE OR ON NAVIGATION"
                color: routeBezel.hasRoute ? Theme.dimText : Theme.info
                font.family: Theme.crtFont; font.pixelSize: Math.max(13, 24 * deck.s); font.letterSpacing: 2 * deck.s
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 24 * deck.s; y: 14 * deck.s
                spacing: 22 * deck.s
                Repeater {
                    model: [["SCOOPABLE", Theme.ok, true], ["NO SCOOP", Theme.info, true], ["UNKNOWN", Theme.dimText, false]]
                    Row {
                        spacing: 6 * deck.s
                        Rectangle { width: 12 * deck.s; height: width; radius: width / 2; anchors.verticalCenter: parent.verticalCenter
                                    color: modelData[2] ? modelData[1] : "transparent"; border.color: modelData[1]; border.width: 1 }
                        Text { text: modelData[0]; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(10, 18 * deck.s) }
                    }
                }
            }
            Item {
                id: track
                x: 40 * deck.s; y: 44 * deck.s
                width: parent.width - 80 * deck.s - (routeBezel.nodes.more > 0 ? 150 * deck.s : 0)
                height: parent.height - y - 10 * deck.s
                readonly property int n: Math.max(1, routeBezel.nodes.list.length)
                readonly property real step: n > 1 ? width / n : width
                readonly property real ringD: Math.min(height * 0.72, 74 * deck.s)
                // dashed connectors, with a slow dot travelling along the current leg
                Repeater {
                    model: Math.max(0, track.n - 1)
                    Row {
                        x: index * track.step + track.ringD + 12 * deck.s
                        y: track.height / 2 - 1
                        width: track.step - track.ringD - 24 * deck.s
                        spacing: 8 * deck.s
                        clip: true
                        Repeater { model: 40; Rectangle { width: 10 * deck.s; height: Math.max(1, 2 * deck.s); color: Theme.ok; opacity: 0.35 } }
                    }
                }
                Rectangle {
                    visible: routeBezel.hasRoute && track.n > 1
                    width: 10 * deck.s; height: width; radius: width / 2; color: Theme.ok
                    y: track.height / 2 - height / 2
                    property real f: 0
                    x: track.ringD + 12 * deck.s + f * (track.step - track.ringD - 24 * deck.s) - width / 2
                    opacity: Math.sin(f * Math.PI)   // fades in and out at both ends, so the loop has no seam
                    NumberAnimation on f { from: 0; to: 1; duration: 3200; loops: Animation.Infinite; running: routeBezel.visible }
                }
                Repeater {
                    model: routeBezel.nodes.list
                    Item {
                        x: index * track.step; width: track.step; height: track.height
                        readonly property bool known: modelData.scoopable !== null && modelData.scoopable !== undefined
                        readonly property color c: !known ? Theme.dimText : (modelData.scoopable ? Theme.ok : Theme.info)
                        Rectangle {
                            id: ring
                            width: track.ringD; height: width; radius: width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            color: "transparent"; border.color: parent.c; border.width: Math.max(2, 3 * deck.s)
                            opacity: parent.known ? 1 : 0.6
                            Rectangle { anchors.fill: parent; anchors.margins: -6 * deck.s; radius: width / 2; color: "transparent"; border.color: parent.border.color; border.width: 1; opacity: index === 0 ? 0.5 : 0.18 }
                            Text {
                                anchors.centerIn: parent
                                text: String(modelData.starClass || "-") === "-" ? "?" : String(modelData.starClass).toUpperCase().slice(0, 2)
                                color: parent.parent.c
                                font.family: Theme.crtFont; font.pixelSize: Math.max(14, ring.width * 0.46)
                            }
                        }
                        Column {
                            x: ring.width + 16 * deck.s; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - x - 10 * deck.s
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: String(modelData.system || "-").toUpperCase()
                                color: Theme.phosphor
                                font.family: Theme.crtFont; font.pixelSize: Math.max(13, 28 * deck.s); font.letterSpacing: 1 * deck.s
                            }
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: index === 0 ? "YOU ARE HERE"
                                      : "JUMP " + index + (parent.parent.known && !modelData.scoopable ? " // NO SCOOP" : "")
                                color: Theme.dimText
                                font.family: Theme.crtFont; font.pixelSize: Math.max(11, 20 * deck.s)
                            }
                        }
                    }
                }
            }
            Column {
                visible: routeBezel.nodes.more > 0
                anchors.right: parent.right; anchors.rightMargin: 30 * deck.s
                y: track.y + track.height / 2 - height / 2
                width: 130 * deck.s
                Text { text: "> +" + routeBezel.nodes.more; color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: Math.max(14, 30 * deck.s) }
                Text { width: parent.width; elide: Text.ElideRight; text: "TO " + String(routeBezel.nodes.dest || bridge.destination).toUpperCase()
                       color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(10, 18 * deck.s) }
            }
        }
    }

    // ================================================================= ACTION DECK
    Plate {
        id: actionPanel
        x: 0; y: deck.deckY
        width: deck.width; height: deck.height - y
        dark: true
        screwSize: 13 * deck.s
        Dymo { x: 26 * deck.s; y: 14 * deck.s; text: "ACTIONS // FLIGHT DECK" }

        readonly property string bstate: String(bridge.bridgeState || "").toUpperCase()
        readonly property bool inControl: bridge.controlOwner !== "NONE" && bridge.controlOwner !== ""
        readonly property bool bindsReady: bridge.eliteControlsReady
        readonly property string bindsReason: String(bridge.eliteControlReason || "") !== "" ? String(bridge.eliteControlReason).toUpperCase() : "ELITE KEY BINDS NOT FOUND // SEE SETUP > CONTROLS"
        readonly property bool docked: String(bridge.gameState).toUpperCase() === "DOCKED"
        property string lastService: ""

        function keyState(running, needsDock) {
            if (running) return "running"
            if (!bindsReady) return "unavailable"
            if (needsDock && !docked) return "unavailable"
            return "ready"
        }
        function reason(needsDock) { return !bindsReady ? bindsReason : (needsDock && !docked ? "DOCK AT A STATION FIRST" : "") }

        readonly property real keyH: Math.min(height - 66 * deck.s, 150 * deck.s)
        readonly property real keyY: 52 * deck.s + (height - 66 * deck.s - keyH) / 2
        readonly property real cancelW: 300 * deck.s
        readonly property real divW: 60 * deck.s
        readonly property real keyGap: 18 * deck.s
        readonly property real keyW: (width - 26 * deck.s - cancelW - 40 * deck.s - 44 * deck.s - divW - keyGap * 6) / 6

        Row {
            x: 26 * deck.s; y: actionPanel.keyY
            spacing: actionPanel.keyGap
            DeckKey {
                id: dockKey
                width: actionPanel.keyW; height: actionPanel.keyH
                title: "DOCK"
                readonly property bool run: actionPanel.bstate === "DOCKING PROTOCOL" || actionPanel.bstate === "REQUEST DOCKING"
                legend: run ? bridge.bridgeMessage : "REQUEST DOCKING"
                keyState: actionPanel.keyState(run, false); unavailableReason: actionPanel.reason(false)
                tooltip: "REQUEST DOCKING"; tooltipDetail: "BRIDGE ASKS THE STATION AND CUTS THROTTLE"
                onActivated: bridge.requestCommand("dock")
                onDenied: (r) => deck.denied("DOCK UNAVAILABLE", r)
            }
            DeckKey {
                width: actionPanel.keyW; height: actionPanel.keyH
                title: "LAUNCH"
                readonly property bool run: actionPanel.bstate === "AUTO LAUNCH"
                legend: run ? bridge.bridgeMessage : "TAKE OFF"
                keyState: actionPanel.keyState(run, false); unavailableReason: actionPanel.reason(false)
                tooltip: "LAUNCH FROM THE PAD"; tooltipDetail: "AUTO LAUNCH SEQUENCE"
                onActivated: bridge.requestCommand("launch")
                onDenied: (r) => deck.denied("LAUNCH UNAVAILABLE", r)
            }
            DeckKey {
                width: actionPanel.keyW; height: actionPanel.keyH
                title: "CLEAR + JUMP"
                readonly property bool run: actionPanel.bstate.indexOf("CLEAR STATION") === 0
                legend: run ? bridge.bridgeMessage : "EXIT & ENGAGE FSD"
                keyState: actionPanel.keyState(run, false); unavailableReason: actionPanel.reason(false)
                tooltip: "CLEAR THE STATION AND JUMP"; tooltipDetail: "LEAVES MASS LOCK, THEN ENGAGES THE FSD"
                onActivated: bridge.requestCommand("clear")
                onDenied: (r) => deck.denied("CLEAR + JUMP UNAVAILABLE", r)
            }
            // groove divider + group label
            Item {
                width: actionPanel.divW; height: actionPanel.keyH
                Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 4 * deck.s; height: parent.height; radius: 2 * deck.s; color: "#0b0b0a"; border.color: "#3e3b32"; border.width: 1 }
            }
            Repeater {
                model: [["REFUEL", "station_refuel", "FILL THE TANK"], ["REPAIR", "station_repair", "FIX HULL + MODULES"], ["REARM", "station_rearm", "RESTOCK AMMO"]]
                DeckKey {
                    width: actionPanel.keyW; height: actionPanel.keyH
                    cap: "grey"
                    title: modelData[0]
                    readonly property bool run: actionPanel.bstate === "SHIP SERVICES" && actionPanel.lastService === modelData[1]
                    legend: run ? bridge.bridgeMessage : modelData[2]
                    keyState: actionPanel.keyState(run, true); unavailableReason: actionPanel.reason(true)
                    tooltip: modelData[0] + " AT THIS STATION"; tooltipDetail: "ONE STATION SERVICE, RUN NOW"
                    onActivated: { actionPanel.lastService = modelData[1]; bridge.requestCommand(modelData[1]) }
                    onDenied: (r) => deck.denied(modelData[0] + " UNAVAILABLE", r)
                }
            }
        }
        Text {
            x: 26 * deck.s + (actionPanel.keyW + actionPanel.keyGap) * 3 + actionPanel.divW + actionPanel.keyGap
            y: actionPanel.keyY - height - 6 * deck.s
            text: "STATION SERVICES"
            color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: Math.max(8, 13 * deck.s); font.letterSpacing: 3 * deck.s
        }

        // CANCEL: pinned far right, the only key with hazard stripes; glows while the Bridge is flying
        Item {
            x: actionPanel.width - actionPanel.cancelW - 40 * deck.s
            y: actionPanel.keyY
            width: actionPanel.cancelW; height: actionPanel.keyH
            Glow { target: cancelKey; color: "#ff5040"; spread: 34 * deck.s; radius: 8 * deck.s; intensity: actionPanel.inControl ? 0.8 : 0 }
            DeckKey {
                id: cancelKey
                anchors.fill: parent
                title: "CANCEL"; legend: "STOP ALL AUTOMATION"
                cap: "red"; hazard: true
                tooltip: "STOP ALL AUTOMATION"; tooltipDetail: "BRIDGE RELEASES YOUR CONTROLS"
                onActivated: bridge.requestCommand("cancel")
            }
        }
    }
}
