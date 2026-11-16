# Shell commands

- **Shell commands** (shell.rs, `runShell` in main.qml, vim's
  `shellRequested`): `:!cmd` runs `cmd` in the shell (`:set shell`, a vim
  setting the Settings window saves; empty for `System.defaultShell`:
  `$SHELL`, or `%ComSpec%` on Windows, as vim's) in the dir koil has open
  (`Koil.currentDir`, also while a file is, as vim's cwd), with nothing on
  its stdin. `%` in it is, as in vim, the file (relative to that dir if
  it's in it), but in the listing the entry on the cursor's line, where
  its ID is on disk, as for Space r (`listing::paths_on_lines`; a new
  entry or a copy is an error). From the path field, it's the open dir, `.`, or if
  a pattern is open, every line's entry, as `:%` gives them
  (`listing::paths_in_field`), so `wc -l %` with `src/**/*.rs` counts
  what it matches, as a shell's glob would, not fail on `src`. And in the
  scratchpad a file of its text (`Document.writeScratchpad`, written
  before the command runs: `scratchpad.txt` in a dir of Koil's own in the
  temp dir, made new, so on Linux's shared `/tmp` no one else's can be in
  its place, and taken away when Koil quits; with a line break after its
  last line, as vim writes one, so `echo hi >> %` writes a line of its
  own, which reading it back takes off). Once a command that isn't a
  filter or `:_!` is done, what's in the file goes in the scratchpad
  (`afterShell`, if its size or time changed), as a change `u` takes back
  (`Vim.replaceTextKeeping`: a line that stays keeps its hidden text,
  wherever it goes, as the file has the icons alone). `<cfile>`, as in
  vim, is the file name under the cursor as gf takes it, in a file or the
  scratchpad (`listing::links_on_lines`, `link::link_at`: the URL or path
  Cmd+click underlines, or else vim's file name there or after it; a path
  as `link::target` reads it, from the file's dir, then the open dir, and
  must be on disk, E447, and a URL as it opens; on a line with an entry
  pasted with its ID, where that is on disk; none is vim's E446), and in
  the listing the entry, as `%`. With a range, it's each line's first
  link, or else its first file name (`link::first_link`: `git status
  --short`'s ` M src/a.rs` is `src/a.rs`, not `M`). Both take vim's
  modifiers (`%:p`, `:h`, `:t`, `:r`,
  `:e`); `\%` is a `%` (`date +\%F`), and `\<cfile>` a `<cfile>`, as in
  vim, also in quotes. A path is quoted as the shell's kind needs
  (`shell::Kind`, by its name: cmd.exe, PowerShell, else sh), only if it
  must be, and escaped instead where the `%` is in quotes (`"%"` works);
  one starting with `-` gets `./`. With a range (`:.,+2!`, `:'<,'>!`),
  it's vim's filter, the same everywhere: the lines go to its stdin, and
  its stdout replaces them (`Vim.filterLines`, one undo step; no output
  deletes them; a failure, or the text changed meanwhile, leaves them;
  marked lines go to it together, and its output goes where the first
  one was), without the empty line after a file's last line break, which
  `:%!sort` would sort first. In the listing, they go to it without their
  prefixes (`Vim.filterInput`), and its lines get one each
  (`prefixLines`): new entries, as its output has no IDs. But a command
  with `<cfile>`, or in the listing with `%` (not escaped), is run on the
  entries (or paths) of the range's lines instead, which they stand for
  (blank lines left out; `paths_on_lines` and `links_on_lines` take
  spans of lines, as `'<,'>` after marked lines is only those: see
  Marked lines). `!` everywhere is one of `commandKeys` (`bangLines`),
  typing `:! %` with the command line's cursor before the ` %`
  (`Vim.openBang`), so the command goes there; with a count, the range
  of its lines (`3!`: `:.,.+2!`), and in visual mode or on marked lines
  `:'<,'>!` (`:` types `'<,'>` too, leaving visual mode, as in vim),
  each with ` %` after it in the listing (`Vim.bangEntries`), so it's on
  their entries, in the scratchpad with ` <cfile>`, for the entries
  pasted there, but none in a file, where it's vim's filter. `g!` is vim's `!` operator (`g!{motion}`,
  `g!!`, typing the range of the lines it covers, or in visual mode and
  on marked lines `:'<,'>!`), for the filter where `!` isn't; Vim.qml's
  own `!` operator is the same, which Koil's key takes the place of
  (only the tests have it). Ex commands take vim's ranges (`exRange`: numbers,
  `.`, `$`, `'<`, `'>`, `+N`, `-N`, `%`): one alone goes to its last line,
  and commands other than `!`, `:s` and `:normal` (`takesRange` in
  `exCommands`) refuse one (E481). A `!` first is the last
  command (`:!!`). `:_!cmd` (Koil's, after the scratchpad's key; `:%_!`
  with a range) puts what it writes in the scratchpad (`showInScratch`),
  in place of its text, as a change `u` takes back (`Vim.replaceWhole`):
  stdout and stderr as for `:!`, but all of it (up to `FILTER_BYTES`) and
  with its tabs (`Request::scratchpad`). A range's lines go to its stdin,
  and stay, or with `<cfile>`, or `%` in the listing, it's on their
  entries, as for `:!`. It shows the
  scratchpad as `_` does: from the listing, updating before the command
  runs (after which the listing might not read: an entry it deleted), and
  from a file over the file, which keeps its unsaved changes. If it writes nothing,
  nothing changes. A macro running it goes on in the scratchpad:
  `endWait`'s `done` shows it as a step of the run (`inChunk`), which
  `vim.reset` would otherwise interrupt. It runs on a thread
  (`System.runShell`, one at a time), in the environment the user's shell
  sets up (`environment`): on macOS, an app opened from Finder has only
  launchd's (the system's PATH, not Homebrew's), so unless Koil was
  started from a terminal (`TERM` set), it's read once, as VS Code and
  Zed do, from `$SHELL -l -i -c`, interactive so it reads `.zshrc` too
  (where Homebrew's PATH often is; `-l` alone, as MacVim's, missed it).
  Running every command that way took 200 ms each, and the rc file
  printed into the output, so it runs once (`read_environment`, started
  on a thread from main.qml's `onCompleted`, or as the setting is turned
  on: `System.loadShellEnvironment`; the first command waits for it),
  prints the environment between marks (`env -0`), is killed after 10 s,
  and has `KOIL_RESOLVING_ENVIRONMENT` set, for an rc file to skip what's
  slow. Commands then get it (`env_clear`, so its PATH finds the shell
  too) and no `-l`, which would run `path_helper` again and put
  `/usr/bin` first. If it can't be read, or the Settings window's Shell
  environment (`shellEnvironment`, off at first, the last row, macOS
  only; `Request::environment`) is off, which doesn't run the user's shell
  at all, those in `LOGIN_SHELLS` get `-l`, as before. Its note then names
  the files that login shell reads (`environmentNote`, by the shell's
  name: zsh's `.zprofile`, not `.zshrc`), and says to turn it on if a
  command isn't found, like Homebrew's. Sh and the like run
  with `-c`, cmd.exe
  with `/d /s /c "…"` as a raw argument, PowerShell with
  `-EncodedCommand`, and Git Bash with its command line always quoted (its
  runtime globs an argument that isn't), in a process group of its own
  (no console window on Windows). It runs once the copies applying would
  make are made (`copyFirst` with no path, see Files), as it could change
  what they copy; not before a filter of the listing's lines, which only
  edits them, and whose lines making them would show again (`:%!sort`
  with its output rejected, as the text changed). Meanwhile vim waits (`Vim.waiting`,
  "Running (Esc to stop)"): keys do nothing but Esc and Ctrl-C, which stop
  it (`Running::stop`: SIGINT to the group, SIGKILL a second later;
  `taskkill /T /F` on Windows), a macro running it waits too (`runChunk`
  stops; `endWait` goes on), and `boxOpen` keeps the menu, drops and syncs
  from changing anything. Its stdout and stderr come through one pipe
  (`io::pipe`), in order, shown as a terminal would show them
  (`shell::Screen`: no escapes, `\r` and backspaces writing over, tabs
  as spaces), its last `SHOWN_LINES` (1000, as a terminal keeps the last;
  `Ran::cut` is how many came before, which the box says over them): a
  line that fits goes in the status line (`StatusLine.fits`), more in
  the output box (`help.showText`, see Output box, where `/` searches it,
  and Enter closes it, as vim's "Press ENTER"). A `Screen` is given what's
  written as it comes (`write`), so an escape, a character or a BOM cut
  in two by a read waits for the rest (`Escape`, `Decoder`: UTF-8, or
  UTF-16 after its BOM, as `document::decode_lossy` reads all of it), and
  what it costs is by what's written, not by all of it each time;
  `as_shown` is one given everything (a filter's stderr is one too, but
  its stdout and `:_!`'s are kept as written, `Kept`). While the command
  runs, `Started::finish` tells what's new (`Live::due`, a
  `shell::Output`, at most every `LIVE_EVERY`, 100 ms, and all of it
  before it returns; `System.shellOutput`): the lines that ended since,
  the line being written as it is now (a progress bar, as `\r` wrote it
  last), and how many of the lines told before aren't kept any more
  (`drop`, or `reset` for all, once more was written between two tells
  than is kept), so Koil adds to what it shows rather than taking it all
  again. Blank lines at the end are told only once something follows
  them, as they're left out in the end. Until the box shows it,
  `shellOutput` in main.qml keeps it (`shellRun.lines`) and the status
  line shows its last line that isn't blank, in place of the command, as
  it does all the while for `:_!`. Once the command wrote something and
  has run for `liveDelay` (400 ms: `showLive`, from `shellOutput` and
  `liveTimer`), the box opens on what it wrote so far, and takes what
  comes from then on (`help.addOutput`) until `shellDone` says how it
  ended (`help.endOutput`), after which it stays open; a command done
  sooner shows its output as before, so a quick one opens no box for a
  line. Not a filter's, whose output is its lines. The command still
  writes to a pipe, not a terminal: one that draws its bar only on a
  terminal (cargo, pip, npm) shows none, and most buffer their stdout,
  which comes in bursts (a pty would fix both). A failure
  ("shell returned 1") is an error, which stops a macro. What it starts
  with `&` keeps its output open, which is read only `AFTER_EXIT` longer.
  Koil quitting stops it (`SystemRust`'s `Drop`). The Settings window's
  list is `shell::shells`: `/etc/shells`, or cmd.exe, both PowerShells and
  Git Bash where it installs or by git on the PATH. Windows' kinds are
  untried, but `shell.rs` checks for its target.
- **Output box** (Output in HelpPanel.qml): what a shell command wrote
  is the help's box in another look (`output`), as a terminal's: the
  command in the editor's font over it (not the help's big title), how
  it ended on its right after a dot in its color (`outputStatus`: Done
  green, `Exit 2` red, Stopped yellow, with how long it ran, or Running,
  whose dot pulses and time counts by a `Timer`, not an animation), its
  text on the editor's background in a frame, as a question's list, and
  the keys under it. The text is one plain `TextEdit` (`outputText`), not
  a section's rich text: `addOutput` takes its first lines off and puts
  the new ones and the line being written at its end (by `outputLengths`
  and `outputEnd`, so the text isn't read to find where), which lays out
  only those; setting 1000 lines of rich text again at every tell took
  too long. Search goes through it as through the help's texts
  (`searchTexts`, its key "output"), and it draws its matches in view
  itself (`marks`: a part a row, with the matched text again in black
  over the highlight, as plain text can't color it). While the command
  runs (`running`), Esc and Ctrl-C emit `stopRequested` (Ctrl+C copies a
  selection first, where it's Copy), and nothing closes the box (`q`,
  Enter, a click outside), but something else taking the keys (see Help;
  main.qml then shows the last line in the status line again,
  `shellRun.closed`). The view stays at the end as more is written
  (`following`) until it's scrolled off it, and again once it's scrolled
  back; that's told from the scrolls themselves (`scrolled`: keys, the
  wheel, the scroll bar, a search), as the view's place also changes
  when the box grows, which Qt tells before `maxY` follows. A box opened
  while the command ran (`live`) isn't in the middle: its top is where
  it would be at its tallest, and it grows down, so the lines stay where
  they are as more come (in the middle, each new line moved them all).
  The command's room in the header leaves a fixed width for the status,
  or its middle was cut elsewhere as the seconds counted.
