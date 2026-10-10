// Round panel lamp: domed glass lens in a metal bezel, with light spilling onto the panel.
// lit: "g" green, "a" amber, "r" red, "w" white, "" off. Size = the lens; the glow draws outside it.
import QtQuick
import "."

Item {
    id: lamp
    property string lit: "g"
    implicitWidth: 30; implicitHeight: 30
    readonly property bool on: lit !== ""
    readonly property color coreColor: lit === "g" ? "#7dffa0" : lit === "a" ? "#ffc44d" : lit === "r" ? "#ff5a46" : lit === "w" ? "#eef3ff" : "#3a4a3c"
    readonly property color deepColor: lit === "g" ? "#13893a" : lit === "a" ? "#b86a08" : lit === "r" ? "#8e1a12" : lit === "w" ? "#8a97b5" : "#121411"
    property real level: on ? 1 : 0
    Behavior on level { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }   // filament warm-up / cool-down
    property bool breathe: false             // slow "breathing" (TIP key only); a whole cycle per loop, no seam
    property real breath: 1
    SequentialAnimation on breath {
        running: lamp.breathe && lamp.visible; loops: Animation.Infinite
        NumberAnimation { from: 1; to: 0.3; duration: 1600; easing.type: Easing.InOutSine }
        NumberAnimation { from: 0.3; to: 1; duration: 1600; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) lamp.breath = 1
    }

    ShaderEffect {
        anchors.centerIn: parent
        width: lamp.width * 3.2; height: lamp.height * 3.2
        property color core: lamp.on ? lamp.coreColor : "#3a4a3c"
        property color deep: lamp.on ? lamp.deepColor : "#121411"
        property real lit: lamp.level * (lamp.breathe ? lamp.breath : 1)
        property real px: 2.0 / Math.max(1, width)
        fragmentShader: Qt.resolvedUrl("shaders/lamp.frag.qsb")
    }
}
