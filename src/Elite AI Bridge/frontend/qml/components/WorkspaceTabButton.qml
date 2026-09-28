import QtQuick

Item {
    id: root
    property string text: "VIEW"
    property color accent: "#2aff80"
    property bool active: false
    property bool compact: false
    property real scaleUnit: 1.0
    signal clicked()

    property bool hovered: mouse.containsMouse
    property bool down: mouse.pressed
    property real pressOffset: down ? Math.max(1, 1.5*scaleUnit) : 0

    // Compact mechanical selector using the same brass/black/green visual language
    // as the normal cockpit buttons, while retaining the exact workspace-tab footprint.
    Rectangle {
        x: Math.max(1, 2*root.scaleUnit); y: Math.max(1, 2*root.scaleUnit)
        width: Math.max(0, parent.width - x); height: Math.max(0, parent.height - y)
        radius: Math.max(1, 2*root.scaleUnit)
        color: "#000000"; opacity: .62
    }

    Rectangle {
        anchors.fill: parent
        radius: Math.max(1, 2*root.scaleUnit)
        border.color: root.active ? root.accent : (root.hovered ? "#b89252" : "#5d5545")
        border.width: root.active ? Math.max(1, 2*root.scaleUnit) : 1
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.hovered ? "#4a4032" : "#383127" }
            GradientStop { position: 0.18; color: root.hovered ? "#2b261e" : "#242019" }
            GradientStop { position: 0.62; color: "#14130f" }
            GradientStop { position: 1.0; color: "#090a08" }
        }
    }

    Rectangle {
        id: face
        property real inset: root.compact ? Math.max(2, 3*root.scaleUnit) : Math.max(3, 5*root.scaleUnit)
        x: inset
        y: inset + root.pressOffset
        width: Math.max(0, parent.width - inset*2)
        height: Math.max(0, parent.height - inset*2)
        radius: Math.max(1, 2*root.scaleUnit)
        color: root.active ? "#0a2113" : (root.hovered ? "#181812" : "#090b09")
        border.color: root.active ? Qt.darker(root.accent, 1.25) : (root.hovered ? "#8e7a52" : "#403d33")
        border.width: 1
        Behavior on y { NumberAnimation { duration: 55 } }
    }

    Rectangle {
        x: face.x + Math.max(2, 3*root.scaleUnit)
        y: face.y + Math.max(1, 2*root.scaleUnit)
        width: Math.max(0, face.width - Math.max(4, 6*root.scaleUnit))
        height: 1
        color: "#efe0bc"
        opacity: root.down ? .05 : (root.hovered ? .28 : .15)
    }

    Rectangle {
        anchors.left: face.left; anchors.right: face.right; anchors.bottom: face.bottom
        anchors.leftMargin: Math.max(2, 3*root.scaleUnit); anchors.rightMargin: Math.max(2, 3*root.scaleUnit)
        height: root.active ? Math.max(2, 4*root.scaleUnit) : Math.max(1, 2*root.scaleUnit)
        color: root.active ? root.accent : (root.hovered ? "#7b6745" : "#252b25")
        opacity: root.active ? .96 : .72
    }

    // Small status lamp makes the selected state read as a cockpit control, not a header.
    Rectangle {
        width: root.compact ? Math.max(5, 7*root.scaleUnit) : Math.max(7, 9*root.scaleUnit)
        height: width; radius: width/2
        x: root.compact ? Math.max(7, 10*root.scaleUnit) : Math.max(10, 14*root.scaleUnit)
        anchors.verticalCenter: parent.verticalCenter
        color: root.active ? root.accent : (root.hovered ? "#6f765f" : "#323832")
        border.color: root.active ? Qt.lighter(root.accent, 1.15) : "#665d4b"
        border.width: 1
        opacity: root.active ? 1.0 : .78
    }

    Text {
        text: root.text.toUpperCase()
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.pressOffset
        color: root.active ? root.accent : (root.hovered ? "#fff4d6" : "#d9d4c2")
        font.family: "Consolas"; font.bold: true
        font.pixelSize: root.compact ? Math.max(11, 15*root.scaleUnit) : Math.max(14, 18*root.scaleUnit)
        elide: Text.ElideRight
        width: parent.width - (root.compact ? Math.max(36, 52*root.scaleUnit) : Math.max(46, 68*root.scaleUnit))
        horizontalAlignment: Text.AlignHCenter
        maximumLineCount: 1
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
