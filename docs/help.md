# The help

- **Help** (HelpPanel.qml): every text in it is a `CodeText`, rich text whose
  `` `code` `` (in the keys column, a key) is in the editor's font, on a shade
  drawn behind the text (`place`), so it still selects and copies. Rich
  text has no inline padding, so letter spacing on the character before a
  code and on its last one makes room for the shade (and copies as
  nothing), and a code's spaces are no-break ones (copied as spaces). Its
  search is vim's (`Txt.searchRegExp`, so smart case, and PCRE2's with its
  `regexEngine`, see Regular expressions), over each text as
  shown (`searchTexts`, keyed by section and part), from the match it went
  to last if that's in view, else from the top of the view; Esc clears the
  highlights before it closes the help. The top of the view is a place
  among the texts (`viewTop`: the first text shown that reaches past it,
  and the character there), not a height, as a search being typed
  unfolds sections, which moves everything under them. A text's matches (`matchMarks`, a
  string per key, so only texts whose matches change are made again) are
  drawn behind it in the editor's colors (`theme.searchMatch`), and made
  black in its rich text. The Repeater deletes old texts some time after
  `shownSections` changes, so a text takes marks only if search went
  through its text (an old one has a new one's key). It must keep the keys
  while it's open, or it stays open with no key reaching it to close it:
  Find, Replace and Find Next/Previous go to its search (`root.find`,
  `root.findNext`), the menu's items that open, save or edit something
  are off while it or a question is open (`boxOpen`), syncing waits (it
  can switch vim's buffer), and if anything else still takes the keys it
  closes (`keepHelpKeys`, leaving them there: `hadKeys`). `:h topic`
  (`show`) unfolds only the section whose `tags` have it, as typed first (so
  `gI` isn't `gi`), then in any case, and scrolls to its row of that key
  if it has one (`shownRow`, `keyRow`: a code in the row's keys, `:h gs`);
  a topic no section has goes to the first row with that key (`:h J`),
  again as typed first. So the keys of the list of changes (`:h pick`,
  "Picking changes") are the last section: before, `:h d` would go to
  its `d` rather than vim's. `<C-a>`, `^A` and `CTRL-A` are `Ctrl-A`. The keys
  starting with `g`, `z` and Space, and the Ctrl keys, have sections of
  their own (`:h g`, `:h z`, `:h space`, `:h ctrl`), as an index of them,
  pointing to the sections that say more. Key names (`:h keynames`)
  lists every name a key can have where keys are written (a shortcut's,
  `:norm`), which are those `Vim.keysIn` reads: a new one goes in both,
  as `test_helpKeyNames` checks each name listed is one key to a macro.
- **Help window** (HelpWindow.qml, main.qml's `helpWindow`): the help
  asked for while a box has the keys is in a window of its own, as `:h`'s
  box would take the box's place: a list to pick from's ? button, or `?`
  there (ConfirmDialog's `helpTopic`, "pick", `askHelp`,
  `helpRequested`; under the list was a row of the keys no button shows,
  `hints`, which took a row and still left most out), opens it at
  `:h pick`, and the question stays as it is under it, with the keys
  again once it closes (`q`, Esc, Cmd+W). It's a tool window (`Qt.Tool`),
  which floats over Koil's other windows, so a click back on the
  question doesn't put it behind the main window, placed once (`place`:
  beside the main window where the screen has room, else over its right
  side), then where the user left it. All it has is a second `HelpPanel`
  that fills it (its size, no dimming, a plain background, set on the
  instance), which closes with it either way: the cheap way, until the
  help's text is a view both a box and a window show. Its Cmd+W is a
  `Shortcut` in the panel, as a modal popup keeps its window's own from
  running. After `?` it opens once the key is up, as the Shortcuts
  window after `Space q` (the Shift can go first, so a modifier's
  release doesn't count). Whatever else points to the help from a box
  or a window of its own does it with a link (see Help links).
- **Help links** (HelpLink.qml, `Txt.helpTopic`): a code that's what's
  typed to show a topic (`:h pick`, `:help set`, or `:h` alone) is a
  link to it wherever it's written, so a text that says "see `:h
  keynames`" needs nothing more: `Txt.parseCode` gives each code its
  `link` (the topic, or null), and `Txt.codeHtml`, given a color, has
  the links in it (`theme.link`, the dirs' blue, as a link in the
  editor). Over each link's shade is a `HelpLink`, a `MouseArea` that
  underlines it (not rich text's underline, which would go on under the
  code's letter spacing), makes the pointer a hand, shades it more with
  the pointer on it, and tells a click (`followed`). In the help
  (`CodeText`, but not a row's keys, which are what's typed: `links`
  off, so `:h` and `:help [topic]` there aren't), a click goes to the
  topic in that same help, box or window (`follow`, `topicPlace`, which
  `show` uses too): its section unfolded with the others as they are,
  so what was being read stays, and Ctrl-O goes back (`goBack`, `jumps`:
  the view, the folds and the cursor's section as they were, which the
  header's keys say while there's one to go back to; `shownY` has the
  view there again once the sections unfolded again are laid out). A
  list in the help's box (About's `:h`) gives way to the help. Anywhere
  else it's a `CodeLabel` with `links` on, which asks for the topic
  (`helpRequested`), and what shows it opens the help window: a
  question's text (ConfirmDialog's own `helpRequested`), and the
  Settings and Shortcuts windows, which have no `:` to type it in
  (main.qml's `openHelp`: the Settings window's Shortcuts note and its
  line by Restore Defaults, `:h set`; the Shortcuts window's hints,
  `LinkHint`: `:h shortcuts` under the list, `:h keynames` under the
  keys a shortcut runs, `:h pick` over the export's list). Not in a
  `Tip`, which goes as the pointer leaves for it. A link has no key:
  it's the pointer's. `test_helpLinks` checks every link in help.js
  goes somewhere, so a new "see" there should name a topic.
- **Help folds** (Folds in HelpPanel.qml): the help's sections are
  folded, each to its title (an arrow before it, as a group's heading in
  a question's list), so `:h` alone is a list of what there's help for,
  and `:h topic` unfolds only its topic's (`showBox`'s `unfold`;
  `unfolded`, by index, replaced, never changed in place). A list
  (`showList`, About) and a command's output have none (`folds`). A
  section that's a `part` of the one before (help.js: how to set an
  option, after the options) has no fold of its own, and shows while that
  one is unfolded (`foldOf`), its title smaller, in the text's color. A
  folded section has no rows (its `Repeater`'s model is empty), so Koil
  starts and the help opens without making every row, which it did
  before. One section is the cursor's (`current`, its title on
  `theme.checked`): `j` and `k` move it (`moveCursor`), but through an
  unfolded one's text first, by scrolling a line while that goes on past
  the view's edge (there's no cursor in the text), as vim's go over
  folds; Enter, Space, Tab or `za` folds or unfolds it (`toggle`; without
  folds, Enter closes the box and Space pages down), as a click on its title does (a `MouseArea`
  over it, so a title isn't selected), `l`, Right or `zo` unfolds it,
  `h`, Left or `zc` folds it (`setOpen`), and `zR` and `zM` do them all
  (`zPending`, which a Shift alone doesn't end). Scrolled out of view any
  other way, the cursor's is the first in view (`followView`). A search
  goes through every text, folded or not, and unfolds the section of the
  match it goes to (`reveal`), as vim's does; cancelled, the folds and
  the cursor are as they were (`leaveSearch`). A section's rows are made
  and laid out only as it unfolds, so what the view should show is kept
  until the user scrolls (`settle`, as the layout changes; `unsettle`):
  `:h`'s section and row, the match a search went to, or the section
  just folded or unfolded, as much of it as fits from its title.
- **Scrolling boxes**: the help, the hover box and the settings are
  `WheelFlickable`s: `Flickable`s that aren't interactive (a
  drag selects their text), scrolled by a `WheelHandler`. It needs
  `acceptedDevices` with
  `PointerDevice.TouchPad`: by default it takes only a mouse wheel, and the
  trackpad's scrolls go to the popup, which drops them. A question's list
  is a `ListView` scrolled the same way (see Questions).
