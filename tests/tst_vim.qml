import QtQuick
import QtQuick.Controls
import QtTest

import "../qml"

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
                entries.push({ at: text.length, icon: icon, text: "h" + ++n });
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

    // Types keys: characters, and names like <Esc>, <CR>, <C-v> (Ctrl) or
    // <D-c> (Cmd on macOS, Ctrl elsewhere).
    function keys(s) {
        const named = {
            "Esc": Qt.Key_Escape, "CR": Qt.Key_Return, "BS": Qt.Key_Backspace, "Del": Qt.Key_Delete,
            "Tab": Qt.Key_Tab, "Left": Qt.Key_Left, "Right": Qt.Key_Right, "Up": Qt.Key_Up, "Down": Qt.Key_Down
        };
        const ctrl = isMac ? Qt.MetaModifier : Qt.ControlModifier;
        for (const m of s.match(/<[^<>]+>|[\s\S]/g)) {
            if (m.length === 1 || m === "<>") {
                keyClick(m);
            } else {
                const name = m.slice(1, -1);
                if (named[name] !== undefined)
                    keyClick(named[name]);
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
        onCursorPositionChanged: vim.syncFromEditor()
        onSelectedTextChanged: vim.syncFromEditor()
        Keys.onPressed: event => {
            event.accepted = vim.handleKey(event);
        }
    }

    // As in the app: without a binding to it, a bug that hangs the app
    // while typing can go unnoticed.
    Label {
        y: 220
        text: vim.positionLabel()
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

    FindBar {
        id: findBar

        y: 240
        editor: editor
        vim: vim
        theme: theme
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

    function test_multipleCursors() {
        load("ab\ncd");
        vim.toggleCursor(3);
        compare(vim.cursors.length, 1);
        keys("iX<Esc>");
        compare(render(), "Xab\nXcd");
        compare(vim.cursors.length, 0);
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

    // ---- Hidden text ---------------------------------------------------------

    function test_hiddenAt() {
        load("M  a\nC  b");
        compare(render(), "<M:h1>  a\n<C:h2>  b");
        compare(vim.hiddenAt(0).text, "h1");
        compare(vim.hiddenAt(6).icon, chair);
        compare(vim.hiddenAt(1), null);
        compare(vim.revealed(editor.text, vim.hidden), "h1  a\nh2  b");
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

    // Other apps get the hidden text; Koil gets the icons back.
    function test_clipboard() {
        load("M  a");
        keys("\"+yy");
        compare(clipboard.text, "h1  a\n");
        compare(JSON.parse(clipboard.data).hidden, [{ at: 0, icon: mushroom, text: "h1" }]);
        keys("\"+p");
        compare(render(), "<M:h1>  a\n<M:h1>  a");
        keys("v<D-c>$<D-v>");
        compare(render(), "<M:h1>  a\n<M:h1>  <M:h1>a");
    }

    function test_invalidClipboardData() {
        load("x");
        clipboard.text = "y" + mushroom;
        clipboard.data = JSON.stringify({ text: "y" + mushroom, hidden: [{ at: 0, icon: mushroom, text: "no" }] });
        keys("\"+p");
        compare(render(), "xyM");
        clipboard.data = JSON.stringify({ text: "y" + mushroom, hidden: [{ at: 1, icon: "💩", text: "no" }] });
        keys("u\"+p");
        compare(render(), "xyM");
        clipboard.data = JSON.stringify({ text: "y" + mushroom, hidden: [{ at: 1, icon: mushroom, text: "ok" }] });
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
