pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

import "text.js" as Txt

// :help, a box over the editor with what isn't obvious: Koil's listing,
// :set and its forms, the commands, search, registers and macros, visual
// block and multiple cursors, hidden text and other keys. :help topic scrolls to a section.
// :reg shows the registers in it too (showList).
// Keys scroll it as in a vim help buffer, / and ? search it (see Search);
// Esc or q closes it. Its text can be selected with the mouse and copied.
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
                "gr", "gs", "sort", "sorting", "_", "scratch", "scratchpad"],
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
                ["`Space u`  `u`", "Undo applies, picked from all of them, also those of earlier sessions, "
                    + "newest first (`u` once there's nothing left to undo). The last one is picked; "
                    + "picking an older one picks the newer ones that changed the same paths. "
                    + "Deleted files come back from the trash."],
                ["`Enter`", "Open the dir or file on the line. A new file is created first, after asking."],
                ["`Shift+Enter`", "Vim's `Enter`: the first character of the next line."],
                ["`-`", "Open the dir above (`3-`: three up). In a file: back to the listing."],
                ["`_`", "The scratchpad: text of your own, never saved, kept as you left it until Koil "
                    + "quits. `_` or `-` there goes back to where you were."],
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
                ["`gs`", "Sort: shows by what, then a key picks it, like `gss` by size (biggest first) and "
                    + "`gsS` the other way round, or `gsd` by size on disk (what files take up: less if "
                    + "compressed, a whole block if small" + (Qt.platform.os === "windows"
                        ? "; slower, as every file is opened" : "") + "). Dirs stay first. By a size or a "
                    + "date, each line shows it after its end. A dir's size is counted in the background, "
                    + "its dots coming and going until it is; once all are, the dirs are sorted by them."],
                [isMac ? "`⇧⌘O`" : "`Ctrl+Shift+O`", "Open a folder (`" + cmdKey + "O`: a file)."]
            ]
        },
        {
            title: "Options (:set)",
            tags: ["set", "se", "options", "option", "fontsize", "fs", "guifont", "gfn", "font",
                "number", "nu", "relativenumber", "rnu", "sidescrolloff", "siso", "hidden", "hid", "gitignore",
                "ignore", "regex", "re", "sortreverse", "sr"],
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
                ["`regex`  `re`", "Read the path as a regex, not a glob. `,` is any character but `/`."],
                ["`sort`", "What the listing is sorted by (see `gs`), like `:set sort=size`: `name`, "
                    + "`natural`, `extension`, `size`, `disk`, `modified`, `created` or `accessed`. Default "
                    + "`name`."],
                ["`sortreverse`  `sr`", "Sort the other way round."]
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
                    "In the find bar: match case, whole word, regular expression."],
                ["`↑`  `↓`", "In the find bar: earlier and later finds (or replacements)."]
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
        clearSearch();
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
        clearSearch();
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

    // Text with `code` as the text it shows: each code without its
    // backticks, and the spaces between collapsed, as rich text shows
    // them; and where each code is in it. `plain` text is as it is.
    function parseCode(text, plain) {
        if (plain)
            return { text: text, codes: [] };
        const codes = [];
        let shown = "";
        text.split("`").forEach((part, i) => {
            if (i % 2 === 1)
                codes.push({ start: shown.length, text: part });
            else
                part = part.replace(/ +/g, " ");
            shown += part;
        });
        return { text: shown, codes: codes };
    }

    // The rich text that shows parsed text (see parseCode): its codes in
    // the editor's font, with letter spacing on the characters before and
    // at the end of each, which makes room for its shade and copies as
    // nothing, and the search matches in `marks` ([start, end, current])
    // in black, as they're on a highlight. Spaces in a code (or in plain
    // text) don't break or collapse, and copy as spaces.
    function codeHtml(parsed, marks, plain) {
        const t = parsed.text;
        const inCode = 1, spaced = 2, marked = 4;
        const flags = new Uint8Array(t.length);
        // Letter spacing goes after a character, so on both of a pair of
        // surrogates.
        const space = i => {
            flags[i] |= spaced;
            if (i > 0 && /[\udc00-\udfff]/.test(t[i]))
                flags[i - 1] |= spaced;
        };
        for (const code of parsed.codes) {
            const end = code.start + code.text.length;
            for (let i = code.start; i < end; i++)
                flags[i] |= inCode;
            if (code.start > 0)
                space(code.start - 1);
            space(end - 1);
        }
        for (const mark of marks) {
            for (let i = mark[0]; i < mark[1]; i++)
                flags[i] |= marked;
        }
        let html = "";
        for (let i = 0, j; i < t.length; i = j) {
            const f = flags[i];
            for (j = i + 1; j < t.length && flags[j] === f;)
                j++;
            let run = t.slice(i, j).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
            if (plain || f & inCode)
                run = run.replace(/ /g, " ");
            const style = (f & inCode ? "font-family:'" + monoFamily + "';" : "")
                + (f & spaced ? "letter-spacing:" + codePadding + "px;" : "") + (f & marked ? "color:black;" : "");
            html += style ? "<span style=\"" + style + "\">" + run + "</span>" : run;
        }
        return html;
    }

    // ---- Search ------------------------------------------------------------
    // As vim's: / and ? type a search (on the search line, at the bottom),
    // highlighting its matches and going to the one Enter goes to as it's
    // typed; n and N go on. A search goes from the match it went to last,
    // if that's in view, else from the top of the view. Esc clears the
    // highlights, and then closes the help.

    // The search being typed ("/" or "?"), or "".
    property string searchKind: ""
    // The pattern whose matches are highlighted ("" for none), the last one
    // searched for (which n searches for again), and which way.
    property string searchPattern: ""
    property string lastPattern: ""
    property bool lastForward: true
    // The match a search went to (in matches), or -1.
    property int matchIndex: -1
    // What the search line says after a search went round the end, or
    // found nothing (searchFailed).
    property string searchMessage: ""
    property bool searchFailed: false
    // The patterns searched for (the newest last), which Up and Down go
    // through as a search is typed (from historyAt, the one shown).
    property var searchHistory: []
    property int historyAt: -1
    property string typedSearch: ""
    // The view, highlights and match before a search was typed, which
    // cancelling it goes back to, and the match it goes from (or null).
    property var searchStart: null
    // The CodeTexts by key, to find a match on the screen.
    property var textItems: ({})

    readonly property bool searchShown: searchPattern !== "" || searchMessage !== ""

    // Every text of shownSections, in order, as search sees them ({ key,
    // text }, where key is CodeText's), and each key's place in that order.
    readonly property var searchTexts: {
        const list = [], order = {};
        shownSections.forEach((section, s) => {
            const add = (part, markup) => {
                if (!markup)
                    return;
                order[s + "/" + part] = list.length;
                list.push({ key: s + "/" + part, text: parseCode(markup, !!section.plain).text });
            };
            add("title", section.title);
            add("intro", section.intro);
            section.rows.forEach((row, r) => {
                add(r + "k", row[0]);
                add(r + "t", row[1]);
            });
            add("note", section.note);
        });
        return { list: list, order: order };
    }

    // Each match of searchPattern: { key, start, end }, in order. Empty
    // ones don't count.
    readonly property var matches: {
        if (searchPattern === "")
            return [];
        const re = Txt.searchRegExp(searchPattern), found = [];
        for (const t of searchTexts.list) {
            re.lastIndex = 0;
            let m;
            while ((m = re.exec(t.text)) !== null) {
                if (m[0] === "")
                    re.lastIndex++;
                else
                    found.push({ key: t.key, start: m.index, end: m.index + m[0].length });
            }
        }
        return found;
    }

    // Each text's matches, as CodeText.marks: "start,end,current;…" (a
    // string, so a text whose matches stay the same isn't laid out again).
    readonly property var matchMarks: {
        const marks = {};
        matches.forEach((m, i) => {
            const mark = m.start + "," + m.end + "," + (i === matchIndex ? 1 : 0);
            marks[m.key] = marks[m.key] ? marks[m.key] + ";" + mark : mark;
        });
        return marks;
    }

    // Where match m's line is in the body.
    function matchY(m) {
        const item = textItems[m.key];
        return item ? item.mapToItem(body, 0, item.positionToRectangle(m.start).y).y : 0;
    }

    function inView(m) {
        const y = matchY(m);
        return y >= scroller.contentY && y < scroller.contentY + scroller.height;
    }

    // Scrolls match i to the middle, if it's out of view.
    function reveal(i) {
        shownSection = -1;
        const item = textItems[matches[i].key];
        if (!item)
            return;
        const height = item.positionToRectangle(matches[i].start).height;
        const y = matchY(matches[i]);
        if (y < scroller.contentY || y + height > scroller.contentY + scroller.height)
            scroller.contentY = Math.max(0, Math.min(scroller.maxY, y - (scroller.height - height) / 2));
    }

    // The match a search goes to, from `from` (a match, maybe of another
    // search), else from the top of the view, going round at the end:
    // { index, wrapped }, or null if there's none.
    function nextMatch(forward, from) {
        const order = searchTexts.order;
        const compare = m => from ? order[m.key] - order[from.key] || m.start - from.start
            : matchY(m) >= scroller.contentY ? 1 : -1;
        if (forward) {
            const i = matches.findIndex(m => compare(m) > 0);
            return i >= 0 ? { index: i, wrapped: false } : matches.length ? { index: 0, wrapped: true } : null;
        }
        for (let i = matches.length - 1; i >= 0; i--) {
            if (compare(matches[i]) < 0)
                return { index: i, wrapped: false };
        }
        return matches.length ? { index: matches.length - 1, wrapped: true } : null;
    }

    // Searches for lastPattern from `from` (see nextMatch).
    function goToMatch(forward, from) {
        searchPattern = lastPattern;
        const target = nextMatch(forward, from);
        matchIndex = target ? target.index : -1;
        searchFailed = !target;
        searchMessage = !target ? "E486: Pattern not found: " + lastPattern
            : !target.wrapped ? "" : forward ? "search hit BOTTOM, continuing at TOP"
            : "search hit TOP, continuing at BOTTOM";
        if (target)
            reveal(target.index);
    }

    // n and N (and Find Next and Previous, `forward` or not).
    function searchAgain(forward) {
        if (lastPattern === "") {
            searchFailed = true;
            searchMessage = "E35: No previous regular expression";
            return;
        }
        const from = matchIndex >= 0 && inView(matches[matchIndex]) ? matches[matchIndex] : null;
        goToMatch(forward, from);
    }

    // / or ? (and Find). Find while a search is typed selects it.
    function startSearch(kind) {
        if (searchKind) {
            searchField.selectAll();
            return;
        }
        const from = matchIndex >= 0 && inView(matches[matchIndex]) ? matches[matchIndex] : null;
        searchStart = { pattern: searchPattern, index: matchIndex, from: from, contentY: scroller.contentY };
        shownSection = -1;
        searchMessage = "";
        historyAt = -1;
        searchField.text = "";
        searchKind = kind;
        searchField.forceActiveFocus();
    }

    // Shows the matches of the search being typed, and the one Enter would
    // go to (vim's 'incsearch').
    function previewSearch(pattern) {
        scroller.contentY = searchStart.contentY;
        searchPattern = pattern || searchStart.pattern;
        const target = pattern ? nextMatch(searchKind === "/", searchStart.from) : null;
        matchIndex = pattern ? (target ? target.index : -1) : searchStart.index;
        if (target)
            reveal(target.index);
    }

    // Enter (`accept`), or Esc. An empty search searches for the last
    // pattern again.
    function finishSearch(accept) {
        const typed = searchField.text, forward = searchKind === "/";
        searchKind = "";
        scroller.forceActiveFocus();
        scroller.contentY = searchStart.contentY;
        searchPattern = searchStart.pattern;
        matchIndex = searchStart.index;
        if (!accept || !typed && !lastPattern)
            return;
        if (typed) {
            searchHistory = searchHistory.filter(p => p !== typed).concat([typed]).slice(-100);
            lastPattern = typed;
        }
        lastForward = forward;
        goToMatch(forward, searchStart.from);
    }

    // Up (`back`) and Down while a search is typed.
    function browseHistory(back) {
        if (historyAt < 0) {
            if (!back || searchHistory.length === 0)
                return;
            typedSearch = searchField.text;
            historyAt = searchHistory.length - 1;
        } else if (back) {
            historyAt = Math.max(0, historyAt - 1);
        } else if (++historyAt >= searchHistory.length) {
            historyAt = -1;
        }
        searchField.text = historyAt < 0 ? typedSearch : searchHistory[historyAt];
    }

    // Whether item is in the help (as the item with the keys, say).
    function holds(item) {
        for (let i = item; i; i = i.parent) {
            if (i === contentItem.parent)
                return true;
        }
        return false;
    }

    function clearSearch() {
        searchKind = "";
        searchPattern = "";
        matchIndex = -1;
        searchMessage = "";
        searchFailed = false;
    }

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(parent ? parent.width - 48 * zoom : 700, 760 * zoom)
    height: Math.min(parent ? parent.height - 48 * zoom : 500,
        body.height + header.height + searchLine.height + 2 * padding)
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
    // drawn behind the text so it still selects and copies, and its search
    // matches highlighted. `plain` shows the text as it is (a :reg list).
    component CodeText: HelpText {
        id: codeText

        property string markup
        property bool plain
        // Which text of shownSections it is ("" for none), which search
        // goes through (see searchTexts).
        property string key
        readonly property var parsed: help.parseCode(markup, plain)
        // Its search matches, if search went through its text: the
        // Repeater deletes the old texts some time after shownSections
        // changes, and those mustn't take the new ones' matches.
        readonly property string marks: key !== "" && help.matchMarks[key]
            && help.searchTexts.list[help.searchTexts.order[key]].text === parsed.text ? help.matchMarks[key] : ""
        readonly property var markList: marks === "" ? [] : marks.split(";").map(m => m.split(",").map(Number))
        // The shades and highlights are placed once the text is laid out.
        readonly property var layout: [text, width, contentWidth, contentHeight]
        property var shades: []
        property var highlights: []
        readonly property FontMetrics codeMetrics: FontMetrics {
            font.family: help.monoFamily
            font.pixelSize: codeText.font.pixelSize
        }
        readonly property FontMetrics textMetrics: FontMetrics {
            font: codeText.font
        }

        function inCode(i) {
            return parsed.codes.some(code => i >= code.start && i < code.start + code.text.length);
        }

        // Rectangles over the characters [start, end), one per line they're
        // on (a code can break at a `/` or `-`): from `before` px before
        // start (`pad` on the next lines) to where the character after end
        // starts (past its letter spacing), less `trim`, or `pad` past a
        // line's last character.
        function rectsOver(start, end, before, pad, trim) {
            const rects = [];
            let from = positionToRectangle(start), left = from.x - before;
            for (let i = start + 1; i <= end; i++) {
                const at = positionToRectangle(i);
                if (at.y === from.y && i < end)
                    continue;
                const right = at.y === from.y ? at.x - trim : positionToRectangle(i - 1).x
                    + (inCode(i - 1) ? codeMetrics : textMetrics).advanceWidth(parsed.text[i - 1]) + pad;
                rects.push(Qt.rect(left, from.y, right - left, from.height));
                from = at;
                left = at.x - pad;
            }
            return rects;
        }

        // A shade behind each code, and a highlight behind each match. One
        // that starts or ends with a code covers its shade there.
        function place() {
            const pad = help.codePadding;
            const starts = parsed.codes.map(code => code.start);
            const s = [], h = [];
            for (const code of parsed.codes)
                s.push(...rectsOver(code.start, code.start + code.text.length, pad, pad, 0));
            for (const [start, end, current] of markList) {
                for (const r of rectsOver(start, end, starts.includes(start) ? pad : 0, 0, starts.includes(end) ? pad : 0))
                    h.push({ rect: r, current: current === 1 });
            }
            shades = s;
            highlights = h;
        }

        // Room for a shade at a line's start (so all text has it).
        leftPadding: help.codePadding
        text: help.codeHtml(parsed, markList, plain)
        textFormat: TextEdit.RichText
        wrapMode: TextEdit.Wrap
        onLayoutChanged: Qt.callLater(place)
        Component.onCompleted: {
            if (key !== "")
                help.textItems[key] = codeText;
        }
        Component.onDestruction: {
            if (help.textItems[key] === codeText)
                delete help.textItems[key];
        }

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
        Repeater {
            model: codeText.highlights

            Rectangle {
                required property var modelData

                z: -0.5
                x: modelData.rect.x
                y: modelData.rect.y
                width: modelData.rect.width
                height: modelData.rect.height
                radius: 3 * help.zoom
                color: modelData.current ? help.theme.currentMatch : help.theme.searchMatch
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
                markup: "`/` to search · `j` `k` to scroll · `Esc` or `q` to close"
                font.pixelSize: Math.round(12 * help.zoom)
                color: help.theme.dim
            }
        }

        Flickable {
            id: scroller

            readonly property real maxY: Math.max(0, contentHeight - height)

            anchors.top: header.bottom
            anchors.bottom: searchLine.top
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
                else if (event.key === Qt.Key_Escape && help.searchShown)
                    help.clearSearch();
                else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q && !event.modifiers)
                    help.close();
                else if (!ctrl && (event.text === "/" || event.text === "?"))
                    help.startSearch(event.text);
                else if (!ctrl && (event.text === "n" || event.text === "N"))
                    help.searchAgain(event.text === "n" ? help.lastForward : !help.lastForward);
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
                        required property int index

                        width: body.width
                        spacing: 6 * help.zoom

                        CodeText {
                            visible: !!section.modelData.title
                            key: section.index + "/title"
                            markup: section.modelData.title
                            font.pixelSize: Math.round(15 * help.zoom)
                            font.bold: true
                            color: help.theme.accent
                        }
                        CodeText {
                            width: parent.width
                            visible: !!section.modelData.intro
                            key: section.index + "/intro"
                            markup: section.modelData.intro || ""
                            font.pixelSize: Math.round(13 * help.zoom)
                            color: help.theme.text
                        }
                        Repeater {
                            model: section.modelData.rows

                            Row {
                                id: row

                                required property var modelData
                                required property int index

                                spacing: 12 * help.zoom

                                CodeText {
                                    id: keysText

                                    width: section.modelData.keyColumns
                                        ? Math.ceil(section.modelData.keyColumns * monoMetrics.averageCharacterWidth)
                                        : Math.round(body.width * 0.34)
                                    key: section.index + "/" + row.index + "k"
                                    markup: row.modelData[0]
                                    plain: !!section.modelData.plain
                                    font.family: help.monoFamily
                                    font.pixelSize: Math.round(13 * help.zoom)
                                    color: help.theme.text
                                }
                                CodeText {
                                    width: body.width - keysText.width - row.spacing
                                    key: section.index + "/" + row.index + "t"
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
                            key: section.index + "/note"
                            markup: section.modelData.note || ""
                            font.pixelSize: Math.round(12 * help.zoom)
                            color: help.theme.dim
                        }
                    }
                }
            }
        }

        // The search line, as vim's command line: the search being typed,
        // else the last one, or what it says, and which match it's at.
        Item {
            id: searchLine

            anchors.bottom: parent.bottom
            width: parent.width
            height: visible ? searchPrefix.height + 6 * help.zoom : 0
            visible: help.searchKind !== "" || help.searchShown

            Rectangle {
                width: parent.width
                height: 1
                color: help.theme.panelBorder
            }
            Text {
                id: searchPrefix

                anchors.left: parent.left
                anchors.leftMargin: help.codePadding
                anchors.bottom: parent.bottom
                width: help.searchKind ? implicitWidth : Math.min(implicitWidth, matchCount.x - x - 12 * help.zoom)
                text: help.searchKind || help.searchMessage || (help.lastForward ? "/" : "?") + help.lastPattern
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.family: help.monoFamily
                font.pixelSize: Math.round(13 * help.zoom)
                color: help.searchFailed && !help.searchKind ? help.theme.error : help.theme.text
            }
            TextInput {
                id: searchField

                anchors.left: searchPrefix.right
                anchors.right: matchCount.left
                anchors.rightMargin: 12 * help.zoom
                anchors.baseline: searchPrefix.baseline
                visible: help.searchKind !== ""
                clip: true
                font: searchPrefix.font
                color: help.theme.text
                selectByMouse: true
                selectionColor: help.theme.highlight
                selectedTextColor: help.theme.highlightedText
                onTextChanged: {
                    if (help.searchKind)
                        help.previewSearch(text);
                }
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        help.finishSearch(true);
                    else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace && text === "")
                        help.finishSearch(false);
                    else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down)
                        help.browseHistory(event.key === Qt.Key_Up);
                    else
                        return;
                    event.accepted = true;
                }
            }
            Text {
                id: matchCount

                anchors.right: parent.right
                anchors.rightMargin: help.codePadding
                anchors.baseline: searchPrefix.baseline
                text: help.matchIndex >= 0 ? "[" + (help.matchIndex + 1) + "/" + help.matches.length + "]" : ""
                font: searchPrefix.font
                color: help.theme.dim
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
