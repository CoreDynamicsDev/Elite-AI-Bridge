// Setup wizard v2 (claude/wizard-redesign.md, mockups Mockups\wizard_simple\).
// One centred terminal, one question per screen, one to three big keys. The real
// cockpit sits behind it, dark, and powers up a piece at a time (invisible training).
// Screens (app.introStep):
//   core   0 NAME  1 ELITE  2 ELITE KEYS  3 CONTROLS  4 SOUND  5 BRIDGE SCREEN (2+ screens only)
//          6 ELITE SCREEN + OVERLAY  7 READY (Basic | AI split)
//   AI     8 COST  9 LIMITS (on OpenAI's site)  10 KEY  11 PUSH TO TALK
// Nothing moves on by itself. The keys stay greyed out until the ship has finished
// reading the screen (2026-10-10), with safeties so setup can't get stuck.
// The ship voice reads each screen (backend _wizard_page_text). Nothing here sends
// cockpit keys to Elite: the Bridge runtime is paused while the wizard is open.
import QtQuick
import QtQuick.Window
import QtQml
import "../skin"

Item {
    id: wz
    property var app                       // Main.qml root
    property var targets: ({})             // { identity, deck, dock, voice, header }
    readonly property real s: Theme.s
    readonly property int step: app ? app.introStep : 0
    readonly property bool aiRun: step >= 8
    readonly property bool upgradeOnly: app ? app.wizardUpgradeOnly : false

    // ---------------------------------------------------------------- navigation
    function go(n) {
        bridge.cancelAnyCapture()
        app.introStep = n
        app.wizardBackendStep = n
        bridge.narrateWizardStep(n)
    }
    function closeWizard(completed) {
        bridge.cancelAnyCapture()
        bridge.stopWizard()
        if (completed) {
            bridge.playUiCue("confirm")
            bridge.markFirstRunSetupCompleted()
            bridge.setFirstRunSetupEnabled(false)
        }
        app.introManualOpen = false
        app.introSessionDismissed = true
        app.startupPreflightSessionDismissed = true
        app.wizardUpgradeOnly = false
        app.wizardPath = bridge.aiApiVerified ? "COPILOT" : "CORE"
    }
    function startFlying() {
        if (!bridge.aiApiVerified) bridge.setSetupValue("bridge_mode", "CORE")
        closeWizard(true)
    }
    function finishAi() {
        bridge.setSetupValue("bridge_mode", "COPILOT")
        closeWizard(!upgradeOnly || bridge.firstRunSetupEnabled)
    }

    // ---------------------------------------------------------------- live facts
    readonly property string eliteCase: {
        if (bridge.eliteTelemetryState === "CONNECTED") return "RUNNING"
        var c = String(bridge.commander || "")
        if (bridge.eliteTelemetryState === "MENU") return "MENU"
        return (c !== "" && c !== "-") ? "FILES" : "NONE"
    }
    function known(v) { v = String(v || ""); return (v === "-" || v === "UNKNOWN") ? "" : v }
    readonly property string cmdrName: known(bridge.commander)
    readonly property string shipText: { var m = known(bridge.shipModel); return app && m ? app.niceShipName(m) : m }
    readonly property string systemText: known(bridge.system)
    readonly property var eliteRows: bridge.setupEliteBindingRows || []
    readonly property var missingKeys: { var out = []; for (var i = 0; i < eliteRows.length; i++) if (String(eliteRows[i].status) !== "READY") out.push(eliteRows[i]); return out }
    readonly property bool keysReadable: bridge.eliteBindingsLive && eliteRows.length > 0
    readonly property var controlRows: bridge.setupControlRows || []
    readonly property bool overlayCaution: String(bridge.eliteOverlayCompatibility || "").indexOf("CAUTION") === 0
    property bool pickingOutput: false
    property string keyMsg: ""             // step 9: "empty" / "short" before anything is sent
    property bool showKey: false
    property int ovScreen: 0               // step 6: the screen picked for the overlay (Elite's screen)
    readonly property int screenCount: Math.max(1, Number(bridge.monitorCount) || 1)
    readonly property int bridgeScreen: Math.max(0, Number(bridge.activeMonitorIndex))
    readonly property var otherScreens: { var o = []; for (var i = 0; i < Math.min(4, screenCount); i++) if (i !== bridgeScreen) o.push(i); return o }
    // step 6 with 2+ screens: the real overlay shows on Elite's screen while the pilot looks
    readonly property bool previewLive: visible && step === 6 && screenCount > 1 && ovScreen !== bridgeScreen
    Binding { target: wz.app; property: "overlayPreview"; value: wz.previewLive; when: !!wz.app }
    readonly property string verify: String(bridge.aiApiVerifyStatus || "")
    readonly property string heard: { var t = String(bridge.voiceLastText || ""); return (t === "-" ? "" : t) }
    readonly property bool heardOk: String(bridge.voiceInputStatus || "").indexOf("TRANSCRIPTION PASS") >= 0 && heard !== ""
    onStepChanged: {
        pickingOutput = false; keyMsg = ""; showKey = false; lockStart()
        // 2.0.0: the overlay is never switched on by itself; the pilot chooses on screen 6.
        // Elite's screen starts on the saved one, or the first screen that isn't the Bridge's.
        if (step === 6) {
            var saved = Math.max(0, Math.min(screenCount - 1, Number(bridge.gameOverlayScreen)))
            ovScreen = (screenCount > 1 && saved === bridgeScreen && otherScreens.length > 0) ? otherScreens[0] : saved
            bridge.setGameOverlayScreen(ovScreen)
        }
        if (step === 10) keyFocus.restart()
    }
    // ---- keys wait for the voice: locked from a screen change until the ship has finished
    // reading it. Safeties: unlock if the voice never starts (6 s), and after 40 s whatever happens.
    property bool voiceSeen: false
    property bool locked: false
    function lockStart() { voiceSeen = false; locked = visible; lockNoVoice.restart(); lockMax.restart() }
    Connections {
        target: bridge
        function onStateChanged() {
            if (!wz.locked) return
            if (bridge.wizardNarrationActive || bridge.voiceEngineWarming) { wz.voiceSeen = true; lockNoVoice.stop() }
            else if (wz.voiceSeen) wz.locked = false
        }
    }
    Timer { id: lockNoVoice; interval: 6000; onTriggered: if (!wz.voiceSeen) wz.locked = false }
    Timer { id: lockMax; interval: 40000; onTriggered: wz.locked = false }

    // a CRT-style pick-one row: LABEL  [ RIGHT ]  LEFT  CENTER
    component CrtPick: Row {
        id: cp
        property string label: ""
        property var opts: []
        property string cur: ""
        signal picked(string v)
        spacing: 22 * wz.s
        Text { width: 120 * wz.s; text: cp.label; color: "#bfffd0"; opacity: 0.6; font.family: Theme.crtFont; font.pixelSize: 32 * wz.s }
        Repeater {
            model: cp.opts
            delegate: Text {
                required property var modelData
                readonly property bool on: String(modelData) === cp.cur
                text: on ? "[" + modelData + "]" : " " + modelData + " "
                color: on ? Theme.ok : (pka.containsMouse ? "#ffffff" : "#bfffd0"); opacity: on ? 1 : 0.75
                font.family: Theme.crtFont; font.pixelSize: 32 * wz.s
                PressArea { id: pka; anchors.fill: parent; anchors.margins: -6 * wz.s; onActivated: { cp.picked(String(modelData)); bridge.playUiCue("nav") } }
            }
        }
    }
    // after a move, show the numbers once the window has landed
    Timer { id: moveIdent; interval: 450; onTriggered: wz.identify() }

    // ---------------------------------------------------------------- the screens
    // small: grey line on top; big: the one question/fact; line: one plain line;
    // amber: a heads-up line; note: faint line; keys: [title, legend, action]; dflt: lit key
    readonly property var screen: {
        var n = step
        if (n === 0) return { small: "ELITE AI BRIDGE // FIRST START", big: "HELLO. WHAT SHOULD\nI CALL YOU?", input: true,
                              keys: [["NEXT", "THAT'S ME", "name"]] }
        if (n === 1) {
            if (eliteCase === "RUNNING") return { small: "ELITE CONNECTED", big: "FOUND YOU, " + (cmdrName || "COMMANDER").toUpperCase() + ".",
                    line: (shipText ? "FLYING THE " + shipText.toUpperCase() : "") + (systemText ? " IN " + systemText.toUpperCase() : "") + (shipText || systemText ? "." : ""),
                    sub: "THAT'S YOU, UP TOP.",
                    amber: overlayCaution ? "ONE THING: SET ELITE TO BORDERLESS IF YOU WANT THE IN-GAME OVERLAY." : "",
                    keys: [["NEXT", "LOOKS RIGHT", "next"]] }
            if (eliteCase === "MENU") return { small: "ELITE AT MAIN MENU", big: "ELITE IS UP.",
                    line: cmdrName ? "LAST TIME: " + cmdrName.toUpperCase() + (shipText ? ", IN THE " + shipText.toUpperCase() : "") + "." : "",
                    amber: "LOAD INTO THE GAME WHEN YOU'RE READY. I'LL PICK UP YOUR SHIP BY ITSELF.",
                    keys: [["LOOK AGAIN", "I'M IN NOW", "look"], ["NEXT", "CARRY ON", "next"]] }
            if (eliteCase === "FILES") return { small: "LOOKING FOR ELITE...", big: "FOUND YOUR ELITE FILES.",
                    line: "LAST TIME: " + cmdrName.toUpperCase() + (shipText ? ", IN THE " + shipText.toUpperCase() : "") + (systemText ? " AT " + systemText.toUpperCase() : "") + ".",
                    amber: "ELITE ISN'T RUNNING. THAT'S FINE: START IT ANY TIME AND I'LL PICK IT UP.",
                    keys: [["LOOK AGAIN", "ELITE IS UP NOW", "look"], ["NEXT", "CARRY ON", "next"]] }
            return { small: "LOOKING FOR ELITE...", big: "I CAN'T FIND ELITE YET.", bigAmber: true,
                     line: "START ELITE AND LOAD INTO YOUR SHIP ONCE.\nTHEN PRESS LOOK AGAIN.",
                     note: "YOU CAN SKIP THIS AND SET UP SOUND AND CONTROLS FIRST.",
                     keys: [["SKIP", "DO IT LATER", "next"], ["LOOK AGAIN", "ELITE IS UP NOW", "look"]] }
        }
        if (n === 2) {
            if (!keysReadable) return { small: "CHECKING YOUR ELITE KEYS...", big: "I CAN'T READ YOUR\nELITE KEYS YET.", bigAmber: true,
                    line: "START ELITE ONCE SO IT SAVES ITS CONTROLS FILE.", note: "EVERYTHING ELSE WORKS WITHOUT THEM. YOU CAN DO THIS LATER.",
                    keys: [["LATER", "SKIP FOR NOW", "next"], ["LOOK AGAIN", "CHECK AGAIN", "binds"]] }
            if (missingKeys.length > 0) {
                var names = []
                for (var i = 0; i < Math.min(3, missingKeys.length); i++) names.push(String(missingKeys[i].label).toUpperCase())
                var more = missingKeys.length > 3 ? " AND " + (missingKeys.length - 3) + " MORE" : ""
                var sug = String(missingKeys[0].suggestion || "")
                return { small: "CHECKING YOUR ELITE KEYS...", big: "ELITE IS MISSING " + missingKeys.length + " KEY" + (missingKeys.length === 1 ? "" : "S") + "\nI NEED.", bigAmber: true,
                         line: names.join(", ") + more + ".", sub: "IN ELITE: OPTIONS > CONTROLS." + (sug ? " TRY " + sug.toUpperCase() + "." : ""),
                         note: "EVERYTHING ELSE WORKS WITHOUT THEM. YOU CAN DO THIS LATER.",
                         keys: [["LATER", "SKIP FOR NOW", "next"], ["LOOK AGAIN", "I SET THEM", "binds"]] }
            }
            return { small: "ELITE KEYS CHECKED", big: "YOUR ELITE KEYS\nARE ALL SET.", line: "THE BRIDGE CAN WORK ELITE'S CONTROLS FOR YOU.",
                     keys: [["NEXT", "GOOD", "next"]] }
        }
        if (n === 3) return { small: "YOUR CONTROLS", big: "THE DECK IS\nYOUR CONTROLS.",
                    line: "CLICK A KEY AND THE BRIDGE DOES IT FOR YOU.", sub: "CANCEL ALWAYS STOPS IT.",
                    keys: [["NEXT", "GOT IT", "next"]] }
        if (n === 4) {
            if (pickingOutput) return { small: "WHERE SHOULD I PLAY?", big: "PICK YOUR SPEAKERS.", picker: true,
                    keys: [["BACK", "KEEP " + String(bridge.voiceOutputDevice).toUpperCase(), "unpick"]] }
            return { small: "PLAYING ON: " + String(bridge.voiceOutputDevice).toUpperCase(), big: "CAN YOU HEAR ME?",
                     line: "THIS IS MY VOICE. YOU CAN CHANGE HOW I SOUND LATER IN SETUP.",
                     keys: [["WRONG SPEAKERS", "PICK WHERE I PLAY", "pick"], ["PLAY AGAIN", "ONE MORE TIME", "voicetest"], ["YES", "I HEAR YOU", "next"]], dflt: 2 }
        }
        if (n === 5) return { small: "YOUR SCREENS", big: "WHERE SHOULD THE\nBRIDGE GO?", bridgeScreens: true,
                    line: "CLICK A SCREEN AND I'LL MOVE THERE. NOT SURE WHICH IS WHICH? PRESS IDENTIFY.",
                    keys: [["IDENTIFY", "SHOW SCREEN NUMBERS", "identify"], ["NEXT", "BRIDGE ON SCREEN " + (bridgeScreen + 1), "next"]] }
        if (n === 6) {
            // 2.0.0: optional, off until the pilot turns it on. It steps aside while the Bridge
            // window is in front on the same screen.
            var oc = String(bridge.eliteOverlayCompatibility || "")
            var on = app && app.overlayRuntimeRequested
            var many = screenCount > 1
            var live = previewLive && oc.indexOf("CAUTION") !== 0
            var ks6 = [["NO THANKS", on ? "TURN IT OFF" : "LEAVE IT OFF", "ovoff"],
                       ["TURN IT ON", many ? (ovScreen === bridgeScreen ? "WITH THE BRIDGE" : "ON SCREEN " + (ovScreen + 1)) : "OVER THE GAME", "ovon"]]
            if (many) ks6.unshift(["IDENTIFY", "SHOW SCREEN NUMBERS", "identify"])
            return { small: "IN-GAME OVERLAY // OPTIONAL", big: many ? "WHICH SCREEN IS ELITE ON?" : "WANT THE IN-GAME OVERLAY?", overlay: true,
                     line: many ? "PICK IT AND THE OVERLAY SHOWS UP THERE, SO YOU CAN SEE IT. THEN TURN IT ON, OR LEAVE IT OFF."
                                : "A SMALL PANEL OVER ELITE: WHAT THE BRIDGE IS DOING AND WHAT THE AI SAID. CLICKS GO STRAIGHT THROUGH.",
                     okLine: live ? "● LOOK AT SCREEN " + (ovScreen + 1) + ": THAT'S THE OVERLAY." : "",
                     amber: oc.indexOf("CAUTION") === 0 ? "ELITE IS IN FULLSCREEN. TO USE THE OVERLAY, IN ELITE: OPTIONS > GRAPHICS > DISPLAY, SET FULLSCREEN TO BORDERLESS." : "",
                     note: "IT STEPS ASIDE WHILE THE BRIDGE IS IN FRONT. CHANGE IT ANY TIME IN SETUP > DISPLAY.",
                     keys: ks6, dflt: (many ? 1 : 0) + (on ? 1 : 0) }
        }
        if (n === 7) {
            return { split: true,
                     keys: [["START FLYING", "FREE", "fly"], bridge.aiApiVerified ? ["AI SETUP", "CHECK IT", "ai"] : ["SET UP AI", "ABOUT 5 MIN", "ai"]], dflt: 0 }
        }
        if (n === 8) return { small: "AI ADD-ON // WHAT IT COSTS", big: "THE AI RUNS ON OPENAI.\nEACH QUESTION COSTS FRACTIONS OF A PENNY.",
                    line: "YOU SET THE LIMITS ON THEIR SITE, SO IT CAN'T SURPRISE YOU.",
                    keys: [["BACK", upgradeOnly ? "NOT NOW" : "TO READY", "aiback"], ["NEXT", "SHOW ME", "next"]] }
        if (n === 9) return { small: "YOUR LIMITS // ON OPENAI'S SITE", big: "BUY PREPAID CREDIT.\nTURN AUTO-RECHARGE OFF.",
                    line: "YOU CAN ALSO SET A MONTHLY BUDGET THERE.", sub: "WHEN THE CREDIT RUNS OUT, THE AI STOPS AND THE BRIDGE TELLS YOU.",
                    keys: [["OPEN BILLING", "IN YOUR BROWSER", "billing"], ["DONE", "IT'S OFF", "next"]] }
        if (n === 10) {
            var savedKey = bridge.setupApiKeyLast4 ? "SAVED KEY: sk-••••" + bridge.setupApiKeyLast4 : ""
            var st = verify === "VERIFIED" && bridge.aiApiVerified ? { t: "● KEY WORKS. IT STAYS ON THIS PC.", c: "ok" }
                   : verify === "VERIFYING" ? { t: "CHECKING THE KEY WITH OPENAI...", c: "info" }
                   : verify === "FAILED" ? { t: "THAT KEY DIDN'T WORK. " + String(bridge.aiApiVerifyDetail || "").toUpperCase(), c: "bad" }
                   : keyMsg === "empty" ? { t: "PUT YOUR KEY IN THE BOX FIRST: CLICK IT, THEN CTRL+V.", c: "bad" }
                   : keyMsg === "short" ? { t: "THAT'S TOO SHORT FOR A KEY. COPY THE WHOLE THING FROM OPENAI.", c: "bad" }
                   : { t: "", c: "info" }
            var ks = [["OPEN OPENAI", "MAKE A KEY", "keys"], ["VERIFY", "CHECK MY KEY", "verify"]]
            if (bridge.aiApiVerified) ks.push(["NEXT", "KEY WORKS", "next"])
            return { small: "YOUR KEY // LIKE A PASSWORD FOR YOUR OPENAI ACCOUNT", big: "MAKE A KEY ON OPENAI,\nTHEN PASTE IT BELOW.",
                     keyinput: true, saved: savedKey, status: st, keys: ks, dflt: bridge.aiApiVerified ? 2 : 1 }
        }
        return { small: "LAST ONE // PUSH-TO-TALK", big: "HOLD YOUR TALK BUTTON\nAND SAY \"HELLO\".",
                 heardLine: true,
                 note: bridge.hotasCaptureActive ? "PRESS THE BUTTON ON YOUR STICK NOW..." : "NO TALK BUTTON YET? PRESS SET BUTTON, THEN ONE ON YOUR STICK. OR HOLD CTRL+ALT+SHIFT+V.",
                 keys: [["SET BUTTON", bridge.hotasCaptureActive ? "LISTENING..." : "PICK A TALK BUTTON", "pttbind"], ["FINISH", "START FLYING", "finish"]] }
    }

    function act(a) {
        if (a === "name") {
            var t = String(nameInput.text || "").trim()
            if (t !== "") bridge.setSetupValue("commander_address", t)
            go(1)
        }
        else if (a === "next") go(step === 4 && screenCount < 2 ? 6 : step + 1)   // one screen: no Bridge-screen page
        else if (a === "identify") identify()
        else if (a === "look") { bridge.requestCommand("setup_preflight"); bridge.playUiCue("nav") }
        else if (a === "binds") { bridge.requestCommand("setup_binds"); bridge.playUiCue("nav") }
        else if (a === "pick") { bridge.requestCommand("audio_rescan"); pickingOutput = true }
        else if (a === "unpick") pickingOutput = false
        else if (a === "voicetest") bridge.requestCommand("voice_test")
        else if (a === "fly") startFlying()
        else if (a === "ai") go(8)
        else if (a === "aiback") { if (upgradeOnly) closeWizard(false); else go(7) }

        else if (a === "billing") Qt.openUrlExternally("https://platform.openai.com/settings/organization/billing/overview")
        else if (a === "keys") Qt.openUrlExternally("https://platform.openai.com/api-keys")
        else if (a === "verify") {
            var k = String(keyInput.text || "").replace(/\s+/g, "")
            if (k === "") { keyMsg = "empty"; keyInput.forceActiveFocus() }
            else if (k.length < 20) keyMsg = "short"
            else { keyMsg = ""; bridge.saveApiKey(k) }
        }
        else if (a === "ovon") {
            bridge.setGameOverlayScreen(ovScreen)
            if (app) app.overlayRuntimeRequested = true
            bridge.setGameOverlayEnabled(true)
            go(7)
        }
        else if (a === "ovoff") {
            if (app) app.overlayRuntimeRequested = false
            bridge.setGameOverlayEnabled(false)
            go(7)
        }
        else if (a === "pttbind") { if (bridge.hotasCaptureActive) bridge.cancelAnyCapture(); else bridge.beginHotasCapturePtt() }
        else if (a === "finish") finishAi()
    }

    // ---------------------------------------------------------------- the cockpit behind, powering up
    readonly property var litNames: {
        var n = step
        if (n === 0) return []
        if (n === 1) return eliteCase === "NONE" ? [] : ["identity"]
        if (n === 2) return ["identity", "deck"]
        if (n === 3) return ["identity", "deck"]
        if (n === 4) return ["identity", "deck", "voice", "header"]
        if (n === 5 || n === 6) return ["identity", "deck", "voice", "header"]
        return []
    }
    readonly property bool allOn: step >= 7
    readonly property var hlNames: step === 3 ? ["cancel"] : (step === 11 ? ["voice", "header"] : [])
    function rectOf(name) {
        var it = targets[name]
        if (!it || !it.visible || width <= 0 || height <= 0) return Qt.vector4d(0, 0, 0, 0)
        var p = it.mapToItem(wz, 0, 0)
        return Qt.vector4d(p.x / width, p.y / height, it.width / width, it.height / height)
    }
    property int layoutTick: 0                  // re-measure after the cockpit lays out
    Timer { interval: 400; running: wz.visible; repeat: true; onTriggered: wz.layoutTick++ }
    function litRect(i) { var _t = layoutTick; return i < litNames.length ? rectOf(litNames[i]) : Qt.vector4d(0, 0, 0, 0) }

    MouseArea { anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.AllButtons; onWheel: (w) => w.accepted = true }   // the cockpit behind is look-only
    ShaderEffect {
        anchors.fill: parent
        property vector4d r0: wz.allOn ? Qt.vector4d(0, 0, 1, 1) : wz.litRect(0)
        property vector4d r1: wz.allOn ? Qt.vector4d(0, 0, 0, 0) : wz.litRect(1)
        property vector4d r2: wz.allOn ? Qt.vector4d(0, 0, 0, 0) : wz.litRect(2)
        property vector4d r3: wz.allOn ? Qt.vector4d(0, 0, 0, 0) : wz.litRect(3)
        property real dark: wz.allOn ? 0.55 : 0.90
        property real soft: 0.012
        property real aspect: wz.width / Math.max(1, wz.height)
        Behavior on dark { NumberAnimation { duration: 500 } }
        fragmentShader: Qt.resolvedUrl("../skin/shaders/scrim.frag.qsb")
    }
    // highlight rings (the key or part this screen is about)
    Repeater {
        model: wz.hlNames
        delegate: Rectangle {
            required property var modelData
            readonly property vector4d r: { var _t = wz.layoutTick; return wz.rectOf(modelData) }
            visible: r.z > 0
            x: r.x * wz.width - 6 * wz.s; y: r.y * wz.height - 6 * wz.s
            width: r.z * wz.width + 12 * wz.s; height: r.w * wz.height + 12 * wz.s
            radius: 10 * wz.s; color: "transparent"; border.color: Theme.ok; border.width: Math.max(2, 3 * wz.s)
            SequentialAnimation on opacity { loops: Animation.Infinite; running: wz.visible
                NumberAnimation { to: 0.45; duration: 900; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine } }
        }
    }

    // ---------------------------------------------------------------- the terminal
    Plate {
        id: term
        width: (wz.screen.split ? 1900 : 1500) * wz.s; height: (wz.screen.split || wz.screen.overlay ? 1060 : 900) * wz.s + waveBand
        readonly property real waveBand: 76 * wz.s      // room under the keys for the voice lines
        anchors.horizontalCenter: parent.horizontalCenter
        y: (parent.height - height) / 2 + 20 * wz.s
        screwSize: 14 * wz.s
        Bezel {
            id: bez
            x: 40 * wz.s; y: 40 * wz.s; width: parent.width - 80 * wz.s; height: (wz.screen.split || wz.screen.overlay ? 770 : 600) * wz.s
            pad: 20 * wz.s
            Column {
                id: body
                visible: !wz.screen.split
                x: 90 * wz.s; width: bez.width - 180 * wz.s
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Text { width: parent.width; text: wz.screen.small || ""; color: Theme.phosphor; opacity: 0.6; elide: Text.ElideRight
                       font.family: Theme.crtFont; font.pixelSize: 40 * wz.s }
                Item { width: 1; height: 16 * wz.s }
                Text { width: parent.width; text: wz.screen.big || ""; wrapMode: Text.WordWrap
                       color: wz.screen.bigAmber ? "#ffcf6e" : "#bfffd0"; lineHeight: 0.95
                       font.family: Theme.crtFont; font.pixelSize: (String(wz.screen.big || "").length > 34 ? 72 : 88) * wz.s }
                // name field
                Item { width: 1; height: wz.screen.input ? 34 * wz.s : 0; visible: !!wz.screen.input }
                Rectangle {
                    visible: !!wz.screen.input
                    width: 900 * wz.s; height: visible ? 96 * wz.s : 0
                    color: "#061309"; border.color: Qt.rgba(0.62, 1, 0.71, 0.6); border.width: 2
                    TextInput {
                        id: nameInput
                        anchors.fill: parent; anchors.leftMargin: 24 * wz.s; anchors.rightMargin: 24 * wz.s
                        verticalAlignment: TextInput.AlignVCenter
                        color: "#bfffd0"; font.family: Theme.crtFont; font.pixelSize: 70 * wz.s
                        maximumLength: 40; selectByMouse: true; clip: true
                        cursorDelegate: Rectangle { width: 26 * wz.s; color: Theme.ok
                            SequentialAnimation on opacity { loops: Animation.Infinite; NumberAnimation { to: 0; duration: 500 } NumberAnimation { to: 1; duration: 500 } } }
                        onAccepted: if (!wz.locked) wz.act("name")
                    }
                }
                Item { width: 1; height: wz.screen.line ? 24 * wz.s : 0 }
                Text { width: parent.width; visible: !!wz.screen.line; text: wz.screen.line || ""; wrapMode: Text.WordWrap
                       color: "#bfffd0"; opacity: 0.85; lineHeight: 1.05; font.family: Theme.crtFont; font.pixelSize: 44 * wz.s }
                Text { width: parent.width; visible: !!wz.screen.sub; text: wz.screen.sub || ""; wrapMode: Text.WordWrap
                       color: "#bfffd0"; opacity: 0.7; font.family: Theme.crtFont; font.pixelSize: 40 * wz.s }
                // BRIDGE SCREEN (2.0.0): one tile per screen; click moves the Bridge there and shows the numbers
                Item { width: 1; height: wz.screen.bridgeScreens ? 30 * wz.s : 0 }
                Row {
                    visible: !!wz.screen.bridgeScreens
                    height: visible ? 150 * wz.s : 0
                    spacing: 20 * wz.s
                    Repeater {
                        model: wz.screen.bridgeScreens ? Math.min(4, wz.screenCount) : 0
                        delegate: Rectangle {
                            id: btile
                            required property int index
                            readonly property bool here: index === wz.bridgeScreen
                            readonly property var row: (bridge.monitorRows || [])[index]
                            width: Math.min(380 * wz.s, (body.width - 20 * wz.s * (Math.min(4, wz.screenCount) - 1)) / Math.min(4, wz.screenCount)); height: 150 * wz.s
                            radius: 6 * wz.s; color: here ? Qt.rgba(0.49, 1, 0.61, 0.12) : Qt.rgba(0, 0, 0, 0.3)
                            border.color: here ? Theme.ok : (bpa.containsMouse ? "#bfffd0" : "#3a3c36"); border.width: here ? 3 : 2
                            Text { x: 18 * wz.s; y: 10 * wz.s; text: "SCREEN " + (btile.index + 1); color: btile.here ? Theme.ok : "#bfffd0"
                                   font.family: Theme.crtFont; font.pixelSize: 46 * wz.s }
                            Text { x: 18 * wz.s; y: 66 * wz.s; text: btile.row ? String(btile.row.size) : ""; color: "#bfffd0"; opacity: 0.6
                                   font.family: Theme.crtFont; font.pixelSize: 28 * wz.s }
                            Text { x: 18 * wz.s; anchors.bottom: parent.bottom; anchors.bottomMargin: 10 * wz.s
                                   text: btile.here ? "● BRIDGE IS HERE" : "CLICK TO MOVE HERE"; color: btile.here ? Theme.ok : Theme.info; opacity: btile.here ? 1 : 0.8
                                   font.family: Theme.crtFont; font.pixelSize: 28 * wz.s }
                            PressArea { id: bpa; anchors.fill: parent
                                onActivated: { if (!btile.here) { bridge.moveToMonitor(btile.index); bridge.playUiCue("nav") } moveIdent.restart() } }
                        }
                    }
                }
                // ELITE SCREEN + OVERLAY: a stand-in game view (our own starfield, no game art) with the
                // real panels where they'll sit, beside it the screens and the SIDE / SIZE pickers (2.0.0)
                Item { width: 1; height: wz.screen.overlay ? 22 * wz.s : 0 }
                Row {
                    visible: !!wz.screen.overlay
                    height: visible ? 300 * wz.s : 0
                    spacing: 30 * wz.s
                    Rectangle {
                        id: stand
                        width: 600 * wz.s; height: 300 * wz.s
                        color: "#020306"; border.color: "#3a3c36"; border.width: 2; clip: true
                        Canvas {
                            anchors.fill: parent
                            onPaint: {
                                var c = getContext("2d"); var seed = 11
                                function rnd() { seed = (seed * 16807) % 2147483647; return seed / 2147483647 }
                                for (var i = 0; i < 160; i++) { c.fillStyle = "rgba(255,255,255," + (0.2 + 0.6 * rnd()) + ")"; c.fillRect(rnd() * width, rnd() * height, 1.5, 1.5) }
                                var g = c.createRadialGradient(width * 0.25, height * 1.6, height * 0.3, width * 0.25, height * 1.6, height * 1.25)
                                g.addColorStop(0, "#1d3d5a"); g.addColorStop(0.8, "#0d2236"); g.addColorStop(0.82, "#4a86b8"); g.addColorStop(0.86, "rgba(40,80,120,0.2)"); g.addColorStop(1, "rgba(0,0,0,0)")
                                c.fillStyle = g; c.fillRect(0, 0, width, height)
                            }
                        }
                        OverlayPanels {
                            id: mini
                            readonly property string side: String(bridge.gameOverlayLayout || "RIGHT")
                            readonly property string sz: String(bridge.gameOverlaySize || "STANDARD")
                            f: 0.36 * (sz === "SMALL" ? 0.62 : (sz === "LARGE" ? 1.42 : 1.0))
                            see: Math.max(0.25, Math.min(1.0, Number(bridge.gameOverlayOpacity || 75) / 100))
                            x: side === "LEFT" ? 12 * wz.s : (side === "CENTER" ? (stand.width - width) / 2 : stand.width - width - 12 * wz.s)
                            y: side === "CENTER" ? 10 * wz.s : (stand.height - height) / 2
                            animate: wz.visible && !!wz.screen.overlay
                            activity: "AUTOMATION"; detail: "DOCKING PROTOCOL // CANCEL TO STOP"
                            rows: [{ speaker: "CMDR", text: "Request docking." }, { speaker: "BRIDGE", text: "Docking granted, pad 14. Taking us in." }]
                        }
                        Text { x: 14 * wz.s; y: parent.height - height - 10 * wz.s; text: "ELITE // YOUR GAME SCREEN"; color: "#556070"
                               font.family: Theme.crtFont; font.pixelSize: 22 * wz.s }
                    }
                    Column {
                        width: body.width - stand.width - 30 * wz.s
                        spacing: 10 * wz.s
                        Grid {
                            visible: wz.screenCount > 1
                            columns: 2; spacing: 12 * wz.s
                            Repeater {
                                // the other screens, then "same as the Bridge" (Elite windowed beside it)
                                model: wz.screenCount > 1 ? wz.otherScreens.concat([wz.bridgeScreen]) : []
                                delegate: Rectangle {
                                    id: tile
                                    required property var modelData
                                    required property int index
                                    readonly property int scr: Number(modelData)
                                    readonly property bool same: scr === wz.bridgeScreen
                                    readonly property bool picked: scr === wz.ovScreen
                                    readonly property var row: (bridge.monitorRows || [])[scr]
                                    width: (parent.parent.width - 12 * wz.s) / 2; height: 80 * wz.s
                                    radius: 6 * wz.s; color: picked ? Qt.rgba(0.49, 1, 0.61, 0.12) : Qt.rgba(0, 0, 0, 0.3)
                                    border.color: picked ? Theme.ok : (tpa.containsMouse ? "#bfffd0" : "#3a3c36"); border.width: picked ? 3 : 2
                                    Text { x: 14 * wz.s; y: 6 * wz.s; width: parent.width - 28 * wz.s; elide: Text.ElideRight
                                           text: tile.same ? "SAME AS BRIDGE" : "SCREEN " + (tile.scr + 1); color: tile.picked ? Theme.ok : "#bfffd0"
                                           font.family: Theme.crtFont; font.pixelSize: (tile.same ? 30 : 36) * wz.s }
                                    Text { x: 14 * wz.s; anchors.bottom: parent.bottom; anchors.bottomMargin: 6 * wz.s; width: parent.width - 28 * wz.s; elide: Text.ElideRight
                                           text: tile.same ? "ELITE WINDOWED BESIDE IT" : (tile.row ? String(tile.row.size) : "")
                                           color: "#bfffd0"; opacity: 0.6; font.family: Theme.crtFont; font.pixelSize: 22 * wz.s }
                                    PressArea { id: tpa; anchors.fill: parent
                                        onActivated: { wz.ovScreen = tile.scr; bridge.setGameOverlayScreen(tile.scr); bridge.playUiCue("nav") } }
                                }
                            }
                        }
                        Text { width: parent.width; visible: wz.screenCount < 2; wrapMode: Text.WordWrap
                               text: "ONE SCREEN: IT SITS OVER THE GAME. WHEN THE BRIDGE IS IN FRONT IT STEPS ASIDE."
                               color: "#bfffd0"; opacity: 0.8; font.family: Theme.crtFont; font.pixelSize: 32 * wz.s }
                        Item { width: 1; height: 4 * wz.s }
                        CrtPick { label: "SIDE"; opts: ["LEFT", "CENTER", "RIGHT"]; cur: String(bridge.gameOverlayLayout || "RIGHT")
                                  onPicked: (v) => { bridge.setGameOverlayLayout(v); bridge.setGameOverlayPosition(v) } }
                        CrtPick { label: "SIZE"; opts: ["SMALL", "STANDARD", "LARGE"]; cur: String(bridge.gameOverlaySize || "STANDARD")
                                  onPicked: (v) => bridge.setGameOverlaySize(v) }
                    }
                }
                Text { width: parent.width; visible: !!wz.screen.okLine; text: wz.screen.okLine || ""; wrapMode: Text.WordWrap; topPadding: 20 * wz.s
                       color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: 36 * wz.s }
                // SOUND: output picker
                Column {
                    visible: !!wz.screen.picker
                    width: parent.width; spacing: 4 * wz.s
                    Item { width: 1; height: 18 * wz.s }
                    Repeater {
                        model: wz.screen.picker ? (bridge.audioOutputDevices || []).slice(0, 6) : []
                        delegate: Text {
                            required property var modelData
                            readonly property bool cur: String(modelData) === String(bridge.voiceOutputDevice)
                            width: parent.width; elide: Text.ElideRight
                            text: (cur ? "> " : "  ") + String(modelData).toUpperCase()
                            color: pa.containsMouse ? "#ffffff" : (cur ? Theme.ok : "#bfffd0")
                            font.family: Theme.crtFont; font.pixelSize: 42 * wz.s
                            PressArea { id: pa; anchors.fill: parent
                                onActivated: { bridge.setAudioDevice("output", String(modelData)); wz.pickingOutput = false; voiceTestDelay.restart() } }
                        }
                    }
                }
                // KEY: a normal text box (2.0.0). Click it, Ctrl+V or right-click to paste, Enter or VERIFY.
                Item { width: 1; height: wz.screen.keyinput ? 30 * wz.s : 0 }
                Rectangle {
                    id: keyBox
                    visible: !!wz.screen.keyinput
                    width: Math.min(parent.width, 1150 * wz.s); height: visible ? 96 * wz.s : 0
                    color: "#061309"; border.color: keyInput.activeFocus ? Theme.ok : Qt.rgba(0.62, 1, 0.71, 0.6); border.width: keyInput.activeFocus ? 3 : 2
                    TextInput {
                        id: keyInput
                        objectName: "wizardKeyInput"
                        anchors.left: parent.left; anchors.right: showBtn.visible ? showBtn.left : parent.right
                        anchors.leftMargin: 24 * wz.s; anchors.rightMargin: 16 * wz.s
                        anchors.verticalCenter: parent.verticalCenter
                        color: "#bfffd0"; font.family: Theme.crtFont; font.pixelSize: 48 * wz.s
                        echoMode: wz.showKey ? TextInput.Normal : TextInput.Password
                        passwordCharacter: "•"
                        maximumLength: 400; selectByMouse: true; clip: true
                        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                        onTextChanged: if (wz.keyMsg !== "") wz.keyMsg = ""
                        onAccepted: if (!wz.locked) wz.act("verify")
                        cursorDelegate: Rectangle { width: 20 * wz.s; color: Theme.ok; visible: keyInput.activeFocus
                            SequentialAnimation on opacity { loops: Animation.Infinite; NumberAnimation { to: 0; duration: 500 } NumberAnimation { to: 1; duration: 500 } } }
                        Text { x: 34 * wz.s; anchors.verticalCenter: parent.verticalCenter; visible: keyInput.text === ""
                               text: "CLICK HERE, THEN CTRL+V TO PASTE YOUR KEY"; color: "#bfffd0"; opacity: 0.35
                               font.family: Theme.crtFont; font.pixelSize: 38 * wz.s }
                    }
                    // right-click pastes, like a terminal (there is no menu on this box)
                    MouseArea { anchors.fill: keyInput; acceptedButtons: Qt.RightButton
                                onClicked: { keyInput.forceActiveFocus(); keyInput.selectAll(); keyInput.paste() } }
                    Text {
                        id: showBtn
                        anchors.right: parent.right; anchors.rightMargin: 22 * wz.s; anchors.verticalCenter: parent.verticalCenter
                        visible: keyInput.text !== ""
                        text: wz.showKey ? "HIDE" : "SHOW"; color: spa.containsMouse ? "#ffffff" : Theme.info
                        font.family: Theme.crtFont; font.pixelSize: 34 * wz.s
                        PressArea { id: spa; anchors.fill: parent; anchors.margins: -10 * wz.s; onActivated: wz.showKey = !wz.showKey }
                    }
                }
                Text { width: parent.width; visible: !!wz.screen.saved; text: wz.screen.saved || ""; topPadding: 12 * wz.s
                       color: "#bfffd0"; opacity: 0.55; font.family: Theme.crtFont; font.pixelSize: 30 * wz.s }
                Text { width: parent.width; visible: !!(wz.screen.status && wz.screen.status.t); text: wz.screen.status ? wz.screen.status.t : ""
                       wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                       color: !wz.screen.status ? Theme.ok : (wz.screen.status.c === "ok" ? Theme.ok : (wz.screen.status.c === "bad" ? Theme.bad : "#ffcf6e"))
                       font.family: Theme.crtFont; font.pixelSize: 38 * wz.s; topPadding: 16 * wz.s }
                // PTT: what the Bridge heard
                Text { width: parent.width; visible: !!wz.screen.heardLine; topPadding: 22 * wz.s
                       textFormat: Text.StyledText
                       text: wz.heardOk ? "I HEARD: <font color='#ffffff'>\"" + wz.heard.toUpperCase().replace(/</g, "") + "\"</font> <font color='#7dff9c'>YOU'RE ALL SET.</font>"
                           : (String(bridge.voiceMode) === "LISTENING" ? "LISTENING..." : "WAITING FOR YOUR TALK BUTTON...")
                       color: "#bfffd0"; wrapMode: Text.WordWrap; font.family: Theme.crtFont; font.pixelSize: 46 * wz.s }
                Text { width: parent.width; visible: !!wz.screen.amber; text: wz.screen.amber || ""; wrapMode: Text.WordWrap; topPadding: 30 * wz.s
                       color: "#ffcf6e"; font.family: Theme.crtFont; font.pixelSize: 38 * wz.s }
                Text { width: parent.width; visible: !!wz.screen.note; text: wz.screen.note || ""; wrapMode: Text.WordWrap; topPadding: 24 * wz.s
                       color: "#bfffd0"; opacity: 0.55; font.family: Theme.crtFont; font.pixelSize: 32 * wz.s }
            }
            // READY: two roads, each with its own key underneath
            Item {
                id: split
                visible: !!wz.screen.split
                anchors.fill: parent; anchors.margins: 18 * wz.s
                Text { id: splitHead; anchors.horizontalCenter: parent.horizontalCenter; y: 6 * wz.s
                       text: "YOUR BRIDGE IS READY. PICK HOW YOU WANT TO FLY."; color: "#bfffd0"; font.family: Theme.crtFont; font.pixelSize: 46 * wz.s }
                Text { anchors.horizontalCenter: parent.horizontalCenter; y: splitHead.y + splitHead.height + 2 * wz.s
                       text: "YOU CAN ADD AI LATER IN SETUP > VOICE & AI."; color: "#bfffd0"; opacity: 0.5; font.family: Theme.crtFont; font.pixelSize: 26 * wz.s }
                Repeater {
                    model: [
                        { head: "BRIDGE BASIC", tag: "FREE", col: "#7dff9c", ai: false,
                          rows: ["DECK KEYS DOCK, LAUNCH AND JUMP FOR YOU", "STATION SERVICES, COMBAT TARGETING", "ROUTES, TRADE AND COLONY PAGES", "SHIP VOICE ALERTS + IN-GAME OVERLAY", "NOTHING TO SIGN UP FOR"],
                          cost: "FREE, NO ACCOUNT NEEDED" },
                        { head: "AI CO-PILOT", tag: bridge.aiApiVerified ? "SET UP" : "ADD-ON", col: "#ffcf6e", ai: true,
                          rows: ["EVERYTHING ON THE LEFT, PLUS:", "TALK TO YOUR SHIP WITH PUSH TO TALK", "ASK ANYTHING: ROUTES, TRADES, YOUR STATS", "GIVE ORDERS BY VOICE", "NEEDS YOUR OWN OPENAI ACCOUNT"],
                          cost: bridge.aiApiVerified ? "YOUR AI CO-PILOT IS ALREADY SET UP" : "TALKING TO THE AI COSTS FRACTIONS OF A PENNY" }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        x: index === 0 ? 0 : split.width / 2 + 10 * wz.s
                        y: 104 * wz.s
                        width: split.width / 2 - 10 * wz.s; height: split.height - y
                        radius: 6 * wz.s; color: Qt.rgba(0, 0, 0, 0.25)
                        border.color: modelData.col; border.width: 2
                        Rectangle { x: 0; y: 8 * wz.s; width: 6 * wz.s; height: parent.height - 16 * wz.s; color: modelData.col; opacity: 0.85 }
                        Text { x: 26 * wz.s; y: 14 * wz.s; text: modelData.head; color: modelData.col; font.family: Theme.crtFont; font.pixelSize: 50 * wz.s }
                        Text { anchors.right: parent.right; anchors.rightMargin: 20 * wz.s; y: 26 * wz.s; text: modelData.tag; color: modelData.col; opacity: 0.8
                               font.family: Theme.labelFont; font.weight: Font.DemiBold; font.pixelSize: 18 * wz.s; font.letterSpacing: 3 * wz.s }
                        // picture: AI = voice scope + a sample exchange; BASIC = three real deck keys
                        Item {
                            id: pic
                            x: 26 * wz.s; y: 76 * wz.s; width: parent.width - 52 * wz.s; height: 120 * wz.s
                            VoiceScope { visible: modelData.ai; width: 108 * wz.s; height: width; activity: "SPEAKING"; animate: false; t: 1.3; k: 0.9; rim: 6 * wz.s }
                            Column {
                                visible: modelData.ai
                                x: 126 * wz.s; anchors.verticalCenter: parent.verticalCenter; width: parent.width - x; spacing: 6 * wz.s
                                Text { width: parent.width; elide: Text.ElideRight; text: "CMDR> WHERE CAN I SELL MY GOLD?"; color: Theme.plateText; font.family: Theme.crtFont; font.pixelSize: 26 * wz.s }
                                Text { width: parent.width; wrapMode: Text.WordWrap; text: "BRIDGE> HUDSON HUB, 18 LY. PAYING 61,400 A TON. PLOT IT?"; color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: 26 * wz.s }
                            }
                            Row {
                                visible: !modelData.ai
                                anchors.verticalCenter: parent.verticalCenter; spacing: 12 * wz.s
                                Repeater {
                                    model: [["DOCK", "REQUEST DOCKING"], ["LAUNCH", "TAKE OFF"], ["CLEAR + JUMP", "EXIT & ENGAGE FSD"]]
                                    DeckKey { width: (pic.width - 24 * wz.s) / 3; height: 100 * wz.s; title: modelData[0]; legend: modelData[1] }
                                }
                            }
                        }
                        Column {
                            x: 26 * wz.s; y: pic.y + pic.height + 18 * wz.s; width: parent.width - 52 * wz.s; spacing: 10 * wz.s
                            Repeater { model: modelData.rows
                                delegate: Text { required property var modelData; width: parent.width; elide: Text.ElideRight
                                    text: "> " + modelData; color: "#bfffd0"; opacity: 0.85; font.family: Theme.crtFont; font.pixelSize: 34 * wz.s } }
                        }
                        Text { x: 26 * wz.s; anchors.bottom: parent.bottom; anchors.bottomMargin: 14 * wz.s; width: parent.width - 52 * wz.s; elide: Text.ElideRight
                               text: modelData.cost; color: modelData.col; font.family: Theme.crtFont; font.pixelSize: 30 * wz.s }
                    }
                }
            }
        }
        // the ship is talking (on the plate, left of the dots, so it never sits on the screen's text)
        Text {
            x: bez.x + 10 * wz.s; y: bez.y + bez.height + 18 * wz.s
            visible: bridge.wizardNarrationActive || bridge.voiceEngineWarming
            text: bridge.voiceEngineWarming ? "VOICE WARMING UP..." : "SHIP SPEAKING..."
            color: "#d9a54a"; font.family: Theme.labelFont; font.weight: Font.DemiBold; font.pixelSize: 15 * wz.s; font.letterSpacing: 3 * wz.s
        }
        // progress dots (+ AI ADD-ON tag)
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: bez.y + bez.height + 24 * wz.s
            spacing: 14 * wz.s
            Text { visible: wz.aiRun; text: "AI ADD-ON"; color: Qt.rgba(1, 0.81, 0.43, 0.85); anchors.verticalCenter: parent.verticalCenter
                   font.family: Theme.labelFont; font.weight: Font.DemiBold; font.pixelSize: 15 * wz.s; font.letterSpacing: 3 * wz.s }
            Repeater {
                model: wz.aiRun ? 4 : 8
                delegate: Rectangle {
                    required property int index
                    readonly property int here: wz.aiRun ? wz.step - 8 : wz.step
                    width: 16 * wz.s; height: width; radius: width / 2; anchors.verticalCenter: parent.verticalCenter
                    color: index < here ? Theme.ok : (index === here ? "#e8e4d8" : "#2a2c28")
                }
            }
        }
        // keys
        Row {
            id: keyRow
            anchors.horizontalCenter: parent.horizontalCenter
            y: bez.y + bez.height + 80 * wz.s
            spacing: wz.screen.split ? bez.width / 2 - 420 * wz.s : 32 * wz.s
            readonly property var ks: wz.screen.keys || []
            readonly property int def: wz.screen.dflt !== undefined ? wz.screen.dflt : ks.length - 1
            Repeater {
                model: keyRow.ks
                delegate: Item {
                    required property var modelData
                    required property int index
                    width: (wz.screen.split ? 420 : (keyRow.ks.length > 2 ? 340 : (keyRow.ks.length > 1 ? 360 : 420))) * wz.s; height: 120 * wz.s
                    Rectangle { visible: index === keyRow.def; anchors.fill: parent; anchors.margins: -8 * wz.s; radius: 8 * wz.s
                                color: "transparent"; border.color: Qt.rgba(0.49, 1, 0.61, 0.6); border.width: 2 }
                    DeckKey {
                        anchors.fill: parent
                        title: String(modelData[0]); legend: String(modelData[1])
                        keyState: wz.locked ? "unavailable" : "ready"
                        unavailableReason: "LISTEN FIRST // THE SHIP IS STILL TALKING"
                        lampOverride: (modelData[2] === "pttbind" && bridge.hotasCaptureActive) ? "a" : "-"
                        onActivated: wz.act(String(modelData[2]))
                    }
                }
            }
        }
        // wizard overlay (2.0.0): just the voice lines, under the keys. Same shapes and colours
        // as the in-game overlay, so the pilot learns what each one means while setting up.
        WaveLine {
            id: waveStrip
            anchors.horizontalCenter: parent.horizontalCenter
            y: keyRow.y + 120 * wz.s + 22 * wz.s
            width: 860 * wz.s; height: term.waveBand
            activity: (bridge.wizardNarrationActive || bridge.voiceEngineWarming) ? "SPEAKING" : String(bridge.bridgeActivity || "IDLE")
            k: Math.max(0.5, 1.0 * wz.s)
            animate: wz.visible
        }
        // corner: leave setup
        Text {
            anchors.right: parent.right; anchors.rightMargin: 36 * wz.s; anchors.bottom: parent.bottom; anchors.bottomMargin: 22 * wz.s
            text: "CLOSE SETUP"; color: Theme.plateText; opacity: closeArea.containsMouse ? 1 : 0.55
            font.family: Theme.labelFont; font.weight: Font.DemiBold; font.pixelSize: 15 * wz.s; font.letterSpacing: 3 * wz.s
            PressArea { id: closeArea; anchors.fill: parent; anchors.margins: -10 * wz.s; onActivated: wz.closeWizard(false) }
        }
    }
    Timer { id: voiceTestDelay; interval: 700; onTriggered: bridge.requestCommand("voice_test") }
    Timer { id: keyFocus; interval: 120; onTriggered: if (wz.step === 10) keyInput.forceActiveFocus() }
    // a good key: the box empties (the key now lives only in the Bridge's settings)
    onVerifyChanged: if (verify === "VERIFIED") { keyInput.text = ""; showKey = false }

    // IDENTIFY: a big number on every screen for 3 s (same as Setup > Display)
    property bool identifying: false
    Timer { id: idTimer; interval: 3000; onTriggered: wz.identifying = false }
    function identify() { identifying = false; identifying = true; idTimer.restart() }
    Instantiator {
        model: wz.identifying ? Qt.application.screens.length : 0
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
                color: "#ee050b07"; border.color: idWin.here ? Theme.ok : Theme.phosphor; border.width: 5
                Text { anchors.horizontalCenter: parent.horizontalCenter; y: idWin.side * 0.07; text: "SCREEN"
                       color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: idWin.side * 0.12; font.letterSpacing: 6 }
                Text { anchors.centerIn: parent; anchors.verticalCenterOffset: 14; text: String(idWin.index + 1)
                       color: idWin.here ? Theme.ok : Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: idWin.side * 0.62 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: idWin.side * 0.06
                       text: idWin.here ? "BRIDGE IS HERE" : ""; color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: idWin.side * 0.09; font.letterSpacing: 3 }
            }
        }
    }

    onVisibleChanged: {
        if (visible) {
            lockStart()
            app.currentPage = 0
            nameInput.text = String(bridge.setupCommanderAddress || "")
            if (step === 0) nameInput.forceActiveFocus()
            if (step === 10) keyFocus.restart()
        } else bridge.cancelAnyCapture()
    }
}
