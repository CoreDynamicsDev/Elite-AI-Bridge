import QtQuick

Row {
    id: root
    property int segments: 8
    property int value: 6
    property color onColor: "#2aff80"
    property color offColor: "#102719"
    spacing: 4
    Repeater {
        model: root.segments
        Rectangle {
            width: Math.max(6, (root.width - (root.segments-1)*root.spacing)/root.segments)
            height: root.height
            color: index < root.value ? root.onColor : root.offColor
            border.color: index < root.value ? "#7dffad" : "#183622"
            border.width: 1
            opacity: index < root.value ? .92 : .72
        }
    }
}
