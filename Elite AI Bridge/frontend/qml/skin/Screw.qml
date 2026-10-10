import QtQuick
import "."

Item {
    property real slot: 20   // slot angle, vary per screw so they don't all line up
    implicitWidth: 16 * Theme.s; implicitHeight: 16 * Theme.s
    Rectangle {
        anchors.fill: parent; radius: width / 2
        border.color: "#22201c"; border.width: 1
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#b8b4a6" }
            GradientStop { position: 0.45; color: "#77736a" }
            GradientStop { position: 1.0; color: "#1c1b18" }
        }
    }
    Rectangle { anchors.centerIn: parent; width: parent.width * 0.75; height: Math.max(1.5, parent.height * 0.13); color: "#1a1916"; rotation: parent.slot }
}
