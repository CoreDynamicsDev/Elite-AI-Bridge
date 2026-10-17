// SETUP > STATUS (page 8). Start here: is everything working, and where to fix what isn't.
// Plain layout on purpose (setup-plan.md): title, one sentence, controls. No animation.
import QtQuick
import "../skin"

Item {
    id: st
    property var app
    signal denied(string title, string reason)
    signal notice(string title, string detail, string level)

    readonly property Item checkTarget: checkPlate
    readonly property Item sideTarget: sideCol
    readonly property Item deckTarget: deck

    readonly property real s: Theme.s
    readonly property real g: Math.max(8, 14 * s)
    readonly property real deckH: height * 0.175
    readonly property real deckY: height - deckH
    readonly property real bodyH: deckY - g
    readonly property real leftW: width * 0.6

    // ---------- checklist: plain names, fixed order, and which tab fixes each one
    // page ids: 6 voice & ai, 7 sound, 9 display, 10 controls
    readonly property var plan: [
        { key: "ELITE GAME DATA", name: "ELITE IS RUNNING", tab: -1, hint: "START ELITE DANGEROUS AND LOAD INTO THE GAME" },
        { key: "PUSH-TO-TALK", name: "PUSH TO TALK", tab: 10, hint: "" },
        { key: "ELITE KEYBOARD CONTROLS", name: "ELITE KEYS THE BRIDGE NEEDS", tab: 10, hint: "" },
        { key: "MICROPHONE", name: "MICROPHONE", tab: 7, hint: "" },
        { key: "SPEAKERS / OUTPUT", name: "SPEAKERS", tab: 7, hint: "" },
        { key: "AI CO-PILOT / OPENAI", name: "AI CO-PILOT", tab: 6, hint: "" },
        { key: "BRIDGE SHORTCUTS", name: "BRIDGE SHORTCUT KEYS", tab: 10, hint: "" },
        { key: "DISPLAY", name: "SCREEN", tab: 9, hint: "" },
        { key: "MARKET DATA", name: "MARKET DATA", tab: -1, hint: "ARRIVES BY ITSELF WHEN YOU DOCK OR SEARCH" },
        { key: "BRIDGE CORE", name: "BRIDGE", tab: -1, hint: "" }
    ]
    readonly property var tabNames: ({ 6: "VOICE & AI", 7: "SOUND", 9: "DISPLAY", 10: "CONTROLS" })
    function kind(stat) {
        stat = String(stat || "").toUpperCase()
        if (stat === "READY") return "ok"
        if (stat === "OFF") return "off"
        if (stat === "MISSING" || stat === "NEEDS ATTENTION" || stat === "ERROR") return "bad"
        return "wait"
    }
    readonly property var rows: {
        var src = st.app ? st.app.startupPreflightRows() : []
        var byKey = {}
        for (var i = 0; i < src.length; i++) byKey[String(src[i].label).toUpperCase()] = src[i]
        var out = []
        for (var j = 0; j < plan.length; j++) {
            var r = byKey[plan[j].key]
            if (!r) continue
            var row = { name: plan[j].name, tab: plan[j].tab, hint: plan[j].hint, status: String(r.status), detail: String(r.detail || ""), kind: kind(r.status) }
            // push to talk only does something with the AI co-pilot, so without it it's optional, not red
            if (plan[j].key === "PUSH-TO-TALK" && String(bridge.bridgeMode) === "CORE" && row.kind !== "ok") {
                row.kind = "off"; row.status = "OFF"; row.detail = "ONLY NEEDED WITH THE AI CO-PILOT"; row.tab = -1
            }
            out.push(row)
        }
        return out
    }
    readonly property int nOk: { var n = 0; for (var i = 0; i < rows.length; i++) if (rows[i].kind === "ok") n++; return n }
    readonly property int nBad: { var n = 0; for (var i = 0; i < rows.length; i++) if (rows[i].kind === "bad") n++; return n }
    readonly property int nWait: { var n = 0; for (var i = 0; i < rows.length; i++) if (rows[i].kind === "wait") n++; return n }
    property string lastCheck: ""
    property bool checking: false
    Timer { id: checkDone; interval: 1400; onTriggered: { st.checking = false; st.lastCheck = Qt.formatTime(new Date(), "h:mm AP"); Theme.cue(st.nBad === 0 ? "confirm" : "warn") } }
    function runCheck() {
        if (checking) return
        checking = true
        bridge.requestCommand("setup_preflight")
        bridge.requestCommand("setup_binds")
        bridge.requestCommand("audio_rescan")
        checkDone.restart()
    }

    component Caption: Text {
        color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: Math.max(8, 13 * st.s); font.letterSpacing: 3 * st.s
    }
    component Blurb: Text {
        color: Theme.plateText; opacity: 0.85; font.family: Theme.labelFont; font.pixelSize: Math.max(10, 16 * st.s); wrapMode: Text.WordWrap; lineHeight: 1.1
    }

    // ================================================================= CHECKLIST
    Plate {
        id: checkPlate
        x: 0; y: 0; width: st.leftW; height: st.bodyH
        screwSize: 13 * st.s
        Dymo { id: cDymo; x: 26 * st.s; y: 14 * st.s; text: "IS EVERYTHING WORKING?" }
        Blurb {
            x: 26 * st.s; y: 56 * st.s; width: parent.width - 52 * st.s
            text: "Green is ready. Amber can wait or is optional. Red needs fixing: its FIX button takes you to the tab that fixes it."
        }
        Bezel {
            id: cBezel
            x: 16 * st.s; y: 100 * st.s
            width: parent.width - 32 * st.s; height: parent.height - 116 * st.s
            pad: 12 * st.s
            readonly property real iw: width - pad * 2
            readonly property real ih: height - pad * 2
            readonly property real fs: Math.max(12, Math.min(24 * st.s, ih / 26))
            Text {
                x: 16 * st.s; y: 10 * st.s
                text: st.checking ? "CHECKING..." : (st.nBad === 0 ? "ALL GOOD" : st.nBad + " NEED" + (st.nBad === 1 ? "S" : "") + " FIXING")
                color: st.checking ? Theme.info : (st.nBad === 0 ? Theme.ok : Theme.bad)
                font.family: Theme.crtFont; font.pixelSize: cBezel.fs * 1.35
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 16 * st.s; y: 16 * st.s
                text: st.nOk + " READY // " + st.nWait + " WAITING // " + st.nBad + " TO FIX" + (st.lastCheck !== "" ? " // CHECKED " + st.lastCheck : "")
                color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: cBezel.fs * 0.8
            }
            Column {
                id: rowsCol
                x: 16 * st.s; y: cBezel.fs * 2.4
                width: cBezel.iw - 32 * st.s
                readonly property real rh: Math.min(cBezel.fs * 2.7, (cBezel.ih - y - 8 * st.s) / Math.max(1, st.rows.length))
                Repeater {
                    model: st.rows
                    Item {
                        width: rowsCol.width; height: rowsCol.rh
                        readonly property color c: modelData.kind === "ok" ? Theme.ok : (modelData.kind === "bad" ? Theme.bad : (modelData.kind === "off" ? Theme.dimText : Theme.info))
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#1d3a26" }
                        Rectangle {
                            x: 2 * st.s; y: parent.height * 0.12 + cBezel.fs * 0.25
                            width: cBezel.fs * 0.55; height: width; radius: width / 2; color: parent.c
                            opacity: modelData.kind === "off" ? 0.4 : 0.95
                        }
                        Text {
                            x: cBezel.fs * 1.3; y: parent.height * 0.12
                            width: parent.width * 0.42; elide: Text.ElideRight
                            text: modelData.name; color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: cBezel.fs
                        }
                        Text {
                            x: parent.width * 0.45; y: parent.height * 0.12
                            text: modelData.kind === "off" ? "NOT USED" : String(modelData.status).toUpperCase()
                            color: parent.c; font.family: Theme.crtFont; font.pixelSize: cBezel.fs
                        }
                        Text {
                            x: cBezel.fs * 1.3; y: parent.height * 0.12 + cBezel.fs * 1.05
                            width: parent.width - x - (fixKey.visible ? fixKey.width + 16 * st.s : 0); elide: Text.ElideRight
                            text: (modelData.kind !== "ok" && modelData.hint !== "") ? modelData.hint : String(modelData.detail).toUpperCase()
                            color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: cBezel.fs * 0.72
                        }
                        LitButton {
                            id: fixKey
                            visible: (modelData.kind === "bad" || modelData.kind === "wait") && modelData.tab >= 0
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            width: 290 * st.s; height: Math.min(parent.height * 0.85, 58 * st.s)
                            centered: true
                            title: "FIX ON " + st.tabNames[modelData.tab]
                            onActivated: if (st.app) st.app.currentPage = modelData.tab
                        }
                    }
                }
            }
        }
    }

    // ================================================================= RIGHT COLUMN
    Column {
        id: sideCol
        x: st.leftW + st.g; y: 0
        width: st.width - x
        spacing: st.g
        readonly property real h1: st.bodyH * 0.2
        readonly property real h2: st.bodyH * 0.17
        readonly property real hU: st.bodyH * 0.33
        readonly property real h3: st.bodyH - h1 - h2 - hU - spacing * 3

        // ---- name
        Plate {
            width: parent.width; height: sideCol.h1
            screwSize: 13 * st.s
            Dymo { x: 26 * st.s; y: 14 * st.s; text: "WHAT THE BRIDGE CALLS YOU" }
            Blurb { x: 26 * st.s; y: 56 * st.s; width: parent.width - 52 * st.s
                    text: "The ship's voice uses this when it talks to you, like \"Docking granted, " + (nameInput.text.trim() !== "" ? nameInput.text.trim() : "Commander") + ".\"" }
            Rectangle {
                id: nameBox
                x: 26 * st.s; y: parent.height - height - 22 * st.s
                width: parent.width - 52 * st.s - saveName.width - 14 * st.s; height: 54 * st.s
                radius: 6 * st.s; color: "#06140b"; border.color: nameInput.activeFocus ? Theme.ok : "#2e4a36"; border.width: 1
                TextInput {
                    id: nameInput
                    anchors.fill: parent; anchors.margins: 12 * st.s
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: Math.max(14, 26 * st.s)
                    selectByMouse: true; maximumLength: 40
                    property string saved: String(bridge.setupCommanderAddress || "")
                    onSavedChanged: if (!activeFocus) text = saved
                    Component.onCompleted: text = saved
                    Keys.onReturnPressed: saveName.save()
                }
            }
            LitButton {
                id: saveName
                anchors.right: parent.right; anchors.rightMargin: 26 * st.s; y: nameBox.y
                width: 150 * st.s; height: nameBox.height
                centered: true; title: "SAVE"
                function save() {
                    bridge.setSetupValue("commander_address", nameInput.text.trim())
                    nameInput.focus = false
                    st.notice("NAME SAVED", "THE BRIDGE WILL CALL YOU " + (nameInput.text.trim() !== "" ? nameInput.text.trim().toUpperCase() : "COMMANDER"), "ok")
                }
                onActivated: save()
            }
        }

        // ---- first-time help
        Plate {
            width: parent.width; height: sideCol.h2
            screwSize: 13 * st.s
            Dymo { x: 26 * st.s; y: 14 * st.s; text: "NEW TO THE BRIDGE?" }
            Blurb { x: 26 * st.s; y: 56 * st.s; width: parent.width - 52 * st.s
                    text: "The setup wizard sets up Elite, your voice and your keys. The tutorial tours every page." }
            Item {
                x: 26 * st.s; y: parent.height - height - 20 * st.s
                width: parent.width - 52 * st.s; height: 50 * st.s
                Text {
                    anchors.verticalCenter: parent.verticalCenter; width: parent.width - wizRocker.width - 14 * st.s; wrapMode: Text.WordWrap
                    text: "SHOW THE SETUP WIZARD WHEN THE BRIDGE STARTS"
                    color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: Math.max(9, 14 * st.s); font.letterSpacing: 2 * st.s
                }
                OnOffPair {
                    id: wizRocker
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    buttonWidth: 76 * st.s; buttonHeight: 46 * st.s
                    on: bridge.firstRunSetupEnabled
                    onChanged: (v) => { if (st.app) st.app.introSessionDismissed = true; bridge.setFirstRunSetupEnabled(v) }
                }
            }
        }

        // ---- 2.0.1: version and update notice. The Bridge only asks GitHub which release is
        // newest; DOWNLOAD opens the release page in the browser. Nothing installs by itself.
        Plate {
            id: updPlate
            width: parent.width; height: sideCol.hU
            screwSize: 13 * st.s
            readonly property bool avail: bridge.updateAvailable
            readonly property real fs: Math.max(11, Math.min(20 * st.s, height / 13))
            Dymo { id: verTape; x: 26 * st.s; y: 14 * st.s; text: "BRIDGE VERSION // " + bridge.appVersion }
            Lamp { visible: updPlate.avail; lit: "a"; breathe: true; width: 20 * st.s; height: width
                   x: verTape.x + verTape.width + 14 * st.s; y: verTape.y + (verTape.height - height) / 2 }
            Item {
                anchors.right: parent.right; anchors.rightMargin: 26 * st.s; y: 8 * st.s
                width: updRocker.width + updLabel.width + 12 * st.s; height: 46 * st.s
                Text {
                    id: updLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: "CHECK DAILY"
                    color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: Math.max(9, 14 * st.s); font.letterSpacing: 2 * st.s
                }
                OnOffPair {
                    id: updRocker
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    buttonWidth: 66 * st.s; buttonHeight: 40 * st.s
                    on: bridge.updateCheckEnabled
                    onChanged: (v) => bridge.setUpdateCheckEnabled(v)
                }
            }
            Bezel {
                id: updBezel
                x: 16 * st.s; y: 66 * st.s
                width: parent.width - 32 * st.s; height: parent.height - y - updKeys.height - 26 * st.s
                pad: 10 * st.s
                Text {
                    id: updHead
                    x: 14 * st.s; y: 8 * st.s; width: updBezel.width - 2 * updBezel.pad - 28 * st.s; elide: Text.ElideRight
                    text: updPlate.avail ? "UPDATE AVAILABLE // " + bridge.updateLatestVersion : String(bridge.updateStatusText)
                    color: updPlate.avail ? Theme.info : (bridge.updateCheckEnabled ? Theme.ok : Theme.dimText)
                    font.family: Theme.crtFont; font.pixelSize: updPlate.fs * 1.15
                }
                Flickable {
                    id: notesFlick
                    x: 14 * st.s; y: updHead.y + updHead.height + 6 * st.s
                    width: updHead.width; height: updBezel.height - 2 * updBezel.pad - y - 6 * st.s
                    clip: true; contentHeight: notesText.height; boundsBehavior: Flickable.StopAtBounds
                    Text {
                        id: notesText
                        width: notesFlick.width; wrapMode: Text.WordWrap; textFormat: Text.PlainText
                        text: updPlate.avail
                              ? (bridge.updateNotes !== "" ? "WHAT'S NEW\n" + String(bridge.updateNotes) : "WHAT'S NEW IS ON THE RELEASE PAGE.")
                              : "ONCE A DAY THE BRIDGE ASKS GITHUB IF THERE IS A NEWER VERSION. IT NEVER DOWNLOADS OR INSTALLS ANYTHING BY ITSELF."
                        color: updPlate.avail ? Theme.phosphor : Theme.dimText
                        font.family: Theme.crtFont; font.pixelSize: updPlate.fs * 0.8
                    }
                }
            }
            Row {
                id: updKeys
                x: 26 * st.s; y: parent.height - height - 14 * st.s
                spacing: 14 * st.s
                height: 44 * st.s
                LitButton {
                    visible: updPlate.avail
                    width: 230 * st.s; height: parent.height; centered: true
                    title: "DOWNLOAD " + bridge.updateLatestVersion
                    onActivated: { bridge.openUpdatePage(); st.notice("OPENING THE RELEASE PAGE", "DOWNLOAD THE INSTALLER AND RUN IT // YOUR SETTINGS ARE KEPT", "info") }
                }
                LitButton {
                    width: 200 * st.s; height: parent.height; centered: true
                    title: "CHECK NOW"
                    onActivated: bridge.checkForUpdatesNow()
                }
            }
        }

        // ---- AI usage
        Plate {
            width: parent.width; height: sideCol.h3
            screwSize: 13 * st.s
            Dymo { id: uDymo; x: 26 * st.s; y: 14 * st.s; text: "AI USAGE // ALL TIME" }
            LitButton {
                anchors.right: parent.right; anchors.rightMargin: 26 * st.s; y: 10 * st.s
                width: 210 * st.s; height: 40 * st.s; centered: true
                title: "RESET COUNTERS"
                onActivated: { bridge.requestCommand("ai_usage_reset"); st.notice("COUNTERS RESET", "YOUR API KEY AND SETTINGS ARE UNCHANGED", "ok") }
            }
            Blurb { x: 26 * st.s; y: 60 * st.s; width: parent.width - 52 * st.s
                    text: "An estimate from the Bridge's own count. Your OpenAI account shows the real bill." }
            Bezel {
                id: uBezel
                x: 16 * st.s; y: 100 * st.s
                width: parent.width - 32 * st.s; height: parent.height - 126 * st.s
                pad: 10 * st.s
                readonly property real fs: Math.max(11, Math.min(22 * st.s, (height - 2 * pad) / 2.4))
                Grid {
                    x: 14 * st.s; anchors.verticalCenter: parent.verticalCenter
                    columns: 4; columnSpacing: 16 * st.s; rowSpacing: uBezel.fs * 0.35
                    readonly property real cw: (uBezel.width - uBezel.pad * 2 - 28 * st.s - columnSpacing * 3) / 4
                    Repeater {
                        model: [
                            { label: "ESTIMATED COST", value: String(bridge.aiUsageEstimatedCostText || "-") },
                            { label: "AI REQUESTS", value: Number(bridge.aiUsageCalls || 0).toLocaleString(Qt.locale("en_US"), "f", 0) },
                            { label: "TOKENS IN / OUT", value: Number(bridge.aiUsageInputTokens || 0).toLocaleString(Qt.locale("en_US"), "f", 0) + " / " + Number(bridge.aiUsageOutputTokens || 0).toLocaleString(Qt.locale("en_US"), "f", 0) },
                            { label: "VOICE HEARD", value: String(bridge.aiUsageTranscriptionSecondsText || "-") }
                        ]
                        Column {
                            width: parent.cw
                            Text { text: modelData.label; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: uBezel.fs * 0.75 }
                            Text { width: parent.width; elide: Text.ElideRight; text: modelData.value; color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: uBezel.fs * 1.15 }
                        }
                    }
                }
            }
        }
    }

    // ================================================================= ACTION DECK
    component Groove: Item {
        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 4 * st.s; height: parent.height; radius: 2 * st.s; color: "#0b0b0a"; border.color: "#3e3b32"; border.width: 1 }
    }
    Plate {
        id: deck
        dark: true
        screwSize: 13 * st.s
        x: 0; y: st.deckY; width: st.width; height: st.deckH
        readonly property real keyH: Math.min(height - 66 * st.s, 150 * st.s)
        readonly property real keyY: 52 * st.s + (height - 66 * st.s - keyH) / 2
        readonly property real cancelW: 270 * st.s
        readonly property real divW: 40 * st.s
        readonly property real keyGap: 14 * st.s
        readonly property real keyW: (width - 26 * st.s - cancelW - 40 * st.s - 44 * st.s - divW * 2 - keyGap * 8) / 7
        Dymo { x: 26 * st.s; y: 14 * st.s; text: "ACTIONS // STATUS" }
        Row {
            id: dRow
            x: 26 * st.s; y: deck.keyY
            spacing: deck.keyGap
            DeckKey {
                id: checkKey
                width: deck.keyW; height: deck.keyH
                title: "RUN CHECK"; legend: st.checking ? "CHECKING..." : "LOOK AGAIN NOW"
                keyState: st.checking ? "running" : "ready"
                tooltip: "CHECK EVERYTHING AGAIN"; tooltipDetail: "ELITE, KEYS, PUSH TO TALK, SOUND, AI"
                onActivated: st.runCheck()
            }
            Groove { width: deck.divW; height: deck.keyH }
            DeckKey {
                id: wizKey
                width: deck.keyW; height: deck.keyH
                title: "SETUP WIZARD"; legend: "STEP BY STEP"
                tooltip: "OPEN THE SETUP WIZARD"; tooltipDetail: "ELITE, VOICE AND KEYS, ONE STEP AT A TIME"
                onActivated: if (st.app) st.app.openFullSetupWizard()
            }
            DeckKey {
                id: tourKey
                width: deck.keyW; height: deck.keyH
                title: "TUTORIAL"; legend: "TOUR EVERY PAGE"
                tooltip: "START THE GUIDED TOUR"; tooltipDetail: "NEVER STARTS BY ITSELF"
                onActivated: if (st.app) { st.app.launchLiveOrientation(true); Theme.cue("confirm") }
            }
            Groove { width: deck.divW; height: deck.keyH }
            DeckKey {
                id: helpKey
                width: deck.keyW * 1.25; height: deck.keyH
                title: "MAKE SUPPORT FILE"; legend: "STEP 1 // ONE ZIP"
                tooltip: "ONE ZIP TO ATTACH WHEN YOU ASK FOR HELP"; tooltipDetail: "OPENS ITS FOLDER // YOUR API KEY IS NEVER INCLUDED"
                onActivated: { bridge.requestCommand("save_data"); st.notice("MAKING SUPPORT FILE", "THE FOLDER OPENS WHEN IT'S READY // THEN SEND IT ON GITHUB OR BY EMAIL", "info") }
            }
            DeckKey {
                id: ghKey
                readonly property string url: "https://github.com/CoreDynamicsDev/Elite-AI-Bridge-Download/issues/new"
                width: deck.keyW; height: deck.keyH
                title: "REPORT ON GITHUB"; legend: "STEP 2 // ATTACH THE ZIP"
                tooltip: "OPENS THE BUG REPORT PAGE IN YOUR BROWSER"; tooltipDetail: "NEEDS A FREE GITHUB ACCOUNT // DRAG THE SUPPORT ZIP IN"
                onActivated: { Qt.openUrlExternally(url); st.notice("OPENING GITHUB", "SAY WHAT YOU WERE DOING AND DRAG THE SUPPORT ZIP IN", "info") }
            }
            DeckKey {
                id: mailKey
                readonly property string email: "coredynamicsdev@gmail.com"
                width: deck.keyW; height: deck.keyH
                title: "EMAIL IT"; legend: "NO GITHUB? USE EMAIL"
                tooltip: "OPENS YOUR EMAIL APP"; tooltipDetail: "TO " + email.toUpperCase() + " // ATTACH THE SUPPORT ZIP"
                onActivated: { Qt.openUrlExternally("mailto:" + email + "?subject=" + encodeURIComponent("Elite AI Bridge bug report")); st.notice("OPENING EMAIL", "TO " + email.toUpperCase() + " // ATTACH THE SUPPORT ZIP", "info") }
            }
        }
        Caption { x: dRow.x + wizKey.x + (tourKey.x + tourKey.width - wizKey.x) / 2 - width / 2; y: deck.keyY - height - 6 * st.s; text: "GUIDES" }
        Caption { x: dRow.x + helpKey.x + (mailKey.x + mailKey.width - helpKey.x) / 2 - width / 2; y: deck.keyY - height - 6 * st.s; text: "FOUND A BUG? REPORT IT" }
        Item {
            x: deck.width - deck.cancelW - 40 * st.s; y: deck.keyY; width: deck.cancelW; height: deck.keyH
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
