// ENGINEERING (page 14), 2026-10-28. Journal facts only: the engineered modules on the ship you're
// flying (Loadout) or in storage (StoredModules, as of your last outfitting visit), every engineer the
// game has told you about (EngineerProgress), and your manufactured + encoded materials (Materials).
// Raw materials live on Mining > RHINO + RAW. Blueprint reference / search needs a data source (later).
import QtQuick
import "../skin"

Item {
    id: en
    property var app
    signal denied(string title, string reason)
    signal notice(string title, string detail, string level)
    readonly property Item modulesTarget: modPlate
    readonly property Item engineersTarget: engPlate
    readonly property Item matsTarget: matPlate

    readonly property real s: Theme.s
    readonly property real g: Math.max(8, 14 * s)
    property int modView: 0          // 0 this ship, 1 stored
    property int matView: 0          // 0 manufactured, 1 encoded

    function up(x) { x = String(x === undefined || x === null ? "-" : x); return x === "" ? "-" : x.toUpperCase() }
    readonly property var e: bridge.engineering || ({})
    readonly property var modules: (modView === 0 ? e.modules : e.stored) || []
    readonly property var engineers: e.engineers || []
    readonly property var mats: (matView === 0 ? e.manufactured : e.encoded) || []

    readonly property real deckH: height * 0.175
    readonly property real deckY: height - deckH
    readonly property real bodyH: deckY - g
    readonly property real leftW: width * 0.58
    readonly property real rightX: leftW + g
    readonly property real rightW: width - rightX
    readonly property real engH: bodyH * 0.48

    component Caption: Text { color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: Math.max(8, 13 * en.s); font.letterSpacing: 3 * en.s }
    component Crt: Text { color: Theme.phosphor; font.family: Theme.crtFont; font.pixelSize: Math.max(11, 22 * en.s) }

    // ---------------------------------------------------------------- ENGINEERED MODULES
    Plate {
        id: modPlate
        x: 0; y: 0; width: en.leftW; height: en.bodyH
        screwSize: 13 * en.s
        Dymo { id: mDymo; x: 26 * en.s; y: 14 * en.s; text: en.modView === 0 ? "ENGINEERED // THIS SHIP" : "ENGINEERED // STORED" }
        Caption { x: mDymo.x + mDymo.width + 20 * en.s; anchors.verticalCenter: mDymo.verticalCenter
                  width: parent.width - x - 26 * en.s; elide: Text.ElideRight
                  text: en.modules.length + " MODULES" + (en.modView === 1 ? "  //  AS OF YOUR LAST OUTFITTING VISIT" : "  //  BLUEPRINT, GRADE, HOW FAR THROUGH IT") }
        Bezel {
            id: mBezel
            x: 16 * en.s; y: 50 * en.s; width: parent.width - 32 * en.s; height: parent.height - 66 * en.s
            pad: 12 * en.s
            readonly property real fs: Math.max(11, 20 * en.s)
            PhosphorList {
                id: modList
                // 2026-11-01: inset further than the other lists. This is the biggest screen, so the
                // glass curve is strongest at its sides and clipped the start of the module names.
                x: 40 * en.s; y: 8 * en.s; width: mBezel.width - mBezel.pad * 2 - 80 * en.s; height: mBezel.height - mBezel.pad * 2 - 16 * en.s
                fontSize: mBezel.fs * 0.8
                model: en.modules
                delegate: Item {
                    id: mr
                    required property var modelData
                    width: modList.list.width - (modList.overflow ? 0 : 26 * en.s); height: mBezel.fs * 2.7
                    Crt { y: 2 * en.s; width: parent.width * 0.42; elide: Text.ElideRight; font.pixelSize: mBezel.fs
                          text: mr.modelData.name + (mr.modelData.rating ? "  " + mr.modelData.rating : "") }
                    Crt { x: parent.width * 0.43; y: 2 * en.s; width: parent.width * 0.33; elide: Text.ElideRight; font.pixelSize: mBezel.fs
                          color: Theme.ok; text: mr.modelData.blueprint }
                    // grade: five pips, the current one part-filled by quality
                    Row {
                        anchors.right: parent.right; y: 6 * en.s; spacing: 4 * en.s
                        Repeater {
                            model: 5
                            Rectangle {
                                required property int index
                                readonly property real fill: index < mr.modelData.level - 1 ? 1 : (index === mr.modelData.level - 1 ? Math.max(0.15, Number(mr.modelData.quality)) : 0)
                                width: mBezel.fs * 0.9; height: mBezel.fs * 0.55; radius: 2 * en.s
                                color: "transparent"; border.color: fill > 0 ? Theme.ok : Theme.t("#447dff9c"); border.width: 1
                                Rectangle { x: 1; y: 1; height: parent.height - 2; width: (parent.width - 2) * parent.fill; color: Theme.ok; opacity: 0.85 }
                            }
                        }
                        Crt { text: "G" + mr.modelData.level; color: Theme.ok; font.pixelSize: mBezel.fs * 0.85; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Crt { y: mBezel.fs * 1.3; width: parent.width; elide: Text.ElideRight; font.pixelSize: mBezel.fs * 0.8
                          color: mr.modelData.experimental ? Theme.info : Theme.dimText
                          text: (mr.modelData.experimental ? "EXPERIMENTAL  " + mr.modelData.experimental : "NO EXPERIMENTAL")
                                + (mr.modelData.engineer ? "  //  " + mr.modelData.engineer : "")
                                + (mr.modelData.where ? "  //  " + en.up(mr.modelData.where) : "")
                                + "  //  " + Math.round(Number(mr.modelData.quality) * 100) + "% THROUGH G" + mr.modelData.level }
                    Rectangle { anchors.bottom: parent.bottom; anchors.bottomMargin: 2 * en.s; width: parent.width; height: 1; color: Theme.t("#227dff9c") }
                }
            }
            Crt { visible: en.modules.length === 0; anchors.centerIn: parent; width: mBezel.width * 0.8
                  horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; color: Theme.dimText
                  text: en.modView === 0 ? "NO ENGINEERED MODULES ON THIS SHIP // OR THE GAME HASN'T SENT ITS LOADOUT YET"
                                         : "NOTHING ENGINEERED IN STORAGE // OPEN OUTFITTING AT ANY STATION TO REFRESH THIS LIST" }
        }
    }

    // ---------------------------------------------------------------- ENGINEERS
    Plate {
        id: engPlate
        x: en.rightX; y: 0; width: en.rightW; height: en.engH
        screwSize: 13 * en.s
        Dymo { id: eDymo; x: 26 * en.s; y: 14 * en.s; text: "ENGINEERS" }
        Caption { x: eDymo.x + eDymo.width + 20 * en.s; anchors.verticalCenter: eDymo.verticalCenter
                  text: (en.e.unlocked || 0) + " UNLOCKED OF " + en.engineers.length + " KNOWN" }
        Bezel {
            id: eBezel
            x: 16 * en.s; y: 50 * en.s; width: parent.width - 32 * en.s; height: parent.height - 66 * en.s
            pad: 12 * en.s
            readonly property real fs: Math.max(11, 19 * en.s)
            PhosphorList {
                id: engList
                x: 14 * en.s; y: 8 * en.s; width: eBezel.width - eBezel.pad * 2 - 28 * en.s; height: eBezel.height - eBezel.pad * 2 - 16 * en.s
                fontSize: eBezel.fs * 0.8
                model: en.engineers
                delegate: Item {
                    required property var modelData
                    readonly property bool unlocked: modelData.progress === "UNLOCKED"
                    width: engList.list.width - (engList.overflow ? 0 : 26 * en.s); height: eBezel.fs * 1.6
                    Crt { width: parent.width * 0.5; elide: Text.ElideRight; font.pixelSize: eBezel.fs
                          color: parent.unlocked ? Theme.phosphor : Theme.dimText; text: parent.modelData.name }
                    Crt { x: parent.width * 0.52; font.pixelSize: eBezel.fs * 0.85; color: parent.unlocked ? Theme.ok : Theme.dimText
                          text: parent.modelData.progress }
                    Row {
                        visible: parent.unlocked
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 3 * en.s
                        Repeater {
                            model: 5
                            Rectangle { required property int index; width: eBezel.fs * 0.5; height: width; radius: width / 2
                                        color: index < parent.parent.modelData.rank ? Theme.ok : "transparent"
                                        border.color: Theme.t("#557dff9c"); border.width: 1 }
                        }
                    }
                }
            }
            Crt { visible: en.engineers.length === 0; anchors.centerIn: parent; width: eBezel.width * 0.8
                  horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; color: Theme.dimText
                  text: "THE ENGINEER LIST ARRIVES WHEN YOU LOAD INTO THE GAME" }
        }
    }

    // ---------------------------------------------------------------- MATERIALS
    Plate {
        id: matPlate
        x: en.rightX; y: en.engH + en.g; width: en.rightW; height: en.bodyH - y
        screwSize: 13 * en.s
        Dymo { id: tDymo; x: 26 * en.s; y: 14 * en.s; text: en.matView === 0 ? "MANUFACTURED" : "ENCODED" }
        Caption { x: tDymo.x + tDymo.width + 20 * en.s; anchors.verticalCenter: tDymo.verticalCenter
                  width: parent.width - x - 26 * en.s; elide: Text.ElideRight
                  text: en.mats.length + " KINDS  //  RAWS ARE ON MINING > RHINO + RAW" }
        Bezel {
            id: tBezel
            x: 16 * en.s; y: 50 * en.s; width: parent.width - 32 * en.s; height: parent.height - 66 * en.s
            pad: 12 * en.s
            readonly property real fs: Math.max(11, 19 * en.s)
            PhosphorList {
                id: matList
                x: 14 * en.s; y: 8 * en.s; width: tBezel.width - tBezel.pad * 2 - 28 * en.s; height: tBezel.height - tBezel.pad * 2 - 16 * en.s
                fontSize: tBezel.fs * 0.8
                model: en.mats
                delegate: Item {
                    required property var modelData
                    width: matList.list.width - (matList.overflow ? 0 : 26 * en.s); height: tBezel.fs * 1.5
                    Crt { width: parent.width * 0.8; elide: Text.ElideRight; font.pixelSize: tBezel.fs; text: parent.modelData.name }
                    Crt { anchors.right: parent.right; font.pixelSize: tBezel.fs; color: Theme.ok; text: parent.modelData.count }
                }
            }
            Crt { visible: en.mats.length === 0; anchors.centerIn: parent; width: tBezel.width * 0.8
                  horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; color: Theme.dimText
                  text: en.e.known ? "NONE OF THESE YET" : "YOUR MATERIALS ARRIVE WHEN YOU LOAD INTO THE GAME" }
        }
    }

    // ---------------------------------------------------------------- ACTION DECK
    Plate {
        id: deck
        dark: true
        screwSize: 13 * en.s
        x: 0; y: en.deckY; width: en.width; height: en.deckH
        readonly property real keyH: Math.min(height - 66 * en.s, 150 * en.s)
        readonly property real keyY: 52 * en.s + (height - 66 * en.s - keyH) / 2
        readonly property real cancelW: 270 * en.s
        Dymo { x: 26 * en.s; y: 14 * en.s; text: "ACTIONS // ENGINEERING" }
        Row {
            x: 26 * en.s; y: deck.keyY + (deck.keyH - height) / 2; spacing: 40 * en.s
            Column {
                spacing: 8 * en.s
                Caption { text: "MODULES" }
                SelectorRow { options: ["THIS SHIP", "STORED"]; buttonWidth: 170 * en.s; buttonHeight: 44 * en.s
                              currentIndex: en.modView; onPicked: (i) => en.modView = i }
            }
            Column {
                spacing: 8 * en.s
                Caption { text: "MATERIALS" }
                SelectorRow { options: ["MANUFACTURED", "ENCODED"]; buttonWidth: 170 * en.s; buttonHeight: 44 * en.s
                              currentIndex: en.matView; onPicked: (i) => en.matView = i }
            }
        }
        Item {
            x: deck.width - deck.cancelW - 40 * en.s; y: deck.keyY; width: deck.cancelW; height: deck.keyH
            DeckKey {
                anchors.fill: parent
                title: "CANCEL"; legend: "STOP ALL AUTOMATION"
                cap: "red"; hazard: true
                tooltip: "STOP ALL AUTOMATION"; tooltipDetail: "BRIDGE RELEASES YOUR CONTROLS"
                onActivated: bridge.requestCommand("cancel")
            }
        }
    }
}
