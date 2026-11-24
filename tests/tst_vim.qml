import QtQuick
import QtQuick.Controls
import QtTest

import "../qml"
import "../qml/text.js" as Txt

// Vim.qml (and the find bar's replace) without the Rust app:
//   QT_QPA_PLATFORM=offscreen qmltestrunner -input tests
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

    // Types keys: characters, and names like <Esc>, <CR>, <F12>, <S-Tab>,
    // <C-v> (Ctrl) or <D-c> (Cmd on macOS, Ctrl elsewhere), named keys
    // with those (<S-CR>, <C-Esc>, <D-S-F12>), and either with more
    // modifiers (<C-K> with Shift, <C-M-k>, <C-D-K>, <C-M-D-S-Left>), and
    // digits and signs with them (<C-1>, <C-/>).
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
            "Home": Qt.Key_Home,
            "End": Qt.Key_End,
            "PageUp": Qt.Key_PageUp,
            "PageDown": Qt.Key_PageDown,
            "Ins": Qt.Key_Insert
        };
        const ctrl = isMac ? Qt.MetaModifier : Qt.ControlModifier;
        for (const m of s.match(/<[^<>]+>|[\s\S]/g)) {
            if (m.length === 1 || m === "<>") {
                keyClick(m);
                continue;
            }
            const name = m.slice(1, -1);
            const k = /^(C-)?(M-)?(D-)?(S-)?(.+)$/.exec(name);
            const mods = k ? (k[1] ? ctrl : 0) | (k[2] ? Qt.AltModifier : 0) | (k[3] ? Qt.ControlModifier : 0)
                | (k[4] ? Qt.ShiftModifier : 0) : 0;
            const key = k && (/^F\d+$/.test(k[5]) ? Qt.Key_F1 + Number(k[5].slice(1)) - 1 : named[k[5]]);
            if (name === "S-Tab")
                keyClick(Qt.Key_Backtab, Qt.ShiftModifier);
            else if (k && (k[1] || k[3]) && /^[a-zA-Z]$/.test(k[5]))
                keyClick(Qt.Key_A + k[5].toLowerCase().charCodeAt(0) - 97,
                    mods | (k[5] < "a" ? Qt.ShiftModifier : 0));
            else if (key !== undefined && key !== null)
                keyClick(key, mods);
            else if (k && (k[1] || k[3]) && /^[!-~]$/.test(k[5]))
                keyClick(k[5].charCodeAt(0), mods);
            else
                fail("unknown key " + m);
        }
    }

    // What System gives for regular expressions (see Vim's regexEngine),
    // made with QML's RegExp: the tests have no System, so its PCRE is
    // tested in ffi/tests.rs, and this the reading of its numbers.
    QtObject {
        id: regexEngine

        // With an empty group at the end, which next drops (see
        // Txt.interpretedRegExp).
        function compiled(pattern, flags) {
            return Txt.interpretedRegExp(pattern, "gm" + flags.replace("l", ""));
        }
        function regexError(pattern, flags) {
            try {
                compiled(pattern, flags);
                return "";
            } catch (e) {
                return e.message;
            }
        }
        function next(re, text, from) {
            if (from > text.length)
                return null;
            re.lastIndex = from;
            const m = re.exec(text);
            if (m)
                m.pop();
            return m;
        }
        function after(m) {
            return m.index + Math.max(1, m[0].length);
        }
        function regexMatches(text, pattern, flags, from, to, limit) {
            const re = compiled(pattern, flags), found = [], perLine = flags.includes("l");
            for (let at = from, n = 0, m; n < limit && (m = next(re, text, at)) !== null && m.index <= to; n++) {
                if (found.length === 0)
                    found.push(2 * m.length);
                // A group's text is where it is, in these tests.
                m.forEach((group, i) => {
                    const start = group === undefined ? -1 : i === 0 ? m.index : text.indexOf(group, m.index);
                    found.push(start, start < 0 ? -1 : start + group.length);
                });
                at = after(m);
                if (perLine) {
                    const nl = text.indexOf("\n", m.index);
                    if (nl < 0)
                        break;
                    at = Math.max(at, nl + 1);
                }
            }
            return new Int32Array(found).buffer;
        }
        function regexBefore(text, pattern, flags, at) {
            const re = compiled(pattern, flags);
            let before = -1, last = -1;
            for (let from = 0, m; (m = next(re, text, from)) !== null; from = after(m)) {
                if (m.index >= at && before >= 0)
                    break;
                last = m.index;
                if (m.index < at)
                    before = m.index;
            }
            return [before, last];
        }
        function regexGroupNames(pattern, flags) {
            const names = [""];
            for (const m of pattern.match(/\\.|\((?!\?)|\(\?<\w+>/g) || []) {
                if (m[0] === "(")
                    names.push(m.slice(3, -1));
            }
            return names;
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
        id: helpRequests

        target: confirm
        signalName: "helpRequested"
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
        id: scratches

        target: vim
        signalName: "scratchRequested"
    }

    SignalSpy {
        id: scratchPuts

        target: vim
        signalName: "scratchPutRequested"
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

    SignalSpy {
        id: saveAsCommands

        target: vim
        signalName: "saveAsRequested"
    }

    SignalSpy {
        id: emptyTrashCommands

        target: vim
        signalName: "emptyTrashRequested"
    }

    SignalSpy {
        id: clipboardWants

        target: vim
        signalName: "clipboardWanted"
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
        vim.regexEngine = null;
        vim.singleLine = false;
        vim.linePrefixes = false;
        vim.bangEntries = "";
        vim.commandKeys = {};
        vim.visualCommandKeys = {};
        vim.ownKeys = [];
        vim.shortcuts = [];
        vim.completer = null;
        vim.wordSources = null;
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

    // With System's regular expressions (see Vim's regexEngine), the
    // search, :s and the find bar read the matches from its numbers.
    function test_regexEngine() {
        vim.regexEngine = regexEngine;
        load("foo bar\nbar foo\nfoo");
        keys("/bar<CR>");
        compare(vim.cursor, 4);
        keys("n");
        compare(vim.cursor, 8);
        keys("n");
        compare(vim.cursor, 4);
        keys("N");
        compare(vim.cursor, 8);
        keys("N");
        compare(vim.cursor, 4);
        keys("?fo+<CR>");
        compare(vim.cursor, 0);
        compare(vim.searchHighlights().map(s => [s.start, s.end]), [[0, 3], [12, 15], [16, 19]]);
        // One that isn't a regular expression is searched for as it is.
        load("a(b a(b");
        keys("/a(<CR>");
        compare(vim.cursor, 4);
        // :s: the groups, one that took no part, the first on each line.
        load("foo bar\nbar foo\nfoo");
        keys(":%s/(\\w+) (\\w+)/\\2 \\1/<CR>");
        compare(editor.text, "bar foo\nfoo bar\nfoo");
        keys(":%s/o/0/<CR>");
        compare(editor.text, "bar f0o\nf0o bar\nf0o");
        keys(":%s/(x)|o/[\\1]/g<CR>");
        compare(editor.text, "bar f0[]\nf0[] bar\nf0[]");
        keys(":2s/^/> /<CR>");
        compare(editor.text, "bar f0[]\n> f0[] bar\nf0[]");
        // In a selection, a line's first match in it.
        load("a a a\na a a");
        keys("l<C-v>j3l:s/a/b/<CR>");
        compare(editor.text, "a b a\na b a");
        // The find bar: a group by its name, whole words, its error.
        load("ab-cd abcd");
        findBar.open(true);
        findBar.useRegex = true;
        findBar.query = "(?<one>\\w+)-(?<two>\\w+)";
        findBar.replacement = "$<two>-$<one>-$1";
        findBar.replaceAll();
        compare(editor.text, "cd-ab-ab abcd");
        findBar.query = "ab";
        findBar.wholeWord = true;
        compare(findBar.matches.map(m => m.start), [3, 6]);
        findBar.wholeWord = false;
        compare(findBar.matches.map(m => m.start), [3, 6, 9]);
        findBar.query = "(ab";
        compare(findBar.matches.length, 0);
        verify(findBar.error !== "");
        findBar.query = "";
        findBar.replacement = "";
        findBar.close();
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

    // gg and NG go to the line's first non-blank, as vim's startofline,
    // and G alone to the text's last character. N%, :N and commands on
    // whole lines (dd, >>, ==, V's d) keep the cursor's column, as
    // Neovim's nostartofline, and j and k keep it after them too.
    function test_noStartOfLine() {
        load("abcdef\n  ab\nabcdef");
        keys("3lG");
        compare(vim.cursor, 17);
        keys("gg");
        compare(vim.cursor, 0);
        keys("3l2G");
        compare(vim.cursor, 9);
        keys("3gg");
        compare(vim.cursor, 12);
        keys("3l2%");
        compare(vim.cursor, 3);
        keys("50%");
        compare(vim.cursor, 10);
        keys(":3<CR>");
        compare(vim.cursor, 15);
        keys("$gg");
        compare(vim.cursor, 0);
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
    // one that runs itself more than that fails, once it ran a thousand
    // times, in chunks (see Batches and runs), more than one if the
    // machine is slow.
    function test_recursiveMacro() {
        load("1\n1\n1");
        keys("qa<C-a>j@aq@a");
        compare(render(), "2\n2\n2");
        compare(vim.running, null);
        load("1");
        keys("qa@a<C-a>q@a");
        tryCompare(vim, "running", null);
        compare(vim.message, "E223: recursive mapping");
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

    // A command at many cursors is one edit where it can be (see
    // Vim.atOnce), and does what it did one cursor at a time: the same
    // text and hidden text, cursors, mode, registers (each cursor's own),
    // message, and one undo step. Edits that overlap, and what it can't
    // do at once, still go one cursor at a time.
    function test_cursorsAtOnce() {
        const run = (spec, at, ks, listing) => {
            if (listing)
                loadListing(spec);
            else
                load(spec);
            vim.setCursor(at[0]);
            for (const p of at.slice(1))
                vim.toggleCursor(p);
            keys(ks);
            const r = { text: render(), cursor: vim.cursor, cursors: vim.cursors.map(c => c.pos), mode: vim.mode,
                registers: JSON.stringify(vim.registers), theirs: JSON.stringify(vim.cursors.map(c => c.registers)),
                message: vim.message };
            keys("<Esc>u");
            r.undone = render();
            return r;
        };
        const same = (spec, at, list, listing) => {
            for (const ks of list) {
                vim.cursorsAtOnce = false;
                const one = run(spec, at, ks, listing);
                vim.cursorsAtOnce = true;
                compare(JSON.stringify(run(spec, at, ks, listing)), JSON.stringify(one), ks + " on " + spec);
            }
        };
        // The main cursor between the others, one on an empty line (where
        // x fails), one at a line's end.
        same("abc Def\nghi\n\nJkl mno", [4, 0, 8, 12, 19],
            ["g~iw", "gUiw", "guiw", "g?iw", "diw", "daw", "dw", "de", "x", "3x", "X", "D", "Cz<Esc>", "sz<Esc>",
                "~", "3~", "rZ", "2rZ", "yiw", "yw", "Y", "\"ayiw", "ciwNEW<Esc>", "cwA<Esc>", "x.", "g~iw.",
                "dd", "x\"ap"]);
        // Two cursors in one word overlap.
        same("abc def", [0, 1], ["diw", "g~iw", "x"]);
        // Commands on lines, a cursor on each of some (lines next to each
        // other touch), the last one too, where dd takes the line break
        // before it.
        const lines = ["dd", "2dd", "3dd", "yy", "3yy", "ccZ<Esc>", "SZ<Esc>", ">>", "<<", "g~~", "dj", "dk",
            "yyp", "yyP", "ddp", "oZ<Esc>", "OZ<Esc>", "2oZ<Esc>", "yiwp", "yiwP", "dd."];
        same("a1\n  b2\nc3\nd4\ne5", [3, 0, 9, 15], lines);
        same("a1\nb2\nc3", [0, 3, 6], lines);
        // But where the lines from a cursor's to the end go, the cursors
        // meet on the line left, where one at a time, the one that went
        // first was left past that line's end (and p and . then acted
        // there too).
        same("a1\nb2\nc3", [3, 6], lines.filter(ks => !ks.startsWith("dd")));
        same("a1\nb2\nc3\n", [3, 6, 9], lines.filter(ks => !ks.startsWith("dd")));
        load("a1\nb2\nc3");
        vim.setCursor(3);
        vim.toggleCursor(6);
        keys("dd");
        compare(editor.text, "a1");
        compare(vim.cursor, 0);
        compare(vim.cursors, []);
        // Two on one line: dd at each, one at a time, takes the next line.
        same("a1 x\nb2\nc3", [0, 3, 8], ["dd", "yy", ">>", "p", "o<Esc>"]);
        // J joins at each, lines next to each other too; <C-a> and <C-x>
        // the number at each (two on one number add twice).
        const joins = ["J", "gJ", "3J", "J.", "<C-a>", "<C-x>", "5<C-a>", "<C-a>."];
        same("a1 (\n  b2\n)c3\n\nd4 0x0f\n  -e5", [0, 6, 12, 15, 25], joins);
        same("a1\nb2\nc3\nd4", [0, 3, 6, 9], joins);
        same("a1 b20\nc3", [0, 4, 5, 7], joins);
        same("Ma1\nCb2\nMc3", [0, 4, 8], joins);
        // Icons, with what they hide.
        same("Mab cd\nCef", [2, 5, 10, 0, 8], ["x", "~", "g~iw", "diw", "yiw", "rZ", "cwX<Esc>"]);
        // gn on every match, as after ga.
        load("a_b x c_d\ne_f");
        keys("/\\w+_\\w+<CR>ga");
        vim.cursorsAtOnce = false;
        keys("g~gn");
        const one = render();
        vim.cursorsAtOnce = true;
        keys("u/\\w+_\\w+<CR>gacgnZ<Esc>");
        compare(render(), "Z x Z\nZ");
        keys("u/\\w+_\\w+<CR>gag~gn");
        compare(render(), one);
        // What it does at once, and what it doesn't.
        const t = editor.text, at = ks => vim.plannedEdit(t, 0, vim.parse(Array.from(ks), false, false).cmd);
        for (const ks of ["g~iw", "dgn", "cw", "x", "D", "~", "rZ", "s", "y$", "dd", "yy", "cc", "S", ">>", "<<",
            "dj", "g~~", "p", "P", "o", "O", "J", "gJ", "3J"])
            verify(at(ks) !== null, ks);
        for (const ks of ["==", "r\n"])
            compare(at(ks), null, ks);
        // The listing: from the names, X at their starts takes the icon.
        same("M  ab cd\nC  ef", [4, 7, 14], ["x", "X", "ciwZ<Esc>", "D", "~", "g~iw", "dw"], true);
    }

    // One cursor at a time, a command runs in chunks, so the window goes
    // on, the status line counts the cursors, and Esc stops it, keeping
    // what it did, as one undo step. One that ends in insert mode runs at
    // once.
    function test_cursorsInChunks() {
        const lines = [];
        for (let i = 0; i < 30; i++)
            lines.push("a" + i);
        const text = lines.join("\n"), all = () => {
            load(text);
            for (let i = 1; i < lines.length; i++)
                vim.toggleCursor(Txt.lineToPos(editor.text, i + 1));
        };
        vim.chunkTime = 0; // a cursor a chunk
        all();
        keys("ysiw)"); // surround, which goes one cursor at a time
        verify(vim.running);
        compare(vim.progress, "30 cursors 3%");
        keys("x"); // nothing, while it runs
        tryCompare(vim, "running", null);
        compare(editor.text, lines.map(l => "(" + l + ")").join("\n"));
        compare(vim.cursors.length, 29);
        keys("u");
        compare(editor.text, text);
        all();
        keys("ysiw)<Esc>");
        compare(vim.running, null);
        compare(vim.message, "Interrupted");
        compare(editor.text, text.slice(0, text.lastIndexOf("\n")) + "\n(a29)"); // the last line, done first
        compare(vim.cursors.length, 29);
        keys("u");
        compare(editor.text, text);
        all();
        keys("A");
        compare(vim.running, null);
        compare(vim.mode, "insert");
        keys("Z<Esc>");
        compare(editor.text, lines.map(l => l + "Z").join("\n"));
    }

    // The selections: the main one's ends, then each extra one's.
    function selections() {
        return [[vim.anchor, vim.cursor]].concat(vim.cursors.map(c => [c.anchor, c.pos]));
    }

    // With extra cursors, v selects at each; motions, text objects, o and
    // gn move every selection's end, and Esc goes back to cursors at their
    // ends. V and Ctrl-V take one cursor.
    function test_multipleSelections() {
        load("abc def\nghi jkl\npqr");
        vim.toggleCursor(8);
        keys("v");
        compare(vim.mode, "visual");
        compare(selections(), [[0, 0], [8, 8]]);
        keys("e");
        compare(selections(), [[0, 2], [8, 10]]);
        keys("o");
        compare(selections(), [[2, 0], [10, 8]]);
        keys("o$");
        compare(selections(), [[0, 7], [8, 15]]); // on the line breaks
        keys("<Esc>");
        compare(vim.mode, "normal");
        compare(vim.cursor, 6);
        compare(vim.cursors.map(c => c.pos), [14]);
        compare(vim.cursors[0].anchor, undefined);
        keys("0viw");
        compare(selections(), [[0, 2], [8, 10]]);
        keys("aw");
        compare(selections(), [[0, 3], [8, 11]]);
        keys("<Esc>gv"); // with the extra ones
        compare(vim.mode, "visual");
        compare(selections(), [[0, 3], [8, 11]]);
        keys("e");
        compare(selections(), [[0, 6], [8, 14]]);
        keys("U");
        compare(editor.text, "ABC DEF\nGHI JKL\npqr");
        compare(vim.mode, "normal");
        compare([vim.cursor].concat(vim.cursors.map(c => c.pos)), [0, 8]);
        compare(vim.cursors[0].anchor, undefined);
        keys("u");
        compare(editor.text, "abc def\nghi jkl\npqr");
        // V and Ctrl-V take one cursor.
        keys("V");
        compare(vim.mode, "normal");
        compare(vim.message, "V works only at one cursor");
        keys("v<C-v>");
        compare(vim.mode, "visual");
        compare(vim.message, "<C-v> works only at one cursor");
        keys("<C-c>");
        compare(vim.mode, "normal");
        compare(vim.cursors.length, 1);
        // m marks the lines of them all, @ runs on them.
        keys("vm");
        compare(vim.marked, [0, 8]);
        compare(vim.cursors, []);
        keys("<Esc>");
        load("a\nb\nc\nd");
        vim.toggleCursor(4);
        vim.registers.q = { text: "Ax", linewise: false, hidden: [] };
        keys("vj@q");
        compare(editor.text, "ax\nbx\ncx\ndx");
        compare(vim.cursors, []);
        // ga in them: the matches in every one.
        load("ab ab ab ab");
        keys("/ab<CR>0");
        vim.toggleCursor(6);
        keys("vlga");
        compare(vim.mode, "normal");
        compare([vim.cursor].concat(vim.cursors.map(c => c.pos)), [6, 0]); // from the cursor on
        // gn: in normal mode, a match at every cursor, in visual mode, on
        // to the next at each.
        keys("gn");
        compare(vim.mode, "visual");
        compare(selections(), [[6, 7], [0, 1]]);
        keys("gn");
        compare(selections(), [[6, 10], [0, 4]]);
        keys("gN");
        compare(selections(), [[6, 9], [0, 3]]);
        // A search typed takes every one's end on, as n.
        load("x1 ab x2 ab");
        vim.toggleCursor(6);
        keys("v/ab<CR>");
        compare(selections(), [[0, 3], [6, 9]]);
        // A tag asked for once, around each.
        load("ab cd");
        vim.toggleCursor(3);
        keys("veS<");
        keys("b>");
        compare(editor.text, "<b>ab</b> <b>cd</b>");
        keys("u");
        compare(editor.text, "ab cd");
        load("ab cd");
        vim.toggleCursor(3);
        keys("veS)");
        compare(editor.text, "(ab) (cd)");
    }

    // gA selects every match of the last search, as ga then gn at each
    // would, the main one the first from the cursor on; then visual
    // mode's commands act on each. In visual mode, only the matches in
    // the selections.
    function test_gA() {
        load("a_b x c_d\ne_f");
        keys("/\\w+_\\w+<CR>gA");
        compare(vim.mode, "visual");
        compare(vim.message, "3 selections");
        compare(selections(), [[6, 8], [0, 2], [10, 12]]);
        compare(vim.highlightPattern, "\\w+_\\w+");
        keys("U");
        compare(editor.text, "A_B x C_D\nE_F");
        compare([vim.cursor].concat(vim.cursors.map(c => c.pos)), [6, 0, 10]);
        // As ga, then gn at each.
        keys("u<Esc>0gA");
        const all = selections();
        keys("<Esc><Esc>0gagn");
        compare(selections(), all);
        keys("<Esc><Esc>ggvjgA");
        compare(vim.message, "2 selections");
        compare(selections(), [[0, 2], [6, 8]]);
        keys("cZ<Esc>");
        compare(editor.text, "Z x Z\ne_f");
        compare(vim.mode, "normal");
        compare(vim.cursors, []);
        keys("u/zz<CR>gA");
        compare(vim.message, "E486: Pattern not found: zz");
        compare(vim.mode, "normal");
        // In the listing, from the names.
        loadListing("M  a_b\nC  c_d");
        keys("/\\w_\\w<CR>gAd");
        compare(render(), "<M:h1>  \n<C:h2>  ");
    }

    // A visual-mode command at many selections is one edit where it can
    // be (see Vim.atOnce), and does what it did one at a time, as at many
    // cursors (see test_cursorsAtOnce).
    function test_selectionsAtOnce() {
        const run = (spec, at, ks, listing) => {
            if (listing)
                loadListing(spec);
            else
                load(spec);
            vim.setCursor(at[0]);
            for (const p of at.slice(1))
                vim.toggleCursor(p);
            keys(ks);
            const r = { text: render(), cursor: vim.cursor, cursors: vim.cursors.map(c => c.pos), mode: vim.mode,
                anchors: vim.cursors.filter(c => c.anchor !== undefined).length,
                registers: JSON.stringify(vim.registers), theirs: JSON.stringify(vim.cursors.map(c => c.registers)),
                message: vim.message };
            keys("<Esc>u");
            r.undone = render();
            return r;
        };
        const same = (spec, at, list, listing) => {
            for (const ks of list) {
                vim.cursorsAtOnce = false;
                const one = run(spec, at, ks, listing);
                vim.cursorsAtOnce = true;
                compare(JSON.stringify(run(spec, at, ks, listing)), JSON.stringify(one), ks + " on " + spec);
            }
        };
        const list = ["ve~", "veU", "veu", "veg?", "veg~", "ved", "vex", "ve<Del>", "vecZ<Esc>", "vesZ<Esc>",
            "vey", "ve\"ay", "veY", "veD", "veX", "veCZ<Esc>", "veRZ<Esc>", "ver*", "ver<CR>", "ve>", "ve3>", "vj>",
            "vjJ", "vjgJ", "vJ", "veIZ<Esc>", "veAZ<Esc>", "vep", "yiwwvep", "yiwwveP", "yyjvep", "ve=", "veS)",
            "vjd", "vjy"];
        // One on an empty line, one at the end; the main one between.
        same("abc Def\n  ghi\n\nJkl mno", [4, 0, 10, 14, 19], list);
        // Selections that overlap go one at a time.
        same("abc def ghi", [0, 1, 8], ["ved", "veU", "vecZ<Esc>"]);
        // On lines next to each other, and the last one.
        same("a1\nb2\nc3", [0, 3, 6], ["vD", "vX", "vY", "vCZ<Esc>", "v>", "vJ", "vlp"]);
        // Icons, with what they hide.
        same("Mab cd\nCef", [2, 5, 10, 0, 8], ["v~", "veU", "ved", "vey", "vr*", "vecX<Esc>", "yiwvep"]);
        // What it does at once, and what it doesn't.
        load("abc def");
        const t = editor.text, at = ks => vim.plannedVisual(t, { anchor: 0, pos: 2 },
            vim.parse(Array.from(ks), true, false).cmd);
        for (const ks of ["d", "c", "y", "x", "s", "X", "D", "C", "R", "Y", "~", "u", "U", "g~", "gu", "gU", "g?", ">",
            "<", "r*", "J", "gJ", "I", "A", "p", "P"])
            verify(at(ks) !== null, ks);
        for (const ks of ["=", "g="])
            compare(at(ks), null, ks);
        // The listing, from the names.
        same("M  ab cd\nC  ef", [4, 7, 14], ["vx", "veU", "vecZ<Esc>", "veIZ<Esc>", "vD", "vep"], true);
    }

    // A search from many cursors (n, N, gn, gN at each) finds what it
    // would from each cursor alone, also going back, where the matches are
    // found once for them all (see Vim.manyBefore), and round the text's
    // ends; so does dgN at each, as one edit or one at a time.
    function test_searchFromManyCursors() {
        const run = (spec, listing, at, search, ks) => {
            if (listing)
                loadListing(spec);
            else
                load(spec);
            keys(search + "<CR>");
            vim.setCursor(at[0]);
            for (const p of at.slice(1))
                vim.toggleCursor(p);
            keys(ks);
        };
        const ends = () => [vim.cursor].concat(vim.cursors.map(c => c.pos)).sort((a, b) => a - b);
        const check = (spec, listing, at, list) => {
            for (const [search, ks] of list) {
                const alone = at.map(p => {
                    run(spec, listing, [p], search, ks);
                    return vim.cursor;
                }).sort((a, b) => a - b).filter((p, i, all) => i === 0 || p !== all[i - 1]);
                run(spec, listing, at, search, ks);
                compare(ends(), alone, search + " " + ks + " on " + spec);
            }
        };
        const list = [["/ab", "N"], ["/ab", "n"], ["/ab", "3N"], ["?ab", "n"], ["?ab", "N"], ["/ab", "gN"],
            ["/ab", "gn"], ["/ab", "vgN"], ["/ab", "vgn"], ["/a\\w|x", "N"], ["/\\n", "N"]];
        check("ab x ab\nzz ab\n\nab", false, [3, 0, 5, 8, 14, 16], list);
        check("ab x ab\nzz ab\n\nab", false, [8, 16, 3], list); // fewer cursors than matches
        check("M  ab x\nC  zz ab\n   ab", true, [4, 6, 13, 22], list);
        for (const [spec, at] of [["ab x ab\nzz ab\n\nab", [3, 0, 8, 14]], ["x ab ab y\nab", [0, 8, 10]]]) {
            vim.cursorsAtOnce = false;
            run(spec, false, at, "/ab", "dgN");
            const one = [render(), vim.cursor, JSON.stringify(vim.cursors.map(c => c.pos))];
            vim.cursorsAtOnce = true;
            run(spec, false, at, "/ab", "dgN");
            compare([render(), vim.cursor, JSON.stringify(vim.cursors.map(c => c.pos))], one, "dgN on " + spec);
        }
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

    // A search reads its pattern with the u flag where it can, as the find
    // bar does: . is a whole emoji, and \u{…} is a code point. One that
    // isn't valid with it (\-) is read without it.
    function test_searchUnicode() {
        load("a😀b x-y ab");
        keys("$/a.b<CR>");
        compare(vim.cursor, 0);
        keys("$/\\u{1F600}<CR>");
        compare(vim.cursor, 1);
        keys("/x\\-y<CR>");
        compare(vim.cursor, 5);
        verify(!vim.messageIsError);
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
    // :sav path (and :sav! path) asks Koil to save what's shown there;
    // :emptytrash to empty the trash.
    function test_saveAsCommand() {
        load("a");
        saveAsCommands.clear();
        keys(":sav ~/new.txt<CR>:saveas! \"a b\"<CR>:sav<CR>");
        compare(saveAsCommands.signalArguments.map(a => [a[0], a[1]]), [["~/new.txt", false], ["\"a b\"", true]]);
        compare(vim.message, "E471: Argument required");
        emptyTrashCommands.clear();
        keys(":emptytrash<CR>:emptyt<CR>");
        compare(emptyTrashCommands.count, 2);
        keys(":emptytrash x<CR>");
        compare(vim.message, "E492: Not an editor command: emptytrash x");
    }

    // In a browser (asyncClipboard), a key that reads the "+ register waits
    // for the browser's clipboard, with those typed after it, then they run
    // with what it gave; Esc drops them, and if it can't be read, Koil's own
    // is used.
    function test_asyncClipboard() {
        load("a");
        vim.asyncClipboard = true;
        try {
            clipboardWants.clear();
            clipboard.text = "old";
            keys("\"+pu");
            compare(clipboardWants.count, 1);
            compare(editor.text, "a");
            compare(vim.message, "Reading the clipboard…");
            vim.clipboardReady("new", "");
            compare(editor.text, "a", "u took the paste back");
            keys("\"*p");
            vim.clipboardReady("new\n", "");
            compare(editor.text, "a\nnew");
            compare(vim.message, "");
            // the browser answers before the command is typed out
            keys("u\"+");
            vim.clipboardReady("early\n", "");
            compare(editor.text, "a");
            keys("p");
            compare(editor.text, "a\nearly");
            compare(vim.freshClipboard, null);
            // Esc ends the command, and what the browser gave with it
            keys("u\"*");
            vim.clipboardReady("late\n", "");
            keys("<Esc>");
            compare(vim.freshClipboard, null);
            compare(clipboardWants.count, 4);
            keys("\"*p");
            vim.clipboardReady("new\n", "");
            compare(editor.text, "a\nnew");
            // what Koil copied, with its data, if the browser has it still
            keys("yy");
            clipboard.text = "copied\n";
            clipboard.data = JSON.stringify({ text: "copied\n", hidden: [], block: false, session: "" });
            keys("\"+P");
            vim.clipboardReady("copied\n", "");
            compare(editor.text, "a\ncopied\nnew");
            // Esc drops them
            keys("\"+p");
            keys("<Esc>");
            compare(vim.message, "Interrupted");
            vim.clipboardReady("late", "");
            compare(editor.text, "a\ncopied\nnew");
            keys("p");
            compare(clipboardWants.count, 7);
            compare(editor.text, "a\ncopied\nnew\nnew", "the \" was dropped too");
            // can't be read: Koil's own
            keys("u\"+p");
            vim.clipboardReady("", "denied");
            compare(editor.text, "a\ncopied\ncopied\nnew");
            compare(vim.message, "Can't read the clipboard: denied");
            // a register's name after " alone, and :reg
            keys("u");
            clipboardWants.clear();
            keys("2+");
            compare(clipboardWants.count, 0);
            keys(":reg<CR>");
            compare(clipboardWants.count, 1);
            vim.clipboardReady("x", "");
            // a macro's keys don't wait
            clipboardWants.clear();
            vim.registers.q = { text: "\"+p", linewise: false, hidden: [] };
            keys("@q");
            compare(clipboardWants.count, 0);
        } finally {
            vim.asyncClipboard = false;
        }
    }

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

    // :normal presses keys as a macro does (in one undo step), and ends
    // what they leave half done; with a range, on each line from its
    // start. Keys are written as a shortcut's.
    function test_normalCommand() {
        load("a\nb\nc");
        keys(":norm Ax<CR>");
        compare(render(), "ax\nb\nc");
        compare(vim.mode, "normal");
        compare(vim.running, null);
        keys("u");
        compare(render(), "a\nb\nc");
        keys(":%norm A;<CR>");
        compare(render(), "a;\nb;\nc;");
        keys(":2,3normal I-<CR>");
        compare(render(), "a;\n-b;\n-c;");
        keys("ggVj:norm! x<CR>");
        compare(render(), ";\nb;\n-c;");
        load("a");
        vim.runCommands(["norm ihi<Esc>x"], "-c");
        compare(render(), "ha");
        keys(":norm<CR>");
        compare(vim.message, "E471: Argument required");
        keys(":2norm x<CR>");
        compare(vim.message, "E16: Invalid range");
        compare(render(), "ha");
    }

    // A long text's line starts, found once, go on through its edits (see
    // Txt.carryLines, which moves those past an edit only once it must):
    // edits line after line, back, far apart, adding and taking away line
    // breaks, before all of them were found, and as many again as lines.
    function test_lineIndexCarried() {
        const lines = [];
        for (let i = 0; i < 3000; i++)
            lines.push("line " + i);
        let t = lines.join("\n"), seed = 7;
        const random = n => {
            seed = (seed * 1103515245 + 12345) % 2147483648;
            return seed % n;
        };
        // What the index should give, counted.
        const lineOf = p => {
            let n = 1;
            for (let i = t.indexOf("\n"); i >= 0 && i < p; i = t.indexOf("\n", i + 1))
                n++;
            return n;
        };
        const lineToPos = line => {
            let p = 0;
            for (let n = 1; n < line; n++) {
                const i = t.indexOf("\n", p);
                if (i < 0)
                    break;
                p = i + 1;
            }
            return p;
        };
        const check = (what, k) => {
            const p = random(t.length + 1), line = 1 + random(lineOf(t.length) + 1);
            compare(Txt.lineOf(t, p), lineOf(p), what + " " + k + ": lineOf " + p);
            compare(Txt.lineToPos(t, line), lineToPos(line), what + " " + k + ": lineToPos " + line);
        };
        const edit = (s, e, text) => {
            const after = t.slice(0, s) + text + t.slice(e);
            Txt.carryLines(t, after, s, e, text);
            t = after;
        };
        Txt.lineOf(t, 300); // found as far as line 50
        for (let k = 0; k < 600; k++) {
            const kind = k % 4;
            let s;
            if (kind === 0) // line after line
                s = Txt.lineToPos(t, 1 + (k >> 2) % 2000) + random(4);
            else if (kind === 1) // back
                s = Txt.lineToPos(t, Math.max(1, 2000 - (k >> 2) * 3));
            else // anywhere
                s = random(t.length);
            const e = Math.min(t.length, s + random(kind === 3 ? 30 : 4));
            edit(s, e, ["", "x", "yz", "\n", "a\nb", "\n\n"][random(6)]);
            check("edit", k);
            if (k % 50 === 0)
                compare(Txt.countLines(t), lineOf(t.length), "countLines " + k);
        }
        // An edit at each line, from the first to the last, as :%norm x.
        for (let line = 1, n = Txt.countLines(t); line <= n; line++) {
            const ls = Txt.lineToPos(t, line);
            if (ls < t.length && t[ls] !== "\n")
                edit(ls, ls + 1, "");
        }
        for (let k = 0; k < 20; k++)
            check("after", k);
    }

    // :normal and a macro on many lines of a long text (where the lines'
    // starts are kept, and the lines left to run on move all at once).
    function test_normalOnLongText() {
        const lines = [];
        for (let i = 0; i < 2000; i++)
            lines.push("a" + i);
        const text = lines.join("\n");
        load(text);
        keys(":%norm Ax<CR>");
        tryCompare(vim, "running", null, 60000);
        compare(editor.text, lines.map(l => l + "x").join("\n"));
        compare(Txt.lineToPos(editor.text, 1500), editor.text.indexOf("a1499x"));
        keys("u");
        compare(editor.text, text);
        // A line joined to the one before goes with it (see Marked lines),
        // so J goes on joining.
        keys(":%norm J<CR>");
        tryCompare(vim, "running", null, 60000);
        compare(editor.text, lines.join(" "));
        compare(Txt.countLines(editor.text), 1);
        keys("u");
        compare(Txt.lineToPos(editor.text, 700), editor.text.indexOf("a699"));
        // Each line copied, in visual mode with a macro.
        vim.registers.q = { text: "yypA!<Esc>", linewise: false, hidden: [] };
        keys("ggVG@q");
        tryCompare(vim, "running", null, 60000);
        compare(Txt.countLines(editor.text), 4000);
        compare(editor.text, lines.map(l => l + "\n" + l + "!").join("\n"));
        compare(Txt.lineOf(editor.text, editor.text.indexOf("a1999!")), 4000);
    }

    // :normal, a macro on lines and :g on many lines of the listing, whose
    // icons' hidden text moves by a shift put off till what reads it (see
    // Vim.hiddenPending): each icon keeps its own, through edits on its
    // line, lines added and taken away, and undo.
    function test_hiddenThroughLongRuns() {
        const n = 300, names = [], spec = [];
        for (let i = 0; i < n; i++) {
            names.push("ab" + i);
            spec.push((i % 2 ? "C" : "M") + "  ab" + i);
        }
        const shown = f => names.map((name, i) => "<" + (i % 2 ? "C" : "M") + ":h" + (i + 1) + ">  " + f(name, i));
        loadListing(spec.join("\n"));
        const all = shown(s => s).join("\n");
        compare(render(), all);
        const each = (ks, want) => {
            keys(ks);
            tryCompare(vim, "running", null, 60000);
            compare(render(), want, ks);
            keys("u");
            compare(render(), all, ks + " undone");
        };
        each(":%norm x<CR>", shown(s => s.slice(1)).join("\n"));
        each(":%norm Afoo<CR>", shown(s => s + "foo").join("\n"));
        each(":%norm $xIZ<CR>", shown(s => "Z" + s.slice(0, -1)).join("\n"));
        each(":%norm yyp<CR>", shown(s => s).map(l => l + "\n" + l).join("\n"));
        each(":g/b1/norm A!<CR>", shown(s => /b1/.test(s) ? s + "!" : s).join("\n"));
        vim.registers.q = { text: "jddk", linewise: false, hidden: [] };
        each("ggVG@q", shown(s => s).filter((l, i) => i % 2 === 0).join("\n"));
        vim.registers.q = { text: "A?<Esc>0x", linewise: false, hidden: [] };
        each("ggVG@q", shown(s => s.slice(1) + "?").join("\n"));
        // Back on the line before (where k fails, on the first, the rest
        // of the keys don't run).
        vim.registers.q = { text: "A!<Esc>kA?<Esc>", linewise: false, hidden: [] };
        each("ggVG@q", shown((s, i) => s + "!" + (i < n - 1 ? "?" : "")).join("\n"));
    }

    // With a !, no shortcut takes :normal's keys, as no mapping takes
    // vim's.
    function test_normalCommandShortcuts() {
        load("ab");
        vim.shortcuts = [{ keys: "x", macro: "A!<Esc>", label: "x", normal: true, visual: false }];
        keys(":norm x<CR>");
        compare(render(), "ab!");
        keys(":norm! 0x<CR>");
        compare(render(), "b!");
        vim.shortcuts = [];
    }

    // -c's commands run in turn, as a macro's: one that fails stops the
    // rest, and so does :normal whose keys fail, but with a range, only on
    // the line they fail on.
    function test_runCommands() {
        load("a\nb");
        vim.runCommands(["s/a/x/", "bogus", "s/x/y/"], "-c");
        compare(render(), "x\nb");
        compare(vim.message, "E492: Not an editor command: bogus");
        compare(vim.running, null);
        keys("u");
        compare(render(), "a\nb");
        vim.runCommands(["norm fzx", "norm Ay"], "-c");
        compare(render(), "a\nb");
        compare(vim.running, null);
        load("a,1\nb\nc,3");
        vim.runCommands(["%norm f,r;", "norm Ay"], "-c");
        compare(render(), "a;1\nb\nc;3y");
        vim.runCommands([], "-c");
        compare(render(), "a;1\nb\nc;3y");
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
        // Nor in a """ string's lines, which stay, nor after a Python
        // string's prefix.
        load("f(\n\"\"\"\n(\n\"\"\",\nf')',\n1)\n");
        keys("gg=G");
        compare(render(), "f(\n    \"\"\"\n(\n\"\"\",\n    f')',\n    1)\n");
        // A // whose line goes on to close a bracket opened before it
        // divides, as syntax.rs has it, rather than hiding the bracket.
        load("f(n // 2)\nb\ng(a, // (\nc)\n");
        keys("gg=G");
        compare(render(), "f(n // 2)\nb\ng(a, // (\n    c)\n");
    }

    // g= reindents by the lines around, not by brackets (see Guessed
    // indent): a line alone or a block's first goes where the line above
    // lets it, and a block keeps its own levels, moved with it.
    function test_guessIndent() {
        // A level deeper after a :, as deep as the line above, and deep
        // enough for the line below.
        load("def f():\n    if x:\n    a()\n            b()\n    c()\n");
        keys("jjg==");
        compare(render(), "def f():\n    if x:\n        a()\n            b()\n    c()\n");
        keys("jg==");
        compare(render(), "def f():\n    if x:\n        a()\n        b()\n    c()\n");
        load("def f():\n    if x:\n        a()\nb()\n    c()\n");
        keys("4Gg==");
        compare(render(), "def f():\n    if x:\n        a()\n    b()\n    c()\n");
        // A block put where it doesn't fit, flat or too deep.
        load("def f():\n    if x:\nif y:\n    a()\nb()\n");
        keys("jjVjjg=");
        compare(render(), "def f():\n    if x:\n        if y:\n            a()\n        b()\n");
        compare(vim.message, "3 lines indented");
        load("def f():\n    a()\n            if y:\n                b()\n            c()\n");
        keys("jjg=2j");
        compare(render(), "def f():\n    a()\n    if y:\n        b()\n    c()\n");
        // What's right stays: a dedent, brackets' lines under what follows
        // the bracket, a closing one as deep as its opener's line.
        const py = "class a:\n    def f(self):\n        if x:\n            a()\n        else:\n            b()\n"
            + "        return {\n            \"k\": [1,\n                  2],\n        }\n\n    def g(self):\n"
            + "        pass\n";
        load(py);
        keys("ggg=G");
        compare(render(), py);
        // Fixed: a line a column off, a dedent between levels, a bracket's
        // line not deeper than it, and a closing one shallower than its
        // opener's line.
        load("def f():\n    a = 1\n     b = 2\n   y = [\n1,\n  ]\nz = f(a,\nb)\n");
        keys("ggg=G");
        compare(render(), "def f():\n    a = 1\n    b = 2\n    y = [\n        1,\n    ]\nz = f(a,\n      b)\n");
        // A docstring moves with its first line, another string's text
        // stays, and a comment's brackets don't count.
        load("def f():\n\"\"\"doc (\n  rest\n\"\"\"\nx = \"\"\"\ntext\n\"\"\"\n# (\nreturn x\n");
        keys("jVGg=");
        compare(render(), "def f():\n    \"\"\"doc (\n      rest\n    \"\"\"\n    x = \"\"\"\ntext\n\"\"\"\n    # (\n"
            + "    return x\n");
        // A list's item's text.
        load("- key: a\n      value: b\n");
        keys("jg==");
        compare(render(), "- key: a\n  value: b\n");
        // . repeats it, u undoes it, and marked lines get it each.
        load("if x:\na()\nif y:\nb()\n");
        keys("jg==");
        compare(render(), "if x:\n    a()\nif y:\nb()\n");
        keys("jj.");
        compare(render(), "if x:\n    a()\nif y:\n    b()\n");
        keys("uu");
        compare(render(), "if x:\na()\nif y:\nb()\n");
        keys("ggjmjjmg=");
        compare(render(), "if x:\n    a()\nif y:\n    b()\n");
        // A line after a : in the block may be as deep as it (YAML's list
        // as its key), and a # comment's brackets don't count.
        load("key:\n- a\n#x(\nb: 1\n");
        keys("ggg=G");
        compare(render(), "key:\n- a\n#x(\nb: 1\n");
        load("def f():\n    x = range(n // 2)\n    y = 1\n");
        keys("ggg=G");
        compare(render(), "def f():\n    x = range(n // 2)\n    y = 1\n");
        // After the listing's prefixes.
        loadListing("M  a:\nC  b");
        keys("jg==");
        compare(render(), "<M:h1>  a:\n<C:h2>      b");
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
        keys(":_x<CR>");
        compare(vim.message, "E492: Not an editor command: _x");
        keys(":_!<CR>");
        compare(vim.message, "E471: Argument required");
        compare(shellCalls(), [["git log", null, "_"], ["sort", "1-4", "_"], ["sort", "2-2", "_"]]);
    }

    // :_ is for Koil to show the scratchpad, and takes nothing.
    function test_scratchpadShown() {
        load("one\ntwo");
        scratches.clear();
        keys(":_<CR>");
        keys(": _ <CR>");
        compare(scratches.count, 2);
        keys(":2_<CR>");
        compare(vim.message, "E481: No range allowed");
        keys(":_ x<CR>");
        compare(vim.message, "E488: Trailing characters: x");
        compare(scratches.count, 2);
    }

    // :_put gives Koil a register as lines, with its hidden text, to put
    // in the scratchpad: the unnamed one, or the one named.
    function test_scratchpadPut() {
        load("Mone\ntwo three");
        scratchPuts.clear();
        const puts = () => scratchPuts.signalArguments.map(a => [a[0], a[1].map(h => h.at + ":" + h.text)]);
        keys(":_put<CR>");
        compare(vim.message, "E353: Nothing in register \"");
        keys("yy:_pu<CR>");
        // Characters go as a line too.
        keys("jw\"ayw:_pu a<CR>");
        keys(":_put \"a<CR>");
        keys(":_pu \"<CR>");
        keys(":_ put \"0<CR>");
        compare(puts(), [[mushroom + "one\n", ["0:h1"]], ["three\n", []], ["three\n", []], ["three\n", []],
            [mushroom + "one\n", ["0:h1"]]]);
        keys(":_pu b<CR>");
        compare(vim.message, "E353: Nothing in register b");
        keys(":_pu ab<CR>");
        compare(vim.message, "E488: Trailing characters: b");
        keys(":2_pu<CR>");
        compare(vim.message, "E481: No range allowed");
        keys(":_putx<CR>");
        compare(vim.message, "E492: Not an editor command: _putx");
        compare(scratchPuts.count, 5);
        compare(editor.text, mushroom + "one\ntwo three");
    }

    // Lines put after the last one, as a change of its own, with the
    // cursor on the last of them; an empty text is only them.
    function test_putAtEnd() {
        load("one\n two");
        vim.putAtEnd(mushroom + "\n  x\n", [{ at: 0, icon: mushroom, text: "id" }]);
        compare(render(), "one\n two\n<M:id>\n  x");
        compare(vim.cursor, editor.text.length - 1);
        keys("u");
        compare(render(), "one\n two");
        keys("<C-r>");
        compare(render(), "one\n two\n<M:id>\n  x");
        load("");
        vim.putAtEnd("a\nb\n", []);
        compare(editor.text, "a\nb");
        compare(vim.cursor, 2);
        // A pasted entry's icon is indentation, as for ^.
        vim.putAtEnd(mushroom + "  x\n", [{ at: 0, icon: mushroom, text: "id" }]);
        compare(render(), "a\nb\n<M:id>  x");
        compare(vim.cursor, editor.text.length - 1);
    }

    // The same in a buffer vim isn't editing, from its text and state.
    function test_putInState() {
        load("Mone\n two");
        keys("lx");
        const t = editor.text, state = vim.leaveBuffer();
        const put = vim.putInState(t, state, mushroom + "\n  x\n", [{ at: 0, icon: mushroom, text: "id" }]);
        // What vim edits meanwhile is left alone.
        compare(render(), "<M:h1>ne\n two");
        editor.text = put.text;
        vim.enterBuffer(put.state);
        compare(render(), "<M:h1>ne\n two\n<M:id>\n  x");
        compare(vim.cursor, editor.text.length - 1);
        keys("u");
        compare(render(), "<M:h1>ne\n two");
        keys("u");
        compare(render(), "<M:h1>one\n two");
        keys("<C-r><C-r>");
        compare(render(), "<M:h1>ne\n two\n<M:id>\n  x");
        // One never shown has no state, and no text.
        const first = vim.putInState("", null, "a\nb\n", []);
        compare(first.text, "a\nb");
        editor.text = first.text;
        vim.enterBuffer(first.state);
        compare(vim.cursor, 2);
        keys("u");
        compare(editor.text, "");
        // A pasted entry's icon is indentation, as for ^.
        const icon = vim.putInState("a", null, " " + mushroom + "  x\n", [{ at: 1, icon: mushroom, text: "id" }]);
        editor.text = icon.text;
        vim.enterBuffer(icon.state);
        compare(render(), "a\n <M:id>  x");
        compare(vim.cursor, editor.text.length - 1);
        // An empty line in an empty text changes nothing.
        compare(vim.putInState("", null, "\n", []), { text: "", state: null });
    }

    // An icon that hides text (an entry pasted in the scratchpad) and the
    // blanks after it are indentation, outside the listing: ^, I, gg, + and
    // yss go to what's after them, but 0 to the icon.
    function test_iconIndent() {
        const icon = mushroom.length;
        load("M  one\n  C  two\nm  three\nM");
        keys("$^");
        compare(vim.cursor, icon + 2);
        keys("0");
        compare(vim.cursor, 0);
        keys("+");
        compare(vim.cursor, editor.text.indexOf("two"));
        keys("2gg");
        compare(vim.cursor, editor.text.indexOf("two"));
        keys("gg");
        compare(vim.cursor, icon + 2);
        // One that hides nothing is a character.
        keys("3G");
        compare(vim.cursor, editor.text.indexOf(mushroom + "  three"));
        // Alone on its line, it has the cursor.
        keys("G^");
        compare(vim.cursor, editor.text.lastIndexOf(mushroom));
        keys("ggIx<Esc>");
        compare(render(), "<M:h1>  xone\n  <C:h2>  two\nM  three\n<M:h3>");
        keys("jyss\"");
        compare(render(), "<M:h1>  xone\n  <C:h2>  \"two\"\nM  three\n<M:h3>");
        // On lines of its own, what's after the icon goes a level deeper
        // than the line's blanks, which the new lines start with (not with
        // a copy of the icon).
        load(" M  one");
        keys("ySSb");
        compare(render(), " <M:h1>  (\n     one\n )");
        // In the listing, the icon is the prefix, as before.
        load("M  one");
        vim.linePrefixes = true;
        keys("$^");
        compare(vim.cursor, icon + 2);
        vim.linePrefixes = false;
    }

    // Word motions take an icon that's indentation as a blank, so they go
    // past it to the name, as ^ does, and as they do a listing's prefix.
    function test_iconWords() {
        load("x y\n  M  one two\nM  three\nMfour\na M b");
        const at = s => editor.text.indexOf(s);
        keys("w");
        compare(vim.cursor, at("y"));
        keys("w");
        compare(vim.cursor, at("one"));
        keys("b");
        compare(vim.cursor, at("y"));
        keys("e");
        compare(vim.cursor, at("one") + 2);
        keys("2w");
        compare(vim.cursor, at("three"));
        keys("ge");
        compare(vim.cursor, at("two") + 2);
        keys("W");
        compare(vim.cursor, at("three"));
        // One with no blank after it too.
        keys("w");
        compare(vim.cursor, at("four"));
        keys("B");
        compare(vim.cursor, at("three"));
        keys("E");
        compare(vim.cursor, at("three") + 4);
        keys("E");
        compare(vim.cursor, at("four") + 3);
        // In a line, it's a character.
        keys("w");
        compare(vim.cursor, at("a"));
        keys("w");
        compare(vim.cursor, at("a") + 2);
        // On it, cw changes it as a blank, up to the name, as dw does.
        load("M  one");
        keys("0cwx<Esc>");
        compare(render(), "xone");
        // An icon that hides nothing is a character.
        load("x\nm  one");
        keys("w");
        compare(vim.cursor, 2);
        // At the text's start, b goes to it, as vim's to its first column.
        load("M  one");
        keys("^b");
        compare(vim.cursor, 0);
        // In the listing, the prefix is the blank, as before.
        load("x\nM  one");
        vim.linePrefixes = true;
        keys("w");
        compare(vim.cursor, at("one"));
        vim.linePrefixes = false;
    }

    // The icons that are indentation, by line, for the scratchpad's
    // colors: not one in a line, nor one that hides nothing.
    function test_indentIcons() {
        load("M  a\n\t C  b\nx M\nm  c\n");
        compare(vim.indentIcons(editor.text).map(i => [i.line, i.hidden.text]), [[0, "h1"], [1, "h2"]]);
        // Of the text and hidden text given.
        compare(vim.indentIcons("a\n" + chair, [{ at: 2, icon: chair, text: "id" }]).map(i => i.line), [1]);
    }

    // p says how many lines it added, if more than two.
    function test_pasteReport() {
        load("a\nb\nc\nd");
        keys("yyp");
        compare(vim.message, "");
        keys("2yyp");
        compare(vim.message, "");
        keys("3yyGp");
        compare(vim.message, "3 more lines");
        keys(":noh<CR>yy2P");
        compare(vim.message, "");
        keys("3P");
        compare(vim.message, "3 more lines");
        // Characters with line breaks in them too.
        load("a\nb\nc\nd\ne");
        keys("vjjjy$p");
        compare(vim.message, "3 more lines");
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
        vim.bangEntries = "%";
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
        vim.openBang("", "%");
        compare(vim.commandLine, ":! %");
        compare(vim.commandCursor, 2);
        keys("<Esc>");
        // In the scratchpad, a <cfile>.
        vim.bangEntries = "<cfile>";
        keys("Vj!");
        compare(vim.commandLine, ":'<,'>! <cfile>");
        compare(vim.commandCursor, 7);
        keys("rm");
        compare(vim.commandLine, ":'<,'>!rm <cfile>");
        keys("<Esc>ggmjm!");
        compare(vim.commandLine, ":'<,'>! <cfile>");
        keys("<Esc>gvg!");
        compare(vim.commandLine, ":'<,'>!");
        keys("<Esc><Esc>");
        vim.bangEntries = "";
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

    // Cmd+V in the command line types the clipboard's text at its cursor,
    // as one line, and a macro recorded meanwhile keeps the text.
    function test_commandLinePaste() {
        load("a b\na b\na b");
        clipboard.text = "x y";
        keys(":s/a/<D-v>");
        compare(vim.commandLine, ":s/a/x y");
        compare(vim.commandCursor, 8);
        keys("<CR>");
        compare(editor.text, "x y b\na b\na b");
        // at the cursor, a yanked line without its line break, and line
        // breaks inside as spaces
        clipboard.text = "one\r\ntwo\n\n";
        keys(":ab<Left><D-v>");
        compare(vim.commandLine, ":aone twob");
        compare(vim.commandCursor, 9);
        keys("<Esc>");
        // nothing to paste
        clipboard.text = "\n";
        keys(":<D-v>");
        compare(vim.commandLine, ":");
        keys("<Esc>");
        // a search too
        clipboard.text = "b";
        keys("gg/<D-v><CR>");
        compare(vim.cursor, 4);
        // a macro keeps what was pasted, not the paste
        clipboard.text = "<CR>\tz";
        keys("jqq:s/a/<D-v><CR>q");
        compare(editor.text, "x y b\n<CR>\tz b\na b");
        clipboard.text = "other";
        keys("j@q");
        compare(editor.text, "x y b\n<CR>\tz b\n<CR>\tz b");
    }

    // The command line has a text field's keys: by words, to its ends,
    // selecting with Shift, copying and cutting, and a macro recorded
    // meanwhile does the same.
    function test_commandLineField() {
        load("a b\na b");
        const word = isMac ? Qt.AltModifier : Qt.ControlModifier;
        const selection = () => [vim.commandSelectionStart, vim.commandSelectionEnd];
        keys(":foo bar.baz");
        keyClick(Qt.Key_Left, word);
        compare(vim.commandCursor, 9);
        keyClick(Qt.Key_Left, word);
        compare(vim.commandCursor, 8);
        keyClick(Qt.Key_Left, word);
        compare(vim.commandCursor, 5);
        keyClick(Qt.Key_Right, word);
        compare(vim.commandCursor, 8);
        verify(!vim.commandSelecting);
        keys("<Home>");
        compare(vim.commandCursor, 1);
        // with Shift it selects, which Copy takes
        keyClick(Qt.Key_Right, word | Qt.ShiftModifier);
        compare(selection(), [1, 4]);
        keys("<D-c>");
        compare(clipboard.text, "foo");
        compare(vim.commandLine, ":foo bar.baz");
        compare(selection(), [1, 4]);
        // what's typed takes its place
        keys("x");
        compare(vim.commandLine, ":x bar.baz");
        compare(vim.commandCursor, 2);
        verify(!vim.commandSelecting);
        // to the end, and Cut
        keyClick(Qt.Key_End, Qt.ShiftModifier);
        compare(selection(), [2, 10]);
        keys("<D-x>");
        compare(vim.commandLine, ":x");
        compare(clipboard.text, " bar.baz");
        // all of it, which a paste takes the place of
        keys("<D-a>");
        compare(selection(), [1, 2]);
        clipboard.text = "new";
        keys("<D-v>");
        compare(vim.commandLine, ":new");
        // an arrow alone goes to the selection's end that way
        keyClick(Qt.Key_Left, Qt.ShiftModifier);
        keyClick(Qt.Key_Left, Qt.ShiftModifier);
        compare(selection(), [2, 4]);
        keys("<Right>");
        compare(vim.commandCursor, 4);
        verify(!vim.commandSelecting);
        keyClick(Qt.Key_Left, Qt.ShiftModifier);
        keyClick(Qt.Key_Left, Qt.ShiftModifier);
        keys("<Left>");
        compare(vim.commandCursor, 2);
        // back over the anchor, nothing is selected
        keyClick(Qt.Key_Right, Qt.ShiftModifier);
        keyClick(Qt.Key_Left, Qt.ShiftModifier);
        verify(!vim.commandSelecting);
        // a word deleted, back and on, and a selection by Backspace
        keys("<Esc>:one two");
        keyClick(Qt.Key_Backspace, word);
        compare(vim.commandLine, ":one ");
        keys("<Home>");
        keyClick(Qt.Key_Delete, word);
        compare(vim.commandLine, ": ");
        keys("ab");
        keyClick(Qt.Key_Left, Qt.ShiftModifier);
        keyClick(Qt.Key_Left, Qt.ShiftModifier);
        keys("<BS>");
        compare(vim.commandLine, ": ");
        compare(vim.commandCursor, 1);
        // vim's keys end a selection, and so does closing it
        keys("abc");
        keyClick(Qt.Key_Left, Qt.ShiftModifier);
        keys("<C-b>");
        verify(!vim.commandSelecting);
        compare(vim.commandLine, ":abc ");
        keyClick(Qt.Key_End, Qt.ShiftModifier);
        keys("<Esc>");
        compare(vim.commandLine, "");
        compare(vim.commandAnchor, -1);
        // the pointer: a press, a drag (or Shift), and a double click
        keys(":hello world");
        vim.commandLineWord(8);
        compare(selection(), [7, 12]);
        vim.commandLineClick(3, false);
        compare(vim.commandCursor, 3);
        verify(!vim.commandSelecting);
        vim.commandLineClick(6, true);
        compare(selection(), [3, 6]);
        vim.commandLineClick(1, true);
        compare(selection(), [1, 3]);
        keys("<Esc>");
        // a macro runs the same, with nothing selected
        keys("qq:s/a/xyz");
        keyClick(Qt.Key_Left, word | Qt.ShiftModifier);
        compare(selection(), [5, 8]);
        keys("Q<CR>q");
        compare(editor.text, "Q b\na b");
        keys("j@q");
        compare(editor.text, "Q b\nQ b");
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
        compare(parts(":_"), ["_:command"]);
        compare(parts(":_ put a"), ["_ put:command"]);
        compare(parts(":_pu"), ["_pu:command"]);
        compare(parts(":_p"), []);
        compare(parts(":_putx"), []);
        compare(parts(":!!"), ["!!:command"]);
        compare(parts(":%s/a/b/g"), ["%:range", "s:command"]);
        compare(parts(":&&"), ["&&:command"]);
        compare(parts(":set nowrap fs=14 bogus"), ["set:command", "nowrap:option", "fs:option"]);
        compare(parts(":conf q"), ["conf:command", "q:command"]);
        compare(parts(":e! ~/my dir "), ["e!:command", "~/my dir:file"]);
        compare(parts(":wq"), ["wq:command"]);
        compare(parts(":conf apply"), ["conf:command", "apply:command"]);
        compare(parts(":undolist"), ["undolist:command"]);
        compare(parts(":undo"), []);
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
        // Patterns are /'s, which they become, but don't highlight after,
        // as they may match what replaced them; n's do, as a search's.
        compare(vim.lastSearch.pattern, "^");
        compare(vim.highlightPattern, "");
        load("ss;");
        keys("/s<CR>");
        compare(vim.highlightPattern, "s");
        keys(":s/s(?=;)//<CR>");
        compare(editor.text, "s;");
        compare(vim.lastSearch.pattern, "s(?=;)");
        compare(vim.highlightPattern, "");
        compare(vim.searchHighlights(), []);
        keys(":s/s//n<CR>");
        compare(vim.message, "1 match on 1 line");
        compare(vim.highlightPattern, "s");
        keys("n");
        compare(vim.highlightPattern, "s");
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
        keys(":s/a/x/p<CR>");
        compare(vim.message, "E488: Trailing characters: p");
        keys(":s/a/x/g 0<CR>");
        compare(vim.message, "E939: Positive count required");
        keys(":3s/a/x/<CR>");
        compare(vim.message, "E16: Invalid range");
        compare(editor.text, "a\nb");
        // Not :s, though it starts with s.
        keys(":set nu<CR>");
        verify(vim.number);
        keys(":set nonu<CR>");
        keys(":sx<CR>");
        compare(vim.message, "E492: Not an editor command: sx");
        keys(":sil<CR>");
        compare(vim.message, "E492: Not an editor command: sil");
        keys(":sgx<CR>");
        compare(vim.message, "E488: Trailing characters: gx");
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

    // :sg is :s g, as in vim, and :~ (and r) take the last search's
    // pattern, where :& takes the last :s's. r isn't kept with the flags.
    function test_substituteFlags() {
        load("a b a\na b a");
        keys(":s/a/x/<CR>");
        compare(editor.text, "x b a\na b a");
        keys("j:sg<CR>");
        compare(editor.text, "x b a\nx b x");
        keys("u:sgI<CR>");
        compare(editor.text, "x b a\nx b x");
        // :& takes the last :s's pattern, :~, :&r and :sr the last search's
        // (which a :s's then is).
        keys("u/b<CR>2G:~<CR>");
        compare(editor.text, "x b a\na x a");
        compare(vim.lastSubstitute.pattern, "b");
        keys("u/a<CR>2G:&<CR>");
        compare(editor.text, "x b a\na x a");
        keys("u/a<CR>2G:&r<CR>");
        compare(editor.text, "x b a\nx b a");
        keys("u/b<CR>2G:sr<CR>");
        compare(editor.text, "x b a\na x a");
        // r only picks the pattern: it isn't kept with the flags.
        keys("u:s/b/y/gr<CR>");
        compare(editor.text, "x b a\na y a");
        compare(vim.lastSubstitute.flags, "g");
        // Colored as :s.
        const parts = line => vim.commandLineParts(line).map(p => line.slice(p.start, p.end) + ":" + p.kind);
        compare(parts(":sgi"), ["sgi:command"]);
        compare(parts(":%~&"), ["%:range", "~:command"]);
        compare(parts(":sil"), []);
    }

    // :g marks the lines a match starts on (:v and :g! the others), in its
    // range or on every line. Its pattern becomes the last search's.
    function test_global() {
        load("a1\nb\na2\nc\na3");
        keys(":g/a/<CR>");
        compare(vim.marked, [0, 5, 10]);
        compare(vim.message, "3 lines marked");
        compare(vim.lastSearch.pattern, "a");
        compare(vim.highlightPattern, "");
        keys("d");
        compare(editor.text, "b\nc");
        keys("u:v/a/<CR>");
        compare(vim.marked, [3, 8]);
        keys("<Esc>:g!/a/<CR>");
        compare(vim.marked, [3, 8]);
        keys("<Esc>:2,4g/a/<CR>");
        compare(vim.marked, [5]);
        compare(vim.message, "1 line marked");
        keys("<Esc>:g/z/<CR>");
        compare(vim.message, "Pattern not found: z");
        verify(!vim.messageIsError);
        compare(vim.marked, []);
        keys(":v/./<CR>");
        compare(vim.message, "Pattern found in every line: .");
        // '<,'> after lines were marked is those lines.
        load("a1\nb1\na2");
        keys(":g/a/<CR>:");
        compare(vim.commandLine, ":'<,'>");
        keys("g/1/d<CR>");
        compare(editor.text, "b1\na2");
        // Errors.
        keys(":g<CR>");
        compare(vim.message, "E148: Regular expression missing from :global");
        keys(":g a<CR>");
        compare(vim.message, "E146: Regular expressions can't be delimited by letters");
        keys(":gx<CR>");
        compare(vim.message, "E492: Not an editor command: gx");
        keys(":9g/a/<CR>");
        compare(vim.message, "E16: Invalid range");
        // Colored, with the command it runs.
        const parts = line => vim.commandLineParts(line).map(p => line.slice(p.start, p.end) + ":" + p.kind);
        compare(parts(":%g/a/s/b/c/"), ["%:range", "g:command", "s:command"]);
        compare(parts(":v/a/ .,+1d"), ["v:command", ".,+1:range", "d:command"]);
        compare(parts(":g!"), ["g!:command"]);
        compare(parts(":global#a#norm x"), ["global:command", "norm:command"]);
        // In the listing, from a line's name.
        loadListing("M  ab\nC  ba");
        keys(":g/^b/<CR>");
        compare(vim.marked, [editor.text.indexOf("\n") + 1]);
    }

    // :g with a command runs it on each line, from the first, as one
    // change: a line it takes away is left out, the others move with the
    // edits. Its :s's are counted together once it's done, and one that
    // finds nothing is no error. The command isn't in the history.
    function test_globalCommand() {
        load("a1\nb\na2\nc\na3");
        keys(":g/a/d<CR>");
        compare(editor.text, "b\nc");
        compare(vim.running, null);
        compare(vim.message, "3 fewer lines");
        keys("u");
        compare(editor.text, "a1\nb\na2\nc\na3");
        keys(":v/a/s/$/!/<CR>");
        compare(editor.text, "a1\nb!\na2\nc!\na3");
        keys("u:g/a/norm A;<CR>");
        compare(editor.text, "a1;\nb\na2;\nc\na3;");
        const commands = vim.history[":"];
        compare(commands[commands.length - 1], "g/a/norm A;");
        keys("u");
        compare(editor.text, "a1\nb\na2\nc\na3");
        load("x\nx\n1\nx\n2\n3");
        keys(":g/x/.,+1d<CR>");
        compare(editor.text, "1\n3");
        compare(vim.message, "4 fewer lines");
        load("ab\nb\nab\nab");
        keys(":g/b/s/a/x/<CR>");
        compare(editor.text, "xb\nb\nxb\nxb");
        compare(vim.message, "3 substitutions on 3 lines");
        keys("u:g/b/s/a//n<CR>");
        compare(vim.message, "3 matches on 3 lines");
        compare(editor.text, "ab\nb\nab\nab");
        keys(":g/b/s/a/x/c<CR>");
        verify(vim.message.startsWith("Can't ask in :g"));
        compare(editor.text, "ab\nb\nab\nab");
        // An empty pattern is the last search's; any punctuation can stand
        // for /; a :g in a :g is an error.
        keys("/^b<CR>:g##d<CR>");
        compare(editor.text, "ab\nab\nab");
        keys(":g/a/g/b/d<CR>");
        compare(vim.message, "E147: Cannot do :global recursive");
        compare(editor.text, "ab\nab\nab");
    }

    // :d deletes the cursor's line, a range's, or `count` from its last,
    // into a register, as one change, the cursor on the line after them.
    function test_deleteCommand() {
        load("1\n2\n3\n4\n5\n6");
        keys("j:d<CR>");
        compare(editor.text, "1\n3\n4\n5\n6");
        compare(vim.registers["\""].text, "2\n");
        compare(vim.registers["\""].linewise, true);
        compare(cursorLine(), 2);
        keys("u:3,4d a<CR>");
        compare(editor.text, "1\n2\n5\n6");
        compare(vim.registers["a"].text, "3\n4\n");
        compare(cursorLine(), 3);
        keys(":1d 2<CR>");
        compare(editor.text, "5\n6");
        keys("u:$d<CR>");
        compare(editor.text, "1\n2\n5");
        compare(cursorLine(), 3);
        keys(":%de<CR>");
        compare(editor.text, "");
        compare(vim.message, "3 fewer lines");
        keys("u:d 0<CR>");
        compare(vim.message, "E939: Positive count required");
        keys(":d a b<CR>");
        compare(vim.message, "E488: Trailing characters: a b");
        keys(":9d<CR>");
        compare(vim.message, "E16: Invalid range");
        compare(editor.text, "1\n2\n5");
        // '<,'> after lines were marked is those lines.
        keys("ggmGm:");
        keys("d<CR>");
        compare(editor.text, "2");
    }

    // gn selects the match of the last search the cursor is on, or else
    // the next one, and in visual mode goes on to the end of the next one;
    // after an operator it acts on it, and . on the next one. gN goes back.
    function test_gn() {
        load("foo bar foo baz foo");
        keys("/foo<CR>");
        compare(vim.cursor, 8);
        keys("0gn");
        compare(vim.mode, "visual");
        compare([vim.anchor, vim.cursor], [0, 2]);
        compare(vim.highlightPattern, "foo");
        keys("gn");
        compare([vim.anchor, vim.cursor], [0, 10]);
        keys("gN");
        compare(vim.cursor, 8);
        keys("<Esc>0cgnX<Esc>");
        compare(editor.text, "X bar foo baz foo");
        keys(".");
        compare(editor.text, "X bar X baz foo");
        keys("$gN");
        compare([vim.anchor, vim.cursor], [12, 14]);
        keys("<Esc>0dgN"); // round from the start to the last one
        compare(editor.text, "X bar X baz ");
        keys("u");
        compare(editor.text, "X bar X baz foo");
        load("a_b c_d");
        keys("/\\w+_\\w+<CR>g~gn");
        compare(editor.text, "a_b C_D");
        keys("0gUgn");
        compare(editor.text, "A_B C_D");
        keys("/zz<CR>dgn");
        compare(vim.message, "E486: Pattern not found: zz");
        vim.lastSearch = null;
        keys("gn");
        compare(vim.message, "E35: No previous regular expression");
        compare(vim.mode, "normal");
        compare(editor.text, "A_B C_D");
    }

    // ga puts a cursor at every match of the last search, the main one at
    // the first from the cursor on; then keys act at each. In visual mode
    // and on marked lines, only the matches in them.
    function test_ga() {
        load("a_b x c_d\ne_f");
        keys("/\\w+_\\w+<CR>");
        compare(vim.cursor, 6);
        keys("ga");
        compare(vim.message, "3 cursors");
        compare(vim.cursor, 6);
        compare(vim.cursors.map(c => c.pos), [0, 10]);
        compare(vim.highlightPattern, "\\w+_\\w+");
        keys("g~gn");
        compare(editor.text, "A_B x C_D\nE_F");
        keys("u");
        compare(editor.text, "a_b x c_d\ne_f");
        keys("<Esc>");
        compare(vim.cursors, []);
        keys("ggvjga");
        compare(vim.mode, "normal");
        compare(vim.message, "2 cursors");
        compare([vim.cursor].concat(vim.cursors.map(c => c.pos)), [0, 6]);
        keys("<Esc>Gmga");
        compare(vim.message, "1 cursor");
        compare(vim.cursor, 10);
        compare(vim.cursors, []);
        compare(vim.marked, []);
        keys("/zz<CR>ga");
        compare(vim.message, "E486: Pattern not found: zz");
        vim.lastSearch = null;
        keys("ga");
        compare(vim.message, "E35: No previous regular expression");
        // In the listing, from the names.
        loadListing("M  a_b\nC  c_d");
        keys("/^\\w<CR>ga");
        compare(vim.cursor, 12);
        compare(vim.cursors.map(c => c.pos), [4]);
        keys("~");
        compare(render(), "<M:h1>  A_b\n<C:h2>  C_d");
    }

    // A count after the flags: that many lines from the range's last, as
    // far as there are.
    function test_substituteCount() {
        load("a\na\na\na\na");
        keys("j:s/a/b/ 2<CR>");
        compare(editor.text, "a\nb\nb\na\na");
        keys("u:1,3s/a/c/2<CR>");
        compare(editor.text, "a\na\nc\nc\na");
        keys("u:4&&9<CR>");
        compare(editor.text, "a\na\na\nc\nc");
        // A :s with a count is previewed over its lines.
        keys("gg:s/a/d/ 3");
        compare(editor.text, "d\nd\nd\nc\nc");
        keys("<Esc>");
        compare(editor.text, "a\na\na\nc\nc");
    }

    // c asks about each match, as vim's: y replaces it, n leaves it, l
    // replaces it and stops, a replaces it and all after, q and Esc stop.
    // All it replaced is one change; the cursor stays on the last
    // replacement. Keys answer it before anything else: a macro's too.
    function test_substituteConfirm() {
        load("a a a\na a\nb");
        keys(":%s/a/xx/gc<CR>");
        verify(vim.confirming);
        compare(vim.message, "replace with xx (y/n/a/q/l/^E/^Y)?");
        compare(vim.cursor, 0);
        const shown = () => vim.searchHighlights().map(s => [editor.text.slice(s.start, s.end), s.current]);
        compare(shown(), [["a", true], ["a", false], ["a", false], ["a", false], ["a", false]]);
        keys("y");
        compare(editor.text, "xx a a\na a\nb");
        compare(vim.cursor, 3);
        compare(shown(), [["a", true], ["a", false], ["a", false], ["a", false]]);
        keys("n");
        compare(vim.cursor, 5);
        keys("dj"); // nothing, as in vim
        compare(editor.text, "xx a a\na a\nb");
        verify(vim.confirming);
        keys("y");
        compare(editor.text, "xx a xx\na a\nb");
        compare(vim.cursor, 8);
        keys("a");
        compare(editor.text, "xx a xx\nxx xx\nb");
        compare(vim.confirming, null);
        compare(vim.message, "4 substitutions on 2 lines");
        compare(vim.cursor, 11); // the last replacement's start
        compare(vim.searchHighlights(), []);
        keys("u");
        compare(editor.text, "a a a\na a\nb");
        // l replaces and stops, q and Esc only stop.
        keys(":%s/a/y/gc<CR>nl");
        compare(editor.text, "a y a\na a\nb");
        compare(vim.confirming, null);
        compare(vim.message, "");
        compare(vim.cursor, 2);
        keys("u:%s/a/y/gc<CR>yq");
        compare(editor.text, "y a a\na a\nb");
        compare(vim.confirming, null);
        keys("u:%s/a/y/gc<CR>nn<Esc>");
        compare(editor.text, "a a a\na a\nb");
        compare(vim.cursor, 0); // back where it was
        compare(vim.undoStack.length, 0); // nothing replaced, no change
        // Through the end, the last one answered ends it; & asks again.
        keys(":s/a/z/gc<CR>nyn");
        compare(editor.text, "a z a\na a\nb");
        compare(vim.confirming, null);
        keys("j&");
        verify(vim.confirming);
        keys("a");
        compare(editor.text, "a z a\nz z\nb");
        // In a macro, its keys answer.
        load("a a a\na a a");
        keys("qq:s/a/w/gc<CR>ynyq");
        compare(editor.text, "w a w\na a a");
        keys("j@q");
        compare(editor.text, "w a w\nw a w");
        compare(vim.confirming, null);
        // Something from outside (a click) ends it, keeping what was
        // replaced; the listing as it's read again drops it.
        load("a a a");
        keys(":s/a/b/gc<CR>y");
        vim.interrupt();
        compare(vim.confirming, null);
        compare(vim.message, "");
        compare(editor.text, "b a a");
        keys("u");
        compare(editor.text, "a a a");
        keys(":s/a/b/gc<CR>");
        vim.reset([]);
        compare(vim.confirming, null);
        // Typed, it's previewed as n is: the matches only highlighted.
        load("a a");
        keys(":s/a/b/gc");
        compare(editor.text, "a a");
        compare(vim.searchHighlights().length, 2);
        keys("<Esc>");
        // A replacement with a line break, and in the listing, its prefix.
        loadListing("M  ab\nC  ba");
        keys(":%s/a/1\\r2/gc<CR>");
        compare(vim.cursor, 4);
        keys("ny");
        compare(render(), "<M:h1>  ab\n<C:h2>  b1\n   2");
        compare(vim.confirming, null);
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

    // The Space keys are Ex commands too, which run what the keys do where
    // vim is, and fail where they aren't keys.
    function test_commandKeysAsEx() {
        load("one\ntwo");
        vim.commandKeys = {
            "  ": "apply",
            " a": "applyAsking",
            " u": "undoApply",
            " r": "reveal",
            " o": "openInApp",
            " O": "openWith",
            " q": "shortcuts",
            "K": "info"
        };
        keyCommands.clear();
        const ran = () => keyCommands.signalArguments.map(a => [a[0], a[1]]);
        keys(":apply<CR>:ap<CR>");
        keys(":confirm apply<CR>:conf ap<CR>");
        keys(":undolist<CR>:undol<CR>");
        keys(":reveal<CR>:rev<CR>");
        keys(":open<CR>:o<CR>");
        keys(":shortcuts<CR>:sho<CR>");
        // K is :info.
        keys(":info<CR>:inf<CR>");
        compare(ran(), [["apply", 0], ["apply", 0], ["applyAsking", 0], ["applyAsking", 0], ["undoApply", 0],
            ["undoApply", 0], ["reveal", 0], ["reveal", 0], ["openInApp", 0], ["openInApp", 0],
            ["shortcuts", 0], ["shortcuts", 0], ["info", 0], ["info", 0]]);
        compare(vim.message, "");
        // They take no range, nor an argument.
        keys(":2reveal<CR>");
        compare(vim.message, "E481: No range allowed");
        keys(":open x<CR>");
        compare(vim.message, "E492: Not an editor command: open x");
        keys(":a<CR>");
        compare(vim.message, "E492: Not an editor command: a");
        keys(":i<CR>");
        compare(vim.message, "E492: Not an editor command: i");
        compare(keyCommands.count, 14);
        // :openwith takes the app, as the rest of the line, which the keys
        // don't.
        keyCommands.clear();
        keys(":openwith<CR>:openw Visual Studio Code<CR>:openwi  xcode <CR>");
        keys(" O");
        compare(keyCommands.signalArguments.map(a => [a[0], a[1], a[2]]),
            [["openWith", 0, ""], ["openWith", 0, "Visual Studio Code"], ["openWith", 0, "xcode"],
                ["openWith", 0, ""]]);
        keys(":2openwith x<CR>");
        compare(vim.message, "E481: No range allowed");
        keys(":openwit! x<CR>");
        compare(vim.message, "E492: Not an editor command: openwit! x");
        compare(keyCommands.count, 4);
        // In a file, Space Space saves, so :apply does, also after
        // :confirm, as Space a isn't a key there, nor is Space u.
        vim.commandKeys = { "  ": "save", " q": "shortcuts" };
        keyCommands.clear();
        keys(":apply<CR>:confirm apply<CR>:shortcuts<CR>");
        compare(ran(), [["save", 0], ["save", 0], ["shortcuts", 0]]);
        keys(":undol<CR>");
        compare(vim.message, ":undol does nothing here");
        verify(vim.messageIsError);
        keys(":info<CR>");
        compare(vim.message, ":info does nothing here");
        compare(keyCommands.count, 3);
        // -c's commands stop there, and go on after one that runs.
        vim.runCommands(["open", "norm x"], "-c");
        compare(vim.message, ":open does nothing here");
        compare(editor.text, "one\ntwo");
        vim.runCommands(["apply", "norm x"], "-c");
        compare(ran(), [["save", 0], ["save", 0], ["shortcuts", 0], ["save", 0]]);
        compare(editor.text, "ne\ntwo");
    }

    // Keys that are no command say so, rather than do nothing: that the
    // other mode has them, that they're Koil's own but not here, or that
    // they're no command at all. Esc after other keys, and Ctrl-C, cancel
    // them without a word, as in vim.
    function test_badKeys() {
        load("one two\nthree");
        vim.commandKeys = { " r": "reveal", "K": "info", "gss": "sort:size" };
        vim.visualCommandKeys = { " q": "shortcuts" };
        vim.ownKeys = ["  ", " u", " r", "K", "gs"];
        vim.shortcuts = [{ keys: "gc", macro: "A!<Esc>", label: "gc", normal: true, visual: false },
            { keys: "gC", macro: "U", label: "gC", normal: false, visual: true }];
        keyCommands.clear();
        const error = text => {
            compare(vim.message, text);
            verify(vim.messageIsError);
            compare(vim.pendingKeys, "");
        };
        keys(" x");
        error("Space x isn't a command");
        keys("dq");
        error("dq isn't a command");
        // Named without the register and count.
        keys("\"a3<C-g>");
        error("<C-g> isn't a command");
        // Keys only a shortcut takes too, which end the command.
        keys("d<F5>");
        error("d<F5> isn't a command");
        keys(" u");
        error("Space u does nothing here");
        keys("U");
        error("U works only in visual mode");
        keys("gC");
        error("gC works only in visual mode");
        keys("d<Esc>");
        compare(vim.message, "");
        compare(vim.pendingKeys, "");
        compare(render(), "one two\nthree");
        // In visual mode, which stays.
        keys("v");
        keys("2K");
        error("K works only in normal mode");
        keys(" r");
        error("Space r works only in normal mode");
        keys("zz");
        error("zz works only in normal mode");
        keys("gs");
        error("gs works only in normal mode");
        keys("gc");
        error("gc works only in normal mode");
        keys(" u");
        error("Space u does nothing here");
        keys(" x");
        error("Space x isn't a command");
        // d is a command at once in visual mode, so d isn't what zq goes
        // on from.
        keys("zq");
        error("zq isn't a command");
        compare(vim.mode, "visual");
        compare(keyCommands.count, 0);
        keys("<Esc>");
        compare(render(), "one two\nthree");
        // They stop a macro, and say why.
        keys(":norm xzqx<CR>");
        compare(render(), "ne two\nthree");
        error("zq isn't a command");
        // A command cancelled stops it too, but without a word.
        vim.message = "";
        vim.runCommands(["norm d<Esc>x"], "-c");
        vim.runCommands(["norm d<C-c>x"], "-c");
        compare(render(), "ne two\nthree");
        compare(vim.message, "");
    }

    // Ctrl-C leaves visual mode, as Esc does, as vim's (typed, only on
    // macOS: elsewhere Ctrl+C is Copy, which yanks what's selected).
    function test_visualCtrlC() {
        load("one two");
        vim.runCommands(["norm vl<C-c>x"], "-c");
        compare(render(), "oe two");
        if (isMac) {
            keys("vl<C-c>");
            compare([vim.mode, vim.message, vim.cursor], ["normal", "", 2]);
        }
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
    // goes on until a command fails. Each runs a thousand times first, in
    // chunks (see Batches and runs), more than one if the machine is busy.
    function test_recursiveShortcuts() {
        load("1\n1\n1");
        vim.shortcuts = [
            { keys: "s", macro: "ys", label: "s", normal: true, visual: false },
            { keys: "ys", macro: "s", label: "ys", normal: true, visual: false }
        ];
        keys("s");
        tryCompare(vim, "running", null);
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
        tryCompare(vim, "running", null);
        compare(vim.message, "E223: recursive mapping");
        vim.shortcuts = [{ keys: "s", macro: "@b", label: "s", normal: true, visual: false }];
        keys("qbqqbsqs");
        tryCompare(vim, "running", null);
        compare(vim.message, "E223: recursive mapping");
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
        compare(vim.message, "d<D-j> isn't a command");
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
        // Esc and Enter with Cmd, which do nothing without a shortcut
        vim.shortcuts = [{ keys: "<D-Esc>", macro: "<C-a>", label: "<D-Esc>", normal: true, visual: false },
            { keys: "g<D-CR>", macro: "<C-x>", label: "g<D-CR>", normal: true, visual: false }];
        keys("<Esc><D-Esc>");
        compare(editor.text, "5\n1");
        keys("g<D-CR>");
        compare(editor.text, "4\n1");
        vim.shortcuts = [];
        keys("d<D-Esc>");
        compare([vim.pendingKeys, vim.message], ["", "d<D-Esc> isn't a command"]);
        keys("d<D-CR>w");
        compare(editor.text, "4\n1");
    }

    // Keys with a name, with Shift, Ctrl or Cmd, as vim names them (Alt
    // isn't told apart), and F-keys.
    function test_keyNames() {
        const name = (key, modifiers) => vim.tokenFor({ key: key, modifiers: modifiers || Qt.NoModifier, text: "" });
        const ctrl = isMac ? Qt.MetaModifier : Qt.ControlModifier;
        compare([name(Qt.Key_F12), name(Qt.Key_F1, Qt.ShiftModifier), name(Qt.Key_F35, ctrl),
            name(Qt.Key_PageDown), name(Qt.Key_PageDown, Qt.ShiftModifier), name(Qt.Key_PageDown, Qt.AltModifier),
            name(Qt.Key_Left, ctrl | Qt.ShiftModifier), name(Qt.Key_Backtab, Qt.ShiftModifier),
            name(Qt.Key_Backtab, ctrl | Qt.ShiftModifier), name(Qt.Key_Backspace, Qt.ShiftModifier),
            name(Qt.Key_Delete, ctrl)],
            ["<F12>", "<S-F1>", "<C-F35>", "<PageDown>", "<S-PageDown>", "<PageDown>", "<C-S-Left>", "<S-Tab>",
                "<C-S-Tab>", "<BS>", null]);
        if (isMac)
            compare([name(Qt.Key_F12, Qt.ControlModifier), name(Qt.Key_Down, Qt.ControlModifier | Qt.ShiftModifier)],
                ["<D-F12>", "<D-S-Down>"]);
        compare(vim.macroKeys("<F12><S-F12><D-S-F35><F36><C-S-PageDown><S-Home>"), ["<F12>", "<S-F12>", "<D-S-F35>",
            "<", "F", "3", "6", ">", "<C-S-PageDown>", "<S-Home>"]);
    }

    // Every modifier held is in a key's name, in one order: Ctrl, Alt
    // (only with Ctrl or Cmd), Cmd, and Shift, which is in a character
    // (<C-K>, <C-?>) and S- only before a key with a name.
    function test_modifierNames() {
        const name = (key, modifiers, text) => vim.tokenFor({ key: key, modifiers: modifiers, text: text || "" });
        const ctrl = isMac ? Qt.MetaModifier : Qt.ControlModifier;
        const shift = Qt.ShiftModifier, alt = Qt.AltModifier;
        compare([name(Qt.Key_K, ctrl), name(Qt.Key_K, ctrl | shift), name(Qt.Key_K, ctrl | alt),
            name(Qt.Key_K, ctrl | alt | shift), name(Qt.Key_Left, ctrl | alt), name(Qt.Key_F5, ctrl | alt | shift),
            name(Qt.Key_Left, alt | shift), name(Qt.Key_BracketLeft, ctrl), name(Qt.Key_BracketLeft, ctrl | alt),
            name(Qt.Key_1, ctrl), name(Qt.Key_Question, ctrl | shift), name(Qt.Key_Greater, ctrl | shift),
            name(Qt.Key_Space, ctrl), name(Qt.Key_K, alt, "˚"), name(Qt.Key_K, alt | shift, "")],
            ["<C-k>", "<C-K>", "<C-M-k>", "<C-M-K>", "<C-M-Left>", "<C-M-S-F5>", "<S-Left>", "<Esc>", "<C-M-[>",
                "<C-1>", "<C-?>", null, null, "˚", null]);
        if (isMac) {
            const cmd = Qt.ControlModifier;
            // Option types a character, which the key's name doesn't follow
            compare([name(Qt.Key_K, cmd | ctrl), name(Qt.Key_K, cmd | ctrl | shift), name(Qt.Key_K, cmd | alt, "˚"),
                name(Qt.Key_K, cmd | ctrl | alt | shift), name(Qt.Key_1, cmd | alt), name(Qt.Key_Slash, cmd | ctrl),
                name(Qt.Key_Left, cmd | ctrl), name(Qt.Key_Left, cmd | ctrl | alt | shift),
                name(Qt.Key_Backspace, cmd), name(Qt.Key_Backspace, cmd | ctrl), name(Qt.Key_K, ctrl | alt, "˚")],
                ["<C-D-k>", "<C-D-K>", "<M-D-k>", "<C-M-D-K>", "<M-D-1>", "<C-D-/>", "<C-D-Left>",
                    "<C-M-D-S-Left>", "<D-BS>", null, "<C-M-k>"]);
        } else {
            // AltGr comes as Ctrl+Alt, and types; Ctrl+Alt and a key it
            // types nothing with comes with the key's own letter or digit
            // (as Windows sends them), and is the key
            compare([name(Qt.Key_Q, ctrl | alt, "@"), name(Qt.Key_K, ctrl | alt, "K"),
                name(Qt.Key_K, ctrl | alt | shift, "K"), name(Qt.Key_1, ctrl | alt, "1")],
                ["@", "<C-M-k>", "<C-M-K>", "<C-M-1>"]);
        }
        compare(vim.macroKeys("<C-K><C-M-k><C-M-K><C-D-K><M-D-k><C-M-D-1><C-M-D-S-F5><M-D-Left><C-1><C-?><C-M-[>"),
            ["<C-K>", "<C-M-k>", "<C-M-K>", "<C-D-K>", "<M-D-k>", "<C-M-D-1>", "<C-M-D-S-F5>", "<M-D-Left>", "<C-1>",
                "<C-?>", "<C-M-[>"]);
        // not in another order, nor Alt alone, nor S- and a character, nor
        // Ctrl+[, which is Esc
        for (const none of ["<S-C-k>", "<M-C-k>", "<D-C-k>", "<D-M-k>", "<M-k>", "<M-Left>", "<M-S-Left>", "<S-k>",
                "<C-S-k>", "<D-S-k>", "<C-M-BS>", "<C-[>", "<C->>"])
            verify(vim.macroKeys(none).length > 1, none);
    }

    // A shortcut on Ctrl and a letter runs whatever the editor or vim has
    // on it (on macOS, Ctrl+K is Qt's Cut, Ctrl+Y its Paste).
    function test_ctrlShortcuts() {
        const shortcut = (k, macro) => ({ keys: k, macro: macro, label: k, normal: true, visual: true });
        const failed = [];
        for (let i = 0; i < 26; i++) {
            const k = "<C-" + String.fromCharCode(97 + i) + ">";
            load("a\nb");
            vim.shortcuts = [shortcut(k, "rx")];
            keys(k);
            if (editor.text !== "x\nb")
                failed.push(k);
            load("a\nb");
            keys("v" + k);
            if (editor.text !== "x\nb")
                failed.push("v" + k);
            keys("<Esc>");
        }
        vim.shortcuts = [];
        compare(failed, []);
    }

    // Ctrl+Shift and a letter is Ctrl and the letter, but for a shortcut
    // that takes it; with Alt (or Cmd) too, or a digit or a sign, a key
    // only a shortcut takes.
    function test_modifierShortcuts() {
        load("1\n1");
        const shortcut = (k, macro) => ({ keys: k, macro: macro, label: k, normal: true, visual: false });
        keys("<C-A>");
        compare(editor.text, "2\n1");
        keys("qa<C-A>q");
        compare(vim.getRegister("a").text, "<C-a>");
        // written by hand (a shortcut's keys), as vim reads it
        vim.shortcuts = [shortcut("gz", "<C-A>")];
        keys("gz");
        compare(editor.text, "4\n1");
        vim.shortcuts = [shortcut("<C-A>", "j"), shortcut("<C-M-k>", "<C-x>"), shortcut("g<C-M-S-Left>", "k"),
            shortcut("<C-1>", "<C-a>"), shortcut("<C-?>", "<C-x>")];
        keys("<C-A>");
        compare([editor.text, cursorLine()], ["4\n1", 2]);
        keys("<C-a>");
        compare(editor.text, "4\n2");
        keys("2<C-M-k>");
        compare(editor.text, "4\n0");
        keys("<C-1><C-1><C-?>");
        compare(editor.text, "4\n1");
        keys("g<C-M-S-Left>");
        compare(cursorLine(), 1);
        keys("qb<C-A>q");
        compare([vim.getRegister("b").text, cursorLine()], ["<C-A>", 2]);
        // only normal mode's: while typing and in the command line, the
        // key without Shift
        keys("ggv<C-A>");
        compare([vim.mode, cursorLine()], ["visual", 1]);
        keys("<Esc>:ab<C-U>");
        compare(vim.commandLine, ":");
        keys("<Esc>");
        if (isMac) {
            vim.shortcuts = [shortcut("<C-D-K>", "<C-a>"), shortcut("<M-D-k>", "<C-x><C-x>")];
            keys("<C-D-K>");
            compare(editor.text, "5\n1");
            keys("<M-D-k>");
            compare(editor.text, "3\n1");
        }
        // without a shortcut they're no command, which ends the one typed
        vim.shortcuts = [];
        load("a b\n1");
        keys("d<C-1>");
        compare([vim.pendingKeys, vim.message], ["", "d<C-1> isn't a command"]);
        keys("d<C-M-k>w");
        keys("d<C-M-S-Left>w");
        keys("d<C-?>w");
        compare(editor.text, "a b\n1");
    }

    // An F-key is no command but a shortcut's, and Shift and a key vim
    // knows is the key, but for a shortcut that takes it.
    function test_namedKeyShortcuts() {
        load("1\n1\n1");
        keys("<S-Down>");
        compare(cursorLine(), 2);
        keys("d<F12>");
        compare([vim.pendingKeys, vim.message], ["", "d<F12> isn't a command"]);
        keys("d<S-F12>j");
        compare([editor.text, cursorLine()], ["1\n1\n1", 3]);
        load("1\n1");
        vim.shortcuts = [{ keys: "<S-F12>", macro: "<C-a>", label: "<S-F12>", normal: true, visual: false },
            { keys: "<S-Down>", macro: "<C-x>", label: "<S-Down>", normal: true, visual: false }];
        keys("<S-F12>");
        compare(editor.text, "2\n1");
        keys("<S-Down>");
        compare([editor.text, cursorLine()], ["1\n1", 1]);
        // only normal mode's
        keys("v<S-Down>");
        compare([vim.mode, cursorLine()], ["visual", 2]);
        keys("<Esc>");
        // and in the command line, the key alone (but the arrows, which
        // select there)
        keys(":ab<S-Up><S-Esc>");
        compare(vim.commandLine, "");
        compare(vim.mode, "normal");
    }

    // Shift+Esc is Esc, but for a shortcut that takes it, in normal or
    // visual mode, as Shift+Enter is Enter.
    function test_shiftEsc() {
        load("1\n1");
        keys("ix<S-Esc>");
        compare([editor.text, vim.mode], ["x1\n1", "normal"]);
        keys("d<S-Esc>x");
        compare(editor.text, "1\n1");
        keys("v<S-Esc>");
        compare(vim.mode, "normal");
        vim.shortcuts = [{ keys: "<S-Esc>", macro: "<C-a>", label: "<S-Esc>", normal: true, visual: false }];
        keys("<S-Esc>");
        compare(editor.text, "2\n1");
        keys("ix<S-Esc>");
        compare([editor.text, vim.mode], ["x2\n1", "normal"]);
        // only normal mode's
        keys("v<S-Esc>");
        compare(vim.mode, "normal");
        compare(editor.text, "x2\n1");
        compare(vim.macroKeys("<S-Esc>x"), ["<S-Esc>", "x"]);
    }

    // Shift+Tab, and Esc, Enter and Tab with Ctrl (or Cmd, see
    // test_cmdKeys), which vim has no use for, are keys a shortcut can
    // have, with a count; without one they're no command, which ends the
    // one typed (see test_completion).
    function test_shortcutOnlyKeys() {
        load("1\n1");
        const shortcut = (k, macro) => ({ keys: k, macro: macro, label: k, normal: true, visual: false });
        vim.shortcuts = [shortcut("<S-Tab>", "<C-a>"), shortcut("g<C-CR>", "j"), shortcut("<C-Tab>", "k"),
            shortcut("<C-Esc>", "<C-x>")];
        keys("<S-Tab>");
        compare(editor.text, "2\n1");
        keys("g<C-CR>");
        compare(cursorLine(), 2);
        keys("<C-Tab>");
        compare(cursorLine(), 1);
        keys("<C-Esc>");
        compare(editor.text, "1\n1");
        keys("3<S-Tab>");
        compare(editor.text, "4\n1");
        // a macro records them
        keys("qa<S-Tab>q@a");
        compare(editor.text, "6\n1");
        compare(vim.getRegister("a").text, "<S-Tab>");
        compare(vim.macroKeys("<S-Tab><C-Tab><C-Esc><C-CR><D-Esc><D-CR><D-Tab>"), ["<S-Tab>", "<C-Tab>", "<C-Esc>",
            "<C-CR>", "<D-Esc>", "<D-CR>", "<D-Tab>"]);
        vim.shortcuts = [];
        keys("d<S-Tab>");
        compare([vim.pendingKeys, vim.message], ["", "d<S-Tab> isn't a command"]);
        keys("d<C-Esc>w");
        keys("d<C-CR>w");
        keys("d<C-Tab>w");
        compare(editor.text, "6\n1");
        compare(vim.mode, "normal");
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

    // Skips a test that needs text measured in a real font: Windows'
    // offscreen platform has none (no font families at all), and draws
    // every character as a box as wide as the font's size, which leaves
    // the views here too few columns for what the test does. With
    // windows, it runs.
    function needFonts() {
        if (Qt.fontFamilies().length === 0)
            skip("no fonts here (Windows' offscreen platform): run with windows");
    }

    // zl and zh scroll sideways, as far as the room right of the text
    // (Editor.qml's sideScrollRoom), and move the cursor as far as keeps
    // it sidescrolloff columns in view, unless its line ends before the
    // view, which then stays. zL and zH scroll half the view, zs and ze
    // put the cursor at its edges.
    function test_scrollSideways() {
        needFonts();
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
        // Back where it was each time, though the view scrolls by whole
        // pixels and a column needn't be (it went a pixel further each).
        keys("zLzHzLzHzLzH");
        fuzzyCompare(f.contentX + left, x(4), 0.5);
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

    // A tab goes on to its tab stop, so zL and zH find the character
    // sidescrolloff columns from the edge by where it's drawn: by its
    // column, zL put the cursor far past the view, which then jumped to
    // it, and zH took the line as ending before the view, which left the
    // cursor out of it.
    function test_scrollSidewaysTabs() {
        needFonts();
        load("one");
        narrowText.text = "\t".repeat(30) + "end";
        waitForRendering(narrow);
        const f = narrow.contentItem as Flickable;
        switchTo(narrowText, {
            cursor: 0
        }, f);
        const x = p => narrowText.positionToRectangle(p).x;
        const cw = x(31) - x(30), left = narrowText.leftPadding, right = narrowText.rightPadding;
        const tabs = narrowText.tabStopDistance;
        narrowText.tabStopDistance = 3 * cw;
        waitForRendering(narrow);
        vim.charWidth = cw;
        keys(":set siso=2<CR>");
        keys("zL");
        const half = Math.floor((f.width - left - right) / cw / 2);
        fuzzyCompare(f.contentX, half * cw, 0.5);
        const first = f.contentX + left + 2 * cw - 0.5;
        verify(x(vim.cursor) >= first, "the cursor is in view");
        verify(x(vim.cursor - 1) < first, "the first tab that is");
        keys("$zH");
        const last = f.contentX + f.width - right - 2 * cw + 0.5;
        verify(x(vim.cursor + 1) <= last, "the cursor is in view");
        verify(x(vim.cursor + 2) > last, "the last tab that is");
        narrowText.tabStopDistance = tabs;
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
        needFonts();
        const wide = "one two three four five six seven eight nine ten eleven twelve";
        const t = loadWrapped(["x", wide, wide, wide, wide, wide, wide], 1);
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
        // Shift+Tab is no command elsewhere, which ends the one typed.
        keys("0d<S-Tab>w");
        compare(other.text, "docs/docs/");
        // Enter with Ctrl or Cmd makes no line break in one line.
        keys("A<C-CR><D-CR>");
        compare([other.text, vim.mode], ["docs/docs/", "insert"]);
        keys("<Esc>");
    }

    // Ctrl-N and Ctrl-P while typing complete the word before the cursor
    // from the words in the text, as vim's keyword completion does.
    function test_wordCompletion() {
        const line = n => editor.text.split("\n")[n - 1];
        const names = () => vim.completion.options.map(o => o.name);
        const label = "-- Keyword completion (^N^P) ";
        load("food foo\nfox\n\nfoobar");
        // Ctrl-N: the nearest word after the cursor first, then on from
        // the text's start, each once, and past the last, what was written.
        keys("3Gifo<C-n>");
        compare(line(3), "foobar");
        compare(names(), ["foobar", "food", "foo", "fox"]);
        compare(vim.modeLabel, label + "match 1 of 4");
        keys("<C-n><C-n>");
        compare(line(3), "foo");
        keys("<C-n><C-n>");
        compare([line(3), vim.modeLabel], ["fo", label + "Back at original"]);
        keys("<C-n>");
        compare(line(3), "foobar");
        keys("<C-p><C-p>");
        compare(line(3), "fox");
        // Esc keeps it, and "." types that word again.
        keys("<Esc>");
        compare([line(3), vim.completion, vim.modeLabel], ["fox", null, ""]);
        keys(".");
        compare(line(3), "fofoxx");
        // Ctrl-P: the nearest before the cursor first, at the list's
        // bottom, as vim's, so Ctrl-P, as Shift+Tab, goes up it, and Ctrl-N
        // down. The status line counts in the order found.
        keys("ccfo<C-p>");
        compare([line(3), names(), vim.completion.index], ["fox", ["foobar", "food", "foo", "fox"], 3]);
        compare(vim.modeLabel, label + "match 1 of 4");
        keys("<C-p>");
        compare([line(3), vim.completion.index, vim.modeLabel], ["foo", 2, label + "match 2 of 4"]);
        keys("<S-Tab>");
        compare([line(3), vim.completion.index, vim.modeLabel], ["foo", 1, label + "match 3 of 4"]);
        keys("<C-n>");
        compare([line(3), vim.completion.index], ["foo", 2]);
        keys("<C-n><C-n>");
        compare([line(3), vim.completion.index, vim.modeLabel], ["fo", -1, label + "Back at original"]);
        keys("<C-p>");
        compare([line(3), vim.completion.index], ["fox", 3]);
        keys("<C-n><C-n>");
        compare([line(3), vim.completion.index], ["foobar", 0]);
        // Ctrl-E puts back what was written.
        keys("<C-e>");
        compare([line(3), vim.completion, vim.mode], ["fo", null, "insert"]);
        // Down and Up only pick one, which Enter puts in. Otherwise Enter
        // makes a new line.
        keys("<C-n><Down><Down><Up><Down>");
        compare([line(3), vim.completion.index], ["foobar", 2]);
        keys("<CR>");
        compare([line(3), vim.completion, vim.mode], ["foo", null, "insert"]);
        // So do Tab and Shift+Tab, as in the path field.
        keys("<BS><C-n><Tab><Tab><S-Tab><Tab>");
        compare([line(3), vim.completion.index, vim.completionListed], ["foobar", 2, true]);
        keys("<CR>");
        compare([line(3), vim.completion, vim.mode], ["foo", null, "insert"]);
        keys("<BS><C-n><CR>");
        compare(editor.text, "food foo\nfox\nfoobar\n\nfoobar");
        // Ctrl-Y keeps the one that's in, or puts in the one picked.
        keys("fo<C-n><C-n><C-y>");
        compare([line(4), vim.completion], ["food", null]);
        keys(" fo<C-n><Down><C-y>");
        compare([line(4), vim.completion], ["food food", null]);
        // None found: the status line says so, as an error, until the next
        // key.
        keys("<C-n>");
        compare([line(4), vim.modeLabel, vim.wordsFailed], ["food food", label + "Pattern not found", true]);
        keys("s");
        compare([line(4), vim.modeLabel, vim.wordsFailed], ["food foods", "-- INSERT --", false]);
        keys("<Esc>");

        // Backspace finds the words for what's left, keeping the one
        // picked, to pick from; so does typing then. None ends it.
        load("food foo\nfox\n\nfoobar");
        keys("3Gifo<C-n><BS>");
        compare([line(3), names(), vim.completion.index], ["fooba", ["foobar"], 0]);
        keys("<BS><BS>");
        compare([line(3), names(), vim.completion.index], ["foo", ["foobar", "food"], 0]);
        keys("<Down><CR>");
        compare([line(3), vim.completion], ["food", null]);
        keys("<BS><BS><C-n><BS><BS><BS><BS>o");
        compare([line(3), names(), vim.completion.index], ["foo", ["foobar", "food"], 0]);
        keys("d");
        compare([line(3), vim.completion], ["food", null]);
        // Backspace that would leave no word ends it, and deletes.
        keys("<BS><BS><C-n><BS><BS><BS><BS><BS>");
        compare([line(3), names()], ["f", ["foobar", "food", "foo", "fox"]]);
        keys("<BS>");
        compare([line(3), vim.completion], ["", null]);
        // Typing before one is picked ends it, and types.
        keys("fo<C-n>s");
        compare([line(3), vim.completion], ["foobars", null]);
        keys("<Esc>");
        // The one picked, once typing leaves it out, gives way to the
        // nearest above it, as vim's.
        load("food foo\nfox\n\nfoobar");
        keys("3Gif<C-n><BS><BS><BS><BS><BS><Down><Down><Down>o");
        compare([line(3), vim.completion.index], ["fo", 3]);
        keys("o");
        compare([line(3), names(), vim.completion.index], ["foo", ["foobar", "food"], 1]);
        // None picked stays so, and Enter then makes a new line, as vim's.
        keys("<C-e><BS><C-n><C-n><C-n><C-n><C-n><BS>");
        compare([line(3), names(), vim.completion.index], ["f", ["foobar", "food", "foo", "fox"], -1]);
        keys("<CR>");
        compare([line(3), line(4), vim.completion], ["f", "", null]);
        keys("<Esc>");

        // Case counts only with an uppercase letter, as in a search.
        load("Foo foo bar");
        keys("A F<C-n>");
        compare([editor.text, vim.modeLabel], ["Foo foo bar Foo", label + "The only match"]);
        // With no list to pick from, Tab types itself.
        keys("<Tab>");
        compare([editor.text, vim.completion], ["Foo foo bar Foo\t", null]);
        keys("<Esc>A f<C-n>");
        compare(names(), ["Foo", "foo"]);
        keys("<Esc>");
        // With no word before the cursor, every word of two characters or
        // more, which leaves out the listing's icons.
        load("a bc de");
        keys("A <C-n>");
        compare([editor.text, names()], ["a bc de bc", ["bc", "de"]]);
        keys("<Esc>");
        load("M  one\nM  two");
        vim.linePrefixes = true;
        keys("Go<C-n>");
        compare([render(), names()], ["<M:h1>  one\n<M:h2>  two\n   one", ["one", "two"]]);
        keys("<Esc>");
        vim.linePrefixes = false;
        // The other buffers' words come after this one's.
        vim.wordSources = () => ["other foobaz"];
        load("food");
        keys("A fo<C-n>");
        compare(names(), ["food", "foobaz"]);
        keys("<C-e><C-p>");
        compare([names(), vim.completion.index, editor.text], [["foobaz", "food"], 1, "food food"]);
        keys("<Esc>");
        vim.wordSources = null;
        // At every cursor.
        load("fo\nfo\nfoobar");
        vim.toggleCursor(3);
        keys("A<C-n><Esc>");
        compare(editor.text, "foobar\nfoobar\nfoobar");
        // A macro runs Ctrl-N again, where it's run.
        load("food");
        keys("qaofo<C-n><Esc>q@a");
        compare(editor.text, "food\nfood\nfood");

        // In the path field, Tab ends it, then completes the path.
        other.text = "";
        switchTo(other, null);
        vim.singleLine = true;
        vim.completer = completerOf(["src/main/", "docs/"]);
        vim.wordSources = () => ["src"];
        keys("is<C-n>");
        compare([other.text, vim.completion.words], ["src", true]);
        keys("<Tab>");
        compare([other.text, vim.completion], ["src/", null]);
        keys("<Esc>");
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
        const show = names => shown = names;
        vim.registersRequested.connect(show);
        vim.lastInsert = "";
        vim.lastSearch = null;
        vim.history = { ":": [], "/": [], "<": [] };
        keys("yyjdw\"ayy");
        const row = (name, type, lines, more) => ({ name: name, type: type, lines: lines, more: more || 0 });
        compare(vim.registerList(""), [row("\"", "l", ["x"]), row("0", "l", ["one"]), row("a", "l", ["x"]),
            row("-", "c", ["two "])]);
        // Koil lists those it names, if any holds something.
        keys(":reg 0 -<CR>");
        compare(shown, "0 -");
        compare(vim.registerList(shown).map(row => row.name), ["0", "-"]);
        shown = null;
        keys(":di z<CR>");
        compare(shown, null);
        compare(vim.message, "Nothing in those registers");
        vim.registersRequested.disconnect(show);
        // The clipboard is listed once, as "+, also asked for as "*.
        const clipboard = vim.clipboard;
        vim.clipboard = { clipboardData: () => "", clipboardText: () => "clip" };
        compare(vim.registerList("").filter(row => row.lines[0] === "clip").map(row => row.name), ["+"]);
        compare(vim.registerList("*").map(row => row.name), ["+"]);
        vim.clipboard = clipboard;
        vim.registers = { "a": { text: "x".repeat(400), linewise: false, hidden: [] } };
        compare(vim.registerList("a")[0].lines, ["x".repeat(300) + "…"]);
        // Its lines, each a line: the first ones, and how many more it
        // has. Characters that end with a line break show it.
        const entry = (text, linewise) => ({ text: text, linewise: linewise, hidden: [] });
        const letters = "abcdefghij".split("");
        vim.registers = { "a": entry("one\n\ntwo\n", true), "b": entry("one\ntwo", false), "c": entry("one\n", false),
            "d": entry(letters.slice(0, 6).join("\n") + "\n", true), "e": entry(letters.slice(0, 7).join("\n"), false),
            "f": entry("\n", true), "g": entry("x".repeat(400) + "\ty\n" + letters.join("\n") + "\n", false),
            "h": entry("\ta\tbcde\tf\r\n", true) };
        compare(vim.registerList("abcdefg"), [row("a", "l", ["one", "", "two"]), row("b", "c", ["one", "two"]),
            row("c", "c", ["one^J"]), row("d", "l", letters.slice(0, 6)), row("e", "c", letters.slice(0, 5), 2),
            row("f", "l", [""]), row("g", "c", ["x".repeat(300) + "…"].concat(letters.slice(0, 4)), 6)]);
        // A tab goes to its tab stop, as in the editor.
        compare(vim.registerList("h"), [row("h", "l", ["    a   bcde    f^M"])]);
    }

    // What :reg's list does with the registers picked: pastes them after
    // the cursor, several as one, or empties them.
    function test_registerListActions() {
        load("one\ntwo");
        const entry = (text, linewise) => ({ text: text, linewise: linewise, hidden: [] });
        vim.registers = { "a": entry("A\n", true), "b": entry("b", false), "c": entry("c", false) };
        // One, as "ap, from any mode, and . pastes it again.
        keys("v");
        vim.putRegisters(["b"]);
        compare(vim.mode, "normal");
        compare(editor.text, "obne\ntwo");
        keys(".");
        compare(editor.text, "obbne\ntwo");
        keys("u");
        compare(editor.text, "obne\ntwo");
        keys("u");
        compare(editor.text, "one\ntwo");
        // Characters one after another, in one change.
        vim.putRegisters(["b", "c"]);
        compare(editor.text, "obcne\ntwo");
        keys("u");
        compare(editor.text, "one\ntwo");
        // Lines, if one of them is, each after the one before.
        vim.putRegisters(["b", "a", "c"]);
        compare(editor.text, "one\nb\nA\nc\ntwo");
        keys("u");
        // One that holds nothing is left out.
        vim.putRegisters(["z"]);
        vim.putRegisters(["z", "a"]);
        compare(editor.text, "one\nA\ntwo");
        keys("u");
        compare(editor.text, "one\ntwo");

        // Cleared, they hold nothing; not those vim fills itself.
        keys(":noh<CR>");
        compare(vim.clearRegisters(["a", "c", ":"]), [":"]);
        compare(vim.registerList("abc:").map(row => row.name), ["b", ":"]);
        compare(vim.getRegister("a"), null);
        keys("\"ap");
        compare(editor.text, "one\ntwo");
        // A cleared one is written again as any other.
        keys("\"ayy\"Ayy");
        compare(vim.getRegister("a").text, "one\none\n");
        compare(vim.macroList().map(macro => macro.name), ["a", "b", "\""]);
        compare(vim.clearRegisters(["\"", "b"]), []);
        compare(vim.registerList("\"b"), []);
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
        // p left the cursor on the name, after the icon (see firstNonBlank).
        // Off macOS, Ctrl+V starts visual block mode, and Shift+Insert is
        // Paste.
        keys("0v<D-c>$" + (isMac ? "<D-v>" : "<S-Ins>"));
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
        keys("mGmCx<Esc>");
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

    // S and gS on marked lines: around each run of them next to each
    // other, as on those lines selected with V, as one change, after which
    // gv marks them again. A tag is asked for with them still drawn.
    function test_markedSurround() {
        load("a\nb\nc\nd\ne");
        keys("mjmjjmS)");
        compare(render(), "(\n    a\n    b\n)\nc\n(\n    d\n)\ne");
        compare(vim.marked, []);
        compare(vim.cursor, 0);
        keys("gv");
        compare(vim.marked, [2, 8, 20]);
        keys("<Esc>u");
        compare(render(), "a\nb\nc\nd\ne");
        load("a\nb\nc");
        keys("mjjmgS]");
        compare(render(), "[\na\n]\nb\n[\nc\n]");
        // Brackets have each one's inside reindented by them.
        load("a\n      b\nc\nd\n      e");
        keys("mjmjjmjmS{");
        compare(render(), "{\n    a\n    b\n}\nc\n{\n    d\n    e\n}");
        load("a\nb\nc");
        keys("mjjmS<");
        compare(vim.commandLine, "<");
        compare(vim.marked, []);
        compare(vim.visualShown.marked, [0, 4]);
        keys("p>");
        compare(render(), "<p>\n    a\n</p>\nb\n<p>\n    c\n</p>");
        compare(vim.visualShown, null);
        keys("gv");
        compare(vim.marked, [4, 21]);
        // Esc puts in none, and gv marks them again.
        load("a\nb");
        keys("mjmS<");
        keys("p<Esc>");
        compare(render(), "a\nb");
        keys("gv");
        compare(vim.marked, [0, 2]);
    }

    // U on marked lines makes them uppercase, as in visual mode, and @
    // and Q run a macro on each one, unmarked first.
    function test_markedVisualKeys() {
        load("ab\ncd\nef");
        keys("mjjmU");
        compare(render(), "AB\ncd\nEF");
        compare(vim.marked, []);
        keys("u");
        compare(render(), "ab\ncd\nef");
        load("a\nb\nc\nd");
        vim.registers["q"] = { text: "A!<Esc>", linewise: false, hidden: [] };
        keys("jmjjm@q");
        compare(render(), "a\nb!\nc\nd!");
        compare(vim.marked, []);
        compare(vim.running, null);
        keys("u");
        compare(render(), "a\nb\nc\nd");
        keys("gv@@");
        compare(render(), "a\nb!\nc\nd!");
        // Q, the one recorded last
        load("a\nb\nc");
        keys("qqA!<Esc>qjjmQ");
        compare(render(), "a!\nb\nc!");
    }

    // While lines are marked, a shortcut for visual mode runs on them, as
    // on a selection, before one for normal mode with the same keys.
    function test_markedShortcuts() {
        load("a\nb\nc\nd");
        vim.commandKeys = { "  ": "apply" };
        vim.shortcuts = [
            { keys: " c", macro: ":s/^/# /<CR>", label: "Space c", normal: false, visual: true },
            { keys: " u", macro: "<C-a>", label: "Space u", normal: true, visual: false },
            { keys: " u", macro: "gU", label: "Space u", normal: false, visual: true }
        ];
        keys("mjjm c");
        compare(editor.text, "# a\nb\n# c\nd");
        compare(vim.marked, []);
        // a run is one undo step, after which gv marks them again
        keys("u");
        compare(editor.text, "a\nb\nc\nd");
        keys("gv u");
        compare(editor.text, "A\nb\nC\nd");
        // S surrounds them, as in visual mode
        vim.shortcuts = vim.shortcuts.concat([{ keys: " s", macro: "S)", label: "Space s", normal: false,
            visual: true }]);
        keys("ggmjjm s");
        compare(editor.text, "(\n    A\n)\nb\n(\n    C\n)\nd");
        // without marks, Space c is a bad command in normal mode, and
        // Space u is normal mode's
        load("1\nb");
        keys(" c");
        compare(editor.text, "1\nb");
        compare(vim.pendingKeys, "");
        keys(" u");
        compare(editor.text, "2\nb");
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

    // The replacement, as VS Code's: $1, $&, $$, \u before a group; & is
    // itself. \0 to \9 are the match and its groups too, as :s's are, and
    // one that isn't a group stays as it is.
    function test_replacementSyntax() {
        load("ab cd");
        findBar.open(true);
        findBar.useRegex = true;
        findBar.query = "(\\w)(\\w)";
        findBar.replacement = "$2&$$\\u$1[\\0]\\2\\3";
        findBar.replaceAll();
        compare(render(), "b&$A[ab]b\\3 d&$C[cd]d\\3");
        vim.nativeUndo(false);
        findBar.useRegex = false;
        findBar.query = "ab";
        findBar.replacement = "\\0$&";
        findBar.replaceAll();
        compare(render(), "\\0$& cd");
        findBar.useRegex = true;
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
        // Once it's as tall as its rows: before that only its first row is
        // in view, and `n` goes on from the match it's on only if that
        // shows (a key came that soon offscreen, about every other run).
        waitForRendering(help.contentItem);
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
        compare(help.matches.length, 6);
        compare(help.matchMarks["0/0t"], "56,67,1");
        compare(help.matchMarks["0/1k"], "0,11,0");
        keys("<Esc><Esc>");
        tryCompare(help, "opened", false);
    }

    // A title too long for its rows (a shell command on many paths) loses
    // its middle, so the text under it still has room; a short one doesn't.
    function test_helpLongHeading() {
        const names = [];
        for (let i = 0; i < 300; i++)
            names.push("file" + i + ".rs");
        const title = ":!wc -l " + names.join(" ");
        help.showText(title, "output", "");
        tryCompare(help, "opened", true);
        verify(help.shownHeading.length < title.length);
        verify(help.shownHeading.startsWith(":!wc -l file0.rs"));
        verify(help.shownHeading.endsWith("file299.rs"));
        verify(help.shownHeading.includes("…"));
        verify(help.shownHeadingRows <= help.headingRows, help.shownHeadingRows);
        verify(help.shownHeadingRows > 1, help.shownHeadingRows);
        help.close();
        tryCompare(help, "opened", false);
        help.showText(":!ls", "output", "");
        tryCompare(help, "opened", true);
        compare(help.shownHeading, ":!ls");
        help.close();
        tryCompare(help, "opened", false);
    }

    // What a command writes while it runs is added to the box as it
    // comes, where Esc stops it rather than closing the box, until it's
    // done.
    function test_helpOutput() {
        const out = (lines, line, more) => Object.assign({ reset: false, drop: 0, lines: lines, line: line, cut: 0 }, more);
        let stops = 0;
        const stop = () => stops++;
        help.stopRequested.connect(stop);
        help.showRunning(":!make", Date.now());
        tryCompare(help, "opened", true);
        verify(help.running);
        compare(help.outputStatus, "Running");
        // the lines that ended, then the one being written, which the next
        // takes the place of
        help.addOutput(out(["one", "two"], "10%"));
        compare(help.outputShown(), "one\ntwo\n10%");
        help.addOutput(out([], "20%"));
        compare(help.outputShown(), "one\ntwo\n20%");
        // the first lines go as more are kept than are shown
        help.addOutput(out(["20%"], "", { drop: 1, cut: 1 }));
        compare(help.outputShown(), "two\n20%");
        compare(help.outputCut, 1);
        help.addOutput(out(["", "x"], "y", { cut: 1 }));
        compare(help.outputShown(), "two\n20%\n\nx\ny");
        // it's searched as the help is
        keys("/x<CR>");
        compare(help.matches.length, 1);
        compare(help.matches[0].start, 9);
        keys("<Esc>");
        compare(help.searchPattern, "");
        // all of them go
        help.addOutput(out(["z"], "", { drop: 4, cut: 5 }));
        compare(help.outputShown(), "z");
        help.addOutput(out(["", "a"], "b", { reset: true, cut: 9 }));
        compare(help.outputShown(), "\na\nb");
        compare(help.outputCut, 9);
        // Esc stops it, and nothing closes the box
        keys("q<CR>");
        verify(help.opened);
        compare(stops, 0);
        keys("<Esc>");
        verify(help.opened);
        compare(stops, 1);
        keys("<C-c>");
        compare(stops, 2);
        help.endOutput("failed", "Exit 2");
        verify(!help.running);
        verify(help.outputStatus.startsWith("Exit 2 · "), help.outputStatus);
        help.addOutput(out(["late"], ""));
        compare(help.outputShown(), "\na\nb");
        keys("<Esc>");
        tryCompare(help, "opened", false);
        compare(stops, 2);
        help.stopRequested.disconnect(stop);

        // One that's done, with how it ended.
        help.showText(":!ls", "a\nb", { failed: "", took: 1234, cut: 3 });
        tryCompare(help, "opened", true);
        verify(!help.running);
        compare(help.outputShown(), "a\nb");
        compare(help.outputStatus, "Done · 1.2s");
        compare(help.outputCut, 3);
        compare(help.duration(75000, false), "1m 15s");
        compare(help.duration(12900, true), "12s");
        keys("q");
        tryCompare(help, "opened", false);
        // The help isn't one.
        help.showList("Test", [["a", "one"]], 4);
        tryCompare(help, "opened", true);
        verify(!help.output);
        keys("<Esc>");
        tryCompare(help, "opened", false);
        // as it was, for the other tests
        help.lastPattern = "";
        help.searchHistory = [];
    }

    // Every name of a key the help lists (:h keynames) is one key to a
    // macro, and those it says aren't keys are their characters.
    function test_helpKeyNames() {
        const section = help.sections.find(s => s.title === "Key names");
        verify(section);
        let names = 0;
        for (const row of section.rows) {
            for (const code of Txt.parseCode(row[0], false).codes) {
                compare(vim.macroKeys(code.text), [code.text], code.text);
                names++;
            }
        }
        verify(names > 25);
        for (const none of ["<cr>", "<c-a>", "<Space>", "<lt>", "<Bar>", "<Leader>", "<Nop>", "<S-BS>", "<C-Del>",
                "<C-S-k>", "<C-[>", "<F36>", "<M-a>", "<A-a>"])
            verify(vim.macroKeys(none).length > 1, none);
        verify(help.show("keynames"));
        compare(help.sections[help.shownSection].title, "Key names");
        // A name that's no topic of another section (<CR> is the
        // listing's Enter).
        verify(help.show("<PageDown>"));
        compare(help.sections[help.shownSection].title, "Key names");
        help.close();
    }

    // The links to the help (see HelpLink) that show under `item`.
    function helpLinks(item) {
        const found = [];
        const walk = i => {
            if (!i.visible)
                return;
            if (i.topic !== undefined && i.shade !== undefined)
                found.push(i);
            for (const child of i.children)
                walk(child);
        };
        walk(item);
        return found;
    }

    // A `:h topic` in a text is a link to it: each one in the help goes
    // somewhere, a click goes there with the other sections as they are,
    // and Ctrl-O goes back; in a question, it asks for the topic.
    function test_helpLinks() {
        compare(Txt.helpTopic(":h pick"), "pick");
        compare(Txt.helpTopic(":help set"), "set");
        compare(Txt.helpTopic(":h"), "");
        compare(Txt.helpTopic("%:h"), null);
        compare(Txt.helpTopic(":hidden"), null);
        compare(Txt.helpTopic(":h a b"), null);
        let links = 0;
        for (const s of help.sections) {
            for (const markup of [s.intro, s.note].concat(s.rows.map(r => r[1]))) {
                for (const code of Txt.parseCode(markup || "", false).codes) {
                    if (code.link === null)
                        continue;
                    verify(help.topicPlace(code.link), code.text);
                    links++;
                }
            }
        }
        verify(links > 25);
        // Only a link is in the link's color, and only where one is given.
        const parsed = Txt.parseCode("see `:h pick`, not `x`", false);
        const html = Txt.codeHtml(parsed, [], false, "Menlo", 4, "#123456");
        verify(/color:#123456;">:h/.test(html));
        verify(!/color:#123456;">x</.test(html));
        verify(!Txt.codeHtml(parsed, [], false, "Menlo", 4, "").includes("color:"));

        const section = title => help.sections.findIndex(s => s.title === title);
        const unfolded = () => help.sections.map((s, i) => i).filter(i => help.isOpen(i));
        const ctrl = section("Ctrl keys"), block = section("Visual block and multiple cursors");
        verify(help.show("ctrl"));
        tryCompare(help, "opened", true);
        compare(unfolded(), [ctrl]);
        // A row's keys aren't links, its text's `:h block` (and `:h
        // complete`) is.
        let link;
        tryVerify(() => (link = helpLinks(help.contentItem).find(l => l.topic === "block")) !== undefined);
        // Once its rows are laid out, which is where the link is.
        tryVerify(() => help.span(ctrl).bottom - help.span(ctrl).top > 100);
        verify(helpLinks(help.contentItem).every(l => l.topic === "block" || l.topic === "complete"));
        // Scrolled to, if it's below what the help shows: a click only
        // reaches what does, and how far down the link is goes by the
        // font (offscreen's put it under the window's edge).
        const below = link.mapToItem(help.contentItem, 0, link.height).y - help.contentItem.height;
        if (below > 0)
            help.scrollBy(below + link.height);
        mouseClick(link);
        compare(unfolded(), [block, ctrl]);
        compare(help.current, block);
        compare(help.shownSection, block);
        compare(help.jumps.length, 1);
        // A key's row, in a section that's unfolded already.
        help.follow("ctrl-o");
        compare(unfolded(), [block, ctrl]);
        compare(help.current, ctrl);
        compare(help.shownRow, help.sections[ctrl].rows.findIndex(r => r[0] === "`Ctrl-O`"));
        compare(help.jumps.length, 2);
        keys("<C-o>");
        compare(help.current, block);
        compare(unfolded(), [block, ctrl]);
        keys("<C-o>");
        compare(help.current, ctrl);
        compare(unfolded(), [ctrl]);
        compare(help.jumps.length, 0);
        keys("<C-o>");
        compare(unfolded(), [ctrl]);
        // One to nothing stays.
        help.follow("no such topic");
        compare(help.jumps.length, 0);
        // :h again starts over.
        help.follow("block");
        verify(help.show("set"));
        compare(help.jumps.length, 0);
        // From a list (About), the help takes its place.
        help.showPlain("About", { title: "", intro: "`:h` shows the help.", rows: [] });
        verify(!help.folds);
        tryVerify(() => (link = helpLinks(help.contentItem).find(l => l.topic === "")) !== undefined);
        waitForRendering(help.contentItem);
        mouseClick(link);
        verify(help.folds);
        compare(unfolded(), []);
        help.close();
        tryCompare(help, "opened", false);

        // In a question, in the help's window.
        helpRequests.clear();
        confirm.ask("Apply them (see `:h pick`)?", [{ text: "MOVE a -> b", needs: [] }], () => {});
        tryCompare(confirm, "opened", true);
        tryVerify(() => (link = helpLinks(confirm.contentItem).find(l => l.topic === "pick")) !== undefined);
        waitForRendering(confirm.contentItem);
        mouseClick(link);
        compare(helpRequests.count, 1);
        compare(helpRequests.signalArguments[0][0], "pick");
        verify(confirm.opened);
        confirm.answer("cancel");
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
        shows("sort", "Options (:set)", "`sort`");
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
        // The list of changes' keys, last, so vim's come first.
        shows("pick", "Picking changes");
        shows("D", "Picking changes", "`d`  `D`");
        shows("u", "The listing", "`u`");
        shows("d", "Marked lines", "`d`  `y`");
        shows("Y", "Other keys", "`Y`");
        // The help's own fold keys, with the help's other keys.
        shows("zR", "Commands", "`zR`  `zM`");
        shows("za", "Keys starting with z", "`za`  `zo`  `zc`");
        verify(!help.show("nothing"));
        help.close();
        tryCompare(help, "opened", false);
    }

    // The help's sections are folded: :h unfolds only its topic's, keys
    // and a search the cursor's.
    function test_helpFolds() {
        const section = title => help.sections.findIndex(s => s.title === title);
        const unfolded = () => help.sections.map((s, i) => i).filter(i => help.isOpen(i));
        verify(help.show(""));
        tryCompare(help, "opened", true);
        verify(help.folds);
        compare(unfolded(), []);
        compare(help.current, 0);
        // A topic's section, with the parts after it, and a part's key.
        const set = section("Options (:set)");
        verify(help.show("set"));
        compare(unfolded(), [set, set + 1, set + 2, set + 3]);
        compare(help.current, set);
        verify(help.show("fs-=2"));
        compare(help.shownSection, set + 2);
        compare(unfolded(), [set, set + 1, set + 2, set + 3]);
        compare(help.current, set);
        const surround = section("Surround");
        verify(help.show("ys"));
        compare(unfolded(), [surround]);

        // j and k move over the titles, past the parts.
        help.show("");
        keys("j");
        compare(help.current, 1);
        keys("kk");
        compare(help.current, 0);
        help.current = set;
        keys("j");
        compare(help.current, set + 4);
        keys("k");
        compare(help.current, set);
        // The keys that fold and unfold the cursor's.
        for (const [key, open] of [["<CR>", true], ["<CR>", false], ["<Tab>", true], ["<Tab>", false],
                [" ", true], [" ", false], ["l", true],
                ["l", true], ["h", false], ["h", false], ["za", true], ["za", false], ["zo", true], ["zc", false],
                ["<Right>", true], ["<Left>", false]]) {
            keys(key);
            compare(help.isOpen(set), open, key);
            compare(unfolded().length, open ? 4 : 0, key);
        }
        keys("zR");
        compare(unfolded().length, help.sections.length);
        keys("zM");
        compare(unfolded(), []);
        verify(help.opened);
        // Through an unfolded one's text first, by scrolling.
        help.show("");
        keys("l");
        compare(unfolded(), [0]);
        tryVerify(() => help.span(0).bottom > 1000);
        const scrollY = () => findChild(help.contentItem, "helpScroller").contentY;
        compare(scrollY(), 0);
        keys("jj");
        compare(help.current, 0);
        verify(scrollY() > 0);
        keys("kk");
        compare(scrollY(), 0);
        compare(help.current, 0);
        // G and g go to the last and the first.
        keys("G");
        compare(help.current, help.sections.length - 1);
        keys("g");
        compare(help.current, 0);
        keys("h");

        // A search unfolds the section it goes to, as it's typed, and Esc
        // folds it again.
        keys("/vim-surround");
        compare(unfolded(), [surround]);
        compare(help.current, surround);
        keys("<Esc>");
        compare(unfolded(), []);
        compare(help.current, 0);
        keys("/vim-surround<CR>");
        compare(unfolded(), [surround]);
        compare(help.current, surround);
        compare(help.matchIndex, 0);
        keys("n");
        compare(help.matchIndex, 1);
        // A click on a title folds or unfolds its section.
        keys("<Esc>");
        help.toggle(set);
        compare(unfolded(), [set, set + 1, set + 2, set + 3, surround]);
        compare(help.current, set);
        keys("q");
        tryCompare(help, "opened", false);

        // A list has no folds, and Enter closes it.
        help.showList("Test", [["a", "one"]], 4);
        tryCompare(help, "opened", true);
        verify(!help.folds);
        verify(help.isOpen(0));
        keys("<CR>");
        tryCompare(help, "opened", false);
        // as it was, for the other tests
        help.lastPattern = "";
        help.searchHistory = [];
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
        // A row each, the rows apart, as one takes two lines of text.
        compare(confirm.rowCount, 4);
        verify(confirm.spaced);
        compare(confirm.textLines, 5);
        compare(confirm.rowParts(confirm.picks.items[0]).map(part => part.rest), ["A", "step"]);
        // Copy gives them all, or the rows v selected.
        compare(confirm.copyText(), "A\nstep\n\nB\n\nC\n\nD");
        confirm.picks.row = 2;
        confirm.picks.anchor = 1;
        compare(confirm.copyText(), "B\n\nC");
        confirm.picks.anchor = -1;
        confirm.picks.row = 0;
        // A click on a row is Space on it.
        confirm.picks.clickRow(2);
        compare(confirm.picks.picked, [true, false, true, false]);
        compare(confirm.picks.row, 2);
        verify(confirm.picks.rowShown);
        confirm.picks.clickRow(2);
        compare(confirm.picks.picked, [true, false, false, false]);

        // Picking one picks what it needs, and leaving one out leaves out
        // what needs it; one that can't be picked stays out.
        confirm.picks.toggle(1);
        compare(confirm.picks.picked, [true, false, false, false]);
        confirm.picks.toggle(3);
        compare(confirm.picks.picked, [true, false, true, true]);
        confirm.picks.toggle(0);
        compare(confirm.picks.picked, [false, false, false, false]);
        confirm.picks.pickAll();
        compare(confirm.picks.picked, [true, false, true, true]);
        confirm.picks.pickAll();
        compare(confirm.picks.picked, [false, false, false, false]);
        // Yes does nothing with none picked.
        verify(!confirm.canAnswer("yes"));
        confirm.answer("yes");
        compare(chosen, null);
        verify(confirm.opened);

        confirm.picks.toggle(2);
        confirm.answer("yes");
        compare(chosen, [0, 2]);
        verify(!confirm.opened);
    }

    // A question can name No Cancel, when No has nothing to do (a list of
    // changes to pick from, where No would read as leaving them out).
    function test_confirmCancel() {
        let chosen = null;
        confirm.ask("Apply?", [{ text: "A", needs: [] }], picked => chosen = picked, null, null, { cancel: true });
        tryCompare(confirm, "opened", true);
        compare(confirm.choices.map(c => c.label), ["Yes", "Cancel"]);
        compare(confirm.choices.map(c => c.keys), ["y", "c"]);
        keyClick(Qt.Key_C);
        verify(!confirm.opened);
        compare(chosen, null);
        // With something for No to do, it's No and Cancel.
        confirm.ask("Quit?", "", () => {}, () => {}, null, { cancel: true });
        tryCompare(confirm, "opened", true);
        compare(confirm.choices.map(c => c.answer), ["yes", "no", "cancel"]);
        keyClick(Qt.Key_Escape);
        verify(!confirm.opened);
        // And without the option, No alone.
        confirm.ask("Undo?", "", () => {});
        tryCompare(confirm, "opened", true);
        compare(confirm.choices.map(c => c.label), ["Yes", "No"]);
        keyClick(Qt.Key_Escape);
    }

    // Yes and No are named by what they do, if the question says, with the
    // same keys.
    function test_confirmLabels() {
        let saved = false;
        confirm.ask("Save?", "", () => saved = true, () => {}, null, { yes: "Save", no: "Don't Save" });
        tryCompare(confirm, "opened", true);
        compare(confirm.choices.map(c => c.label), ["Save", "Don't Save", "Cancel"]);
        compare(confirm.choices.map(c => c.keys), ["y", "n", "c"]);
        keyClick(Qt.Key_Y);
        verify(saved);
        // The one that isn't Yes too, or it's Cancel.
        confirm.ask("Delete?", "", () => {}, null, null, { yes: "Delete", no: "Keep" });
        compare(confirm.choices.map(c => c.label), ["Delete", "Keep"]);
        confirm.ask("Delete?", "", () => {}, null, null, { yes: "Delete", cancel: true });
        compare(confirm.choices.map(c => c.label), ["Delete", "Cancel"]);
        // And the next question has its own.
        confirm.ask("Undo?", "", () => {});
        compare(confirm.choices.map(c => c.label), ["Yes", "No"]);
        keyClick(Qt.Key_Escape);
    }

    // Yes is the button Enter answers, whatever is pressed: h, l, Tab and
    // the arrows do nothing in a list without groups.
    function test_confirmButtons() {
        let chosen = null;
        const lines = ["A", "B"].map(text => ({ text: text, needs: [] }));
        confirm.ask("Apply?", lines, picked => chosen = picked, null, null, { cancel: true });
        tryCompare(confirm, "opened", true);
        for (const key of [Qt.Key_L, Qt.Key_H, Qt.Key_Tab, Qt.Key_Left, Qt.Key_Right])
            keyClick(key);
        keyClick(Qt.Key_Backtab, Qt.ShiftModifier);
        verify(confirm.opened);
        verify(!confirm.picks.rowShown);
        compare(confirm.picks.inside, -1);
        // Select All's button leaves the question open, and with none
        // picked Enter does nothing.
        confirm.answer("all");
        compare(confirm.picks.picked, [false, false]);
        keyClick(Qt.Key_Return);
        verify(confirm.opened);
        confirm.answer("all");
        keyClick(Qt.Key_Return);
        compare(chosen, [0, 1]);
        verify(!confirm.opened);
        // Without a list too.
        let saved = false;
        confirm.ask("Save?", "", () => saved = true, () => {});
        tryCompare(confirm, "opened", true);
        keyClick(Qt.Key_L);
        keyClick(Qt.Key_Tab);
        keyClick(Qt.Key_Return);
        verify(saved);
    }

    // A question that has Yes take the current row while none is picked
    // (the registers): Enter and y do what Y does, and with some picked,
    // those. Its lines are cut off, not wrapped.
    function test_confirmCurrent() {
        let chosen = null;
        const lines = () => ["A", "B", "C"].map(text => ({ text: text, needs: [], picked: false }));
        const ask = options => {
            chosen = null;
            confirm.ask("Paste?", lines(), picked => chosen = picked, null, null,
                Object.assign({ cancel: true, showRow: true, current: true, cut: true }, options));
            tryCompare(confirm, "opened", true);
        };
        ask();
        verify(confirm.cutLines);
        verify(confirm.canAnswer("yes"));
        keyClick(Qt.Key_J);
        keyClick(Qt.Key_Return);
        compare(chosen, [1]);
        verify(!confirm.opened);
        // The rows v selected.
        ask();
        keyClick(Qt.Key_V);
        keyClick(Qt.Key_J);
        keyClick(Qt.Key_Y);
        compare(chosen, [0, 1]);
        // The picked ones, wherever the cursor is.
        ask();
        keyClick(Qt.Key_G, Qt.ShiftModifier);
        keyClick(Qt.Key_Space);
        keyClick(Qt.Key_G);
        confirm.answer("yes");
        compare(chosen, [2]);
        // With the cursor not shown yet, the first Enter only shows it.
        ask({ showRow: false });
        keyClick(Qt.Key_Return);
        verify(confirm.opened);
        verify(confirm.picks.rowShown);
        keyClick(Qt.Key_Return);
        compare(chosen, [0]);
        // The next question is as before: Yes is off with none picked.
        confirm.ask("Apply?", lines(), picked => chosen = picked, null, null, { cancel: true, showRow: true });
        tryCompare(confirm, "opened", true);
        verify(!confirm.cutLines);
        verify(!confirm.canAnswer("yes"));
        keyClick(Qt.Key_Return);
        verify(confirm.opened);
        keyClick(Qt.Key_Escape);
    }

    // Lines in groups: a heading over each one's lines, whose box is all
    // of theirs. The cursor is on all of a group, and j and k go from one
    // to the next, until l (or Tab) goes into it, where it's on a line of
    // it, and h (or Tab) goes out again. One that's closed shows some of
    // its lines, the picked ones first, then a row for the others, and
    // what its lines are after its heading, until the cursor goes into it.
    function test_confirmGroups() {
        const line = (text, group, more) => Object.assign({ text: text, needs: [], group: group, picked: false }, more);
        const lines = [
            line("A", 0), line("B", 0, { needs: [0] }),
            line("C", 1, { blocked: "gone" }), line("D", 1, { needs: [1] }), line("E", 1), line("F", 1), line("G", 1),
            line("MOVE h", 2), line("MOVE i", 2), line("TRASH j", 2), line("MOVE k", 2), line("MOVE l", 2),
            line("TRASH m", 2)
        ];
        const groups = [
            { key: "1", text: "one", note: "2 <changes>" },
            { key: "2", text: "two" },
            { key: "3", text: "three", open: false, note: "6 changes" }
        ];
        const options = { groups: groups, keywords: { MOVE: "rename", TRASH: "delete" } };
        const shown = () => confirm.picks.rows.map(at => at.group !== undefined ? "g" + at.group
            : at.more !== undefined ? "m" + at.more : at.item);
        const pickedLines = () => confirm.picks.picked.map((p, i) => p ? i : -1).filter(i => i >= 0);
        let chosen = null;
        confirm.ask("Undo?", lines, picked => chosen = picked, null, null, Object.assign({ showRow: true }, options));
        tryCompare(confirm, "opened", true);
        // The third one shows its first lines, and a row for the others;
        // the others say nothing of closing.
        compare(shown(), ["g0", 0, 1, "g1", 2, 3, 4, 5, 6, "g2", 7, 8, 9, "m2"]);
        compare(confirm.rowCount, 14);
        compare([0, 1, 2].map(g => confirm.picks.canClose(g)), [false, false, true]);
        compare(confirm.moreText(2), "… 3 more");
        compare(confirm.copyText(), "one\n  A\n  B\ntwo\n  C\n  D\n  E\n  F\n  G\nthree\n  MOVE h\n  MOVE i\n"
            + "  TRASH j\n  MOVE k\n  MOVE l\n  TRASH m");
        // After a closed one's heading, how many of its lines are what,
        // most first; else its note.
        compare(confirm.groupKinds[2], [{ word: "MOVE", count: 4 }, { word: "TRASH", count: 2 }]);
        compare(confirm.groupKinds[0], []);
        compare(confirm.groupNote(2), "4 <font color=\"" + theme.changeColor("rename") + "\">MOVE</font> · 2 <font color=\""
            + theme.changeColor("delete") + "\">TRASH</font>");
        compare(confirm.groupNote(0), "2 &lt;changes>");
        compare(confirm.groupNote(1), "");

        // The cursor is on all of a group, which Space picks, and j and k
        // go to the next one, g and G to the first and last.
        compare(confirm.picks.cursorRows, [0, 2]);
        keyClick(Qt.Key_Space);
        compare(pickedLines(), [0, 1]);
        compare(confirm.picks.groupPicks(0), 2);
        keyClick(Qt.Key_J);
        compare(confirm.picks.row, 3);
        compare(confirm.picks.cursorRows, [3, 8]);
        keyClick(Qt.Key_J);
        keyClick(Qt.Key_J);
        compare(confirm.picks.cursorRows, [9, 13]);
        keyClick(Qt.Key_G);
        compare(confirm.picks.row, 0);
        keyClick(Qt.Key_G, Qt.ShiftModifier);
        compare(confirm.picks.row, 9);
        keyClick(Qt.Key_K);
        keyClick(Qt.Key_K);
        keyClick(Qt.Key_K);
        compare(confirm.picks.row, 0);

        // l goes into it, on its first line, and j and k stay in it.
        keyClick(Qt.Key_L);
        compare(confirm.picks.inside, 0);
        compare(confirm.picks.cursorRows, [1, 1]);
        keyClick(Qt.Key_K);
        compare(confirm.picks.row, 1);
        keyClick(Qt.Key_J);
        keyClick(Qt.Key_J);
        compare(confirm.picks.row, 2);
        keyClick(Qt.Key_Space);
        compare(pickedLines(), [0]);
        keyClick(Qt.Key_G);
        compare(confirm.picks.row, 1);
        keyClick(Qt.Key_G, Qt.ShiftModifier);
        compare(confirm.picks.row, 2);
        // h goes out, back on all of it; Tab does either.
        keyClick(Qt.Key_L);
        compare(confirm.picks.inside, 0);
        keyClick(Qt.Key_H);
        compare(confirm.picks.inside, -1);
        compare(confirm.picks.cursorRows, [0, 2]);
        compare(confirm.picks.groupPicks(0), 1);
        keyClick(Qt.Key_H);
        compare(confirm.picks.row, 0);
        keyClick(Qt.Key_Tab);
        compare([confirm.picks.inside, confirm.picks.row], [0, 1]);
        keyClick(Qt.Key_Tab);
        compare([confirm.picks.inside, confirm.picks.row], [-1, 0]);
        keyClick(Qt.Key_Right);
        compare(confirm.picks.inside, 0);
        keyClick(Qt.Key_Left);
        compare(confirm.picks.inside, -1);

        // Going into a closed one shows all its lines, and out of it only
        // some again: the picked ones first.
        keyClick(Qt.Key_G, Qt.ShiftModifier);
        keyClick(Qt.Key_L);
        compare(confirm.picks.inside, 2);
        compare(shown().slice(9), ["g2", 7, 8, 9, 10, 11, 12]);
        compare(confirm.picks.row, 10);
        compare(confirm.groupNote(2), "6 changes");
        keyClick(Qt.Key_G, Qt.ShiftModifier);
        compare(confirm.picks.row, 15);
        keyClick(Qt.Key_Space);
        keyClick(Qt.Key_K);
        keyClick(Qt.Key_K);
        keyClick(Qt.Key_Space);
        compare(pickedLines(), [0, 10, 12]);
        keyClick(Qt.Key_H);
        compare(shown().slice(9), ["g2", 7, 10, 12, "m2"]);
        compare(confirm.picks.row, 9);
        compare(confirm.picks.cursorRows, [9, 13]);
        compare(confirm.groupNote(2).indexOf("4 <font"), 0);
        // Picked from its heading, they're its first again.
        keyClick(Qt.Key_Space);
        compare(pickedLines(), [0, 7, 8, 9, 10, 11, 12]);
        compare(shown().slice(9), ["g2", 7, 8, 9, "m2"]);
        keyClick(Qt.Key_Space);
        compare(pickedLines(), [0]);

        // v selects groups, which Space picks: all their lines that Yes can
        // do, with what they need.
        keyClick(Qt.Key_K);
        compare(confirm.picks.row, 3);
        keyClick(Qt.Key_V);
        keyClick(Qt.Key_J);
        compare(confirm.picks.selectedRows, [3, 13]);
        keyClick(Qt.Key_X);
        compare(pickedLines(), [0, 1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
        compare(confirm.picks.anchor, -1);
        verify(!confirm.picks.groupBlocked(1));

        // Asked again, the cursor is in the group it was in, on its line.
        keyClick(Qt.Key_K);
        keyClick(Qt.Key_L);
        keyClick(Qt.Key_J);
        compare([confirm.picks.inside, confirm.picks.row], [1, 5]);
        const place = confirm.place();
        confirm.ask("Sure?", "A\nB", () => {});
        compare(confirm.picks.inside, -1);
        confirm.ask("Undo?", lines, picked => chosen = picked, null, null, Object.assign({ again: place }, options));
        compare([confirm.picks.inside, confirm.picks.row], [1, 5]);
        verify(confirm.picks.rowShown);
        compare(confirm.picks.pickedCount, 12);
        // Y on a group is Yes with its lines, shown or not.
        keyClick(Qt.Key_H);
        keyClick(Qt.Key_J);
        compare(confirm.picks.row, 9);
        keyClick(Qt.Key_Y, Qt.ShiftModifier);
        compare(chosen, [7, 8, 9, 10, 11, 12]);
        verify(!confirm.opened);

        // A click on the row for a closed group's other lines goes into
        // it; one on a line or a heading picks it, wherever the cursor is,
        // which goes there only in its own group, or among the groups.
        confirm.ask("Undo?", lines, () => {}, null, null, options);
        tryCompare(confirm, "opened", true);
        compare(confirm.picks.inside, -1);
        confirm.picks.clickRow(13);
        compare([confirm.picks.inside, confirm.picks.row], [2, 10]);
        compare(shown().length, 16);
        confirm.picks.clickRow(0);
        compare(pickedLines(), [0, 1]);
        compare([confirm.picks.inside, confirm.picks.row], [2, 10]);
        confirm.picks.clickRow(12);
        compare(pickedLines(), [0, 1, 9]);
        compare(confirm.picks.row, 12);
        keyClick(Qt.Key_Tab);
        compare([confirm.picks.inside, confirm.picks.row], [-1, 9]);
        compare(shown().slice(9), ["g2", 7, 8, 9, "m2"]);
        confirm.picks.clickRow(5);
        compare(pickedLines(), [0, 1, 3, 9]);
        compare(confirm.picks.row, 3);
        keyClick(Qt.Key_Escape);
        verify(!confirm.opened);
    }

    // A list to pick from moves by pages: Ctrl-D and Ctrl-U half a page,
    // Ctrl-F and Ctrl-B (PageDown and PageUp) a page, of the rows the list
    // has room for, a row at least; the first only shows the cursor, as
    // j does. With groups, to the group that far, the next one at least,
    // or inside one, as far as its first and last line. A list of text
    // scrolls with them instead.
    function test_confirmPages() {
        const ctrl = isMac ? Qt.MetaModifier : Qt.ControlModifier;
        const lines = [];
        for (let i = 0; i < 400; i++)
            lines.push({ text: "MOVE a" + i + " -> b" + i, needs: [] });
        confirm.ask("Apply?", lines, () => {}, null, null, { cancel: true });
        tryCompare(confirm, "opened", true);
        const picks = confirm.picks;
        // A page is the rows the list has room for; ten from here on,
        // whatever room the box has once it's laid out.
        tryVerify(() => picks.pageRows > 3);
        picks.pageRows = 10;
        keyClick(Qt.Key_D, ctrl);
        verify(picks.rowShown);
        compare(picks.row, 0);
        keyClick(Qt.Key_D, ctrl);
        compare(picks.row, 5);
        keyClick(Qt.Key_F, ctrl);
        compare(picks.row, 15);
        keyClick(Qt.Key_PageDown);
        compare(picks.row, 25);
        keyClick(Qt.Key_U, ctrl);
        compare(picks.row, 20);
        keyClick(Qt.Key_B, ctrl);
        compare(picks.row, 10);
        keyClick(Qt.Key_PageUp);
        compare(picks.row, 0);
        keyClick(Qt.Key_U, ctrl);
        compare(picks.row, 0);
        keyClick(Qt.Key_End);
        compare(picks.row, 399);
        keyClick(Qt.Key_F, ctrl);
        compare(picks.row, 399);
        keyClick(Qt.Key_Home);
        compare(picks.row, 0);
        // Ctrl-E and Ctrl-Y scroll the rows, with the cursor where it is.
        picks.scroll(2);
        tryVerify(() => confirm.place().y > 0);
        picks.scroll(-2);
        tryVerify(() => confirm.place().y === 0);
        keyClick(Qt.Key_E, ctrl);
        tryVerify(() => confirm.place().y > 0);
        compare(picks.row, 0);
        // Not with another modifier, nor another key with Ctrl.
        keyClick(Qt.Key_D, ctrl | Qt.ShiftModifier);
        keyClick(Qt.Key_J, ctrl);
        compare(picks.row, 0);
        keyClick(Qt.Key_Escape);
        tryCompare(confirm, "opened", false);

        // Groups: each a heading and two lines, so three rows.
        const groups = [], items = [];
        for (let g = 0; g < 30; g++) {
            groups.push({ key: "g" + g, text: "group " + g });
            for (let i = 0; i < 2; i++)
                items.push({ text: "MOVE a" + g + i, needs: [], group: g });
        }
        confirm.ask("Undo?", items, () => {}, null, null, { cancel: true, groups: groups, showRow: true });
        tryCompare(confirm, "opened", true);
        // To the heading of the group the row a page down is in.
        keyClick(Qt.Key_F, ctrl);
        compare(picks.row, 9);
        verify(picks.rows[picks.row].group !== undefined);
        keyClick(Qt.Key_B, ctrl);
        compare(picks.row, 0);
        // A group at least, however short the page is.
        picks.movePage(0.01);
        compare(picks.row, 3);
        picks.movePage(-0.01);
        compare(picks.row, 0);
        // Inside a group, it stays in it.
        keyClick(Qt.Key_L);
        compare(picks.row, 1);
        keyClick(Qt.Key_F, ctrl);
        compare(picks.row, 2);
        keyClick(Qt.Key_B, ctrl);
        compare(picks.row, 1);
        keyClick(Qt.Key_Escape);
        tryCompare(confirm, "opened", false);

        // A list of text scrolls.
        confirm.ask("Quit?", lines.map(line => line.text).join("\n"), () => {});
        tryCompare(confirm, "opened", true);
        tryVerify(() => confirm.place().y === 0);
        keyClick(Qt.Key_D, ctrl);
        const y = confirm.place().y;
        verify(y > 0);
        keyClick(Qt.Key_PageDown);
        verify(confirm.place().y > y);
        keyClick(Qt.Key_Home);
        compare(confirm.place().y, 0);
        keyClick(Qt.Key_Escape);
        tryCompare(confirm, "opened", false);
    }

    // / searches a list to pick from: only the lines with every word typed
    // show, as it's typed, whatever their case unless one is uppercase.
    // Enter keeps it, Esc puts the one before back, and Esc in the list
    // shows all of it again. Picks stay, shown or not, and Select All is
    // of the lines that show.
    function test_confirmSearch() {
        const lines = () => ["TRASH bob", "MOVE a -> Bob2", "CREATE alice", "TRASH docs/bob  & <x>"]
            .map(text => ({ text: text, needs: [], picked: false }));
        const shown = () => confirm.picks.rows.map(at => at.item);
        let chosen = null;
        confirm.ask("Apply?", lines(), picked => chosen = picked, null, null, { keywords: { TRASH: "delete" } });
        tryCompare(confirm, "opened", true);
        compare(confirm.withMarks("TRASH bob"), "");
        keyClick(Qt.Key_J);
        keyClick(Qt.Key_J);
        keyClick(Qt.Key_J);
        compare(confirm.picks.row, 2);
        keyClick(Qt.Key_Slash);
        verify(confirm.picks.filtering);
        // The keys are the search's: b isn't a key of the list's.
        keyClick(Qt.Key_B, Qt.NoModifier);
        keyClick(Qt.Key_O);
        compare(confirm.picks.filter, "bo");
        compare(shown(), [0, 1, 3]);
        compare(confirm.picks.shownCount, 3);
        // The cursor's line went, so it's on the first.
        compare(confirm.picks.row, 0);
        keyClick(Qt.Key_B);
        keyClick(Qt.Key_Space);
        keyClick(Qt.Key_T);
        compare(confirm.picks.filter, "bob t");
        compare(shown(), [0, 3]);
        // What matched is underlined, as styled text.
        const mark = text => "<u><font color=\"" + confirm.markColor + "\">" + text + "</font></u>";
        compare(confirm.withMarks("TRASH  "), mark("T") + "RASH&nbsp; ");
        compare(confirm.withMarks("docs/bob  & <x>"), "docs/" + mark("bob") + "&nbsp; &amp; &lt;x&gt;");
        compare(confirm.withMarks("alice"), "");
        // Down and Up move the cursor meanwhile, and Enter keeps the
        // search, with the cursor shown.
        keyClick(Qt.Key_Down);
        compare(confirm.picks.row, 1);
        keyClick(Qt.Key_Return);
        verify(!confirm.picks.filtering);
        verify(confirm.opened);
        compare(confirm.picks.filter, "bob t");
        verify(confirm.picks.rowShown);
        // Space picks the line the cursor is on, the last one's.
        keyClick(Qt.Key_Space);
        compare(confirm.picks.picked, [false, false, false, true]);
        keyClick(Qt.Key_G);
        compare(confirm.picks.row, 0);
        keyClick(Qt.Key_G, Qt.ShiftModifier);
        compare(confirm.picks.row, 1);
        // a picks those that show, or none of them.
        compare(confirm.picks.allPicked, false);
        keyClick(Qt.Key_A);
        compare(confirm.picks.picked, [true, false, false, true]);
        compare(confirm.picks.allPicked, true);
        compare(confirm.copyText(), "TRASH bob\nTRASH docs/bob  & <x>");

        // Another search starts from this one, selected, so typing
        // replaces it; an uppercase letter has the case count.
        keyClick(Qt.Key_Slash);
        keyClick("B");
        compare(confirm.picks.filter, "B");
        compare(shown(), [1]);
        compare(confirm.picks.hiddenPicked, 2);
        // Esc puts the one before back.
        keyClick(Qt.Key_Escape);
        verify(confirm.opened);
        verify(!confirm.picks.filtering);
        compare(confirm.picks.filter, "bob t");
        compare(shown(), [0, 3]);
        // No line has it: none shows, and Enter picks nothing.
        keyClick(Qt.Key_Slash);
        keyClick(Qt.Key_Z);
        compare(shown(), []);
        compare(confirm.picks.shownCount, 0);
        keyClick(Qt.Key_Return);
        keyClick(Qt.Key_Space);
        keyClick(Qt.Key_J);
        keyClick(Qt.Key_G, Qt.ShiftModifier);
        compare(confirm.picks.picked, [true, false, false, true]);
        // Emptied, it's no search any more; Backspace then leaves it.
        keyClick(Qt.Key_Slash);
        keyClick(Qt.Key_Backspace);
        compare(shown(), [0, 1, 2, 3]);
        keyClick(Qt.Key_Backspace);
        verify(!confirm.picks.filtering);
        compare(confirm.picks.filter, "");

        // Asked again, it's searched for still, the current line the
        // next one left that shows.
        keyClick(Qt.Key_Slash);
        keyClick(Qt.Key_B);
        keyClick(Qt.Key_Return);
        keyClick(Qt.Key_J);
        compare(shown(), [0, 1, 3]);
        compare(confirm.picks.row, 1);
        confirm.ask("Apply?", lines().filter((line, i) => i !== 1), () => {}, null, null, { again: true });
        compare(confirm.picks.filter, "b");
        compare(shown(), [0, 2]);
        compare(confirm.picks.row, 1);
        compare(confirm.picks.picked, [true, false, true]);
        // Esc in the list shows all of it again, and only then cancels.
        keyClick(Qt.Key_Escape);
        verify(confirm.opened);
        compare(confirm.picks.filter, "");
        compare(shown(), [0, 1, 2]);
        compare(confirm.picks.row, 2);
        // Yes takes the picked lines, shown or not.
        keyClick(Qt.Key_Slash);
        keyClick(Qt.Key_D);
        keyClick(Qt.Key_Return);
        compare(shown(), [2]);
        confirm.ask("Apply?", lines(), picked => chosen = picked, null, null, { again: true });
        keyClick(Qt.Key_Y);
        compare(chosen, [0, 3]);
        verify(!confirm.opened);
        // Not if no line has it any more, nor in a new question, nor in a
        // list that's not one to pick from, where / is no key.
        confirm.ask("Apply?", lines().slice(0, 3), () => {}, null, null, { again: true });
        compare(confirm.picks.filter, "");
        confirm.picks.setFilter("bob");
        confirm.ask("Apply?", lines(), () => {});
        compare(confirm.picks.filter, "");
        confirm.ask("Sure?", "A\nB", () => {});
        keyClick(Qt.Key_Slash);
        verify(!confirm.picks.filtering);
        keyClick(Qt.Key_Escape);
        verify(!confirm.opened);
    }

    // Searching a list in groups: a group shows the lines that have it,
    // or all of them if its heading does, and one with none isn't shown.
    // Its heading's box, Space on it and what's after it are of those.
    function test_confirmSearchGroups() {
        const line = (text, group, more) => Object.assign({ text: text, needs: [], group: group, picked: false }, more);
        const lines = [
            line("TRASH bob", 0), line("MOVE a -> b", 0),
            line("CREATE c", 1),
            line("MOVE bob1", 2), line("MOVE x", 2), line("MOVE bob2", 2), line("TRASH bob3", 2), line("MOVE bob4", 2),
            line("MOVE bob5", 2), line("MOVE y", 2, { needs: [3] })
        ];
        const groups = [
            { key: "1", text: "now  ~/src" },
            { key: "2", text: "1 day ago  ~/docs" },
            { key: "3", text: "2 days ago  ~/src", open: false, note: "7 changes" }
        ];
        const options = { groups: groups, keywords: { MOVE: "rename", TRASH: "delete", CREATE: "create" }, showRow: true };
        const shown = () => confirm.picks.rows.map(at => at.group !== undefined ? "g" + at.group
            : at.more !== undefined ? "m" + at.more : at.item);
        const pickedLines = () => confirm.picks.picked.map((p, i) => p ? i : -1).filter(i => i >= 0);
        let chosen = null;
        confirm.ask("Undo?", lines, picked => chosen = picked, null, null, options);
        tryCompare(confirm, "opened", true);
        compare(shown(), ["g0", 0, 1, "g1", 2, "g2", 3, 4, 5, "m2"]);
        keyClick(Qt.Key_J);
        compare(confirm.picks.row, 3);

        confirm.picks.setFilter("bob");
        // The second group has none, so the cursor is on the first row;
        // the third is closed still, with its first lines that have it.
        compare(shown(), ["g0", 0, "g2", 3, 5, 6, "m2"]);
        compare(confirm.picks.row, 0);
        compare(confirm.moreText(2), "… 2 more");
        compare(confirm.groupKinds[2], [{ word: "MOVE", count: 4 }, { word: "TRASH", count: 1 }]);
        compare(confirm.copyText(), "now  ~/src\n  TRASH bob\n2 days ago  ~/src\n  MOVE bob1\n  MOVE bob2\n"
            + "  TRASH bob3\n  MOVE bob4\n  MOVE bob5");
        // j and G go by the groups that show.
        keyClick(Qt.Key_J);
        compare(confirm.picks.cursorRows, [2, 6]);
        keyClick(Qt.Key_J);
        compare(confirm.picks.row, 2);
        keyClick(Qt.Key_G);
        compare(confirm.picks.row, 0);
        keyClick(Qt.Key_G, Qt.ShiftModifier);
        compare(confirm.picks.row, 2);
        // Space on a heading picks its lines that show, and its box is
        // theirs.
        keyClick(Qt.Key_Space);
        compare(pickedLines(), [3, 5, 6, 7, 8]);
        compare(confirm.picks.groupPicks(2), 2);
        compare(confirm.picks.hiddenPicked, 0);
        // Going in shows all that have it; j stays in them.
        keyClick(Qt.Key_L);
        compare(shown(), ["g0", 0, "g2", 3, 5, 6, 7, 8]);
        keyClick(Qt.Key_G, Qt.ShiftModifier);
        compare(confirm.picks.row, 7);
        keyClick(Qt.Key_J);
        compare(confirm.picks.row, 7);
        // Leaving one out leaves out what needs it, shown or not.
        keyClick(Qt.Key_G);
        keyClick(Qt.Key_Space);
        compare(pickedLines(), [5, 6, 7, 8]);
        compare(confirm.picks.groupPicks(2), 1);

        // A word of the heading counts for all its lines: both words
        // must be in a line or its heading.
        confirm.picks.setFilter("src move");
        compare(confirm.picks.inside, 2);
        compare(shown(), ["g0", 1, "g2", 3, 4, 5, 7, 8, 9]);
        confirm.picks.setFilter("docs");
        compare(confirm.picks.inside, -1);
        compare(shown(), ["g1", 2]);
        compare(confirm.picks.row, 0);
        // a is of the lines that show.
        keyClick(Qt.Key_A);
        compare(pickedLines(), [2, 5, 6, 7, 8]);
        compare(confirm.picks.hiddenPicked, 4);
        // Y on a heading takes its lines that show.
        confirm.picks.setFilter("trash");
        compare(shown(), ["g0", 0, "g2", 6]);
        keyClick(Qt.Key_J);
        keyClick(Qt.Key_Y, Qt.ShiftModifier);
        compare(chosen, [6]);
        verify(!confirm.opened);
    }

    // Asked again with other lines (`again`), as if it never closed: those
    // still there keep their picks, and the current line stays on its line,
    // or goes to the next one left, still highlighted.
    function test_confirmAgain() {
        const lines = (texts, picked) => texts.map(text => ({ text: text, needs: [], picked: picked }));
        confirm.ask("Apply?", lines(["A", "B", "C", "D"], true), () => {}, null, null, { cancel: true });
        tryCompare(confirm, "opened", true);
        confirm.picks.toggle(1);
        confirm.picks.toggle(3);
        keyClick(Qt.Key_J); // shows the current line, the first
        keyClick(Qt.Key_J);
        keyClick(Qt.Key_J);
        compare(confirm.picks.row, 2);
        // C went, so the line after it (D) is the current one; E is new.
        confirm.ask("Apply?", lines(["B", "D", "E"], false), () => {}, null, null, { cancel: true, again: true });
        compare(confirm.picks.picked, [false, false, false]);
        compare(confirm.picks.row, 1);
        verify(confirm.picks.rowShown);
        // Its own line, if it's still there, and nothing after it: the last.
        confirm.picks.toggle(0);
        confirm.ask("Apply?", lines(["A", "B", "D"], true), () => {}, null, null, { again: true });
        compare(confirm.picks.picked, [true, true, false]);
        compare(confirm.picks.row, 2);
        confirm.ask("Apply?", lines(["A"], true), () => {}, null, null, { again: true });
        compare(confirm.picks.row, 0);
        // Without it, asked anew.
        keyClick(Qt.Key_Escape);
        confirm.ask("Apply?", lines(["A", "B"], true), () => {});
        tryCompare(confirm, "opened", true);
        compare(confirm.picks.picked, [true, true]);
        compare(confirm.picks.row, 0);
        verify(!confirm.picks.rowShown);
        keyClick(Qt.Key_Escape);
    }

    // v selects lines, which Space or x then picks all of, or leaves all
    // out if they're all picked, ending the selection; Esc ends it before
    // it cancels.
    function test_confirmSelectLines() {
        const lines = ["A", "B", "C", "D"].map(text => ({ text: text, needs: [], picked: false }));
        confirm.ask("Apply?", lines, () => {});
        tryCompare(confirm, "opened", true);
        keyClick(Qt.Key_V);
        verify(confirm.picks.rowShown);
        compare(confirm.picks.anchor, 0);
        keyClick(Qt.Key_J);
        keyClick(Qt.Key_J);
        keyClick(Qt.Key_Space);
        compare(confirm.picks.picked, [true, true, true, false]);
        compare(confirm.picks.anchor, -1);
        // All picked: all left out.
        keyClick(Qt.Key_V);
        keyClick(Qt.Key_K);
        keyClick(Qt.Key_X);
        compare(confirm.picks.picked, [true, false, false, false]);
        // One left out: all picked, upwards too.
        keyClick(Qt.Key_J);
        keyClick(Qt.Key_V);
        keyClick(Qt.Key_K);
        keyClick(Qt.Key_K);
        keyClick(Qt.Key_Space);
        compare(confirm.picks.picked, [true, true, true, false]);
        // G and g go to the last line and the first, also selecting.
        keyClick(Qt.Key_G, Qt.ShiftModifier);
        compare(confirm.picks.row, 3);
        keyClick(Qt.Key_V);
        keyClick(Qt.Key_G);
        compare(confirm.picks.row, 0);
        keyClick(Qt.Key_Space);
        compare(confirm.picks.picked, [true, true, true, true]);
        // v again ends it, as Esc does, which cancels only then.
        keyClick(Qt.Key_V);
        keyClick(Qt.Key_V);
        compare(confirm.picks.anchor, -1);
        keyClick(Qt.Key_V);
        keyClick(Qt.Key_Escape);
        compare(confirm.picks.anchor, -1);
        verify(confirm.opened);
        keyClick(Qt.Key_Escape);
        verify(!confirm.opened);
    }

    // u answers with the question's own action, if it has one; and asked
    // again with `row`, the current line is the one at that index.
    function test_confirmUndo() {
        let undone = null;
        const lines = ["A", "B", "C"].map(text => ({ text: text, needs: [] }));
        confirm.ask("Apply?", lines, () => {}, null, null, { undo: picked => undone = picked });
        tryCompare(confirm, "opened", true);
        keyClick(Qt.Key_Space);
        keyClick(Qt.Key_U);
        verify(!confirm.opened);
        compare(undone, [1, 2]);
        confirm.ask("Apply?", lines, () => {}, null, null, { again: true, row: 2 });
        tryCompare(confirm, "opened", true);
        compare(confirm.picks.row, 2);
        compare(confirm.picks.picked, [false, true, true]);
        confirm.ask("Apply?", lines, () => {}, null, null, { again: true, row: 9 });
        compare(confirm.picks.row, 2);
        // Without it, u does nothing.
        keyClick(Qt.Key_U);
        verify(confirm.opened);
        keyClick(Qt.Key_Escape);
    }

    // Shift and the button apart's key does what the button does, with the
    // current line, or the lines v selected, picked or not; the first only
    // shows the current line, as j does. And a question can be asked as it
    // was before another (`place`).
    function test_confirmExtraOnLines() {
        let chosen = null;
        const lines = [
            { text: "A", needs: [] },
            { text: "B", needs: [0] },
            { text: "C", needs: [1] },
            { text: "D", needs: [] }
        ];
        const extra = { label: "Discard", key: Qt.Key_D, action: picked => chosen = picked };
        confirm.ask("Apply?", lines, () => {}, null, null, { extra: extra });
        tryCompare(confirm, "opened", true);
        // Its key is on its button.
        compare(confirm.extraKeys, "d");
        keyClick(Qt.Key_D, Qt.ShiftModifier);
        verify(confirm.opened);
        verify(confirm.picks.rowShown);
        compare(chosen, null);
        // Left out, with what needs it, and still D's.
        keyClick(Qt.Key_Space);
        compare(confirm.picks.picked, [false, false, false, true]);
        keyClick(Qt.Key_D, Qt.ShiftModifier);
        compare(chosen, [0]);
        verify(!confirm.opened);
        compare(confirm.picks.withDependents([0]), [0, 1, 2]);
        compare(confirm.picks.withDependents([1, 3]), [1, 2, 3]);
        compare(confirm.picks.withNeeds([2]), [0, 1, 2]);
        compare(confirm.picks.withNeeds([0, 3]), [0, 3]);

        // Y is y with the current line, picked or not.
        let yes = null;
        confirm.ask("Apply?", lines, picked => yes = picked, null, null, { extra: extra, showRow: true });
        tryCompare(confirm, "opened", true);
        keyClick(Qt.Key_J);
        keyClick(Qt.Key_J);
        keyClick(Qt.Key_Space);
        keyClick(Qt.Key_Y, Qt.ShiftModifier);
        compare(yes, [2]);
        verify(!confirm.opened);
        // Not with a line Yes can't do.
        yes = null;
        confirm.ask("Undo?", [{ text: "A", needs: [] }, { text: "B", needs: [], blocked: true }], picked => yes = picked,
            null, null, { extra: extra, showRow: true });
        tryCompare(confirm, "opened", true);
        keyClick(Qt.Key_J);
        keyClick(Qt.Key_Y, Qt.ShiftModifier);
        compare(yes, null);
        verify(confirm.opened);
        keyClick(Qt.Key_K);
        keyClick(Qt.Key_Y, Qt.ShiftModifier);
        compare(yes, [0]);

        confirm.ask("Apply?", lines, () => {}, null, null, { extra: extra, showRow: true });
        tryCompare(confirm, "opened", true);
        keyClick(Qt.Key_J);
        keyClick(Qt.Key_V);
        keyClick(Qt.Key_J);
        keyClick(Qt.Key_D, Qt.ShiftModifier);
        compare(chosen, [1, 2]);

        confirm.ask("Apply?", lines, () => {}, null, null, { extra: extra, showRow: true });
        tryCompare(confirm, "opened", true);
        keyClick(Qt.Key_J);
        keyClick(Qt.Key_Space);
        compare(confirm.picks.picked, [true, false, false, true]);
        const place = confirm.place();
        confirm.ask("Sure?", "A\nB", () => {});
        confirm.ask("Apply?", lines, () => {}, null, null, { extra: extra, again: place });
        compare(confirm.picks.row, 1);
        verify(confirm.picks.rowShown);
        compare(confirm.picks.picked, [true, false, false, true]);
        keyClick(Qt.Key_Escape);
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
            { showRow: true, extra: { label: "Delete History", key: Qt.Key_D, action: picked => extra = picked } });
        tryCompare(confirm, "opened", true);
        verify(confirm.picks.rowShown);
        compare(confirm.picks.picked, [false, false, false]);
        compare(confirm.choices.map(c => c.answer), ["yes", "no"]);
        keyClick(Qt.Key_J);
        compare(confirm.picks.row, 1);
        keyClick(Qt.Key_D);
        compare(extra, null);
        verify(confirm.opened);
        keyClick(Qt.Key_Space);
        keyClick(Qt.Key_J);
        keyClick(Qt.Key_Space);
        compare(confirm.picks.picked, [false, true, true]);
        verify(confirm.picks.blockedPicked);
        verify(!confirm.canAnswer("yes"));
        keyClick(Qt.Key_Y);
        compare(chosen, null);
        verify(confirm.opened);
        // a picks only those Yes can do, which turns it on again.
        keyClick(Qt.Key_A);
        compare(confirm.picks.picked, [true, true, false]);
        verify(confirm.canAnswer("yes"));
        verify(confirm.picks.allPicked);
        keyClick(Qt.Key_Space);
        keyClick(Qt.Key_D);
        compare(extra, [0, 1, 2]);
        compare(chosen, null);
        verify(!confirm.opened);

        // Without them, as before: nor can that line be picked.
        confirm.ask("Undo?", lines, () => {});
        tryCompare(confirm, "opened", true);
        verify(!confirm.picks.rowShown);
        compare(confirm.extra, null);
        confirm.picks.toggle(2);
        compare(confirm.picks.picked, [false, false, false]);
        keyClick(Qt.Key_D);
        verify(confirm.opened);
        confirm.answer("cancel");
    }

    // A list to pick from has a ? button, which asks for the help on its
    // keys, as ? does once it's let go (the Shift it's typed with can go
    // first), and the question stays open; a list of text has neither.
    function test_confirmHelp() {
        helpRequests.clear();
        confirm.ask("Apply?", [{ text: "MOVE a -> b", needs: [] }, { text: "TRASH c", needs: [] }], () => {});
        tryCompare(confirm, "opened", true);
        compare(confirm.helpTopic, "pick");
        const button = findChild(confirm.contentItem, "helpButton");
        verify(button.visible);
        keyPress(Qt.Key_Question, Qt.ShiftModifier);
        keyRelease(Qt.Key_Shift);
        compare(helpRequests.count, 0);
        keyRelease(Qt.Key_Question);
        tryCompare(helpRequests, "count", 1);
        compare(helpRequests.signalArguments[0][0], "pick");
        // Held, it's asked for a moment later.
        keyPress(Qt.Key_Question, Qt.ShiftModifier);
        tryCompare(helpRequests, "count", 2);
        keyRelease(Qt.Key_Question, Qt.ShiftModifier);
        wait(0);
        compare(helpRequests.count, 2);
        mouseClick(button);
        compare(helpRequests.count, 3);
        verify(confirm.opened);
        compare(confirm.picks.pickedCount, 2);
        // Not while its search is typed, which takes the key.
        keyClick(Qt.Key_Slash);
        keyClick(Qt.Key_Question, Qt.ShiftModifier);
        wait(350);
        compare(helpRequests.count, 3);
        compare(confirm.picks.filter, "?");
        keyClick(Qt.Key_Escape);
        confirm.answer("cancel");
        confirm.ask("Quit?", "MOVE a -> b", () => {});
        tryCompare(confirm, "opened", true);
        verify(!button.visible);
        keyClick(Qt.Key_Question, Qt.ShiftModifier);
        wait(350);
        compare(helpRequests.count, 3);
        verify(confirm.opened);
        confirm.answer("cancel");
    }

    // The words lines start with get the color of the change they stand
    // for, with the spaces after them, only in the questions that say so;
    // and the line that says why a line can't be done is told apart.
    function test_confirmKeywords() {
        confirm.ask("Apply?", "MOVE   a -> b\n\nother c", () => {}, null, null, { keywords: { MOVE: "rename", TRASH: "delete" } });
        compare(confirm.lines, ["MOVE   a -> b", "", "other c"]);
        compare(confirm.rowCount, 3);
        compare(confirm.textLines, 2.5);
        compare(confirm.longest, 13);
        compare(confirm.helpTopic, "");
        compare(confirm.rowParts(confirm.lines[0]),
            [{ word: "MOVE   ", rest: "a -> b", color: theme.changeColor("rename"), error: false }]);
        compare(confirm.rowParts(confirm.lines[2]), [{ word: "", rest: "other c", color: "", error: false }]);
        compare(confirm.copyText(), "MOVE   a -> b\n\nother c");
        confirm.answer("cancel");
        confirm.ask("Delete it anyway?", "MOVE -> b\ntoString x", () => {});
        compare(confirm.rowParts(confirm.lines[0])[0].word, "");
        compare(confirm.rowParts(confirm.lines[1])[0].word, "");
        confirm.answer("cancel");
        const parts = confirm.rowParts({ text: "12:00\nTRASH a\nCan't be undone: `a` is gone", needs: [], blocked: "`a` is gone" });
        compare(parts.map(part => part.error), [false, false, true]);
        // What a line to pick from starts with (a time) in a color of its
        // own, with the spaces after it; only its first line.
        const led = confirm.rowParts({ text: "2 days ago  ~/src\n2 days", needs: [],
            lead: { length: 10, color: theme.ageColor("days") } });
        compare(led[0], { word: "2 days ago  ", rest: "~/src", color: theme.ageColor("days"), error: false });
        compare(led[1].word, "");
        compare(confirm.rowParts({ text: "just now", needs: [], lead: { length: 8, color: "red" } })[0],
            { word: "just now", rest: "", color: "red", error: false });
        // A lead of several parts, each in its color (a register's type
        // and name), the last with the spaces after it.
        const two = confirm.rowParts({ text: "c  \"a  x <y\n       z", needs: [],
            lead: [{ length: 3, color: "gray" }, { length: 2, color: "red" }] });
        compare([two[0].word, two[0].rest, two[0].color, two[1].word], ["c  \"a  ", "x <y", "red", ""]);
        compare(two[0].leads, [{ text: "c  ", color: "gray" }, { text: "\"a  ", color: "red" }]);
        compare(confirm.leadText(two[0]), "<font color=\"gray\">c&nbsp; </font><font color=\"red\">\"a&nbsp; </font>");
        compare(confirm.leadText(led[0]), "");
        // Each age has its color, the oldest the palest.
        const ages = ["today", "days", "weeks", "months", "years"].map(age => String(theme.ageColor(age)));
        compare(ages.filter((color, i) => ages.indexOf(color) === i).length, 5);
        compare(ages[3], String(theme.dim));
        compare(ages[4], String(theme.faint));
    }
}
