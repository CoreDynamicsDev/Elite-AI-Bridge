// ON / OFF as one rocker button (approved rocker_mockup_v2.png). The side that is set sits down
// in the housing and is lit (ON green, OFF warm white); the other side is plain raised plastic.
import QtQuick
import "."

Item {
    id: pair
    property bool on: false
    property real buttonWidth: 84
    property real buttonHeight: 48
    property bool available: true
    property string unavailableReason: ""
    property real spacing: 0
    signal changed(bool on)
    signal denied(string reason)
    width: buttonWidth * 2; height: buttonHeight
    readonly property real u: height / 48
    readonly property bool hovered: area.containsMouse
    // Flip straight away when clicked, then follow the backend: the saved value comes back
    // through 'on' a moment later (up to ~1 s). If it never agrees, fall back after 3 s.
    property int pending: -1                  // -1 none, 0 off, 1 on
    readonly property bool shown: pending === -1 ? on : pending === 1
    onOnChanged: if (pending !== -1 && on === (pending === 1)) pending = -1
    Timer { id: pendingTimer; interval: 3000; onTriggered: pair.pending = -1 }

    // housing
    Rectangle { anchors.fill: parent; anchors.margins: -3 * pair.u; radius: 7 * pair.u; color: "#0b0b0a"; border.color: "#3e3b32"; border.width: 1 }
    Rectangle { anchors.fill: parent; radius: 5 * pair.u; color: "#151513" }

    // two halves; the pressed one is sunk and shaded, the raised one catches the light
    Repeater {
        model: [{ label: "ON", isOn: true }, { label: "OFF", isOn: false }]
        Item {
            id: half
            x: index === 0 ? 0 : pair.width / 2; width: pair.width / 2; height: pair.height
            readonly property bool pressed: modelData.isOn === pair.shown
            readonly property bool glowing: pressed && pair.available   // an unused rocker shows no light at all
            readonly property bool lit: modelData.isOn && pair.shown
            Rectangle {
                id: face
                anchors.fill: parent; anchors.margins: 2 * pair.u
                anchors.topMargin: (half.pressed ? 5 : 2) * pair.u
                anchors.bottomMargin: (half.pressed ? 1 : 4) * pair.u
                radius: 4 * pair.u
                readonly property bool isOn: modelData.isOn
                gradient: Gradient {
                    GradientStop { position: 0.0; color: half.glowing ? (face.isOn ? "#3a9a58" : "#8a7a58") : half.pressed ? "#242421" : (pair.hovered ? "#6a675d" : "#5c5a51") }
                    GradientStop { position: 0.25; color: half.glowing ? (face.isOn ? "#257a42" : "#5e5440") : (half.pressed ? "#20201d" : "#45433c") }
                    GradientStop { position: 1.0; color: half.glowing ? (face.isOn ? "#0e3a1f" : "#2e2a20") : (half.pressed ? "#1a1a17" : "#2c2b27") }
                }
                border.color: half.pressed ? "#0a0a09" : "#7a776c"; border.width: 1
                // highlight on the raised side, inner shadow on the sunk side
                Rectangle { x: 4 * pair.u; y: 1; width: parent.width - 8 * pair.u; height: 1; color: "white"; opacity: half.pressed ? 0.04 : 0.3 }
                Rectangle { anchors.top: parent.top; width: parent.width; height: 6 * pair.u; radius: parent.radius; visible: half.pressed
                            gradient: Gradient { GradientStop { position: 0; color: "#99000000" } GradientStop { position: 1; color: "#00000000" } } }
                Text {
                    anchors.centerIn: parent; anchors.verticalCenterOffset: half.pressed ? 1 * pair.u : -1 * pair.u
                    text: modelData.label
                    font.family: Theme.labelFont; font.weight: Font.Bold; font.pixelSize: 15 * pair.u; font.letterSpacing: 2 * pair.u
                    color: half.glowing ? (face.isOn ? "#eaffef" : "#fff3d6") : (pair.available ? "#d9d4c4" : "#6d6a60")
                }
            }
            Glow { target: face; color: modelData.isOn ? "#46ff82" : "#ffd27a"; spread: 16 * pair.u; radius: 4 * pair.u; intensity: half.glowing ? (modelData.isOn ? 0.55 : 0.35) : 0 }
        }
    }
    // pivot line + the shadow the raised half throws onto the sunk one
    Rectangle { x: pair.width / 2 - 1; y: 3 * pair.u; width: 2; height: pair.height - 6 * pair.u; color: "#080807" }
    Rectangle { x: pair.shown ? pair.width / 2 - 8 * pair.u : pair.width / 2 + 1; y: 4 * pair.u; width: 7 * pair.u; height: pair.height - 8 * pair.u
                gradient: Gradient { orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: pair.shown ? "#00000000" : "#88000000" }
                    GradientStop { position: 1; color: pair.shown ? "#88000000" : "#00000000" } } }
    Rectangle { anchors.fill: parent; radius: 5; color: "black"; opacity: pair.available ? 0 : 0.35 }
    PressArea {
        id: area
        anchors.fill: parent
        available: pair.available
        unavailableReason: pair.unavailableReason
        onActivated: { Theme.cue("toggle"); var v = !pair.shown; pair.pending = v ? 1 : 0; pendingTimer.restart(); pair.changed(v) }
        onDenied: (r) => pair.denied(r)
    }
}
