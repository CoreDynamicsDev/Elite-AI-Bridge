// Dymo-style tooltip: line 1 what it does, line 2 binding or why it's unavailable.
import QtQuick
import "."

Item {
    id: tip
    property string text: ""
    property string detail: ""
    property bool shown: false
    visible: opacity > 0
    opacity: shown && text !== "" ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 90 } }
    width: col.implicitWidth + 28 * Theme.s; height: col.implicitHeight + 16 * Theme.s
    z: 100
    Rectangle { anchors.fill: parent; color: "#141414"; radius: 2; border.color: "#000"; border.width: 1
        Image { anchors.fill: parent; source: "textures/tex_tape.png"; fillMode: Image.Tile; opacity: 0.8 } }
    Column {
        id: col; x: 14 * Theme.s; y: 8 * Theme.s; spacing: 2 * Theme.s
        Text { text: tip.text.toUpperCase(); color: Theme.tapeText; font.family: Theme.labelFont; font.weight: Font.DemiBold; font.pixelSize: Math.max(10, 15 * Theme.s); font.letterSpacing: 2 * Theme.s }
        Text { visible: tip.detail !== ""; text: tip.detail.toUpperCase(); color: Theme.tapeText; opacity: 0.7; font.family: Theme.labelFont; font.pixelSize: Math.max(9, 13 * Theme.s); font.letterSpacing: 2 * Theme.s }
    }
}
