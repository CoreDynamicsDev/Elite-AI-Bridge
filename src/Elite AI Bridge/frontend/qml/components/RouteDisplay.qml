import QtQuick

Item {
    id: root
    property color green: "#2aff80"
    property color dimGreen: "#125e36"
    property color amber: "#d6a540"
    property color scoopableColor: "#47cfff"
    property color nonScoopableColor: "#ff6a4a"
    property color unknownColor: "#839084"
    property real phase: 0.0
    property string origin: "-"
    property string destination: "NO ROUTE"
    property bool inSystemTargetVisible: false
    property string inSystemTargetName: "-"
    property string inSystemTargetKind: "IN-SYSTEM TARGET"
    property bool inSystemTargetConfirmedStation: false
    property var waypoints: []
    property real textScale: 1.0
    property bool animateDirection: true

    Rectangle {
        anchors.fill: parent
        color: "#031006"
        border.color: "#244a30"
        border.width: 1
    }

    Canvas {
        id: routeGrid
        anchors.fill: parent
        opacity: .55
        onPaint: {
            var c=getContext("2d")
            c.reset(); c.clearRect(0,0,width,height)
            c.strokeStyle="rgba(38,118,64,0.28)"
            c.lineWidth=1
            var step=Math.max(26,width/18)
            for (var x=0;x<width;x+=step){c.beginPath();c.moveTo(x,0);c.lineTo(x,height);c.stroke()}
            for (var y=0;y<height;y+=step){c.beginPath();c.moveTo(0,y);c.lineTo(width,y);c.stroke()}

            // In-system station targets live on the same plotted course instead of
            // drawing a second amber route over the green navigation line.
            var stationOnly = root.inSystemTargetVisible && (!root.waypoints || root.waypoints.length <= 1)
            var endFrac = stationOnly ? 0.58 : 1.0
            var endX = width*(.10 + .77*endFrac)
            var endY = height*(.70 - .44*endFrac)
            c.strokeStyle="rgba(42,255,128,0.22)"
            c.lineWidth=2
            c.beginPath(); c.moveTo(width*.10,height*.70); c.lineTo(endX,endY); c.stroke()
        }
        onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
    }
    Connections {
        target: root
        function onInSystemTargetVisibleChanged() { routeGrid.requestPaint() }
        function onWaypointsChanged() { routeGrid.requestPaint() }
    }

    // Dim background stars are decorative only. They twinkle gently and stay
    // neutral so they cannot be mistaken for scoopability route nodes.
    Repeater {
        model: [
            {x:.18,y:.24,size:4,tw:.02}, {x:.30,y:.79,size:4,tw:.19}, {x:.57,y:.73,size:4,tw:.37},
            {x:.72,y:.66,size:3,tw:.56}, {x:.48,y:.20,size:3,tw:.74}, {x:.82,y:.78,size:4,tw:.91},
            {x:.12,y:.47,size:3,tw:.28}, {x:.24,y:.17,size:2,tw:.63}, {x:.39,y:.84,size:3,tw:.83},
            {x:.64,y:.35,size:2,tw:.11}, {x:.77,y:.16,size:3,tw:.47}, {x:.91,y:.58,size:2,tw:.68}
        ]
        Rectangle {
            x: parent.width*modelData.x-width/2; y: parent.height*modelData.y-height/2
            width: modelData.size*root.textScale; height: width; radius: width/2
            color: root.unknownColor
            opacity: 0.16 + 0.22*(0.5 + 0.5*Math.sin((root.phase + modelData.tw)*6.28318))
        }
    }

    Repeater {
        id: routeNodes
        model: root.waypoints && root.waypoints.length ? root.waypoints : []
        Item {
            readonly property real frac: routeNodes.count <= 1 ? 0 : index/(routeNodes.count-1)
            readonly property bool isCurrent: String(modelData.kind || "") === "CURRENT"
            readonly property bool isDestination: String(modelData.kind || "") === "DESTINATION" || index===routeNodes.count-1
            readonly property bool isEllipsis: String(modelData.kind || "") === "ELLIPSIS"
            readonly property color nodeColor: isCurrent ? root.green : (modelData.scoopable === true ? root.scoopableColor : (modelData.scoopable === false ? root.nonScoopableColor : root.unknownColor))
            x: parent.width*(.10 + .77*frac) - width/2
            y: parent.height*(.70 - .44*frac) - height/2
            width: (isEllipsis ? 34 : (isCurrent || isDestination ? 16 : 11))*root.textScale
            height: isEllipsis ? 16*root.textScale : width

            // Intermediate route nodes pulse in their scoopability color. The halo is
            // intentionally softer than origin/target so route hierarchy stays obvious.
            Rectangle {
                visible: !parent.isEllipsis && !parent.isCurrent && !parent.isDestination
                anchors.centerIn: parent
                width: parent.width*(1.75 + .28*Math.sin((root.phase + index*.13)*6.28318))
                height: width; radius: width/2
                color: parent.nodeColor
                opacity: .10 + .08*(0.5 + 0.5*Math.sin((root.phase + index*.13)*6.28318))
            }
            Rectangle {
                visible: !parent.isEllipsis
                anchors.fill: parent; radius: width/2
                color: parent.nodeColor
                opacity: parent.isCurrent || parent.isDestination
                    ? .98
                    : (.76 + .18*(0.5 + 0.5*Math.sin((root.phase + index*.13)*6.28318)))
            }
            Rectangle {
                visible: !parent.isEllipsis && parent.isDestination
                anchors.centerIn: parent
                width: parent.width*2.0; height: width; radius: width/2
                color: "transparent"; border.color: root.amber; border.width: 2
                opacity: .72 + .20*Math.sin(root.phase*6.28318)
            }
            Rectangle {
                visible: !parent.isEllipsis && (parent.isCurrent || parent.isDestination)
                anchors.centerIn: parent
                width: parent.width*(2.8 + .35*Math.sin(root.phase*6.28318)); height: width; radius: width/2
                color: parent.nodeColor
                opacity: .07
            }
            Rectangle {
                visible: parent.isEllipsis
                anchors.centerIn: parent
                width: Math.max(82, 106*root.textScale)
                height: Math.max(22, 28*root.textScale)
                radius: height/2
                color: "#111713"
                border.color: "#66736b"
                border.width: 1
                opacity: .94
                Text {
                    anchors.centerIn: parent
                    text: "+" + String(modelData.hiddenCount || 0) + " MORE JUMPS"
                    color: "#a9b3ac"
                    font.family: "Consolas"; font.bold: true
                    font.pixelSize: Math.max(12, 14*root.textScale)
                }
            }

            // Intermediate route labels. Origin and target already have large labels;
            // these names travel with the live NavRoute list as each jump completes.
            // Callouts are deliberately pulled away from the route line so long system
            // names stay readable without obscuring scoopability dots or travel chevrons.
            readonly property bool routeLabelAbove: index % 2 === 0
            readonly property real routeLabelGap: Math.max(50, 58*root.textScale)
            readonly property real routeLabelWidth: Math.max(160, Math.min(220*root.textScale, root.width*0.28))
            readonly property real routeLabelXShift: Math.max(-46, Math.min(46, (index - (routeNodes.count-1)/2) * 14*root.textScale))
            readonly property real routeLeaderWidth: Math.max(3, 3.2*root.textScale)

            Rectangle {
                id: routeLabelBox
                z: 2
                visible: !parent.isCurrent && !parent.isDestination && !parent.isEllipsis
                x: parent.width/2 - width/2 + parent.routeLabelXShift
                y: parent.routeLabelAbove
                    ? parent.height/2 - parent.routeLabelGap - height
                    : parent.height/2 + parent.routeLabelGap
                width: parent.routeLabelWidth
                height: Math.max(30, routeLabelText.implicitHeight + 12*root.textScale)
                radius: 3*root.textScale
                color: "#071009"
                border.color: Qt.rgba(parent.nodeColor.r, parent.nodeColor.g, parent.nodeColor.b, 0.50)
                border.width: 1
                opacity: .96
                Text {
                    id: routeLabelText
                    width: parent.width - 14*root.textScale
                    x: 7*root.textScale
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(modelData.system || "-")
                    color: "#c0cac3"
                    font.family: "Consolas"
                    font.bold: true
                    font.pixelSize: Math.max(11, 12.5*root.textScale)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WrapAnywhere
                }
            }

            // Heavier leader line from the full-name callout back to its route dot.
            Rectangle {
                id: routeLabelLeader
                z: -1
                visible: routeLabelBox.visible
                readonly property real nodeX: parent.width/2
                readonly property real nodeY: parent.height/2
                readonly property real labelX: routeLabelBox.x + routeLabelBox.width/2
                readonly property real labelY: parent.routeLabelAbove ? routeLabelBox.y + routeLabelBox.height : routeLabelBox.y
                readonly property real dx: labelX - nodeX
                readonly property real dy: labelY - nodeY
                readonly property real lineLength: Math.sqrt(dx*dx + dy*dy)
                x: nodeX
                y: nodeY - height/2
                width: lineLength
                height: parent.routeLeaderWidth
                radius: height/2
                color: parent.nodeColor
                opacity: .78
                transform: Rotation {
                    origin.x: 0
                    origin.y: routeLabelLeader.height/2
                    angle: Math.atan2(routeLabelLeader.dy, routeLabelLeader.dx) * 180 / Math.PI
                }
            }
        }
    }

    // When Status.json exposes a named in-system destination, place that
    // destination directly on the normal navigation course.  If there is no
    // hyperspace route left, the station becomes a strong mid-map objective.
    // If a hyperspace route is still present, it moves toward the destination
    // end without pretending that the 2-D diagram is a distance scale.
    Item {
        id: inSystemConnector
        anchors.fill: parent
        z: 1
        visible: root.inSystemTargetVisible
        readonly property bool routeHasHyperspace: root.waypoints && root.waypoints.length > 1
        readonly property real stationFrac: routeHasHyperspace ? 0.93 : 0.58
        readonly property real toX: root.width*(.10 + .77*stationFrac)
        readonly property real toY: root.height*(.70 - .44*stationFrac)

        Item {
            id: inSystemEndpoint
            x: parent.toX-width/2
            y: parent.toY-height/2
            width: Math.max(36,44*root.textScale)
            height: width
            readonly property bool isOutpost: root.inSystemTargetKind === "OUTPOST"
            readonly property bool isSettlement: root.inSystemTargetKind === "SETTLEMENT"
            readonly property bool isCarrier: root.inSystemTargetKind === "CARRIER"
            readonly property bool isKnownStation: root.inSystemTargetConfirmedStation

            Rectangle {
                anchors.centerIn: parent
                width: parent.width*(1.72+.18*Math.sin(root.phase*6.28318))
                height: width; radius: width/2
                color: "transparent"
                border.color: root.amber; border.width: Math.max(1,1.6*root.textScale)
                opacity: .18+.14*(.5+.5*Math.sin(root.phase*6.28318))
            }

            // Starport/carrier: orbital ring with bright core.
            Rectangle {
                visible: parent.isKnownStation && !parent.isOutpost && !parent.isSettlement
                anchors.centerIn: parent
                width: parent.width*.74; height: width; radius: width/2
                color: "#071009"; border.color: root.amber; border.width: Math.max(2,2.3*root.textScale)
            }
            Rectangle {
                visible: parent.isKnownStation && !parent.isOutpost && !parent.isSettlement
                anchors.centerIn: parent
                width: parent.width*.25; height: width; radius: width/2
                color: root.amber; opacity: .94
            }

            // Compact outpost: structural cross.
            Rectangle {
                visible: parent.isOutpost
                anchors.centerIn: parent
                width: parent.width*.48; height: width; radius: 2
                color: "#071009"; border.color: root.amber; border.width: Math.max(2,2.0*root.textScale)
            }
            Rectangle { visible: parent.isOutpost; anchors.centerIn: parent; width: parent.width*.94; height: Math.max(3,4*root.textScale); color: root.amber; opacity: .82 }
            Rectangle { visible: parent.isOutpost; anchors.centerIn: parent; width: Math.max(3,4*root.textScale); height: parent.height*.94; color: root.amber; opacity: .82 }

            // Settlement: low horizontal surface marker.
            Rectangle {
                visible: parent.isSettlement
                anchors.centerIn: parent
                width: parent.width*.70; height: parent.height*.44; radius: 2
                color: "#071009"; border.color: root.amber; border.width: Math.max(2,2.0*root.textScale)
            }
            Rectangle { visible: parent.isSettlement; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: parent.height*.18; width: parent.width*.90; height: Math.max(2,3*root.textScale); color: root.amber; opacity: .76 }

            // Unknown named Status.json destination: honest target diamond.
            Rectangle {
                visible: !parent.isKnownStation
                anchors.centerIn: parent
                width: parent.width*.56; height: width
                rotation: 45
                color: "transparent"; border.color: root.amber; border.width: Math.max(2,2.0*root.textScale)
            }
            Rectangle { visible: !parent.isKnownStation; anchors.centerIn: parent; width: parent.width*.15; height: width; radius: width/2; color: root.amber }
        }

        Rectangle {
            id: inSystemTargetLabel
            x: Math.max(14*root.textScale, Math.min(root.width-width-14*root.textScale, inSystemEndpoint.x+inSystemEndpoint.width/2-width/2))
            y: parent.routeHasHyperspace
                ? Math.min(root.height-height-10*root.textScale, inSystemEndpoint.y+inSystemEndpoint.height+12*root.textScale)
                : Math.max(44*root.textScale, inSystemEndpoint.y-height-14*root.textScale)
            width: Math.max(190,Math.min(300*root.textScale,root.width*.38))
            height: Math.max(40,inSystemTargetText.implicitHeight+14*root.textScale)
            radius: 3
            color: "#071009"; border.color: "#6c5a31"; border.width: 1
            opacity: .97
            Text {
                id: inSystemTargetText
                x: 7*root.textScale; width: parent.width-14*root.textScale
                anchors.verticalCenter: parent.verticalCenter
                text: root.inSystemTargetKind + " // " + root.inSystemTargetName
                color: "#e3cf92"
                font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(11,13*root.textScale)
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WrapAnywhere
            }
        }
    }

    // Direction-of-travel chevrons. These move from ORIGIN toward TARGET
    // and are intentionally dimmer than star nodes so route metadata stays primary.
    Repeater {
        model: root.animateDirection && root.waypoints && root.waypoints.length > 1 ? 4 : 0
        Item {
            readonly property real travelFrac: (root.phase + index*0.245) % 1.0
            readonly property real travelEndFrac: root.inSystemTargetVisible && (!root.waypoints || root.waypoints.length <= 1) ? 0.58 : 1.0
            readonly property real plottedFrac: travelFrac * travelEndFrac
            readonly property real routeAngle: Math.atan2(parent.height*(-0.44), parent.width*0.77) * 180 / Math.PI
            x: parent.width*(.10 + .77*plottedFrac) - width/2
            y: parent.height*(.70 - .44*plottedFrac) - height/2
            width: 18*root.textScale; height: 18*root.textScale
            rotation: routeAngle
            opacity: 0.22 + 0.42*(1.0 - Math.abs(travelFrac-.5))
            Text {
                anchors.centerIn: parent
                text: "›"
                color: root.green
                font.family: "Consolas"; font.bold: true
                font.pixelSize: Math.max(14, 18*root.textScale)
            }
        }
    }

    Row {
        x: 18*root.textScale; y: 16*root.textScale; spacing: 19*root.textScale
        Row {
            spacing: 5*root.textScale
            Rectangle { width: 8*root.textScale; height: 8*root.textScale; radius: 4*root.textScale; color: root.scoopableColor; anchors.verticalCenter: parent.verticalCenter }
            Text { text: "SCOOPABLE"; color: "#86a58d"; font.family: "Consolas"; font.pixelSize: Math.max(12,13*root.textScale); font.bold: true }
        }
        Row {
            spacing: 5*root.textScale
            Rectangle { width: 8*root.textScale; height: 8*root.textScale; radius: 4*root.textScale; color: root.nonScoopableColor; anchors.verticalCenter: parent.verticalCenter }
            Text { text: "NON-SCOOPABLE"; color: "#86a58d"; font.family: "Consolas"; font.pixelSize: Math.max(12,13*root.textScale); font.bold: true }
        }
        Row {
            spacing: 5*root.textScale
            Rectangle { width: 8*root.textScale; height: 8*root.textScale; radius: 4*root.textScale; color: root.unknownColor; anchors.verticalCenter: parent.verticalCenter }
            Text { text: "UNKNOWN"; color: "#86a58d"; font.family: "Consolas"; font.pixelSize: Math.max(12,13*root.textScale); font.bold: true }
        }
    }

    Text {
        text: "ORIGIN // " + root.origin
        x: 18*root.textScale; y: parent.height-54*root.textScale
        color: "#86a58d"; font.family: "Consolas"; font.pixelSize: 18*root.textScale; font.bold: true
        width: parent.width*.52; elide: Text.ElideRight
    }
    Text {
        text: root.inSystemTargetVisible ? ("TARGET // " + root.inSystemTargetName) : ("TARGET // " + root.destination)
        anchors.right: parent.right; anchors.rightMargin: 18*root.textScale
        y: 16*root.textScale
        color: root.inSystemTargetVisible ? root.amber : (root.destination === "NO ROUTE" ? "#718178" : root.green)
        font.family: "Consolas"; font.pixelSize: 19*root.textScale; font.bold: true
        width: parent.width*.45; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight
    }

    Rectangle {
        width: parent.width*.18; height: Math.max(1,2*root.textScale)
        x: (parent.width+width)*root.phase-width; y: parent.height*.53
        color: root.green; opacity: .10
    }
}
