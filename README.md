# Koil

Koil edits a directory as text, like [oil.nvim](https://github.com/stevearc/oil.nvim),
in an editor with vim's keys. Each entry is a line: its icon and its name. Edit
a name to rename it, delete lines to delete, copy lines to copy, and write new
ones to create (`notes.txt`, `docs/` for a dir, `a/b/c.txt` with its dirs).
Cut a line, go to another dir and paste it to move. Nothing changes on disk
until you apply, and your edits stay while you go through other dirs.

| Key            | Does                                                                              |
| -------------- | --------------------------------------------------------------------------------- |
| `Cmd+S`        | Update: read your edits and show the listing again (doesn't change anything)      |
| `Space Space`  | Apply, Deletes go to the trash. In a file, save                                   |
| `u`            | Undo                                                                              |
| `Enter`        | Open the dir or file on the line                                                  |
| `-`            | The dir above (`3-`: three up). In a file, back to the listing                    |
| `Tab`          | Go between the listing and the path field over it                                 |
| `g.` `gi` `gr` | Toggle hidden files, hiding what git ignores, and reading the path as a regex     |
| `gs`           | Change sort order, (sort by size, size on disk, last modified, natural, and more) |
| `_`            | The scratchpad                                                                    |
| `Space r`      | Show the entry in Finder or Explorer                                              |
| `Space o`      | Open the entry in its default app                                                 |
| `Space q`      | Your shortcuts: run one, edit them or make one                                    |
| `!`            | Run a shell command on the entry (`!git add`). `:!cmd` runs any command           |
| `m`            | Mark lines anywhere, then `d`, `y`, `!` or `A` act on all of them at once         |
| `:h`           | Show help page (`:h g`: the keys starting with `g`; `:h gJ`: a key)               |

`Cmd` is `Ctrl` on Windows.

## Good to know

### In short

- In the path field's regex mode (`gr`), `,` is any character but `/`.
- In a glob, `*` matches only files and `*/` only dirs (`*{,/}` both).
- Vim-surround keys work, like `dsb` or `ysiw)`
- `Cmd+click` a path or URL to open it.
- `!` runs a shell command on the entry on the line (`g!` is vim's `!`).
- `:h` and a key or a word shows its help, like `:h g` or `:h gJ`.
- `koil` cli command opens koil, useful for automation (`-c` is especially useful)

### In detail

- **The path field** takes a path relative to the open dir (`src`,
  `../docs`), `~`, one pasted from a terminal (`"my dir"`, `my\ dir`), or a
  glob (`**/*.rs`). Write `/`, also on Windows. `Tab` while typing completes
  a dir like a shell (and like zsh, `myt` gives `my_tools` if no dir starts
  with `myt`), and `k` and `j` go through the dirs you listed before.
- **Globs match a dir with its `/`**, as it's listed, so unlike in a shell,
  `*` shows only files, `*/` only dirs, and `{*,*/}` both. As in a shell,
  `*` skips names starting with `.`, but `.*` or `**/.env` shows them even
  while hidden entries are off (`g.`).
- **Regex paths** (`gr`) must match the whole path below the dir they start
  in. For convenience, `,` is same as `.` except it does not match `/`, which
  is useful to list things without going into subdirectories
  (`dir/,*` matches `dir/file.txt` but not `dir/subdir/file.txt`)
- **Smart case**: search, `:s` and `Tab` completion ignore case unless you
  type an uppercase letter. Search takes JavaScript regexes (`\d{3}`,
  `\bword\b`), not vim's.
- **Replace** with vim's `:s`: `:%s/old/new/g`, or in visual mode `:s` in
  only the selection. As you type it, the text shows what it would become,
  and `Esc` puts it back. In the listing a line starts at its name, so
  `:%s/^/old_/` renames every entry.
- **Surround**, as vim-surround: `ysiw)` puts `(`…`)` around a word, `yss"`
  quotes the line, `ds(` deletes the brackets around the cursor, `cs"'`
  changes `"` to `'`, and `S)` in visual mode surrounds the selection.
  `ysiw<em>` puts a tag around it (`dst`, `cst<` for tags).
- **Reindent** with `=`: `==` the line, `gg=G` the file. A line in
  brackets (or HTML tags) goes a level deeper than the line they open on;
  lines in none keep their indent, so Python and YAML don't break.
- **Neovim's defaults**: `Y` yanks to the line's end, `&` keeps `:s`'s
  flags, `G`, `gg` and `dd` keep the cursor's column, `*` in visual mode
  searches for the selection, `@q` in visual mode runs the macro on each
  line, and `Q` runs the one recorded last.
- **IDs**: each icon hides its entry's ID, which goes with the line wherever
  it's pasted, so a pasted line is a copy or a move, never a new empty file.
  `gh` (or hovering the mouse on the icon) shows the path an ID stands for.
  `Backspace` at the start of a name drops its ID, making the entry new.
- **Marked lines**: `m` marks a line (in visual mode, the selected lines),
  and the cursor moves on as usual, so lines far apart can be marked. Then
  the keys of visual mode act on all of them, as if they were together:
  `d` or `y` takes them in one register (`p` in another dir then moves or
  copies them there), `!git add` runs on all of them, `A.bak<Esc>` types
  after each, and `:s` changes only them. `Esc` unmarks them.
- **The scratchpad** (`_`, or `koil -s`) is a text that's never saved, kept
  until Koil quits. Lines pasted there keep their IDs, so you can put
  entries aside and paste them into a listing later.
- **Colors in a file** (and the scratchpad) suit any file rather than its
  language: strings, numbers, comments, paths and URLs, and the bracket
  that matches the one at the cursor. In Markdown, `#` starts a heading,
  not a comment, and in Python `//` divides. `:syntax off` (or Settings)
  turns them off.
- **Links**: in a file, `gf` opens the file or dir under the cursor in Koil
  (a relative path is looked for next to the file, then in the open dir),
  or a URL in the browser, and `gx` opens it in its default app. Hold
  `Cmd` and click a path or URL to open it as `gf` does. In the listing,
  they open the entry on the line.
- **Word wrap** (_View → Word Wrap_, `⌥Z`, or `:set wrap`; Settings turns
  it on for good): a line too long for the window goes on in rows under
  it, at a word's start in a file, and anywhere in the listing, where a
  long name goes on under itself. `gj` and `gk` go a row down or up.
- **Changes on disk** show in the listing as they happen, keeping your
  edits. If one goes against them (a file you deleted was renamed), Koil
  asks. A file that changes is read again, as a change `u` takes back (if
  you changed it too, Koil asks first).
- **Problems**, like a name written twice or one Windows can't use, are
  underlined as you type. Errors block applying.
- **Sizes**: sorted by size, each line shows its entry's, and dirs' are
  counted in the background (the `...` animation), then sorted.
- **Shell commands** run in the open dir, in the shell from Settings (Git
  Bash, say, on Windows). `%` is the entry on the line (or the open file),
  quoted, like vim's: `:!mv % old/`, and `!` types `:! %` for it. `!` in
  visual mode (or with lines marked) runs one on every selected entry,
  and `g!` is vim's `!`, which puts the lines through a command (`g!ip`,
  then `fmt`). `<cfile>` is the path or URL under the cursor, as `gf`
  opens it.
  `:_!cmd` puts what it writes in the scratchpad, like `:_!git log`, where
  `%` is a file of its text (`!echo hi >> %` adds a line).
- **Shortcuts** (`Space q`, _Koil → Shortcuts…_, or Settings): keys of
  yours, like `Space c` or `gc`, run keys as a macro does, like
  `:!echo %:p | pbcopy<CR>` to copy the entry's path. Type the keys, or take
  a macro you recorded with `q`. A click in the list runs one, also one with
  no keys. Built-in shortcuts can't be changed or taken; the lock button
  shows them under yours.
- **Settings** (`Cmd+,`): rest the pointer on a setting's name to see what
  it does.

## Install

Download the installer from the
[latest release](https://github.com/Barni228/koil/releases/latest).

**macOS**: open the `.dmg` and drag Koil to Applications. The app isn't
signed, so clear the quarantine flag before the first launch:

```sh
xattr -cr "/Applications/Koil.app"
```

**Windows**: run the setup `.exe`. If SmartScreen blocks it, choose
_More info → Run anyway_.

## Open a folder from Finder or Explorer

**macOS**: in Finder, right-click a folder and choose _Services → Open in
Koil_, or select it and press `⌃⇧K`. On a file, it opens the folder the
file is in, with the cursor on it. To change the shortcut,
open _System Settings → Keyboard → Keyboard Shortcuts... → Services →
Files and Folders_ (Koil's Settings window has a button for it),
double-click the one next to _Open in Koil_ and press the
new shortcut (or backspace for no shortcut at all).

**Windows**: right-click a folder, the background of a folder's window, or
a drive, and choose _Open in Koil_ (on Windows 11, under _Show more
options_). The installer adds it unless you untick that option.

## Command line

```sh
koil                  # lists the Start in setting's directory, or your home
koil ~/src            # a directory, a glob ('src/**/*.rs'), or a file
koil +42 notes.txt    # the file, with the cursor on line 42
koil -s               # the scratchpad
git diff | koil       # what's piped in opens in the scratchpad
ls | koil -p | sort   # prints the scratchpad's text when Koil quits
koil --help           # all the options
```

`-c` runs a command once Koil has opened, as if typed after `:`, so
anything Koil does can be done from the command line. Each `-c` runs in
turn, and `:normal` presses keys:

```sh
koil ~/src -c 'set sort=size wrap' -c 'set gfn=Menlo fs=16'
koil ~/src -c 'norm G'
```

To have `koil` in your terminal:

**macOS**: choose _Koil → Settings… → Command line → Install “koil”
Command_. It puts `koil` in `/usr/local/bin`, so macOS asks for your
password. The same button removes it: do that before you delete Koil, as
nothing else does (after, `sudo rm /usr/local/bin/koil`).

**Windows**: the installer adds Koil to `PATH` unless you untick that
option. Terminals opened after that have `koil`.

## Build

Needs Rust and Qt 6 with `qmake` on `PATH` (macOS: `brew install qtbase qtdeclarative`).

```sh
cargo run                    # lists your home directory
cargo run -- path            # a directory, a pattern, or a file to edit
cargo test                   # the listing's tests
qmltestrunner -input tests   # the editor's tests
```
