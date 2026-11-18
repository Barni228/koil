import QtQuick
import QtQuick.Controls

// The status line under the editor: vim's message, mode or command line
// (with its cursor and selection, which the mouse sets too), and the
// cursor's position or what vim waits for.
Pane {
    id: bar

    required property Vim vim
    required property Theme theme

    // The command line `line` as the status line shows it: its parts in
    // their colors (see Vim.commandLineParts), as styled text, where its
    // spaces are no-break ones, which it doesn't run together.
    function commandLineHtml(line) {
        const html = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/ /g, "&nbsp;");
        let shown = "", at = 0;
        for (const p of bar.vim.commandLineParts(line)) {
            shown += html(line.slice(at, p.start)) + "<font color=\"" + bar.theme.commandColor(p.kind) + "\">"
                + html(line.slice(p.start, p.end)) + "</font>";
            at = p.end;
        }
        return shown + html(line.slice(at));
    }

    // The place in the command line the pointer at `x` is nearest to: an
    // index as Vim's commandCursor, after the character it's past the
    // middle of.
    function commandPositionAt(x) {
        const line = bar.vim.commandLine;
        let left = statusFont.advanceWidth(line.slice(0, 1));
        for (let i = 1; i < line.length; i++) {
            const right = statusFont.advanceWidth(line.slice(0, i + 1));
            if (x < (left + right) / 2)
                return i;
            left = right;
        }
        return line.length;
    }

    // Whether `text` fits in the status line.
    function fits(text) {
        statusMetrics.text = text;
        return statusMetrics.advanceWidth <= status.width;
    }

    contentHeight: position.implicitHeight
    padding: 4
    leftPadding: 8
    rightPadding: 8

    Label {
        id: status

        anchors.left: parent.left
        anchors.right: position.left
        // A message too long to fit loses its middle, as its end often
        // says why (a path can be long); the command line its end, as
        // its cursor is measured from its start.
        elide: bar.vim.commandLine === "" ? Text.ElideMiddle : Text.ElideRight
        font.family: bar.vim.fontFamily
        font.pixelSize: bar.vim.fontSize
        textFormat: bar.vim.commandLine === "" ? Text.PlainText : Text.StyledText
        color: bar.vim.commandLine === "" && (bar.vim.message !== "" ? bar.vim.messageIsError : bar.vim.wordsFailed)
            ? "#d33" : bar.theme.windowText
        text: bar.vim.commandLine ? bar.commandLineHtml(bar.vim.commandLine) : bar.vim.message || bar.vim.modeLabel || " "

        // For what's shown here or not (see fits).
        TextMetrics {
            id: statusMetrics

            font: status.font
        }

        // Measured with TextMetrics, whose widths are properties, so they
        // follow font size changes (FontMetrics.advanceWidth() is a call).
        TextMetrics {
            id: beforeCursor

            font: status.font
            text: bar.vim.commandLine.slice(0, bar.vim.commandCursor)
        }
        TextMetrics {
            id: underCursor

            font: status.font
            text: commandCursor.character || " "
        }
        TextMetrics {
            id: beforeSelection

            font: status.font
            text: bar.vim.commandLine.slice(0, Math.max(0, bar.vim.commandSelectionStart))
        }
        TextMetrics {
            id: selected

            font: status.font
            text: bar.vim.commandSelecting
                ? bar.vim.commandLine.slice(bar.vim.commandSelectionStart, bar.vim.commandSelectionEnd) : ""
        }
        // For a press's place (see commandPositionAt).
        FontMetrics {
            id: statusFont

            font: status.font
        }

        // The command line's selection (see Vim's commandLineEdit), in
        // the editor's selection colors, with its text over it. The cursor
        // isn't drawn then, as in a text field.
        Rectangle {
            visible: bar.vim.commandSelecting
            x: beforeSelection.advanceWidth
            width: Math.min(selected.advanceWidth, status.width - x)
            height: parent.height
            clip: true
            color: bar.theme.highlight

            Text {
                text: selected.text
                font: status.font
                color: bar.theme.highlightedText
                textFormat: Text.PlainText
            }
        }

        // The pointer in the command line, as in a text field: a press
        // puts the cursor there, with Shift or dragged it selects, and a
        // double click selects a word. It never takes the keys.
        MouseArea {
            anchors.fill: parent
            enabled: bar.vim.commandLine !== ""
            visible: enabled
            cursorShape: Qt.IBeamCursor
            onPressed: mouse => bar.vim.commandLineClick(bar.commandPositionAt(mouse.x),
                (mouse.modifiers & Qt.ShiftModifier) !== 0)
            onPositionChanged: mouse => {
                if (pressed)
                    bar.vim.commandLineClick(bar.commandPositionAt(mouse.x), true);
            }
            onDoubleClicked: mouse => bar.vim.commandLineWord(bar.commandPositionAt(mouse.x))
        }

        // Command-line cursor: a block over the character it's on.
        Rectangle {
            id: commandCursor

            readonly property string character: bar.vim.commandLine.charAt(bar.vim.commandCursor)

            visible: bar.vim.commandLine !== "" && !bar.vim.commandSelecting
            x: beforeCursor.advanceWidth
            width: underCursor.advanceWidth
            height: parent.height
            color: status.color

            Text {
                text: commandCursor.character
                font: status.font
                color: bar.theme.window
                textFormat: Text.PlainText
            }
        }
    }

    Label {
        id: position

        anchors.right: parent.right
        font.family: bar.vim.fontFamily
        font.pixelSize: bar.vim.fontSize
        // A macro's progress while it runs: not the position, which
        // would be found again at every key it runs. Or what vim waits
        // for (a shell command).
        text: bar.vim.waiting || bar.vim.progress ? (bar.vim.waiting || bar.vim.progress) + " (Esc to stop)"
            : bar.vim.pendingKeys + "    " + bar.vim.positionLabel()
    }
}
