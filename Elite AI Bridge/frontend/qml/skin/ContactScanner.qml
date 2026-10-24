// Contact scanner: shown in place of ship art when there's nothing on file to draw.
// A slow radar sweep on the shield plane, a title and up to two lines under it.
//   NO SHIP DATA        (no ship: Elite offline, on foot, SRV)       blip: false
//   NO SIGNATURE MATCH  (a ship type the Bridge has no class for)    blip: true
//   CONTACT // NON-STANDARD (a target that isn't a ship class)       blip: true
// Original design; no sound.
import QtQuick
import "."

Item {
    id: sc
    property string title: ""
    property string line2: ""
    property string line3: ""
    property bool blip: false
    property color col: Theme.ok
    property vector2d centerAt: Qt.vector2d(0.5, 0.62)     // same plane as the shield ring
    property vector2d ringRadii: Qt.vector2d(0.47, 0.20)
    property real fontScale: 1.0
    property real textY: 0.10                               // top of the text, as a fraction of height

    property real th: 0
    NumberAnimation on th { from: 0; to: 2 * Math.PI; duration: 4000; loops: Animation.Infinite; running: sc.visible }

    Canvas {
        property bool themeAmber: Theme.amber   // LAB themes: repaint when the screen theme changes
        onThemeAmberChanged: requestPaint()
        id: cv
        anchors.fill: parent
        property real step: Math.floor(sc.th * 30) / 30          // about 30 repaints a second
        onStepChanged: requestPaint()
        onPaint: {
            var c = getContext("2d"); c.reset()
            var w = width, h = height
            var cx = w * sc.centerAt.x, cy = h * sc.centerAt.y, rx = w * sc.ringRadii.x * 0.92, ry = h * sc.ringRadii.y * 0.92
            var r = sc.col.r, g = sc.col.g, b = sc.col.b
            function ell(f, a, lw) {
                c.strokeStyle = Qt.rgba(r, g, b, a); c.lineWidth = lw
                c.beginPath(); c.ellipse(cx - rx * f, cy - ry * f, 2 * rx * f, 2 * ry * f); c.stroke()
            }
            ell(1.0, 0.45, 1.6); ell(0.66, 0.28, 1.2); ell(0.33, 0.28, 1.2)
            c.strokeStyle = Qt.rgba(r, g, b, 0.16); c.lineWidth = 1
            c.beginPath(); c.moveTo(cx - rx, cy); c.lineTo(cx + rx, cy); c.moveTo(cx, cy - ry); c.lineTo(cx, cy + ry); c.stroke()
            // sweep with a fading trail
            for (var j = 0; j < 26; j++) {
                var a = sc.th - j * 0.035
                var k = 1 - j / 26
                c.strokeStyle = Qt.rgba(r, g, b, 0.6 * k * k); c.lineWidth = 2.4
                c.beginPath(); c.moveTo(cx, cy); c.lineTo(cx + rx * Math.cos(a), cy + ry * Math.sin(a)); c.stroke()
            }
            if (sc.blip) {
                var ba = 0.9, bx = cx + rx * 0.55 * Math.cos(ba), by = cy + ry * 0.55 * Math.sin(ba)
                var since = ((sc.th - ba) % (2 * Math.PI) + 2 * Math.PI) % (2 * Math.PI)
                var glow = Math.max(0.15, 1 - since / (2 * Math.PI) * 1.3)
                var rr = (7 + 5 * (1 - glow)) * Math.max(0.6, w / 700)
                c.strokeStyle = Qt.rgba(r, g, b, glow); c.lineWidth = 2
                c.beginPath(); c.ellipse(bx - rr, by - rr * 0.6, 2 * rr, 1.2 * rr); c.stroke()
                c.fillStyle = Qt.rgba(r, g, b, glow)
                c.beginPath(); c.ellipse(bx - 4, by - 3, 8, 6); c.fill()
            }
        }
    }
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * sc.textY
        width: parent.width * 0.92
        spacing: 4 * Theme.s
        visible: sc.title !== ""
        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
               text: sc.title; color: sc.col
               font.family: Theme.crtFont; font.pixelSize: Math.max(14, 44 * Theme.s * sc.fontScale); font.letterSpacing: 2 * Theme.s }
        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
               visible: sc.line2 !== ""; text: sc.line2.toUpperCase(); color: Theme.phosphor
               font.family: Theme.crtFont; font.pixelSize: Math.max(12, 30 * Theme.s * sc.fontScale); font.letterSpacing: 1.5 * Theme.s }
        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
               visible: sc.line3 !== ""; text: "> " + sc.line3.toUpperCase(); color: Theme.dimText
               font.family: Theme.crtFont; font.pixelSize: Math.max(11, 24 * Theme.s * sc.fontScale); font.letterSpacing: 1.5 * Theme.s }
    }
}
