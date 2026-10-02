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
    // (Shift+Enter), <C-v> (Ctrl) or <D-c> (Cmd on macOS, Ctrl elsewhere).
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
                else if (/^C-[a-z]$/.test(name))
                    keyClick(Qt.Key_A + name.charCodeAt(2) - 97, ctrl);
                else if (/^D-[a-z]$/.test(name))
                    keyClick(Qt.Key_A + name.charCodeAt(2) - 97, Qt.ControlModifier);
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

    property int defaultChunkTime
    property real defaultCharWidth
    property int defaultSideScrollOff

    function initTestCase() {
        defaultChunkTime = vim.chunkTime;
        defaultCharWidth = vim.charWidth;
        defaultSideScrollOff = vim.sideScrollOff;
    }

    // Back to the editor, after a test that switched buffers.
    function cleanup() {
        if (vim.running)
            vim.stopRun();
        vim.chunkTime = defaultChunkTime;
        vim.charWidth = defaultCharWidth;
        vim.sideScrollOff = defaultSideScrollOff;
        if (vim.editor !== editor)
            switchTo(editor, null);
        vim.flickable = null;
        vim.singleLine = false;
        vim.linePrefixes = false;
        vim.commandKeys = {};
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
            "  ": "update",
            " a": "apply",
            "-": "parent",
            "<CR>": "open"
        };
        keyCommands.clear();
        keys("  ");
        keys(" a");
        keys("3-");
        keys("<CR>");
        compare(keyCommands.signalArguments.map(a => [a[0], a[1]]), [["update", 0], ["apply", 0], ["parent", 3], ["open", 0]]);
        compare(vim.cursor, 0);
        // Space then anything else is a mistake, as vim's own bad keys are.
        keys(" l");
        compare(keyCommands.count, 4);
        compare(vim.cursor, 0);
        compare(vim.pendingKeys, "");
        // Shift+Enter is vim's Enter, and so is "-" after an operator or in
        // visual mode.
        keys("<S-CR>");
        compare(vim.cursor, 6);
        keys("d-");
        compare(render(), "three");
        compare(keyCommands.count, 4);
        vim.commandKeys = {};
        keys("<CR>");
        compare(keyCommands.count, 4);
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
}
