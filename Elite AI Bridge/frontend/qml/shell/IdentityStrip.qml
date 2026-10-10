// Identity strip shared by every page: CMDR, SHIP, SYSTEM, STATION, GAME STATE.
// (The clock lives in the header now: one home per piece of information.)
import QtQuick
import QtQuick.Layouts
import "../skin"

Item {
    id: strip
    readonly property real s: Theme.s

    function stateColor(v) {
        var t = String(v || "").toUpperCase()
        if (t.indexOf("OFFLINE") >= 0) return Theme.bad
        if (t.indexOf("WAITING") >= 0 || t.indexOf("STARTING") >= 0 || t.indexOf("CHARGING") >= 0) return Theme.info
        return Theme.phosphor
    }

    Plate { anchors.fill: parent; screwSize: 12 * strip.s }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 30 * strip.s; anchors.rightMargin: 30 * strip.s
        anchors.topMargin: 30 * strip.s; anchors.bottomMargin: 14 * strip.s
        spacing: 18 * strip.s
        Repeater {
            model: [
                ["CMDR", bridge.commander, 1.0],
                ["SHIP", bridge.ship, 2.0],
                ["SYSTEM", bridge.system, 1.25],
                ["STATION", bridge.station, 2.0],
                ["GAME STATE", bridge.gameState, 1.2]
            ]
            Item {
                Layout.fillWidth: true; Layout.fillHeight: true
                Layout.preferredWidth: modelData[2] * 100
                Bezel {
                    anchors.fill: parent
                    pad: 6 * strip.s
                    Text {
                        x: 16 * strip.s; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 28 * strip.s
                        text: String(modelData[1] || "-").toUpperCase()
                        color: index === 4 ? strip.stateColor(modelData[1]) : Theme.phosphor
                        font.family: Theme.crtFont; font.pixelSize: Math.max(16, 40 * strip.s); font.letterSpacing: 2 * strip.s
                        fontSizeMode: Text.HorizontalFit; minimumPixelSize: Math.max(12, 26 * strip.s)
                        elide: Text.ElideRight; maximumLineCount: 1
                    }
                }
                Dymo { x: 10 * strip.s; y: -20 * strip.s; text: modelData[0]; small: true }
            }
        }
    }
}
