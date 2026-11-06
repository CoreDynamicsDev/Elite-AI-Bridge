// Pick one value from a list that can grow: < VALUE > with arrows like the VOICE picker,
// and a click on the value drops down a scrolling list of every choice.
// options: [[value, label], ...]   value: the current value   picked(value) when changed.
// (LAB 2026-11-06, Setup > Display THEME and HOLIDAYS)
import QtQuick
import QtQuick.Controls
import "."

Item {
    id: lp
    property var options: []
    property string value: ""
    property real s: Theme.s
    property int maxRows: 7
    signal picked(string v)

    // show a new pick at once, follow the backend after (3 s fallback)
    property string pending: ""
    readonly property string shown: pending !== "" ? pending : value
    onValueChanged: if (pending === value) pending = ""
    Timer { id: pendTimer; interval: 3000; onTriggered: lp.pending = "" }

    function indexOf(v) {
        for (var i = 0; i < options.length; i++) if (String(options[i][0]) === String(v)) return i
        return -1
    }
    function labelOf(v) { var i = indexOf(v); return i >= 0 ? String(options[i][1]) : String(v || "-") }
    function choose(v) {
        if (v === shown) return
        pending = v; pendTimer.restart(); Theme.cue("tick"); picked(v)
    }
    function step(d) {
        if (!options || options.length === 0) return
        var i = Math.max(0, indexOf(shown))
        choose(String(options[(i + d + options.length) % options.length][0]))
    }

    LitButton { id: prev; x: 0; width: height; height: parent.height; centered: true; title: "<"; onActivated: lp.step(-1) }
    Rectangle {
        id: field
        x: prev.width + 6 * lp.s; width: parent.width - prev.width * 2 - 12 * lp.s; height: parent.height
        radius: 5 * lp.s; color: Theme.t("#06140b")
        border.color: fieldMouse.containsMouse || drop.opened ? Theme.screen : Theme.t("#2e4a36")
        Text {
            anchors.verticalCenter: parent.verticalCenter
            x: 12 * lp.s; width: parent.width - 40 * lp.s; elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            text: lp.labelOf(lp.shown).toUpperCase(); color: Theme.ok
            font.family: Theme.crtFont; font.pixelSize: Math.max(13, Math.min(26 * lp.s, parent.height * 0.62))
        }
        // drop arrow
        Text {
            anchors.right: parent.right; anchors.rightMargin: 10 * lp.s; anchors.verticalCenter: parent.verticalCenter
            text: drop.opened ? "▲" : "▼"; color: Theme.dimText
            font.pixelSize: Math.max(9, parent.height * 0.32)
        }
        MouseArea { id: fieldMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { if (drop.opened) drop.close(); else { Theme.cue("click"); drop.open() } } }
    }
    LitButton { anchors.right: parent.right; width: height; height: parent.height; centered: true; title: ">"; onActivated: lp.step(1) }

    Popup {
        id: drop
        x: field.x; y: field.height + 4 * lp.s
        width: field.width
        readonly property real rowH: Math.max(26, 40 * lp.s)
        height: Math.min(lp.options.length, lp.maxRows) * rowH + 8 * lp.s
        padding: 4 * lp.s
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpened: list.positionViewAtIndex(Math.max(0, lp.indexOf(lp.shown)), ListView.Center)
        background: Rectangle {
            radius: 5 * lp.s; color: Theme.t("#030b06"); border.color: Theme.screen; border.width: Math.max(1, 1.5 * lp.s)
        }
        contentItem: ListView {
            id: list
            clip: true
            model: lp.options
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: list.contentHeight > list.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff }
            delegate: Rectangle {
                required property var modelData
                required property int index
                width: list.width - (list.contentHeight > list.height ? 10 * lp.s : 0); height: drop.rowH
                readonly property bool cur: String(modelData[0]) === lp.shown
                color: rowMouse.containsMouse ? Theme.t("#123a22") : (cur ? Theme.t("#0b2616") : "transparent")
                radius: 3 * lp.s
                Text {
                    anchors.verticalCenter: parent.verticalCenter; x: 12 * lp.s; width: parent.width - 24 * lp.s; elide: Text.ElideRight
                    text: (parent.cur ? "▶ " : "  ") + String(modelData[1]).toUpperCase()
                    color: parent.cur ? Theme.ok : Theme.phosphor
                    font.family: Theme.crtFont; font.pixelSize: Math.max(12, drop.rowH * 0.6)
                }
                MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { lp.choose(String(modelData[0])); drop.close() } }
            }
        }
    }
}
