import QtQuick

Item {
    id: root
    property color panelColor: "#070907"
    property color metalDark: "#11100f"
    property color metalMid: "#2e2c28"
    property color edgeLight: "#5b554a"
    property color edgeWarm: "#8b7447"
    property real bevel: 9
    property bool crt: true
    property bool heavy: true
    default property alias contentData: content.data

    Rectangle {
        x: 5; y: 7; width: parent.width; height: parent.height
        radius: 3
        color: "#000000"
        opacity: 0.76
    }

    Rectangle {
        id: housing
        anchors.fill: parent
        radius: 3
        border.color: "#040403"
        border.width: 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#655844" }
            GradientStop { position: 0.05; color: "#4a4032" }
            GradientStop { position: 0.18; color: "#302920" }
            GradientStop { position: 0.55; color: "#171511" }
            GradientStop { position: 1.0; color: "#080807" }
        }
    }

    Canvas {
        anchors.fill: housing
        opacity: .14
        onPaint: {
            var c = getContext("2d")
            c.reset(); c.clearRect(0,0,width,height)
            for (var i = 0; i < height; i += 5) {
                c.fillStyle = (i % 14 === 0) ? "rgba(255,232,186,0.028)" : "rgba(255,255,255,0.008)"
                c.fillRect(0, i, width, 1)
            }
            for (var j = -height; j < width; j += 14) {
                c.strokeStyle = "rgba(255,255,255,0.010)"
                c.beginPath()
                c.moveTo(j, 0)
                c.lineTo(j + height, height)
                c.stroke()
            }
        }
        onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: 3
        color: "transparent"
        border.color: "#796a51"
        border.width: 1
        opacity: .72
    }
    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        anchors.margins: 3; height: 1; color: "#e0cfab"; opacity: .18
    }
    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.margins: 3; height: 2; color: "#000000"; opacity: .45
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: root.heavy ? 8 : 6
        radius: 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0e0d0c" }
            GradientStop { position: 1.0; color: "#020202" }
        }
        border.color: "#090908"
        border.width: 2
    }

    Rectangle {
        id: screen
        anchors.fill: parent
        anchors.margins: root.heavy ? 13 : 10
        radius: 1
        color: root.panelColor
        border.color: root.metalMid
        border.width: 1
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.lighter(root.panelColor, 1.12) }
            GradientStop { position: 0.12; color: root.panelColor }
            GradientStop { position: 0.84; color: Qt.darker(root.panelColor, 1.14) }
            GradientStop { position: 1.0; color: "#020302" }
        }
    }

    Rectangle {
        anchors.fill: screen
        anchors.margins: 1
        color: "transparent"
        border.color: "#17251b"
        border.width: 1
        opacity: .56
    }
    Rectangle {
        anchors.left: screen.left; anchors.right: screen.right; anchors.top: screen.top
        height: 2; color: "#b6ab8f"; opacity: .22
    }
    Rectangle {
        anchors.top: screen.top; anchors.bottom: screen.bottom; anchors.left: screen.left
        width: 1; color: "#897c69"; opacity: .18
    }
    Rectangle {
        anchors.left: screen.left; anchors.right: screen.right; anchors.bottom: screen.bottom
        height: 3; color: "#000000"; opacity: .72
    }
    Rectangle {
        anchors.top: screen.top; anchors.bottom: screen.bottom; anchors.right: screen.right
        width: 2; color: "#000000"; opacity: .62
    }

    Rectangle {
        visible: root.crt
        anchors.left: screen.left; anchors.right: screen.right; anchors.top: screen.top
        height: screen.height * .20
        opacity: .05
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#f5f0dd" }
            GradientStop { position: 1.0; color: "#00000000" }
        }
    }

    Rectangle {
        visible: root.crt
        anchors.fill: screen
        color: "transparent"
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0d000000" }
            GradientStop { position: 1.0; color: "#26000000" }
        }
        opacity: .16
    }

    ScanGrid {
        visible: root.crt
        anchors.fill: screen
        anchors.margins: 2
        opacity: .17
        step: 30
        majorEvery: 5
    }

    Canvas {
        anchors.fill: screen
        opacity: .08
        onPaint: {
            var c = getContext("2d")
            c.reset(); c.clearRect(0,0,width,height)
            for (var i=0; i<46; ++i) {
                var x = (i*59 + 11) % Math.max(1,width)
                var y = (i*37 + 13) % Math.max(1,height)
                c.fillStyle = (i % 4 === 0) ? "rgba(42,255,128,0.024)" : "rgba(255,255,255,0.008)"
                c.fillRect(x, y, 1, 1)
            }
        }
        onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
    }

    Repeater {
        model: [
            {x: 6, y: 6}, {x: root.width - 14, y: 6},
            {x: 6, y: root.height - 14}, {x: root.width - 14, y: root.height - 14}
        ]
        Item {
            x: modelData.x; y: modelData.y; width: 9; height: 9
            Rectangle { anchors.fill: parent; radius: 4.5; color: "#181612"; border.color: "#8f7a53"; border.width: 1; opacity: .78 }
            Rectangle { x: 2.5; y: 2.5; width: 4; height: 4; radius: 2; color: "#d2b77a"; opacity: .18 }
            Rectangle { x: 1; y: 1; width: parent.width-2; height: 1; color: "#fff1d0"; opacity: .16 }
        }
    }

    Item {
        id: content
        anchors.fill: screen
        anchors.margins: 9
        clip: true
    }
}
