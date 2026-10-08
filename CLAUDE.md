# CLAUDE.md

Koil desktop app: a vim-style editor in Rust + Qt 6 via cxx-qt 0.10, with the
UI in QML, that edits a directory as text (like oil.nvim) through koil-core
(`../koil-core`, a library; `../koil-cli` is its CLI; read their CLAUDE.md for
how Koil works). The editor is the one from `~/projects/vim-edit`, cleaned up.
It shows Koil's listing (see Koil), a file opened with File > Open, or
the scratchpad (see Scratchpad).

## Layout

- `src/main.rs`: creates the app, installs the "Settings…" translator, the
  Nerd Font and the window icon, sets the Windows style, loads
  `qml/main.qml`.
- `src/listing.rs`: the listing as text, without Qt: `render`, `parse`,
  `check`, `update` (read it into koil, then navigate), the confirmations'
  lines (`actions`, `history`), the path field's regex parts
  (`path_syntax`), what Tab completes in it (`complete`), what's shown after
  each line when sorted by size or a date (`notes`), and what changed on
  disk as edits to the text and questions (`sync`, `resolve`, `merge`).
  Its tests (`src/listing/tests.rs`) use a temp dir.
- `src/history.rs`: `History`, the undo history kept in a file across
  sessions (see Undo history). Its tests (`src/history/tests.rs`) use a
  temp dir.
- `src/sizes.rs`: `Sizes`, which counts the sizes of dirs on its own
  threads and keeps them (see Kept sizes). Its tests
  (`src/sizes/tests.rs`) use a temp dir.
- `src/koil.rs`: `Koil` (QML element): wraps `koil_core::Koil` and calls
  listing.rs, taking and giving JSON. `showHidden`, `gitignore`, `regex`,
  `sort` and `sortReverse` are properties, bound to vim's `:set` options.
  It also watches the disk (`watch`, `changedOnDisk`; see Changes on disk),
  and counts dirs' sizes (`sizes`, `dirSizes`; see Sorting).
- `src/document.rs`: `Document` (QML element): reading and writing files, the
  path on the command line.
- `src/system.rs`: `System` (QML element): the system clipboard, the
  installed monospaced fonts and the Nerd Font's family, and the editor's
  text, line format and colors.
- `src/ffi.rs` + `cpp/native.{h,cpp}`: the C++ helpers behind `System` and
  `main.rs` (menu title translator, Controls style, clipboard, fonts, the
  Nerd Font, the window icon, files macOS asks to open, line format,
  `setText`, the listing's and path field's `QSyntaxHighlighter`, and the
  confirmations' (`setKeywordColors`), `redrawText`).
- `qml/main.qml`: the window: settings, menus, dialogs, status line, the
  path field and its option buttons, and Koil's listing (`showListing`,
  `updateListing`, `applyChanges`, `undoApply`), a file (`loadFile`) or
  the scratchpad (`openScratch`), and which of the two editors vim edits (`activate`). It wires the pieces
  together; no editing logic lives here.
- `qml/Editor.qml`: the `TextArea` in a `ScrollView`, and everything drawn
  with it: cursors, selection, search highlights, the notes after lines
  (`infos`, see Sorting), warnings and errors, line numbers, the `HoverBox`
  and the `CompletionList`. Both the listing (or
  file) and the path field are one (`pathField`).
- `qml/HoverBox.qml`: the VS Code-style box that shows what an icon hides (an
  ID, as its path), or a warning's or error's message.
- `qml/CompletionList.qml`: the dirs Tab can complete the path field to, in
  a box under it, like VS Code's suggestions (see Completion).
- `qml/SortMenu.qml`: what `gs` and a key sort the listing by, in a box
  under the sort button (see Sorting).
- `qml/Vim.qml`: the vim emulation (modes, motions, operators, registers,
  undo, macros, visual block, multiple cursors, hidden text, the listing's
  prefixes, `:` and `/`, buffers). It drives the `TextArea` through
  `insert`/`remove`/`select`.
- `qml/text.js`: pure text helpers (lines, characters, words, text objects),
  imported as `Txt` by Vim.qml and the views. The only state it keeps is
  where the lines of the last two long texts start (`lineIndex`), so
  `lineOf`, `lineToPos` and `countLines` (the status line, line numbers,
  highlights) don't go through the text each time.
- `qml/FindBar.qml`: the find and replace bar (Cmd+F, Cmd+Option+F).
- `qml/HelpPanel.qml`: `:help` (`:h topic`), a box listing what isn't obvious;
  `:reg` shows the registers in it (`showList`). `/` and `?` search it (see
  Help).
- `qml/ConfirmDialog.qml`: the [Y]es/(N)o/(C)ancel box, with a list under
  the question: `:confirm q`, applying and undoing (lists to pick from),
  and what changed on disk against the user's edits.
- `qml/SettingsWindow.qml`: the Settings window (Cmd+,).
- `qml/Theme.qml`, `Panel.qml`, `Tip.qml`, `Icon.qml`, `IconButton.qml`: the
  look the app's own controls share (see Theme).
- `tests/tst_vim.qml`: qmltestrunner tests for Vim.qml, the find bar and the
  help's search.
- `scripts/`: `bundle-macos.sh` (makes the `.app`), `package-macos.sh` (the
  `.dmg`), `package-windows.ps1` (windeployqt, then the Inno Setup
  installer), `make-icons.sh` (the icons, from `packaging/icon.png`).
- `packaging/`: `icon.png` (the app's icon) and the icons made from it
  (committed, so building needs no ImageMagick): `macos/Koil.icns`,
  `windows/koil.ico` (in the exe through `koil.rc`, which `build.rs`
  compiles with `embed-resource`) and `window-icon.png` (see App icon);
  `macos/Info.plist` (with a `@VERSION@` placeholder) and
  `windows/installer.iss`.
- `fonts/`: the Nerd Font Koil ships (see Icon font) and its license.

## Build and test

- Local Qt comes from Homebrew (`qtbase`, `qtdeclarative`); `qmake` must be on
  `PATH`. `cargo build`, `cargo run` (lists the home dir, or the
  Start in setting's), `cargo run -- dir`
  (or a pattern), `cargo run -- file` to open a file. Try applying in a
  scratch dir: it really moves and trashes files.
- `cargo test` runs listing.rs's tests; `cargo clippy --all-targets`,
  `cargo fmt`.
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
  `Document` and `System`; `Editor` takes `System` as a `var`).
- `qmllint -I target/cxxqt/qml_modules qml/*.qml` should print nothing.
  cxx-qt-build writes `.qmlls.ini` (ignored by git) for qmlls.
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
  lines that have none (`prefixLines`); `J`, `gJ` and Delete at a line's
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
  find bar skip matches that start in a prefix. The status line's columns
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
  its last `/`) can be, in the dir before it, read as `open` reads it: not
  hidden ones unless the part starts with `.` or `:set hidden` is on, not
  ignored ones with `gitignore`, new dirs in the diff too, `..` for `.`, and
  ignoring case unless the part has an uppercase letter (smart case, as
  search does: `k` gives `Koil` too). Tab fills in the only one
  (with its `/`, which steps over a `/` right after the cursor), or else the
  longest start they share, if that's longer than the part (`fill`).
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
  the applies to undo (see Undo history), `-` opens `..`
  (`3-`: `../../..`), `_` the scratchpad (see Scratchpad), Tab goes to
  the other editor (`activate`), `g.`,
  `gi` and `gr` toggle `:set hidden`, `gitignore` and `regex` (like the
  buttons), and `gs` and a key sort it (see Sorting). Cmd+S (File > Save,
  named Update in the listing) updates.
  Enter in the listing opens the dir or file on its line
  (`listing::target_on_line`: a dir if the name ends with `/`, else the file
  its ID points to on disk, even if the line renames it; a new file is
  created first, see Files); on a line without an entry it's vim's Enter.
  Enter in the
  path field (`openPath`, also from insert mode: see `singleLine`) updates
  and goes to the listing, unless the update fails; Shift+Enter there only
  updates, so vim stays in the field. In a file with a path,
  `-` is Koil's too (`leaveFile`): back to the listing, on the file's line.
  They're only matched at the start of a normal-mode command (so `d-` and
  visual `-` are vim's), with a count; keys that start one and go on
  differently are a bad command (Space l), unless they go on as a name of
  vim's (`gg`, `gU`). Shift+Enter is its own token, `<S-CR>`, a motion like
  `<CR>`, and plain `<CR>` everywhere else (insert mode, the command line),
  but in the path field's insert mode, which hands it to normal mode.
- **Update** (`updateListing`): koil reads the entries with the settings they
  were shown with, then takes vim's `:set hidden/gitignore/regex`, then opens
  the Enter/`-` target, else the path field's path if it changed (like
  koil-cli, where it's the first line). The field is read with the listing
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
- **Apply and undo**: `Space Space`, `:w`, File > Apply Changes… update,
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
  `Koil::undo_only`): `u` or Cmd+Z with nothing left to undo in vim emits
  `nothingToUndo`, and `undoApply` updates (vim's undo may have taken the
  buffer back past an update) and lists the applies (and Enter's
  creates) koil can undo, newest first, in `ConfirmDialog`
  (`listing::history`: each one's time, its dir if it isn't the open one,
  and what undoing it does, up to `SHOWN_STEPS` steps, relative to its
  dir); koil refuses while changes are pending. Not from the path field,
  whose undo history is its own; `Space u` asks at once, from either.
  Only the last apply is picked at first, so Enter undoes what `u` did
  before there was a history. An apply needs the newer ones that changed
  a path it changed, or one in it or that it's in (koil-core's
  `Undoable::needs`), which picking it picks. One that can't be undone
  now (koil-core checks every step against the disk, with what it needs:
  something gone, or taken, or emptied from the trash) says why, has a
  crossed out box (`blocked`) and can't be picked. Yes undoes the picked
  ones, newest first (`Koil.undo(picked)`, indexes into the
  `shown_history` that `history()` kept); a step koil can see won't run
  undoes nothing. Undoing always asks (a `u` too many mustn't change files
  unasked). The history lasts across sessions (`History` in history.rs):
  it's in `history.json` in Koil's data dir (`~/Library/Application
  Support/Koil` on macOS, `%APPDATA%\Koil` on Windows), the newest
  `KEPT` (100), and every Koil running shares it: `History::merge`
  reads the file and merges both ways after anything that changes
  koil's (an apply, a create, an undo, and a sync whose steps followed a
  rename, `merge_changed`), and before the history is shown or undone.
  Applies are told apart by their time, and what both had at the last
  merge (`last`) tells one the other Koil added from one this one undid.
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
  cursor and the view where they were). Back from a file, sorted another
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
  other options.
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
  known or kept start, and every other count stops. The counts take
  turns (`turns`), a dir each, so they all go on at once and small ones
  are done soon, on up to 8 threads that each read a dir at a time
  (reading is mostly waiting for the disk), and stop once no dir is left
  to read and none is being read, which could find more. Counting, a dir's
  note is its size so far with `...` after it (`listing::COUNTING`), and
  its ID is in `busy`; main.qml's `sizeTimer` polls `Koil.dirSizes` every
  300 ms while any is, and Editor.qml shows `infoDots` of the three dots,
  the note's place worked out with all of them (so nothing moves as they
  come and go). The dirs counted go first, by size (`listing::listing`,
  `compare`, which `merge` uses too), and the others after, in koil's
  order. Once they're all counted, `sortCounted` updates (`sortedCounting`:
  it was sorted before they were), keeping the view as for `gs`; not while
  the user is halfway through something (it waits), nor if the update
  would fail on errors or open a path typed in the field (the next update
  sorts it).
- **Kept sizes** (sizes.rs): a count finds the size of every dir in the
  dir counted on its way (`Count::dirs`, each done once the dirs in it
  are, adding itself to the one it's in), and keeps them (`kept`, but
  those that can't be read, and small ones), so a dir listed again, or
  one in it (Enter, `-`), shows its size at once. A small dir (`SMALL`:
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
  it, unless it has files with hard links in it (`Kept::links`: one may
  be elsewhere in the count too), or it's stale. Those count once in each
  dir (`Dir::links`, merged into the dir it's in, a file in both taken
  off once), so a dir's size is the same counted on its own or in
  another. A home dir of 146,000 dirs keeps 40,000 (5 MB; all of them
  took 22 MB), and is counted in 10 s, as fast as before sizes were kept.
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
  count makes the dirs it's in stale as they're done (`Count::changed`,
  `missed`, `gone`: what was read of them may be from before), rather
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
- **Quitting**: `modified` is the file's unsaved changes, or in the listing,
  edits or pending changes (`koil.hasChanges()` after each update). `:q`
  updates first (`unsaved`); `:confirm q` (and `ZZ` in the listing) asks to
  apply the changes, where No quits without them; if the listing can't be
  read (errors, or a path that can't be opened), they ask instead whether
  to quit without them, under the update's error. `:wq` applies, then
  quits; it only fails then, as a write that fails does in vim.
- **Files**: Enter on a file, File > Open (and a file on the command line)
  leave the listing (updating it first, so its edits stay in koil) for a
  plain editor: no colors or problems, only `-` of `commandKeys`, and `:w`
  saves. `-` goes back to what's still open in koil, on `openedFrom` (the
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
- **Scratchpad** (`openScratch`): `_` in the listing (or the path field)
  shows a text of the user's that's never saved, kept until Koil quits.
  It leaves the listing as a file does (updating it first, `fileSpot`),
  and `_` or `-` there goes back (`leaveFile`) to where the cursor was,
  in the path field if it was there (`scratchFromPath`). It's the
  listing's editor, so whatever shows something else in it saves the
  scratchpad's text, cursor, undo history and view first (`keepScratch`,
  from `showListing` and `load`, as anything shown goes through those),
  and `openScratch` gives them back (`vim.enterBuffer`). Its hidden text
  comes back too, on purpose: entries pasted there keep their IDs, as in
  a register, so they can be put aside and pasted back into a listing,
  and `gh` shows their paths. An ID means the same path all session, so
  one pasted back after its file is gone is an error (`NotOnDisk` in
  koil-core), not another file. Edits don't make it modified, `:w` and
  Cmd+S only say it isn't saved, `:wq` and `ZZ` quit as `:q` does
  (`quitApp`: back to the listing while it has changes), and Save As is
  off.
- **Colors** (`setListingColors` in native.cpp): a `QSyntaxHighlighter` on
  the editor's document colors each line's icon (colors from devicons,
  gathered from every listing shown, `iconColors`, dark or light by theme)
  and `/`-ending names (`theme.directory`). It's text-based, so it follows
  edits. A pending entry's icon (one applying would change: new, but not
  `../`, or at a path that isn't its ID's on disk, so renamed, copied or
  moved here; `listing::pending_lines`, from `Koil::is_pending`) is pure white in a dark theme and
  pure black in a light one (`PENDING_COLOR`, sent as `pendingColor`), and
  `listing::apart` moves devicons' colors that come within `APART` of those
  (its white icons, like `vercel.json`'s) a fifth away. main.qml finds the
  pending lines after every edit of the listing (`updatePendingLines`, with
  `Qt.callLater`: halfway through vim's `replaceRange` its hidden text isn't
  up to date, and coloring is a text change to Qt, which would make
  `trackEdit` shift the hidden text again), and the highlighter colors those
  lines' icons (`setPendingLines`). The highlighter is found by object name
  (no moc for native.cpp). Highlighting counts as a text change to Qt (as
  `fixLineFormat` does), so Editor.qml only emits `edited` when the text
  really changed (`lastText`), and `trackEdit` returns at once. Coloring
  again goes through `recolor`: only the lines whose pending state changed,
  nothing if the colors are the same, and as one edit, with layout off for
  more than a few lines (`QSyntaxHighlighter` lays the document out after
  each line, so coloring a 3000-line listing again took a second, and `-`
  out of it two). The path field's document has one too
  (`setPathColors`, `isPath`): all of it in `theme.directory`, and while the
  path is read as a regex (`:set regex` and the path changed, or a regex is
  open), `pathSyntax` gives its parts (`listing::path_syntax`: from where
  `Koil::read_location` says the regex starts, after the longest existing
  dir, at the first part with a special character that isn't quoted),
  drawn over that in `theme.regexColors`.
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
- **Clipboard**: the `"+` data carries `session`, random per run; another
  Koil's hidden texts (IDs, which mean other paths there) are dropped on
  paste, so its lines become new entries rather than copies of whatever has
  that ID here.

## Non-obvious decisions

- **Menus**: QtQuick Controls menus have no `role` property, so macOS uses
  `Qt.labs.platform` MenuBar with `PreferencesRole`/`QuitRole`, which moves the
  items into the app menu. Windows and Linux use an in-window Controls
  `MenuBar`. Both are created in `Component.onCompleted`, so only one exists at
  a time. Qt titles the PreferencesRole item "Preferences..."; a `QTranslator`
  for the `MAC_APPLICATION_MENU` context renames it to "Settings…".
- **Shortcuts**: use `StandardKey` where Qt has a binding. On macOS
  `StandardKey.ZoomIn` also fires on Cmd+=; on Windows it doesn't, so that
  menu uses "Ctrl+=" plus a `Shortcut` for Ctrl++. The Windows/Linux menu
  writes "Ctrl+," and "Ctrl+Q" as plain strings, because `Preferences` and
  `Quit` have no Ctrl binding on Windows. "Ctrl+0" has no `StandardKey`. In
  strings, Qt maps Ctrl to Cmd on macOS.
- **Open With**: Koil offers to open text files but is never their default
  app. On macOS, `Info.plist` claims `public.text` (which source code
  conforms to) at the `Alternate` rank. Files of undeclared types
  (`dyn.*`) can't be offered: Launch Services ignores an `Alternate` claim
  on `public.data`, and a `Default` one makes the app their default. Finder
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
  it only for them). Both give it the path on the command line, without
  taking any extension.
- **App icon**: macOS draws icons as they are, so `Koil.icns` shrinks
  `icon.png`'s rounded square to Apple's grid (824 of 1024 pixels);
  Windows' fills its square. Qt gives windows the exe's `IDI_ICON1` on
  Windows; elsewhere `main.rs` sets `window-icon.png` (the macOS-sized one)
  as the window icon, for Linux and `cargo run` on macOS (its Dock icon;
  the bundle's is the same).
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
  block), which Editor.qml draws. Insert mode uses the `TextArea`'s own cursor
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
  bars, which take room from each other, made a binding loop. Sideways, the
  cursor keeps `:set sidescrolloff` (default 4) columns in view on either
  side wherever it moves (`showColumn`, after Qt's own scroll: `flush`,
  `setCursor`, and typing, a `Qt.callLater`), and at a name's start in the
  listing the whole prefix, so `0` scrolls all the way left. Vim keeps its own undo stack (diffs per change), so native
  undo (Cmd+Z) is routed to it. Only the `"+`/`"*` registers use the system
  clipboard. Registers follow vim's (`setRegister`): `"0` only yanks,
  deletes and changes go in `"1` (shifting to `"9`) or `"-`, and `".`,
  `":`, `"/` and `"%` (`fileName`: the file, or the listing's location)
  are read from vim's state and can't be written. `:reg` (`:di`) lists
  them (`registerList`) in the help box, one line each, cut off. The `TextArea` does nothing on Cmd+Backspace, so on macOS
  it's vim's `<D-BS>`: typed by vim in insert mode (`typedEdit`: back to
  the line's start, the name's in the listing, and there Backspace),
  `Ctrl-U` in the command line, nothing in the other modes.
- **Macros**: typed keys are recorded as tokens (`"<Esc>"`, `"x"`); the register
  keeps them as `keys` next to the text, so literal "<CR>" typed in insert mode
  stays text. `@` pushes a frame (`{ keys, next, runs }`, not the keys `runs`
  times) on `typeahead`, whose keys a run (see Batches and runs) gives
  `runKey` with no key event, so vim types insert-mode keys itself
  (`typeKey`, `insertMove`). A failing command (bad keys, failed motion,
  `showError`) empties `typeahead`.
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
  view alone, even off the cursor.
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
  message) and is cut there anyway. They're worked out over all the text
  (`aside.refresh`, counting a column per code point, `Txt.columns`, as
  `Txt.column` is too slow for all of a long listing), so they don't move
  as it scrolls, but whenever it changes, or the notes, the problems or the
  view's width do; the overlays then place the lines in view
  (`aside.spots`), never over what's before them (an emoji wider than a
  column).
- **Quitting**: `:q` with unsaved changes fails (E37); `:confirm q` asks
  instead, in a `ConfirmDialog` rather than a `MessageDialog` (which is native
  on macOS, can't use the editor's font or vim's keys). `ConfirmDialog.ask`
  takes what Yes and No do; without a No action it offers only [Y]es/(N)o. Saving a file that has
  no path opens the Save dialog, so `root.save(quit)` sets `quitAfterSave` to
  quit once it's saved (also for `:wq`).
- **Find bar**: moving to a match moves vim's cursor to its start
  (`vim.jumpTo`, which leaves visual mode and breaks an insert); it doesn't
  select it. The current match is the one starting at the cursor
  (`currentStart`), however the cursor got there. Its matches take over the
  search highlights while it's open; Esc in normal mode (`highlightsCleared`)
  closes it. Replace All is one `replaceRange` over the first to last match,
  keeping the hidden text between matches. On Windows, Ctrl+F is Find, not
  vim's page down. Each field keeps a history (`Field.remember`: the newest
  100, until Koil quits) of what it had when it was used (a match moved to,
  a replace, the bar closed, or a query replaced by Find's seed), and Up
  and Down put those back (`browse`) as the path history does, apart from
  vim's `/` history (the bar's query isn't a vim pattern).
- **Theme and zoom**: `Theme` (one, in main.qml, passed to every control)
  takes its colors from the editor's palette, so they follow the light or dark
  theme. When the theme changes, a `Palette` emits only `changed`, not its
  per-color signals, so a binding on `palette.base` keeps the old color;
  `Theme` copies the colors on `changed`, and QML reads them from `theme`
  (`theme.base`, `theme.highlight`), never from a palette. It also holds `zoom` (font size / default). Every text in the app grows
  and shrinks with View > Zoom (Cmd+ / Cmd- / Cmd+0), not just the editor:
  text in the editor's font uses `theme.font`, other UI scales its sizes by
  `theme.zoom`. New UI must do the same, and use `Panel` for a box over the
  editor, `Tip` for tooltips (keys that do the same go in its
  `shortcuts`, each shown as code, not in the text) and `IconButton` for small
  buttons.
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
  bar, which changed the width), the gutter gets its width before the text
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
- **Line numbers** (`:set nu`/`rnu`): the `gutter` is a child of the
  `TextArea` (so it scrolls with the text), kept at `contentX` and drawn over
  text scrolled under it. The styles hard-code `leftPadding` (7 on macOS,
  `padding + 4` in Fusion), so the editor keeps the style's value and adds the
  gutter width (the digits and two spaces) to it. Only visible lines get a row.
- **Settings**: `settings` (a QtCore `Settings` in main.qml) holds the saved
  values. The ones in use are vim's (`fontSize`, `fontFamily`, `number`,
  `relativeNumber`, which `:set` changes: `root.vimSettings`),
  `root.colorScheme` and `root.confirmChanges`, bound to the saved ones at
  startup. The Settings window
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
  Settings window's size follows the zoom, so it isn't resizable. They're
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
  closes (`keepHelpKeys`, leaving them there: `hadKeys`).
- **Scrolling boxes**: the help, the hover box and the confirmations are
  `Flickable`s that aren't interactive (a drag selects their text),
  scrolled by a `WheelHandler`. It needs `acceptedDevices` with
  `PointerDevice.TouchPad`: by default it takes only a mouse wheel, and the
  trackpad's scrolls go to the popup, which drops them.
- **QML's JavaScript**: don't make a binding depend on something by reading it
  as a bare statement (`editor.revision;`): the app's QML is compiled ahead of
  time, which can drop it, though `qmltestrunner` keeps it. Use the value. The
  engine has no `Array.prototype.flatMap`; `?.` and `??` work. A `var`
  property bound to objects of constants (`dark ? { create: "#73c991" } :
  { … }`) came out undefined in the compiled app, though qmltestrunner had
  it (`regexColors`, with a `String(text)` in it, works), so
  `theme.changeColor` is a function.

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
