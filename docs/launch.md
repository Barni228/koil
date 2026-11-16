# Starting Koil

- **Command line** (cli.rs, read in `main` before the app, so `--help`
  doesn't show it in the Dock): `koil [OPTIONS] [PATH] [+N]`, parsed by
  clap's builder (`arg!`, not derive), its help and errors clap's (exit
  2), printed by `clap::Error::exit` once `attach_console` ran. The path
  is as under Files (one: more is most likely a pattern the shell
  expanded, which the error's tip says to quote). `-s` (`--scratchpad`,
  aliases `-t`, `--temp`) starts in the scratchpad, over the file or the
  listing of the path (`startUp` in main.qml, `startScratch`; over a
  file that can't be read, its dir's listing, on its entry). Text from
  stdin goes in it too (`Document.takeStartupText`), read to its end
  before the window opens, as vim's `-`: with `-` (from a terminal too,
  until Ctrl-D), or else if stdin is a pipe or a file (`piped`: not
  `/dev/null`, which an app launched from Finder or the Dock has, nor a
  device that never ends, like `/dev/zero`) and has something in it.
  Unlike a file, it's shown whatever it is, with what isn't text as `�`
  (`document::decode_lossy`). `-p` (`--print`) starts in the scratchpad
  too, and prints its text to stdout as Koil quits, however it quits
  (`onAboutToQuit` in main.qml: `scratchText`, shown or kept, without a
  `:s` preview; `Document.printScratchpad`, `cli::print_scratchpad`),
  as it is, with no line break added (`hi` prints `hi`), so Koil can
  edit text in a pipe (`ls | koil -p | sort`, as `vipe`). Nothing else
  Koil does writes to stdout, and what it starts that could (Space r,
  Space o's `xdg-open`) gets a null one: an app given Koil's would keep
  the pipe open after Koil quits. `+N` puts the cursor on line N of what's
  shown (`+` the last one), in the middle of the view, as vim's
  (`goToLine` types `NGzz`). Then each `-c` (`--command`, `Args::commands`,
  `Document.startupCommands`) runs, in order, as typed after a `:`
  (`shown` in main.qml, `Vim.runCommands`: all of them one run, the keys
  `:`, the command's characters and `<CR>` each, as `@:` types it), so
  anything Koil does can be done at startup without an option of its own
  (`-c 'set sort=size wrap'`, and keys with `-c 'norm G'`). As a macro's,
  a command that fails stops the rest (keys that fail in `:normal` too),
  and they go in the command line's history. Keys run one after another
  in the run, and what `_` shows is shown before its key is done
  (`keyCommand` goes through `outside`), so `-c 'norm _ihi'` types in the
  scratchpad, however long the listing took to show. They
  run after the file can't be read too, over its dir's listing. clap has no `+` options and fills
  positionals in order, so `[PATH]`, `[+N]` and a hidden `more` only
  collect them, and `parse` tells `-`, `+N` and the path apart by what
  they are; after `--` they're all paths (`escaped`, a `last`
  positional), as in vim. `-psn_…`, which older macOS passes, is taken
  out before clap, which would read it as `-p -s -n`. Qt is given every
  argument too (cxx-qt passes them all), so Koil's mustn't be options Qt
  reads (`-platform`, `-style`, `-reverse`), which are errors here (Qt's
  environment variables still work). The scratchpad opens once the
  editor is done, as a file does (so a long text is laid out once); a
  path that can't be opened lists the home dir under it, with why only
  in the status line, since back from the scratchpad the field shows the
  listing's path. A Windows release build is a GUI app, which has no
  console, so `--help` (and an error) attaches to the one it was started
  from (`attach_console`, untried), as does `-p`'s text.
- **The koil command**: on macOS, the Settings window's Command line
  button (`Document.changeCommand`) puts a script at `/usr/local/bin/koil`
  (`install::COMMAND`: on the PATH every shell gets, from `/etc/paths`)
  that `exec`s Koil's binary where it is (`install::script`), or takes it
  away. Nothing else takes it away (macOS runs nothing for an app dragged
  to the Trash), so if the binary isn't there any more, the script says
  so and how to remove it (exit 127), rather than `exec`'s error. A script, not a link to the binary, so the binary runs from its
  bundle as when it's opened: through a link, `current_exe` is the link,
  so `in_bundle` would be false (a window icon over the bundle's). The
  dir is root's, so it's written
  as the user if they can (a Homebrew `/usr/local` on Intel), or else as
  root through `osascript`'s `do shell script … with administrator
  privileges` (`as_admin`), which shows macOS's password dialog: on a
  thread, so the windows don't hang meanwhile, then `commandChanged`
  with why it failed (nothing if the dialog was cancelled). It's
  installed for the Koil that runs (`this_exe`), but not from the disk
  image or a translocated copy, which go away. `commandStatus` says
  what's there, which the window reads whenever it's active: this
  Koil's script, another Koil's (by `MARK`, the line after `#!`: one
  moved, or another copy; Replace makes it this one's), another program,
  or nothing. On Windows, the installer's `addtopath` task puts Koil's
  folder last in the PATH (the user's, or the machine's for all users),
  in `[Code]` (`SetPath`), which takes it out when uninstalled or
  reinstalled without the task; last, as Koil's Qt DLLs are on the PATH
  with it, and mustn't come before another Qt's. Untried, but CI's ISCC
  compiles the code.
- **Open in Koil**: on macOS, a service (`NSServices` in Info.plist) on
  what's selected in Finder, only there (`NSRequiredContext`, without
  which macOS also has a service off at first): in its right-click menu
  (Services) and the Services menu. It takes anything (`public.item` in
  `NSSendFileTypes`; it took only folders, `public.folder`, at first,
  and its message is still `openFolder`, as the shortcut the user set is
  kept by it), which is what puts it in right-click menus and
  under Files and Folders in System Settings; one that takes nothing (as
  it did, asking Finder through `osascript` which folder its front window
  showed) is under General, and macOS ignores `NSServiceCategory` (tried
  with a test bundle; `_NSCopyServiceActions` lists each service's
  category, as System Settings does). The cost: with nothing selected,
  macOS turns it off, shortcut and all. macOS handles its shortcut,
  launching Koil if it isn't running, so Koil needn't run to listen. It's
  ⌃⇧K at first (`^$k`), which Finder doesn't use, nor text fields (not
  ⌃K, their delete to the line's end, which a service's shortcut would
  take first, as in Finder's rename field), but Keka's "Send to Keka" does
  (the README says how to change it). `NSKeyEquivalent` is a letter, with Command (and Shift if it's
  uppercase), or modifiers and a key as pbs keeps them (`^$K` is ⌃⇧K, as
  Keka's are; `_NSCopyServiceActions` shows the shortcut macOS takes). The files come on the pasteboard (finder_mac.mm), and
  Koil comes to the front (macOS doesn't bring it for a service that
  gives it nothing back) and opens the first (`Document`'s
  `folderRequested`, not while a dialog is open): a folder as a dropped
  one (`openDropped`), anything else (a file, or an app or another
  package, which Finder shows as a file: `file`) as the dir it's in, on
  its entry (`showFileDir`, through `openFolder`, so the listing's edits
  stay). Its provider is set from the Document's `onCompleted`, before
  the app runs, so the request that launched Koil comes. The user changes
  the shortcut in System Settings (Keyboard Shortcuts > Services > Files
  and Folders), which keeps it in `pbs`'s preferences (`NSServicesStatus`,
  by the bundle ID, menu item and message); the Settings window shows it
  from there (`finderServiceShortcut`), read whenever it's active, and its
  button opens Keyboard Shortcuts on Spotlight, the row under Services: no
  anchor goes to Services (`?Shortcuts` lands on Modifier Keys, the last
  row; the anchors are `name of every anchor of pane id
  "com.apple.Keyboard-Settings.extension"`). It works only from an app
  bundle Launch Services knows (`lsregister -f`, then `pbs -update` to
  have macOS read its services), not `cargo run`. On
  Windows, the installer adds "Open in Koil" to the right-click menu of
  folders, a folder window's background and drives (a task, on at
  first), which starts Koil with the folder; on Windows 11 it's under
  "Show more options". A drive's root comes quoted, `"C:\"`, which reads
  as `C:"` (`command_line_path`). Nothing on Linux.
- **Open With**: Koil offers to open text files but isn't made the default
  app of a type another app opens. On macOS, `Info.plist` claims, at the
  `Alternate` rank (`None` isn't in Open With at all), `public.text`
  (which source code macOS knows conforms to) and `public.data`, which
  matches only a file of that type itself: one with no extension (empty
  too) or a dotfile (`.envrc`), not a picture or an archive. A file
  whose extension macOS doesn't know (`.toml`) has a `dyn.*` type, which
  no claim on a type it conforms to matches (not `public.data`,
  `public.item`, nor a `*` extension), so a second document type claims a
  list of text and source code extensions by name
  (`CFBundleTypeExtensions`, as VS Code and Zed do; a dict with
  `LSItemContentTypes` ignores them), the same as Windows' `Exts`. It
  has their `'****'` OS type too (`CFBundleTypeOSTypes`,
  `legacy-wildcard` in `lsregister -dump`), which adds no other files:
  Launch Services puts a claim with it after every claim without it,
  whatever their ranks, so without it Koil was the default of `.rs` and
  `.toml` over their `Default` claims. Koil is the default of one only if
  no other app claims it. Launch Services ignores a bundle in `/tmp`, so
  trying claims out takes one elsewhere (`lsregister -f`, then `-u`),
  with a Mach-O executable, launched once (`open -g -j`): before, Koil
  wasn't the default of anything another app claims. Finder
  gives the file as a `QFileOpenEvent`, not on the command line (also to
  Koil already running): `Document.watchFileOpens` has native.cpp's filter
  call `document::file_opened` (C++ can't emit a cxx-qt signal, and the
  bridge allows no `#[allow(dead_code)]` for a signal only C++ uses), and
  main.qml opens it as a dropped file (`openDropped`). A cold start shows
  the home dir (or Start in) first, as the event comes once the event loop runs. On
  Windows, the installer does as vim-edit's: a `Koil.Text` ProgID, in the
  `OpenWithProgids` of a list of text and source code extensions (`Exts` in
  `installer.iss`; what the Open With menu shows), and those extensions as
  `Applications\koil.exe`'s `SupportedTypes` (so "Choose another app" offers
  it only for them). Its first is `.`, the key Windows looks up for a file
  with no extension (untried: the docs for it are old); a dotfile's name
  (`.gitignore`) is its extension there. Both give it the path on the
  command line, without taking any extension.
