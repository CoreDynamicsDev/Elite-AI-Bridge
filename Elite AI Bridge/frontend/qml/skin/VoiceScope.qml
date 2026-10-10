// Voice scope: one look for the whole Bridge. Shape and colour follow the shared
// activity state (bridge.bridgeActivity), so the module column and the in-game
// overlay always agree. IDLE flat trace + sweeping beam; LISTENING lively wave;
// THINKING marching dots; SPEAKING big wave; AUTOMATION square wave (white);
// DONE gentle wave; FAILED / CRITICAL red (CRITICAL pulses); FAULT / NOCREDITS amber, flat.
import QtQuick
import "."

Item {
    id: sc
    property string activity: "IDLE"
    property real t: 0                      // 0..4 s loop
    property bool animate: true             // run our own clock (off when a parent drives t)
    property real k: 1.0                    // line and dot size
    property real rim: 5                    // bezel thickness in px
    readonly property color col: Theme.activityColor(activity)

    FrameAnimation { running: sc.animate && sc.visible; onTriggered: sc.t = (sc.t + frameTime) % 4.0 }

    Rectangle { anchors.fill: parent; radius: width / 2
        gradient: Gradient { GradientStop { position: 0; color: "#5a5850" } GradientStop { position: 1; color: "#141412" } } }
    Rectangle { anchors.fill: parent; anchors.margins: sc.rim; radius: width / 2; border.color: "#000"; border.width: 1
        gradient: Gradient { GradientStop { position: 0; color: Theme.glassTop } GradientStop { position: 1; color: Theme.glassEdge } } }
    Canvas {
        id: trace
        anchors.fill: parent; anchors.margins: sc.rim + 2
        property real tt: Math.round(sc.t * 30) / 30
        onTtChanged: requestPaint()
        property string mode: sc.activity
        onModeChanged: requestPaint()
                onPaint: {
                    var c = getContext("2d"); c.reset()
                    var w = width, h = height, r = w / 2, m = sc.activity
                    var col = sc.col, rgb = Math.round(col.r * 255) + "," + Math.round(col.g * 255) + "," + Math.round(col.b * 255)
                    var ph = sc.t * Math.PI * 2 / 4
                    c.save(); c.beginPath(); c.arc(r, r, r - 1, 0, Math.PI * 2); c.clip()
                    c.strokeStyle = "rgba(125,255,156,0.12)"; c.lineWidth = 1
                    c.beginPath(); c.moveTo(0, r); c.lineTo(w, r); c.moveTo(r, 0); c.lineTo(r, h); c.stroke()
                    var alpha = 0.95
                    if (m === "CRITICAL") alpha = 0.45 + 0.5 * (0.5 + 0.5 * Math.sin(ph * 4))
                    c.strokeStyle = "rgba(" + rgb + "," + alpha + ")"; c.lineWidth = Math.max(1.4, 2.2 * sc.k)
                    if (m === "THINKING") {
                        // marching dots, slow pulse
                        c.fillStyle = "rgba(" + rgb + "," + (0.55 + 0.4 * (0.5 + 0.5 * Math.sin(ph * 2))) + ")"
                        for (var d = 0; d < 7; d++) {
                            var x = ((d / 7 + sc.t / 4) % 1) * w
                            c.beginPath(); c.arc(x, r, 2.4 * sc.k, 0, Math.PI * 2); c.fill()
                        }
                    } else if (m === "AUTOMATION") {
                        // square wave
                        c.beginPath()
                        var a = 0.22 * r, per = w / 3, off = (sc.t / 4) * per * 4
                        for (var i = 0; i <= 60; i++) {
                            var xx = i / 60 * w
                            var hi = Math.floor((xx + off) / (per / 2)) % 2 === 0
                            var yy = r + (hi ? -a : a)
                            if (i === 0) c.moveTo(xx, yy); else c.lineTo(xx, yy)
                        }
                        c.stroke()
                    } else if (m === "IDLE" || m === "FAULT" || m === "NOCREDITS") {
                        // flat trace, beam sweeps left to right
                        c.beginPath(); c.moveTo(0, r); c.lineTo(w, r); c.globalAlpha = 0.45; c.stroke(); c.globalAlpha = 1
                        var bx = (sc.t / 4) * w * 2 % w
                        var gr = c.createRadialGradient(bx, r, 0, bx, r, 8 * sc.k)
                        gr.addColorStop(0, "rgba(" + rgb + ",0.95)"); gr.addColorStop(1, "rgba(" + rgb + ",0)")
                        c.fillStyle = gr; c.beginPath(); c.arc(bx, r, 8 * sc.k, 0, Math.PI * 2); c.fill()
                    } else {
                        var amp = m === "SPEAKING" ? 0.36 : m === "LISTENING" ? 0.24 : m === "CRITICAL" ? 0.30 : 0.14
                        c.beginPath()
                        for (var k = 0; k <= 48; k++) {
                            var x2 = k / 48
                            var y2 = Math.sin(x2 * 9.4 + ph * 3) * 0.6 + Math.sin(x2 * 21.0 - ph * 5) * 0.3 + Math.sin(x2 * 4.0 + ph) * 0.4
                            if (m === "CRITICAL") y2 = Math.sin(x2 * 6.3 + ph * 2) * 0.9
                            var py = r + y2 * amp * r * Math.sin(x2 * Math.PI)
                            if (k === 0) c.moveTo(x2 * w, py); else c.lineTo(x2 * w, py)
                        }
                        c.stroke()
                    }
                    c.restore()
                }
    }
}
