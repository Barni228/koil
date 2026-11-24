# Files and the scratchpad

- **Files**: Enter on a file, File > Open (and a file on the command line)
  leave the listing (updating it first, so its edits stay in koil) for a
  plain editor: no colors or problems, only `-`, `_`, `!`, `Space r`,
  `Space o`, `Space O` and `Space Space` (a save) of `commandKeys`, and `:w` saves. `-` goes back to what's still open in koil, on `openedFrom` (the
  entry Enter was on), with the column and view it had (`fileSpot`), or
  for a file opened otherwise, opens its dir. Enter
  on a new file (`createFile`) updates, then asks to create it, listing the
  new dirs it's in (`Koil.createSteps`, koil-core's `Koil::create_steps`),
  and Yes creates them (`Koil.create`, `Koil::create_now`: an undo step like
  an apply's, keeping the other changes) and opens it. The listing starts
  over first, as after an apply: undo mustn't bring back its line without
  its ID, which koil would read as new again. One that needs other changes
  (a new `a` where `a` is moved away, or in a renamed dir) isn't created,
  and the status line says to apply them. Enter on a copy (a line with
  an ID whose file stays, or goes to another line: `Target::Copy`, which
  `listing::copies` finds by reading the listing into a copy of the Koil,
  koil-core's `Koil::copied_from`) is the same: it isn't the file it
  copies, which opening would change, and the copy then get too (what
  `yyp` and Enter did), so it asks "“b.txt” doesn't exist yet. Copy
  “a.txt” to it?", and Yes copies it on its own (`create_now` takes copies
  too), as a file of its own, with an ID of its own, and opens it, or
  lists it, a dir. And as a copy is of what's on disk when it's made,
  whatever Koil does that lets a file that applying copies, or a dir
  it's in, change (koil-core's `Koil::copies_of`: `yyp` of a file to keep
  it as it is, then Enter on the file) makes those copies first
  (`copyFirst`): opening it (`readFile`, so also `:e`, File > Open, gf
  and a drop), Space o, Space O and gx (another app could change it),
  and Save As
  over it; and before any shell command (see Shell commands), every copy
  applying would make (`listing::copies_of` with no path). They're asked
  about as the confirmChanges setting says, as a create is ("Applying
  the changes makes a copy of “a.txt”, which would get your changes to
  it too. Make it now?"), where No does nothing (there's no opening it
  as it is: the copy mustn't get its changes); not asking, they're made
  at once, and the status line says so. In the listing, they're found as
  koil will have them once it reads it (a copy of the Koil reads it,
  only if a line isn't at its ID's path or koil has copies), and made
  after an update, then the listing is shown from scratch, as for a
  create. One that can't be made before the other changes (where a file
  is moved away) stops it, and the status line says to apply them. Edits
  from other apps (one opened outside Koil) still reach the copies. What changes
  inside a dir in the listing, a copy of it never gets either: koil-core
  copies a dir before the changes inside it. Unsaved
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
  puts a command's output in it. `:_` (Koil's, vim's `scratchRequested`)
  shows it, or stays in it, where `_` would leave it, so a shortcut can
  end up there wherever it's run. `:_put` (`:_pu`, `:_pu a`; vim's
  `scratchPutRequested`, `putInScratch` in main.qml) puts a register
  after its last line (in place of an empty text), as lines whatever it
  holds, as vim's `:put`, with its hidden text, and always says how many
  lines went ("3 lines put in the scratchpad"), as it isn't shown for
  it: going there and back (`_Gp_`) would update the listing first
  (failing on its errors), start its undo history over, and clear the
  message. Shown, it's `Vim.putAtEnd`; else `Vim.putInState` makes the
  kept text and state (`scratchState`) what that would have, with an
  undo step of its own, so `u` there takes it back. It's the
  listing's editor, so whatever shows something else in it saves the
  scratchpad's text, cursor, undo history and view first (`keepScratch`,
  from `showListing` and `load`, as anything shown goes through those),
  and `openScratch` gives them back (`vim.enterBuffer`). Its hidden text
  comes back too, on purpose: entries pasted there keep their IDs, as in
  a register, so they can be put aside and pasted back into a listing,
  and meanwhile work as in the listing, by the ID of the icon their
  line starts with (`listing::pasted_entry`), wherever the cursor is on
  it: `gh` shows its path, `K`, `Space r`, `Space o` and `Space O` take it
  (`entryOnDisk`, and K's box follows the cursor's column too,
  `infoSpot`, as a path written is the one under it), gf opens it, and
  `!` with a count, in visual mode or on marked lines types a `<cfile>`
  for a command on them (`Vim.bangEntries`, a `%` in the listing), where
  `g!` is the filter, as in the listing; `!` alone types `:! <cfile>` on
  such a line (`pastedEntryAt`), and else `:! %`, the scratchpad's file.
  Enter opens it as gf does (`openPasted`; vim's Enter on a line without
  one). Its icon and the blanks after it are indentation
  (`Vim.firstNonBlank`, outside the listing, for an icon that hides
  text, `pastIndent`, which `:_put` puts the cursor after too): `^`,
  `I`, `gg`, `NG`, `+`, `-`, `yss` and where `p` and the commands on
  lines leave the cursor go to the name, and the word motions (`w`, `b`,
  `e`, `ge`, and `cw` on it) take the icon as a blank (`iconBlanks`,
  `Txt.classAt`, as `wordStep` does a prefix), so the cursor is
  seldom on the icon, though `0`, `h` and a click still put it there
  (it's no prefix: see Prefixes, which also keep new lines and searches
  out of one). What goes at a line's blanks (`indentEnd`: surround's
  new lines) doesn't take the icon. Their lines look as the listing's (`setTextColors`'
  `iconColors`, which Editor.qml gives only with no `filePath`: the
  lines of `setTextEntryLines`, those whose icon is indentation, by
  `Vim.indentIcons`, get the listing's colors in place of a file's,
  also with `:set nosyntax`: its icon, its dirs, and the names of those
  of files that can be run green). A line that only starts with a
  listing's icon (`eza --icons` written there, or lines from another
  Koil, whose IDs a paste drops) is a file's, as it's no entry. After each
  line, as the listing's notes (`Editor.infos` and `links`, by ID), is
  where a symlink points, and for an entry that isn't in the open dir,
  the dir it's in, as gh shows a path (`listing::pasted_looks`,
  `scratchLooks`, `updateScratchLooks` in main.qml): two `main.rs` put
  aside from two dirs read the same otherwise, and the line's text
  can't say, as it's the name the entry gets where it's pasted (a path
  written there would move it to that path). They're read from disk as
  the scratchpad is shown, after a shell command, and after an edit
  that brings other IDs (a paste), not watched. An ID means the same path all session, so
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
  */` or `<!-- -->` goes on to the next line as the block's state. Every
  file has every comment, whatever its name, as it knows no language: a
  Markdown heading (`# Title`) is colored as one, and so is what follows
  a Python division (`a // b`), but for one whose line goes on to close a
  bracket opened before it (`range(n // 2)`, `closes_before`). Only a
  line's first `MAX_LENGTH` (3000) characters are colored, as with vim's
  `synmaxcol`. native.cpp's
  `TextColors` asks Rust for each line's spans (`syntaxSpans`, in UTF-16,
  as Qt has it, of the line's first `coloredLength` characters) and gives
  them to the line's layout, apart (`syntax::apart`: Qt Quick drops the
  end of a format that starts in another, so a path in a string lost its
  last character and the string's closing quote), as a
  `QSyntaxHighlighter` would, but without
  its format for each character of the line (5 ms for a line of a
  megabyte), and not again when only the text's format changed
  (`FormatOnly`: the colors, or a new layout, see Text layout), which
  had it color every line again; in the scratchpad a line of an entry
  pasted with its ID is colored as the listing's highlighter colors it
  instead (`entryColors`, see Scratchpad), and with no syntax colors,
  only those are colored; a line's state (in a `/* */`) is its
  block's user state, as a highlighter's. Only one highlighter may color a
  document (each would take the other's colors away), so Editor.qml takes
  the listing's
  away before giving a file's, and the file's before the listing's. Which
  it gives follows `listing` only as the text is replaced
  (`listingColors`, set in `setText` with no text in, as the line format
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
- **Web files** (web.rs, web.cpp, `web/pre.js`): the web version's home
  dir is kept in the browser's storage: Emscripten's IndexedDB file
  system (IDBFS), which `pre.js` mounts at the home dir before Koil
  starts, and reads in first (a run dependency holds back `main` until
  it's read). It's saved to IndexedDB a moment (300 ms) after Koil writes
  it (`web::disk_changed`, after an apply, undo or create, `Koil.history`'s
  merge, a file saved and an import), one save at a time, and as the page
  is hidden or closed. What's outside the home dir is in memory alone:
  `/tmp` (the scratchpad's file, which desktop never keeps either, what an
  import picked before it's in place, a folder's `.zip` before it
  downloads) and Qt's caches (`XDG_CACHE_HOME` is `/tmp/cache`, set in
  lib.rs, as QML's compiled code went in `~/.cache` and would have been
  saved). The undo history, the trash (`~/.local/share/Trash`, the
  `trash` crate's freedesktop one) and `visited` are in the home dir, so
  they're kept. The first visit (no `~/.local/share/koil/visited`) writes
  `~/welcome.txt`, unless there's one, and opens it, as if it were on the
  command line (`web::first_visit`, in `run`). `Space i` and `Space I`
  (`:import`, `:import!`, File > Import File… and Import Folder…, in the
  listing) open the browser's list of files to pick (an `<input
  type="file">`, `webkitdirectory` for a folder, which every browser has
  as a one-time copy): `Document.importFiles` remembers the open dir, and
  web.cpp's `pickWebFiles` writes what's picked into `/tmp/koil-import`
  (each file, or the folder with its files, by their
  `webkitRelativePath`, without parts that could climb out), then calls
  back `web_files_picked`, where `web::import` copies each into the dir
  (`/tmp` is another file system, which `rename` can't move from), a name
  that's taken getting ` (2)` (` (3)`…) before its extension, as browsers
  name downloads: an import never replaces anything. A browser gives a
  folder's files alone, so its empty dirs don't come. Then `imported`
  shows them in the listing, keeping its edits (`syncListing`, as a change
  on disk does), opens a file alone and lists a folder alone. A browser
  opens its list only right after a key or click, which these are. `Space
  e` (`:export`, `:export path`, File > Export…) downloads the entry on
  the line (the file, in one) or a path from the open dir: a file as it
  is, a dir as a `.zip` that `web::zip_dir` makes in `/tmp` (deflated by
  `zip` with flate2's miniz_oxide, Rust alone, which builds for the web),
  named as the dir (`home.zip`, and a `home` folder in it, for the home
  dir, which is `web_user`), with what's hidden in it but Koil's own (its
  undo history and the trash, in `~/.local/share`), each entry with the
  time it was modified (zip's are local times; without one it's 1980);
  links are followed to files and left out to dirs. web.cpp's
  `downloadWebFile` hands it to the browser as a `Blob` and an `<a
  download>`, deleting the `.zip`. On desktop the keys and commands do
  nothing (they aren't Koil's keys there), and the menu items are hidden.
