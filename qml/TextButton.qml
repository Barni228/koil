import QtQuick
import QtQuick.Controls

// A button with a label, in a window (Settings, Shortcuts), which Tab
// reaches, and Space or Enter clicks.
AbstractButton {
    id: textButton

    required property Theme theme
    // The default one, which Enter clicks (Save), in the accent's color.
    property bool primary

    implicitWidth: implicitContentWidth + 24 * theme.zoom
    implicitHeight: 26 * theme.zoom
    opacity: enabled ? 1 : 0.4
    focusPolicy: Qt.TabFocus
    hoverEnabled: true
    Accessible.name: text
    Keys.onReturnPressed: click()
    Keys.onEnterPressed: click()

    background: Rectangle {
        radius: 4 * textButton.theme.zoom
        color: textButton.primary ? (textButton.pressed ? Qt.darker(textButton.theme.accent, 1.15) : textButton.theme.accent)
            : textButton.hovered || textButton.pressed ? Qt.tint(textButton.theme.field, textButton.theme.hover)
            : textButton.theme.field
        border.color: textButton.visualFocus ? (textButton.primary ? textButton.theme.windowText : textButton.theme.accent)
            : textButton.primary ? textButton.theme.accent : textButton.theme.fieldBorder
    }
    contentItem: Text {
        text: textButton.text
        font.pixelSize: Math.round(13 * textButton.theme.zoom)
        color: textButton.primary ? textButton.theme.highlightedText : textButton.theme.windowText
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
