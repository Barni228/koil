import QtQuick
import QtQuick.Controls

// A switch for a setting that's on or off, in a window (Settings), which
// Tab reaches, and Space or Enter flips. Not `checkable`: it shows
// `checked` and emits `clicked`, leaving the setting to whoever has it,
// so its binding stays.
AbstractButton {
    id: toggle

    required property Theme theme

    readonly property real zoom: theme.zoom

    // As tall as the other controls, so the rows line up.
    implicitWidth: 34 * zoom
    implicitHeight: 26 * zoom
    focusPolicy: Qt.TabFocus
    hoverEnabled: true
    Accessible.role: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: checked
    Keys.onReturnPressed: click()
    Keys.onEnterPressed: click()

    contentItem: Item {
        Rectangle {
            id: track

            anchors.verticalCenter: parent.verticalCenter
            width: 34 * toggle.zoom
            height: 20 * toggle.zoom
            radius: height / 2
            color: {
                const color = toggle.checked ? toggle.theme.accent
                    : toggle.theme.dark ? Qt.tint(toggle.theme.window, "#40ffffff") : "#d9d9d9";
                return toggle.pressed ? Qt.darker(color, 1.15) : toggle.hovered ? Qt.tint(color, toggle.theme.hover) : color;
            }
            border.color: !toggle.visualFocus ? "transparent" : toggle.checked ? toggle.theme.windowText : toggle.theme.accent

            Behavior on color {
                ColorAnimation {
                    duration: 120
                }
            }

            Rectangle {
                width: track.height - 4 * toggle.zoom
                height: width
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                x: toggle.checked ? track.width - width - 2 * toggle.zoom : 2 * toggle.zoom
                color: "white"
                border.color: toggle.theme.dark ? "transparent" : "#26000000"

                Behavior on x {
                    NumberAnimation {
                        duration: 120
                        easing.type: Easing.InOutQuad
                    }
                }
            }
        }
    }
}
