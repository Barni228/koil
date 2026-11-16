# Vim

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
  and `nostartofline`: `H`, `M`, `L`, `N%` (`keepCol`), `:N` and the
  commands on whole lines (`dd`, `>>`, `==`, visual and marked lines'
  `d`, `>`, `<`: `toLine`) keep the cursor's column, which j and k then
  go on from (`colKept`). But `gg` and `NG` go to the line's first
  non-blank, as Vim's `startofline` has them, and `G` alone to the
  text's last character. Only the `"+`/`"*`
  registers use the system clipboard. Cmd+V in the command line (Ctrl+V
  too, as in insert mode: `pasteInCommandLine`, from `keyPressed`, as its
  `<D-v>` is a key the command line drops) types the clipboard's text
  at its cursor, as one line: its line breaks spaces, but those it ends
  with (a yanked line's), and a macro being recorded keeps the keys that
  type it, not the paste. The command line has a text field's other keys
  too (`commandLineEdit`, before vim's own, `commandLineKey`): the
  arrows move by a word with Option (Ctrl off macOS) and to the line's
  ends with Cmd (Home and End), and select with Shift (`commandAnchor`,
  the selection's other end; `commandSelecting` and its start and end
  are properties, for the status line's bindings); Backspace and Delete
  take a word with Option, or the selection; Cmd+A selects all of it,
  Cmd+C and Cmd+X copy and cut what's selected (the text alone, to the
  clipboard, not through a register), and what's typed or pasted takes
  its place. Ctrl+C with nothing selected still closes it, as in vim
  (it's Copy on Windows). They're read from the key event, as Option
  isn't in vim's names for keys (it types characters on macOS), so a
  macro being recorded keeps what they did as vim's keys: each move of
  the cursor as `<Left>`s or `<Right>`s (`moveCommandCursor`), and what's
  deleted as `<BS>`s (`deleteCommandRange`), so it runs the same with
  nothing selected. Any of vim's keys ends the selection, but not a
  modifier alone (no token), which Cmd+C starts with. StatusLine.qml
  draws the selection in the editor's selection colors, its text again
  over it, and no cursor then, and gives the pointer's presses
  (`commandLineClick`: a press puts the cursor there, Shift or a drag
  selects; `commandLineWord` for a double click), finding the place by
  the widths of the line's starts (`commandPositionAt`); its `MouseArea`
  never takes the keys, which stay the editor's. Registers follow vim's (`setRegister`): `"0` only yanks,
  deletes and changes go in `"1` (shifting to `"9`) or `"-`, and `".`,
  `":`, `"/` and `"%` (`fileName`: the file, or the listing's location)
  are read from vim's state and can't be written. `p` says how many
  lines it added, if more than two ("3 more lines"), as `y` and `d` do
  theirs (vim's `report`). `:reg` (`:di`) lists
  them to pick from (see Registers' list). A yank
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
  `Ctrl-U` in the command line, nothing in the other modes. A
  `TextInput` (every other text field: the find bar's, the help's
  search, the Settings and Shortcuts windows') deletes a word on it
  (Qt's Ctrl+Backspace, as Qt reads Cmd as Ctrl), so native.cpp's
  `LineDeleteFilter`, an application's event filter (`useLineDeleteKey`
  in main.rs), has it delete back to the field's start, or the
  selection, through `remove`, which Cmd+Z undoes. With nothing to
  delete, the field's Keys handlers have it (the help's search closes). Other Cmd
  keys (`<D-k>`, `<D-Left>`, see Shortcuts) do nothing but run a
  shortcut: insert mode leaves them to the editor (Cmd and an arrow), and
  the command line drops them.
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
    clipboard; see Clipboard for `session`).
  - Qt's native Backspace deletes one code point, so vim handles Backspace in
    insert mode, and cursor steps go through `Txt.charStart`/`charEnd` (never
    `±1`), which treat an emoji with its modifiers as one character, as Qt
    does. Columns count characters (`Txt.column`, `Txt.atColumn`).
  - Resting the mouse on an icon (a `HoverHandler`) or `gh` (with nothing
    under the cursor, a problem say, on the icon the cursor's line starts
    with: the listing's, which the cursor is never on, or a pasted entry's)
    shows its text in the `HoverBox`, in the window's `Overlay` (so the
    editor doesn't clip it).
    Its text is a read-only `TextEdit` that never takes focus, so keys stay
    with the editor, which forwards Copy to it. Any other key, a scroll or an
    edit hides it; one the mouse opened also hides 300 ms after the pointer is
    on neither the target nor the box (and isn't dragging a selection).
