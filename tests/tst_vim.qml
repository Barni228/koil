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

    // A buffer whose lines wrap (see switchTo), a row about 16 columns
    // wide.
    ScrollView {
        id: wrapView

        x: 300
        width: 150
        height: 120

        TextArea {
            id: wrapText

            textFormat: TextEdit.PlainText
            wrapMode: TextEdit.Wrap
            readOnly: true
            onCursorPositionChanged: {
                if (vim.editor === wrapText)
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

    SignalSpy {
        id: shells

        target: vim
        signalName: "shellRequested"
    }

    SignalSpy {
        id: stops

        target: vim
        signalName: "stopRequested"
    }

    SignalSpy {
        id: links

        target: vim
        signalName: "linkRequested"
    }

    SignalSpy {
        id: editCommands

        target: vim
        signalName: "editRequested"
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
    property int defaultPreviewMargin

    function initTestCase() {
        defaultChunkTime = vim.chunkTime;
        defaultPreviewMargin = vim.previewMargin;
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
        vim.previewMargin = defaultPreviewMargin;
        if (vim.editor !== editor)
            switchTo(editor, null);
        vim.flickable = null;
        vim.wrap = false;
        (wrapView.contentItem as Flickable).contentY = 0;
        (wrapView.contentItem as Flickable).bottomMargin = 0;
        narrow.height = 30;
        (narrow.contentItem as Flickable).bottomMargin = 0;
        (narrow.contentItem as Flickable).rightMargin = 0;
        vim.singleLine = false;
        vim.linePrefixes = false;
        vim.bangEntries = false;
        vim.commandKeys = {};
        vim.visualCommandKeys = {};
        vim.shortcuts = [];
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

    // * and # in visual mode search for what's selected, as it is (not as
    // a regex), as Neovim's, without the prefixes in the listing.
    function test_visualSearch() {
        load("x foo.bar\nfooXbar foo.bar");
        keys("wv6l*");
        compare(vim.mode, "normal");
        compare(vim.cursor, 18);
        compare(vim.lastSearch.pattern, "foo\\.bar");
        keys("v6l#");
        compare(vim.cursor, 2);
        keys("n");
        compare(vim.cursor, 18);
        load("ab\ncd\nab\ncd");
        keys("Vj*");
        compare(vim.cursor, 6);
        compare(vim.lastSearch.pattern, "ab\\ncd");
        loadListing("M  ab\nC  ab");
        keys("V*");
        compare(vim.cursor, editor.text.lastIndexOf("ab"));
    }

    // Y yanks to the line's end, as Neovim's (y$), but lines in visual
    // mode.
    function test_yankToEnd() {
        load("one two\nthree\nfour");
        keys("wY");
        compare(vim.registers["\""].text, "two");
        compare(vim.registers["\""].linewise, false);
        compare(vim.cursor, 4);
        keys("2Y");
        compare(vim.registers["\""].text, "two\nthree");
        keys("vjY");
        compare(vim.registers["\""].text, "one two\nthree\n");
        compare(render(), "one two\nthree\nfour");
    }

    // G, gg, N%, :N and commands on whole lines (dd, >>, ==, V's d) keep
    // the cursor's column, as Neovim's nostartofline, and j and k keep it
    // after them too. Vim's go to the first non-blank.
    function test_noStartOfLine() {
        load("abcdef\n  ab\nabcdef");
        keys("3lG");
        compare(vim.cursor, 15);
        keys("gg");
        compare(vim.cursor, 3);
        keys("2%");
        compare(vim.cursor, 3);
        keys("50%");
        compare(vim.cursor, 10);
        keys(":3<CR>");
        compare(vim.cursor, 15);
        keys("$gg");
        compare(vim.cursor, 5);
        load("abcdef\nab\nabcdef");
        keys("4ldd");
        compare(vim.cursor, 1);
        keys("j");
        compare(vim.cursor, 7);
        load("abcdef\nabcdef\nabcdef");
        keys("3lVjd");
        compare(render(), "abcdef");
        compare(vim.cursor, 3);
        load("abcdef");
        keys("2l>>");
        verify(editor.text.endsWith("abcdef") && editor.text.length > 6);
        compare(vim.cursor, 2);
        load("{\nabc\n}");
        keys("j2l==");
        compare(render(), "{\n    abc\n}");
        compare(vim.cursor, 4);
        // In the listing, out of the prefixes.
        loadListing("M  abc\nC  d");
        keys("G");
        compare(vim.cursor, 12);
    }

    // j and k keep the column the cursor last went to, but not past a new
    // text, nor an edit, a yank or an undo that left it in another (as vim).
    function test_jkColumn() {
        load("abcdef\nabcdef\nabcdef");
        keys("4lj");
        compare(vim.cursor, 11);
        load("abcdef\nabcdef\nabcdef");
        keys("j");
        compare(vim.cursor, 7);
        keys("4ld0j");
        compare(vim.cursor, 10);
        load("abcdef\nabcdef\nabcdef");
        keys("4lyypj");
        compare(vim.cursor, 14);
        load("abcdef\nabcdef");
        keys("4lx0uj");
        compare(vim.cursor, 11);
        load("abcdef\nabcdef");
        keys("lvlllyj");
        compare(vim.cursor, 8);
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

    // The line starts of a long text carried past an edit (Txt.carryLines)
    // are those going through the edited text finds, however far they
    // were found before it.
    function test_carryLines() {
        const plainStarts = t => {
            const r = [0];
            for (let i = t.indexOf("\n"); i >= 0; i = t.indexOf("\n", i + 1))
                r.push(i + 1);
            return r;
        };
        let t = "";
        for (let i = 0; i < 3000; i++)
            t += "line " + i + "\n";
        // [start, end, text]: [100, 200) is lines 15 to 30.
        const edits = [[5, 5, "x"], [100, 200, ""], [100, 200, "a\nb\n"], [8000, 8010, "\n\n"], [t.length - 3, t.length, "z"], [0, t.length, "short"]];
        let k = 0;
        for (const [start, end, text] of edits) {
            for (const found of [1, 30, 2000, Infinity]) {
                // A text of its own, which no other lookup found lines in.
                const before = t + "#" + k++;
                if (found === Infinity)
                    Txt.countLines(before);
                else
                    Txt.lineToPos(before, found);
                const after = before.slice(0, start) + text + before.slice(end);
                Txt.carryLines(before, after, start, end, text);
                const plain = plainStarts(after), got = [];
                for (let n = 1; n <= plain.length; n++)
                    got.push(Txt.lineToPos(after, n));
                const what = JSON.stringify([start, end, text, found]);
                compare(JSON.stringify(got), JSON.stringify(plain), what);
                compare(Txt.countLines(after), plain.length, what);
            }
        }
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

    // @ in visual mode runs the macro on each line, as Neovim's, from its
    // start, as one undo step. A line it fails on is skipped, and what it
    // leaves half done (an insert) is ended.
    function test_visualMacro() {
        load("a\nb\nc\nd");
        vim.registers["q"] = { text: "A!<Esc>", linewise: false, hidden: [] };
        keys("jVj@q");
        compare(render(), "a\nb!\nc!\nd");
        compare(vim.mode, "normal");
        compare(vim.running, null);
        keys("u");
        compare(render(), "a\nb\nc\nd");
        load("a,1\nb\nc,3");
        vim.registers["q"] = { text: "f,r;", linewise: false, hidden: [] };
        keys("VG@q");
        compare(render(), "a;1\nb\nc;3");
        compare(vim.typeahead.length, 0);
        load("a\nb");
        vim.registers["q"] = { text: "A!", linewise: false, hidden: [] };
        keys("Vj@q");
        compare(render(), "a!\nb!");
        compare(vim.mode, "normal");
        // in the last command line typed, and with a count
        load("a\nb\nc");
        keys(":s/$/!/<CR>jVj@:");
        compare(render(), "a!\nb!\nc!");
        load("a\nb");
        vim.registers["q"] = { text: "A!<Esc>", linewise: false, hidden: [] };
        keys("Vj2@q");
        compare(render(), "a!!\nb!!");
    }

    // The lines it goes to move with the edits, as the marked lines do,
    // rather than going by their numbers as :normal does.
    function test_visualMacroFollowsLines() {
        load("a\nb");
        vim.registers["q"] = { text: "yyp", linewise: false, hidden: [] };
        keys("Vj@q");
        compare(render(), "a\na\nb\nb");
        load("a\nb\nc\nd");
        vim.registers["q"] = { text: "dd", linewise: false, hidden: [] };
        keys("jVj@q");
        compare(render(), "a\nd");
    }

    // A macro running one on each line goes on after it, also after a
    // line it failed on, as after :normal.
    function test_visualMacroInMacro() {
        load("a,\nb\nc,");
        vim.registers["q"] = { text: "f,x", linewise: false, hidden: [] };
        vim.registers["w"] = { text: "VG@qggAz<Esc>", linewise: false, hidden: [] };
        keys("@w");
        compare(render(), "az\nb\nc");
        load("a,\nb,\nc");
        vim.registers["q"] = { text: "f,x", linewise: false, hidden: [] };
        vim.registers["w"] = { text: "VG@qGAz<Esc>", linewise: false, hidden: [] };
        keys("@w");
        compare(render(), "a\nb\ncz");
    }

    // Q runs the macro recorded last, as Neovim's, and in visual mode on
    // each line.
    function test_replayRecorded() {
        load("a\nb\nc");
        vim.lastRecorded = "";
        keys("Q");
        compare(vim.message, "E748: No previously used register");
        keys("qqA!<Esc>qjQ");
        compare(render(), "a!\nb!\nc");
        keys("jVkQ");
        compare(render(), "a!\nb!!\nc!");
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

    // :set syntax, and vim's :syntax on and off.
    function test_syntax() {
        load("a");
        keys(":set nosyn<CR>");
        verify(!vim.syntax);
        keys(":syntax on<CR>");
        verify(vim.syntax);
        keys(":sy off<CR>:syntax<CR>");
        verify(!vim.syntax);
        compare(vim.message, "nosyntax");
        keys(":syntax maybe<CR>");
        verify(vim.messageIsError);
        keys(":set syn&<CR>");
        verify(vim.syntax);
    }

    // gf and gx ask Koil to open the link at the cursor, and in visual
    // mode what's selected, then leave it.
    function test_links() {
        load("see a.txt or https://x.org\nnext");
        links.clear();
        keys("wgf2Wgx");
        compare(links.signalArguments.map(a => [a[0], a[1], a[2]]), [[4, "", false], [13, "", true]]);
        links.clear();
        keys("0wvEgx");
        compare(links.signalArguments.map(a => [a[1], a[2]]), [["a.txt", true]]);
        compare(vim.mode, "normal");
        compare(vim.cursor, 8);
        links.clear();
        keys("jVgf");
        compare(links.signalArguments.map(a => a[1]), ["next"]);
        // none of them a change
        nothingToUndo.clear();
        keys("u");
        compare(nothingToUndo.count, 1);
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

    // :e asks Koil to open a path as written (spaces and quotes too), or
    // with none, to read what's shown again; :e! to drop unsaved changes.
    function test_editCommand() {
        load("a");
        editCommands.clear();
        keys(":e ~/src<CR>:edit \"my dir\"/x  <CR>:e<CR>:e!<CR>:edi! a b<CR>");
        compare(editCommands.signalArguments.map(a => [a[0], a[1]]), [["~/src", false], ["\"my dir\"/x", false], ["", false],
            ["", true], ["a b", true]]);
        // Not another command, nor with a range.
        keys(":ex<CR>");
        compare(vim.message, "E492: Not an editor command: ex");
        keys(":1e a<CR>");
        compare(vim.message, "E481: No range allowed");
        compare(editCommands.count, 5);
    }

    // ---- Surround ------------------------------------------------------------

    // vim-surround's ys, ds and cs, with the cursor on the pair's start,
    // and no register changed.
    function test_surround() {
        load("one two three");
        keys("wysiw)");
        compare(render(), "one (two) three");
        compare(vim.cursor, 4);
        keys("ds)");
        compare(render(), "one two three");
        compare(vim.cursor, 4);
        // An opening bracket puts a space inside, and takes the blanks
        // inside away.
        keys("ysiw(");
        compare(render(), "one ( two ) three");
        keys("ds(");
        compare(render(), "one two three");
        // A word's blanks after it stay out.
        keys("ysaw]");
        compare(render(), "one [two] three");
        keys("cs]{");
        compare(render(), "one { two } three");
        keys("cs{\"");
        compare(render(), "one \"two\" three");
        keys("cs\"'");
        compare(render(), "one 'two' three");
        keys("ds'");
        compare(render(), "one two three");
        keys("u");
        compare(render(), "one 'two' three");
        keys("yss*");
        compare(render(), "*one 'two' three*");
        compare(vim.cursor, 0);
        // Another sign is the nearest ones on the line.
        keys("fwds*");
        compare(render(), "one 'two' three");
        compare(JSON.stringify(vim.registers), "{}");
        // Aliases, a space first, and s.
        load("ab");
        keys("ysiwb");
        compare(render(), "(ab)");
        keys("csbB");
        compare(render(), "{ab}");
        keys("csBr");
        compare(render(), "[ab]");
        keys("csra");
        compare(render(), "<ab>");
        keys("cs> )");
        compare(render(), "( ab )");
        keys("ds )");
        compare(render(), "ab");
        load("f(x)");
        keys("fxcsbs");
        compare(render(), "f x");
        // A word has nothing to take away: csw is ysiw.
        load("ab cd");
        keys("csw)");
        compare(render(), "(ab) cd");
        keys("dsw");
        compare(render(), "(ab) cd");
        // The second pair out, by either count.
        load("f(a(b)c)");
        keys("fbds2(");
        compare(render(), "fa(b)c");
        load("f(a(b)c)");
        keys("fb2ds(");
        compare(render(), "fa(b)c");
        // yss over lines, from the first one's indent.
        load("  a\nb\nc");
        keys("2yss)");
        compare(render(), "  (a\nb)\nc");
        // Nothing for keys that put nothing, or a pair that isn't there.
        load("a b");
        keys("ysiwq");
        compare(render(), "a b");
        keys("ds(ds*ds\"");
        compare(render(), "a b");
        keys("yss)");
        compare(render(), "(a b)");
    }

    // "." repeats a surround, and it's at every cursor.
    function test_surroundRepeat() {
        load("a b c");
        keys("ysiw\"W.W.");
        compare(render(), "\"a\" \"b\" \"c\"");
        keys("0ds\"W.");
        compare(render(), "a b \"c\"");
        load("a\nb");
        vim.toggleCursor(2);
        keys("ysiw]");
        compare(render(), "[a]\n[b]");
        keys("<Esc>u");
        compare(render(), "a\nb");
    }

    // Over lines: a linewise motion puts the pair on lines of its own, a
    // bracket alone on its line goes with it, and yS, ySS and S on lines
    // indent what's inside.
    function test_surroundLines() {
        load("one\ntwo\n\nthree");
        keys("ysip)");
        compare(render(), "(\none\ntwo\n)\n\nthree");
        compare(vim.cursor, 0);
        keys("ds)");
        compare(render(), "one\ntwo\n\nthree");
        load("f(\n    a\n)");
        keys("jds)");
        compare(render(), "f\n    a");
        // No space inside next to a line break.
        load("f(\n  a\n)");
        keys("jcs)[");
        compare(render(), "f[\n  a\n]");
        load("  a b");
        keys("ySS}");
        compare(render(), "  {\n      a b\n  }");
        load("foo bar");
        keys("wySiw)");
        compare(render(), "foo (\n    bar\n)");
        // Brackets have what's inside reindented by them, as = does.
        load("x\n\ty\nz");
        keys("jySj]");
        compare(render(), "x\n\t[\n\t\ty\n\t\tz\n\t]");
        keys("ds]");
        compare(render(), "x\n\t\ty\n\t\tz");
        load("a\n      b");
        keys("VjS{");
        compare(render(), "{\n    a\n    b\n}");
        // Another pair, which = knows nothing of, a level deeper as > goes.
        load("a\n  b");
        keys("VjS\"");
        compare(render(), "\"\n    a\n      b\n\"");
        load("<p>x</p>");
        keys("ySS<");
        keys("div>");
        compare(render(), "<div>\n    <p>x</p>\n</div>");
        load("a(b)");
        keys("fbcS([");
        compare(render(), "a[\n    b\n]");
    }

    // S in visual mode: around the characters, or the lines on lines of
    // their own (indented, but by gS), or each line's part of a block.
    function test_surroundVisual() {
        load("one two");
        keys("wveS'");
        compare(render(), "one 'two'");
        compare(vim.mode, "normal");
        compare(vim.cursor, 4);
        load("a\nb");
        keys("VjS)");
        compare(render(), "(\n    a\n    b\n)");
        load("a\nb");
        keys("VjgS)");
        compare(render(), "(\na\nb\n)");
        load("one two");
        keys("wvegS)");
        compare(render(), "one (\n    two\n)");
        load("abc\nde\nfgh");
        keys("l<C-v>ljjS)");
        compare(render(), "a(bc)\nd(e )\nf(gh)");
        compare(vim.cursor, 1);
    }

    // A tag is asked for, ends with > or Enter, and cs keeps the old one's
    // attributes unless it ended with >. "." doesn't ask again.
    function test_surroundTags() {
        load("one two");
        keys("wysiw<");
        compare(vim.commandLine, "<");
        keys("em>");
        compare(render(), "one <em>two</em>");
        compare(vim.commandLine, "");
        compare(vim.cursor, 4);
        keys("cst<");
        keys("b class=\"x\"<CR>");
        compare(render(), "one <b class=\"x\">two</b>");
        keys("cst<");
        keys("i<CR>");
        compare(render(), "one <i class=\"x\">two</i>");
        keys("cst<");
        keys("u>");
        compare(render(), "one <u>two</u>");
        keys("cst\"");
        compare(render(), "one \"two\"");
        keys("u");
        compare(render(), "one <u>two</u>");
        keys("dst");
        compare(render(), "one two");
        load("a b");
        keys("ysiwt");
        keys("br/<CR>");
        compare(render(), "<br />a b");
        load("a b");
        keys("ysiw<");
        keys("i>W.");
        compare(render(), "<i>a</i> <i>b</i>");
        // Esc, or nothing typed, puts in none.
        load("a");
        keys("ysiw<");
        keys("em<Esc>ysiw<");
        keys("<CR>");
        compare(render(), "a");
        compare(vim.commandLine, "");
        // From visual mode, on the selection, which stays drawn meanwhile.
        load("one two");
        keys("wveS<");
        compare(vim.mode, "normal");
        verify(vim.visualShown !== null);
        keys("b>");
        compare(render(), "one <b>two</b>");
        // Earlier tags come back with Up.
        keys("0ysiw<");
        keys("<Up><CR>");
        compare(render(), "<b>one</b> <b>two</b>");
    }

    // it and at: in the tags around the cursor, or with them.
    function test_tagObjects() {
        load("<a><b>x</b> <br> y</a>");
        keys("fxdit");
        compare(render(), "<a><b></b> <br> y</a>");
        keys("dat");
        compare(render(), "<a> <br> y</a>");
        keys("fyvity");
        compare(vim.registers["0"].text, " <br> y");
        compare(Txt.tagPair("<a>x</a>", 1, 2), null);
        compare(Txt.tagPair("<a><b/>x</a>", 7, 1), { o1: 0, o2: 3, c1: 8, c2: 12 });
    }

    // In the listing, a pair goes after a line's prefix, and lines it's
    // put on get one, while the entries keep their IDs.
    function test_surroundPrefixes() {
        loadListing("M  one\nC  two");
        keys("yss)");
        compare(render(), "<M:h1>  (one)\n<C:h2>  two");
        keys("ysj]");
        compare(render(), "   [\n<M:h1>  (one)\n<C:h2>  two\n   ]");
        keys("ds]");
        compare(render(), "<M:h1>  (one)\n<C:h2>  two");
        keys("ds)");
        compare(render(), "<M:h1>  one\n<C:h2>  two");
    }

    // = reindents lines by their brackets and tags: in them a level deeper
    // than the line they open on, one that starts by closing them as deep
    // as that line, a blank one with none, and one in none as it is.
    function test_reindent() {
        load("f() {\nx(\n1,\n    2\n        )\n}\n");
        keys("gg=G");
        compare(render(), "f() {\n    x(\n        1,\n        2\n    )\n}\n");
        compare(vim.message, "6 lines indented");
        compare(vim.cursor, 0);
        keys("u");
        compare(render(), "f() {\nx(\n1,\n    2\n        )\n}\n");
        load("{\na\nb\n}");
        keys("j==");
        compare(render(), "{\n    a\nb\n}");
        keys("j2==");
        compare(render(), "{\n    a\n    b\n}");
        load("{\na\nb\n}");
        keys("jVj=");
        compare(render(), "{\n    a\n    b\n}");
        compare(vim.cursor, 2); // in its column, as Neovim's nostartofline
        load("{\na\nb\nc\n}");
        keys("jmjjm=");
        compare(render(), "{\n    a\nb\n    c\n}");
        // Python, outside brackets, stays; a blank line goes.
        load("def f():\n    return (1,\n2)\n  \nx = 1");
        keys("gg=G");
        compare(render(), "def f():\n    return (1,\n        2)\n\nx = 1");
        // Not brackets in strings and comments, nor an apostrophe's or a
        // lifetime's quote for a string.
        load("a(\n\")\",\n// )\n/* ( */\n'(',\nit's (\nb)\n)");
        keys("gg=G");
        compare(render(), "a(\n    \")\",\n    // )\n    /* ( */\n    '(',\n    it's (\n        b)\n)");
        load("fn f<'a>(x: &'a str) {\nb\n}");
        keys("gg=G");
        compare(render(), "fn f<'a>(x: &'a str) {\n    b\n}");
        // A comment's lines starting with *.
        load("{\n/**\n* doc\n*/\n}");
        keys("gg=G");
        compare(render(), "{\n    /**\n     * doc\n     */\n}");
        // Tags that pair, not a type's <>.
        load("<ul>\n<li>a</li>\n<li>\nb\n</li>\n</ul>\nList<String> x;\ny");
        keys("gg=G");
        compare(render(), "<ul>\n    <li>a</li>\n    <li>\n        b\n    </li>\n</ul>\nList<String> x;\ny");
        // A level as the text has them, if lines show it twice.
        load("a {\n  b {\n    c\n  }\n}\nd {\ne\n}");
        keys("gg=G");
        compare(render(), "a {\n  b {\n    c\n  }\n}\nd {\n  e\n}");
        load("a {\n  b\n}\nc {\nd\n}");
        keys("gg=G");
        compare(render(), "a {\n    b\n}\nc {\n    d\n}");
        load("a {\n\tb\nc\n}");
        keys("gg=G");
        compare(render(), "a {\n\tb\n\tc\n}");
        // After the listing's prefixes.
        loadListing("M  a(\nC  b\n   )");
        keys("gg=G");
        compare(render(), "<M:h1>  a(\n<C:h2>      b\n   )");
    }

    // ---- Ranges and shell commands -------------------------------------------

    // The line the cursor is on.
    function cursorLine() {
        return Txt.lineOf(editor.text, vim.cursor);
    }

    // The commands :! asked for, as [command, "first-last"] (or null for
    // no range).
    function shellCalls() {
        // "_" after those for the scratchpad's (:_!)
        return shells.signalArguments.map(a => [a[0], a[1] ? a[1].first + "-" + a[1].last : null]
            .concat(a[2] ? ["_"] : []));
    }

    function test_ranges() {
        load("one\ntwo\nthree\nfour\nfive");
        keys(":3<CR>");
        compare(cursorLine(), 3);
        keys(":+<CR>");
        compare(cursorLine(), 4);
        keys(":-2<CR>");
        compare(cursorLine(), 2);
        keys(":.+2<CR>");
        compare(cursorLine(), 4);
        keys(":$-3<CR>");
        compare(cursorLine(), 2);
        keys(":0<CR>");
        compare(cursorLine(), 1);
        keys(":99<CR>");
        compare(cursorLine(), 5);
        keys(":1,3<CR>");
        compare(cursorLine(), 3);
        keys(":%<CR>");
        compare(cursorLine(), 5);
        keys(":2,3set nu<CR>");
        compare(vim.message, "E481: No range allowed");
    }

    function test_shellCommand() {
        load("one\ntwo\nthree\nfour");
        shells.clear();
        vim.lastShell = "";
        keys(":!!<CR>");
        compare(vim.message, "E34: No previous command");
        keys(":!ls -la<CR>");
        keys("j:.,+2!sort<CR>");
        keys(":%!tr a-z A-Z<CR>");
        keys(":!! | wc<CR>");
        keys(":$ !rev<CR>");
        keys(":3,2!rev<CR>");
        compare(shellCalls(), [["ls -la", null], ["sort", "2-4"], ["tr a-z A-Z", "1-4"],
            ["tr a-z A-Z | wc", null], ["rev", "4-4"], ["rev", "2-3"]]);
        keys(":!<CR>");
        compare(vim.message, "E471: Argument required");
        keys(":2,9!sort<CR>");
        compare(vim.message, "E16: Invalid range");
        compare(shells.count, 6);
    }

    // A command that takes no argument, or a ! not before blanks, isn't
    // one; :confirm needs one.
    function test_exCommandNames() {
        load("a");
        editCommands.clear();
        for (const c of ["w foo", "q x", "noh x", "e!foo", "se!", "h:s", "write!"]) {
            keys(":" + c + "<CR>");
            compare(vim.message, "E492: Not an editor command: " + c);
        }
        keys(":confirm<CR>");
        compare(vim.message, "E471: Argument required");
        compare(editCommands.count, 0);
        keys(":e!  x<CR>");
        compare(editCommands.signalArguments.map(a => [a[0], a[1]]), [["x", true]]);
    }

    // :_! is for the scratchpad, with a range too.
    function test_scratchpadCommand() {
        load("one\ntwo\nthree\nfour");
        shells.clear();
        keys(":_!git log<CR>");
        keys(":%_ !sort<CR>");
        keys(":2_!!<CR>");
        keys(":_<CR>");
        compare(vim.message, "E492: Not an editor command: _");
        keys(":_!<CR>");
        compare(vim.message, "E471: Argument required");
        compare(shellCalls(), [["git log", null, "_"], ["sort", "1-4", "_"], ["sort", "2-2", "_"]]);
    }

    // : and ! in visual mode are for its lines, after it.
    function test_visualRange() {
        load("one\ntwo\nthree\nfour");
        shells.clear();
        vim.lastVisual = null;
        // (a < alone, as keys() reads <,'> as a key's name)
        keys(":'");
        keyClick("<");
        keys(",'>!x<CR>");
        compare(vim.message, "E20: Mark not set");
        keys("jVj:");
        compare(vim.commandLine, ":'<,'>");
        compare(vim.mode, "normal");
        keys("!sort<CR>");
        keys("ggvj!");
        compare(vim.commandLine, ":'<,'>!");
        keys("rev<CR>");
        compare(shellCalls(), [["sort", "2-3"], ["rev", "1-2"]]);
    }

    // ! and a motion type the lines' range, as in vim, and change nothing
    // (Koil's ! is one of its keys instead: see main.qml's bangLines), and
    // g! does too, for Koil.
    function test_bangOperator() {
        load("one\ntwo\nthree\nfour");
        keys("j!j");
        compare(vim.commandLine, ":.,.+1!");
        keys("<Esc>!!");
        compare(vim.commandLine, ":.!");
        keys("<Esc>3!!");
        compare(vim.commandLine, ":.,.+2!");
        keys("<Esc>G!k");
        compare(vim.commandLine, ":.,.+1!");
        compare(cursorLine(), 3);
        keys("<Esc>gg");
        keys("g!j");
        compare(vim.commandLine, ":.,.+1!");
        keys("<Esc>g!!");
        compare(vim.commandLine, ":.!");
        keys("<Esc>2g!g!");
        compare(vim.commandLine, ":.,.+1!");
        keys("<Esc>u");
        compare(editor.text, "one\ntwo\nthree\nfour");
        compare(vim.undoStack.length, 0);
    }

    // For Koil's listing and scratchpad, ! in visual mode and on marked
    // lines types a % for their entries, with the cursor before it, and g!
    // types vim's filter.
    function test_bangEntries() {
        load("one\ntwo\nthree");
        vim.bangEntries = true;
        keys("Vj!");
        compare(vim.commandLine, ":'<,'>! %");
        compare(vim.commandCursor, 7);
        keys("ls");
        compare(vim.commandLine, ":'<,'>!ls %");
        keys("<Esc>gvg!");
        compare(vim.commandLine, ":'<,'>!");
        keys("<Esc>ggmjm!");
        compare(vim.commandLine, ":'<,'>! %");
        compare(vim.visualShown.marked, [0, 4]);
        keys("<Esc>ggmjmg!");
        compare(vim.commandLine, ":'<,'>!");
        keys("<Esc>");
        vim.openBang("", true);
        compare(vim.commandLine, ":! %");
        compare(vim.commandCursor, 2);
        keys("<Esc>");
        vim.bangEntries = false;
        keys("Vj!");
        compare(vim.commandLine, ":'<,'>!");
        keys("<Esc>");
    }

    // While vim waits (for a shell command), keys do nothing, but Esc asks
    // to stop it.
    function test_waiting() {
        load("one\ntwo");
        stops.clear();
        vim.waiting = "Running";
        keys("dd");
        compare(editor.text, "one\ntwo");
        keys("<Esc>");
        compare(stops.count, 1);
        vim.endWait(false);
        keys("dd");
        compare(editor.text, "two");
    }

    // A macro waits for a command it runs, and goes on once it's done.
    function test_macroWaits() {
        load("a\nb\nc\nd");
        const wait = () => vim.waiting = "Running";
        vim.shellRequested.connect(wait);
        keys("qq:!x<CR>");
        vim.endWait(false);
        keys("jxq");
        compare(editor.text, "a\n\nc\nd");
        keys("@q");
        verify(vim.running);
        compare(editor.text, "a\n\nc\nd");
        vim.endWait(false);
        verify(!vim.running);
        compare(editor.text, "a\n\n\nd");
        // stopped: not the rest of it
        keys("gg@q");
        vim.endWait(true);
        verify(!vim.running);
        compare(editor.text, "a\n\n\nd");
        compare(vim.message, "Interrupted");
        vim.shellRequested.disconnect(wait);
    }

    // What a command shows as vim's wait ends (:_!'s output, in the
    // scratchpad, after it starts over) is a step of the macro that ran it,
    // which goes on rather than being stopped by it.
    function test_macroWaitsForScratchpad() {
        load("a\nb\nc");
        const wait = () => vim.waiting = "Running";
        const shown = () => {
            editor.text = "old";
            vim.reset([]);
            vim.replaceWhole("p\nq\nr");
        };
        vim.shellRequested.connect(wait);
        keys("qq:_!x<CR>");
        vim.endWait(false, shown);
        keys("jxq");
        compare(editor.text, "p\n\nr");
        keys("@q");
        verify(vim.running);
        vim.endWait(false, shown);
        verify(!vim.running);
        compare(editor.text, "p\n\nr");
        verify(vim.message !== "Interrupted");
        vim.shellRequested.disconnect(wait);
    }

    // The parts of the command line that are colored, as "text:kind".
    function test_commandLineParts() {
        const parts = line => vim.commandLineParts(line).map(p => line.slice(p.start, p.end) + ":" + p.kind);
        compare(parts(":!git add %"), ["!:command", "%:file"]);
        compare(parts(":'<,'>!mv %:p:h \\% x"), ["'<,'>:range", "!:command", "%:p:h:file", "\\%:escape"]);
        compare(parts(":!echo \\\\%"), ["!:command", "%:file"]);
        compare(parts(":'<,'>!cp <cfile>:t % \\<cfile> <cfil"),
            ["'<,'>:range", "!:command", "<cfile>:t:file", "%:file", "\\<cfile>:escape"]);
        compare(parts(":.,+2_!sort"), [".,+2:range", "_!:command"]);
        compare(parts(":!!"), ["!!:command"]);
        compare(parts(":%s/a/b/g"), ["%:range", "s:command"]);
        compare(parts(":&&"), ["&&:command"]);
        compare(parts(":set nowrap fs=14 bogus"), ["set:command", "nowrap:option", "fs:option"]);
        compare(parts(":conf q"), ["conf:command", "q:command"]);
        compare(parts(":e! ~/my dir "), ["e!:command", "~/my dir:file"]);
        compare(parts(":wq"), ["wq:command"]);
        compare(parts(":5"), ["5:range"]);
        compare(parts(":bogus %"), []);
        compare(parts("/a %"), []);
    }

    // A filter's output in place of its lines.
    function test_filterLines() {
        load("one\ntwo\nthree\nfour");
        compare(vim.filterInput(2, 3, null), "two\nthree\n");
        vim.filterLines(2, 3, "TWO\nTHREE\nextra");
        compare(editor.text, "one\nTWO\nTHREE\nextra\nfour");
        compare(cursorLine(), 2);
        keys("u");
        compare(editor.text, "one\ntwo\nthree\nfour");
        // no output: the lines go, as with dd
        vim.filterLines(2, 3, "");
        compare(editor.text, "one\nfour");
        compare(cursorLine(), 2);
        vim.filterLines(2, 2, "");
        compare(editor.text, "one");
        vim.filterLines(1, 1, "");
        compare(editor.text, "");
    }

    // In the listing, a filter takes the lines without their prefixes, and
    // its lines get one each, as new entries.
    function test_filterPrefixes() {
        load("M  b\nC  a\nM  c");
        vim.linePrefixes = true;
        compare(vim.filterInput(1, 2, null), "b\na\n");
        compare(vim.filterInput(1, 3, [1, 3]), "b\nc\n");
        vim.filterLines(1, 2, "a\nb");
        compare(render(), "   a\n   b\n<M:h3>  c");
        compare(vim.cursor, 3);
    }

    // :_!'s output in place of all of the text, as a change of its own.
    function test_replaceWhole() {
        load("one\ntwo\nthree");
        keys("Gl");
        vim.replaceWhole("a\nb");
        compare(editor.text, "a\nb");
        compare(vim.cursor, 0);
        keys("u");
        compare(editor.text, "one\ntwo\nthree");
        keys("<C-r>");
        compare(editor.text, "a\nb");
    }

    // ---- Substitute ------------------------------------------------------

    // :s on the cursor's line or a range, the first match on each line, or
    // all with g, in smart case unless i or I says, as one change, with the
    // cursor on the last line it changed.
    function test_substitute() {
        load("a a\nA a\n  b");
        keys(":s/a/x/<CR>");
        compare(editor.text, "x a\nA a\n  b");
        keys(":%s/a/y/g<CR>");
        compare(editor.text, "x y\ny y\n  b");
        compare(vim.message, "3 substitutions on 2 lines");
        compare(cursorLine(), 2);
        keys("u");
        compare(editor.text, "x a\nA a\n  b");
        keys(":%s/A/z/<CR>");
        compare(editor.text, "x a\nz a\n  b");
        keys("u:%s/A/z/gi<CR>");
        compare(editor.text, "x z\nz z\n  b");
        keys("u:%s/a/z/gI<CR>");
        compare(editor.text, "x z\nA z\n  b");
        keys("u:2,$s/b/c/<CR>");
        compare(editor.text, "x a\nA a\n  c");
        compare(vim.cursor, 10); // the first non-blank
        keys(":1,2s/^/> /<CR>");
        compare(editor.text, "> x a\n> A a\n  c");
        compare(vim.message, "");
        // Patterns are /'s, which they become, and highlight.
        compare(vim.lastSearch.pattern, "^");
        compare(vim.highlightPattern, "^");
    }

    // The replacement: & or \0 the match, \1 its groups, \u \l \U \L \E for
    // case, \r or \n a line break, and \ before anything else makes it itself.
    function test_substituteReplacement() {
        load("foo bar");
        keys(":s/(\\w+) (\\w+)/\\2 \\1 [&]/<CR>");
        compare(editor.text, "bar foo [foo bar]");
        keys(":s/\\w+/\\u&/g<CR>");
        compare(editor.text, "Bar Foo [Foo Bar]");
        keys(":s/bar/\\U\\0\\E!/<CR>");
        compare(editor.text, "BAR! Foo [Foo Bar]");
        keys(":s/foo \\[/\\L&/<CR>");
        compare(editor.text, "BAR! foo [Foo Bar]");
        keys(":s/ /\\&\\/\\\\~/<CR>");
        compare(editor.text, "BAR!&/\\~foo [Foo Bar]");
        keys(":s/ \\[/\\r\\t/<CR>");
        compare(editor.text, "BAR!&/\\~foo\n\tFoo Bar]");
        load("a/b,c");
        keys(":s#/#-#<CR>");
        compare(editor.text, "a-b,c");
        keys(":s/-/\\//<CR>");
        compare(editor.text, "a/b,c");
        keys(":s/\\//+<CR>");
        compare(editor.text, "a+b,c");
        // Without a replacement it deletes, as in vim.
        keys(":s/,");
        compare(editor.text, "a+b,c");
        keys("<CR>");
        compare(editor.text, "a+bc");
    }

    function test_substituteErrors() {
        load("a\nb");
        vim.lastSubstitute = null;
        vim.lastSearch = null;
        keys(":s<CR>");
        compare(vim.message, "E35: No previous regular expression");
        keys(":s//x/<CR>");
        compare(vim.message, "E35: No previous regular expression");
        keys(":s/z/x/<CR>");
        compare(vim.message, "E486: Pattern not found: z");
        keys(":s/z/x/e<CR>");
        compare(vim.message, "");
        keys(":s/a/x/c<CR>");
        compare(vim.message, "E488: Trailing characters: c");
        keys(":3s/a/x/<CR>");
        compare(vim.message, "E16: Invalid range");
        compare(editor.text, "a\nb");
        // Not :s, though it starts with s.
        keys(":set nu<CR>");
        verify(vim.number);
        keys(":set nonu<CR>");
        keys(":sx<CR>");
        compare(vim.message, "E492: Not an editor command: sx");
        // n only counts.
        load("a a\na");
        keys(":%s/a//gn<CR>");
        compare(vim.message, "3 matches on 2 lines");
        compare(editor.text, "a a\na");
    }

    // :&&, & (as Neovim's) and g& run the last one again with its flags,
    // :s alone (with flags of its own) and :& without them (which, as in
    // vim, they then forget), g& on every line with the last search's
    // pattern.
    function test_substituteAgain() {
        load("a a\na a\na a\nb b");
        keys(":s/a/b/g<CR>");
        compare(editor.text, "b b\na a\na a\nb b");
        keys("j&");
        compare(editor.text, "b b\nb b\na a\nb b");
        keys("u:&&<CR>");
        compare(editor.text, "b b\nb b\na a\nb b");
        keys("j:&<CR>");
        compare(editor.text, "b b\nb b\nb a\nb b");
        keys("u:s g<CR>");
        compare(editor.text, "b b\nb b\nb b\nb b");
        keys("u/a a<CR>g&");
        compare(editor.text, "b b\nb b\nb\nb b");
        // An empty pattern is the last search's.
        keys("u/a<CR>:%s//c/g<CR>");
        compare(editor.text, "b b\nb b\nc c\nb b");
    }

    // While a :s is typed, its matches are highlighted, and once its
    // replacement is, the buffer shows what it would make (hidden text and
    // all), which Esc takes back. Enter runs it, as one change.
    function test_substitutePreview() {
        load("a M a\nC a");
        vim.highlightPattern = "";
        const before = render();
        keys(":%s/a");
        compare(render(), before);
        verify(!vim.previewing);
        const shown = () => vim.searchHighlights().map(s => editor.text.slice(s.start, s.end));
        compare(shown(), ["a", "a"]); // the first on each line
        keys("/x");
        compare(render(), "x <M:h1> a\n<C:h2> x");
        verify(vim.previewing);
        compare(shown(), ["x", "x"]);
        keys("/g");
        compare(render(), "x <M:h1> x\n<C:h2> x");
        compare(shown(), ["x", "x", "x"]);
        keys("<BS><BS><BS>y");
        edits.clear();
        keys("y");
        compare(render(), "yy <M:h1> a\n<C:h2> yy");
        verify(edits.count <= 2, edits.count + " edits");
        keys("<Esc>");
        compare(render(), before);
        verify(!vim.previewing);
        compare(vim.substitution, null);
        compare(vim.undoStack.length, 0);
        compare(shown(), []);
        // Backspace back into the pattern shows the matches again.
        keys(":s/a/b<BS><BS>");
        compare(render(), before);
        compare(shown(), ["a"]);
        keys("<Esc>:%s/a/yy/g<CR>");
        compare(render(), "yy <M:h1> yy\n<C:h2> yy");
        verify(!vim.previewing);
        compare(vim.undoStack.length, 1);
        keys("u");
        compare(render(), before);
        keys("<C-r>");
        compare(render(), "yy <M:h1> yy\n<C:h2> yy");
        // n only counts, so it only highlights.
        keys(":%s/yy/z/gn");
        compare(render(), "yy <M:h1> yy\n<C:h2> yy");
        compare(shown(), ["yy", "yy", "yy"]);
        keys("<Esc>");
    }

    // A preview that replaces matches with nothing (or only with line
    // breaks) still shows where they were: an empty span there, which the
    // view draws as a thin line. In :s and the find bar's replace field.
    function test_previewNothing() {
        load("ab a\nb a");
        const spans = () => vim.searchHighlights().map(s => [s.start, s.end]);
        keys(":%s/a/");
        compare(editor.text, "b a\nb ");
        compare(spans(), [[0, 0], [6, 6]]);
        keys("<Esc>:%s/ /\\r");
        compare(editor.text, "ab\na\nb\na");
        compare(spans(), [[2, 2], [6, 6]]);
        keys("<Esc>");
        compare(editor.text, "ab a\nb a");
        load("a b a");
        findBar.open(false); // the word under the cursor: a
        findBar.replacement = "";
        compare(findBar.highlightSpans().map(s => [s.start, s.end]), [[0, 1], [4, 5]]);
        findBar.open(true);
        compare(editor.text, " b ");
        compare(spans(), [[0, 0], [3, 3]]);
        findBar.close();
        compare(editor.text, "a b a");
    }

    // The cursor stays on its character while a preview changes the text
    // before it (or on what replaces its match), and goes back with it.
    function test_substitutePreviewCursor() {
        load("a a\nb x");
        keys("j$");
        const at = vim.cursor;
        keys(":%s/a/AAA/g");
        compare(editor.text, "AAA AAA\nb x");
        compare(editor.text[vim.cursor], "x");
        keys("<BS>");
        compare(editor.text, "AAA a\nb x");
        compare(editor.text[vim.cursor], "x");
        keys("<Esc>");
        compare(vim.cursor, at);
        keys("gg0:s/a/xy/");
        compare(vim.cursor, 0);
        keys("<Esc>");
        // In the listing, it stays out of the icons.
        loadListing("M  ab/\nC  cd/");
        keys("j");
        keys(":%s`../`&a");
        compare(render(), "<M:h1>  ab/a\n<C:h2>  cd/a");
        compare(editor.text[vim.cursor], "c");
        keys("aa");
        compare(render(), "<M:h1>  ab/aaa\n<C:h2>  cd/aaa");
        compare(editor.text[vim.cursor], "c");
        keys("<Esc>");
        compare(editor.text[vim.cursor], "c");
    }

    // Starting over (another listing shown) drops the preview, as the text
    // it replaced isn't there any more.
    function test_substitutePreviewReset() {
        load("a b");
        keys(":s/a/x/");
        compare(editor.text, "x b");
        editor.text = "new";
        vim.reset([]);
        verify(!vim.previewing);
        compare(vim.commandLine, "");
        compare(editor.text, "new");
        // endPreview (main.qml's, before it reads the listing) puts it back.
        load("a b");
        keys(":s/a/x/");
        vim.endPreview();
        compare(editor.text, "a b");
        compare(vim.commandLine, "");
        vim.endPreview();
        compare(editor.text, "a b");
    }

    // :'<,'>s (: in visual mode) keeps to the selection: its characters,
    // its block or its lines.
    function test_substituteVisual() {
        load("aaa aaa aaa\naaa aaa aaa");
        // What : left visual mode with stays selected while the command is
        // typed, as in vim, through the preview too.
        const selected = () => {
            const v = vim.visualShown, r = vim.selectedRange(editor.text, v.mode, v.anchor, v.cursor);
            return editor.text.slice(r.start, r.end);
        };
        keys("wviw:");
        compare(vim.commandLine, ":'<,'>");
        compare(selected(), "aaa");
        keys("s/a/bb/g");
        compare(editor.text, "aaa bbbbbb aaa\naaa aaa aaa");
        compare(selected(), "bbbbbb");
        keys("<BS><BS>");
        compare(editor.text, "aaa bbaa aaa\naaa aaa aaa");
        compare(selected(), "bbaa");
        keys("<BS>/g<CR>");
        compare(editor.text, "aaa bbb aaa\naaa aaa aaa");
        compare(vim.visualShown, null);
        keys("viw:");
        verify(vim.visualShown);
        keys("<Esc>");
        compare(vim.visualShown, null);
        keys("ugg0vjl:s/a/b/g<CR>");
        compare(editor.text, "bbb bbb bbb\nbba aaa aaa");
        keys("ugg0w<C-v>jl:");
        compare(vim.blockSpans(0, editor.text.length, vim.visualShown).map(b => editor.text.slice(b.start, b.end)),
            ["aa", "aa"]);
        keys("s/a/b/g<CR>");
        compare(editor.text, "aaa bba aaa\naaa bba aaa");
        keys("ugg0<C-v>j$:s/a$/b/<CR>");
        compare(editor.text, "aaa aaa aab\naaa aaa aab");
        keys("uggVj:s/a/b/<CR>");
        compare(editor.text, "baa aaa aaa\nbaa aaa aaa");
        // A range typed otherwise is lines, as in vim.
        keys("ugg0wviw<Esc>:1s/a/b/g<CR>");
        compare(editor.text, "bbb bbb bbb\naaa aaa aaa");
    }

    // A macro runs :s as typed (without a preview), as one undo step, and
    // stops where it finds nothing.
    function test_substituteMacro() {
        load("a1\na2\nb3\na4");
        keys("qa:s/a/x/<CR>jq");
        compare(editor.text, "x1\na2\nb3\na4");
        edits.clear();
        keys("@a");
        compare(editor.text, "x1\nx2\nb3\na4");
        verify(edits.count <= 2, edits.count + " edits"); // none for a preview
        verify(!vim.previewing);
        keys("3@a");
        compare(editor.text, "x1\nx2\nb3\na4");
        compare(vim.message, "E486: Pattern not found: a");
        compare(cursorLine(), 3);
        keys("u");
        compare(editor.text, "x1\na2\nb3\na4");
        // @: runs the last one again.
        keys("G:s/a/y/<CR>ggj@:");
        compare(editor.text, "x1\ny2\nb3\ny4");
    }

    // Through the text without the listing's prefixes, as a search: a line
    // starts at its name, and a line a replacement starts gets a prefix.
    function test_substitutePrefixes() {
        loadListing("M  ab\nC  ba\n   b");
        keys(":%s/^b/x/<CR>");
        compare(render(), "<M:h1>  ab\n<C:h2>  xa\n   x");
        keys("gg:s/a/a\\r/<CR>");
        compare(render(), "<M:h1>  a\n   b\n<C:h2>  xa\n   x");
        keys("u:%s/a/\\U&/g");
        compare(render(), "<M:h1>  Ab\n<C:h2>  xA\n   x");
        keys("<Esc>");
        compare(render(), "<M:h1>  ab\n<C:h2>  xa\n   x");
    }

    // The view goes to the match from the cursor on as it's typed, and
    // back when it's cancelled.
    function test_substituteView() {
        const lines = [];
        for (let i = 1; i <= 100; i++)
            lines.push((i === 80 ? "x" : "y") + i);
        narrow.height = 100;
        narrowText.text = lines.join("\n");
        waitForRendering(narrow);
        const f = narrow.contentItem as Flickable;
        const line = n => narrowText.positionToRectangle(Txt.lineToPos(narrowText.text, n));
        vim.lineHeight = line(2).y - line(1).y;
        switchTo(narrowText, {
            cursor: 0
        }, f);
        f.contentY = 0;
        keys(":%s/x");
        const r = line(80);
        verify(f.contentY <= r.y && r.y + r.height <= f.contentY + f.height, "the match is in view");
        keys("/z");
        compare(narrowText.text.split("\n")[79], "z80");
        verify(f.contentY <= r.y && r.y + r.height <= f.contentY + f.height, "the match is in view");
        keys("<Esc>");
        compare(f.contentY, 0);
        compare(narrowText.text.split("\n")[79], "x80");
        // In a long text, only the lines near the view are replaced, and
        // the others are highlighted as they are.
        vim.previewMargin = 10;
        keys(":%s/y/w/");
        const shown = narrowText.text.split("\n");
        compare(shown[0], "w1");
        compare(shown[15], "w16");
        compare(shown[39], "y40");
        const spans = vim.substitution.spans;
        compare(spans.length, 99);
        compare(narrowText.text.slice(spans[0].start, spans[0].end), "w");
        compare(narrowText.text.slice(spans[98].start, spans[98].end), "y");
        keys("<CR>");
        compare(narrowText.text.split("\n").filter(l => l[0] === "w").length, 99);
    }

    function test_setShell() {
        load("a");
        vim.shell = "";
        vim.defaultShell = "";
        vim.systemShell = "/bin/zsh";
        keys(":set sh?<CR>");
        compare(vim.message, "  shell=/bin/zsh");
        keys(":set sh=/bin/bash<CR>");
        compare(vim.shell, "/bin/bash");
        keys(":set shell=C:\\Program\\ Files\\Git\\bin\\bash.exe<CR>");
        compare(vim.shell, "C:\\Program Files\\Git\\bin\\bash.exe");
        keys(":set sh&<CR>");
        compare(vim.shell, "");
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

    // The user's shortcuts run their keys as a macro does, with a count,
    // in the modes they're for.
    function test_shortcuts() {
        load("1\n1\n1\n1");
        vim.commandKeys = { "  ": "apply" };
        vim.shortcuts = [
            { keys: " i", macro: "<C-a>j", label: "Space i", normal: true, visual: false },
            { keys: " u", macro: "U", label: "Space u", normal: false, visual: true }
        ];
        keys(" i");
        compare(editor.text, "2\n1\n1\n1");
        compare(cursorLine(), 2);
        keys("2 i");
        compare(editor.text, "2\n2\n2\n1");
        // a run is one undo step
        keys("u");
        compare(editor.text, "2\n1\n1\n1");
        // not in the other mode: Space u in normal mode is a bad command,
        // and Space i in visual mode still moves
        keys("gg u");
        compare(editor.text, "2\n1\n1\n1");
        compare(vim.pendingKeys, "");
        load("one two\nthree");
        const visual = vim.shortcuts.filter(s => s.visual);
        vim.shortcuts = vim.shortcuts.filter(s => s.normal);
        keys("v ");
        compare(vim.cursor, 1);
        keys("<Esc>");
        vim.shortcuts = vim.shortcuts.concat(visual, [
            { keys: " d", macro: "d", label: "Space d", normal: false, visual: true }
        ]);
        keys("viw u");
        compare(editor.text, "ONE two\nthree");
        compare(vim.mode, "normal");
        keys("wvl d");
        compare(editor.text, "ONE o\nthree");
        // Space then a key no shortcut has, in visual mode
        keys("v x");
        compare(vim.mode, "visual");
        compare(editor.text, "ONE o\nthree");
        keys("<Esc>");
    }

    // Koil's own keys come before a shortcut's, which a macro records as
    // typed, and the registers a shortcut can take its keys from.
    function test_shortcutsAndMacros() {
        load("1\n1\n1");
        vim.commandKeys = { " a": "applyAsking" };
        vim.shortcuts = [
            { keys: " a", macro: "x", label: "Space a", normal: true, visual: false },
            { keys: " i", macro: "<C-a>j", label: "Space i", normal: true, visual: false }
        ];
        keyCommands.clear();
        keys(" a");
        compare(keyCommands.signalArguments.map(a => a[0]), ["applyAsking"]);
        compare(editor.text, "1\n1\n1");
        keys("qq iq");
        compare(editor.text, "2\n1\n1");
        compare(vim.getRegister("q").text, " i");
        keys("@q");
        compare(editor.text, "2\n2\n1");
        keys("\"ayy");
        compare(vim.macroList().map(m => "\"" + m.name + " " + m.keys), ["\"a 1<CR>", "\"q  i", "\"\" 1<CR>"]);
    }

    // Shortcuts and macros that run only each other fail, as vim's
    // recursive mappings do, but one that runs a command and then itself
    // goes on until a command fails.
    function test_recursiveShortcuts() {
        load("1\n1\n1");
        vim.shortcuts = [
            { keys: "s", macro: "ys", label: "s", normal: true, visual: false },
            { keys: "ys", macro: "s", label: "ys", normal: true, visual: false }
        ];
        keys("s");
        compare(vim.message, "E223: recursive mapping");
        compare(vim.running, null);
        compare(vim.typeahead.length, 0);
        compare(editor.text, "1\n1\n1");
        vim.shortcuts = [{ keys: " n", macro: "<C-a>j n", label: "Space n", normal: true, visual: false }];
        keys(" n");
        compare(editor.text, "2\n2\n2");
        compare(vim.running, null);
        compare(vim.message, "");
        // a macro that only runs itself, and one a shortcut runs that runs
        // the shortcut
        keys("qaqqa@aq@a");
        compare(vim.message, "E223: recursive mapping");
        compare(vim.running, null);
        vim.shortcuts = [{ keys: "s", macro: "@b", label: "s", normal: true, visual: false }];
        keys("qbqqbsqs");
        compare(vim.message, "E223: recursive mapping");
        compare(vim.running, null);
        compare(editor.text, "2\n2\n2");
    }

    // A shortcut's keys in parts, the names of keys apart, which Koil
    // colors: only the names macros read as keys.
    function test_keyParts() {
        const parts = text => vim.keyParts(text).map(p => (p.special ? "*" : "") + p.text);
        compare(parts(":!ls <C-r>x<CR><Esc>"), [":!ls ", "*<C-r>", "x", "*<CR>", "*<Esc>"]);
        compare(parts("<cr><Foo><CR"), ["<cr><Foo><CR"]);
        compare(parts("<S-CR><S-CR>"), ["*<S-CR>", "*<S-CR>"]);
        compare(parts(""), []);
    }

    // Koil's list of shortcuts opens with Space q in visual mode too, and
    // runs one (also one with no key) from there: on the selection if it's
    // for visual mode, else in normal mode, which vim goes to first.
    function test_shortcutsFromOutside() {
        load("one two\nthree");
        vim.visualCommandKeys = { " q": "shortcuts" };
        keyCommands.clear();
        keys("viw q");
        compare(keyCommands.signalArguments.map(a => a[0]), ["shortcuts"]);
        compare(vim.mode, "visual");
        vim.runShortcut({ macro: "U", label: "Upper", visual: true });
        compare(editor.text, "ONE two\nthree");
        compare(vim.mode, "normal");
        keys("A!");
        vim.runShortcut({ macro: "ddp", label: "Swap", visual: false });
        compare(editor.text, "three\nONE two!");
        compare(vim.mode, "normal");
        keys("u");
        compare(editor.text, "ONE two!\nthree");
        keys("j0v");
        vim.runShortcut({ macro: "x", label: "x", visual: false });
        compare(editor.text, "ONE two!\nhree");
        compare(vim.mode, "normal");
    }

    // Any keys can be a shortcut's: gc, which vim reads as a bad command,
    // with a count, or keys of vim's, which then wait for the rest of the
    // shortcut's, while vim's other commands with their start still work.
    function test_shortcutKeys() {
        load("1\n1\n1");
        vim.commandKeys = { "g.": "hidden" };
        vim.shortcuts = [
            { keys: "gc", macro: "<C-a>j", label: "gc", normal: true, visual: false },
            { keys: "xa", macro: "<C-a><C-a>", label: "xa", normal: true, visual: false }
        ];
        keys("gc");
        compare(editor.text, "2\n1\n1");
        compare(cursorLine(), 2);
        keys("2gc");
        compare(editor.text, "2\n2\n2");
        keys("ggxa");
        compare(editor.text, "4\n2\n2");
        keys("x");
        compare(vim.pendingKeys, "x");
        keys("l");
        compare(vim.pendingKeys, "");
        compare(editor.text, "4\n2\n2");
        keys("jgg");
        compare(cursorLine(), 1);
        keys("gJ");
        compare(editor.text, "42\n2");
        vim.commandKeys = {};
    }

    // Cmd and a key are keys too on macOS (as MacVim names them), for the
    // user's shortcuts, which a macro records; Cmd+C still copies.
    function test_cmdKeys() {
        if (Qt.platform.os !== "osx")
            skip("Cmd is macOS's");
        load("1\n1");
        vim.shortcuts = [{ keys: "<D-k>", macro: "<C-a>", label: "<D-k>", normal: true, visual: false }];
        keys("<D-k>");
        compare(editor.text, "2\n1");
        // a bad command, like any key vim doesn't know
        keys("d<D-j>");
        compare(vim.pendingKeys, "");
        compare(editor.text, "2\n1");
        keys("qa<D-k>q");
        compare(editor.text, "3\n1");
        compare(vim.getRegister("a").text, "<D-k>");
        keys("@a");
        compare(editor.text, "4\n1");
        compare(vim.macroKeys("<D-k><D-K><D-BS><D-,><D->"), ["<D-k>", "<D-K>", "<D-BS>", "<D-,>", "<", "D", "-",
            ">"]);
        keys("ggV<D-c>");
        compare(clipboard.text, "4\n");
    }

    // A shortcut's keys as Koil shows them: Space as a word.
    function test_keysName() {
        compare(vim.keysName(" gc"), "Space gc");
        compare(vim.keysName("  "), "Space Space");
        compare(vim.keysName("g "), "g Space");
        compare(vim.keysName("<C-k> x"), "<C-k> Space x");
        compare(vim.keysName(""), "");
    }

    // What of vim's own a shortcut's keys take the place of, whatever
    // Koil's and the shortcuts already have.
    function test_vimCommandIn() {
        vim.commandKeys = { "x": "parent" };
        vim.shortcuts = [{ keys: "gc", macro: "x", label: "gc", normal: true, visual: true }];
        compare(vim.vimCommandIn("gc", false), null);
        compare(vim.vimCommandIn("xa", false), { keys: "x", whole: true });
        compare(vim.vimCommandIn("dd", false), { keys: "dd", whole: true });
        compare(vim.vimCommandIn("z", false), { keys: "z", whole: false });
        compare(vim.vimCommandIn("<C-k>", false), null);
        compare(vim.vimCommandIn("U", false), null);
        compare(vim.vimCommandIn("U", true), { keys: "U", whole: true });
        vim.commandKeys = {};
        vim.shortcuts = [];
    }

    // The bracket at the cursor and its match, as vim's matchparen shows
    // them, looked for only in view.
    function test_bracketPair() {
        const t = "f(a[1], {b})\n)";
        compare(Txt.bracketPair(t, 1, false, 0, t.length), [1, 11]);
        compare(Txt.bracketPair(t, 11, false, 0, t.length), [11, 1]);
        compare(Txt.bracketPair(t, 10, false, 0, t.length), [10, 8]);
        // none at it: in insert mode, the one before it
        compare(Txt.bracketPair(t, 2, false, 0, t.length), null);
        compare(Txt.bracketPair(t, 2, true, 0, t.length), [1, 11]);
        compare(Txt.bracketPair("f(x)", 4, true, 0, 4), [3, 1]);
        // unmatched, or matched out of view
        compare(Txt.bracketPair(t, 13, false, 0, t.length), null);
        compare(Txt.bracketPair(t, 1, false, 0, 10), null);
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

    // zl and zh scroll sideways, as far as the room right of the text
    // (Editor.qml's sideScrollRoom), and move the cursor as far as keeps
    // it sidescrolloff columns in view, unless its line ends before the
    // view, which then stays. zL and zH scroll half the view, zs and ze
    // put the cursor at its edges.
    function test_scrollSideways() {
        load("one");
        narrowText.text = "x".repeat(60) + "\nab";
        waitForRendering(narrow);
        const f = narrow.contentItem as Flickable;
        switchTo(narrowText, {
            cursor: 0
        }, f);
        const x = p => narrowText.positionToRectangle(p).x;
        const cw = x(1) - x(0), left = narrowText.leftPadding, right = narrowText.rightPadding;
        vim.charWidth = cw;
        f.rightMargin = 20 * cw;
        keys(":set siso=2<CR>");
        keys("3zl");
        fuzzyCompare(f.contentX, 3 * cw, 0.5);
        compare(vim.cursor, 5);
        // The cursor's line is long enough until the view is past it.
        const max = f.contentWidth + f.rightMargin - f.width;
        keys("100zl");
        fuzzyCompare(f.contentX, max, 0.5);
        verify(f.contentX > f.contentWidth - f.width + 1, "into the room right of the text");
        compare(vim.cursor, 5);
        keys("zh");
        fuzzyCompare(f.contentX, max - cw, 0.5);
        // Moving the cursor shows it again.
        keys("l");
        compare(vim.cursor, 6);
        fuzzyCompare(f.contentX + left, x(4), 0.5);
        keys("zL");
        const half = Math.floor((f.width - left - right) / cw / 2);
        fuzzyCompare(f.contentX + left, x(4) + half * cw, 0.5);
        compare(vim.cursor, 4 + half + 2);
        keys("zH");
        fuzzyCompare(f.contentX + left, x(4), 0.5);
        compare(vim.cursor, 4 + half + 2, "still in view");
        keys("zs");
        fuzzyCompare(f.contentX + left, x(vim.cursor - 2), 0.5);
        keys("ze");
        fuzzyCompare(f.contentX + f.width, x(vim.cursor + 3) + right, 0.5);
        // The cursor right of the view goes left.
        keys("$100zh");
        compare(f.contentX, 0);
        fuzzyCompare(x(vim.cursor + 3) + right, f.width, cw);
        verify(x(vim.cursor + 3) + right <= f.width + 0.5, "the cursor is in view");
        // In visual mode too.
        keys("0v10zl");
        fuzzyCompare(f.contentX, 10 * cw, 0.5);
        compare(vim.mode, "visual");
        compare(vim.cursor, 12);
        keys("<Esc>");
    }

    // From a name's start in the listing, zl keeps scrolling right: the
    // cursor goes past where its room would reach the prefix, which would
    // scroll back to show all of it.
    function test_scrollSidewaysPrefix() {
        load("one");
        narrowText.text = mushroom + "  " + "x".repeat(60);
        waitForRendering(narrow);
        const f = narrow.contentItem as Flickable;
        vim.linePrefixes = true;
        switchTo(narrowText, {
            hidden: [{ at: 0, icon: mushroom, text: "1" }]
        }, f);
        const x = p => narrowText.positionToRectangle(p).x;
        vim.charWidth = x(10) - x(9);
        keys(":set siso=2<CR>");
        keys("0");
        compare(f.contentX, 0);
        let last = 0;
        for (let i = 1; i <= 10; i++) {
            keys("zl");
            verify(f.contentX > last, "zl " + i + " scrolls right");
            last = f.contentX;
        }
    }

    // Makes vim edit the buffer whose lines wrap (see wrapView), with
    // :set wrap, from its line `at` (from 1), where `lines` start with a
    // short one (so the rows' height is the first two lines' distance).
    function loadWrapped(lines, at) {
        load("a");
        wrapText.text = lines.join("\n");
        waitForRendering(wrapView);
        const t = wrapText.text;
        vim.lineHeight = wrapText.positionToRectangle(Txt.lineToPos(t, 2)).y - wrapText.positionToRectangle(0).y;
        vim.charWidth = wrapText.positionToRectangle(1).x - wrapText.positionToRectangle(0).x;
        vim.wrap = true;
        switchTo(wrapText, {
            cursor: Txt.lineToPos(t, at)
        }, wrapView.contentItem as Flickable);
        verify(vim.wrapping);
        return t;
    }

    // While lines wrap, gj and gk go a row (screen line) down or up, to
    // the same place in it, which they keep through shorter ones as j and
    // k do; j and k still go a line. Without wrapping, gj and gk are j and
    // k, but not linewise, as in vim.
    function test_wrapRows() {
        const t = loadWrapped(["x", "one two three four five six seven eight nine ten eleven", "short", "end"], 2);
        const rect = p => wrapText.positionToRectangle(p);
        const lh = vim.lineHeight, line2 = Txt.lineToPos(t, 2), last = Txt.lineEnd(t, line2) - 1;
        verify(rect(last).y >= rect(line2).y + 2 * lh - 0.5, "line 2 wraps on three rows or more");
        keys("w");
        const x0 = rect(vim.cursor).x, y0 = rect(vim.cursor).y;
        keys("gj");
        compare(Txt.lineOf(t, vim.cursor), 2);
        fuzzyCompare(rect(vim.cursor).y, y0 + lh, 0.5);
        fuzzyCompare(rect(vim.cursor).x, x0, vim.charWidth);
        keys("gk");
        compare(vim.cursor, line2 + 4);
        keys("j");
        compare(Txt.lineOf(t, vim.cursor), 3);
        // Through a shorter row and back.
        keys("0fr");
        const r = vim.cursor, line4 = Txt.lineToPos(t, 4);
        keys("gj");
        compare(vim.cursor, line4 + 2);
        keys("gk");
        compare(vim.cursor, r);
        keys("gj2gk");
        fuzzyCompare(rect(vim.cursor).y, rect(last).y, 0.5);
        compare(Txt.lineOf(t, vim.cursor), 2);
        // At the last row, there's nowhere to go.
        keys("G");
        const end = vim.cursor;
        keys("gj");
        compare(vim.cursor, end);
        // After $, to the end of the row.
        keys("2G$gk");
        fuzzyCompare(rect(vim.cursor).y, rect(last).y - lh, 0.5);
        verify(rect(vim.cursor + 1).y > rect(vim.cursor).y, "the row's end");
        // An operator goes to the same place, not linewise.
        keys("0w");
        keys("gj");
        const below = vim.cursor;
        keys("gkdgj");
        compare(wrapText.text, t.slice(0, line2 + 4) + t.slice(below));
        // Not wrapping.
        switchTo(editor, null);
        vim.wrap = false;
        load("abc\ndef");
        keys("lgj");
        compare(vim.cursor, 5);
        keys("gk");
        compare(vim.cursor, 1);
        keys("dgj");
        compare(editor.text, "aef");
    }

    // While lines wrap, Ctrl-E and Ctrl-Y scroll rows, moving the cursor a
    // row at a time to keep it in view, H, M and L go to lines that start
    // and end in view, zt puts the cursor's row at the top, the page keys
    // count rows, and nothing scrolls sideways.
    function test_wrapView() {
        const long = "one two three four five six seven eight nine ten eleven twelve";
        const t = loadWrapped(["x", long, long, long, long, long, long], 1);
        const f = wrapView.contentItem as Flickable;
        const rect = p => wrapText.positionToRectangle(p);
        const lh = vim.lineHeight, top = wrapText.topPadding;
        const rowOf = p => Math.round((rect(p).y - top) / lh);
        f.bottomMargin = f.height - lh - wrapText.bottomPadding;
        keys("2<C-e>");
        fuzzyCompare(f.contentY, 2 * lh, 0.5);
        compare(rowOf(vim.cursor), 2, "the cursor is on the top row in view");
        compare(Txt.lineOf(t, vim.cursor), 2);
        // Line 2 starts above the view, so H goes to line 3.
        keys("H");
        compare(Txt.lineOf(t, vim.cursor), 3);
        keys("L");
        const shown = Math.floor((f.contentY + f.height - top) / lh) - 1;
        verify(rowOf(Txt.lineEnd(t, vim.cursor)) <= shown, "L's line ends in view");
        verify(rowOf(Txt.lineEnd(t, Txt.lineEnd(t, vim.cursor) + 1)) > shown, "and the next one doesn't");
        keys("zt");
        fuzzyCompare(f.contentY, rect(vim.cursor).y - top, 0.5);
        // The row it scrolls to at the top, as without wrapping.
        keys("2<C-y>");
        fuzzyCompare(f.contentY, rect(vim.cursor).y - 2 * lh, 0.5);
        // Ctrl-D scrolls half a page, and the cursor goes as many rows.
        keys("gg<C-d>");
        const half = Math.floor(vim.pageLines / 2);
        fuzzyCompare(f.contentY, half * lh, 0.5);
        compare(rowOf(vim.cursor), half);
        // Ctrl-F leaves the last two rows at the top, the cursor on them.
        keys("gg<C-f>");
        const below = Math.floor((f.height - top) / lh + 0.25);
        fuzzyCompare(f.contentY, (below - 2) * lh, 0.5);
        compare(rowOf(vim.cursor), below - 2);
        const cursor = vim.cursor;
        keys("zl5zl");
        compare(f.contentX, 0);
        compare(vim.cursor, cursor);
        // A buffer of one line doesn't wrap.
        vim.singleLine = true;
        verify(!vim.wrapping);
    }

    function test_setWrap() {
        load("a");
        keys(":set wrap?<CR>");
        compare(vim.message, "nowrap");
        keys(":set wrap<CR>");
        verify(vim.wrap);
        keys(":set nowrap<CR>");
        verify(!vim.wrap);
        vim.defaultWrap = true;
        keys(":set wrap&<CR>");
        verify(vim.wrap);
        vim.defaultWrap = false;
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
        vim.history = { ":": [], "/": [], "<": [] };
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

    // The scratchpad read back from its file, which has the icons alone: the
    // lines that stay keep their hidden text, as one undo step.
    function test_replaceTextKeeping() {
        load("M a\nC b\nM c");
        vim.replaceTextKeeping(mushroom + " a\nx\n" + mushroom + " c\nhi");
        compare(render(), "<M:h1> a\nx\n<M:h3> c\nhi");
        // the same: no change
        vim.replaceTextKeeping(mushroom + " a\nx\n" + mushroom + " c\nhi");
        keys("u");
        compare(render(), "<M:h1> a\n<C:h2> b\n<M:h3> c");
        keys("<C-r>");
        compare(render(), "<M:h1> a\nx\n<M:h3> c\nhi");
        // moved, and the same line twice: the first is the first's
        load("M a\nM a\nM b");
        vim.replaceTextKeeping(mushroom + " b\n" + mushroom + " a\n" + mushroom + " a\n" + mushroom + " a");
        compare(render(), "<M:h3> b\n<M:h1> a\n<M:h2> a\nM a");
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
        keys("G0i<CR>x<Esc>");
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

    // A search sees a line start at its name, so ^ is there, and a match
    // that goes on to the next line goes over its prefix.
    function test_prefixSearchLineStart() {
        loadListing("M  ab\nC  ba\n   b\nplain");
        keys("/^b<CR>");
        compare(vim.positionLabel(), "2:1");
        keys("n");
        compare(vim.positionLabel(), "3:1");
        keys("?^a<CR>");
        compare(vim.positionLabel(), "1:1");
        keys("/b\\nb<CR>");
        compare(vim.positionLabel(), "1:2");
        keys("/^p<CR>");
        compare(vim.positionLabel(), "4:1");
        findBar.open(true);
        findBar.useRegex = true;
        findBar.query = "^b";
        compare(findBar.matches.map(m => editor.text.slice(m.start, m.end)), ["b", "b"]);
        findBar.query = "b\\nb";
        compare(findBar.matches.map(m => editor.text.slice(m.start, m.end)), ["b\n" + chair + "  b"]);
        compare(findBar.highlightSpans().map(s => editor.text.slice(s.start, s.end)), ["b", "b"]);
        findBar.query = "^b";
        findBar.replacement = "x";
        findBar.replaceAll();
        compare(render(), "<M:h1>  ab\n<C:h2>  xa\n   x\nplain");
        // A match that ends with a line break leaves the next prefix, and
        // a line the replacement starts gets one.
        findBar.query = "a\\n";
        findBar.replacement = "a\\ny\\n";
        findBar.replaceAll();
        compare(render(), "<M:h1>  ab\n<C:h2>  xa\n   y\n   x\nplain");
        findBar.useRegex = false;
        findBar.close();
    }

    // ---- Marked lines --------------------------------------------------------

    // m marks the cursor's line (with a count, as many), or unmarks them if
    // they're all marked, and in visual mode, its lines. Esc unmarks them
    // all, and gv marks them again.
    function test_markLines() {
        load("a\nb\nc\nd");
        keys("m");
        compare(vim.marked, [0]);
        keys("jjm");
        compare(vim.marked, [0, 4]);
        compare(vim.modeLabel, "2 MARKED");
        keys("m");
        compare(vim.marked, [0]);
        keys("k2m");
        compare(vim.marked, [0, 2, 4]);
        keys("2m");
        compare(vim.marked, [0]);
        keys("<Esc>");
        compare(vim.marked, []);
        compare(vim.modeLabel, "");
        keys("gv");
        compare(vim.marked, [0]);
        compare(vim.mode, "normal");
        keys("jVjm");
        compare(vim.mode, "normal");
        compare(vim.marked, [0, 4, 6]);
        keys("ggVGm");
        compare(vim.marked, [0, 2, 4, 6]);
        keys("ggVGm");
        compare(vim.marked, []);
        // Not in a buffer of one line.
        vim.singleLine = true;
        load("a");
        keys("m");
        compare(vim.marked, []);
    }

    // d puts the marked lines in its register together, as if they were,
    // and p puts them back so. The cursor stays on its line, or goes to
    // the one after it if that's deleted.
    function test_markedDelete() {
        load("a\nb\nc\nd\ne");
        keys("mjjmj");
        keys("d");
        compare(render(), "b\nd\ne");
        compare(vim.registers["\""].text, "a\nc\n");
        verify(vim.registers["\""].linewise);
        compare(vim.registers["1"].text, "a\nc\n");
        compare(vim.marked, []);
        compare(cursorLine(), 2);
        keys("Gp");
        compare(render(), "b\nd\ne\na\nc");
        keys("uu");
        compare(render(), "a\nb\nc\nd\ne");
        // Where they were, which u brought them back to.
        keys("gv");
        compare(vim.marked, [0, 4]);
        // With the cursor's own, and the last line (with the line break
        // before it).
        keys("Gmx");
        compare(render(), "b\nd");
        compare(vim.registers["\""].text, "a\nc\ne\n");
        compare(cursorLine(), 2);
        compare(vim.message, "3 fewer lines");
    }

    function test_markedYank() {
        load("a\nb\nc");
        keys("mjjm\"ay");
        compare(vim.registers["a"].text, "a\nc\n");
        compare(render(), "a\nb\nc");
        compare(vim.marked, []);
        compare(cursorLine(), 3);
        keys("km\"AY");
        compare(vim.registers["a"].text, "a\nc\nb\n");
    }

    // A yank shows what it took for a moment (vim.yanked), as Neovim's
    // on_yank: yy its line with its line break, a text object its
    // characters, a block its part of each line, marked lines each, at
    // every cursor all. Not a delete, a change, nor a yank into "_, and
    // an edit ends it.
    function test_yankFlash() {
        const yanked = () => JSON.stringify(vim.yanked);
        load("one two\nthree\nfour");
        keys("yy");
        compare(yanked(), JSON.stringify([{ start: 0, end: 8 }]));
        tryCompare(vim, "yanked", null);
        keys("wyiw");
        compare(yanked(), JSON.stringify([{ start: 4, end: 7 }]));
        keys("x");
        compare(vim.yanked, null);
        for (const k of ["dd", "ciw<Esc>", "\"_yy"]) {
            keys(k);
            compare(vim.yanked, null, k);
        }
        load("a\nb\nc\nd");
        keys("Vjy");
        compare(yanked(), JSON.stringify([{ start: 0, end: 4 }]));
        keys("mjjmy");
        compare(yanked(), JSON.stringify([{ start: 0, end: 2 }, { start: 4, end: 6 }]));
        load("abc\ndef\nghi");
        keys("l<C-v>jly");
        compare(yanked(), JSON.stringify([{ start: 1, end: 3 }, { start: 5, end: 7 }]));
        load("ab\ncd\nef");
        vim.toggleCursor(6);
        keys("yl");
        compare(yanked(), JSON.stringify([{ start: 0, end: 1 }, { start: 6, end: 7 }]));
        // Another buffer doesn't show it.
        keys("yy");
        verify(vim.yanked);
        switchTo(other, null);
        compare(vim.yanked, null);
    }

    // A macro's yanks don't show, as Neovim's on_yank doesn't show them,
    // also its last key's, whose frame is gone by then. A shortcut's do.
    function test_yankFlashMacro() {
        load("a\nb");
        keys("qayyq");
        tryCompare(vim, "yanked", null);
        keys("@a");
        compare(vim.yanked, null);
        vim.shortcuts = [{ keys: " y", macro: "yy", label: "Space y", normal: true, visual: false }];
        keys(" y");
        compare(JSON.stringify(vim.yanked), JSON.stringify([{ start: 0, end: 2 }]));
    }

    // c changes them into one line, where the first one was. In the
    // listing, that one keeps its icon (it's renamed).
    function test_markedChange() {
        load("a\nb\nc\nd");
        keys("mjjmcx<Esc>");
        compare(render(), "x\nb\nd");
        compare(vim.registers["\""].text, "a\nc\n");
        keys("u");
        compare(render(), "a\nb\nc\nd");
        loadListing("M  a\nC  b\nM  c");
        keys("mGmSx<Esc>");
        compare(render(), "<M:h1>  x\n<C:h2>  b");
        compare(vim.registers["\""].hidden.map(h => h.text), ["h1", "h3"]);
    }

    // >, case changes and r change each marked line where it is, and gv
    // then marks the same lines.
    function test_markedInPlace() {
        load("a\nb\nc");
        keys("mjjm>");
        compare(render(), "    a\nb\n    c");
        compare(vim.marked, []);
        keys("gvgU");
        compare(render(), "    A\nb\n    C");
        keys("gv~");
        compare(render(), "    a\nb\n    c");
        keys("gvrx");
        compare(render(), "xxxxx\nb\nxxxxx");
        keys("ugv2<");
        compare(render(), "a\nb\nc");
        keys("u");
        compare(render(), "    a\nb\n    c");
    }

    // J joins them to the first one; one line joins the next.
    function test_markedJoin() {
        load("a\nb\n  c\nd");
        keys("mjjmjmJ");
        compare(render(), "a c d\nb");
        compare(vim.cursor, 3);
        keys("ugvgJ");
        compare(render(), "a  cd\nb");
        load("a\nb");
        keys("mJ");
        compare(render(), "a b");
    }

    // p puts the register where the first one was, and the marked lines in
    // the register; P leaves it.
    function test_markedPut() {
        load("a\nb\nc\nd");
        keys("jyykmjjmp");
        compare(render(), "b\nb\nd");
        compare(vim.registers["\""].text, "a\nc\n");
        compare(cursorLine(), 1);
        load("a\nb\nc");
        keys("ylmGmP");
        compare(render(), "a\nb");
        compare(vim.registers["\""].text, "a");
    }

    // I and A type on every marked line, which stay marked while they do.
    function test_markedInsert() {
        load("ab\ncd\nef");
        keys("mGmA!");
        compare(vim.marked, [0, 7]);
        keys("<Esc>");
        compare(render(), "ab!\ncd\nef!");
        compare(vim.marked, []);
        compare(vim.cursors, []);
        keys("gvI-<Esc>");
        compare(render(), "-ab!\ncd\n-ef!");
        keys("u");
        compare(render(), "ab!\ncd\nef!");
        // In the listing, after the prefix.
        loadListing("M  a\nC  b\nM  c");
        keys("mGmgIx<Esc>");
        compare(render(), "<M:h1>  xa\n<C:h2>  b\n<M:h3>  xc");
    }

    // Edits move the marks with their lines: a line deleted is unmarked,
    // and one joined to the line above goes with it.
    function test_marksMove() {
        load("a\nb\nc");
        keys("Gm");
        compare(vim.marked, [4]);
        keys("ggOx<Esc>");
        compare(vim.marked, [6]);
        keys("u");
        compare(vim.marked, [4]);
        keys("ji12<CR><Esc>"); // typed by the editor
        compare(render(), "a\n12\nb\nc");
        compare(vim.marked, [7]);
        load("a\nb");
        keys("Gox<Esc>m");
        compare(vim.marked, [4]);
        keys("u");
        compare(render(), "a\nb");
        compare(vim.marked, []);
        load("a\nb");
        keys("jmi<BS><Esc>");
        compare(render(), "ab");
        compare(vim.marked, [0]);
        // A change within lines keeps each where it is.
        load("aa\naa\naa\naa");
        keys(":%s/a/bb/g<CR>ujmjjmg&");
        compare(render(), "bbbb\nbbbb\nbbbb\nbbbb");
        compare(vim.marked, [5, 15]);
        // As do edits from outside, and u, which marks nothing again.
        load("a\nb\nc");
        keys("Gm");
        vim.mergeEdits([{ start: 0, end: 2, text: "", hidden: [] }], false);
        compare(vim.marked, [2]);
        load("ab\ncd");
        keys("xjm.");
        compare(render(), "b\nd");
        keys("u");
        compare(render(), "b\ncd");
        compare(vim.marked, [2]);
    }

    // : and ! give a command line for the marked lines, '<,'> standing for
    // them, which stay drawn while it's typed.
    function test_markedCommandLine() {
        load("one\ntwo\nthree\nfour");
        shells.clear();
        keys("mjjm:");
        compare(vim.commandLine, ":'<,'>");
        compare(vim.marked, []);
        compare(vim.visualShown.marked, [0, 8]);
        keys("!sort<CR>");
        compare(shells.count, 1);
        const range = shells.signalArguments[0][1];
        compare([range.first, range.last, range.lines], [1, 3, [1, 3]]);
        compare(vim.visualShown, null);
        // ! is vim's operator without Koil's keys, which they take at once.
        keys("gv!");
        compare(vim.commandLine, ":'<,'>!");
        keys("<Esc>");
        // Only '<,'> as a whole is them.
        keys(":'");
        keyClick("<");
        keys(",'>+1!x<CR>");
        compare(shells.signalArguments[1][1].lines, undefined);
        compare(shellCalls()[1], ["x", "1-4"]);
        // :s changes only them.
        load("aa\naa\naa");
        keys("mGm:s/a/bb/g");
        compare(editor.text, "bbbb\naa\nbbbb");
        compare(vim.visualShown.marked, [0, 8]);
        keys("<CR>");
        compare(editor.text, "bbbb\naa\nbbbb");
    }

    // A filter's output goes where the first marked line was, and the
    // others go.
    function test_filterMarked() {
        load("c\nx\na\ny\nb");
        compare(vim.filterInput(1, 5, [1, 3, 5]), "c\na\nb\n");
        vim.filterLines(1, 5, "a\nb\nc", [1, 3, 5]);
        compare(render(), "a\nb\nc\nx\ny");
        load("c\nx\na\ny\nb");
        vim.filterLines(1, 5, "", [1, 3, 5]);
        compare(render(), "x\ny");
    }

    // Each buffer has its own, and the listing's entries are found again
    // by what their icons hide (Koil's IDs).
    function test_markedBuffers() {
        load("a\nb");
        keys("m");
        const left = switchTo(other, null);
        compare(vim.marked, []);
        compare(left.marked, [0]);
        switchTo(editor, left);
        compare(vim.marked, [0]);
        loadListing("M  a\nC  b\nM  c");
        keys("mGm");
        compare(vim.markedTexts(), ["h1", "h3"]);
        vim.markTexts(["h2"]);
        compare(vim.marked, [editor.text.indexOf(chair)]);
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

    // While the replace field has the keys, the buffer shows what Replace
    // All would make of it (hidden text and all), as a :s's preview does,
    // with the replacements highlighted. In the find field, the matches are
    // only highlighted. Whatever the bar does, it does to the text without
    // the preview, which then shows again.
    function test_replacePreview() {
        load("a M a\nC a");
        const before = render();
        const shown = () => (vim.substitution ? vim.searchHighlights() : findBar.highlightSpans())
            .map(s => editor.text.slice(s.start, s.end));
        findBar.open(false); // the word under the cursor: a
        findBar.replacement = "xy";
        compare(render(), before);
        verify(!vim.previewing);
        compare(shown(), ["a", "a", "a"]);
        findBar.open(true); // to the replace field
        verify(findBar.previewShown);
        compare(render(), "xy <M:h1> xy\n<C:h2> xy");
        verify(vim.previewing);
        compare(shown(), ["xy", "xy", "xy"]);
        compare(editor.text[vim.cursor], "x");
        // The matches are the text's, which the bar counts.
        compare(findBar.matches.map(m => m.start), [0, 5, 10]);
        compare(findBar.current, 0);
        edits.clear();
        findBar.replacement = "z";
        compare(render(), "z <M:h1> z\n<C:h2> z");
        verify(edits.count <= 2, edits.count + " edits");
        compare(vim.undoStack.length, 0);
        // The find field (or the editor) has the keys: the text is back.
        editor.forceActiveFocus();
        compare(render(), before);
        verify(!vim.previewing);
        compare(vim.substitution, null);
        compare(vim.cursor, 0);
        compare(shown(), ["a", "a", "a"]);
        // Replace replaces the one at the cursor, and the others show.
        findBar.open(true);
        findBar.replaceOne();
        compare(render(), "z <M:h1> z\n<C:h2> z");
        compare(vim.undoStack.length, 1);
        compare(findBar.matches.map(m => m.start), [5, 10]);
        compare(findBar.current, 0);
        editor.forceActiveFocus();
        compare(render(), "z <M:h1> a\n<C:h2> a");
        // Undo in the field undoes the text's change.
        findBar.open(true);
        findBar.undo(false);
        compare(render(), "z <M:h1> z\n<C:h2> z");
        compare(findBar.matches.length, 3);
        editor.forceActiveFocus();
        compare(render(), before);
        compare(vim.undoStack.length, 0);
        // Put back from outside (main.qml, before it reads the text), it
        // shows again.
        findBar.open(true);
        vim.endPreview();
        compare(render(), before);
        tryVerify(() => vim.previewing);
        compare(render(), "z <M:h1> z\n<C:h2> z");
        // Replace All leaves nothing to preview.
        findBar.replaceAll();
        compare(render(), "z <M:h1> z\n<C:h2> z");
        verify(!vim.previewing);
        compare(vim.undoStack.length, 1);
        vim.nativeUndo(false);
        compare(render(), before);
        // Closed, the text is back.
        findBar.open(true);
        verify(vim.previewing);
        findBar.close();
        compare(render(), before);
        verify(!vim.previewing);
        compare(vim.undoStack.length, 0);
    }

    // With Find in Selection, only the matches in it are replaced, and the
    // selection stays on its characters.
    function test_replacePreviewInSelection() {
        load("a a\na a\na a");
        keys("jVj");
        findBar.open(true);
        compare(findBar.inSelection, true);
        findBar.query = "a";
        findBar.replacement = "bbb";
        findBar.open(true);
        compare(editor.text, "a a\nbbb bbb\nbbb bbb");
        const t = editor.text, scope = vim.findScope;
        compare(t.slice(scope[0].start, scope[scope.length - 1].end), "bbb bbb\nbbb bbb");
        editor.forceActiveFocus();
        compare(editor.text, "a a\na a\na a");
        compare(vim.findScope, [{ start: 4, end: 11 }]);
        findBar.close();
    }

    function test_findInSelection() {
        // Lines: opened with them, it finds only in them.
        load("a a\na a\na a\na a");
        keys("jVj");
        findBar.open(true);
        compare(findBar.inSelection, true);
        compare(vim.findScope, [{ start: 4, end: 11 }]);
        // Typed in the find field, over what it had.
        keyClick("a");
        compare(findBar.query, "a");
        compare(findBar.matches.map(m => m.start), [4, 6, 8, 10]);
        compare(vim.cursor, 4);
        compare(vim.mode, "normal");
        findBar.replacement = "bb";
        findBar.replaceAll();
        compare(editor.text, "a a\nbb bb\nbb bb\na a");
        // Edits move it, and undo takes them back.
        compare(vim.findScope, [{ start: 4, end: 15 }]);
        vim.nativeUndo(false);
        compare(editor.text, "a a\na a\na a\na a");
        compare(vim.findScope, [{ start: 4, end: 11 }]);
        findBar.toggleInSelection();
        compare(findBar.inSelection, false);
        compare(findBar.matches.length, 8);
        // On again: the last selection, which the bar left.
        findBar.toggleInSelection();
        compare(findBar.matches.map(m => m.start), [4, 6, 8, 10]);
        findBar.close();
        compare(vim.findScope, null);

        // Marked lines, which it unmarks, as a command does.
        load("a\na\na\na");
        keys("mjjm");
        findBar.open(false);
        compare(vim.marked, []);
        compare(vim.findScope, [{ start: 0, end: 1 }, { start: 4, end: 5 }]);
        findBar.query = "a";
        compare(findBar.matches.map(m => m.start), [0, 4]);
        findBar.close();

        // A block: its part of each line.
        load("abc\nabc\nabc");
        keys("l<C-v>jl");
        findBar.open(false);
        findBar.query = "[ab]";
        compare(findBar.matches.map(m => m.start), [1, 5]);
        findBar.close();

        // A selection in a line is the query, but can be turned on after.
        load("ab ab\nab");
        keys("vl");
        findBar.open(false);
        compare(findBar.query, "ab");
        compare(findBar.inSelection, false);
        compare(findBar.matches.length, 3);
        findBar.toggleInSelection();
        compare(findBar.matches.map(m => m.start), [0]);
        findBar.close();

        // With nothing selected, it stays off.
        load("ab");
        vim.lastVisual = null;
        findBar.open(false);
        findBar.toggleInSelection();
        compare(findBar.inSelection, false);
        compare(vim.messageIsError, true);
        findBar.close();
    }

    // In the listing, lines selected start at their names, as for a search.
    function test_findInSelectionListing() {
        loadListing("M  a\nC  b\nM  a");
        keys("Vj");
        findBar.open(true);
        findBar.useRegex = true;
        findBar.query = "^a";
        compare(findBar.matches.length, 1);
        findBar.replacement = "xyz";
        findBar.replaceAll();
        compare(render(), "<M:h1>  xyz\n<C:h2>  b\n<M:h3>  a");
        findBar.query = "\\w+";
        compare(findBar.matches.map(m => editor.text.slice(m.start, m.end)), ["xyz", "b"]);
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
        // The replace field has its own. Replace opens with the keys in
        // the find field, as Find does, and Tab goes on to it.
        findBar.open(true);
        findBar.replacement = "3";
        findBar.replaceAll();
        findBar.replacement = "";
        keyClick(Qt.Key_Tab);
        keyClick(Qt.Key_Up);
        compare(findBar.replacement, "3");
        compare(findBar.query, "three");
        findBar.close();
        // Replace while the bar is open goes to the replace field, with
        // its text selected.
        findBar.open(false);
        const query = findBar.query;
        findBar.open(true);
        keyClick("x");
        compare(findBar.replacement, "x");
        compare(findBar.query, query);
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
        compare(help.matches.length, 3);
        compare(help.matchMarks["0/1k"], "0,11,1");
        keys("<Esc><Esc>");
        tryCompare(help, "opened", false);
    }

    // :h goes to a topic's section, and to the row of a key in it, or
    // else to the first row of that key.
    function test_helpTopics() {
        const section = title => help.sections.findIndex(s => s.title === title);
        const row = (title, keys) => help.sections[section(title)].rows.findIndex(r => r[0] === keys);
        const shows = (topic, title, keys) => {
            verify(help.show(topic), topic);
            compare(help.shownSection, section(title), topic);
            compare(help.shownRow, keys ? row(title, keys) : -1, topic);
        };
        shows("", "The listing");
        shows("g", "Keys starting with g");
        shows("Z", "Keys starting with z");
        shows("space", "Keys starting with Space");
        // As typed first, so gI isn't gi, then in any case.
        shows("gI", "Keys starting with g", "`gI`");
        shows("gi", "The listing", "`g.`  `gi`  `gr`");
        shows("gs", "The listing", "`gs`");
        shows("zs", "Keys starting with z", "`zs`  `ze`");
        shows("ZZ", "Keys starting with z", "`ZZ`");
        shows("gS", "Surround", "`S`  `gS`");
        shows("enter", "The listing", "`Enter`");
        // A key no section is for, where it's written.
        shows("J", "Marked lines", "`c`  `p`  `J`");
        shows("Shift+Enter", "The listing", "`Shift+Enter`");
        // Ctrl keys however they're written.
        shows("<C-a>", "Ctrl keys", "`Ctrl-A`  `Ctrl-X`");
        shows("CTRL-D", "Ctrl keys", "`Ctrl-D`  `Ctrl-U`");
        shows("^x", "Ctrl keys", "`Ctrl-A`  `Ctrl-X`");
        verify(!help.show("nothing"));
        help.close();
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

    // The undo history's: the first line highlighted at once, so j moves
    // off it, and a button apart from the choices for the picked lines,
    // which its key clicks, off while none is picked. With it, a line Yes
    // can't do can be picked too, which turns Yes off.
    function test_confirmShowRowAndExtra() {
        let chosen = null, extra = null;
        const lines = [
            { text: "A", needs: [], picked: false },
            { text: "B", needs: [], picked: false },
            { text: "C", needs: [], picked: false, blocked: true }
        ];
        confirm.ask("Undo?", lines, picked => chosen = picked, null, null,
            { showRow: true, extra: { label: "(D)elete History", key: Qt.Key_D, action: picked => extra = picked } });
        tryCompare(confirm, "opened", true);
        verify(confirm.rowShown);
        compare(confirm.picked, [false, false, false]);
        compare(confirm.choices.map(c => c.answer), ["yes", "no"]);
        keyClick(Qt.Key_J);
        compare(confirm.row, 1);
        keyClick(Qt.Key_D);
        compare(extra, null);
        verify(confirm.opened);
        keyClick(Qt.Key_Space);
        keyClick(Qt.Key_J);
        keyClick(Qt.Key_Space);
        compare(confirm.picked, [false, true, true]);
        const [off, on, blocked, blockedOn] = confirm.boxes;
        compare(confirm.list, off + "A\n" + on + "B\n" + blockedOn + "C");
        verify(!confirm.canAnswer("yes"));
        keyClick(Qt.Key_Y);
        compare(chosen, null);
        verify(confirm.opened);
        // a picks only those Yes can do, which turns it on again.
        keyClick(Qt.Key_A);
        compare(confirm.picked, [true, true, false]);
        verify(confirm.canAnswer("yes"));
        keyClick(Qt.Key_Space);
        keyClick(Qt.Key_D);
        compare(extra, [0, 1, 2]);
        compare(chosen, null);
        verify(!confirm.opened);

        // Without them, as before: nor can that line be picked.
        confirm.ask("Undo?", lines, () => {});
        tryCompare(confirm, "opened", true);
        verify(!confirm.rowShown);
        compare(confirm.extra, null);
        confirm.toggle(2);
        compare(confirm.picked, [false, false, false]);
        keyClick(Qt.Key_D);
        verify(confirm.opened);
        confirm.answer("cancel");
    }

    // The words lines start with get the color of the change they stand
    // for, only in the questions that say so.
    function test_confirmKeywords() {
        confirm.ask("Apply?", "MOVE   a -> b", () => {}, null, null, { keywords: { MOVE: "rename", TRASH: "delete" } });
        compare(confirm.keywordColors, ["MOVE", theme.changeColor("rename"), "TRASH", theme.changeColor("delete")]);
        confirm.answer("cancel");
        confirm.ask("Delete it anyway?", "MOVE -> b", () => {});
        compare(confirm.keywordColors, []);
        confirm.answer("cancel");
    }
}
