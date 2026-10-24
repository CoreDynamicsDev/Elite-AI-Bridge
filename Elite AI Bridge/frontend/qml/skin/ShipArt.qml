// Ship render on the CRT glass. Class art has a transparent background (useAlpha); older art
// drops its black background by luminance. alarm 0..1 pulls the picture toward red (shields down).
// motion: "" (still), "light", "medium", "large": a slow idle loop (bob, small roll, breathing,
// a glint along the hull once per loop). Heavier classes move slower and less.
import QtQuick
import "."

Item {
    id: art
    property url source
    property real alarm: 0
    property bool useAlpha: true
    property string motion: ""
    readonly property real paintedWidth: img.paintedWidth
    readonly property real paintedHeight: img.paintedHeight

    readonly property var amounts: ({ light: [2.4, 0.010, 1.0], medium: [1.6, 0.0075, 1.0], large: [0.9, 0.005, 1.0] })
    readonly property var amt: amounts[motion] || [0, 0, 0]
    property real phase: 0
    NumberAnimation on phase {
        from: 0; to: 2 * Math.PI; duration: 6000; loops: Animation.Infinite
        running: art.motion !== "" && art.visible
    }

    Image {
        id: img
        anchors.fill: parent
        source: art.source
        fillMode: Image.PreserveAspectFit
        asynchronous: true; smooth: true; mipmap: true
        sourceSize.width: 1024
        visible: false
    }
    ShaderEffect {
        id: fx
        visible: img.status === Image.Ready && String(art.source) !== ""
        x: (art.width - img.paintedWidth) / 2; y: (art.height - img.paintedHeight) / 2
        width: img.paintedWidth; height: img.paintedHeight
        property variant src: img
        property color tint: Theme.screen   // LAB themes: ship art follows the screen colour
        property color alarm: Theme.bad
        property real alarmAmt: art.alarm
        property real lo: 0.10
        property real hi: 0.30
        property real gain: 1.15
        property real useAlpha: art.useAlpha ? 1 : 0
        property real glintPos: art.motion !== "" ? (art.phase / (2 * Math.PI)) * 2.2 - 0.6 : -5
        property real glintAmt: art.motion !== "" ? 0.35 : 0
        transform: [
            Rotation { origin.x: fx.width / 2; origin.y: fx.height / 2; angle: art.amt[0] * Math.sin(art.phase) },
            Scale { origin.x: fx.width / 2; origin.y: fx.height / 2
                    xScale: 1 + art.amt[1] * Math.sin(art.phase); yScale: xScale },
            Translate { y: art.amt[0] > 0 ? art.height * 0.018 * art.amt[0] / 2.4 * Math.sin(art.phase + 0.6) : 0
                        x: art.amt[0] > 0 ? art.width * 0.004 * Math.sin(2 * art.phase) : 0 }
        ]
        fragmentShader: Qt.resolvedUrl("shaders/shipart.frag.qsb")
    }
}
