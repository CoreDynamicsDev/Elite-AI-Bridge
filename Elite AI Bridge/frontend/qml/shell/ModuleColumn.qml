// Left column shared by every page: module buttons, AI COMMS screen, AI session line,
// and the compact voice block (scope, PTT, talk level).
import QtQuick
import "../skin"

Item {
    id: col
    property var app
    property alias moduleRepeater: rep
    property alias guideTarget: guide
    property alias voiceTarget: voiceBlock    // setup wizard lights it
    signal modulePicked(int page)

    readonly property real s: Theme.s

    // [title, subtitle, page]. Order = the guided tour order (firstOrientationPages in Main.qml).
    readonly property var modules: [
        ["FLIGHT DECK", "SHIP + ROUTE + LOG", 0],
        ["COMBAT", "THREAT ANALYSIS", 2],
        ["TRADE", "MARKETS & GOODS", 3],
        ["NAVIGATION", "ROUTE COMPUTER", 1],
        ["COLONIZATION", "SYSTEM DEVELOPMENT", 4],
        ["COMMANDER", "RECORDS + CARGO", 5],
        ["SETUP", "SYSTEM SETTINGS", 8]
    ]
    // "?" beside a module: go to that page (if needed) and play its spoken walkthrough
    function startTour(page, tourPage) {
        if (!col.isActive(page)) { col.modulePicked(page); tourPage = page === 0 ? 12 : page }
        bridge.markTourWatched(page)
        Qt.callLater(function () { bridge.startPageHelp(tourPage) })
    }
    function isActive(page) {
        var p = col.app.currentPage
        if (page === 8) return p === 6 || p === 7 || p === 8 || p === 9 || p === 10 || p === 11
        return p === page
    }

    Plate { anchors.fill: parent; screwSize: 14 * col.s }

    Dymo { x: 26 * col.s; y: 20 * col.s; text: "MODULE SELECT" }

    // tour highlight target for the whole module bank
    Item {
        id: guide
        x: 14 * col.s; y: buttons.y - 10 * col.s
        width: parent.width - 28 * col.s
        height: buttons.height + 20 * col.s
    }
    Column {
        id: buttons
        x: 22 * col.s; y: 62 * col.s
        width: parent.width - 44 * col.s
        spacing: 9 * col.s
        Repeater {
            id: rep
            model: col.modules
            // module button + its own small "?" tour button (2026-10-10). The dot under the "?"
            // is amber until that page's tour has been watched once.
            Item {
                id: row
                width: buttons.width; height: Math.max(40, 74 * col.s)
                readonly property real tourW: 58 * col.s
                readonly property int page: modelData[2]
                // Flight Deck plays its own tour (help page 12); Setup plays the tab you're on
                readonly property int tourPage: page === 0 ? 12 : (page === 8 && col.isActive(8) ? col.app.currentPage : page)
                readonly property bool watched: (bridge.tourWatched || []).indexOf(page) >= 0
                LitButton {
                    width: parent.width - row.tourW - 8 * col.s; height: parent.height
                    title: modelData[0]; sub: modelData[1]
                    on: col.isActive(modelData[2])
                    onActivated: col.modulePicked(modelData[2])
                }
                LitButton {
                    x: parent.width - row.tourW; width: row.tourW; height: parent.height
                    title: "?"; pip: false; centered: true
                    tooltip: "TOUR THIS PAGE"
                    available: !col.app.firstOrientationActive
                    unavailableReason: "THE FULL TOUR IS RUNNING"
                    onActivated: col.startTour(row.page, row.tourPage)
                    Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: parent.height - 16 * col.s
                                width: 9 * col.s; height: width; radius: width / 2
                                color: row.watched ? "#1a1c18" : Theme.info; border.color: "#0a0a09"; border.width: 1 }
                }
            }
        }
    }

    // ---------- AI COMMS
    Dymo { id: commsTape; x: 26 * col.s; y: buttons.y + buttons.height + 24 * col.s; text: "AI COMMS"; small: true }
    Bezel {
        id: commsBezel
        x: 18 * col.s; y: commsTape.y + commsTape.height + 10 * col.s
        width: parent.width - 36 * col.s
        height: Math.max(80 * col.s, sessionLine.y - y - 12 * col.s)
        pad: 10 * col.s
        PhosphorList {
            id: comms
            anchors.fill: parent; anchors.margins: 12 * col.s
            anchors.bottomMargin: 34 * col.s
            stickToEnd: true
            fontSize: Math.max(13, 21 * col.s)
            model: bridge.aiCommsRows
            delegate: Text {
                required property var modelData
                width: comms.list.width
                readonly property bool cmdr: String(modelData.speaker || "").toUpperCase() === "CMDR"
                text: (cmdr ? "CMDR> " : "BRIDGE> ") + String(modelData.text || "")
                color: cmdr ? "#b9c7bb" : Theme.ok
                font.family: Theme.crtFont; font.pixelSize: comms.fontSize
                wrapMode: Text.WordWrap; lineHeight: 0.95
                bottomPadding: 8 * col.s
            }
        }
        Text {
            visible: comms.list.count === 0
            x: 12 * col.s; y: 12 * col.s; width: parent.width - 24 * col.s
            text: "HOLD PTT AND ASK THE BRIDGE WHAT YOU WANT TO DO."
            color: Theme.dimText; wrapMode: Text.WordWrap
            font.family: Theme.crtFont; font.pixelSize: Math.max(13, 21 * col.s)
        }
        Text {
            x: 12 * col.s; anchors.bottom: parent.bottom; anchors.bottomMargin: 8 * col.s
            width: parent.width - 24 * col.s; elide: Text.ElideRight
            readonly property bool thinking: String(bridge.aiCopilotStatus || "").toUpperCase().indexOf("THINK") >= 0
            text: String(bridge.aiCopilotStatus || "READY").toUpperCase() + " // HOLD PTT"
            color: thinking ? Theme.info : Theme.dimText
            font.family: Theme.crtFont; font.pixelSize: Math.max(12, 18 * col.s)
        }
    }
    Text {
        id: sessionLine
        x: 24 * col.s; y: voiceBlock.y - height - 12 * col.s
        width: parent.width - 48 * col.s; elide: Text.ElideRight
        text: bridge.bridgeMode === "CORE" ? "AI SESSION // OFF // CORE MODE"
              : "AI SESSION // " + bridge.aiCalls + " REQ // " + bridge.aiEstimatedCostText
        color: Theme.plateText; opacity: 0.85
        font.family: Theme.labelFont; font.pixelSize: Math.max(9, 13 * col.s); font.letterSpacing: 2 * col.s
    }

    // ---------- VOICE
    Item {
        id: voiceBlock
        x: 18 * col.s; width: parent.width - 36 * col.s
        height: 214 * col.s
        anchors.bottom: parent.bottom; anchors.bottomMargin: 20 * col.s
        Rectangle { anchors.fill: parent; radius: 4 * col.s; color: "#1e1d19"; border.color: "#000"; border.width: 1; opacity: 0.6 }
        Dymo { x: 10 * col.s; y: -8 * col.s; text: "VOICE"; small: true }

        // voice scope: same shape and colour as the in-game overlay (bridge.bridgeActivity)
        VoiceScope {
            id: scope
            x: 12 * col.s; y: 22 * col.s
            width: 100 * col.s; height: width
            activity: bridge.bridgeActivity
            k: Math.max(0.7, Theme.s); rim: 7 * col.s
        }

        Column {
            x: scope.x + scope.width + 14 * col.s; y: 34 * col.s
            width: parent.width - x - 10 * col.s
            spacing: 10 * col.s
            Row {
                spacing: 10 * col.s
                Lamp { width: 22 * col.s; height: width; anchors.verticalCenter: parent.verticalCenter
                       lit: bridge.voiceMode === "LISTENING" ? "g" : (bridge.pttStatus === "NOT MAPPED" ? "a" : "") }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: bridge.voiceMode === "LISTENING" ? "PTT // LISTENING" : (bridge.pttStatus === "NOT MAPPED" ? "PTT // NOT MAPPED" : "PTT // HOLD")
                    color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: Math.max(9, 14 * col.s); font.letterSpacing: 2 * col.s
                }
            }
            Text {
                width: parent.width; elide: Text.ElideRight
                text: bridge.bridgeActivity === "IDLE" ? "VOICE // READY" : bridge.bridgeActivityTitle
                color: Theme.plateText; opacity: 0.75; font.family: Theme.labelFont; font.pixelSize: Math.max(8, 12 * col.s); font.letterSpacing: 2 * col.s
            }
        }
        Text {
            x: 12 * col.s; y: talk.y - height - 4 * col.s
            text: "TALK LEVEL"
            color: Theme.plateText; opacity: 0.8; font.family: Theme.labelFont; font.pixelSize: Math.max(8, 12 * col.s); font.letterSpacing: 2 * col.s
        }
        SelectorRow {
            id: talk
            x: 12 * col.s; y: parent.height - buttonHeight - 12 * col.s
            readonly property var values: ["OFF", "IMPORTANT", "MOST"]
            options: ["QUIET", "BALANCED", "TALKATIVE"]     // same stored values; "OFF" still spoke safety alerts
            currentIndex: Math.max(0, values.indexOf(String(bridge.voiceAttentionMode || "IMPORTANT")))
            buttonHeight: 44 * col.s
            buttonWidth: (parent.width - 24 * col.s - spacing * 2) / 3
            onPicked: (index) => { if (index !== currentIndex) bridge.setVoiceAttention(values[index]) }
        }
    }
}
