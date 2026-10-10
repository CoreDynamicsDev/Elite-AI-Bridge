// SETUP > AUTOMATION (page 11). Everything the Bridge does on its own, without you asking.
// Plain layout on purpose (setup-plan.md): title, one sentence, then one row per setting.
import QtQuick
import "../skin"

Item {
    id: au
    property var app
    signal denied(string title, string reason)
    signal notice(string title, string detail, string level)

    readonly property Item dockTarget: dockPlate
    readonly property Item combatTarget: combatPlate
    readonly property Item aiTarget: aiPlate
    readonly property Item deckTarget: deck

    readonly property real s: Theme.s
    readonly property real g: Math.max(8, 14 * s)
    readonly property real deckH: height * 0.175
    readonly property real deckY: height - deckH
    readonly property real bodyH: deckY - g
    readonly property real colW: (width - g) / 2
    readonly property real rowH: Math.max(56 * s, Math.min(84 * s, bodyH / 12.5))

    component Blurb: Text {
        color: Theme.plateText; opacity: 0.85; font.family: Theme.labelFont; font.pixelSize: Math.max(10, 16 * au.s); wrapMode: Text.WordWrap; lineHeight: 1.1
    }
    // one setting: name, one plain line, ON / OFF rocker on the right
    component SettingRow: Item {
        id: sr
        property string name: ""
        property string line: ""
        property bool on: false
        property bool enabled2: true
        property bool child: false            // sits under the master switch: indented, with a feed line
        signal flipped(bool v)
        width: parent ? parent.width : 0; height: au.rowH
        opacity: enabled2 ? 1 : 0.45
        readonly property real ind: child ? 44 * au.s : 0
        Rectangle { anchors.bottom: parent.bottom; x: sr.ind; width: parent.width - sr.ind; height: 1; color: "#3a3730"; opacity: 0.7 }
        // feed line from the master switch: vertical bus + a short tap into this row
        Rectangle { visible: sr.child; x: 16 * au.s; y: 0; width: 3 * au.s; height: parent.height; color: sr.enabled2 ? Theme.ok : "#4a473e"; opacity: sr.enabled2 ? 0.55 : 1 }
        Rectangle { visible: sr.child; x: 16 * au.s; anchors.verticalCenter: parent.verticalCenter; width: 18 * au.s; height: 3 * au.s; color: sr.enabled2 ? Theme.ok : "#4a473e"; opacity: sr.enabled2 ? 0.55 : 1 }
        Column {
            x: sr.ind
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - rk.width - 20 * au.s - sr.ind
            spacing: 3 * au.s
            Text { text: sr.name; color: Theme.plateText; font.family: Theme.labelFont; font.weight: Font.DemiBold; font.pixelSize: Math.max(11, 19 * au.s); font.letterSpacing: 2 * au.s }
            Text { visible: sr.height >= 40; width: parent.width; wrapMode: Text.WordWrap; text: sr.line; color: Theme.plateText; opacity: 0.7; font.family: Theme.labelFont; font.pixelSize: Math.max(9, 14 * au.s) }
        }
        OnOffPair {
            id: rk
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            buttonWidth: 76 * au.s; buttonHeight: 46 * au.s
            on: sr.on
            available: sr.enabled2
            unavailableReason: "TURN ON AUTOMATIC AI ASSISTANCE FIRST"
            onChanged: (v) => sr.flipped(v)
            onDenied: (r) => au.denied("NOT AVAILABLE", r)
        }
    }
    // the master switch: its own recessed panel, a lamp, a bigger rocker; the rows under it hang off it
    component MasterRow: Item {
        id: mr
        property string name: ""
        property string line: ""
        property bool on: false
        signal flipped(bool v)
        width: parent ? parent.width : 0; height: au.rowH * 1.3
        Rectangle {
            anchors.fill: parent; anchors.topMargin: 4 * au.s; anchors.bottomMargin: 6 * au.s
            radius: 8 * au.s; color: "#141410"; border.color: mr.on ? Theme.ok : "#55513f"; border.width: Math.max(1, 2 * au.s)
            Rectangle { anchors.fill: parent; anchors.margins: 3 * au.s; radius: 6 * au.s; color: "transparent"; border.color: "#000000"; border.width: 1; opacity: 0.6 }
        }
        Lamp { id: ml; x: 18 * au.s; anchors.verticalCenter: parent.verticalCenter; width: 26 * au.s; height: width; lit: mr.on ? "g" : "" }
        Column {
            x: ml.x + ml.width + 16 * au.s
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - mrk.width - 32 * au.s
            spacing: 3 * au.s
            Text { text: "MASTER // " + mr.name; color: mr.on ? Theme.ok : Theme.plateText; font.family: Theme.labelFont; font.weight: Font.Bold; font.pixelSize: Math.max(12, 21 * au.s); font.letterSpacing: 2.5 * au.s }
            Text { visible: mr.height >= 46; width: parent.width; wrapMode: Text.WordWrap; text: mr.line; color: Theme.plateText; opacity: 0.75; font.family: Theme.labelFont; font.pixelSize: Math.max(9, 14 * au.s) }
        }
        OnOffPair {
            id: mrk
            anchors.right: parent.right; anchors.rightMargin: 14 * au.s; anchors.verticalCenter: parent.verticalCenter
            buttonWidth: 92 * au.s; buttonHeight: 56 * au.s
            on: mr.on
            onChanged: (v) => mr.flipped(v)
        }
    }
    component Section: Plate {
        id: sec
        property string title: ""
        property string blurb: ""
        default property alias rows: holder.data
        screwSize: 13 * au.s
        Dymo { x: 26 * au.s; y: 14 * au.s; text: sec.title }
        Blurb { id: sb; x: 26 * au.s; y: 56 * au.s; width: sec.width - 52 * au.s; text: sec.blurb }
        Column { id: holder; x: 26 * au.s; y: sb.y + sb.height + 4 * au.s; width: sec.width - 52 * au.s }
    }

    // ================================================================= LEFT: docking + launch
    Section {
        id: dockPlate
        x: 0; y: 0; width: au.colW; height: au.bodyH * 0.52
        title: "AFTER YOU DOCK"
        blurb: "Station services the Bridge buys for you as soon as you land, when the station has them."
        SettingRow { name: "AUTO REFUEL"; line: "Fills the tank."; on: bridge.setupAutoRefuel; onFlipped: (v) => bridge.setSetupBool("auto_refuel", v) }
        SettingRow { name: "AUTO REPAIR"; line: "Repairs the hull and modules."; on: bridge.setupAutoRepair; onFlipped: (v) => bridge.setSetupBool("auto_repair", v) }
        SettingRow { name: "AUTO REARM"; line: "Refills ammo and limpets the station sells."; on: bridge.setupAutoRearm; onFlipped: (v) => bridge.setSetupBool("auto_rearm", v) }
    }
    Section {
        id: launchPlate
        x: 0; y: dockPlate.height + au.g; width: au.colW; height: au.bodyH - y
        title: "AFTER YOU LAUNCH // THIS SESSION ONLY"
        blurb: "Turns itself off when you close the Bridge."
        SettingRow {
            name: "CLEAR + JUMP AFTER LAUNCH"
            line: "When Auto Launch has cleared the station, the Bridge carries on and jumps to your plotted route."
            on: bridge.aiLaunchRuleEnabled
            onFlipped: (v) => { if (v !== bridge.aiLaunchRuleEnabled) bridge.requestCommand("ai_toggle_launch_rule") }
        }
    }

    // ================================================================= RIGHT: combat + AI
    Section {
        id: combatPlate
        x: au.colW + au.g; y: 0; width: au.colW; height: au.bodyH * 0.52
        title: "IN COMBAT"
        blurb: "Help the Bridge gives you in a fight. The same switches are on the Combat page."
        SettingRow { name: "DYNAMIC PIPS"; line: "Moves power between systems, engines and weapons to suit the fight, then puts it back."; on: bridge.setupDynamicPips; onFlipped: (v) => bridge.setSetupBool("dynamic_pips", v) }
        SettingRow { name: "AUTO POWER PLANT"; line: "Targets the power plant on big wanted ships once they're scanned."; on: bridge.setupAutoPowerPlant; onFlipped: (v) => bridge.setSetupBool("auto_powerplant", v) }
        SettingRow { name: "AUTO CHAFF"; line: "Fires chaff when you're taking steady fire."; on: bridge.setupAutoChaff; onFlipped: (v) => bridge.setSetupBool("auto_chaff", v) }
        Item {
            width: parent.width; height: au.rowH
            opacity: bridge.setupAutoChaff ? 1 : 0.45
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - chaffSel.width - 20 * au.s
                spacing: 3 * au.s
                Text { text: "HOW EASILY CHAFF FIRES"; color: Theme.plateText; font.family: Theme.labelFont; font.weight: Font.DemiBold; font.pixelSize: Math.max(11, 19 * au.s); font.letterSpacing: 2 * au.s }
                Text { width: parent.width; wrapMode: Text.WordWrap; text: "Low saves chaff, high fires sooner. Medium suits most fights."
                       color: Theme.plateText; opacity: 0.7; font.family: Theme.labelFont; font.pixelSize: Math.max(9, 14 * au.s) }
            }
            SelectorRow {
                id: chaffSel
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                options: ["LOW", "MEDIUM", "HIGH"]
                buttonWidth: 98 * au.s; buttonHeight: 46 * au.s
                currentIndex: ["LOW", "MED", "HIGH"].indexOf(String(bridge.setupAutoChaffProfile || "MED"))
                onPicked: (i) => bridge.setSetupValue("auto_chaff_profile", ["LOW", "MED", "HIGH"][i])
            }
        }
    }
    Section {
        id: aiPlate
        x: au.colW + au.g; y: combatPlate.height + au.g; width: au.colW; height: au.bodyH - y
        title: "AI SPEAKS UP ON ITS OWN"
        blurb: "Lets the AI comment or give advice when something happens, without you asking. It never flies the ship."
        // rows share what's left under the blurb, so the four fit in small windows too
        readonly property real avail: height - 100 * au.s - 12
        readonly property real masterH: Math.min(au.rowH * 1.3, avail * 0.31)
        readonly property real childH: Math.min(au.rowH, (avail - masterH) / 3)
        MasterRow { height: aiPlate.masterH; name: "AUTOMATIC AI ASSISTANCE"; line: "Turns everything below on or off. Off = the AI only answers when you talk to it."; on: bridge.aiSmartAutoEnabled; onFlipped: (v) => bridge.setSetupBool("ai_smart_auto", v) }
        SettingRow { child: true; height: aiPlate.childH; name: "TRADE + POWERPLAY"; line: "Buying, selling and powerplay events."; on: bridge.setupAiTradeAuto; enabled2: bridge.aiSmartAutoEnabled; onFlipped: (v) => bridge.setSetupBool("ai_trade_auto", v) }
        SettingRow { child: true; height: aiPlate.childH; name: "MISSIONS"; line: "Taking, finishing and failing missions."; on: bridge.setupAiMissionAuto; enabled2: bridge.aiSmartAutoEnabled; onFlipped: (v) => bridge.setSetupBool("ai_mission_auto", v) }
        SettingRow { child: true; height: aiPlate.childH; name: "TRAVEL + DOCKING"; line: "Jumps, arrivals and docking."; on: bridge.setupAiTravelAuto; enabled2: bridge.aiSmartAutoEnabled; onFlipped: (v) => bridge.setSetupBool("ai_travel_auto", v) }
    }

    // ================================================================= DECK (CANCEL only)
    Plate {
        id: deck
        dark: true
        screwSize: 13 * au.s
        x: 0; y: au.deckY; width: au.width; height: au.deckH
        readonly property real keyH: Math.min(height - 66 * au.s, 150 * au.s)
        readonly property real keyY: 52 * au.s + (height - 66 * au.s - keyH) / 2
        readonly property real cancelW: 270 * au.s
        Dymo { x: 26 * au.s; y: 14 * au.s; text: "ACTIONS // AUTOMATION" }
        Text {
            x: 26 * au.s; y: deck.keyY; width: deck.width - deck.cancelW - 120 * au.s; height: deck.keyH
            verticalAlignment: Text.AlignVCenter; wrapMode: Text.WordWrap
            text: "Changes save straight away. CANCEL stops anything the Bridge is doing right now."
            color: Theme.plateText; opacity: 0.8; font.family: Theme.labelFont; font.pixelSize: Math.max(10, 17 * au.s)
        }
        Item {
            x: deck.width - deck.cancelW - 40 * au.s; y: deck.keyY; width: deck.cancelW; height: deck.keyH
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
