// NAVIGATION (page 1). Retro redesign, build step 6 (mockup navigation_v1.png, approved).
// Same bridge data and the same commands as v1.0.1; only the presentation changed.
// Route computer (cool factor) + full flight plan, set destination, in-system target,
// route log, and the fixed Action Deck with HOME / BOOKMARK presets (tap = plot, hold = save).
import QtQuick
import "../skin"

Item {
    id: nv
    property var app
    property bool demo: false                 // first orientation tour shows a demo route
    signal denied(string title, string reason)
    signal notice(string title, string detail, string level)

    // tour highlight targets (Main.qml pageHelpTarget)
    readonly property Item routeTarget: routePanel
    readonly property Item destinationTarget: destPanel
    readonly property Item deckTarget: actionPanel

    readonly property real s: Theme.s
    readonly property real g: Math.max(8, 14 * s)

    // ---------- destination editor state (QML owns the typing; backend owns the plotted route)
    property string navDraft: ""
    property string navSelected: ""
    property string lastLive: ""
    Component.onCompleted: { navDraft = bridge.navDestinationInput; lastLive = bridge.navDestinationInput }
    Connections {
        target: bridge
        function onStateChanged() {
            var live = bridge.navDestinationInput
            if (live !== nv.lastLive && !destInput.activeFocus) {
                nv.lastLive = live
                nv.navDraft = live
                nv.navSelected = ""
            }
        }
    }
    Timer { id: suggestTimer; interval: 350; onTriggered: bridge.requestSystemSuggestions(nv.navDraft) }
    // One selected system for the whole page: a match, a flight plan row or a map star.
    // PLOT ROUTE goes there and a preset hold saves it. Clicking it again clears it.
    function pick(name) {
        name = String(name || "").trim()
        if (name === "" || name === "-") return
        if (nv.navSelected.toUpperCase() === name.toUpperCase() && infoName !== "") { clearSelection(); return }
        nv.navSelected = name
        nv.navDraft = name
        bridge.requestSystemSuggestions("")
        showInfo(name)
    }
    function clearSelection() { nv.navSelected = ""; hideInfo() }

    // System info card (replaces ROUTE LOG for a while)
    property string infoName: ""
    readonly property int infoMs: 30000
    function showInfo(name) {
        if (nv.demo) return
        infoName = String(name)
        bridge.requestSystemInfo(infoName)
        infoTimer.restart()
    }
    function hideInfo() { infoName = ""; infoTimer.stop() }
    Timer { id: infoTimer; interval: nv.infoMs; onTriggered: nv.hideInfo() }
    onVisibleChanged: if (!visible) hideInfo()
    // route data for a system (star class, scoop, jump number) when it's on the route
    function routeRow(name) {
        var up = String(name || "").toUpperCase()
        var r = nv.fullRoute || []
        for (var i = 0; i < r.length; i++) if (String(r[i].system).toUpperCase() === up) return { row: r[i], index: i }
        return null
    }
    readonly property string saveTarget: navSelected !== "" ? navSelected : String(bridge.navMemoryCaptureSystem || "")
    readonly property string plotTarget: navSelected !== "" ? navSelected : String(navDraft || "").trim()

    // ---------- demo data for the first orientation tour
    readonly property var demoEntries: [
        { system: "EGA", starClass: "K", kind: "CURRENT", scoopable: true },
        { system: "LTT 15449", starClass: "M", kind: "NEXT", scoopable: true },
        { system: "HR 4979", starClass: "DA", kind: "ROUTE", scoopable: false },
        { system: "SHENVE", starClass: "G", kind: "ROUTE", scoopable: true },
        { system: "WISE 1506+7027", starClass: "-", kind: "ROUTE", scoopable: null },
        { system: "HIP 20277", starClass: "F", kind: "ROUTE", scoopable: true },
        { system: "4 MORE", kind: "ELLIPSIS", hiddenCount: 4 },
        { system: "SHINRARTA DEZHRA", starClass: "K", kind: "DESTINATION", scoopable: true }
    ]
    readonly property var entries: demo ? demoEntries : (bridge.navRouteEntries || [])
    readonly property var fullRoute: demo ? demoEntries.filter(function (e) { return e.kind !== "ELLIPSIS" }) : (bridge.navFullRoute || [])
    readonly property bool hasRoute: demo || (bridge.destination !== "NO ROUTE" && entries.length > 1)
    readonly property bool inSysVisible: !demo && bridge.navInSystemTargetVisible

    // ---------- colour helpers
    function scoopColor(e) {
        if (!e || e.scoopable === null || e.scoopable === undefined) return Theme.dimText
        return e.scoopable ? Theme.ok : Theme.info
    }
    function starText(e) {
        var c = String((e && e.starClass) || "-")
        return c === "-" ? "?" : c.toUpperCase().slice(0, 2)
    }
    function logColor(t) {
        t = String(t || "").toUpperCase()
        if (/FAIL|DENIED|ABORT|ERROR|INTERDICT|DISARM/.test(t)) return Theme.bad
        if (/ROUTE|PLOT|TARGET|NEXT|CLEARED|UPDATED/.test(t)) return Theme.info
        if (/DOCKED|ARRIVED|LAUNCH|UNDOCK|JUMP|TRACKING/.test(t)) return Theme.ok
        return Theme.phosphor
    }
    function fsdColor(t) {
        t = String(t || "").toUpperCase()
        if (t === "" || t === "-" || t === "UNKNOWN") return Theme.dimText
        if (t.indexOf("LOCK") >= 0) return Theme.bad
        if (t.indexOf("READY") >= 0 || t.indexOf("CLEAR") >= 0) return Theme.ok
        return Theme.info
    }

    // ---------- layout rows
    readonly property real topH: height * 0.505
    readonly property real midH: height * 0.27
    readonly property real leftW: width * 0.66
    readonly property real deckY: topH + midH + g * 2

    // ================================================================= ROUTE COMPUTER
    Plate {
        id: routePanel
        x: 0; y: 0; width: nv.leftW; height: nv.topH
        screwSize: 13 * nv.s
        Dymo { x: 26 * nv.s; y: 14 * nv.s; text: "ROUTE COMPUTER" }
        Bezel {
            id: rcBezel
            x: 16 * nv.s; y: 50 * nv.s
            width: parent.width - 32 * nv.s; height: parent.height - 66 * nv.s
            pad: 12 * nv.s
            readonly property real iw: width - pad * 2
            readonly property real ih: height - pad * 2

            // legend
            Row {
                x: 22 * nv.s; y: 14 * nv.s
                spacing: 22 * nv.s
                Repeater {
                    model: [["SCOOPABLE", Theme.ok, true], ["NO SCOOP", Theme.info, true], ["UNKNOWN", Theme.dimText, false]]
                    Row {
                        spacing: 6 * nv.s
                        Rectangle { width: 12 * nv.s; height: width; radius: width / 2; anchors.verticalCenter: parent.verticalCenter
                                    color: modelData[2] ? modelData[1] : "transparent"; border.color: modelData[1]; border.width: 1 }
                        Text { text: modelData[0]; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(10, 18 * nv.s) }
                    }
                }
            }
            // target + source
            Column {
                anchors.right: parent.right; anchors.rightMargin: 26 * nv.s; y: 10 * nv.s
                Text {
                    anchors.right: parent.right
                    text: nv.demo ? "TARGET // SHINRARTA DEZHRA"
                          : (nv.hasRoute ? "TARGET // " + String(bridge.destination).toUpperCase()
                             : (nv.inSysVisible ? "TARGET // " + String(bridge.navInSystemTargetName).toUpperCase() : "NO TARGET"))
                    color: nv.hasRoute || nv.inSysVisible ? Theme.ok : Theme.dimText
                    font.family: Theme.crtFont; font.pixelSize: Math.max(14, 30 * nv.s); font.letterSpacing: 2 * nv.s
                }
                Text {
                    anchors.right: parent.right
                    visible: nv.hasRoute
                    text: "SET BY // " + (nv.demo ? "ORIENTATION DEMO" : String(bridge.navRouteSource || "-").toUpperCase())
                    color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(10, 18 * nv.s); font.letterSpacing: 1 * nv.s
                }
            }

            // ---------- the angled map
            Item {
                id: map
                x: 30 * nv.s; y: 70 * nv.s
                width: rcBezel.iw - 60 * nv.s
                height: rcBezel.ih - y - stats.height - 26 * nv.s
                // nodes: route entries, or CURRENT + in-system target when there is no hyperspace route
                readonly property var nodes: {
                    if (nv.hasRoute) return nv.entries
                    var cur = nv.entries.length > 0 ? [nv.entries[0]] : [{ system: bridge.system, starClass: "-", kind: "CURRENT", scoopable: null }]
                    if (nv.inSysVisible) cur = cur.concat([{ system: bridge.navInSystemTargetName, kind: "INSYS" }])
                    return cur
                }
                readonly property int n: nodes.length
                readonly property real ringD: Math.min(height * 0.2, 66 * nv.s)
                function fx(i) { return n <= 1 ? 0.10 : 0.06 + 0.86 * i / (n - 1) }
                function px(i) { return width * fx(i) }
                function py(i) { return height * (0.74 - 0.48 * (n <= 1 ? 0 : i / (n - 1))) }
                onNodesChanged: links.requestPaint()
                onWidthChanged: links.requestPaint()
                onHeightChanged: links.requestPaint()

                // faint grid
                Canvas {
                    property bool themeAmber: Theme.amber   // LAB themes: repaint when the screen theme changes
                    onThemeAmberChanged: requestPaint()
                    id: grid
                    anchors.fill: parent; opacity: 0.5
                    onPaint: {
                        var c = getContext("2d"); c.reset()
                        c.strokeStyle = "rgba(" + Theme.rgb("125,255,156") + ",0.07)"; c.lineWidth = 1
                        var st = Math.max(30, width / 16)
                        for (var x = 0; x < width; x += st) { c.beginPath(); c.moveTo(x, 0); c.lineTo(x, height); c.stroke() }
                        for (var y = 0; y < height; y += st) { c.beginPath(); c.moveTo(0, y); c.lineTo(width, y); c.stroke() }
                    }
                    onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
                }
                // dashed links between node rims
                Canvas {
                    property bool themeAmber: Theme.amber   // LAB themes: repaint when the screen theme changes
                    onThemeAmberChanged: requestPaint()
                    id: links
                    anchors.fill: parent
                    onPaint: {
                        var c = getContext("2d"); c.reset()
                        var r = map.ringD / 2 + 8 * nv.s
                        for (var i = 0; i < map.n - 1; i++) {
                            var x0 = map.px(i), y0 = map.py(i), x1 = map.px(i + 1), y1 = map.py(i + 1)
                            var dx = x1 - x0, dy = y1 - y0, L = Math.sqrt(dx * dx + dy * dy)
                            if (L < 2 * r) continue
                            var ux = dx / L, uy = dy / L
                            var nextEll = String(map.nodes[i + 1].kind) === "ELLIPSIS" || String(map.nodes[i].kind) === "ELLIPSIS"
                            c.strokeStyle = String(map.nodes[i + 1].kind) === "INSYS" ? "rgba(" + Theme.rgb("255,184,77") + ",0.55)" : (nextEll ? "rgba(" + Theme.rgb("125,255,156") + ",0.28)" : "rgba(" + Theme.rgb("125,255,156") + ",0.5)")
                            c.lineWidth = Math.max(1.5, 2.5 * nv.s)
                            var dash = 10 * nv.s, gap = 8 * nv.s
                            for (var d = r; d < L - r; d += dash + gap) {
                                var e = Math.min(d + dash, L - r)
                                c.beginPath(); c.moveTo(x0 + ux * d, y0 + uy * d); c.lineTo(x0 + ux * e, y0 + uy * e); c.stroke()
                            }
                        }
                    }
                }
                // pulse dot on the current leg (fades in and out at both ends: no seam)
                Rectangle {
                    visible: map.n > 1
                    width: 12 * nv.s; height: width; radius: width / 2; color: Theme.ok
                    property real f: 0
                    readonly property real r: map.ringD / 2 + 8 * nv.s
                    readonly property real len: map.n > 1 ? Math.sqrt(Math.pow(map.px(1) - map.px(0), 2) + Math.pow(map.py(1) - map.py(0), 2)) : 1
                    readonly property real t: (r + f * Math.max(0, len - 2 * r)) / Math.max(1, len)
                    x: map.px(0) + (map.n > 1 ? (map.px(1) - map.px(0)) * t : 0) - width / 2
                    y: map.py(0) + (map.n > 1 ? (map.py(1) - map.py(0)) * t : 0) - height / 2
                    opacity: Math.sin(f * Math.PI)
                    NumberAnimation on f { from: 0; to: 1; duration: 2600; loops: Animation.Infinite; running: nv.visible }
                }
                // nodes + labels
                Repeater {
                    model: map.nodes
                    Item {
                        id: node
                        readonly property string kind: String(modelData.kind || "")
                        readonly property bool isCur: kind === "CURRENT"
                        readonly property bool isDest: kind === "DESTINATION" || (index === map.n - 1 && index > 0 && kind !== "INSYS" && kind !== "ELLIPSIS")
                        readonly property bool isEll: kind === "ELLIPSIS"
                        readonly property bool isIns: kind === "INSYS"
                        readonly property color c: isIns ? Theme.info : nv.scoopColor(modelData)
                        readonly property bool labelAbove: isDest ? false : (index % 2 === 0)
                        readonly property real d: isCur ? map.ringD * 1.12 : (isDest ? map.ringD * 1.05 : map.ringD * 0.86)
                        // jump number counts real systems, skipping the ellipsis
                        readonly property int jump: {
                            var k = 0
                            for (var i = 1; i <= index && i < map.n; i++) if (String(map.nodes[i].kind) !== "ELLIPSIS") k++
                            return k
                        }
                        x: map.px(index) - d / 2; y: map.py(index) - d / 2
                        width: d; height: d
                        readonly property bool chosen: !isEll && nv.navSelected !== "" && String(modelData.system).toUpperCase() === nv.navSelected.toUpperCase()
                        // selection frame
                        Rectangle {
                            visible: node.chosen
                            anchors.fill: parent; anchors.margins: -8 * nv.s
                            color: "transparent"; border.color: Theme.ok; border.width: Math.max(2, 2 * nv.s); radius: 3 * nv.s
                            opacity: 0.9
                        }
                        PressArea {
                            enabled: !node.isEll && !nv.demo
                            anchors.fill: parent; anchors.margins: -12 * nv.s
                            onActivated: { Theme.cue("tick"); nv.pick(node.isIns ? bridge.system : modelData.system) }
                        }

                        // ring (current, route) / square (destination) / diamond (in-system target)
                        Rectangle {
                            visible: !node.isEll && !node.isIns
                            anchors.fill: parent
                            radius: node.isDest ? 4 * nv.s : width / 2
                            color: Theme.t("#5006140b")
                            border.color: node.c; border.width: Math.max(2, 3 * nv.s)
                            opacity: modelData.scoopable === null || modelData.scoopable === undefined ? 0.6 : 1
                            Rectangle {
                                anchors.fill: parent; anchors.margins: -7 * nv.s
                                radius: node.isDest ? 6 * nv.s : width / 2
                                color: "transparent"; border.color: node.c; border.width: 1
                                opacity: node.isCur ? 0.5 + 0.2 * Math.sin(bridge.pulse * 6.28318) : (node.isDest ? 0.45 : 0.18)
                            }
                            Text {
                                anchors.centerIn: parent
                                text: nv.starText(modelData)
                                color: node.c
                                font.family: Theme.crtFont; font.pixelSize: Math.max(14, node.d * 0.5)
                            }
                        }
                        Rectangle {
                            visible: node.isIns
                            anchors.centerIn: parent
                            width: node.d * 0.62; height: width; rotation: 45
                            color: Theme.t("#5006140b"); border.color: Theme.info; border.width: Math.max(2, 3 * nv.s)
                            Rectangle { anchors.centerIn: parent; width: parent.width * 0.28; height: width; color: Theme.info }
                        }
                        // ellipsis: "+N" with "MORE JUMPS" under it
                        Column {
                            visible: node.isEll
                            anchors.centerIn: parent
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "+" + Number(modelData.hiddenCount || 0)
                                   color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: Math.max(14, 30 * nv.s) }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "MORE JUMPS"
                                   color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(10, 17 * nv.s) }
                        }
                        // label
                        Column {
                            visible: !node.isEll
                            width: Math.min(260 * nv.s, map.width / Math.max(3, map.n) * 1.9)
                            x: node.width / 2 - width / 2
                            y: node.labelAbove ? -height - (node.chosen ? 16 : 12) * nv.s : node.height + (node.chosen ? 14 : 10) * nv.s
                            Text {
                                width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                                text: String(modelData.system || "-").toUpperCase()
                                color: node.isCur ? Theme.ok : (node.c === Theme.info ? Theme.info : Theme.phosphor)
                                font.family: Theme.crtFont; font.pixelSize: Math.max(13, 27 * nv.s); font.letterSpacing: 1 * nv.s
                            }
                            Text {
                                width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                                text: node.isCur ? "YOU ARE HERE"
                                      : node.isIns ? String(bridge.navInSystemTargetKind || "IN-SYSTEM TARGET").toUpperCase()
                                      : node.isDest ? "DESTINATION"
                                      : "JUMP " + node.jump + (modelData.scoopable === false ? " // NO SCOOP" : "")
                                color: modelData.scoopable === false && !node.isCur && !node.isDest ? Theme.info : Theme.dimText
                                font.family: Theme.crtFont; font.pixelSize: Math.max(10, 18 * nv.s)
                            }
                        }
                    }
                }
                // nothing plotted
                Column {
                    visible: !nv.hasRoute && !nv.inSysVisible
                    anchors.centerIn: parent
                    spacing: 6 * nv.s
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "NO ROUTE PLOTTED"
                           color: Theme.info; font.family: Theme.crtFont; font.pixelSize: Math.max(16, 36 * nv.s); font.letterSpacing: 3 * nv.s }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "PLOT ONE IN ELITE, OR TYPE A SYSTEM BELOW"
                           color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(11, 20 * nv.s) }
                }
            }

            // ---------- stats row
            Row {
                id: stats
                x: 14 * nv.s; y: rcBezel.ih - height - 12 * nv.s
                width: rcBezel.iw - 28 * nv.s; height: 70 * nv.s
                spacing: 10 * nv.s
                readonly property string nextStar: {
                    if (nv.demo) return "M // SCOOP"
                    var c = String(bridge.nextStarClass || "-")
                    if (c === "-") return "UNKNOWN"
                    return c.toUpperCase() + (bridge.nextStarScoopableKnown ? (bridge.nextStarScoopable ? " // SCOOP" : " // NO SCOOP") : "")
                }
                Repeater {
                    model: [
                        ["ROUTE", nv.demo ? "LIVE" : (!bridge.navArmed ? "NAV DISARMED" : (nv.hasRoute ? "LIVE" : "NONE")),
                         nv.demo ? Theme.ok : (!bridge.navArmed ? Theme.bad : (nv.hasRoute ? Theme.ok : Theme.dimText))],
                        ["JUMPS LEFT", nv.demo ? "12" : bridge.navJumpsText, nv.demo || bridge.routeJumps >= 0 ? Theme.phosphor : Theme.dimText],
                        ["FSD", nv.demo ? "READY" : bridge.fsdState, nv.demo ? Theme.ok : nv.fsdColor(bridge.fsdState)],
                        ["MASS LOCK", nv.demo ? "CLEAR" : bridge.navMassLock, nv.demo ? Theme.ok : (String(bridge.navMassLock).toUpperCase() === "LOCKED" ? Theme.bad : Theme.ok)],
                        ["NEXT STAR", stats.nextStar,
                         nv.demo ? Theme.ok : (stats.nextStar === "UNKNOWN" ? Theme.dimText : (bridge.nextStarScoopableKnown && !bridge.nextStarScoopable ? Theme.info : Theme.ok))]
                    ]
                    Rectangle {
                        width: (stats.width - stats.spacing * 4) / 5; height: stats.height
                        color: Theme.t("#0a9dffb6"); border.color: Theme.t("#2a9dffb6"); border.width: 1
                        Text { x: 12 * nv.s; y: 4 * nv.s; text: modelData[0]; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(10, 18 * nv.s); font.letterSpacing: 1.5 * nv.s }
                        Text {
                            x: 12 * nv.s; anchors.bottom: parent.bottom; anchors.bottomMargin: 4 * nv.s
                            width: parent.width - 20 * nv.s; elide: Text.ElideRight
                            text: String(modelData[1] || "-").toUpperCase(); color: modelData[2]
                            font.family: Theme.crtFont; font.pixelSize: Math.max(13, 30 * nv.s); font.letterSpacing: 1.5 * nv.s
                        }
                    }
                }
            }
        }
    }

    // ================================================================= FLIGHT PLAN
    Plate {
        id: planPanel
        x: routePanel.width + nv.g; y: 0
        width: nv.width - x; height: nv.topH
        screwSize: 13 * nv.s
        Dymo { x: 26 * nv.s; y: 14 * nv.s; text: "FLIGHT PLAN" }
        Bezel {
            x: 16 * nv.s; y: 50 * nv.s
            width: parent.width - 32 * nv.s; height: parent.height - 66 * nv.s
            pad: 12 * nv.s
            Item {
                id: planHead
                x: 18 * nv.s; y: 14 * nv.s; width: parent.width - 36 * nv.s - 26 * nv.s; height: 26 * nv.s
                readonly property real fs: Math.max(10, 18 * nv.s)
                Text { x: 0; text: "#"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: planHead.fs }
                Text { x: parent.width * 0.12; text: "SYSTEM"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: planHead.fs }
                Text { x: parent.width * 0.66; width: parent.width * 0.1; horizontalAlignment: Text.AlignHCenter; text: "STAR"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: planHead.fs }
                Text { anchors.right: parent.right; text: "SCOOP"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: planHead.fs }
            }
            PhosphorList {
                id: plan
                x: 18 * nv.s; y: planHead.y + planHead.height + 6 * nv.s
                width: parent.width - 36 * nv.s; height: parent.height - y - 14 * nv.s
                fontSize: Math.max(13, 25 * nv.s)
                model: nv.fullRoute
                delegate: Item {
                    required property var modelData
                    required property int index
                    width: plan.list.width - (plan.overflow ? 0 : 26 * nv.s)
                    height: plan.fontSize * 1.3
                    readonly property bool cur: String(modelData.kind) === "CURRENT"
                    readonly property bool dest: String(modelData.kind) === "DESTINATION"
                    readonly property bool chosen: nv.navSelected !== "" && String(modelData.system).toUpperCase() === nv.navSelected.toUpperCase()
                    Rectangle { anchors.fill: parent; visible: parent.cur || parent.chosen || rowArea.containsMouse
                                color: parent.chosen ? Theme.t("#2a7dff9c") : (parent.cur ? Theme.t("#1a7dff9c") : Theme.t("#107dff9c"))
                                border.color: parent.chosen ? Theme.t("#807dff9c") : Theme.t("#337dff9c"); border.width: 1 }
                    PressArea { id: rowArea; anchors.fill: parent; enabled: !nv.demo; onActivated: { Theme.cue("tick"); nv.pick(modelData.system) } }
                    Text { x: 6 * nv.s; anchors.verticalCenter: parent.verticalCenter; text: ("0" + (index + 1)).slice(-Math.max(2, String(index + 1).length))
                           color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: plan.fontSize }
                    Text {
                        x: parent.width * 0.12; width: parent.width * 0.52; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                        text: (parent.chosen ? "> " : "") + String(modelData.system || "-").toUpperCase() + (parent.dest ? "  // DEST" : (parent.cur ? "  // HERE" : ""))
                        color: parent.cur ? Theme.ok : Theme.phosphor
                        font.family: Theme.crtFont; font.pixelSize: plan.fontSize; font.letterSpacing: 1 * nv.s
                    }
                    Text { x: parent.width * 0.66; width: parent.width * 0.1; horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter
                           text: nv.starText(modelData); color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: plan.fontSize }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: 6 * nv.s; anchors.verticalCenter: parent.verticalCenter
                        text: modelData.scoopable === null || modelData.scoopable === undefined ? "UNKNOWN" : (modelData.scoopable ? "SCOOP" : "NO SCOOP")
                        color: nv.scoopColor(modelData); font.family: Theme.crtFont; font.pixelSize: plan.fontSize * 0.86
                    }
                }
            }
            Text {
                visible: plan.list.count <= 1 && !nv.demo
                anchors.horizontalCenter: parent.horizontalCenter; y: parent.height * 0.45
                text: "NO ROUTE // NOTHING TO LIST"
                color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(13, 24 * nv.s)
            }
        }
    }

    // ================================================================= SET DESTINATION
    Plate {
        id: destPanel
        x: 0; y: nv.topH + nv.g
        width: nv.width * 0.405; height: nv.midH
        screwSize: 13 * nv.s
        Dymo { x: 26 * nv.s; y: 14 * nv.s; text: "SET DESTINATION" }
        Bezel {
            id: destBezel
            x: 16 * nv.s; y: 50 * nv.s
            width: parent.width - 32 * nv.s; height: parent.height - 66 * nv.s
            pad: 12 * nv.s
            readonly property real iw: width - pad * 2
            readonly property real fs: Math.max(12, 22 * nv.s)
            Text {
                x: 20 * nv.s; y: 10 * nv.s
                text: "TYPE A SYSTEM NAME // 3+ CHARACTERS"
                color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(10, 18 * nv.s); font.letterSpacing: 1 * nv.s
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 20 * nv.s; y: 10 * nv.s
                width: destBezel.iw * 0.4; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight
                visible: destInput.activeFocus || (bridge.navSystemSuggestions || []).length > 0
                text: String(bridge.navSuggestionStatus || "").toUpperCase()
                color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(10, 18 * nv.s)
            }
            // entry field: the one kind of CRT item you type into (blinking cursor)
            Rectangle {
                id: field
                x: 18 * nv.s; y: 38 * nv.s
                width: destBezel.iw - 36 * nv.s; height: Math.max(30, 56 * nv.s)
                color: Theme.t("#0a7dff9c"); border.color: destInput.activeFocus ? Theme.t("#807dff9c") : Theme.t("#337dff9c"); border.width: 1
                TextInput {
                    id: destInput
                    x: 12 * nv.s; width: parent.width - 24 * nv.s; height: parent.height
                    verticalAlignment: TextInput.AlignVCenter
                    text: nv.navDraft
                    color: Theme.ok; selectionColor: Theme.t("#2f7a45"); selectedTextColor: Theme.control
                    font.family: Theme.crtFont; font.pixelSize: Math.max(16, 38 * nv.s); font.letterSpacing: 2 * nv.s; font.capitalization: Font.AllUppercase
                    clip: true; selectByMouse: true
                    cursorDelegate: Rectangle {
                        width: Math.max(6, 14 * nv.s); color: Theme.ok
                        visible: destInput.activeFocus
                        SequentialAnimation on opacity { loops: Animation.Infinite; running: destInput.activeFocus
                            NumberAnimation { to: 0; duration: 0 } PauseAnimation { duration: 530 } NumberAnimation { to: 0.9; duration: 0 } PauseAnimation { duration: 530 } }
                    }
                    onTextEdited: { nv.navDraft = text; nv.clearSelection(); suggestTimer.restart() }
                    function takeFirst() {
                        var list = bridge.navSystemSuggestions || []
                        nv.pick(list.length > 0 ? String(list[0]) : String(nv.navDraft).trim())
                    }
                    Keys.onReturnPressed: takeFirst()
                    Keys.onEnterPressed: takeFirst()
                }
                Text {
                    visible: !destInput.activeFocus && destInput.text === ""
                    x: 14 * nv.s; anchors.verticalCenter: parent.verticalCenter
                    text: "CLICK TO TYPE_"
                    color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(14, 30 * nv.s)
                }
            }
            // matches: pick-list (hover bar, ">" on the chosen row). Selecting only picks; PLOT ROUTE acts.
            Grid {
                id: picks
                x: 18 * nv.s; y: field.y + field.height + 10 * nv.s
                width: field.width
                columns: 2; columnSpacing: 16 * nv.s; rowSpacing: 2 * nv.s
                readonly property var all: bridge.navSystemSuggestions || []
                readonly property real rowH: destBezel.fs * 1.35
                readonly property int fitRows: Math.max(1, Math.floor((hint.y - 4 * nv.s - y) / (rowH + rowSpacing)))
                readonly property var items: all.slice(0, fitRows * 2)
                readonly property int hidden: Math.max(0, all.length - items.length)
                Repeater {
                    model: picks.items
                    Rectangle {
                        width: (picks.width - picks.columnSpacing) / 2; height: picks.rowH
                        readonly property bool chosen: nv.navSelected !== "" && String(modelData).toUpperCase() === nv.navSelected.toUpperCase()
                        color: chosen ? Theme.t("#2a7dff9c") : (pickArea.containsMouse ? Theme.t("#167dff9c") : "transparent")
                        border.color: chosen ? Theme.t("#667dff9c") : "transparent"; border.width: 1
                        Text {
                            x: 8 * nv.s; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 16 * nv.s; elide: Text.ElideRight
                            text: (parent.chosen ? "> " : "  ") + String(modelData).toUpperCase()
                            color: parent.chosen ? Theme.ok : Theme.phosphor
                            font.family: Theme.crtFont; font.pixelSize: destBezel.fs
                        }
                        PressArea { id: pickArea; anchors.fill: parent; onActivated: { Theme.cue("tick"); nv.pick(modelData) } }
                    }
                }
            }
            // hint line
            Text {
                id: hint
                x: 20 * nv.s; y: destBezel.height - destBezel.pad * 2 - height - 8 * nv.s
                width: destBezel.iw - 40 * nv.s; elide: Text.ElideRight
                textFormat: Text.StyledText
                readonly property bool typing: destInput.activeFocus || picks.all.length > 0 || (String(nv.navDraft).trim() !== "" && String(nv.navDraft).trim().toUpperCase() !== String(bridge.destination).toUpperCase())
                readonly property string status: nv.demo ? "ROUTE LIVE // ORIENTATION DEMO ROUTE" : String(bridge.navStatus || "").toUpperCase()
                text: nv.navSelected !== ""
                      ? "SELECTED // " + nv.navSelected.toUpperCase() + " // <font color='" + Theme.info + "'>PLOT ROUTE</font> OR HOLD A SAVED LOCATION"
                      : (typing ? (picks.hidden > 0 ? "+" + picks.hidden + " MORE // KEEP TYPING TO NARROW, OR " : "") + "PICK A MATCH, THEN <font color='" + Theme.info + "'>PLOT ROUTE</font>" : status)
                color: nv.navSelected !== "" || typing ? Theme.dimText : (/FAIL|ERROR|REQUIRED|DISARM|OFF/.test(status) ? Theme.bad : (/ROUTE LIVE/.test(status) ? Theme.ok : Theme.phosphor))
                font.family: Theme.crtFont; font.pixelSize: Math.max(10, 18 * nv.s)
            }
        }
    }

    // ================================================================= IN-SYSTEM TARGET
    Plate {
        id: insysPanel
        x: destPanel.width + nv.g; y: destPanel.y
        width: nv.leftW - x; height: nv.midH
        screwSize: 13 * nv.s
        Dymo { x: 26 * nv.s; y: 14 * nv.s; text: "IN-SYSTEM TARGET" }
        Bezel {
            id: insBezel
            x: 16 * nv.s; y: 50 * nv.s
            width: parent.width - 32 * nv.s; height: parent.height - 66 * nv.s
            pad: 12 * nv.s
            readonly property real iw: width - pad * 2
            Column {
                x: 20 * nv.s; y: 10 * nv.s; width: insBezel.iw - 40 * nv.s
                spacing: 2 * nv.s
                Text { text: nv.inSysVisible ? "LOCKED TARGET" : "NO TARGET LOCKED"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(10, 18 * nv.s); font.letterSpacing: 1 * nv.s }
                Text {
                    width: parent.width; height: Math.max(30, 36 * nv.s) * 2.05
                    verticalAlignment: Text.AlignTop
                    wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                    fontSizeMode: Text.Fit; minimumPixelSize: Math.max(12, 24 * nv.s)
                    lineHeight: 0.92
                    text: nv.inSysVisible ? String(bridge.navInSystemTargetName).toUpperCase() : "-"
                    color: nv.inSysVisible ? Theme.ok : Theme.dimText
                    font.family: Theme.crtFont; font.pixelSize: Math.max(15, 36 * nv.s); font.letterSpacing: 2 * nv.s
                }
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: nv.inSysVisible
                          ? (String(bridge.navInSystemTargetStationType || "") !== "" ? String(bridge.navInSystemTargetStationType).toUpperCase() : String(bridge.navInSystemTargetKind).toUpperCase())
                            + (bridge.navInSystemTargetConfirmedStation ? " // CONFIRMED" : " // UNCONFIRMED")
                          : "TARGET A STATION IN ELITE'S NAV PANEL"
                    color: nv.inSysVisible ? (bridge.navInSystemTargetConfirmedStation ? Theme.ok : Theme.info) : Theme.dimText
                    font.family: Theme.crtFont; font.pixelSize: Math.max(11, 22 * nv.s)
                }
            }
            Item {
                x: 20 * nv.s; width: insBezel.iw - 40 * nv.s; height: 30 * nv.s
                y: insBezel.height - insBezel.pad * 2 - height - 10 * nv.s
                Rectangle { width: parent.width; height: 1; color: Theme.t("#337dff9c") }
                Text { y: 6 * nv.s; text: "MASS LOCK"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(11, 22 * nv.s) }
                Text {
                    anchors.right: parent.right; y: 6 * nv.s
                    text: String(bridge.navMassLock || "-").toUpperCase()
                    color: String(bridge.navMassLock).toUpperCase() === "LOCKED" ? Theme.bad : Theme.ok
                    font.family: Theme.crtFont; font.pixelSize: Math.max(11, 22 * nv.s)
                }
            }
        }
    }

    // ================================================================= ROUTE LOG / SYSTEM INFO
    // Selecting a system swaps the route log for a card about it. The card goes back to
    // the log after 30 s, when the selection is cleared, a route is plotted, or the page changes.
    Plate {
        id: logPanel
        x: planPanel.x; y: destPanel.y
        width: nv.width - x; height: nv.midH
        screwSize: 13 * nv.s
        readonly property bool card: nv.infoName !== ""
        Dymo { x: 26 * nv.s; y: 14 * nv.s; text: logPanel.card ? "SYSTEM INFO" : "ROUTE LOG" }
        Bezel {
            id: logBezel
            x: 16 * nv.s; y: 50 * nv.s
            width: parent.width - 32 * nv.s; height: parent.height - 66 * nv.s
            pad: 12 * nv.s
            readonly property real iw: width - pad * 2
            readonly property real ih: height - pad * 2
            PhosphorList {
                id: rlog
                visible: !logPanel.card
                anchors.fill: parent; anchors.margins: 16 * nv.s
                newestFirst: true
                fontSize: Math.max(12, 22 * nv.s)
                model: bridge.navHistory
                delegate: LogRow {
                    required property var modelData
                    required property int index
                    width: rlog.list.width
                    opacity: Math.max(0.5, 1.0 - index * 0.06)
                    readonly property string body: String(modelData.text || "")
                    readonly property int cut: body.indexOf(" // ")
                    fontSize: rlog.fontSize
                    emphasize: index === 0
                    timeW: 0.21; eventW: 0.30
                    time: modelData.time
                    event: cut >= 0 ? body.slice(0, cut) : body
                    detail: cut >= 0 ? body.slice(cut + 4) : ""
                    eventColor: nv.logColor(event)
                }
            }
            Text {
                visible: !logPanel.card && rlog.list.count === 0
                anchors.centerIn: parent
                text: "WAITING FOR TRAVEL EVENTS"
                color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(12, 24 * nv.s)
            }

            // ---------- system info card
            Item {
                id: card
                visible: logPanel.card
                anchors.fill: parent; anchors.margins: 16 * nv.s
                readonly property var info: bridge.navSystemInfo || ({})
                readonly property bool mine: String(info.name || "").toUpperCase() === nv.infoName.toUpperCase()
                readonly property var i: mine ? info : ({})
                readonly property var rr: nv.routeRow(nv.infoName)
                readonly property real fs: Math.max(11, 21 * nv.s)
                readonly property string status: mine ? String(info.status || "") : "LOOKING UP"
                function v(x) { return (x === undefined || x === null || String(x) === "") ? "-" : String(x).toUpperCase() }
                function pop(n) {
                    if (n === undefined || n === null) return "-"
                    n = Number(n)
                    if (n <= 0) return "NONE"
                    if (n >= 1e9) return (n / 1e9).toFixed(1) + " BILLION"
                    if (n >= 1e6) return (n / 1e6).toFixed(1) + " MILLION"
                    if (n >= 1e3) return Math.round(n / 1e3) + " THOUSAND"
                    return String(n)
                }
                readonly property string star: {
                    var t = i.starType ? String(i.starType).toUpperCase().replace(" STAR", "") : ""
                    if (t !== "") return t
                    return rr ? (String(rr.row.starClass || "-") === "-" ? "UNKNOWN" : String(rr.row.starClass).toUpperCase() + " CLASS") : "-"
                }
                readonly property var scoop: i.scoopable !== undefined ? i.scoopable : (rr ? rr.row.scoopable : null)
                readonly property string dist: {
                    if (rr && rr.index === 0) return "YOU ARE HERE"
                    var d = i.distanceLy !== undefined ? Number(i.distanceLy).toFixed(2) + " LY" : ""
                    var j = rr && rr.index > 0 ? "JUMP " + rr.index : ""
                    return d !== "" && j !== "" ? d + " // " + j : (d !== "" ? d : (j !== "" ? j : "-"))
                }
                readonly property string stations: {
                    if (i.stationCount === undefined) return "-"
                    var n = Number(i.stationCount)
                    if (n === 0 || !i.stations || i.stations.length === 0) return n === 0 ? "NONE" : String(n)
                    var f = i.stations[0]
                    return n + " // NEAREST " + String(f.name).toUpperCase() + " (" + String(f.type).toUpperCase() + ") " + f.ls + " LS"
                }

                // header
                Text {
                    width: parent.width * 0.68; elide: Text.ElideRight
                    text: nv.infoName.toUpperCase()
                    color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: card.fs * 1.45; font.letterSpacing: 2 * nv.s
                }
                Text {
                    anchors.right: parent.right; y: card.fs * 0.3
                    text: card.status === "EDSM" ? "EDSM" : (card.status === "" ? "" : card.status + (card.rr ? " // ROUTE DATA" : ""))
                    color: card.status === "EDSM" ? Theme.dimText : (card.status === "LOOKING UP" ? Theme.info : Theme.dimText)
                    font.family: Theme.crtFont; font.pixelSize: card.fs * 0.85
                }
                Grid {
                    y: card.fs * 1.9
                    width: parent.width; columns: 2; columnSpacing: 20 * nv.s; rowSpacing: 1 * nv.s
                    Repeater {
                        model: [
                            ["STAR", card.star, Theme.phosphor],
                            ["SCOOP", card.scoop === null || card.scoop === undefined ? "UNKNOWN" : (card.scoop ? "YES" : "NO"),
                             card.scoop === null || card.scoop === undefined ? Theme.dimText : (card.scoop ? Theme.ok : Theme.info)],
                            ["DISTANCE", card.dist, Theme.phosphor],
                            ["SECURITY", card.v(card.i.security), /ANARCHY|LOW/.test(card.v(card.i.security)) ? Theme.info : Theme.phosphor],
                            ["ALLEGIANCE", card.v(card.i.allegiance), Theme.phosphor],
                            ["GOVERNMENT", card.v(card.i.government), /ANARCHY/.test(card.v(card.i.government)) ? Theme.info : Theme.phosphor],
                            ["ECONOMY", card.v(card.i.economy) + (card.i.secondEconomy ? " / " + card.v(card.i.secondEconomy) : ""), Theme.phosphor],
                            ["POPULATION", card.pop(card.i.population), Theme.phosphor]
                        ]
                        Item {
                            width: (card.width - 20 * nv.s) / 2; height: card.fs * 1.18
                            Text { text: modelData[0]; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: card.fs * 0.85; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                x: parent.width * 0.38; width: parent.width * 0.62; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter
                                text: modelData[1]; color: modelData[1] === "-" ? Theme.dimText : modelData[2]
                                font.family: Theme.crtFont; font.pixelSize: card.fs
                            }
                        }
                    }
                }
                Item {
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 6 * nv.s
                    width: parent.width; height: card.fs * 1.2
                    Text { text: "STATIONS"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: card.fs * 0.85; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        x: (card.width - 20 * nv.s) / 2 * 0.38; width: parent.width - x; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter
                        text: card.stations; color: card.stations === "-" ? Theme.dimText : Theme.phosphor
                        font.family: Theme.crtFont; font.pixelSize: card.fs
                    }
                }
                // time left before the card goes back to the log
                Rectangle {
                    id: cardBar
                    anchors.bottom: parent.bottom; height: Math.max(1, 2 * nv.s); color: Theme.ok; opacity: 0.35
                    width: parent.width * frac
                    property real frac: 1
                    NumberAnimation on frac { id: cardAnim; from: 1; to: 0; duration: nv.infoMs; running: false }
                    Connections { target: nv; function onInfoNameChanged() { if (nv.infoName !== "") { cardAnim.restart() } else cardAnim.stop() } }
                }
            }
        }
    }

    // ================================================================= ACTION DECK
    Plate {
        id: actionPanel
        x: 0; y: nv.deckY
        width: nv.width; height: nv.height - y
        dark: true
        screwSize: 13 * nv.s
        Dymo { x: 26 * nv.s; y: 14 * nv.s; text: "ACTIONS // NAVIGATION" }

        readonly property string bstate: String(bridge.bridgeState || "").toUpperCase()
        readonly property bool inControl: bridge.controlOwner !== "NONE" && bridge.controlOwner !== ""
        readonly property bool bindsReady: bridge.eliteControlsReady
        readonly property string bindsReason: String(bridge.eliteControlReason || "") !== "" ? String(bridge.eliteControlReason).toUpperCase() : "ELITE KEY BINDS NOT FOUND // SEE SETUP > CONTROLS"
        property string lastPreset: ""
        // The route engine doesn't expose a busy state, so plot keys don't show RUNNING;
        // the result shows on the destination status line and in ROUTE LOG.
        readonly property bool plotting: false

        function keyState(running) { return running ? "running" : (bindsReady ? "ready" : "unavailable") }

        readonly property real keyH: Math.min(height - 66 * nv.s, 150 * nv.s)
        readonly property real keyY: 52 * nv.s + (height - 66 * nv.s - keyH) / 2
        readonly property real cancelW: 270 * nv.s
        readonly property real divW: 44 * nv.s
        readonly property real keyGap: 16 * nv.s
        readonly property real keyW: (width - 26 * nv.s - cancelW - 40 * nv.s - 44 * nv.s - divW - keyGap * 7) / 7

        Row {
            x: 26 * nv.s; y: actionPanel.keyY
            spacing: actionPanel.keyGap
            DeckKey {
                id: plotKey
                width: actionPanel.keyW; height: actionPanel.keyH
                title: "PLOT ROUTE"
                readonly property bool run: actionPanel.plotting && actionPanel.lastPreset === "plot"
                legend: run ? bridge.bridgeMessage : (nv.plotTarget !== "" ? "TO " + nv.plotTarget : "TO TYPED SYSTEM")
                keyState: run ? "running" : (!actionPanel.bindsReady || nv.plotTarget === "" ? "unavailable" : "ready")
                unavailableReason: !actionPanel.bindsReady ? actionPanel.bindsReason : "TYPE A SYSTEM NAME IN SET DESTINATION FIRST"
                tooltip: "PLOT A ROUTE IN ELITE'S GALAXY MAP"; tooltipDetail: nv.plotTarget !== "" ? "TO " + nv.plotTarget.toUpperCase() : "TYPE OR PICK A SYSTEM ABOVE"
                onActivated: { actionPanel.lastPreset = "plot"; bridge.plotRoute(nv.plotTarget); nv.clearSelection() }
                onDenied: (r) => nv.denied("PLOT ROUTE UNAVAILABLE", r)
            }
            DeckKey {
                width: actionPanel.keyW; height: actionPanel.keyH
                title: "CLEAR + JUMP"
                readonly property bool run: actionPanel.bstate.indexOf("CLEAR STATION") === 0
                legend: run ? bridge.bridgeMessage : "EXIT & ENGAGE FSD"
                keyState: actionPanel.keyState(run); unavailableReason: actionPanel.bindsReason
                tooltip: "CLEAR THE STATION AND JUMP"; tooltipDetail: "LEAVES MASS LOCK, THEN ENGAGES THE FSD"
                onActivated: bridge.requestCommand("clear")
                onDenied: (r) => nv.denied("CLEAR + JUMP UNAVAILABLE", r)
            }
            DeckKey {
                width: actionPanel.keyW; height: actionPanel.keyH
                title: "DOCK"
                readonly property bool run: actionPanel.bstate === "DOCKING PROTOCOL" || actionPanel.bstate === "REQUEST DOCKING"
                legend: run ? bridge.bridgeMessage : "REQUEST DOCKING"
                keyState: actionPanel.keyState(run); unavailableReason: actionPanel.bindsReason
                tooltip: "REQUEST DOCKING"; tooltipDetail: "BRIDGE ASKS THE STATION AND CUTS THROTTLE"
                onActivated: bridge.requestCommand("dock")
                onDenied: (r) => nv.denied("DOCK UNAVAILABLE", r)
            }
            DeckKey {
                width: actionPanel.keyW; height: actionPanel.keyH
                title: "LAUNCH"
                readonly property bool run: actionPanel.bstate === "AUTO LAUNCH"
                legend: run ? bridge.bridgeMessage : "TAKE OFF"
                keyState: actionPanel.keyState(run); unavailableReason: actionPanel.bindsReason
                tooltip: "LAUNCH FROM THE PAD"; tooltipDetail: "AUTO LAUNCH SEQUENCE"
                onActivated: bridge.requestCommand("launch")
                onDenied: (r) => nv.denied("LAUNCH UNAVAILABLE", r)
            }
            Item {
                width: actionPanel.divW; height: actionPanel.keyH
                Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 4 * nv.s; height: parent.height; radius: 2 * nv.s; color: "#0b0b0a"; border.color: "#3e3b32"; border.width: 1 }
            }
            // saved locations: tap = plot, hold 2 s = save the current target there
            Repeater {
                model: [["HOME", "home", bridge.navHomeSystem], ["BOOKMARK 1", "bookmark1", bridge.navBookmark1System], ["BOOKMARK 2", "bookmark2", bridge.navBookmark2System]]
                DeckKey {
                    width: actionPanel.keyW; height: actionPanel.keyH
                    title: modelData[0]
                    holdToSave: true
                    readonly property string saved: String(modelData[2] || "")
                    readonly property bool run: actionPanel.plotting && actionPanel.lastPreset === modelData[1]
                    legend: run ? bridge.bridgeMessage : saved
                    keyState: run ? "running" : (saved === "" ? "empty" : (actionPanel.bindsReady ? "ready" : "unavailable"))
                    unavailableReason: actionPanel.bindsReason
                    tooltip: saved !== "" ? "PLOT TO " + saved.toUpperCase() : modelData[0] + " IS EMPTY"
                    tooltipDetail: "HOLD 2 SEC TO SAVE " + (nv.saveTarget !== "" ? nv.saveTarget.toUpperCase() : "THE SELECTED SYSTEM")
                    onActivated: { actionPanel.lastPreset = modelData[1]; nv.navDraft = saved; nv.clearSelection(); bridge.plotMemory(modelData[1]) }
                    property bool savedNow: false
                    property bool announced: false
                    onHoldProgressChanged: {
                        if (holdProgress > 0 && !announced) {
                            announced = true; savedNow = false
                            nv.notice("SAVING " + modelData[0], nv.saveTarget !== "" ? "HOLD // " + nv.saveTarget : "NOTHING SELECTED OR PLOTTED", "info")
                        } else if (holdProgress === 0 && announced) {
                            announced = false
                            notSaved.restart()
                        }
                    }
                    Timer { id: notSaved; interval: 60; onTriggered: if (!parent.savedNow) nv.notice(modelData[0] + " NOT SAVED", "HOLD THE KEY FOR 2 SECONDS", "info") }
                    onSaveRequested: {
                        savedNow = true
                        var t = nv.saveTarget
                        if (t === "" || t === "-") { nv.notice(modelData[0] + " NOT SAVED", "SELECT A SYSTEM OR PLOT A ROUTE FIRST", "bad"); return }
                        if (nv.navSelected !== "") bridge.setNavigationMemory(modelData[1], t)
                        else bridge.captureNavigationMemory(modelData[1])
                        nv.notice(modelData[0] + " SAVED", t, "ok")
                    }
                    onDenied: (r) => nv.denied(modelData[0] + (saved === "" ? " EMPTY" : " UNAVAILABLE"), saved === "" ? "HOLD 2 SEC TO SAVE " + (nv.saveTarget !== "" ? nv.saveTarget.toUpperCase() : "THE SELECTED SYSTEM") : r)
                }
            }
        }
        Text {
            x: 26 * nv.s + (actionPanel.keyW + actionPanel.keyGap) * 4 + actionPanel.divW + actionPanel.keyGap
            y: actionPanel.keyY - height - 6 * nv.s
            text: "SAVED LOCATIONS // PRESS TO PLOT // HOLD 2 SEC TO SAVE"
            color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: Math.max(8, 13 * nv.s); font.letterSpacing: 3 * nv.s
        }

        // CANCEL: pinned far right
        Item {
            x: actionPanel.width - actionPanel.cancelW - 40 * nv.s
            y: actionPanel.keyY
            width: actionPanel.cancelW; height: actionPanel.keyH
            Glow { target: cancelKey; color: "#ff5040"; spread: 34 * nv.s; radius: 8 * nv.s; intensity: actionPanel.inControl ? 0.8 : 0 }
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
