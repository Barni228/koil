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
        readonly property var spaceKeys: ({ " ": "applies", "q": "lists your shortcuts" })
        // The keys of the shortcuts run.
        property var ran: []
        property real x: 0
        property real y: 0
        property real width: 900
        property real height: 600

        function saveShortcuts(list) {
            shortcuts = list;
        }
        function runShortcut(s) {
            ran = ran.concat([s.macro]);
        }
        function keyParts(text) {
            return text.split(/(<CR>)/).filter(t => t).map(t => ({ text: t, special: t === "<CR>" }));
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
            { name: "Copy", key: "c", macro: "yy", mode: "normal", enabled: true },
            { name: "", key: "e", macro: "dd", mode: "both", enabled: true }
        ];
        app.ran = [];
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
        compare(order, ["Edit", "Delete", "New Shortcut", "Search shortcuts"]);
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
        compare(order, ["Key after Space", "Keys it runs", "Recorded Macros", "Mode", "Enabled", "Delete",
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
        compare(focused(), "Key after Space");
        keyClick("x");
        compare(win.draft.key, "x");
        tab(7);
        compare(focused(), "Save");
        keyClick(Qt.Key_Space);
        verify(!win.editing);
        compare(app.shortcuts[1].key, "x");
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
