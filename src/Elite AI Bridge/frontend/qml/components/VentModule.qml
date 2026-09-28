import QtQuick

Item {
    id: root
    property bool animated: false
    property real phase: 0.0
    property bool showFan: true
    property int rows: 6
    property int columns: 14
    property bool horizontalMotion: false
    property real scaleUnit: 1.0

    Rectangle { x: 4*root.scaleUnit; y: 5*root.scaleUnit; width: parent.width; height: parent.height; color: "#000000"; opacity: .56; radius: 3*root.scaleUnit }

    Rectangle {
        anchors.fill: parent
        radius: 3
        border.color: "#171511"
        border.width: 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#645845" }
            GradientStop { position: 0.14; color: "#3a3228" }
            GradientStop { position: 0.56; color: "#191612" }
            GradientStop { position: 1.0; color: "#0b0a09" }
        }
    }

    Rectangle { anchors.fill: parent; anchors.margins: 4*root.scaleUnit; radius: 2*root.scaleUnit; color: "transparent"; border.color: "#8e7b58"; border.width: 1; opacity: .62 }

    Rectangle {
        id: cavity
        anchors.fill: parent; anchors.margins: 10*root.scaleUnit
        radius: 2*root.scaleUnit
        color: "#0b0c0a"
        border.color: "#26231d"
        border.width: 2
    }
    Rectangle { anchors.fill: cavity; anchors.margins: 4*root.scaleUnit; color: "#050605"; border.color: "#131410"; border.width: 1 }
    Rectangle { anchors.fill: cavity; anchors.margins: 8*root.scaleUnit; color: "#020302"; border.color: "#1a1d18"; border.width: 1 }
    Rectangle { anchors.fill: cavity; anchors.margins: 12*root.scaleUnit; color: "transparent"; border.color: "#5b5e56"; border.width: 1; opacity: .14 }
    Rectangle { anchors.left: cavity.left; anchors.right: cavity.right; anchors.top: cavity.top; anchors.margins: 10*root.scaleUnit; height: Math.max(1,root.scaleUnit); color: "#d4c39a"; opacity: .12 }

    Item {
        id: motionBay
        anchors.fill: cavity
        anchors.margins: 10*root.scaleUnit
        clip: true
        opacity: .64

        Item {
            id: fanRack
            visible: root.showFan
            width: parent.width * 0.86
            height: parent.height * 0.90
            anchors.centerIn: parent

            Row {
                anchors.fill: parent
                spacing: fanRack.width * 0.035

                Repeater {
                    model: 3
                    Item {
                        width: (fanRack.width - fanRack.width*0.07) / 3
                        height: fanRack.height

                        Rectangle {
                            anchors.centerIn: parent
                            width: Math.min(parent.width*0.93, parent.height*0.96)
                            height: width
                            radius: width / 2
                            color: "#080908"
                            border.color: "#1f251f"
                            border.width: 1
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: Math.min(parent.width*0.78, parent.height*0.80)
                            height: width
                            radius: width / 2
                            color: "transparent"
                            border.color: "#171b16"
                            border.width: 1
                        }

                        Item {
                            id: rotor
                            anchors.centerIn: parent
                            width: Math.min(parent.width*0.72, parent.height*0.74)
                            height: width
                            property real angleValue: 0
                            transform: Rotation { origin.x: rotor.width/2; origin.y: rotor.height/2; angle: rotor.angleValue }
                            NumberAnimation on angleValue {
                                from: 0
                                to: index % 2 === 0 ? 360 : -360
                                duration: 1650 + index * 170
                                loops: Animation.Infinite
                                running: root.animated
                            }

                            Repeater {
                                model: 5
                                Item {
                                    anchors.fill: parent
                                    rotation: index * 72
                                    Rectangle {
                                        width: rotor.width * 0.19
                                        height: rotor.height * 0.40
                                        radius: width / 2
                                        color: "#2f3831"
                                        opacity: .72
                                        border.color: "#4f5b50"
                                        border.width: 1
                                        x: parent.width/2 - width/2
                                        y: parent.height * 0.08
                                    }
                                }
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: rotor.width * 0.20; height: width; radius: width / 2
                                color: "#171b18"
                                border.color: "#5b665c"
                                border.width: 1
                            }
                        }
                    }
                }
            }
        }

        Item {
            visible: root.horizontalMotion && !root.showFan
            anchors.fill: parent
            clip: true
            opacity: 0.85

            Repeater {
                model: 4
                Rectangle {
                    width: parent.width * 0.28
                    height: Math.max(8, parent.height * 0.18)
                    radius: 2
                    y: parent.height * (0.11 + index * 0.19)
                    x: -width + (index * 26)
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#050605" }
                        GradientStop { position: 0.4; color: "#475346" }
                        GradientStop { position: 1.0; color: "#111512" }
                    }
                    border.color: "#788474"
                    border.width: 1
                    SequentialAnimation on x {
                        loops: Animation.Infinite
                        running: root.animated
                        NumberAnimation { from: -width; to: parent.width; duration: 3200 + index*200; easing.type: Easing.Linear }
                        PauseAnimation { duration: 100 }
                    }
                }
            }
            Rectangle {
                width: parent.width * 0.18
                height: parent.height
                x: (parent.width + width) * root.phase - width
                y: 0
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#00ffffff" }
                    GradientStop { position: 0.5; color: "#15d8c189" }
                    GradientStop { position: 1.0; color: "#00ffffff" }
                }
                opacity: .12
            }
        }
    }

    Rectangle {
        anchors.fill: cavity
        anchors.margins: 6*root.scaleUnit
        color: "#000000"
        opacity: root.showFan ? 0.16 : 0.08
    }

    // grille frame and bars
    Rectangle { anchors.fill: cavity; anchors.margins: 3*root.scaleUnit; color: "transparent"; border.color: "#0f100d"; border.width: 1 }
    Repeater {
        model: root.columns
        Rectangle {
            width: 4*root.scaleUnit
            height: cavity.height - 10*root.scaleUnit
            x: cavity.x + 5*root.scaleUnit + index * ((cavity.width - 10*root.scaleUnit) / Math.max(1, root.columns - 1)) - width / 2
            y: cavity.y + 5*root.scaleUnit
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#8a9187" }
                GradientStop { position: 0.35; color: index % 3 === 0 ? "#6a7268" : "#5d655d" }
                GradientStop { position: 1.0; color: "#343933" }
            }
            opacity: .98
        }
    }
    Repeater {
        model: root.rows
        Rectangle {
            width: cavity.width - 10*root.scaleUnit
            height: 4*root.scaleUnit
            x: cavity.x + 5*root.scaleUnit
            y: cavity.y + 5*root.scaleUnit + index * ((cavity.height - 10*root.scaleUnit) / Math.max(1, root.rows - 1)) - height / 2
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#8f968b" }
                GradientStop { position: 0.4; color: index % 2 === 0 ? "#717970" : "#606862" }
                GradientStop { position: 1.0; color: "#353a34" }
            }
            opacity: .98
        }
    }

    Repeater {
        model: [
            {x: 8*root.scaleUnit, y: root.height/2-4*root.scaleUnit}, {x: root.width-16*root.scaleUnit, y: root.height/2-4*root.scaleUnit}
        ]
        Item {
            x: modelData.x; y: modelData.y; width: 8*root.scaleUnit; height: 8*root.scaleUnit
            Rectangle { anchors.fill: parent; radius: 4*root.scaleUnit; color: "#161512"; border.color: "#8a7751"; border.width: 1; opacity: .65 }
        }
    }

    Canvas {
        anchors.fill: parent
        opacity: .10
        onPaint: {
            var c = getContext("2d")
            c.reset(); c.clearRect(0,0,width,height)
            for (var i=0;i<58;i++) {
                var x = (i*53+11)%width
                var y = (i*31+17)%height
                if (x < 14 || x > width-14 || y < 14 || y > height-14) {
                    c.fillStyle = (i%4===0) ? "rgba(255,228,170,0.14)" : "rgba(0,0,0,0.14)"
                    c.fillRect(x,y,1,1)
                }
            }
        }
        onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
    }
}
