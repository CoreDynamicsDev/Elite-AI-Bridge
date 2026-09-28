import QtQuick

Item {
    id: root
    property string label: "SYSTEM"
    property string value: "READY"
    property color stateColor: "#2aff80"
    property bool pulse: false
    property real phase: 0.0
    property real fontScale: 1.0
    readonly property real uiScale: Math.max(0.50, root.height/36.0)

    Rectangle {
        id: socket
        width: Math.min(root.height*.72, 24*root.uiScale); height: width; radius: width/2
        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
        color: "#050605"; border.color: "#4d493f"; border.width: Math.max(1, 2*root.uiScale)
        Rectangle {
            anchors.centerIn: parent; width: parent.width*.53; height: width; radius: width/2
            color: root.stateColor
            opacity: root.pulse ? .60 + .34*Math.sin(root.phase*6.28318) : .86
        }
        Rectangle {
            anchors.centerIn: parent; width: parent.width*1.55; height: width; radius: width/2
            color: root.stateColor; opacity: root.pulse ? .08 + .05*Math.sin(root.phase*6.28318) : .04
        }
    }
    Text {
        text: root.label.toUpperCase(); color: "#c5cdbf"
        font.family: "Consolas"; font.pixelSize: Math.max(10, root.height*.34*root.fontScale)
        anchors.left: socket.right; anchors.leftMargin: 10*root.uiScale; anchors.verticalCenter: parent.verticalCenter
    }
    Text {
        text: root.value.toUpperCase(); color: root.stateColor
        font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10, root.height*.34*root.fontScale)
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
    }
}
