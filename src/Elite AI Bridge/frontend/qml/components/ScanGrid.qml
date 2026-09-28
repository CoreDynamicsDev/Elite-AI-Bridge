import QtQuick

Canvas {
    id: grid
    property color majorColor: "#10301d"
    property color minorColor: "#08150d"
    property color scanColor: "#153321"
    property int step: 28
    property int majorEvery: 4
    opacity: 0.55

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset(); ctx.clearRect(0,0,width,height)
        for (var x=0; x<width; x+=step) {
            ctx.strokeStyle = ((x/step)%majorEvery===0) ? majorColor : minorColor
            ctx.lineWidth = 1
            ctx.beginPath(); ctx.moveTo(x+.5,0); ctx.lineTo(x+.5,height); ctx.stroke()
        }
        for (var y=0; y<height; y+=step) {
            ctx.strokeStyle = ((y/step)%majorEvery===0) ? majorColor : minorColor
            ctx.lineWidth = 1
            ctx.beginPath(); ctx.moveTo(0,y+.5); ctx.lineTo(width,y+.5); ctx.stroke()
        }
        ctx.strokeStyle = scanColor; ctx.globalAlpha=.14
        for (var sy=2; sy<height; sy+=6) {
            ctx.beginPath(); ctx.moveTo(0,sy+.5); ctx.lineTo(width,sy+.5); ctx.stroke()
        }
        ctx.globalAlpha=1
    }
    onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
}
