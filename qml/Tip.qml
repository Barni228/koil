pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

// A tooltip in the style of the hover box, with the keys that do the same
// (`shortcuts`, if any) after its text, as code: each in the editor's font,
// on a shade of its own, as `code` in its text is (see CodeLabel). Whoever
// shows it places it.
ToolTip {
    id: tip

    required property Theme theme
    property list<string> shortcuts
    // Past this width (if any), the text wraps.
    property real wrapWidth: 0

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

        CodeLabel {
            anchors.verticalCenter: parent.verticalCenter
            width: tip.wrapWidth > 0 ? Math.min(implicitWidth, tip.wrapWidth) : implicitWidth
            theme: tip.theme
            markup: tip.text
            font.pixelSize: Math.round(12 * tip.theme.zoom)
            color: tip.theme.text
        }
        Repeater {
            model: tip.shortcuts

            Rectangle {
                id: key

                required property string modelData

                // Gone with the tip's button (a row of the shortcuts' list).
                anchors.verticalCenter: parent?.verticalCenter
                width: keyText.implicitWidth
                height: keyText.implicitHeight
                radius: 3 * tip.theme.zoom
                color: tip.theme.code

                Text {
                    id: keyText

                    leftPadding: 4 * tip.theme.zoom
                    rightPadding: 4 * tip.theme.zoom
                    topPadding: 1 * tip.theme.zoom
                    bottomPadding: 1 * tip.theme.zoom
                    text: key.modelData
                    font.family: tip.theme.font.family
                    font.pixelSize: Math.round(12 * tip.theme.zoom)
                    color: tip.theme.text
                    textFormat: Text.PlainText
                }
            }
        }
    }
    background: Panel {
        theme: tip.theme
    }
}
