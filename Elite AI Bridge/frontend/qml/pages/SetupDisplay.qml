// SETUP > DISPLAY (page 9). The Bridge window, the screen effects, and the in-game overlay.
// Plain layout on purpose (setup-plan.md). Every control shows its new value the moment it's touched.
import QtQuick
import QtQuick.Window
import QtQml
import "../skin"

Item {
    id: dp
    property var app
    signal denied(string title, string reason)
    signal notice(string title, string detail, string level)

    readonly property Item windowTarget: winPlate
    readonly property Item fxTarget: fxPlate
    readonly property Item overlayTarget: ovPlate
    readonly property Item deckTarget: deck

    readonly property real s: Theme.s
    readonly property real g: Math.max(8, 14 * s)
    readonly property real deckH: height * 0.175
    readonly property real deckY: height - deckH
    readonly property real bodyH: deckY - g
    readonly property real leftW: (width - g) * 0.42
    readonly property real rowH: Math.max(56 * s, Math.min(84 * s, bodyH / 9.5))

    readonly property bool caution: String(bridge.eliteOverlayCompatibility).indexOf("CAUTION") === 0
    readonly property bool ready: String(bridge.eliteOverlayCompatibility).indexOf("READY") === 0
    readonly property bool overlayOn: app ? !!app.overlayRuntimeRequested : false
    readonly property int screenCount: Math.max(1, Number(bridge.monitorCount) || 1)

    component Blurb: Text {
        color: Theme.plateText; opacity: 0.85; font.family: Theme.labelFont; font.pixelSize: Math.max(10, 16 * dp.s); wrapMode: Text.WordWrap; lineHeight: 1.1
    }
    // one setting: name, one plain line, a control on the right
    component Row2: Item {
        id: r2
        property string name: ""
        property string line: ""
        default property alias holder: slot.data
        width: parent ? parent.width : 0; height: dp.rowH
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#3a3730"; opacity: 0.7 }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - slot.width - 20 * dp.s
            spacing: 3 * dp.s
            Text { text: r2.name; color: Theme.plateText; font.family: Theme.labelFont; font.weight: Font.DemiBold; font.pixelSize: Math.max(11, 19 * dp.s); font.letterSpacing: 2 * dp.s }
            Text { width: parent.width; wrapMode: Text.WordWrap; text: r2.line; visible: text !== ""; color: Theme.plateText; opacity: 0.7; font.family: Theme.labelFont; font.pixelSize: Math.max(9, 14 * dp.s) }
        }
        Item { id: slot; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: childrenRect.width; height: childrenRect.height }
    }

    // ================================================================= THIS WINDOW
    Plate {
        id: winPlate
        x: 0; y: 0; width: dp.leftW; height: dp.bodyH * 0.40
        screwSize: 13 * dp.s
        Dymo { x: 26 * dp.s; y: 14 * dp.s; text: "THIS WINDOW" }
        Blurb { id: wb; x: 26 * dp.s; y: 56 * dp.s; width: parent.width - 52 * dp.s
                text: "Where the Bridge sits. Use the keys below to move it to another screen, fill the screen, or go fullscreen. Sizing follows Windows on its own." }
        Bezel {
            id: winBezel
            x: 16 * dp.s; y: wb.y + wb.height + 10 * dp.s
            width: parent.width - 32 * dp.s; height: parent.height - y - 16 * dp.s
            pad: 10 * dp.s
            readonly property real fs: Math.max(11, Math.min(22 * dp.s, (height - 20 * dp.s) / 5.4))
            Column {
                x: 14 * dp.s; y: 8 * dp.s; width: winBezel.width - 2 * winBezel.pad - 28 * dp.s
                spacing: 2 * dp.s
                Repeater {
                    model: [
                        ["SCREEN", String(bridge.activeMonitorName || "-") + (Number(bridge.monitorCount) > 1 ? "  (" + bridge.monitorCount + " SCREENS)" : "")],
                        ["RESOLUTION", String(bridge.activeMonitorResolution || "-")],
                        ["WINDOWS SCALE", String(bridge.activeMonitorDpiScale || "-")],
                        ["MODE", String(bridge.displayMode || "-")]
                    ]
                    Item {
                        width: parent.width; height: winBezel.fs * 1.3
                        Text { text: modelData[0]; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: winBezel.fs * 0.8; anchors.verticalCenter: parent.verticalCenter }
                        Text { anchors.right: parent.right; width: parent.width * 0.62; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight
                               text: String(modelData[1]).toUpperCase(); color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: winBezel.fs; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
            }
        }
    }

    // ================================================================= SCREEN EFFECTS
    Plate {
        id: fxPlate
        x: 0; y: winPlate.height + dp.g; width: dp.leftW; height: dp.bodyH - y
        screwSize: 13 * dp.s
        Dymo { x: 26 * dp.s; y: 14 * dp.s; text: "SCREEN EFFECTS" }
        // LAB themes: screen colour. Only the screens change; keys, lamps and plates stay.
        Row {
            id: themeRow
            anchors.right: parent.right; anchors.rightMargin: 26 * dp.s; y: 12 * dp.s
            spacing: 12 * dp.s
            Text { anchors.verticalCenter: parent.verticalCenter; text: "THEME"; color: Theme.plateText; opacity: 0.8
                   font.family: Theme.labelFont; font.pixelSize: Math.max(9, 14 * dp.s); font.letterSpacing: 2 * dp.s }
            SelectorRow {
                readonly property var vals: ["GREEN", "AMBER"]
                options: ["GREEN", "OLD SCHOOL AMBER"]
                buttonWidth: 170 * dp.s; buttonHeight: 40 * dp.s
                currentIndex: Math.max(0, vals.indexOf(String(bridge.screenTheme)))
                onPicked: (i) => bridge.setScreenTheme(vals[i])
            }
        }
        Blurb { id: fb; x: 26 * dp.s; y: 62 * dp.s; width: parent.width - 52 * dp.s
                text: "The old-monitor look on the Bridge screens. THEME picks the screen colour. Drag the faders to preview, they save when you let go. Both at 0 turns the effect off and saves GPU." }
        Column {
            x: 26 * dp.s; y: fb.y + fb.height + 16 * dp.s
            width: parent.width - 52 * dp.s
            spacing: 18 * dp.s
            readonly property real fh: Math.min(130 * dp.s, (fxPlate.height - y - 40 * dp.s) / 2 - spacing)
            SlideFader {
                width: parent.width; height: parent.fh; vertical: false
                label: "STATIC"; note: "GRAIN + FLICKER"
                value: bridge.crtStatic
                onMoved: (v) => bridge.setCrtLevel("static", Math.round(v), false)
                onCommitted: (v) => bridge.setCrtLevel("static", Math.round(v), true)
            }
            SlideFader {
                width: parent.width; height: parent.fh; vertical: false
                label: "SCREEN FX"; note: "SCANLINES + GLOW"
                value: bridge.crtScreenFx
                onMoved: (v) => bridge.setCrtLevel("screen_fx", Math.round(v), false)
                onCommitted: (v) => bridge.setCrtLevel("screen_fx", Math.round(v), true)
            }
        }
        Text { x: 26 * dp.s; y: parent.height - height - 16 * dp.s; text: "DEFAULT // GREEN // STATIC 50 // SCREEN FX 80"
               color: Theme.plateText; opacity: 0.6; font.family: Theme.labelFont; font.pixelSize: Math.max(9, 13 * dp.s); font.letterSpacing: 1.5 * dp.s }
    }

    // ================================================================= IN-GAME OVERLAY
    Plate {
        id: ovPlate
        x: dp.leftW + dp.g; y: 0; width: dp.width - x; height: dp.bodyH
        screwSize: 13 * dp.s
        Dymo { x: 26 * dp.s; y: 14 * dp.s; text: "IN-GAME OVERLAY" }
        Blurb { id: ob; x: 26 * dp.s; y: 56 * dp.s; width: parent.width - 52 * dp.s
                text: "A small Bridge panel drawn over Elite. Clicks go straight through to the game, and it steps aside while the Bridge is in front on the same screen. Needs Elite in borderless or windowed mode." }
        Rectangle {
            id: warn
            visible: dp.caution
            x: 26 * dp.s; y: ob.y + ob.height + 10 * dp.s; width: parent.width - 52 * dp.s; height: visible ? wc.height + 20 * dp.s : 0
            color: "#24100c"; border.color: Theme.bad; border.width: 1; radius: 4 * dp.s
            // what's wrong, then how to fix it in Elite (the Bridge can't change Elite's setting: Elite only reads it at start)
            Column {
                id: wc
                anchors.centerIn: parent; width: parent.width - 20 * dp.s; spacing: 4 * dp.s
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                       text: "ELITE IS IN FULLSCREEN, SO THE OVERLAY CAN'T SHOW."
                       color: Theme.bad; font.family: Theme.labelFont; font.weight: Font.DemiBold; font.pixelSize: Math.max(10, 15 * dp.s); font.letterSpacing: 1 * dp.s }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                       text: "TO FIX IT, IN ELITE: OPTIONS > GRAPHICS > DISPLAY, SET FULLSCREEN TO BORDERLESS (OR WINDOWED). THE OVERLAY COMES BACK BY ITSELF."
                       color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: Math.max(9, 14 * dp.s); font.letterSpacing: 0.8 * dp.s }
            }
        }
        Column {
            id: ovCol
            x: 26 * dp.s; y: (warn.visible ? warn.y + warn.height : ob.y + ob.height) + 6 * dp.s
            width: parent.width - 52 * dp.s
            Row2 {
                name: "OVERLAY"
                line: dp.caution ? (dp.overlayOn ? "Paused: Elite is fullscreen. Set Elite to borderless and it comes back by itself." : "Not available while Elite is fullscreen.")
                    : (dp.ready ? "Elite is borderless or windowed. Good to go." : "Elite's display mode isn't known yet.")
                OnOffPair {
                    buttonWidth: 84 * dp.s; buttonHeight: 48 * dp.s
                    on: dp.overlayOn
                    available: !dp.caution
                    unavailableReason: "SWITCH ELITE TO BORDERLESS OR WINDOWED FIRST"
                    onChanged: (v) => { if (dp.app) dp.app.overlayRuntimeRequested = v; bridge.setGameOverlayEnabled(v) }
                    onDenied: (r) => dp.denied("ELITE IS FULLSCREEN", r)
                }
            }
            Row2 {
                name: "SCREEN"
                line: dp.screenCount > 1 ? "The screen Elite is on. IDENTIFY below shows the numbers." : "Your only screen. It sits over the game."
                opacity: dp.overlayOn ? 1 : 0.55
                SelectorRow {
                    options: { var o = []; for (var i = 0; i < Math.min(4, dp.screenCount); i++) o.push("SCREEN " + (i + 1)); return o }
                    buttonWidth: (dp.screenCount > 3 ? 104 : 128) * dp.s; buttonHeight: 48 * dp.s
                    currentIndex: Math.min(3, Number(bridge.gameOverlayScreen))
                    onPicked: (i) => bridge.setGameOverlayScreen(i)
                }
            }
            Row2 {
                name: "SHOWS"
                line: "Activity is status and alerts. Chat is what you and the AI said."
                opacity: dp.overlayOn ? 1 : 0.55
                SelectorRow {
                    readonly property var vals: ["ACTIVITY", "ACTIVITY_CHAT", "CHAT"]
                    options: ["ACTIVITY", "HUD + CHAT", "CHAT ONLY"]
                    buttonWidth: 128 * dp.s; buttonHeight: 48 * dp.s
                    currentIndex: Math.max(0, vals.indexOf(String(bridge.gameOverlayMode)))
                    onPicked: (i) => bridge.setGameOverlayMode(vals[i])
                }
            }
            Row2 {
                name: "SIDE"
                line: "Left and right sit halfway down the edge. Center sits across the top, out of your sights."
                opacity: dp.overlayOn ? 1 : 0.55
                SelectorRow {
                    readonly property var vals: ["LEFT", "CENTER", "RIGHT"]
                    options: vals
                    buttonWidth: 128 * dp.s; buttonHeight: 48 * dp.s
                    currentIndex: vals.indexOf(String(bridge.gameOverlayLayout))
                    onPicked: (i) => { bridge.setGameOverlayLayout(vals[i]); bridge.setGameOverlayPosition(vals[i]) }
                }
            }
            Row2 {
                name: "SIZE"
                line: ""
                opacity: dp.overlayOn ? 1 : 0.55
                SelectorRow {
                    readonly property var vals: ["SMALL", "STANDARD", "LARGE"]
                    options: vals
                    buttonWidth: 128 * dp.s; buttonHeight: 48 * dp.s
                    currentIndex: Math.max(0, vals.indexOf(String(bridge.gameOverlaySize)))
                    onPicked: (i) => bridge.setGameOverlaySize(vals[i])
                }
            }
            Item {
                width: parent.width; height: dp.rowH * 1.5
                opacity: dp.overlayOn ? 1 : 0.55
                // fader runs 0..100; the overlay takes 25..100 % visible
                SlideFader {
                    id: opFader
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width; height: Math.min(parent.height, 120 * dp.s); vertical: false
                    label: "HOW SOLID"; note: "LEFT END 25%, RIGHT END 100%"
                    property real live: -1
                    readonly property int shownPct: live >= 0 ? Math.round(25 + live * 0.75) : Number(bridge.gameOverlayOpacity || 75)
                    readout: shownPct + "%"
                    value: live >= 0 ? live : (Number(bridge.gameOverlayOpacity || 75) - 25) / 0.75
                    onMoved: (v) => live = v
                    onCommitted: (v) => { bridge.setGameOverlayOpacity(Math.round(25 + v * 0.75)); opReset.restart() }
                    Timer { id: opReset; interval: 1500; onTriggered: opFader.live = -1 }
                }
            }
        }
        Text { x: 26 * dp.s; y: parent.height - height - 16 * dp.s; text: "DEFAULT // OFF // MAIN SCREEN // HUD + CHAT // RIGHT // STANDARD // 75%"
               color: Theme.plateText; opacity: 0.6; font.family: Theme.labelFont; font.pixelSize: Math.max(9, 13 * dp.s); font.letterSpacing: 1.5 * dp.s }
    }


    // ---------------------------------------------------------------- IDENTIFY: a big number on every screen for 3 s
    property bool identifying: false
    Timer { id: idTimer; interval: 3000; onTriggered: dp.identifying = false }
    function identify() { identifying = false; identifying = true; idTimer.restart() }
    Instantiator {
        model: dp.identifying ? Qt.application.screens.length : 0
        delegate: Window {
            id: idWin
            required property int index
            readonly property var scr: Qt.application.screens[index] || Qt.application.screens[0]
            readonly property real side: Math.max(160, Math.min(340, scr.width * 0.4, scr.height * 0.4))
            readonly property bool here: index === Number(bridge.activeMonitorIndex)
            screen: scr
            flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool | Qt.WindowDoesNotAcceptFocus | Qt.WindowTransparentForInput
            color: "transparent"
            width: side; height: side
            x: scr.virtualX + (scr.width - width) / 2
            y: scr.virtualY + (scr.height - height) / 2
            visible: true
            Rectangle {
                anchors.fill: parent; radius: 22
                color: Theme.t("#ee050b07"); border.color: idWin.here ? Theme.ok : Theme.phosphor; border.width: 5
                Text { anchors.horizontalCenter: parent.horizontalCenter; y: idWin.side * 0.07; text: "SCREEN"
                       color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: idWin.side * 0.12; font.letterSpacing: 6 }
                Text { anchors.centerIn: parent; anchors.verticalCenterOffset: 14; text: String(idWin.index + 1)
                       color: idWin.here ? Theme.ok : Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: idWin.side * 0.62 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: idWin.side * 0.06
                       text: idWin.here ? "BRIDGE IS HERE" : ""; color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: idWin.side * 0.09; font.letterSpacing: 3 }
            }
        }
    }

    // ================================================================= ACTION DECK
    component Groove: Item {
        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 4 * dp.s; height: parent.height; radius: 2 * dp.s; color: "#0b0b0a"; border.color: "#3e3b32"; border.width: 1 }
    }
    Plate {
        id: deck
        dark: true
        screwSize: 13 * dp.s
        x: 0; y: dp.deckY; width: dp.width; height: dp.deckH
        readonly property real keyH: Math.min(height - 66 * dp.s, 150 * dp.s)
        readonly property real keyY: 52 * dp.s + (height - 66 * dp.s - keyH) / 2
        readonly property real cancelW: 270 * dp.s
        readonly property real divW: 40 * dp.s
        readonly property real keyGap: 14 * dp.s
        readonly property real keyW: (width - 26 * dp.s - cancelW - 40 * dp.s - 44 * dp.s - divW * 2 - keyGap * 8) / 7
        readonly property bool full: String(bridge.displayMode) === "FULLSCREEN"
        readonly property int screens: Math.max(1, Number(bridge.monitorCount) || 1)
        readonly property int here: Number(bridge.activeMonitorIndex)
        Dymo { x: 26 * dp.s; y: 14 * dp.s; text: "ACTIONS // DISPLAY" }
        Row {
            x: 26 * dp.s; y: deck.keyY
            spacing: deck.keyGap
            // up to 4 screens: one key each. 5 or more: one key that steps through them.
            Repeater {
                model: deck.screens <= 4 ? deck.screens : 0
                DeckKey {
                    required property int index
                    readonly property bool here: index === deck.here
                    readonly property var row: (bridge.monitorRows || [])[index]
                    width: deck.keyW * 0.85; height: deck.keyH
                    title: "SCREEN " + (index + 1)
                    legend: deck.screens < 2 ? "ONLY SCREEN" : (here ? "BRIDGE IS HERE" : (row ? String(row.size) : ""))
                    lampOverride: here ? "g" : ""
                    tooltip: deck.screens < 2 ? "THE BRIDGE IS ON YOUR ONLY SCREEN" : "MOVE THE BRIDGE TO SCREEN " + (index + 1)
                    tooltipDetail: row ? String(row.name).toUpperCase() + " // " + String(row.size) : ""
                    onActivated: { if (!here) bridge.moveToMonitor(index); dp.identify() }
                }
            }
            DeckKey {
                visible: deck.screens > 4
                width: visible ? deck.keyW * 1.2 : 0; height: deck.keyH
                title: "SCREEN " + (deck.here >= 0 ? deck.here + 1 : "?") + " OF " + deck.screens
                legend: "PRESS FOR NEXT"
                lampOverride: "g"
                tooltip: "MOVE THE BRIDGE TO THE NEXT SCREEN"; tooltipDetail: "STEPS 1, 2, 3... AND BACK TO 1 // IDENTIFY SHOWS THE NUMBERS"
                onActivated: { bridge.cycleMonitor(); dp.identify() }
            }
            DeckKey {
                width: deck.keyW * 0.85; height: deck.keyH
                title: "IDENTIFY"; legend: "SHOW NUMBERS"
                tooltip: "WHICH SCREEN IS WHICH"; tooltipDetail: "PUTS A BIG NUMBER ON EACH SCREEN FOR 3 SECONDS"
                onActivated: dp.identify()
            }
            Groove { width: deck.divW; height: deck.keyH }
            DeckKey {
                width: deck.keyW * 1.15; height: deck.keyH
                title: "MAXIMIZE"; legend: "FILL THIS SCREEN"
                tooltip: "FILL THE SCREEN"; tooltipDetail: "KEEPS THE WINDOW FRAME"
                onActivated: bridge.maximizeBridge()
            }
            DeckKey {
                width: deck.keyW * 1.15; height: deck.keyH
                title: "FULLSCREEN"; legend: deck.full ? "ON // CLICK TO LEAVE" : "OFF"
                lampOverride: deck.full ? "g" : ""
                tooltip: "FULLSCREEN ON OR OFF"; tooltipDetail: "CLICK AGAIN TO GO BACK TO A WINDOW"
                onActivated: bridge.toggleFullScreen()
            }
            Groove { width: deck.divW; height: deck.keyH }
            DeckKey {
                width: deck.keyW * 1.15; height: deck.keyH
                title: "RESET WINDOW"; legend: "MAIN SCREEN, FULLSCREEN"
                tooltip: "PUT THE WINDOW BACK"; tooltipDetail: "MOVES IT TO YOUR MAIN SCREEN, FULLSCREEN"
                onActivated: { bridge.resetDisplaySettings(); dp.notice("WINDOW RESET", "MAIN SCREEN // FULLSCREEN", "ok") }
            }
        }
        Item {
            x: deck.width - deck.cancelW - 40 * dp.s; y: deck.keyY; width: deck.cancelW; height: deck.keyH
            DeckKey {
                anchors.fill: parent
                title: "CANCEL"; legend: "STOP ALL AUTOMATION"
                cap: "red"; hazard: true
                tooltip: "STOP ALL AUTOMATION"; tooltipDetail: "BRIDGE RELEASES YOUR CONTROLS"
                onActivated: bridge.requestCommand("cancel")
            }
        }
    }
}
