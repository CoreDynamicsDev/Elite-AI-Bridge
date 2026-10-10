// Action Deck keycap. One component for every deck key on every page.
// keyState: "ready" (green lamp), "running" (amber lamp + progress, legend shows live status),
//           "unavailable" (dimmed, lamp off, press = denied + reason), "empty" (preset with nothing saved),
//           "saving" (preset being saved, amber + fill).
// cap: "cream" normal, "mustard" emergency, "grey" secondary, "red" CANCEL / EXIT only.
// The key only reports; the page sends the same command a HOTAS / Stream Deck / voice input would.
import QtQuick
import "."

Item {
    id: key
    property string title: ""
    property string legend: ""
    property string cap: "cream"
    property string keyState: "ready"
    property real progress: -1                 // 0..1 while running, -1 = no bar
    property string tooltip: ""
    property string tooltipDetail: ""
    property string unavailableReason: ""
    property bool holdToSave: false            // Home / Bookmark presets only
    property bool hazard: false                // CANCEL only
    property string lampOverride: "-"          // "-" = lamp follows keyState; otherwise g / a / r / w / ""
    property bool lampBreathe: false
    readonly property real holdProgress: area.holdProgress   // preset keys: 0..1 while held
    signal activated()
    signal denied(string reason)
    signal saveRequested()

    implicitWidth: 240; implicitHeight: 117
    readonly property real u: height / 117
    readonly property bool hovered: area.containsMouse
    readonly property bool down: area.pressed && area.containsMouse
    readonly property var capColors: ({
        cream:   ["#e7dfc8", "#cbc1a5", "#b8ad90", "#7e7660", "#1b1a17"],
        mustard: ["#d9b04a", "#bf9330", "#a87f24", "#6f5418", "#1b1a17"],
        grey:    ["#a3a198", "#878579", "#75736a", "#4b4a43", "#1b1a17"],
        red:     ["#bf4234", "#a3312a", "#8a2721", "#5a1914", "#f3e6d8"]
    })
    readonly property var c: capColors[cap] || capColors.cream
    readonly property bool dimmed: keyState === "unavailable"
    readonly property real travel: 9 * u

    // hazard frame (CANCEL)
    Item {
        visible: key.hazard
        x: -16 * key.u; y: -16 * key.u; width: parent.width + 32 * key.u; height: parent.height + 28 * key.u
        HazardStripes { anchors.fill: parent; stripe: 16 * key.u }
        Rectangle { anchors.fill: parent; anchors.margins: 10 * key.u; color: "#151513"; radius: 4 }
    }
    // cast shadow + skirt (the depth of the key)
    Rectangle { x: 0; y: key.travel + 7 * key.u; width: parent.width; height: parent.height - key.travel; radius: 8 * key.u; color: "black"; opacity: 0.5 }
    Rectangle { x: 0; y: key.travel; width: parent.width; height: parent.height - key.travel; radius: 7 * key.u; color: key.c[3]; border.color: "#2a2822"; border.width: 1 }

    // the cap: lifts on hover, sinks on press
    Item {
        id: capItem
        width: parent.width; height: parent.height - key.travel
        y: key.down ? key.travel * 0.78 : (key.hovered && !key.dimmed ? -3 * key.u : 0)
        Behavior on y { NumberAnimation { duration: key.down ? Theme.pressMs : Theme.releaseMs; easing.type: Easing.OutCubic } }
        Rectangle {
            anchors.fill: parent; radius: 7 * key.u
            gradient: Gradient {
                GradientStop { position: 0.0; color: key.c[0] }
                GradientStop { position: 0.7; color: key.c[1] }
                GradientStop { position: 1.0; color: key.c[2] }
            }
            border.width: key.hovered && !key.down ? 2 : 0
            border.color: key.dimmed ? "#a8a08a" : "#7dff9c"
            Behavior on border.width { NumberAnimation { duration: Theme.hoverInMs } }
        }
        Rectangle { x: 6 * key.u; y: 2; width: parent.width - 12 * key.u; height: 2; radius: 1; color: "white"; opacity: key.cap === "red" ? 0.3 : 0.5 }
        // grime toward the bottom
        Rectangle {
            anchors.fill: parent; radius: 7 * key.u
            gradient: Gradient { GradientStop { position: 0.6; color: "#00281e0a" } GradientStop { position: 1.0; color: "#40281e0a" } }
        }
        Column {
            anchors.centerIn: parent
            spacing: 3 * key.u
            // titles and legends shrink to fit narrow keys instead of running off the cap
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: key.width - 22 * key.u; height: font.pixelSize * 1.25
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                fontSizeMode: Text.HorizontalFit; minimumPixelSize: Math.max(9, 14 * key.u)
                text: key.title.toUpperCase()
                font.family: Theme.labelFont; font.weight: Font.Bold
                font.pixelSize: (key.title.length > 12 ? 22 : (key.title.length > 8 ? 26 : 30)) * key.u
                font.letterSpacing: (key.width < 250 * key.u ? 2 : 3) * key.u
                color: key.c[4]
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: text !== ""
                width: key.width - 20 * key.u; height: font.pixelSize * 1.3
                horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                fontSizeMode: Text.HorizontalFit; minimumPixelSize: Math.max(8, 10 * key.u)
                text: (key.keyState === "empty" ? "EMPTY // HOLD TO SAVE" : key.legend).toUpperCase()
                font.family: Theme.labelFont; font.weight: Font.Medium
                font.pixelSize: 13 * key.u; font.letterSpacing: (key.width < 250 * key.u ? 1.5 : 2.5) * key.u
                color: key.c[4]; opacity: 0.75
            }
        }
        Lamp {
            visible: key.cap !== "red"
            width: 13 * key.u; height: width
            x: parent.width - width - 12 * key.u; y: 10 * key.u
            lit: key.lampOverride !== "-" ? key.lampOverride
                 : key.keyState === "ready" ? "g" : (key.keyState === "running" || key.keyState === "saving") ? "a" : ""
            breathe: key.lampBreathe
        }
        // progress (running) or hold fill (saving)
        Rectangle {
            visible: key.keyState === "running" && key.progress >= 0 || area.holdProgress > 0
            x: 14 * key.u; width: parent.width - 28 * key.u; height: 6 * key.u; y: parent.height - 14 * key.u
            radius: 2; color: "#40000000"
            Rectangle {
                width: parent.width * (area.holdProgress > 0 ? area.holdProgress : Math.max(0, Math.min(1, key.progress)))
                height: parent.height; radius: 2; color: "#d98a12"
            }
        }
        Rectangle { anchors.fill: parent; radius: 7 * key.u; color: "black"; opacity: key.dimmed ? 0.24 : 0 }
    }

    PressArea {
        id: area
        anchors.fill: parent
        available: key.keyState !== "unavailable" && key.keyState !== "empty"
        unavailableReason: key.keyState === "empty" ? "EMPTY // HOLD TO SAVE" : key.unavailableReason
        holdEnabled: key.holdToSave
        onActivated: { Theme.cue("key"); key.activated() }
        onDenied: (reason) => key.denied(reason)
        onHeld: { Theme.cue("confirm"); key.saveRequested() }
    }

    Timer { id: tipTimer; interval: Theme.tooltipDelayMs; running: area.containsMouse && !area.pressed }
    RetroToolTip {
        text: key.dimmed ? "UNAVAILABLE // " + key.unavailableReason : key.tooltip
        detail: key.tooltipDetail
        shown: area.containsMouse && !area.pressed && !tipTimer.running
        x: (key.width - width) / 2; y: -height - 14 * key.u
    }
}
