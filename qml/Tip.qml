import QtQuick
import QtQuick.Controls

// A tooltip in the style of the hover box, with the keys that do the same
// (`shortcut`, if any) after its text, as code: in the editor's font, on a
// shade of their own. Whoever shows it places it.
ToolTip {
    id: tip

    required property Theme theme
    property string shortcut

    delay: 600
    leftPadding: 8 * theme.zoom
    rightPadding: 8 * theme.zoom
    topPadding: 4 * theme.zoom
    bottomPadding: 4 * theme.zoom
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

    contentItem: Row {
        spacing: 6 * tip.theme.zoom

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: tip.text
            font.pixelSize: Math.round(12 * tip.theme.zoom)
            color: tip.theme.text
            textFormat: Text.PlainText
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: tip.shortcut !== ""
            width: keys.implicitWidth
            height: keys.implicitHeight
            radius: 3 * tip.theme.zoom
            color: tip.theme.code

            Text {
                id: keys

                leftPadding: 4 * tip.theme.zoom
                rightPadding: 4 * tip.theme.zoom
                topPadding: 1 * tip.theme.zoom
                bottomPadding: 1 * tip.theme.zoom
                text: tip.shortcut
                font.family: tip.theme.font.family
                font.pixelSize: Math.round(12 * tip.theme.zoom)
                color: tip.theme.text
                textFormat: Text.PlainText
            }
        }
    }
    background: Panel {
        theme: tip.theme
    }
}
