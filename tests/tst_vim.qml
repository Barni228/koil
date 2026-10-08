import QtQuick
import QtQuick.Controls
import QtTest

import "../qml"
import "../qml/text.js" as Txt

// Vim.qml (and the find bar's replace) without the Rust app:
//   qmltestrunner -input tests
TestCase {
    id: tc

    readonly property string mushroom: "🍄"
    readonly property string chair: "🪑"
    readonly property bool isMac: Qt.platform.os === "osx"

    name: "Vim"
    width: 500
    height: 300
    when: windowShown

    // Starts over with `spec` as the text, where "M" and "C" are a 🍄 and a
    // 🪑 that hide "h1", "h2" and so on, and "m" is a 🍄 that hides nothing.
    function load(spec) {
        let text = "", n = 0;
        const entries = [];
        for (const ch of spec) {
            if (ch === "M" || ch === "C") {
                const icon = ch === "M" ? mushroom : chair;
                n += 1;
                entries.push({
                    at: text.length,
                    icon: icon,
                    text: "h" + n
                });
                text += icon;
            } else {
                text += ch === "m" ? mushroom : ch;
            }
        }
        editor.text = text;
        vim.reset(entries);
        vim.registers = {};
        clipboard.text = "";
        clipboard.data = "";
        editor.forceActiveFocus();
    }

    // The text with each icon that hides text written as <M:text> or
    // <C:text>, and any other icon as M or C.
    function render() {
        const t = editor.text;
        let r = "", i = 0;
        for (const h of vim.hidden) {
            r += t.slice(i, h.at) + "<" + (h.icon === mushroom ? "M" : "C") + ":" + h.text + ">";
            i = h.at + h.icon.length;
        }
        return (r + t.slice(i)).split(mushroom).join("M").split(chair).join("C");
    }

    // Types keys: characters, and names like <Esc>, <CR>, <S-CR>
    // (Shift+Enter), <S-Tab>, <C-v> (Ctrl) or <D-c> (Cmd on macOS, Ctrl elsewhere).
    function keys(s) {
        const named = {
            "Esc": Qt.Key_Escape,
            "CR": Qt.Key_Return,
            "BS": Qt.Key_Backspace,
            "Del": Qt.Key_Delete,
            "Tab": Qt.Key_Tab,
            "Left": Qt.Key_Left,
            "Right": Qt.Key_Right,
            "Up": Qt.Key_Up,
            "Down": Qt.Key_Down,
            "Home": Qt.Key_Home
        };
        const ctrl = isMac ? Qt.MetaModifier : Qt.ControlModifier;
        for (const m of s.match(/<[^<>]+>|[\s\S]/g)) {
            if (m.length === 1 || m === "<>") {
                keyClick(m);
            } else {
                const name = m.slice(1, -1);
                if (named[name] !== undefined)
                    keyClick(named[name]);
                else if (name === "S-CR")
                    keyClick(Qt.Key_Return, Qt.ShiftModifier);
                else if (name === "S-Tab")
                    keyClick(Qt.Key_Backtab, Qt.ShiftModifier);
                else if (/^C-[a-z]$/.test(name))
                    keyClick(Qt.Key_A + name.charCodeAt(2) - 97, ctrl);
                else if (/^D-[a-z]$/.test(name))
                    keyClick(Qt.Key_A + name.charCodeAt(2) - 97, Qt.ControlModifier);
                else if (name === "D-BS")
                    keyClick(Qt.Key_Backspace, Qt.ControlModifier);
                else
                    fail("unknown key " + m);
            }
        }
    }

    QtObject {
        id: clipboard

        property string text: ""
        property string data: ""

        function clipboardText() {
            return text;
        }
        function clipboardData() {
            return data;
        }
        function setClipboardText(t, d) {
            text = t;
            data = d;
        }
    }

    TextArea {
        id: editor

        width: 400
        height: 200
        textFormat: TextEdit.PlainText
        wrapMode: TextEdit.NoWrap
        readOnly: true
        onCursorPositionChanged: {
            if (vim.editor === editor)
                vim.syncFromEditor();
        }
        onSelectedTextChanged: {
            if (vim.editor === editor)
                vim.syncFromEditor();
        }
        Keys.onPressed: event => {
            event.accepted = vim.handleKey(event);
        }
    }

    // Another buffer (as Koil's path field is), see switchTo.
    TextArea {
        id: other

        x: 410
        width: 80
        height: 30
        textFormat: TextEdit.PlainText
        wrapMode: TextEdit.NoWrap
        readOnly: true
        onCursorPositionChanged: {
            if (vim.editor === other)
                vim.syncFromEditor();
        }
        Keys.onPressed: event => {
            event.accepted = vim.handleKey(event);
        }
    }

    // A buffer too narrow for its line, which vim scrolls (see switchTo).
    ScrollView {
        id: narrow

        y: 260
        width: 100
        height: 30

        TextArea {
            id: narrowText

            textFormat: TextEdit.PlainText
            wrapMode: TextEdit.NoWrap
            readOnly: true
            onCursorPositionChanged: {
                if (vim.editor === narrowText)
                    vim.syncFromEditor();
            }
            Keys.onPressed: event => {
                event.accepted = vim.handleKey(event);
            }
        }
    }

    // As in the app: without a binding to it, a bug that hangs the app
    // while typing can go unnoticed.
    Label {
        y: 220
        text: vim.progress || vim.positionLabel()
    }

    Vim {
        id: vim

        editor: editor
        clipboard: clipboard
    }

    Theme {
        id: theme

        palette: editor.palette
        font: editor.font
    }

    SignalSpy {
        id: edits

        target: editor
        signalName: "textChanged"
    }

    SignalSpy {
        id: keyCommands

        target: vim
        signalName: "keyCommand"
    }

    SignalSpy {
        id: nothingToUndo

        target: vim
        signalName: "nothingToUndo"
    }

    SignalSpy {
        id: quits

        target: vim
        signalName: "quitRequested"
    }

    SignalSpy {
        id: writes

        target: vim
        signalName: "writeRequested"
    }

    FindBar {
        id: findBar

        y: 240
        editor: editor
        vim: vim
        theme: theme
    }

    HelpPanel {
        id: help

        theme: theme
    }

    ConfirmDialog {
        id: confirm

        theme: theme
    }

    property int defaultChunkTime
    property real defaultCharWidth
    property real defaultLineHeight
    property int defaultSideScrollOff

    function initTestCase() {
        defaultChunkTime = vim.chunkTime;
        defaultCharWidth = vim.charWidth;
        defaultLineHeight = vim.lineHeight;
        defaultSideScrollOff = vim.sideScrollOff;
    }

    // Back to the editor, after a test that switched buffers.
    function cleanup() {
        if (vim.running)
            vim.stopRun();
        vim.chunkTime = defaultChunkTime;
        vim.charWidth = defaultCharWidth;
        vim.lineHeight = defaultLineHeight;
        vim.sideScrollOff = defaultSideScrollOff;
        if (vim.editor !== editor)
            switchTo(editor, null);
        vim.flickable = null;
        narrow.height = 30;
        (narrow.contentItem as Flickable).bottomMargin = 0;
        vim.singleLine = false;
        vim.linePrefixes = false;
        vim.commandKeys = {};
        vim.completer = null;
        vim.lineHistory = null;
    }

    // Makes vim edit `to` (the editor, `other` or `narrowText`, scrolled by
    // `flickable`) from `state`, as main.qml does, and returns the state of
    // the one it left.
    function switchTo(to, state, flickable) {
        const left = vim.leaveBuffer();
        vim.editor = to;
        vim.flickable = flickable || null;
        vim.enterBuffer(state);
        to.forceActiveFocus();
        return left;
    }

    // ---- Vim -----------------------------------------------------------------

    function test_operators() {
        load("one two three\nfour five");
        keys("dw");
        compare(render(), "two three\nfour five");
        keys("ciwxx<Esc>");
        compare(render(), "xx three\nfour five");
        keys("jdd");
        compare(render(), "xx three");
        keys("p");
        compare(render(), "xx three\nfour five");
        keys("u<C-r>u");
        compare(render(), "xx three");
        keys("3.");
        compare(render(), "xx three\nfour five\nfour five\nfour five");
    }

    function test_countsAndRepeat() {
        load("abcdef");
        keys("2x.");
        compare(render(), "ef");
        keys("A!<Esc>0.");
        compare(render(), "ef!!");
        keys("I<<Esc>5.");
        compare(render(), "<<<<<<ef!!");
    }

    function test_visualBlockInsert() {
        load("ab\ncd\nef");
        keys("<C-v>jjIX<Esc>");
        compare(render(), "Xab\nXcd\nXef");
        compare(vim.cursor, 0);
        keys("u");
        compare(render(), "ab\ncd\nef");
    }

    function test_macro() {
        load("1\n1\n1");
        keys("qa<C-a>jq2@a");
        compare(render(), "2\n2\n2");
    }

    // Line lookups in a long text (which Txt keeps the line starts of)
    // give what going through the text does, also after it changed.
    function test_lineIndex() {
        const plainLineOf = (t, p) => t.slice(0, Math.max(0, p)).split("\n").length;
        const plainLineToPos = (t, line) => {
            const lines = t.split("\n");
            return lines.slice(0, Math.max(0, Math.min(line, lines.length) - 1)).join("\n").length + (line > 1 ? 1 : 0);
        };
        let t = "";
        for (let i = 0; i < 3000; i++)
            t += "line " + i + "\n";
        for (const text of [t, t + "end", t.slice(0, 500) + "\n\n" + t.slice(500)]) {
            compare(Txt.countLines(text), text.split("\n").length);
            for (const p of [-1, 0, 7, 8, 9, 500, 501, 502, text.length - 1, text.length, text.length + 5])
                compare(Txt.lineOf(text, p), plainLineOf(text, p), "lineOf " + p);
            for (const line of [0, 1, 2, 60, 2999, 3000, 3001, 3002, 5000])
                compare(Txt.lineToPos(text, line), plainLineToPos(text, line), "lineToPos " + line);
        }
        compare(Txt.lineOf(t, 8), 2); // the first text again
    }

    // As in vim, u undoes a whole run, which is one change.
    function test_macroUndo() {
        load("1\n1\n1\n1");
        keys("qa<C-a>jq2@a");
        compare(render(), "2\n2\n2\n1");
        keys("u");
        compare(render(), "2\n1\n1\n1");
        keys("u");
        compare(render(), "1\n1\n1\n1");
    }

    // Runs macro `reg` `count` times a key per chunk: the first one now,
    // the others only by step() (keyClick lets the timer run them).
    function startChunks(reg, count) {
        vim.chunkTime = 0;
        vim.runMacro(reg, count);
        vim.chunkTimer.stop();
    }

    function step() {
        vim.runChunk();
        vim.chunkTimer.stop();
    }

    // A long run goes in chunks (here a key each), after each of which the
    // editor has its edits and the status line its progress.
    function test_macroChunks() {
        load("1");
        keys("qayyp<C-a>q");
        startChunks("a", 3); // yank
        verify(vim.running);
        compare(vim.progress, "@a 8%");
        step();
        step();
        compare(editor.text, "1\n2\n2"); // pasted
        compare(vim.progress, "@a 25%");
        vim.chunkTimer.start();
        tryCompare(vim, "running", null);
        compare(vim.progress, "");
        compare(render(), "1\n2\n3\n4\n5");
        compare(vim.cursor, 8);
        keys("u");
        compare(render(), "1\n2");
    }

    // Esc stops a run between its chunks, which other keys don't run in.
    function test_macroStops() {
        load("1");
        keys("qayyp<C-a>q");
        startChunks("a", 3);
        keys("x<Esc>");
        compare(vim.running, null);
        compare(vim.message, "Interrupted");
        compare(render(), "1\n2");
        keys("x");
        compare(render(), "1\n");
        // So does anything else that moves vim, like a click.
        load("1");
        keys("qayyp<C-a>q");
        startChunks("a", 3);
        editor.cursorPosition = 0;
        compare(vim.running, null);
        compare(vim.cursor, 0);
    }

    // A macro that runs itself last (until j fails) doesn't stack up, and
    // one that runs itself more than that fails.
    function test_recursiveMacro() {
        load("1\n1\n1");
        keys("qa<C-a>j@aq@a");
        compare(render(), "2\n2\n2");
        compare(vim.running, null);
        load("1");
        keys("qa@a<C-a>q@a");
        compare(vim.message, "E223: recursive mapping");
        compare(vim.running, null);
        compare(vim.typeahead.length, 0);
    }

    // A long command (u with a count) runs in chunks too, with its
    // progress, and Esc stops it as far as it got.
    function test_longCommand() {
        load("abcd");
        keys("xxx");
        vim.chunkTime = 0;
        vim.undo(3);
        vim.chunkTimer.stop();
        compare(vim.progress, "3u 33%");
        compare(editor.text, "cd");
        step();
        compare(editor.text, "bcd");
        step();
        compare(vim.running, null);
        compare(vim.progress, "");
        compare(render(), "abcd");
        compare(vim.cursor, 0);
        keys("xxx");
        vim.undo(3);
        vim.chunkTimer.stop();
        keys("<Esc>");
        compare(vim.running, null);
        compare(vim.message, "Interrupted");
        compare(render(), "cd");
        keys("<C-r>");
        compare(render(), "d");
        // So does @: with a count (here at once, in one chunk).
        vim.chunkTime = defaultChunkTime;
        vim.charWidth = defaultCharWidth;
        vim.sideScrollOff = defaultSideScrollOff;
        load("x");
        const size = vim.fontSize;
        keys(":set fs+=1<CR>3@:");
        compare(vim.fontSize, size + 4);
        vim.fontSize = size;
    }

    // A count's repeat of an insert that deletes (or of a replace) goes key
    // by key, as a long command, which Esc stops; leaving the insert waits
    // for it.
    function test_longInsertRepeat() {
        load("x");
        vim.chunkTime = 0;
        keys("4ia<BS>b<Esc>");
        vim.chunkTimer.stop();
        compare(vim.progress, "4i 33%");
        compare(editor.text, "bbx");
        compare(vim.mode, "insert");
        step();
        step();
        compare(vim.running, null);
        compare(vim.mode, "normal");
        compare(render(), "bbbbx");
        compare(vim.cursor, 3);
        keys("u");
        compare(render(), "x");
        keys("3Rab<BS><Esc>");
        vim.chunkTimer.stop();
        compare(vim.progress, "3R 50%");
        keys("<Esc>");
        compare(vim.running, null);
        compare(vim.message, "Interrupted");
        compare(vim.mode, "normal");
        compare(render(), "aa");
        keys("u");
        compare(render(), "x");
        // Leaving the buffer doesn't repeat it, as moving the cursor doesn't.
        keys("4ia<BS>b");
        const state = switchTo(other, null);
        compare(vim.running, null);
        compare(editor.text, "bx");
        // In the path field, Enter runs after it.
        other.text = "x";
        vim.singleLine = true;
        vim.commandKeys = {
            "<CR>": "open"
        };
        keyCommands.clear();
        keys("4ia<BS>b<CR>");
        vim.chunkTimer.stop();
        compare(keyCommands.count, 0);
        vim.chunkTimer.start();
        tryCompare(vim, "running", null);
        compare(other.text, "bbbbx");
        compare(vim.mode, "normal");
        compare(keyCommands.signalArguments.map(a => a[0]), ["open"]);
        switchTo(editor, state);
    }

    // A huge count takes no longer than one that's just big enough: a
    // motion stops where it can't go further, and a search stops going
    // round its matches.
    function test_hugeCounts() {
        const huge = "99999999";
        for (const m of ["w", "W", "e", "E", "b", "B", "ge", "gE", "}", "{"]) {
            for (const from of [0, 6, 12]) {
                load("one two\n\nthree, four");
                vim.setCursor(from);
                keys("20" + m);
                const target = vim.cursor;
                vim.setCursor(from);
                keys(huge + m);
                compare(vim.cursor, target, m + " from " + from);
            }
        }
        load("a b\nc d");
        keys("d20w");
        const deleted = editor.text;
        load("a b\nc d");
        keys("d" + huge + "w");
        compare(editor.text, deleted);
        load("a b\nc d");
        keys("c" + huge + "wx<Esc>");
        compare(editor.text, "x");
        // 99999999 is 3 times 33333333: round to where it started.
        load("a b a c a");
        keys("/a<CR>");
        compare(vim.cursor, 4);
        keys(huge + "n");
        compare(vim.cursor, 4);
        keys("1" + huge + "n"); // 1 more
        compare(vim.cursor, 8);
        keys(huge + "N");
        compare(vim.cursor, 8);
        keys("0" + huge + "*");
        compare(vim.cursor, 0);
    }

    // However many edits a key makes (J, a block's lines), the editor gets
    // one: each has Qt go over all the text.
    function test_oneEditPerKey() {
        load("a\nb\nc\nd\ne");
        edits.clear();
        keys("4J");
        compare(render(), "a b c d\ne");
        verify(edits.count <= 2, edits.count + " edits");
        edits.clear();
        keys("u");
        compare(render(), "a\nb\nc\nd\ne");
        verify(edits.count <= 2, edits.count + " edits");
        edits.clear();
        keys("<C-v>Gd");
        compare(render(), "\n\n\n\n");
        verify(edits.count <= 2, edits.count + " edits");
    }

    // A key that changes nothing leaves the view where it is, even with the
    // cursor out of it (scrolled by the mouse).
    function test_viewStays() {
        narrowText.text = "x".repeat(60);
        waitForRendering(narrow);
        const f = narrow.contentItem as Flickable;
        switchTo(narrowText, {
            cursor: 0
        }, f);
        narrowText.forceActiveFocus();
        f.contentX = 200;
        keys("<Esc>");
        compare(f.contentX, 200);
        keys("l");
        compare(vim.cursor, 1);
        const x = narrowText.positionToRectangle(1).x;
        verify(f.contentX <= x && x < f.contentX + f.width, "the cursor is in view");
    }

    // After an edit the view shows the cursor, even if the edit put the
    // editor's cursor where vim's is (so setting it didn't scroll), and
    // isn't left past the text's end (deleting all of a long text from its
    // end left the view blank).
    function test_editShowsCursor() {
        const f = narrow.contentItem as Flickable;
        const line = n => narrowText.positionToRectangle(Txt.lineToPos(narrowText.text, n));
        const cursorLine = () => Txt.lineOf(narrowText.text, vim.cursor);
        const cases = [
            { lines: 100, at: 100, keys: "100dk", line: 1 },
            { lines: 1000, at: 300, keys: "dgg", line: 1 },
            { lines: 1000, at: 300, keys: "200dk", line: 100 },
            { lines: 100, at: 50, keys: "ztdG", line: 49 }
        ];
        for (const c of cases) {
            // Lines that differ from their first character, or the edit
            // the editor gets (vim's diff) would start after what's alike.
            const lines = [];
            for (let i = 1; i <= c.lines; i++)
                lines.push(String.fromCharCode(97 + i % 26) + i);
            narrowText.text = lines.join("\n");
            waitForRendering(narrow);
            vim.lineHeight = line(2).y - line(1).y;
            switchTo(narrowText, {
                cursor: Txt.lineToPos(narrowText.text, c.at)
            }, f);
            keys("zz");
            verify(f.contentY > line(c.at).y - f.height, "the cursor's line is in view");
            keys(c.keys);
            compare(cursorLine(), c.line);
            const r = line(c.line);
            verify(f.contentY <= r.y && r.y + r.height <= f.contentY + f.height, c.keys + ": the cursor is in view");
            verify(f.contentY <= Math.max(0, f.contentHeight - f.height), c.keys + ": the view is past the end");
        }
    }

    // With room below the text (Editor.qml's scrollRoom), zz and zt work on
    // the last line, Ctrl-E and Ctrl-F scroll until it's at the top, and an
    // edit keeps the view there, but a search and Ctrl-D go no further
    // than the text's end.
    function test_scrollPastEnd() {
        const f = narrow.contentItem as Flickable;
        const line = n => narrowText.positionToRectangle(Txt.lineToPos(narrowText.text, n));
        const lines = [];
        for (let i = 1; i <= 50; i++)
            lines.push("line" + i);
        narrow.height = 150;
        narrowText.text = lines.join("\n");
        waitForRendering(narrow);
        vim.lineHeight = line(2).y - line(1).y;
        f.bottomMargin = f.height - vim.lineHeight - narrowText.bottomPadding;
        const end = f.contentHeight - f.height, last = line(50);
        switchTo(narrowText, {
            cursor: Txt.lineToPos(narrowText.text, 50)
        }, f);
        keys("zz");
        fuzzyCompare(f.contentY, last.y + last.height / 2 - f.height / 2, 0.5);
        verify(f.contentY > end + 1, "zz scrolls past the end");
        const y = f.contentY;
        keys("x");
        compare(f.contentY, y);
        keys("zt");
        fuzzyCompare(f.contentY, last.y - narrowText.topPadding, 0.5);
        keys("ggG");
        fuzzyCompare(f.contentY, end, 0.5);
        keys("100<C-e>");
        fuzzyCompare(f.contentY, last.y, 0.5);
        keys("<C-e>");
        fuzzyCompare(f.contentY, last.y, 0.5);
        keys("gg/ine50");
        fuzzyCompare(f.contentY, end, 0.5);
        keys("<CR>");
        fuzzyCompare(f.contentY, end, 0.5);
        keys("gg<C-d><C-d><C-d><C-d><C-d><C-d><C-d><C-d><C-d><C-d><C-d><C-d><C-d>");
        fuzzyCompare(f.contentY, end, 0.5);
        keys("Gzt<C-d>");
        fuzzyCompare(f.contentY, last.y - narrowText.topPadding, 0.5);
        keys("<C-u>");
        fuzzyCompare(f.contentY, last.y - narrowText.topPadding - Math.floor(vim.pageLines / 2) * vim.lineHeight, 0.5);
        // Ctrl-F keeps the last two lines in view, and puts the cursor on
        // the top line, where zt would have it.
        const top = n => line(n).y - narrowText.topPadding;
        const cursorLine = () => Txt.lineOf(narrowText.text, vim.cursor);
        const page = vim.pageLines - 2;
        keys("gg<C-f>");
        fuzzyCompare(f.contentY, top(1 + page), 0.5);
        compare(cursorLine(), 1 + page);
        keys("gg3<C-f>");
        fuzzyCompare(f.contentY, top(1 + 3 * page), 0.5);
        compare(cursorLine(), 1 + 3 * page);
        // With the last line in view, it goes to the top.
        keys("ggG<C-f>");
        fuzzyCompare(f.contentY, top(50), 0.5);
        compare(cursorLine(), 50);
        keys("gg100<C-f>");
        fuzzyCompare(f.contentY, top(50), 0.5);
        // Then there's nothing left to scroll.
        keys("<C-f>");
        fuzzyCompare(f.contentY, top(50), 0.5);
        compare(cursorLine(), 50);
    }

    // Koil's keys in a macro see its edits so far (main.qml reads the
    // editor).
    function test_macroCommandKey() {
        load("abc");
        vim.commandKeys = { "-": "parent" };
        vim.registers.a = { text: "x-", linewise: false, hidden: [] };
        let seen = "";
        const f = () => seen = editor.text;
        vim.keyCommand.connect(f);
        keys("@a");
        vim.keyCommand.disconnect(f);
        compare(seen, "bc");
    }

    // Edits in chunks keep the hidden text right, also for the editor's own
    // edits after them.
    function test_macroKeepsHidden() {
        load("M  1");
        vim.linePrefixes = true;
        keys("qayyp<C-a>q");
        vim.chunkTime = 0; // with the timer
        keys("2@a");
        tryCompare(vim, "running", null);
        compare(render(), "<M:h1>  1\n<M:h1>  2\n<M:h1>  3\n<M:h1>  4");
        keys("ggAx<Esc>");
        compare(render(), "<M:h1>  1x\n<M:h1>  2\n<M:h1>  3\n<M:h1>  4");
    }

    function test_multipleCursors() {
        load("ab\ncd");
        vim.toggleCursor(3);
        compare(vim.cursors.length, 1);
        keys("iX<Esc>");
        compare(render(), "Xab\nXcd");
        compare(vim.cursors.length, 0);
        // The main cursor after an extra one.
        load("ab\ncd\nef");
        keys("j");
        vim.toggleCursor(6);
        vim.toggleCursor(0);
        keys("iX");
        compare(vim.cursor, 5);
        compare(vim.cursors.map(c => c.pos), [1, 9]);
        keys("<Esc>");
        compare(render(), "Xab\nXcd\nXef");
    }

    // Drawing a block gives only the lines asked for.
    function test_blockSpans() {
        load("ab\ncd\nef\ngh");
        keys("l<C-v>jj");
        compare(vim.blockSpans(), [{ start: 1, end: 2 }, { start: 4, end: 5 }, { start: 7, end: 8 }]);
        compare(vim.blockSpans(3, 8), [{ start: 4, end: 5 }, { start: 7, end: 8 }]);
        compare(vim.blockSpans(9, 11), []);
    }

    function test_countedInsert() {
        load("1");
        keys("3oab<Esc>");
        compare(render(), "1\nab\nab\nab");
        compare(vim.cursor, 9);
        load("x");
        keys("2ia<CR>b<Esc>");
        compare(render(), "a\nba\nbx");
        load("x");
        keys("3iab<BS>c<Esc>"); // typed again key by key
        compare(render(), "acacacx");
        keys("u");
        compare(render(), "x");
    }

    function test_blockEditKeepsHidden() {
        load("Mab\nCcd\nMef");
        keys("l<C-v>jjIXY<BS><Esc>");
        compare(render(), "<M:h1>Xab\n<C:h2>Xcd\n<M:h3>Xef");
        keys("ugg0<C-v>jjIZ<Esc>");
        compare(render(), "Z<M:h1>ab\nZ<C:h2>cd\nZ<M:h3>ef");
        keys("ugg0<C-v>jjI<Del><Esc>");
        compare(render(), "ab\ncd\nef");
        keys("u");
        compare(render(), "<M:h1>ab\n<C:h2>cd\n<M:h3>ef");
        load("Mab\nC\nMef");
        keys("l<C-v>jjAX<Esc>"); // pads the short line
        compare(render(), "<M:h1>aXb\n<C:h2> X\n<M:h3>eXf");
        // Cursors far apart edit one by one.
        load("a" + "x".repeat(3000) + "\nb");
        vim.toggleCursor(3002);
        keys("iZ<Esc>");
        compare(render(), "Za" + "x".repeat(3000) + "\nZb");
    }

    function test_setAndSearch() {
        load("a b a b");
        keys(":set nu fs+=2<CR>");
        verify(vim.number);
        compare(vim.fontSize, 18);
        keys("/b<CR>n");
        compare(vim.cursor, 6);
        keys(":bogus<CR>");
        verify(vim.messageIsError);
    }

    // Smart case: a search ignores case unless it has an uppercase letter,
    // not counting an escape's.
    function test_smartCase() {
        load("Ab ab AB");
        keys("/ab<CR>");
        compare(vim.cursor, 3);
        keys("n");
        compare(vim.cursor, 6);
        keys("/AB<CR>");
        compare(vim.cursor, 6);
        keys("n");
        compare(vim.cursor, 6);
        keys("0/\\Sb<CR>");
        compare(vim.cursor, 3);
        keys("/A(<CR>"); // not a valid regular expression: literal, and no match
        verify(vim.messageIsError);
        // A search that found nothing highlights nothing, even once the text
        // has it.
        compare(vim.highlightPattern, "");
        keys("0iA(<Esc>");
        compare(vim.searchHighlights(), []);
        keys("n");
        compare(vim.highlightPattern, "A(");
        verify(Txt.ignoresCase("\\x4a\\u00C9\\cM\\D", true));
        verify(!Txt.ignoresCase("\\\\S", true));
        verify(!Txt.ignoresCase("\\S", false));
    }

    // & goes back to the defaults Koil gives (the saved settings).
    function test_setDefault() {
        load("a");
        vim.defaultNumber = true;
        vim.defaultFontSize = 20;
        keys(":set nonu fs=12<CR>:set nu& fs&<CR>");
        verify(vim.number);
        compare(vim.fontSize, 20);
        vim.defaultNumber = false;
        vim.defaultFontSize = 16;
        keys(":set nu& fs&<CR>");
    }

    // Koil's :set options.
    function test_setKoilOptions() {
        load("a");
        keys(":set hid ignore re<CR>");
        verify(vim.showHidden && vim.gitignore && vim.regex);
        keys(":set nohidden gitignore& invregex<CR>");
        verify(!vim.showHidden && !vim.gitignore && !vim.regex);
        keys(":set sort=size sr<CR>");
        compare([vim.sort, vim.sortReverse], ["size", true]);
        keys(":set sort?<CR>");
        compare(vim.message, "  sort=size");
        keys(":set sort=big<CR>");
        verify(vim.messageIsError);
        compare(vim.sort, "size");
        keys(":set sort= nosortreverse<CR>");
        compare([vim.sort, vim.sortReverse], ["name", false]);
    }

    // What the quit commands ask for: quitRequested's force, confirm and
    // all, and writeRequested's quit and confirm.
    function test_quitCommands() {
        load("a");
        quits.clear();
        writes.clear();
        keys(":q<CR>:qa<CR>:q!<CR>ZQ:qa!<CR>:conf q<CR>");
        compare(quits.signalArguments.map(a => [a[0], a[1], a[2]]), [[false, false, false], [false, false, true], [true, false, false], [true, false, false], [true, false, true], [false, true, false]]);
        keys(":w<CR>:wq<CR>ZZ");
        compare(writes.signalArguments.map(a => [a[0], a[1]]), [[false, false], [true, false], [true, true]]);
    }

    // ---- Koil's keys ---------------------------------------------------------

    function test_commandKeys() {
        load("one\n  two\nthree");
        vim.commandKeys = {
            "  ": "apply",
            " a": "applyAsking",
            " u": "undoApply",
            "-": "parent",
            "<CR>": "open"
        };
        keyCommands.clear();
        keys("  ");
        keys(" a");
        keys(" u");
        keys("3-");
        keys("<CR>");
        compare(keyCommands.signalArguments.map(a => [a[0], a[1]]),
            [["apply", 0], ["applyAsking", 0], ["undoApply", 0], ["parent", 3], ["open", 0]]);
        compare(vim.cursor, 0);
        // Space then anything else is a mistake, as vim's own bad keys are.
        keys(" l");
        compare(keyCommands.count, 5);
        compare(vim.cursor, 0);
        compare(vim.pendingKeys, "");
        // Shift+Enter is vim's Enter, and so is "-" after an operator or in
        // visual mode.
        keys("<S-CR>");
        compare(vim.cursor, 6);
        keys("d-");
        compare(render(), "three");
        compare(keyCommands.count, 5);
        vim.commandKeys = {};
        keys("<CR>");
        compare(keyCommands.count, 5);
    }

    // Koil's g. and the like leave vim's own g commands alone.
    function test_commandKeysAfterG() {
        load("one two\nthree");
        vim.commandKeys = {
            "g.": "hidden",
            "gi": "gitignore"
        };
        keyCommands.clear();
        keys("jgg");
        compare(vim.cursor, 0);
        keys("gUiw");
        compare(render(), "ONE two\nthree");
        keys("3g.gi");
        compare(keyCommands.signalArguments.map(a => [a[0], a[1]]), [["hidden", 3], ["gitignore", 0]]);
        keys("gx");
        compare(vim.pendingKeys, "");
        compare(keyCommands.count, 2);
    }

    // What's drawn after lines (Editor's notes and messages) goes in a
    // column where the most of it is, and still ends by the view's edge.
    function test_inLine() {
        const cells = (owns, widths) => owns.map((own, i) => ({ own: own, width: widths[i] }));
        // all of them, after the longest line
        compare(Txt.inLine(cells([8, 12, 10], [5, 5, 5]), 40), 12);
        // not after one too long for the view: it keeps its own
        compare(Txt.inLine(cells([8, 10, 60], [5, 5, 5]), 40), 10);
        compare(Txt.cellColumn(60, 5, 10, 40), 60);
        compare(Txt.cellColumn(8, 5, 10, 40), 10);
        // none fits in line: each stays at its own
        const narrow = Txt.inLine(cells([8, 10], [5, 5]), 12);
        compare([Txt.cellColumn(8, 5, narrow, 12), Txt.cellColumn(10, 5, narrow, 12)], [8, 10]);
        // a wide one that would end past the view stays at its own, and
        // the others go in line
        compare(Txt.inLine(cells([6, 6, 20, 20], [30, 4, 4, 4]), 30), 20);
        compare(Txt.cellColumn(6, 30, 20, 30), 6);
        // but one that doesn't fit is in line at its own column
        compare(Txt.inLine(cells([10, 11], [17, 51]), 40), 11);
        compare(Txt.cellColumn(10, 17, 11, 40), 11);
        compare(Txt.cellColumn(11, 51, 11, 40), 11);
        // as many either way: the closer column
        compare(Txt.inLine(cells([5, 9], [3, 2]), 10), 5);
        compare(Txt.inLine([], 40), -1);
        // a column per character, an icon's surrogate pair too
        compare(Txt.columns("a" + mushroom + "b\nc", 0, 4), 3);
    }

    // gs waits for the key of a sort (Koil's sort menu shows while it
    // does), and a key it doesn't know is a mistake.
    function test_sortKeys() {
        load("one two\nthree");
        vim.commandKeys = {
            "gss": "sort:size",
            "gsS": "sortReverse:size"
        };
        keyCommands.clear();
        keys("gs");
        compare(vim.pendingKeys, "gs");
        keys("S");
        compare(vim.pendingKeys, "");
        keys("gsx");
        compare(vim.pendingKeys, "");
        compare(render(), "one two\nthree");
        // From outside vim (the sort button, a click in the menu), out of
        // insert mode first.
        keys("A!");
        vim.startCommand(["g", "s"]);
        compare([vim.mode, vim.pendingKeys], ["normal", "gs"]);
        vim.startCommand([]);
        compare(vim.pendingKeys, "");
        vim.startCommand(["g", "s", "s"]);
        compare(keyCommands.signalArguments.map(a => a[0]), ["sortReverse:size", "sort:size"]);
        compare(render(), "one two!\nthree");
        vim.commandKeys = {};
    }

    // Shift+Enter in insert mode is a line break, not Qt's line separator.
    function test_shiftEnterInInsert() {
        load("ab");
        keys("a<S-CR><Esc>");
        compare(render(), "a\nb");
    }

    // Each buffer has its own text, cursor, undo history and hidden text;
    // registers are shared.
    function test_buffers() {
        load("one M\ntwo");
        keys("jdd0yw");
        other.text = "path";
        const listing = switchTo(other, null);
        compare(vim.cursor, 0);
        compare(vim.hidden, []);
        keys("$p");
        compare(other.text, "pathone ");
        keys("uu");
        compare(other.text, "path");
        compare(vim.message, "Already at oldest change");
        keys("0xA!");
        compare(vim.mode, "insert");

        // Leaving a buffer leaves insert mode.
        const path = switchTo(editor, listing);
        compare(vim.mode, "normal");
        compare(other.text, "ath!");
        verify(other.readOnly);
        compare(render(), "one <M:h1>");
        compare(vim.cursor, 0);
        keys("u");
        compare(render(), "one <M:h1>\ntwo");
        keys("vj");

        // So does visual mode, and the cursor comes back where it was left.
        switchTo(other, path);
        compare(vim.mode, "normal");
        compare(vim.cursor, 3);
        keys("uu");
        compare(other.text, "path");
        compare(editor.text, "one " + mushroom + "\ntwo");
    }

    // Entering a buffer with the cursor past the right edge scrolls to all
    // of the character it's on, not just to the edge of its cursor
    // rectangle (a bar).
    function test_enterShowsWholeCursor() {
        load("one");
        narrowText.text = "x".repeat(60);
        waitForRendering(narrow);
        const f = narrow.contentItem as Flickable;
        switchTo(narrowText, {
            cursor: 59
        }, f);
        compare(vim.cursor, 59);
        verify(f.contentX > 0);
        verify(f.contentX + f.width >= narrowText.positionToRectangle(60).x, "the last x is cut off");
    }

    // The cursor scrolls the view sideways as little as keeps
    // sidescrolloff columns in view on either side of it.
    function test_sideScrollOff() {
        load("one");
        narrowText.text = "x".repeat(60);
        waitForRendering(narrow);
        const f = narrow.contentItem as Flickable;
        switchTo(narrowText, {
            cursor: 0
        }, f);
        const x = p => narrowText.positionToRectangle(p).x;
        vim.charWidth = x(1) - x(0);
        keys(":set siso=2<CR>");
        // The view scrolls by whole pixels (a ScrollView's Flickable is
        // pixelAligned).
        keys("30l");
        fuzzyCompare(f.contentX + f.width, x(33) + narrowText.rightPadding, 0.5);
        keys("20h");
        fuzzyCompare(f.contentX + narrowText.leftPadding, x(8), 0.5);
        keys("$");
        fuzzyCompare(f.contentX, f.contentWidth - f.width, 0.5);
        keys("0");
        compare(f.contentX, 0);
        // Typing too, which the editor does.
        keys("i" + "y".repeat(20));
        wait(0);
        compare(vim.cursor, 20);
        fuzzyCompare(f.contentX + f.width, x(23) + narrowText.rightPadding, 0.5);
        keys("<Esc>");
    }

    // At a name's start in the listing, the view shows its prefix, the
    // icon that hides its ID, even with no sidescrolloff.
    function test_sideScrollOffPrefix() {
        load("one");
        narrowText.text = mushroom + "  " + "x".repeat(60);
        waitForRendering(narrow);
        const f = narrow.contentItem as Flickable;
        vim.linePrefixes = true;
        switchTo(narrowText, {
            hidden: [{ at: 0, icon: mushroom, text: "1" }]
        }, f);
        vim.sideScrollOff = 0;
        keys("$");
        verify(f.contentX > 0);
        keys("0");
        compare(vim.cursor, mushroom.length + 2);
        compare(f.contentX, 0);
        keys("$b^");
        compare(f.contentX, 0);
    }

    // A one-line buffer (Koil's path field) gets spaces for line breaks,
    // and Enter while typing does what it does in normal mode.
    function test_singleLine() {
        load("one\ntwo");
        keys("yj");
        other.text = "a b";
        switchTo(other, null);
        vim.singleLine = true;
        keys("p");
        compare(other.text, "a b one two");
        keys("ox<Esc>");
        compare(other.text, "a b one two x");
        vim.commandKeys = {
            "<CR>": "open",
            "<S-CR>": "update"
        };
        keyCommands.clear();
        keys("Ay<CR>");
        compare(other.text, "a b one two xy");
        compare(vim.mode, "normal");
        compare(keyCommands.signalArguments.map(a => a[0]), ["open"]);
        keys("Rz<S-CR>");
        compare(other.text, "a b one two xz");
        compare(vim.mode, "normal");
        compare(keyCommands.signalArguments.map(a => a[0]), ["open", "update"]);
        // Without a command for Enter, it's only Esc.
        vim.commandKeys = {};
        keys("a!<CR>");
        compare(other.text, "a b one two xz!");
        compare(vim.mode, "normal");
    }

    // A one-line buffer's history (Koil's path field's): k and j, and Up
    // and Down also while typing, put what was entered before back.
    function test_lineHistory() {
        other.text = "now";
        switchTo(other, null);
        vim.singleLine = true;
        vim.lineHistory = ["a", "now", "b"];
        // The one before, skipping what's there already, with the cursor at
        // its end.
        keys("k");
        compare([other.text, vim.cursor], ["b", 0]);
        keys("k");
        compare(other.text, "a");
        // Nothing older: it stays.
        keys("k");
        compare(other.text, "a");
        // After the newest, what it was.
        keys("2j");
        compare([other.text, vim.cursor], ["now", 2]);
        keys("j");
        compare(other.text, "now");
        keys("<Up>");
        compare(other.text, "b");
        // Each is a change, which undo takes back.
        keys("u");
        compare(other.text, "now");
        keys("<Down>");
        compare(other.text, "now");
        // Once the line is edited, it starts over from it.
        keys("kA2<Esc>");
        compare(other.text, "b2");
        keys("k");
        compare(other.text, "b");
        keys("j");
        compare(other.text, "b2");
        // While typing, Up and Down do it, and k and j are typed.
        keys("cc<Up>");
        compare([other.text, vim.mode, vim.cursor], ["b", "insert", 1]);
        keys("<Up>k<Esc>");
        compare(other.text, "nowk");
        keys("u");
        compare(other.text, "now");
        keys("u");
        compare(other.text, "b");
        keys("u");
        compare(other.text, "");
        keys("u");
        compare(other.text, "b2");
        // A new history starts over.
        keys("k");
        vim.lineHistory = ["c"];
        keys("k");
        compare(other.text, "c");
        // Without one, k is vim's, which can't go up from one line.
        vim.lineHistory = null;
        keys("k");
        compare(other.text, "c");
    }

    // A completer like Koil's (see listing::complete) of the dirs `dirs`,
    // like "src/main/", without quotes, case or icons.
    function completerOf(dirs) {
        return (line, cursor) => {
            const before = line.slice(0, cursor), start = before.lastIndexOf("/") + 1;
            const dir = before.slice(0, start), part = before.slice(start);
            const names = [];
            for (const d of dirs) {
                const name = d.startsWith(dir) ? d.slice(dir.length).split("/")[0] : "";
                if (name && name.startsWith(part) && !names.includes(name))
                    names.push(name);
            }
            names.sort();
            let shared = names[0] || "";
            for (const n of names) {
                while (!n.startsWith(shared))
                    shared = shared.slice(0, -1);
            }
            return {
                start: start,
                fill: names.length === 1 ? names[0] + "/" : shared.length > part.length ? shared : "",
                options: names.map(n => ({ name: n + "/", icon: "x", colors: ["", ""] }))
            };
        };
    }

    // Tab while typing completes (Koil's path field), like a shell: as far
    // as all the options go alike, then it shows them to pick one.
    function test_completion() {
        other.text = "";
        switchTo(other, null);
        vim.singleLine = true;
        vim.commandKeys = { "<CR>": "openPath" };
        vim.completer = completerOf(["src/main/", "src/test/", "src-old/", "docs/"]);
        keys("is<Tab>");
        compare(other.text, "src");
        compare(vim.completion, null);
        // Nothing more to fill in: the options, with the first picked.
        keys("<Tab>");
        compare(vim.completion.options.map(o => o.name), ["src/", "src-old/"]);
        compare(vim.completion.index, 0);
        keys("<Tab>");
        compare(vim.completion.index, 1);
        keys("<Tab><S-Tab>");
        compare(vim.completion.index, 1);
        keys("<S-Tab><S-Tab><Down><Down><C-n><C-p><Up>");
        compare(vim.completion.index, 0);
        // Enter takes one, rather than opening the path.
        keyCommands.clear();
        keys("<CR>");
        compare(other.text, "src/");
        compare([vim.completion, vim.mode, keyCommands.count], [null, "insert", 0]);
        // Typing narrows them; a `/` shows that dir's.
        keys("<BS><Tab>");
        compare(vim.completion.options.length, 2);
        keys("/");
        compare(other.text, "src/");
        compare(vim.completion.options.map(o => o.name), ["main/", "test/"]);
        keys("t");
        compare(vim.completion.options.map(o => o.name), ["test/"]);
        // and Backspace widens them, keeping the picked one.
        keys("<BS>");
        compare(vim.completion.options.length, 2);
        compare(vim.completion.index, 1);
        keys("<CR>");
        compare(other.text, "src/test/");
        // Esc only closes them, and another key closes them and does its
        // own thing.
        keys("<BS><BS><BS><BS><BS><Tab>");
        verify(vim.completion !== null);
        keys("<Esc>");
        compare([vim.completion, vim.mode], [null, "insert"]);
        keys("<Tab><Left>");
        compare([vim.completion, vim.cursor], [null, 3]);
        // A click takes one.
        keys("<Right><Tab>");
        vim.takeCompletion(1);
        compare(other.text, "src/test/");
        compare(vim.cursor, 9);
        // The only option, whose `/` steps over the one after the cursor.
        keys("<Esc>");
        other.text = "do/x";
        switchTo(other, null);
        keys("la<Tab>");
        compare(other.text, "docs/x");
        compare(vim.cursor, 5);
        // "." types what the completion did.
        other.text = "";
        switchTo(other, null);
        keys("Ad<Tab><Esc>.");
        compare(other.text, "docs/docs/");
        // Shift+Tab does nothing elsewhere, not even end a command.
        keys("0d<S-Tab>w");
        compare(other.text, "/docs/");
    }

    function test_nothingToUndo() {
        load("ab");
        nothingToUndo.clear();
        keys("xu");
        compare(nothingToUndo.count, 0);
        keys("u");
        compare(nothingToUndo.count, 1);
        compare(vim.message, "Already at oldest change");
    }

    // ---- Hidden text ---------------------------------------------------------

    function test_hiddenAt() {
        load("M  a\nC  b");
        compare(render(), "<M:h1>  a\n<C:h2>  b");
        compare(vim.hiddenAt(0).text, "h1");
        compare(vim.hiddenAt(6).icon, chair);
        compare(vim.hiddenAt(1), null);
    }

    function test_motionsOverIcon() {
        load("aMbC");
        keys("l");
        compare(vim.cursor, 1);
        keys("l");
        compare(vim.cursor, 3);
        compare(vim.positionLabel(), "1:3");
        keys("$h");
        compare(vim.cursor, 3);
        keys("0fb");
        compare(vim.cursor, 3);
    }

    function test_deleteAndUndo() {
        load("aMbMc");
        keys("lx");
        compare(render(), "ab<M:h2>c");
        keys("u");
        compare(render(), "a<M:h1>b<M:h2>c");
        keys("2x");
        compare(render(), "a<M:h2>c");
    }

    // Deleting either of two icons side by side leaves the other's text.
    function test_iconsSideBySide() {
        load("MC");
        keys("x");
        compare(render(), "<C:h2>");
        keys("u");
        compare(render(), "<M:h1><C:h2>");
        keys("lx");
        compare(render(), "<M:h1>");
        keys("u");
        compare(render(), "<M:h1><C:h2>");
    }

    function test_replaceChar() {
        load("aMb");
        keys("lrx");
        compare(render(), "axb");
        keys("u");
        compare(render(), "a<M:h1>b");
    }

    // Backspace in replace mode puts back what was replaced, text and all.
    function test_replaceModeBackspace() {
        load("Mbc");
        keys("Rxy<BS><BS><Esc>");
        compare(render(), "<M:h1>bc");
    }

    function test_changeWordAndRepeat() {
        load("M one M two");
        keys("wcwx<Esc>ww.");
        compare(render(), "<M:h1> x <M:h2> x");
    }

    // Typing is the editor's own edit, which the entries follow.
    function test_typingBeforeIcon() {
        load("M x");
        keys("iab<Esc>");
        compare(render(), "ab<M:h1> x");
        keys("A!<BS>?<Esc>");
        compare(render(), "ab<M:h1> x?");
        keys("u");
        compare(render(), "ab<M:h1> x");
        keys("u");
        compare(render(), "<M:h1> x");
    }

    function test_indentAndCase() {
        load("M ab C");
        keys(">>");
        compare(render(), "    <M:h1> ab <C:h2>");
        keys("gUU");
        compare(render(), "    <M:h1> AB <C:h2>");
        keys("g??");
        compare(render(), "    <M:h1> NO <C:h2>");
    }

    function test_registers() {
        load("M a\nC b");
        keys("\"ayyj\"Ayy\"ap");
        compare(render(), "<M:h1> a\n<C:h2> b\n<M:h1> a\n<C:h2> b");
        keys("gg\"_dd");
        compare(render(), "<C:h2> b\n<M:h1> a\n<C:h2> b");
        compare(vim.getRegister("a").hidden.length, 2);
    }

    // "0 keeps the last yank, deletes and changes go in "1 to "9 (lines)
    // or "- (within a line), and ". ": "/ are vim's own.
    function test_specialRegisters() {
        load("one\ntwo\nthree");
        keys("yyjddx\"0p");
        compare(editor.text, "one\nhree\none");
        compare(vim.getRegister("1").text, "two\n");
        compare(vim.getRegister("-").text, "t");
        keys("ggddcwx<Esc>");
        compare(vim.getRegister("0").text, "one\n");
        compare(vim.getRegister("1").text, "one\n");
        compare(vim.getRegister("2").text, "two\n");
        compare(vim.getRegister("-").text, "hree");
        compare(vim.getRegister(".").text, "x");
        keys("\"_dd");
        compare(vim.getRegister("\"").text, "hree");
        load("a b");
        keys("Afoo<BS>x<Esc>/b<CR>:noh<CR>");
        compare(vim.getRegister(".").text, "fox");
        compare(vim.getRegister("/").text, "b");
        compare(vim.getRegister(":").text, "noh");
        keys("\".P");
        compare(editor.text, "a foxbfox");
        // They can't be written.
        keys("\".dd");
        compare(editor.text, "a foxbfox");
    }

    // :reg lists them in vim's order, each on one line.
    function test_registerList() {
        load("one\ntwo\tx");
        let shown = null;
        const show = rows => shown = rows;
        vim.registersRequested.connect(show);
        vim.lastInsert = "";
        vim.lastSearch = null;
        vim.history = { ":": [], "/": [] };
        keys("yyjdw\"ayy");
        compare(vim.registerList(""), [["l  \"\"", "x^J"], ["l  \"0", "one^J"], ["l  \"a", "x^J"],
            ["c  \"-", "two^I"]]);
        keys(":reg 0 -<CR>");
        compare(shown, [["l  \"0", "one^J"], ["c  \"-", "two^I"]]);
        shown = null;
        keys(":di z<CR>");
        compare(shown, null);
        compare(vim.message, "Nothing in those registers");
        vim.registersRequested.disconnect(show);
        vim.registers = { "a": { text: "x".repeat(400), linewise: false, hidden: [] } };
        compare(vim.registerList("a")[0][1], "x".repeat(300) + "…");
    }

    // Other apps get the icons; Koil gets the hidden text back.
    function test_clipboard() {
        load("M  a");
        keys("\"+yy");
        compare(clipboard.text, mushroom + "  a\n");
        compare(JSON.parse(clipboard.data).hidden, [
            {
                at: 0,
                icon: mushroom,
                text: "h1"
            }
        ]);
        keys("\"+p");
        compare(render(), "<M:h1>  a\n<M:h1>  a");
        keys("v<D-c>$<D-v>");
        compare(render(), "<M:h1>  a\n<M:h1>  <M:h1>a");
    }

    // Koil's listing read again, as one undo step.
    function test_replaceText() {
        load("M a\nC b");
        const entries = [
            {
                at: 0,
                icon: chair,
                text: "h2"
            },
            {
                at: chair.length + 3,
                icon: mushroom,
                text: "h3"
            }
        ];
        vim.replaceText(chair + " b\n" + mushroom + " c", entries);
        compare(render(), "<C:h2> b\n<M:h3> c");
        keys("u");
        compare(render(), "<M:h1> a\n<C:h2> b");
        keys("<C-r>");
        compare(render(), "<C:h2> b\n<M:h3> c");
    }

    // An edit that isn't the user's (Koil's listing, as it changed on disk):
    // undo doesn't take it back, but goes on around it, and the cursor stays
    // on what it was on.
    function test_mergeEdits() {
        load("one\ntwo\nthree");
        keys("jAX<Esc>");
        compare(vim.cursor, 7);
        vim.mergeEdits([
            { start: 0, end: 0, text: "zero\n", hidden: [] },
            { start: 9, end: 14, text: "THREE", hidden: [] }
        ], false);
        compare(editor.text, "zero\none\ntwoX\nTHREE");
        compare(vim.cursor, 12);
        keys("u");
        compare(editor.text, "zero\none\ntwo\nTHREE");
        keys("u");
        compare(editor.text, "zero\none\ntwo\nTHREE");
        keys("<C-r>");
        compare(editor.text, "zero\none\ntwoX\nTHREE");
    }

    // A change the edit touches can't be undone after it, nor can the older
    // ones; the newer ones can.
    function test_mergeEditsTouchesChange() {
        load("abc\ndef");
        keys("x");
        keys("lrX");
        keys("jx");
        compare(editor.text, "bX\ndf");
        vim.mergeEdits([{ start: 0, end: 2, text: "QQ", hidden: [] }], false);
        compare(editor.text, "QQ\ndf");
        keys("u");
        compare(editor.text, "QQ\ndef");
        keys("u");
        compare(editor.text, "QQ\ndef");
    }

    // Redo goes on around it too.
    function test_mergeEditsRedo() {
        load("a\nb");
        keys("x");
        keys("u");
        compare(editor.text, "a\nb");
        vim.mergeEdits([{ start: 3, end: 3, text: "\nc", hidden: [] }], false);
        keys("<C-r>");
        compare(editor.text, "\nb\nc");
    }

    // While typing: what was typed before it is a change, and what after
    // another.
    function test_mergeEditsWhileTyping() {
        load("one");
        keys("Atwo");
        vim.mergeEdits([{ start: 0, end: 0, text: "zero\n", hidden: [] }], false);
        keys("three<Esc>");
        compare(editor.text, "zero\nonetwothree");
        keys("u");
        compare(editor.text, "zero\nonetwo");
        keys("u");
        compare(editor.text, "zero\none");
    }

    // With the hidden texts of what it puts in, and as a change of its own
    // if it's undoable (an answer to Koil's question).
    function test_mergeEditsHidden() {
        load("M a\nC b");
        const hidden = [{ at: 0, icon: chair, text: "h9" }];
        vim.mergeEdits([{ start: 0, end: 0, text: chair + " z\n", hidden: hidden }], false);
        compare(render(), "<C:h9> z\n<M:h1> a\n<C:h2> b");
        const line = (chair + " z\n").length;
        vim.mergeEdits([{ start: line, end: line + mushroom.length + 3, text: "", hidden: [] }], true);
        compare(render(), "<C:h9> z\n<C:h2> b");
        keys("u");
        compare(render(), "<C:h9> z\n<M:h1> a\n<C:h2> b");
    }

    // Any one character can be an icon, like the Nerd Font ones Koil uses
    // (one outside the BMP here), and it's one character to vim.
    function test_anyIcon() {
        const icon = "\u{f0868}";
        load("");
        editor.text = icon + "  a";
        vim.reset([
            {
                at: 0,
                icon: icon,
                text: "7"
            }
        ]);
        keys("l");
        compare(vim.cursor, 2);
        keys("0\"+yy\"+p");
        compare(vim.hidden.map(h => h.text), ["7", "7"]);
        compare(vim.hiddenAt(icon.length + 4).icon, icon);
    }

    function test_invalidClipboardData() {
        load("x");
        clipboard.text = "y" + mushroom;
        clipboard.data = JSON.stringify({
            text: "y" + mushroom,
            hidden: [
                {
                    at: 0,
                    icon: mushroom,
                    text: "no"
                }
            ]
        });
        keys("\"+p");
        compare(render(), "xyM");
        clipboard.data = JSON.stringify({
            text: "y" + mushroom,
            hidden: [
                {
                    at: 1,
                    icon: "💩",
                    text: "no"
                }
            ]
        });
        keys("u\"+p");
        compare(render(), "xyM");
        // Another Koil's hidden texts (IDs) mean other things.
        clipboard.data = JSON.stringify({
            text: "y" + mushroom,
            hidden: [
                {
                    at: 1,
                    icon: mushroom,
                    text: "ok"
                }
            ]
        });
        keys("u\"+p");
        compare(render(), "xyM");
        clipboard.data = JSON.stringify({
            text: "y" + mushroom,
            hidden: [
                {
                    at: 1,
                    icon: mushroom,
                    text: "ok"
                }
            ],
            session: vim.clipboardSession
        });
        keys("u\"+p");
        compare(render(), "xy<M:ok>");
    }

    function test_mouseSelection() {
        load("aMb");
        editor.select(1, 3);
        compare(vim.mode, "visual");
        keys("d");
        compare(render(), "ab");
        keys("u");
        compare(render(), "a<M:h1>b");
    }

    // ---- Prefixes ------------------------------------------------------------

    // Starts over with `spec` (see load) as Koil's listing, whose lines
    // start with a prefix (an icon or a space, then two spaces) that the
    // cursor stays out of. Columns in positionLabel count from its end.
    function loadListing(spec) {
        vim.linePrefixes = true;
        load(spec);
    }

    function test_prefixMotions() {
        loadListing("M  one two\nC  three\n   four");
        compare(vim.positionLabel(), "1:1");
        keys("$0h");
        compare(vim.positionLabel(), "1:1");
        keys("ww"); // over the chair
        compare(vim.positionLabel(), "2:1");
        keys("b");
        compare(vim.positionLabel(), "1:5");
        keys("ee");
        compare(vim.positionLabel(), "2:5");
        keys("ge");
        compare(vim.positionLabel(), "1:7");
        keys("jj^");
        compare(vim.positionLabel(), "3:1");
        keys("gg");
        compare(vim.positionLabel(), "1:1");
        // Nothing before the name, and a space in the prefix isn't found.
        keys("bdF ");
        compare(render(), "<M:h1>  one two\n<C:h2>  three\n   four");
        compare(vim.positionLabel(), "1:1");
        keys("3|");
        compare(vim.positionLabel(), "1:3");
        // A click on an icon goes to its name, also in insert mode.
        editor.cursorPosition = editor.text.indexOf(chair);
        compare(vim.positionLabel(), "2:1");
        keys("A<Up><Home>");
        compare(vim.positionLabel(), "1:1");
        keys("<Left>x<Esc>");
        compare(render(), "<M:h1>  xone two\n<C:h2>  three\n   four");
    }

    // o, O and Enter start a line with three spaces, and Enter at a name's
    // start leaves its icon on it.
    function test_prefixNewLines() {
        loadListing("M  one\nC  two");
        keys("onew<Esc>");
        compare(render(), "<M:h1>  one\n   new\n<C:h2>  two");
        keys("Oup<Esc>");
        compare(render(), "<M:h1>  one\n   up\n   new\n<C:h2>  two");
        keys("Gi<CR>x<Esc>");
        compare(render(), "<M:h1>  one\n   up\n   new\n   \n<C:h2>  xtwo");
        keys("ggla<CR>b<Esc>");
        compare(render(), "<M:h1>  on\n   be\n   up\n   new\n   \n<C:h2>  xtwo");
        loadListing("M  a");
        keys("2ob<Esc>");
        compare(render(), "<M:h1>  a\n   b\n   b");
        // An empty listing gets a prefix to type after.
        loadListing("");
        keys("inew<Esc>");
        compare(render(), "   new");
    }

    // Backspace at a name's start clears the icon (its ID goes), then joins
    // the line to the one above; Delete at a line's end joins the next name.
    function test_prefixBackspace() {
        loadListing("M  one\nC  two");
        keys("ji<BS>");
        compare(render(), "<M:h1>  one\n   two");
        keys("<BS>");
        compare(render(), "<M:h1>  onetwo");
        keys("<BS><Esc>");
        compare(render(), "<M:h1>  ontwo");
        compare(vim.positionLabel(), "1:2");
        keys("u");
        compare(render(), "<M:h1>  one\n<C:h2>  two");
        keys("ggA<Del><Esc>");
        compare(render(), "<M:h1>  onetwo");
        // X and dh clear the icon in normal mode, but keep the line break.
        loadListing("M  one\nC  two");
        keys("jX");
        compare(render(), "<M:h1>  one\n   two");
        compare(vim.positionLabel(), "2:1");
        keys("dhX");
        compare(render(), "<M:h1>  one\n   two");
        compare(vim.positionLabel(), "2:1");
        keys("gg.");
        compare(render(), "   one\n   two");
        keys("u");
        compare(render(), "<M:h1>  one\n   two");
        // At every cursor of a block, as one edit.
        loadListing("M  a\nC  b");
        keys("<C-v>jI<BS><BS><Esc>");
        compare(render(), "   ab");
        // Replace mode's line break goes back with its prefix.
        loadListing("M  ab");
        keys("lR<CR>x");
        compare(render(), "<M:h1>  a\n   x");
        keys("<BS><BS><Esc>");
        compare(render(), "<M:h1>  ab");
    }

    // Cmd+Backspace deletes to the line's start (in the listing, the
    // name's), and there is Backspace. In the command line, it's Ctrl-U.
    function test_cmdBackspace() {
        if (!isMac)
            skip("Cmd+Backspace is macOS's");
        load("one\ntwo three");
        keys("jfhi<D-BS>");
        compare(editor.text, "one\nhree");
        keys("<D-BS><Esc>");
        compare(editor.text, "onehree");
        compare(vim.positionLabel(), "1:3");
        // Typed again by . and a count.
        load("ab\ncd");
        keys("Ax<D-BS>y<Esc>j.");
        compare(editor.text, "y\ny");
        load("ab");
        keys("2Ax<D-BS>y<Esc>");
        compare(editor.text, "y");
        // What's selected goes, as with Backspace.
        load("one two");
        keys("A");
        for (let i = 0; i < 3; i++)
            keyClick(Qt.Key_Left, Qt.ShiftModifier);
        keys("<D-BS><Esc>");
        compare(editor.text, "one ");
        // Normal mode doesn't know it.
        keys("0<D-BS>x");
        compare(editor.text, "ne ");
        keys(":abc<Left><D-BS>");
        compare(vim.commandLine, ":c");
        keys("<Esc>");
        loadListing("M  one\nC  two");
        keys("jA<D-BS>");
        compare(render(), "<M:h1>  one\n<C:h2>  ");
        keys("<D-BS>");
        compare(render(), "<M:h1>  one\n   ");
        keys("<D-BS><Esc>");
        compare(render(), "<M:h1>  one");
    }

    // Whole lines take their prefix along; other edits leave it be.
    function test_prefixEdits() {
        loadListing("M  one\nC  two");
        keys("yyjp");
        compare(render(), "<M:h1>  one\n<C:h2>  two\n<M:h1>  one");
        compare(vim.positionLabel(), "3:1");
        keys("ddVkI!<Esc>");
        compare(render(), "<M:h1>  !one\n<C:h2>  two");
        keys("ccuno<Esc>");
        compare(render(), "<M:h1>  uno\n<C:h2>  two");
        keys("J");
        compare(render(), "<M:h1>  uno two");
        keys("ugJ");
        compare(render(), "<M:h1>  unotwo");
        keys("u>>");
        compare(render(), "<M:h1>      uno\n<C:h2>  two");
        keys("<<Vjrx");
        compare(render(), "<M:h1>  xxx\n<C:h2>  xxx");
        keys("ggdaw");
        compare(render(), "<M:h1>  \n<C:h2>  xxx");
        keys("X");
        compare(render(), "   \n<C:h2>  xxx");
    }

    // Pasted lines get a prefix if they have none, and text with an
    // entry's icon (its ID) pastes as lines.
    function test_prefixPaste() {
        loadListing("M  one\nC  two");
        clipboard.text = "a\nb\n";
        keys("\"+p");
        compare(render(), "<M:h1>  one\n   a\n   b\n<C:h2>  two");
        keys("u");
        clipboard.text = "x\ny";
        keys("gg\"+P");
        compare(render(), "<M:h1>  x\n   yone\n<C:h2>  two");
        loadListing("M  one\nC  two");
        vim.registers = {
            "\"": {
                text: mushroom + "  new",
                linewise: false,
                hidden: [
                    {
                        at: 0,
                        icon: mushroom,
                        text: "h9"
                    }
                ],
                blockwise: false
            }
        };
        keys("p");
        compare(render(), "<M:h1>  one\n<M:h9>  new\n<C:h2>  two");
        // In insert mode, above the cursor's line.
        keys("gg\"+yyGA<D-v>!<Esc>");
        compare(render(), "<M:h1>  one\n<M:h9>  new\n<M:h1>  one\n<C:h2>  two!");
    }

    function test_prefixSearch() {
        loadListing("M  a  b\nC  c");
        keys("/  <CR>");
        compare(vim.positionLabel(), "1:2");
        keys("n");
        compare(vim.positionLabel(), "1:2");
        findBar.open(false);
        findBar.query = "  ";
        compare(findBar.matches.length, 1);
        findBar.close();
    }

    // ---- Find bar ------------------------------------------------------------

    function test_replaceAllKeepsHidden() {
        load("a M a C a");
        findBar.open(true);
        findBar.query = "a";
        findBar.replacement = "b";
        findBar.replaceAll();
        compare(render(), "b <M:h1> b <C:h2> b");
        vim.nativeUndo(false);
        compare(render(), "a <M:h1> a <C:h2> a");
        findBar.close();
    }

    // Older entries come from other tests, so this stays among its own.
    function test_findHistory() {
        load("one two three");
        findBar.open(false);
        findBar.query = "two";
        findBar.next();
        findBar.query = "three";
        findBar.next();
        findBar.query = "tw";
        keyClick(Qt.Key_Up);
        compare(findBar.query, "three");
        keyClick(Qt.Key_Up);
        compare(findBar.query, "two");
        compare(vim.cursor, 4); // it searches, as typing does
        keyClick(Qt.Key_Down);
        compare(findBar.query, "three");
        keyClick(Qt.Key_Down);
        compare(findBar.query, "tw");
        keyClick(Qt.Key_Down);
        compare(findBar.query, "tw");
        keyClick(Qt.Key_Up, Qt.ShiftModifier);
        compare(findBar.query, "tw");
        // What the field has is skipped, and an edit starts over.
        findBar.query = "three";
        keyClick(Qt.Key_Up);
        compare(findBar.query, "two");
        findBar.query = "x";
        keyClick(Qt.Key_Up);
        compare(findBar.query, "three");
        // Using one puts it last.
        findBar.query = "two";
        findBar.previous();
        findBar.query = "";
        keyClick(Qt.Key_Up);
        compare(findBar.query, "two");
        keyClick(Qt.Key_Up);
        compare(findBar.query, "three");
        findBar.close();
        // The replace field has its own.
        findBar.open(true);
        findBar.replacement = "3";
        findBar.replaceAll();
        findBar.replacement = "";
        keyClick(Qt.Key_Up);
        compare(findBar.replacement, "3");
        compare(findBar.query, "three");
        findBar.close();
    }

    // ---- Help ----------------------------------------------------------------

    function test_helpSearch() {
        help.showList("Test", [["a", "one two"], ["b", "two three two"], ["c", "x"]], 4);
        tryCompare(help, "opened", true);
        keys("n");
        compare(help.searchMessage, "E35: No previous regular expression");
        keys("<Esc>");
        verify(help.opened);

        // Matches as it's typed, from the top of the view.
        keys("/tw");
        compare(help.searchKind, "/");
        compare(help.matches.length, 3);
        compare(help.matchIndex, 0);
        compare(help.matchMarks["0/1t"], "0,2,0;10,12,0");
        keys("o<CR>");
        compare(help.searchKind, "");
        compare(help.lastPattern, "two");
        compare(help.matchIndex, 0);
        compare(help.matchMarks["0/0t"], "4,7,1");

        keys("nn");
        compare(help.matchIndex, 2);
        keys("n");
        compare(help.matchIndex, 0);
        compare(help.searchMessage, "search hit BOTTOM, continuing at TOP");
        keys("N");
        compare(help.matchIndex, 2);
        compare(help.searchMessage, "search hit TOP, continuing at BOTTOM");
        // An empty search searches for the last pattern, the new way.
        keys("?<CR>");
        compare(help.matchIndex, 1);
        compare(help.searchMessage, "");
        keys("n");
        compare(help.matchIndex, 0);
        keys("N");
        compare(help.matchIndex, 1);
        // Find Next and Previous go down and up, whichever way n goes.
        help.searchAgain(true);
        compare(help.matchIndex, 2);
        help.searchAgain(false);
        compare(help.matchIndex, 1);

        // Find while typing selects the search, which typing replaces.
        keys("/tw");
        help.startSearch("/");
        compare(help.searchKind, "/");
        compare(help.searchPattern, "tw");
        verify(help.holds(tc.Window.window.activeFocusItem));
        keys("two<CR>");
        compare(help.lastPattern, "two");
        verify(help.holds(tc.Window.window.activeFocusItem));
        verify(!help.holds(editor));

        keys("/zzz<CR>");
        compare(help.matchIndex, -1);
        compare(help.searchMessage, "E486: Pattern not found: zzz");
        verify(help.searchFailed);

        // Esc while typing goes back to before, as does Backspace on nothing.
        keys("/thr");
        compare(help.matches.length, 1);
        keys("<Esc>");
        compare(help.searchKind, "");
        compare(help.searchPattern, "zzz");
        verify(help.opened);
        keys("/<Up>");
        compare(help.searchPattern, "zzz");
        keys("<Up>");
        compare(help.searchPattern, "two");
        compare(help.matchIndex, 0);
        keys("<Down><Down>");
        compare(help.searchPattern, "zzz");
        keys("<BS>");
        compare(help.searchKind, "");

        // Esc clears the highlights, and then closes the help.
        keys("<Esc>");
        compare(help.searchPattern, "");
        verify(help.opened);
        keys("<Esc>");
        tryCompare(help, "opened", false);

        // Codes are searched as they're shown.
        help.show("");
        tryCompare(help, "opened", true);
        keys("/Space Space<CR>");
        compare(help.matches.length, 1);
        compare(help.matchMarks["0/1k"], "0,11,1");
        keys("<Esc><Esc>");
        tryCompare(help, "opened", false);
    }

    // ---- Confirmations -------------------------------------------------------

    // Lines to pick from as the undo history gives them: some start left
    // out, some can't be picked, and one takes two lines of text.
    function test_confirmPicks() {
        let chosen = null;
        confirm.ask((count, picked) => count + ":" + picked.join(","), [
            { text: "A\nstep", needs: [], picked: true },
            { text: "B", needs: [], picked: false, blocked: true },
            { text: "C", needs: [0], picked: false },
            { text: "D", needs: [2], picked: false }
        ], picked => chosen = picked);
        tryCompare(confirm, "opened", true);
        compare(confirm.text, "1:true,false,false,false");
        const [off, on, blocked] = confirm.boxes;
        // With an empty line between them, as one takes two lines.
        compare(confirm.list, on + "A\n" + confirm.pad + "step\n\n" + blocked + "B\n\n" + off + "C\n\n" + off + "D");
        // The second line of text is the first line's, and the empty one
        // after it no line's.
        const at = part => confirm.itemAt(confirm.list.indexOf(part));
        compare(at("step"), 0);
        compare(confirm.itemAt(confirm.list.indexOf("step") + 5), -1);
        compare(at("C"), 2);

        // Picking one picks what it needs, and leaving one out leaves out
        // what needs it; one that can't be picked stays out.
        confirm.toggle(1);
        compare(confirm.picked, [true, false, false, false]);
        confirm.toggle(3);
        compare(confirm.picked, [true, false, true, true]);
        confirm.toggle(0);
        compare(confirm.picked, [false, false, false, false]);
        confirm.pickAll();
        compare(confirm.picked, [true, false, true, true]);
        confirm.pickAll();
        compare(confirm.picked, [false, false, false, false]);

        confirm.toggle(2);
        confirm.answer("yes");
        compare(chosen, [0, 2]);
        verify(!confirm.opened);
    }

    // The words lines start with get the color of the change they stand
    // for, only in the questions that say so.
    function test_confirmKeywords() {
        confirm.ask("Apply?", "MOVE   a -> b", () => {}, null, null, { MOVE: "rename", TRASH: "delete" });
        compare(confirm.keywordColors, ["MOVE", theme.changeColor("rename"), "TRASH", theme.changeColor("delete")]);
        confirm.answer("cancel");
        confirm.ask("Delete it anyway?", "MOVE -> b", () => {});
        compare(confirm.keywordColors, []);
        confirm.answer("cancel");
    }
}
