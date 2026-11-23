# Layout

- `src/lib.rs`: the crate's modules, and `run`, the startup: reads the
  command line (cli.rs), creates the app, installs the "Settings…"
  translator, the Nerd Font and the window icon, sets the Windows style,
  loads `qml/main.qml`. Koil is a library so the web build (`web/`) can
  link it as a static one (see Web).
- `src/main.rs`: the desktop app, which calls `koil::run`.
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
  opens (`file_at`), what Enter opens (`target_on_line`), which lines are
  copies (`copies`, read into a copy of the Koil: `with_listing`) and the
  copies of a file to make before it changes (`copies_of`), what's shown after
  each line when sorted by size or a date (`notes`), and whatever it's
  sorted by, a link's target and the files that can be run (`looks`), what changed on
  disk as edits to the text and questions (`sync`, `resolve`, `merge`),
  what the scratchpad shows of the entries pasted in it (`pasted_looks`),
  and the entries a shell command runs on (`paths_on_lines`, or from the
  path field `paths_in_field`), or what `<cfile>` stands for on a file's
  lines (`links_on_lines`). Its tests (`src/listing/tests.rs`) use a temp
  dir.
- `src/history.rs`: `History`, the undo history kept in a file across
  sessions (see Undo history). Its tests (`src/history/tests.rs`) use a
  temp dir.
- `src/info.rs`: what `K` shows of an entry (`read`, then `Entry::show`
  with a dir's size as `Sizes` knows it then; see Info). Its tests
  (`src/info/tests.rs`) use a temp dir.
- `src/shell.rs`: shell commands (see Shell commands): the shell's kind
  (`Kind`), `%` in a command (`expand`), running one (`start`, then
  `Started::finish` on a thread) and stopping it (`Running::stop`), the
  environment it runs in (`environment`), its output as shown, as it
  comes (`Screen`, `as_shown`, and `Live`, which tells what's new of it
  while it runs), and the shells installed (`shells`). Its
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
  scratchpad's file (`writeScratchpad`, see Shell commands), the files
  of shortcuts exported and imported (`writeText`, `readText`, apart from
  the file shown), the command line, and installing the `koil` command
  (on a thread).
- `src/system.rs`: `System` (QML element): the system clipboard, the
  installed monospaced fonts and the Nerd Font's family, the editor's
  text, line format and colors, showing a path in Finder or Explorer
  (`reveal`) or opening it in its default app (`openInApp`) or another
  that can (`appsToOpen`, `openWith`, with `sorted_apps` and `named`,
  see Keys; tests in `src/system/tests.rs`), links
  (`linkAt`, `linkTarget`), the search's regular expressions
  (`regexMatches`, see Regular expressions), and running shell commands
  (`runShell`, `stopShell`, `shellDone`). Its methods that only hand a QML item to
  native.cpp are made by `forward!`.
- `src/ffi.rs` + `cpp/native.{h,cpp}`: the C++ helpers behind `System` and
  `lib.rs` (menu title translator, Controls style, clipboard, fonts, the
  Nerd Font, the window icon, files macOS asks to open, Cmd+Backspace in
  text fields, clicks on a popup window kept from the window under it
  (`keepPopupClicks`, see Windows), Koil's text layout (`TextLayout`: `setLineFormat`, see
  Text layout, Long lines and Wrapping),
  `setText`, the listing's and path field's `QSyntaxHighlighter`, a
  file's colors (`TextColors`: `setTextColors`, with syntax.rs) and
  `K`'s (`setSpanColors`), `redrawText`, what changed in
  a text (`TextChanges`, see Long texts), and PCRE2's regular expressions
  (`regexMatches`, see Regular expressions)).
- `cpp/finder_mac.mm`: the "Open in Koil" service on macOS (see Open in
  Koil), what Finder says is available on a volume
  (`importantCapacity`, see Info), and the apps its Open With lists
  (`appsToOpen`, see Keys), Objective-C++, which `build.rs` adds only
  there (native.cpp has what the others get).
- `cpp/apps_win.cpp`: the apps Explorer's Open With lists and opening a
  file with one (`appsToOpen`, `openWithApp`, see Keys), through the
  shell's COM interfaces, which `build.rs` adds only on Windows.
- `qml/main.qml`: the window: settings, menus (`MacMenuBar.qml`, and
  `WindowMenuBar.qml` elsewhere, which run its functions), dialogs, the
  status line (`StatusLine.qml`), the path field and its option buttons, and Koil's listing (`showListing`,
  `updateListing`, `applyChanges`, `undoApply`), a file (`loadFile`) or
  the scratchpad (`openScratch`), and which of the two editors vim edits (`activate`). It wires the pieces
  together; no editing logic lives here.
- `qml/Editor.qml`: the `TextArea` in a `ScrollView`, and everything drawn
  with it: cursors, selections (see Multiple selections), the marked
  lines (see Marked lines), the
  find bar's scope and what was just yanked (each a `SpanShade`), the
  selection's whitespace (`whitespace`, see Whitespace in the
  selection), search highlights, the
  bracket matching the cursor's (`brackets`), the notes after lines (`infos`, see Sorting),
  warnings and errors, line numbers, the link under the pointer with Cmd
  held (`link`, see Links), the long lines Qt doesn't draw (`longText`,
  see Long lines), the `HoverBox` and the
  `CompletionList`, each in a part a row while lines wrap (`rowSpans`, see
  Wrapping). Both the listing (or
  file) and the path field are one (`pathField`).
- `qml/CodeLabel.qml`: text with `code` in backquotes, each in the
  editor's font on a shade, as the help shows them, for `Tip` and the
  Settings window's notes (see Theme); `qml/HelpLink.qml`, a `:h topic`
  in one, or in the help, as a link (see Help links).
- `qml/HoverBox.qml`: the VS Code-style box that shows what an icon hides (an
  ID, as its path), or a warning's or error's message.
- `qml/InfoBox.qml`: what `K` shows of an entry, in the middle of the
  window, without the keys (see Info).
- `qml/CompletionList.qml`: the dirs Tab can complete the path field to, in
  a box under it, like VS Code's suggestions (see Completion), or the
  words Ctrl-N and Ctrl-P go through (see Word completion).
- `qml/SortMenu.qml`: what `gs` and a key sort the listing by, in a box
  under the sort button (see Sorting).
- `qml/Vim.qml`: the vim emulation (modes, motions, operators, registers,
  undo, macros, visual block, multiple cursors and selections, `gn`,
  `ga` and `gA`, marked lines, hidden text, the listing's prefixes, `:`
  and its ranges, `/`, `:s`, `:g`, surround, buffers). It drives the
  `TextArea` through `insert`/`remove`/`select`.
- `qml/text.js`: pure text helpers (lines, characters, words, text objects
  and the tags `it` and `at` find, `tagPair`, `=`'s indents, `reindent`,
  and `g=`'s, `guessIndents`, the lines they read, `codeScanner`,
  `:s`'s arguments and replacement, the regular expressions a search
  looks for (`regExp`), `code` in the help and tips), imported
  as `Txt` by Vim.qml and the views. The only state it keeps is
  where the lines of the last two long texts start (`lineIndex`), so
  `lineOf`, `lineToPos` and `countLines` (the status line, line numbers,
  highlights) don't go through the text each time.
- `qml/FindBar.qml`: the find and replace bar (Cmd+F, Cmd+Option+F).
- `qml/HelpPanel.qml`: `:help` (`:h topic`, `:h key`), a box listing what
  isn't obvious (`qml/help.js`'s `sections`), each section folded to its
  title (see Help folds); it can show a list of rows
  too (`showList`, which only the tests use now), and `:!` what a command
  wrote (`showText`), also as it runs (`showRunning`; see Output box). `/` and `?` search it (see
  Help).
- `qml/HelpWindow.qml`: the help in a window of its own, which a
  question's ? opens beside it (see Help window).
- `qml/ConfirmDialog.qml`: every question's box, with Yes, No and Cancel
  as buttons, named by what they do (Apply, Don't Save), that show their
  keys, and a list under the question:
  `:confirm q`, applying and undoing (lists to pick from, a row with a
  checkbox each), and what changed on disk against the user's edits (see
  Questions).
- `qml/PickList.qml`: a list to pick from, without a look: its lines,
  picks, cursor, selection, groups and search, and the keys for them,
  which every such list shares, however it's drawn (a question's, the
  shortcuts to export); `ListSearch.qml`, the line its search is typed on
  (see Lists to pick from).
- `qml/SettingsWindow.qml`: the Settings window (Cmd+,), which scrolls,
  and shows what a setting does with the pointer on it (see Settings).
- `qml/ShortcutsWindow.qml`: the user's shortcuts, listed, edited,
  exported and imported (see Shortcuts).
- `qml/Theme.qml`, `Panel.qml`, `Tip.qml`, `Icon.qml`, `IconButton.qml`,
  `KeyCap.qml`: the look the app's own controls share (see Theme);
  `ModalBox.qml` (:help's and the questions' box), `WheelFlickable.qml`
  (see Scrolling boxes) and `SelectableText.qml`, the boxes'; and
  `TextButton.qml`, `Segmented.qml` and `DropList.qml` (with
  `DropOption.qml`, a row of it), the buttons and lists the Settings and
  Shortcuts windows share (a question's buttons are `TextButton`s too,
  with the key that clicks each after its label, `keys`), `Toggle.qml`, the switch of a setting that's
  on or off, and `Check.qml`, a checkbox, for one of two that are each on
  or off (line numbers' Absolute and Relative, a shortcut's Normal and
  Visual), rather than a choice of neither, one or both. A delegate other
  files use is a file of its own: an inline component of a file with
  `ComponentBehavior: Bound` is bound to it, and Qt makes none from
  another file (the lists were empty).
- `tests/tst_vim.qml`: qmltestrunner tests for Vim.qml, the find bar and the
  help's search; `tests/tst_shortcuts.qml`, the Shortcuts window with the
  keys alone.
- `scripts/`: `bundle-macos.sh` (makes the `.app`), `package-macos.sh` (the
  `.dmg`), `package-windows.ps1` (windeployqt, then the Inno Setup
  installer), `make-icons.sh` (the icons, from `packaging/icon.png`),
  `qml-tests.sh` (the QML tests as CI runs them, a failed one again).
- `packaging/`: `icon.png` (the app's icon, as macOS draws it) and the
  icons made from it (committed, so building needs no ImageMagick):
  `macos/Koil.icns`, `windows/koil.ico` (in the exe through `koil.rc`,
  which `build.rs` compiles with `embed-resource`) and `window-icon.png`
  (see App icon); `macos/Info.plist` (with a `@VERSION@` placeholder) and
  `windows/installer.iss`.
- `fonts/`: the Nerd Font Koil ships (see Icon font) and its license.
