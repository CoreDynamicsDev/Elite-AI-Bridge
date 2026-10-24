// SETUP > CONTROLS (page 10). Push to talk, the Bridge's own shortcut keys, and the Elite keys it needs.
// Binding works like Elite: click a cell, press the key or button. Esc or Backspace clears it.
// Clicking anywhere else (or waiting 12 s) stops listening and changes nothing.
import QtQuick
import "../skin"

Item {
    id: ct
    property var app
    signal denied(string title, string reason)
    signal notice(string title, string detail, string level)

    readonly property Item pttTarget: pttPlate
    readonly property Item commandsTarget: cmdPlate
    readonly property Item eliteTarget: elitePlate
    readonly property Item deckTarget: deck

    readonly property real s: Theme.s
    readonly property real g: Math.max(8, 14 * s)
    readonly property real deckH: height * 0.175
    readonly property real deckY: height - deckH
    readonly property real bodyH: deckY - g
    readonly property real leftW: (width - g) * 0.56

    onVisibleChanged: if (!visible) bridge.cancelAnyCapture()

    // ---- rows (only swap when the content changes; the bridge resends every 250 ms)
    readonly property var liveRows: bridge.setupControlRows || []
    property var rows: []
    property string rowsKey: ""
    onLiveRowsChanged: { var k = JSON.stringify(liveRows); if (k !== rowsKey) { rowsKey = k; rows = liveRows } }
    readonly property var liveElite: bridge.setupEliteBindingRows || []
    property var eliteRows: []
    property string eliteKey: ""
    onLiveEliteChanged: { var k = JSON.stringify(liveElite); if (k !== eliteKey) { eliteKey = k; eliteRows = liveElite } }

    readonly property int pttIndex: { for (var i = 0; i < rows.length; i++) if (String(rows[i].id) === "push_to_talk") return i; return -1 }
    readonly property var ptt: pttIndex >= 0 ? rows[pttIndex] : null
    readonly property var cmdRows: { var out = []; for (var i = 0; i < rows.length; i++) if (String(rows[i].id) !== "push_to_talk") out.push({ row: rows[i], index: i }); return out }

    readonly property string capAction: String(bridge.keyboardCaptureAction || "")
    readonly property bool capListening: bridge.keyboardCaptureListening
    readonly property bool hotasListening: bridge.hotasCaptureActive
    readonly property var done: bridge.keyboardCaptureDone || ({})
    // a finished binding flashes green (or red with the reason) for 3 s
    property real nowSec: Date.now() / 1000
    Timer { interval: 250; running: ct.visible; repeat: true; onTriggered: ct.nowSec = Date.now() / 1000 }
    function flashFor(action) {
        if (!done || String(done.action) !== action) return ""
        if (nowSec - Number(done.at || 0) > 3.5) return ""
        return done.ok ? "ok" : "bad"
    }

    function hotkeyState(r) {
        var st = String(r.hotkeyState || "")
        if (st === "READY") return { t: "READY", c: Theme.ok }
        if (st === "NOT SET") return { t: "NOT SET", c: Theme.dimText }
        if (st === "CONFLICT") return { t: "KEY BLOCKED", c: Theme.info }
        return { t: "NOT ACTIVE", c: Theme.info }
    }

    component Blurb: Text {
        color: Theme.plateText; opacity: 0.85; font.family: Theme.labelFont; font.pixelSize: Math.max(10, 16 * ct.s); wrapMode: Text.WordWrap; lineHeight: 1.1
    }

    // one click-to-bind cell (CRT style)
    component BindCell: Rectangle {
        id: bc
        property string value: ""
        property bool listening: false
        property bool waiting: false
        property string flash: ""          // "ok" / "bad" / ""
        property bool bad: false           // clash with Elite etc.
        property string listenText: "> PRESS A KEY... ESC = CLEAR"
        property string emptyText: "NOT SET // CLICK TO SET"
        property real fs: Math.max(12, 23 * ct.s)
        signal clicked()
        radius: 3 * ct.s
        color: flash === "ok" ? "#1e4a2a" : (flash === "bad" || bad ? "#2a0e0b" : (listening || waiting ? "#2a1e08" : (cellPress.containsMouse ? Theme.t("#0f2a18") : Theme.t("#07130b"))))
        border.width: listening || waiting || flash !== "" || bad ? 2 : 1
        border.color: flash === "ok" ? Theme.ok : (flash === "bad" || bad ? Theme.bad : (listening || waiting ? Theme.info : (cellPress.containsMouse ? Theme.ok : Theme.t("#2a5a38"))))
        Text {
            id: cellText
            anchors.fill: parent; anchors.leftMargin: 10 * ct.s; anchors.rightMargin: 10 * ct.s
            verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
            text: bc.waiting ? "GETTING READY..." : (bc.listening ? bc.listenText : (bc.value !== "" ? bc.value.toUpperCase() : bc.emptyText))
            color: bc.listening || bc.waiting ? Theme.info : (bc.bad ? Theme.bad : (bc.value !== "" ? Theme.phosphor : Theme.dimText))
            font.family: Theme.crtFont; font.pixelSize: bc.fs
            SequentialAnimation on opacity { running: bc.listening; loops: Animation.Infinite; NumberAnimation { to: 0.35; duration: 450 } NumberAnimation { to: 1; duration: 450 } }
        }
        PressArea { id: cellPress; anchors.fill: parent; onActivated: { Theme.cue("tick"); bc.clicked() } }
    }

    // click anywhere else on the page: stop listening, change nothing
    MouseArea { anchors.fill: parent; z: -1; onPressed: (m) => { bridge.cancelAnyCapture(); m.accepted = false } }

    // ================================================================= PUSH TO TALK
    Plate {
        id: pttPlate
        x: 0; y: 0; width: ct.leftW; height: ct.bodyH * 0.36
        screwSize: 13 * ct.s
        // push to talk only talks to the AI co-pilot: without it the panel is greyed out (still settable)
        readonly property bool needsAi: String(bridge.bridgeMode) === "CORE"
        readonly property bool mapped: ct.ptt !== null && String(ct.ptt.controllerState || "UNBOUND") !== "UNBOUND" && String(ct.ptt.controller || "NOT MAPPED") !== "NOT MAPPED"
        Dymo { x: 26 * ct.s; y: 14 * ct.s; text: pttPlate.needsAi ? "PUSH TO TALK // NEEDS THE AI CO-PILOT" : "PUSH TO TALK // REQUIRED" }
        Blurb { id: pb; x: 26 * ct.s; y: 56 * ct.s; width: parent.width - 52 * ct.s
                text: pttPlate.needsAi ? "Push to talk is how you speak to the AI co-pilot, so it does nothing until the AI is set up (Setup > Voice & AI). You can still set the button now."
                                       : "Hold it to talk to the ship. Click a cell, then press the button or key. Esc or Backspace clears it. Test it with MIC CHECK on Voice & AI." }
        Bezel {
            id: pttBezel
            opacity: pttPlate.needsAi ? 0.45 : 1
            x: 16 * ct.s; y: pb.y + pb.height + 10 * ct.s
            width: parent.width - 32 * ct.s; height: parent.height - y - 16 * ct.s
            pad: 10 * ct.s
            readonly property real fs: Math.max(12, 22 * ct.s)
            readonly property real rowH: Math.min(fs * 2.1, (height - pad * 2 - 16 * ct.s) / 3.2)
            readonly property bool clash: ct.ptt !== null && !!ct.ptt.controllerConflict
            readonly property bool ready: pttPlate.mapped || (ct.ptt !== null && String(ct.ptt.hotkeyState) === "READY")
            Column {
                x: 12 * ct.s; y: 8 * ct.s
                width: pttBezel.width - pttBezel.pad * 2 - 24 * ct.s
                // same row layout as the shortcut list: name, click-to-set cell, status
                Item {
                    width: parent.width; height: pttBezel.rowH
                    Text { x: 4 * ct.s; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.40; elide: Text.ElideRight
                           text: "HOTAS / CONTROLLER"; color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: pttBezel.fs }
                    BindCell {
                        x: parent.width * 0.42; y: 3 * ct.s; width: parent.width * 0.36; height: parent.height - 6 * ct.s
                        fs: pttBezel.fs * 0.95
                        value: pttPlate.mapped ? String(ct.ptt.controller) : ""
                        emptyText: "NOT SET // CLICK TO SET"
                        listenText: "> PRESS A BUTTON... ESC = CLEAR"
                        listening: ct.hotasListening
                        bad: pttBezel.clash
                        onClicked: { if (ct.hotasListening) bridge.cancelAnyCapture(); else bridge.beginHotasCapturePtt() }
                    }
                    Text { anchors.right: parent.right; anchors.rightMargin: 6 * ct.s; anchors.verticalCenter: parent.verticalCenter
                           text: pttBezel.clash ? "CLASH" : (pttPlate.mapped ? "READY" : "NOT SET")
                           color: pttBezel.clash ? Theme.bad : (pttPlate.mapped ? Theme.ok : Theme.dimText)
                           font.family: Theme.crtFont; font.pixelSize: pttBezel.fs * 0.85 }
                }
                Item {
                    width: parent.width; height: pttBezel.rowH
                    readonly property var st: ct.ptt ? ct.hotkeyState(ct.ptt) : ({ t: "NOT SET", c: Theme.dimText })
                    Text { x: 4 * ct.s; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.40; elide: Text.ElideRight
                           text: "KEYBOARD BACKUP"; color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: pttBezel.fs }
                    BindCell {
                        x: parent.width * 0.42; y: 3 * ct.s; width: parent.width * 0.36; height: parent.height - 6 * ct.s
                        fs: pttBezel.fs * 0.95
                        value: ct.ptt ? String(ct.ptt.hotkey || "") : ""
                        waiting: ct.capAction === "push_to_talk" && !ct.capListening
                        listening: ct.capAction === "push_to_talk" && ct.capListening
                        flash: ct.flashFor("push_to_talk")
                        onClicked: { if (ct.capAction === "push_to_talk") bridge.cancelAnyCapture(); else bridge.beginBridgeHotkeyCaptureRowSafe(ct.pttIndex) }
                    }
                    Text { anchors.right: parent.right; anchors.rightMargin: 6 * ct.s; anchors.verticalCenter: parent.verticalCenter
                           text: parent.st.t; color: parent.st.c; font.family: Theme.crtFont; font.pixelSize: pttBezel.fs * 0.85 }
                }
                Item { width: parent.width; height: pttBezel.fs * 0.5 }
                Text {
                    width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                    text: pttBezel.clash ? "> ELITE ALREADY USES THIS BUTTON: " + String(ct.ptt.controllerConflictDetail || "") + ". PICK ANOTHER."
                        : pttPlate.needsAi ? "> WORKS ONCE THE AI CO-PILOT IS SET UP."
                        : (pttBezel.ready ? "> READY. HOLD IT AND SPEAK, LET GO TO SEND." : "> NOT SET. THE SHIP CAN'T HEAR YOU UNTIL ONE IS SET.")
                    color: pttBezel.clash ? Theme.bad : (pttPlate.needsAi ? Theme.dimText : (pttBezel.ready ? Theme.ok : Theme.info))
                    font.family: Theme.crtFont; font.pixelSize: pttBezel.fs * 0.9
                }
            }
        }
    }

    // ================================================================= BRIDGE COMMANDS (keyboard)
    Plate {
        id: cmdPlate
        x: 0; y: pttPlate.height + ct.g; width: ct.leftW; height: ct.bodyH - y
        screwSize: 13 * ct.s
        readonly property int nReady: { var n = 0; for (var i = 0; i < ct.cmdRows.length; i++) if (String(ct.cmdRows[i].row.hotkeyState) === "READY") n++; return n }
        readonly property int nBlocked: { var n = 0; for (var i = 0; i < ct.cmdRows.length; i++) if (String(ct.cmdRows[i].row.hotkeyState) === "CONFLICT") n++; return n }
        readonly property int nUnset: { var n = 0; for (var i = 0; i < ct.cmdRows.length; i++) if (String(ct.cmdRows[i].row.hotkeyState) === "NOT SET") n++; return n }
        Dymo { x: 26 * ct.s; y: 14 * ct.s; text: "BRIDGE SHORTCUT KEYS" }
        Text { anchors.right: parent.right; anchors.rightMargin: 26 * ct.s; y: 20 * ct.s
               text: cmdPlate.nReady + " READY" + (cmdPlate.nBlocked ? " // " + cmdPlate.nBlocked + " BLOCKED" : "") + (cmdPlate.nUnset ? " // " + cmdPlate.nUnset + " NOT SET" : "")
               color: cmdPlate.nBlocked ? Theme.info : Theme.plateText; font.family: Theme.labelFont; font.weight: Font.DemiBold; font.pixelSize: Math.max(10, 15 * ct.s); font.letterSpacing: 2 * ct.s }
        Blurb { id: cb; x: 26 * ct.s; y: 56 * ct.s; width: parent.width - 52 * ct.s
                text: "Work anywhere, even while Elite has focus, so they suit a Stream Deck or HOTAS software. Click a key, press the new one (it needs Ctrl or Alt). Esc or Backspace clears it. Don't reuse a combo you gave an Elite control." }
        Bezel {
            id: cmdBezel
            x: 16 * ct.s; y: cb.y + cb.height + 10 * ct.s
            width: parent.width - 32 * ct.s; height: parent.height - y - 16 * ct.s - msg.height - 8 * ct.s
            pad: 10 * ct.s
            readonly property real fs: Math.max(12, 22 * ct.s)
            PhosphorList {
                id: cmdList
                x: 12 * ct.s; y: 8 * ct.s
                width: cmdBezel.width - cmdBezel.pad * 2 - 24 * ct.s; height: cmdBezel.height - cmdBezel.pad * 2 - 16 * ct.s
                fontSize: cmdBezel.fs
                model: ct.cmdRows
                delegate: Item {
                    required property var modelData
                    readonly property var r: modelData.row
                    readonly property string act: String(r.id)
                    readonly property var st: ct.hotkeyState(r)
                    width: cmdList.list.width - (cmdList.overflow ? 0 : 26 * ct.s)
                    height: cmdBezel.fs * 2.1
                    Text { x: 4 * ct.s; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.40; elide: Text.ElideRight
                           text: String(r.label); color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: cmdBezel.fs }
                    BindCell {
                        x: parent.width * 0.42; y: 3 * ct.s; width: parent.width * 0.36; height: parent.height - 6 * ct.s
                        fs: cmdBezel.fs * 0.95
                        value: String(r.hotkey || "")
                        waiting: ct.capAction === act && !ct.capListening
                        listening: ct.capAction === act && ct.capListening
                        flash: ct.flashFor(act)
                        onClicked: { if (ct.capAction === act) bridge.cancelAnyCapture(); else bridge.beginBridgeHotkeyCaptureRowSafe(modelData.index) }
                    }
                    Text { anchors.right: parent.right; anchors.rightMargin: 6 * ct.s; anchors.verticalCenter: parent.verticalCenter
                           text: parent.st.t; color: parent.st.c; font.family: Theme.crtFont; font.pixelSize: cmdBezel.fs * 0.85 }
                }
            }
        }
        Text {
            id: msg
            x: 26 * ct.s; y: parent.height - height - 14 * ct.s; width: parent.width - 52 * ct.s
            elide: Text.ElideRight
            readonly property string st: String(bridge.keyboardCaptureStatus || "")
            readonly property string err: String(bridge.keyboardCaptureError || "")
            text: ct.capAction !== "" ? (ct.capListening ? (st.indexOf("ADD CTRL") >= 0 || st.indexOf("UNSUPPORTED") >= 0 ? st : "LISTENING // PRESS THE NEW KEY // ESC OR BACKSPACE CLEARS IT // CLICK ANYWHERE ELSE TO STOP") : "GETTING READY // RELEASING THE BRIDGE'S SHORTCUTS FOR A MOMENT")
                : (ct.flashFor(String(ct.done.action || "")) === "bad" ? String(ct.done.text || err)
                : (ct.flashFor(String(ct.done.action || "")) === "ok" ? "SAVED // " + String(ct.done.text || "")
                : (st.indexOf("TIMED OUT") === 0 ? st : "Windows only lets one program own a key. KEY BLOCKED means another program has it; pick another.")))
            color: ct.capAction !== "" ? Theme.info : (ct.flashFor(String(ct.done.action || "")) === "bad" ? Theme.bad : (ct.flashFor(String(ct.done.action || "")) === "ok" ? Theme.ok : Theme.plateText))
            opacity: ct.capAction === "" && ct.flashFor(String(ct.done.action || "")) === "" ? 0.7 : 1
            font.family: Theme.labelFont; font.weight: Font.DemiBold; font.pixelSize: Math.max(10, 15 * ct.s); font.letterSpacing: 1 * ct.s
        }
    }

    // ================================================================= KEYS ELITE MUST HAVE
    property int pickedElite: -1
    readonly property var pickedEliteRow: pickedElite >= 0 && pickedElite < eliteRows.length ? eliteRows[pickedElite] : null
    Plate {
        id: elitePlate
        x: ct.leftW + ct.g; y: 0; width: ct.width - x; height: ct.bodyH
        screwSize: 13 * ct.s
        readonly property int nMissing: { var n = 0; for (var i = 0; i < ct.eliteRows.length; i++) if (String(ct.eliteRows[i].status) !== "READY") n++; return n }
        readonly property bool live: bridge.eliteBindingsLive
        Dymo { x: 26 * ct.s; y: 14 * ct.s; text: "KEYS ELITE MUST HAVE" }
        Text { anchors.right: parent.right; anchors.rightMargin: 26 * ct.s; y: 20 * ct.s
               text: !elitePlate.live ? "NO PROFILE FOUND" : (ct.eliteRows.length - elitePlate.nMissing) + " SET" + (elitePlate.nMissing ? " // " + elitePlate.nMissing + " MISSING" : "")
               color: !elitePlate.live || elitePlate.nMissing ? Theme.info : Theme.plateText; font.family: Theme.labelFont; font.weight: Font.DemiBold; font.pixelSize: Math.max(10, 15 * ct.s); font.letterSpacing: 2 * ct.s }
        Blurb { id: eb; x: 26 * ct.s; y: 56 * ct.s; width: parent.width - 52 * ct.s
                text: elitePlate.live ? "The Bridge presses these Elite keys for you, so they need a key in Elite's own Controls. It reads your active profile and never changes it. A missing one shows a free key you could use: pick it, then COPY SUGGESTION."
                                      : "No active Elite key profile found. Start Elite once, then press RESCAN ELITE. Docking, launch and combat keys from the Bridge won't work until then." }
        Bezel {
            id: eBezel
            x: 16 * ct.s; y: eb.y + eb.height + 10 * ct.s
            width: parent.width - 32 * ct.s; height: parent.height - y - 16 * ct.s
            pad: 10 * ct.s
            readonly property real fs: Math.max(12, 22 * ct.s)
            PhosphorList {
                id: eList
                x: 12 * ct.s; y: 8 * ct.s
                width: eBezel.width - eBezel.pad * 2 - 24 * ct.s; height: eBezel.height - eBezel.pad * 2 - 16 * ct.s
                fontSize: eBezel.fs
                model: ct.eliteRows
                delegate: Item {
                    required property var modelData
                    required property int index
                    readonly property bool ready: String(modelData.status) === "READY"
                    readonly property bool picked: index === ct.pickedElite
                    width: eList.list.width - (eList.overflow ? 0 : 26 * ct.s)
                    height: eBezel.fs * 1.5
                    Rectangle { anchors.fill: parent; visible: parent.picked || ePress.containsMouse
                                color: parent.picked ? Theme.t("#2a7dff9c") : Theme.t("#127dff9c"); border.color: parent.picked ? Theme.t("#807dff9c") : "transparent"; border.width: 1 }
                    Text { x: 6 * ct.s; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.48; elide: Text.ElideRight
                           text: (parent.picked ? "> " : "  ") + String(modelData.label)
                           color: parent.ready ? Theme.phosphor : Theme.info; font.family: Theme.crtFont; font.pixelSize: eBezel.fs }
                    Text { anchors.right: parent.right; anchors.rightMargin: 6 * ct.s; anchors.verticalCenter: parent.verticalCenter
                           width: parent.width * 0.50; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight
                           text: parent.ready ? String(modelData.detail || "READY").toUpperCase()
                               : (String(modelData.status) === "UNAVAILABLE" ? "NO PROFILE" : "MISSING" + (modelData.suggestion ? " // TRY " + String(modelData.suggestion).toUpperCase() : ""))
                           color: parent.ready ? Theme.dimText : Theme.info; font.family: Theme.crtFont; font.pixelSize: eBezel.fs * 0.85 }
                    PressArea { id: ePress; anchors.fill: parent; onActivated: { Theme.cue("tick"); ct.pickedElite = (ct.pickedElite === index ? -1 : index) } }
                }
            }
        }
    }

    // ================================================================= ACTION DECK
    component Groove: Item {
        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 4 * ct.s; height: parent.height; radius: 2 * ct.s; color: "#0b0b0a"; border.color: "#3e3b32"; border.width: 1 }
    }
    Plate {
        id: deck
        dark: true
        screwSize: 13 * ct.s
        x: 0; y: ct.deckY; width: ct.width; height: ct.deckH
        readonly property real keyH: Math.min(height - 66 * ct.s, 150 * ct.s)
        readonly property real keyY: 52 * ct.s + (height - 66 * ct.s - keyH) / 2
        readonly property real cancelW: 270 * ct.s
        readonly property real divW: 40 * ct.s
        readonly property real keyGap: 14 * ct.s
        readonly property real keyW: (width - 26 * ct.s - cancelW - 40 * ct.s - 44 * ct.s - divW * 2 - keyGap * 8) / 7
        readonly property bool hasSuggestion: ct.pickedEliteRow !== null && String(ct.pickedEliteRow.suggestion || "") !== ""
        Dymo { x: 26 * ct.s; y: 14 * ct.s; text: "ACTIONS // CONTROLS" }
        Row {
            x: 26 * ct.s; y: deck.keyY
            spacing: deck.keyGap
            DeckKey {
                id: restoreKey
                width: deck.keyW * 1.2; height: deck.keyH
                title: "RESTORE KEYS"; legend: holdProgress > 0 ? "KEEP HOLDING..." : "HOLD 2 SEC"
                holdToSave: true
                tooltip: "PUT EVERY BRIDGE SHORTCUT BACK TO CTRL+ALT+SHIFT"; tooltipDetail: "HOLD 2 SECONDS // HOTAS PUSH TO TALK IS KEPT"
                onActivated: ct.notice("HOLD TO RESTORE", "HOLD THE KEY FOR 2 SECONDS", "info")
                onSaveRequested: { bridge.cancelAnyCapture(); bridge.restoreBridgeHotkeys(); ct.notice("KEYS RESTORED", "ALL BRIDGE SHORTCUTS BACK TO DEFAULT", "ok") }
            }
            Groove { width: deck.divW; height: deck.keyH }
            DeckKey {
                width: deck.keyW * 1.2; height: deck.keyH
                title: "RESCAN ELITE"; legend: "AFTER CHANGING ELITE KEYS"
                tooltip: "READ ELITE'S KEY PROFILE AGAIN"; tooltipDetail: "USE AFTER CHANGING CONTROLS IN ELITE"
                onActivated: { bridge.requestCommand("setup_binds"); ct.notice("RESCANNING", "READING ELITE'S ACTIVE KEY PROFILE", "info") }
            }
            DeckKey {
                width: deck.keyW * 1.2; height: deck.keyH
                title: "COPY SUGGESTION"; legend: deck.hasSuggestion ? String(ct.pickedEliteRow.suggestion).toUpperCase() : "PICK A MISSING KEY"
                keyState: deck.hasSuggestion ? "ready" : "unavailable"
                unavailableReason: "PICK A MISSING KEY IN THE LIST FIRST"
                tooltip: "COPY THE FREE KEY TO THE CLIPBOARD"; tooltipDetail: "THEN SET IT IN ELITE'S OWN CONTROLS"
                onActivated: { bridge.copyTextToClipboard(String(ct.pickedEliteRow.suggestion)); ct.notice("COPIED", String(ct.pickedEliteRow.label) + " // " + String(ct.pickedEliteRow.suggestion).toUpperCase(), "ok") }
                onDenied: (r) => ct.denied("NOTHING PICKED", r)
            }
        }
        Item {
            x: deck.width - deck.cancelW - 40 * ct.s; y: deck.keyY; width: deck.cancelW; height: deck.keyH
            DeckKey {
                anchors.fill: parent
                title: "CANCEL"; legend: "STOP ALL AUTOMATION"
                cap: "red"; hazard: true
                tooltip: "STOP ALL AUTOMATION"; tooltipDetail: "BRIDGE RELEASES YOUR CONTROLS"
                onActivated: { bridge.cancelAnyCapture(); bridge.requestCommand("cancel") }
            }
        }
    }
}
