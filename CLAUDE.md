# CLAUDE.md

Koil desktop app: a vim-style editor in Rust + Qt 6 via cxx-qt 0.10, with the
UI in QML, that edits a directory as text (like oil.nvim) through koil-core
(`../koil-core`, a library; `../koil-cli` is its CLI; read their CLAUDE.md for
how Koil works). The editor is the one from `~/projects/vim-edit`, cleaned up.
It shows Koil's listing (see Koil), a file opened with File > Open, or
the scratchpad (see Scratchpad).

## Layout

- `src/main.rs`: reads the command line (cli.rs), creates the app,
  installs the "Settings…" translator, the Nerd Font and the window icon,
  sets the Windows style, loads `qml/main.qml`.
- `src/cli.rs`: the command line, with clap's builder and `arg!`
  (`command`, `parse`), the scratchpad's text from stdin (`read_stdin`),
  and `ARGS`, which `Document` gives QML (see Command line).
- `src/install.rs`: the `koil` command on macOS, which the Settings window
  installs and removes (see The koil command). Its tests use a temp dir.
- `src/listing.rs`: the listing as text, without Qt: `render`, `parse`
  (and `read`, through koil-core's `read_shown`), `check`, `update` (read
  it into koil, then navigate), a path as QML takes it (`unicode`), the confirmations'
  lines (`actions`, `history`), the path field's regex parts
  (`path_syntax`), what Tab completes in it (`complete`), the file `:e`
  opens (`file_at`), what's shown after
  each line when sorted by size or a date (`notes`), what changed on
  disk as edits to the text and questions (`sync`, `resolve`, `merge`),
  and the entries a shell command runs on (`paths_on_lines`), or what
  `<cfile>` stands for on a file's lines (`links_on_lines`). Its tests
  (`src/listing/tests.rs`) use a temp dir.
- `src/history.rs`: `History`, the undo history kept in a file across
  sessions (see Undo history). Its tests (`src/history/tests.rs`) use a
  temp dir.
- `src/shell.rs`: shell commands (see Shell commands): the shell's kind
  (`Kind`), `%` in a command (`expand`), running one (`start`, then
  `Started::finish` on a thread) and stopping it (`Running::stop`), the
  environment it runs in (`environment`), its output as shown
  (`as_shown`), and the shells installed (`shells`). Its
  tests (`src/shell/tests.rs`) run sh on Unix.
- `src/sizes.rs`: `Sizes`, which counts the sizes of dirs on its own
  threads and keeps them (see Kept sizes). Its tests
  (`src/sizes/tests.rs`) use a temp dir.
- `src/syntax.rs`: a file's colors, found without knowing its language
  (`spans`, see Syntax), which native.cpp's `TextColors` asks for a line
  at a time through ffi.rs, and the URL or path at a place (`link_at`). Its
  tests (`src/syntax/tests.rs`) take lines.
- `src/link.rs`: what gf, gx and Cmd+click open (see Links): the link at a
  place in a line (`link_at`), or a line's first (`first_link`, for
  `<cfile>`), and what its text stands for (`target`). Its tests
  (`src/link/tests.rs`) use a temp dir.
- `src/convert.rs`: what the QML elements share: JSON in and out of
  QML's strings (`to_json`, `from_json`), paths (`path_string`, `paths`),
  and a signal a watcher's thread emits once a burst (`Coalesced`).
- `src/koil.rs`: `Koil` (QML element): wraps `koil_core::Koil` and calls
  listing.rs, taking and giving JSON. `showHidden`, `gitignore`, `regex`,
  `sort` and `sortReverse` are properties, bound to vim's `:set` options.
  It also watches the disk (`watch`, `changedOnDisk`; see Changes on disk),
  and counts dirs' sizes (`sizes`, `dirSizes`; see Sorting).
- `src/document.rs`: `Document` (QML element): reading and writing files,
  watching the one shown (`watchFile`, see Files changed on disk), the
  scratchpad's file (`writeScratchpad`, see Shell commands), the command
  line, and installing the `koil` command (on a thread).
- `src/system.rs`: `System` (QML element): the system clipboard, the
  installed monospaced fonts and the Nerd Font's family, the editor's
  text, line format and colors, showing a path in Finder or Explorer
  (`reveal`) or opening it in its default app (`openInApp`), links
  (`linkAt`, `linkTarget`), and running shell commands (`runShell`,
  `stopShell`, `shellDone`). Its methods that only hand a QML item to
  native.cpp are made by `forward!`.
- `src/ffi.rs` + `cpp/native.{h,cpp}`: the C++ helpers behind `System` and
  `main.rs` (menu title translator, Controls style, clipboard, fonts, the
  Nerd Font, the window icon, files macOS asks to open, line format,
  `setText`, the listing's and path field's `QSyntaxHighlighter`, a
  file's colors (`TextColors`: `setTextColors`, with syntax.rs), and the
  confirmations' (`setKeywordColors`), `redrawText`, the long lines Qt
  doesn't lay out (`LongLines`, see Long lines), and what changed in a
  text (`TextChanges`, see Long texts)).
- `cpp/finder_mac.mm`: the "Open in Koil" service on macOS (see Open in
  Koil), Objective-C++, which `build.rs` adds only there.
- `qml/main.qml`: the window: settings, menus (`MacMenuBar.qml`, and
  `WindowMenuBar.qml` elsewhere, which run its functions), dialogs, the
  status line (`StatusLine.qml`), the path field and its option buttons, and Koil's listing (`showListing`,
  `updateListing`, `applyChanges`, `undoApply`), a file (`loadFile`) or
  the scratchpad (`openScratch`), and which of the two editors vim edits (`activate`). It wires the pieces
  together; no editing logic lives here.
- `qml/Editor.qml`: the `TextArea` in a `ScrollView`, and everything drawn
  with it: cursors, selection, the marked lines (see Marked lines), the
  find bar's scope and what was just yanked (each a `SpanShade`), search
  highlights, the
  bracket matching the cursor's (`brackets`), the notes after lines (`infos`, see Sorting),
  warnings and errors, line numbers, the link under the pointer with Cmd
  held (`link`, see Links), the long lines Qt doesn't draw (`longText`,
  see Long lines), the `HoverBox` and the
  `CompletionList`, each in a part a row while lines wrap (`rowSpans`, see
  Wrapping). Both the listing (or
  file) and the path field are one (`pathField`).
- `qml/CodeLabel.qml`: text with `code` in backquotes, each in the
  editor's font on a shade, as the help shows them, for `Tip` and the
  Settings window's notes (see Theme).
- `qml/HoverBox.qml`: the VS Code-style box that shows what an icon hides (an
  ID, as its path), or a warning's or error's message.
- `qml/CompletionList.qml`: the dirs Tab can complete the path field to, in
  a box under it, like VS Code's suggestions (see Completion).
- `qml/SortMenu.qml`: what `gs` and a key sort the listing by, in a box
  under the sort button (see Sorting).
- `qml/Vim.qml`: the vim emulation (modes, motions, operators, registers,
  undo, macros, visual block, multiple cursors, marked lines, hidden text,
  the listing's prefixes, `:` and its ranges, `/`, `:s`, surround,
  buffers). It drives the `TextArea` through `insert`/`remove`/`select`.
- `qml/text.js`: pure text helpers (lines, characters, words, text objects
  and the tags `it` and `at` find, `tagPair`, `=`'s indents, `reindent`,
  `:s`'s arguments and replacement, `code` in the help and tips), imported
  as `Txt` by Vim.qml and the views. The only state it keeps is
  where the lines of the last two long texts start (`lineIndex`), so
  `lineOf`, `lineToPos` and `countLines` (the status line, line numbers,
  highlights) don't go through the text each time.
- `qml/FindBar.qml`: the find and replace bar (Cmd+F, Cmd+Option+F).
- `qml/HelpPanel.qml`: `:help` (`:h topic`, `:h key`), a box listing what
  isn't obvious (`qml/help.js`'s `sections`); `:reg` shows the registers
  in it (`showList`), and `:!` what a command wrote (`showText`). `/` and
  `?` search it (see Help).
- `qml/ConfirmDialog.qml`: the [Y]es/(N)o/(C)ancel box, with a list under
  the question: `:confirm q`, applying and undoing (lists to pick from),
  and what changed on disk against the user's edits.
- `qml/SettingsWindow.qml`: the Settings window (Cmd+,), which scrolls,
  and shows what a setting does with the pointer on it (see Settings).
- `qml/ShortcutsWindow.qml`: the user's shortcuts, listed and edited (see
  Shortcuts).
- `qml/Theme.qml`, `Panel.qml`, `Tip.qml`, `Icon.qml`, `IconButton.qml`,
  `KeyCap.qml`: the look the app's own controls share (see Theme);
  `ModalBox.qml` (:help's and the questions' box), `WheelFlickable.qml`
  (see Scrolling boxes) and `SelectableText.qml`, the boxes'; and
  `TextButton.qml`, `Segmented.qml` and `DropList.qml`, the buttons and
  lists the Settings and Shortcuts windows share.
- `tests/tst_vim.qml`: qmltestrunner tests for Vim.qml, the find bar and the
  help's search; `tests/tst_shortcuts.qml`, the Shortcuts window with the
  keys alone.
- `scripts/`: `bundle-macos.sh` (makes the `.app`), `package-macos.sh` (the
  `.dmg`), `package-windows.ps1` (windeployqt, then the Inno Setup
  installer), `make-icons.sh` (the icons, from `packaging/icon.png`).
- `packaging/`: `icon.png` (the app's icon, as macOS draws it) and the
  icons made from it (committed, so building needs no ImageMagick):
  `macos/Koil.icns`, `windows/koil.ico` (in the exe through `koil.rc`,
  which `build.rs` compiles with `embed-resource`) and `window-icon.png`
  (see App icon); `macos/Info.plist` (with a `@VERSION@` placeholder) and
  `windows/installer.iss`.
- `fonts/`: the Nerd Font Koil ships (see Icon font) and its license.

## Build and test

- Local Qt comes from Homebrew (`qtbase`, `qtdeclarative`); `qmake` must be on
  `PATH`. `cargo build`, `cargo run` (lists the home dir, or the
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
- `qmltestrunner -input tests` runs the tests. They load `qml/` by path, so
  anything they instantiate must not `import Koil` (only `main.qml` does, for
  `Document` and `System`; `Editor` takes `System` as a `var`). A test's
  keys go to the window that has them, and while another app is in front
  (where the tests were started from), macOS takes qmltestrunner's
  activation away about half a second in and refuses to give it back: so
  tst_shortcuts.qml, whose keys go to a window of their own, sends them
  through `press`, which shows that window again first (`keepKeys`).
- `qmllint -I target/cxxqt/qml_modules qml/*.qml` should print nothing.
  cxx-qt-build writes `.qmlls.ini` (ignored by git) for qmlls.
- Windows' Qt (6.10, see CI) can be tried on macOS, for a bug only
  Windows has: `uvx --from aqtinstall aqt install-qt mac desktop 6.10.3
  clang_64 -O <dir>`, then `cargo build` with its `bin` first on `PATH`,
  `CXXFLAGS="-include arm_acle.h"` (its `qyieldcpu.h` fails with newer
  Apple clang otherwise) and a `CARGO_TARGET_DIR` of its own.
  `QML_DISABLE_DISK_CACHE=1` runs the QML without what qmlcachegen
  compiled, which tells a bug of the compiled code apart.
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

## Koil

- **The listing** (listing.rs): per entry its devicons icon, two spaces and
  its name (`/` after a dir's), one per line. The location (`~` for the home
  dir) is apart, in the path field over it (`Rendered.path`), which `update`
  takes as `path`. Users write only `/`, also on Windows: koil opens a
  plain path with `\` (a pasted one), but in a pattern `\` is an escape, and
  a pattern's base dir ends only at a `/`. So every path Koil shows has `/`
  (`koil_core::with_slashes`: `show_path`, the confirmations, the hover;
  koil gives names and the paths in its messages with `/` itself, and only
  those, so a pattern an error quotes keeps its `\`), and once a pasted
  `C:\src` opens, the field shows `C:/src`, after which a pattern can be
  typed. `show_location` is `Koil::location` (the dir, a `/` and the pattern
  as it is) with `~` written only at the start, as text (`with_tilde`), so a
  pattern's `\` is never touched. koil-core reads a `~` back
  (`Koil::read_location`). The icon hides the entry's ID
  (`Id.0`, as text) as vim's hidden text, so it yanks, pastes and undoes
  with its line. `parse` reads a
  line as an existing entry if its first character is an icon with a hidden
  entry, else as a new one; a Private Use Area character first (the icon
  `render` gives a new entry) is dropped, and names are trimmed. An icon
  hiding something that isn't a number is an error, and so is an empty path;
  both block an update like koil's own. devicons' default file icon is `*`
  (a glob character), so `FILE_ICON` replaces it. The hover shows an ID as
  the path it stands for, relative to the open dir like the confirmations
  (`listing::id_path`, given to the editor as `describeHidden`), even on a
  line that renames it, so it says whose ID it is; hidden text that isn't
  an ID koil knows shows as it is.
- **Prefixes** (Prefixes in Vim.qml, `linePrefixes`, on while vim edits the
  listing): a line's icon and the two spaces after it (or three spaces, on
  a new line) are its prefix, which the cursor never goes into, as if the
  name started the line. `setCursor`, vim's `clampNormal` and `motion()`
  move a position out of one (word motions step over it like blanks,
  `wordStep`; an `f`/`t` target in one isn't found), and `syncFromEditor`
  does for clicks and the editor's own arrow keys (not while typing:
  `cursorPositionChanged` comes before `text` has the typed character, so
  it checks `length`). Lines get one where they start: `o`, `O` and Enter
  (`lineBreak`), typing on an empty line (`prefixEmptyLine`), and pasted
  lines that have none (`prefixLines`), so in normal mode the cursor on
  an empty line (an empty dir's listing) is drawn where its name would
  start (`spotAt`), not under the icons; `J`, `gJ` and Delete at a line's
  end drop the next line's with the line break. In insert mode vim types
  Enter and the keys that would delete into a prefix (`prefixKey`, like
  Alt+Backspace at a name's start), as `typedEdit` says: Backspace at a
  name's start clears the icon (the ID goes, so the entry is new), then
  joins the line to the one above (`X` and `dh` there only clear the icon,
  as vim's don't join lines, and leave the registers alone); Enter there
  puts the new line above, so the name keeps its ID. Whole lines (`dd`, `yy`, `V`) keep their
  prefixes, `cc` keeps its line's (a rename), `>>` indents after it, and
  text that starts with an icon and two spaces pastes as lines
  (`pastesLines`; above the cursor's line in insert mode). Search and the
  find bar go through the text without its prefixes (`withoutPrefixes`,
  kept while the text and hidden text stay), so a line starts at its name
  (`^a`), and a match on to the next line covers its prefix (one ending
  with the line break doesn't); a replacement's new lines get one
  (`prefixLines`). The status line's columns
  (and `|`) count from its end. A line without one (that doesn't start
  with an icon or a space, then two spaces) is plain.
- **Problems**: `Koil::check` runs 200 ms after the last edit
  (`checkTimer`), and gives `{ line, column, severity, message }`; Editor.qml
  draws each from `column` (where the name starts) to the line's end.
  Everything else (squiggles, the message after the line, the hover, `gh`)
  works as before. A failed update gives the path's problems apart
  (`pathProblems`: none, or it can't be opened), which the path field shows
  until the path is edited or an update works. koil's `open` fails on a
  path that isn't there or is a file (`OpenError::NotFound`,
  `NotADirectory`, naming its first part that isn't a dir, which
  `listing::describe_open` shows with `~`), rather than opening its closest
  parent, so it can be fixed. A path on the command line (or the Start in
  setting, see Settings) that can't be opened lists the home dir, with it
  in the path field and its problem
  (`Document.startupPath` makes it absolute from the dir Koil started in,
  since the field is read relative to the open dir, by writing it after that
  dir and a `/`: `std::path::absolute` would make a pattern's `/` a `\`, and
  `join` would put a `\` before it).
- **The path field** (`pathView` in main.qml, over the listing): an Editor
  with `pathField` set, one line in a field, with the option buttons (the
  find bar's `IconButton`s) on its right. It's hidden while a file is open.
  One `Vim` edits both it and the listing, one at a time (see Buffers under
  Non-obvious decisions): `activeView` is the one it edits, which vim's
  `editor`, `flickable`, `singleLine` and the find bar's `editor` follow.
  Everything that changes the listing (`showListing`) switches vim to it,
  and back to the path field after if it was there, so a setting toggled in
  the field (`g.`, a button) leaves vim in it (insert mode ends, though).
  When the location changes, the field gets a new buffer, with the cursor
  at the end; otherwise it keeps its text and undo history. koil reads it
  as a terminal would (see Patterns in koil-core's CLAUDE.md): a path can
  be quoted (`"my dir"`, `'my dir'`) or escaped (`my\ dir`, not on Windows),
  like one pasted from a terminal, and a quoted character is never special
  in a pattern. A name with quotes in it (`it's`) still opens as it's
  shown. After the update the field shows the location as Koil does, with
  no quotes (`showPath`). koil-core also reads a `~` at the start as the
  home dir, also right after a quote (`"~/x"`, unlike a shell).
- **Path history** (`pathHistory` in main.qml, `vim.lineHistory`): every
  location the listing shows goes last in the history (`onLocationChanged`,
  so from the field, Enter, `-`, Open Folder, or the open dir renamed on
  disk), once, keeping the newest 100, until Koil quits (it isn't saved).
  It's the location as shown, so not relative to the dir a path was
  typed in. In the field, `k` and `j` (Up and Down, also in insert mode)
  put the one before or after in (`browseLines`), skipping ones that are
  what the field had before browsing (usually the location), and after
  the newest, that again, as the command line's history does. Each is a
  change undo takes back, and a field edited since starts over
  (`lineBrowse.shown`).
- **Completion** (Completion in Vim.qml, `listing::complete`, koil-core's
  `Koil::complete`): Tab while typing in the path field (`vim.completer`,
  set only there) completes the dir being written, like a shell. koil-core
  reads the path up to the cursor and gives the dirs its last part (after
  its last `/`) can be the start of, or if none, those that have its
  characters in order, as zsh's fuzzy matcher (Zim's `r:|?=**`: `myt`
  gives `my_tools`), in the dir before it, read as `open` reads it: not
  hidden ones unless the part starts with `.` or `:set hidden` is on, not
  ignored ones with `gitignore`, new dirs in the diff too, `..` for `.`, and
  ignoring case unless the part has an uppercase letter (smart case, as
  search does: `k` gives `Koil` too). Tab fills in the only one
  (with its `/`, which steps over a `/` right after the cursor), or else the
  longest start they share, if that's longer than the part and has its
  characters in order (`fill`, `has_in_order`: `myt` fills in `my_t` of
  `my_tests` and `my_tools`, but `ts` nothing, which would lose its `s`).
  Otherwise vim shows them (`vim.completion`, drawn by `CompletionList` in
  the window's overlay, a row per dir as its listing line, the names under
  the part): Tab and Shift+Tab (`<S-Tab>`, which does nothing elsewhere;
  also Down and Up, Ctrl-N and Ctrl-P) pick the next or previous one, Enter
  takes it (so Enter opens the path only once they're closed), Esc closes
  them but stays in insert mode, typing and
  Backspace narrow them (vim types those itself, so the options follow at
  once; a `/` shows that dir's), and other keys close them and then do what
  they do (but a key with no token, like the Ctrl before N, leaves them).
  Moving the cursor or the mode closes them (`onCursorChanged`, which the
  completion's own edits get past by setting them after). Names are written
  as they are, since koil opens a location that's a dir as written before
  reading its quotes. A completion goes into the insert as Backspaces and
  its text, so `.` and counts repeat it.
- **Keys** (`commandKeys` in Vim.qml, only while a listing is shown, in the
  listing and the path field): `Space Space` applies (`Space a` too, but
  always asking first, whatever the setting: see Apply), `Space u` lists
  the applies to undo (see Undo history), `Space r` shows the entry on
  the cursor's line in Finder or Explorer, selected (`reveal`: where its
  ID is on disk, as Enter opens it; from the path field, the open dir; a
  new entry isn't on disk yet, so the status line says so, as
  `Koil.pathOnLine` gives `{ path, message }`; `System.reveal`
  runs `open -R`, or `explorer /select,`, or on Linux opens the dir it's
  in), `Space o` opens the same path (`entryPath`) as a double-click in
  Finder or Explorer does, a file in its default app (`System.openInApp`:
  `open`, `explorer` or `xdg-open`, waited for on a thread, as `open`
  waits while an app launches; on macOS `openFailed` then says why it
  failed, like "No app opens", which Finder would ask about, while
  Explorer asks itself), `-` opens `..`
  (`3-`: `../../..`), where a pattern is a level of its own (`Koil.up`,
  `listing::up`): `dir/*` goes to `dir`, on the dir or file there that
  the cursor's entry is in (`src/` of `src/main.rs`), then to the dir
  it's in, `_` the scratchpad (see Scratchpad), `!` a shell
  command on the entry (see Shell commands), Tab goes to
  the other editor (`activate`), `g.`,
  `gi` and `gr` toggle `:set hidden`, `gitignore` and `regex` (like the
  buttons), and `gs` and a key sort it (see Sorting). Cmd+S (File > Save,
  named Update in the listing) and `:w` update: only `Space Space` and
  `Space a` apply (`save`), as a `:w` typed out of habit mustn't change
  files.
  Enter in the listing opens the dir or file on its line
  (`listing::target_on_line`: a dir if the name ends with `/`, else the file
  its ID points to on disk, even if the line renames it; a new file is
  created first, see Files); on a line without an entry it's vim's Enter.
  Enter in the
  path field (`openPath`, also from insert mode: see `singleLine`) updates
  and goes to the listing, unless the update fails; Shift+Enter there only
  updates, so vim stays in the field. In a file, `Space Space` saves (as
  `:w`: `save`), `!` is Koil's too, and with a path, so are `-`
  (`leaveFile`): back to the listing, on the file's line, a level up, so
  `3-` goes two up from there (`goUp`), `_`: the scratchpad over the
  file, and `Space r` and `Space o`, which take the file, as `%` does
  (`entryPath`; in the scratchpad, they say it isn't on disk). `Space q` lists the user's shortcuts
  (see Shortcuts) everywhere, in visual mode too (`visualCommandKeys`), so
  the list can run one on the selection.
  They're only matched at the start of a normal-mode command (so `d-` and
  visual `-` are vim's), with a count; keys that start one and go on
  differently are a bad command (Space l), unless they go on as a name of
  vim's (`gg`, `gU`). Shift+Enter is its own token, `<S-CR>`, a motion like
  `<CR>`, and plain `<CR>` everywhere else (insert mode, the command line),
  but in the path field's insert mode, which hands it to normal mode.
- **Update** (`updateListing`): koil reads the entries with the settings they
  were shown with, then takes vim's `:set hidden/gitignore/regex`, then opens
  the Enter/`-` target, else the path field's path if it changed (like
  koil-cli, where it's the first line), or if the pattern open was read
  as a glob and `:set regex` is on, or the other way round
  (`listing::rereads`): koil-core keeps a pattern as it was read when only
  the settings change, so `gr` left a regex written as a glob a glob,
  matching nothing, and Enter didn't open it again, as it hadn't changed
  (`takeSettings` reads it again too). `:set` while a file is open
  reaches koil only once a listing is shown: `Koil.open` (back to a file's
  dir, a folder opened) opens with the settings (koil-core's `open_with`,
  so what was open isn't read again for them first), and `showListing`
  of a new listing (`moved`, which no text of the one before is read
  into: `-` back to it) has koil take them (`Koil.takeSettings`), else it
  came back unsorted and without hidden entries, as vim said otherwise.
  The field is read with the listing
  wherever the update comes from, so a path typed there and left without
  Enter is opened by the next update. koil-core does all of it as one step
  (`Koil::update_and_open`), so if opening fails, koil stays as it was, since
  the listing isn't shown again: koil keeping the new settings would read the
  shown listing as missing what they show (`g.` with a bad path, then fixing
  it, deleted every hidden entry).
  The listing is then shown again. If what's shown stayed the same (same
  dir and pattern, same hidden/gitignore: koil's `Updated::moved` is
  false), the new text replaces
  the old as one vim change (`vim.replaceText`, which changes only the span
  that differs), so `u` can take it back: Koil reads the buffer as a whole
  each time, so undoing to an earlier listing of the same view is safe.
  Otherwise vim starts over (`vim.reset`): undo must never bring back
  another view's entries, which Koil would read as this one's (missing
  hidden entries would be deleted, other dirs' IDs moved here). `from` puts
  the cursor on the dir `-` came from. Whenever the same location is shown
  again (the same listing, or other entries of it: `:set hidden`,
  `gitignore`, a sort), the cursor stays on the same line (`listingSpot`),
  even if the update moved its entry (a rename or a new entry goes where
  it sorts), at the same column and the same place in the view.
- **Apply and undo**: `Space Space`, `Space a`, File > Apply Changes… update,
  then `ConfirmDialog` lists `listing::actions` (paths relative to
  the open dir; `Koil::changes`, so a swap is its two renames, not the
  three steps through a temp name), each with a checked box before it
  (a Nerd Font icon, `boxes`, with two spaces after it), all picked.
  The user leaves some out (j and k move the current line, Space or x or a
  click on the box toggles it, a picks all or none; the current line is
  highlighted only once one of those is used, and the first j or k only
  shows it, on the first line), and a line goes with
  what it needs (`needs`: a swap's other half, the new dir a file goes
  in): picking one picks those, leaving one out leaves out what needs it.
  The boxes are text in the one `TextEdit`, so the list still selects and
  copies as it is. The question counts what's picked, and stays over the
  list as it scrolls. The word a line starts with (after its box) is
  colored by the change it stands for (`root.changeKeywords`, passed to
  `ask` by the apply, undo and create questions only, as a conflict's
  lines are paths; `theme.changeColor`): CREATE and RESTORE green, DELETE
  and TRASH red, MOVE yellow, COPY blue, by a `QSyntaxHighlighter`
  (`setKeywordColors`), so the text stays plain. Yes applies the
  picked lines (`Koil.apply(picked)`, indexes into the `shown` actions
  `actions()` kept, given to `Koil::apply_only`, so only what the user saw
  is applied) and forgets the rest; with none picked, it discards them all
  ("Discard these 3 changes?", "3 changes discarded"). Then vim starts
  over (koil refreshed: new IDs for renamed paths), with the cursor where it was (`listingSpot`: the
  same line; the listing's cursor even while vim is in the path field) and
  the view as it was; so does undoing an apply. The "Ask before applying" setting
  (`confirmChanges`: always, when deleting, never; `asksFirst`) can skip
  the confirmation (but not `Space a`'s or File > Apply Changes…'s: `ask`),
  applying every line (`deletes` says which delete), and Enter's create's
  too. `:confirm q` and `ZZ` always ask, and their question is whether to
  quit without the changes.
- **Undo history** (`undoApply`, koil-core's `Koil::undoable` and
  `Koil::undo_only`): `Space u` (from the listing or the path field)
  updates (vim's undo may have taken the buffer back past an update) and
  lists the applies (and Enter's creates) koil can undo, newest first, in
  `ConfirmDialog` (`listing::history`: each one's time, its dir if it
  isn't the open one, and what undoing it does, up to `SHOWN_STEPS`
  steps, relative to its dir); koil refuses while changes are pending.
  None is picked at first, and the first is highlighted at once
  (`ask`'s `showRow`). `u` or Cmd+Z with nothing left
  to undo in vim emits `nothingToUndo`, and `undoLast` asks only about
  the last apply alone: "Undo the last apply?"
  over every step undoing it does, relative to the open dir
  (`HistoryLine::steps`), or says why it can't be undone. Not from the
  path field, whose undo history is its own. An apply needs the newer
  ones that changed a path it changed, or one in it or that it's in
  (koil-core's `Undoable::needs`), which picking it picks. One that can't
  be undone now (koil-core checks every step against the disk, with what
  it needs: something gone, or taken, or emptied from the trash) says
  why and has a crossed out box (`blocked`, the reason). Yes undoes the picked
  ones, newest first (`Koil.undo(picked)`, indexes into the
  `shown_history` that `history()` kept), and is off while one that
  can't be undone is picked (`blockedPicked`); a step koil can see won't run
  undoes nothing. Delete from History (`d`; `ask`'s `extra`, a button
  on the left, apart from the choices, so Enter never answers it, and
  off while none is picked) asks again, then forgets the picked ones
  (`Koil.forgetHistory`, `History::forget`, by their time, also for
  other Koils), so they can't be undone: it's what one that can't be
  undone is picked for (a filled crossed out box; `a` picks only the
  others). An older apply that needed one deleted is then checked
  against the disk without it. Undoing always asks (a `u` too many mustn't change files
  unasked). The history lasts across sessions (`History` in history.rs):
  it's in `history.json` in Koil's data dir (`~/Library/Application
  Support/Koil` on macOS, `%APPDATA%\Koil` on Windows), the newest
  `KEPT` (100), and every Koil running shares it: `History::merge`
  reads the file and merges both ways after anything that changes
  koil's (an apply, a create, an undo, and a sync whose steps followed a
  rename, `merge_changed`), and before the history is shown or undone.
  Applies are told apart by their time, and what both had at the last
  merge (`last`) tells one the other Koil added from one this one undid.
  A file that can't be read (half written) is as it was at the last
  merge, not empty, which would make every apply one the other undid, and
  each Koil writes it through a temp file of its own
  (`history.json.<pid>.new`).
- **Sorting** (koil-core's `Settings::sort`; read its CLAUDE.md): `gs`
  shows the sort menu (`SortMenu`, under the sort button beside the
  options, visible while vim's `pendingKeys` end in `gs`), and a key picks
  one: `gsn` name, `gsv` natural (`a2` before `a10`), `gse` extension,
  `gss` size (biggest first; a dir's is counted, see below), `gsd` size
  on disk (koil-core's `SortBy::Disk`; a dir's counted too), `gsm`
  modified, `gsc` created, `gsa` accessed (newest first), shifted the
  other way round (`gsS`). They're `commandKeys` of three keys
  (`root.sorts`, `sortKeys`: `"gss": "sort:size"`), so a key it doesn't
  know after `gs` is a bad command, and macros and counts work as for the
  others. The button and a click in the menu go through vim too
  (`vim.startCommand`: out of insert or visual mode first, then the keys:
  `gs`, or `gs` and the clicked key; none hides the menu). They set
  `:set sort` and `sortreverse` (`vim.sort`, `vim.sortReverse`, which
  `Koil` binds; `settingChanged` updates, and an update with only the sort
  changed isn't `moved`, so it's one change undo can take back, with the
  cursor and the view where they were). In a run (a macro's `gss`, `-c`'s
  `set sort=size`), vim waits for the update (`waiting`), which is a step
  of the run (`updateInRun`, through `endWait`'s `done`), so the keys
  after it have the listing sorted: updated once the event loop ran, as
  it is otherwise, it landed between the run's chunks (`-c` after `set
  wrap`'s layout) and stopped the run. Back from a file, sorted another
  way meanwhile, the view stays too (`shownSort`: every line moved, so
  following the file's would scroll the rest away), scrolling only to
  show the cursor. Sorted by size or a date, each line
  shows it, dimmed, after its end (`listing::notes`: `1.2 KB`,
  KB as 1000 bytes like macOS; `2026-10-06 14:03`, local time
  through chrono), before a warning's or an error's message (`notes` in
  Editor.qml), lined up (see Notes after lines). They come as `infos`, `{ id: text }` (`Rendered`, and
  `Synced` with what sync read), so a line's goes with its ID wherever it's
  moved or copied, and a new entry has none. Only the lines in view are
  looked up (`firstAt` in the sorted hidden text). While the listing shows
  them, the watcher doesn't skip writes to files (`DiskWatcher::writes`),
  so a file written shows its new size or time; its line stays where it is
  until the next update sorts it again. The sort isn't saved, like Koil's
  other options. Whether dirs go before files is a setting the Settings
  window saves (Folders first, `:set dirsfirst`, koil-core's
  `Sort::dirs_first`); off, they're sorted together (`1/`, `2.txt`, `3/`),
  and by a size, koil-core puts the dirs after the files, as it knows
  only how many entries each has, so here a dir counted goes among the
  files by its size (`listing::together`, `size`), and one not counted
  yet stays after them.
- **Dir sizes** (sizes.rs): sorted by size or size on disk, a dir's size
  is everything in it, counted on other threads (koil-core's `entries`,
  how many it has, is only the order until then). By size (`Measure::Size`)
  it's the files' bytes as Finder counts; on disk (`Measure::Disk`), their
  blocks (koil-core's `disk_size`, which the files' notes use too) and the
  dirs' own, as `du` counts (`du -skx` gives the same). Either way a link
  is counted itself, not followed, what's on another device isn't
  (`du -x`), and a file with hard links counts once (as `du`: Cargo
  hard-links its builds, which made `target/` a GB too big). Counting on
  disk takes as long as by size on macOS (3 s for `/System/Library`
  either way: the blocks come with the same `lstat`), but on Windows it
  opens every file, which is why the menu says it's slower there.
  `Sizes` counts by one measure at a time (asked for by another one,
  `gss` then `gsd`, its counts stop), and keeps what it counted by each
  apart, so a render never shows the other one's sizes. `render` and
  `sync` give the dirs they show sizes for (`Notes::dirs`, by the path
  their ID was read at), and `Koil` has `Sizes::want` them: those not
  known or kept start, and every other count stops (`stop`), but what's
  read of a dir isn't read again: one in a dir that's counted goes on,
  and that count waits for it once it finds it (`add`: `-` while the
  dirs listed are counted, or a pattern listing a dir and one in it),
  and a dir asked for that's counted in another goes on from there as a
  count of its own (Enter). So the dirs being counted (`State::dirs`, a
  path once) are trees, each dir read for the closest `Count` of the
  dir it's in or itself (`count_of`), and each has what's counted of it
  so far, the dirs in it too (`Dir::bytes`), which its note shows. The
  paths are the same whichever way a dir was opened (`~`, `..`): koil
  canonicalizes them, and the threads join names to them. The counts
  take turns
  (`turns`), a dir each, so they all go on at once and small ones are
  done soon, on up to 8 threads that each read a dir at a time
  (reading is mostly waiting for the disk), and stop once no dir is left
  to read and none is being read, which could find more. Counting, a dir's
  note is its size so far with `...` after it (`listing::COUNTING`), and
  its ID is in `busy`; main.qml's `sizeTimer` polls `Koil.dirSizes` every
  300 ms while any is, and Editor.qml shows `infoDots` of the three dots,
  the note's place worked out with all of them (so nothing moves as they
  come and go). The dirs counted go first, by size (`listing::listing`,
  `compare`, which `merge` uses too, through `by_size`), and the others
  after, in koil's order (with Folders first off, among the files: see
  Sorting). Once they're all counted, `sortCounted` updates (`sortedCounting`:
  it was sorted before they were), keeping the view as for `gs`; not while
  the user is halfway through something (it waits), nor if the update
  would fail on errors or open a path typed in the field (the next update
  sorts it).
- **Kept sizes** (sizes.rs): a count finds the size of every dir in the
  dir counted on its way (each done once the dirs in it are), and keeps
  them (`kept`, but those that can't be read, and small ones), so a dir
  listed again, or one in it (Enter, `-`), shows its size at once. A small dir (`SMALL`:
  no dirs in it, and under 100 entries) is counted again instead, which
  takes no time, and most dirs are: `render` asks for the dirs it shows
  (`listing::size_dirs`) before it's made, and `want` waits for those it
  starts that nothing is known of (`Count::unknown`, which the threads
  read first; `WAIT`: 40 ms at most, and only while they're done one
  after another, `QUIET`, as the others take long), so they're known as
  it's sorted. The counting is on the threads, so a disk that doesn't
  answer never keeps Koil waiting longer; those not done show `...` as
  before. Going into `~/Library/Application Scripts` (1,059 small dirs)
  waits 34 ms, others a few. `sync` waits for those it starts too (dirs
  that changed, new ones), and `count_sizes` then gives their notes as
  they are. The listing looks sizes up as it's made (`SizeOf`;
  `Sizes::known` gives each dir's as it was first asked for, so sorting
  sees the same throughout). A count adds a dir kept instead of reading
  it, unless it's stale. A file with hard links counts once in each dir
  (`Link`, `Dir::links`, merged into the dir it's in, a file in both
  taken off once), so a dir's size is the same counted on its own or in
  another, and once all its links are found, it's forgotten. A dir kept
  keeps the files whose other links are outside it (`Kept::links`), so a
  count that adds it counts them once too: Cargo links each build file
  in `deps/` and `incremental/`, which `target/debug` has both of, and
  the home dir keeps 26,000 (1 MB). A dir kept with links used to be
  read again, so `-` from a home dir counted took 1.6 s rather than
  0.15. A home dir of 146,000 dirs keeps 40,000 (5 MB; all of them
  took 22 MB), and is counted in 10 s, as fast as before sizes were kept.
  What a listing hides isn't counted, so `-` from one counted that hides
  `.cargo` and such counts those (5 s in a home dir).
- **Stale sizes** (sizes.rs): what's kept goes stale when something
  changes in it on disk. The watcher (see Changes on disk) also watches
  the dirs counted and those asked for, with everything in them
  (`Sizes::watches`; more than `SIBLINGS` in one dir, that dir, as
  notify's FSEvents goes through every dir watched for each change; on
  Windows their drives' roots, as a dir with a watched one in it can't
  be renamed or deleted there), and tells `Sizes::changed` of every
  change but reads (`Change`): the dirs it's in go stale, and if it isn't
  a dir any more (gone, or a file), the dirs in it are forgotten; a dir
  still there changed itself (a file added), not what's in its dirs.
  Changes missed make everything in them stale (`lost`, for a rescan;
  `forget`, for a watcher error), and what's kept in a dir that can't be
  watched is forgotten (`unwatched`). Apply, undo and create tell it what
  they change themselves, as they show the listing before the watcher
  tells. A stale dir asked for is counted again, and until it's done it
  shows what it was with `...` after it (`DirSize::Stale`), and sorts by
  it, so nothing moves: `~/Library` changes all the time, and counted
  again it came in as `...`, after the dirs counted, then jumped to its
  place. Then it moves only if its place changed (`sortCounted`). A dir
  shown keeps its size until it's asked for again (the next update or
  sync), and is counted again then (`Wanted::changed`), so a build
  writing in it doesn't have it counted over and over. A change during a
  count makes the dirs it's in stale as they're done (`Dir::stale`, or
  not kept if it's gone: what was read of them may be from before), rather
  than dropping them, as they were before: going into a dir the first
  time showed `...` for those that changed while they were counted (and
  in `~/Library` some always do), which nothing was kept of. Its dir is
  counted again when it's asked for, which reads only those.
- **Changes on disk** (koil-core's `Koil::sync`; read its CLAUDE.md): the
  listing shows what changes on disk as it happens, keeping the user's
  edits. `Koil.watch()` (after every `showListing`, sync and answer) has a
  `notify` watcher watch what `Koil::watched` says, and the dirs whose
  sizes are kept (see Stale sizes), changing only the watches that
  changed, at once (`paths_mut`: on macOS each change restarts the
  FSEvents stream), and only if the dirs did. Its thread
  skips reads, writes (unless sorted by size or a date, see Sorting) and
  events `Watched::affects` says can't matter, and
  queues `changedOnDisk` once per burst (`queued`). `syncTimer` then syncs
  (`syncListing`) 100 ms later, and not again for four times as long as
  the last sync took (a pattern's walk can be slow); not while a file is
  open (`showListing` syncs when the listing is back), nor while a dialog
  is open or questions are being asked, a macro runs, or the user types
  in the path field (it polls until then). `listing::sync` parses the
  buffer as the user has it (errors and all), gives it to `Koil::sync`,
  and turns its entry edits into text edits (`merge`): a line changes or
  goes for its entry, and a new one goes where `render` would put it among
  the lines with IDs (a new entry's after the last entry), as few spans as
  possible, without the line breaks around them (`trim_breaks`). Vim makes
  them with `mergeEdits` (see Edits from outside), from the listing
  (`mergeListing` switches from the path field and back), and they don't
  make the listing modified. A renamed open dir puts its new path in the
  field; a gone one shows its parent as a new listing (`moved`). What goes
  against the user's edits comes as one question per kind (`Question`:
  "`a` was renamed to `b` on disk, but you deleted it. Delete it anyway?"),
  asked in turn (`askConflicts`, chained by `ConfirmDialog.ask`'s `after`,
  which also runs when it's closed by a click outside). Until answered it
  stays the safe way; Yes resolves it (`Koil.resolve`), as an edit undo
  can take back.
- **Quitting**: `modified` (the title's dot) is the file's unsaved
  changes, or in the listing, edits or pending changes
  (`pendingChanges`: `koil.hasChanges()` after each update, koil-core's
  `has_changes`, from the diff alone). An edit
  makes it only if the text isn't what it was (`unedited`, as the file
  was opened or saved, or the listing shown, with its hidden text;
  `checkModified`), so `a` typed and deleted, or undone, leaves it off.
  The texts are compared only when they're as long (`System.sameText`).
  A sync merged into an edited listing makes that unknown (null) until
  it's shown again. `:q` updates first (`unsaved`); `:confirm q` (and
  `ZZ` in the listing) asks to
  apply the changes, where No quits without them; if the listing can't be
  read (errors, or a path that can't be opened), they ask instead whether
  to quit without them, under the update's error. `:wq` updates, as `:w`
  does, then quits as `:q` (`quitCommand`), so it doesn't apply either.
- **Files**: Enter on a file, File > Open (and a file on the command line)
  leave the listing (updating it first, so its edits stay in koil) for a
  plain editor: no colors or problems, only `-`, `_`, `!`, `Space r`,
  `Space o` and `Space Space` (a save) of `commandKeys`, and `:w` saves. `-` goes back to what's still open in koil, on `openedFrom` (the
  entry Enter was on), with the column and view it had (`fileSpot`), or
  for a file opened otherwise, opens its dir. Enter
  on a new file (`createFile`) updates, then asks to create it, listing the
  new dirs it's in (`Koil.createSteps`, koil-core's `Koil::create_steps`),
  and Yes creates them (`Koil.create`, `Koil::create_now`: an undo step like
  an apply's, keeping the other changes) and opens it. The listing starts
  over first, as after an apply: undo mustn't bring back its line without
  its ID, which koil would read as new again. One that needs other changes
  (a new `a` where `a` is moved away, or in a renamed dir) isn't created,
  and the status line says to apply them. Unsaved
  changes are asked about first (save, drop, or stay: `askToSave`), there
  and before File > Open, Open Folder or a drop opens something else
  (after the pick, so a dialog cancelled asks nothing). While the listing has
  pending changes, every quit command in a file (`quitApp`) goes back to the
  listing instead, once the file is saved or dropped as the command says
  (`:q` still fails on its unsaved changes); `:confirm q` and `ZZ` then ask
  about applying them. `:qa!` and Cmd+Q still quit. File > Open Folder
  (Cmd+Shift+O) and a dir or pattern on the command line list it; with no
  argument Koil lists the Start in setting's dir (see Settings), else the
  home dir. A file or dir dropped on the window
  opens as those would (`openDropped`; the first local one of several):
  `dropArea` is in the overlay, so the status line takes drops too, and
  opens it with `Qt.callLater`, so the app it came from isn't kept
  waiting while a long file or listing opens. A file is UTF-8, or UTF-16
  after a BOM (what Windows PowerShell 5 writes), and saving writes it
  back as it was, BOM and all (`Document`'s `encoding`; Save As too).
  Other encodings aren't opened: without a BOM they can't be told apart,
  and a Latin-1 fallback (vim's) would open a picture as text. A file that
  can't be read (one that isn't text, like a picture) isn't opened, and
  the status line says why,
  as for a save that fails (no `MessageDialog`, whose macOS style can't
  be themed), naming only the file, so a long path doesn't push why out
  of view; one on the command line lists its dir instead, on its entry.
  A message too long for the status line loses its middle, not its end.
- **`:e`** (`edit` in main.qml, vim's `editRequested`): `:e path` opens a
  file, or lists a dir or pattern, from anywhere (the listing, the path
  field, a file, the scratchpad), so a shortcut of `:e ~/src<CR>` is a
  favorite dir that works wherever it's run (a macro of Tab and the path
  went from the path field to the listing). The path is read as the path
  field reads it (quotes, `\`, `~`, patterns), from the open dir
  (`Koil.currentDir`, vim's cwd, also in a file). One that's a file on
  disk opens (`listing::file_at`: as written first, as a dir is, so
  `a[1].txt` isn't a pattern, then as koil-core's `read_location` reads
  it, as a glob, so `main.rs` isn't a regex with `:set regex`); anything
  else goes to `openFolder`, whose error says why it can't be opened.
  Vim then edits the listing, from the path field too, as Enter there
  does. Unsaved changes are asked about first (`askToSave`), as for a
  drop, and `:e!` drops them. `:e` alone reads what's shown again: the
  listing updates (keeping its edits, as Koil keeps them as changes, so
  `:e!` has nothing to drop there), a file is read again in place
  (`reloadFile`, `reloading`: `vim.replaceText`, one change `u` takes
  back, with the cursor on its line and column), unless it has unsaved
  changes (E37, which `:e!` drops), and the scratchpad has no file (E32).
- **Files changed on disk** (`checkFile` in main.qml): `Document.watchFile`
  watches the file shown (`filePath`) through its dir, as an app may save
  one by renaming another over it, and `fileChanged` has `fileTimer`
  check it 100 ms later: `Document.fileChange` compares its size and the
  time it was modified with what Koil last read or wrote (`Stamp`), so
  Koil's own saves aren't changes, and tells each change once. A file
  without unsaved changes is read again as `:e` reads it (`reloadFile`:
  one change `u` takes back, after which it's modified, as its text
  isn't the disk's), and the status line says it changed on disk; with
  unsaved changes, `ConfirmDialog` asks first (Yes reads it, and `u`
  brings them back, as Koil never drops them unasked). A file gone from
  disk is modified (`unedited` null), as its text is nowhere else. It
  waits while the user is halfway through something (insert or visual
  mode, the command line, a box, a run: `fileTimer` polls), but not after
  a shell command (`afterShell`, through `endWait`'s `done`), so a macro
  that ran `!echo hi >> %` goes on with what it wrote, and one `u` takes
  that back; unsaved changes are asked about once it's done.
- **Scratchpad** (`openScratch`): `_` in the listing (or the path field)
  or a file shows a text of the user's that's never saved, kept until
  Koil quits (`koil -s` starts in it, text piped in starts it, and `koil
  -p` prints it as Koil quits: see Command line).
  It leaves the listing as a file does (updating it first, `fileSpot`),
  and `_` or `-` there goes back (`leaveFile`) to where the cursor was,
  in the path field if it was there (`scratchFromPath`), which is a
  level, as from a file, so `3-` is `-` twice more from there (`_` takes
  no count). From a file, it
  keeps the file as it is (`scratchFromFile`: its text, unsaved changes
  and all, cursor, undo history, view and `openedFrom`), and `_` or `-`
  gives it back (`backToFile`), then reads what changed on disk meanwhile
  (`checkFile`), as it wasn't watched: so the scratchpad's own file
  (see Shell commands) has a stamp of its own in Document
  (`scratch_known`), as writing it made `fileChange` forget the file's.
  Anything else shown from the scratchpad asks about the file's unsaved
  changes first (`askToSave`, which saves the kept text), as from the
  file, and leaves it (`keepScratch`); a quit command goes back to the
  file first (`quitCommand`), so `:q` fails there on them (E37), and
  `ZZ` asks. In a shell
  command there, `%` is a file of its text, which goes back in it after,
  and `<cfile>` the path under the cursor (see Shell commands), and `:_!`
  puts a command's output in it. It's the
  listing's editor, so whatever shows something else in it saves the
  scratchpad's text, cursor, undo history and view first (`keepScratch`,
  from `showListing` and `load`, as anything shown goes through those),
  and `openScratch` gives them back (`vim.enterBuffer`). Its hidden text
  comes back too, on purpose: entries pasted there keep their IDs, as in
  a register, so they can be put aside and pasted back into a listing,
  and `gh` shows their paths. An ID means the same path all session, so
  one pasted back after its file is gone is an error (`NotOnDisk` in
  koil-core), not another file. Edits don't make it modified, `:w`,
  `Space Space` and Cmd+S only say it isn't saved, `:wq` and `ZZ` quit as
  `:q` and `:confirm q` do (`quitApp`: back to the listing while it has
  changes). Save As
  (`saveScratch`) writes its text to a file, as UTF-8
  (`Document.saveNewFile`: `saveFile` would store it as the file opened
  last was), and opens that in its place as File > Open does (asking
  about the unsaved changes of a file it's over first), with the
  cursor and the view where they were; the scratchpad keeps its text, as
  it does when anything else is shown.
- **Shell commands** (shell.rs, `runShell` in main.qml, vim's
  `shellRequested`): `:!cmd` runs `cmd` in the shell (`:set shell`, a vim
  setting the Settings window saves; empty for `System.defaultShell`:
  `$SHELL`, or `%ComSpec%` on Windows, as vim's) in the dir koil has open
  (`Koil.currentDir`, also while a file is, as vim's cwd), with nothing on
  its stdin. `%` in it is, as in vim, the file (relative to that dir if
  it's in it), but in the listing the entry on the cursor's line (from the
  path field, the open dir, `.`), where its ID is on disk, as for Space r
  (`listing::paths_on_lines`; a new entry is an error), and in the
  scratchpad a file of its text (`Document.writeScratchpad`, written
  before the command runs: `scratchpad.txt` in a dir of Koil's own in the
  temp dir, made new, so on Linux's shared `/tmp` no one else's can be in
  its place, and taken away when Koil quits; with a line break after its
  last line, as vim writes one, so `echo hi >> %` writes a line of its
  own, which reading it back takes off). Once a command that isn't a
  filter or `:_!` is done, what's in the file goes in the scratchpad
  (`afterShell`, if its size or time changed), as a change `u` takes back
  (`Vim.replaceTextKeeping`: a line that stays keeps its hidden text,
  wherever it goes, as the file has the icons alone). `<cfile>`, as in
  vim, is the file name under the cursor as gf takes it, in a file or the
  scratchpad (`listing::links_on_lines`, `link::link_at`: the URL or path
  Cmd+click underlines, or else vim's file name there or after it; a path
  as `link::target` reads it, from the file's dir, then the open dir, and
  must be on disk, E447, and a URL as it opens; on a line with an entry
  pasted with its ID, where that is on disk; none is vim's E446), and in
  the listing the entry, as `%`. With a range, it's each line's first
  link, or else its first file name (`link::first_link`: `git status
  --short`'s ` M src/a.rs` is `src/a.rs`, not `M`). Both take vim's
  modifiers (`%:p`, `:h`, `:t`, `:r`,
  `:e`); `\%` is a `%` (`date +\%F`), and `\<cfile>` a `<cfile>`, as in
  vim, also in quotes. A path is quoted as the shell's kind needs
  (`shell::Kind`, by its name: cmd.exe, PowerShell, else sh), only if it
  must be, and escaped instead where the `%` is in quotes (`"%"` works);
  one starting with `-` gets `./`. With a range (`:.,+2!`, `:'<,'>!`),
  it's vim's filter, the same everywhere: the lines go to its stdin, and
  its stdout replaces them (`Vim.filterLines`, one undo step; no output
  deletes them; a failure, or the text changed meanwhile, leaves them;
  marked lines go to it together, and its output goes where the first
  one was), without the empty line after a file's last line break, which
  `:%!sort` would sort first. In the listing, they go to it without their
  prefixes (`Vim.filterInput`), and its lines get one each
  (`prefixLines`): new entries, as its output has no IDs. But a command
  with `<cfile>`, or in the listing with `%` (not escaped), is run on the
  entries (or paths) of the range's lines instead, which they stand for
  (blank lines left out; `paths_on_lines` and `links_on_lines` take
  spans of lines, as `'<,'>` after marked lines is only those: see
  Marked lines). `!` everywhere is one of `commandKeys` (`bangLines`),
  typing `:! %` with the command line's cursor before the ` %`
  (`Vim.openBang`), so the command goes there; with a count, the range
  of its lines (`3!`: `:.,.+2!`), and in visual mode or on marked lines
  `:'<,'>!` (`:` types `'<,'>` too, leaving visual mode, as in vim),
  each with ` %` after it in the listing (`Vim.bangEntries`), so it's on
  their entries, but none elsewhere, where it's vim's filter (no key
  types `<cfile>`). `g!` is vim's `!` operator (`g!{motion}`,
  `g!!`, typing the range of the lines it covers, or in visual mode and
  on marked lines `:'<,'>!`), for the filter where `!` isn't; Vim.qml's
  own `!` operator is the same, which Koil's key takes the place of
  (only the tests have it). Ex commands take vim's ranges (`exRange`: numbers,
  `.`, `$`, `'<`, `'>`, `+N`, `-N`, `%`): one alone goes to its last line,
  and commands other than `!`, `:s` and `:normal` (`takesRange` in
  `exCommands`) refuse one (E481). A `!` first is the last
  command (`:!!`). `:_!cmd` (Koil's, after the scratchpad's key; `:%_!`
  with a range) puts what it writes in the scratchpad (`showInScratch`),
  in place of its text, as a change `u` takes back (`Vim.replaceWhole`):
  stdout and stderr as for `:!`, but all of it (up to `FILTER_BYTES`) and
  with its tabs (`Request::scratchpad`). A range's lines go to its stdin,
  and stay, or with `<cfile>`, or `%` in the listing, it's on their
  entries, as for `:!`. It shows the
  scratchpad as `_` does: from the listing, updating before the command
  runs (after which the listing might not read: an entry it deleted), and
  from a file over the file, which keeps its unsaved changes. If it writes nothing,
  nothing changes. A macro running it goes on in the scratchpad:
  `endWait`'s `done` shows it as a step of the run (`inChunk`), which
  `vim.reset` would otherwise interrupt. It runs on a thread
  (`System.runShell`, one at a time), in the environment the user's shell
  sets up (`environment`): on macOS, an app opened from Finder has only
  launchd's (the system's PATH, not Homebrew's), so unless Koil was
  started from a terminal (`TERM` set), it's read once, as VS Code and
  Zed do, from `$SHELL -l -i -c`, interactive so it reads `.zshrc` too
  (where Homebrew's PATH often is; `-l` alone, as MacVim's, missed it).
  Running every command that way took 200 ms each, and the rc file
  printed into the output, so it runs once (`read_environment`, started
  on a thread from main.qml's `onCompleted`, or as the setting is turned
  on: `System.loadShellEnvironment`; the first command waits for it),
  prints the environment between marks (`env -0`), is killed after 10 s,
  and has `KOIL_RESOLVING_ENVIRONMENT` set, for an rc file to skip what's
  slow. Commands then get it (`env_clear`, so its PATH finds the shell
  too) and no `-l`, which would run `path_helper` again and put
  `/usr/bin` first. If it can't be read, or the Settings window's Shell
  environment (`shellEnvironment`, on at first, the last row, macOS
  only; `Request::environment`) is off, which doesn't run the user's shell
  at all, those in `LOGIN_SHELLS` get `-l`, as before. Sh and the like run
  with `-c`, cmd.exe
  with `/d /s /c "…"` as a raw argument, PowerShell with
  `-EncodedCommand`, and Git Bash with its command line always quoted (its
  runtime globs an argument that isn't), in a process group of its own
  (no console window on Windows). Meanwhile vim waits (`Vim.waiting`,
  "Running (Esc to stop)"): keys do nothing but Esc and Ctrl-C, which stop
  it (`Running::stop`: SIGINT to the group, SIGKILL a second later;
  `taskkill /T /F` on Windows), a macro running it waits too (`runChunk`
  stops; `endWait` goes on), and `boxOpen` keeps the menu, drops and syncs
  from changing anything. Its stdout and stderr come through one pipe
  (`io::pipe`), in order, shown as a terminal would show them
  (`shell::as_shown`: no escapes, `\r` and backspaces writing over, tabs
  as spaces), the first `SHOWN_LINES` (1000: the help box took half a
  second to lay out 3000): a line that fits goes in the status line
  (`StatusLine.fits`), more in the help box (`help.showText`, plain, where `/`
  searches it, and Enter closes it, as vim's "Press ENTER"). A failure
  ("shell returned 1") is an error, which stops a macro. What it starts
  with `&` keeps its output open, which is read only `AFTER_EXIT` longer.
  Koil quitting stops it (`SystemRust`'s `Drop`). The Settings window's
  list is `shell::shells`: `/etc/shells`, or cmd.exe, both PowerShells and
  Git Bash where it installs or by git on the PATH. Windows' kinds are
  untried, but `shell.rs` checks for its target.
- **Command line** (cli.rs, read in `main` before the app, so `--help`
  doesn't show it in the Dock): `koil [OPTIONS] [PATH] [+N]`, parsed by
  clap's builder (`arg!`, not derive), its help and errors clap's (exit
  2), printed by `clap::Error::exit` once `attach_console` ran. The path
  is as under Files (one: more is most likely a pattern the shell
  expanded, which the error's tip says to quote). `-s` (`--scratchpad`,
  aliases `-t`, `--temp`) starts in the scratchpad, over the file or the
  listing of the path (`startUp` in main.qml, `startScratch`; over a
  file that can't be read, its dir's listing, on its entry). Text from
  stdin goes in it too (`Document.takeStartupText`), read to its end
  before the window opens, as vim's `-`: with `-` (from a terminal too,
  until Ctrl-D), or else if stdin is a pipe or a file (`piped`: not
  `/dev/null`, which an app launched from Finder or the Dock has, nor a
  device that never ends, like `/dev/zero`) and has something in it.
  Unlike a file, it's shown whatever it is, with what isn't text as `�`
  (`document::decode_lossy`). `-p` (`--print`) starts in the scratchpad
  too, and prints its text to stdout as Koil quits, however it quits
  (`onAboutToQuit` in main.qml: `scratchText`, shown or kept, without a
  `:s` preview; `Document.printScratchpad`, `cli::print_scratchpad`),
  with a line break after its last line, as `%`'s file has, so Koil can
  edit text in a pipe (`ls | koil -p | sort`, as `vipe`). Nothing else
  Koil does writes to stdout, and what it starts that could (Space r,
  Space o's `xdg-open`) gets a null one: an app given Koil's would keep
  the pipe open after Koil quits. `+N` puts the cursor on line N of what's
  shown (`+` the last one), in the middle of the view, as vim's
  (`goToLine` types `NGzz`). Then each `-c` (`--command`, `Args::commands`,
  `Document.startupCommands`) runs, in order, as typed after a `:`
  (`shown` in main.qml, `Vim.runCommands`: all of them one run, the keys
  `:`, the command's characters and `<CR>` each, as `@:` types it), so
  anything Koil does can be done at startup without an option of its own
  (`-c 'set sort=size wrap'`, and keys with `-c 'norm G'`). As a macro's,
  a command that fails stops the rest (keys that fail in `:normal` too),
  and they go in the command line's history. Keys run one after another
  in the run, and what `_` shows is shown before its key is done
  (`keyCommand` goes through `outside`), so `-c 'norm _ihi'` types in the
  scratchpad, however long the listing took to show. They
  run after the file can't be read too, over its dir's listing. clap has no `+` options and fills
  positionals in order, so `[PATH]`, `[+N]` and a hidden `more` only
  collect them, and `parse` tells `-`, `+N` and the path apart by what
  they are; after `--` they're all paths (`escaped`, a `last`
  positional), as in vim. `-psn_…`, which older macOS passes, is taken
  out before clap, which would read it as `-p -s -n`. Qt is given every
  argument too (cxx-qt passes them all), so Koil's mustn't be options Qt
  reads (`-platform`, `-style`, `-reverse`), which are errors here (Qt's
  environment variables still work). The scratchpad opens once the
  editor is done, as a file does (so a long text is laid out once); a
  path that can't be opened lists the home dir under it, with why only
  in the status line, since back from the scratchpad the field shows the
  listing's path. A Windows release build is a GUI app, which has no
  console, so `--help` (and an error) attaches to the one it was started
  from (`attach_console`, untried), as does `-p`'s text.
- **The koil command**: on macOS, the Settings window's Command line
  button (`Document.changeCommand`) puts a script at `/usr/local/bin/koil`
  (`install::COMMAND`: on the PATH every shell gets, from `/etc/paths`)
  that `exec`s Koil's binary where it is (`install::script`), or takes it
  away. Nothing else takes it away (macOS runs nothing for an app dragged
  to the Trash), so if the binary isn't there any more, the script says
  so and how to remove it (exit 127), rather than `exec`'s error. A script, not a link to the binary, so the binary runs from its
  bundle as when it's opened: through a link, `current_exe` is the link,
  so `in_bundle` would be false (a window icon over the bundle's). The
  dir is root's, so it's written
  as the user if they can (a Homebrew `/usr/local` on Intel), or else as
  root through `osascript`'s `do shell script … with administrator
  privileges` (`as_admin`), which shows macOS's password dialog: on a
  thread, so the windows don't hang meanwhile, then `commandChanged`
  with why it failed (nothing if the dialog was cancelled). It's
  installed for the Koil that runs (`this_exe`), but not from the disk
  image or a translocated copy, which go away. `commandStatus` says
  what's there, which the window reads whenever it's active: this
  Koil's script, another Koil's (by `MARK`, the line after `#!`: one
  moved, or another copy; Replace makes it this one's), another program,
  or nothing. On Windows, the installer's `addtopath` task puts Koil's
  folder last in the PATH (the user's, or the machine's for all users),
  in `[Code]` (`SetPath`), which takes it out when uninstalled or
  reinstalled without the task; last, as Koil's Qt DLLs are on the PATH
  with it, and mustn't come before another Qt's. Untried, but CI's ISCC
  compiles the code.
- **Open in Koil**: on macOS, a service (`NSServices` in Info.plist) on
  what's selected in Finder, only there (`NSRequiredContext`, without
  which macOS also has a service off at first): in its right-click menu
  (Services) and the Services menu. It takes anything (`public.item` in
  `NSSendFileTypes`; it took only folders, `public.folder`, at first,
  and its message is still `openFolder`, as the shortcut the user set is
  kept by it), which is what puts it in right-click menus and
  under Files and Folders in System Settings; one that takes nothing (as
  it did, asking Finder through `osascript` which folder its front window
  showed) is under General, and macOS ignores `NSServiceCategory` (tried
  with a test bundle; `_NSCopyServiceActions` lists each service's
  category, as System Settings does). The cost: with nothing selected,
  macOS turns it off, shortcut and all. macOS handles its shortcut,
  launching Koil if it isn't running, so Koil needn't run to listen. It's
  ⌃⇧K at first (`^$k`), which Finder doesn't use, nor text fields (not
  ⌃K, their delete to the line's end, which a service's shortcut would
  take first, as in Finder's rename field), but Keka's "Send to Keka" does
  (the README says how to change it). `NSKeyEquivalent` is a letter, with Command (and Shift if it's
  uppercase), or modifiers and a key as pbs keeps them (`^$K` is ⌃⇧K, as
  Keka's are; `_NSCopyServiceActions` shows the shortcut macOS takes). The files come on the pasteboard (finder_mac.mm), and
  Koil comes to the front (macOS doesn't bring it for a service that
  gives it nothing back) and opens the first (`Document`'s
  `folderRequested`, not while a dialog is open): a folder as a dropped
  one (`openDropped`), anything else (a file, or an app or another
  package, which Finder shows as a file: `file`) as the dir it's in, on
  its entry (`showFileDir`, through `openFolder`, so the listing's edits
  stay). Its provider is set from the Document's `onCompleted`, before
  the app runs, so the request that launched Koil comes. The user changes
  the shortcut in System Settings (Keyboard Shortcuts > Services > Files
  and Folders), which keeps it in `pbs`'s preferences (`NSServicesStatus`,
  by the bundle ID, menu item and message); the Settings window shows it
  from there (`finderServiceShortcut`), read whenever it's active, and its
  button opens Keyboard Shortcuts on Spotlight, the row under Services: no
  anchor goes to Services (`?Shortcuts` lands on Modifier Keys, the last
  row; the anchors are `name of every anchor of pane id
  "com.apple.Keyboard-Settings.extension"`). It works only from an app
  bundle Launch Services knows (`lsregister -f`, then `pbs -update` to
  have macOS read its services), not `cargo run`. On
  Windows, the installer adds "Open in Koil" to the right-click menu of
  folders, a folder window's background and drives (a task, on at
  first), which starts Koil with the folder; on Windows 11 it's under
  "Show more options". A drive's root comes quoted, `"C:\"`, which reads
  as `C:"` (`command_line_path`). Nothing on Linux.
- **Colors** (`setListingColors` in native.cpp): a `QSyntaxHighlighter` on
  the editor's document colors each line's icon (colors from devicons,
  gathered from every listing shown, `iconColors`, dark or light by theme)
  and a name up to its last `/` (`theme.directory`: a dir's whole name,
  and the dirs of a pattern's path, `src/` of `src/main.rs`). It's
  text-based, so it follows
  edits. A pending entry's icon (one applying would change: new, or at a
  path that isn't its ID's on disk, so renamed, copied or moved here;
  `listing::pending_lines`, from `Koil::is_pending`) is pure white in a dark theme and
  pure black in a light one (`PENDING_COLOR`, sent as `pendingColor`), and
  `listing::apart` moves devicons' colors that come within `APART` of those
  (its white icons, like `vercel.json`'s) a fifth away. main.qml finds the
  pending lines after every edit of the listing (`updatePendingLines`, with
  `Qt.callLater`: halfway through vim's `replaceRange` its hidden text isn't
  up to date, and coloring is a text change to Qt, which would make
  `trackEdit` shift the hidden text again), and the highlighter colors those
  lines' icons (`setPendingLines`): every line whose icon was last colored
  otherwise (`ColoredAs`, its block's user data), not only those that were
  pending, as Qt colors a line as an edit reaches it, with the pending
  lines it has then, and vim's edit is a remove and an insert, between
  which lines have other numbers (a `:s` preview left a file's icon
  white). The highlighter is found by object name
  (no moc for native.cpp). Highlighting counts as a text change to Qt (as
  `fixLineFormat` does), so Editor.qml only emits `edited` when the text
  really changed (see `latest` under Long texts), and `trackEdit` returns
  at once. Coloring again goes through `recolor`: only the lines whose
  pending state changed,
  nothing if the colors are the same, and as one edit, with layout off for
  more than a few lines (`QSyntaxHighlighter` lays the document out after
  each line, so coloring a 3000-line listing again took a second, and `-`
  out of it two). The path field's document has one too
  (`setPathColors`, `isPath`): all of it in `theme.directory`, and if the
  path has a pattern, `pathSyntax` gives it in the text's color, so it's
  told apart from the dirs before it (`dir/*`), and its parts over that
  (`listing::path_syntax`: from where `Koil::read_location` says the
  pattern starts, after the longest existing dir, at the first part with a
  special character that isn't quoted; a regex's, `regex_parts`, with
  `:set regex`, which the next update reads it with, else a glob's,
  `glob_parts`), in `theme.patternColors`.
- **Syntax** (syntax.rs, `setTextColors` in native.cpp): a file (and the
  scratchpad) is colored by what most files share, not by its language
  (unless `:set nosyntax`, a vim setting, `vim.syntax`, which `:syntax
  off` and `on` set too; the Settings window saves it; off, `applyColors`
  gives no colors, which takes the highlighter away):
  strings (`"`, `` ` ``, and `'` only where no word goes on from its end,
  so neither `it's` nor Rust's `&'a` starts one; Python's `f'…'` does),
  with their escapes; numbers (not a unit after them, `10px`, nor a hash,
  `3f2a`); comments (`//`, `/* */`, `<!-- -->`, and `#` before a blank,
  more `#`s, a line of `-`s or a shebang, but not `#include`, `#[derive]`,
  `#fff` or `#123`); and over those, URLs (underlined) and paths (in
  `theme.directory`, as in the listing): `/abs`, `~/`, `./`, `C:\`, or a
  relative one that looks like one (`src/main.rs`, `a/b/c`, `docs/`, but
  not `and/or`, `km/h`, `1/2`). Strings and comments are found as their
  starts come, left to right, so a `#` in a string isn't a comment. A `/*
  */` or `<!-- -->` goes on to the next line as the block's state. The
  file's name says which comments it can have (`Comments::of`): no `#`
  ones in Markdown (headings), no `//` in Python (division), which is all
  it knows of languages. Only a line's first `MAX_LENGTH` (3000)
  characters are colored, as with vim's `synmaxcol`. native.cpp's
  `TextColors` asks Rust for each line's spans (`syntaxSpans`, in UTF-16,
  as Qt has it, of the line's first `coloredLength` characters) and gives
  them to the line's layout, apart (`syntax::apart`: Qt Quick drops the
  end of a format that starts in another, so a path in a string lost its
  last character and the string's closing quote), as a
  `QSyntaxHighlighter` would, but without
  its format for each character of the line (5 ms for a line of a
  megabyte), and not again when only the text's format changed
  (`FormatOnly`: the line format, Koil's margins, see Long lines), which
  had it color every line again; a line's state (in a `/* */`) is its
  block's user state, as a highlighter's. Only one highlighter may color a
  document (each would take the other's colors away), so Editor.qml takes
  the listing's
  away before giving a file's, and the file's before the listing's. Which
  it gives follows `listing` only as the text is replaced
  (`listingColors`, set in `setText` with no text in, as the wrap mode
  is): `listing` comes before the text, and the listing's highlighter
  went through every character of a gigabyte's file (QSyntaxHighlighter
  makes a format for each) before the listing replaced it, 4 s of `-`. A new
  one colors at once (else Qt colors it all again once the event loop
  runs, without `recolor`'s batching, and colors no edit until then); new
  colors or comments color again a moment later (`stale`), which `setText`
  drops, as the text it puts in is colored as it goes in: so main.qml's
  `load` sets `filePath` before the text, and a `.md` opened after a `.rs`
  isn't colored as the old text first. What colors cost is Qt's layout,
  which splits lines where the colors change: a 105,000-line file opened
  in 4.4 s rather than 3.5 (the Rust took 60 ms of that).
- **Links** (link.rs, `openLink` in main.qml): in a file or the
  scratchpad, gf (vim's `linkRequested`) opens the link under the cursor
  in Koil, as a drop does (`openDropped`: a dir is listed, a file opened,
  unsaved changes asked about first), gx in its default app
  (`System.openInApp`), and either a URL in the browser
  (`Qt.openUrlExternally`; `www.` gets `https://`). The link is a URL or a
  path as syntax.rs colors them (`syntax::link_at`), or else the file name
  there or the first one after it on the line, as vim's `<cfile>` (its
  default `isfname`, `\ ` going on, a sentence's `.` or `,` off its end:
  `Cargo.toml` works, which isn't colored as a path). In visual mode it's
  what's selected. `link::target` reads its text: a `file://` URL is its
  file, `~` the home dir, `\ ` a space (not on Windows), and a relative
  path is looked for in the file's dir, then in Koil's (`currentDir`), as
  vim's `path` (`.,,`), and must be on disk (vim's E447 otherwise); its
  `..`s are taken away as written (`normalized`), so the title shows
  `README.md`, not `src/../README.md`. On a line with an entry pasted with
  its ID (see Scratchpad), wherever the cursor is, it's that entry, where
  its ID is on disk, as `<cfile>` takes it (`linkTargetAt`,
  `listing::pasted_entry`), not its name read from the open dir, as in the
  listing. In the listing, gf opens the entry
  on the cursor's line as Enter does (`openEntry`, but with no vim's Enter
  on a line without one), gx as Space o, and from the path field gf opens
  the path and gx the open dir. Cmd (Ctrl elsewhere) held with the pointer
  on a link (Editor's `link`: in the listing, and on a line with a pasted
  entry, the name on the line; not the path field) underlines it in `theme.directory` and makes the pointer
  a hand; a press there and a release on the same link moves the cursor
  to the character clicked (`vim.jumpTo`) and opens it as gf does
  (`linkClicked`, `clickLink`; not while `boxOpen`). Whether Cmd is held
  comes from the `HoverHandler`'s `point.modifiers` as the pointer moves,
  and from Cmd's own key events (`Qt.Key_Control`, which is Cmd on macOS)
  for one pressed while the pointer rests; the editor losing the keys
  takes it as let go, as one let go after Cmd+Tab never comes. A scroll
  drops the link until the pointer moves, as its place in the editor
  changed.
- **Matching brackets** (`brackets` in Editor.qml, `Txt.bracketPair`): as
  vim's matchparen does, the bracket at the cursor (or before it, in
  insert mode) and the one it matches are boxed, in every buffer, but
  only when both are in view, which is as far as it looks (vim's `%`,
  `matchPair`, goes through all the text). Brackets in strings and
  comments count.
- **Icon font**: devicons' icons are Nerd Font glyphs in the Private Use
  Area. Koil ships one, JetBrains Mono NL Nerd Font (Nerd Fonts v3.5.1,
  `fonts/`), compiled into the binary (`include_bytes!` in main.rs), so no
  packaging script copies it. Every character advances one column, but the
  icons are drawn up to ~1.75 columns wide, over the next one: that's why an
  entry has two spaces after its icon. Not the "Mono" variant, which shrinks
  the icons to one column. "NL" is no ligatures, which would draw several
  characters, like the `=` line, as one. `useNerdFont` adds it and makes it
  Qt's fallback for the icons (Qt 6.8+; Qt only takes application fallbacks
  for real scripts, and treats these as `Script_Common`), so they show in
  fonts like Menlo. It's also the editor's default font
  (`defaultFontFamily`), by the family Qt gives it (`System.nerdFontFamily`,
  as the font has two names, and which one Qt uses depends on the
  platform). Only the regular weight is shipped: the editor draws no bold.
- **Shortcuts** (`Vim.shortcuts`, ShortcutsWindow.qml): the user's own,
  any keys (`Space c`, `gc`, `<C-k>`, written as `commandKeys`' are) that
  run keys of theirs as `@` runs a register's
  (`runKeys`: in chunks, one undo step, Esc stops it, a count runs it that
  many times), in normal mode, visual mode or both, wherever vim is (the
  listing, the path field, a file, the scratchpad). `commandFor` matches
  them after `commandKeys`, which are normal mode's only; in visual mode
  too, so Space there waits for a key rather than moving (`Space q` is
  one), and Space and another key is a bad command. They come before
  vim's own keys, as a vim mapping does: a shortcut on `xa` makes `x`
  wait (no timeout tells it apart), and any key but `a` after it is a bad
  command; `gc`, which vim reads as a bad command, takes nothing. A macro
  recorded meanwhile keeps the shortcut's keys, not what they ran.
  Their keys run other shortcuts (as macros recorded with them need),
  which can loop (see Macros).
  They're saved in `settings.shortcuts`, as JSON of `{ name, keys, macro,
  mode, enabled }` (`readShortcuts` drops what isn't one, as the settings
  can be edited by hand), which Restore Defaults leaves alone, and
  only the enabled ones with keys reach vim. Koil shows keys with Space
  as a word (`Vim.keysName`: `Space gc`), in the list, the form and the
  status line's run. The window (`Space q`, Koil >
  Shortcuts…, `ApplicationSpecificRole`, which puts it in the app menu;
  File > Shortcuts… elsewhere; and a button in Settings) lists each by its
  name, else its keys, else the keys it runs, and under them, while the
  lock button by + is on (`root.showOwnShortcuts`, saved, off at first),
  Koil's own
  (`root.ownShortcuts`: `commandKeys`' of every buffer, by hand, with
  where they work; `gs` for the sort keys), under a heading, each with a
  lock rather than a pencil and a trash, dimmed where they do nothing
  (`commandHere`: none of `commandKeys` starts with them). A click on one
  (or Enter) closes it and runs it in the main window
  (`runShortcut`), even one that's off or has no keys: in visual mode if
  vim is in it and the shortcut is for it, else in normal mode, which vim
  goes to first; Koil's own as if typed in normal mode
  (`vim.startCommand`), only where they do something; not while a box
  has the keys or a shell command runs.
  Its pencil shows it in a form, as + (or Cmd+N) does a new one, which Save
  saves (Esc and Cancel go back to the list), and its trash deletes it at
  once. `Space q` opens it once the key is up (`openShortcuts`, on the
  editor's `keyReleased`, or 300 ms later for a macro's keys): opened while
  `q` was down, its release went to the new window, and macOS's text input
  (which watches a held key for its accent menu) logged
  "TSMSendMessageToUIServer: … FAILED" up to three times. A window becoming
  active still logs it now and then (Settings too), which nothing here
  causes. In the form, Enter saves whatever has the keys (a `Shortcut`, as
  Return is a macOS dialog's default button, which `primary` colors), and
  Space clicks a button. Everything in it is reached with Tab (`tab`, a list of what each
  page has, which every control there hands Tab and Shift+Tab to): Qt's
  own Tab reaches only text fields and lists on macOS unless Keyboard
  navigation is on in System Settings, and skips every button. The list
  has no keys of its own (it had vim's `j`, `k`, `e`, `a` and `/`): the
  search over it has them whenever the list shows (`focusSearch`), so
  typing searches, Up and Down pick a shortcut, Enter runs it, and Tab
  goes to the picked one's pencil and trash, then +. The search shows only
  the shortcuts every word of it matches (`shown`, `shownOwn`, `matches`:
  in the name or the keys it runs, or a word of its keys as shown,
  `space` or `gc`, as a part of "space" would match every shortcut with
  Space). Esc empties it, as in a macOS
  search field, and with none, closes the window (`back`). A row gets its
  shortcut with its index (`rows`: `{ at, shortcut, own, heading }`), not
  the index alone, as the shortcuts change before the list does, which
  left a deleted one's row reading past their end. Opened anew, it has no search, on its
  first. Its shortcuts, and Settings' (Esc, Cmd+W), are on only while
  their window has the keys (`focused`: its `activeFocusItem`, which is
  null otherwise): with Qt Quick Controls loaded, a `Shortcut` takes its
  window as active while any of the main window's family has the keys,
  so Esc in the editor closed them, and with both open, their Escs were
  ambiguous and neither ran. Space or Enter clicks a
  button (`TextButton`, `IconButton`), and `Segmented` is one stop, where
  Left and Right pick. While the macros are listed, their popup's window
  gets the keys (so it has `focus`, and both it and the button handle
  them: `macroKey`), and the window asks to be active again once it
  closes, as Qt's offscreen platform left the popup's. The form's key box
  takes the keys typed, as vim names them (`typeKey`, `Vim.tokenFor`:
  Backspace takes one back, Cmd+Backspace all; Tab, Enter and Esc go to
  the form, so no shortcut has them). On macOS, Cmd and a letter, digit or
  sign is a key too (`<D-k>`, `<D-K>` with Shift, as MacVim names them),
  in the box and in the editor, where only a shortcut does something with
  it (else it's a bad command); Cmd+W goes to the box rather than closing
  the window. They can't be Koil's own, start
  them, or start with them (`g`, `g.x`), nor a key Koil's menus or the
  editor's copy, paste and undo take before vim gets it
  (`root.menuShortcuts`, which the list doesn't show: Cmd keys on macOS,
  Ctrl elsewhere), nor another enabled shortcut's,
  in the same mode, nor start with a count or `"`, which vim reads first
  (`problemOf`). What of vim's they take the place of is said, in the
  warning's color, but they can be saved (`noteOf`, `Vim.vimCommandIn`:
  `parse`'s `plain` reads vim's keys alone; not where Koil's own already
  took them, as Space). The keys it runs are typed as `q` records
  them (`<CR>`), or taken from a register `q` records into
  (`Vim.macroList`). The names of keys in them are colored
  (`theme.specialKey`, `styledKeys`, from `Vim.keyParts`, so only what a
  macro reads as a key), in the field, the list and the macros: the
  field's own text is clear, and a `Text` over it draws it, at the
  cursor's place less the text before it, so it follows the field's
  scrolling (a font of one width, so the colors move nothing). Qt draws
  the cursor in the text's color, so the field has its own
  (`cursorDelegate`), which blinks as Qt's does. The window's height is the form's, worked out before
  the form is first laid out, when a wrapped text is measured too tall, so
  its hint is one line.
- **Clipboard**: the `"+` data carries `session`, random per run; another
  Koil's hidden texts (IDs, which mean other paths there) are dropped on
  paste, so its lines become new entries rather than copies of whatever has
  that ID here.
- **Paths that aren't Unicode** (only on Linux, or a malformed name on
  Windows; macOS keeps only UTF-8 names): a name shows with `�`
  (`to_string_lossy`), and the listing is read back through koil-core's
  `Koil::read_shown` (`listing::read`), which takes a part shown so for its
  ID's, so an unchanged line isn't a rename (`MOVE a� -> a�`, which applying
  made). QML's strings can't hold one, so Koil's JSON gives QML only
  strings, and where it would act on such a path (Enter, gf, Space r,
  Space o, a shell command's `%` or `<cfile>` on an entry) it says it can't
  (`listing::unicode`: `Target::Error`, the `message` of `{ path, message }`
  and `{ paths, message }`), rather than give another path; a dir's name
  is the same (the dir can't be entered). koil-core's types that QML hands
  back (a question's `Conflict`s) and the undo history's file keep it, as
  koil-core keeps paths in JSON (`serde_path`); serde's own `Path` fails on
  it, which made `to_json`'s `expect` abort Koil.

## Non-obvious decisions

- **Menus**: QtQuick Controls menus have no `role` property, so macOS uses
  `Qt.labs.platform` MenuBar with `PreferencesRole`/`QuitRole`, which moves the
  items into the app menu (`MacMenuBar.qml`). Windows and Linux use an
  in-window Controls `MenuBar` (`WindowMenuBar.qml`), with the same items,
  so a change to one goes in both. One is created in main.qml's
  `Component.onCompleted`, so only one exists at a time. Qt titles the PreferencesRole item "Preferences..."; a `QTranslator`
  for the `MAC_APPLICATION_MENU` context renames it to "Settings…".
- **Shortcuts**: use `StandardKey` where Qt has a binding. On macOS
  `StandardKey.ZoomIn` also fires on Cmd+=; on Windows it doesn't, so that
  menu uses "Ctrl+=" plus a `Shortcut` for Ctrl++. The Windows/Linux menu
  writes "Ctrl+," and "Ctrl+Q" as plain strings, because `Preferences` and
  `Quit` have no Ctrl binding on Windows. "Ctrl+0" has no `StandardKey`. In
  strings, Qt maps Ctrl to Cmd on macOS.
- **Open With**: Koil offers to open text files but isn't made the default
  app of a type another app opens. On macOS, `Info.plist` claims, at the
  `Alternate` rank (`None` isn't in Open With at all), `public.text`
  (which source code macOS knows conforms to) and `public.data`, which
  matches only a file of that type itself: one with no extension (empty
  too) or a dotfile (`.envrc`), not a picture or an archive. A file
  whose extension macOS doesn't know (`.toml`) has a `dyn.*` type, which
  no claim on a type it conforms to matches (not `public.data`,
  `public.item`, nor a `*` extension), so a second document type claims a
  list of text and source code extensions by name
  (`CFBundleTypeExtensions`, as VS Code and Zed do; a dict with
  `LSItemContentTypes` ignores them), the same as Windows' `Exts`. It
  has their `'****'` OS type too (`CFBundleTypeOSTypes`,
  `legacy-wildcard` in `lsregister -dump`), which adds no other files:
  Launch Services puts a claim with it after every claim without it,
  whatever their ranks, so without it Koil was the default of `.rs` and
  `.toml` over their `Default` claims. Koil is the default of one only if
  no other app claims it. Launch Services ignores a bundle in `/tmp`, so
  trying claims out takes one elsewhere (`lsregister -f`, then `-u`),
  with a Mach-O executable, launched once (`open -g -j`): before, Koil
  wasn't the default of anything another app claims. Finder
  gives the file as a `QFileOpenEvent`, not on the command line (also to
  Koil already running): `Document.watchFileOpens` has native.cpp's filter
  call `document::file_opened` (C++ can't emit a cxx-qt signal, and the
  bridge allows no `#[allow(dead_code)]` for a signal only C++ uses), and
  main.qml opens it as a dropped file (`openDropped`). A cold start shows
  the home dir (or Start in) first, as the event comes once the event loop runs. On
  Windows, the installer does as vim-edit's: a `Koil.Text` ProgID, in the
  `OpenWithProgids` of a list of text and source code extensions (`Exts` in
  `installer.iss`; what the Open With menu shows), and those extensions as
  `Applications\koil.exe`'s `SupportedTypes` (so "Choose another app" offers
  it only for them). Its first is `.`, the key Windows looks up for a file
  with no extension (untried: the docs for it are old); a dotfile's name
  (`.gitignore`) is its extension there. Both give it the path on the
  command line, without taking any extension.
- **App icon**: macOS draws icons as they are, so `icon.png` is on
  Apple's grid: 1024 pixels, with the rounded square in the middle 824.
  It's Apple's shape too, with continuous corners (UIBezierPath's, radius
  185.4, as in Apple's templates): macOS 26 puts an icon that isn't in a
  gray one (in Finder, Launchpad, the Dock). A new picture must be put on
  the grid first, as `make-icons.sh` only scales it, and crops it for
  Windows, whose icons nearly fill their square (90%). Qt gives windows
  the exe's `IDI_ICON1` on Windows; elsewhere `main.rs` sets
  `window-icon.png` (the macOS one) as the window icon, for Linux and
  `cargo run` on macOS (its Dock icon), but not in the bundle
  (`in_bundle`), as on macOS it's the Dock's icon too, which then
  wouldn't be the one macOS draws from the bundle's, as Finder does.
- **cxx-qt**: bridges containing a `#[qobject]` declare `QObject` implicitly
  (declaring it again fails); plain bridges like `ffi.rs` must declare it
  themselves. `#[auto_cxx_name]` turns snake_case into camelCase for QML.
  qmlcachegen rejects `native` as a QML property name (hence `System`).
- **macOS**: `MACOSX_DEPLOYMENT_TARGET` is set to 13.0 in `bundle-macos.sh`.
  Without it, cc and rustc target the build machine's macOS version.
  `macdeployqt` breaks signatures, so the bundle is re-signed ad hoc. The
  Homebrew-only `macdeployqt` errors about QtSvg are harmless.
- **Windows**: `main.rs` sets the Fusion style (`QQuickStyle::setStyle`, unless
  `QT_QUICK_CONTROLS_STYLE` is set; setting that variable from Rust doesn't
  reach Qt, which reads the C runtime's startup copy), because the default
  "Windows" style has no dark theme (FluentWinUI3 left the title bar and menus
  light; Fusion doesn't). Fusion frames a TextArea like a text field, so
  Editor.qml replaces its background with a plain one. `build.rs` compiles
  the C++ with `/utf-8`: MSVC otherwise reads it in the system's code page,
  and qmlcachegen writes QML's strings into it as they are (the drop
  label's “%1” came out garbled). The MSVC CRT DLLs are
  copied app-locally, so no VC++ Redistributable is needed.
  `package-windows.ps1` loads the VS dev shell itself; `ilammy/msvc-dev-cmd`
  was removed because it's stuck on Node 20.
- **Buffers** (Vim.qml): vim edits one editor at a time, the listing or the
  path field. `leaveBuffer` ends insert or visual mode and the command line,
  and returns the buffer's state (cursor, `wantCol`, undo and redo stacks,
  `hidden`, `lastVisual`); `enterBuffer` takes it back once `editor` and
  `flickable` point at that buffer (`null`, or anything missing, starts
  empty). Registers, searches, macros, `.`, the command line and the options
  are shared. The editor vim doesn't edit (`Editor.active` false) keeps the
  state in `saved`, from which its hover finds hidden text
  (`Editor.hidden`) and its relative line numbers count; vim's own overlays
  (cursors, the current line, selection, highlights) are drawn only in the
  active one, and its diagnostics and line numbers use its own
  `visibleLines`. A press on the other editor switches before the
  `TextArea` handles it (the `MouseArea`), since the `TextArea` moves its
  cursor before it takes focus; taking focus any other way switches too
  (`activated`). `singleLine` (the path field) makes `replaceRange` turn line
  breaks into spaces (the same length, so positions stay right), and Enter
  while typing leave insert mode and then run normal mode's Enter. The
  macOS style doesn't let a `TextArea`'s background be replaced (it warns
  and keeps it; it's `palette.light`, not `base`), so the path field hides
  it, and the window behind the field uses the listing's background color.
- **Vim**: `Vim.qml` owns the cursor (`vim.cursor` is the character under the
  block), which Editor.qml draws (not while the command line is open,
  which has the cursor, as in vim). Insert mode uses the `TextArea`'s own cursor
  (`cursorDelegate`). Outside insert mode the `TextArea` is `readOnly`, so macOS
  doesn't open the accent picker on held keys and only vim edits the text.
  Changing `readOnly` makes the editor scroll to a stale cursor position, so
  `setMode` restores the view and then scrolls only if the cursor is out of it
  (`showCursor`: to all of the character under the block, and the padding
  after it, since Qt's cursor rectangle is a thin bar). The view scrolls
  past the text's end as far as its last line at the top (`scrollRoom` in
  Editor.qml: the `Flickable`'s `bottomMargin`, not the `TextArea`'s
  padding, above which it scrolls to show its cursor), for `zz`, `zt`,
  Ctrl-E, Ctrl-F (`pageForward`, as vim's), edits and the wheel
  (`maxScroll`; a click there goes to the last line), but a search and
  the other page keys stop at the text's end, as vim's jumps do
  (`endScroll`). The vertical scroll bar shows only when the text itself
  doesn't fit, and then on macOS it's `AlwaysOn`: with `AsNeeded`, the
  style's `visible` reads its size, which follows the room, and the two
  bars, which take room from each other, made a binding loop. Sideways
  (not while lines wrap, see Wrapping), the
  cursor keeps `:set sidescrolloff` (default 4) columns in view on either
  side wherever it moves (`showColumn`, after Qt's own scroll: `flush`,
  `setCursor`, and typing, a `Qt.callLater`), and at a name's start in the
  listing the whole prefix, so `0` scrolls all the way left. The view
  scrolls right past the text as far as the notes and messages after its
  lines reach (`sideScrollRoom`, the `rightMargin`; `maxScrollX`), for
  the wheel, the scroll bar and `zh`, `zl`, `zH`, `zL`
  (`scrollSideways`), which move the cursor as far as keeps it in view, as
  vim's do, but unlike vim's go on past the end of its line (which vim
  stops at), leaving the cursor, so a long line's note or message can be
  read; `zs` and `ze` put the cursor at an edge. Vim keeps its own undo stack (diffs per change), so native
  undo (Cmd+Z) is routed to it. Where Neovim's defaults differ from
  Vim's, Koil's are Neovim's: `Y` is `y$` (but lines in visual mode and
  on marked lines), `&` is `:&&`, `Q` runs the macro recorded last
  (`lastRecorded`), `@` and `Q` in visual mode run one on each line (see
  Macros), `*` and `#` in visual mode search for what's selected, as it
  is (`searchSelection`, which goes on from the selection's end or back
  from its start, so `#` doesn't stop on it first, as Neovim's does),
  and `nostartofline`: `G`, `gg`, `H`, `M`, `L`, `N%` (`keepCol`), `:N`
  and the commands on whole lines (`dd`, `>>`, `==`, visual and marked
  lines' `d`, `>`, `<`: `toLine`) keep the cursor's column, which j and
  k then go on from (`colKept`). Only the `"+`/`"*`
  registers use the system clipboard. Registers follow vim's (`setRegister`): `"0` only yanks,
  deletes and changes go in `"1` (shifting to `"9`) or `"-`, and `".`,
  `":`, `"/` and `"%` (`fileName`: the file, or the listing's location)
  are read from vim's state and can't be written. `:reg` (`:di`) lists
  them (`registerList`) in the help box, one line each, cut off. A yank
  shows what it took for 200 ms, as Neovim's `vim.hl.on_yank` does
  (`yanked`, `flashYank`: yy its line, a block its part of each line,
  the marked lines each, every cursor's at once), drawn under the text
  (a `SpanShade` in Editor.qml), which keeps its colors, until an edit or
  another buffer.
  Not into `"_`, nor a macro's (`macroKey`, set as its key runs, since
  its frame goes before its last key), as Neovim's `on_macro`, but a
  shortcut's, as a mapping's. The `TextArea` does nothing on Cmd+Backspace, so on macOS
  it's vim's `<D-BS>`: typed by vim in insert mode (`typedEdit`: back to
  the line's start, the name's in the listing, and there Backspace),
  `Ctrl-U` in the command line, nothing in the other modes. Other Cmd
  keys (`<D-k>`, see Shortcuts) do nothing but run a shortcut: insert
  mode leaves them to the editor, the command line drops them, and Cmd
  and an arrow stays the editor's (no token).
- **Macros**: typed keys are recorded as tokens (`"<Esc>"`, `"x"`); the register
  keeps them as `keys` next to the text, so literal "<CR>" typed in insert mode
  stays text. `@` pushes a frame (`{ keys, next, runs }`, not the keys `runs`
  times) on `typeahead`, whose keys a run (see Batches and runs) gives
  `runKey` with no key event, so vim types insert-mode keys itself
  (`typeKey`, `insertMove`). A failing command (bad keys, failed motion,
  `showError`) empties `typeahead` (`macroFails`). Past `maxMacroDepth`
  frames it's E223,
  as vim's `'maxmapdepth'`, and so is a chain of that many shortcuts and
  `@`s with no other command between (`chainedRuns`): one that runs
  itself last (`qa@aq`, or `s` running `ys`, which runs `s`) doesn't nest,
  and would never end (vim's `@` loops until Ctrl-C). One that runs a
  command, then itself (`qa<C-a>j@aq`), goes on until a command fails.
  `@q` in visual mode (`runOnLines`) is a frame with `each`: its keys run
  on each line in turn, from its start, as `:'<,'>normal @q` does
  (`macroStep` goes to the next line once a line's are done, ending what
  they left half done, `endHalfDone`), and a command that fails empties
  `typeahead` only down to it, which goes on with its next line, so the
  frames under it go on too, as after `:normal`. The lines left move
  with the edits as the marked lines do (`moveLineRuns`, through
  `movedMarks`), rather than by number as `:normal`'s do, which has `yyp`
  copy the copies. Koil's `:normal` (`:norm`, `normalCommand`) is such a
  frame too, and so goes by the lines the same way: with a range, on each
  of its lines, and without one, at the cursor, with no lines (`starts`
  empty, not `due`), ending what its keys left half done, as vim's. That
  one is `whole`: keys that fail in it fail it as a command (`macroFails`
  goes past it), stopping what runs it, unlike vim's, which stops only its
  keys: `-c 'norm _' -c 'norm ihi'` typed `hi` in the listing when `_`
  couldn't show the scratchpad (an update that failed). With a range, a
  line they fail on is skipped, as `@q`'s in visual mode. Its
  keys are written as a shortcut's (`macroKeys`: `<CR>`, `<Esc>`), not
  typed as they are, as vim's, since Koil has no `:exe` to write those
  keys with. `:normal!`'s frame is `plain`, whose keys no shortcut takes
  (`plainKey`, in `commandFor`), as no mapping takes vim's; a macro they
  run isn't, as vim's `@` maps its keys.
- **Batches and runs** (Vim.qml): each edit of the `TextArea` has Qt go over
  all the text, so while a key runs (`handleKey` through `batched`) vim edits
  a copy (`batch`; everything reads the text through `bufferText()`), and
  `flush` gives the editor the edits as one, with vim's mode and cursor
  (`setMode`, `setCursor` and `showCursor` wait for it; what needs the view,
  like `zz`, `H` or a search's preview, flushes first). The edit doesn't
  scroll (the view stays, as far as a shorter text reaches); the cursor
  scrolls as Qt does it, and after an edit or a new mode as `setMode` does
  (`showCursor`), since an edit can move the editor's cursor to where vim's
  goes, and setting it there doesn't scroll (`100000dk` from the end of a
  long text left the view blank); a key that changes nothing leaves the
  view alone, even off the cursor. A batch and a change (an undo step)
  keep how much of their text's start and end no edit touched
  (`unchanged`, which `replaceRange` narrows; the editor's own edits,
  typing, make a change's unknown), so `diff` compares only what's
  between: it compared slices from both ends of all of a long text, twice
  a key.
  Signals main.qml handles by reading the editor are emitted through
  `outside`, which flushes first. Commands that edit in many places make
  one edit through `replaceRanges` (`J`, a block's lines, `putBlock`), which
  took `4000J` from two minutes to a tenth of a second. What stays a loop is
  a run (`running`): a macro (`10000@q` took minutes, and as the JS never
  returned to Qt, its memory ran out), or a long command, `startTask`'s
  steps (`5000u`, `5000<C-r>`, `100@:`, and a count's repeat of an insert
  that goes key by key, `repeatInsert`: `10000ia<BS>b<Esc>` took over a
  minute; leaving insert mode, `endInsert`, waits for it, and so does
  Enter after it in the path field). Every other loop a count drives ends
  with the text: a motion stops at a step that doesn't move (`steps`),
  and a search stops going round its matches, so a huge count is never
  slow; a count that repeats text makes it in one edit. A run goes in
  chunks of `chunkTime` ms (`runChunk`), each a batch; between them the
  editor is up to date, the status line shows `vim.progress` ("@q 34%",
  "5000u 34%") instead of the position (which would be found again at
  every key), Esc or Ctrl-C stops the run (`handleKey`; other keys do
  nothing), and anything else that edits or moves vim (a click, the find
  bar, `reset`) stops it first (`interrupt`). A run is one undo step, as a
  macro's is in vim (`commitChange` waits for it, unless forced: `u`,
  leaving the buffer). Qt
  draws only once nothing is waiting, which a due timer never lets it, so
  the next chunk usually starts at once, but now and then waits `drawTime`
  for a frame: as often as keeps drawing to about a fifth of the time (a
  frame of 40,000 lines takes over 100 ms), at most 4 times a second.
- **Edits from outside** (`mergeEdits` in Vim.qml): Koil's listing as it
  changed on disk isn't the user's change, so `u` mustn't take it back (it
  would delete a file that appeared, or rename one back). It's made in one
  batch, and the undo and redo steps are moved past it (`movedSteps`): from
  the newest, each step's start moves past the edits before it, and the
  edits are taken back through the step, to where they are in the text
  before it, for the next one. A step an edit touches (overlaps; touching
  is fine) can't be undone any more, and the stack keeps only the newer
  ones. An insert going on is committed first and goes on as a new change.
  The cursors move past the edits (`movedPast`: in a replaced line, as far
  in as they were). With `undoable` (an answer to a question), it's a
  change like any other.
- **Visual block** (`visualBlock`): the editor's selection can't be a block, so
  it's cleared and Editor.qml draws `vim.blockSpans()` (the lines in
  view: all of a 100,000-line block took a second a key). Columns count
  characters, and `wantCol === Infinity` (after `$`) makes the block reach
  every line end. `I`/`A`/`c` put an extra cursor on each other line;
  `blockHome` makes Esc remove them and go back to the start. Ctrl+V is Paste
  on Windows, so `handleKey` lets it through as `<C-v>` outside insert mode; in
  insert mode it pastes on every OS. Likewise Ctrl+Y (Redo on Windows, Paste in
  Qt's macOS bindings) scrolls outside insert mode.
- **Multiple cursors**: `vim.cursors` holds the extra ones (Alt+click via a
  `MouseArea` over the editor, which passes plain clicks through). The editor
  knows one cursor, so with extras vim handles insert-mode typing and arrows
  itself: `editAll` runs an edit at every cursor from last to first, and
  `replaceRange` (or `trackEdit`, for the editor's own edits) moves the cursors
  after each edit. Each edit goes over all the text and hidden text, so a key
  typed at cursors close together is one edit over all of them instead
  (`editAtOnce`, `replaceRanges`: a block insert over 3000 lines took 12 s
  a key), and so is a count's repeat of an insert (`repeatInsert`: `10000o`).
  With 100,000 cursors a key still takes over a second, most of it Qt
  laying out every changed line again (a native edit per line, in one
  edit block, was no faster).
  Leaving insert mode removes them. In normal mode `moveBy`
  moves them too (`moveCursors`; each keeps its own `col` for j/k, and
  `motion(..., quiet)` doesn't scroll), and `execute` runs operators and
  `everyCursorActions` once per cursor (`atEveryCursor`), swapping in each
  extra cursor's own `registers`. They're drawn like the main one (no cursor
  blinks), but only those in view
  (`visibleCursors`): drawing a block insert's 100,000 took minutes a key.
- **Marked lines** (Marked lines in Vim.qml): `m` marks the cursor's line
  (`3m` three; in visual mode, the selection's lines, back in normal
  mode), or unmarks them if they're all marked (`toggleMarks`), so lines
  far apart can be used together, as the cursor still moves as in normal
  mode. `vim.marked` is their starts, sorted. While there are any, the
  keys of `markedActions` act on them as on a `V` selection of them all
  together (`executeMarked`; `parse`'s `marking` makes an operator act at
  once, as in visual mode): `d` and `y` put them in one register, `c`, `p`
  and `J` put what takes their place where the first one is, `>`, case
  changes and `r` change each one where it is (`markedBlocks`, as one edit
  through `replaceRanges`), `I`, `A` and `gI` type on each one (extra
  cursors; they stay marked meanwhile: `markedInsert`), and `:` (and `!`
  and `g!`: `bangLines`) types `'<,'>`, which then stands for them
  (`exRange` gives their `lines`: `:s` keeps to them through
  `selectionRegion`, `:!` with `%` runs on their entries, `pathsOnLines`
  taking spans of lines, and a filter takes them together). Other keys are normal
  mode's (`u` undoes, `i` types at the cursor), and `.` repeating a change
  isn't on them. A command (or `Esc`) unmarks them (`unmark`), and
  `lastVisual` (mode `"marked"`) keeps them for `gv`: where they are after
  the command if it kept them all (`>gv>`), else where they were, which `u`
  brings back. Edits move them with their lines (`movedMarks`, in
  `replaceRange` and `trackEdit`): an edit with as many line breaks as it
  took away (`:s`, `>`) leaves each after the same one, else a line taken
  away with a line break is unmarked, and one joined to the line before
  goes with it. `replaceRanges` moves them edit by edit (`placingMarks`),
  as one edit from its first to its last would take away the lines
  between. Each buffer has its own (`leaveBuffer`), the listing's drawn
  also while vim is in the path field. In the listing they follow the
  entries' IDs when it's shown again (`listingSpot`'s `marks`, which
  `showListing` gives `Vim.markTexts`): a sort or `:set hidden` moves
  every line, and a file or the scratchpad shows something else in the
  editor. They're drawn like a selection of lines in `theme.marked` (the
  selection's color, paler: they aren't what the cursor selects), under
  visual mode's selection, and from `visualShown` while `:` is typed.
- **Hidden text**: an icon (any one character; in the listing, a file's
  icon, hiding its ID) can hide some text. The document holds the plain
  icon, and `vim.hidden` keeps the text as `{ at, icon, text }` entries
  sorted by position (`at` is a UTF-16 index). Only text the editor is given
  has entries (`vim.reset(entries)`, `vim.replaceText`); the user can't hide
  or reveal text, and an icon without an entry is a plain character. The
  tests use 🍄 and 🪑. `hidden` is replaced, never changed in place, so a reference is a
  snapshot (undo relies on this).
  - Vim's own edits go through `replaceRange(start, end, text, entries)`, which
    shifts the entries (`shiftHidden`): one whose icon the edit touches is
    dropped, `entries` (the inserted text's) are added. Callers that insert
    text with icons pass its entries (paste, undo/redo, replace-mode
    Backspace); ones that rewrite text in place (`~`, `gu`, `>`) pass
    `carriedHidden`, which matches the k-th 🍄 of the old text with the k-th
    🍄 of the new one (likewise 🪑).
  - The editor's own edits (typing, IME, Delete) arrive only as
    `textChanged`: `trackEdit` diffs against `trackedText` and applies the
    changed span. Both skip all of this while there are no entries or cursors.
  - Undo stores each change as a span found by `diff`, which also compares
    entries (icon and text), since deleting either of two identical icons
    gives the same text. Registers, undo steps and the clipboard carry the
    entries for their text (`at` from its start; `hiddenIn` takes the entries
    whose whole icon is in a range, `shifted` moves them). Being sorted, they
    are found by binary search (`firstAt`), not by going over all of them
    (a listing has one per line). `diff` compares slices rather than
    characters (V4 makes a string of each character it indexes), and undo
    steps and registers keep their text through `own`: V4's `slice` keeps
    the whole string it was cut from until the slice is read.
  - The `"+` register (and Cmd+C/X/V in every mode) writes the text as
    shown, icons and all, for other apps (an ID means nothing outside
    Koil), and JSON
    `{ text, hidden, block, session }` as `application/x-koil-data`, which
    Koil reads back (`validHidden` checks it first: any app can write the
    clipboard; see Clipboard under Koil for `session`).
  - Qt's native Backspace deletes one code point, so vim handles Backspace in
    insert mode, and cursor steps go through `Txt.charStart`/`charEnd` (never
    `±1`), which treat an emoji with its modifiers as one character, as Qt
    does. Columns count characters (`Txt.column`, `Txt.atColumn`).
  - Resting the mouse on an icon (a `HoverHandler`) or `gh` (in the listing,
    on the icon of the cursor's line, unless a problem is under the cursor)
    shows its text in the `HoverBox`, in the window's `Overlay` (so the
    editor doesn't clip it).
    Its text is a read-only `TextEdit` that never takes focus, so keys stay
    with the editor, which forwards Copy to it. Any other key, a scroll or an
    edit hides it; one the mouse opened also hides 300 ms after the pointer is
    on neither the target nor the box (and isn't dragging a selection).
- **Warnings and errors** (`diagnostics` in Editor.qml): Koil's problems
  (see Koil) get a VS Code-style squiggle in the visible lines, and their
  line shows a message after its end (an error's before a warning's), and
  after its note, if it has one. The hover box shows the message (with an
  icon) as it does an icon's text; `targetUnder` also finds the message
  after the line.
- **Notes after lines** (`aside` in Editor.qml): the notes (`infos`) and
  the messages go in a column each, like a table, at least four spaces
  after what's before them. A column is where the most of them are and
  still end in view (`Txt.inLine`: one of their own columns, right after
  the line), so a line too long for it has its own after its end, and so
  does one that would end past the view's edge if it went in line (a long
  message), which the view then scrolls to (`widest`, the column the last
  of them ends at, makes `sideScrollRoom`; a click there goes to the
  line's end, and the hover box shows a message there, through a
  `MouseArea` of its own, as the room isn't the editor's). They're worked
  out over all the text
  (`aside.refresh`, counting a column per code point, `Txt.columns`, as
  `Txt.column` is too slow for all of a long listing), so they don't move
  as it scrolls, but whenever it changes, or the notes, the problems or the
  view's width do; the overlays then place the lines in view
  (`aside.spots`), never over what's before them (an emoji wider than a
  column). While lines wrap, they go after a line's last row, and the
  view doesn't scroll to them (see Wrapping).
- **Quitting**: `:q` with unsaved changes fails (E37); `:confirm q` asks
  instead, in a `ConfirmDialog` rather than a `MessageDialog` (which is native
  on macOS, can't use the editor's font or vim's keys). `ConfirmDialog.ask`
  takes what Yes and No do; without a No action it offers only [Y]es/(N)o.
  Every file shown has a path, so with none (nothing is shown: the home
  dir couldn't be listed) `:w` is vim's E32.
- **Surround** (Surround in Vim.qml, `parseSurround`): vim-surround's keys,
  `ys{motion}{pair}` (`yss` the line, after its indent), `ds{target}`,
  `cs{target}{pair}` and `S{pair}` in visual mode, which takes the place of
  vim's visual `S` (change lines; marked lines' `S` is still that, as
  marked lines are normal mode, which vim-surround leaves `S` to). `yS`,
  `ySS`, `cS` and `S` on lines (`gS` on characters) put the pair on lines
  of its own and what's inside a level deeper, as `>` indents it
  (`wrapEdits`), then for brackets and tags reindent what's inside and
  the closing line as `=` does (`surroundWith`), as vim-surround's
  `'[=']` does: not for a quote or a sign, which `=` knows nothing of, so
  it keeps the `>`'s level. A linewise motion and `gS` on lines put it on
  lines of its own, not deeper, and nothing is reindented (vim-surround
  reindents only with a language's indent). Pairs (`surroundPair`)
  and targets (`surroundTarget`) are vim-surround's, but for `p`, `s` as a
  target, `f`, `<C-t>` and `/` as a comment: `/` is a sign like `*`. A
  parsed one is an action, `surround`, with `cmd.surround` holding its
  motion or text object (so `execute` doesn't take it for a motion), and
  runs at every cursor; `operatorRange` (out of `executeOperator`) gives
  the range `ys` goes over. Each is one `replaceRanges` of the pair's
  spans only, so the hidden text inside stays, and none touches a
  register (vim-surround puts its own back). Over lines, `ds` takes a
  bracket alone on its line away with its line (`ysip)` then `ds)` gives
  the paragraph back), and a pair's space inside isn't put next to a line
  break (`cs)(` on a block that's on its own lines). A tag (`<` or `t`) is
  asked for in the command line, as its kind `"<"` (`askTag`, with its
  own history; `>` ends it as Enter does, as vim-surround's `cnoremap`),
  before anything changes, so Esc leaves no undo step, and the command
  runs again with `surround.tag` (`finishTag`), which `.` then repeats
  without asking. From visual mode, it keeps the selection
  (`surround.selection`, drawn as `visualShown` meanwhile), and isn't
  repeated, as visual commands aren't.
- **Reindent** (`=`, `Txt.reindent`): vim's `=` operator (`==`, `=ip`,
  visual mode, marked lines), as its C-indenting does without a language,
  but by brackets and tags only: a line in them goes a level deeper than
  the line the innermost opens on (only the first still open on a line
  makes a level: `foo({` is one), one starting by closing them as deep as
  the line the outermost it closes opens on, and a blank line has none.
  A line in none keeps its indent, so Python, YAML and Markdown, whose
  levels brackets don't show, aren't flattened (vim's `gg=G` puts every
  top-level line at column 0). Brackets in strings and comments don't
  count, read as syntax.rs reads them (`'` as an apostrophe or a
  lifetime's isn't a string; no `//` in Python, by `fileName`), and only
  tags with a closing tag of their name count (`pairedTags`), so
  `List<String>` and `<br>` don't. It reads from the text's start, as a
  bracket that's open can be anywhere above (0.3 s for 120,000 lines),
  jumping between the characters that can start something with a regex
  (`signs`). A level is the text's (`indentUnit`): a tab if most indented
  lines start with one, else 2, 4 or 8 spaces, the step lines most often
  go in by, if twice or more (a text to reindent can have one stray), else
  4; surround's levels use it too, `>` doesn't.
- **Substitute** (`:s`, Substitute in Vim.qml): vim's, with `/`'s patterns
  (JavaScript regexes, smart case unless the `i` or `I` flag says) through
  the text without its prefixes, as a search (a line starts at its name,
  and a line a replacement starts gets one: `prefixLines`), and vim's
  replacement (`Txt.substitution`: `&`, `\1`, `\u`, `\r`; but `~` is only
  a `~`, which paths have). Flags `g`, `i`, `I`, `n`, `e`, `&` first
  keeping the last one's; `:s` alone, `:&`, `:&&`, `&` (`:&&`, as
  Neovim's) and `g&` run `lastSubstitute` again. With the range `'<,'>` it keeps to the last
  selection (`selectionRegion`: its characters or block, where vim's takes
  the lines), whose `wantCol` `lastVisual` keeps for a `$` block. Typed,
  it's previewed as neovim's `inccommand` does (`previewSubstitute`, at
  every `commandLine` change): the matches it would replace are
  highlighted (`substitution.spans`, which `searchHighlights` and
  `previewSearch`'s view use), and once the replacement's delimiter is
  typed, the buffer itself shows the result, made at each key from the
  text as it was (`substitution.before`, put back first in the same batch,
  so the editor gets one edit). A replacement that shows nothing (empty,
  or only line breaks) is highlighted as a thin line where it is
  (`addHighlight`'s `thin`: an empty span, which Editor.qml draws as
  wide as the insert bar, a little shorter than the line, so ones above
  each other stay apart), so it's still seen. The cursor, and the
  selection `:` left visual mode with (`visualShown`, drawn while the
  command line is open, as in vim), stay on their characters through it
  (`previewedAt`). Qt lays out again every line an edit changes (400 ms a
  key for 20,000 lines), so only the matches `previewMargin` (500) lines
  or less from the view are replaced (`previewWindow`), and the others
  are highlighted as they are.
  The command line closing puts the text back, and Enter then runs it, as
  one change. Not for a macro's keys (`inChunk`). The preview isn't the
  user's text: main.qml works out `modified` from the text before it
  (`usersText`, the substitution's `before`), and `previewing` is in
  `boxOpen` (nothing syncs, drops or saves meanwhile); `updateListing`
  ends it first (`endPreview`: an option button updates), and `reset`
  drops it without putting the text back, as the new text replaced it.
- **Command line colors** (`Vim.commandLineParts`, `commandLineHtml` in
  StatusLine.qml, `theme.commandColor`): as a `:` command is typed, the status
  line colors its range, the name of a command `runEx` knows
  (`exCommands`, `substituteNames`, `!`, `_!`), a shell command's `%` and `<cfile>` with
  their modifiers (in the dirs' color, as a path) and `\%` and
  `\<cfile>`, `:set`'s options and `:e`'s
  path. It's styled text (`<font color>`), where spaces are `&nbsp;`, as
  styled text runs spaces together; the cursor block is measured on the
  plain text, which is as wide in a font of one width. A new command goes
  in `exCommands`, which both `runEx` and the colors read.
- **Find bar**: moving to a match moves vim's cursor to its start
  (`vim.jumpTo`, which leaves visual mode and breaks an insert); it doesn't
  select it. Its regex option (`useRegex`) is on at first, so Find's seed
  goes in escaped. The current match is the one starting at the cursor
  (`currentStart`), however the cursor got there. Its matches take over the
  search highlights while it's open; Esc in normal mode (`highlightsCleared`)
  closes it. Replace All is one `replaceRange` over the first to last match,
  keeping the hidden text between matches (`vim.substituted`, as `:s`).
  While the replace field has the keys (`previewShown`), the buffer shows
  what Replace All would make of it, as `:s`'s preview does
  (`vim.previewReplacements`, a `substitution` with `findBar` set), the
  replacements highlighted; in the find field the matches are only
  highlighted. Whatever the bar does (find, move, replace, undo, an
  option) is done on the text without it (`unpreviewed`: put back first,
  `endReplacements`, then shown again, in one batch, so the editor gets
  one edit), and `matches` are that text's. Whatever else edits or moves
  vim puts it back first (`toNormal`, `jumpTo`, `externalEdit`,
  `nativeUndo`, and a press on the editor, whose `TextArea` moves its
  cursor before it takes the keys), and the bar shows it again if the
  field still has them (`onPreviewingChanged`). A Replace there can leave
  the editor's text as it was (the preview showed it already), so
  main.qml checks `modified` again as the substitution changes. On
  Windows, Ctrl+F is Find, not
  vim's page down. Each field keeps a history (`Field.remember`: the newest
  100, until Koil quits) of what it had when it was used (a match moved to,
  a replace, the bar closed, or a query replaced by Find's seed), and Up
  and Down put those back (`browse`) as the path history does, apart from
  vim's `/` history (the bar's query isn't a vim pattern). Find in
  Selection (Cmd+Option+L, Alt+L elsewhere, as in VS Code) keeps it to
  `vim.findScope`, spans as `:'<,'>s` keeps to (`selectionScope`: the
  selection, else the marked lines, which it unmarks as a command does,
  else `lastVisual`; a `V` selection's lines from the first's start to the
  last's end), and finds as `:'<,'>s` does too (`inRegion`), so `^` is
  only where a line starts. It's on at once when the bar opens with a
  selection that can't be the query (over lines, a block, marked lines),
  as VS Code's `autoFindInSelection: multiline`, and off when it closes.
  Opening the bar takes the editor's keys, which drops its selection, so
  leaving visual mode that way (`syncFromEditor`), as by `jumpTo`, keeps
  it in `lastVisual`, as vim does whichever way visual mode ends. Edits
  move the spans (`moveScope`, from `replaceRange` and `trackEdit`), and
  text put in at their edges goes in them, so undoing a Replace All puts
  its first and last matches back in. They're the buffer's only
  (`leaveBuffer` drops them), and drawn in `theme.findScope`, under the
  marked lines.
- **Theme and zoom**: `Theme` (one, in main.qml, passed to every control)
  takes its colors from the editor's palette, so they follow the light or dark
  theme. When the theme changes, a `Palette` emits only `changed`, not its
  per-color signals, so a binding on `palette.base` keeps the old color;
  `Theme` copies the colors on `changed`, and QML reads them from `theme`
  (`theme.base`, `theme.highlight`), never from a palette. It also holds `zoom` (font size / default). Every text in the app grows
  and shrinks with View > Zoom (Cmd+ / Cmd- / Cmd+0), not just the editor:
  text in the editor's font uses `theme.font`, other UI scales its sizes by
  `theme.zoom`. Both are in pixels (`fontSize` too: `font.pixelSize`): in
  points, Windows' 96 dpi (macOS's 72 makes them the same) made the editor
  a third bigger next to the UI. New UI must do the same, and use `Panel` for a box over the
  editor, `Tip` for tooltips (keys that do the same go in its
  `shortcuts`, each shown as code, not in the text; other keys, commands
  like `:set wrap` and file names go in its text in backquotes, which
  `CodeLabel` shows as the help does: `Txt.parseCode`, `Txt.codeHtml`, and
  a shade a line behind each) and `IconButton` for small buttons.
- **Overlays** (Editor.qml): the carets, selection, highlights and squiggles
  are each a `Layer`, which recomputes its model with Qt.callLater once its
  `inputs` change (`view.layout` for the text and its layout, `view.viewport`
  for scrolling), so after an edit rather than halfway through one (while
  `editor.remove()` runs, the document is already shorter but
  `editor.length` isn't updated, and asking for a position then warns). A
  `Layer` empties its model first, because a Repeater keeps delegates whose
  model data didn't change, and their rectangles must be recomputed after a
  relayout. Nothing drawn may depend on `editor.text` directly, or it
  recomputes in the middle of an edit. The carets are declared after the
  search highlights, so they're drawn over them.
- **Line height**: emoji come from a taller font and would make their line
  taller, so `fixLineFormat` gives every block a fixed height (a block format;
  Qt counts it as an edit, so `quiet` keeps it from marking the file
  modified). Setting the `TextArea`'s text resets it, so `setText` goes
  through `System.setText`, which puts the text in with the format (see Long
  texts); `quiet` also keeps its cursor moves from vim (`syncFromEditor`
  would read the old `text`, which Qt updates after, and ask for a position
  past the new one's end), which starts over after it. Qt puts a fixed-height line's baseline at 4/5 of
  it, so to center the text the block gets a shorter line plus a bottom margin
  that makes up `lineHeight` (`textBaseline` is where the baseline ends up).
  Qt keeps both in 64ths of a pixel and drops the rest, so the line's height
  is rounded down to one: else each line comes out a 64th short, and in a
  10,000-line file the text drifts lines away from the overlays.
  Qt's selection and `positionToRectangle` still use the natural (taller)
  height on emoji lines, so the selection is drawn by the app (under the text,
  `z: -0.5`), and all overlays use `cellAt` (the whole line, snapped to the
  line grid). The current-line highlight is at `z: -0.6`.
- **Long texts**: a `TextEdit` with over 10,000 characters builds only the
  lines in view (`ItemObservesViewport`), and after a change builds again
  from where those started, so a new text that ends before that shows none
  of it (`-` from the end of a long file showed an empty listing until the
  cursor moved). Turning that off would cost ~130 ms per 10,000 lines on
  every open and zoom, so `setText` calls `System.redrawText` first, which
  runs Qt's `q_invalidate` slot (what it runs when fonts change: build
  everything again) on the window's `afterAnimating`, right before the
  frame is synced, since a change after it (text, colors, selection) would
  ask for the changed lines only again.
  Qt decides whether a text is long only when it's set, so one that grew
  long by edits (a paste of 100,000 lines) had all its lines built, and
  each key took seconds (`j` 1.7 s, against 80 ms in the same text
  opened). So Editor.qml calls `System.followTextLength` after every
  change, which decides it by the length, and has Qt build the lines
  again: those in view (`updateWholeDocument`, which a short text's lines,
  built from its start, allow), or for a text that's short now, all of
  them from scratch (`q_invalidate`, as its built lines may start far past
  its end).
  Qt lays out all of a text again (about a second for 100,000 lines) when
  it or its format changes, and when the editor's width or padding does,
  as the text's width changes with it (even without wrapping). So opening
  one makes it once: `System.setText` replaces the text and gives every
  line its format in one edit block (setting the text the `TextArea`'s way
  and then the format laid it out twice; emptying it first hid the scroll
  bar, which changed the width), clearing the document in it (a selection
  removed stays in its buffer, where Qt's positions are ints: a gigabyte
  opened again after the listing went past them and crashed), the gutter
  gets its width before the text
  (`gutter.fit`), and a file on the command line opens after the editor's
  `onCompleted`, which adds the gutter's padding. A window resize still
  lays it out again, and so does the scroll bar showing up on macOS, whose
  style makes room for it (Fusion draws it over the text): keeping that
  room even without one saved most of a second, but left a strip the text
  didn't reach.
  Qt's `TextArea` clips its text to the view as it was when it last drew
  (`QQuickTextArea::updatePaintNode`), and a resize doesn't make it draw
  when the text overflows the view both ways, so the window made bigger
  showed none of a short text past the old edges (a long one draws again
  as the view changes). Editor.qml calls `editor.update()` when the
  view's size changes.
  Each read of `text` makes a new string of all of it (`toPlainText`: 100 ms
  for 54 MB), and V4 compares two strings by hashing all of both, unless
  they're the same one (an `===` of a long text took tens of milliseconds,
  many times a key). So the TextArea keeps its text as one string a change
  (`latest.text`, in an object: writing a long string to a property took as
  long), which everything reads (vim's `editorText`): the one before with
  what changed in it (`System.takeTextChange`, what `TextChanges` saw of
  `contentsChange` since, as `toPlainText` gives it), or vim's text after
  its edit (`latest.expected`, unless Qt changes what goes in: a `\r`, a
  no-break space), or `text` if that doesn't add up. `setText` gives its
  string as `expected` too, if Qt keeps it as it is (`System.keptAsIs`),
  and then the change's text isn't made at all (`takeTextChange`'s
  `withText`): making it, and then comparing the copy with the string
  `setText` had indexed, took 5 s of opening a gigabyte. Vim's edit is
  one Qt edit (`replaceInEditor`, `System.replaceText`), not a remove and
  an insert, between which the text was made for QML too. Whatever reads
  all the text reads `latest.text` (the hover, saves, the find bar through
  `vim.editorText`): reading `text` on every move of the pointer took 2 s
  in a gigabyte. Changes only to the format (`formatting` in Editor.qml,
  `FormatOnly` in native.cpp: the line format, the colors, Koil's
  margins) leave it alone. Txt's line index takes
  the string it's asked with (`lineIndex`), if it's the same string, not
  only the same text, which `System.sameString` tells by its data in O(1)
  (`Txt.compareStringsWith`; `===` in the tests): vim's text during a key
  and the editor's are as long after `r`, and `===` hashed both, seconds a
  key. An edit carries the line starts found past it (`Txt.carryLines`),
  so the text isn't looked through again (0.5 s a key at the end of a
  gigabyte). `isEdited` compares texts with `System.sameText`, which stops
  at the first difference. A gigabyte still takes a second or two an edit:
  V4 copies all of the string to make the new one (slices and their
  concatenation), which only a text that isn't one JS string would avoid.
  `Txt.column` and `atColumn` count a code unit a character up to the
  first that may not be one (`mayAttach`, found by a regex), as a long line
  took seconds.
- **Long lines** (`LongLines` in native.cpp, `longText` in Editor.qml): a
  `TextEdit` builds only the lines in view, but all of each, so Qt shaped
  every character of a line in view (300 ns each, again when the text's
  width changed) and put a glyph of each in the scene graph: `big` (52 lines
  of a megabyte) took a minute to show and seconds an edit. A line longer
  than `longLength` (10,000) is hidden from Qt (`QTextBlock::setVisible`,
  set in `contentsChange`, before Qt lays it out), which then never lays it
  out or draws it, and the line after hidden ones gets a top margin as tall
  as their rows (the text's end, a bottom margin of the root frame), so the
  lines Qt lays out stay on the grid (`placeLongLines`, after each change,
  around it). Each has the bottom margin of the line Qt laid out before
  them too, which Qt adds only before a next line it lays out: without it
  at the text's end, a long last line ended past the text, and Qt's guard
  in `ensureCursorVisible` (as far as the content goes) didn't scroll to
  it. Koil places a hidden line's characters, a column a UTF-16
  unit, `rowLength` a row while lines wrap (anywhere): `longLineSpot` and
  `longLinePosition`, which the TextArea's `rectAt` and `posAt` give in
  place of `positionToRectangle` and `positionAt` (vim's and the overlays'
  go through them), and draws only what's in view of them (`longText`, a
  `Text` a run of one color, from `TextColors`'s formats: `longLineRuns`; a
  tab is a space). Qt's cursor rectangle in a hidden line is at the text's
  start, so its TextArea mustn't scroll to it: its private
  `ensureCursorVisible` is disconnected (`scrollToCursorInQml`), and
  Editor.qml's does the same (QML handlers run before C++ slots anyway),
  with Koil's rectangle in a hidden line; Qt hides its cursor delegate when
  that rectangle is out of view, so there `carets` draws the insert bar, and
  a press on one (and its drag) is Koil's (the `MouseArea`). Qt builds again
  only the lines a selection touches, and past a hidden line put the lines
  after it too far down (it takes an empty node, where it skipped the hidden
  line, as the next one's place), so a selection change has it build all the
  lines in view (`rebuildTextNodes`). Placed while Qt resized the TextArea,
  the margins' height went nowhere (its `updateSize` guards against itself),
  so a resize places them after. The matching bracket is looked for at most
  `reach` characters away. A `QTextCursor` lays out the line it's put in to
  find its x, so native.cpp reads text with `characterAt` and blocks' text
  (`textBetween`). `big` shows in half a second, and an edit takes 0.1 to
  0.3 s, mostly V4 copying all 54 MB.
- **Wrapping** (`:set wrap`, a vim setting the Settings window saves, and
  View > Word Wrap, Alt+Z as in VS Code; never in the path field:
  `Editor.wrapping`, `Vim.wrapping`): a line too long for the view goes on
  in rows under it, at a word's start in a file (`TextEdit.Wrap`), but
  anywhere in the listing (`WrapAnywhere`, as vim wraps oil.nvim's): at a
  word's start, a name of one long word left its icon alone on a row.
  The wrap mode goes in with the text (`setText` empties the editor
  first, a file after the listing), not as a binding, which laid out the
  old text again in the new mode (`applyWrapMode`). Qt gives each of a
  wrapped line's rows the format's fixed height, and its bottom margin
  after the last (`layoutBlock`), so while lines wrap, `lineFormat` makes
  rows `lineHeight` tall with no margin. Qt then puts the baseline at 4/5
  of a row, below `textBaseline`, so the rows start lower, by
  `textShift` (`textTop`, the grid's top, which `cellAt` and vim's
  `textTop` use): moving the text up by its padding instead made the
  style's `implicitHeight` a binding loop. In the listing, a name's rows
  after its first start under it, not under its icon (a hanging indent:
  the blocks' left margin, and as much text indent taken off), and with
  notes (sorted by size or a date) none reaches into the notes' room on
  the right (`noteRoom`, the blocks' right margin), so each note fits
  after its line, lined up as in a table. Qt fits a `TextArea` to its
  view's width only as the view or the text's size changes, which a new
  wrap mode doesn't do, so `fitWidth` gives it the width. On macOS the
  vertical scroll bar is `AlwaysOn` while lines wrap: one showing up
  narrowed the view inside Qt's own resize, whose new size Qt doesn't
  tell then (`contentSizeChanged`), which left the content a row short.
  The overlays draw a span in a part a row (`rowSpans`, finding where
  rows start by `cellAt`, only those in view: a line can have thousands),
  the current line's band covers all its rows, a line number is on its
  first row, and the notes and messages after its last, cut off at the
  view's edge (`asideWidth`), as the view doesn't scroll sideways then
  (its `Flickable` is `VerticalFlick`, `maxScrollX` is 0, and `zh` and the
  like do nothing, as in vim). Vim counts rows where it counted the lines
  in view (`rowRect`, `rowOf`, `rowStart`): H, M and L go to the lines
  that start and end in view, Ctrl-E and Ctrl-Y scroll rows, and the page
  keys move the cursor as many rows (`rowMotion`), as `gj` and `gk` do,
  which keep to an x in the rows they go through (`rowWant`, while the
  cursor is where they left it), or go to a row's end after `$`. Not
  `positionAt` far right with 1e9, which wrapped round (Qt keeps an x in
  64ths of a pixel, in 32 bits) to the row's start. Toggling it lays all
  the text out twice (the format, then the wrap mode): 10 s for 100,000
  lines in a debug build. `setLineFormat` turns the layout off while it
  applies the format, as `recolor` does: Qt's highlighter colors every line
  again on a format change and laid the document out after each one, so
  turning wrapping off took five minutes in a colored file of 100,000
  lines (a file's `TextColors` doesn't color them again, see Syntax).
- **Line numbers** (`:set nu`/`rnu`): the `gutter` is a child of the
  `TextArea` (so it scrolls with the text), kept at `contentX` and drawn over
  text scrolled under it. The styles hard-code `leftPadding` (7 on macOS,
  `padding + 4` in Fusion), so the editor keeps the style's value and adds the
  gutter width (the digits and two spaces) to it. Only visible lines get a row.
- **Settings**: `settings` (a QtCore `Settings` in main.qml) holds the saved
  values. The ones in use are vim's (`fontSize`, `fontFamily`, `number`,
  `relativeNumber`, `syntax`, `wrap`, `shell`, `dirsFirst`, which `:set`
  changes, as View > Word Wrap does `wrap`: `root.vimSettings`),
  `root.colorScheme`, `root.confirmChanges` and `root.shellEnvironment`
  (see Shell commands), bound to the saved ones at startup. The Settings
  window
  shows the saved ones and changes both (`changeSetting`). The zoom and `:set`
  change only the ones in use, until Koil quits, so the Settings window
  doesn't show them. Their defaults (Cmd+0, `:set fs&`) are the saved values
  (vim's `default*` properties are bound to `settings`), not Koil's defaults.
  Koil's own options (`:set hidden`, `gitignore`, `regex`, `sort`,
  `sortreverse`) aren't saved, and start off (sorted by name). Start in
  (`startDir`, empty for the home dir) is only read at
  startup, with no path on the command line, so the Settings window writes
  it to `settings` alone. It's a dir or pattern as the path field takes it,
  read from the home dir (`Document.startDir`), so it can't open a file;
  the folder button puts a picked one in with `~`. The color scheme sets `Application.styleHints.colorScheme` (Qt 6.8+), which
  also switches the palette, title bar and menus; "system" unsets it. The
  Settings window's size follows the zoom, so it isn't resizable. Its
  settings scroll (`scroller`, a `WheelFlickable`, as a drag selects in a
  field) past
  `maxListHeight` (440 at zoom 1, and never past the screen), with Restore
  Defaults under them, and Tab scrolls to what it goes to
  (`onActiveFocusItemChanged`). The pointer on a setting's name (its
  `SettingLabel`'s `HoverHandler`) shows what it does after a moment, in a
  `Tip` under its row (over it, at the view's end; `rowOf`: GridLayout
  puts the children that show three to a row), from the label's `about`,
  so its note (if any) is a short line. Only the name: anywhere on the row
  (and its note's), a tip showed wherever the pointer rested. They're
  stored in `~/Library/Preferences/com.koil.Koil.plist` on macOS, the registry
  (`HKEY_CURRENT_USER\Software\Koil\Koil`) on Windows.
- **Fonts**: the editor offers only monospaced fonts
  (`System.monospaceFamilies`), since visual block and the overlays count
  columns. A font counts if its Latin text has one width, not by
  `QFontDatabase::isFixedPitch`, which leaves out Nerd Fonts with wide icons
  and is slower. Either way it loads every font (a few hundred ms), so
  `root.fontFamilies` is filled on first use (`loadFontFamilies`: the Settings
  font list, or `:set gfn` via `vim.fontFamiliesNeeded`). The Settings font
  picker is a field that searches, with the list in a `Popup.Window` (so the
  Settings window doesn't cut it off); the field keeps the keys, but the popup
  takes Esc, so it closes on Esc itself.
- **Help** (HelpPanel.qml): every text in it is a `CodeText`, rich text whose
  `` `code` `` (in the keys column, a key) is in the editor's font, on a shade
  drawn behind the text (`place`), so it still selects and copies. Rich
  text has no inline padding, so letter spacing on the character before a
  code and on its last one makes room for the shade (and copies as
  nothing), and a code's spaces are no-break ones (copied as spaces). Its
  search is vim's (`Txt.searchRegExp`, so smart case), over each text as
  shown (`searchTexts`, keyed by section and part), from the match it went
  to last if that's in view, else from the top of the view; Esc clears the
  highlights before it closes the help. A text's matches (`matchMarks`, a
  string per key, so only texts whose matches change are made again) are
  drawn behind it in the editor's colors (`theme.searchMatch`), and made
  black in its rich text. The Repeater deletes old texts some time after
  `shownSections` changes, so a text takes marks only if search went
  through its text (an old one has a new one's key). It must keep the keys
  while it's open, or it stays open with no key reaching it to close it:
  Find, Replace and Find Next/Previous go to its search (`root.find`,
  `root.findNext`), the menu's items that open, save or edit something
  are off while it or a question is open (`boxOpen`), syncing waits (it
  can switch vim's buffer), and if anything else still takes the keys it
  closes (`keepHelpKeys`, leaving them there: `hadKeys`). `:h topic`
  (`show`) goes to the section whose `tags` have it, as typed first (so
  `gI` isn't `gi`), then in any case, and scrolls to its row of that key
  if it has one (`shownRow`, `keyRow`: a code in the row's keys, `:h gs`);
  a topic no section has goes to the first row with that key (`:h J`),
  again as typed first. `<C-a>`, `^A` and `CTRL-A` are `Ctrl-A`. The keys
  starting with `g`, `z` and Space, and the Ctrl keys, have sections of
  their own (`:h g`, `:h z`, `:h space`, `:h ctrl`), as an index of them,
  pointing to the sections that say more.
- **Scrolling boxes**: the help, the hover box, the confirmations and the
  settings are `WheelFlickable`s: `Flickable`s that aren't interactive (a
  drag selects their text), scrolled by a `WheelHandler`. It needs
  `acceptedDevices` with
  `PointerDevice.TouchPad`: by default it takes only a mouse wheel, and the
  trackpad's scrolls go to the popup, which drops them.
- **QML's JavaScript**: don't make a binding depend on something by reading it
  as a bare statement (`editor.revision;`): the app's QML is compiled ahead of
  time, which can drop it, though `qmltestrunner` keeps it. Use the value. The
  engine has no `Array.prototype.flatMap` nor `String.prototype.trimEnd`;
  `?.` and `??` work. A `Set` takes time in proportion to its size for
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
  a setup `.exe` (windows-latest) on every push. `v*` tags also publish a
  GitHub release. It doesn't run the tests.
- The Qt version is pinned per OS. macOS uses 6.11, because 6.8's headers fail
  with newer Apple clang. Windows uses 6.10, because Qt 6.11 for Windows uses a
  repository layout that aqtinstall 3.3 can't read. Move Windows up once
  aqtinstall supports it.
- Keep actions on Node 24 releases (checkout v7, upload-artifact v7,
  download-artifact v8, action-gh-release v3).
- Releases: `cargo release <level> --execute`. `Cargo.toml` makes it skip
  crates.io (`publish = false`) and run only on `main`, and it needs a clean
  working tree.
