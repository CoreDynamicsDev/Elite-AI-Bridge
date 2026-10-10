// Embossed label-maker tape. Sizes itself to the text.
import QtQuick
import "."

Item {
    id: tape
    property string text: ""
    property bool red: false
    property bool small: false
    property real tilt: -0.4
    implicitWidth: label.implicitWidth + (small ? 18 : 24) * Theme.s
    implicitHeight: label.implicitHeight + (small ? 3 : 5) * Theme.s
    width: implicitWidth; height: implicitHeight
    rotation: tilt
    Rectangle { x: 0; y: 2 * Theme.s; width: parent.width; height: parent.height; color: "black"; opacity: 0.55; radius: 1 }
    Rectangle {
        anchors.fill: parent; radius: 1; clip: true; color: tape.red ? "#7d1d17" : "#141414"
        Image { anchors.fill: parent; source: "textures/tex_tape.png"; fillMode: Image.Tile; opacity: tape.red ? 0.35 : 1 }
    }
    Text {
        id: label
        anchors.centerIn: parent
        text: tape.text.toUpperCase()
        font.family: Theme.labelFont; font.weight: Font.DemiBold
        font.pixelSize: Math.max(9, (tape.small ? 13 : 17) * Theme.s); font.letterSpacing: (tape.small ? 2.5 : 3.5) * Theme.s
        color: Theme.tapeText
        style: Text.Raised; styleColor: "#30000000"
    }
}
