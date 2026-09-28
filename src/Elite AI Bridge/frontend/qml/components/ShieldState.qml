import QtQuick

Item {
    id: root
    property string state: "DOWN"
    property real phase: 0.0 // retained for API compatibility; animation is state-timed locally
    property string normalizedState: state.toUpperCase()
    property bool known: normalizedState === "UP" || normalizedState === "DOWN"
    property bool up: normalizedState === "UP"
    property color goodColor: "#45cfff"
    property color badColor: "#ff493e"
    property color unknownColor: "#859086"
    property color stateColor: known ? (up ? goodColor : badColor) : unknownColor
    property real fieldPhase: 0.0

    NumberAnimation on fieldPhase {
        from: 0.0; to: 1.0
        duration: root.known ? (root.up ? 3000 : 720) : 2400
        loops: Animation.Infinite
        running: root.visible
    }

    Text {
        text: "SHIELDS"; color: "#94a096"; font.family: "Consolas"
        font.pixelSize: Math.max(10, root.height*.19); anchors.left: parent.left; anchors.top: parent.top
    }
    Text {
        text: root.state.toUpperCase(); color: root.stateColor; font.family: "Consolas"; font.bold: true
        font.pixelSize: Math.max(12, root.height*.24); anchors.right: parent.right; anchors.top: parent.top
    }

    Canvas {
        id: canvas
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: parent.width
        height: parent.height*.73

        function rgba(alpha) {
            if (!root.known) return "rgba(133,144,134,"+alpha.toFixed(3)+")"
            return root.up ? "rgba(69,207,255,"+alpha.toFixed(3)+")" : "rgba(255,73,62,"+alpha.toFixed(3)+")"
        }
        function fieldWing(c, cx, cy, side, innerX, outerX, halfH, alpha, lineW) {
            var sx=side
            c.strokeStyle=rgba(alpha); c.lineWidth=lineW; c.lineCap="round"; c.lineJoin="round"
            c.beginPath()
            c.moveTo(cx+sx*innerX,cy-halfH*.80)
            c.bezierCurveTo(cx+sx*outerX*.72,cy-halfH, cx+sx*outerX,cy-halfH*.62, cx+sx*outerX,cy)
            c.bezierCurveTo(cx+sx*outerX,cy+halfH*.62, cx+sx*outerX*.72,cy+halfH, cx+sx*innerX,cy+halfH*.80)
            c.stroke()
        }
        function bracket(c,cx,cy,side,w,h,alpha) {
            c.strokeStyle=rgba(alpha); c.lineWidth=Math.max(2,w*.055); c.lineCap="square"
            c.beginPath()
            c.moveTo(cx+side*w*.64,cy-h*.72); c.lineTo(cx+side*w*.82,cy-h*.55); c.lineTo(cx+side*w*.82,cy+h*.55); c.lineTo(cx+side*w*.64,cy+h*.72)
            c.stroke()
        }

        onPaint: {
            var c=getContext("2d")
            c.reset(); c.clearRect(0,0,width,height)
            var cx=width*.5, cy=height*.54
            var base=Math.min(width,height)
            var t=root.fieldPhase
            var pulse=.5+.5*Math.sin(t*6.28318)

            // Oversized layered side fields. Healthy shields breathe from the inner
            // plate outward slowly; down shields repeat the same travel much faster.
            for (var i=0;i<4;i++) {
                var travel=(t*4-i+4)%4
                var wave=Math.max(0,1-Math.abs(travel-1.0))
                var alpha=!root.known ? (.12+.10*pulse) : (.18+.64*wave)
                var inner=width*(.075+i*.012)
                var outer=width*(.245+i*.072)
                var halfH=height*(.23+i*.055)
                fieldWing(c,cx,cy,-1,inner,outer,halfH,alpha,Math.max(2.4,base*(.024+i*.003)))
                fieldWing(c,cx,cy, 1,inner,outer,halfH,alpha,Math.max(2.4,base*(.024+i*.003)))
            }

            // Bright inner defensive plates give the icon the exaggerated armored silhouette.
            var plateAlpha=!root.known?.32:(root.up ? .62+.25*pulse : .50+.45*pulse)
            bracket(c,cx,cy,-1,base*.52,base*.50,plateAlpha)
            bracket(c,cx,cy, 1,base*.52,base*.50,plateAlpha)

            // Compact central shield badge. Side fields remain the visual hero.
            var s=base*.145
            c.strokeStyle=!root.known ? "rgba(133,144,134,0.55)" : (root.up ? "rgba(190,245,255,"+(.72+.22*pulse).toFixed(3)+")" : "rgba(255,190,180,"+(.58+.38*pulse).toFixed(3)+")")
            c.fillStyle=!root.known ? "rgba(80,90,84,0.10)" : (root.up ? "rgba(35,145,210,0.18)" : "rgba(150,20,18,"+(.12+.18*pulse).toFixed(3)+")")
            c.lineWidth=Math.max(2,base*.024)
            c.beginPath()
            c.moveTo(cx-s*.55,cy-s*.88); c.lineTo(cx+s*.55,cy-s*.88)
            c.lineTo(cx+s*.88,cy-s*.50); c.lineTo(cx+s*.88,cy+s*.45)
            c.lineTo(cx+s*.52,cy+s*.88); c.lineTo(cx-s*.52,cy+s*.88)
            c.lineTo(cx-s*.88,cy+s*.45); c.lineTo(cx-s*.88,cy-s*.50)
            c.closePath(); c.fill(); c.stroke()

            if (root.known && !root.up) {
                c.strokeStyle="rgba(255,73,62,"+(.66+.34*pulse).toFixed(3)+")"
                c.lineWidth=Math.max(2.8,base*.035)
                c.beginPath(); c.moveTo(cx-s*.62,cy-s*.58); c.lineTo(cx+s*.62,cy+s*.58); c.stroke()
            }
        }
        Connections {
            target: root
            function onStateChanged(){ canvas.requestPaint() }
            function onFieldPhaseChanged(){ canvas.requestPaint() }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()
    }
}
