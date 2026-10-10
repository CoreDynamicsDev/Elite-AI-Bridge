// Yellow and black hazard stripes. Reserved for CANCEL only.
import QtQuick

Canvas {
    property color a: "#c79f2c"
    property color b: "#151513"
    property real stripe: 16
    onPaint: {
        var ctx = getContext("2d"); ctx.reset()
        ctx.fillStyle = b; ctx.fillRect(0, 0, width, height)
        ctx.fillStyle = a
        for (var x = -height; x < width + height; x += stripe * 2) {
            ctx.beginPath(); ctx.moveTo(x, height); ctx.lineTo(x + stripe, height)
            ctx.lineTo(x + stripe + height, 0); ctx.lineTo(x + height, 0); ctx.closePath(); ctx.fill()
        }
    }
    onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
}
