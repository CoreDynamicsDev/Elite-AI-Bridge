// Raised key for modules, views and small pick-one rows (approved mockup controls_mockup_v1.png).
// Up: a graphite keycap with a shadow under it, so it reads as something to press.
// on: latched down and lit ("you are here"): a green window on keys with a pip, the whole
// face lit green on small centred keys. Pressing a key that's already on does nothing.
import QtQuick
import "."

Item {
    id: pb
    property string title: ""
    property string sub: ""
    property bool on: false
    property bool latched: false          // kept for old callers: pressed in, not lit
    property bool pip: true               // lit window (views, modules)
    property bool centered: false         // small pick-one keys (no window, face lights)
    property string tooltip: ""
    property bool available: true
    property string unavailableReason: ""
    property int repeatMs: Theme.repeatGuardMs
    signal activated()
    signal denied(string reason)
    implicitWidth: 300; implicitHeight: 76
    readonly property real u: height / 76
    readonly property bool hovered: area.containsMouse && available
    readonly property bool down: on || latched || (area.pressed && area.containsMouse)
    readonly property real depth: 6 * u
    readonly property real travel: down ? depth * 0.85 : (hovered ? -1 * u : 0)
    readonly property bool faceLit: on && (centered || !pip)
    readonly property bool windowRight: sub !== ""        // modules keep the light on the right

    // well the key sits in
    Rectangle { anchors.fill: parent; radius: 7 * pb.u; color: "#0d0d0c"; border.color: "#3a3832"; border.width: 1 }
    // shadow + key side while it's up
    Rectangle { x: 2 * pb.u; y: pb.depth + 2 * pb.u; width: parent.width - 4 * pb.u; height: parent.height - pb.depth - 2 * pb.u; radius: 6 * pb.u
                color: "#000"; opacity: pb.down ? 0 : 0.6 }
    Rectangle { x: 1; y: pb.depth; width: parent.width - 2; height: parent.height - pb.depth - 1; radius: 6 * pb.u
                color: "#141412"; visible: !pb.down }
    Glow { target: cap; color: "#46ff82"; spread: 18 * pb.u; radius: 6 * pb.u; intensity: pb.on ? (pb.faceLit ? 0.5 : 0.28) : 0 }
    // cap
    Rectangle {
        id: cap
        x: 1; y: 1 + pb.travel; width: parent.width - 2; height: parent.height - pb.depth - 2
        radius: 6 * pb.u
        gradient: Gradient {
            GradientStop { position: 0.0;  color: pb.faceLit ? "#3b9c5a" : (pb.down ? "#3a3934" : (pb.hovered ? "#6a675d" : "#5c5a51")) }
            GradientStop { position: 0.14; color: pb.faceLit ? "#2c7a45" : (pb.down ? "#2c2b27" : "#45433c") }
            GradientStop { position: 1.0;  color: pb.faceLit ? "#0d3a1f" : (pb.down ? "#1f1e1b" : "#2c2b27") }
        }
        border.color: pb.faceLit ? "#7dff9c" : (pb.down ? "#11110f" : (pb.hovered ? "#8a877b" : "#77746a")); border.width: 1
        Rectangle { x: 6 * pb.u; y: 1; width: parent.width - 12 * pb.u; height: 1; color: "white"; opacity: pb.down ? 0.05 : 0.28 }
        // lit window
        Rectangle {
            id: win
            visible: pb.pip && !pb.centered
            x: pb.windowRight ? parent.width - width - 14 * pb.u : 14 * pb.u
            anchors.verticalCenter: parent.verticalCenter
            width: (pb.windowRight ? 14 : 38) * pb.u; height: (pb.windowRight ? 14 : 15) * pb.u; radius: 2 * pb.u
            color: pb.on ? "#8dffaa" : "#1a1c18"; border.color: "#0a0a09"; border.width: 1
            Rectangle { anchors.fill: parent; anchors.margins: 2; radius: 1; visible: pb.on
                        gradient: Gradient { GradientStop { position: 0; color: "#ccffda" } GradientStop { position: 1; color: "#4fe07a" } } }
        }
        Glow { target: win; color: "#46ff82"; spread: 14 * pb.u; radius: 3; intensity: pb.on && win.visible ? 0.8 : 0 }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            x: pb.centered ? (parent.width - width) / 2 : ((win.visible && !pb.windowRight) ? win.x + win.width + 14 * pb.u : 16 * pb.u)
            spacing: 1
            Text {
                text: pb.title.toUpperCase()
                font.family: Theme.labelFont; font.weight: Font.DemiBold
                font.pixelSize: (pb.sub !== "" ? 25 : 20) * pb.u; font.letterSpacing: (pb.centered ? 2 : 4) * pb.u
                color: pb.on ? "#eaffef" : (pb.latched ? "#e8e4d8" : "#d9d4c4")
                style: pb.faceLit ? Text.Outline : Text.Normal; styleColor: "#3346ff82"
            }
            Text {
                visible: pb.sub !== ""
                text: pb.sub.toUpperCase()
                font.family: Theme.labelFont; font.pixelSize: 13 * pb.u; font.letterSpacing: 3 * pb.u
                color: pb.on ? "#a9f3bf" : "#9a968a"
            }
        }
        Rectangle { anchors.fill: parent; radius: parent.radius; color: "black"; opacity: pb.available ? 0 : 0.45 }
    }
    PressArea {
        id: area
        anchors.fill: parent
        available: pb.available
        guardMs: pb.repeatMs
        unavailableReason: pb.unavailableReason
        onActivated: { if (pb.on) return; Theme.cue("click"); pb.activated() }
        onDenied: (r) => pb.denied(r)
    }
}
