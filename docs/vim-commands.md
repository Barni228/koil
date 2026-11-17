# Vim's commands

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
  changes (`U` too, which normal mode doesn't have) and `r` change each
  one where it is (`markedBlocks`, as one edit through `replaceRanges`),
  `S` and `gS` surround each run of them (see Surround), `@` and `Q` run
  a macro on each one, unmarked first, so its keys don't act on them all
  (`runOnLines`, as in visual mode, with a copy of them, as it takes its
  lines from the array it's given), `I`, `A` and `gI` type on each one (extra
  cursors; they stay marked meanwhile, `markedInsert`, so the edits move
  them for `gv`, but aren't drawn, as a block's selection isn't while its
  insert types), and `:` (and `!`
  and `g!`: `bangLines`) types `'<,'>`, which then stands for them
  (`exRange` gives their `lines`: `:s` keeps to them through
  `selectionRegion`, `:!` with `%` runs on their entries, `pathsOnLines`
  taking spans of lines, and a filter takes them together), and a
  shortcut of the user's for visual mode runs on them (see
  Shortcuts). Other keys are normal
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
- **Surround** (Surround in Vim.qml, `parseSurround`): vim-surround's keys,
  `ys{motion}{pair}` (`yss` the line, after its indent), `ds{target}`,
  `cs{target}{pair}` and `S{pair}` in visual mode, which takes the place of
  vim's visual `S` (change lines), and on marked lines, around each run
  of them next to each other (`markedBlocks`), as on those lines selected
  with `V` (`surroundMarked`, all as one edit and one reindent through
  `surroundAll`; asking for a tag, they're drawn as `visualShown`, and
  marked again for the edit, so `gv` marks them where they are). `yS`,
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
- **Regular expressions** (`Txt.regExp`, `regexMatches` in native.cpp): the
  search, `:s`, the find bar and the help's search look for PCRE2's,
  through Qt's `QRegularExpression`, not QML's `RegExp`: Qt's JavaScript
  has no look behind (`(?<!a)b` is "Invalid regular expression"), no
  `(?i)`, `a++`, `(?>a)` nor `\p{L}`, and nothing stops a pattern that
  takes forever (PCRE2 gives up after its match limit, as no match). It
  reads the text as it is (UTF-16, so the positions are the editor's, and
  nothing is copied), compiled to machine code, and the compiled ones are
  kept (`compiledRegex`), as a search asks for the same one at every key
  and scroll. `^` and `$` are a line's (`MultilineOption`), `.` is a whole
  character but no line break, and `\w`, `\d` and `\b` know every script
  (`UseUnicodePropertiesOption`). `Txt.regExp(source, ignoreCase, engine)`
  gives `first`, `all` and `before` (a search backwards), each one call
  into C++ however many matches (`regexMatches` gives numbers: where each
  match and its groups start and end, as the bytes of an `Int32Array`,
  which QML reads three times faster than a list's), and matches as
  `RegExp`'s, with `end`. PCRE2 would check that the text is UTF-16 at
  every match it's asked for, from there to the text's end (32 s for the
  5,000 matches the highlights ask for at most in 10 MB, 7 ms for the one
  at the cursor), so `isUtf16` checks it once and keeps the text it found
  right (which shares it, so it can tell it's the same one), for half a
  minute after it was last asked about, and the matches are asked for
  without the check; a text that isn't UTF-16 (half a surrogate pair) has
  no matches, and a search never starts inside a pair (`characterStart`).
  In 10 MB (200,000 lines), against QML's `RegExp`: the first match, at
  the end, 3 ms (117), none at all 2 ms (115), a search backwards from the
  end 34 ms (196), 19,999 for the find bar 11 ms (31), a match at the
  cursor or the view's highlights under 1 ms (the same), and the first on
  each line with a group, as a `:%s` asks at every key of its preview,
  181 ms (123): 200,000 calls into PCRE2 take 88 of them. After a match of nothing the next is looked for a whole character
  on (`afterMatch`), and `:s` without `g` asks for the first on each line
  (`perLine`, an `l` in the flags). `engine` is `System`, which `Vim` and `HelpPanel` take as
  `regexEngine`; the tests have none, so there it's QML's `RegExp` behind
  the same three functions (`scriptRegExp`), PCRE itself is tested in
  ffi/tests.rs (a test can call native.cpp's functions that need no app),
  and `test_regexEngine` has a stand-in, for the reading of the numbers.
  A look behind can be of a few lengths (`(?<=ab|c)`), but not of any
  (`(?<=a+)`), unlike the path field's (koil-core's `fancy-regex`, see The
  path field), whose regexes are otherwise written the same. Smart case
  (`Txt.ignoresCase`) doesn't count the letters of an escape (`\S`,
  `\p{Lu}`, `\k<Name>`), a group's name or a verb.
- **Substitute** (`:s`, Substitute in Vim.qml): vim's, with `/`'s patterns
  (see Regular expressions; smart case unless the `i` or `I` flag says) through
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
  (`exCommands`, `substituteNames`, `!`, `_!`, `_`, `_put`), a shell command's `%` and `<cfile>` with
  their modifiers (in the dirs' color, as a path) and `\%` and
  `\<cfile>`, `:set`'s options and `:e`'s
  path. It's styled text (`<font color>`), where spaces are `&nbsp;`, as
  styled text runs spaces together; the cursor block is measured on the
  plain text, which is as wide in a font of one width. A new command goes
  in `exCommands`, which both `runEx` and the colors read.
- **Find bar**: moving to a match moves vim's cursor to its start
  (`vim.jumpTo`, which leaves visual mode and breaks an insert); it doesn't
  select it. Its regex option (`useRegex`) is on at first, so Find's seed
  goes in escaped; a query that isn't one shows PCRE2's reason (`error`).
  It asks for as many matches as it shows (`maxMatches`) at a time, and
  for more while whole word or the selection left some out. The current match is the one starting at the cursor
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
