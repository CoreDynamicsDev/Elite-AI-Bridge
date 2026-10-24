// Shield halo ring. Use two: one behind the ship art (frontHalf: false, also draws the faint dome)
// and one over it (frontHalf: true). shield: "UP", "DOWN" or anything else = unknown.
import QtQuick
import "."

ShaderEffect {
    id: halo
    property string shield: "UNKNOWN"
    property bool frontHalf: false
    property vector2d centerAt: Qt.vector2d(0.5, 0.6)
    property vector2d ringRadii: Qt.vector2d(0.46, 0.17)
    property real dome: 0.40
    property color color: shield === "UP" ? Theme.screen : (shield === "DOWN" ? Theme.bad : Theme.dimText)
    property vector2d size: Qt.vector2d(width, height)
    property vector2d center: centerAt
    property vector2d radii: ringRadii
    property real domeRy: dome
    property real lineW: Math.max(1.2, 2.2 * Theme.s)
    property real time: 0
    property real mode: shield === "UP" ? 0 : (shield === "DOWN" ? 1 : 2)
    property real front: frontHalf ? 1 : 0
    fragmentShader: Qt.resolvedUrl("shaders/halo.frag.qsb")
    FrameAnimation { running: halo.visible; onTriggered: halo.time += frameTime }
}
