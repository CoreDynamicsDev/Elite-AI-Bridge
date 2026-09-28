import QtQuick

Item {
    id: root
    property string text: "TOGGLE"
    property string subtext: ""
    property bool checked: false
    property color accent: "#2aff80"
    property real scaleUnit: 1.0
    signal toggled(bool requestedChecked)

    Rectangle {
        anchors.fill: parent
        radius: 3
        color: "#080a08"
        border.color: root.checked ? root.accent : "#3f443e"
        border.width: root.checked ? 2 : 1
        Rectangle { anchors.fill: parent; anchors.margins: 4; color: "transparent"; border.color: root.checked ? "#203a27" : "#20251f"; border.width: 1 }
    }

    Text {
        text: root.text
        x: 12*root.scaleUnit; y: 8*root.scaleUnit
        width: parent.width-24*root.scaleUnit
        color: root.checked ? root.accent : "#aaa99f"
        font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(13,17*root.scaleUnit)
        elide: Text.ElideRight
    }

    Rectangle {
        id: track
        x: 12*root.scaleUnit; y: 34*root.scaleUnit
        width: Math.max(78,96*root.scaleUnit); height: Math.max(22,28*root.scaleUnit)
        radius: height/2
        color: root.checked ? "#0b170f" : "#111210"
        border.color: root.checked ? root.accent : "#454a44"
        border.width: 2

        Text {
            text: root.checked ? "ON" : "OFF"
            anchors.verticalCenter: parent.verticalCenter
            x: root.checked ? 14*root.scaleUnit : parent.width-width-14*root.scaleUnit
            color: root.checked ? root.accent : "#8b8d86"
            font.family: "Consolas"; font.bold: true
            font.pixelSize: Math.max(10,11*root.scaleUnit)
        }

        Rectangle {
            width: parent.height-6*root.scaleUnit; height: width; radius: width/2
            y: 3*root.scaleUnit
            x: root.checked ? parent.width-width-3*root.scaleUnit : 3*root.scaleUnit
            color: root.checked ? root.accent : "#676a64"
            border.color: root.checked ? Qt.lighter(root.accent,1.35) : "#8b8d86"
            Behavior on x { NumberAnimation { duration: 110 } }
            Rectangle { anchors.centerIn: parent; width: parent.width*1.8; height: width; radius: width/2; color: root.accent; opacity: root.checked ? .10 : 0 }
        }
    }

    Text {
        text: root.subtext
        x: track.x + track.width + 12*root.scaleUnit; y: 35*root.scaleUnit
        width: parent.width-x-10*root.scaleUnit; height: Math.max(22,30*root.scaleUnit)
        color: root.checked ? root.accent : "#737970"
        font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,12*root.scaleUnit)
        wrapMode: Text.WordWrap; maximumLineCount: 2; clip: true
    }

    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.toggled(!root.checked) }
}
