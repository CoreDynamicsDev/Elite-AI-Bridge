// Asteroid for the Mining page (2026-10-25, v3). One original still render (make_asteroid.py,
// skin/textures/asteroid_rock.png) moved live at full frame rate: a slow spin, a gentle tilt that
// fakes turning, fragments drifting off, and a targeting reticle that hops between spots on the
// surface and locks on. verdict sets the colours: MINE green, MAYBE amber, SKIP dim, CORE gold
// with the crack line pulsing, "" plain scanner green.
// scan(): a scan band sweeps across once (new prospector result). checking: keeps sweeping.
import QtQuick
import "."

Item {
    id: rock
    property string verdict: ""
    property bool running: visible
    property int seq: 0
    property bool checking: false
    onSeqChanged: scan()

    readonly property var palettes: ({
        MINE:  ["#0c3d2c", "#54ff86", "#3ee8ff", "#ffd257"],
        MAYBE: ["#3d2c0c", "#ffb547", "#ffd27a", "#ffd257"],
        SKIP:  ["#1e2622", "#5d6b64", "#71807a", "#ffd257"],
        CORE:  ["#3d300c", "#ffd257", "#ffe9a0", "#fff1b8"],
        "":    ["#0c3d2c", "#45e07a", "#3ee8ff", "#ffd257"]
    })
    readonly property var pal: palettes[verdict] || palettes[""]
    readonly property real side: Math.min(width, height) * 1.15

    // spots on the rock the reticle visits (fractions of the image, from make_asteroid.py)
    readonly property var spots: [[-0.176, 0.199], [0.029, -0.074], [-0.084, 0.086], [0.221, -0.021],
                                  [0.141, -0.211], [0.117, 0.08], [-0.264, 0.0]]

    function scan() { sweepAnim.restart() }
    Timer { interval: 1400; repeat: true; running: rock.checking && rock.running; onTriggered: rock.scan() }

    property real spin: 0
    NumberAnimation on spin { from: 0; to: 360; duration: 90000; loops: Animation.Infinite; running: rock.running }
    property real phase: 0
    NumberAnimation on phase { from: 0; to: 1; duration: 14000; loops: Animation.Infinite; running: rock.running }
    property real pulse: 0
    SequentialAnimation on pulse {
        loops: Animation.Infinite; running: rock.running && (rock.verdict === "CORE" || rock.verdict === "MINE")
        NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0; duration: 900; easing.type: Easing.InOutSine }
    }
    property real sweepPos: -1
    property real sweepAmt: 0
    SequentialAnimation {
        id: sweepAnim
        PropertyAction { target: rock; property: "sweepAmt"; value: 1 }
        NumberAnimation { target: rock; property: "sweepPos"; from: -0.1; to: 1.1; duration: 1100; easing.type: Easing.InOutQuad }
        PropertyAction { target: rock; property: "sweepAmt"; value: 0 }
    }

    // fragments drifting off (behind the rock)
    Repeater {
        model: 5
        Rectangle {
            required property int index
            readonly property real p: (rock.phase * 1.6 + index / 5) % 1
            readonly property real ang: index * 1.37 + 0.4
            readonly property real dist: rock.side * (0.30 + 0.32 * p)
            width: Math.max(2, rock.side * (0.014 + 0.007 * (index % 2))); height: width
            rotation: p * 220 + index * 40
            x: rock.width / 2 + Math.cos(ang) * dist - width / 2
            y: rock.height / 2 + Math.sin(ang) * dist * 0.8 - height / 2
            color: rock.pal[1]
            opacity: p < 0.15 ? p / 0.15 * 0.75 : 0.75 * (1 - (p - 0.15) / 0.85)
        }
    }

    Image {
        id: img
        source: "textures/asteroid_rock.png"
        visible: false
        asynchronous: true; smooth: true; mipmap: true
    }

    // the rock and its reticle move together
    Item {
        id: body
        width: rock.side; height: rock.side
        x: (rock.width - width) / 2; y: (rock.height - height) / 2
        transform: [
            Rotation { origin.x: body.width / 2; origin.y: body.height / 2; angle: rock.spin },
            Rotation { origin.x: body.width / 2; origin.y: body.height / 2; axis { x: 0; y: 1; z: 0 }
                       angle: 16 * Math.sin(rock.phase * 2 * Math.PI) },
            Rotation { origin.x: body.width / 2; origin.y: body.height / 2; axis { x: 1; y: 0; z: 0 }
                       angle: 9 * Math.sin(rock.phase * 4 * Math.PI + 1.0) },
            Translate { y: body.height * 0.012 * Math.sin(rock.phase * 6 * Math.PI) }
        ]
        ShaderEffect {
            anchors.fill: parent
            visible: img.status === Image.Ready
            property variant atlas: img
            property color bodyColor: rock.pal[0]
            property color lineColor: rock.pal[1]
            property color rimColor: rock.pal[2]
            property color crackColor: rock.pal[3]
            property real frame: 0
            property real cols: 1
            property real rows: 1
            property real cell: img.sourceSize.width > 0 ? img.sourceSize.width : 512
            property real crackAmt: rock.verdict === "CORE" ? 1 : 0
            property real sweepPos: rock.sweepPos
            property real sweepAmt: rock.sweepAmt
            property real pulse: rock.pulse
            Behavior on bodyColor { ColorAnimation { duration: 500 } }
            Behavior on lineColor { ColorAnimation { duration: 500 } }
            Behavior on rimColor { ColorAnimation { duration: 500 } }
            fragmentShader: Qt.resolvedUrl("shaders/rock.frag.qsb")
        }

        // targeting reticle: glides to a spot, locks (brackets close in, centre blinks), holds, moves on
        Item {
            id: reticle
            property int spot: 0
            property real lock: 0
            readonly property real sz: rock.side * 0.11
            width: sz; height: sz
            x: body.width * (0.5 + rock.spots[spot][0]) - width / 2
            y: body.height * (0.5 + rock.spots[spot][1]) - height / 2
            Behavior on x { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
            Behavior on y { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
            rotation: -rock.spin       // stays upright while the rock turns
            readonly property real gap: sz * (0.5 - 0.22 * lock)
            readonly property real arm: sz * 0.28
            readonly property color c: rock.pal[2]
            Repeater {
                model: 4
                Item {
                    required property int index
                    readonly property int sx: index % 2 === 0 ? -1 : 1
                    readonly property int sy: index < 2 ? -1 : 1
                    x: reticle.width / 2 + sx * reticle.gap; y: reticle.height / 2 + sy * reticle.gap
                    Rectangle { x: parent.sx < 0 ? 0 : -reticle.arm; y: parent.sy < 0 ? 0 : -2; width: reticle.arm; height: 2; color: reticle.c }
                    Rectangle { x: parent.sx < 0 ? 0 : -2; y: parent.sy < 0 ? 0 : -reticle.arm; width: 2; height: reticle.arm; color: reticle.c }
                }
            }
            Rectangle { anchors.centerIn: parent; width: Math.max(3, reticle.sz * 0.08); height: width; radius: width / 2
                        color: reticle.c; opacity: reticle.lock > 0.95 ? reticle.blink : 0.25 }
            property real blink: 1
            SequentialAnimation on blink {
                loops: Animation.Infinite; running: rock.running
                NumberAnimation { to: 0.2; duration: 260 }
                NumberAnimation { to: 1; duration: 260 }
            }
            SequentialAnimation {
                id: hop
                loops: Animation.Infinite; running: rock.running
                PropertyAction { target: reticle; property: "lock"; value: 0 }
                ScriptAction { script: reticle.spot = (reticle.spot + 1 + Math.floor(Math.random() * (rock.spots.length - 1))) % rock.spots.length }
                PauseAnimation { duration: 650 }
                NumberAnimation { target: reticle; property: "lock"; to: 1; duration: 280; easing.type: Easing.OutBack }
                PauseAnimation { duration: 1700 }
            }
        }
    }
}
