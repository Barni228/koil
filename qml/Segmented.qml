pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

// One of a few options, as a row of buttons, in a window (Settings,
// Shortcuts). With the keys, it's one stop for Tab, where Left and Right
// pick the option before or after.
Rectangle {
    id: segmented

    required property Theme theme
    property var options: [] // { label }
    property int current: -1

    signal picked(int index)

    implicitWidth: row.implicitWidth + 4 * theme.zoom
    implicitHeight: 26 * theme.zoom
    radius: 4 * theme.zoom
    color: theme.field
    border.color: activeFocus ? theme.accent : theme.fieldBorder
    activeFocusOnTab: true
    Keys.onLeftPressed: {
        if (current > 0)
            picked(current - 1);
    }
    Keys.onRightPressed: {
        if (current < options.length - 1)
            picked(current + 1);
    }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 2 * segmented.theme.zoom

        Repeater {
            model: segmented.options

            AbstractButton {
                id: option

                required property var modelData
                required property int index
                readonly property bool selected: index === segmented.current

                implicitWidth: optionText.implicitWidth + 20 * segmented.theme.zoom
                implicitHeight: segmented.height - 4 * segmented.theme.zoom
                focusPolicy: Qt.NoFocus
                hoverEnabled: true
                Accessible.name: modelData.label
                Accessible.role: Accessible.RadioButton
                Accessible.checked: selected
                onClicked: segmented.picked(index)

                background: Rectangle {
                    radius: 3 * segmented.theme.zoom
                    color: option.selected ? segmented.theme.accent : option.hovered ? segmented.theme.hover : "transparent"
                }
                contentItem: Text {
                    id: optionText

                    text: option.modelData.label
                    font.pixelSize: Math.round(13 * segmented.theme.zoom)
                    color: option.selected ? segmented.theme.highlightedText : segmented.theme.windowText
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
