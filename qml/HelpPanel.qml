pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

// :help, a box over the editor with what isn't obvious: Koil's listing,
// :set and its forms, the commands, search, registers and macros, visual
// block and multiple cursors, hidden text and other keys. :help topic scrolls to a section.
// :reg shows the registers in it too (showList).
// Keys scroll it as in a vim help buffer; Esc or q closes it. Its text can be
// selected with the mouse and copied.
Popup {
    id: help

    required property Theme theme
    // The font Koil ships, for :set guifont.
    property string defaultFontFamily

    readonly property real zoom: theme.zoom
    readonly property bool isMac: Qt.platform.os === "osx"
    readonly property string monoFamily: theme.font.family
    // Modifier keys as the OS writes them.
    readonly property string cmdKey: isMac ? "⌘" : "Ctrl+"
    readonly property string altKey: isMac ? "⌥" : "Alt+"
    readonly property real lineStep: Math.round(20 * zoom)
    // What it shows: the help, or a list (see showList).
    property string heading: "Koil Help"
    property var shownSections: sections

    // Each section: a title, the :help topics that go to it, an optional
    // intro and note, and rows of [keys, what they do]. `code` in text is
    // shown in the editor's font.
    readonly property var sections: [
        {
            title: "The listing",
            tags: ["koil", "listing", "list", "entry", "entries", "space", "update", "apply", "-", "enter",
                "<cr>", "cr", "path", "pattern", "glob", "folder", "dir", "undo", "tab", "<tab>", "g.", "gi",
                "gr"],
            intro: "Koil shows a dir as text: its path in a field at the top, then a line per entry: its icon "
                + "(which hides its ID), two spaces, and its name, with `/` after a dir's. Edit the names to "
                + "rename, delete lines to delete, copy lines (icon and all) to copy, and write lines "
                + "without an icon to create, like `new.txt` or `new/dir/`. A line cut here and pasted in "
                + "another dir moves the entry. Nothing changes on disk until it's applied.",
            rows: [
                ["Space Space", "Update: Koil reads the listing (keeping the changes, also in other dirs) "
                    + "and shows it again, opening the path in the field if it changed."],
                ["Space a  :w", "Apply the changes, after showing what they'll do. `:wq` quits afterwards."],
                ["[x]", "Applying lists the changes picked: `j` and `k` go through them, Space or `x` (or a "
                    + "click on the box) leaves one out or picks it again, along with what goes with it (a "
                    + "swap's other half, the new dir a file goes in), and `a` picks all or none. What's left "
                    + "out is forgotten."],
                ["u", "With no edit left to undo: undo the last apply, after showing what that will do. "
                    + "Deleted entries come back from the trash."],
                ["Enter", "Open the dir or file on the cursor's line. A file opens as it is on disk, even "
                    + "if its line renames it. A new file is created first, if you say so (the other "
                    + "changes stay)."],
                ["Shift+Enter", "Vim's Enter: the first character of the next line."],
                ["icons", "The cursor stays out of an icon and the two spaces after it: `0` goes to the "
                    + "name, and `o` (or Enter) starts a line after three spaces. Backspace at a name's "
                    + "start clears its icon (making the entry new), then joins the line to the one "
                    + "above; `X` there only clears the icon. Whole lines (`dd`, `yy`, `V`) take their icons along, and pasted ones go "
                    + "first on their lines."],
                ["-", "Open the dir above (`3-`: three dirs up). In a file: back to the listing, on the "
                    + "file's line (asking to save it first, if it has changes)."],
                ["quitting", "`:conf q` and `ZZ` ask to apply the changes (No quits without them), or, "
                    + "while the listing has errors, whether to quit without them. In a file, while the "
                    + "listing has changes that aren't applied, `:q`, `:wq`, `ZZ`, `:q!` and the rest (but "
                    + "`:qa!`) go back to the listing instead (saving or dropping the file as they say), "
                    + "where `:conf q` and `ZZ` then ask."],
                ["path", "The field at the top: a dir, or a pattern of files, like `~/src/**/*.rs`, or a "
                    + "regex with `:set regex` (where `,` is any character but `/`), whose parts get colors. "
                    + "Write paths with `/`, also on Windows: a path pasted with `\\` opens, and then shows "
                    + "with `/`, but in a pattern `\\` escapes, like `\\.`. It's one line, edited with vim's "
                    + "keys too; Enter (also in insert mode) opens it and "
                    + "goes back to the listing, and Shift+Enter opens it but stays in the field. `k` and `j` "
                    + "(Up and Down, also while typing) go through the dirs and patterns listed before, "
                    + "since Koil started."],
                ["Tab", "In normal mode: go from the listing to the path field, or back. So does a click. "
                    + "While typing a path: complete the dir being written, like a shell, as far as it can; "
                    + "with nothing more to fill in, list the dirs it can be: Tab and Shift+Tab (or Down and "
                    + "Up) pick one, Enter takes it, Esc closes the list, and typing narrows it."],
                ["g.  gi  gr", "Turn `:set hidden`, `gitignore` and `regex` on or off, like the buttons beside "
                    + "the path."],
                [(isMac ? "⇧⌘O" : "Ctrl+Shift+O"), "Open a folder. " + cmdKey + "O opens a file to edit "
                    + "instead."]
            ]
        },
        {
            title: "Options (:set)",
            tags: ["set", "se", "options", "option", "fontsize", "fs", "guifont", "gfn", "font",
                "number", "nu", "relativenumber", "rnu", "sidescrolloff", "siso", "hidden", "hid", "gitignore",
                "ignore", "regex", "re"],
            intro: "`:set` with no arguments lists the options that aren't at their default. "
                + "Several can be set at once: `:set nu rnu fs=18`.",
            rows: [
                ["fontsize, fs", "Font size in points, 6 to 72. Default 16."],
                ["guifont, gfn", "Font: an installed monospaced one, in any case. Default `"
                    + defaultFontFamily + "`, which comes with Koil. Any font shows the listing's icons."],
                ["number, nu", "Line numbers."],
                ["relativenumber, rnu", "Line numbers counted from the cursor's line. With `nu` too, "
                    + "the cursor's line shows its own number."],
                ["sidescrolloff, siso", "Columns kept in view on either side of the cursor when the text "
                    + "scrolls sideways. Default 4. At a name's start, its icon is always in view."],
                ["hidden, hid", "Show hidden entries (starting with `.`), and `../` to open the dir above."],
                ["gitignore, ignore", "Hide what git ignores, and `.git`."],
                ["regex, re", "Read the path as a regex, not a glob."]
            ],
            note: "An entry with changes is shown even if it's hidden or ignored."
        },
        {
            title: "Setting an on/off option",
            tags: [],
            rows: [
                [":set nu", "Turn it on."],
                [":set nonu", "Turn it off."],
                [":set nu!  :set invnu", "Toggle it."],
                [":set nu?", "Show it: `number` or `nonumber`."],
                [":set nu&", "Back to what Settings says."]
            ]
        },
        {
            title: "Setting a number option",
            tags: [],
            rows: [
                [":set fs=16  :set fs:16", "Set it."],
                [":set fs+=2  fs-=2  fs^=2", "Add, subtract, multiply."],
                [":set fs  :set fs?", "Show it: `fontsize=16`."],
                [":set fs&", "Back to the size in Settings."]
            ]
        },
        {
            title: "Setting the font",
            tags: [],
            rows: [
                [":set gfn=Monaco", "Set it."],
                [":set gfn=Fira\\ Code", "A backslash before a space."],
                [":set gfn  :set gfn?", "Show it: `guifont=Monaco`."],
                [":set gfn&  :set gfn=", "Back to the font in Settings."]
            ],
            note: "Zoom and `:set` last until Koil quits, and don't change Settings (" + cmdKey
                + ",), which Koil starts with and `&` goes back to."
        },
        {
            title: "Commands",
            tags: ["commands", "command", "ex", "w", "write", "quit", "wq", "x", "confirm", "conf", "noh",
                "nohlsearch", "help", "h", "history"],
            rows: [
                [":w", "Save (in the listing: apply)."],
                [":wq  :x", "Save and quit."],
                ["ZZ", "Save and quit (in the listing: `:confirm q`)."],
                [":q  :qa", "Quit, unless there are unsaved changes."],
                [":q!  ZQ", "Quit without saving."],
                [":qa!", "Quit without saving anything, also from a file while the listing has changes."],
                [":conf q  :confirm q", "Quit, asking whether to save unsaved changes: `y`, `n`, or `c` (or "
                    + "Esc) to cancel. Left and Right pick a choice for Enter."],
                [":42  :$", "Go to line 42, or the last line."],
                [":noh", "Clear the search highlights (so does Esc in normal mode)."],
                [":reg  :reg [names]", "Show what the registers hold, e.g. `:reg a0`. `c`, `l` and `b` "
                    + "say whether one holds characters, lines or a block."],
                [":h  :help [topic]", "This help, e.g. `:h set`, `:h search`, `:h macros`."],
                ["↑ ↓", "In the command line: earlier and later commands (or searches)."],
                ["Ctrl-U  Ctrl-W", "In the command line: delete to the start, or the word before the cursor."],
                ["@:", "Run the last command again."]
            ]
        },
        {
            title: "Search",
            tags: ["search", "/", "?", "regex", "regexp", "pattern", "find", "replace", "n", "*"],
            rows: [
                ["/pattern  ?pattern", "Search forward or backward. Patterns are JavaScript regular "
                    + "expressions, not vim's: `\\bword\\b`, `(a|b)+`, `\\d{3}`. "
                    + "One that isn't valid (yet) is searched for as plain text. They ignore case, "
                    + "unless they have an uppercase letter (an escape's, like `\\S`, doesn't count)."],
                ["n  N", "Next or previous match."],
                ["*  #", "Search for the word under the cursor."],
                [cmdKey + "F", "The find bar. Its matches are highlighted while it's open."],
                [isMac ? "⌘G  ⇧⌘G" : "F3  Shift+F3  Ctrl+G  Ctrl+Shift+G",
                    "Next or previous find bar match (opens the bar if it has nothing to find)."],
                [isMac ? "⌘⌥F" : "Ctrl+H", "Find and replace."],
                [isMac ? "⌃⌥C  ⌃⌥W  ⌃⌥R" : "Alt+C  Alt+W  Alt+R",
                    "In the find bar: match case, whole word, regular expression."]
            ]
        },
        {
            title: "Registers and macros",
            tags: ["registers", "register", "reg", "clipboard", "\"", "\"+", "+", "*", "\"0", "\"_", "\"-",
                "\"1", "\".", "\":", "\"/", "\"%", "macros", "macro",
                "q", "@", "@@", "record", "recording", "yank", "paste", "p", "y"],
            rows: [
                ["\"+  \"*", "The system clipboard, e.g. `\"+yy` or `\"+p`. Other registers (and "
                    + "plain `y`, `d`, `p`) don't touch the clipboard; " + (isMac ? "⌘C and ⌘V do."
                    : "Ctrl+C does (on a selection), and so does Ctrl+V in insert mode. Elsewhere "
                    + "Ctrl+V starts a visual block, and Shift+Insert pastes.")],
                ["\"a … \"z", "Named registers, e.g. `\"ayw`. `\"A` appends to `a`."],
                ["\"0  \"_", "The last yank; and the black hole, e.g. `\"_dd` deletes without "
                    + "changing any register."],
                ["\"1 … \"9  \"-", "Deleted or changed lines, the newest in `1`; text deleted "
                    + "within a line."],
                ["\".  \":  \"/  \"%", "The last text typed, command line and search, and the "
                    + "file (or dir) open. They can only be pasted."],
                ["qa … q", "Record the keys you type into register `a`. `qA` appends to it."],
                ["@a  3@a  @@", "Run the macro in `a`, three times, or the last one run again. "
                    + "`u` undoes all of a run. A long one shows how far it is; Esc or Ctrl-C stops it "
                    + "(so do `5000u`, `5000 Ctrl-R` and `100@:`)."]
            ]
        },
        {
            title: "Visual block and multiple cursors",
            tags: ["block", "visualblock", "ctrl-v", "<c-v>", "cursors", "cursor", "multiple", "multi",
                "alt-click", "click"],
            rows: [
                ["Ctrl-V", "Visual block. On Windows too, where Ctrl+V pastes only in insert mode."],
                ["I  A  c", "In a block: type on every line of it at once."],
                ["$", "In a block: reach the end of every line."],
                [altKey + "click", "Add a cursor, or remove one. A plain click goes back to one."],
                ["", "With several cursors, motions and edits happen at each, each with its own "
                    + "registers. Esc goes back to one cursor."]
            ]
        },
        {
            title: "Hidden text",
            tags: ["hide", "reveal", "icon", "icons", "id", "gh"],
            rows: [
                ["icons", "In the listing, each icon hides its entry's ID. The cursor can't go on it, but "
                    + "whole lines take it along: yank, delete and paste them (see `:h listing`)."],
                ["gh", "Show the text behind the icon of the cursor's line, unless there's a warning or "
                    + "error under the cursor (so does resting the mouse on the icon). An ID shows as the "
                    + "path it stands for, even if its line renames it."],
                ["", "Yanks, undo and copying keep the hidden text. Other apps get the icons."]
            ]
        },
        {
            title: "Warnings and errors",
            tags: ["warning", "warnings", "error", "errors", "diagnostics", "squiggle"],
            rows: [
                ["", "Koil's problems with the listing get a wavy underline, orange or red, and a message "
                    + "after the end of their line, as in VS Code. An error (like a name written twice) "
                    + "stops Space Space and applying; a warning (like a name a shell needs quoted) doesn't. "
                    + "A name Windows can't use is a warning, but an error on Windows."],
                ["gh", "Show the message of the warning or error under the cursor (so does resting the "
                    + "mouse on it, or on the message)."]
            ]
        },
        {
            title: "Other keys",
            tags: ["keys", "other", "ctrl-a", "ctrl-x", "g?", "rot13", "ctrl-e", "ctrl-y", "scroll", "zoom",
                "settings", "undo", "gv", "zz"],
            rows: [
                ["Ctrl-A  Ctrl-X", "Add to or subtract from the number under or after the cursor."],
                ["g?  g~  gu  gU", "ROT13, toggle case, lowercase, uppercase (with a motion, e.g. `g?w`)."],
                ["Ctrl-E  Ctrl-Y", "Scroll a line down or up. The cursor stays, unless it would leave the screen."],
                ["zz  zt  zb", "Scroll the cursor's line to the middle, top or bottom."],
                ["gv", "Select the last visual selection again."],
                [isMac ? "⌘Z  ⇧⌘Z" : "Ctrl+Z  Ctrl+Shift+Z", "Undo and redo, the same as `u` and `Ctrl-R`."],
                [isMac ? "⌘+  ⌘-  ⌘0" : "Ctrl+=  Ctrl+-  Ctrl+0", "Zoom in, out, back to the size in Settings."],
                [cmdKey + ",", "Settings: font size, line numbers, theme."]
            ]
        }
    ]

    // Opens the help at the section for `topic` (all of it if ""). False if
    // there's no help for it.
    function show(topic) {
        const t = topic.trim().toLowerCase().replace(/^:/, "").replace(/^'(.*)'$/, "$1");
        const i = t === "" ? 0 : sections.findIndex(s => s.tags.includes(t));
        if (i < 0)
            return false;
        heading = "Koil Help";
        shownSections = sections;
        open();
        shownSection = i;
        showSection();
        return true;
    }

    // Opens the box with `title` over `rows` of [keys, text], both shown
    // as they are in the editor's font, the keys taking `keyColumns`
    // characters (:reg).
    function showList(title, rows, keyColumns) {
        heading = title;
        shownSections = [{ title: "", rows: rows, plain: true, keyColumns: keyColumns }];
        open();
        shownSection = 0;
        showSection();
    }

    // The section :help went to. Its text is laid out over the first frames,
    // so it's scrolled to again as the layout changes, until the user scrolls.
    property int shownSection: -1

    function showSection() {
        const item = shownSection >= 0 ? sectionRepeater.itemAt(shownSection) : null;
        if (item)
            scroller.contentY = Math.min(item.y, scroller.maxY);
    }

    function scrollBy(dy) {
        shownSection = -1;
        scroller.contentY = Math.max(0, Math.min(scroller.maxY, scroller.contentY + dy));
    }

    // The text with a selection. Each text selects on its own, so selecting
    // in one clears the last one.
    property TextEdit selected: null

    function copySelection() {
        if (selected && selected.selectedText !== "")
            selected.copy();
    }

    // `code` in the editor's font, the rest as plain text.
    function styled(text) {
        const escaped = text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        return escaped.replace(/`([^`]+)`/g, "<span style=\"font-family:'" + monoFamily + "'\">$1</span>");
    }

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(parent ? parent.width - 48 * zoom : 700, 760 * zoom)
    height: Math.min(parent ? parent.height - 48 * zoom : 500, body.height + header.height + 2 * padding)
    padding: 16 * zoom
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onClosed: {
        if (selected)
            selected.deselect();
    }

    Overlay.modal: Rectangle {
        color: help.theme.dark ? "#60000000" : "#30000000"
    }

    FontMetrics {
        id: monoMetrics

        font.family: help.monoFamily
        font.pixelSize: Math.round(13 * help.zoom)
    }

    background: Panel {
        theme: help.theme
        raised: true
    }

    // Selectable, but never focused, so keys stay with the help (which
    // forwards Copy, see copySelection).
    component HelpText: TextEdit {
        id: helpText

        readOnly: true
        selectByMouse: true
        activeFocusOnPress: false
        persistentSelection: true
        selectionColor: help.theme.highlight
        selectedTextColor: help.theme.highlightedText
        onSelectedTextChanged: {
            if (selectedText === "" || help.selected === helpText)
                return;
            if (help.selected)
                help.selected.deselect();
            help.selected = helpText;
        }

        HoverHandler {
            cursorShape: Qt.IBeamCursor
        }
    }

    contentItem: Item {
        Item {
            id: header

            width: parent.width
            height: title.height + 12 * help.zoom

            HelpText {
                id: title

                text: help.heading
                font.pixelSize: Math.round(18 * help.zoom)
                font.bold: true
                color: help.theme.text
            }
            HelpText {
                anchors.right: parent.right
                anchors.baseline: title.baseline
                text: "Esc or q to close · j k to scroll"
                font.pixelSize: Math.round(12 * help.zoom)
                color: help.theme.dim
            }
        }

        Flickable {
            id: scroller

            readonly property real maxY: Math.max(0, contentHeight - height)

            anchors.top: header.bottom
            anchors.bottom: parent.bottom
            width: parent.width
            contentWidth: width
            contentHeight: body.height
            clip: true
            focus: true
            // Not interactive, since a drag selects text; the wheel scrolls it.
            interactive: false

            ScrollBar.vertical: ScrollBar {
                id: scrollBar

                onPressedChanged: help.shownSection = -1
            }

            onMaxYChanged: help.showSection()

            // The trackpad too, which a WheelHandler leaves out by default.
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => help.scrollBy(-(event.pixelDelta.y || event.angleDelta.y / 120 * 3 * help.lineStep))
            }

            // As in a vim help buffer, and the usual keys.
            Keys.onPressed: event => {
                const ctrl = event.modifiers & (help.isMac ? Qt.MetaModifier : Qt.ControlModifier);
                const page = height - help.lineStep;
                if (event.matches(StandardKey.Copy))
                    help.copySelection();
                else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q && !event.modifiers)
                    help.close();
                else if (event.key === Qt.Key_J && !ctrl || event.key === Qt.Key_Down || ctrl && event.key === Qt.Key_E)
                    help.scrollBy(help.lineStep);
                else if (event.key === Qt.Key_K && !ctrl || event.key === Qt.Key_Up || ctrl && event.key === Qt.Key_Y)
                    help.scrollBy(-help.lineStep);
                else if (ctrl && event.key === Qt.Key_D)
                    help.scrollBy(height / 2);
                else if (ctrl && event.key === Qt.Key_U)
                    help.scrollBy(-height / 2);
                else if (ctrl && event.key === Qt.Key_F || event.key === Qt.Key_PageDown || event.key === Qt.Key_Space)
                    help.scrollBy(page);
                else if (ctrl && event.key === Qt.Key_B || event.key === Qt.Key_PageUp)
                    help.scrollBy(-page);
                else if (event.key === Qt.Key_G && event.modifiers & Qt.ShiftModifier || event.key === Qt.Key_End)
                    help.scrollBy(maxY);
                else if (event.key === Qt.Key_G || event.key === Qt.Key_Home)
                    help.scrollBy(-contentY);
                else
                    return;
                event.accepted = true;
            }

            Column {
                id: body

                width: scroller.width - 12 * help.zoom // clear of the scroll bar
                spacing: 18 * help.zoom
                onHeightChanged: help.showSection()

                Repeater {
                    id: sectionRepeater

                    model: help.shownSections

                    Column {
                        id: section

                        required property var modelData

                        width: body.width
                        spacing: 6 * help.zoom

                        HelpText {
                            visible: !!section.modelData.title
                            text: section.modelData.title
                            font.pixelSize: Math.round(15 * help.zoom)
                            font.bold: true
                            color: help.theme.accent
                        }
                        HelpText {
                            width: parent.width
                            visible: !!section.modelData.intro
                            text: help.styled(section.modelData.intro || "")
                            textFormat: TextEdit.RichText
                            wrapMode: TextEdit.Wrap
                            font.pixelSize: Math.round(13 * help.zoom)
                            color: help.theme.text
                        }
                        Repeater {
                            model: section.modelData.rows

                            Row {
                                id: row

                                required property var modelData

                                spacing: 12 * help.zoom

                                HelpText {
                                    id: keysText

                                    width: section.modelData.keyColumns
                                        ? Math.ceil(section.modelData.keyColumns * monoMetrics.averageCharacterWidth)
                                        : Math.round(body.width * 0.34)
                                    text: row.modelData[0]
                                    textFormat: TextEdit.PlainText
                                    wrapMode: TextEdit.Wrap
                                    font.family: help.monoFamily
                                    font.pixelSize: Math.round(13 * help.zoom)
                                    color: help.theme.text
                                }
                                HelpText {
                                    width: body.width - keysText.width - row.spacing
                                    text: section.modelData.plain ? row.modelData[1] : help.styled(row.modelData[1])
                                    textFormat: section.modelData.plain ? TextEdit.PlainText : TextEdit.RichText
                                    wrapMode: section.modelData.plain ? TextEdit.WrapAnywhere : TextEdit.Wrap
                                    font.family: section.modelData.plain ? help.monoFamily : help.font.family
                                    font.pixelSize: Math.round(13 * help.zoom)
                                    color: help.theme.text
                                }
                            }
                        }
                        HelpText {
                            width: parent.width
                            visible: !!section.modelData.note
                            text: help.styled(section.modelData.note || "")
                            textFormat: TextEdit.RichText
                            wrapMode: TextEdit.Wrap
                            font.pixelSize: Math.round(12 * help.zoom)
                            color: help.theme.dim
                        }
                    }
                }
            }
        }

        // A press anywhere but on the selected text (or the scroll bar)
        // clears the selection, as in other apps. The handler only watches,
        // so the press goes on to what's under it. Not a MouseArea, which
        // would show its arrow cursor over the text's I-beam.
        Item {
            id: pressWatcher

            anchors.fill: parent
            anchors.margins: -help.padding
            z: 1

            PointHandler {
                acceptedButtons: Qt.LeftButton
                onActiveChanged: {
                    const s = help.selected, p = point.position;
                    if (active && s && !s.contains(pressWatcher.mapToItem(s, p))
                        && !scrollBar.contains(pressWatcher.mapToItem(scrollBar, p)))
                        s.deselect();
                }
            }
        }
    }
}
