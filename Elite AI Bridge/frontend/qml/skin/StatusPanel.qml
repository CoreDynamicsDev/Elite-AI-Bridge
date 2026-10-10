// Annunciator panel (approved controls_mockup_v1.png): warning tiles in their own recessed glass
// panel (2 rows), labelled STATUS, so they never look like buttons. No hover, no cursor.
import QtQuick
import "."

Item {
    id: sp
    property var items: []          // [[text, lit], ...]  lit: "" / "a" / "r"
    property int columns: 4
    readonly property real u: Theme.s
    readonly property int rows: Math.ceil(items.length / columns)
    Text {
        id: lab
        anchors.verticalCenter: parent.verticalCenter
        text: "STATUS"; color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: Math.max(8, 13 * sp.u); font.letterSpacing: 3 * sp.u
    }
    Rectangle {
        id: well
        x: lab.width + 14 * sp.u; width: parent.width - x; height: parent.height
        radius: 4 * sp.u; color: "#070807"; border.color: "#3e3b32"; border.width: 1
        // inner shadow: the panel sits behind the plate
        Rectangle { anchors.fill: parent; radius: parent.radius
                    gradient: Gradient { GradientStop { position: 0; color: "#cc000000" } GradientStop { position: 0.18; color: "#00000000" } } }
        Grid {
            id: grid
            anchors.fill: parent; anchors.margins: 5 * sp.u
            columns: sp.columns; spacing: 3 * sp.u
            Repeater {
                model: sp.items
                Item {
                    width: (grid.width - grid.spacing * (sp.columns - 1)) / sp.columns
                    height: (grid.height - grid.spacing * (sp.rows - 1)) / sp.rows
                    readonly property string lit: modelData[1]
                    Rectangle {
                        id: glass
                        anchors.fill: parent; radius: 1
                        color: parent.lit === "a" ? "#e3a02c" : (parent.lit === "r" ? "#d8402e" : "#141512")
                        border.color: "#000"; border.width: 1
                        Rectangle { anchors.fill: parent; anchors.margins: 1; visible: parent.parent.lit !== ""
                                    gradient: Gradient { GradientStop { position: 0; color: "#55ffffff" } GradientStop { position: 0.5; color: "#00ffffff" } } }
                    }
                    Glow { target: glass; color: parent.lit === "r" ? "#ff5040" : "#ffaa28"; spread: 14 * sp.u; radius: 2; intensity: parent.lit !== "" ? 0.6 : 0 }
                    Text {
                        anchors.centerIn: parent; width: parent.width - 6; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                        text: String(modelData[0]).toUpperCase()
                        font.family: Theme.labelFont; font.weight: Font.Bold; font.pixelSize: Math.max(8, parent.height * 0.48); font.letterSpacing: 1.5 * sp.u
                        color: parent.lit === "a" ? "#2a1a05" : (parent.lit === "r" ? "#2a0805" : "#4a4840")
                    }
                }
            }
        }
    }
}
