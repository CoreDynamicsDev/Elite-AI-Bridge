// In-game overlay panels (v2, retro skin). Pure drawing: the window, position and
// state logic live in Main.qml / main.py. Spec: claude/overlay-activity-state.md.
//   activity: IDLE LISTENING THINKING SPEAKING AUTOMATION CRITICAL DONE FAILED FAULT NOCREDITS
// Light scanlines only (no grain, flicker or curvature) so it stays readable over the game.
import QtQuick
import "."

Item {
    id: ov
    property string activity: "IDLE"
    property string detail: ""
    property string title: ""              // overrides the state's own words when set
    property var rows: []                  // [{speaker: "CMDR"|"BRIDGE", text}]
    property real f: 1.0                   // size factor (SMALL 0.62, STANDARD 1, LARGE 1.42)
    property real see: 0.82                // panel opacity (HOW SOLID)
    property bool showActivity: true
    property bool showChat: true
    property bool animate: true
    property real t: 0                     // 0..4 s loop, shared by the scope

    readonly property int activityW: Math.round(420 * f)
    readonly property int activityH: Math.round(100 * f)
    readonly property int chatW: activityW
    readonly property int chatH: Math.round(300 * f)
    readonly property int gap: Math.round(10 * f)
    implicitWidth: activityW
    implicitHeight: (showActivity ? activityH : 0) + (showActivity && showChat ? gap : 0) + (showChat ? chatH : 0)

    readonly property var look: ({
        IDLE:       { title: "BRIDGE READY" },
        LISTENING:  { title: "LISTENING" },
        THINKING:   { title: "THINKING" },
        SPEAKING:   { title: "SHIP SPEAKING" },
        AUTOMATION: { title: "BRIDGE IN CONTROL" },
        CRITICAL:   { title: "SHIELDS DOWN" },
        DONE:       { title: "DONE" },
        FAILED:     { title: "COMMAND FAILED" },
        FAULT:      { title: "BRIDGE FAULT" },
        NOCREDITS:  { title: "AI OFFLINE" }
    })
    readonly property var cur: look[activity] || look.IDLE
    readonly property color col: Theme.activityColor(activity)
    readonly property string titleText: title !== "" ? title : cur.title

    FrameAnimation { running: ov.animate && ov.visible; onTriggered: ov.t = (ov.t + frameTime) % 4.0 }

    component Glass: Item {
        id: g
        property color edge: "#4a4c44"
        property color tint: ov.col
        Rectangle { anchors.fill: parent; radius: 6 * ov.f; opacity: ov.see
            gradient: Gradient { GradientStop { position: 0; color: Theme.t("#0b1a10") } GradientStop { position: 1; color: Theme.t("#030805") } }
            border.color: g.edge; border.width: 1 }
        Rectangle { anchors.fill: parent; anchors.margins: 2; radius: 5 * ov.f; color: "transparent"
            border.color: g.tint; border.width: 1; opacity: 0.30 * ov.see + 0.1 }
        Rectangle { x: 0; y: 6 * ov.f; width: Math.max(3, 5 * ov.f); height: parent.height - 12 * ov.f; radius: 2; color: g.tint; opacity: 0.9 }
        // scanlines
        Canvas {
            property bool themeAmber: Theme.amber   // LAB themes: repaint when the screen theme changes
            onThemeAmberChanged: requestPaint()
            anchors.fill: parent; anchors.margins: 2; opacity: 0.5
            onPaint: { var c = getContext("2d"); c.reset(); c.fillStyle = "rgba(0,0,0,0.22)"
                       for (var y = 0; y < height; y += 3) c.fillRect(0, y, width, 1) }
        }
    }

    // ================================================================ ACTIVITY
    Item {
        id: act
        visible: ov.showActivity
        width: ov.activityW; height: ov.activityH
        Glass { anchors.fill: parent }

        // mini voice scope (shared with the module column)
        VoiceScope {
            id: scope
            x: 16 * ov.f; anchors.verticalCenter: parent.verticalCenter
            width: 76 * ov.f; height: width
            activity: ov.activity; t: ov.t; animate: false; k: ov.f; rim: 5 * ov.f
        }
        // state words: fade out, colour shifts, fade in (seamless rule)
        Item {
            id: words
            x: scope.x + scope.width + 16 * ov.f; width: parent.width - x - 14 * ov.f
            height: parent.height
            property string shownTitle: ov.titleText
            property string shownDetail: ov.detail
            Column {
                id: wc
                anchors.verticalCenter: parent.verticalCenter; width: parent.width; spacing: 2 * ov.f
                Text { width: parent.width; elide: Text.ElideRight; text: words.shownTitle; color: ov.col
                       font.family: Theme.crtFont; font.pixelSize: Math.max(14, 34 * ov.f); font.letterSpacing: 1.5 * ov.f }
                Text { width: parent.width; elide: Text.ElideRight; visible: text !== ""; text: words.shownDetail.toUpperCase(); color: Theme.phosphor; opacity: 0.85
                       font.family: Theme.crtFont; font.pixelSize: Math.max(11, 19 * ov.f); font.letterSpacing: 0.5 * ov.f }
            }
            Connections {
                target: ov
                function onActivityChanged() { swap.restart() }
                function onTitleTextChanged() { if (!swap.running) swap.restart() }
                function onDetailChanged() { if (!swap.running) words.shownDetail = ov.detail }
            }
            SequentialAnimation {
                id: swap
                NumberAnimation { target: wc; property: "opacity"; to: 0; duration: 160 }
                ScriptAction { script: { words.shownTitle = ov.titleText; words.shownDetail = ov.detail } }
                NumberAnimation { target: wc; property: "opacity"; to: 1; duration: 220 }
            }
        }
    }

    // ================================================================ AI COMMS
    Item {
        id: chat
        visible: ov.showChat
        y: ov.showActivity ? ov.activityH + ov.gap : 0
        width: ov.chatW; height: ov.chatH
        Glass { anchors.fill: parent; tint: "#c98a2c" }
        Text { x: 18 * ov.f; y: 9 * ov.f; text: "AI COMMS"; color: "#d9a54a"
               font.family: Theme.labelFont; font.pixelSize: Math.max(9, 14 * ov.f); font.letterSpacing: 3 * ov.f }
        Rectangle { x: 18 * ov.f; y: 32 * ov.f; width: parent.width - 32 * ov.f; height: 1; color: "#6e5a32"; opacity: 0.8 }
        Item {
            id: lines
            x: 18 * ov.f; y: 40 * ov.f; width: parent.width - 32 * ov.f; height: parent.height - 50 * ov.f
            clip: true
            Text { anchors.centerIn: parent; visible: (ov.rows || []).length === 0; text: "AI COMMS STANDING BY"; color: Theme.dimText
                   font.family: Theme.crtFont; font.pixelSize: Math.max(11, 22 * ov.f) }
            // newest at the bottom, older lines fade; can't scroll (click-through window)
            Column {
                anchors.bottom: parent.bottom; width: parent.width; spacing: 6 * ov.f
                Repeater {
                    model: (ov.rows || []).slice(-6)
                    delegate: Row {
                        required property var modelData
                        required property int index
                        readonly property int fromEnd: Math.min(6, (ov.rows || []).length) - 1 - index
                        readonly property bool cmdr: String(modelData.speaker || "").toUpperCase() === "CMDR"
                        width: lines.width; spacing: 8 * ov.f
                        opacity: Math.max(0.3, 1 - fromEnd * 0.16)
                        Text { width: 66 * ov.f; text: parent.cmdr ? "CMDR" : "BRIDGE"; color: parent.cmdr ? Theme.plateText : Theme.ok
                               font.family: Theme.crtFont; font.pixelSize: Math.max(10, 20 * ov.f) }
                        Text { width: parent.width - 74 * ov.f; text: String(modelData.text || ""); color: parent.cmdr ? Theme.plateText : Theme.phosphor
                               wrapMode: Text.WordWrap; maximumLineCount: 4; elide: Text.ElideRight
                               font.family: Theme.crtFont; font.pixelSize: Math.max(10, 20 * ov.f) }
                    }
                }
            }
        }
    }
}
