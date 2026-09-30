import QtQuick
import QtQuick.Controls

// A tooltip in the style of the hover box. Whoever shows it places it.
ToolTip {
    id: tip

    required property Theme theme

    delay: 600
    padding: 0
    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0
            to: 1
            duration: 100
        }
    }
    exit: Transition {
        NumberAnimation {
            property: "opacity"
            to: 0
            duration: 100
        }
    }

    contentItem: Text {
        leftPadding: 8 * tip.theme.zoom
        rightPadding: 8 * tip.theme.zoom
        topPadding: 4 * tip.theme.zoom
        bottomPadding: 4 * tip.theme.zoom
        text: tip.text
        font.pixelSize: Math.round(12 * tip.theme.zoom)
        color: tip.theme.text
        textFormat: Text.PlainText
    }
    background: Panel {
        theme: tip.theme
    }
}
