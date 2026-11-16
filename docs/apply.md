# Applying, undoing and quitting

- **Apply and undo**: `Space Space`, `Space a`, File > Apply Changes… update,
  then `ConfirmDialog` lists `listing::actions` (paths relative to
  the open dir; `Koil::changes`, so a swap is its two renames, not the
  three steps through a temp name), a row each, with a checked box before
  it, all picked.
  The user leaves some out (j and k move the current line, Space or x or a
  click on the row toggles it, a or Select All picks all or none; the
  current line is highlighted only once one of those keys is used, and
  the first j or k only shows it, on the first line), and a line goes with
  what it needs (`needs`: a swap's other half, the new dir a file goes
  in): picking one picks those, leaving one out leaves out what needs it.
  Copy copies the list as text (the lines `v` selected, or all of it:
  `copyText`), as its rows can't be selected with the pointer. The
  question counts what's picked, and stays over the
  list as it scrolls. The word a line starts with is
  colored by the change it stands for (`root.changeKeywords`, passed to
  `ask` by the apply, undo and create questions only, as a conflict's
  lines are paths; `theme.changeColor`): CREATE and RESTORE green, DELETE
  and TRASH red, MOVE yellow, COPY blue (`rowParts`). Yes applies the
  picked lines (`Koil.apply(picked)`, indexes into the `shown` actions
  `actions()` kept, given to `Koil::apply_only`, so only what the user saw
  is applied), and the rest stay pending, to apply later: koil-core moves
  them along with what was applied (a change inside a renamed dir follows
  it, one inside a deleted dir goes with it) and keys each by the path its
  file is at now (`Diff::after_steps`, `Koil::rekey`), so the status line
  says how many are left ("2 changes applied, 3 left"). Leaving a line
  out isn't discarding it: Discard (`d`, `ask`'s `extra`, as Delete from
  History is in the undo history's) takes the picked lines back instead
  (`Koil.discard`, `Koil::discard_only`: the diff without them, and
  without those that need one, which couldn't be applied, so it can
  discard more than is picked; nothing on disk changes), and shows the
  listing again as an edit (`showListing` not `moved`, as the IDs stay),
  which `u` takes back, but only for what the listing shows (another
  dir's changes are gone). With none picked, Yes and Discard are off
  ("Pick what to apply or discard"). After either, if any are left, the
  question is asked again about those (`askAgain`, from the listing as
  it is now), so what was left out can be applied or discarded next, as
  if it never closed (`ask`'s `again`): a line still there (by its text)
  picked as it was, so all left out, as the picked ones went (and so is
  one whose text changed, a move inside a dir that was renamed), the
  current line on its line, or the next one left, and it highlighted,
  the list scrolled and the choice highlighted as they were; not after
  one that failed, whose error the status line shows. `u` there
  (`ask`'s `undo`, `undoInApply`) undoes the listing's edits, as Esc, `u`
  and Space a would (from the path field too), as far back as changes
  what applying does: an update can be a step that doesn't (a renamed
  entry's icon), which the next update would do again, so `u` never got
  past it. Koil reads the listing after each step (`readListing`, the
  update of `tryUpdate` without showing it), and it's shown once, after
  the last, then asked again with the current line at the same index
  (`ask`'s `row`), the lines still there picked as they were, and one
  that came back picked (as a discarded one was). With nothing left in
  vim to undo since an apply made from the question (after which vim
  started over), it undoes that apply as if it never ran
  (`undoApplied`): `Koil.apply` gives an `unapply` with it (its time,
  how many lines it applied, and what was pending before it,
  koil-core's `Koil::pending`), which main.qml keeps with the listing as
  it was, its text and vim's buffer (`appliedFrom`, newest last), and
  `Koil.unapply` gives back to `Koil::unapply`, which undoes it while
  changes are pending (only the last apply), and has what was pending
  before it pending again, the applied changes too, in every dir; vim
  gets the listing back, undo history and all, so the next `u` goes on
  from there, and the question is asked as it was before it (its
  `place`), the applied lines picked again. A new question starts over,
  and so does one that fails, as the older ones need it undone first.
  With nothing in vim to undo and no apply made from the question, it
  says so, rather than ask to undo the last apply (which can't be undone
  while there are changes). `v` there (in any list to
  pick from) selects lines, from the current one to where `j` and `k`
  (or `g` and `G`, the first and last line: `moveToEnd`) take it (`anchor`, drawn in `theme.marked`), which Space or `x` then
  picks, or leaves out if they're all picked (`toggleSelected`), ending
  the selection, as `v`, `a`, a click and Esc do (Esc cancels only
  then). The uppercase of a key that acts on the picked lines acts on
  the current line, or those `v` selected, picked or not, in any list to
  pick from (`answerHighlighted`, `answer`'s `lines`, `chosenLines`; the
  first only shows the current line, if it isn't yet, as `j` does): `Y`
  (Yes; not on a line Yes can't do) and `D` (Shift and the button
  apart's key: Discard here, Delete from History in the undo history,
  which lists what it deletes, `forgetApplies`). What takes more than was
  chosen asks first, listing them all (`confirmMore`): an apply or an
  undo the lines it needs (`withNeeds`: `applyLines`, `undoLines`), and
  a discard the lines that need it (`withDependents`: `discardLines`,
  `d`'s too); Cancel asks the list again as it was before (`ask`'s
  `again` taking what `place` gave), and Yes does it, then asks it again
  so (`applyPicked`, `discardNow`). The choice that isn't Yes is Cancel (`ask`'s `cancel`), as it
  leaves them all as they are (No would read as leaving them out). After an apply vim starts
  over (koil refreshed: new IDs for renamed paths), with the cursor where it was (`listingSpot`: the
  same line; the listing's cursor even while vim is in the path field) and
  the view as it was; so does undoing an apply. If an action fails, those
  that didn't run stay pending too. The "Ask before applying" setting
  (`confirmChanges`: always, when deleting, never; `asksFirst`) can skip
  the confirmation (but not `Space a`'s or File > Apply Changes…'s: `ask`),
  applying every line (`deletes` says which delete), and Enter's create's
  too. `:confirm q` and `ZZ` always ask, and their question is whether to
  quit without the changes; there, what's left out is lost with them
  ("Apply 2 of these 5 changes and quit without the rest?"), and there's
  no Discard, as No quits without them all.
- **Undo history** (`undoApply`, koil-core's `Koil::undoable` and
  `Koil::undo_some`): `Space u` (from the listing or the path field)
  updates (vim's undo may have taken the buffer back past an update) and
  lists the applies (and Enter's creates) koil can undo, newest first, in
  `ConfirmDialog` (`listing::history`, a `HistoryList`): each a heading
  (a group, see Questions: its time, and its dir if it isn't the open
  one, with how many changes it has at the row's end), over what undoing
  it does, a step a line to pick from, relative to its dir, so one change
  of an apply can be undone without the others (it was all of an apply
  or nothing). The cursor is on all of an apply at first, as it was
  when an apply was a line: `j` and `k` go from apply to apply, Space
  picks all of one (its heading's box shows whether all, some or none
  are picked), and `Y` and `D` take it. `l` (or Right, or Tab) goes into
  it, where the cursor is on one of its steps, and `j` and `k` stay in
  it, until `h` (or Left, or Tab again) goes out. An apply with more
  than `SHOWN_STEPS` (10) steps shows only three of them while the
  cursor isn't in it, those picked first, then a row that says how many
  more it has ("… 21 more"), and its heading says how many of its steps
  are of each kind, in their colors (`16 MOVE · 4 TRASH`), in place of
  how many it has, so what's in it can be told without going in; going
  in shows them all, as a click on that row or its arrow does. The
  time is in the color of how old it is
  (`listing::age`, by what `time_ago` counts it in; `theme.ageColor`:
  under a day cyan, days blue, weeks purple, months dim, a year or more
  faint, so the newest stand out, and none is a change's color), which
  main.qml gives the heading as its `lead` (`{ length, color }`, the
  start of a row's text in a color: `rowParts`); koil refuses while changes are pending.
  None is picked at first, and the first row is highlighted at once
  (`ask`'s `showRow`). `/` searches them, as any list to pick from (see
  Questions): typing a file's name shows only what was done with it,
  and the applies that have it. `u` or Cmd+Z with nothing left
  to undo in vim emits `nothingToUndo`, and `undoLast` asks only about
  the last apply alone: "Undo the last apply?"
  over every step undoing it does, relative to the open dir
  (`HistoryApply::steps`), all of which it undoes, or says why it can't
  be undone (`HistoryApply::blocked`, the apply's as a whole). Not from the
  path field, whose undo history is its own. A step needs the steps that
  run before it (a newer apply's, or one before it in its own) that
  changed a path it changed, or one in it or that it's in
  (koil-core's `UndoableStep::needs`), which picking it picks. One that can't
  be undone now (koil-core checks it against the disk, with the steps
  it needs: something gone, or taken, or emptied from the trash) says
  why on a line under it, in the error's color, and is dimmed, with a
  crossed out box (`blocked`, the reason), but the other steps of its
  apply can still be undone. Yes undoes the picked
  ones, newest first (`Koil.undo(picked)`, indexes into the steps
  `history()` gave, which `Koil` keeps as `shown_steps`, each an apply of
  `shown_history` and one of its steps: `picked_steps`), and is off while one that
  can't be undone is picked (`blockedPicked`); a step koil can see won't run
  undoes nothing. An apply keeps the steps that weren't undone, under
  the same time, and goes once it has none. Delete from History (`d`; `ask`'s `extra`, a button
  on the left, apart from the choices, where the highlight doesn't start,
  so Enter answers it only once it's moved there, and off while none is
  picked) asks again, then forgets the picked steps
  (`Koil.forgetHistory`, `History::forget`, by their apply's time and
  their index in it, also for other Koils; an apply keeps its others),
  so they can't be undone: it's what one that can't be
  undone is picked for (its box filled in the error's color, with a
  cross; `a` picks only the others). An older step that needed one deleted is then checked
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
- **Changes on disk** (koil-core's `Koil::sync`; read its CLAUDE.md): the
  listing shows what changes on disk as it happens, keeping the user's
  edits. `Koil.watch()` (after every `showListing`, sync and answer) has a
  `notify` watcher watch what `Koil::watched` says, and the dirs whose
  sizes are kept (see Stale sizes), changing only the watches that
  changed, at once (`paths_mut`: on macOS each change restarts the
  FSEvents stream), and only if the dirs did. Its thread
  skips reads, writes (unless sorted by size or a date, see Sorting) and
  events `Watched::affects` says can't matter (`Filter::matters`), but
  not a `chmod` that makes a file listed one that can be run, or one that
  can't any more (see Colors): it comes as a change of metadata, as a
  write's new time does, so for a file listed (`Filter::files`, from
  `listing::looks`, by its path) the thread reads its permissions again
  (`listing::runs`), which costs a write one `lstat`, and only a change of
  what its name shows syncs. Then it
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
- **Quitting**: `:q` with unsaved changes fails (E37); `:confirm q` asks
  instead, in a `ConfirmDialog` rather than a `MessageDialog` (which is native
  on macOS, can't use the editor's font or vim's keys). `ConfirmDialog.ask`
  takes what Yes and No do; without a No action it offers only Yes and No.
  Every file shown has a path, so with none (nothing is shown: the home
  dir couldn't be listed) `:w` is vim's E32.
