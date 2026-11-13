import QtQuick
import QtQuick.Controls

// A button with a label, in a window (Settings, Shortcuts), which Tab
// reaches, and Space or Enter clicks, or in a question (ConfirmDialog),
// which keeps the keys itself (no focusPolicy), and shows the key that
// clicks it after its label (`keys`).
AbstractButton {
    id: textButton

    required property Theme theme
    // The default one, which Enter clicks (Save), in the accent's color.
    property bool primary
    // The key that does the same, if any, shown as code after the label.
    property string keys
    readonly property color textColor: primary ? theme.highlightedText : theme.windowText

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
    contentItem: Item {
        implicitWidth: content.implicitWidth
        implicitHeight: content.implicitHeight

        Row {
            id: content

            anchors.centerIn: parent
            spacing: 7 * textButton.theme.zoom

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: textButton.text
                font.pixelSize: Math.round(13 * textButton.theme.zoom)
                color: textButton.textColor
            }
            KeyCap {
                anchors.verticalCenter: parent.verticalCenter
                visible: textButton.keys !== ""
                theme: textButton.theme
                text: textButton.keys
                fontSize: Math.round(11 * textButton.theme.zoom)
                textColor: textButton.textColor
                // On the accent's color, a shade that shows on it.
                color: textButton.primary ? "#33ffffff" : textButton.theme.code
            }
        }
    }
}
