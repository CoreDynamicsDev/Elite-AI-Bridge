// One row of a CRT log (Flight Deck EVENT LOG, Navigation ROUTE LOG).
// time | event | detail. A row with no detail lets the event text use the full width.
// Long text is cut to one line; the newest row (emphasize) shows up to two lines,
// and hovering a row shows up to four, so nothing needs to scroll sideways.
import QtQuick
import "."

Item {
    id: row
    property string time: ""
    property string event: ""
    property string detail: ""
    property color eventColor: Theme.phosphor
    property real fontSize: 22
    property bool emphasize: false
    property real timeW: 0.16                 // column widths as fractions of the row
    property real eventW: 0.25

    readonly property bool hovered: hover.containsMouse
    readonly property bool hasDetail: detail !== ""
    readonly property int lines: hovered ? 4 : (emphasize ? 2 : 1)
    readonly property real gapW: width * 0.015
    readonly property Text bodyText: hasDetail ? detailText : eventText

    height: Math.max(fontSize * 1.3, bodyText.implicitHeight + fontSize * 0.3)
    Behavior on height { NumberAnimation { duration: Theme.hoverInMs } }

    Rectangle { anchors.fill: parent; color: Theme.t("#147dff9c"); visible: row.hovered && (eventText.truncated || detailText.truncated || row.lines > 1) }

    Text {
        y: row.fontSize * 0.15
        width: row.width * row.timeW; elide: Text.ElideRight
        text: row.time; color: Theme.dimText
        font.family: Theme.crtFont; font.pixelSize: row.fontSize
    }
    Text {
        id: eventText
        x: row.width * row.timeW + row.gapW; y: row.fontSize * 0.15
        width: row.hasDetail ? row.width * row.eventW : row.width - x
        wrapMode: row.hasDetail ? Text.NoWrap : Text.WordWrap
        maximumLineCount: row.hasDetail ? 1 : row.lines
        elide: Text.ElideRight
        text: row.event.toUpperCase(); color: row.eventColor
        font.family: Theme.crtFont; font.pixelSize: row.fontSize; font.letterSpacing: 1 * Theme.s
    }
    Text {
        id: detailText
        visible: row.hasDetail
        x: row.width * (row.timeW + row.eventW) + row.gapW * 2; y: row.fontSize * 0.15
        width: row.width - x
        wrapMode: Text.WordWrap; maximumLineCount: row.lines; elide: Text.ElideRight
        text: row.detail.toUpperCase(); color: Theme.phosphor; opacity: 0.88
        font.family: Theme.crtFont; font.pixelSize: row.fontSize
    }
    MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
}
