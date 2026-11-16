# The editor

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
- **Text layout** (`TextLayout` in native.cpp): Koil lays out the
  editors' text itself, a `QAbstractTextDocumentLayout` that
  `setLineFormat` puts in place of Qt's `QTextDocumentLayout` (which it
  deletes), with the grid Editor.qml's `fixLineFormat` gives it
  (`lineFormat`). Every row is `lineHeight` tall, the baseline
  `textBaseline` down it, however tall its characters are: emoji come from
  a taller font, which made their line taller in Qt's, and the fixed-height
  block format that made up for it put the baseline at 4/5 of a line, kept
  in 64ths of a pixel (each line drifted a 64th off the grid), and while
  lines wrapped, rows lower than the grid. A new grid isn't an edit: the
  layout lays the text out again as far as it changes it, and has the
  TextEdit take its size, draw its lines again and move its cursor
  delegate, through slots of Qt's that aren't public (`updateSize`,
  `updateWholeDocument`, `moveCursorDelegate`), which `formatting` keeps
  Editor.qml's `ensureCursorVisible` from following. Qt Quick asks a layout
  only what `QAbstractTextDocumentLayout` gives: where a line is
  (`blockBoundingRect`, of which its lines' `QTextLine`s are placed),
  `hitTest`, `documentSize` and `frameBoundingRect`. Each line's rows are
  counted (`RowCounts`, a Fenwick tree), so a line's place is found in
  O(log n) and an edit lays out only its own lines (Qt's moved every line
  after it). Qt's `QTextDocument` calls `documentChanged` with (0, 0, its
  length) both when all of the text went in and when what it's laid out by
  changed (its width, font or wrap mode, or the layout enabled again), but
  tells a change to the text first (`contentsChange`), so one it didn't
  tell lays out only as far as it matters: a new width while lines don't
  wrap lays out nothing (a resize laid all the text out again). It calls it
  while the layout is disabled too (`LayoutPaused`), which lays all of it
  out once it's enabled. `QTextDocument::idealWidth` is the widest line
  only for Qt's layout (a cast), the text's width for any other, which a
  TextEdit takes as its content's, so while lines don't wrap Editor.qml
  makes the TextArea as wide as its widest line (`fitWidth`,
  `System.layoutWidth`) or the view, after each change and resize.
  Clearing the text (`setText`) deletes the root frame, which Qt's layout
  made again as it laid it out; Qt Quick asks for it as it draws, in its
  render thread, where a `QObject` of the document can't be made, so
  `documentChanged` asks first. Qt's selection and `positionToRectangle`
  still use a line's natural (taller) height on emoji lines, so the
  selection is drawn by the app (under the text, `z: -0.5`), and all
  overlays use `cellAt` (the whole row, snapped to the grid). The
  current-line highlight is at `z: -0.6`. Its lines are aligned left, as
  Qt's layout aligns a block: a TextEdit's text option has no horizontal
  alignment unless it's set, and in a line without one, Qt takes a tab as
  wide as its glyph (or nothing) rather than as far as its tab stop, where
  it's drawn and `cursorToX` puts what's after it. So a line with tabs
  was narrower than drawn, the view didn't scroll to its end (`$` left
  the cursor out of it), and `xToCursor` put a click past that width at
  its end. Its tab stops are every `tabColumns` (4) columns, so what's
  after a tab is on the grid of columns (Qt's are every 80 pixels,
  whatever the font); a long line Koil draws itself still has a tab as a
  space (see Long lines). In a debug build, 100,000 lines
  open in 7.5 s (11 with Qt's layout), 10.5 wrapped (20), and an edit takes
  20 to 40 ms.
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
  The layout lays out all of a text again (about a second for 100,000
  lines) when it or its grid changes, and while lines wrap, when the
  editor's width or padding does. So opening one makes it once:
  `System.setText` replaces the text in one edit block (setting it the
  `TextArea`'s way emptied it first, which hid the scroll bar, which
  changed the width), after its grid (`applyLineFormat`, with no text in
  when a file follows the listing or the other way round), clearing the
  document in it (a selection removed stays in its buffer, where Qt's
  positions are ints: a gigabyte opened again after the listing went past
  them and crashed), the gutter gets its width before the text
  (`gutter.fit`), and a file on the command line opens after the editor's
  `onCompleted`, which adds the gutter's padding. While lines wrap, a
  window resize still lays it out again, and so does the scroll bar
  showing up on macOS, whose style makes room for it (Fusion draws it over
  the text): keeping that room even without one saved most of a second,
  but left a strip the text didn't reach.
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
  `FormatOnly` in native.cpp: the colors, a new layout) leave it alone.
  Txt's line index takes the string it's asked with (`lineIndex`), if
  it's the same string, not
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
- **Long lines** (`TextLayout` in native.cpp, `longText` in Editor.qml):
  a `TextEdit` builds only the lines in view, but all of each, so Qt shaped
  every character of a line in view (300 ns each, again when the text's
  width changed) and put a glyph of each in the scene graph: `big` (52 lines
  of a megabyte) took a minute to show and seconds an edit. A line longer
  than `longLength` (10,000) is hidden from Qt (`QTextBlock::setVisible`)
  as the layout lays it out, so Qt never lays it out or draws it, and the
  layout gives it its rows (`rowLength` columns a row while lines wrap,
  anywhere, as finding where words end would read all of a megabyte), so
  the lines after it are where they should be. Koil places a hidden line's
  characters, a column a UTF-16 unit: `longLineSpot` and
  `longLinePosition`, which the TextArea's `rectAt` and `posAt` give in
  place of `positionToRectangle` and `positionAt` (vim's and the overlays'
  go through them), and draws only what's in view of them (`longText`, a
  `Text` a run of one color, from `TextColors`'s formats: `longLineRuns`; a
  tab is a space). Qt's cursor rectangle in a hidden line is at its start,
  however far in the cursor is, so its TextArea mustn't scroll to it: its
  private `ensureCursorVisible` is disconnected (`scrollToCursorInQml`),
  and Editor.qml's does the same (QML handlers run before C++ slots
  anyway), with Koil's rectangle in a hidden line; Qt hides its cursor
  delegate when that rectangle is out of view, so there `carets` draws the
  insert bar, and a press on one (and its drag) is Koil's (the
  `MouseArea`). The layout gives a hidden line's place
  (`blockBoundingRect`) too, where Qt's gave an empty rectangle: Qt Quick
  moves the lines it drew after a change by as much as the first of them
  moved, which put those after a hidden line too far down whenever the
  selection changed (and all the lines in view were drawn again after each
  change of it). With Qt's layout, the line after hidden ones had a top
  margin as tall as their rows, and the text's end a bottom margin, which
  Qt resizing the TextArea left untold. The matching bracket is looked for
  at most `reach` characters away. A `QTextCursor` lays out the line it's
  put in to find its x, so native.cpp reads text with `characterAt` and
  blocks' text (`textBetween`). `big` shows in half a second, and an edit
  takes 0.1 to 0.3 s, mostly V4 copying all 54 MB.
- **Wrapping** (`:set wrap`, a vim setting the Settings window saves, and
  View > Word Wrap, Alt+Z as in VS Code; never in the path field:
  `Editor.wrapping`, `Vim.wrapping`): a line too long for the view goes on
  in rows under it, in the listing too. A row ends where `breaksBefore`
  lets it, the last place that fits: after a space, or where a word
  (letters and digits, as a regex's `\b`, but not `_`) starts or ends,
  but not before a space, nor before what stays with the word before it
  (`staysBefore`: a `,`, `.`, `;`, `:`, `!`, `?`, `-`, `_` or `/`, a
  closing bracket or quote), so `foo.bar` breaks after the `.`, `a/b`
  after the `/`, `snake_case` after the `_`, and `f(x, y)` before the
  `(`, after it or after the `, `. Where none
  fits, where the next character doesn't (`breakRow`: Qt lays the row out
  to break anywhere, and again as wide as up to the place picked and
  halfway into the character after it, which then doesn't fit). In the
  listing (`prefixed`), not in a line's prefix nor right after it, so an
  icon is never alone on its row, and a name's rows after its first start
  under it, not under its icon. Qt's line breaking (Unicode's, UAX #14)
  breaks only at spaces and after a `-` or `/`, and broke after the
  prefix's spaces, which left the icon of a long `snake_case` or dotted
  name alone: nothing lets its breaks be changed, which is why Koil lays
  the text out itself (see Text layout). With notes (sorted by size or a
  date) no row reaches into the notes' room on the right (`noteRoom`,
  `rightMargin`), so each note fits after its line, lined up as in a
  table. The hover box and K's box always wrap so, as the editor would
  (`SelectableText`'s `system`): their rows as tall as the font's lines (a
  `lineHeight` of 0, which follows the zoom). They're sized to their
  text unwrapped (`naturalWidth`, `System.layoutWidth`, rounded up, as a
  layout gives its items whole pixels: a box 399.48 wide got 399,
  and wrapped its last word), which their
  `implicitWidth` isn't with Koil's layout (see Text layout): its rows'
  advances side by side, with the spaces a row ends with, which Qt's
  advance leaves out (laid out narrower first, a box was sized a space too
  narrow, and wrapped at that space again). So it's the same however the
  text wraps, and `measure` doesn't read it again as its own new width
  (a box sized to it) lays the text out again: bound to `contentHeight`,
  which that changes, it was a binding loop whenever a box grew. The wrap
  mode is set by `applyWrapMode`, not a binding: Qt fits
  a `TextArea` to its view's width only as the view or the text's size
  changes, and a new wrap mode had it do that inside its own resize, so
  the wrapped text's height went untold (`contentSizeChanged`, see below):
  the view kept the unwrapped height, and `j` and `G` went past its end
  without scrolling. So `applyWrapMode` gives it the view's width before
  the wrap mode. On macOS the vertical scroll bar is `AlwaysOn` while
  lines wrap: one showing up narrowed the view inside Qt's own resize,
  whose new size Qt doesn't tell then (`contentSizeChanged`), which left
  the content a row short. Qt doesn't tell the room a scroll bar takes
  (`effectiveScrollBarWidth` or `Height`) if that changes while it tells
  the other's (QQuickScrollViewPrivate's `isUpdatingScrollBar`), as when
  both show up or go at once (a text opened, lines starting or stopping
  wrapping), so Editor.qml tells both again once either does
  (`tellScrollBars`): the macOS style's padding kept none, and the text
  went under the bar, the last line under the horizontal one after `G`.
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
  the text out once: `onWrappingChanged` gives the wrap mode and the line
  format (the notes' room) in the order that lays it out only for the
  first (3.4 s for 100,000 lines in a debug build; Qt's laid it out twice,
  in 10). `fixLineFormat` keeps the cursor in view, if it was, as Qt
  scrolls to it only when it moves (a zoom, the notes' room), and
  `showListing` gives the new grid (the notes' room) before it places the
  view, then shows the cursor, whose line a sort can move with the rows
  above it while its place stays.
- **Line numbers** (`:set nu`/`rnu`): the `gutter` is a child of the
  `TextArea` (so it scrolls with the text), kept at `contentX` and drawn over
  text scrolled under it. The styles hard-code `leftPadding` (7 on macOS,
  `padding + 4` in Fusion), so the editor keeps the style's value and adds the
  gutter width (the digits and two spaces) to it. Only visible lines get a row.
- **Whitespace in the selection** (`whitespace` in Editor.qml,
  `whitespaceIn`): in visual mode (and while `:` left it, `visualShown`),
  the selection's spaces show as `·` and its tabs as `→` at their start,
  dimmed (`theme.faint`), as VS Code's `renderWhitespace: "selection"`,
  while `:set visualwhitespace` (`vws`, Koil's) is on: a vim setting the
  Settings window saves (Whitespace in selection, on at first). A run of
  spaces is one `Text` of `·`s from its first, as they're a column each;
  a tab is one of its own, as it ends at its tab stop, and another kind of
  space (an em space, which can be wider) is a `␣` of its own. A no-break
  space is a `·`: Qt gives the text with spaces for them. A line break
  the selection has (`eol`) is a `¬` (vim's `listchars` often has one),
  in the column the selection's shade gives it after the line. Not in a
  listing line's prefix, where the icon is drawn over the space after it,
  and only what's in view, sideways too (`posAt` at the view's edges), as
  a line can be long.
- **Warnings and errors** (`diagnostics` in Editor.qml): Koil's problems
  (see Problems) get a VS Code-style squiggle in the visible lines, and their
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
  view doesn't scroll to them (see Wrapping). After its note, a link's
  line shows where it points (`links`, from `listing::looks` at each
  render and sync, whatever it's sorted by: `→ target`, as written, as `ls
  -l` has it, in `theme.infoColor("link")`, or `theme.error` if nothing's
  there), two spaces after the longest note (`infoWidth`, `noteOf`, which
  the columns are worked out with), so they're lined up too. The notes'
  room while lines wrap (`noteRoom`) is the notes' alone, as a long target
  would narrow every row: a link's is cut off at the view's edge.
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
  fonts like Menlo. A block cursor on an icon (in the scratchpad or a
  file: in the listing it's never on one) is as wide as the icon is
  drawn (`Caret`'s `inkEnd`, from the glyph's `tightBoundingRect`, a
  column at least and two at most), if nothing is drawn in the column
  after it (a space, or the line's end: `spotAt`'s `wide`), rather than
  over the icon's left half. It's also the
  editor's default font
  (`defaultFontFamily`), by the family Qt gives it (`System.nerdFontFamily`,
  as the font has two names, and which one Qt uses depends on the
  platform). Only the regular weight is shipped: the editor draws no bold.
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
