// Physical slide fader for levels (volumes, CRT effects, see-through).
// value 0..100. moved() while dragging (live preview), committed() on release (save it then).
import QtQuick
import "."

Item {
    id: fader
    property real value: 50
    property bool vertical: true
    property string label: ""
    property string note: ""
    property string readout: ""           // shown instead of the % when set (e.g. speech speed)
    signal moved(real value)
    signal committed(real value)
    readonly property real k: Theme.s
    implicitWidth: (vertical ? 150 : 360) * k
    implicitHeight: (vertical ? 360 : 120) * k
    readonly property real slotLen: vertical ? height - 110 * k : width - 150 * k
    readonly property real capW: (vertical ? 64 : 36) * k
    readonly property real capH: (vertical ? 36 : 64) * k
    readonly property real slotX: vertical ? width / 2 : 20 * k
    readonly property real slotY: (vertical ? 40 : 70) * k

    Dymo { visible: fader.label !== ""; text: fader.label; small: true; x: fader.vertical ? (fader.width - width) / 2 : 0; y: 0 }
    // recessed slot
    Rectangle {
        x: fader.vertical ? fader.slotX - 5 * fader.k : fader.slotX; y: fader.vertical ? fader.slotY : fader.slotY - 5 * fader.k
        width: fader.vertical ? 10 * fader.k : fader.slotLen; height: fader.vertical ? fader.slotLen : 10 * fader.k
        radius: 5 * fader.k; color: "#0b0b0a"; border.color: "#000"
    }
    // printed scale
    Repeater {
        model: 11
        Item {
            readonly property real p: index / 10
            Rectangle {
                color: "#80e1d7be"
                x: fader.vertical ? fader.slotX - 32 * fader.k : fader.slotX + p * fader.slotLen
                y: fader.vertical ? fader.slotY + fader.slotLen - p * fader.slotLen : fader.slotY + 16 * fader.k
                width: fader.vertical ? (index % 5 ? 7 : 12) * fader.k : Math.max(1, 2 * fader.k)
                height: fader.vertical ? Math.max(1, 2 * fader.k) : (index % 5 ? 7 : 12) * fader.k
            }
            Text {
                visible: index % 5 === 0
                text: index * 10
                font.family: Theme.labelFont; font.pixelSize: Math.max(9, 12 * fader.k); color: "#c8e1d7be"
                x: fader.vertical ? fader.slotX - 62 * fader.k : fader.slotX + p * fader.slotLen - width / 2
                y: fader.vertical ? fader.slotY + fader.slotLen - p * fader.slotLen - height / 2 : fader.slotY + 30 * fader.k
            }
        }
    }
    // cap
    Rectangle {
        id: knob
        width: fader.capW; height: fader.capH; radius: 4 * fader.k
        x: fader.vertical ? fader.slotX - width / 2 : fader.slotX + fader.value / 100 * fader.slotLen - width / 2
        y: fader.vertical ? fader.slotY + fader.slotLen - fader.value / 100 * fader.slotLen - height / 2 : fader.slotY - height / 2
        gradient: Gradient {
            orientation: fader.vertical ? Gradient.Vertical : Gradient.Horizontal
            GradientStop { position: 0.0; color: "#e8e4d8" }
            GradientStop { position: 0.45; color: "#b9b4a6" }
            GradientStop { position: 1.0; color: "#8d897e" }
        }
        border.color: drag.containsMouse || drag.pressed ? "#7dff9c" : "#2a2822"; border.width: drag.containsMouse || drag.pressed ? 2 : 1
        Repeater { model: [0.3, 0.5, 0.7]; Rectangle { color: "#40000000"
            x: fader.vertical ? 8 * fader.k : knob.width * modelData - 1; y: fader.vertical ? knob.height * modelData - 1 : 8 * fader.k
            width: fader.vertical ? knob.width - 16 * fader.k : 2; height: fader.vertical ? 2 : knob.height - 16 * fader.k } }
        Rectangle { color: "white"; x: fader.vertical ? 3 * fader.k : knob.width / 2 - 1.5 * fader.k; y: fader.vertical ? knob.height / 2 - 1.5 * fader.k : 3 * fader.k
            width: fader.vertical ? knob.width - 6 * fader.k : 3 * fader.k; height: fader.vertical ? 3 * fader.k : knob.height - 6 * fader.k }
    }
    Text {
        text: fader.readout !== "" ? fader.readout : Math.round(fader.value) + "%"
        font.family: Theme.labelFont; font.pixelSize: Math.max(12, 22 * fader.k); color: "#d9ffe3"
        x: fader.vertical ? (fader.width - width) / 2 : fader.slotX + fader.slotLen + 34 * fader.k
        y: fader.vertical ? fader.slotY + fader.slotLen + 22 * fader.k : fader.slotY - height / 2
    }
    Text {
        visible: fader.note !== ""; text: fader.note.toUpperCase(); width: fader.vertical ? fader.width : fader.slotLen
        horizontalAlignment: fader.vertical ? Text.AlignHCenter : Text.AlignLeft; wrapMode: Text.WordWrap
        font.family: Theme.labelFont; font.pixelSize: Math.max(9, 12 * fader.k); font.letterSpacing: 1.5 * fader.k; color: "#8ce1d7be"
        x: fader.vertical ? 0 : fader.slotX; y: fader.vertical ? fader.slotY + fader.slotLen + 54 * fader.k : fader.slotY + 50 * fader.k
    }
    // drag anywhere along the slot; click jumps there
    MouseArea {
        id: drag
        x: fader.vertical ? fader.slotX - fader.capW / 2 - 6 * fader.k : fader.slotX - fader.capW / 2
        y: fader.vertical ? fader.slotY - fader.capH / 2 : fader.slotY - fader.capH / 2 - 6 * fader.k
        width: fader.vertical ? fader.capW + 12 * fader.k : fader.slotLen + fader.capW
        height: fader.vertical ? fader.slotLen + fader.capH : fader.capH + 12 * fader.k
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        function setFrom(mx, my) {
            var p = fader.vertical ? 1 - (my - fader.capH / 2) / fader.slotLen : (mx - fader.capW / 2) / fader.slotLen
            var v = Math.round(Math.max(0, Math.min(1, p)) * 100)
            if (v !== Math.round(fader.value)) fader.moved(v)
        }
        onPressed: (m) => setFrom(m.x, m.y)
        onPositionChanged: (m) => { if (pressed) setFrom(m.x, m.y) }
        onReleased: { Theme.cue("tick"); fader.committed(fader.value) }
    }
}
