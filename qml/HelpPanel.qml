pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

import "text.js" as Txt

// :help, a box over the editor with what isn't obvious: Koil's listing,
// :set and its forms, the commands, shell commands, search, registers and
// macros, visual block and multiple cursors, marked lines, hidden text, the
// keys starting with g, z and Space, Ctrl keys and other keys.
// :help topic scrolls to a section, or a key's row (see show). :reg shows
// the registers in it too (showList), and :! what a command wrote
// (showText).
// Keys scroll it as in a vim help buffer, / and ? search it (see Search);
// Esc, q or Enter (as after vim's :!) closes it. Its text can be selected
// with the mouse and copied.
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
    // Where Space r shows an entry (and Space o opens it as from there).
    readonly property string fileManager: isMac ? "Finder" : Qt.platform.os === "windows" ? "Explorer"
        : "the file manager"
    // The shell :! runs commands in, unless Settings says otherwise.
    readonly property string systemShell: Qt.platform.os === "windows" ? "cmd.exe" : "$SHELL"
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
            tags: ["koil", "listing", "list", "entry", "entries", "update", "apply", "-", "enter",
                "<cr>", "cr", "path", "pattern", "glob", "folder", "dir", "undo", "tab", "<tab>", "g.", "gi",
                "gr", "gs", "sort", "sorting", "_", "scratch", "scratchpad", "reveal", "finder", "explorer",
                "app"],
            intro: "Koil shows a dir as text, a line per entry: its icon (which hides its ID), two spaces "
                + "and its name, with `/` after a dir's. Edit a name to rename, delete lines to delete, "
                + "copy lines to copy, and write new ones to create (`new.txt`, `new/dir/`). A line cut "
                + "and pasted in another dir moves. Nothing changes on disk until you apply, and changes "
                + "stay while you go to other dirs.",
            rows: [
                ["`" + cmdKey + "S`", "Update: read the edits and show the listing again."],
                ["`Space Space`  `:w`", "Apply the changes, listing them first (Settings can skip that). `:wq` "
                    + "then quits. In a file: save."],
                ["`Space a`", "Apply, always listing the changes first (so does File > Apply Changes…)."],
                ["󰄲", "In that list: `j` and `k` move, `Space`, `x` or a click picks or leaves out a change "
                    + "(with what it needs), and `a` picks all or none. What's left out is discarded."],
                ["`Space u`", "Undo applies, picked from all of them, also those of earlier sessions, "
                    + "newest first. Picking one picks the newer ones that changed the same paths. "
                    + "Deleted files come back from the trash. `d` there deletes the picked ones from "
                    + "the history instead, also those that can't be undone any more."],
                ["`u`", "Once there's nothing left to undo: undo the last apply, after listing what that "
                    + "does."],
                ["`Enter`", "Open the dir or file on the line. A new file is created first, after asking."],
                ["`Space r`", "Show the entry on the line in " + fileManager + " (from the path field, the "
                    + "open dir)."],
                ["`Space o`", "Open the entry on the line in its default app, as a double-click in "
                    + fileManager + " does (from the path field, the open dir)."],
                ["`!`", "Run a shell command on the entry on the line (or the marked ones: see `:h m`): "
                    + "`!git add` or `!rm`, then `Enter` (see `:h !`)."],
                ["`Shift+Enter`", "Vim's `Enter`: the first character of the next line."],
                ["`-`", "Open the dir above (`3-`: three up). In a file: back to the listing."],
                ["`_`", "The scratchpad: text of your own, never saved, kept as you left it until Koil "
                    + "quits. `_` or `-` there goes back to where you were, and `!` runs a command on the "
                    + "path on the line (`!rm`), as in the listing."],
                ["icons", "The cursor skips each line's icon and the spaces after it, so `0` goes to the "
                    + "name. `Backspace` there clears the icon (the entry becomes new), then joins lines."],
                ["quitting", "`:conf q` and `ZZ` ask to apply the changes first. In a file, quitting goes "
                    + "back to the listing while it has changes (`:qa!` still quits)."],
                ["path", "The field at the top: a dir or a glob, like `~/src/**/*.rs` (a regex with `:set "
                    + "regex`). Write `/`, also on Windows: in a pattern, `\\` escapes."],
                ["glob", "A dir matches with its `/`: `*` is only files, `*/` only dirs, `{*,*/}` both. "
                    + "`*` skips names starting with `.`, but `.*` and `**/.env` show them."],
                ["`Enter`  `Shift+Enter`", "In the path field: open it and go to the listing, or open it and "
                    + "stay."],
                ["`k`  `j`", "In the path field: the dirs listed before (`↑` and `↓` while typing)."],
                ["`Tab`", "Go between the listing and the path field (so does a click)."],
                ["`Tab`  `Shift+Tab`", "While typing a path: complete the dir, like a shell (if none starts "
                    + "with what's typed, one with its letters in order: `myt` gives `my_tools`). With "
                    + "several to pick from, they go through them, and `Enter` takes one."],
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
                "number", "nu", "relativenumber", "rnu", "syntax", "syn", "wrap", "sidescrolloff", "siso", "hidden", "hid",
                "gitignore", "ignore", "regex", "re", "sortreverse", "sr", "dirsfirst", "df", "colors"],
            intro: "`:set` alone lists the options that aren't at their default. Several can be set at "
                + "once: `:set nu rnu fs=18`.",
            rows: [
                ["`fontsize`  `fs`", "Font size in pixels, 6 to 72. Default 16."],
                ["`guifont`  `gfn`", "An installed monospaced font. Default `" + defaultFontFamily
                    + "` (comes with Koil). Icons show in any font."],
                ["`number`  `nu`", "Line numbers."],
                ["`relativenumber`  `rnu`", "Line numbers counted from the cursor's line."],
                ["`syntax`  `syn`", "Color files and the scratchpad: strings, numbers, comments, paths and URLs. "
                    + "`:syntax off` and `:syntax on` turn it off and on too."],
                ["`wrap`", "Wrap a line too long for the window: at a word's start, but anywhere in the listing. "
                    + "View > Word Wrap (`" + altKey + "Z`) toggles it too. Then `gj` and `gk` go "
                    + "a row down or up, the page keys and `Ctrl-E` count rows, and nothing scrolls sideways."],
                ["`sidescrolloff`  `siso`", "Columns kept in view beside the cursor. Default 4."],
                ["`shell`  `sh`", "The shell `:!` runs commands in: a path, or a name on the PATH, like "
                    + "`:set sh=bash`. Default: the one in Settings, else `" + systemShell + "`."],
                ["`hidden`  `hid`", "Show entries starting with `.`."],
                ["`gitignore`  `ignore`", "Hide what git ignores, and `.git`."],
                ["`regex`  `re`", "Read the path as a regex, not a glob. `,` is any character but `/`."],
                ["`sort`", "What the listing is sorted by (see `gs`), like `:set sort=size`: `name`, "
                    + "`natural`, `extension`, `size`, `disk`, `modified`, `created` or `accessed`. Default "
                    + "`name`."],
                ["`sortreverse`  `sr`", "Sort the other way round."],
                ["`dirsfirst`  `df`", "Folders before files, else sorted with them. Sorted by size, a folder "
                    + "goes after the files until its size is counted. Default: the one in Settings (on)."]
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
                "nohlsearch", "help", "h", "history", "e", "edit", "e!", "edit!", "reload", "favorite", "favorites",
                "bookmark", "bookmarks"],
            rows: [
                ["`:e path`", "Open a file, or list a dir or pattern, like `:e ~/src`, read as the path field "
                    + "reads it, from the open dir. As a shortcut (`:e ~/src<CR>`: see `:h shortcuts`), a key "
                    + "opens a dir from anywhere. `:e! path` drops a file's unsaved changes."],
                ["`:e`  `:e!`", "Read the file again from disk (`:e!` dropping its unsaved changes, which `u` "
                    + "brings back). In the listing: update."],
                ["`:w`", "Save (in the listing: apply)."],
                ["`:wq`  `:x`", "Save and quit."],
                ["`ZZ`", "Save and quit (in the listing: `:confirm q`)."],
                ["`:q`  `:qa`", "Quit, unless there are unsaved changes."],
                ["`:q!`  `ZQ`", "Quit without saving."],
                ["`:qa!`", "Quit without saving anything."],
                ["`:conf q`  `:confirm q`", "Quit, asking whether to save first (`y`, `n`, or `c` to cancel)."],
                ["`:42`  `:$`  `:+3`", "Go to line 42, the last line, or 3 lines down."],
                ["`:!cmd`", "Run a shell command (see `:h !`)."],
                ["`:s/old/new/`  `:%s/old/new/g`", "Replace on the line, or every match in the file (see `:h s`)."],
                ["`:noh`", "Clear the search highlights (so does `Esc` in normal mode)."],
                ["`:reg`  `:reg [names]`", "Show the registers, e.g. `:reg a0`."],
                ["`:h`  `:help [topic]`", "This help, e.g. `:h set`, `:h macros`, `:h g` (the keys starting "
                    + "with `g`), or a key, like `:h gJ`."],
                ["`↑`  `↓`", "In the command line: earlier and later commands (or searches)."],
                ["`Ctrl-U`  `Ctrl-W`", "In the command line: delete to the start, or a word back."],
                ["`@:`", "Run the last command again."]
            ]
        },
        {
            title: "Links",
            tags: ["gf", "gx", "link", "links", "url", "urls", "cmd-click", "ctrl-click", "open", "browser"],
            intro: "A URL or a path in a file (or the scratchpad) opens from where it's written. A relative path is "
                + "looked for in the file's dir, then in the open dir.",
            rows: [
                ["`gf`", "Open the file or dir under the cursor in Koil (a dir is listed), or a URL in the browser. "
                    + "Not on a URL or a path, it takes the file name there or after it, like vim's. In the "
                    + "listing: the entry on the line, as `Enter`."],
                ["`gx`", "Open the file, dir or URL under the cursor in its default app. In the listing: the entry "
                    + "on the line, as `Space o`."],
                ["`" + cmdKey + "click`", "Open the URL or path under the pointer, as `gf`. Holding `" + cmdKey.replace("+", "")
                    + "` underlines the one under the pointer. In the listing: the entry."],
                ["visual", "In visual mode, `gf` and `gx` open what's selected."]
            ]
        },
        {
            title: "Shell commands",
            tags: ["!", "g!", "g!!", ":!", ":!!", ":_!", "_!", "shell", "sh", "filter", "%", "%:p", "%:h", "%:t",
                "%:r", "%:e", "terminal", "run"],
            intro: "`:!cmd` runs `cmd` in the shell (`:set shell`, or Settings), in the dir that's open, like "
                + "`:!git status`. What it writes shows in the status line, or in a box like this one if it's "
                + "longer (`:_!cmd`: in the scratchpad). `Esc` stops it.",
            rows: [
                ["`!`", "Types `:! %` with the cursor before the `%`, for a command on the entry on the "
                    + "line, like `git add` then `Enter`. With a count (`3!`), in visual mode or with lines "
                    + "marked (`m`), the range of those lines, where `%` is their entries. In a file, `%` is "
                    + "the file, and a range is put through the command, as `g!` does."],
                ["`g!`", "Vim's `!`: `g!!` or `g!ip` types the range of those lines (in visual mode, the "
                    + "selection's), which go through the command you type, like `sort`, and its output "
                    + "takes their place (in the listing, as new entries)."],
                ["`%`", "The entry on the line (from the path field, the open dir; in the scratchpad, the "
                    + "path written on it), or in a file, the file, quoted for the shell. With a range, in "
                    + "the listing and the scratchpad, the entries on its lines. `\\%` is a `%`, as in "
                    + "`:!date +\\%F`."],
                ["`%:p`  `%:h`  `%:t`", "Its full path, the dir it's in, its name."],
                ["`%:r`  `%:e`", "It without its extension, and its extension (`%:t:r`: its name without it)."],
                ["`:.,+2!cmd`  `:'<,'>!cmd`", "As in vim: put the lines through it, and its output in "
                    + "their place (`:%!sort`). In the listing and the scratchpad, one with `%` is run on "
                    + "the entries on those lines instead (`:'<,'>!git add %`)."],
                ["`:_!cmd`", "Put what it writes in the scratchpad, in place of its text (`u` brings that "
                    + "back), like `:_!git log`. With a range, the lines go to it but stay, or with `%`, "
                    + "it's on their entries."],
                ["`:!!`", "Run the last command again."]
            ],
            note: "A command can't read what you type: one that asks (`rm -i`) gets no answer."
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
                [isMac ? "`⌘⌥C`  `⌘⌥W`  `⌘⌥R`" : "`Alt+C`  `Alt+W`  `Alt+R`",
                    "In the find bar: match case, whole word, regular expression."],
                [isMac ? "`⌘⌥L`" : "`Alt+L`",
                    "In the find bar: find only in the selection (or the marked lines, or else the last "
                    + "selection). On at once for one over lines, a block or marked lines."],
                ["`↑`  `↓`", "In the find bar: earlier and later finds (or replacements)."]
            ]
        },
        {
            title: "Substitute",
            tags: ["s", ":s", "substitute", "sub", "&", ":&", "&&", ":&&", "g&"],
            intro: "`:s/old/new/` replaces the first match on the cursor's line, as in vim, and "
                + "`:%s/old/new/g` every one in the file. As you type it, the matches are highlighted, then "
                + "the text shows what it would become, and `Esc` puts it back. In the listing a line starts "
                + "at its name, so `:%s/^/old_/` renames every entry.",
            rows: [
                ["`:%s`  `:2,5s`  `:'<,'>s`", "Every line, lines 2 to 5, or (`:` in visual mode) only what's "
                    + "selected: its characters, its block or its lines."],
                ["`old`", "A JavaScript regex, as `/` takes (`(\\d+)`, not vim's `\\(\\d\\+\\)`). Case counts "
                    + "only if it has an uppercase letter. Empty, it's the last search."],
                ["`&`  `\\0`  `\\1`", "In the replacement: the match, or its first group."],
                ["`\\u`  `\\l`  `\\U`  `\\L`  `\\E`", "Uppercase or lowercase the next character, or all of "
                    + "them up to `\\E`."],
                ["`\\r`  `\\t`", "A line break (`\\n` too) or a tab. `\\&`, `\\/` and `\\\\` are themselves, "
                    + "and so is `~` (unlike vim's)."],
                ["`g`  `i`  `I`", "Flags, after the last `/`: every match on a line, not only the first; ignore "
                    + "case; don't."],
                ["`n`  `e`", "Only count the matches; no error if there are none."],
                ["`:s#/#-#`", "Any punctuation can stand for `/`."],
                ["`&`  `:s`  `:&&`", "Run the last one again on the cursor's line (`:&&`: with its flags)."],
                ["`g&`", "Run it again on every line, with its flags, for the last search."]
            ]
        },
        {
            title: "Surround",
            tags: ["surround", "vim-surround", "ys", "yss", "yS", "ySS", "ds", "cs", "cS", "S", "gS", "pair",
                "pairs", "brackets", "quotes", "tag", "tags", "it", "at"],
            intro: "As vim-surround: put brackets, quotes or tags around text, or change or delete the ones "
                + "around the cursor.",
            rows: [
                ["`ys`", "Around what a motion or text object goes over: `ysiw)` makes `word` `(word)`, and "
                    + "`ys$\"` quotes up to the line's end. Blanks at its end stay out (`ysaw]`). One over "
                    + "lines (`ysip)`) gets the pair on lines of its own."],
                ["`yss`", "Around the line, after its indent (`2yss)`: two lines)."],
                ["`ds`", "Delete the pair around the cursor: `ds)`, `ds\"`, `dst` for tags, `ds2(` for the "
                    + "second one out. A bracket alone on its line goes with the line."],
                ["`cs`", "Change it: `cs\"'` makes `\"a\"` `'a'`, and `cs)]` makes `(a)` `[a]`."],
                ["`S`  `gS`", "In visual mode: around the selection, like `S)`. Lines get the pair on lines of "
                    + "its own, a level deeper (with `gS`, not deeper), and a block on each of its lines. "
                    + "`gS` puts it on lines of its own around characters too."],
                ["`yS`  `ySS`  `cS`", "As `ys`, `yss` and `cs`, with the pair on lines of its own and "
                    + "what's inside a level deeper. Inside brackets or tags, it's then reindented as `=` "
                    + "does."],
                ["`)`  `]`  `}`  `>`", "The brackets (`b`, `r`, `B` and `a` too). `(`, `[` and `{` put a space "
                    + "inside, and as what to delete or change, take the blanks inside away (so does a space "
                    + "before the key: `ds )`)."],
                ["`*`  `_`  `|`", "Any other sign goes on both sides, and as what to delete or change, is the "
                    + "nearest one on each side on the line. `s` is a space before: `csbs` makes `f(x)` `f x`."],
                ["`<`", "A tag (`t` too), typed in the status line: `ysiw<em>` makes `<em>word</em>`. `cst<` "
                    + "keeps the old tag's attributes if it ends with `Enter` rather than `>`."],
                ["`it`  `at`", "The text inside the tags around the cursor, or with them, as in vim: `dit`, `vat`."]
            ],
            note: "`.` repeats them. Unlike vim-surround's, they leave the registers alone."
        },
        {
            title: "Registers and macros",
            tags: ["registers", "register", "reg", "clipboard", "\"", "\"+", "+", "*", "\"0", "\"_", "\"-",
                "\"1", "\".", "\":", "\"/", "\"%", "macros", "macro",
                "q", "@", "@@", "record", "recording", "yank", "paste", "p", "y", "shortcuts", "shortcut", "map",
                "mapping", "mappings"],
            rows: [
                ["`\"+`  `\"*`", "The system clipboard, e.g. `\"+yy`. Plain `y` and `p` don't use it; "
                    + (isMac ? "`⌘C` and `⌘V` do." : "`Ctrl+C` does, and `Ctrl+V` while typing.")],
                ["`\"a` … `\"z`", "Named registers, e.g. `\"ayw`. `\"A` appends to `a`."],
                ["`\"0`  `\"_`", "The last yank; the black hole (`\"_dd` changes no register)."],
                ["`\"1` … `\"9`  `\"-`", "Deleted lines, the newest in `1`; text deleted within a line."],
                ["`\".`  `\":`  `\"/`  `\"%`", "The last insert, command and search, and the open file or dir."],
                ["`qa` … `q`", "Record keys into register `a`. `qA` appends to it."],
                ["`@a`  `3@a`  `@@`", "Run the macro in `a`, three times, or the last one again. `u` undoes a "
                    + "whole run, and `Esc` stops a long one."],
                ["Your keys", "Your shortcuts: keys of yours (`Space c`, `gc`, `<C-k>`"
                    + (isMac ? ", `⌘K` as `<D-k>`" : "") + ") that run keys as a "
                    + "macro does, like `:!git add %<CR>`, in normal mode, visual mode or both. A count runs one "
                    + "that many times. They come before vim's: a shortcut on `xa` makes `x` wait for the `a`. "
                    + "Koil's own keys can't be taken, nor keys that start them or start with them (`g`, `g.x`)."],
                ["`Space q`", "List your shortcuts (so do " + (isMac ? "Koil > Shortcuts…" : "File > Shortcuts…")
                    + " and Settings), and under them the built-in ones, with the lock button on. Typing searches "
                    + "them, `↑` and `↓` pick one, and `Enter` or a click runs it, also one with no keys, on the "
                    + "selection if it's for visual mode. The pencil edits one, and `" + cmdKey + "N` adds one."]
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
            title: "Marked lines",
            tags: ["m", "mark", "marks", "marked", "select", "selection", "lines", "move", "gather"],
            intro: "`m` marks lines, which can be far apart, as the cursor moves as in normal mode. Then the "
                + "keys that act on a visual selection act on all of them at once, as on lines selected "
                + "with `V` if they were together. Using them unmarks them.",
            rows: [
                ["`m`  `3m`", "Mark the line (or 3 lines from it), or unmark it if it's marked. In visual mode: "
                    + "its lines."],
                ["`d`  `y`", "Delete or yank them, all in one register (`\"ay` too). `p` then puts them "
                    + "together: in the listing, mark entries in a dir, `d`, and `p` in another to move them."],
                ["`!`", "In the listing: run a command on their entries (`!git add`). In a file: put them "
                    + "through it, its output where the first one was."],
                ["`I`  `A`", "Type at the start or end of each one, like `A.bak<Esc>`."],
                ["`c`  `p`  `J`", "Change them into one line, put a register in their place, or join them, "
                    + "where the first one is."],
                ["`>`  `=`  `gU`  `r`", "Indent, reindent, change case or replace characters on each one."],
                ["`:`", "`:'<,'>` is them: `:s/a/b/` changes only them."],
                ["`Esc`", "Unmark them all. `gv` marks them again (also after using them)."]
            ],
            note: "Other keys work as in normal mode: `u` undoes, `i` and `o` type at the cursor."
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
            title: "Keys starting with g",
            tags: ["g", "gg", "ge", "gE", "gj", "gk", "gI", "gJ", "g~", "gu", "gU", "g?", "rot13", "case",
                "uppercase", "lowercase", "gv"],
            rows: [
                ["`gg`", "The first line (`5gg`: line 5)."],
                ["`ge`  `gE`", "Back to the end of the word before (`gE`: of the WORD, between blanks)."],
                ["`gj`  `gk`", "Down or up a row of a line that wraps (see `:set wrap`)."],
                ["`gI`", "Type at the line's very start, before its indent (in the listing, at the name)."],
                ["`gJ`", "Join the lines, adding no space between them."],
                ["`gS`", "In visual mode: put a pair on lines of its own around the selection (see `:h surround`)."],
                ["`g~`  `gu`  `gU`  `g?`", "Toggle case, lowercase, uppercase or ROT13, over a motion: "
                    + "`gUiw` uppercases a word, `gUU` the line."],
                ["`g!`", "Put lines through a shell command, like `g!ip` then `sort` (see `:h !`)."],
                ["`g&`", "Run the last `:s` again on every line (see `:h s`)."],
                ["`gv`", "Select the last visual selection again, or mark the last marked lines again."],
                ["`gh`", "Show what the line's icon hides, or the message under the cursor."],
                ["`gf`  `gx`", "Open the link under the cursor in Koil, or in its default app (see `:h gf`)."],
                ["`g.`  `gi`  `gr`", "In the listing: toggle hidden files, hiding what git ignores, and "
                    + "reading the path as a regex."],
                ["`gs`", "In the listing: sort, by the key after it: `n` name, `v` natural, `e` extension, "
                    + "`s` size, `d` size on disk, `m` modified, `c` created, `a` accessed (`gss` by size). "
                    + "Shifted, the other way round (`gsS`)."]
            ]
        },
        {
            title: "Keys starting with z",
            tags: ["z", "zz", "zt", "zb", "zl", "zh", "zL", "zH", "zs", "ze", "ZZ", "ZQ", "scroll", "sideways"],
            rows: [
                ["`zz`  `zt`  `zb`", "Scroll the cursor's line to the middle, top or bottom."],
                ["`zl`  `zh`", "Scroll sideways a column (`5zl`: five), as far as the sizes and messages "
                    + "after the lines."],
                ["`zL`  `zH`", "Scroll sideways half the view."],
                ["`zs`  `ze`", "Scroll sideways to put the cursor at the left or right edge."],
                ["`ZZ`", "Save and quit (in the listing: `:confirm q`)."],
                ["`ZQ`", "Quit without saving."]
            ],
            note: "Nothing scrolls sideways while lines wrap (`:set wrap`)."
        },
        {
            title: "Keys starting with Space",
            tags: ["space", "<space>", "leader"],
            intro: "Koil's own, in the listing and the path field. In a file, `Space Space` saves, and "
                + "`Space q` works everywhere, in visual mode too.",
            rows: [
                ["`Space Space`", "Apply the changes, listing them first (Settings can skip that). In a "
                    + "file: save."],
                ["`Space a`", "Apply, always listing the changes first."],
                ["`Space u`", "Undo applies, picked from all of them, newest first."],
                ["`Space r`", "Show the entry on the line in " + fileManager + "."],
                ["`Space o`", "Open the entry on the line in its default app."],
                ["`Space q`", "List your shortcuts, and the built-in ones (see `:h shortcuts`)."]
            ],
            note: "Shortcuts of yours can start with `Space` too, like `Space c`."
        },
        {
            title: "Ctrl keys",
            tags: ["ctrl", "control", "ctrl-a", "ctrl-x", "ctrl-e", "ctrl-y", "ctrl-d", "ctrl-u", "ctrl-f",
                "ctrl-b", "ctrl-r", "ctrl-c", "ctrl-n", "ctrl-p", "ctrl-w"],
            intro: isMac ? "The `Ctrl` key, not `⌘`."
                : "On Windows, `Ctrl+F` is Find, and `Ctrl+V` pastes while typing.",
            rows: [
                ["`Ctrl-D`  `Ctrl-U`", "Down or up half a page."],
                ["`Ctrl-F`  `Ctrl-B`", "Down or up a page."],
                ["`Ctrl-E`  `Ctrl-Y`", "Scroll a line down or up (a row, while lines wrap)."],
                ["`Ctrl-R`", "Redo."],
                ["`Ctrl-A`  `Ctrl-X`", "Add to or subtract from the number at or after the cursor."],
                ["`Ctrl-V`", "Visual block (see `:h block`)."],
                ["`Ctrl-C`", "Stop a macro or shell command that's running, or close the command line, "
                    + "as `Esc` does."],
                ["`Ctrl-N`  `Ctrl-P`", "While completing a path: the next or previous dir."],
                ["`Ctrl-U`  `Ctrl-W`", "In the command line: delete to the start, or a word back."],
                ["`Ctrl-B`  `Ctrl-E`", "In the command line: go to the start or the end."]
            ]
        },
        {
            title: "Other keys",
            tags: ["keys", "other", "zoom", "settings", "undo", "word", "=", "==", "indent", "reindent"],
            rows: [
                ["`=`  `==`", "Reindent: `==` the line, `=ip` the paragraph, `gg=G` all of it, or in visual mode "
                    + "what's selected. A line in brackets (or HTML tags) goes a level deeper than the line "
                    + "they open on, and one that closes them as deep as that line. A line in none keeps its "
                    + "indent, so Python and YAML stay as they are. A level is the file's: a tab, or 2, 4 or "
                    + "8 spaces."],
                [isMac ? "`⌘Z`  `⇧⌘Z`" : "`Ctrl+Z`  `Ctrl+Shift+Z`",
                    "Undo and redo, like `u` and `Ctrl-R`."],
                [isMac ? "`⌘+`  `⌘-`  `⌘0`" : "`Ctrl+=`  `Ctrl+-`  `Ctrl+0`",
                    "Zoom in, out, or back to the Settings size."],
                ["`" + cmdKey + ",`", "Settings: font, line numbers, syntax colors, word wrap, theme, folders "
                    + "first, when applying asks, start dir, shell and more. The pointer on a setting's name "
                    + "shows what it does."]
            ]
        }
    ]

    // Opens the help at the section for `topic` (all of it if ""), at its
    // row of that key if it has one (`:h gs`), or else at the first row of
    // that key (`:h zs`). Tags and keys match as typed first, so `gI` isn't
    // `gi`, then in any case. `<C-a>`, `^A` and `CTRL-A` are `Ctrl-A`. False
    // if there's no help for it.
    function show(topic) {
        const t = topic.trim().replace(/^:/, "").replace(/^'(.*)'$/, "$1")
            .replace(/^(?:<c-(.)>|\^(.)|ctrl[-+](.))$/i, (m, a, b, c) => "Ctrl-" + (a || b || c).toUpperCase());
        const lower = t.toLowerCase();
        let i = t === "" ? 0 : sections.findIndex(s => s.tags.includes(t));
        if (i < 0)
            i = sections.findIndex(s => s.tags.some(tag => tag.toLowerCase() === lower));
        // The key's row in that section, else in the first that has it.
        let row = -1;
        const looked = i >= 0 ? [i] : sections.map((s, k) => k);
        for (const exact of t === "" ? [] : [true, false]) {
            const s = looked.find(s => keyRow(sections[s], t, exact) >= 0);
            if (s !== undefined) {
                i = s;
                row = keyRow(sections[s], t, exact);
                break;
            }
        }
        if (i < 0)
            return false;
        heading = "Koil Help";
        shownSections = sections;
        clearSearch();
        open();
        shownSection = i;
        shownRow = row;
        showSection();
        return true;
    }

    // The row of `section` with `key` in its keys (as written, or unless
    // `exact`, in any case), or -1.
    function keyRow(section, key, exact) {
        const same = code => exact ? code === key : code.toLowerCase() === key.toLowerCase();
        return section.rows.findIndex(row => Txt.parseCode(row[0], false).codes.some(c => same(c.text)));
    }

    // Opens the box with `title` over `rows` of [keys, text], both shown
    // as they are in the editor's font, the keys taking `keyColumns`
    // characters (:reg).
    function showList(title, rows, keyColumns) {
        showPlain(title, { title: "", rows: rows, plain: true, keyColumns: keyColumns });
    }

    // Opens the box with `title` over `text`, as it is in the editor's
    // font, with its line breaks, and `note` after it (what a shell command
    // wrote).
    function showText(title, text, note) {
        showPlain(title, { title: "", intro: text, plain: true, rows: [], note: note });
    }

    function showPlain(title, section) {
        heading = title;
        shownSections = [section];
        clearSearch();
        open();
        shownSection = 0;
        shownRow = -1;
        showSection();
    }

    // The section :help went to, and its row (-1 for its top). Its text is
    // laid out over the first frames, so it's scrolled to again as the
    // layout changes, until the user scrolls.
    property int shownSection: -1
    property int shownRow: -1

    function showSection() {
        const item = shownSection >= 0 ? sectionRepeater.itemAt(shownSection) : null;
        if (!item)
            return;
        const row = shownRow >= 0 ? textItems.get(shownSection + "/" + shownRow + "k") : null;
        scroller.contentY = Math.min(row ? row.mapToItem(body, 0, 0).y : item.y, scroller.maxY);
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
    // The CodeTexts by key, to find a match on the screen. A Map, as
    // keys come and go: qmlcachegen compiles ({}) to a QVariantMap, not a
    // JS object, and in Qt 6.10 taking a key after one was deleted
    // crashed (showing what :! wrote, on Windows).
    property var textItems: new Map()

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
                list.push({ key: s + "/" + part, text: Txt.parseCode(markup, !!section.plain).text });
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
        const item = textItems.get(m.key);
        return item ? item.mapToItem(body, 0, item.positionToRectangle(m.start).y).y : 0;
    }

    function inView(m) {
        const y = matchY(m);
        return y >= scroller.contentY && y < scroller.contentY + scroller.height;
    }

    // Scrolls match i to the middle, if it's out of view.
    function reveal(i) {
        shownSection = -1;
        const item = textItems.get(matches[i].key);
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

    // Text with `code` (see Txt.parseCode), each code on a shade of its own,
    // drawn behind the text so it still selects and copies, and its search
    // matches highlighted. `plain` shows the text as it is (a :reg list).
    component CodeText: HelpText {
        id: codeText

        property string markup
        property bool plain
        // Which text of shownSections it is ("" for none), which search
        // goes through (see searchTexts).
        property string key
        readonly property var parsed: Txt.parseCode(markup, plain)
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
        text: Txt.codeHtml(parsed, markList, plain, help.monoFamily, help.codePadding)
        textFormat: TextEdit.RichText
        wrapMode: TextEdit.Wrap
        onLayoutChanged: Qt.callLater(place)
        Component.onCompleted: {
            if (key !== "")
                help.textItems.set(key, codeText);
        }
        Component.onDestruction: {
            if (help.textItems.get(key) === codeText)
                help.textItems.delete(key);
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

                // A long one (a shell command) wraps, clear of the keys.
                width: Math.min(implicitWidth, parent.width - keysHint.implicitWidth - 12 * help.zoom)
                wrapMode: TextEdit.WrapAnywhere
                leftPadding: help.codePadding // as CodeText's
                text: help.heading
                font.pixelSize: Math.round(18 * help.zoom)
                font.bold: true
                color: help.theme.text
            }
            CodeText {
                id: keysHint

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
                else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q && !event.modifiers
                        || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
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
                            plain: !!section.modelData.plain
                            font.family: plain ? help.monoFamily : help.font.family
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
