// Voice waveform lines on their own: no ring, no panel. Same shapes and colours as
// VoiceScope (the activity state), drawn wide for the setup wizard (2.0.0). Each line
// gets a soft dark edge and a faint glow so it reads over anything behind it.
// IDLE flat trace + sweeping beam; LISTENING lively wave; THINKING marching dots;
// SPEAKING big wave; AUTOMATION square wave; CRITICAL pulses red; FAULT / NOCREDITS flat.
import QtQuick
import "."

Item {
    id: wl
    property string activity: "IDLE"
    property real t: 0                      // 0..4 s loop
    property bool animate: true
    property real k: 1.0                    // line size
    readonly property color col: Theme.activityColor(activity)

    FrameAnimation { running: wl.animate && wl.visible; onTriggered: wl.t = (wl.t + frameTime) % 4.0 }

    Canvas {
        id: trace
        anchors.fill: parent
        property real tt: Math.round(wl.t * 30) / 30
        onTtChanged: requestPaint()
        property string mode: wl.activity
        onModeChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            var c = getContext("2d"); c.reset()
            var w = width, h = height, mid = h / 2, m = wl.activity
            var col = wl.col, rgb = Math.round(col.r * 255) + "," + Math.round(col.g * 255) + "," + Math.round(col.b * 255)
            var ph = wl.t * Math.PI * 2 / 4
            var alpha = 0.95
            if (m === "CRITICAL") alpha = 0.45 + 0.5 * (0.5 + 0.5 * Math.sin(ph * 4))
            var lw = Math.max(1.6, 3 * wl.k)
            c.lineJoin = "round"; c.lineCap = "round"
            // one path, three strokes: dark edge, glow, line
            function strokeAll(path) {
                c.beginPath(); path()
                c.strokeStyle = "rgba(0,0,0,0.55)"; c.lineWidth = lw + 5 * wl.k; c.stroke()
                c.strokeStyle = "rgba(" + rgb + "," + (0.18 * alpha) + ")"; c.lineWidth = lw + 9 * wl.k; c.stroke()
                c.strokeStyle = "rgba(" + rgb + "," + alpha + ")"; c.lineWidth = lw; c.stroke()
            }
            if (m === "THINKING") {
                var a1 = 0.55 + 0.4 * (0.5 + 0.5 * Math.sin(ph * 2))
                for (var d = 0; d < 14; d++) {
                    var x = ((d / 14 + wl.t / 4) % 1) * w
                    c.fillStyle = "rgba(0,0,0,0.55)"; c.beginPath(); c.arc(x, mid, 5.5 * wl.k, 0, Math.PI * 2); c.fill()
                    c.fillStyle = "rgba(" + rgb + "," + a1 + ")"; c.beginPath(); c.arc(x, mid, 3.6 * wl.k, 0, Math.PI * 2); c.fill()
                }
            } else if (m === "AUTOMATION") {
                var a = 0.30 * h, per = w / 6, off = (wl.t / 4) * per * 4
                strokeAll(function () {
                    for (var i = 0; i <= 160; i++) {
                        var xx = i / 160 * w
                        var hi = Math.floor((xx + off) / (per / 2)) % 2 === 0
                        var yy = mid + (hi ? -a : a)
                        if (i === 0) c.moveTo(xx, yy); else c.lineTo(xx, yy)
                    }
                })
            } else if (m === "IDLE" || m === "FAULT" || m === "NOCREDITS") {
                c.globalAlpha = 0.5
                strokeAll(function () { c.moveTo(0, mid); c.lineTo(w, mid) })
                c.globalAlpha = 1
                var bx = (wl.t / 4) * w * 2 % w
                var gr = c.createRadialGradient(bx, mid, 0, bx, mid, 14 * wl.k)
                gr.addColorStop(0, "rgba(" + rgb + ",0.95)"); gr.addColorStop(1, "rgba(" + rgb + ",0)")
                c.fillStyle = gr; c.beginPath(); c.arc(bx, mid, 14 * wl.k, 0, Math.PI * 2); c.fill()
            } else {
                var amp = m === "SPEAKING" ? 0.44 : m === "LISTENING" ? 0.32 : m === "CRITICAL" ? 0.38 : 0.18
                strokeAll(function () {
                    for (var k = 0; k <= 160; k++) {
                        var x2 = k / 160
                        var y2 = Math.sin(x2 * 28 + ph * 3) * 0.6 + Math.sin(x2 * 63 - ph * 5) * 0.3 + Math.sin(x2 * 12 + ph) * 0.4
                        if (m === "CRITICAL") y2 = Math.sin(x2 * 19 + ph * 2) * 0.9
                        var py = mid + y2 * amp * mid * Math.sin(x2 * Math.PI)
                        if (k === 0) c.moveTo(x2 * w, py); else c.lineTo(x2 * w, py)
                    }
                })
            }
        }
    }
}
