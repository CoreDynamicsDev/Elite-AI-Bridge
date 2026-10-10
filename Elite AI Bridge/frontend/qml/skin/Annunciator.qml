// Backlit warning tile. lit: "" dark (all fine), "a" amber, "r" red.
import QtQuick
import "."

Item {
    id: tile
    property string text: ""
    property string lit: ""
    implicitWidth: 180; implicitHeight: 48
    Rectangle {
        anchors.fill: parent; radius: 3
        border.color: "#000"; border.width: 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: tile.lit === "a" ? "#ffd27a" : tile.lit === "r" ? "#ff8a74" : "#23231f" }
            GradientStop { position: 0.55; color: tile.lit === "a" ? "#e09a24" : tile.lit === "r" ? "#d43a2a" : "#1a1a17" }
            GradientStop { position: 1.0; color: tile.lit === "a" ? "#8a5410" : tile.lit === "r" ? "#7a1810" : "#121210" }
        }
    }
    Glow { target: tile; color: tile.lit === "r" ? "#ff5040" : "#ffaa28"; spread: 26 * Theme.s; radius: 3; intensity: tile.lit !== "" ? 0.75 : 0 }
    Text {
        anchors.centerIn: parent; width: parent.width - 10; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
        text: tile.text.toUpperCase()
        font.family: Theme.labelFont; font.weight: Font.Bold; font.pixelSize: Math.max(10, parent.height * 0.3); font.letterSpacing: 2
        color: tile.lit === "a" ? "#2a1a05" : tile.lit === "r" ? "#2a0805" : "#55524a"
    }
}
