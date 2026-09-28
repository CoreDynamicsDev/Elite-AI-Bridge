import QtQuick

Item {
    id: root
    property string text: "MODE"
    property string subtext: ""
    property color accent: "#2aff80"
    property bool active: false
    property real scaleUnit: 1.0
    signal clicked()

    property bool hovered: mouse.containsMouse
    property bool down: mouse.pressed
    property real latchOffset: root.active ? Math.max(2, 3*root.scaleUnit) : 0
    property real pressOffset: root.down ? Math.max(2, 3*root.scaleUnit) : root.latchOffset

    // Drop shadow deepens when raised and nearly disappears once the selector latches in.
    Rectangle {
        x: Math.max(2, 4*root.scaleUnit)
        y: root.active ? Math.max(2, 3*root.scaleUnit) : Math.max(4, 7*root.scaleUnit)
        width: Math.max(0, parent.width - x)
        height: Math.max(0, parent.height - y)
        radius: Math.max(2, 3*root.scaleUnit)
        color: "#000000"
        opacity: root.active ? .40 : .78
    }

    // Heavy outer mounting bezel.
    Rectangle {
        anchors.fill: parent
        radius: Math.max(2, 3*root.scaleUnit)
        border.color: root.hovered ? "#aa8c54" : "#665b47"
        border.width: 1
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.hovered ? "#5b4e3b" : "#4a4032" }
            GradientStop { position: 0.14; color: "#302a22" }
            GradientStop { position: 0.62; color: "#15130f" }
            GradientStop { position: 1.0; color: "#090907" }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: Math.max(3, 5*root.scaleUnit)
        radius: Math.max(1, 2*root.scaleUnit)
        color: "transparent"
        border.color: root.hovered ? "#b7985d" : "#4b463a"
        border.width: 1
    }

    // Button face. Active mode sits lower in the chassis to read as physically latched.
    Rectangle {
        id: face
        x: Math.max(7, 11*root.scaleUnit)
        y: Math.max(7, 10*root.scaleUnit) + root.pressOffset
        width: parent.width - x*2
        height: parent.height - Math.max(16, 21*root.scaleUnit)
        radius: Math.max(1, 2*root.scaleUnit)
        border.color: root.hovered ? "#a78b55" : "#5a5447"
        border.width: 1
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.down ? "#181610" : "#3b372c" }
            GradientStop { position: 0.12; color: root.down ? "#17150f" : "#29271f" }
            GradientStop { position: 0.62; color: "#171711" }
            GradientStop { position: 1.0; color: "#080a07" }
        }
        Behavior on y { NumberAnimation { duration: 65 } }
    }

    // Raised top highlight disappears when latched, reinforcing depth.
    Rectangle {
        x: face.x + Math.max(2, 4*root.scaleUnit)
        y: face.y + Math.max(1, 2*root.scaleUnit)
        width: face.width - Math.max(4, 8*root.scaleUnit)
        height: 1
        color: "#efe0bc"
        opacity: root.hovered ? .30 : .18
    }

    // Recessed square annunciator lens. Hover never lights it green.
    Rectangle {
        id: lampHousing
        width: Math.max(24, 32*root.scaleUnit)
        height: width
        x: face.x + Math.max(11, 16*root.scaleUnit)
        anchors.verticalCenter: face.verticalCenter
        anchors.verticalCenterOffset: root.pressOffset * .10
        radius: Math.max(1, 2*root.scaleUnit)
        color: "#050605"
        border.color: root.active ? Qt.darker(root.accent, 1.25) : "#71654e"
        border.width: 1

        Rectangle {
            anchors.fill: parent
            anchors.margins: Math.max(3, 5*root.scaleUnit)
            radius: Math.max(1, 1.5*root.scaleUnit)
            gradient: Gradient {
                GradientStop { position: 0.0; color: root.active ? Qt.lighter(root.accent, 1.12) : "#2a2b25" }
                GradientStop { position: 1.0; color: root.active ? Qt.darker(root.accent, 1.20) : "#11120f" }
            }
            opacity: root.active ? 1.0 : .32
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: -Math.max(2, 4*root.scaleUnit)
            radius: Math.max(2, 3*root.scaleUnit)
            color: root.accent
            opacity: root.active ? .08 : 0
        }
    }

    Column {
        anchors.left: lampHousing.right
        anchors.leftMargin: Math.max(12, 18*root.scaleUnit)
        anchors.right: face.right
        anchors.rightMargin: Math.max(12, 18*root.scaleUnit)
        anchors.verticalCenter: face.verticalCenter
        anchors.verticalCenterOffset: root.pressOffset * .10
        spacing: Math.max(1, 2*root.scaleUnit)

        Text {
            width: parent.width
            text: root.text.toUpperCase()
            color: root.hovered ? "#fff3d2" : "#e0dbc9"
            font.family: "Consolas"
            font.bold: true
            font.pixelSize: Math.max(11, 18*root.scaleUnit)
            fontSizeMode: Text.HorizontalFit; minimumPixelSize: 10
            elide: Text.ElideRight
            maximumLineCount: 1
        }
        Text {
            width: parent.width
            text: root.active ? "ACTIVE MODE" : root.subtext.toUpperCase()
            color: root.active ? root.accent : (root.hovered ? "#c8c0a8" : "#89928a")
            font.family: "Consolas"
            font.bold: root.active
            font.pixelSize: Math.max(10, 11*root.scaleUnit)
            fontSizeMode: Text.HorizontalFit; minimumPixelSize: 9
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }

    // Small lower detent strip reads like a hardware latch, not a web-tab underline.
    Rectangle {
        x: face.x + Math.max(5, 8*root.scaleUnit)
        y: face.y + face.height - Math.max(4, 6*root.scaleUnit)
        width: face.width - Math.max(10, 16*root.scaleUnit)
        height: 1
        color: root.hovered ? "#6f6754" : "#171a17"
        opacity: root.hovered ? .72 : .55
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
