# Questions and lists to pick from

- **Questions** (ConfirmDialog.qml): one box asks them all
  (`confirmDialog.ask`), so a new one needs nothing of its own: the
  question in the window's font, with `code` in backquotes as the help
  shows it (a `CodeLabel`), a list under it if it has one, on the
  editor's background in the editor's font, and the choices as buttons
  (`TextButton`s with `keys`: `Yes` `y`, `No` `n`, `Cancel` `c`, and the
  button apart, `extra`, with its key). Yes and No are named by what they
  do (`ask`'s `yes` and `no`: Apply, Undo, Discard, Save and Don't Save,
  Reload and Keep Mine; a conflict's come with it, `Question`'s `yes` and
  `no` in listing.rs, like Delete and Keep), with the same keys, so a new
  question should name them too, and where the other one does nothing,
  be asked with `cancel`, as "No" beside a verb reads as another thing to
  do. Yes is in the accent's color, and Enter answers it, always: h, l
  and Tab moved a highlight through the buttons at first, which was
  little use, and they're the undo history's keys now (see below), so
  nothing moves it, and in a list without groups they do nothing. With
  lines to pick from and none picked, Yes is off, unless the question
  has it take the current row then, as `Y` does (`ask`'s `current`,
  `takesCurrent`: the registers). A
  list of text (not one to pick from) scrolls with `j`, `k`, `g`, `G`
  and Ctrl-D, Ctrl-U, Ctrl-F, Ctrl-B, Ctrl-E, Ctrl-Y, PageDown and
  PageUp, as the help does.
  The box keeps the keys in one handler:
  no button or row takes them (`focusPolicy: Qt.NoFocus`, a `TapHandler`
  a row), as Space picks a row rather than clicks a button. The list is a
  `ListView`, a row a line of `details` or a line to pick from (`ListRow`:
  its box drawn as `Check`'s, and each line of its text a keyword in its
  color and the rest, which wraps under itself; `rowParts`), so only the
  rows in view are made, however many changes there are. A keyword's
  `Text` is as wide as its characters (`charWidth`, a `TextMetrics`, as a
  `FontMetrics`' `advanceWidth` is a function, which a binding doesn't
  follow as the font changes), as a `Text` leaves the spaces it ends
  with out of its width. The box is as wide as the list with no line
  wrapped (`listWidth`, from its longest line, counted in `ask`), and the
  list as tall as its rows (the `ListView`'s `contentHeight`, or until
  they're laid out `listHeight`, counted too, without which it would
  have no height to make rows in). By a list to pick from's buttons are
  a ? button (the keys no button shows, see Help window), Select All
  (`a`) and how many are picked; where the box is too narrow for the list's buttons
  and the choices side by side, the choices go under them (`buttons`, a
  grid of one column then, by `sideBySide`, their width in one row, so
  the box's width doesn't depend on which it is). The layout doesn't
  shrink a button under its width: in one row they went past the box's
  edge in a narrow window. The lines to pick from can be in groups
  (`ask`'s `groups`, the undo history's applies): each a heading row over
  its lines, which are further in, with a box that is its lines'
  (`groupPicks`: a dash while only some are picked; Space on it picks
  those Yes can do, `linesOf`). The list's model is `rows`, what shows
  (`shownRows`: `{ item }` a line, `{ group }` a heading, and `{ more }`,
  the row that says how many more lines a closed group has, with no box,
  as it has no lines of its own), which the current row and `v`'s other
  end index, so without groups a row's index is its line's, as before.
  With groups the cursor has two levels (`inside`, the group it's in, or
  -1). Out of one, `row` is a heading's, and the cursor is on all of that
  group's rows (`cursorRows`, `spanOf`; `selectedRows` for `v`'s), which
  the rows draw as one shape: each goes a pixel under the next, in a
  color made opaque (`Qt.tint` on the base), as see-through ones showed a
  line between the rows, or a darker one where they overlapped; `j`, `k`,
  `g` and `G` go by headings (`moveRow`, `moveToEnd`), and Space, `Y` and
  `D` on a heading are its group's lines. `l`, Right or Tab goes in
  (`goIn`, `putIn`: `enter` is `Popup`'s own), on the group's first line,
  where `j` and `k` stop at its first and last, and `h`, Left or Tab goes
  out (`goOut`), back on all of it. A group asked with `open: false` (and
  more than `preview` + 1 lines: `canClose`) shows all its lines only
  while the cursor is in it (`isOpen`); else `preview` (3) of them, those
  picked first, then the others, in their order (`previewOf`), and the
  row for the rest, so a pick made inside still shows once the cursor is
  out, and an apply of thousands of steps makes few rows until it's gone
  into. A pick can change which show (`syncRows`, after `setPicked` and
  `pickAll`, which makes the model again only if they're other lines).
  After such a group's heading is how many of its lines start with each
  keyword, most first (`groupKinds`, counted in `ask`; `groupNote`,
  styled text, the keywords in their colors and the editor's font), if
  they all start with one, else its `note`, which it shows while the
  cursor is in it. A click picks the line or the group clicked, wherever
  the cursor is, which goes there only where that moves no row (among
  the groups, or to a line of the group it's in), and on the row for the
  rest, or a heading's arrow, the cursor goes into that group
  (`clickRow`). The model is made again as the cursor goes in or out,
  so the list is scrolled back as far as it was, then to the cursor's
  rows (`showRow`: to the last of them, then the first, and twice, as a
  row made as the list jumps to it is placed by a guess of its height,
  which cut the second line of the last row off after `G`). A line is
  told apart by its group's `key` and its text (`itemKeys`), as two
  applies can have the same step, and asked again (`place`), the cursor
  is in the group it was in. `/` in a list to pick from searches it
  (`startFilter`, `setFilter`, a `TextInput` on a line under the rows,
  as the help's, which has the keys meanwhile: `filtering`): only the
  lines with every word typed show (`shown`, `updateShown`: in their
  text or their group's heading, so the undo history's dir counts,
  smart case, the words as they are, not a regex, as paths have `.`
  and `[`), as it's typed, so what was done with a file is found by its
  name. What matched is underlined, in `markColor` (`withMarks`: styled
  text, only where it matched; its regex is kept as its source, as a
  `var` property may not keep a `RegExp`). It's a view only: picked
  lines stay picked, shown or not (the search's line says how many
  aren't shown, not the count by the buttons, whose width the box
  takes), and a group has only its lines that show (`shownItems`, in
  place of `groupItems` for the rows, the cursor, a heading's box and
  Space, Y and D on it, what a closed one shows and counts; one with
  none has no heading), as Select All has. Enter keeps it, with the
  cursor shown (Up and Down move it meanwhile), Esc puts the one
  before back, and Esc in the list clears it before it cancels. The
  list stays as tall as it was (`heldHeight`), so the box doesn't
  change its size at every key. Asked again (`place`'s `filter`), it's
  searched for still, unless no line has it. A row's index isn't its
  line's then, also without groups (`rowFrom`, `place`'s `line`).
- **Lists to pick from** (PickList.qml, ListSearch.qml): the keys of the
  undo history's list are every such list's, whatever it looks like. A
  `PickList` is the list without a look (a `QtObject`): its lines
  (`load`: `{ text, needs, picked, blocked, group }` each, and `groups`),
  which are picked, the rows as shown (`rows`), the cursor (`row`,
  `rowShown`, `cursorRows`), the rows `v` selected (`anchor`,
  `selectedRows`), the group the cursor is in, the search, and what the
  keys do with those. What draws one makes its rows from that, its own
  way (ConfirmDialog's `ListRow`, ShortcutsWindow's `ExportRow`), and
  gives each key event it gets to `key`, which says whether it was the
  list's (`j`, `k`, `g`, `G`, Space, `x`, `a`, `v`, `/`, with groups `l`,
  `h` and Tab, and Esc while it ends something, `stepBack`; and vim's
  scrolling keys, which move the cursor, as the view follows it: Ctrl-D
  and Ctrl-U half a page, Ctrl-F and Ctrl-B, or PageDown and PageUp, a
  page, `movePage`, of `pageRows` rows, which what draws the list says,
  as it knows its room; with groups, out of one, to the group the row
  that far is in, the next one at least; Ctrl-E and Ctrl-Y only ask what
  draws it to scroll a row, `scroll`; Home and End are `g` and `G`),
  then does
  its own with the rest (Enter, the answers' keys, and `Y` with
  `cursorLines`, the cursor's lines or those `v` selected). The search is
  typed on a `ListSearch` put at the list's bottom, which takes the keys
  while `filtering` and gives them back to its `owner`, by `focus`, not
  forced, as a question closed meanwhile mustn't take them from the
  editor. A list tells what draws it that its rows were made again
  (`replacing` before, to keep how far it's scrolled, and `replaced`
  after, to scroll back there or to the top), and the cursor moving is
  `rowChanged`. So a new list to pick from is a `PickList`,
  a view of its `rows`, a `ListSearch`, and `key` in its key handler (or
  a question, as `:reg`'s: see Registers' list); a
  new key for all of them goes in `key`. The names below (`rows`,
  `groupPicks`, `linesOf`, `inside`, `shown`, `place`) are the
  `PickList`'s, a question's being `confirmDialog.picks`.
- **Registers' list** (`:reg`, `showRegisters` in main.qml, vim's
  `registersRequested`): the registers that hold something (those named,
  or all: `Vim.registerList`, `{ name, type, lines, more }` each; the
  clipboard once, as `"+`, which `:reg *` lists too, as `"*` is the
  same), a question with a list to pick from, as the undo history's, so
  with its keys: a row a register, its type (`c` characters, `l` lines,
  `b` a block, as vim's `:reg`), dimmed, and its name in
  `theme.registerName` (a bright amber: `theme.specialKey`'s purple,
  which both were in at first, didn't stand out), so the name is what's
  seen first (its `lead`, of two parts,
  which `leadText` makes styled text of), then what it holds, its lines under
  each other, after the name: the first `registerLines` (5; one more, if
  that's all), then `… 4 more lines`, as a register can hold a file. A
  line is cut off at 300 characters, and where the box ends (`ask`'s
  `cut`), a tab is spaces to its tab stop, as the editor shows it, and
  other control characters are written as `^M`; lines don't show the
  line break they end with, so characters that end with one show it
  (`^J`, which every line break was at first, each register on one
  line). None is picked, and the cursor is shown. Yes is Paste (`y` the picked ones, `Y` the current row's
  or those `v` selected, and so does Enter while none is picked: `ask`'s
  `current`, as going to a register and pressing Enter is what's wanted
  most): `Vim.putRegisters` pastes them after the cursor as `p` does,
  from normal mode, one by its name (`"ap`, so `.` reads it again),
  several as one, each after the one before, joined as `"A` appends
  (lines if any is; `getRegister` takes what a register holds in place
  of a name for it). The button apart is Clear (`d`, `D`):
  `Vim.clearRegisters` empties them at once (set to null, not deleted,
  see QML's JavaScript; the clipboard for `"+`), but those vim
  fills itself (`readOnlyRegisters`), which the status line says can't
  be cleared, and the list is asked again (`again`) with those left, if
  any. It was the help's box at first (`showList`), which only listed
  them.
