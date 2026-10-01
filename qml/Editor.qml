pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Shapes

import "text.js" as Txt

// An editor: a TextArea in a ScrollView, which vim drives while it's the
// one vim edits (`active`: there's also the path field over the listing).
// Vim's cursors, the selection, search highlights, Koil's warnings and
// errors, and line numbers are drawn over (or under) its text here, and the
// hover box shows what's under the pointer.
Item {
    id: view

    required property Vim vim
    required property FindBar findBar
    required property Theme theme
    // System (main.qml), for the line format and the listing's colors.
    required property var system
    // Whether the text is Koil's listing (rather than a file), which gets
    // colors: its icons' (`iconColors`, as { icon: [dark, light] }, or
    // `pendingIconColor` on `pendingLines`, the lines whose entries applying
    // would change: see listing::pending_lines), and its dirs'.
    property bool listing: false
    property var iconColors: ({})
    property var pendingIconColor: ["", ""]
    property var pendingLines: []
    // Whether this is the path field over the listing: one line, in the
    // dirs' color, with no line numbers. `pathSyntax` holds the parts of it
    // to color (a regex's), as { start, length, kind } (see listing::Span).
    property bool pathField: false
    property var pathSyntax: []
    // Koil's warnings and errors about the text's lines, as { line,
    // column, severity, message } (see listing::Problem): drawn from the
    // column to the line's end.
    property var problems: []
    // Vim's state for this editor while it edits another one (see
    // Vim.leaveBuffer), kept here for main.qml to give back.
    property var saved: null

    // Whether vim edits this editor. The other one keeps its cursor where
    // vim left it (`cursorPos`), and its hidden text.
    readonly property bool active: vim.editor === editor
    readonly property int cursorPos: active ? vim.cursor : saved && saved.cursor || 0
    readonly property var hidden: active ? vim.hidden : saved && saved.hidden || []

    readonly property alias textArea: editor
    readonly property Flickable flickable: scrollView.contentItem as Flickable
    readonly property alias metrics: metrics
    // Every line is this tall, even one with an emoji (see fixLineFormat).
    // The extra space keeps an emoji clear of the lines around it.
    readonly property int lineHeight: Math.ceil(metrics.lineSpacing * 1.25)
    // Where the baseline is in a line: the font's characters sit in the
    // middle of it (see fixLineFormat).
    readonly property real textBaseline: (lineHeight + metrics.ascent - metrics.descent) / 2
    // Changes when the text or its layout does, and when the view scrolls
    // or resizes: what the overlays are computed from (see Layer).
    readonly property var layout: [editor.revision, editor.font, editor.contentWidth, editor.contentHeight, editor.leftPadding]
    readonly property var viewport: [flickable.contentY, flickable.height]
    // Set while the text changes in a way that isn't an edit.
    property bool quiet: false
    // The text as of its last change, to tell edits from changes to its
    // format (fixLineFormat, colors), which Qt reports as text changes too.
    property string lastText: ""

    // The text changed, by vim or by typing (not by setText).
    signal edited()
    // The editor was clicked (or given the keyboard) while vim edits the
    // other one, which should switch.
    signal activated()

    // Replaces the text (a file or a listing was opened); not an edit.
    function setText(text) {
        system.redrawText(editor); // or it may show none of a shorter text
        quiet = true;
        editor.text = text;
        quiet = false;
        fixLineFormat(); // setting the text reset it
    }

    // Colors the listing (see `listing`) or the path field, in the light or
    // dark theme's colors; a file gets none.
    function applyColors() {
        if (pathField) {
            const spans = [];
            for (const s of pathSyntax)
                spans.push(String(s.start), String(s.length), theme.regexColors[s.kind]);
            system.setPathColors(editor.textDocument, String(theme.directory), spans);
            return;
        }
        const colors = [];
        for (const icon in iconColors)
            colors.push(icon, iconColors[icon][theme.dark ? 0 : 1]);
        system.setListingColors(editor.textDocument, colors, pendingIconColor[theme.dark ? 0 : 1], listing ? String(theme.directory) : "");
        applyPendingLines();
    }

    function applyPendingLines() {
        if (listing)
            system.setPendingLines(editor.textDocument, pendingLines.map(String));
    }

    onListingChanged: applyColors()
    onIconColorsChanged: applyColors()
    onPendingIconColorChanged: applyColors()
    onPendingLinesChanged: applyPendingLines()
    onPathSyntaxChanged: applyColors()

    // An emoji comes from a taller font than the editor's, which makes its
    // line taller. Give every line the same height instead. Qt puts a
    // fixed-height line's baseline at 4/5 of it, so to center the text, the
    // line is made shorter and a bottom margin makes up the rest. Qt counts
    // the new block format as an edit, but it isn't one.
    function fixLineFormat() {
        // Not textBaseline, which may not have caught up with the font yet.
        const baseline = (lineHeight + metrics.ascent - metrics.descent) / 2;
        // In whole 64ths of a pixel, as Qt keeps both and drops the rest:
        // else each line comes out a 64th short, and in a long file the
        // text drifts off the line grid the overlays are drawn on.
        const height = Math.floor(Math.min(lineHeight, baseline * 5 / 4) * 64) / 64;
        quiet = true;
        system.setLineFormat(editor.textDocument, height, lineHeight - height);
        quiet = false;
    }

    // The rectangle of the character at pos, as tall as the line. The
    // cursors and highlights use it rather than positionToRectangle, which
    // gives a line with an emoji its natural height, while every line is
    // lineHeight tall (see fixLineFormat).
    function cellAt(pos) {
        const r = editor.positionToRectangle(pos);
        const h = lineHeight;
        const line = Math.round((r.y + r.height / 2 - editor.topPadding - h / 2) / h);
        return Qt.rect(r.x, editor.topPadding + line * h, r.width, h);
    }

    // Where to draw a cursor at pos: { cell, character, main }, where
    // character is the whole character there (an emoji, say), or "" for
    // none (at a line's end or on a tab).
    function spotAt(pos, main) {
        const t = editor.text, p = Math.min(pos, editor.length);
        const ch = t.slice(p, Txt.charEnd(t, p));
        return {
            cell: cellAt(p),
            character: ch === "\t" || ch === "\n" || ch === "\u2029" ? "" : ch,
            main: main
        };
    }

    // The selection in the visible lines, as one { start, end, eol } span
    // per line, where eol means it includes the line break. A visual block
    // isn't the editor's selection, so vim gives it.
    function selectionSpans() {
        const block = vim.mode === "visualBlock";
        const s = editor.selectionStart, e = editor.selectionEnd;
        if (!active || s === e && !block)
            return [];
        const t = editor.text, v = visibleRange();
        if (block)
            return vim.blockSpans().filter(r => r.start >= v.from && r.start <= v.to);
        const spans = [];
        for (let p = Math.max(s, v.from); p <= Math.min(e, v.to); ) {
            const le = Txt.lineEnd(t, p);
            if (p === e)
                break;
            spans.push({
                start: p,
                end: Math.min(le, e),
                eol: le < e
            });
            p = le + 1;
        }
        return spans;
    }

    // The warning or error with the character at pos, or null.
    function diagnosticAt(pos) {
        return diagnostics.at(pos);
    }

    // The entry of the icon at p that hides text, or null (see Hidden text
    // in Vim.qml).
    function hiddenAt(p) {
        return hidden.find(h => h.at === p) || null;
    }

    // The lines in view, even partly, as { top, bottom } counted from 0
    // (bottom can be past the last line), as vim's visibleLines would give
    // them if it edited this editor.
    function visibleLines() {
        const y = flickable.contentY - editor.topPadding;
        return {
            top: Math.max(0, Math.floor(y / lineHeight)),
            bottom: Math.max(0, Math.ceil((y + flickable.height) / lineHeight))
        };
    }

    // The part of the text [from, to] in the visible lines.
    function visibleRange() {
        const t = editor.text, v = visibleLines();
        return {
            from: Txt.lineToPos(t, v.top + 1),
            to: Txt.lineEnd(t, Txt.lineToPos(t, v.bottom + 1))
        };
    }

    // The message shown after a line's end at point p (in the editor), as
    // { start, rect } (its diagnostic's start), or null.
    function messageUnder(p) {
        return diagnostics.messageUnder(p);
    }

    onLineHeightChanged: fixLineFormat()
    onTextBaselineChanged: fixLineFormat()
    Component.onCompleted: fixLineFormat()

    FontMetrics {
        id: metrics

        font: editor.font
    }

    TextMetrics {
        id: spaceMetrics

        font: editor.font
        text: " "
    }

    Connections {
        target: view.vim
        enabled: view.active

        function onCursorChanged() {
            hover.hide();
        }
        function onHoverRequested(at) {
            hover.show(at, false);
        }
    }

    Connections {
        target: view.theme

        function onDarkChanged() {
            view.applyColors();
        }
    }

    Connections {
        target: view.flickable

        function onContentXChanged() {
            hover.hide();
        }
        function onContentYChanged() {
            hover.hide();
        }
    }

    HoverBox {
        id: hover

        editor: view
        theme: view.theme
    }

    // An overlay drawn from a model (spans, cursors), which it recomputes
    // with `compute` once anything in `inputs` changed and the current edit
    // is done: while editor.remove() runs, the document is already shorter
    // but editor.length isn't updated yet, and asking for a position then
    // warns.
    component Layer: Item {
        id: layer

        property var inputs: []
        property var compute: () => []
        property var model: []

        function refresh() {
            // A Repeater keeps its delegates when the new model equals the
            // old one, but after a relayout their rectangles must be
            // recomputed, so always start from an empty model.
            model = [];
            model = compute();
        }

        onInputsChanged: Qt.callLater(refresh)
    }

    // A cursor over the character in `cell`: a bar, a block that shows
    // the character, or an underline.
    component Caret: Rectangle {
        id: caret

        required property rect cell
        required property string character
        required property string shape // "bar", "block" or "underline"
        property bool shown: true

        x: cell.x
        y: shape === "underline" ? cell.y + cell.height - height : cell.y
        width: shape === "bar" ? 2 : charMetrics.advanceWidth
        height: shape === "underline" ? Math.max(2, Math.round(cell.height / 8)) : cell.height
        color: editor.color
        visible: shown && (shape !== "bar" || editor.activeFocus && editor.blinkOn)
        opacity: editor.activeFocus ? 1 : 0.4

        TextMetrics {
            id: charMetrics

            font: editor.font
            text: caret.character || " "
        }

        Text {
            y: view.textBaseline - baselineOffset
            visible: caret.shape === "block"
            text: caret.character
            font: editor.font
            color: view.theme.base
            textFormat: Text.PlainText
        }
    }

    // A line with a cursor, a shade off the background as in other editors.
    component Band: Rectangle {
        required property rect row

        x: view.flickable.contentX
        y: row.y
        width: view.flickable.width
        height: row.height
        color: Qt.tint(view.theme.base, view.theme.dark ? "#19ffffff" : "#0f000000")
    }

    ScrollView {
        id: scrollView

        anchors.fill: parent
        // The path field scrolls with vim's cursor, or the wheel.
        ScrollBar.horizontal.policy: view.pathField ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded
        ScrollBar.vertical.policy: view.pathField ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded

        TextArea {
            id: editor

            // Bumped on every change to the text, for things that must
            // refresh after one.
            property int revision: 0
            // Whether the insert-mode bars are in the visible half of a blink.
            property bool blinkOn: true

            font.family: view.vim.fontFamily
            font.pointSize: view.vim.fontSize
            textFormat: TextEdit.PlainText
            wrapMode: TextEdit.NoWrap
            selectByMouse: true
            // The selection is drawn below (see `selection`), not by Qt.
            selectionColor: "transparent"
            selectedTextColor: color
            readOnly: true // vim starts in normal mode
            focus: true
            onTextChanged: {
                if (!view.quiet && text !== view.lastText)
                    view.edited();
                view.lastText = text;
                revision++;
            }
            onCursorPositionChanged: {
                blinkOn = true;
                if (view.active)
                    view.vim.syncFromEditor();
            }
            onSelectedTextChanged: {
                if (view.active)
                    view.vim.syncFromEditor();
            }
            onRevisionChanged: hover.hide()
            // Given the keyboard some other way than a click (see the
            // MouseArea), it switches too.
            onActiveFocusChanged: {
                if (!activeFocus)
                    hover.hide();
                else if (!view.active)
                    view.activated();
            }
            Component.onCompleted: {
                // Make room for the line numbers beside the style's padding.
                const base = leftPadding;
                leftPadding = Qt.binding(() => base + gutter.columnWidth);
                // The path field is a line in a field (which main.qml
                // draws), with no room around it. The macOS style doesn't
                // let the background be replaced, only hidden.
                if (view.pathField) {
                    topPadding = 0;
                    bottomPadding = 0;
                    background.visible = false;
                } else if (Qt.platform.os !== "osx") {
                    // Fusion (Windows and Linux) frames a TextArea like a
                    // text field, which doesn't suit a full-window editor.
                    background = plainBackground.createObject(editor);
                }
            }
            Keys.onPressed: event => {
                if (event.matches(StandardKey.Copy) && hover.copySelection()) {
                    event.accepted = true;
                    return;
                }
                // Not on a lone modifier, which may start Cmd+C.
                if (![Qt.Key_Shift, Qt.Key_Control, Qt.Key_Meta, Qt.Key_Alt, Qt.Key_AltGr].includes(event.key))
                    hover.hide(); // gh shows it again
                // Keys for an editor vim doesn't edit (which it should, see
                // onActiveFocusChanged) go nowhere.
                event.accepted = !view.active || view.vim.handleKey(event);
            }

            Component {
                id: plainBackground

                Rectangle {
                    color: view.theme.base
                }
            }

            // The pointer resting on an icon that hides text shows the
            // text, and on a warning or error (or its message after the
            // line) the message.
            HoverHandler {
                onPointChanged: hover.pointerAt(hovered ? point.position : null)
                onHoveredChanged: hover.pointerAt(hovered ? point.position : null)
            }

            // Insert mode: a blinking bar. The editor puts the delegate at its
            // cursor rectangle; the bar itself fills the line.
            cursorDelegate: Item {
                id: bar

                width: 2
                visible: view.vim.mode === "insert" && editor.activeFocus && editor.blinkOn

                Rectangle {
                    y: view.cellAt(editor.cursorPosition).y - bar.y
                    width: parent.width
                    height: view.lineHeight
                    color: editor.color
                }
            }

            // The bars blink together: the one above and the extra cursors'.
            Timer {
                interval: 530
                repeat: true
                running: view.vim.mode === "insert" && editor.activeFocus
                onRunningChanged: editor.blinkOn = true
                onTriggered: editor.blinkOn = !editor.blinkOn
            }

            // Alt+click adds a cursor (or removes one). A plain click goes
            // back to one cursor and then does what it always does. Either
            // one on the editor vim doesn't edit switches to it first, so
            // the click moves its cursor.
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.IBeamCursor
                onPressed: mouse => {
                    if (!view.active)
                        view.activated();
                    if (mouse.modifiers & Qt.AltModifier) {
                        editor.forceActiveFocus();
                        view.vim.toggleCursor(editor.positionAt(mouse.x, mouse.y));
                    } else {
                        view.vim.clearCursors();
                        mouse.accepted = false;
                    }
                }
            }

            // The lines with a cursor, under the selection. Not while
            // there's a selection, nor in the path field.
            Item {
                z: -0.6
                visible: !view.pathField && !(view.active && view.vim.isVisual)

                Repeater {
                    model: carets.model

                    Band {
                        required property var modelData

                        row: modelData.cell
                    }
                }
            }

            // The selection, drawn under the text (a negative z puts a child
            // below its parent's content) with the same height on every line.
            Layer {
                id: selection

                z: -0.5
                inputs: [view.active, editor.selectionStart, editor.selectionEnd, view.vim.mode, view.vim.anchor, view.vim.cursor, view.vim.wantCol, view.layout, view.viewport]
                compute: () => view.selectionSpans()

                Repeater {
                    model: selection.model

                    Rectangle {
                        required property var modelData
                        readonly property rect startRect: view.cellAt(modelData.start)
                        readonly property rect endRect: view.cellAt(modelData.end)

                        x: startRect.x
                        y: startRect.y
                        // A selected line break shows as a space, as in Qt.
                        width: endRect.x - startRect.x + (modelData.eol ? spaceMetrics.advanceWidth : 0)
                        height: startRect.height
                        color: view.theme.highlight
                    }
                }
            }

            // Search matches: the search being typed, else the find bar's
            // while it's open, else the last search until Esc.
            Layer {
                id: highlights

                inputs: [view.active, view.vim.commandLine, view.vim.highlightPattern, view.vim.highlightTarget, view.findBar.active, view.findBar.matches, view.findBar.current, view.layout, view.viewport]
                compute: () => !view.active ? [] : view.vim.typedSearch() === null && view.findBar.active ? view.findBar.highlightSpans() : view.vim.searchHighlights()

                Repeater {
                    model: highlights.model

                    Rectangle {
                        id: match

                        required property var modelData
                        readonly property rect startRect: view.cellAt(modelData.start)
                        readonly property rect endRect: view.cellAt(modelData.end)

                        x: startRect.x
                        y: startRect.y
                        width: endRect.x - startRect.x
                        height: startRect.height
                        color: modelData.current ? "#ff9f1a" : "#f5d547"

                        // Redraw the matched text on top, dark on the highlight.
                        Text {
                            y: view.textBaseline - baselineOffset
                            text: editor.getText(match.modelData.start, match.modelData.end)
                            font: editor.font
                            color: "black"
                            textFormat: Text.PlainText
                        }
                    }
                }
            }

            // Every cursor: the main one, then the extra ones (Alt+click, or
            // a block insert's lines), as spotAt gives them. After the search
            // highlights, so they're drawn over them. While vim edits the
            // other editor, where it left the cursor (the path field shows
            // none).
            Layer {
                id: carets

                inputs: [view.active, view.cursorPos, view.vim.cursors, editor.cursorRectangle, view.layout]
                compute: () => !view.active ? (view.pathField ? [] : [view.spotAt(view.cursorPos, true)])
                    : [view.spotAt(view.vim.cursor, true)].concat(view.vim.cursors.map(c => view.spotAt(c.pos, false)))

                // Shaped like the main one. In insert mode the main one is
                // the editor's own bar (see cursorDelegate).
                Repeater {
                    model: carets.model

                    Caret {
                        required property var modelData

                        cell: modelData.cell
                        character: modelData.character
                        shape: view.active ? view.vim.cursorShape : "block"
                        shown: !modelData.main || !view.active || view.vim.mode !== "insert"
                    }
                }
            }

            // Koil's warnings and errors, as in VS Code: a wavy underline,
            // orange or red, and a message after the end of the line (an
            // error's, if the line has both). The pointer resting on either
            // (or gh) shows the message in the hover box.
            Item {
                id: diagnostics

                // The one whose message shows after its line's end, for each
                // line in view.
                readonly property var messages: {
                    const shown = [];
                    for (const d of squiggles.model) {
                        const prev = shown[shown.length - 1];
                        if (!prev || prev.lineEnd !== d.lineEnd)
                            shown.push(d);
                        else if (prev.severity !== "error" && d.severity === "error")
                            shown[shown.length - 1] = d;
                    }
                    return shown;
                }

                // The warnings and errors on the lines of t from `from` to
                // `to`, as { start, end, severity, message, lineEnd }, in
                // order.
                function find(t, from, to) {
                    const first = Txt.lineOf(t, from) - 1, last = Txt.lineOf(t, to) - 1, list = [];
                    for (const p of view.problems) {
                        if (p.line < first || p.line > last)
                            continue;
                        const ls = Txt.lineToPos(t, p.line + 1), le = Txt.lineEnd(t, ls);
                        list.push({
                            start: Math.min(ls + p.column, le),
                            end: le,
                            severity: p.severity,
                            message: p.message,
                            lineEnd: le
                        });
                    }
                    return list.sort((a, b) => a.start - b.start);
                }

                // The warning or error with the character at pos, or null.
                function at(pos) {
                    return find(editor.text, pos, pos).find(d => d.start <= pos && pos < d.end) || null;
                }

                // The message shown after a line's end at point p, as
                // { start, rect } (its diagnostic's start), or null.
                function messageUnder(p) {
                    for (let i = 0; i < messageRepeater.count; i++) {
                        const m = messageRepeater.itemAt(i), cell = view.cellAt(messages[i].lineEnd);
                        if (m && p.x >= m.x && p.x < m.x + m.width && p.y >= cell.y && p.y < cell.y + cell.height)
                            return {
                                start: messages[i].start,
                                rect: Qt.rect(m.x, cell.y, m.width, cell.height)
                            };
                    }
                    return null;
                }

                // A zigzag `width` long, `step` high, with a peak every
                // other step. The last step ends partway at `width`.
                function wave(width, step) {
                    let path = "M0 " + step;
                    for (let x = step, up = true; x - step < width; x += step, up = !up) {
                        const end = Math.min(x, width), part = (end - x + step) / step;
                        path += " L" + end + " " + (up ? step * (1 - part) : step * part);
                    }
                    return path;
                }

                // The ones in the visible lines.
                Layer {
                    id: squiggles

                    inputs: [view.problems, view.layout, view.viewport]
                    compute: () => {
                        const v = view.visibleRange();
                        return diagnostics.find(editor.text, v.from, v.to);
                    }

                    // Centered on the bottom of the font's descent.
                    Repeater {
                        model: squiggles.model

                        Shape {
                            id: squiggle

                            required property var modelData
                            readonly property rect startRect: view.cellAt(modelData.start)

                            x: startRect.x
                            y: startRect.y + view.textBaseline + metrics.descent - height / 2
                            width: view.cellAt(modelData.end).x - startRect.x
                            height: 3 * view.theme.zoom
                            preferredRendererType: Shape.CurveRenderer

                            ShapePath {
                                strokeColor: view.theme.severityColor(squiggle.modelData.severity)
                                strokeWidth: view.theme.zoom
                                fillColor: "transparent"
                                joinStyle: ShapePath.RoundJoin

                                PathSvg {
                                    path: diagnostics.wave(squiggle.width, squiggle.height)
                                }
                            }
                        }
                    }
                }

                Repeater {
                    id: messageRepeater

                    model: diagnostics.messages

                    // Four spaces after the line's end.
                    Text {
                        required property var modelData
                        readonly property rect cell: view.cellAt(modelData.lineEnd)

                        x: cell.x + 4 * spaceMetrics.advanceWidth
                        y: cell.y + view.textBaseline - baselineOffset
                        text: modelData.message
                        font: editor.font
                        color: view.theme.severityColor(modelData.severity)
                        textFormat: Text.PlainText
                    }
                }
            }

            // Line numbers (:set number / relativenumber) for the visible
            // lines, in the left padding, two spaces before the text. It
            // stays put when the text scrolls sideways, and covers the text
            // that scrolls under it. As in vim, with both options the
            // cursor's line shows its own number, on the left.
            Rectangle {
                id: gutter

                readonly property bool shown: !view.pathField && (view.vim.number || view.vim.relativeNumber)
                property int digits: 3
                // Room for the numbers and two spaces after them.
                readonly property real columnWidth: shown ? (digits + 2) * digitMetrics.advanceWidth : 0
                property var rows: []
                readonly property var inputs: [shown, view.vim.number, view.vim.relativeNumber, view.cursorPos, view.lineHeight, view.layout, view.viewport]

                function refresh() {
                    if (!shown) {
                        rows = [];
                        return;
                    }
                    const t = editor.text, v = view.visibleLines();
                    const count = Txt.countLines(t);
                    digits = Math.max(3, String(count).length);
                    const current = Txt.lineOf(t, view.cursorPos) - 1;
                    const list = [];
                    for (let i = v.top; i <= Math.min(count - 1, v.bottom); i++) {
                        const own = i === current && view.vim.number;
                        list.push({
                            line: i,
                            current: i === current,
                            left: own && view.vim.relativeNumber,
                            label: String(view.vim.relativeNumber && !own ? Math.abs(i - current) : i + 1)
                        });
                    }
                    rows = list;
                }

                onInputsChanged: Qt.callLater(refresh)

                visible: shown
                x: view.flickable.contentX
                width: editor.leftPadding
                height: editor.height
                color: (editor.background as Rectangle).color

                TextMetrics {
                    id: digitMetrics

                    font: editor.font
                    text: "0"
                }

                Repeater {
                    model: gutter.rows

                    Text {
                        required property var modelData

                        x: editor.leftPadding - gutter.columnWidth
                        y: editor.topPadding + modelData.line * view.lineHeight + view.textBaseline - baselineOffset
                        width: gutter.digits * digitMetrics.advanceWidth
                        horizontalAlignment: modelData.left ? Text.AlignLeft : Text.AlignRight
                        text: modelData.label
                        font: editor.font
                        color: modelData.current ? editor.color : Qt.tint(view.theme.base, view.theme.dark ? "#80ffffff" : "#80000000")
                        textFormat: Text.PlainText
                    }
                }
            }
        }
    }
}
