import QtQuick

Item {
    id: root
    property string text: "SECTION"
    property color amber: "#d6a540"
    property color line: "#36533f"
    readonly property real uiScale: Math.max(0.50, root.height/36.0)

    Rectangle {
        id: tag
        height: parent.height*.72
        width: label.implicitWidth + 26*root.uiScale
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        color: "#0b0d0a"
        border.color: "#51452e"
        border.width: 1
    }
    Rectangle {
        width: 5*root.uiScale; height: 5*root.uiScale; rotation: 45; color: root.amber
        anchors.left: tag.left; anchors.leftMargin: -3*root.uiScale; anchors.verticalCenter: tag.verticalCenter
    }
    Text {
        id: label
        text: root.text.toUpperCase()
        color: root.amber
        font.family: "Consolas"
        font.bold: true
        font.pixelSize: Math.max(11, root.height*.42)
        anchors.left: tag.left; anchors.leftMargin: 13*root.uiScale
        anchors.verticalCenter: tag.verticalCenter
    }
    Rectangle {
        anchors.left: tag.right; anchors.leftMargin: 10*root.uiScale
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 1
        color: root.line
        opacity: .95
    }
    Rectangle {
        anchors.left: tag.right; anchors.leftMargin: 14*root.uiScale
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(52*root.uiScale, Math.max(0,parent.width-tag.width-20*root.uiScale)); height: Math.max(1,3*root.uiScale)
        color: root.line; opacity: .30
    }
}
