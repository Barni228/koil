# Theme and settings

- **Theme and zoom**: `Theme` (one, in main.qml, passed to every control)
  takes its colors from the editor's palette, so they follow the light or dark
  theme. When the theme changes, a `Palette` emits only `changed`, not its
  per-color signals, so a binding on `palette.base` keeps the old color;
  `Theme` copies the colors on `changed`, and QML reads them from `theme`
  (`theme.base`, `theme.highlight`), never from a palette. It also holds `zoom` (font size / default). Every text in the app grows
  and shrinks with View > Zoom (Cmd+ / Cmd- / Cmd+0), not just the editor:
  text in the editor's font uses `theme.font`, other UI scales its sizes by
  `theme.zoom`. Both are in pixels (`fontSize` too: `font.pixelSize`): in
  points, Windows' 96 dpi (macOS's 72 makes them the same) made the editor
  a third bigger next to the UI. New UI must do the same, and use `Panel` for a box over the
  editor, `Tip` for tooltips (keys that do the same go in its
  `shortcuts`, each shown as code, not in the text; other keys, commands
  like `:set wrap` and file names go in its text in backquotes, which
  `CodeLabel` shows as the help does: `Txt.parseCode`, `Txt.codeHtml`, and
  a shade a line behind each) and `IconButton` for small buttons.
- **Settings**: `settings` (a QtCore `Settings` in main.qml) holds the saved
  values. The ones in use are vim's (`fontSize`, `fontFamily`, `number`,
  `relativeNumber`, `syntax`, `wrap`, `visualWhitespace`, `shell`,
  `dirsFirst`, which `:set`
  changes, as View > Word Wrap does `wrap`: `root.vimSettings`),
  `root.colorScheme`, `root.confirmChanges` and `root.shellEnvironment`
  (see Shell commands), bound to the saved ones at startup. The Settings
  window
  shows the saved ones and changes both (`changeSetting`). The zoom and `:set`
  change only the ones in use, until Koil quits, so the Settings window
  doesn't show them. Their defaults (Cmd+0, `:set fs&`) are the saved values
  (vim's `default*` properties are bound to `settings`), not Koil's defaults.
  Koil's own options (`:set hidden`, `gitignore`, `regex`, `sort`,
  `sortreverse`) aren't saved, and start off (sorted by name). Start in
  (`startDir`, empty for the home dir) is only read at
  startup, with no path on the command line, so the Settings window writes
  it to `settings` alone. It's a dir or pattern as the path field takes it,
  read from the home dir (`Document.startDir`), so it can't open a file;
  the folder button puts a picked one in with `~`. The color scheme sets `Application.styleHints.colorScheme` (Qt 6.8+), which
  also switches the palette, title bar and menus; "system" unsets it. The
  Settings window's size follows the zoom, so it isn't resizable. Its
  settings scroll (`scroller`, a `WheelFlickable`, as a drag selects in a
  field) past
  `maxListHeight` (440 at zoom 1, and never past the screen), with Restore
  Defaults under them, and Tab scrolls to what it goes to
  (`onActiveFocusItemChanged`). The pointer on a setting's name (its
  `SettingLabel`'s `HoverHandler`) shows what it does after a moment, in a
  `Tip` under its row (over it, at the view's end; `rowOf`: GridLayout
  puts the children that show three to a row), from the label's `about`,
  so its note (if any) is a short line. Only the name: anywhere on the row
  (and its note's), a tip showed wherever the pointer rested. They're
  stored in `~/Library/Preferences/io.github.barni228.Koil.plist` on macOS
  (Qt's name for it, from the organization domain main.rs sets and the
  app's name, is the bundle ID, so they're the app's own defaults: one
  that differed only in case would be the same file under two names), the
  registry (`HKEY_CURRENT_USER\Software\Koil\Koil`) on Windows.
