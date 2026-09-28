import QtQuick

Canvas {
    id: root
    property color color: "#2aff80"
    property real phase: 0.0
    onPaint: {
        var c=getContext("2d"); c.reset(); c.clearRect(0,0,width,height)
        var cx=width/2, cy=height/2, r=Math.min(width,height)*.29
        c.strokeStyle=root.color; c.lineWidth=2; c.globalAlpha=.9
        c.beginPath(); c.arc(cx,cy,r,0,Math.PI*2); c.stroke()
        function line(x1,y1,x2,y2){ c.beginPath();c.moveTo(x1,y1);c.lineTo(x2,y2);c.stroke() }
        line(cx-r*1.55,cy,cx-r*.78,cy); line(cx+r*.78,cy,cx+r*1.55,cy)
        line(cx,cy-r*1.55,cx,cy-r*.78); line(cx,cy+r*.78,cx,cy+r*1.55)
        c.globalAlpha=.25+.15*Math.sin(root.phase*6.28318)
        c.beginPath(); c.arc(cx,cy,r*1.35,-Math.PI*.15,Math.PI*.72); c.stroke()
        c.globalAlpha=1
        c.fillStyle=root.color; c.beginPath(); c.arc(cx,cy,3,0,Math.PI*2); c.fill()
    }
    onWidthChanged: requestPaint(); onHeightChanged: requestPaint(); onPhaseChanged: requestPaint()
}
