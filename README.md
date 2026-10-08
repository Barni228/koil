# Koil

Koil desktop app: a vim-style editor in Rust + Qt 6
([CXX-Qt](https://github.com/KDAB/cxx-qt)) and QML.

It edits a directory as text, like [oil.nvim](https://github.com/stevearc/oil.nvim):
the first line is the directory (or a glob or regex of files), then each entry
is a line with its icon and name. Rename, delete, copy and create entries by
editing the lines, and move them by cutting a line in one directory and
pasting it in another. `Cmd+S` (`Ctrl+S`) updates the listing, `Space Space`
applies the changes once you confirm them (deleted files go to the trash),
and `u` after that undoes them. Enter opens a directory or a file, and `-`
the directory above (or, in a file, goes back to the listing).
`:help` (or `:h`) lists everything that isn't standard vim.

The icons are [Nerd Font](https://www.nerdfonts.com) glyphs. Koil comes with
one, JetBrains Mono NL (its default font), which shows them whatever the
editor's font. It's under the [SIL Open Font License](fonts/OFL.txt).

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

**macOS**: in Finder, press `⇧⌘J` (or choose _Finder → Services → Open in
Koil_) to open the folder Finder's window shows in Koil. It works whether
Koil is running or not, and only in Finder. The first time, macOS asks to
let Koil control Finder, which is how Koil finds out which folder that is.

The default is `⇧⌘J` because a shortcut an app gives its service can only
be `⌘` plus a key, or `⇧⌘` plus a letter, and `⇧⌘J` is one Finder doesn't
use (`⇧⌘K` is Finder's _Network_). To pick another one, like `⌥⌘K` or `⌃K`,
open _System Settings → Keyboard → Keyboard Shortcuts… → Services →
General_, double-click the shortcut next to _Open in Koil_ and press the new
one. Koil's Settings window shows the shortcut in use, and has a button that
opens Keyboard Shortcuts.

**Windows**: right-click a folder, the background of a folder's window, or
a drive, and choose _Open in Koil_ (on Windows 11, under _Show more
options_). The installer adds it unless you untick that option.

## Build

Needs Rust and Qt 6 with `qmake` on `PATH` (macOS: `brew install qtbase qtdeclarative`).

```sh
cargo run                    # lists your home directory
cargo run -- path            # a directory, a pattern, or a file to edit
cargo test                   # the listing's tests
qmltestrunner -input tests   # the editor's tests
```

## Release

```sh
cargo release patch --execute   # or minor / major
```

This bumps the version, tags it and pushes. CI then builds both installers
and publishes them as a GitHub release.
