// Soft light spill around a lit shape. Put it behind the lit item with the same geometry.
import QtQuick
import "."

ShaderEffect {
    id: glow
    property Item target: parent
    property color color: Theme.ok
    property real spread: 22
    property real radius: 4
    property real intensity: 0.7
    property vector2d size: Qt.vector2d(width, height)
    x: target ? -spread : 0; y: target ? -spread : 0
    width: (target ? target.width : 0) + spread * 2
    height: (target ? target.height : 0) + spread * 2
    visible: intensity > 0.001
    z: -1
    fragmentShader: Qt.resolvedUrl("shaders/glow.frag.qsb")
}
