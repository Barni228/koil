pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

// What the listing can be sorted by, under the sort button (`anchor`),
// while gs waits for the key that picks one: a row per sort, with its key
// and its first way, and its shifted key and the other way, each as code
// (as in a Tip). The sort in use is marked. A click on one picks it. It
// lives in the window's overlay, over the listing.
Item {
    id: menu

    required property Theme theme
    // As main.qml's sorts: { key, by, label, first, other }.
    required property var sorts
    // The sort in use: what it's by, and whether the other way round.
    property string sort: ""
    property bool reverse: false
    // What it's put under, right-aligned with it.
    property Item anchor
    readonly property real inset: 6 * theme.zoom
    readonly property int fontSize: Math.round(13 * theme.zoom)
    // How wide each column's texts are, so they line up.
    readonly property real labelWidth: widest(sorts.map(s => s.label), metrics.font)
    readonly property real firstWidth: widest(sorts.map(s => s.first), metrics.font)
    readonly property real otherWidth: widest(sorts.map(s => s.other), metrics.font)

    // The key of a sort that was clicked (shifted for the other way).
    signal picked(string key)

    // How wide the widest of `texts` is in `font`, metrics' (whose
    // changes the widths follow, as the zoom changes it).
    function widest(texts, font) {
        return font.pixelSize > 0 ? Math.max(0, ...texts.map(t => metrics.advanceWidth(t))) : 0;
    }

    // Under the anchor, as far right as its right edge, but in the window.
    function place() {
        if (!anchor || !parent)
            return;
        const p = anchor.mapToItem(parent, anchor.width, anchor.height);
        x = Math.max(8, Math.min(p.x, parent.width - 8) - width);
        y = p.y + 4 * theme.zoom;
    }

    parent: Overlay.overlay
    width: frame.width
    height: frame.height
    onVisibleChanged: place()
    onWidthChanged: place()

    Connections {
        target: menu.parent

        function onWidthChanged() {
            menu.place();
        }
    }

    // Measures the texts in the font they're shown in.
    Text {
        id: sample

        visible: false
        font.pixelSize: menu.fontSize
    }

    FontMetrics {
        id: metrics

        font: sample.font
    }

    // A way to sort: its key, as code, and what it does. Marked if it's
    // the one in use, and picked with a click.
    component Choice: Rectangle {
        id: choice

        required property string key
        required property string text
        required property bool current
        // How wide its text is laid out, to line up with the others.
        property real textWidth

        width: row.width + 2 * menu.inset
        height: row.height + menu.inset
        radius: 3 * menu.theme.zoom
        color: current ? menu.theme.checked : pointer.containsMouse ? menu.theme.hover : "transparent"
        border.color: current ? menu.theme.accent : "transparent"

        Row {
            id: row

            anchors.centerIn: parent
            spacing: 6 * menu.theme.zoom

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: keyText.implicitWidth
                height: keyText.implicitHeight
                radius: 3 * menu.theme.zoom
                color: menu.theme.code

                Text {
                    id: keyText

                    leftPadding: 4 * menu.theme.zoom
                    rightPadding: 4 * menu.theme.zoom
                    topPadding: 1 * menu.theme.zoom
                    bottomPadding: 1 * menu.theme.zoom
                    text: choice.key
                    font.family: menu.theme.font.family
                    font.pixelSize: menu.fontSize
                    color: menu.theme.text
                    textFormat: Text.PlainText
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: choice.textWidth
                text: choice.text
                font.pixelSize: menu.fontSize
                color: menu.theme.text
                textFormat: Text.PlainText
            }
        }

        MouseArea {
            id: pointer

            anchors.fill: parent
            hoverEnabled: true
            onClicked: menu.picked(choice.key)
        }
    }

    Panel {
        id: frame

        theme: menu.theme
        width: content.width + 2 * menu.inset
        height: content.height + 2 * menu.inset

        Column {
            id: content

            x: menu.inset
            y: menu.inset
            spacing: menu.inset / 2

            Text {
                leftPadding: menu.inset
                text: qsTr("Sort by")
                font.pixelSize: menu.fontSize
                font.bold: true
                color: menu.theme.text
                textFormat: Text.PlainText
            }

            Repeater {
                model: menu.sorts

                Row {
                    id: sortRow

                    required property var modelData

                    spacing: menu.inset / 2

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: menu.labelWidth + 2 * menu.inset
                        leftPadding: menu.inset
                        text: sortRow.modelData.label
                        font.pixelSize: menu.fontSize
                        color: menu.theme.dim
                        textFormat: Text.PlainText
                    }
                    Choice {
                        key: sortRow.modelData.key
                        text: sortRow.modelData.first
                        textWidth: menu.firstWidth
                        current: menu.sort === sortRow.modelData.by && !menu.reverse
                    }
                    Choice {
                        key: sortRow.modelData.key.toUpperCase()
                        text: sortRow.modelData.other
                        textWidth: menu.otherWidth
                        current: menu.sort === sortRow.modelData.by && menu.reverse
                    }
                }
            }
        }
    }
}
