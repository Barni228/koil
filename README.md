# Koil

Koil edits a directory as text, like [oil.nvim](https://github.com/stevearc/oil.nvim),
in an editor with vim's keys. Each entry is a line: its icon and its name. Edit
a name to rename it, delete lines to delete, copy lines to copy, and write new
ones to create (`notes.txt`, `docs/` for a dir, `a/b/c.txt` with its dirs).
Cut a line, go to another dir and paste it to move. Nothing changes on disk
until you apply, and your edits stay while you go through other dirs.

| Key            | Does                                                                          |
| -------------- | ----------------------------------------------------------------------------- |
| `Cmd+S`        | Update: read your edits and show the listing again (doesn't change anything)  |
| `Space Space`  | Apply, Deletes go to the trash. In a file, save                               |
| `u`            | Undo                                                                          |
| `Enter`        | Open the dir or file on the line                                              |
| `-`            | The dir above (`3-`: three up). In a file, back to the listing                |
| `Tab`          | Go between the listing and the path field over it                             |
| `g.` `gi` `gr` | Toggle hidden files, hiding what git ignores, and reading the path as a regex |
| `gs`           | Change sort order: `gss` by size, `gsm` by date modified, `gsS` biggest last, |
| `_`            | The scratchpad                                                                |
| `Space r`      | Show the entry in Finder or Explorer                                          |
| `:h`           | Show help page                                                                |

`Cmd` is `Ctrl` on Windows.

## Good to know

- **The path field** takes a path relative to the open dir (`src`,
  `../docs`), `~`, one pasted from a terminal (`"my dir"`, `my\ dir`), or a
  glob (`**/*.rs`). Write `/`, also on Windows. `Tab` while typing completes
  a dir like a shell, and `k` and `j` go through the dirs you listed before.
- **Regex paths** (`gr`) must match the whole path below the dir they start
  in. For convenience, `,` is same as `.` except it does not match `/`, which
  is useful to list things without going into subdirectories
  (`dir/,*` matches `dir/file.txt` but not `dir/subdir/file.txt`)
- **Smart case**: search and `Tab` completion ignore case unless you type an
  uppercase letter. Search takes JavaScript regexes (`\d{3}`, `\bword\b`),
  not vim's.
- **IDs**: each icon hides its entry's ID, which goes with the line wherever
  it's pasted, so a pasted line is a copy or a move, never a new empty file.
  `gh` (or hovering the mouse on the icon) shows the path an ID stands for.
  `Backspace` at the start of a name drops its ID, making the entry new.
- **The scratchpad** (`_`, or `koil -s`) is a text that's never saved, kept
  until Koil quits. Lines pasted there keep their IDs, so you can put
  entries aside and paste them into a listing later.
- **Changes on disk** show in the listing as they happen, keeping your
  edits. If one goes against them (a file you deleted was renamed), Koil
  asks.
- **Problems**, like a name written twice or one Windows can't use, are
  underlined as you type. Errors block applying.
- **Sizes**: sorted by size, each line shows its entry's, and dirs' are
  counted in the background (the `...` animation), then sorted.

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
Koil_, or select it and press `⌃⇧K`. To change the shortcut,
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
koil --help           # all the options
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
