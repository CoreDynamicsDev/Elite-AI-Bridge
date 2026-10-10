// Moulded bezel around a CRT screen.
import QtQuick
import "."

Item {
    id: bezel
    property real pad: 16 * Theme.s
    property alias screen: glass
    default property alias content: glass.content
    Rectangle { x: -3 * Theme.s; y: -3 * Theme.s; width: parent.width + 6 * Theme.s; height: parent.height + 6 * Theme.s; radius: 16 * Theme.s; color: "#0b0b0a" }
    Rectangle {
        anchors.fill: parent; radius: 14 * Theme.s
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: "#3a3a35" }
            GradientStop { position: 0.4; color: "#1d1d1a" }
            GradientStop { position: 1.0; color: "#121210" }
        }
        Rectangle { x: 6; y: 1; width: parent.width - 12; height: 2; radius: 1; color: "white"; opacity: 0.12 }
    }
    CrtScreen { id: glass; anchors.fill: parent; anchors.margins: bezel.pad }
}
