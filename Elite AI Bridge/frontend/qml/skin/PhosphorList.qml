// A list on a CRT that scrolls inside its own screen (every-list-scrolls rule).
// Phosphor rail + draggable thumb on the right, "▼ N MORE BELOW" hint at the bottom.
// stickToEnd: live logs stay on the newest entry unless the user scrolled away ("▼ NEW ENTRIES").
import QtQuick
import "."

Item {
    id: pl
    property alias model: lv.model
    property alias delegate: lv.delegate
    property alias list: lv
    property bool stickToEnd: false
    property bool newestFirst: false          // logs with newest on top say "OLDER BELOW"
    property real fontSize: 22
    readonly property bool overflow: lv.contentHeight > pl.height + 1
    readonly property real hintHeight: fontSize * 1.15
    // rows still below the visible part (from the scroll position, so no layout loop)
    readonly property int moreBelow: overflow ? Math.round(lv.count * Math.max(0, 1 - lv.visibleArea.yPosition - lv.visibleArea.heightRatio)) : 0
    property bool _away: false

    ListView {
        id: lv
        anchors.fill: parent
        anchors.rightMargin: pl.overflow ? 26 * Theme.s : 0
        anchors.bottomMargin: pl.overflow ? pl.hintHeight + 6 * Theme.s : 0
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        onMovementEnded: pl._away = pl.stickToEnd && !atYEnd
        onCountChanged: if (pl.stickToEnd && !pl._away) Qt.callLater(positionViewAtEnd)
    }
    // rail
    Rectangle {
        id: rail
        visible: pl.overflow
        anchors.right: parent.right; anchors.rightMargin: 4 * Theme.s
        y: 0; width: 12 * Theme.s; height: lv.height
        radius: 2; color: "#73000000"; border.color: "#4d9dffb6"; border.width: 1
        Rectangle {
            id: thumb
            x: 2; width: parent.width - 4; radius: 1
            height: Math.max(20, (parent.height - 4) * lv.visibleArea.heightRatio)
            y: 2 + (parent.height - 4 - height) * (lv.visibleArea.yPosition / Math.max(0.0001, 1 - lv.visibleArea.heightRatio))
            color: "#9dffb6"; opacity: thumbArea.containsMouse || thumbArea.pressed ? 0.8 : 0.55
        }
        MouseArea {
            id: thumbArea
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            function scrollTo(my) {
                var r = Math.max(0, Math.min(1, (my - thumb.height / 2) / Math.max(1, height - thumb.height)))
                lv.contentY = r * (lv.contentHeight - lv.height) + lv.originY
            }
            onPressed: (m) => scrollTo(m.y)
            onPositionChanged: (m) => { if (pressed) scrollTo(m.y) }
        }
    }
    Text {
        id: hint
        height: pl.hintHeight; verticalAlignment: Text.AlignVCenter
        visible: pl.overflow && (pl.moreBelow > 0 || pl._away)
        anchors.left: parent.left; anchors.bottom: parent.bottom
        text: pl._away ? "▼ NEW ENTRIES // CLICK TO JUMP" : (pl.newestFirst ? "▼ OLDER BELOW" : "▼ " + pl.moreBelow + " MORE BELOW")
        font.family: Theme.crtFont; font.pixelSize: pl.fontSize * 0.9; color: Theme.phosphor; opacity: 0.6
        MouseArea { anchors.fill: parent; enabled: pl._away; cursorShape: Qt.PointingHandCursor; onClicked: { pl._away = false; lv.positionViewAtEnd() } }
    }
}
