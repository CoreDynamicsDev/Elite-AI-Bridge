import QtQuick

Item {
    id: root
    property int percent: 78
    property color green: "#2aff80"
    property color amber: "#d6a540"
    property color red: "#ff493e"
    property color levelColor: percent < 0 ? "#506454" : (percent < 18 ? red : (percent < 35 ? amber : green))
    readonly property real uiScale: Math.max(0.50, root.height/82.0)

    Text {
        text: "MAIN FUEL"; color: "#94a096"; font.family: "Consolas"
        font.pixelSize: Math.max(10, root.height*.20); anchors.left: parent.left; anchors.top: parent.top
    }
    Text {
        text: percent < 0 ? "UNKNOWN" : percent + "%"; color: root.levelColor; font.family: "Consolas"; font.bold: true
        font.pixelSize: Math.max(12, root.height*.24); anchors.right: parent.right; anchors.top: parent.top
    }
    Rectangle {
        id: tank
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: root.height*.50; color: "#050805"; border.color: "#4b554a"; border.width: Math.max(1,2*root.uiScale)
        Row {
            anchors.fill: parent; anchors.margins: 5*root.uiScale; spacing: 3*root.uiScale
            Repeater {
                model: 12
                Rectangle {
                    width: Math.max(4*root.uiScale,(parent.width-33*root.uiScale)/12); height: parent.height
                    color: root.percent >= 0 && index < Math.ceil(root.percent/100*12) ? root.levelColor : "#0c1710"
                    opacity: root.percent >= 0 && index < Math.ceil(root.percent/100*12) ? .90 : .62
                }
            }
        }
        Rectangle { width: parent.width; height: Math.max(1,2*root.uiScale); anchors.top: parent.top; color: "#9a9d88"; opacity: .15 }
    }
}
