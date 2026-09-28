import QtQuick

Item {
    id: root
    property int percent: 100
    property color good: "#2aff80"
    property color warn: "#d6a540"
    property color bad: "#ff493e"
    property color stateColor: percent < 0 ? "#506454" : (percent < 35 ? bad : (percent < 70 ? warn : good))
    readonly property real uiScale: Math.max(0.50, root.height/88.0)

    Text {
        text: "HULL INTEGRITY"; color: "#94a096"; font.family: "Consolas"
        font.pixelSize: Math.max(10, root.height*.22); anchors.left: parent.left; anchors.top: parent.top
    }
    Text {
        text: root.percent < 0 ? "UNKNOWN" : root.percent + "%"; color: root.stateColor; font.family: "Consolas"; font.bold: true
        font.pixelSize: Math.max(12, root.height*.25); anchors.right: parent.right; anchors.top: parent.top
    }
    Row {
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: root.height*.43; spacing: 4*root.uiScale
        Repeater {
            model: 10
            Rectangle {
                width: Math.max(5*root.uiScale,(parent.width-36*root.uiScale)/10); height: parent.height
                color: root.percent >= 0 && index < Math.ceil(root.percent/10) ? root.stateColor : "#101612"
                border.color: root.percent >= 0 && index < Math.ceil(root.percent/10) ? Qt.lighter(root.stateColor,1.25) : "#283027"
                border.width: 1
                opacity: root.percent >= 0 && index < Math.ceil(root.percent/10) ? .90 : .72
            }
        }
    }
}
