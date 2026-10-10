// SETUP > VOICE & AI (page 6). How the ship sounds and talks, what it hears, and what the AI may do.
// Plain layout on purpose (setup-plan.md): title, one sentence, then the controls.
import QtQuick
import QtQuick.Controls
import "../skin"

Item {
    id: va
    property var app
    signal denied(string title, string reason)
    signal notice(string title, string detail, string level)

    readonly property Item voiceTarget: voicePlate
    readonly property Item hearTarget: hearPlate
    readonly property Item aiTarget: rightCol
    readonly property Item deckTarget: deck

    readonly property real s: Theme.s
    readonly property real g: Math.max(8, 14 * s)
    readonly property real deckH: height * 0.175
    readonly property real deckY: height - deckH
    readonly property real bodyH: deckY - g
    readonly property real leftW: (width - g) * 0.5
    readonly property bool core: String(bridge.bridgeMode) === "CORE"
    readonly property real rowH: Math.max(52 * s, Math.min(70 * s, bodyH / 12))

    component Blurb: Text {
        color: Theme.plateText; opacity: 0.85; font.family: Theme.labelFont; font.pixelSize: Math.max(10, 16 * va.s); wrapMode: Text.WordWrap; lineHeight: 1.1
    }
    component Label2: Text {
        color: Theme.plateText; font.family: Theme.labelFont; font.weight: Font.DemiBold; font.pixelSize: Math.max(11, 18 * va.s); font.letterSpacing: 2 * va.s
    }
    component Line: Text {
        color: Theme.plateText; opacity: 0.7; font.family: Theme.labelFont; font.pixelSize: Math.max(9, 14 * va.s); wrapMode: Text.WordWrap
    }
    // < VALUE > picker for a list; shows the new value at once, follows the backend after
    component Stepper: Item {
        id: sp
        property var options: []
        property string value: ""
        signal picked(string v)
        property string pending: ""
        readonly property string shown: pending !== "" ? pending : value
        onValueChanged: if (pending === value) pending = ""
        // keep showing the new value until the backend reports it (10 s fallback, counted from the send)
        Timer { id: spTimer; interval: 10000; onTriggered: sp.pending = "" }
        // the name changes on every click; the backend only gets the one you stop on
        // (each change re-configures the voice and saves, so clicking through ten
        // voices would otherwise queue ten saves)
        Timer { id: sendTimer; interval: 350; onTriggered: { spTimer.restart(); sp.picked(sp.pending) } }
        // send a waiting change right now (VOICE TEST calls this so the test uses what you see)
        function flush() { if (sendTimer.running) { sendTimer.stop(); spTimer.restart(); picked(pending) } }
        function step(d) {
            if (!options || options.length === 0) return
            var i = options.indexOf(shown); if (i < 0) i = 0
            var n = options[(i + d + options.length) % options.length]
            pending = n; spTimer.restart(); sendTimer.restart(); Theme.cue("tick")
        }
        LitButton { id: prev; x: 0; width: height; height: parent.height; centered: true; title: "<"; repeatMs: 60; onActivated: sp.step(-1) }
        Rectangle {
            x: prev.width + 6 * va.s; width: parent.width - prev.width * 2 - 12 * va.s; height: parent.height
            radius: 5 * va.s; color: "#06140b"; border.color: "#2e4a36"
            Text { anchors.centerIn: parent; text: String(sp.shown || "-").toUpperCase(); color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: Math.max(13, 26 * va.s) }
        }
        LitButton { anchors.right: parent.right; width: height; height: parent.height; centered: true; title: ">"; repeatMs: 60; onActivated: sp.step(1) }
    }

    // ================================================================= SHIP VOICE
    Plate {
        id: voicePlate
        x: 0; y: 0; width: va.leftW; height: va.bodyH * 0.64
        screwSize: 13 * va.s
        Dymo { x: 26 * va.s; y: 14 * va.s; text: "SHIP VOICE" }
        Blurb { id: vb; x: 26 * va.s; y: 56 * va.s; width: parent.width - 52 * va.s
                text: "How the ship sounds and how much it talks. VOICE TEST below plays a sample." }
        Column {
            x: 26 * va.s; y: vb.y + vb.height + 12 * va.s
            width: parent.width - 52 * va.s
            spacing: 10 * va.s
            // talk level
            Item {
                width: parent.width; height: va.rowH
                Column {
                    anchors.verticalCenter: parent.verticalCenter; width: parent.width - talkSel.width - 16 * va.s
                    Label2 { text: "HOW MUCH IT TALKS" }
                    Line { width: parent.width; text: "Quiet still warns you about danger." }
                }
                SelectorRow {
                    id: talkSel
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    readonly property var values: ["OFF", "IMPORTANT", "MOST"]
                    options: ["QUIET", "BALANCED", "TALKATIVE"]
                    buttonWidth: 132 * va.s; buttonHeight: 48 * va.s
                    currentIndex: Math.max(0, values.indexOf(String(bridge.voiceAttentionMode || "IMPORTANT")))
                    onPicked: (i) => { if (i !== currentIndex) bridge.setVoiceAttention(values[i]) }
                }
            }
            // voice + pitch
            Row {
                width: parent.width; height: va.rowH * 1.4; spacing: 20 * va.s
                Column {
                    width: (parent.width - parent.spacing) / 2; spacing: 4 * va.s
                    Label2 { text: "VOICE" }
                    Stepper { id: nameStep; width: parent.width; height: 50 * va.s; options: bridge.voiceNameOptions; value: bridge.voiceName
                              onPicked: (v) => bridge.setVoiceTuning("name", v) }
                }
                Column {
                    width: (parent.width - parent.spacing) / 2; spacing: 4 * va.s
                    Label2 { text: "PITCH" }
                    Stepper { id: pitchStep; width: parent.width; height: 50 * va.s; options: bridge.voicePitchOptions; value: bridge.voicePitch
                              onPicked: (v) => bridge.setVoiceTuning("pitch", v) }
                }
            }
            Row {
                width: parent.width; height: va.rowH * 1.4; spacing: 20 * va.s
                Column {
                    width: (parent.width - parent.spacing) / 2; spacing: 4 * va.s
                    Label2 { text: "CHARACTER" }
                    Stepper { id: charStep; width: parent.width; height: 50 * va.s; options: bridge.voiceEffectOptions; value: bridge.voiceEffect
                              onPicked: (v) => bridge.setVoiceTuning("effect", v) }
                }
                Line { width: (parent.width - parent.spacing) / 2; anchors.bottom: parent.bottom; anchors.bottomMargin: 8 * va.s
                       text: "Clean is a plain voice; the others add a radio, ship or synth sound." }
            }
            // faders
            Row {
                width: parent.width; height: 120 * va.s; spacing: 20 * va.s
                SlideFader {
                    id: strengthFader
                    width: (parent.width - parent.spacing) / 2; height: parent.height; vertical: false
                    label: "EFFECT STRENGTH"
                    property real live: -1
                    value: live >= 0 ? live : Number(bridge.voiceEffectStrength || 0)
                    onMoved: (v) => live = v
                    onCommitted: (v) => { bridge.setVoiceTuningNumber("effect_strength", v); liveReset.restart() }
                    Timer { id: liveReset; interval: 1500; onTriggered: strengthFader.live = -1 }
                }
                SlideFader {
                    id: speedFader
                    width: (parent.width - parent.spacing) / 2; height: parent.height; vertical: false
                    label: "SPEECH SPEED"
                    // speed 0.7x .. 2.0x shown on a 0..100 slot
                    property real live: -1
                    readonly property real speed: live >= 0 ? 0.7 + live / 100 * 1.3 : Number(bridge.voiceSpeed || 1)
                    value: live >= 0 ? live : Math.max(0, Math.min(100, (Number(bridge.voiceSpeed || 1) - 0.7) / 1.3 * 100))
                    readout: speed.toFixed(2) + "X"
                    onMoved: (v) => live = v
                    onCommitted: (v) => { bridge.setVoiceTuningNumber("speed", Math.round((0.7 + v / 100 * 1.3) * 20) / 20); speedReset.restart() }
                    Timer { id: speedReset; interval: 1500; onTriggered: speedFader.live = -1 }
                }
            }
        }
    }

    // ================================================================= WHAT THE BRIDGE HEARS
    Plate {
        id: hearPlate
        x: 0; y: voicePlate.height + va.g; width: va.leftW; height: va.bodyH - y
        screwSize: 13 * va.s
        Dymo { x: 26 * va.s; y: 14 * va.s; text: "WHAT THE BRIDGE HEARS" }
        Blurb { id: hb; x: 26 * va.s; y: 56 * va.s; width: parent.width - 52 * va.s
                text: va.core ? "Talking to the ship needs AI Co-Pilot. Core Bridge only speaks to you."
                              : "Press MIC CHECK below and talk for 5 seconds. No push to talk needed and nothing is run. It shows your level and the words the AI heard." }
        Bezel {
            id: hearBezel
            visible: !va.core
            x: 16 * va.s; y: hb.y + hb.height + 10 * va.s
            width: parent.width - 32 * va.s; height: parent.height - y - 16 * va.s
            pad: 10 * va.s
            readonly property real fs: Math.max(11, Math.min(22 * va.s, (height - 20 * va.s) / 6))
            Column {
                x: 14 * va.s; y: 8 * va.s; width: hearBezel.width - 2 * hearBezel.pad - 28 * va.s
                spacing: 2 * va.s
                readonly property bool checking: String(bridge.micCheckState) !== "IDLE"
                Repeater {
                    model: parent.checking ? [] : [
                        ["PUSH TO TALK", String(bridge.pttStatus) === "NOT MAPPED" ? "KEYBOARD ONLY // CTRL+ALT+SHIFT+V" : String(bridge.voicePttMapping)],
                        ["MICROPHONE", String(bridge.voiceInputDevice || "-")],
                        ["LAST HEARD", String(bridge.voiceLastText) === "-" ? "NOTHING YET" : "\"" + String(bridge.voiceLastText) + "\""]
                    ]
                    Item {
                        width: parent.width; height: hearBezel.fs * 1.3
                        Text { text: modelData[0]; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: hearBezel.fs * 0.8; anchors.verticalCenter: parent.verticalCenter }
                        Text { anchors.right: parent.right; width: parent.width * 0.68; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight
                               text: String(modelData[1]).toUpperCase(); color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: hearBezel.fs; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
                Item {
                    width: parent.width; height: hearBezel.fs * 1.4
                    Text { id: lvl; text: "MIC LEVEL"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: hearBezel.fs * 0.8; anchors.verticalCenter: parent.verticalCenter }
                    BlockBar { x: parent.width * 0.32; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.68; height: parent.height * 0.55
                               segments: 12; value: Number(bridge.voiceMicMeter || 0) }
                }
                // mic check result (shown while checking and for a while after)
                Item { width: parent.width; height: hearBezel.fs * 0.4; visible: parent.checking }
                Text {
                    width: parent.width; elide: Text.ElideRight
                    readonly property string st: String(bridge.micCheckState)
                    visible: st !== "IDLE"
                    text: st === "LISTENING" ? "> LISTENING... TALK NOW // " + bridge.micCheckSecondsLeft + " SEC"
                        : st === "CHECKING" ? "> CHECKING WHAT IT HEARD..."
                        : "> " + String(bridge.micCheckResult)
                    color: st !== "DONE" ? Theme.info : (String(bridge.micCheckLevel) === "ok" ? Theme.ok : (String(bridge.micCheckLevel) === "bad" ? Theme.bad : Theme.info))
                    font.family: Theme.crtFont; font.pixelSize: hearBezel.fs * 1.05
                }
                Text {
                    width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                    visible: String(bridge.micCheckState) === "DONE" && String(bridge.micCheckHeard) !== ""
                    text: "HEARD: \"" + String(bridge.micCheckHeard).toUpperCase() + "\""
                    color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: hearBezel.fs
                }
                Text {
                    width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
                    visible: String(bridge.micCheckState) === "DONE" && String(bridge.micCheckDetail) !== ""
                    text: String(bridge.micCheckDetail).toUpperCase()
                    color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: hearBezel.fs * 0.8
                }
            }
        }
    }

    // ================================================================= RIGHT: AI
    Column {
        id: rightCol
        x: va.leftW + va.g; y: 0
        width: va.width - x
        spacing: va.g
        readonly property real h1: va.core ? va.bodyH : va.bodyH * 0.26
        readonly property real h2: va.bodyH * 0.34
        readonly property real h3: va.bodyH - h1 - h2 - spacing * 2

        // ---- co-pilot status / upgrade
        Plate {
            width: parent.width; height: rightCol.h1
            screwSize: 13 * va.s
            Dymo { x: 26 * va.s; y: 14 * va.s; text: "AI CO-PILOT" }
            Blurb { id: cpb; x: 26 * va.s; y: 56 * va.s; width: parent.width - 52 * va.s
                    visible: va.core || rightCol.h1 > 150
                    text: va.core ? "AI Co-Pilot is an optional upgrade. It adds talking to the ship, questions and answers, and help that knows what you're doing. Your buttons and automation stay as they are. It needs your own OpenAI API key, which OpenAI bills you for."
                                  : "Talk to the ship with push to talk. It answers using what the Bridge sees in your game." }
            Grid {
                visible: !va.core
                x: 26 * va.s; y: cpb.visible ? cpb.y + cpb.height + 12 * va.s : 52 * va.s
                columns: 4; columnSpacing: 24 * va.s; rowSpacing: 8 * va.s
                readonly property real cw: (rightCol.width - 52 * va.s - columnSpacing * 3) / 4
                Repeater {
                    model: [
                        ["CO-PILOT", String(bridge.aiCopilotStatus || "-"), String(bridge.lunaStatus) === "NO KEY" ? Theme.bad : Theme.ok],
                        ["API KEY", bridge.aiApiConfigured ? "SET AND WORKING" : "NOT SET", bridge.aiApiConfigured ? Theme.ok : Theme.bad],
                        ["MODEL", String(bridge.aiModel || "-"), Theme.phosphor],
                        ["SAFETY WATCH", String(bridge.aiSafetyLevel || "-"), (String(bridge.aiSafetyLevel) === "DANGER" || String(bridge.aiSafetyLevel) === "CRITICAL") ? Theme.bad : Theme.ok]
                    ]
                    Column {
                        width: parent.cw
                        Text { text: modelData[0]; color: Theme.plateText; opacity: 0.7; font.family: Theme.labelFont; font.pixelSize: Math.max(9, 13 * va.s); font.letterSpacing: 2 * va.s }
                        Text { width: parent.width; elide: Text.ElideRight; text: String(modelData[1]).toUpperCase(); color: modelData[2]
                               font.family: Theme.crtFont; font.pixelSize: Math.max(13, 24 * va.s); style: Text.Outline; styleColor: "#40000000" }
                    }
                }
            }
            LitButton {
                visible: va.core
                x: 26 * va.s; y: cpb.y + cpb.height + 24 * va.s
                width: Math.min(parent.width - 52 * va.s, 520 * va.s); height: 64 * va.s
                title: "UPGRADE TO AI CO-PILOT"; sub: "STEP BY STEP: COST, LIMITS, KEY, PUSH TO TALK"
                onActivated: if (va.app) va.app.openCopilotUpgradeWizard()
            }
        }

        // ---- what the AI may do
        Plate {
            visible: !va.core
            width: parent.width; height: rightCol.h2
            screwSize: 13 * va.s
            Dymo { x: 26 * va.s; y: 14 * va.s; text: "WHAT THE AI MAY DO" }
            Blurb { id: mb; x: 26 * va.s; y: 56 * va.s; width: parent.width - 52 * va.s
                    text: "When you ask the AI to plot a route or use a station service, whether it does it straight away." }
            SelectorRow {
                id: modeSel
                x: 26 * va.s; y: mb.y + mb.height + 12 * va.s
                // ASK FIRST was dropped in step 24 (old saves read as DO IT)
                readonly property var values: ["Suggest Only", "Auto Navigation"]
                options: ["SUGGEST ONLY", "DO IT"]
                buttonWidth: (parent.width - 52 * va.s - spacing) / 2; buttonHeight: 50 * va.s
                currentIndex: String(bridge.aiToolMode) === "Suggest Only" ? 0 : 1
                onPicked: (i) => bridge.setSetupValue("ai_tool_mode", values[i])
            }
            Line {
                x: 26 * va.s; y: modeSel.y + modeSel.height + 10 * va.s; width: parent.width - 52 * va.s
                visible: y + height < parent.height - 70 * va.s
                opacity: 0.85
                text: ["Suggest only: the AI tells you what it would do, but doesn't plot routes or run services.",
                       "Do it: the AI plots the routes and runs the station services you ask for. CANCEL always stops it."][modeSel.shownIndex]
            }
            Row {
                x: 26 * va.s; y: parent.height - height - 18 * va.s
                width: parent.width - 52 * va.s; height: 46 * va.s; spacing: 14 * va.s
                Rectangle {
                    width: parent.width - clearRules.width - parent.spacing; height: parent.height
                    radius: 5 * va.s; color: "#06140b"; border.color: "#2e4a36"
                    Text { anchors.verticalCenter: parent.verticalCenter; x: 12 * va.s; width: parent.width - 24 * va.s; elide: Text.ElideRight
                           text: Number(bridge.aiSessionRuleCount || 0) + " SESSION RULE" + (Number(bridge.aiSessionRuleCount || 0) === 1 ? "" : "S") + " // RULES YOU GIVE THE AI LAST UNTIL THE BRIDGE CLOSES"
                           color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: Math.max(12, 21 * va.s) }
                }
                LitButton {
                    id: clearRules
                    width: 230 * va.s; height: parent.height; centered: true
                    title: "CLEAR SESSION RULES"
                    available: Number(bridge.aiSessionRuleCount || 0) > 0
                    unavailableReason: "NO SESSION RULES // RULES YOU GIVE THE AI LAST UNTIL THE BRIDGE CLOSES"
                    onActivated: { bridge.requestCommand("clear_rules"); va.notice("SESSION RULES CLEARED", "", "ok") }
                    onDenied: (r) => va.denied("NOTHING TO CLEAR", r)
                }
            }
        }

        // ---- what the AI knows
        Plate {
            visible: !va.core
            width: parent.width; height: rightCol.h3
            screwSize: 13 * va.s
            Dymo { x: 26 * va.s; y: 14 * va.s; text: "WHAT THE AI KNOWS ABOUT YOU" }
            LitButton {
                anchors.right: parent.right; anchors.rightMargin: 26 * va.s; y: 10 * va.s
                width: 190 * va.s; height: 40 * va.s; centered: true; title: "RESET TO DEFAULT"
                onActivated: { ctx.focus = false; ctx.text = String(bridge.setupAiContextDefault || ""); bridge.setSetupValue("ai_context_reset", "1"); va.notice("AI NOTES RESET", "BACK TO THE DEFAULT", "ok") }
            }
            Blurb { id: kb; x: 26 * va.s; y: 60 * va.s; width: parent.width - 52 * va.s
                    text: "Optional. Tell the AI what you're doing or how you like help; it reads this with every request." }
            Rectangle {
                id: ctxBox
                x: 26 * va.s; y: kb.y + kb.height + 10 * va.s
                width: parent.width - 52 * va.s - saveCtx.width - 14 * va.s; height: parent.height - y - 46 * va.s
                radius: 6 * va.s; color: "#06140b"; border.color: ctx.activeFocus ? Theme.ok : "#2e4a36"
                ScrollView {
                    anchors.fill: parent; anchors.margins: 6 * va.s
                    TextArea {
                        id: ctx
                        wrapMode: TextEdit.Wrap; selectByMouse: true
                        color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: Math.max(12, 20 * va.s)
                        placeholderText: "e.g. I'm new to combat, keep advice short."; placeholderTextColor: Theme.dimText
                        background: Item {}
                        property string saved: String(bridge.setupAiContext || "")
                        onSavedChanged: if (!activeFocus) text = saved
                        Component.onCompleted: text = saved
                    }
                }
            }
            LitButton {
                id: saveCtx
                anchors.right: parent.right; anchors.rightMargin: 26 * va.s; y: ctxBox.y
                width: 150 * va.s; height: 54 * va.s; centered: true; title: "SAVE"
                onActivated: {
                    var t = ctx.text.trim().slice(0, 1000)
                    if (t.length === 0) t = String(bridge.setupAiContextDefault || "")
                    ctx.text = t; ctx.focus = false
                    bridge.setSetupValue("ai_context", t)
                    va.notice("AI NOTES SAVED", "USED WITH EVERY AI REQUEST", "ok")
                }
            }
            Line {
                x: 26 * va.s; y: parent.height - height - 14 * va.s; width: parent.width - 52 * va.s; opacity: 0.6
                text: "OpenAI runs the AI and bills your account. Answers can be wrong, and the cost shown on Status is an estimate."
            }
        }
    }

    // ================================================================= ACTION DECK
    component Groove: Item {
        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 4 * va.s; height: parent.height; radius: 2 * va.s; color: "#0b0b0a"; border.color: "#3e3b32"; border.width: 1 }
    }
    component Caption: Text {
        color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: Math.max(8, 13 * va.s); font.letterSpacing: 3 * va.s
    }
    Plate {
        id: deck
        dark: true
        screwSize: 13 * va.s
        x: 0; y: va.deckY; width: va.width; height: va.deckH
        readonly property real keyH: Math.min(height - 66 * va.s, 150 * va.s)
        readonly property real keyY: 52 * va.s + (height - 66 * va.s - keyH) / 2
        readonly property real cancelW: 270 * va.s
        readonly property real divW: 40 * va.s
        readonly property real keyGap: 14 * va.s
        readonly property real keyW: (width - 26 * va.s - cancelW - 40 * va.s - 44 * va.s - divW * 2 - keyGap * 8) / 7
        Dymo { x: 26 * va.s; y: 14 * va.s; text: "ACTIONS // VOICE & AI" }
        Row {
            id: dRow
            x: 26 * va.s; y: deck.keyY
            spacing: deck.keyGap
            DeckKey {
                id: vtKey
                width: deck.keyW; height: deck.keyH
                title: "VOICE TEST"; legend: "HEAR THE SHIP"
                tooltip: "PLAY A SAMPLE"; tooltipDetail: "USES THE VOICE SETTINGS ABOVE"
                // changes still waiting to be sent go first (one ordered queue), so the test uses them
                onActivated: { nameStep.flush(); pitchStep.flush(); charStep.flush(); bridge.requestCommand("voice_test") }
            }
            DeckKey {
                id: micKey
                visible: !va.core
                readonly property string st: String(bridge.micCheckState)
                width: visible ? deck.keyW * 1.2 : 0; height: deck.keyH
                title: "MIC CHECK"
                legend: st === "LISTENING" ? "LISTENING // " + bridge.micCheckSecondsLeft + " SEC"
                      : st === "CHECKING" ? "CHECKING..."
                      : "5 SEC // NO PTT"
                keyState: (st === "LISTENING" || st === "CHECKING") ? "running" : "ready"
                tooltip: "CHECK YOUR MICROPHONE"; tooltipDetail: bridge.micCheckWords ? "TALK FOR 5 SECONDS // SHOWS LEVEL AND WORDS HEARD // NOTHING IS RUN" : "TALK FOR 5 SECONDS // SHOWS YOUR LEVEL"
                onActivated: if (keyState !== "running") bridge.requestCommand("mic_hearing_check")
            }
        }
        Item {
            x: deck.width - deck.cancelW - 40 * va.s; y: deck.keyY; width: deck.cancelW; height: deck.keyH
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
