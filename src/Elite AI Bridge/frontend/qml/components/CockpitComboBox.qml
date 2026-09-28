import QtQuick
import QtQuick.Controls

ComboBox {
    id: control
    property color accentColor: "#2aff80"
    property color textColor: "#d9d4c2"
    property color mutedColor: "#859086"
    property color idleBorder: "#31513a"
    property real scaleUnit: 1.0

    font.family: "Consolas"
    font.bold: true
    font.pixelSize: Math.max(12, 15 * scaleUnit)

    contentItem: Text {
        leftPadding: 12 * control.scaleUnit
        rightPadding: 42 * control.scaleUnit
        text: control.displayText
        color: control.enabled ? control.accentColor : control.mutedColor
        font: control.font
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    indicator: Text {
        text: "▼"
        color: control.hovered || control.down ? control.accentColor : control.textColor
        font.family: "Consolas"
        font.bold: true
        font.pixelSize: Math.max(12, 16 * control.scaleUnit)
        anchors.right: parent.right
        anchors.rightMargin: 13 * control.scaleUnit
        anchors.verticalCenter: parent.verticalCenter
    }

    background: Rectangle {
        color: control.down ? "#102016" : (control.hovered ? "#0c1a11" : "#061008")
        border.color: control.hovered || control.activeFocus ? control.accentColor : control.idleBorder
        border.width: control.hovered || control.activeFocus ? 2 : 1
    }
}
