// Shared interaction base for every clickable skin control (interaction-spec.md).
// Fires on release inside only (drag off = nothing), ignores repeats within 300 ms,
// never goes dead: an unavailable control still hovers and answers with "denied" + reason.
import QtQuick
import "."

MouseArea {
    id: area
    property bool available: true
    property string unavailableReason: ""
    property bool holdEnabled: false          // only preset keys (hold to save)
    property int guardMs: Theme.repeatGuardMs // step arrows use a shorter guard so quick clicks count
    property int holdMs: 2000
    readonly property real holdProgress: _hold
    property real _hold: 0
    property double _last: 0
    property bool _held: false
    signal activated()
    signal denied(string reason)
    signal held()

    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton

    onPressed: { _held = false; if (holdEnabled) { _hold = 0; holdAnim.restart() } }
    onReleased: { holdAnim.stop(); _hold = 0 }
    onCanceled: { holdAnim.stop(); _hold = 0 }
    onClicked: {
        if (_held) return                      // a completed hold is not also a tap
        var now = Date.now()
        if (now - _last < guardMs) return
        _last = now
        if (!available) { Theme.cue("denied"); denied(unavailableReason); return }
        activated()
    }
    NumberAnimation {
        id: holdAnim
        target: area; property: "_hold"; from: 0; to: 1; duration: area.holdMs
        onFinished: if (area.pressed && area.containsMouse) { area._held = true; area._hold = 0; area.held() }
    }
}
