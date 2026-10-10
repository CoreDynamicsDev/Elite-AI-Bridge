// Segmented phosphor bar (hull, fuel, pips). value 0..1; segments light from the left.
import QtQuick
import "."

Row {
    id: bar
    property real value: 0
    property int segments: 24
    property color color: Theme.ok
    property bool known: true
    spacing: Math.max(1, 3 * Theme.s)
    readonly property real segW: (width - spacing * (segments - 1)) / segments
    Repeater {
        model: bar.segments
        Rectangle {
            width: bar.segW; height: bar.height
            readonly property bool lit: bar.known && (index + 0.5) / bar.segments <= bar.value
            color: lit ? bar.color : Qt.rgba(bar.color.r, bar.color.g, bar.color.b, 0.10)
            border.width: lit ? 0 : 1
            border.color: Qt.rgba(bar.color.r, bar.color.g, bar.color.b, 0.16)
        }
    }
}
