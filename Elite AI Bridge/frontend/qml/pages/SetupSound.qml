// SETUP > SOUND (page 7). Where sound plays, what the Bridge listens on, levels, and the alert sounds.
// Plain layout on purpose (setup-plan.md). Every control shows its new value the moment it's touched.
import QtQuick
import "../skin"

Item {
    id: so
    property var app
    signal denied(string title, string reason)
    signal notice(string title, string detail, string level)

    readonly property Item devicesTarget: devPlate
    readonly property Item levelsTarget: levelPlate
    readonly property Item sfxTarget: sfxPlate
    readonly property Item deckTarget: deck

    readonly property real s: Theme.s
    readonly property real g: Math.max(8, 14 * s)
    readonly property real deckH: height * 0.175
    readonly property real deckY: height - deckH
    readonly property real bodyH: deckY - g
    readonly property real leftW: (width - g) * 0.48

    component Blurb: Text {
        color: Theme.plateText; opacity: 0.85; font.family: Theme.labelFont; font.pixelSize: Math.max(10, 16 * so.s); wrapMode: Text.WordWrap; lineHeight: 1.1
    }
    component Label2: Text {
        color: Theme.plateText; font.family: Theme.labelFont; font.weight: Font.DemiBold; font.pixelSize: Math.max(11, 18 * so.s); font.letterSpacing: 2 * so.s
    }

    // ---------- lists only swap when their content changes (the bridge resends every 250 ms)
    readonly property var liveOut: bridge.audioOutputDevices || []
    readonly property var liveIn: bridge.audioInputDevices || []
    readonly property var liveSfx: bridge.audioSfxRows || []
    property var outRows: []
    property var inRows: []
    property var sfxRows: []
    property string outKey: ""
    property string inKey: ""
    property string sfxKey: ""
    onLiveOutChanged: { var k = JSON.stringify(liveOut); if (k !== outKey) { outKey = k; outRows = liveOut } }
    onLiveInChanged: { var k = JSON.stringify(liveIn); if (k !== inKey) { inKey = k; inRows = liveIn } }
    onLiveSfxChanged: { var k = JSON.stringify(liveSfx); if (k !== sfxKey) { sfxKey = k; sfxRows = liveSfx } }

    // picked sound (shown at once, told to the backend in the background)
    property string pickedKey: ""
    readonly property string pickKey: pickedKey !== "" ? pickedKey : String(bridge.audioSfxSelectedKey || "")
    readonly property var picked: { for (var i = 0; i < sfxRows.length; i++) if (sfxRows[i].key === pickKey) return sfxRows[i]; return null }
    function pick(k) { pickedKey = k; bridge.selectSfxEvent(k) }

    // device choice shown at once
    property string pendOut: ""
    property string pendIn: ""
    Timer { id: devTimer; interval: 6000; onTriggered: { so.pendOut = ""; so.pendIn = "" } }
    readonly property string shownOut: pendOut !== "" ? pendOut : String(bridge.voiceOutputDevice || "System Default")
    readonly property string shownIn: pendIn !== "" ? pendIn : String(bridge.voiceInputDevice || "System Default")
    function isDefault(name) { var n = String(name || "").toLowerCase(); return n === "system default" || n === "windows default" || n === "default" }

    // one device list: Windows default first, the one in use marked
    component DeviceList: Bezel {
        id: dl
        property var rows: []
        property string shown: ""
        property string winDefault: ""
        signal choose(string name)
        pad: 10 * so.s
        readonly property real fs: Math.max(12, 21 * so.s)
        PhosphorList {
            id: dlist
            x: 12 * so.s; y: 8 * so.s
            width: dl.width - dl.pad * 2 - 24 * so.s; height: dl.height - dl.pad * 2 - 16 * so.s
            fontSize: dl.fs
            model: dl.rows
            delegate: Item {
                required property var modelData
                required property int index
                width: dlist.list.width - (dlist.overflow ? 0 : 26 * so.s)
                height: dlist.fontSize * 1.45
                readonly property bool inUse: String(modelData) === dl.shown || (so.isDefault(modelData) && so.isDefault(dl.shown))
                Rectangle { anchors.fill: parent; visible: parent.inUse || dPress.containsMouse
                            color: parent.inUse ? Theme.t("#2a7dff9c") : Theme.t("#127dff9c"); border.color: parent.inUse ? Theme.t("#807dff9c") : "transparent"; border.width: 1 }
                Text {
                    x: 6 * so.s; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 120 * so.s; elide: Text.ElideRight
                    text: (parent.inUse ? "> " : "  ") + (so.isDefault(modelData) ? "WINDOWS DEFAULT" + (dl.winDefault !== "" ? " (" + dl.winDefault + ")" : "") : String(modelData)).toUpperCase()
                    color: parent.inUse ? Theme.ok : Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: dlist.fontSize
                }
                Text { visible: parent.inUse; anchors.right: parent.right; anchors.rightMargin: 8 * so.s; anchors.verticalCenter: parent.verticalCenter
                       text: "IN USE"; color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: dlist.fontSize * 0.8 }
                PressArea { id: dPress; anchors.fill: parent; onActivated: if (!parent.inUse) { Theme.cue("tick"); dl.choose(String(modelData)) } }
            }
        }
    }

    // ================================================================= WHERE SOUND GOES
    Plate {
        id: devPlate
        x: 0; y: 0; width: so.leftW; height: so.bodyH
        screwSize: 13 * so.s
        Dymo { x: 26 * so.s; y: 14 * so.s; text: "WHERE SOUND GOES" }
        Blurb { id: db; x: 26 * so.s; y: 56 * so.s; width: parent.width - 52 * so.s
                text: "Click a device to use it. Windows default follows whatever Windows is set to; pick a named device to keep the Bridge on it." }
        Label2 { id: outLbl; x: 26 * so.s; y: db.y + db.height + 14 * so.s; text: "SHIP VOICE AND SOUND EFFECTS PLAY ON" }
        DeviceList {
            id: outList
            x: 16 * so.s; y: outLbl.y + outLbl.height + 8 * so.s
            width: parent.width - 32 * so.s; height: (parent.height - y - 24 * so.s) / 2 - outLbl.height - 10 * so.s
            rows: so.outRows; shown: so.shownOut; winDefault: String(bridge.audioDefaultOutput || "")
            onChoose: (n) => { so.pendOut = n; devTimer.restart(); bridge.setAudioDevice("output", n) }
        }
        Label2 { id: inLbl; x: 26 * so.s; y: outList.y + outList.height + 16 * so.s; text: "THE BRIDGE LISTENS ON" + (String(bridge.bridgeMode) === "CORE" ? "  (USED BY AI CO-PILOT)" : "") }
        DeviceList {
            id: inList
            x: 16 * so.s; y: inLbl.y + inLbl.height + 8 * so.s
            width: parent.width - 32 * so.s; height: parent.height - y - 16 * so.s
            rows: so.inRows; shown: so.shownIn; winDefault: String(bridge.audioDefaultInput || "")
            onChoose: (n) => { so.pendIn = n; devTimer.restart(); bridge.setAudioDevice("input", n) }
        }
    }

    // ================================================================= LEVELS
    Plate {
        id: levelPlate
        x: so.leftW + so.g; y: 0; width: so.width - x; height: so.bodyH * 0.36
        screwSize: 13 * so.s
        Dymo { x: 26 * so.s; y: 14 * so.s; text: "LEVELS" }
        Blurb { id: lb; x: 26 * so.s; y: 56 * so.s; width: parent.width - 52 * so.s - masterBox.width - startBox.width - 30 * so.s
                text: "Drag to set; it saves when you let go." }
        // LAB: startup sound (boot splash). Saved in the frontend settings; takes effect next launch.
        Item {
            id: startBox
            anchors.right: masterBox.left; anchors.rightMargin: 30 * so.s; y: 46 * so.s
            width: startLbl.width + startRk.width + 16 * so.s; height: 46 * so.s
            Label2 { id: startLbl; anchors.verticalCenter: parent.verticalCenter; text: "STARTUP SOUND" }
            OnOffPair {
                id: startRk
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                buttonWidth: 70 * so.s; buttonHeight: 42 * so.s
                on: bridge.startupSoundEnabled
                onChanged: (v) => bridge.setStartupSoundEnabled(v)
            }
        }
        Item {
            id: masterBox
            anchors.right: parent.right; anchors.rightMargin: 26 * so.s; y: 46 * so.s
            width: masterLbl.width + masterRk.width + 16 * so.s; height: 46 * so.s
            Label2 { id: masterLbl; anchors.verticalCenter: parent.verticalCenter; text: "SOUND EFFECTS" }
            OnOffPair {
                id: masterRk
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                buttonWidth: 70 * so.s; buttonHeight: 42 * so.s
                on: bridge.voiceSfxEnabled
                onChanged: (v) => bridge.setSfxEventEnabled("master", v)
            }
        }
        Row {
            x: 26 * so.s; y: lb.y + lb.height + 14 * so.s
            width: parent.width - 52 * so.s; height: parent.height - y - 14 * so.s
            spacing: 30 * so.s
            SlideFader {
                id: voiceFader
                width: (parent.width - parent.spacing) / 2; height: Math.min(parent.height, 120 * so.s); vertical: false
                label: "SHIP VOICE"
                property real live: -1
                value: live >= 0 ? live : Number(bridge.voiceVolume || 0)
                onMoved: (v) => live = v
                onCommitted: (v) => { bridge.setAudioLevel("voice", Math.round(v)); vReset.restart() }
                Timer { id: vReset; interval: 1500; onTriggered: voiceFader.live = -1 }
            }
            SlideFader {
                id: sfxFader
                width: (parent.width - parent.spacing) / 2; height: Math.min(parent.height, 120 * so.s); vertical: false
                label: "SOUND EFFECTS"
                opacity: masterRk.shown ? 1 : 0.45
                property real live: -1
                value: live >= 0 ? live : Number(bridge.audioSfxVolume || 0)
                onMoved: (v) => live = v
                onCommitted: (v) => { bridge.setAudioLevel("sfx", Math.round(v)); sReset.restart() }
                Timer { id: sReset; interval: 1500; onTriggered: sfxFader.live = -1 }
            }
        }
    }

    // ================================================================= ALERT SOUNDS
    Plate {
        id: sfxPlate
        x: so.leftW + so.g; y: levelPlate.height + so.g; width: so.width - x; height: so.bodyH - y
        screwSize: 13 * so.s
        opacity: masterRk.shown ? 1 : 0.55
        Dymo { x: 26 * so.s; y: 14 * so.s; text: "ALERT SOUNDS" }
        Blurb { id: sb; x: 26 * so.s; y: 56 * so.s; width: parent.width - 52 * so.s
                text: "Short sounds for things like docking and danger. Click one to pick it, PLAY SOUND below to hear it. Urgent alarms always cut in first." }
        Column {
            id: sfxCol
            x: 26 * so.s; y: sb.y + sb.height + 10 * so.s
            width: parent.width - 52 * so.s
            readonly property real rh: Math.min(56 * so.s, (sfxPlate.height - y - 16 * so.s) / Math.max(1, so.sfxRows.length))
            Repeater {
                model: so.sfxRows
                Item {
                    width: sfxCol.width; height: sfxCol.rh
                    readonly property bool isPicked: modelData.key === so.pickKey
                    Rectangle { anchors.fill: parent; anchors.rightMargin: rk.width + 12 * so.s; radius: 4 * so.s
                                color: parent.isPicked ? Theme.t("#3346ff82") : (rowPress.containsMouse ? Theme.t("#1846ff82") : "transparent")
                                border.color: parent.isPicked ? Theme.t("#8046ff82") : "transparent"; border.width: 1 }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#3a3730"; opacity: 0.6 }
                    Text {
                        x: 10 * so.s; anchors.verticalCenter: parent.verticalCenter; width: parent.width - rk.width - 30 * so.s; elide: Text.ElideRight
                        text: (parent.isPicked ? "> " : "") + String(modelData.label)
                        color: Theme.plateText; font.family: Theme.labelFont; font.weight: Font.DemiBold; font.pixelSize: Math.max(10, 17 * so.s); font.letterSpacing: 1.5 * so.s
                    }
                    PressArea { id: rowPress; anchors.fill: parent; anchors.rightMargin: rk.width + 12 * so.s
                                onActivated: { Theme.cue("tick"); so.pick(modelData.key) } }
                    OnOffPair {
                        id: rk
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        buttonWidth: 62 * so.s; buttonHeight: Math.min(40 * so.s, sfxCol.rh - 8 * so.s)
                        on: !!modelData.enabled
                        onChanged: (v) => bridge.setSfxEventEnabled(modelData.key, v)
                    }
                }
            }
        }
    }

    // ================================================================= ACTION DECK
    component Groove: Item {
        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 4 * so.s; height: parent.height; radius: 2 * so.s; color: "#0b0b0a"; border.color: "#3e3b32"; border.width: 1 }
    }
    component Caption: Text {
        color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: Math.max(8, 13 * so.s); font.letterSpacing: 3 * so.s
    }
    Plate {
        id: deck
        dark: true
        screwSize: 13 * so.s
        x: 0; y: so.deckY; width: so.width; height: so.deckH
        readonly property real keyH: Math.min(height - 66 * so.s, 150 * so.s)
        readonly property real keyY: 52 * so.s + (height - 66 * so.s - keyH) / 2
        readonly property real cancelW: 270 * so.s
        readonly property real divW: 40 * so.s
        readonly property real keyGap: 14 * so.s
        readonly property real keyW: (width - 26 * so.s - cancelW - 40 * so.s - 44 * so.s - divW * 2 - keyGap * 8) / 7
        Dymo { x: 26 * so.s; y: 14 * so.s; text: "ACTIONS // SOUND" }
        Row {
            id: dRow
            x: 26 * so.s; y: deck.keyY
            spacing: deck.keyGap
            DeckKey {
                id: playKey
                width: deck.keyW * 1.15; height: deck.keyH
                title: "PLAY SOUND"; legend: so.picked ? String(so.picked.label) : "PICK A SOUND"
                keyState: so.picked ? "ready" : "unavailable"
                unavailableReason: "PICK A SOUND IN THE LIST FIRST"
                tooltip: "HEAR THE PICKED SOUND"; tooltipDetail: "PLAYS EVEN IF IT'S SWITCHED OFF"
                onActivated: bridge.testSfxEvent(so.pickKey)
                onDenied: (r) => so.denied("NOTHING PICKED", r)
            }
            DeckKey {
                id: startKey
                width: deck.keyW * 1.15; height: deck.keyH
                title: "STARTUP SOUND"; legend: "HEAR IT"
                tooltip: "PLAY THE STARTUP SOUND"; tooltipDetail: "THE SOUND THAT PLAYS WITH THE OPENING ANIMATION"
                onActivated: bridge.testStartupSound()
            }
            Groove { width: deck.divW; height: deck.keyH }
            DeckKey {
                id: rescanKey
                width: deck.keyW * 1.15; height: deck.keyH
                title: "RESCAN DEVICES"; legend: "AFTER PLUGGING IN"
                tooltip: "LOOK FOR SPEAKERS AND MICROPHONES AGAIN"; tooltipDetail: "USE AFTER PLUGGING IN A HEADSET"
                onActivated: { bridge.requestCommand("audio_rescan"); so.notice("RESCANNING", "LOOKING FOR SOUND DEVICES", "info") }
            }
        }
        Item {
            x: deck.width - deck.cancelW - 40 * so.s; y: deck.keyY; width: deck.cancelW; height: deck.keyH
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
