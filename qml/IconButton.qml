import QtQuick
import QtQuick.Controls

// A small button with an icon (an SVG path, see Icon) or a short label, and
// a tooltip below it, with the keys that do the same, if any.
AbstractButton {
    id: button

    required property Theme theme
    property string iconPath
    property real iconRotation
    // Text instead of an icon, maybe underlined.
    property string label
    property bool underline
    property color color: theme.text
    property string tip
    property list<string> shortcuts

    implicitWidth: 22 * theme.zoom
    implicitHeight: 22 * theme.zoom
    padding: 0
    focusPolicy: Qt.NoFocus
    hoverEnabled: true
    opacity: enabled ? 1 : 0.4
    Accessible.name: tip || label

    Tip {
        theme: button.theme
        visible: button.hovered && button.tip !== ""
        text: button.tip
        shortcuts: button.shortcuts
        x: Math.round((button.width - width) / 2)
        y: button.height + 6 * button.theme.zoom
    }

    background: Rectangle {
        radius: 3 * button.theme.zoom
        color: button.checked ? button.theme.checked : button.hovered || button.pressed ? button.theme.hover : "transparent"
        border.color: button.checked || button.visualFocus ? button.theme.accent : "transparent"
    }
    contentItem: Item {
        Icon {
            anchors.centerIn: parent
            visible: button.iconPath !== ""
            theme: button.theme
            path: button.iconPath
            color: button.color
            rotation: button.iconRotation
        }
        Text {
            anchors.centerIn: parent
            visible: button.label !== ""
            text: button.label
            font.pixelSize: Math.round(12 * button.theme.zoom)
            font.underline: button.underline
            color: button.color
        }
    }
}
