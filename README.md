# Koil

Koil's desktop app: a vim-style editor in Rust + Qt 6
([CXX-Qt](https://github.com/KDAB/cxx-qt)) and QML.

For now it opens with a sample listing, where each line starts with an icon
(🍄 or 🪑) that hides some text. Rest the mouse on an icon, or press `gh` on
it, to see what it hides. `:help` (or `:h`) lists everything that isn't
standard vim.

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
cargo run
qmltestrunner -input tests   # the editor's tests
```

## Release

```sh
cargo release patch --execute   # or minor / major
```

This bumps the version, tags it and pushes. CI then builds both installers
and publishes them as a GitHub release.
