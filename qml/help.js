.pragma library

// What :help says (see HelpPanel), for `help`'s platform: isMac,
// isWindows, cmdKey and altKey (modifier keys as the OS writes them),
// fileManager, systemShell and defaultFontFamily. Each section: a title,
// the :help topics that go to it, an optional intro and note, and rows of
// [keys, what they do]. `code` in any of them (a key, in keys) is shown in
// the editor's font, on a shade of its own as in a Tip (see CodeText).
function sections(help) {
    const isMac = help.isMac, isWindows = help.isWindows, cmdKey = help.cmdKey, altKey = help.altKey;
    const fileManager = help.fileManager, systemShell = help.systemShell;
    const defaultFontFamily = help.defaultFontFamily;
    return [
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
                ["`" + cmdKey + "S`  `:w`", "Update: read the edits and show the listing again. Only "
                    + "`Space Space` and `Space a` apply them."],
                ["`Space Space`", "Apply the changes, listing them first (Settings can skip that). In a file: "
                    + "save."],
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
                    + "open dir; in a file, the file)."],
                ["`Space o`", "Open the entry on the line in its default app, as a double-click in "
                    + fileManager + " does (from the path field, the open dir; in a file, the file)."],
                ["`!`", "Run a shell command on the entry on the line (or the marked ones: see `:h m`): "
                    + "`!git add` or `!rm`, then `Enter` (see `:h !`)."],
                ["`Shift+Enter`", "Vim's `Enter`: the first character of the next line."],
                ["`-`", "Open the dir above (`3-`: three up). In a file: back to the listing, and in the "
                    + "scratchpad, to where you were (`3-`: and `-` twice more from there)."],
                ["`_`", "The scratchpad (from a file too): text of your own, never saved, kept as you left "
                    + "it until Koil quits. `_` or `-` there goes back to where you were, a file with its "
                    + "unsaved changes. In a command, `%` is a file of its text (`!wc -w`), and `<cfile>` "
                    + "the path under the cursor (`:!rm <cfile>`)."],
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
                    + "compressed, a whole block if small" + (isWindows
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
                "bookmark", "bookmarks", "norm", "normal", "norm!", "normal!", "-c", "startup"],
            rows: [
                ["`:e path`", "Open a file, or list a dir or pattern, like `:e ~/src`, read as the path field "
                    + "reads it, from the open dir. As a shortcut (`:e ~/src<CR>`: see `:h shortcuts`), a key "
                    + "opens a dir from anywhere. `:e! path` drops a file's unsaved changes."],
                ["`:e`  `:e!`", "Read the file again from disk (`:e!` dropping its unsaved changes, which `u` "
                    + "brings back). In the listing: update. A file that changes on disk is read again "
                    + "by itself, as a change `u` takes back, and if you changed it too, Koil asks first."],
                ["`:w`", "Save (in the listing: update, as `" + cmdKey + "S`; `Space Space` applies)."],
                ["`:wq`  `:x`", "Save and quit (in the listing: update and quit, as `:q`)."],
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
                ["`:norm keys`", "Press keys, as a macro does, like `:norm gss` (keys such as `<CR>` and `<Esc>` "
                    + "written as in a shortcut). With a range, on each line, from its start (`:%norm A;`). "
                    + "`:norm!` leaves your shortcuts out."],
                ["`koil -c 'cmd'`", "Run a command once Koil has opened, like `koil ~/src -c 'set sort=size'`. "
                    + "Several `-c`s run in turn."],
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
                    + "listing (and on a line pasted from it): the entry on the line, as `Enter`."],
                ["`gx`", "Open the file, dir or URL under the cursor in its default app. In the listing (and on a "
                    + "line pasted from it): the entry on the line, as `Space o`."],
                ["`" + cmdKey + "click`", "Open the URL or path under the pointer, as `gf`. Holding `" + cmdKey.replace("+", "")
                    + "` underlines the one under the pointer. In the listing (and on a line pasted from it): "
                    + "the entry."],
                ["visual", "In visual mode, `gf` and `gx` open what's selected."]
            ]
        },
        {
            title: "Shell commands",
            tags: ["!", "g!", "g!!", ":!", ":!!", ":_!", "_!", "shell", "sh", "filter", "%", "%:p", "%:h", "%:t",
                "%:r", "%:e", "<cfile>", "cfile", "terminal", "run"],
            intro: "`:!cmd` runs `cmd` in the shell (`:set shell`, or Settings), in the dir that's open, like "
                + "`:!git status`. What it writes shows in the status line, or in a box like this one if it's "
                + "longer (`:_!cmd`: in the scratchpad). `Esc` stops it.",
            rows: [
                ["`!`", "Types `:! %` with the cursor before the `%`, for a command on the entry on the "
                    + "line, like `git add` then `Enter` (in a file or the scratchpad, on the file). With a "
                    + "count (`3!`), in visual mode or with lines marked (`m`), the range of those lines: in "
                    + "the listing, `%` is their entries, and elsewhere they're put through the command, as "
                    + "`g!` does."],
                ["`g!`", "Vim's `!`: `g!!` or `g!ip` types the range of those lines (in visual mode, the "
                    + "selection's), which go through the command you type, like `sort`, and its output "
                    + "takes their place (in the listing, as new entries)."],
                ["`%`", "The entry on the line (from the path field, the open dir, or a pattern's "
                    + "entries, as a shell's glob gives them), or in a file, the file, quoted for the shell. "
                    + "In the scratchpad, a file of its text, which then goes back in it (`!echo hi >> %`: "
                    + "`u` takes it back). With a range, in the listing, the entries on its lines. `\\%` is a "
                    + "`%`, as in `:!date +\\%F`."],
                ["`<cfile>`", "The path or URL under the cursor, as `gf` opens it (`" + cmdKey + "click` "
                    + "underlines it), or else the file name there; in the listing, the entry, as `%`. With a "
                    + "range, the first on each line, like `:'<,'>!rm <cfile>` on what `:_!find` wrote. "
                    + "`\\<cfile>` is a `<cfile>`."],
                ["`%:p`  `%:h`  `%:t`", "Its full path, the dir it's in, its name (`<cfile>:t` too)."],
                ["`%:r`  `%:e`", "It without its extension, and its extension (`%:t:r`: its name without it)."],
                ["`:.,+2!cmd`  `:'<,'>!cmd`", "As in vim: put the lines through it, and its output in "
                    + "their place (`:%!sort`). In the listing, one with `%` is run on the entries on those "
                    + "lines instead (`:'<,'>!git add %`), and anywhere, one with `<cfile>` on their paths."],
                ["`:_!cmd`", "Put what it writes in the scratchpad, in place of its text (`u` brings that "
                    + "back), like `:_!git log`. With a range, the lines go to it but stay, or with `%` in "
                    + "the listing, or `<cfile>`, it's on their entries."],
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
                ["`*`  `#`", "Search for the word under the cursor, or in visual mode for what's selected, "
                    + "as it is (not as a regex), as Neovim's do."],
                ["`" + cmdKey + "F`", "The find bar. Its matches are highlighted while it's open."],
                [isMac ? "`⌘G`  `⇧⌘G`" : "`F3`  `Shift+F3`  `Ctrl+G`  `Ctrl+Shift+G`",
                    "Next or previous find bar match."],
                [isMac ? "`⌘⌥F`" : "`Ctrl+H`", "Find and replace."],
                ["`$&`  `$1`  `\\1`", "In the find bar's replacement, with a regex: the match (`$0` and `\\0` "
                    + "too), or its first group. `$$` is a `$`, `\\n` and `\\t` a line break and a tab, and `&` "
                    + "itself, as in VS Code."],
                ["`\\u`  `\\l`  `\\U`  `\\L`", "In the find bar's replacement: uppercase or lowercase the group "
                    + "after it, its first character or all of it (`\\u$1`)."],
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
                ["`&`  `:&&`  `:s`", "Run the last one again on the cursor's line: `&` and `:&&` with its flags "
                    + "(as Neovim's `&`; Vim's drops them), `:s` and `:&` without."],
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
                "q", "@", "@@", "Q", "record", "recording", "yank", "paste", "p", "y", "shortcuts", "shortcut", "map",
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
                ["`Q`", "Run the macro recorded last, as Neovim's (Vim's starts Ex mode)."],
                ["`@a`  `Q`", "In visual mode: run the macro on each selected line in turn, from its start, as "
                    + "Neovim's do (`:'<,'>normal @a`). A line it fails on is skipped, and the lines go with its "
                    + "edits, so one that adds or deletes lines still runs on each. `@:` runs the last command."],
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
            intro: "Koil's own, in the listing and the path field. In a file, `Space Space` saves, `Space r` "
                + "and `Space o` take the file, and `Space q` works everywhere, in visual mode too.",
            rows: [
                ["`Space Space`", "Apply the changes, listing them first (Settings can skip that). In a "
                    + "file: save."],
                ["`Space a`", "Apply, always listing the changes first."],
                ["`Space u`", "Undo applies, picked from all of them, newest first."],
                ["`Space r`", "Show the entry on the line (in a file, the file) in " + fileManager + "."],
                ["`Space o`", "Open the entry on the line (in a file, the file) in its default app."],
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
            tags: ["keys", "other", "zoom", "settings", "undo", "word", "=", "==", "indent", "reindent", "Y",
                "startofline", "sol", "nostartofline", "column"],
            rows: [
                ["`Y`", "Yank to the line's end, as `y$` (and as Neovim's), like `D` and `C`. Vim's yanks "
                    + "the line, which `yy` does. In visual mode it still yanks the lines."],
                ["`G`  `gg`  `dd`  `>>`", "Keep the cursor's column, as Neovim's do, and so do `H`, `M`, `L`, "
                    + "`50%`, `:5`, `==` and visual `d`, `>` and `<` on lines. Vim's go to the line's first "
                    + "character that isn't blank, which `^` does."],
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
    ];
}
