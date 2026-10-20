import QtQuick

// Keys as code, on a shade: a tip's shortcuts, the sort menu's keys and a
// shortcut's keys in the list of them.
Rectangle {
    id: cap

    required property Theme theme
    property string text
    property real fontSize: Math.round(12 * theme.zoom)
    property alias textColor: capText.color
    // Left and right of the keys.
    property real padding: 4 * theme.zoom

    implicitWidth: capText.implicitWidth
    implicitHeight: capText.implicitHeight
    radius: 3 * theme.zoom
    color: theme.code

    Text {
        id: capText

        leftPadding: cap.padding
        rightPadding: cap.padding
        topPadding: 1 * cap.theme.zoom
        bottomPadding: 1 * cap.theme.zoom
        text: cap.text
        font.family: cap.theme.font.family
        font.pixelSize: cap.fontSize
        color: cap.theme.text
        textFormat: Text.PlainText
    }
}
