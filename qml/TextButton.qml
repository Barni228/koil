import QtQuick
import QtQuick.Controls

// A button with a label, in a window (Settings, Shortcuts), which Tab
// reaches.
AbstractButton {
    id: textButton

    required property Theme theme

    implicitWidth: implicitContentWidth + 24 * theme.zoom
    implicitHeight: 26 * theme.zoom
    opacity: enabled ? 1 : 0.4
    focusPolicy: Qt.TabFocus
    hoverEnabled: true
    Accessible.name: text

    background: Rectangle {
        radius: 4 * textButton.theme.zoom
        color: textButton.hovered || textButton.pressed ? Qt.tint(textButton.theme.field, textButton.theme.hover)
            : textButton.theme.field
        border.color: textButton.visualFocus ? textButton.theme.accent : textButton.theme.fieldBorder
    }
    contentItem: Text {
        text: textButton.text
        font.pixelSize: Math.round(13 * textButton.theme.zoom)
        color: textButton.theme.windowText
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
