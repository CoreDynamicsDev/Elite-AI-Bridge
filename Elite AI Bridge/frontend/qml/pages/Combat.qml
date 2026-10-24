// COMBAT (page 2). Retro redesign, build step 7 (mockups combat_v3.png, combat_bounty_hunting_v1.png).
// Two views on the strip under the identity bar: TACTICAL and BOUNTY HUNTING.
// Same bridge data and the same commands as v1.0.1; only the presentation changed.
import QtQuick
import "../skin"

Item {
    id: cb
    property var app
    property bool demo: false                 // first orientation tour shows a demo target
    property int utilityMode: 0               // 0 tactical, 1 bounty hunting (name kept for ui_context)
    signal denied(string title, string reason)

    // tour highlight targets (Main.qml pageHelpTarget)
    readonly property Item deckTarget: utilityMode === 0 ? tacDeck : bhDeck
    readonly property Item viewTarget: viewStrip
    readonly property Item infoTarget: utilityMode === 0 ? infoColumn : sitesPanel

    readonly property real s: Theme.s
    readonly property real g: Math.max(8, 14 * s)

    // ---------- target data (demo values during the first tour)
    readonly property bool tPresent: demo || bridge.combatTargetPresent
    readonly property string tShip: demo ? "Vulture" : String(bridge.combatTargetShip)
    readonly property string tPilot: demo ? "Kael Vorn" : String(bridge.combatTargetPilot)
    readonly property string tFaction: demo ? "Crimson Veil Syndicate" : String(bridge.combatTargetFaction)
    readonly property string tLegal: demo ? "WANTED" : String(bridge.combatTargetLegal)
    readonly property string tRank: demo ? "DANGEROUS" : String(bridge.combatTargetRank)
    readonly property int tHull: demo ? 78 : bridge.combatTargetHullPercent
    readonly property int tShield: demo ? 46 : bridge.combatTargetShieldPercent
    readonly property string tBounty: demo ? "842,500 CR" : String(bridge.combatTargetBounty)
    readonly property string tSub: demo ? "POWER PLANT" : String(bridge.combatTargetSubsystem)
    readonly property int tSubPct: demo ? 68 : bridge.combatTargetSubsystemPercent
    readonly property int tScan: demo ? 3 : bridge.combatTargetScanStage
    readonly property bool wanted: tLegal.toUpperCase() === "WANTED"

    // ---------- live combat extras (all from real data)
    readonly property var sweep: demo ? [
        { ship: "vulture", pilot: "Kael Vorn", legal: "WANTED", best: true, eligible: true },
        { ship: "cobra_mk_iii", pilot: "-", legal: "WANTED", best: false, eligible: true },
        { ship: "viper_mk_iii", pilot: "-", legal: "CLEAN", best: false, eligible: false }
    ] : (bridge.combatSweepContacts || [])
    function hullSize(t) {
        t = String(t || "").toLowerCase().replace(/[^a-z0-9]/g, "")
        if (/anaconda|cutter|corvette|type9|type10|beluga|panther|mandalay|typex/.test(t)) return 3
        if (/vulture|python|krait|ferdelance|mamba|chieftain|challenger|crusader|gunship|dropship|assault|clipper|asp|alliance|keelback|type7|type8|orca|dolphin|cobramkv|cobramkiv|corsair/.test(t)) return 2
        return 1
    }
    readonly property var ranks: ["HARMLESS", "MOSTLY HARMLESS", "NOVICE", "COMPETENT", "EXPERT", "MASTER", "DANGEROUS", "DEADLY", "ELITE"]
    function threatClass() {
        if (!tPresent) return [0, "-", Theme.dimText]
        var r = ranks.indexOf(String(tRank).toUpperCase())
        var score = hullSize(tShip) + (r < 0 ? 1 : r / 2.7)
        if (score >= 5.4) return [4, "EXTREME", Theme.bad]
        if (score >= 4.0) return [3, "HIGH", Theme.info]
        if (score >= 2.6) return [2, "MEDIUM", Theme.phosphor]
        return [1, "LOW", Theme.ok]
    }
    function parsePair(v) {
        var m = String(v || "").match(/^\s*([0-9,]+)\s*\/\s*([0-9,]+)/)
        return m ? [Number(m[1].replace(/,/g, "")), Number(m[2].replace(/,/g, ""))] : [0, 0]
    }
    readonly property var bountyPair: demo ? [4, 1240000] : parsePair(rowValue(bridge.combatSessionRows, "BOUNTIES"))
    readonly property var bondPair: demo ? [0, 0] : parsePair(rowValue(bridge.combatSessionRows, "BONDS"))
    readonly property int sessionKills: bountyPair[0] + bondPair[0]
    readonly property real sessionCr: bountyPair[1] + bondPair[1]
    function fmtCr(v) { return Math.round(v).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",") + " CR" }
    // odometer: the session total rolls up when a bounty lands
    QtObject {
        id: odo
        property real shown: cb.sessionCr
        property bool rolling: false
        Behavior on shown { NumberAnimation { id: odoAnim; duration: 1600; easing.type: Easing.OutCubic
                                              onRunningChanged: odo.rolling = running } }
    }
    // time on the current target
    property double engagedSince: 0
    property string engagedText: "0:00"
    readonly property string targetIdent: tPresent ? (tShip + "|" + tPilot) : ""
    onTargetIdentChanged: { engagedSince = tPresent ? Date.now() : 0; tickEngaged() }
    function tickEngaged() {
        if (!tPresent || engagedSince === 0) { engagedText = "0:00"; return }
        var sec = Math.floor((Date.now() - engagedSince) / 1000)
        engagedText = Math.floor(sec / 60) + ":" + ("0" + (sec % 60)).slice(-2)
    }
    Timer { interval: 1000; repeat: true; running: cb.visible && cb.tPresent; onTriggered: cb.tickEngaged() }
    // always come back to TACTICAL after leaving the page
    onVisibleChanged: if (!visible) utilityMode = 0

    function rowValue(rows, label) {
        rows = rows || []
        for (var i = 0; i < rows.length; i++) if (String(rows[i].label) === label) return String(rows[i].value)
        return "-"
    }
    function rowLevel(rows, label) {
        rows = rows || []
        for (var i = 0; i < rows.length; i++) if (String(rows[i].label) === label) return String(rows[i].level)
        return "info"
    }
    function levelColor(l) { return l === "bad" ? Theme.bad : (l === "warn" ? Theme.info : (l === "ok" ? Theme.ok : Theme.phosphor)) }
    function nice(t) { t = String(t || "-"); return t === "-" ? "-" : t.replace(/_/g, " ").toUpperCase() }

    // ---------- shared deck helpers
    readonly property string bstate: String(bridge.bridgeState || "").toUpperCase()
    readonly property bool inControl: bridge.controlOwner !== "NONE" && bridge.controlOwner !== ""
    readonly property bool bindsReady: bridge.eliteControlsReady
    readonly property string bindsReason: String(bridge.eliteControlReason || "") !== "" ? String(bridge.eliteControlReason).toUpperCase() : "ELITE KEY BINDS NOT FOUND // SEE SETUP > CONTROLS"
    function keyState(running) { return running ? "running" : (bindsReady ? "ready" : "unavailable") }

    // ---------- layout rows
    readonly property real stripH: 88 * s
    readonly property real bodyY: stripH + g
    readonly property real deckH: height * 0.175
    readonly property real deckY: height - deckH
    readonly property real bodyH: deckY - g - bodyY

    // ================================================================= VIEW STRIP + ANNUNCIATORS
    Plate {
        id: viewStrip
        x: 0; y: 0; width: cb.width; height: cb.stripH
        screwSize: 11 * cb.s
        Text {
            x: 26 * cb.s; anchors.verticalCenter: parent.verticalCenter
            text: "VIEW"; color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: Math.max(8, 13 * cb.s); font.letterSpacing: 3 * cb.s
        }
        Row {
            id: views
            x: 82 * cb.s; y: 8 * cb.s
            spacing: 12 * cb.s
            Repeater {
                model: ["TACTICAL", "BOUNTY HUNTING"]
                LitButton {
                    width: 300 * cb.s; height: cb.stripH - 18 * cb.s
                    title: modelData
                    on: cb.utilityMode === index
                    onActivated: cb.utilityMode = index
                }
            }
        }
        StatusPanel {
            id: annun
            x: views.x + views.width + 30 * cb.s; y: 6 * cb.s
            width: viewStrip.width - x - 22 * cb.s; height: cb.stripH - 12 * cb.s
            items: [
                    ["COMBAT ACTIVE", cb.demo || bridge.combatActive ? "a" : ""],
                    ["UNDER ATTACK", bridge.combatUnderAttack ? "r" : ""],
                    ["BEING SCANNED", bridge.combatScanAlertActive ? "a" : ""],
                    ["INTERDICTION", /INTERDICT/i.test(String(bridge.combatThreatWarning)) ? "r" : ""],
                    ["OVERHEATING", cb.rowValue(bridge.combatStatusRows, "HEAT") === "OVERHEATING" ? "r" : ""],
                    ["HARDPOINTS OUT", cb.rowValue(bridge.combatStatusRows, "HARDPOINTS") === "DEPLOYED" ? "a" : ""],
                    ["MASS LOCKED", cb.rowValue(bridge.combatStatusRows, "MASS LOCK") === "YES" ? "a" : ""]
                ]
        }
    }

    // ================================================================= TACTICAL VIEW
    Item {
        id: tactical
        visible: cb.utilityMode === 0
        x: 0; y: cb.bodyY; width: cb.width; height: cb.bodyH
        readonly property real topH: height * 0.645
        readonly property real leftW: width * 0.545

        // ---------------------------------------------------- TARGET (cool factor)
        Plate {
            id: targetPanel
            x: 0; y: 0; width: tactical.leftW; height: tactical.topH
            screwSize: 13 * cb.s
            Dymo { x: 26 * cb.s; y: 14 * cb.s; text: "TARGET" }
            Bezel {
                id: tBezel
                x: 16 * cb.s; y: 50 * cb.s
                width: parent.width - 32 * cb.s; height: parent.height - 66 * cb.s
                pad: 12 * cb.s
                readonly property real iw: width - pad * 2
                readonly property real ih: height - pad * 2

                // red edge flash while taking fire (UnderAttack from the journal)
                Rectangle {
                    anchors.fill: parent; anchors.margins: -2 * cb.s; z: 5
                    color: "transparent"; border.color: Theme.bad; border.width: Math.max(2, 4 * cb.s); radius: 6 * cb.s
                    visible: bridge.combatUnderAttack
                    SequentialAnimation on opacity { running: bridge.combatUnderAttack; loops: Animation.Infinite
                        NumberAnimation { from: 0.9; to: 0.15; duration: 450 } NumberAnimation { from: 0.15; to: 0.9; duration: 450 } }
                }
                // drift clock: one 24 s loop; ship 2 cycles, reticle 3 (whole-number ratios, no seam)
                Item {
                    id: scope
                    x: 0; y: 0; width: tBezel.iw * 0.48; height: tBezel.ih
                    property real th: 0
                    NumberAnimation on th { from: 0; to: 6.28318; duration: 24000; loops: Animation.Infinite; running: cb.visible && cb.utilityMode === 0 && cb.tPresent }
                    readonly property real sx: cb.tPresent ? 9 * cb.s * Math.sin(2 * th) : 0
                    readonly property real sy: cb.tPresent ? 6 * cb.s * Math.sin(4 * th + 0.6) : 0
                    readonly property real rx: cb.tPresent ? 18 * cb.s * Math.sin(3 * th + 0.65) : 0
                    readonly property real ry: cb.tPresent ? 11 * cb.s * Math.cos(6 * th + 0.2) : 0
                    // Elite only reports target shields/hull at scan time, so the ring shows the scan itself.
                    readonly property real lit: cb.tPresent ? Math.max(0, Math.min(1, cb.tScan / 3)) : 0
                    readonly property bool done: cb.tPresent && cb.tScan >= 3

                    // amber shield ring: back half behind the ship, front half over it.
                    // The lit arc (target shield %) orbits once every 24 s.
                    Canvas {
                        property bool themeAmber: Theme.amber   // LAB themes: repaint when the screen theme changes
                        onThemeAmberChanged: requestPaint()
                        id: ringBack
                        anchors.fill: parent
                        visible: cb.tPresent
                        property real spin: Math.floor(scope.th * 120) / 120   // ~30 repaints a second, not every frame
                        onSpinChanged: requestPaint()
                        onPaint: scope.paintRing(getContext("2d"), width, height, false)
                    }
                    // class art for ships on file; the contact scanner for anything else
                    readonly property string kind: cb.tPresent ? cb.app.contactKind(cb.tShip) : "none"
                    readonly property var info: kind === "ship" ? cb.app.shipClassInfo(cb.tShip) : null
                    ShipArt {
                        x: scope.width * 0.10 + scope.sx; y: scope.height * 0.10 + scope.sy
                        width: scope.width * 0.80; height: scope.height * 0.78
                        visible: scope.kind === "ship"
                        source: scope.kind === "ship" ? Qt.resolvedUrl("../" + cb.app.shipArtSource(cb.tShip)) : ""
                        motion: scope.info ? scope.info.size : ""
                        alarm: 0
                    }
                    ContactScanner {
                        anchors.fill: parent
                        visible: scope.kind !== "ship"
                        centerAt: Qt.vector2d(0.5, 0.62); ringRadii: Qt.vector2d(0.42, 0.13)
                        opacity: scope.kind === "none" ? 0.35 : 1
                        blip: scope.kind !== "none"
                        fontScale: 0.8
                        textY: 0.30
                        title: scope.kind === "nonship" ? "CONTACT // NON-STANDARD" : (scope.kind === "unmatched" ? "NO SIGNATURE MATCH" : "")
                        line2: scope.kind === "nonship" ? "NOT A SHIP CLASS" : (scope.kind === "unmatched" ? "CLASS NOT ON FILE" : "")
                        line3: ""
                    }
                    Canvas {
                        property bool themeAmber: Theme.amber   // LAB themes: repaint when the screen theme changes
                        onThemeAmberChanged: requestPaint()
                        id: ringFront
                        anchors.fill: parent
                        visible: cb.tPresent
                        property real spin: Math.floor(scope.th * 120) / 120   // ~30 repaints a second, not every frame
                        onSpinChanged: requestPaint()
                        onPaint: scope.paintRing(getContext("2d"), width, height, true)
                    }
                    function paintRing(c, w, h, front) {
                        c.reset()
                        var cx = w * 0.5, cy = h * 0.62, rx = w * 0.42, ry = h * 0.13
                        var a0 = front ? 0 : Math.PI, a1 = front ? Math.PI : 2 * Math.PI
                        var n = 72
                        c.lineCap = "round"
                        for (var i = 0; i < n; i++) {
                            var a = a0 + (a1 - a0) * (i + 0.15) / n, b = a0 + (a1 - a0) * (i + 0.75) / n
                            // position along the full ring relative to the orbiting start (0..1)
                            var p = ((a / (2 * Math.PI)) - scope.th / (2 * Math.PI) + 2) % 1
                            var on = p < scope.lit
                            var rgb = scope.done ? Theme.rgb("125,255,156") : Theme.rgb("255,184,77")
                            c.strokeStyle = on ? "rgba(" + rgb + "," + (front ? 0.95 : 0.55) + ")" : "rgba(" + rgb + "," + (front ? 0.16 : 0.10) + ")"
                            c.lineWidth = on ? Math.max(2, 4 * cb.s) : Math.max(1, 2 * cb.s)
                            c.beginPath()
                            c.moveTo(cx + rx * Math.cos(a), cy + ry * Math.sin(a))
                            c.lineTo(cx + rx * Math.cos(b), cy + ry * Math.sin(b))
                            c.stroke()
                        }
                    }
                    // reticle: corner brackets + LOCK once the scan is complete
                    Item {
                        id: ret
                        width: Math.min(scope.width, scope.height) * 0.78; height: width * 0.86
                        x: (scope.width - width) / 2 + scope.rx; y: (scope.height - height) / 2 + scope.ry
                        opacity: cb.tPresent ? 1 : 0.3
                        readonly property real arm: Math.max(10, 26 * cb.s)
                        readonly property real thk: Math.max(2, 3 * cb.s)
                        readonly property color c: cb.tPresent ? Theme.ok : Theme.dimText
                        Repeater {
                            model: [[0, 0, 1, 1], [1, 0, -1, 1], [0, 1, 1, -1], [1, 1, -1, -1]]
                            Item {
                                x: modelData[0] * ret.width; y: modelData[1] * ret.height
                                Rectangle { x: modelData[2] > 0 ? 0 : -ret.arm; y: modelData[3] > 0 ? 0 : -ret.thk; width: ret.arm; height: ret.thk; color: ret.c }
                                Rectangle { x: modelData[2] > 0 ? 0 : -ret.thk; y: modelData[3] > 0 ? 0 : -ret.arm; width: ret.thk; height: ret.arm; color: ret.c }
                            }
                        }
                        Text {
                            visible: cb.tPresent && cb.tScan >= 3
                            x: ret.width + 8 * cb.s; y: -height / 2
                            text: "LOCK"; color: Theme.ok
                            font.family: Theme.crtFont; font.pixelSize: Math.max(12, 24 * cb.s); font.letterSpacing: 2 * cb.s
                        }
                    }
                    // scan progress
                    Row {
                        x: 18 * cb.s; anchors.bottom: parent.bottom; anchors.bottomMargin: 8 * cb.s
                        spacing: 6 * cb.s
                        Text { text: "SCAN"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(10, 18 * cb.s) }
                        Repeater {
                            model: 3
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 12 * cb.s; height: width
                                        color: cb.tPresent && index < cb.tScan ? Theme.ok : "transparent"; border.color: Theme.dimText; border.width: 1 }
                        }
                        Text {
                            text: !cb.tPresent ? "" : (cb.tScan >= 3 ? "COMPLETE" : "STAGE " + cb.tScan + " OF 3")
                            color: cb.tScan >= 3 ? Theme.ok : Theme.info; font.family: Theme.crtFont; font.pixelSize: Math.max(10, 18 * cb.s)
                        }
                    }
                    Text {
                        visible: !cb.tPresent
                        anchors.centerIn: parent
                        text: "NO TARGET LOCKED"
                        color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(14, 32 * cb.s); font.letterSpacing: 3 * cb.s
                    }
                }

                // target data
                Column {
                    id: tdata
                    x: tBezel.iw * 0.50; y: 14 * cb.s
                    width: tBezel.iw * 0.48
                    spacing: 6 * cb.s
                    Text { text: "CONTACT"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(10, 18 * cb.s) }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: cb.tPresent ? cb.nice(cb.tShip) : "NO CONTACT"
                        color: cb.tPresent ? Theme.ok : Theme.dimText
                        font.family: Theme.crtFont; font.pixelSize: Math.max(16, 44 * cb.s); font.letterSpacing: 2 * cb.s
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: cb.tPresent ? cb.nice(cb.tPilot) + "  //  " + cb.nice(cb.tFaction) : "TARGET A SHIP IN ELITE, OR PRESS HIGHEST THREAT"
                        color: cb.tPresent ? Theme.phosphor : Theme.dimText
                        font.family: Theme.crtFont; font.pixelSize: Math.max(11, 22 * cb.s)
                    }
                    // LEGAL | BOUNTY (largest) | RANK
                    Row {
                        width: parent.width; height: 74 * cb.s
                        spacing: 8 * cb.s
                        Repeater {
                            model: [
                                ["LEGAL", cb.tPresent ? cb.nice(cb.tLegal) : "-", cb.wanted ? Theme.info : Theme.phosphor, 0.24],
                                ["BOUNTY", cb.tPresent ? String(cb.tBounty).toUpperCase() : "-", Theme.ok, 0.46],
                                ["RANK", cb.tPresent ? cb.nice(cb.tRank) : "-", Theme.phosphor, 0.30]
                            ]
                            Rectangle {
                                width: (tdata.width - 16 * cb.s) * modelData[3]; height: parent.height
                                color: Theme.t("#0a9dffb6"); border.color: index === 1 && cb.tPresent && cb.tBounty !== "-" ? Theme.t("#667dff9c") : Theme.t("#2a9dffb6"); border.width: 1
                                Text { x: 10 * cb.s; y: 4 * cb.s; text: modelData[0]; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(9, 16 * cb.s) }
                                Text {
                                    x: 10 * cb.s; anchors.bottom: parent.bottom; anchors.bottomMargin: 4 * cb.s
                                    width: parent.width - 18 * cb.s; height: parent.height * 0.6
                                    verticalAlignment: Text.AlignBottom; elide: Text.ElideRight
                                    fontSizeMode: Text.HorizontalFit; minimumPixelSize: Math.max(10, 16 * cb.s)
                                    text: modelData[1]; color: modelData[1] === "-" ? Theme.dimText : modelData[2]
                                    font.family: Theme.crtFont; font.pixelSize: (index === 1 ? 40 : 26) * cb.s
                                }
                            }
                        }
                    }
                    // THREAT CLASS: worked out from hull size and pilot rank (both real journal values)
                    Item {
                        width: parent.width; height: 34 * cb.s
                        readonly property var tc: cb.threatClass()
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "THREAT CLASS"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(10, 20 * cb.s) }
                        Row {
                            x: parent.width * 0.36; anchors.verticalCenter: parent.verticalCenter
                            spacing: 4 * cb.s
                            Repeater {
                                model: 4
                                Rectangle { width: 30 * cb.s; height: 14 * cb.s; anchors.verticalCenter: parent.verticalCenter
                                            color: index < parent.parent.tc[0] ? parent.parent.tc[2] : Theme.t("#1a9dffb6"); border.color: Theme.t("#339dffb6"); border.width: 1 }
                            }
                        }
                        Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: parent.tc[1]; color: parent.tc[2]
                               font.family: Theme.crtFont; font.pixelSize: Math.max(12, 26 * cb.s); font.letterSpacing: 2 * cb.s }
                    }
                    // ENGAGEMENT: time on this target, session bounty odometer, kills
                    Row {
                        width: parent.width; height: 70 * cb.s
                        spacing: 8 * cb.s
                        Repeater {
                            model: [
                                ["ENGAGED", cb.tPresent ? cb.engagedText : "--:--", cb.tPresent ? Theme.info : Theme.dimText, 0.27],
                                ["SESSION BOUNTIES", cb.fmtCr(odo.shown), Theme.ok, 0.48],
                                ["KILLS", String(cb.sessionKills), Theme.phosphor, 0.25]
                            ]
                            Rectangle {
                                width: (tdata.width - 16 * cb.s) * modelData[3]; height: parent.height
                                color: index === 1 && odo.rolling ? Theme.t("#227dff9c") : Theme.t("#0a9dffb6")
                                border.color: index === 1 && odo.rolling ? Theme.t("#997dff9c") : Theme.t("#2a9dffb6"); border.width: 1
                                Behavior on color { ColorAnimation { duration: 400 } }
                                Text { x: 10 * cb.s; y: 4 * cb.s; text: modelData[0]; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(9, 16 * cb.s) }
                                Text {
                                    x: 10 * cb.s; anchors.bottom: parent.bottom; anchors.bottomMargin: 4 * cb.s
                                    width: parent.width - 18 * cb.s; height: parent.height * 0.6
                                    verticalAlignment: Text.AlignBottom; elide: Text.ElideRight
                                    fontSizeMode: Text.HorizontalFit; minimumPixelSize: Math.max(10, 16 * cb.s)
                                    text: modelData[1]; color: modelData[2]
                                    font.family: index === 1 ? Theme.counterFont : Theme.crtFont; font.pixelSize: (index === 1 ? 32 : 30) * cb.s
                                }
                            }
                        }
                    }
                    // CONTACTS from the last FIND BEST TARGET sweep
                    Item {
                        width: parent.width; height: 24 * cb.s
                        Text { anchors.bottom: parent.bottom; text: "CONTACTS // LAST SWEEP"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(9, 17 * cb.s) }
                        Text { anchors.right: parent.right; anchors.bottom: parent.bottom; text: cb.sweep.length > 0 ? String(bridge.combatSweepTime) : ""
                               color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(9, 17 * cb.s) }
                    }
                    Item {
                        width: parent.width; height: Math.max(40, tBezel.ih - tdata.y - y - 10 * cb.s)
                        clip: true
                        Column {
                            id: sweepCol
                            width: parent.width
                            readonly property real rowH: Math.max(14, 23 * cb.s)
                            Repeater {
                                model: cb.sweep.slice(0, Math.max(1, Math.floor(sweepCol.parent.height / sweepCol.rowH)))
                                Item {
                                    width: tdata.width; height: sweepCol.rowH
                                    readonly property bool legalWanted: String(modelData.legal) === "WANTED"
                                    Rectangle { anchors.fill: parent; visible: modelData.best; color: Theme.t("#227dff9c"); border.color: Theme.t("#667dff9c"); border.width: 1 }
                                    Text { x: 6 * cb.s; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.55; elide: Text.ElideRight
                                           text: (modelData.best ? "> " : "  ") + cb.nice(modelData.ship) + (String(modelData.pilot) !== "-" && String(modelData.pilot) !== "" ? "  " + cb.nice(modelData.pilot) : "")
                                           color: modelData.best ? Theme.ok : (modelData.eligible ? Theme.phosphor : Theme.dimText); font.family: Theme.crtFont; font.pixelSize: Math.max(10, 20 * cb.s) }
                                    Text { anchors.right: parent.right; anchors.rightMargin: 6 * cb.s; anchors.verticalCenter: parent.verticalCenter
                                           text: (Number(modelData.group || 1) > 1 ? "GROUP OF " + modelData.group + " // " : "") + (modelData.best ? "BEST // " + modelData.legal : modelData.legal)
                                           color: parent.legalWanted ? Theme.info : ((modelData.legal === "CLEAN" || modelData.legal === "AUTHORITY") ? Theme.dimText : (Number(modelData.group || 1) > 1 ? Theme.info : Theme.phosphor))
                                           font.family: Theme.crtFont; font.pixelSize: Math.max(10, 20 * cb.s) }
                                }
                            }
                        }
                        Text {
                            visible: cb.sweep.length === 0
                            text: "NO SWEEP YET // FIND BEST TARGET LISTS EVERY SHIP IN RANGE"
                            width: parent.width; wrapMode: Text.WordWrap
                            color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(10, 18 * cb.s)
                        }
                    }
                }
            }
        }

        // ---------------------------------------------------- right column: OWN SHIP + SUPPORT + SESSION
        Item {
            id: infoColumn
            x: tactical.leftW + cb.g; y: 0
            width: tactical.width - x; height: tactical.topH
            readonly property real ownH: height * 0.52

            Plate {
                id: ownPanel
                x: 0; y: 0; width: parent.width; height: infoColumn.ownH
                screwSize: 13 * cb.s
                Dymo { x: 26 * cb.s; y: 14 * cb.s; text: "OWN SHIP" }
                Bezel {
                    id: ownBezel
                    x: 16 * cb.s; y: 50 * cb.s
                    width: parent.width - 32 * cb.s; height: parent.height - 66 * cb.s
                    pad: 12 * cb.s
                    Grid {
                        id: ownGrid
                        anchors.fill: parent; anchors.margins: 14 * cb.s
                        columns: 3; columnSpacing: 8 * cb.s; rowSpacing: 8 * cb.s
                        readonly property var rows: bridge.combatStatusRows
                        Repeater {
                            model: [
                                ["HULL", cb.rowValue(ownGrid.rows, "HULL"), cb.levelColor(cb.rowLevel(ownGrid.rows, "HULL"))],
                                ["SHIELDS", cb.rowValue(ownGrid.rows, "SHIELDS"), cb.levelColor(cb.rowLevel(ownGrid.rows, "SHIELDS"))],
                                ["POWER", cb.rowValue(ownGrid.rows, "POWER").replace(/\s{2,}/g, " // "), Theme.phosphor],
                                ["HUD MODE", cb.rowValue(ownGrid.rows, "HUD MODE"), cb.rowValue(ownGrid.rows, "HUD MODE") === "ANALYSIS" ? Theme.info : Theme.phosphor],
                                ["FIRE GROUP", cb.rowValue(ownGrid.rows, "FIRE GROUP"), Theme.phosphor],
                                ["CARGO", String(bridge.cargoText || "-"), bridge.combatStolenCargo > 0 ? Theme.bad : Theme.phosphor]
                            ]
                            Rectangle {
                                width: (ownGrid.width - ownGrid.columnSpacing * 2) / 3; height: (ownGrid.height - ownGrid.rowSpacing) / 2
                                color: Theme.t("#0a9dffb6"); border.color: Theme.t("#2a9dffb6"); border.width: 1
                                Text { x: 10 * cb.s; y: 4 * cb.s; text: modelData[0]; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(9, 17 * cb.s) }
                                Text {
                                    x: 10 * cb.s; anchors.bottom: parent.bottom; anchors.bottomMargin: 4 * cb.s
                                    width: parent.width - 18 * cb.s; elide: Text.ElideRight
                                    fontSizeMode: Text.HorizontalFit; minimumPixelSize: Math.max(10, 16 * cb.s)
                                    text: String(modelData[1] || "-").toUpperCase(); color: modelData[1] === "UNKNOWN" || modelData[1] === "-" ? Theme.dimText : modelData[2]
                                    font.family: Theme.crtFont; font.pixelSize: Math.max(12, 30 * cb.s)
                                }
                            }
                        }
                    }
                }
            }
            // SUPPORT and SESSION side by side
            Repeater {
                model: 2
                Plate {
                    x: index === 0 ? 0 : (infoColumn.width + cb.g) / 2
                    y: infoColumn.ownH + cb.g
                    width: (infoColumn.width - cb.g) / 2; height: infoColumn.height - y
                    screwSize: 13 * cb.s
                    Dymo { x: 26 * cb.s; y: 14 * cb.s; text: index === 0 ? "SUPPORT" : "SESSION" }
                    Bezel {
                        x: 16 * cb.s; y: 50 * cb.s
                        width: parent.width - 32 * cb.s; height: parent.height - 66 * cb.s
                        pad: 12 * cb.s
                        Column {
                            id: kv
                            anchors.fill: parent; anchors.margins: 14 * cb.s
                            readonly property var sup: bridge.combatSupportRows
                            readonly property var ses: bridge.combatSessionRows
                            readonly property var al: bridge.combatAlertRows
                            readonly property var sesParts: String(cb.rowValue(ses, "SESSION")).split(" / ")
                            readonly property var items: index === 0 ? [
                                ["LIMPETS", String(bridge.combatLimpetReserve), cb.levelColor(cb.rowLevel(sup, "LIMPET RESERVE"))],
                                ["FIGHTER", cb.rowValue(sup, "FIGHTER"), Theme.phosphor],
                                ["CHAFF", cb.rowValue(sup, "CHAFF").replace(" EST. REMAINING", " EST."), cb.levelColor(cb.rowLevel(sup, "CHAFF"))],
                                ["HEAT SINKS", cb.rowValue(sup, "HEAT SINK").replace(" LAST-KNOWN", " LEFT"), cb.levelColor(cb.rowLevel(sup, "HEAT SINK"))],
                                ["COLLECTORS", cb.rowValue(sup, "COLLECTOR COUNT").replace(" DEPLOYED", " OUT"), cb.levelColor(cb.rowLevel(sup, "COLLECTOR COUNT"))]
                            ] : [
                                ["TIME", sesParts[0] || "-", Theme.phosphor],
                                ["ENCOUNTERS", (sesParts[1] || "-").replace(" ENCOUNTER(S)", ""), Theme.phosphor],
                                ["BOUNTIES", cb.rowValue(ses, "BOUNTIES"), Theme.ok],
                                ["BONDS", cb.rowValue(ses, "BONDS"), Theme.phosphor],
                                ["CREW PAY", cb.rowValue(al, "CREW PAY"), cb.levelColor(cb.rowLevel(al, "CREW PAY"))]
                            ]
                            readonly property real fs: Math.max(10, Math.min(24 * cb.s, height / items.length / 1.3))
                            Repeater {
                                model: kv.items
                                Item {
                                    width: kv.width; height: kv.fs * 1.3
                                    Text { text: modelData[0]; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: kv.fs; anchors.verticalCenter: parent.verticalCenter }
                                    Text {
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width * 0.6; horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft
                                        text: String(modelData[1] || "-").toUpperCase(); color: modelData[1] === "-" ? Theme.dimText : modelData[2]
                                        font.family: Theme.crtFont; font.pixelSize: kv.fs
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---------------------------------------------------- AUTOMATION / WING / TACTICAL ADVISORY
        Item {
            id: midRow
            x: 0; y: tactical.topH + cb.g
            width: tactical.width; height: tactical.height - y
            readonly property real autoW: width * 0.315
            readonly property real wingW: width * 0.315

            Plate {
                id: autoPanel
                x: 0; y: 0; width: midRow.autoW; height: midRow.height
                screwSize: 13 * cb.s
                Dymo { x: 26 * cb.s; y: 14 * cb.s; text: "AUTOMATION" }
                Row {
                    x: 26 * cb.s; y: 58 * cb.s
                    width: parent.width - 52 * cb.s
                    spacing: 18 * cb.s
                    Repeater {
                        model: [
                            ["AUTO PIPS", bridge.combatDynamicPipsEnabled, String(bridge.combatDynamicPipsMode || "-"), "pips"],
                            ["AUTO SUBSYS", bridge.combatAutoSubsystemEnabled, "POWER PLANT", "sub"],
                            ["AUTO CHAFF", bridge.combatAutoChaffEnabled, String(bridge.setupAutoChaffProfile || "MED") + " PROFILE // SET IN SETUP", "chaff"]
                        ]
                        Column {
                            width: (autoPanel.width - 52 * cb.s - 36 * cb.s) / 3
                            spacing: 6 * cb.s
                            Text { text: modelData[0]; color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: Math.max(8, 14 * cb.s); font.letterSpacing: 2.5 * cb.s }
                            OnOffPair {
                                on: modelData[1]
                                buttonWidth: (parent.width - 6 * cb.s) / 2; buttonHeight: Math.max(28, 50 * cb.s)
                                available: modelData[3] === "chaff" || cb.bindsReady
                                unavailableReason: cb.bindsReason
                                onChanged: (v) => {
                                    if (modelData[3] === "pips") bridge.requestCommand("combat_toggle_pips")
                                    else if (modelData[3] === "sub") bridge.requestCommand("combat_toggle_subsystem")
                                    else bridge.setSetupBool("auto_chaff", v)
                                }
                                onDenied: (r) => cb.denied(modelData[0] + " UNAVAILABLE", r)
                            }
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: modelData[1] ? String(modelData[2]).toUpperCase() : "PILOT CONTROL"
                                color: Theme.plateText; opacity: 0.65; font.family: Theme.labelFont; font.pixelSize: Math.max(7, 11 * cb.s); font.letterSpacing: 2 * cb.s
                            }
                        }
                    }
                }
            }

            Plate {
                id: wingPanel
                x: midRow.autoW + cb.g; y: 0; width: midRow.wingW; height: midRow.height
                screwSize: 13 * cb.s
                Dymo { x: 26 * cb.s; y: 14 * cb.s; text: "WING" }
                Row {
                    x: 22 * cb.s; y: 50 * cb.s
                    width: parent.width - 44 * cb.s; height: parent.height - 66 * cb.s
                    spacing: 14 * cb.s
                    Repeater {
                        model: 3
                        Column {
                            width: (wingPanel.width - 44 * cb.s - 28 * cb.s) / 3
                            spacing: 8 * cb.s
                            readonly property real kh: (parent.height - 26 * cb.s - 16 * cb.s) / 2
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "WINGMATE " + (index + 1); color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: Math.max(8, 13 * cb.s); font.letterSpacing: 2.5 * cb.s }
                            DeckKey {
                                width: parent.width; height: parent.kh
                                title: "TARGET"; legend: "THEIR TARGET"
                                keyState: cb.keyState(false); unavailableReason: cb.bindsReason
                                tooltip: "TARGET WINGMATE " + (index + 1) + "'S TARGET"
                                onActivated: bridge.requestCommand("combat_wing_target_" + (index + 1))
                                onDenied: (r) => cb.denied("WING TARGET UNAVAILABLE", r)
                            }
                            DeckKey {
                                width: parent.width; height: parent.kh
                                cap: "grey"; title: "NAVLOCK"
                                keyState: cb.keyState(false); unavailableReason: cb.bindsReason
                                tooltip: "TOGGLE NAV LOCK ON WINGMATE " + (index + 1)
                                onActivated: bridge.requestCommand("combat_navlock_" + (index + 1))
                                onDenied: (r) => cb.denied("NAVLOCK UNAVAILABLE", r)
                            }
                        }
                    }
                }
            }

            Plate {
                id: advPanel
                x: wingPanel.x + wingPanel.width + cb.g; y: 0
                width: midRow.width - x; height: midRow.height
                screwSize: 13 * cb.s
                Dymo { x: 26 * cb.s; y: 14 * cb.s; text: "TACTICAL ADVISORY" }
                Bezel {
                    x: 16 * cb.s; y: 50 * cb.s
                    width: parent.width - 32 * cb.s; height: parent.height - 66 * cb.s
                    pad: 12 * cb.s
                    Column {
                        id: adv
                        anchors.fill: parent; anchors.margins: 16 * cb.s
                        spacing: 2 * cb.s
                        // last command result (10 s), then the observer's advisory, then problems only
                        property string lastCmd: ""
                        Timer { id: cmdClear; interval: 10000; onTriggered: adv.lastCmd = "" }
                        Connections {
                            target: bridge
                            function onStateChanged() {
                                var t = String(bridge.combatCommandStatus || "-")
                                if (t !== "-" && t !== adv.seenCmd) { adv.seenCmd = t; adv.lastCmd = t; cmdClear.restart() }
                            }
                        }
                        property string seenCmd: ""
                        readonly property var lines: {
                            var out = []
                            var eg = String(bridge.combatEgressStatus || "-")
                            if (/ACTIVE|FAILED|REFUSED/i.test(eg)) out.push([eg, Theme.bad])
                            if (adv.lastCmd !== "") out.push([adv.lastCmd, /FAIL|REFUSED|BLOCKED|CAN'T|UNAVAILABLE/i.test(adv.lastCmd) ? Theme.bad : Theme.control])
                            var tw = String(bridge.combatThreatWarning || "-")
                            if (tw !== "-") out.push(["THREAT // " + tw, Theme.bad])
                            out.push([cb.demo ? "TARGET SHIELDS FAILING. SUBSYSTEM LOCK HELD." : String(bridge.combatTacticalAdvisory), Theme.ok])
                            var al = bridge.combatAlertRows || []
                            for (var i = 0; i < al.length; i++) {
                                var lv = String(al[i].level)
                                if (lv === "ok" || lv === "info" || al[i].label === "THREAT WATCH") continue
                                out.push([String(al[i].label) + " // " + String(al[i].value), lv === "bad" ? Theme.bad : Theme.info])
                            }
                            return out
                        }
                        Repeater {
                            model: adv.lines
                            Text {
                                width: adv.width; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                                text: String(modelData[0]).toUpperCase(); color: modelData[1]
                                font.family: Theme.crtFont; font.pixelSize: Math.max(11, 23 * cb.s)
                            }
                        }
                    }
                }
            }
        }
    }

    // ================================================================= BOUNTY HUNTING VIEW
    Item {
        id: hunting
        visible: cb.utilityMode === 1
        x: 0; y: cb.bodyY; width: cb.width; height: cb.bodyH
        readonly property real leftW: width * 0.29
        property int selected: 0
        property string lastSearch: ""          // "all" / "low" / "std" / "high" / "haz" (the key shows SHOWING)
        // search row (step 25): SEARCH WITHIN (LY) and SITE WITHIN (LS); defaults 50 LY / 10,000 LS
        readonly property var lyValues: [25, 50, 100, 200]
        readonly property var lsValues: [2500, 5000, 10000, 500000]
        property int lyIdx: 1
        property int lsIdx: 2
        property bool searched: false           // a search finished since the page opened (for the thin-results line)
        function search(kind) {
            lastSearch = kind; selected = 0; searched = true
            bridge.searchRes(kind, String(lyValues[lyIdx]), String(lsValues[lsIdx]))
        }
        function widen() {
            if (lyIdx < lyValues.length - 1) lyIdx++
            if (lastSearch !== "") search(lastSearch)
        }
        readonly property bool thin: searched && !bridge.combatResBusy && rows.length < 5
        readonly property var rows: bridge.combatResRows || []
        onRowsChanged: if (selected >= rows.length) selected = 0
        readonly property var sel: rows.length > 0 ? rows[Math.max(0, Math.min(selected, rows.length - 1))] : null
        function danger(t) {
            t = String(t || "").toUpperCase()
            if (t.indexOf("HAZ") >= 0) return ["HAZARDOUS", Theme.bad]
            if (t.indexOf("HIGH") >= 0) return ["HIGH", Theme.info]
            if (t.indexOf("LOW") >= 0) return ["LOW", Theme.ok]
            if (t.indexOf("STANDARD") >= 0 || t === "RES") return ["STANDARD", Theme.ok]
            return [t, Theme.phosphor]
        }
        function supColor(q) { q = String(q || "").toUpperCase(); return q === "FULL" ? Theme.ok : (q === "PARTIAL" ? Theme.info : (q === "NONE" ? Theme.bad : Theme.dimText)) }
        readonly property string shownKind: {
            if (lastSearch !== "") return lastSearch
            if (rows.length === 0) return ""
            var k = danger(rows[0].type)[0]
            return k === "HAZARDOUS" ? "haz" : (k === "LOW" ? "low" : (k === "STANDARD" ? "std" : "high"))
        }

        Plate {
            id: whyPanel
            x: 0; y: 0; width: hunting.leftW; height: hunting.height * 0.43
            screwSize: 13 * cb.s
            Dymo { x: 26 * cb.s; y: 14 * cb.s; text: "WHERE THE FIGHTS ARE" }
            Bezel {
                x: 16 * cb.s; y: 50 * cb.s
                width: parent.width - 32 * cb.s; height: parent.height - 66 * cb.s
                pad: 12 * cb.s
                Text {
                    anchors.fill: parent; anchors.margins: 18 * cb.s
                    wrapMode: Text.WordWrap; textFormat: Text.StyledText
                    fontSizeMode: Text.Fit; minimumPixelSize: Math.max(10, 16 * cb.s)
                    lineHeight: 1.1
                    color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: Math.max(12, 25 * cb.s)
                    text: "PIRATES HUNT THE MINERS WORKING PLANETARY RINGS. THOSE MINING SPOTS ARE CALLED <font color='" + Theme.info + "'>RESOURCE EXTRACTION SITES</font> (<font color='" + Theme.info + "'>RES</font> IN YOUR NAV PANEL).<br><br>"
                          + "<font color='" + Theme.dimText + "'>GO THERE, SCAN SHIPS, SHOOT ONLY THE ONES MARKED </font><font color='" + Theme.info + "'>WANTED</font><font color='" + Theme.dimText + "'>.</font>"
                }
            }
        }
        Plate {
            id: ladderPanel
            x: 0; y: whyPanel.height + cb.g; width: hunting.leftW; height: hunting.height - y
            screwSize: 13 * cb.s
            Dymo { x: 26 * cb.s; y: 14 * cb.s; text: "DANGER LEVELS // AS SHOWN IN YOUR NAV PANEL" }
            Bezel {
                id: ladBezel
                x: 16 * cb.s; y: 50 * cb.s
                width: parent.width - 32 * cb.s; height: parent.height - 66 * cb.s
                pad: 12 * cb.s
                Column {
                    id: lad
                    anchors.fill: parent; anchors.margins: 16 * cb.s
                    spacing: 2 * cb.s
                    readonly property real fs: Math.max(10, 21 * cb.s)
                    Item {
                        width: lad.width; height: lad.fs * 1.2
                        Text { text: "LEVEL"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: lad.fs * 0.8 }
                        Text { x: lad.width * 0.55; text: "PIRATES"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: lad.fs * 0.8 }
                        Text { anchors.right: parent.right; text: "POLICE"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: lad.fs * 0.8 }
                    }
                    Repeater {
                        model: [["LOW INTENSITY", "RES [LOW]", 1, "YES", Theme.ok], ["STANDARD", "RES", 2, "YES", Theme.ok],
                                ["HIGH INTENSITY", "RES [HIGH]", 3, "SOME", Theme.info], ["HAZARDOUS", "RES [HAZARDOUS]", 4, "NONE", Theme.bad]]
                        Item {
                            id: ladRow
                            readonly property int level: modelData[2]
                            width: lad.width; height: (lad.height - lad.fs * 1.2 - lad.fs * 2.6) / 4
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                Text { text: modelData[0]; color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: lad.fs }
                                Text { text: "\"" + modelData[1] + "\""; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: lad.fs * 0.75 }
                            }
                            Row {
                                x: lad.width * 0.55; anchors.verticalCenter: parent.verticalCenter
                                spacing: 3 * cb.s
                                Repeater {
                                    model: 4
                                    Rectangle { width: 16 * cb.s; height: 12 * cb.s; color: index < ladRow.level ? Theme.info : Theme.t("#1a9dffb6"); border.color: Theme.t("#33ffb84d"); border.width: 1 }
                                }
                            }
                            Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: modelData[3]; color: modelData[4]; font.family: Theme.crtFont; font.pixelSize: lad.fs }
                        }
                    }
                    Text {
                        width: lad.width; wrapMode: Text.WordWrap; textFormat: Text.StyledText
                        text: "NEW TO THIS? START AT <font color='" + Theme.info + "'>HIGH INTENSITY</font>: LOTS OF TARGETS, POLICE STILL NEARBY."
                        color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: lad.fs * 0.8
                    }
                }
            }
        }

        // ---------------------------------------------------- NEAREST SITES
        Plate {
            id: sitesPanel
            x: hunting.leftW + cb.g; y: 0; width: hunting.width - x; height: hunting.height
            screwSize: 13 * cb.s
            Dymo { id: sitesDymo; x: 26 * cb.s; y: 14 * cb.s; text: "NEAREST BOUNTY HUNTING SITES" }
            // search row: how far to look, and how far the site may be from the arrival star
            Row {
                anchors.right: parent.right; anchors.rightMargin: 26 * cb.s; y: 8 * cb.s
                spacing: 12 * cb.s
                Text { anchors.verticalCenter: parent.verticalCenter; text: "SEARCH WITHIN"; color: Theme.plateText
                       font.family: Theme.labelFont; font.weight: Font.DemiBold; font.pixelSize: Math.max(9, 14 * cb.s); font.letterSpacing: 2 * cb.s }
                SelectorRow {
                    options: ["25 LY", "50 LY", "100 LY", "200 LY"]
                    buttonWidth: 82 * cb.s; buttonHeight: 36 * cb.s
                    currentIndex: hunting.lyIdx
                    onPicked: (i) => hunting.lyIdx = i
                }
                Item { width: 18 * cb.s; height: 1 }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "SITE WITHIN"; color: Theme.plateText
                       font.family: Theme.labelFont; font.weight: Font.DemiBold; font.pixelSize: Math.max(9, 14 * cb.s); font.letterSpacing: 2 * cb.s }
                SelectorRow {
                    options: ["2.5K LS", "5K LS", "10K LS", "ANY"]
                    buttonWidth: 82 * cb.s; buttonHeight: 36 * cb.s
                    currentIndex: hunting.lsIdx
                    onPicked: (i) => hunting.lsIdx = i
                }
            }
            Bezel {
                id: siteBezel
                x: 16 * cb.s; y: 50 * cb.s
                width: parent.width - 32 * cb.s; height: parent.height - 66 * cb.s
                pad: 12 * cb.s
                readonly property real iw: width - pad * 2
                readonly property real ih: height - pad * 2
                readonly property real fs: Math.max(11, 23 * cb.s)
                // column x positions (fractions)
                // left edges: # / danger / system / planet; right edges: LY / LS / resupply
                readonly property var cx: [0.0, 0.05, 0.18, 0.40, 0.66, 0.83, 1.0]
                Text {
                    x: 20 * cb.s; y: 12 * cb.s; width: siteBezel.iw - 40 * cb.s; elide: Text.ElideRight
                    text: bridge.combatResBusy ? "SEARCHING..." : String(bridge.combatResStatus || "-").toUpperCase()
                    color: bridge.combatResBusy ? Theme.info : Theme.ok
                    font.family: Theme.crtFont; font.pixelSize: siteBezel.fs * 0.85
                }
                Item {
                    id: siteHead
                    x: 20 * cb.s; y: 46 * cb.s; width: siteBezel.iw - 40 * cb.s - 26 * cb.s; height: siteBezel.fs
                    Repeater {
                        model: [["#", 0, 0], ["DANGER", 1, 0], ["SYSTEM", 2, 0], ["PLANET", 3, 0], ["LY AWAY", 4, 1], ["LS FROM ARRIVAL", 5, 1], ["RESUPPLY", 6, 1]]
                        Text {
                            x: modelData[2] === 0 ? siteHead.width * siteBezel.cx[modelData[1]] : siteHead.width * siteBezel.cx[modelData[1]] - width
                            text: modelData[0]; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: siteBezel.fs * 0.72
                        }
                    }
                }
                PhosphorList {
                    id: sites
                    x: 20 * cb.s; y: siteHead.y + siteHead.height + 6 * cb.s
                    width: siteBezel.iw - 40 * cb.s; height: siteBezel.ih * 0.66 - y
                    fontSize: siteBezel.fs
                    model: hunting.rows
                    delegate: Item {
                        required property var modelData
                        required property int index
                        width: sites.list.width - (sites.overflow ? 0 : 26 * cb.s)
                        height: sites.fontSize * 1.32
                        readonly property bool chosen: index === hunting.selected
                        readonly property var dz: hunting.danger(modelData.type)
                        Rectangle { anchors.fill: parent; visible: parent.chosen || rowPress.containsMouse
                                    color: parent.chosen ? Theme.t("#2a7dff9c") : Theme.t("#127dff9c"); border.color: parent.chosen ? Theme.t("#807dff9c") : "transparent"; border.width: 1 }
                        Text { x: 4 * cb.s; anchors.verticalCenter: parent.verticalCenter; text: (parent.chosen ? ">" : " ") + ("0" + (index + 1)).slice(-2); color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: sites.fontSize }
                        Text { x: parent.width * siteBezel.cx[1]; anchors.verticalCenter: parent.verticalCenter; text: parent.dz[0]; color: parent.dz[1]; font.family: Theme.crtFont; font.pixelSize: sites.fontSize }
                        Text { x: parent.width * siteBezel.cx[2]; width: parent.width * 0.2; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter
                               text: String(modelData.system).toUpperCase(); color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: sites.fontSize }
                        Text { x: parent.width * siteBezel.cx[3]; width: parent.width * 0.16; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter
                               text: String(modelData.body).toUpperCase(); color: Theme.phosphor; opacity: 0.85; font.family: Theme.crtFont; font.pixelSize: sites.fontSize }
                        Text { x: parent.width * siteBezel.cx[4] - width; anchors.verticalCenter: parent.verticalCenter
                               text: String(modelData.distanceLy); color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: sites.fontSize }
                        Text { x: parent.width * siteBezel.cx[5] - width; anchors.verticalCenter: parent.verticalCenter
                               text: String(modelData.distanceLs); color: Number(modelData.resLs) >= 8000 ? Theme.info : Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: sites.fontSize }
                        Text { anchors.right: parent.right; anchors.rightMargin: 6 * cb.s; anchors.verticalCenter: parent.verticalCenter
                               text: String(modelData.support || "-").toUpperCase(); color: hunting.supColor(modelData.support); font.family: Theme.crtFont; font.pixelSize: sites.fontSize * 0.9 }
                        PressArea { id: rowPress; anchors.fill: parent; onActivated: { Theme.cue("tick"); hunting.selected = index } }
                    }
                }
                Text {
                    visible: hunting.rows.length === 0
                    x: 20 * cb.s; y: sites.y + sites.height * 0.35; width: siteBezel.iw - 40 * cb.s; horizontalAlignment: Text.AlignHCenter
                    text: bridge.combatResBusy ? "SEARCHING THE RINGS NEAR YOU..."
                        : hunting.searched ? "NO SITES FOUND WITHIN " + hunting.lyValues[hunting.lyIdx] + " LY"
                        : "NO SITES LISTED YET // PICK A DANGER LEVEL BELOW TO SEARCH"
                    color: bridge.combatResBusy ? Theme.info : Theme.dimText; font.family: Theme.crtFont; font.pixelSize: siteBezel.fs * 1.1
                }
                // few or no results: say why, offer to look further
                Rectangle {
                    visible: hunting.thin
                    x: 20 * cb.s; width: siteBezel.iw - 40 * cb.s; height: thinRow.height + 16 * cb.s
                    y: hunting.rows.length === 0 ? sites.y + sites.height * 0.35 + siteBezel.fs * 2.2 : siteBezel.ih * 0.66 - height - 6 * cb.s
                    radius: 4 * cb.s; color: Theme.t("#1a1406"); border.color: Theme.t("#66ffb84d"); border.width: 1
                    Row {
                        id: thinRow
                        anchors.centerIn: parent; spacing: 16 * cb.s
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, siteBezel.iw - 40 * cb.s - widenKey.width - 60 * cb.s); wrapMode: Text.WordWrap
                            text: (hunting.rows.length === 0 ? "NOTHING REPORTED HERE YET. " : "ONLY " + hunting.rows.length + " FOUND. ")
                                  + "THE LIST ONLY HAS SITES PLAYERS HAVE REPORTED, AND LOW AND STANDARD GET REPORTED LEAST."
                            color: Theme.info; font.family: Theme.crtFont; font.pixelSize: siteBezel.fs * 0.8
                        }
                        LitButton {
                            id: widenKey
                            visible: hunting.lyIdx < hunting.lyValues.length - 1
                            width: visible ? 230 * cb.s : 0; height: 48 * cb.s; centered: true
                            title: "WIDEN TO " + hunting.lyValues[Math.min(hunting.lyIdx + 1, hunting.lyValues.length - 1)] + " LY"
                            onActivated: hunting.widen()
                        }
                    }
                }
                // selected site
                Column {
                    x: 20 * cb.s; y: siteBezel.ih * 0.69
                    width: siteBezel.iw - 40 * cb.s
                    spacing: 4 * cb.s
                    visible: hunting.sel !== null
                    Rectangle { width: parent.width; height: 1; color: Theme.t("#337dff9c") }
                    Text { text: "SELECTED"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: siteBezel.fs * 0.75 }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: hunting.sel ? String(hunting.sel.system).toUpperCase() + "  //  PLANET " + String(hunting.sel.body).toUpperCase() + "  //  " + hunting.danger(hunting.sel.type)[0] + (hunting.danger(hunting.sel.type)[0] === "HAZARDOUS" ? "" : " INTENSITY") : ""
                        color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: siteBezel.fs * 1.35; font.letterSpacing: 1.5 * cb.s
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight; textFormat: Text.StyledText
                        text: !hunting.sel ? "" : String(hunting.sel.distanceLy) + " LY AWAY  //  SITE IS " + String(hunting.sel.distanceLs) + " LS FROM ARRIVAL  //  RESUPPLY: <font color='" + hunting.supColor(hunting.sel.support) + "'>"
                              + String(hunting.sel.support || "-").toUpperCase() + "</font>" + (hunting.sel.supportStation && String(hunting.sel.supportStation) !== "-" ? " AT " + String(hunting.sel.supportStation).toUpperCase() : "")
                        color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: siteBezel.fs * 0.95
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight; textFormat: Text.StyledText
                        text: "THE NEAREST SITE IS PICKED AUTOMATICALLY. CLICK ANY ROW TO CHOOSE ANOTHER, THEN PRESS <font color='" + Theme.info + "'>PLOT: SITE</font>."
                        color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: siteBezel.fs * 0.78
                    }
                }
            }
        }
    }

    // ================================================================= ACTION DECKS
    component DeckPlate: Plate {
        dark: true
        screwSize: 13 * cb.s
        readonly property real keyH: Math.min(height - 66 * cb.s, 150 * cb.s)
        readonly property real keyY: 52 * cb.s + (height - 66 * cb.s - keyH) / 2
        readonly property real cancelW: 270 * cb.s
        readonly property real divW: 40 * cb.s
        readonly property real keyGap: 14 * cb.s
    }
    // groove divider
    component Groove: Item {
        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 4 * cb.s; height: parent.height; radius: 2 * cb.s; color: "#0b0b0a"; border.color: "#3e3b32"; border.width: 1 }
    }
    component CancelKey: Item {
        Glow { target: ck; color: "#ff5040"; spread: 34 * cb.s; radius: 8 * cb.s; intensity: cb.inControl ? 0.8 : 0 }
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
        color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: Math.max(8, 13 * cb.s); font.letterSpacing: 3 * cb.s
    }

    // ---------------------------------------------------- tactical deck
    DeckPlate {
        id: tacDeck
        visible: cb.utilityMode === 0
        x: 0; y: cb.deckY; width: cb.width; height: cb.deckH
        Dymo { x: 26 * cb.s; y: 14 * cb.s; text: "ACTIONS // COMBAT" }
        readonly property real keyW: (width - 26 * cb.s - cancelW - 40 * cb.s - 44 * cb.s - divW * 2 - keyGap * 10) / 8
        Row {
            id: tacRow
            x: 26 * cb.s; y: tacDeck.keyY
            spacing: tacDeck.keyGap
            Repeater {
                model: [
                    ["HIGHEST THREAT", "SELECT TARGET", "combat_threat", "TARGET HIGHEST THREAT", "TARGETS THE MOST DANGEROUS SHIP NEARBY"],
                    ["FIND BEST TARGET", "FAST HULL SWEEP", "combat_best_target", "FIND BEST TARGET", "SWEEPS CONTACTS AND PICKS THE BEST BOUNTY"],
                    ["POWER PLANT", "TARGET SUBSYSTEM", "combat_powerplant", "TARGET POWER PLANT", "LOCKS THE TARGET'S POWER PLANT"],
                    ["FIRE GROUP", "CYCLE NEXT", "combat_firegroup_next", "CYCLE FIRE GROUP", "SWITCHES TO THE NEXT FIRE GROUP"]
                ]
                DeckKey {
                    width: tacDeck.keyW; height: tacDeck.keyH
                    title: modelData[0]
                    readonly property bool run: cb.bstate === modelData[3]
                    legend: run ? bridge.bridgeMessage : modelData[1]
                    keyState: cb.keyState(run); unavailableReason: cb.bindsReason
                    tooltip: modelData[0]; tooltipDetail: modelData[4]
                    onActivated: bridge.requestCommand(modelData[2])
                    onDenied: (r) => cb.denied(modelData[0] + " UNAVAILABLE", r)
                }
            }
            Groove { width: tacDeck.divW; height: tacDeck.keyH }
            Repeater {
                model: [
                    ["FIGHTER 1", "DEPLOY BAY 1", "combat_fighter_1", "DEPLOY FIGHTER 1"],
                    ["FIGHTER 2", "DEPLOY BAY 2", "combat_fighter_2", "DEPLOY FIGHTER 2"],
                    ["RECALL", "FIGHTER TO DOCK", "combat_fighter_recall", "RECALL FIGHTER"]
                ]
                DeckKey {
                    width: tacDeck.keyW; height: tacDeck.keyH
                    title: modelData[0]
                    readonly property bool run: cb.bstate === modelData[3]
                    legend: run ? bridge.bridgeMessage : modelData[1]
                    keyState: cb.keyState(run); unavailableReason: cb.bindsReason
                    tooltip: modelData[3]
                    onActivated: bridge.requestCommand(modelData[2])
                    onDenied: (r) => cb.denied(modelData[0] + " UNAVAILABLE", r)
                }
            }
            Groove { width: tacDeck.divW; height: tacDeck.keyH }
            DeckKey {
                id: escapeKey
                width: tacDeck.keyW; height: tacDeck.keyH
                cap: "mustard"; title: "ESCAPE AREA"
                readonly property bool run: cb.bstate === "EMERGENCY EGRESS"
                legend: run ? bridge.bridgeMessage : "BOOST // SUPERCRUISE"
                keyState: cb.keyState(run); unavailableReason: cb.bindsReason
                tooltip: "ESCAPE AREA"; tooltipDetail: "FULL ENGINES, BOOST, CHAFF, THEN SUPERCRUISE OUT"
                onActivated: bridge.requestCommand("combat_egress")
                onDenied: (r) => cb.denied("ESCAPE AREA UNAVAILABLE", r)
            }
        }
        GroupLabel { x: tacRow.x + tacDeck.keyW * 2 - width / 2; y: tacDeck.keyY - height - 6 * cb.s; text: "TARGETING" }
        GroupLabel { x: tacRow.x + (tacDeck.keyW + tacDeck.keyGap) * 4 + tacDeck.divW + tacDeck.keyGap + (tacDeck.keyW * 3 + tacDeck.keyGap * 2) / 2 - width / 2; y: tacDeck.keyY - height - 6 * cb.s; text: "FIGHTER BAY" }
        GroupLabel { x: tacRow.x + escapeKey.x + escapeKey.width / 2 - width / 2; y: tacDeck.keyY - height - 6 * cb.s; text: "EMERGENCY" }
        CancelKey { x: tacDeck.width - tacDeck.cancelW - 40 * cb.s; y: tacDeck.keyY; width: tacDeck.cancelW; height: tacDeck.keyH }
    }

    // ---------------------------------------------------- bounty hunting deck
    DeckPlate {
        id: bhDeck
        visible: cb.utilityMode === 1
        x: 0; y: cb.deckY; width: cb.width; height: cb.deckH
        Dymo { x: 26 * cb.s; y: 14 * cb.s; text: "ACTIONS // BOUNTY HUNTING" }
        readonly property real keyW: (width - 26 * cb.s - cancelW - 40 * cb.s - 44 * cb.s - divW - keyGap * 6) / 6
        Row {
            id: bhRow
            x: 26 * cb.s; y: bhDeck.keyY
            spacing: bhDeck.keyGap
            Repeater {
                // [title, legend, command, kind]
                model: [
                    ["ALL SITES", "ALL LEVELS", "combat_res_all", "all"],
                    ["LOW", "FEWEST PIRATES", "combat_res_low", "low"],
                    ["STANDARD", "SOME PIRATES", "combat_res_std", "std"],
                    ["HIGH", "BEST FOR MOST", "combat_res_high", "high"],
                    ["HAZARDOUS", "NO POLICE", "combat_res_haz", "haz"]
                ]
                Item {
                    width: bhDeck.keyW; height: bhDeck.keyH
                    readonly property bool showing: hunting.shownKind === modelData[3] && hunting.rows.length > 0
                    readonly property bool run: bridge.combatResBusy && hunting.lastSearch === modelData[3]
                    // SHOWING: faint green outline around the key whose results are on screen
                    Rectangle { anchors.fill: parent; anchors.margins: -6 * cb.s; anchors.bottomMargin: -2 * cb.s; radius: 9 * cb.s
                                color: "transparent"; border.color: Theme.ok; border.width: Math.max(1, 2 * cb.s); opacity: 0.55; visible: parent.showing && !parent.run }
                    DeckKey {
                        anchors.fill: parent
                        title: modelData[0]
                        legend: parent.run ? "SEARCHING..." : (parent.showing ? "SHOWING" : modelData[1])
                        keyState: parent.run ? "running" : (bridge.combatResBusy ? "unavailable" : "ready")
                        unavailableReason: "A SEARCH IS ALREADY RUNNING"
                        tooltip: modelData[3] === "all" ? "SEARCH EVERY DANGER LEVEL" : "SEARCH " + modelData[0] + " SITES"
                        tooltipDetail: "NEAREST FIRST" + (modelData[3] === "all" ? ", EVERY LEVEL MIXED" : "") + " // WITHIN " + hunting.lyValues[hunting.lyIdx] + " LY"
                                       + (hunting.lsIdx === hunting.lsValues.length - 1 ? ", ANY DISTANCE FROM THE STAR" : ", SITE UNDER " + Number(hunting.lsValues[hunting.lsIdx]).toLocaleString(Qt.locale("en_US"), "f", 0) + " LS")
                        onActivated: hunting.search(modelData[3])
                        onDenied: (r) => cb.denied(modelData[0] + " SEARCH UNAVAILABLE", r)
                    }
                }
            }
            Groove { width: bhDeck.divW; height: bhDeck.keyH }
            DeckKey {
                id: plotSiteKey
                width: bhDeck.keyW; height: bhDeck.keyH
                title: "PLOT: SITE"
                legend: hunting.sel ? String(hunting.sel.system) : "NO SITE SELECTED"
                keyState: hunting.sel === null ? "unavailable" : (cb.bindsReady ? "ready" : "unavailable")
                unavailableReason: hunting.sel === null ? "SEARCH FOR SITES FIRST" : cb.bindsReason
                tooltip: hunting.sel ? "PLOT A ROUTE TO " + String(hunting.sel.system).toUpperCase() : "PLOT A ROUTE TO THE SELECTED SITE"
                tooltipDetail: "THE ROUTE SHOWS UP ON NAVIGATION"
                onActivated: bridge.plotResIndex(hunting.selected)
                onDenied: (r) => cb.denied("PLOT: SITE UNAVAILABLE", r)
            }
        }
        GroupLabel { x: bhRow.x + (bhDeck.keyW * 5 + bhDeck.keyGap * 4) / 2 - width / 2; y: bhDeck.keyY - height - 6 * cb.s; text: "SEARCH BY DANGER LEVEL // LOW TO HAZARDOUS" }
        GroupLabel { x: bhRow.x + plotSiteKey.x + plotSiteKey.width / 2 - width / 2; y: bhDeck.keyY - height - 6 * cb.s; text: "GO THERE" }
        CancelKey { x: bhDeck.width - bhDeck.cancelW - 40 * cb.s; y: bhDeck.keyY; width: bhDeck.cancelW; height: bhDeck.keyH }
    }
}
