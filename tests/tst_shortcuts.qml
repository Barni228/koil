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
            { keys: "  ", name: "Apply", normal: true, visual: false, where: "" },
            { keys: " q", name: "List your shortcuts", normal: true, visual: true, where: "" },
            { keys: "g.", name: "Toggle hidden", normal: true, visual: false, where: "Listing" },
            { keys: "-", name: "Up", normal: true, visual: false, where: "" }
        ]
        readonly property var menuShortcuts: [{ keys: "<D-s>", name: "Save", normal: true, visual: true, where: "" }]
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
            if (event.key === Qt.Key_Backtab)
                return "<S-Tab>";
            // Esc and Enter with Cmd or Shift
            const named = { [Qt.Key_Escape]: "Esc", [Qt.Key_Return]: "CR" }[event.key];
            if (named)
                return event.modifiers & Qt.ControlModifier ? "<D-" + named + ">"
                    : event.modifiers & Qt.ShiftModifier ? "<S-" + named + ">" : "<" + named + ">";
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
        // As main.qml's.
        function readShortcuts(json) {
            let list;
            try {
                list = JSON.parse(json);
            } catch (e) {
                return [];
            }
            return Array.isArray(list) ? list.filter(s => s && typeof s.macro === "string").map(s => ({
                name: typeof s.name === "string" ? s.name : "",
                keys: typeof s.keys === "string" ? s.keys : "",
                macro: s.macro,
                normal: s.normal !== false,
                visual: s.visual === true,
                enabled: s.enabled !== false
            })) : [];
        }
    }

    // Document, as far as the window needs it: files are kept here, by
    // their path.
    QtObject {
        id: doc

        property var files: ({})

        function readText(path) {
            return JSON.stringify(path in files ? { text: files[path] } : { error: "Can't open `" + path + "`" });
        }
        function writeText(path, text) {
            if (path.startsWith("/locked/"))
                return "Can't save `" + path + "`";
            files[path] = text;
            return "";
        }
    }

    ShortcutsWindow {
        id: win

        app: app
        theme: theme
        document: doc
    }

    // The list the macros (and Settings' fonts and shells) are in, with
    // its rows made in another file, as the windows' are.
    DropList {
        id: drop

        theme: theme
        field: editor
        model: ["a", "b"]

        delegate: DropOption {
            required property string modelData

            theme: theme
            text: modelData
        }
    }

    function init() {
        app.shortcuts = [
            { name: "Copy", keys: " c", macro: "yy", normal: true, visual: false, enabled: true },
            { name: "", keys: " e", macro: "dd", normal: true, visual: true, enabled: true }
        ];
        app.ran = [];
        app.showOwnShortcuts = false;
        doc.files = {};
        win.open();
        tryVerify(() => win.active);
        tryVerify(() => focused() !== "none");
    }

    function cleanup() {
        win.close();
    }

    // What has the keys, by its accessible name (a row's is its title).
    function focused() {
        keepKeys();
        const f = win.activeFocusItem;
        return f ? f.Accessible.name || String(f).split("(")[0] : "none";
    }

    // Gives the window the keys back if it lost them. macOS takes the
    // app's activation away once, about half a second after it starts,
    // while another app is in front (the one the tests were started from),
    // and won't give it back for the window asking: then no window has the
    // keys, and keys sent go nowhere. Showing the window again, in front,
    // gives it the keys (the app stays inactive, but the keys sent are
    // Qt's own), and keeps what it shows.
    function keepKeys() {
        if (win.visible && !win.active) {
            win.hide();
            win.show();
            win.raise();
            win.requestActivate();
            tryVerify(() => win.active);
        }
    }

    // A key, to the window (see keepKeys).
    function press(key, modifiers) {
        keepKeys();
        keyClick(key, modifiers);
    }

    function tab(n) {
        for (let i = 0; i < (n || 1); i++)
            press(Qt.Key_Tab);
    }

    function type(text) {
        for (const ch of text)
            press(ch);
    }

    function back(n) {
        for (let i = 0; i < (n || 1); i++)
            press(Qt.Key_Backtab, Qt.ShiftModifier);
    }

    // The search has the keys: typing searches, Up and Down pick a
    // shortcut, Enter runs it, and Tab goes to the picked one's buttons,
    // then +.
    function test_list() {
        compare(focused(), "Search shortcuts");
        compare(win.currentShortcut(), 0);
        const order = [];
        for (let i = 0; i < 6; i++) {
            tab();
            order.push(focused());
        }
        compare(order, ["Edit", "Delete", "Show Built-in Shortcuts", "Import Shortcuts…", "Export Shortcuts…",
            "New Shortcut"]);
        tab();
        back();
        compare(focused(), "New Shortcut");
        tab();
        // letters search, rather than move
        type("jk");
        compare(win.shown, []);
        press(Qt.Key_Escape);
        verify(win.visible);
        compare(win.shown, [0, 1]);
        press(Qt.Key_Down);
        compare(win.currentShortcut(), 1);
        press(Qt.Key_Down);
        compare(win.currentShortcut(), 1);
        press(Qt.Key_Up);
        compare(win.currentShortcut(), 0);
        // the picked one's trash
        press(Qt.Key_Down);
        tab(2);
        compare(focused(), "Delete");
        press(Qt.Key_Space);
        compare(app.shortcuts.map(s => s.name), ["Copy"]);
        compare(focused(), "Search shortcuts");
        press(Qt.Key_Return);
        compare(app.ran, ["yy"]);
        verify(!win.visible);
    }

    // The form, from the pencil: Tab through it both ways, the checkboxes
    // (a mode each, and Enabled) and the buttons with Space, the key, a
    // macro picked, and Enter, which saves from anything.
    function test_form() {
        press(Qt.Key_Down);
        tab();
        compare(focused(), "Edit");
        press(Qt.Key_Return);
        verify(win.editing);
        compare(focused(), "Name");
        const order = [];
        for (let i = 0; i < 10; i++) {
            tab();
            order.push(focused());
        }
        compare(order, ["Shortcut keys", "Keys it runs", "Recorded Macros", "Normal mode", "Visual mode",
            "Enabled", "Delete", "Cancel", "Save", "Name"]);
        back();
        compare(focused(), "Save");
        tab(5);
        compare(focused(), "Normal mode");
        verify(win.draft.normal);
        verify(win.draft.visual);
        press(Qt.Key_Space);
        verify(!win.draft.normal);
        verify(win.draft.visual);
        // in neither mode, it can't be saved
        tab();
        press(Qt.Key_Space);
        compare(win.problem, "It runs in neither mode: check Normal, Visual or both.");
        verify(!win.canSave);
        press(Qt.Key_Return);
        verify(win.editing);
        press(Qt.Key_Space);
        compare(win.problem, "");
        tab();
        press(Qt.Key_Space);
        compare(win.draft.enabled, false);
        press(Qt.Key_Space);
        compare(win.draft.enabled, true);
        // the macros, with the keys
        back(3);
        compare(focused(), "Recorded Macros");
        press(Qt.Key_Space);
        press(Qt.Key_Return);
        compare(win.draft.macro, ":!ls<CR>");
        compare(focused(), "Keys it runs");
        verify(win.editing);
        tab();
        press(Qt.Key_Space);
        press(Qt.Key_Down);
        press(Qt.Key_Return);
        compare(win.draft.macro, "dd");
        // Tab while they're listed goes on from the button
        tab();
        press(Qt.Key_Space);
        tab();
        compare(focused(), "Normal mode");
        back(3);
        compare(focused(), "Shortcut keys");
        // after the keys it had
        press("x");
        compare(win.draft.keys, " ex");
        press(Qt.Key_Backspace);
        press(Qt.Key_Backspace);
        compare(win.draft.keys, " ");
        press(Qt.Key_Space);
        press("x");
        compare(win.draft.keys, "  x");
        press(Qt.Key_Backspace);
        press(Qt.Key_Backspace);
        press("x");
        tab(8);
        compare(focused(), "Save");
        press(Qt.Key_Space);
        verify(!win.editing);
        compare(app.shortcuts[1].keys, " x");
        verify(!app.shortcuts[1].normal);
        verify(app.shortcuts[1].visual);
        compare(focused(), "Search shortcuts");
        compare(win.currentShortcut(), 1);
    }

    // Enter saves from anything in the form, not only a field.
    function test_enterSaves() {
        tab();
        press(Qt.Key_Return);
        verify(win.editing);
        tab(4);
        compare(focused(), "Normal mode");
        press(Qt.Key_Space);
        tab();
        press(Qt.Key_Space);
        press(Qt.Key_Return);
        verify(!win.editing);
        verify(!app.shortcuts[0].normal);
        verify(app.shortcuts[0].visual);
        tab();
        press(Qt.Key_Return);
        tab(6);
        compare(focused(), "Enabled");
        press(Qt.Key_Space);
        press(Qt.Key_Enter);
        verify(!win.editing);
        compare(app.shortcuts[0].enabled, false);
        // and Cancel and Delete still do what they say, with Space
        tab();
        press(Qt.Key_Return);
        tab(8);
        compare(focused(), "Cancel");
        press(Qt.Key_Space);
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
        back(4);
        compare(focused(), "Show Built-in Shortcuts");
        press(Qt.Key_Space);
        verify(app.showOwnShortcuts);
        compare(win.rows.map(r => r.own ? "own:" + r.shortcut.keys : r.at), [0, 1, "own:  ", "own: q", "own:g.",
            "own:-"]);
        compare(win.rows.map(r => r.heading), [false, false, true, false, false, false]);
        tab(4);
        compare(focused(), "Search shortcuts");
        press(Qt.Key_Down);
        press(Qt.Key_Down);
        press(Qt.Key_Down);
        press(Qt.Key_Down);
        compare(win.currentShortcut(), -1);
        tab();
        compare(focused(), "Show Built-in Shortcuts");
        tab(4);
        // g. only in the listing
        press(Qt.Key_Return);
        compare(app.ran, []);
        verify(win.visible);
        press(Qt.Key_Up);
        press(Qt.Key_Return);
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
        press(Qt.Key_Return);
        compare(app.ran, []);
    }

    // Any keys can run a shortcut, except Koil's own, keys that start them
    // or start with them, and another shortcut's (that's on, in the same
    // mode), as one of the two would never run; nor keys that start with a
    // count or a register. Keys of vim's can, but it says so.
    function test_keys() {
        press(Qt.Key_N, Qt.ControlModifier);
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
        press(Qt.Key_K, Qt.MetaModifier);
        compare(win.draft.keys, "gc<C-k>");
        press(Qt.Key_Backspace);
        // Cmd+W too, rather than closing the window
        press(Qt.Key_W, Qt.ControlModifier);
        verify(win.visible);
        compare(win.draft.keys, "gc<D-w>");
        press(Qt.Key_Backspace);
        press(Qt.Key_Backspace);
        press(Qt.Key_Backspace);
        // the menus' keys, which vim never gets
        press(Qt.Key_S, Qt.ControlModifier);
        compare(win.problem, "<D-s> is the built-in “Save”.");
        press(Qt.Key_Backspace);
        type("g");
        compare(win.problem, "g starts the built-in g. (“Toggle hidden”).");
        verify(!win.canSave);
        type(".x");
        compare(win.problem, "g.x starts with the built-in g. (“Toggle hidden”).");
        press(Qt.Key_Backspace);
        compare(win.problem, "g. is the built-in “Toggle hidden”.");
        press(Qt.Key_Backspace);
        press(Qt.Key_Backspace);
        press(Qt.Key_Space);
        compare(win.problem, "Space starts the built-in Space Space (“Apply”).");
        press("c");
        compare(win.problem, "Space c already runs “Copy” in normal mode.");
        press("x");
        compare(win.problem, "Space cx starts with Space c, which already runs “Copy” in normal mode.");
        press(Qt.Key_Backspace);
        press(Qt.Key_Backspace);
        press("e");
        compare(win.problem, "Space e already runs “dd”.");
        // Koil's - is normal mode's, and Space c is too
        press(Qt.Key_Backspace);
        press(Qt.Key_Backspace);
        press("-");
        compare(win.problem, "- is the built-in “Up”.");
        tab(3);
        press(Qt.Key_Space);
        tab();
        press(Qt.Key_Space);
        verify(!win.draft.normal);
        verify(win.draft.visual);
        compare(win.problem, "");
        back(4);
        press(Qt.Key_Backspace);
        press(Qt.Key_Space);
        press("c");
        compare(win.problem, "");
        // nor if it's off
        tab(3);
        press(Qt.Key_Space);
        compare(win.problem, "Space c already runs “Copy” in normal mode.");
        tab(2);
        press(Qt.Key_Space);
        compare(win.draft.enabled, false);
        compare(win.problem, "");
        back(5);
        compare(focused(), "Shortcut keys");
        press(Qt.Key_Backspace);
        press(Qt.Key_Backspace);
        type("2x");
        compare(win.problem, "2x can't start with 2, which is a count.");
        press(Qt.Key_Backspace);
        press(Qt.Key_Backspace);
        // vim's
        type("xa");
        compare(win.problem, "");
        compare(win.note, "It takes the place of vim's x.");
        verify(win.canSave);
        press(Qt.Key_Backspace);
        press(Qt.Key_Backspace);
        type("z");
        compare(win.note, "It takes the place of vim's commands that start with z.");
        press(Qt.Key_Return);
        verify(!win.editing);
        compare(app.shortcuts[2].keys, "z");
    }

    // In the key box, Tab, Esc and Enter with a modifier are keys, and so
    // is Shift+Tab, rather than going back; alone, Tab goes on, Enter
    // saves and Esc goes back to the list.
    function test_modifiedKeys() {
        press(Qt.Key_N, Qt.ControlModifier);
        tab();
        compare(focused(), "Shortcut keys");
        press(Qt.Key_Backtab, Qt.ShiftModifier);
        compare(focused(), "Shortcut keys");
        press(Qt.Key_Escape, Qt.ControlModifier);
        press(Qt.Key_Return, Qt.ControlModifier);
        press(Qt.Key_Escape, Qt.ShiftModifier);
        compare(win.draft.keys, "<S-Tab><D-Esc><D-CR><S-Esc>");
        verify(win.editing);
        tab();
        compare(focused(), "Keys it runs");
        type("x");
        back();
        compare(focused(), "Shortcut keys");
        press(Qt.Key_Return);
        verify(!win.editing);
        compare(app.shortcuts[2].keys, "<S-Tab><D-Esc><D-CR><S-Esc>");
        press(Qt.Key_N, Qt.ControlModifier);
        tab();
        press(Qt.Key_Escape);
        verify(!win.editing);
        compare(app.shortcuts.length, 3);
    }

    // Typing searches the names, keys and keys run, which every word must
    // match. Esc empties the search, and with none, closes.
    function test_search() {
        type("dd");
        compare(win.shown, [1]);
        compare(win.currentShortcut(), 1);
        press(Qt.Key_Escape);
        verify(win.visible);
        compare(win.shown, [0, 1]);
        type("Cop");
        compare(win.shown, [0]);
        type(" zz");
        compare(win.shown, []);
        press(Qt.Key_Escape);
        // a key matches as a word, not as a part of "space"
        type("pa");
        compare(win.shown, []);
        press(Qt.Key_Escape);
        type("space E");
        compare(win.shown, [1]);
        press(Qt.Key_Escape);
        // Koil's own too, under the user's, if they're shown
        type("space");
        compare(win.shownOwn, []);
        app.showOwnShortcuts = true;
        compare(win.shownOwn, [0, 1]);
        app.showOwnShortcuts = false;
        press(Qt.Key_Escape);
        // Up and Down pick a match, and Enter runs it
        type("space");
        compare(win.shown, [0, 1]);
        press(Qt.Key_Down);
        press(Qt.Key_Return);
        compare(app.ran, ["dd"]);
        verify(!win.visible);
    }

    // Esc with no search closes the window.
    function test_close() {
        press(Qt.Key_Escape);
        verify(!win.visible);
    }

    // Cmd+N (Ctrl+N) adds one, as + does.
    function test_add() {
        press(Qt.Key_N, Qt.ControlModifier);
        verify(win.editing);
        compare(focused(), "Name");
        type("New");
        tab(2);
        type("x");
        press(Qt.Key_Return);
        verify(!win.editing);
        compare(app.shortcuts.map(s => s.name), ["Copy", "", "New"]);
        compare(focused(), "Search shortcuts");
        compare(win.currentShortcut(), 2);
    }

    // A DropList's rows are made: an inline component of DropList.qml,
    // which binds them to it (ComponentBehavior: Bound), Qt made none from
    // another file, so the lists were empty.
    function test_dropRows() {
        drop.open();
        tryVerify(() => drop.opened);
        tryVerify(() => drop.view.itemAtIndex(1) !== null);
        const row = drop.view.itemAtIndex(1) as DropOption;
        compare(row.text, "b");
        drop.close();
    }

    // Export asks which to export, all picked at first: Space picks the
    // current one or leaves it out, `a` all or none, Tab goes to the
    // buttons, Esc back to the list. They're saved as the settings keep
    // them (a dialog asks where; writeExport is what it calls).
    function test_export() {
        back(2);
        compare(focused(), "Export Shortcuts…");
        press(Qt.Key_Space);
        verify(win.exporting);
        // its current row, which a ListView gives the keys
        compare(focused(), "Copy");
        const picks = win.exportPicks;
        compare(picks.picked, [true, true]);
        verify(picks.rowShown);
        press(Qt.Key_Space);
        compare(picks.picked, [false, true]);
        press(Qt.Key_A);
        compare(picks.picked, [true, true]);
        press(Qt.Key_A);
        compare(picks.picked, [false, false]);
        compare(win.pickedCount, 0);
        press(Qt.Key_Down);
        press(Qt.Key_Space);
        compare(picks.picked, [false, true]);
        const order = [];
        for (let i = 0; i < 4; i++) {
            tab();
            order.push(focused());
        }
        compare(order, ["Select All", "Cancel", "Export…", "Space e"]);
        // A file that can't be written says why, on the page.
        win.writeExport("/locked/s.json");
        verify(win.exporting);
        compare(win.message, "Can't save `/locked/s.json`");
        verify(win.failed);
        win.writeExport("/x/s.json");
        verify(!win.exporting);
        compare(JSON.parse(doc.files["/x/s.json"]), [app.shortcuts[1]]);
        compare(win.message, "Exported 1 shortcut to “s.json”.");
        verify(!win.failed);
        compare(focused(), "Search shortcuts");
        // Esc leaves the page, exporting nothing.
        win.startExport();
        press(Qt.Key_Escape);
        verify(!win.exporting);
        verify(win.visible);
        compare(win.message, "");
    }

    // The export page's list has the keys of every list to pick from (see
    // PickList), as a question's: j, k, g and G move, x picks, v selects
    // rows, / searches, and Esc ends a selection or a search before it
    // leaves the page.
    function test_exportListKeys() {
        win.startExport();
        const picks = win.exportPicks;
        compare(picks.rows.length, 2);
        compare(picks.row, 0);
        press(Qt.Key_J);
        compare(picks.row, 1);
        press(Qt.Key_K);
        compare(picks.row, 0);
        press(Qt.Key_G, Qt.ShiftModifier);
        compare(picks.row, 1);
        press(Qt.Key_G);
        compare(picks.row, 0);
        press(Qt.Key_X);
        compare(picks.picked, [false, true]);
        // Ctrl-D, Ctrl-F and PageDown go down by pages, as far as the last
        // row, and Ctrl-U, Ctrl-B and PageUp back up; End and Home go to
        // the last and first.
        const ctrl = Qt.platform.os === "osx" ? Qt.MetaModifier : Qt.ControlModifier;
        verify(picks.pageRows > 2);
        for (const [down, up] of [[Qt.Key_D, Qt.Key_U], [Qt.Key_F, Qt.Key_B]]) {
            press(down, ctrl);
            compare(picks.row, 1);
            press(up, ctrl);
            compare(picks.row, 0);
        }
        press(Qt.Key_PageDown);
        compare(picks.row, 1);
        press(Qt.Key_PageUp);
        compare(picks.row, 0);
        press(Qt.Key_End);
        compare(picks.row, 1);
        press(Qt.Key_Home);
        compare(picks.row, 0);
        // Ctrl-E and Ctrl-Y scroll, leaving the cursor.
        press(Qt.Key_E, ctrl);
        press(Qt.Key_Y, ctrl);
        compare(picks.row, 0);
        compare(picks.picked, [false, true]);
        // v selects both rows, and Space picks them, as one is left out.
        press(Qt.Key_V);
        press(Qt.Key_J);
        compare(picks.selectedRows, [0, 1]);
        press(Qt.Key_Space);
        compare(picks.picked, [true, true]);
        compare(picks.anchor, -1);
        // Esc ends a selection, and stays on the page.
        press(Qt.Key_V);
        press(Qt.Key_Escape);
        compare(picks.anchor, -1);
        verify(win.exporting);
        // / searches: only the shortcuts that have what's typed show, and
        // Enter keeps the search rather than exporting.
        press(Qt.Key_Slash);
        verify(picks.filtering);
        type("dd");
        compare(picks.rows.map(row => row.item), [1]);
        press(Qt.Key_Return);
        verify(!picks.filtering);
        verify(win.exporting);
        compare(focused(), "Space e");
        // `a` leaves out those that show; the other stays picked.
        press(Qt.Key_A);
        compare(picks.picked, [true, false]);
        // Esc shows them all again, and the next one leaves the page.
        press(Qt.Key_Escape);
        compare(picks.filter, "");
        compare(picks.rows.length, 2);
        verify(win.exporting);
        // Y takes the cursor's shortcut, picked or not.
        win.exportOnly = [1];
        win.writeExport("/x/one.json");
        compare(JSON.parse(doc.files["/x/one.json"]), [app.shortcuts[1]]);
        win.startExport();
        compare(win.exportOnly, null);
        press(Qt.Key_Escape);
        verify(!win.exporting);
    }

    // Import adds the shortcuts of a file after the user's, but those
    // already here; one whose keys can't be used here (taken, by the
    // user's or Koil's) comes in off. A file that isn't shortcuts, or
    // can't be read, says why.
    function test_import() {
        doc.files["/in.json"] = JSON.stringify([
            { name: "Copy", keys: " c", macro: "yy", normal: true, visual: false, enabled: true },
            { name: "Same keys", keys: " c", macro: "p", normal: true, visual: false, enabled: true },
            { name: "Save", keys: "<D-s>", macro: ":w<CR>", normal: true, visual: false, enabled: true },
            { name: "New", keys: " n", macro: "o", normal: true, visual: false, enabled: true },
            { name: "Visual", keys: " c", macro: "y", normal: false, visual: true, enabled: true }
        ]);
        win.importFrom("/in.json");
        compare(app.shortcuts.map(s => s.name), ["Copy", "", "Same keys", "Save", "New", "Visual"]);
        compare(app.shortcuts.map(s => s.enabled), [true, true, false, false, true, true]);
        compare(win.message, "Imported 4 shortcuts from “in.json”. 2 are off, as their keys can't be used here: "
            + "edit them to change them. 1 was here already.");
        compare(win.currentShortcut(), 2);
        win.importFrom("/in.json");
        compare(app.shortcuts.length, 6);
        compare(win.message, "The shortcuts in “in.json” are all here already.");
        doc.files["/bad.json"] = "{ \"shortcuts\": 1 }";
        win.importFrom("/bad.json");
        compare(win.message, "Can't import “bad.json”: it isn't shortcuts as Export saves them.");
        verify(win.failed);
        win.importFrom("/gone.json");
        compare(win.message, "Can't open `/gone.json`");
        verify(win.failed);
        // Typing a search drops the message.
        type("c");
        compare(win.message, "");
    }

    // + makes a new one, and Esc goes back to the list.
    function test_new() {
        back();
        compare(focused(), "New Shortcut");
        press(Qt.Key_Return);
        verify(win.editing);
        verify(!win.draft.macro);
        press(Qt.Key_Escape);
        verify(!win.editing);
        compare(focused(), "Search shortcuts");
        compare(app.shortcuts.length, 2);
    }
}
