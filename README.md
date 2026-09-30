# Koil

Koil's desktop app: a vim-style editor in Rust + Qt 6
([CXX-Qt](https://github.com/KDAB/cxx-qt)) and QML.

It edits a directory as text, like [oil.nvim](https://github.com/stevearc/oil.nvim):
the first line is the directory (or a glob or regex of files), then each entry
is a line with its icon and name. Rename, delete, copy and create entries by
editing the lines, and move them by cutting a line in one directory and
pasting it in another. `Space Space` updates the listing, `Space a` applies
the changes once you confirm them (deleted files go to the trash), and `u`
after that undoes them. Enter opens a directory, and `-` the one above.
`:help` (or `:h`) lists everything that isn't standard vim.

The icons are [Nerd Font](https://www.nerdfonts.com) glyphs: they show with a
Nerd Font installed (any one is used for them, whatever the editor's font).

## Install

Download the installer from the
[latest release](https://github.com/Barni228/koil/releases/latest).

**macOS**: open the `.dmg` and drag Koil to Applications. The app isn't
signed, so clear the quarantine flag before the first launch:

```sh
xattr -cr "/Applications/Koil.app"
```

**Windows**: run the setup `.exe`. If SmartScreen blocks it, choose
*More info → Run anyway*.

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
