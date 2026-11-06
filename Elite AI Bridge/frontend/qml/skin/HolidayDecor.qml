// Holiday decorations (2026-11-05). One engine for every holiday: the pack in
// holidays/Packs.js names the art, this file places and moves it. Decoration only: it
// never reacts to the game and stays off the in-game overlay. The only clicks it takes
// are the easter eggs: the props themselves, and five taps on the header title.
//   - garlands along the header top edge and the module column top edge
//   - a few props on the module column (top edge and bottom corner)
//   - a falling layer over the whole window that fades in and out at the edges, so a
//     leaf or flake never pops in or vanishes where you can see it
import QtQuick
import QtQuick.Shapes
import "."
import "holidays/Packs.js" as Packs

Item {
    id: hd
    property string packName: ""
    // easter egg: five taps on the ELITE AI BRIDGE title within 3 s (this session only)
    property string secretPack: ""
    signal secretToggled(bool on)
    property int _taps: 0
    Timer { id: tapTimer; interval: 3000; onTriggered: hd._taps = 0 }
    function titleTap() {
        if (!tapTimer.running) _taps = 0
        _taps += 1; tapTimer.restart()
        if (_taps >= 5) {
            _taps = 0; tapTimer.stop()
            secretPack = secretPack === "" ? "LOST_CARGO" : ""
            if (secretPack !== "") sound("secret")
            secretToggled(secretPack !== "")
        }
    }
    function sound(n) { if (typeof bridge !== "undefined" && bridge && bridge.playDecorSound) bridge.playDecorSound(n) }
    readonly property string shownPack: secretPack !== "" ? secretPack : packName
    readonly property var pack: shownPack !== "" ? Packs.PACKS[shownPack] : null
    // each holiday has its own click sound (frontend/sounds); the turkey always gobbles
    readonly property string clickSound: pack && pack.sound ? pack.sound : "pop"
    property bool running: visible
    property real s: Theme.s
    // where the chassis parts are (set by Main.qml)
    property rect headerRect: Qt.rect(0, 0, 0, 0)
    property rect navRect: Qt.rect(0, 0, 0, 0)
    property real titleEnd: 0.245           // header fraction taken by the ELITE AI BRIDGE title
    property real navLabelEnd: 0.56         // module column fraction taken by MODULE SELECT
    visible: pack !== null

    function art(name) { return Qt.resolvedUrl("holidays/art/" + name + ".svg") }
    // small deterministic random so a pack always looks the same
    function rnd(i, k) { var x = Math.sin(i * 12.9898 + k * 78.233) * 43758.5453; return x - Math.floor(x) }

    // ---------------------------------------------------------------- garland
    component Garland: Item {
        id: g
        property real x1: 0
        property real x2: 100
        property real y0: 0
        property real sag: 8
        property int seed: 0
        readonly property var gp: hd.pack ? hd.pack.garland : null
        readonly property bool bulbs: gp && gp.kind === "bulbs"
        readonly property real step: gp ? gp.step * hd.s : 20
        readonly property int count: gp ? Math.max(2, Math.floor((x2 - x1) / step)) : 0
        function px(t) { return x1 + (x2 - x1) * t }
        function py(t) { return y0 + sag * 4 * t * (1 - t) }
        Shape {
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: g.bulbs ? "#1a1d17" : "#3a2412"; strokeWidth: Math.max(1, 2 * hd.s); fillColor: "transparent"
                startX: g.x1; startY: g.y0
                PathQuad { x: g.x2; y: g.y0; controlX: (g.x1 + g.x2) / 2; controlY: g.y0 + g.sag * 2 }
            }
        }
        Repeater {
            model: g.count
            Image {
                id: bit
                required property int index
                readonly property real t: (index + 0.5) / g.count
                readonly property real sz: g.gp.size * hd.s * (g.bulbs ? 1 : 0.8 + 0.4 * hd.rnd(index, g.seed))
                source: hd.art(g.gp.art[(index + g.seed) % g.gp.art.length])
                width: sz; height: sz; sourceSize.width: Math.ceil(sz * 2); sourceSize.height: Math.ceil(sz * 2)
                smooth: true
                x: g.px(t) - width / 2
                y: g.py(t) - (g.bulbs ? height * 0.08 : height * 0.25)
                transformOrigin: Item.Top
                rotation: (hd.rnd(index, g.seed + 3) - 0.5) * (g.bulbs ? 24 : 70)
                // bulbs twinkle slowly; leaves sway a little
                SequentialAnimation on opacity {
                    running: hd.running && g.bulbs; loops: Animation.Infinite
                    PauseAnimation { duration: 400 + 3000 * hd.rnd(bit.index, 7) }
                    NumberAnimation { to: 0.45; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
                }
                SequentialAnimation on rotation {
                    running: hd.running && !g.bulbs; loops: Animation.Infinite
                    NumberAnimation { to: bit.rotation + 9; duration: 1800 + 1400 * hd.rnd(bit.index, 9); easing.type: Easing.InOutSine }
                    NumberAnimation { to: bit.rotation - 9; duration: 1800 + 1400 * hd.rnd(bit.index, 11); easing.type: Easing.InOutSine }
                }
            }
        }
    }

    // ---------------------------------------------------------------- props
    // A prop stands on its bottom centre (px, py). Click one: the turkey gobbles and struts,
    // a present (or heart box, popper, ghost, pot of gold) pops and comes back, anything else hops.
    component Prop: Item {
        id: pr
        property string name: ""
        property real size: 40
        property real px: 0
        property real py: 0
        property int seed: 0
        property real walk: 0          // turkey strut offset
        property real face: 1          // 1 = facing right, -1 = left
        property real hop: 0           // hop height
        property real burst: 0         // present pop, 0..1
        readonly property bool isTurkey: name === "turkey"
        // these pop open with sparkles when clicked
        readonly property bool isPresent: name.indexOf("present") === 0 || name === "heart_box" || name === "popper" || name === "ghost" || name === "pot_of_gold"
        width: size; height: size
        z: isTurkey ? 2 : 1
        x: px - width / 2 + walk; y: py - height - hop
        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (pr.isTurkey) { if (!strut.running) { hd.sound("gobble"); strut.start() } }
                else if (pr.isPresent) { if (!popAnim.running) { hd.sound(hd.clickSound); popAnim.start() } }
                else if (!hopAnim.running) { hd.sound(hd.clickSound); hopAnim.start() }
            }
        }
        SequentialAnimation {
            id: hopAnim
            NumberAnimation { target: pr; property: "hop"; to: pr.size * 0.35; duration: 160; easing.type: Easing.OutQuad }
            NumberAnimation { target: pr; property: "hop"; to: 0; duration: 220; easing.type: Easing.OutBounce }
        }
        SequentialAnimation {
            id: popAnim
            NumberAnimation { target: pr; property: "burst"; from: 0; to: 1; duration: 650; easing.type: Easing.OutQuad }
            PauseAnimation { duration: 2600 }
            PropertyAction { target: pr; property: "burst"; value: 0 }
        }
        // gentle wobble for everything but the turkey (it has its own moves)
        Image {
            id: plain
            visible: !pr.isTurkey
            anchors.fill: parent
            source: visible ? hd.art(pr.name) : ""
            sourceSize.width: Math.ceil(pr.size * 2); sourceSize.height: Math.ceil(pr.size * 2)
            smooth: true
            transformOrigin: Item.Bottom
            // a popped present grows, then fades away; it fades back in when the pop is over
            scale: pr.burst > 0 ? 1 + 0.35 * Math.min(1, pr.burst * 3) : 1
            opacity: pr.burst > 0 ? Math.max(0, 1 - pr.burst * 2.5) : 1
            Behavior on opacity { enabled: pr.burst === 0; NumberAnimation { duration: 500 } }
            SequentialAnimation on rotation {
                running: hd.running && plain.visible; loops: Animation.Infinite
                NumberAnimation { to: 5; duration: 1500 + 900 * hd.rnd(pr.seed, 1); easing.type: Easing.InOutSine }
                NumberAnimation { to: -5; duration: 1500 + 900 * hd.rnd(pr.seed, 2); easing.type: Easing.InOutSine }
            }
        }
        // sparkles out of a popped present
        Repeater {
            model: pr.isPresent ? 8 : 0
            Rectangle {
                required property int index
                readonly property real a: index / 8 * 6.283 + 0.4
                visible: pr.burst > 0
                width: pr.size * 0.16; height: width; rotation: 45
                color: index % 2 === 0 ? "#ffd257" : "#f4f1e6"
                x: pr.width / 2 - width / 2 + Math.cos(a) * pr.size * 1.1 * pr.burst
                y: pr.height * 0.45 - height / 2 + Math.sin(a) * pr.size * 0.9 * pr.burst - pr.size * 0.5 * pr.burst
                opacity: 1 - pr.burst
            }
        }
        // turkey: tail fan opens now and then, head bobs. Clicked: gobble, fan up, strut out and back.
        Item {
            id: turkey
            visible: pr.isTurkey
            anchors.fill: parent
            readonly property real k: width / 96
            transform: Scale { origin.x: turkey.width / 2; xScale: pr.face }
            Image {
                anchors.fill: parent; source: turkey.visible ? hd.art("turkey_fan") : ""
                sourceSize.width: Math.ceil(pr.size * 2); sourceSize.height: Math.ceil(pr.size * 2); smooth: true
                transform: Scale { id: fanScale; origin.x: 48 * turkey.k; origin.y: 66 * turkey.k; xScale: 0.55; yScale: 0.6 }
                SequentialAnimation {
                    id: fanIdle
                    running: hd.running && turkey.visible && !strut.running; loops: Animation.Infinite
                    PauseAnimation { duration: 4200 }
                    ParallelAnimation {
                        NumberAnimation { target: fanScale; property: "xScale"; to: 1; duration: 700; easing.type: Easing.OutBack }
                        NumberAnimation { target: fanScale; property: "yScale"; to: 1; duration: 700; easing.type: Easing.OutBack }
                    }
                    PauseAnimation { duration: 1600 }
                    ParallelAnimation {
                        NumberAnimation { target: fanScale; property: "xScale"; to: 0.55; duration: 600; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: fanScale; property: "yScale"; to: 0.6; duration: 600; easing.type: Easing.InOutQuad }
                    }
                }
            }
            Image { anchors.fill: parent; source: turkey.visible ? hd.art("turkey_body") : ""
                    sourceSize.width: Math.ceil(pr.size * 2); sourceSize.height: Math.ceil(pr.size * 2); smooth: true
                    // little step bounce while strutting
                    y: strut.running ? -Math.abs(Math.sin(pr.walk / (6 * hd.s))) * 3 * hd.s : 0 }
            Image {
                width: parent.width; height: parent.height; source: turkey.visible ? hd.art("turkey_head") : ""
                x: 9 * turkey.k; y: -12 * turkey.k
                sourceSize.width: Math.ceil(pr.size * 2); sourceSize.height: Math.ceil(pr.size * 2); smooth: true
                transform: Rotation { id: headRot; origin.x: 48 * turkey.k; origin.y: 66 * turkey.k; angle: 0 }
                SequentialAnimation {
                    running: hd.running && turkey.visible; loops: Animation.Infinite
                    NumberAnimation { target: headRot; property: "angle"; to: -10; duration: strut.running ? 160 : 500; easing.type: Easing.InOutSine }
                    NumberAnimation { target: headRot; property: "angle"; to: 4; duration: strut.running ? 160 : 450; easing.type: Easing.InOutSine }
                    NumberAnimation { target: headRot; property: "angle"; to: 0; duration: strut.running ? 120 : 400; easing.type: Easing.InOutSine }
                    PauseAnimation { duration: strut.running ? 60 : 1800 }
                }
            }
        }
        SequentialAnimation {
            id: strut
            PropertyAction { target: pr; property: "face"; value: -1 }
            ParallelAnimation {
                NumberAnimation { target: fanScale; property: "xScale"; to: 1.05; duration: 350; easing.type: Easing.OutBack }
                NumberAnimation { target: fanScale; property: "yScale"; to: 1.05; duration: 350; easing.type: Easing.OutBack }
            }
            NumberAnimation { target: pr; property: "walk"; to: -40 * hd.s; duration: 1100; easing.type: Easing.InOutSine }
            PropertyAction { target: pr; property: "face"; value: 1 }
            PauseAnimation { duration: 250 }
            NumberAnimation { target: pr; property: "walk"; to: 0; duration: 1100; easing.type: Easing.InOutSine }
            ParallelAnimation {
                NumberAnimation { target: fanScale; property: "xScale"; to: 0.55; duration: 500; easing.type: Easing.InOutQuad }
                NumberAnimation { target: fanScale; property: "yScale"; to: 0.6; duration: 500; easing.type: Easing.InOutQuad }
            }
        }
    }

    // ---------------------------------------------------------------- placement
    Garland {
        visible: hd.pack !== null && !!hd.pack.garland
        x1: hd.headerRect.x + hd.headerRect.width * hd.titleEnd
        x2: hd.headerRect.x + hd.headerRect.width - 6 * hd.s
        y0: hd.headerRect.y + 3 * hd.s
        sag: 9 * hd.s
        seed: 1
    }
    // column top edge: props stand on it, right of the MODULE SELECT label
    Repeater {
        model: hd.pack ? hd.pack.column : []
        Prop {
            required property int index
            required property string modelData
            name: modelData; seed: index + 20
            readonly property real big: modelData === "turkey" ? 1.0 : 0.5
            size: 104 * hd.s * big
            px: hd.navRect.x + hd.navRect.width * (hd.navLabelEnd + 0.1) + (index === 0 ? 0 : 46 + (index - 1) * 34) * hd.s
            py: hd.navRect.y + (modelData === "turkey" ? 14 : 4) * hd.s
        }
    }
    // column bottom corner
    Repeater {
        model: hd.pack ? hd.pack.corner : []
        Prop {
            required property int index
            required property string modelData
            name: modelData; seed: index + 40
            size: (index === 0 ? 40 : index === 1 ? 30 : 22) * hd.s
            px: hd.navRect.x + hd.navRect.width * 0.5 + [0, 32, 56][index] * hd.s
            py: hd.navRect.y + hd.navRect.height + 4 * hd.s
        }
    }

    // ---------------------------------------------------------------- falling layer
    // Each piece falls from just above the window to just below it. It fades in over the
    // top of its fall and out over the bottom, then starts again above the window at a new
    // spot, so nothing ever appears or disappears in view. Pieces start spread out over
    // the whole fall so they don't move as a group.
    Item {
        id: fallLayer
        anchors.fill: parent
        readonly property var fp: hd.pack ? hd.pack.fall : null
        property var st: []
        Repeater {
            id: fallers
            model: fallLayer.fp ? fallLayer.fp.count : 0
            Image {
                required property int index
                source: fallLayer.fp ? hd.art(fallLayer.fp.art[index % fallLayer.fp.art.length]) : ""
                readonly property real sz: fallLayer.fp ? (fallLayer.fp.size[0] + (fallLayer.fp.size[1] - fallLayer.fp.size[0]) * hd.rnd(index, 5)) * hd.s : 20
                width: sz; height: sz
                sourceSize.width: Math.ceil(sz * 1.5); sourceSize.height: Math.ceil(sz * 1.5)
                smooth: true
                opacity: 0
                property real fx: 1
                transform: Scale { origin.x: width / 2; origin.y: height / 2; xScale: fx }
            }
        }
        function spawn(i, anywhere) {
            var f = fp, H = height
            var r = Math.random
            st[i] = {
                x: r() * width,
                y: anywhere ? -40 * hd.s + r() * (H + 80 * hd.s) : -40 * hd.s - r() * 120 * hd.s,
                v: (f.speed[0] + (f.speed[1] - f.speed[0]) * r()) * hd.s,
                amp: (f.sway[0] + (f.sway[1] - f.sway[0]) * r()) * hd.s,
                ph: r() * 6.283, w: 0.25 + r() * 0.35,
                rot: r() * 360, rv: (r() - 0.5) * 2 * f.spin,
                fl: 0.6 + r() * 0.8
            }
        }
        function reset() {
            st = []
            if (!fp) return
            for (var i = 0; i < fp.count; i++) spawn(i, true)
        }
        // (re)spread once the window has its size; a pack change starts fresh
        onFpChanged: st = []
        FrameAnimation {
            running: hd.running && fallLayer.fp !== null
            onTriggered: {
                var f = fallLayer.fp, H = fallLayer.height, dt = Math.min(0.05, frameTime)
                if (!f) return
                if (fallLayer.st.length !== f.count) { if (H < 50) return; fallLayer.reset() }
                var edge = 0.12 * H
                for (var i = 0; i < f.count; i++) {
                    var p = fallLayer.st[i], item = fallers.itemAt(i)
                    if (!p || !item) continue
                    p.y += p.v * dt; p.ph += p.w * dt * 6.283; p.rot += p.rv * dt
                    if (p.y > H + 40 * hd.s) { fallLayer.spawn(i, false); p = fallLayer.st[i] }
                    item.x = p.x + Math.sin(p.ph) * p.amp - item.width / 2
                    item.y = p.y - item.height / 2
                    item.rotation = p.rot
                    // fade in near the top, out near the bottom
                    var a = Math.max(0, Math.min(1, p.y / edge, (H - p.y) / edge))
                    item.opacity = f.opacity * a
                    if (f.flip) item.fx = Math.cos(p.ph * p.fl)
                }
            }
        }
    }
}
