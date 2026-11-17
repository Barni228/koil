# The listing and the path field

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
  One `Vim` edits both it and the listing, one at a time (see
  Buffers): `activeView` is the one it edits, which vim's
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
- **Back and forward** (`visits` in main.qml, `stepVisits`): apart from
  the path history, the locations the user stopped at, each once, as
  vim's jumplist: `[` (`3[`) goes back through them, `]` forward again.
  Going to another location (`onLocationChanged`) puts the one left
  (`visitAt`) last and then the one gone to, keeping the newest 100, so
  those `]` went forward to stay, before them. They were dropped, as a
  browser's history does (and Neovim's `jumpoptions=stack`), but then
  `[` to the home dir from a dir typed in the path field, and Enter on a
  dir there, lost the typed one, which only the path history had. A
  location that's there already moves last, the same visit, so `[`
  goes back through the stops by when they were last left, each once.
  Not the ones only walked through, so `[` goes
  back to where something was done, not through every dir on the way
  there: a location gone to by Enter on a dir or `-` (`walkTo`, which
  sets `walking`; the visit's `walked`), left the same way, with nothing
  done in it (`used`), is dropped as it's left, and walking back to the
  stop before it (into a dir and out again) is that visit again, not
  another. A visit that's there, other than the one shown, was kept as
  it was left, so it's a stop: going to it again, even by a walk, turns
  its `walked` off, and walking on from it keeps it (else, the only
  visit of its location, it would be lost). Something done (`usedHere`) is the listing edited (checked as
  `showListing` replaces or leaves it, `isEdited`), a file opened from
  it, an entry yanked or marked (vim's `yanked` and `marked`), K, Space
  r, Space o, a shell command, an apply, an undo or a create. Anything
  else that goes to a location is a jump (the path field, `:e`, Open
  Folder, a drop, startup), which makes both the one left and the one
  gone to stops; so does `[` or `]` itself (`walked` off for the one it
  goes to), so the other key always goes back.
  Each keeps where the cursor was when it was left (`spot`, saved by
  `showListing` as the location changes: `listingSpot`, or `fileSpot`
  from a file), which going back to it gives `showListing` as its `keep`,
  but going back up, the cursor is on the dir it came from, as for `-`
  (`Updated::from`). It's an update (`tryUpdate`) of the location as
  shown, as Enter in the path field reads it; while it runs (`stepping`)
  the location changing adds no visit, nor does the open dir renamed on
  disk, which renames the one shown (`setShownVisit`, which drops another
  visit of the new name, as it does for the one `[` goes to, if it reads
  as another location now: each is there once). One that can't be opened
  any more (no problems in the listing or the field, so `open` failed) is
  dropped (`dropVisit`), so the next `[` goes past it. In a file or the
  scratchpad, `[` is `-` without a count (`leave`), and `]` isn't a key.
  The mouse's back and forward buttons type them (`stepButton`, a
  `TapHandler` in the overlay, as `vim.startCommand` does for the sort
  button), only where they do something (`commandHere`), and not while
  a box has the keys or something runs. So do Cmd+[ and Cmd+] on macOS
  (Finder's back and forward, in `menuShortcuts`, so no shortcut of the
  user's has them), Alt+Left and Alt+Right elsewhere (Explorer's; Ctrl+[
  is vim's Esc), and a keyboard's Back and Forward keys: a `Shortcut` for
  each way, once a press, whatever has the keys in the window. Qt gives
  those as `Key_Back` and `Key_Forward` on Windows (`VK_BROWSER_BACK`)
  and Linux. macOS gives apps no key event for them (its key codes have
  none; Karabiner's EventViewer sees them as the HID's `ac_back` and
  `ac_forward`), so there they do nothing, as in every app: reading them
  from the HID device would need Input Monitoring.
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
  the part): Tab and Shift+Tab (`<S-Tab>`, which elsewhere only a
  shortcut takes, see Shortcuts; also Down and Up, Ctrl-N and Ctrl-P) pick the next or previous one, Enter
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
- **Drives** (Windows only, koil-core's `Koil::shows_drives`; read Drives
  in its CLAUDE.md): `-` in a drive's root (`listing::up`'s `..`) lists
  the drives, as koil-core opens them for `..` of a root, and for `/`,
  which the path field then shows (so the path history and `[` and `]`
  go back to it from anywhere; `/x` is in them too, so nowhere, not on
  the open dir's drive as Windows has it). A line is a drive's root,
  named as its drive (`C:/`, with `DRIVE_ICON`, by its name: `is_drive`,
  which the completions' icons use too), whose ID Enter (`Target::Dir`
  of `C:`, which koil reads as `C:\`), K, Space r and `%` take as for
  any dir; `update` puts the cursor on the drive it came from (`from`,
  through `Koil::relative`, which names a path there by its drive). It
  only lists them: editing it is an error, but a line left out, which
  stays. `C:` alone is `C:/` anywhere, and Tab completes a drive from a
  letter (`t` gives `T:/`, with the dirs starting with `t`). As `/` is
  no dir on disk, though Windows reads it as its current drive's root,
  what Koil looks up itself there doesn't go through it
  (`koil_core::in_drives`): from the path field, K, Space r and Space o
  say the drives aren't a folder (`path_on_line`), `%` is every drive
  (`paths_in_field`), a shell command runs in the home dir
  (`Request::dir`), `file_at` and `link::target` don't look in it, and
  `looks` reads nothing (a network drive that can't be reached would
  keep Koil waiting). `slashed` adds no `/` after a root's, which ends
  with one, so the hover and K show `C:/`. Untried on Windows; the
  `#[cfg(windows)]` tests (`test_drives` here, and koil-core's) say what
  it should do, and core's CI runs its own there.
- **Keys** (`commandKeys` in Vim.qml, only while a listing is shown, in the
  listing and the path field): `Space Space` applies (`Space a` too, but
  always asking first, whatever the setting: see Apply), `Space u` lists
  the applies to undo (see Undo history), `Space r` shows the entry on
  the cursor's line in Finder or Explorer, selected (`reveal`: where its
  ID is on disk, as Enter opens it; from the path field, the open dir; a
  new entry or a copy isn't on disk yet, so the status line says so, as
  `Koil.pathOnLine` gives `{ path, message }`; `System.reveal`
  runs `open -R`, or `explorer /select,`, or on Linux opens the dir it's
  in), `Space o` opens the same path (`entryPath`) as a double-click in
  Finder or Explorer does, once its copies are asked about, as in Koil
  (`copyFirst`, see Files), a file in its default app (`System.openInApp`:
  `open`, `explorer` or `xdg-open`, waited for on a thread, as `open`
  waits while an app launches; on macOS `openFailed` then says why it
  failed, like "No app opens", which Finder would ask about, while
  Explorer asks itself), `K` shows all about it (see Info), `-` opens `..`
  (`3-`: `../../..`), where a pattern is a level of its own (`Koil.up`,
  `listing::up`): `dir/*` goes to `dir`, on the dir or file there that
  the cursor's entry is in (`src/` of `src/main.rs`), then to the dir
  it's in, `[` and `]` back and forward (see Back and forward), `_`
  the scratchpad (see Scratchpad), `!` a shell
  command on the entry (see Shell commands), Tab goes to
  the other editor (`activate`), `g.`,
  `gi` and `gr` toggle `:set hidden`, `gitignore` and `regex` (like the
  buttons), and `gs` and a key sort it (see Sorting). Cmd+S (File > Save,
  named Update in the listing) and `:w` update: only `Space Space` and
  `Space a` apply (`save`), as a `:w` typed out of habit mustn't change
  files.
  Enter in the listing opens the dir or file on its line
  (`listing::target_on_line`: a dir if the name ends with `/`, else the file
  its ID points to on disk, even if the line renames it, and so a dir
  renamed or moved here, as it's the same dir, which applying then moves;
  a new file is created first, and a copy made first, see Files); on a
  line without an entry it's vim's Enter.
  Enter in the
  path field (`openPath`, also from insert mode: see `singleLine`) updates
  and goes to the listing, unless the update fails; Shift+Enter there only
  updates, so vim stays in the field. In a file, `Space Space` saves (as
  `:w`: `save`), `!` is Koil's too, and with a path, so are `-`
  (`leaveFile`): back to the listing, on the file's line, a level up, so
  `3-` goes two up from there (`goUp`), `_`: the scratchpad over the
  file, and `Space r`, `Space o` and `K`, which take the file, as `%` does
  (`entryPath`; in the scratchpad, what `<cfile>` stands for: the entry
  pasted on the cursor's line, or else the path under the cursor, as gf
  takes it, `linkTargetAt`, see Scratchpad). `Space q` lists the user's shortcuts
  (see Shortcuts) everywhere, in visual mode too (`visualCommandKeys`), so
  the list can run one on the selection. Each Space key is an Ex command
  too (in `exCommands`, `Vim.commandKey`), so a shortcut or `-c` can say
  what it does: `:apply` (`:ap`, Space Space), `:confirm apply` (Space a),
  `:undolist` (`:undol`, Space u), `:reveal` (`:rev`), `:open` (`:o`) and
  `:shortcuts` (`:sho`). It looks its keys up in `commandKeys` and emits
  `keyCommand` as if they were typed, with no count, so it does what they
  do where vim is (`:apply` in a file saves, and so does `:confirm apply`,
  as Space a isn't a key there), and where they aren't keys it's an error
  ("`:undolist` does nothing here"), which stops a macro or `-c`. They
  take no argument and no range, so not from visual mode, where `:` types
  one. A new Space key gets a command with it.
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
  (its white icons, like `vercel.json`'s) a fifth away. The name of a file
  that can be run (any execute permission, as `ls` and eza color it; a
  file, not a dir nor a link to one: `listing::looks`, read at each render
  and sync, as koil-core keeps no permissions; a `chmod`, from Koil's `:!`
  or anywhere, has the watcher sync, see Changes on disk, and the sync
  colors the lines again, though it changes none; none on Windows) is
  green (`theme.infoColor("execute")`, K's `x`), after the dirs it's in,
  wherever its line is moved or copied, as it's the same file (by its ID,
  in `KoilRust::executables`). main.qml finds the
  pending lines and those after every edit of the listing (`updatePendingLines`, with
  `Qt.callLater`: halfway through vim's `replaceRange` its hidden text isn't
  up to date, and coloring is a text change to Qt, which would make
  `trackEdit` shift the hidden text again; `listing::pending_lines`, as `{
  pending, executable }`), and the highlighter colors those
  lines (`setEntryLines`): every line last colored
  otherwise (`ColoredAs`, its block's user data), not only those that were
  pending, as Qt colors a line as an edit reaches it, with the pending
  lines it has then, and vim's edit is a remove and an insert, between
  which lines have other numbers (a `:s` preview left a file's icon
  white). The highlighter is found by object name
  (no moc for native.cpp). Highlighting counts as a text change to Qt, so
  Editor.qml only emits `edited` when the text
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
  `glob_parts`), in `theme.patternColors`. A regex is koil-core's, which
  can look around and back (`,*(?<!\.min)\.js`, `(,+)/\1\.rs`, see its
  CLAUDE.md), so `(?<!`, `(?<=`, `(?=`, `(?!` and `(?>` are a `group` each
  (what they look for is colored as the rest), `a++` one `quantifier` and
  `\k<name>` one `escape`.
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
