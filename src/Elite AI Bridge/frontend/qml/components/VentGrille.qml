import QtQuick

Item {
    id: root
    property int slats: 9
    property color frameDark: "#11100e"
    property color edge: "#7a6b50"
    property color recess: "#050505"
    property color slat: "#25231e"
    property color shadow: "#000000"

    Rectangle {
        anchors.fill: parent
        radius: 2
        color: frameDark
        border.color: edge
        border.width: 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#312d27" }
            GradientStop { position: 0.18; color: "#1a1814" }
            GradientStop { position: 1.0; color: "#0a0908" }
        }
    }
    Rectangle {
        anchors.fill: parent; anchors.margins: 4
        radius: 1
        color: recess
        border.color: "#27241e"
        border.width: 1
    }
    Repeater {
        model: root.slats
        delegate: Item {
            property real slotH: (root.height - 16) / root.slats
            x: 12
            y: 8 + index * slotH
            width: root.width - 24
            height: Math.max(4, slotH - 4)
            Rectangle {
                anchors.fill: parent
                color: "#0c0c0b"
                border.color: "#1a1815"
                border.width: 1
            }
            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 1; color: "#5a5448"; opacity: .25 }
            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 2; color: root.shadow; opacity: .55 }
            Rectangle { x: 0; y: parent.height*.32; width: parent.width; height: parent.height*.28; color: root.slat; opacity: .95 }
        }
    }
}
