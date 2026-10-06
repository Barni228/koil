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
    // intro and note, and rows of [keys, what they do]. `code` in any of
    // them (a key, in keys) is shown in the editor's font, on a shade of
    // its own as in a Tip (see CodeText).
    readonly property var sections: [
        {
            title: "The listing",
            tags: ["koil", "listing", "list", "entry", "entries", "space", "update", "apply", "-", "enter",
                "<cr>", "cr", "path", "pattern", "glob", "folder", "dir", "undo", "tab", "<tab>", "g.", "gi",
                "gr"],
            intro: "Koil shows a dir as text, a line per entry: its icon (which hides its ID), two spaces "
                + "and its name, with `/` after a dir's. Edit a name to rename, delete lines to delete, "
                + "copy lines to copy, and write new ones to create (`new.txt`, `new/dir/`). A line cut "
                + "and pasted in another dir moves. Nothing changes on disk until you apply, and changes "
                + "stay while you go to other dirs.",
            rows: [
                ["`" + cmdKey + "S`", "Update: read the edits and show the listing again."],
                ["`Space Space`  `:w`", "Apply the changes, listing them first (Settings can skip that). `:wq` "
                    + "then quits."],
                ["`Space a`", "Apply, always listing the changes first (so does File > Apply Changes…)."],
                ["󰄲", "In that list: `j` and `k` move, `Space`, `x` or a click picks or leaves out a change "
                    + "(with what it needs), and `a` picks all or none. What's left out is discarded."],
                ["`u`", "With nothing left to undo: undo the last apply, asking first. Deleted files come back "
                    + "from the trash."],
                ["`Enter`", "Open the dir or file on the line. A new file is created first, after asking."],
                ["`Shift+Enter`", "Vim's `Enter`: the first character of the next line."],
                ["`-`", "Open the dir above (`3-`: three up). In a file: back to the listing."],
                ["icons", "The cursor skips each line's icon and the spaces after it, so `0` goes to the "
                    + "name. `Backspace` there clears the icon (the entry becomes new), then joins lines."],
                ["quitting", "`:conf q` and `ZZ` ask to apply the changes first. In a file, quitting goes "
                    + "back to the listing while it has changes (`:qa!` still quits)."],
                ["path", "The field at the top: a dir or a glob, like `~/src/**/*.rs` (a regex with `:set "
                    + "regex`). Write `/`, also on Windows: in a pattern, `\\` escapes."],
                ["`Enter`  `Shift+Enter`", "In the path field: open it and go to the listing, or open it and "
                    + "stay."],
                ["`k`  `j`", "In the path field: the dirs listed before (`↑` and `↓` while typing)."],
                ["`Tab`", "Go between the listing and the path field (so does a click)."],
                ["`Tab`  `Shift+Tab`", "While typing a path: complete the dir, like a shell. With several to "
                    + "pick from, they go through them, and `Enter` takes one."],
                ["`g.`  `gi`  `gr`", "Toggle `:set hidden`, `gitignore` and `regex`, like the buttons beside "
                    + "the path."],
                [isMac ? "`⇧⌘O`" : "`Ctrl+Shift+O`", "Open a folder (`" + cmdKey + "O`: a file)."]
            ]
        },
        {
            title: "Options (:set)",
            tags: ["set", "se", "options", "option", "fontsize", "fs", "guifont", "gfn", "font",
                "number", "nu", "relativenumber", "rnu", "sidescrolloff", "siso", "hidden", "hid", "gitignore",
                "ignore", "regex", "re"],
            intro: "`:set` alone lists the options that aren't at their default. Several can be set at "
                + "once: `:set nu rnu fs=18`.",
            rows: [
                ["`fontsize`  `fs`", "Font size in points, 6 to 72. Default 16."],
                ["`guifont`  `gfn`", "An installed monospaced font. Default `" + defaultFontFamily
                    + "` (comes with Koil). Icons show in any font."],
                ["`number`  `nu`", "Line numbers."],
                ["`relativenumber`  `rnu`", "Line numbers counted from the cursor's line."],
                ["`sidescrolloff`  `siso`", "Columns kept in view beside the cursor. Default 4."],
                ["`hidden`  `hid`", "Show entries starting with `.`, and `../`."],
                ["`gitignore`  `ignore`", "Hide what git ignores, and `.git`."],
                ["`regex`  `re`", "Read the path as a regex, not a glob. `,` is any character but `/`."]
            ],
            note: "An entry with changes is shown even if it's hidden or ignored."
        },
        {
            title: "Setting an on/off option",
            tags: [],
            rows: [
                ["`:set nu`", "Turn it on."],
                ["`:set nonu`", "Turn it off."],
                ["`:set nu!`  `:set invnu`", "Toggle it."],
                ["`:set nu?`", "Show it: `number` or `nonumber`."],
                ["`:set nu&`", "Back to what Settings says."]
            ]
        },
        {
            title: "Setting a number option",
            tags: [],
            rows: [
                ["`:set fs=16`  `:set fs:16`", "Set it."],
                ["`:set fs+=2`  `fs-=2`  `fs^=2`", "Add, subtract, multiply."],
                ["`:set fs`  `:set fs?`", "Show it: `fontsize=16`."],
                ["`:set fs&`", "Back to the size in Settings."]
            ]
        },
        {
            title: "Setting the font",
            tags: [],
            rows: [
                ["`:set gfn=Monaco`", "Set it."],
                ["`:set gfn=Fira\\ Code`", "A backslash before a space."],
                ["`:set gfn`  `:set gfn?`", "Show it: `guifont=Monaco`."],
                ["`:set gfn&`  `:set gfn=`", "Back to the font in Settings."]
            ],
            note: "Zoom and `:set` last until Koil quits. Settings (`" + cmdKey + ",`) holds what Koil "
                + "starts with and `&` goes back to."
        },
        {
            title: "Commands",
            tags: ["commands", "command", "ex", "w", "write", "quit", "wq", "x", "confirm", "conf", "noh",
                "nohlsearch", "help", "h", "history"],
            rows: [
                ["`:w`", "Save (in the listing: apply)."],
                ["`:wq`  `:x`", "Save and quit."],
                ["`ZZ`", "Save and quit (in the listing: `:confirm q`)."],
                ["`:q`  `:qa`", "Quit, unless there are unsaved changes."],
                ["`:q!`  `ZQ`", "Quit without saving."],
                ["`:qa!`", "Quit without saving anything."],
                ["`:conf q`  `:confirm q`", "Quit, asking whether to save first (`y`, `n`, or `c` to cancel)."],
                ["`:42`  `:$`", "Go to line 42, or the last line."],
                ["`:noh`", "Clear the search highlights (so does `Esc` in normal mode)."],
                ["`:reg`  `:reg [names]`", "Show the registers, e.g. `:reg a0`."],
                ["`:h`  `:help [topic]`", "This help, e.g. `:h set`, `:h search`, `:h macros`."],
                ["`↑`  `↓`", "In the command line: earlier and later commands (or searches)."],
                ["`Ctrl-U`  `Ctrl-W`", "In the command line: delete to the start, or a word back."],
                ["`@:`", "Run the last command again."]
            ]
        },
        {
            title: "Search",
            tags: ["search", "/", "?", "regex", "regexp", "pattern", "find", "replace", "n", "*"],
            rows: [
                ["`/pattern`  `?pattern`", "Search forward or backward, with JavaScript regexes (`\\bword\\b`, "
                    + "`\\d{3}`), not vim's. Case counts only if there's an uppercase letter."],
                ["`n`  `N`", "Next or previous match."],
                ["`*`  `#`", "Search for the word under the cursor."],
                ["`" + cmdKey + "F`", "The find bar. Its matches are highlighted while it's open."],
                [isMac ? "`⌘G`  `⇧⌘G`" : "`F3`  `Shift+F3`  `Ctrl+G`  `Ctrl+Shift+G`",
                    "Next or previous find bar match."],
                [isMac ? "`⌘⌥F`" : "`Ctrl+H`", "Find and replace."],
                [isMac ? "`⌃⌥C`  `⌃⌥W`  `⌃⌥R`" : "`Alt+C`  `Alt+W`  `Alt+R`",
                    "In the find bar: match case, whole word, regular expression."]
            ]
        },
        {
            title: "Registers and macros",
            tags: ["registers", "register", "reg", "clipboard", "\"", "\"+", "+", "*", "\"0", "\"_", "\"-",
                "\"1", "\".", "\":", "\"/", "\"%", "macros", "macro",
                "q", "@", "@@", "record", "recording", "yank", "paste", "p", "y"],
            rows: [
                ["`\"+`  `\"*`", "The system clipboard, e.g. `\"+yy`. Plain `y` and `p` don't use it; "
                    + (isMac ? "`⌘C` and `⌘V` do." : "`Ctrl+C` does, and `Ctrl+V` while typing.")],
                ["`\"a` … `\"z`", "Named registers, e.g. `\"ayw`. `\"A` appends to `a`."],
                ["`\"0`  `\"_`", "The last yank; the black hole (`\"_dd` changes no register)."],
                ["`\"1` … `\"9`  `\"-`", "Deleted lines, the newest in `1`; text deleted within a line."],
                ["`\".`  `\":`  `\"/`  `\"%`", "The last insert, command and search, and the open file or dir."],
                ["`qa` … `q`", "Record keys into register `a`. `qA` appends to it."],
                ["`@a`  `3@a`  `@@`", "Run the macro in `a`, three times, or the last one again. `u` undoes a "
                    + "whole run, and `Esc` stops a long one."]
            ]
        },
        {
            title: "Visual block and multiple cursors",
            tags: ["block", "visualblock", "ctrl-v", "<c-v>", "cursors", "cursor", "multiple", "multi",
                "alt-click", "click"],
            rows: [
                ["`Ctrl-V`", "Visual block, also on Windows (where `Ctrl+V` pastes while typing)."],
                ["`I`  `A`  `c`", "In a block: type on every line of it at once."],
                ["`$`", "In a block: reach the end of every line."],
                ["`" + altKey + "click`", "Add or remove a cursor. A plain click goes back to one."],
                ["", "Motions and edits happen at every cursor, each with its own registers. `Esc` goes "
                    + "back to one."]
            ]
        },
        {
            title: "Hidden text",
            tags: ["hide", "reveal", "icon", "icons", "id", "gh"],
            rows: [
                ["icons", "In the listing, each icon hides its entry's ID, which whole lines take along."],
                ["`gh`", "Show what the line's icon hides: an ID shows as its path (so does resting the "
                    + "mouse on the icon)."],
                ["", "Yanks, undo and copying keep the hidden text. Other apps get the icons."]
            ]
        },
        {
            title: "Warnings and errors",
            tags: ["warning", "warnings", "error", "errors", "diagnostics", "squiggle"],
            rows: [
                ["", "Problems get a wavy underline and a message after the line. An error (like a name "
                    + "written twice) blocks updating and applying; a warning doesn't."],
                ["`gh`", "Show the message under the cursor (or rest the mouse on it)."]
            ]
        },
        {
            title: "Other keys",
            tags: ["keys", "other", "ctrl-a", "ctrl-x", "g?", "rot13", "ctrl-e", "ctrl-y", "scroll", "zoom",
                "settings", "undo", "gv", "zz"],
            rows: [
                ["`Ctrl-A`  `Ctrl-X`", "Add to or subtract from the number at or after the cursor."],
                ["`g?`  `g~`  `gu`  `gU`", "ROT13, toggle case, lowercase, uppercase (e.g. `g?w`)."],
                ["`Ctrl-E`  `Ctrl-Y`", "Scroll a line down or up."],
                ["`zz`  `zt`  `zb`", "Scroll the cursor's line to the middle, top or bottom."],
                ["`gv`", "Select the last visual selection again."],
                [isMac ? "`⌘Z`  `⇧⌘Z`" : "`Ctrl+Z`  `Ctrl+Shift+Z`",
                    "Undo and redo, like `u` and `Ctrl-R`."],
                [isMac ? "`⌘+`  `⌘-`  `⌘0`" : "`Ctrl+=`  `Ctrl+-`  `Ctrl+0`",
                    "Zoom in, out, or back to the Settings size."],
                ["`" + cmdKey + ",`", "Settings: font, line numbers, theme, when applying asks, start dir."]
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

    // How far a code's shade reaches past its text, as in a Tip.
    readonly property real codePadding: 4 * zoom

    // Text with `code` as rich text, the code in the editor's font, and
    // where each code is in it, to shade it (see CodeText). Letter spacing
    // on the characters before and at the end of a code makes room for
    // its shade, and copies as nothing. Spaces in a code don't break, and
    // copy as spaces.
    function parseCode(text) {
        const escape = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        const spaced = s => {
            const last = /[\udc00-\udfff]$/.test(s) ? 2 : 1;
            return s === "" ? "" : escape(s.slice(0, -last)) + "<span style=\"letter-spacing:" + codePadding
                + "px\">" + escape(s.slice(-last)) + "</span>";
        };
        const parts = text.split("`");
        const codes = [];
        let html = "", length = 0;
        parts.forEach((part, i) => {
            if (i % 2 === 1) {
                codes.push({ start: length, text: part });
                html += "<span style=\"font-family:'" + monoFamily + "'\">" + spaced(part.replace(/ /g, " "))
                    + "</span>";
            } else {
                part = part.replace(/ +/g, " "); // as rich text shows it
                html += i + 1 < parts.length ? spaced(part) : escape(part);
            }
            length += part.length;
        });
        return { html: html, codes: codes };
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

    // Text with `code` (see parseCode), each code on a shade of its own,
    // drawn behind the text so it still selects and copies. `plain` shows
    // the text as it is (a :reg list).
    component CodeText: HelpText {
        id: codeText

        property string markup
        property bool plain
        readonly property var parsed: plain ? { html: "", codes: [] } : help.parseCode(markup)
        // The shades are placed once the text is laid out.
        readonly property var layout: [text, width, contentWidth, contentHeight]
        property var shades: []
        readonly property FontMetrics codeMetrics: FontMetrics {
            font.family: help.monoFamily
            font.pixelSize: codeText.font.pixelSize
        }

        // A shade behind each code, one per line it's on (a code can break
        // at a `/` or `-`).
        function placeShades() {
            const pad = help.codePadding;
            const rects = [];
            for (const code of parsed.codes) {
                let from = positionToRectangle(code.start);
                for (let i = 1; i <= code.text.length; i++) {
                    const at = positionToRectangle(code.start + i);
                    if (at.y === from.y && i < code.text.length)
                        continue;
                    // At the code's end, the room after it is in `at`.
                    const right = at.y === from.y ? at.x : positionToRectangle(code.start + i - 1).x
                        + codeMetrics.advanceWidth(code.text[i - 1]) + pad;
                    rects.push(Qt.rect(from.x - pad, from.y, right - from.x + pad, from.height));
                    from = at;
                }
            }
            shades = rects;
        }

        // Room for a shade at a line's start (so all text has it).
        leftPadding: help.codePadding
        text: plain ? markup : parsed.html
        textFormat: plain ? TextEdit.PlainText : TextEdit.RichText
        wrapMode: TextEdit.Wrap
        onLayoutChanged: Qt.callLater(placeShades)

        Repeater {
            model: codeText.shades

            Rectangle {
                required property rect modelData

                z: -1
                x: modelData.x
                y: modelData.y
                width: modelData.width
                height: modelData.height
                radius: 3 * help.zoom
                color: help.theme.code
            }
        }
    }

    contentItem: Item {
        Item {
            id: header

            width: parent.width
            height: title.height + 12 * help.zoom

            HelpText {
                id: title

                leftPadding: help.codePadding // as CodeText's
                text: help.heading
                font.pixelSize: Math.round(18 * help.zoom)
                font.bold: true
                color: help.theme.text
            }
            CodeText {
                anchors.right: parent.right
                anchors.baseline: title.baseline
                markup: "`Esc` or `q` to close · `j` `k` to scroll"
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
                            leftPadding: help.codePadding
                            text: section.modelData.title
                            font.pixelSize: Math.round(15 * help.zoom)
                            font.bold: true
                            color: help.theme.accent
                        }
                        CodeText {
                            width: parent.width
                            visible: !!section.modelData.intro
                            markup: section.modelData.intro || ""
                            font.pixelSize: Math.round(13 * help.zoom)
                            color: help.theme.text
                        }
                        Repeater {
                            model: section.modelData.rows

                            Row {
                                id: row

                                required property var modelData

                                spacing: 12 * help.zoom

                                CodeText {
                                    id: keysText

                                    width: section.modelData.keyColumns
                                        ? Math.ceil(section.modelData.keyColumns * monoMetrics.averageCharacterWidth)
                                        : Math.round(body.width * 0.34)
                                    markup: row.modelData[0]
                                    plain: !!section.modelData.plain
                                    font.family: help.monoFamily
                                    font.pixelSize: Math.round(13 * help.zoom)
                                    color: help.theme.text
                                }
                                CodeText {
                                    width: body.width - keysText.width - row.spacing
                                    markup: row.modelData[1]
                                    plain: !!section.modelData.plain
                                    wrapMode: plain ? TextEdit.WrapAnywhere : TextEdit.Wrap
                                    font.family: plain ? help.monoFamily : help.font.family
                                    font.pixelSize: Math.round(13 * help.zoom)
                                    color: help.theme.text
                                }
                            }
                        }
                        CodeText {
                            width: parent.width
                            visible: !!section.modelData.note
                            markup: section.modelData.note || ""
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
