# CLAUDE.md

Koil desktop app: a vim-style editor in Rust + Qt 6 via cxx-qt 0.10, with the
UI in QML, that edits a directory as text (like oil.nvim) through koil-core
(`../koil-core`, a library; `../koil-cli` is its CLI; read their CLAUDE.md for
how Koil works). The editor is the one from `~/projects/vim-edit`, cleaned up.
It shows Koil's listing (see Koil), or a file opened with File > Open.

## Layout

- `src/main.rs`: creates the app, installs the "Settings…" translator and the
  icon fallback font, sets the Windows style, loads `qml/main.qml`.
- `src/listing.rs`: the listing as text, without Qt: `render`, `parse`,
  `check`, `update` (read it into koil, then navigate), the confirmations'
  lines (`actions`, `undo_steps`) and the path line's regex parts
  (`path_syntax`). Its tests (`src/listing/tests.rs`) use a temp dir.
- `src/koil.rs`: `Koil` (QML element): wraps `koil_core::Koil` and calls
  listing.rs, taking and giving JSON. `showHidden`, `gitignore` and `regex`
  are properties, bound to vim's `:set` options.
- `src/document.rs`: `Document` (QML element): reading and writing files, the
  path on the command line.
- `src/system.rs`: `System` (QML element): the system clipboard, the
  installed monospaced fonts, and the editor's line format and colors.
- `src/ffi.rs` + `cpp/native.{h,cpp}`: the C++ helpers behind `System` and
  `main.rs` (menu title translator, Controls style, clipboard, fonts, icon
  fallback font, line format, the listing's `QSyntaxHighlighter`).
- `qml/main.qml`: the window: settings, menus, dialogs, status line, and
  Koil's listing (`showListing`, `updateListing`, `applyChanges`,
  `undoApply`) or a file (`loadFile`). It wires the pieces together; no
  editing logic lives here.
- `qml/Editor.qml`: the `TextArea` in a `ScrollView`, and everything drawn
  with it: cursors, selection, search highlights, warnings and errors, line
  numbers, and the `HoverBox`.
- `qml/HoverBox.qml`: the VS Code-style box that shows what an icon hides (an
  ID), or a warning's or error's message.
- `qml/Vim.qml`: the vim emulation (modes, motions, operators, registers,
  undo, macros, visual block, multiple cursors, hidden text, `:` and `/`).
  It drives the `TextArea` through `insert`/`remove`/`select`.
- `qml/text.js`: pure text helpers (lines, characters, words, text objects),
  imported as `Txt` by Vim.qml and the views.
- `qml/FindBar.qml`: the find and replace bar (Cmd+F, Cmd+Option+F).
- `qml/HelpPanel.qml`: `:help` (`:h topic`), a box listing what isn't obvious.
- `qml/ConfirmDialog.qml`: the [Y]es/(N)o/(C)ancel box, with a list under
  the question: `:confirm q`, applying, undoing an apply.
- `qml/SettingsWindow.qml`: the Settings window (Cmd+,).
- `qml/Theme.qml`, `Panel.qml`, `Tip.qml`, `Icon.qml`, `IconButton.qml`: the
  look the app's own controls share (see Theme).
- `tests/tst_vim.qml`: qmltestrunner tests for Vim.qml and the find bar.
- `scripts/`: `bundle-macos.sh` (makes the `.app`), `package-macos.sh` (the
  `.dmg`), `package-windows.ps1` (windeployqt, then the Inno Setup installer).
- `packaging/`: `Info.plist` (with a `@VERSION@` placeholder) and
  `installer.iss`.

## Build and test

- Local Qt comes from Homebrew (`qtbase`, `qtdeclarative`); `qmake` must be on
  `PATH`. `cargo build`, `cargo run` (lists the home dir), `cargo run -- dir`
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
  remove it after. The window opens over the user's work, so keep such
  sessions short. A menu shortcut sent this way runs after the keys that
  follow it, and Cmd+= doesn't reach Zoom In at all (neither in vim-edit).

## Koil

- **The listing** (listing.rs): the location (`~` for the home dir) on the
  first line, a line of `=` (at least 42, as in koil-cli), then per entry its
  devicons icon, two spaces and its name (`/` after a dir's). The icon hides
  the entry's ID (`Id.0`, as text) as vim's hidden text, so it yanks, pastes
  and undoes with its line. `parse` reads a line as an existing entry if its
  first character is an icon with a hidden entry, else as a new one; a
  Private Use Area character first (the icon `render` gives a new entry) is
  dropped, and names are trimmed. Header problems (no `=` line, no path, two
  paths) and an icon hiding something that isn't a number are errors, which
  block an update like koil's own. devicons' default file icon is `*` (a
  glob character), so `FILE_ICON` replaces it.
- **Problems**: `Koil::check` runs 200 ms after the last edit
  (`checkTimer`), and gives `{ line, column, severity, message }`; Editor.qml
  draws each from `column` (where the name starts) to the line's end.
  Everything else (squiggles, the message after the line, the hover, `gh`)
  works as before. A failed update also shows the path line's open error,
  until the next check.
- **Keys** (`commandKeys` in Vim.qml, only while a listing is shown): `Space
  Space` updates, `Space a` applies, `-` opens `..` (`3-`: `../../..`), and
  Enter opens the dir or file on its line (`listing::target_on_line`: a dir
  if the name ends with `/`, else the file its ID points to on disk, even if
  the line renames it; a new entry isn't there to open) or the path line.
  On a line without an entry it's vim's Enter. In a file with a path, `-` is
  Koil's too (`leaveFile`): back to the listing, on the file's line.
  They're only matched at the start of a normal-mode command (so `d-` and
  visual `-` are vim's), with a count; a Space followed by anything else is a
  bad command. Shift+Enter is its own token, `<S-CR>`, a motion like `<CR>`,
  and plain `<CR>` everywhere else (insert mode, the command line).
- **Update** (`updateListing`): koil reads the entries with the settings they
  were shown with, then takes vim's `:set hidden/gitignore/regex`, then opens
  the Enter/`-` target, else the path line if it changed (like koil-cli).
  The listing is then shown again. If what's shown stayed the same (same
  location, same hidden/gitignore; `moved` is false), the new text replaces
  the old as one vim change (`vim.replaceText`, which changes only the span
  that differs), so `u` can take it back: Koil reads the buffer as a whole
  each time, so undoing to an earlier listing of the same view is safe.
  Otherwise vim starts over (`vim.reset`): undo must never bring back
  another view's entries, which Koil would read as this one's (missing
  hidden entries would be deleted, other dirs' IDs moved here). `from` puts
  the cursor on the dir `-` came from.
- **Apply and undo**: `Space a`, `:w`, File > Save (renamed Apply Changes…)
  update, then `ConfirmDialog` lists `listing::actions` (paths relative to
  the open dir); yes applies, then vim starts over (koil refreshed: new IDs
  for renamed paths). `u` or Cmd+Z with nothing left to undo in vim emits
  `nothingToUndo`, and `undoApply` updates (vim's undo may have taken the
  buffer back past an update) and asks to run koil's undo, listing its
  steps; koil refuses while changes are pending.
- **Quitting**: `modified` is the file's unsaved changes, or in the listing,
  edits or pending changes (`koil.hasChanges()` after each update). `:q`
  updates first (`unsaved`); `:confirm q` asks to apply the changes, where No
  quits without them. `:wq` applies, then quits.
- **Files**: Enter on a file, File > Open (and a file on the command line)
  leave the listing (updating it first, so its edits stay in koil) for a
  plain editor: no colors or problems, only `-` of `commandKeys`, and `:w`
  saves. `-` goes back to what's still open in koil, on `openedFrom` (the
  entry Enter was on), or for a file opened otherwise, opens its dir. Unsaved
  changes are asked about first (save, drop, or stay). `:q` in a file also
  refuses while the listing has pending changes (E162), and `:confirm q`
  goes back to the listing to ask about applying them. File > Open Folder
  (Cmd+Shift+O) and a dir or pattern on the command line list it; with no
  argument Koil lists the home dir.
- **Colors** (`setListingColors` in native.cpp): a `QSyntaxHighlighter` on
  the editor's document colors each line's icon (colors from devicons,
  gathered from every listing shown, `iconColors`, dark or light by theme),
  the path line and `/`-ending names (`theme.directory`), and the `=` line.
  It's text-based, so it follows edits. It's found by object name (no moc
  for native.cpp). Highlighting counts as a text change to Qt (as
  `fixLineFormat` does), so Editor.qml only emits `edited` when the text
  really changed (`lastText`). While the path is read as a regex (`:set
  regex` and the path changed, or a regex is open), `pathSyntax` gives its
  parts (`listing::path_syntax`: after the longest existing dir, from the
  first part with a special character, as koil splits it), which
  `setPathColors` draws over the path's color in `theme.regexColors`.
- **Icon font**: devicons' icons are Nerd Font glyphs in the Private Use
  Area. `useIconFallbackFont` makes an installed Nerd Font (preferably
  Symbols Nerd Font Mono) Qt's fallback for them (Qt 6.8+; Qt only takes
  application fallbacks for real scripts, and treats these as
  `Script_Common`), so they show in fonts like Menlo. With no Nerd Font
  installed they're boxes.
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
- **No file types**: Koil doesn't claim any file type (no
  `CFBundleDocumentTypes`, no "Open with" registry entries), so nothing opens
  files with it and there's no `QFileOpenEvent` filter. A path on the command
  line is opened (`Document.startupFile`); otherwise the sample listing shows.
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
  Editor.qml replaces its background with a plain one. The MSVC CRT DLLs are
  copied app-locally, so no VC++ Redistributable is needed.
  `package-windows.ps1` loads the VS dev shell itself; `ilammy/msvc-dev-cmd`
  was removed because it's stuck on Node 20.
- **Vim**: `Vim.qml` owns the cursor (`vim.cursor` is the character under the
  block), which Editor.qml draws. Insert mode uses the `TextArea`'s own cursor
  (`cursorDelegate`). Outside insert mode the `TextArea` is `readOnly`, so macOS
  doesn't open the accent picker on held keys and only vim edits the text.
  Changing `readOnly` makes the editor scroll to a stale cursor position, so
  `setMode` restores the view and then scrolls only if the cursor is out of it
  (`showCursor`). Vim keeps its own undo stack (diffs per change), so native
  undo (Cmd+Z) is routed to it. Only the `"+`/`"*` registers use the system
  clipboard.
- **Macros**: typed keys are recorded as tokens (`"<Esc>"`, `"x"`); the register
  keeps them as `keys` next to the text, so literal "<CR>" typed in insert mode
  stays text. `@` puts the keys in `typeahead`, which `runMacro` runs through
  `runKey` with no key event, so vim types insert-mode keys itself (`typeKey`,
  `insertMove`). A failing command (bad keys, failed motion, `showError`)
  empties `typeahead`, and a run stops after `maxMacroKeys` keys.
- **Visual block** (`visualBlock`): the editor's selection can't be a block, so
  it's cleared and Editor.qml draws `vim.blockSpans()`. Columns count
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
  after each edit. Leaving insert mode removes them. In normal mode `moveBy`
  moves them too (`moveCursors`; each keeps its own `col` for j/k, and
  `motion(..., quiet)` doesn't scroll), and `execute` runs operators and
  `everyCursorActions` once per cursor (`atEveryCursor`), swapping in each
  extra cursor's own `registers`. They're drawn like the main one, blinking
  with the real bar via `editor.blinkOn`.
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
    whose whole icon is in a range, `shifted` moves them).
  - The `"+` register (and Cmd+C/X/V in every mode) writes the text with every
    icon replaced by what it hides (`revealed`), for other apps, and JSON
    `{ text, hidden, block, session }` as `application/x-koil-data`, which
    Koil reads back (`validHidden` checks it first: any app can write the
    clipboard; see Clipboard under Koil for `session`).
  - Qt's native Backspace deletes one code point, so vim handles Backspace in
    insert mode, and cursor steps go through `Txt.charStart`/`charEnd` (never
    `±1`), which treat an emoji with its modifiers as one character, as Qt
    does. Columns count characters (`Txt.column`, `Txt.atColumn`).
  - Resting the mouse on an icon (a `HoverHandler`) or `gh` shows its text in
    the `HoverBox`, in the window's `Overlay` (so the editor doesn't clip it).
    Its text is a read-only `TextEdit` that never takes focus, so keys stay
    with the editor, which forwards Copy to it. Any other key, a scroll or an
    edit hides it; one the mouse opened also hides 300 ms after the pointer is
    on neither the target nor the box (and isn't dragging a selection).
- **Warnings and errors** (`diagnostics` in Editor.qml): Koil's problems
  (see Koil) get a VS Code-style squiggle in the visible lines, and their
  line shows a message four spaces after its end (an error's before a
  warning's). The hover box shows the message (with an icon) as it does an
  icon's text; `targetUnder` also finds the message after the line.
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
  vim's page down.
- **Theme and zoom**: `Theme` (one, in main.qml, passed to every control)
  takes its colors from the editor's palette, so they follow the light or dark
  theme. When the theme changes, a `Palette` emits only `changed`, not its
  per-color signals, so a binding on `palette.base` keeps the old color;
  `Theme` copies the colors on `changed`, and QML reads them from `theme`
  (`theme.base`, `theme.highlight`), never from a palette. It also holds `zoom` (font size / default). Every text in the app grows
  and shrinks with View > Zoom (Cmd+ / Cmd- / Cmd+0), not just the editor:
  text in the editor's font uses `theme.font`, other UI scales its sizes by
  `theme.zoom`. New UI must do the same, and use `Panel` for a box over the
  editor, `Tip` for tooltips and `IconButton` for small buttons.
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
  taller, so `fixLineFormat` gives every block a fixed height (a block format,
  reapplied after `setText`; Qt counts it as an edit, so `quiet` keeps it from
  marking the file modified). Qt puts a fixed-height line's baseline at 4/5 of
  it, so to center the text the block gets a shorter line plus a bottom margin
  that makes up `lineHeight` (`textBaseline` is where the baseline ends up).
  Qt's selection and `positionToRectangle` still use the natural (taller)
  height on emoji lines, so the selection is drawn by the app (under the text,
  `z: -0.5`), and all overlays use `cellAt` (the whole line, snapped to the
  line grid). The current-line highlight is at `z: -0.6`.
- **Line numbers** (`:set nu`/`rnu`): the `gutter` is a child of the
  `TextArea` (so it scrolls with the text), kept at `contentX` and drawn over
  text scrolled under it. The styles hard-code `leftPadding` (7 on macOS,
  `padding + 4` in Fusion), so the editor keeps the style's value and adds the
  gutter width (the digits and two spaces) to it. Only visible lines get a row.
- **Settings**: `settings` (a QtCore `Settings` in main.qml) holds the saved
  values. The ones in use are vim's (`fontSize`, `fontFamily`, `number`,
  `relativeNumber`, which `:set` changes: `root.vimSettings`) and
  `root.colorScheme`, bound to the saved ones at startup. The Settings window
  shows the saved ones and changes both (`changeSetting`). The zoom and `:set`
  change only the ones in use, until Koil quits, so the Settings window
  doesn't show them. Their defaults (Cmd+0, `:set fs&`) are the saved values
  (vim's `default*` properties are bound to `settings`), not Koil's defaults.
  Koil's own options (`:set hidden`, `gitignore`, `regex`) aren't saved, and
  start off. The color scheme sets `Application.styleHints.colorScheme` (Qt 6.8+), which
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
- **QML's JavaScript**: don't make a binding depend on something by reading it
  as a bare statement (`editor.revision;`): the app's QML is compiled ahead of
  time, which can drop it, though `qmltestrunner` keeps it. Use the value. The
  engine has no `Array.prototype.flatMap`; `?.` and `??` work.

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
