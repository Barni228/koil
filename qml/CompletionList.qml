pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

// The options Tab shows once it can't fill in more (see Completion in
// Vim.qml), under the part being written, like VS Code's suggestions: a dir
// per row, as its line in the listing shows it (its icon, two spaces and
// its name), with the picked one highlighted and the names lined up with
// what's written. A click takes one. It lives in the window's overlay so
// the editor doesn't clip it.
Item {
    id: list

    // The Editor it shows them in: its textArea, flickable, cellAt,
    // lineHeight, charWidth and textBaseline, and vim. Untyped, as in
    // HoverBox.
    required property var editor
    required property Theme theme
    readonly property var completion: editor.active ? editor.vim.completion : null
    readonly property var options: completion ? completion.options : []
    // How many rows show at once; more scroll.
    readonly property int maxRows: 10
    readonly property real inset: 4 * theme.zoom
    // Where a row's name starts, after its icon and two spaces.
    readonly property real nameX: 2 * inset + 3 * editor.charWidth
    // Where the part being written starts, in the overlay's coordinates.
    property rect anchorRect

    // Once the editor has the edit that showed them, which may also have
    // scrolled it.
    function place() {
        if (!completion)
            return;
        const r = editor.cellAt(completion.start);
        anchorRect = editor.textArea.mapToItem(parent, r.x, r.y, r.width, r.height);
        rows.positionViewAtIndex(completion.index, ListView.Contain);
    }

    parent: Overlay.overlay
    visible: completion !== null && editor.textArea.activeFocus
    width: frame.width
    height: frame.height
    x: Math.max(8, Math.min(anchorRect.x - nameX, (parent ? parent.width : 0) - width - 8))
    y: anchorRect.y + anchorRect.height + 2 * theme.zoom
    onCompletionChanged: Qt.callLater(place)

    Connections {
        target: list.editor.flickable

        function onContentXChanged() {
            list.place();
        }
    }

    // The longest name, to make room for.
    TextMetrics {
        id: longest

        font: list.theme.font
        text: list.options.reduce((a, o) => o.name.length > a.length ? o.name : a, "")
    }

    Panel {
        id: frame

        theme: list.theme
        width: Math.min(list.nameX + longest.advanceWidth + 3 * list.inset, (list.parent ? list.parent.width : 600) - 16)
        height: rows.height + 2 * list.inset

        ListView {
            id: rows

            x: list.inset
            y: list.inset
            width: parent.width - 2 * list.inset
            height: Math.min(count, list.maxRows) * list.editor.lineHeight
            model: list.options
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollIndicator.vertical: ScrollIndicator {}

            delegate: Rectangle {
                id: row

                required property var modelData
                required property int index

                width: ListView.view.width
                height: list.editor.lineHeight
                radius: 3 * list.theme.zoom
                color: list.completion && index === list.completion.index ? list.theme.highlight
                    : pointer.containsMouse ? list.theme.hover : "transparent"

                Text {
                    x: list.inset
                    y: list.editor.textBaseline - baselineOffset
                    text: row.modelData.icon
                    font: list.theme.font
                    color: row.modelData.colors[list.theme.dark ? 0 : 1]
                    textFormat: Text.PlainText
                }

                Text {
                    x: list.nameX - list.inset
                    y: list.editor.textBaseline - baselineOffset
                    width: row.width - x - list.inset
                    text: row.modelData.name
                    font: list.theme.font
                    color: list.theme.directory
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: pointer

                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: list.editor.vim.takeCompletion(row.index)
                }
            }
        }
    }
}
