// Pick one of a few values: a row of small lit buttons, the chosen one lit green.
import QtQuick
import "."

Row {
    id: sel
    property var options: []
    property int currentIndex: 0
    property real buttonWidth: 96
    property real buttonHeight: 48
    signal picked(int index)
    spacing: 6 * Theme.s
    // light the picked button straight away; follow currentIndex once the backend agrees (3 s fallback)
    property int pendingIndex: -1
    readonly property int shownIndex: pendingIndex >= 0 ? pendingIndex : currentIndex
    onCurrentIndexChanged: if (pendingIndex === currentIndex) pendingIndex = -1
    Timer { id: pendingTimer; interval: 3000; onTriggered: sel.pendingIndex = -1 }
    Repeater {
        model: sel.options
        LitButton {
            width: sel.buttonWidth; height: sel.buttonHeight
            title: modelData; pip: false; centered: true
            on: index === sel.shownIndex
            onActivated: { sel.pendingIndex = (index === sel.currentIndex ? -1 : index); pendingTimer.restart(); sel.picked(index) }
        }
    }
}
