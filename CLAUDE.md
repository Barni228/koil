# CLAUDE.md

Koil desktop app: a vim-style editor in Rust + Qt 6 via cxx-qt 0.10, with the
UI in QML, that edits a directory as text (like oil.nvim) through koil-core
(`../koil-core`, a library; `../koil-cli` is its CLI; read their CLAUDE.md for
how Koil works). The editor is the one from `~/projects/vim-edit`, cleaned up.
It shows Koil's listing (see docs/listing.md), a file opened with File > Open, or
the scratchpad (see Scratchpad).

## Docs

The details are in `docs/`, a file a topic. Read the file for what you're
about to change before changing it, and update it in the same change: it's
the only record of why things are as they are. A section named elsewhere
("see Wrapping") is a bold heading in one of them:
`grep -rn '\*\*Wrapping\*\*' docs`.

| File | Sections |
|---|---|
| `docs/layout.md` | Layout |
| `docs/listing.md` | The listing, Prefixes, Problems, The path field, Path history, Back and forward, Completion, Drives, Keys, Update, Colors, Clipboard, Paths that aren't Unicode |
| `docs/apply.md` | Apply and undo, Undo history, Changes on disk, Quitting (both) |
| `docs/sizes.md` | Info, Sorting, Dir sizes, Kept sizes, Stale sizes |
| `docs/files.md` | Files, `:e`, Files changed on disk, Scratchpad, Syntax, Links, Matching brackets |
| `docs/shell.md` | Shell commands, Output box |
| `docs/launch.md` | Command line, The koil command, Open in Koil, Open With |
| `docs/vim.md` | Buffers, Vim, Macros, Unknown keys, Batches and runs, Word completion, Edits from outside, Hidden text |
| `docs/vim-commands.md` | Visual block, Multiple cursors, Matches, Multiple selections, Marked lines, Surround, Reindent, Guessed indent, Regular expressions, Substitute, Global, Command line colors, Find bar |
| `docs/shortcuts.md` | Shortcuts (both), Menus |
| `docs/editor.md` | Overlays, Text layout, Long texts, Long lines, Wrapping, Line numbers, Whitespace in the selection, Warnings and errors, Notes after lines, Icon font, Fonts |
| `docs/help.md` | Help, Help window, Help links, Help folds, Scrolling boxes |
| `docs/questions.md` | Questions, Lists to pick from, Registers' list |
| `docs/ui.md` | Theme and zoom, Settings |
| `docs/platform.md` | App icon, cxx-qt, macOS, Windows |

## Layout

A line a file; `docs/layout.md` says what each has, by function.

- `src/lib.rs`: the modules and `run`, the startup; loads `qml/main.qml`.
  `src/main.rs` calls it. `src/cli.rs`: the command line.
- `src/listing.rs`: the listing as text, without Qt; most of Koil's logic.
- `src/history.rs` (undo history's file), `info.rs` (`K`), `shell.rs`,
  `sizes.rs` (dirs' sizes, on threads), `syntax.rs`, `link.rs`,
  `install.rs` (the `koil` command), `convert.rs` (JSON and paths for QML).
- `src/koil.rs`, `document.rs`, `system.rs`: the QML elements `Koil`,
  `Document` and `System`.
- `src/ffi.rs` + `cpp/native.{h,cpp}`: the C++ helpers (text layout,
  highlighters, clipboard); `cpp/finder_mac.mm`: macOS only.
- `qml/main.qml`: the window; wires the pieces, no editing logic.
- `qml/Editor.qml`: the `TextArea` and everything drawn with it.
- `qml/Vim.qml`: the vim emulation. `qml/text.js`: pure text helpers (`Txt`).
- `qml/ConfirmDialog.qml` (every question), `PickList.qml`, `HelpPanel.qml`
  + `help.js`, `FindBar.qml`, `SettingsWindow.qml`, `ShortcutsWindow.qml`,
  `StatusLine.qml`, `Theme.qml` and the controls that share its look.
- `tests/tst_vim.qml`, `tests/tst_shortcuts.qml`; Rust tests in
  `src/*/tests.rs`.
- `scripts/`, `packaging/`, `fonts/`: bundling, icons, the Nerd Font.
- `web/`: the web version's build (`CMakeLists.txt`, the `koil_web` crate,
  `main.cpp`, the page `index.html`); `cpp/web.{h,cpp}`: what only the
  browser's JavaScript can do. `scripts/build-web.sh` builds it into
  `target/web/`, `scripts/web-smoke.mjs` checks it (docs/platform.md, Web).

## Build and test

- Local Qt comes from Homebrew (`qtbase`, `qtdeclarative`); `qmake` must be on
  `PATH`. On Windows: Visual Studio's Build Tools (C++ workload, which
  `cargo` finds itself), rustup, and CI's Qt from aqtinstall (`aqt
  install-qt windows desktop 6.10.3 win64_msvc2022_64 -O <dir>`, its
  `bin` on `PATH`). `cargo build`, `cargo run` (lists the home dir, or the
  Start in setting's), `cargo run -- dir`
  (or a pattern), `cargo run -- file` to open a file, `cargo run -- -s`
  (or `ls | cargo run`) for the scratchpad, `cargo run -- --help` for the
  rest. Try applying in a
  scratch dir: it really moves and trashes files.
- `cargo test` runs the Rust tests (install.rs's run `osascript`, but
  never as admin); `cargo clippy --all-targets`, `cargo fmt`.
- koil-core comes from GitHub (CI checks out only this repo), locked in
  `Cargo.lock`; `cargo update -p koil-core` takes its latest commit. To try
  local changes to `../koil-core`, patch it in `.cargo/config.toml` (not
  committed) with `[patch."https://github.com/Barni228/koil-core"]
  koil-core = { path = "../koil-core" }`.
- `build.rs` adds every `.qml` and `.js` in `qml/` to the QML module. A file
  whose name starts with an uppercase letter becomes a type (and must end in
  `.qml`, or cxx-qt-build panics); `main.qml` and `text.js` stay lowercase.
- `QT_QPA_PLATFORM=offscreen qmltestrunner -input tests` runs the QML
  tests without windows: run them this way while working. Nothing opens
  over the user's work, and what the user types meanwhile doesn't reach
  the tests (with windows it does, and fails them). Only at the very end,
  once everything else is done, run them once with their windows too
  (`qmltestrunner -input tests`), for what offscreen doesn't have: the
  system's fonts and its windows. Offscreen is fast and has other fonts,
  so a test that passes only with windows waited for nothing: have it wait
  for what it needs (`tryVerify`, `waitForRendering` before a key that
  goes by what's in view, `wait(0)` after closing a popup with a window of
  its own, which gives the keys to the window it was in) and scroll to
  what it clicks, as a click reaches only what shows. Windows' offscreen
  has no fonts at all (`Qt.fontFamilies()` is empty: every character is
  a box as wide as the font's size), so a test that measures text in a
  view too narrow for that skips there (tst_vim.qml's `needFonts`), and
  runs with windows.
  They load `qml/` by path, so
  anything they instantiate must not `import Koil` (only `main.qml` does, for
  `Document` and `System`; `Editor` takes `System` as a `var`). With
  windows, a test's
  keys go to the window that has them, and while another app is in front
  (where the tests were started from), macOS takes qmltestrunner's
  activation away about half a second in and refuses to give it back: so
  tst_shortcuts.qml, whose keys go to a window of their own, sends them
  through `press`, which shows that window again first (`keepKeys`). On
  Windows, a window is `active` as soon as it opens (as the TestCase's,
  which it's transient for, still is), a moment before the system gives
  it the keys, so `keepKeys` also waits for the TestCase's window to lose
  its active focus (`hasKeys`): the first key went there.
- The web version (docs/platform.md, Web) needs Qt for WebAssembly of the
  host Qt's version (`uvx --from aqtinstall aqt install-qt all_os wasm
  6.11.2 wasm_singlethread -O <dir>`), the Emscripten that Qt names
  (`QT_EMCC_RECOMMENDED_VERSION` in its
  `lib/cmake/Qt6/QtPublicWasmToolchainHelpers.cmake`: 4.0.7 for 6.11.2;
  emsdk's `./emsdk install 4.0.7 && ./emsdk activate 4.0.7`) and `rustup
  target add wasm32-unknown-emscripten`. `QT_WASM=<dir>/6.11.2/wasm_singlethread
  EMSDK=<emsdk> scripts/build-web.sh` builds it (minutes; again, about
  one), `node scripts/web-smoke.mjs` checks it in headless Chrome
  (`--shots <dir>` saves screenshots, `VERBOSE=1` prints the console),
  and `python3 -m http.server -d target/web` serves it to try. The page
  has the Emscripten instance as `koil` (`koil.FS` is Koil's disk).
  `brew upgrade qt` needs the wasm Qt of the new version.
- `qmllint -I target/cxxqt/qml_modules qml/*.qml` should print nothing.
  cxx-qt-build writes `.qmlls.ini` (ignored by git) for qmlls.
- Windows' Qt (6.10, see CI) can be tried on macOS, for a bug only
  Windows has: `uvx --from aqtinstall aqt install-qt mac desktop 6.10.3
  clang_64 -O <dir>`, then `cargo build` with its `bin` first on `PATH`,
  `CXXFLAGS="-include arm_acle.h"` (its `qyieldcpu.h` fails with newer
  Apple clang otherwise) and a `CARGO_TARGET_DIR` of its own.
  `QML_DISABLE_DISK_CACHE=1` runs the QML without what qmlcachegen
  compiled, which tells a bug of the compiled code apart. macOS's Qt
  compiles no regexes to machine code, so a bug of Windows' compiled
  ones (see Regular expressions) shows on x86-64 Linux: in Docker
  (`--platform linux/amd64`), Qt from aqtinstall (`linux desktop 6.10.3
  linux_gcc_64`), the QML tests offscreen; with
  `QV4_FORCE_INTERPRETER=1` it compiles none either, which tells such a
  bug apart.
- Checking the real app: `osascript` / System Events can send keys, click
  menus (process `koil`, or `Koil` from the bundle) and read the status
  line and the editor's text (`value of every UI element of window 1`).
  Keys sent right after launch can arrive out of order (an Enter before the
  `:`), so wait a moment first.
  Screen capture isn't permitted; to see the UI, temporarily add a `Timer`
  that saves `root.Overlay.overlay.parent.grabToImage(...)` to a file, and
  remove it after (saving to one file at every tick lets you read it half
  written: number the files and read the one before the newest). The window
  opens over the user's work, so keep such sessions short. System Events'
  `click at` doesn't reach Qt as a mouse press; post a `CGEvent` (a few
  lines of Swift) to click. A menu shortcut sent this way runs after the keys that
  follow it, and Cmd+= doesn't reach Zoom In at all (neither in vim-edit).
  A Koil launched from here may not come to the front while the user
  works in another app (macOS won't let it); then a temporary `Timer`
  that logs the state with `console.log` and calls main.qml's functions
  (`leaveFile`, `openScratch`) checks it without keys.

## Rules

- Colors come from `theme`, never a palette; text uses `theme.font`, other
  sizes scale by `theme.zoom`, in pixels; use `Panel`, `Tip`, `IconButton`
  (docs/ui.md).
- Nothing drawn in Editor.qml may depend on `editor.text`: use a `Layer`,
  and read all the text as `latest.text` (docs/editor.md).
- Cursor steps go through `Txt.charStart`/`charEnd`, never ±1, and
  `vim.hidden` is replaced, never changed in place (docs/vim.md).
- A new `:` command goes in `exCommands`, a new Space key gets a command
  with it, and a new key name goes in `Vim.keysIn` and `:h keynames`.
- A menu item goes in both `MacMenuBar.qml` and `WindowMenuBar.qml`.
- A delegate other files use is a file of its own.
- A question is `confirmDialog.ask`, its Yes and No named by what they do;
  a list to pick from is a `PickList` (docs/questions.md).
- A "see" in help.js names a `:h` topic; the tests check it.
- A regex the user writes is `Txt.regExp` or `Txt.searchRegExp` with the
  `regexEngine` (PCRE2's), never `new RegExp`, which has no look behind
  (docs/vim-commands.md, Regular expressions).
- Paths shown to the user have `/`, also on Windows
  (`koil_core::with_slashes`).
- **QML's JavaScript**: don't make a binding depend on something by reading it
  as a bare statement (`editor.revision;`): the app's QML is compiled ahead of
  time, which can drop it, though `qmltestrunner` keeps it. Use the value. The
  engine has no `Array.prototype.flatMap` nor `String.prototype.trimEnd`;
  `?.` and `??` work. Qt 6.10 (Windows') takes the words ES3 reserved
  as keywords, so they can't be names (`long`, `int`, `char`, `byte`,
  `float`, `double`, `boolean`, `enum`, `goto`, `native`, `final`,
  `public`, `private`…): a `const long` kept all of tst_vim.qml from
  compiling there, though 6.11 has it. A `Set` takes time in proportion to its size for
  each add and lookup (40,000 adds took 2 s, 340,000 lookups 31 s), so
  use a sorted array or an object of keys. A `var`
  property bound to objects of constants (`dark ? { create: "#73c991" } :
  { … }`) came out undefined in the compiled app, though qmltestrunner had
  it (`patternColors`, with a `String(text)` in it, works), so
  `theme.changeColor` is a function. Compiled, a `var` property's `({})`
  is a `QVariantMap`, not a JS object, and in Qt 6.10 (Windows' CI)
  taking a key after one was `delete`d crashed (the help's `textItems`,
  so `:!`'s output closed Koil), so one whose keys go is a `Map`.

## CI and releases

- `.github/workflows/build.yml` builds a `.dmg` (macos-latest, arm64 only) and
  a setup `.exe` (windows-latest) on every push, and the web version
  (ubuntu-latest, its `web` job: Qt for WebAssembly and Linux's desktop Qt
  from aqt, the Emscripten that Qt names, `build-web.sh`, then
  `web-smoke.mjs`), whose `pages` job publishes it to GitHub Pages for a
  `v*` tag (the repo's Pages source must be GitHub Actions, and its
  `github-pages` environment must allow `v*` tags). The web job's Qt is
  pinned in its `QT_VERSION`, and cached with Emscripten by it. Its `test` job runs
  `cargo test` and the QML tests, with windows, on both, through
  `scripts/qml-tests.sh`: some tests fail now and then for timing alone,
  so it runs a failed test again, alone, up to twice, and fails only if
  the test fails every time (a test that passed when run again is a
  warning on the run's page: make it wait for what it needs). `v*` tags
  also publish a GitHub release, once the tests pass.
- The Qt version is pinned per OS. macOS uses 6.11, because 6.8's headers fail
  with newer Apple clang. Windows uses 6.10, because Qt 6.11 for Windows uses a
  repository layout that aqtinstall 3.3 can't read. Move Windows up once
  aqtinstall supports it. Then keep `keepPopupClicks` (docs/platform.md,
  Windows), though 6.11 has Qt's fix: it still passes a click on a
  popup's padding to the window under it. Reword the filter's comments
  and that note to say so. Keep `Txt.interpretedRegExp` too: 6.11
  compiles regexes as 6.10 did (see Regular expressions).
- Keep actions on Node 24 releases (checkout v7, upload-artifact v7,
  download-artifact v8, action-gh-release v3, cache v6, setup-node v7,
  upload-pages-artifact v5, deploy-pages v5).
- Releases: `cargo release <level> --execute`. `Cargo.toml` makes it skip
  crates.io (`publish = false`) and run only on `main`, and it needs a clean
  working tree.
