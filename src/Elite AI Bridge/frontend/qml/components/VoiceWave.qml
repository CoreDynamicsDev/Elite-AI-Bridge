import QtQuick

Item {
    id: root
    property color color: "#2aff80"
    property color activeColor: "#ffd36a"
    property real phase: 0.0
    property bool speaking: false
    property bool listening: false
    readonly property real uiScale: Math.max(0.50, root.height/86.0)

    property color renderColor: root.speaking ? activeColor : color

    Rectangle {
        anchors.centerIn: parent
        width: parent.width * 0.34
        height: parent.height * 0.78
        radius: 4*root.uiScale
        color: renderColor
        opacity: root.speaking ? 0.08 : (root.listening ? 0.04 : 0.02)
    }

    Row {
        anchors.centerIn: parent; spacing: 5*root.uiScale
        Repeater {
            model: 9
            Rectangle {
                width: 4*root.uiScale
                height: Math.max(5*root.uiScale, root.height*(root.speaking
                               ? (.18 + .58*(.5+.5*Math.sin((root.phase*12.56636)+index*1.05)))
                               : (.12 + .34*(.5+.5*Math.sin((root.phase*6.28318)+index*.85)))))
                radius: 2*root.uiScale; color: root.renderColor
                opacity: root.speaking ? (0.84 + 0.12*Math.sin((root.phase*12.56636)+index*.5)) : (root.listening ? .82 : .64)
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
