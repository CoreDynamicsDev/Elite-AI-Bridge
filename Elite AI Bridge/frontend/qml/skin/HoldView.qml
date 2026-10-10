// Cargo hold and full loadout, one view at a time (Flight Deck's event log panel).
// Moved here from Commander (step 27). Fills its parent: give it the space a Bezel would take.
import QtQuick
import "."

Item {
    id: hv
    property int view: 0          // 0 cargo hold, 1 full loadout (journal Loadout)
    readonly property real s: Theme.s
    function num(v) { return Math.round(Number(v) || 0).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",") }

    // ---------- cargo (same rows as Commander had)
    readonly property var liveCargo: bridge.commanderCargoAll || []
    property var cargo: []
    property string cargoKey: ""
    onLiveCargoChanged: {
        var k = JSON.stringify(liveCargo)
        if (k === cargoKey) return
        cargoKey = k
        cargo = liveCargo
    }
    Component.onCompleted: { cargoKey = JSON.stringify(liveCargo); cargo = liveCargo }
    readonly property int cap: bridge.cargoCapacity > 0 ? bridge.cargoCapacity : 0
    readonly property int used: Math.max(0, bridge.cargoUsed)
    readonly property int listedTons: { var n = 0; for (var i = 0; i < cargo.length; i++) n += Number(cargo[i].qty); return n }
    readonly property int limpets: { var n = 0; for (var i = 0; i < cargo.length; i++) if (cargo[i].drones) n += Number(cargo[i].qty); return n }
    readonly property var cargoShades: ["#7dff9c", "#4fc777", "#a9e8bb", "#35a35a", "#c9ffd8", "#5fdc88"]
    function cargoColor(r, i) { return r.stolen > 0 ? Theme.info : (r.drones ? Theme.dimText : cargoShades[i % cargoShades.length]) }

    // full loadout: core, optional, hardpoints, utility (the four that matter in flight are on Flight Deck)
    Bezel {
        id: loBezel
        visible: hv.view === 1
        anchors.fill: parent
        pad: 12 * hv.s
        readonly property real fs: Math.max(11, 20 * hv.s)
        readonly property var rows: {
            var out = [], last = ""
            var src = bridge.shipLoadout || []
            for (var i = 0; i < src.length; i++) {
                if (src[i].group !== last) { out.push({ head: String(src[i].group) }); last = src[i].group }
                out.push(src[i])
            }
            return out
        }
        PhosphorList {
            id: lList
            anchors.fill: parent; anchors.margins: 14 * hv.s
            fontSize: loBezel.fs
            model: loBezel.rows
            delegate: Item {
                required property var modelData
                width: lList.list.width - (lList.overflow ? 0 : 26 * hv.s)
                height: lList.fontSize * (modelData.head ? 1.7 : 1.3)
                Text { visible: !!modelData.head; anchors.bottom: parent.bottom; text: String(modelData.head || ""); color: Theme.dimText
                       font.family: Theme.crtFont; font.pixelSize: lList.fontSize * 0.8; font.letterSpacing: 2 * hv.s }
                Text { visible: !modelData.head; x: 6 * hv.s; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.62; elide: Text.ElideRight
                       text: String(modelData.name || ""); color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: lList.fontSize }
                Text { visible: !modelData.head; anchors.right: parent.right; anchors.rightMargin: 4 * hv.s; anchors.verticalCenter: parent.verticalCenter
                       text: (modelData.note ? String(modelData.note) + "   " : "") + String(modelData.rating || "")
                       color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: lList.fontSize }
            }
        }
        Text { visible: (bridge.shipLoadout || []).length === 0; anchors.centerIn: parent
               text: "WAITING FOR YOUR SHIP'S LOADOUT"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: loBezel.fs * 1.1 }
    }
    Bezel {
        id: hBezel
        visible: hv.view === 0
        anchors.fill: parent
        pad: 12 * hv.s
        readonly property real iw: width - pad * 2
        readonly property real ih: height - pad * 2
        readonly property real fs: Math.max(11, 20 * hv.s)
        Text { x: 14 * hv.s; y: 8 * hv.s
               text: hv.cap > 0 ? hv.num(hv.used) + " OF " + hv.num(hv.cap) + " T" : hv.num(hv.used) + " T"
               color: Theme.ok; font.family: Theme.crtFont; font.pixelSize: hBezel.fs }
        Text { anchors.right: parent.right; anchors.rightMargin: 14 * hv.s; y: 8 * hv.s
               text: hv.cargo.length + " TYPE" + (hv.cargo.length === 1 ? "" : "S") + "  //  " + hv.limpets + " LIMPET" + (hv.limpets === 1 ? "" : "S")
               color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: hBezel.fs * 0.8 }
        // stacked hold bar
        Rectangle {
            id: holdBar
            x: 14 * hv.s; y: hBezel.fs * 1.5
            width: hBezel.iw - 28 * hv.s; height: hBezel.fs * 0.85
            color: "#0a1a10"; border.color: "#337dff9c"; border.width: 1
            Row {
                x: 1; y: 1; height: parent.height - 2
                Repeater {
                    model: hv.cargo
                    Rectangle {
                        readonly property real total: Math.max(hv.cap, hv.used, hv.listedTons, 1)
                        height: parent.height; width: Math.max(1, (holdBar.width - 2) * Number(modelData.qty) / total)
                        color: hv.cargoColor(modelData, index); opacity: 0.8
                        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: "#06140b" }
                    }
                }
            }
        }
        Item {
            id: cHead
            x: 14 * hv.s; y: holdBar.y + holdBar.height + 10 * hv.s
            width: hBezel.iw - 28 * hv.s - 26 * hv.s; height: hBezel.fs * 0.8
            Text { text: "COMMODITY"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: hBezel.fs * 0.68 }
            Text { x: parent.width * 0.72 - width; text: "TONS"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: hBezel.fs * 0.68 }
            Text { anchors.right: parent.right; text: "NOTE"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: hBezel.fs * 0.68 }
        }
        PhosphorList {
            id: cList
            x: 14 * hv.s; y: cHead.y + cHead.height + 4 * hv.s
            width: hBezel.iw - 28 * hv.s; height: hBezel.ih - y - 8 * hv.s
            fontSize: hBezel.fs
            model: hv.cargo
            delegate: Item {
                required property var modelData
                required property int index
                width: cList.list.width - (cList.overflow ? 0 : 26 * hv.s)
                height: cList.fontSize * 1.35
                Rectangle { x: 0; anchors.verticalCenter: parent.verticalCenter; width: 6 * hv.s; height: parent.height * 0.5; color: hv.cargoColor(modelData, index); opacity: 0.85 }
                Text { x: 14 * hv.s; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.55; elide: Text.ElideRight
                       text: String(modelData.drones ? "LIMPETS" : modelData.name)
                       color: modelData.stolen > 0 ? Theme.info : Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: cList.fontSize }
                Text { x: parent.width * 0.72 - width; anchors.verticalCenter: parent.verticalCenter
                       text: hv.num(modelData.qty); color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: cList.fontSize }
                Text { anchors.right: parent.right; anchors.rightMargin: 4 * hv.s; anchors.verticalCenter: parent.verticalCenter
                       text: modelData.stolen > 0 ? (modelData.stolen < modelData.qty ? hv.num(modelData.stolen) + " STOLEN" : "STOLEN") : (modelData.drones ? "DRONES" : "")
                       color: modelData.stolen > 0 ? Theme.info : Theme.dimText; font.family: Theme.crtFont; font.pixelSize: cList.fontSize * 0.85 }
            }
        }
        Text {
            visible: hv.cargo.length === 0
            anchors.horizontalCenter: parent.horizontalCenter; y: hBezel.ih * 0.55
            text: "HOLD EMPTY"; color: Theme.dimText; font.family: Theme.crtFont; font.pixelSize: hBezel.fs * 1.2
        }
    }
}
