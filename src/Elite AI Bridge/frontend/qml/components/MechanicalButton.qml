import QtQuick

Item {
    id: root
    property string text: "BUTTON"
    property string subtext: ""
    property color accent: "#2aff80"
    property color inactiveAccent: "#2d3a31"
    property bool active: false
    property bool stateful: navMode
    property bool danger: false
    property color actionFlashColor: "#2aff80"
    property bool actionFlash: false
    property bool busyPulse: false
    property real busyPulseOpacity: 1.0
    readonly property bool lampOn: enabled && (busyPulse || (stateful ? active : (danger || actionFlash)))
    readonly property color lampColor: danger ? accent : (stateful ? accent : actionFlashColor)
    property real labelScale: 1.0
    property real subtextMinSize: 10
    property bool navMode: false
    property bool showIndicator: true
    signal clicked()

    property bool hovered: mouse.containsMouse
    property bool down: mouse.pressed
    property real pressOffset: root.down ? 2 : 0

    Rectangle {
        x: 3; y: 4; width: parent.width; height: parent.height
        radius: 3; color: "#000000"; opacity: .72
    }
    Rectangle {
        anchors.fill: parent
        radius: 3
        border.color: "#100f0d"
        border.width: 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#5d503f" }
            GradientStop { position: .16; color: "#352d24" }
            GradientStop { position: .55; color: "#1a1713" }
            GradientStop { position: 1.0; color: "#0a0908" }
        }
    }
    Rectangle {
        anchors.fill: parent; anchors.margins: 3
        radius: 2; color: "transparent"
        border.color: !root.enabled ? "#3c3a34" : (root.hovered ? root.accent : "#83745a")
        border.width: root.hovered ? 2 : 1
    }
    Rectangle {
        x: 8; y: 8; width: parent.width-16; height: parent.height-16
        radius: 2; color: "#060605"
        border.color: "#050504"; border.width: 2
    }
    Rectangle {
        id: face
        x: 12; y: 11 + root.pressOffset
        width: parent.width - 24; height: parent.height - 24
        radius: 2
        border.color: root.hovered ? "#a38956" : "#5f594a"
        border.width: 1
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.down ? "#181611" : "#3a372d" }
            GradientStop { position: 0.10; color: root.down ? "#1a1812" : "#2e2d25" }
            GradientStop { position: 0.56; color: root.down ? "#151410" : "#23231d" }
            GradientStop { position: 1.0; color: "#10110d" }
        }
        Behavior on y { NumberAnimation { duration: 55 } }
    }

    Rectangle { x: face.x+2; y: face.y+2; width: face.width-4; height: 1; color: "#efe0bc"; opacity: root.down ? .08 : .22 }
    Rectangle { x: face.x+2; y: face.y+face.height-3; width: face.width-4; height: 2; color: "#000000"; opacity: .66 }
    Rectangle { x: face.x+2; y: face.y+face.height*0.48; width: face.width-4; height: 1; color: "#000000"; opacity: .10 }

    Item {
        id: indicator
        visible: root.showIndicator
        anchors.verticalCenter: face.verticalCenter
        x: face.x + 10
        width: root.navMode ? Math.max(18, parent.height*.24) : Math.max(14, parent.width*.06)
        height: root.navMode ? width : face.height - 16

        Rectangle {
            visible: root.navMode
            anchors.fill: parent
            radius: width/2
            color: "#070706"; border.color: "#645b49"; border.width: 2
            Rectangle {
                width: parent.width*.54; height: width; radius: width/2
                anchors.centerIn: parent
                color: root.lampOn ? root.lampColor : root.inactiveAccent
                opacity: root.busyPulse ? root.busyPulseOpacity : (root.lampOn ? .98 : (root.hovered ? .46 : .18))
            }
            Rectangle {
                width: parent.width*1.9; height: width*1.8; radius: width
                anchors.centerIn: parent
                color: root.lampOn ? root.lampColor : root.inactiveAccent
                opacity: root.lampOn ? .07 : .01
            }
        }
        Rectangle {
            visible: !root.navMode
            anchors.fill: parent
            radius: 2
            color: "#080807"; border.color: "#5e5646"; border.width: 1
            Rectangle {
                anchors.fill: parent; anchors.margins: 3
                radius: 1
                gradient: Gradient {
                    GradientStop { position: 0.0; color: root.lampOn ? Qt.lighter(root.lampColor, 1.05) : Qt.lighter(root.inactiveAccent, 1.02) }
                    GradientStop { position: 1.0; color: root.lampOn ? Qt.darker(root.lampColor, 1.18) : Qt.darker(root.inactiveAccent, 1.10) }
                }
                opacity: root.busyPulse ? root.busyPulseOpacity : (root.lampOn ? .96 : (root.hovered ? .38 : .16))
            }
            Rectangle {
                anchors.fill: parent; anchors.margins: -4
                radius: 2
                color: root.lampOn ? root.lampColor : root.inactiveAccent
                opacity: root.lampOn ? .08 : .01
            }
        }
    }

    Text {
        id: mainLabel
        text: root.text.toUpperCase()
        color: !root.enabled ? "#77766f" : (root.hovered ? "#fff4d6" : "#eee7d4")
        font.family: "Consolas"
        font.bold: true
        font.pixelSize: Math.max(root.navMode ? 12 : 11, root.height*(root.navMode ? .28 : .22)*root.labelScale)
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: 10
        anchors.left: root.showIndicator ? indicator.right : face.left; anchors.leftMargin: root.showIndicator ? (root.navMode ? 13 : 16) : 16
        anchors.right: face.right; anchors.rightMargin: 12
        y: root.subtext.length ? (face.y + face.height*.04) : face.y
        height: root.subtext.length ? face.height*.42 : face.height
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        maximumLineCount: 1
        clip: true
    }

    Text {
        visible: root.subtext.length > 0
        text: root.subtext.toUpperCase()
        color: root.navMode ? "#bdc7b8" : "#b2b9aa"
        font.family: "Consolas"
        font.pixelSize: Math.max(root.navMode ? 10 : Math.max(10, root.subtextMinSize), root.height*(root.navMode ? .19 : .145)*root.labelScale)
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: 9
        anchors.left: mainLabel.left
        anchors.right: face.right; anchors.rightMargin: 12
        y: face.y + face.height*.52
        height: face.height*.38
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        maximumLineCount: 1
        clip: true
    }

    Repeater {
        visible: !root.navMode
        model: [
            {x: face.x + 5, y: face.y + 5},
            {x: face.x + face.width - 11, y: face.y + 5},
            {x: face.x + 5, y: face.y + face.height - 11},
            {x: face.x + face.width - 11, y: face.y + face.height - 11}
        ]
        Item {
            x: modelData.x; y: modelData.y; width: 6; height: 6
            Rectangle { anchors.fill: parent; radius: 3; color: "#171511"; border.color: "#7f6d4d"; border.width: 1; opacity: .60 }
        }
    }


    SequentialAnimation on busyPulseOpacity {
        running: root.busyPulse
        loops: Animation.Infinite
        NumberAnimation { to: .30; duration: 360; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 1.0; duration: 360; easing.type: Easing.InOutQuad }
    }
    Timer {
        id: actionFlashTimer
        interval: 360
        repeat: false
        onTriggered: root.actionFlash = false
    }

    MouseArea {
        id: mouse; anchors.fill: parent; hoverEnabled: true
        enabled: root.enabled
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (!root.stateful && !root.danger) {
                root.actionFlash = true
                actionFlashTimer.restart()
            }
            root.clicked()
        }
    }
}
