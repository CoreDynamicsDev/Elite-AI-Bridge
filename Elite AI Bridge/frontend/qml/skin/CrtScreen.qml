// One CRT screen: dark phosphor glass + the retro shader (build step 1, approved 2026-10-07).
// Content goes inside and is drawn flat; the shader adds the look.
// Levels come from Theme (Setup > Display faders). Both 0 = no shader at all, no GPU cost.
import QtQuick
import "."

Item {
    id: crt
    property real staticAmt: Theme.crtStatic
    property real fxAmt: Theme.crtScreenFx
    property real radius: 18
    default property alias content: holder.data
    readonly property bool effectsOn: staticAmt > 0.001 || fxAmt > 0.001
    readonly property string shaderStatus: fx.status === ShaderEffect.Compiled ? "OK"
                                         : (fx.status === ShaderEffect.Error ? "ERROR: " + fx.log : "LOADING")
    clip: true

    Item {
        id: flat
        anchors.fill: parent
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.glassTop }
                GradientStop { position: 0.55; color: Theme.glassMid }
                GradientStop { position: 1.0; color: Theme.glassEdge }
            }
        }
        Item { id: holder; anchors.fill: parent }
    }

    ShaderEffectSource {
        id: tex
        sourceItem: crt.effectsOn ? flat : null
        hideSource: crt.effectsOn
        live: crt.effectsOn
        visible: false
    }
    ShaderEffect {
        id: fx
        anchors.fill: parent
        visible: crt.effectsOn
        property variant src: tex
        property real time: 0
        property real staticAmt: crt.staticAmt
        property real fxAmt: crt.fxAmt
        property vector4d phos: Theme.amber ? Qt.vector4d(1.0, 0.69, 0.16, 1.0) : Qt.vector4d(0.45, 1.0, 0.55, 1.0)   // LAB themes
        property vector2d res: Qt.vector2d(Math.max(1, width * Screen.devicePixelRatio), Math.max(1, height * Screen.devicePixelRatio))
        fragmentShader: Qt.resolvedUrl("shaders/crt.frag.qsb")
    }
    FrameAnimation {
        running: crt.effectsOn && crt.visible
        onTriggered: fx.time += frameTime
    }
    // glass reflection (on top of the effect, not part of the picture)
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: "#14ffffff" }
            GradientStop { position: 0.35; color: "#00ffffff" }
        }
    }
}
