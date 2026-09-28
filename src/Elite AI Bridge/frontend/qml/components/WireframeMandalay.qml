import QtQuick

Canvas {
    id: root
    property color lineColor: "#2aff80"
    property color dimColor: "#17472a"
    property real sweep: 0.0

    onPaint: {
        var c = getContext("2d")
        c.reset(); c.clearRect(0,0,width,height)
        var cx=width*.50, cy=height*.53, s=Math.min(width,height)*.38
        function line(x1,y1,x2,y2,color,w) {
            c.strokeStyle=color; c.lineWidth=w||1; c.beginPath(); c.moveTo(x1,y1); c.lineTo(x2,y2); c.stroke()
        }
        c.strokeStyle=dimColor; c.lineWidth=1
        c.beginPath(); c.arc(cx,cy,s*.82,0,Math.PI*2); c.stroke()
        line(cx-s*.95,cy,cx+s*.95,cy,dimColor,1)
        line(cx,cy-s*.95,cx,cy+s*.95,dimColor,1)
        var p=[
            [0,-1.00],[-.08,-.66],[-.18,-.50],[-.54,-.20],[-.78,.02],[-.39,.22],[-.29,.53],[-.13,.87],
            [0,.62],[.13,.87],[.29,.53],[.39,.22],[.78,.02],[.54,-.20],[.18,-.50],[.08,-.66]
        ]
        c.strokeStyle=lineColor; c.lineWidth=2
        c.beginPath(); c.moveTo(cx+p[0][0]*s,cy+p[0][1]*s)
        for(var i=1;i<p.length;i++) c.lineTo(cx+p[i][0]*s,cy+p[i][1]*s)
        c.closePath(); c.stroke()
        line(cx,cy-s*.98,cx,cy+s*.60,lineColor,1.5)
        var internals=[
            [-.10,-.58,.10,-.58],[-.34,-.39,-.12,-.17],[.34,-.39,.12,-.17],
            [-.49,-.10,-.18,.11],[.49,-.10,.18,.11],[-.26,.29,0,.14],[.26,.29,0,.14],
            [-.18,.52,0,.34],[.18,.52,0,.34],[-.24,.06,.24,.06],[-.18,.19,.18,.19]
        ]
        for(var j=0;j<internals.length;j++) {
            var a=internals[j]; line(cx+a[0]*s,cy+a[1]*s,cx+a[2]*s,cy+a[3]*s,"#1d7d46",1)
        }
        // narrow scan sweep, deliberately subtle
        var sy=(root.sweep%1.0)*height
        c.strokeStyle="#1d5f35"; c.globalAlpha=.45; c.lineWidth=1
        c.beginPath(); c.moveTo(width*.08,sy); c.lineTo(width*.92,sy); c.stroke(); c.globalAlpha=1
    }
    onWidthChanged: requestPaint(); onHeightChanged: requestPaint(); onSweepChanged: requestPaint()
}
