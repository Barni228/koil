import QtQuick
import QtQuick.Controls
import QtTest

import "../qml"

// The Shortcuts window with the keys alone: Tab goes through all of it
// (which Qt's own Tab doesn't on macOS, unless Keyboard navigation is on).
//   qmltestrunner -input tests
TestCase {
    id: tc

    name: "Shortcuts"
    width: 100
    height: 100
    when: windowShown

    TextArea {
        id: editor
    }

    Theme {
        id: theme

        palette: editor.palette
        font: editor.font
    }

    // main.qml, as far as the window needs it.
    QtObject {
        id: app

        property var shortcuts: []
        readonly property var ownShortcuts: [
            { keys: "  ", name: "Apply", mode: "normal", where: "" },
            { keys: " q", name: "List your shortcuts", mode: "both", where: "" },
            { keys: "g.", name: "Toggle hidden", mode: "normal", where: "Listing" },
            { keys: "-", name: "Up", mode: "normal", where: "" }
        ]
        readonly property var menuShortcuts: [{ keys: "<D-s>", name: "Save", mode: "both", where: "" }]
        property bool showOwnShortcuts: false
        // Koil's own keys that do something where vim is.
        property var here: ["  ", " q", "-"]
        // The keys of the shortcuts run (Koil's own as "own:" and theirs).
        property var ran: []
        property real x: 0
        property real y: 0
        property real width: 900
        property real height: 600

        function saveShortcuts(list) {
            shortcuts = list;
        }
        function runShortcut(s, own) {
            ran = ran.concat([own ? "own:" + s.keys : s.macro]);
        }
        function commandHere(keys) {
            return here.includes(keys);
        }
        function changeSetting(name, value) {
            if (name === "showOwnShortcuts")
                showOwnShortcuts = value;
        }
        function keyParts(text) {
            return text.split(/(<CR>)/).filter(t => t).map(t => ({ text: t, special: t === "<CR>" }));
        }
        function keyTokens(text) {
            return text.match(/<[A-Za-z-]+>|[\s\S]/g) || [];
        }
        // As Vim.keysName.
        function keysName(text) {
            let name = "";
            for (const k of keyTokens(text))
                name += k === " " ? (name && !name.endsWith(" ") ? " " : "") + "Space " : k;
            return name.trim();
        }
        function keyToken(event) {
            if (event.key === Qt.Key_Backspace)
                return "<BS>";
            if (event.key === Qt.Key_K && event.modifiers & Qt.MetaModifier)
                return "<C-k>";
            // Cmd
            if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z && event.modifiers & Qt.ControlModifier)
                return "<D-" + String.fromCharCode(event.key - Qt.Key_A + 97) + ">";
            return event.text || null;
        }
        // Vim's x, and z, which only starts its commands.
        function vimCommandIn(text, visual) {
            return text[0] === "x" ? { keys: "x", whole: true } : text === "z" ? { keys: "z", whole: false } : null;
        }
        function macroList() {
            return [{ name: "q", keys: ":!ls<CR>" }, { name: "w", keys: "dd" }];
        }
    }

    ShortcutsWindow {
        id: win

        app: app
        theme: theme
    }

    function init() {
        app.shortcuts = [
            { name: "Copy", keys: " c", macro: "yy", mode: "normal", enabled: true },
            { name: "", keys: " e", macro: "dd", mode: "both", enabled: true }
        ];
        app.ran = [];
        app.showOwnShortcuts = false;
        win.open();
        tryVerify(() => win.active);
        tryVerify(() => focused() !== "none");
    }

    function cleanup() {
        win.close();
    }

    // What has the keys, by its accessible name (a row's is its title).
    function focused() {
        const f = win.activeFocusItem;
        return f ? f.Accessible.name || String(f).split("(")[0] : "none";
    }

    function tab(n) {
        for (let i = 0; i < (n || 1); i++)
            keyClick(Qt.Key_Tab);
    }

    function type(text) {
        for (const ch of text)
            keyClick(ch);
    }

    function back(n) {
        for (let i = 0; i < (n || 1); i++)
            keyClick(Qt.Key_Backtab, Qt.ShiftModifier);
    }

    // The search has the keys: typing searches, Up and Down pick a
    // shortcut, Enter runs it, and Tab goes to the picked one's buttons,
    // then +.
    function test_list() {
        compare(focused(), "Search shortcuts");
        compare(win.currentShortcut(), 0);
        const order = [];
        for (let i = 0; i < 4; i++) {
            tab();
            order.push(focused());
        }
        compare(order, ["Edit", "Delete", "Show Built-in Shortcuts", "New Shortcut"]);
        tab();
        back();
        compare(focused(), "New Shortcut");
        tab();
        // letters search, rather than move
        type("jk");
        compare(win.shown, []);
        keyClick(Qt.Key_Escape);
        verify(win.visible);
        compare(win.shown, [0, 1]);
        keyClick(Qt.Key_Down);
        compare(win.currentShortcut(), 1);
        keyClick(Qt.Key_Down);
        compare(win.currentShortcut(), 1);
        keyClick(Qt.Key_Up);
        compare(win.currentShortcut(), 0);
        // the picked one's trash
        keyClick(Qt.Key_Down);
        tab(2);
        compare(focused(), "Delete");
        keyClick(Qt.Key_Space);
        compare(app.shortcuts.map(s => s.name), ["Copy"]);
        compare(focused(), "Search shortcuts");
        keyClick(Qt.Key_Return);
        compare(app.ran, ["yy"]);
        verify(!win.visible);
    }

    // The form, from the pencil: Tab through it both ways, the mode with
    // the arrows, the checkbox and the buttons with Space, the key, a macro
    // picked, and Enter, which saves from anything.
    function test_form() {
        keyClick(Qt.Key_Down);
        tab();
        compare(focused(), "Edit");
        keyClick(Qt.Key_Return);
        verify(win.editing);
        compare(focused(), "Name");
        const order = [];
        for (let i = 0; i < 9; i++) {
            tab();
            order.push(focused());
        }
        compare(order, ["Shortcut keys", "Keys it runs", "Recorded Macros", "Mode", "Enabled", "Delete",
            "Cancel", "Save", "Name"]);
        back();
        compare(focused(), "Save");
        tab(5);
        compare(focused(), "Mode");
        keyClick(Qt.Key_Left);
        compare(win.draft.mode, "visual");
        tab();
        keyClick(Qt.Key_Space);
        compare(win.draft.enabled, false);
        keyClick(Qt.Key_Space);
        compare(win.draft.enabled, true);
        // the macros, with the keys
        back(2);
        compare(focused(), "Recorded Macros");
        keyClick(Qt.Key_Space);
        keyClick(Qt.Key_Return);
        compare(win.draft.macro, ":!ls<CR>");
        compare(focused(), "Keys it runs");
        verify(win.editing);
        tab();
        keyClick(Qt.Key_Space);
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Return);
        compare(win.draft.macro, "dd");
        // Tab while they're listed goes on from the button
        tab();
        keyClick(Qt.Key_Space);
        tab();
        compare(focused(), "Mode");
        back(3);
        compare(focused(), "Shortcut keys");
        // after the keys it had
        keyClick("x");
        compare(win.draft.keys, " ex");
        keyClick(Qt.Key_Backspace);
        keyClick(Qt.Key_Backspace);
        compare(win.draft.keys, " ");
        keyClick(Qt.Key_Space);
        keyClick("x");
        compare(win.draft.keys, "  x");
        keyClick(Qt.Key_Backspace);
        keyClick(Qt.Key_Backspace);
        keyClick("x");
        tab(7);
        compare(focused(), "Save");
        keyClick(Qt.Key_Space);
        verify(!win.editing);
        compare(app.shortcuts[1].keys, " x");
        compare(app.shortcuts[1].mode, "visual");
        compare(focused(), "Search shortcuts");
        compare(win.currentShortcut(), 1);
    }

    // Enter saves from anything in the form, not only a field.
    function test_enterSaves() {
        tab();
        keyClick(Qt.Key_Return);
        verify(win.editing);
        tab(4);
        compare(focused(), "Mode");
        keyClick(Qt.Key_Right);
        keyClick(Qt.Key_Return);
        verify(!win.editing);
        compare(app.shortcuts[0].mode, "visual");
        tab();
        keyClick(Qt.Key_Return);
        tab(5);
        compare(focused(), "Enabled");
        keyClick(Qt.Key_Space);
        keyClick(Qt.Key_Enter);
        verify(!win.editing);
        compare(app.shortcuts[0].enabled, false);
        // and Cancel and Delete still do what they say, with Space
        tab();
        keyClick(Qt.Key_Return);
        tab(7);
        compare(focused(), "Cancel");
        keyClick(Qt.Key_Space);
        verify(!win.editing);
        compare(app.shortcuts.length, 2);
    }

    // Keys written out, with the names of keys in their color, and the
    // rest as it is.
    function test_styledKeys() {
        compare(win.styledKeys("a  b<CR>&<x>", "#ff0000"),
            "a&nbsp;&nbsp;b<font color=\"#ff0000\">&lt;CR&gt;</font>&amp;&lt;x&gt;");
    }

    // With the lock button on, Koil's own keys are listed under the user's
    // shortcuts, to run but not to change: Tab goes from one to the
    // button, and Enter runs one only where it does something.
    function test_own() {
        compare(win.rows.map(r => r.at), [0, 1]);
        back(2);
        compare(focused(), "Show Built-in Shortcuts");
        keyClick(Qt.Key_Space);
        verify(app.showOwnShortcuts);
        compare(win.rows.map(r => r.own ? "own:" + r.shortcut.keys : r.at), [0, 1, "own:  ", "own: q", "own:g.",
            "own:-"]);
        compare(win.rows.map(r => r.heading), [false, false, true, false, false, false]);
        tab(2);
        compare(focused(), "Search shortcuts");
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Down);
        compare(win.currentShortcut(), -1);
        tab();
        compare(focused(), "Show Built-in Shortcuts");
        tab(2);
        // g. only in the listing
        keyClick(Qt.Key_Return);
        compare(app.ran, []);
        verify(win.visible);
        keyClick(Qt.Key_Up);
        keyClick(Qt.Key_Return);
        compare(app.ran, ["own: q"]);
        verify(!win.visible);
    }

    // With none of the user's shortcuts, Koil's own are all the list has,
    // and the search goes through them.
    function test_ownOnly() {
        app.shortcuts = [];
        compare(win.rows.length, 0);
        // with the hint over them, which once was a binding loop
        failOnWarning(/Binding loop/);
        app.showOwnShortcuts = true;
        compare(win.rows.length, 4);
        compare(win.currentShortcut(), -1);
        type("toggle");
        compare(win.shown, []);
        compare(win.shownOwn, [2]);
        keyClick(Qt.Key_Return);
        compare(app.ran, []);
    }

    // Any keys can run a shortcut, except Koil's own, keys that start them
    // or start with them, and another shortcut's (that's on, in the same
    // mode), as one of the two would never run; nor keys that start with a
    // count or a register. Keys of vim's can, but it says so.
    function test_keys() {
        keyClick(Qt.Key_N, Qt.ControlModifier);
        tab(2);
        type("d");
        back();
        compare(focused(), "Shortcut keys");
        verify(win.canSave);
        compare(win.problem, "");
        type("gc");
        compare(win.draft.keys, "gc");
        compare(win.problem, "");
        compare(win.note, "");
        verify(win.canSave);
        keyClick(Qt.Key_K, Qt.MetaModifier);
        compare(win.draft.keys, "gc<C-k>");
        keyClick(Qt.Key_Backspace);
        // Cmd+W too, rather than closing the window
        keyClick(Qt.Key_W, Qt.ControlModifier);
        verify(win.visible);
        compare(win.draft.keys, "gc<D-w>");
        keyClick(Qt.Key_Backspace);
        keyClick(Qt.Key_Backspace);
        keyClick(Qt.Key_Backspace);
        // the menus' keys, which vim never gets
        keyClick(Qt.Key_S, Qt.ControlModifier);
        compare(win.problem, "<D-s> is the built-in “Save”.");
        keyClick(Qt.Key_Backspace);
        type("g");
        compare(win.problem, "g starts the built-in g. (“Toggle hidden”).");
        verify(!win.canSave);
        type(".x");
        compare(win.problem, "g.x starts with the built-in g. (“Toggle hidden”).");
        keyClick(Qt.Key_Backspace);
        compare(win.problem, "g. is the built-in “Toggle hidden”.");
        keyClick(Qt.Key_Backspace);
        keyClick(Qt.Key_Backspace);
        keyClick(Qt.Key_Space);
        compare(win.problem, "Space starts the built-in Space Space (“Apply”).");
        keyClick("c");
        compare(win.problem, "Space c already runs “Copy” in normal mode.");
        keyClick("x");
        compare(win.problem, "Space cx starts with Space c, which already runs “Copy” in normal mode.");
        keyClick(Qt.Key_Backspace);
        keyClick(Qt.Key_Backspace);
        keyClick("e");
        compare(win.problem, "Space e already runs “dd”.");
        // Koil's - is normal mode's, and Space c is too
        keyClick(Qt.Key_Backspace);
        keyClick(Qt.Key_Backspace);
        keyClick("-");
        compare(win.problem, "- is the built-in “Up”.");
        tab(3);
        keyClick(Qt.Key_Right);
        compare(win.draft.mode, "visual");
        compare(win.problem, "");
        back(3);
        keyClick(Qt.Key_Backspace);
        keyClick(Qt.Key_Space);
        keyClick("c");
        compare(win.problem, "");
        // nor if it's off
        tab(3);
        keyClick(Qt.Key_Right);
        compare(win.problem, "Space c already runs “Copy” in normal mode.");
        tab();
        keyClick(Qt.Key_Space);
        compare(win.draft.enabled, false);
        compare(win.problem, "");
        back(4);
        compare(focused(), "Shortcut keys");
        keyClick(Qt.Key_Backspace);
        keyClick(Qt.Key_Backspace);
        type("2x");
        compare(win.problem, "2x can't start with 2, which is a count.");
        keyClick(Qt.Key_Backspace);
        keyClick(Qt.Key_Backspace);
        // vim's
        type("xa");
        compare(win.problem, "");
        compare(win.note, "It takes the place of vim's x.");
        verify(win.canSave);
        keyClick(Qt.Key_Backspace);
        keyClick(Qt.Key_Backspace);
        type("z");
        compare(win.note, "It takes the place of vim's commands that start with z.");
        keyClick(Qt.Key_Return);
        verify(!win.editing);
        compare(app.shortcuts[2].keys, "z");
    }

    // Typing searches the names, keys and keys run, which every word must
    // match. Esc empties the search, and with none, closes.
    function test_search() {
        type("dd");
        compare(win.shown, [1]);
        compare(win.currentShortcut(), 1);
        keyClick(Qt.Key_Escape);
        verify(win.visible);
        compare(win.shown, [0, 1]);
        type("Cop");
        compare(win.shown, [0]);
        type(" zz");
        compare(win.shown, []);
        keyClick(Qt.Key_Escape);
        // a key matches as a word, not as a part of "space"
        type("pa");
        compare(win.shown, []);
        keyClick(Qt.Key_Escape);
        type("space E");
        compare(win.shown, [1]);
        keyClick(Qt.Key_Escape);
        // Koil's own too, under the user's, if they're shown
        type("space");
        compare(win.shownOwn, []);
        app.showOwnShortcuts = true;
        compare(win.shownOwn, [0, 1]);
        app.showOwnShortcuts = false;
        keyClick(Qt.Key_Escape);
        // Up and Down pick a match, and Enter runs it
        type("space");
        compare(win.shown, [0, 1]);
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Return);
        compare(app.ran, ["dd"]);
        verify(!win.visible);
    }

    // Esc with no search closes the window.
    function test_close() {
        keyClick(Qt.Key_Escape);
        verify(!win.visible);
    }

    // Cmd+N (Ctrl+N) adds one, as + does.
    function test_add() {
        keyClick(Qt.Key_N, Qt.ControlModifier);
        verify(win.editing);
        compare(focused(), "Name");
        type("New");
        tab(2);
        type("x");
        keyClick(Qt.Key_Return);
        verify(!win.editing);
        compare(app.shortcuts.map(s => s.name), ["Copy", "", "New"]);
        compare(focused(), "Search shortcuts");
        compare(win.currentShortcut(), 2);
    }

    // + makes a new one, and Esc goes back to the list.
    function test_new() {
        back();
        compare(focused(), "New Shortcut");
        keyClick(Qt.Key_Return);
        verify(win.editing);
        verify(!win.draft.macro);
        keyClick(Qt.Key_Escape);
        verify(!win.editing);
        compare(focused(), "Search shortcuts");
        compare(app.shortcuts.length, 2);
    }
}
