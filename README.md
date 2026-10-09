# Koil

Koil edits a directory as text, like [oil.nvim](https://github.com/stevearc/oil.nvim):
the first line is the directory (or a glob or regex of files), then each entry
is a line with its icon and name. Rename, delete, copy and create entries by
editing the lines, and move them by cutting a line in one directory and
pasting it in another. `Cmd+S` (`Ctrl+S`) updates the listing, `Space Space`
applies the changes once you confirm them (deleted files go to the trash),
and `u` after that undoes them. Enter opens a directory or a file, and `-`
the directory above (or, in a file, goes back to the listing).
`:help` (or `:h`) lists everything that isn't standard vim.

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
Koil_, or select it and press `⌃⇧K`, to open it in Koil.

The default shortcut is `⌃⇧K`, To pick another one, open
`System Settings → Keyboard → Keyboard Shortcuts... → Services → Files and Folders`,
double-click the shortcut next to _Open in Koil_ and press the
new one (or press backspace to remove the shortcut).
Koil Settings window shows the shortcut in use, and has a button
that opens Keyboard Shortcuts.

**Windows**: right-click a folder, the background of a folder's window, or
a drive, and choose _Open in Koil_ (on Windows 11, under _Show more
options_). The installer adds it unless you untick that option.

## Command line

```sh
koil                  # lists the Start in setting's directory, or your home
koil ~/src            # a directory, a glob or regex of files ('*.rs'), or a file
koil +42 notes.txt    # the file, with the cursor on line 42
koil -s               # the scratchpad (_ in a listing), a text that's never saved
echo hi | koil        # what's piped in opens in the scratchpad
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
