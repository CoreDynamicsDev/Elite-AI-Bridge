import QtQuick

Item {
    id: root
    property string text: "OPTION"
    property bool selected: false
    property real scaleUnit: 1.0
    signal clicked()
    property bool hovered: mouse.containsMouse
    property bool down: mouse.pressed

    Rectangle { x:3; y:4; width:parent.width; height:parent.height; radius:4; color:"#000000"; opacity:.75 }
    Rectangle {
        anchors.fill: parent; radius:4
        color: root.selected ? "#092317" : "#181610"
        border.color: root.selected ? "#2aff80" : (root.hovered ? "#a38b5d" : "#5d523e")
        border.width: root.selected ? 2 : 1
    }
    Rectangle {
        anchors.fill:parent; anchors.margins:4; radius:2
        color: root.down ? "#10120e" : (root.selected ? "#0d2d1e" : "#252219")
        border.color: root.selected ? "#1ca85a" : "#332f25"; border.width:1
    }
    Rectangle { x:9*root.scaleUnit; anchors.verticalCenter:parent.verticalCenter; width:12*root.scaleUnit; height:12*root.scaleUnit; radius:2; color:"#050706"; border.color:root.selected?"#2aff80":"#655c48"; border.width:1
        Rectangle { anchors.fill:parent; anchors.margins:3; radius:1; color:root.selected?"#2aff80":"#263028"; opacity:root.selected?1:.35 }
    }
    Text { anchors.centerIn:parent; text:root.text; color:root.selected?"#dfffea":"#e6deca"; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,14*root.scaleUnit) }
    Text { visible:root.selected; anchors.right:parent.right; anchors.rightMargin:12*root.scaleUnit; anchors.verticalCenter:parent.verticalCenter; text:"SELECTED"; color:"#2aff80"; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(8,9*root.scaleUnit); opacity:.75 }
    MouseArea { id:mouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; onClicked:root.clicked() }
}
