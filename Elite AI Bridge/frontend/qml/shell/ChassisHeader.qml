// Header plate shared by every page: title, status lamps, MASTER CAUTION, status CRT,
// LED clock, TIP, HELP (guided tour) and EXIT. Reads the same bridge state as v1.0.1.
import QtQuick
import "../skin"

Item {
    id: hdr
    property var app                        // the main window (scaleUnit, tour state, helpers)
    property string notice: ""              // short-lived message (denied key reasons)
    property string noticeDetail: ""
    property string noticeLevel: "info"
    signal masterCautionPressed()
    signal updatePressed()

    readonly property real s: Theme.s
    readonly property bool tourActive: app.firstOrientationActive || bridge.pageHelpActive

    // ---------- state shared by the lamps, MASTER CAUTION and the status screen
    function rowLevel(label) {
        var rows = bridge.systemRows || []
        for (var i = 0; i < rows.length; i++) if (String(rows[i].label) === label) return String(rows[i].level || "info")
        return "info"
    }
    function rowValue(label) {
        var rows = bridge.systemRows || []
        for (var i = 0; i < rows.length; i++) if (String(rows[i].label) === label) return String(rows[i].value || "")
        return ""
    }
    readonly property bool shieldsDown: bridge.shieldState === "DOWN"
    readonly property bool flightAlert: bridge.alertLabel === "ACTIVE ALERTS"
    readonly property var setupProblems: {
        var out = []
        var rows = bridge.systemRows || []
        for (var i = 0; i < rows.length; i++) {
            var lv = String(rows[i].level || "")
            if (lv === "warn" || lv === "bad") out.push(String(rows[i].label) + " // " + String(rows[i].value))
        }
        return out
    }
    // "r" red, "a" amber, "" dark
    readonly property string cautionLevel: !bridge.connected ? ""
        : (shieldsDown || (flightAlert && bridge.alertLevel === "bad")) ? "r"
        : ((flightAlert && bridge.alertLevel === "warn") || setupProblems.length > 0) ? "a" : ""
    readonly property string cautionText: {
        var parts = []
        if (shieldsDown) parts.push("SHIELDS DOWN")
        if (flightAlert) parts.push(bridge.alertDetail)
        for (var i = 0; i < setupProblems.length; i++) parts.push(setupProblems[i])
        return parts.join("  //  ")
    }

    Plate { anchors.fill: parent; screwSize: 14 * hdr.s }

    // ---------- title
    Item {
        id: titleBlock
        x: 34 * hdr.s; width: Math.max(titleText.implicitWidth, updTag.visible ? updTag.x + updTag.width : 0); height: parent.height
        Text {
            id: titleText
            y: parent.height / 2 - height + 8 * hdr.s
            text: "ELITE AI BRIDGE"
            font.family: Theme.stencilFont; font.pixelSize: Math.max(26, 60 * hdr.s); font.letterSpacing: 4 * hdr.s
            color: "#d8d0b8"; style: Text.Sunken; styleColor: "#1a1915"
        }
        Dymo { id: verDymo; x: 6 * hdr.s; y: titleText.y + titleText.height + 6 * hdr.s; text: "CORE DYNAMICS DEV // UNIT " + bridge.appVersion + (bridge.labBuild ? " // LAB" : "") }
        // 2.0.1: update tag beside the version. Slow amber pulse, always on screen (the status
        // screen gets taken by in-game alerts). Click opens SETUP > STATUS.
        Item {
            id: updTag
            visible: bridge.updateAvailable
            x: verDymo.x + verDymo.width + 12 * hdr.s
            y: verDymo.y + (verDymo.height - height) / 2
            width: updRow.width; height: Math.max(updLamp.height, updTape.height)
            Row {
                id: updRow; spacing: 8 * hdr.s
                anchors.verticalCenter: parent.verticalCenter
                Lamp { id: updLamp; width: 20 * hdr.s; height: width; lit: "a"; breathe: !updHover.containsMouse; anchors.verticalCenter: parent.verticalCenter }
                Dymo { id: updTape; small: true; text: "UPDATE " + bridge.updateLatestVersion; anchors.verticalCenter: parent.verticalCenter
                    Rectangle { anchors.fill: parent; radius: 1; color: "#ffffff"; opacity: updHover.containsMouse ? 0.16 : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } } } }
            }
            MouseArea { id: updHover; anchors.fill: parent; anchors.margins: -6 * hdr.s; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: hdr.updatePressed() }
            RetroToolTip { text: "UPDATE AVAILABLE // " + bridge.updateLatestVersion + " // CLICK FOR WHAT'S NEW"; shown: updHover.containsMouse; x: 0; y: parent.height + 10 * hdr.s }
        }
    }
    Rectangle { id: groove1; x: titleBlock.x + titleBlock.width + 34 * hdr.s; y: parent.height * 0.18; width: 3 * hdr.s; height: parent.height * 0.64; color: "#1b1a16"; border.color: "#5e5a4c"; border.width: 1 }

    // ---------- status lamps
    Row {
        id: lampRow
        x: groove1.x + 34 * hdr.s
        anchors.verticalCenter: parent.verticalCenter
        spacing: 34 * hdr.s
        Repeater {
            model: [
                { name: "LINK",  lit: bridge.connected ? "g" : "a",
                  tip: bridge.connected ? "BRIDGE ENGINE LINKED" : "BRIDGE ENGINE STARTING" },
                { name: "ELITE", lit: bridge.eliteTelemetryState === "CONNECTED" ? "g" : ((bridge.eliteTelemetryState === "WAITING" || bridge.eliteTelemetryState === "MENU") ? "a" : "r"),
                  tip: "ELITE DATA // " + (bridge.eliteTelemetryState === "MENU" ? "AT MAIN MENU" : bridge.eliteTelemetryState) },
                { name: "VOICE", lit: hdr.rowLevel("AUDIO OUTPUT") === "ok" ? "g" : "a",
                  tip: "AUDIO OUTPUT // " + (hdr.rowValue("AUDIO OUTPUT") || "-") },
                { name: "AI",    lit: hdr.rowValue("AI / VOICE") === "OFF" ? "" : (hdr.rowLevel("AI / VOICE") === "ok" ? "g" : "a"),
                  tip: "AI CO-PILOT // " + (hdr.rowValue("AI / VOICE") || "-") },
                { name: "PTT",   lit: bridge.voiceMode === "LISTENING" ? "g" : (hdr.rowLevel("VOICE / PTT") === "warn" ? "a" : ""),
                  tip: "PUSH TO TALK // " + bridge.pttStatus }
            ]
            Item {
                width: 56 * hdr.s; height: 78 * hdr.s
                Lamp { width: 38 * hdr.s; height: width; anchors.horizontalCenter: parent.horizontalCenter; y: 4 * hdr.s; lit: modelData.lit }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter; y: 56 * hdr.s
                    text: modelData.name; color: Theme.plateText
                    font.family: Theme.labelFont; font.pixelSize: Math.max(9, 14 * hdr.s); font.letterSpacing: 3 * hdr.s
                }
                MouseArea { id: lampHover; anchors.fill: parent; hoverEnabled: true }
                RetroToolTip { text: modelData.tip; shown: lampHover.containsMouse; x: (parent.width - width) / 2; y: parent.height + 8 * hdr.s }
            }
        }
    }

    // ---------- MASTER CAUTION (dark when fine; lit tile lists what is wrong)
    Item {
        id: caution
        x: lampRow.x + lampRow.width + 34 * hdr.s
        anchors.verticalCenter: parent.verticalCenter
        width: 150 * hdr.s; height: 96 * hdr.s
        Rectangle { anchors.fill: parent; anchors.margins: -5 * hdr.s; radius: 4 * hdr.s; color: "#121210"; border.color: "#000"; border.width: 1 }
        Glow { target: tile; color: hdr.cautionLevel === "r" ? "#ff5040" : "#ffaa28"; spread: 26 * hdr.s; radius: 3 * hdr.s
               intensity: hdr.cautionLevel !== "" ? 0.7 * flash : 0
               property real flash: 1
               SequentialAnimation on flash {   // slow pulse only while lit red (a real warning)
                   running: hdr.cautionLevel === "r"; loops: Animation.Infinite
                   NumberAnimation { from: 1; to: 0.45; duration: 450; easing.type: Easing.InOutSine }
                   NumberAnimation { from: 0.45; to: 1; duration: 450; easing.type: Easing.InOutSine }
               } }
        Rectangle {
            id: tile
            anchors.fill: parent; radius: 3 * hdr.s
            border.color: "#000"; border.width: 2
            gradient: Gradient {
                GradientStop { position: 0.0; color: hdr.cautionLevel === "r" ? "#ff6a50" : hdr.cautionLevel === "a" ? "#ffc155" : "#2c2a22" }
                GradientStop { position: 1.0; color: hdr.cautionLevel === "r" ? "#c0281c" : hdr.cautionLevel === "a" ? "#c98012" : "#1b1a16" }
            }
            Text {
                anchors.centerIn: parent; horizontalAlignment: Text.AlignHCenter
                text: "MASTER\nCAUTION"; lineHeight: 0.95
                font.family: Theme.labelFont; font.weight: Font.Bold; font.pixelSize: Math.max(10, 22 * hdr.s); font.letterSpacing: 3 * hdr.s
                color: hdr.cautionLevel === "" ? "#4a4434" : "#1e1206"
            }
        }
        PressArea {
            id: cautionArea
            anchors.fill: parent
            available: true
            onActivated: { Theme.cue(hdr.cautionLevel === "" ? "tick" : "nav"); hdr.masterCautionPressed() }
        }
        RetroToolTip {
            text: hdr.cautionLevel === "" ? "MASTER CAUTION // ALL CLEAR" : "MASTER CAUTION"
            detail: hdr.cautionLevel === "" ? "LIGHTS WHEN SOMETHING NEEDS YOUR ATTENTION" : hdr.cautionText
            shown: cautionArea.containsMouse
            x: 0; y: parent.height + 12 * hdr.s
        }
    }

    // ---------- right side: EXIT, HELP, TIP, clock (laid out from the right edge)
    Item {
        id: exitBay
        anchors.right: parent.right; anchors.rightMargin: 30 * hdr.s
        anchors.verticalCenter: parent.verticalCenter
        width: 128 * hdr.s; height: 112 * hdr.s
        Rectangle { anchors.fill: parent; radius: 5 * hdr.s; color: "#0e0d0b"; border.color: "#000"; border.width: 2
            Rectangle { anchors.fill: parent; anchors.margins: 3 * hdr.s; radius: 4 * hdr.s; color: "transparent"; border.color: "#3a372e"; border.width: 1 } }
        DeckKey {
            x: 14 * hdr.s; y: 12 * hdr.s; width: parent.width - 28 * hdr.s; height: parent.height - 30 * hdr.s
            title: "EXIT"; cap: "red"
            tooltip: "EXIT BRIDGE"; tooltipDetail: "SAVE + SHUT DOWN"
            onActivated: hdr.app.requestBridgeExit()
        }
    }
    DeckKey {
        id: helpKey
        anchors.right: exitBay.left; anchors.rightMargin: 22 * hdr.s
        anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: -4 * hdr.s
        width: 104 * hdr.s; height: 94 * hdr.s
        // the "?" beside each module plays its tour now (2026-10-10); this key only shows as STOP while one runs
        visible: !hdr.app.introVisible && hdr.tourActive
        // ? plays the walkthrough for the page you're on. The full tour of every
        // module lives on SETUP > STATUS (TUTORIAL). STOP ends either one.
        title: hdr.tourActive ? "STOP" : "?"
        legend: hdr.tourActive ? (hdr.app.firstOrientationActive ? "TUTORIAL" : "HELP") : "HELP"
        lampOverride: hdr.tourActive ? "a" : ""
        tooltip: hdr.tourActive ? (hdr.app.firstOrientationActive ? "STOP THE GUIDED TOUR" : "STOP THE WALKTHROUGH") : "HELP FOR THIS SCREEN"
        tooltipDetail: hdr.tourActive ? (hdr.app.firstOrientationActive ? "CONTROLS UNLOCK WHEN IT STOPS" : "ENDS THE SPOKEN WALKTHROUGH") : "SPOKEN WALKTHROUGH OF THIS PAGE"
        onActivated: {
            if (hdr.app.firstOrientationActive) hdr.app.stopFirstOrientation()
            else if (bridge.pageHelpActive) bridge.stopPageHelp()
            else bridge.startPageHelp(hdr.app.currentPage)
        }
    }
    DeckKey {
        id: tipKey
        anchors.right: helpKey.visible ? helpKey.left : exitBay.left; anchors.rightMargin: (helpKey.visible ? 16 : 22) * hdr.s
        anchors.verticalCenter: helpKey.verticalCenter
        width: 104 * hdr.s; height: 94 * hdr.s
        visible: !hdr.app.introVisible
        title: "TIP"; legend: "SUPPORT"
        // slow amber breathing; held steady during combat or an interdiction
        lampOverride: "a"
        lampBreathe: !bridge.combatActive && !bridge.combatUnderAttack && bridge.alertLevel !== "bad"
        tooltip: "SUPPORT DEVELOPMENT"; tooltipDetail: "OPENS THE TIP PAGE IN YOUR BROWSER"
        onActivated: { bridge.playUiCue("confirm"); bridge.openSupportPage() }
    }
    Item {
        id: clockBlock
        anchors.right: tipKey.left; anchors.rightMargin: 30 * hdr.s
        anchors.verticalCenter: parent.verticalCenter
        width: 300 * hdr.s; height: 118 * hdr.s
        readonly property string raw: String(bridge.localTime || "")
        readonly property string digits: raw.replace(/\s*[AP]M\s*$/i, "")
        readonly property string ampm: (raw.match(/[AP]M/i) || [""])[0].toUpperCase()
        Rectangle {
            id: clockWell
            width: parent.width; height: 92 * hdr.s
            radius: 4 * hdr.s; color: "#0b0605"; border.color: "#000"; border.width: 2
            Rectangle { anchors.fill: parent; anchors.margins: 4 * hdr.s; radius: 3 * hdr.s; color: "transparent"; border.color: "#2b1612"; border.width: 1 }
            Text {   // unlit segments
                anchors.centerIn: parent
                text: clockBlock.digits.replace(/[0-9]/g, "8")
                font.family: Theme.ledFont; font.pixelSize: Math.max(18, 50 * hdr.s)
                color: "#ff4a32"; opacity: 0.07
            }
            Text {
                id: clockDigits
                anchors.centerIn: parent
                text: clockBlock.digits
                font.family: Theme.ledFont; font.pixelSize: Math.max(18, 50 * hdr.s)
                color: "#ff4a32"; style: Text.Outline; styleColor: "#40ff2a10"
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter; y: clockWell.height + 6 * hdr.s
            text: "LOCAL TIME // " + (clockBlock.ampm || "--")
            color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: Math.max(8, 13 * hdr.s); font.letterSpacing: 3 * hdr.s
        }
    }

    // ---------- status CRT (fills the space between MASTER CAUTION and the clock)
    Bezel {
        id: statusBezel
        anchors.left: caution.right; anchors.leftMargin: 40 * hdr.s
        anchors.right: clockBlock.left; anchors.rightMargin: 36 * hdr.s
        anchors.verticalCenter: parent.verticalCenter
        height: 110 * hdr.s
        pad: 10 * hdr.s
        readonly property bool inControl: bridge.controlOwner !== "NONE" && bridge.controlOwner !== ""
        readonly property var lines: {
            if (hdr.notice !== "")
                return [hdr.notice, hdr.noticeDetail, hdr.noticeLevel === "bad" ? Theme.bad : (hdr.noticeLevel === "ok" ? Theme.ok : Theme.info)]
            if (!bridge.connected)
                return [bridge.bridgeState, bridge.bridgeMessage, bridge.bridgeLevel === "bad" ? Theme.bad : Theme.info]
            if (inControl)
                return ["BRIDGE IN CONTROL // " + bridge.bridgeState, bridge.bridgeMessage, Theme.control]
            if (hdr.shieldsDown)
                return ["SHIELDS OFFLINE", hdr.flightAlert ? bridge.alertDetail : "SHIELDS DOWN", Theme.bad]
            if (hdr.flightAlert)
                return [bridge.alertDetail, bridge.alertValue + " ACTIVE ALERT" + (bridge.alertValue === "1" ? "" : "S"), bridge.alertLevel === "bad" ? Theme.bad : Theme.info]
            if (bridge.updateAvailable && String(bridge.bridgeState || "IDLE") === "IDLE")
                return ["UPDATE AVAILABLE // " + bridge.updateLatestVersion, "SEE SETUP > STATUS", Theme.info]
            if (bridge.eliteTelemetryState === "MENU")
                return ["ELITE AT MAIN MENU", "LOAD IN // THE BRIDGE PICKS UP YOUR SHIP", Theme.info]
            if (bridge.eliteTelemetryState !== "CONNECTED")
                return [bridge.eliteTelemetryState === "WAITING" ? "WAITING FOR ELITE" : "ELITE NOT RUNNING",
                        "START ELITE DANGEROUS // THE BRIDGE CONNECTS BY ITSELF", Theme.info]
            var st = String(bridge.bridgeState || "")
            if (st === "IDLE" || st === "") {
                if (hdr.setupProblems.length)
                    return ["SETUP NEEDS ATTENTION", hdr.setupProblems[0] + (hdr.setupProblems.length > 1 ? "  +" + (hdr.setupProblems.length - 1) + " MORE // SEE MASTER CAUTION" : ""), Theme.info]
                return ["ALL SYSTEMS NOMINAL", "NO ACTIVE ALERTS", Theme.ok]
            }
            return [st, bridge.bridgeMessage, bridge.bridgeLevel === "bad" ? Theme.bad : (bridge.bridgeLevel === "warn" ? Theme.info : Theme.ok)]
        }
        Column {
            x: 18 * hdr.s; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 36 * hdr.s
            spacing: -2 * hdr.s
            Text {
                width: parent.width; elide: Text.ElideRight
                text: String(statusBezel.lines[0]).toUpperCase()
                color: statusBezel.lines[2]
                font.family: Theme.crtFont; font.pixelSize: Math.max(16, 38 * hdr.s); font.letterSpacing: 2 * hdr.s
            }
            Row {
                width: parent.width
                Text {
                    id: line2
                    width: Math.min(implicitWidth, parent.width - cursor.width); elide: Text.ElideRight
                    text: String(statusBezel.lines[1] || "").toUpperCase()
                    color: Qt.darker(statusBezel.lines[2], 1.25)
                    font.family: Theme.crtFont; font.pixelSize: Math.max(14, 30 * hdr.s); font.letterSpacing: 2 * hdr.s
                }
                Rectangle {
                    id: cursor
                    width: 14 * hdr.s; height: line2.font.pixelSize * 0.8; anchors.verticalCenter: line2.verticalCenter
                    color: statusBezel.lines[2]
                    opacity: blink.on ? 0.9 : 0
                    Timer { id: blink; property bool on: true; interval: 530; repeat: true; running: true; onTriggered: on = !on }
                }
            }
        }
    }
}
