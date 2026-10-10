// Raised painted metal plate with screws. dark: true for the recessed bay texture.
import QtQuick
import "."

Item {
    id: plate
    property bool dark: false
    property bool screws: true
    property real screwSize: 16 * Theme.s
    default property alias content: inner.data

    // drop shadow (cheap: offset, no blur)
    Rectangle { x: 0; y: 8 * Theme.s; width: parent.width; height: parent.height; radius: 5 * Theme.s; color: "black"; opacity: 0.45 }
    Rectangle {
        anchors.fill: parent; radius: 5 * Theme.s; clip: true; color: "#4a4940"
        Image {
            anchors.fill: parent
            source: plate.dark ? "textures/tex_bay.jpg" : "textures/tex_plate.jpg"
            fillMode: Image.Tile; smooth: true
            sourceSize.width: plate.dark ? 1200 : 1400
        }
        // bevel: light top-left, dark bottom-right
        Rectangle { x: 0; y: 0; width: parent.width; height: 1; color: "#fffae6"; opacity: 0.2 }
        Rectangle { x: 0; y: 0; width: 1; height: parent.height; color: "#fffae6"; opacity: 0.2 }
        Rectangle { x: 0; y: parent.height - 2; width: parent.width; height: 2; color: "black"; opacity: 0.55 }
        Rectangle { x: parent.width - 2; y: 0; width: 2; height: parent.height; color: "black"; opacity: 0.55 }
    }
    Screw { visible: plate.screws; width: plate.screwSize; height: width; x: 8 * Theme.s; y: 8 * Theme.s; slot: 60 }
    Screw { visible: plate.screws; width: plate.screwSize; height: width; x: parent.width - width - 8 * Theme.s; y: 8 * Theme.s; slot: -25 }
    Screw { visible: plate.screws; width: plate.screwSize; height: width; x: 8 * Theme.s; y: parent.height - height - 8 * Theme.s; slot: 15 }
    Screw { visible: plate.screws; width: plate.screwSize; height: width; x: parent.width - width - 8 * Theme.s; y: parent.height - height - 8 * Theme.s; slot: 100 }
    Item { id: inner; anchors.fill: parent }
}
