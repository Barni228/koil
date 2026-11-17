.pragma library

// What :help says (see HelpPanel), for `help`'s platform: isMac,
// isWindows, cmdKey and altKey (modifier keys as the OS writes them),
// fileManager, systemShell and defaultFontFamily. Each section: a title,
// the :help topics that go to it, an optional intro and note, and rows of
// [keys, what they do]. The help folds each to its title; one that's a
// `part` of the section before shows with it, with no fold of its own. `code` in any of them (a key, in keys) is shown in
// the editor's font, on a shade of its own as in a Tip (see CodeText), and
// a `:h topic` outside the keys is a link to that topic, which a click
// goes to: so where a text points to another section, it says `:h` and a
// topic of it (the tests check each goes somewhere).
function sections(help) {
    const isMac = help.isMac, isWindows = help.isWindows, cmdKey = help.cmdKey, altKey = help.altKey;
    const fileManager = help.fileManager, systemShell = help.systemShell;
    const defaultFontFamily = help.defaultFontFamily;
    // The Alt key's name, without altKey's "+".
    const alt = isMac ? "⌥" : "Alt";
    return [
        {
            title: "The listing",
            tags: ["koil", "listing", "list", "entry", "entries", "update", "apply", "-", "[", "]", "back",
                "forward", "enter",
                "<cr>", "cr", "path", "pattern", "glob", "folder", "dir", "undo", "tab", "<tab>", "g.", "gi",
                "gr", "gs", "sorting", "_", ":_", ":_put", ":_pu", "_put", "_pu", "scratch", "scratchpad",
                "reveal", "finder", "explorer",
                "app", "K", "info", "stat", "permissions", "symlink", "drive", "drives"],
            intro: "Koil shows a dir as text, a line per entry: its icon (which hides its ID), two spaces "
                + "and its name, with `/` after a dir's. Edit a name to rename, delete lines to delete, "
                + "copy lines to copy, and write new ones to create (`new.txt`, `new/dir/`). A line cut "
                + "and pasted in another dir moves. Nothing changes on disk until you apply, and changes "
                + "stay while you go to other dirs.",
            rows: [
                ["`" + cmdKey + "S`  `:w`", "Update: read the edits and show the listing again. Only "
                    + "`Space Space` and `Space a` apply them."],
                ["`Space Space`  `:apply`", "Apply the changes, listing them first (Settings can skip that). "
                    + "In a file: save."],
                ["`Space a`  `:conf apply`", "Apply, always listing the changes first (so does File > Apply "
                    + "Changes…)."],
                ["󰄲", "In that list, pick what to apply now (the rest stays, to apply later), or to discard: "
                    + "see `:h pick`."],
                ["`Space u`  `:undolist`", "Undo applies, or single changes of them, picked from all of them, also "
                    + "those of earlier sessions, newest first (`/` searches them, by a file's name say). "
                    + "Picking a change picks the newer ones on the same paths. "
                    + "Deleted files come back from the trash. `d` there deletes them from the history "
                    + "instead, also those that can't be undone any more (see `:h pick`)."],
                ["`u`", "Once there's nothing left to undo: undo the last apply, after listing what that "
                    + "does."],
                ["`Enter`", "Open the dir or file on the line (a renamed one where it is now). A new file "
                    + "is created first, after asking, and so is a copy, so what you change in it isn't "
                    + "in the file it copies. Opening a file that applying copies (or `Space o`, or a "
                    + "shell command) makes the copies first, so they don't get your changes."],
                ["`Space r`  `:reveal`", "Show the entry on the line in " + fileManager + " (from the path field, the "
                    + "open dir; in a file, the file; in the scratchpad, the entry pasted on the line, or "
                    + "the path under the cursor)."],
                ["`Space o`  `:open`", "Open the entry on the line in its default app, as a double-click in "
                    + fileManager + " does (from the path field, the open dir; in a file, the file; in the "
                    + "scratchpad, as `Space r`)."],
                ["`K`", "Show all about the entry on the line: its path, what it is (a symlink's target), "
                    + "its size (a dir's is counted, but "
                    + (isWindows ? "a drive's root shows the drive's" : "a volume's top dir, like `/`, shows the volume's")
                    + " capacity and what's available instead), what a dir has, its times, "
                    + (isWindows ? "and its attributes" : "permissions, owner and group, and flags")
                    + " (from the path field, the open dir; in a file, the file; in the scratchpad, the "
                    + "entry pasted on the line, or the path under the cursor). The box stays while you "
                    + "move (`j`, `k`), showing the entry you're on, until `Esc`."],
                ["`!`", "Run a shell command on the entry on the line (or the marked ones: see `:h m`): "
                    + "`!git add` or `!rm`, then `Enter` (see `:h !`)."],
                ["`Shift+Enter`", "Vim's `Enter`: the first character of the next line."],
                ["`-`", "Open the dir above (`3-`: three up)"
                    + (isWindows ? ", and above a drive's root (`C:/`), the drives, at `/`" : "")
                    + ". In a file: back to the listing, and in the scratchpad, to where you were (`3-`: and "
                    + "`-` twice more from there)."],
                ["`[`  `]`", "Back to the dir you stopped at before (`3[`: three back), and forward again, as "
                    + "a browser's back and forward, but not through the dirs you only passed with `Enter` "
                    + "or `-`: only those you did something in (an edit, a file opened, a yank, `m`, `K`, a "
                    + "shell command, an apply), typed the path of, or left by typing one (so do "
                    + (isMac ? "`Cmd+[` and `Cmd+]`, and the mouse's buttons"
                        : "`Alt+Left` and `Alt+Right`, the mouse's buttons, and a keyboard's Back and Forward keys")
                    + "), with the cursor where it was "
                    + "there. Going to another dir drops those `]` would go forward to. In a file or the "
                    + "scratchpad, `[` goes back as `-` does."],
                ["`_`", "The scratchpad (from a file too): text of your own, never saved, kept as you left "
                    + "it until Koil quits. `_` or `-` there goes back to where you were, a file with its "
                    + "unsaved changes. In a command, `%` is a file of its text (`!wc -w`), and `<cfile>` "
                    + "the path under the cursor (`:!rm <cfile>`). Entries pasted there look and work as in "
                    + "the listing: colored, with where a link points after the line, and the dir of one "
                    + "that isn't in the open dir. `Enter`, `gf`, `gh`, `K`, `Space r`, `Space o` and `!` "
                    + "take the one on the line, its icon counts as indentation (`^`, `I` and `gg` go to "
                    + "the name, and `w` and `b` past it; `0` to the icon), and `!` with a count, a selection or marked lines types "
                    + "`<cfile>` for a command on them (`Vj!`, then `git add`)."],
                ["`:_`", "Show the scratchpad, or stay in it, where `_` would leave it: for a shortcut "
                    + "that should end up there wherever it's run."],
                ["`:_put`  `:_pu a`", "Put what `p` would paste (or register `a`) after the scratchpad's "
                    + "last line, as lines, without showing it, and say how many lines went: a shortcut of "
                    + "`:_pu<CR>` puts what you yanked aside. Entries keep their IDs, and `u` there takes it "
                    + "back."],
                ["icons", "The cursor skips each line's icon and the spaces after it, so `0` goes to the "
                    + "name. `Backspace` there clears the icon (the entry becomes new), then joins lines."],
                ["quitting", "`:conf q` and `ZZ` ask to apply the changes first. In a file, quitting goes "
                    + "back to the listing while it has changes (`:qa!` still quits)."],
                ["path", "The field at the top: a dir or a glob, like `~/src/**/*.rs` (a regex with `:set "
                    + "regex`). Write `/`, also on Windows: in a pattern, `\\` escapes."
                    + (isWindows ? " `/` alone is the drives, and `t:` drive T's root." : "")],
                ["glob", "A dir matches with its `/`: `*` is only files, `*/` only dirs, `{*,*/}` both. "
                    + "`*` skips names starting with `.`, but `.*` and `**/.env` show them."],
                ["`Enter`  `Shift+Enter`", "In the path field: open it and go to the listing, or open it and "
                    + "stay."],
                ["`k`  `j`", "In the path field: the dirs listed before (`↑` and `↓` while typing)."],
                ["`Tab`", "Go between the listing and the path field (so does a click)."],
                ["`Tab`  `Shift+Tab`", "While typing a path: complete the dir, like a shell (if none starts "
                    + "with what's typed, one with its letters in order: `myt` gives `my_tools`)"
                    + (isWindows ? ", or a drive: `t` gives `T:/` (with the dirs starting with `t`)" : "")
                    + ". With several to pick from, they go through them, and `Enter` takes one."],
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
                "number", "nu", "relativenumber", "rnu", "syntax", "syn", "wrap", "visualwhitespace", "vws", "whitespace",
                "sidescrolloff", "siso", "hidden", "hid",
                "gitignore", "ignore", "regex", "re", "sort", "sortreverse", "sr", "dirsfirst", "df", "colors"],
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
                ["`wrap`", "Wrap a line too long for the window: after a space, a `_` or where a word starts or "
                    + "ends (but not before a `,`, `.`, `-`, `_`, `/` or `)`), else anywhere, and in the listing "
                    + "never after the icon alone. Questions (what to apply or undo) and the hover box wrap so too. "
                    + "View > Word Wrap (`" + altKey + "Z`) toggles it too. Then `gj` and `gk` go "
                    + "a row down or up, the page keys and `Ctrl-E` count rows, and nothing scrolls sideways."],
                ["`visualwhitespace`  `vws`", "In visual mode, show the selection's spaces as `·`, its tabs as "
                    + "`→` and its line breaks as `¬` (another kind of space, like an em space, as `␣`). "
                    + "Default: the one in Settings (on)."],
                ["`sidescrolloff`  `siso`", "Columns kept in view beside the cursor. Default 4."],
                ["`shell`  `sh`", "The shell `:!` runs commands in: a path, or a name on the PATH, like "
                    + "`:set sh=bash`. Default: the one in Settings, else `" + systemShell + "`."],
                ["`hidden`  `hid`", "Show entries starting with `.`."],
                ["`gitignore`  `ignore`", "Hide what git ignores, and `.git`."],
                ["`regex`  `re`", "Read the path as a regex, not a glob. `,` is any character but `/`. It "
                    + "can look around, as a search's (see `:h search`): `,*(?<!\\.min)\\.js`."],
                ["`sort`", "What the listing is sorted by (see `:h gs`), like `:set sort=size`: `name`, "
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
            part: true,
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
            part: true,
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
            part: true,
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
                ["`:reg`  `:reg [names]`", "List the registers to pick from, e.g. `:reg a0`, each with its first "
                    + "lines, after its name (`\"a`) and, dimmed before that, what it holds: `c` characters, "
                    + "`l` lines or `b` a block. `Enter` pastes the "
                    + "one the cursor is on after the cursor, as `p` does (`y` the picked ones, as one), and `D` "
                    + "clears it (`d` the picked ones). Its other keys are any list's: see `:h pick`."],
                ["`:apply`  `:open` …", "Each key starting with `Space` is a command too, for a shortcut or "
                    + "`koil -c` to say what it does: `:apply`, `:confirm apply`, `:undolist`, `:reveal`, `:open` "
                    + "and `:shortcuts` (see `:h space`)."],
                ["`:norm keys`", "Press keys, as a macro does, like `:norm gss` (keys such as `<CR>` and `<Esc>` "
                    + "written as in a shortcut: see `:h keynames`). With a range, on each line, from its start (`:%norm A;`). "
                    + "`:norm!` leaves your shortcuts out."],
                ["`koil -c 'cmd'`", "Run a command once Koil has opened, like `koil ~/src -c 'set sort=size'`. "
                    + "Several `-c`s run in turn."],
                ["`:h`  `:help [topic]`", "This help, its sections folded to their titles, with the topic's "
                    + "unfolded, e.g. `:h set`, `:h macros`, `:h g` (the keys starting with `g`), or a key, "
                    + "like `:h gJ`. One written in a text, in blue, is a link: a click goes to it "
                    + "(`Ctrl-O` goes back), or from another window or a question, shows it in a help "
                    + "window of its own."],
                ["`Enter`  `Space`  `Tab`", "In the help: unfold or fold the section the cursor is on, as a click on "
                    + "its title does (`l` unfolds it and `h` folds it; so do `za`, `zo` and `zc`). `j` and "
                    + "`k` move the cursor over the titles, through an unfolded section's text first. A "
                    + "search (`/`) unfolds the section it goes to."],
                ["`zR`  `zM`", "In the help: unfold every section, or fold them all."],
                ["`↑`  `↓`", "In the command line: earlier and later commands (or searches)."],
                ["`Ctrl-U`  `Ctrl-W`", "In the command line: delete to the start, or a word back."],
                [isMac ? "`⌥←`  `⌥→`  `⌘←`  `⌘→`" : "`Ctrl+←`  `Ctrl+→`  `Home`  `End`",
                    "In the command line, as in a text field: a word back or on, and to the start or the end. "
                    + "With `Shift`, or the mouse, they select. " + (isMac ? "`⌥⌫`" : "`Ctrl+Backspace`")
                    + " deletes a word."],
                [isMac ? "`⌘A`  `⌘C`  `⌘X`  `⌘V`" : "`Ctrl+A`  `Ctrl+C`  `Ctrl+X`  `Ctrl+V`",
                    "In the command line: select all of it, copy or cut what's selected, and paste the "
                    + "clipboard, as one line."],
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
                + "longer (`:_!cmd`: in the scratchpad). One that takes a while shows what it writes in the "
                + "box as it comes, like its progress. `Esc` stops it.",
            rows: [
                ["`!`", "Types `:! %` with the cursor before the `%`, for a command on the entry on the "
                    + "line, like `git add` then `Enter` (in a file, on the file; in the scratchpad, on the "
                    + "entry pasted on the line, or else on its file). With a "
                    + "count (`3!`), in visual mode or with lines marked (`m`), the range of those lines: in "
                    + "the listing, `%` is their entries, in the scratchpad `<cfile>` is the entries "
                    + "pasted on them (or the paths written), and in a file they're put through the "
                    + "command, as `g!` does."],
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
            tags: ["search", "/", "?", "regex", "regexp", "pattern", "lookbehind", "lookahead", "find", "replace", "n", "*"],
            rows: [
                ["`/pattern`  `?pattern`", "Search forward or backward, with regexes as Perl's (`\\bword\\b`, "
                    + "`\\d{3}`), not vim's. Case counts only if there's an uppercase letter."],
                ["`(?<!a)b`  `(?<=a)b`", "A `b` that isn't after an `a`, or one that is. What it looks "
                    + "behind for can be `ab|c`, but not `a+` (in the path it can). `b(?!a)` and `b(?=a)` "
                    + "look ahead."],
                ["`(?i)`  `\\p{L}`  `\\1`  `a++`", "Ignore case from there on, any letter (`\\x{1F600}` "
                    + "is a character by its number), what the first group took, and an `a+` that gives "
                    + "nothing back."],
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
                ["`old`", "A regex, as `/` takes (`(\\d+)`, not vim's `\\(\\d\\+\\)`). Case counts "
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
                    + "`gS` puts it on lines of its own around characters too. On marked lines (`:h m`), "
                    + "around each run of them next to each other."],
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
                    + (isMac ? "`⌘C` and `⌘V` do." : "`Ctrl+C` does, and `Ctrl+V` while typing or in the command line.")],
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
                ["Your keys", "Your shortcuts: keys of yours (`Space c`, `gc`, `<C-k>`, `" + (isMac ? "⌃⇧K" : "Ctrl+Shift+K")
                    + "` as `<C-K>`" + (isMac ? ", `⌘K` as `<D-k>`" : "") + ") that run keys as a "
                    + "macro does, like `:!git add %<CR>`, in normal mode, visual mode (also on marked lines: "
                    + "see `:h m`) or both. A count runs one "
                    + "that many times. They come before vim's: a shortcut on `xa` makes `x` wait for the `a`. "
                    + "Koil's own keys can't be taken, nor keys that start them or start with them (`g`, `g.x`). "
                    + "F-keys, and keys like `Esc`, `Tab` and `PageDown` with `Shift`, " + (isMac ? "`⌃` or `⌘`" : "`Ctrl`")
                    + ", are keys too (`<F12>`, `<S-Tab>`, " + (isMac ? "`<D-Esc>` for `⌘Esc`" : "`<C-Esc>`")
                    + "); in the form, `Tab`, `Esc` and `Enter` alone go through it. `:h keynames` lists "
                    + "every name."],
                ["`Space q`  `:shortcuts`", "List your shortcuts (so do " + (isMac ? "Koil > Shortcuts…" : "File > Shortcuts…")
                    + " and Settings), and under them the built-in ones, with the lock button on. Typing searches "
                    + "them, `↑` and `↓` pick one, and `Enter` or a click runs it, also one with no keys, on the "
                    + "selection if it's for visual mode. The pencil edits one, and `" + cmdKey + "N` adds one. "
                    + "Export lists them to pick from, with that list's keys (`j` `k`, `Ctrl-D`, `Space`, `v`, `a`, `/`: "
                    + "see `:h pick`); `Enter` exports the picked ones, `Y` the one the cursor is on."]
            ]
        },
        {
            title: "Key names",
            tags: ["keynames", "keyname", "key-names", "names", "key", "notation", "key-notation", "keycodes",
                "<>", "special"],
            intro: "How keys are written where keys are run: a shortcut's (see `:h shortcuts`), `:norm`, "
                + "`koil -c 'norm …'`, and what `q` records. A key with no name is its character: `a`, `A`, "
                + "`5`, `:`, and a space for `Space`. These are all the names, written as here: `<cr>` or "
                + "`<c-a>` is no key, and types its characters.",
            rows: [
                ["`<Esc>`", "`Esc` (`Ctrl-[` is `<Esc>` too)."],
                ["`<CR>`", "`Enter`."],
                ["`<Tab>`", "`Tab`."],
                ["`<BS>`  `<Del>`", "`Backspace` and `Delete`. They take no `S-` or `C-`."],
                ["`<Left>`  `<Right>`  `<Up>`  `<Down>`", "The arrows."],
                ["`<Home>`  `<End>`  `<PageUp>`  `<PageDown>`", "The keys of those names."],
                ["`<F1>` … `<F35>`", "The F-keys, which do nothing but run a shortcut."],
                ["`<S-CR>`  `<S-Tab>`  `<S-Left>`  `<S-F5>`", "`Shift` and a key with a name (any above but "
                    + "`<BS>` and `<Del>`). `<S-CR>` is vim's `Enter` in the listing, and `<S-Tab>` the dir "
                    + "before while completing a path; the others are the key alone, unless a shortcut takes "
                    + "them. `Shift` and a character is that character: `A`, `?`."],
                ["`<C-a>` … `<C-z>`", "`Ctrl` and a letter, lowercase" + (isMac ? " (the `⌃` key, not `⌘`)" : "")
                    + ", as in `:h ctrl`. A shortcut on one comes before vim's, and before what the "
                    + "key does in a text field" + (isMac ? " (`⌃K`)" : " (`Ctrl+A`)") + "."],
                ["`<C-A>` … `<C-Z>`", "`Ctrl`, `Shift` and a letter: the uppercase letter, with no `S-`. "
                    + "It's `Ctrl` and the letter (`<C-a>`, as vim reads it) unless a shortcut takes it."],
                ["`<C-1>`  `<C-/>`  `<C-?>`", "`Ctrl` and a digit or a sign (but `>`), as `Shift` makes it: "
                    + "`<C-?>` is `Ctrl`, `Shift` and `/`. They do nothing but run a shortcut. `Ctrl-[` is "
                    + "`<Esc>`."],
                ["`<C-M-k>`  `<C-M-K>`  `<C-M-1>`", "`Ctrl`, `" + alt + "` and a letter (uppercase with "
                    + "`Shift`), digit or sign, which do nothing but run a shortcut" + (isMac ? ""
                    : " (not where they type a character, as `AltGr` does)") + ". `M-` goes after `C-`."],
                ["`<C-CR>`  `<C-Esc>`  `<C-Left>`  `<C-F5>`  `<C-S-Left>`  `<C-M-Left>`", "`Ctrl` and a key "
                    + "with a name (not `<BS>` or `<Del>`), with `" + alt + "` and `Shift` too (in that "
                    + "order: `<C-M-S-Left>`), which do nothing but run a shortcut."]
            ].concat(isMac ? [
                ["`<D-k>`  `<D-K>`  `<D-1>`  `<D-/>`", "`⌘` and a letter (uppercase with `⇧`), a digit or a "
                    + "sign (but `>`), which do nothing but run a shortcut. Not those Koil's menus take, "
                    + "like `⌘S` and `⌘C`."],
                ["`<C-D-k>`  `<M-D-k>`  `<C-M-D-K>`", "`⌘` and those with `⌃`, `⌥` or both before it (`C-`, "
                    + "`M-`, then `D-`), and `⇧` still an uppercase letter: `⌃⌘K`, `⌥⌘K`, and all four with `K`."],
                ["`<D-CR>`  `<D-Esc>`  `<D-Left>`  `<D-F5>`  `<D-S-Left>`  `<C-M-D-S-Left>`", "`⌘` and a key "
                    + "with a name, with `⇧` too (`D-` first), and `⌃` and `⌥` before it, for a shortcut as "
                    + "well."],
                ["`<D-BS>`", "`⌘⌫`: while typing, deletes to the line's start (in the listing, the name's), "
                    + "and in the command line, to its start."]
            ] : []),
            note: "`Shift` is `S-` only before a key with a name; with a character, it's in the "
                + "character (`<C-K>`, not `<C-S-k>`). `" + alt + "` alone has no name" + (isMac ? ", as it types characters" : "")
                + ": it's `M-` only with `" + (isMac ? "⌃` or `⌘" : "Ctrl")
                + "`. Nor have vim's `<Space>`, `<lt>`, `<Bar>`, `<Leader>` and `<Nop>`: write a space, `<` "
                + "and `|`. A name is always its key, so keys can't type the text of one, like `<CR>`. In "
                + "the shortcuts' form, `Tab`, `Esc` and `Enter` alone go through it, and with `Shift`"
                + (isMac ? ", `⌃` or `⌘`" : " or `Ctrl`") + " they're keys."
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
                ["`>`  `=`  `U`  `gU`  `r`", "Indent, reindent, change case or replace characters on each "
                    + "one."],
                ["`S`  `gS`", "Surround each run of them next to each other, as lines selected (`S)`: see "
                    + "`:h surround`)."],
                ["`@a`  `Q`", "Run a macro on each one in turn, from its start, as in visual mode."],
                ["`:`", "`:'<,'>` is them: `:s/a/b/` changes only them."],
                ["Your keys", "A shortcut of yours for visual mode runs its keys on them, as on a selection "
                    + "(before one for normal mode with the same keys)."],
                ["`Esc`", "Unmark them all. `gv` marks them again (also after using them)."]
            ],
            note: "Other keys work as in normal mode: `u` undoes, `i` and `o` type at the cursor."
        },
        {
            title: "Hidden text",
            tags: ["hide", "reveal", "icon", "icons", "id", "gh"],
            rows: [
                ["icons", "In the listing, each icon hides its entry's ID, which whole lines take along."],
                ["`gh`", "Show what the line's icon hides, wherever the cursor is on the line: an ID "
                    + "shows as its path (so does resting the mouse on the icon)."],
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
                ["`gg`", "The first line, at its first character that isn't blank (`5gg`: line 5)."],
                ["`ge`  `gE`", "Back to the end of the word before (`gE`: of the WORD, between blanks)."],
                ["`gj`  `gk`", "Down or up a row of a line that wraps (see `:h wrap`)."],
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
                ["`ZQ`", "Quit without saving."],
                ["`za`  `zo`  `zc`", "In the help: fold or unfold the section the cursor is on (`za`), "
                    + "unfold it, or fold it (see `:h help`)."],
                ["`zR`  `zM`", "In the help: unfold every section, or fold them all."]
            ],
            note: "Nothing scrolls sideways while lines wrap (`:set wrap`)."
        },
        {
            title: "Keys starting with Space",
            tags: ["space", "<space>", "leader", "undolist", "undol"],
            intro: "Koil's own, in the listing and the path field. In a file, `Space Space` saves, `Space r` "
                + "and `Space o` take the file, and `Space q` works everywhere, in visual mode too. Each is "
                + "a command too, which does the same wherever the keys do something (`:apply` in a file "
                + "saves), so a shortcut or `koil -c` can say what it does: `koil ~/src -c undolist`.",
            rows: [
                ["`Space Space`  `:apply`", "Apply the changes, listing them first (Settings can skip that). "
                    + "In a file: save."],
                ["`Space a`  `:conf apply`", "Apply, always listing the changes first (`:confirm apply`)."],
                ["`Space u`  `:undolist`", "Undo applies, or single changes of them, picked from all of them, "
                    + "newest first."],
                ["`Space r`  `:reveal`", "Show the entry on the line (in a file, the file) in " + fileManager + "."],
                ["`Space o`  `:open`", "Open the entry on the line (in a file, the file) in its default app."],
                ["`Space q`  `:shortcuts`", "List your shortcuts, and the built-in ones (see `:h shortcuts`)."]
            ],
            note: "Shortcuts of yours can start with `Space` too, like `Space c`. The commands can be cut "
                + "short, as vim's: `:ap`, `:undol`, `:rev`, `:o`, `:sho`."
        },
        {
            title: "Ctrl keys",
            tags: ["ctrl", "control", "ctrl-a", "ctrl-x", "ctrl-e", "ctrl-y", "ctrl-d", "ctrl-u", "ctrl-f",
                "ctrl-b", "ctrl-r", "ctrl-c", "ctrl-n", "ctrl-p", "ctrl-w", "ctrl-o"],
            intro: isMac ? "The `Ctrl` key, not `⌘`."
                : "On Windows, `Ctrl+F` is Find, and `Ctrl+V` pastes while typing or in the command line.",
            rows: [
                ["`Ctrl-D`  `Ctrl-U`", "Down or up half a page."],
                ["`Ctrl-F`  `Ctrl-B`", "Down or up a page."],
                ["`Ctrl-E`  `Ctrl-Y`", "Scroll a line down or up (a row, while lines wrap)."],
                ["`Ctrl-R`", "Redo."],
                ["`Ctrl-A`  `Ctrl-X`", "Add to or subtract from the number at or after the cursor."],
                ["`Ctrl-V`", "Visual block (see `:h block`)."],
                ["`Ctrl-O`", "In the help: back to where a link, like `:h block`, was clicked."],
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
                ["`dd`  `>>`", "Keep the cursor's column, as Neovim's do, and so do `H`, `M`, `L`, "
                    + "`50%`, `:5`, `==` and visual `d`, `>` and `<` on lines. Vim's go to the line's first "
                    + "character that isn't blank, which `^` does. `gg` and `5G` go there too, as Vim's, "
                    + "and `G` to the text's last character."],
                ["`=`  `==`", "Reindent: `==` the line, `=ip` the paragraph, `gg=G` all of it, or in visual mode "
                    + "what's selected. A line in brackets (or HTML tags) goes a level deeper than the line "
                    + "they open on, and one that closes them as deep as that line. A line in none keeps its "
                    + "indent, so Python and YAML stay as they are. A level is the file's: a tab, or 2, 4 or "
                    + "8 spaces."],
                [isMac ? "`⌘Z`  `⇧⌘Z`" : "`Ctrl+Z`  `Ctrl+Shift+Z`",
                    "Undo and redo, like `u` and `Ctrl-R`."],
                [isMac ? "`⌘+`  `⌘-`  `⌘0`" : "`Ctrl+=`  `Ctrl+-`  `Ctrl+0`",
                    "Zoom in, out, or back to the Settings size."],
                ["`" + cmdKey + ",`", "Settings: font, line numbers, syntax colors, word wrap, whitespace in "
                    + "selection, theme, folders first, when applying asks, start dir, shell and more. The "
                    + "pointer on a setting's name shows what it does."]
            ]
        },
        {
            // Last, so a key that's no topic (`:h x`) goes to vim's row
            // first (see HelpPanel.show).
            title: "Picking changes",
            tags: ["pick", "picking", "picked", "discard", "changes", "applies"],
            intro: "`Space Space`, `Space a` and `Space u` list the changes to pick from. `Space u` lists "
                + "each apply's under a heading: there the cursor is on all of an apply, until `l` goes "
                + "into it. Uppercase keys act on what the cursor is on, picked or not. The list stays "
                + "open while changes are left.",
            rows: [
                ["`j`  `k`", "Move down or up."],
                ["`g`  `G`", "Go to the first or last line."],
                ["`Ctrl-D`  `Ctrl-U`", "Move down or up half a page; `Ctrl-F` and `Ctrl-B` (or `PageDown` and "
                    + "`PageUp`) a page. `Ctrl-E` and `Ctrl-Y` scroll a line, leaving the cursor."],
                ["`Space`  `x`", "Pick or leave out the line (with what it needs, or what needs it), as a click on it "
                    + "does."],
                ["`v`", "Select several lines; `v` or `Esc` ends it."],
                ["`a`", "Pick all, or none (searching, of the lines shown)."],
                ["`/`", "Search: only the lines with every word typed show, as you type, like the changes "
                    + "to a file by its name. A word can also be in an apply's heading (its dir). Case counts "
                    + "only with an uppercase letter. `Enter` keeps it (`↑` `↓` move meanwhile), `Esc` puts "
                    + "the last one back, and `Esc` in the list shows all of it again. Picked lines stay "
                    + "picked, shown or not."],
                ["`y`  `Y`", "Apply the picked ones (`Y`: the highlighted one); the rest stays. In `Space u`: "
                    + "undo them."],
                ["`d`  `D`", "Discard the picked ones (`D`: the highlighted one). In `Space u`: delete them "
                    + "from the history."],
                ["`u`", "Undo the listing's last edit, a discard, or an apply made here (its changes come "
                    + "back to pick)."],
                ["`l`  `h`  `Tab`", "In `Space u`: go into the apply the cursor is on, to pick single "
                    + "changes of it, and out again (`Tab` does either). One with many changes shows only "
                    + "some until then: the picked ones first, how many more it has, and how many of each "
                    + "kind."],
                ["`Enter`", "The blue button: apply, or undo."],
                ["`c`  `Esc`", "Cancel (`Esc` first ends a selection, then a search)."],
                ["`?`", "Show these keys, as the ? button does, in a window of its own, so the list stays "
                    + "open: it floats over Koil's windows until `q` or `Esc` closes it."]
            ],
            note: "`Y` and `D` ask first if the line takes others along. Quitting, `n` quits without the "
                + "changes, and there's no `d` or `u`. Every list to pick from has the keys that move, pick, "
                + "select and search, and `Y`: the shortcuts to export too (see `:h shortcuts`), and `:reg`'s "
                + "registers, where `y` and `Y` paste, `d` and `D` clear, and `Enter` with none picked "
                + "pastes the one the cursor is on."
        }
    ];
}
