// Rhino surface drive for the Mining page (2026-10-28, rev 3). Same art as the Asteroid: phosphor body,
// etched lines, cyan rim, scan sweep. You look out of the Rhino's canopy at an endless moon surface
// (shaders/terrain.frag). Mining rigs stand beside the flat track, drilling: a beam down the shaft and
// ore glints rising out of the hole. The reticle locks on as you pass. All original line art.
// It always drives the same way; it doesn't react to the game (kept simple on purpose).
import QtQuick
import QtQuick.Shapes
import "."

Item {
    id: tr
    property bool running: visible
    clip: true

    readonly property var pal: ["#0c3d2c", "#45e07a", "#3ee8ff", "#ffd257"]

    // camera: eye 0.95 above the flat track, looking down 0.10, focal 1.25 (matches the shader)
    readonly property real eye: 0.95
    readonly property real focal: 1.25
    readonly property real spacing: 12          // a rig every 12 units, alternating sides
    readonly property real rigX: 1.75
    readonly property real speed: 2.6

    property real dist: 1
    FrameAnimation {
        running: tr.running
        onTriggered: tr.dist = (tr.dist + frameTime * tr.speed) % (tr.spacing * 1666)
    }
    property real sweepPos: 0
    property real sweepAmt: 0
    SequentialAnimation on sweepPos {
        loops: Animation.Infinite; running: tr.running
        PauseAnimation { duration: 2600 }
        PropertyAction { target: tr; property: "sweepAmt"; value: 1 }
        NumberAnimation { from: 0; to: 1.2; duration: 1800; easing.type: Easing.InOutQuad }
        PropertyAction { target: tr; property: "sweepAmt"; value: 0 }
    }
    // shared drill pulse and ore lift cycle for every rig
    property real drill: 0
    SequentialAnimation on drill {
        loops: Animation.Infinite; running: tr.running
        NumberAnimation { from: 0.35; to: 1; duration: 380; easing.type: Easing.OutQuad }
        NumberAnimation { to: 0.35; duration: 520; easing.type: Easing.InQuad }
    }
    property real lift: 0
    NumberAnimation on lift { from: 0; to: 1; duration: 1500; loops: Animation.Infinite; running: tr.running }

    ShaderEffect {
        id: fx
        anchors.fill: parent
        property color bodyColor: tr.pal[0]
        property color lineColor: tr.pal[1]
        property color rimColor: tr.pal[2]
        property color accentColor: tr.pal[3]
        property real t: tr.dist
        property real aspect: tr.width / Math.max(1, tr.height)
        property real pulse: 0
        property real sweepPos: tr.sweepPos
        property real sweepAmt: tr.sweepAmt
        property real lit: 1
        fragmentShader: Qt.resolvedUrl("shaders/terrain.frag.qsb")
    }

    // ---------------------------------------------------------------- rigs
    // Five slots ride along with the drive; each one is the rig number floor(dist/spacing)+index.
    // Rig art is drawn in a 100 x 100 box (100 = one world unit), origin at the foot of the shaft.
    Repeater {
        model: 5
        Item {
            id: rig
            required property int index
            readonly property int n: Math.floor(tr.dist / tr.spacing) + index
            readonly property real wz: n * tr.spacing + tr.spacing / 2
            readonly property real dz: wz - tr.dist
            readonly property real wx: (n % 2 === 0 ? 1 : -1) * tr.rigX
            readonly property real k: tr.focal / Math.max(0.3, dz)          // screen units per world unit
            readonly property real px: tr.height * k                          // pixels per world unit
            readonly property real fog: Math.exp(-dz * 0.05)
            readonly property real lock: Math.max(0, Math.min(1, (24 - dz) / 5)) * Math.max(0, Math.min(1, (dz - 6) / 2))
            visible: dz > 1.2 && dz < 46
            z: 100 - dz
            opacity: Math.min(1, (46 - dz) / 8) * Math.min(1, (dz - 1.2) / 0.8)
            // foot of the shaft on screen
            x: tr.width / 2 + wx * k * tr.height
            y: tr.height * (0.5 - (-tr.eye * k + 0.10))

            Item {
                id: art
                width: 100; height: 100
                x: -50; y: -100
                scale: rig.px / 100
                transformOrigin: Item.Bottom
                readonly property real sw: 1.6 / Math.max(0.01, scale)
                readonly property color line: Qt.rgba(tr.pal[1].r, tr.pal[1].g, tr.pal[1].b, 0.35 + 0.65 * rig.fog)
                readonly property color body: tr.pal[0]

                // dark hole in the ground with a lit rim
                Rectangle { x: 28; y: 94; width: 44; height: 10; radius: 5; color: Qt.rgba(0.01, 0.04, 0.03, 0.85); border.width: art.sw; border.color: art.line }
                // drill beam down the shaft into the hole
                Rectangle {
                    x: 50 - width / 2; y: 34; width: 10; height: 66; radius: 5
                    opacity: tr.drill * (0.5 + 0.5 * rig.fog)
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.rgba(tr.pal[2].r, tr.pal[2].g, tr.pal[2].b, 0.0) }
                        GradientStop { position: 0.5; color: Qt.rgba(tr.pal[2].r, tr.pal[2].g, tr.pal[2].b, 0.55) }
                        GradientStop { position: 1; color: tr.pal[2] }
                    }
                }
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    // tripod: two side legs and a back leg, to an apex above the housing
                    ShapePath {
                        strokeColor: art.line; strokeWidth: art.sw; fillColor: "transparent"
                        capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                        startX: 8; startY: 100; PathLine { x: 50; y: 4 } PathLine { x: 92; y: 100 }
                        PathMove { x: 50; y: 4 } PathLine { x: 58; y: 90 }
                        PathMove { x: 22; y: 70 } PathLine { x: 78; y: 70 }
                    }
                    // drill housing and shaft
                    ShapePath {
                        strokeColor: art.line; strokeWidth: art.sw; fillColor: art.body
                        joinStyle: ShapePath.MiterJoin
                        startX: 36; startY: 18
                        PathLine { x: 64; y: 18 } PathLine { x: 64; y: 40 } PathLine { x: 56; y: 46 }
                        PathLine { x: 44; y: 46 } PathLine { x: 36; y: 40 } PathLine { x: 36; y: 18 }
                    }
                    ShapePath {
                        strokeColor: art.line; strokeWidth: art.sw; fillColor: "transparent"
                        startX: 40; startY: 28; PathLine { x: 60; y: 28 }
                        PathMove { x: 47; y: 46 } PathLine { x: 47; y: 98 }
                        PathMove { x: 53; y: 46 } PathLine { x: 53; y: 98 }
                    }
                }
                // beacon on the apex
                Rectangle { x: 50 - width / 2; y: 0; width: 7; height: 7; radius: 3.5
                            color: tr.pal[3]; opacity: 0.3 + 0.7 * tr.drill }
                // ore glints lifting out of the hole
                Repeater {
                    model: 3
                    Rectangle {
                        required property int index
                        readonly property real ph: (tr.lift + index / 3) % 1
                        width: 6; height: 6; rotation: 45
                        x: 50 - 3 + Math.sin((ph + index) * 6.28) * 12
                        y: 94 - ph * 46
                        color: tr.pal[3]
                        opacity: (1 - ph) * (0.4 + 0.6 * rig.fog)
                    }
                }
            }

            // lock-on brackets: close in as the rig comes up beside you
            Item {
                id: brk
                visible: rig.lock > 0
                readonly property real sz: Math.max(18, rig.px * 1.25)
                readonly property real gap: sz * (0.62 - 0.12 * rig.lock)
                readonly property real arm: sz * 0.22
                readonly property color c: tr.pal[2]
                x: -width / 2; y: -rig.px * 0.5 - height / 2
                width: sz; height: sz
                opacity: rig.lock
                Repeater {
                    model: 4
                    Item {
                        required property int index
                        readonly property int sx2: index % 2 === 0 ? -1 : 1
                        readonly property int sy2: index < 2 ? -1 : 1
                        x: brk.width / 2 + sx2 * brk.gap; y: brk.height / 2 + sy2 * brk.gap
                        Rectangle { x: parent.sx2 < 0 ? 0 : -brk.arm; y: parent.sy2 < 0 ? 0 : -2; width: brk.arm; height: 2; color: brk.c }
                        Rectangle { x: parent.sx2 < 0 ? 0 : -2; y: parent.sy2 < 0 ? 0 : -brk.arm; width: 2; height: brk.arm; color: brk.c }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- canopy
    // the view is from the Rhino's cab: two canopy pillars, the dash edge and a small HUD reticle
    Shape {
        id: canopy
        anchors.fill: parent
        z: 200
        preferredRendererType: Shape.CurveRenderer
        readonly property real cw: width
        readonly property real ch: height
        readonly property color frame: Qt.rgba(0.02, 0.05, 0.04, 0.96)
        readonly property color edge: Qt.rgba(tr.pal[1].r, tr.pal[1].g, tr.pal[1].b, 0.55)
        // left pillar
        ShapePath {
            fillColor: canopy.frame; strokeColor: canopy.edge; strokeWidth: 1.5
            startX: -2; startY: canopy.ch * 0.80
            PathLine { x: canopy.cw * 0.035; y: -2 }
            PathLine { x: -2; y: -2 }
        }
        // right pillar
        ShapePath {
            fillColor: canopy.frame; strokeColor: canopy.edge; strokeWidth: 1.5
            startX: canopy.cw + 2; startY: canopy.ch * 0.80
            PathLine { x: canopy.cw * 0.965; y: -2 }
            PathLine { x: canopy.cw + 2; y: -2 }
        }
        // dash: a low curved cowl across the bottom
        ShapePath {
            fillColor: canopy.frame; strokeColor: canopy.edge; strokeWidth: 1.5
            startX: -2; startY: canopy.ch * 0.86
            PathQuad { x: canopy.cw + 2; y: canopy.ch * 0.86; controlX: canopy.cw / 2; controlY: canopy.ch * 0.80 }
            PathLine { x: canopy.cw + 2; y: canopy.ch + 2 }
            PathLine { x: -2; y: canopy.ch + 2 }
        }
    }
    // dash readouts: little lit ticks, the middle ones show the drive
    Row {
        z: 201
        anchors.horizontalCenter: parent.horizontalCenter
        y: tr.height * 0.895
        spacing: Math.max(3, tr.width * 0.012)
        Repeater {
            model: 9
            Rectangle {
                required property int index
                width: Math.max(3, tr.width * 0.018); height: Math.max(2, tr.height * 0.018)
                color: index === 4 ? tr.pal[3] : tr.pal[1]
                opacity: Math.abs(index - 4) <= 1 + 3 * tr.drill ? 0.85 : 0.2
            }
        }
    }
    // HUD reticle, faint, on the horizon line
    Item {
        z: 199
        x: tr.width / 2; y: tr.height * 0.40
        opacity: 0.45
        readonly property real r: Math.max(6, tr.height * 0.035)
        Rectangle { x: -parent.r; y: -parent.r; width: parent.r * 2; height: width; radius: parent.r
                    color: "transparent"; border.width: 1.2; border.color: tr.pal[2] }
        Rectangle { x: -parent.r * 2.2; y: -0.6; width: parent.r * 0.9; height: 1.2; color: tr.pal[2] }
        Rectangle { x: parent.r * 1.3; y: -0.6; width: parent.r * 0.9; height: 1.2; color: tr.pal[2] }
    }
}
