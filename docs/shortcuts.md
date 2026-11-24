# Shortcuts and menus

- **Shortcuts** (`Vim.shortcuts`, ShortcutsWindow.qml): the user's own,
  any keys (`Space c`, `gc`, `<C-k>`, written as `commandKeys`' are) that
  run keys of theirs as `@` runs a register's
  (`runKeys`: in chunks, one undo step, Esc stops it, a count runs it that
  many times), in normal mode, visual mode or both, wherever vim is (the
  listing, the path field, a file, the scratchpad). `commandFor` matches
  them after `commandKeys`, which are normal mode's only; in visual mode
  too, so Space there waits for a key rather than moving (`Space q` is
  one), and Space and another key is a bad command. While lines are
  marked (`parse`'s `marking`), visual mode's match too, before normal
  mode's with the same keys (or that start them), still after
  `commandKeys`, and their keys run with the lines marked, so `:`, `d`,
  `>` and `S` in them act on those as on a selection (see Marked lines).
  They come before
  vim's own keys, as a vim mapping does: a shortcut on `xa` makes `x`
  wait (no timeout tells it apart), and any key but `a` after it is a bad
  command; `gc`, which vim reads as a bad command, takes nothing. A macro
  recorded meanwhile keeps the shortcut's keys, not what they ran.
  Their keys run other shortcuts (as macros recorded with them need),
  which can loop (see Macros).
  They're saved in `settings.shortcuts`, as JSON of `{ name, keys, macro,
  normal, visual, enabled }` (`readShortcuts` drops what isn't one, as
  the settings can be edited by hand), which Restore Defaults leaves
  alone, and only the enabled ones with keys reach vim. The form has a
  checkbox for each mode, and one in neither can't be saved; Koil's own
  (`root.ownShortcuts`) say their modes the same way. Koil shows keys
  with Space as a word (`Vim.keysName`: `Space gc`), in the list, the
  form and the status line's run. The window (`Space q`, Koil >
  Shortcuts…, `ApplicationSpecificRole`, which puts it in the app menu;
  File > Shortcuts… elsewhere; and a button in Settings) lists each by its
  name, else its keys, else the keys it runs, and under them, while the
  lock button by + is on (`root.showOwnShortcuts`, saved, off at first),
  Koil's own
  (`root.ownShortcuts`: `commandKeys`' of every buffer, by hand, with
  where they work; `gs` for the sort keys), under a heading, each with a
  lock rather than a pencil and a trash, dimmed where they do nothing
  (`commandHere`: none of `commandKeys` starts with them). A click on one
  (or Enter) closes it and runs it in the main window
  (`runShortcut`), even one that's off or has no keys: in visual mode if
  vim is in it and the shortcut is for it, else in normal mode, which vim
  goes to first; Koil's own as if typed in normal mode
  (`vim.startCommand`), only where they do something; not while a box
  has the keys or a shell command runs.
  Its pencil shows it in a form, as + (or Cmd+N) does a new one, which Save
  saves (Esc and Cancel go back to the list), and its trash deletes it at
  once. Its export button (by +) shows a page of its own (`exporting`,
  `startExport`) with a box before each shortcut, all picked at first,
  a list to pick from (`exportPicks`, a `PickList`, see Lists to pick
  from), so with a question's list's keys, though it looks as the
  window's lists do: `j` and `k` (Up and Down) move, Ctrl-D and the like
  by pages, Space, `x` or a
  click picks the current one or leaves it out, `a` all or none, `v`
  selects rows (drawn in `theme.marked`), `/` searches them (by name,
  keys and the keys they run; its line shows only then), Enter exports
  the picked ones, and `Y` the cursor's or those `v` selected
  (`exportCurrent`, `exportOnly`), and Esc ends a selection or a search
  before it leaves the page (`back`). The list's current row is the
  cursor's (`showExportRow`), which a `ListView` gives the keys, so the
  row hands them to the list's handler before its own (`pressed`: as a
  button, Space would click it). Then a `FileDialog` asks where, and
  `writeExport` saves them as JSON: a list of them as `settings.shortcuts` has it, so a
  file can be edited, or put in the settings, by hand (on the web,
  `chooseExportFile` writes it to `/tmp/koil_shortcuts.json` and the
  browser downloads it, as `:export` does). Its import button
  asks for one (on the web, `chooseImportFile`: the browser's picker,
  through `Document.pickFile`, whose `filePicked` gives where it put the
  file), and `importFrom` adds what `app.readShortcuts` reads of it
  after the user's, but those already there (the same keys running the
  same keys in the same modes); one that's on, but whose keys can't be
  used there (`problemOf` against the list so far: a built-in's, like
  Windows' Ctrl menu keys, or another's that's on; or Cmd keys off
  macOS), comes in off, keys and all, for the user to change. The list's
  hint then says what it did (`message`, `failed` for why it couldn't),
  until anything else is done. Neither goes through `Document`'s
  `saveFile` or `openFile`, which would take the file for the one shown
  (`readText`, of 1 MB at most, and `writeText`). `Space q` opens it once the key is up (`openShortcuts`, on the
  editor's `keyReleased`, or 300 ms later for a macro's keys): opened while
  `q` was down, its release went to the new window, and macOS's text input
  (which watches a held key for its accent menu) logged
  "TSMSendMessageToUIServer: … FAILED" up to three times. A window becoming
  active still logs it now and then (Settings too), which nothing here
  causes. In the form, Enter saves whatever has the keys (a `Shortcut`, as
  Return is a macOS dialog's default button, which `primary` colors), and
  Space clicks a button. Everything in it is reached with Tab (`tab`, a list of what each
  page has, which every control there hands Tab and Shift+Tab to, but
  the key box, which types Shift+Tab): Qt's
  own Tab reaches only text fields and lists on macOS unless Keyboard
  navigation is on in System Settings, and skips every button. The list
  has no keys of its own (it had vim's `j`, `k`, `e`, `a` and `/`): the
  search over it has them whenever the list shows (`focusSearch`), so
  typing searches, Up and Down pick a shortcut, Enter runs it, and Tab
  goes to the picked one's pencil and trash, then +. The search shows only
  the shortcuts every word of it matches (`shown`, `shownOwn`, `matches`:
  in the name or the keys it runs, or a word of its keys as shown,
  `space` or `gc`, as a part of "space" would match every shortcut with
  Space). Esc empties it, as in a macOS
  search field, and with none, closes the window (`back`). A row gets its
  shortcut with its index (`rows`: `{ at, shortcut, own, heading }`), not
  the index alone, as the shortcuts change before the list does, which
  left a deleted one's row reading past their end. Opened anew, it has no search, on its
  first. Its shortcuts, and Settings' (Esc, Cmd+W), are on only while
  their window has the keys (`focused`: its `activeFocusItem`, which is
  null otherwise): with Qt Quick Controls loaded, a `Shortcut` takes its
  window as active while any of the main window's family has the keys,
  so Esc in the editor closed them, and with both open, their Escs were
  ambiguous and neither ran. Space or Enter clicks a
  button (`TextButton`, `IconButton`), and Space flips a checkbox
  (`Check`). While the macros are listed, their popup's window gets the
  keys (so it has `focus`, and both it and the button handle
  them: `macroKey`), and the window asks to be active again once it
  closes, as Qt's offscreen platform left the popup's. The form's key box
  takes the keys typed, as vim names them (`typeKey`, `Vim.tokenFor`:
  Backspace takes one back, Cmd+Backspace all; Tab, Enter and Esc alone
  go to the form, so no shortcut has them, but with a modifier they're
  keys, and Shift+Tab is `<S-Tab>` there, not a step back). On macOS, Cmd
  and a letter, digit or sign is a key too (`<D-k>`, `<D-K>` with Shift,
  as MacVim names them), in the box and in the editor, where only a
  shortcut does something with it (else it's a bad command); Cmd+W goes
  to the box rather than closing the window. A key with a name
  (`keyName`: Esc, Enter, Tab, the arrows, Home, End, PageUp, PageDown,
  F1 to F35) is one of its own with Shift, Ctrl or Cmd (`<S-F12>`,
  `<C-S-Left>`, `<D-Esc>`: `modifiedName`; not Backspace and Delete, and
  Alt alone isn't told apart, as Option types characters). Ctrl takes a
  letter, digit or sign as Cmd does, each the character Shift makes of
  it (`<C-K>` is Ctrl+Shift+K, `<C-?>` Ctrl+Shift+/, as `<D-K>`; not
  `>`, and Ctrl+[ alone is `<Esc>`, so `<C-[>` is no key), and `S-` goes
  only before a key with a name: Qt gives a sign as Shift has it, so
  there's no telling `<D-S-/>`, and one rule covers letters too. Every
  modifier held is in a key's name, in one order, Ctrl, Alt, Cmd, Shift
  (`C-`, `M-`, `D-`, `S-`: `<C-M-k>`, `<C-D-K>`, `<C-M-D-S-Left>`),
  which `keysIn` reads only so. Alt is one only with Ctrl or Cmd, as
  alone it types characters or opens a menu, and off macOS not where
  Ctrl+Alt types one (AltGr, by the event's text). But a letter or digit
  that is the key's own isn't AltGr's: where Ctrl+Alt types nothing,
  Windows gives the key's character, a letter uppercase (Ctrl+Alt+K and
  Ctrl+Alt+Shift+K come with "K", Ctrl+Alt+1 with "1"), which ran `K`
  and started a count, and AltGr never types those. A sign it gives as
  well (Ctrl+Alt+/ with "/") can't be told from one AltGr types, so it
  types it. On macOS, Qt gives
  the letter as the key whatever is held (Option too, though the text is
  `˚`), and a digit or sign with Ctrl as it is, or as Shift has it,
  tried with System Events' `key code` on a window that logs its key
  events, and on Windows with `SendKeys` on one; untried elsewhere.
  F-keys, Shift+Tab, the Ctrl and Cmd ones
  with a name, a digit or sign with Ctrl, and a character with Ctrl or
  Cmd and another of the two or Alt, are keys only a shortcut takes
  (`shortcutOnly`): without one they're no command, an error which ends
  the one typed (see Unknown keys; until they had names they did
  nothing, not even end it, and so until that said so), and in replace
  mode nothing (`runKey` reads them only if a shortcut takes the keys
  so far with them), and Enter's make no line break in the path field.
  Shift and a key vim knows (`<S-Esc>`, `<S-PageDown>`) is that
  key alone, and Ctrl+Shift and a letter is Ctrl and the letter (`<C-K>`
  is `<C-k>`, as vim reads it, also written by hand; `keyPressed` reads
  it so before its own Ctrl+V, and a macro records the `<C-k>`), but for
  a shortcut that takes it in normal or visual mode
  (`unshifted`), as Shift+Enter is `<S-CR>`, and but for the arrows, Home
  and End in the command line, which select there. Keys a shortcut (or
  `commandKeys`) takes, or starts with, where vim alone has no command of
  them, go to it before the editor's own standard keys (`shortcutTakes`,
  first in `keyPressed`): on macOS Ctrl+K is one of Qt's Cuts and Ctrl+Y
  one of its Pastes, which swallowed a shortcut on `<C-k>`, and
  elsewhere Ctrl+A is Select All. They can't be Koil's own, start
  them, or start with them (`g`, `g.x`), nor a key Koil's menus or the
  editor's copy, paste and undo take before vim gets it
  (`root.menuShortcuts`, which the list doesn't show: Cmd keys on macOS,
  with Replace's `<M-D-f>`, Ctrl elsewhere), nor another enabled
  shortcut's,
  in the same mode, nor start with a count or `"`, which vim reads first
  (`problemOf`). What of vim's they take the place of is said, in the
  warning's color, but they can be saved (`noteOf`, `Vim.vimCommandIn`:
  `parse`'s `plain` reads vim's keys alone; not where Koil's own already
  took them, as Space). The keys it runs are typed as `q` records
  them (`<CR>`), or taken from a register `q` records into
  (`Vim.macroList`). The names of keys in them are colored
  (`theme.specialKey`, `styledKeys`, from `Vim.keyParts`, so only what a
  macro reads as a key), in the field, the list and the macros: the
  field's own text is clear, and a `Text` over it draws it, at the
  cursor's place less the text before it, so it follows the field's
  scrolling (a font of one width, so the colors move nothing). Qt draws
  the cursor in the text's color, so the field has its own
  (`cursorDelegate`), which blinks as Qt's does. The window's height is the form's, worked out before
  the form is first laid out, when a wrapped text is measured too tall, so
  its hint is one line.
- **Shortcuts**: use `StandardKey` where Qt has a binding. On macOS
  `StandardKey.ZoomIn` also fires on Cmd+=; on Windows it doesn't, so that
  menu uses "Ctrl+=" plus a `Shortcut` for Ctrl++. The Windows/Linux menu
  writes "Ctrl+," and "Ctrl+Q" as plain strings, because `Preferences` and
  `Quit` have no Ctrl binding on Windows. "Ctrl+0" has no `StandardKey`. In
  strings, Qt maps Ctrl to Cmd on macOS, and in the web version on a Mac
  (see Web), which is why main.qml's `isMac` (macOS's keys and key names,
  passed to Vim, FindBar, the help, the dialogs' lists and the Shortcuts
  window, whose own default is the platform's, for the tests) is apart
  from `macApp` (the desktop app on macOS: its menu bar, Finder, the
  `koil` command).
- **Menus**: QtQuick Controls menus have no `role` property, so macOS uses
  `Qt.labs.platform` MenuBar with `AboutRole`/`PreferencesRole`/`QuitRole`,
  which moves the items into the app menu (`MacMenuBar.qml`). Windows and
  Linux use an in-window Controls `MenuBar` (`WindowMenuBar.qml`), with the
  same items (About in a Help menu), so a change to one goes in both. So
  does the web version, also on a Mac, where there's no menu bar of the
  system's: its `Shortcut`s that add Ctrl++ and Ctrl+G go with
  `WindowMenuBar` (`!macApp`). About
  Koil (main.qml's `about`) shows the version (`Qt.application.version`,
  which lib.rs sets from Cargo's) in the help's box. One is created in main.qml's
  `Component.onCompleted`, so only one exists at a time. Qt titles the PreferencesRole item "Preferences..."; a `QTranslator`
  for the `MAC_APPLICATION_MENU` context renames it to "Settings…".
