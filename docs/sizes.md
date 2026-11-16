# Info, sorting and dirs' sizes

- **Info** (`K`, info.rs, `showInfo` in main.qml): everything there is to
  know of the entry on the cursor's line where it is on disk, as Space r
  takes it, in K's box (`InfoBox`), in the middle of the window, as wide
  and tall as it allows (so a row doesn't wrap out of its column), which
  never takes the keys: a plain item in the overlay (under the hover box
  and the completions, which show what's under the pointer or the
  cursor), whose text a press selects without the keys (Copy goes to it
  through the editors' `copyElsewhere`). So vim goes on, and the box
  follows (`followInfo`, after vim's `cursorChanged`, an edit of the
  listing, or another view or file shown): it shows the entry the cursor
  is on, read only if it's at another path than the one shown
  (`infoSpot`, the cursor's line by its number, text and IDs, as an edit
  can put another entry there; the path field's open dir; the file), or
  why there's none (`entryOnDisk`'s message, which Space r shows in the
  status line), until Esc in normal mode closes it (vim's
  `highlightsCleared`, as for `:noh`), as a hint under its text says,
  dimmed, as the help's header does its keys. K reads it again. A row a
  label and a value (lined up by `Entry::show`): the path (with `/` after a dir's), what it is (a
  symlink's target as written, and where it resolves as the Real path,
  on a row of its own: `target → real` read as the link and its target,
  as `ls -l` has them; the real path if a dir it's in is a link), its size and size on disk (`koil_core::disk_size`),
  what a dir has (by kind, and how many are hidden), its times (local, to
  the second, and how long ago; none at 0, which a device's creation is),
  and on Unix when its metadata changed (`ctime`), its permissions as `ls
  -l` has them and in octal, its owner and group (their names from the `uzers` crate), its hard
  links (not a dir's, which count its dirs), and on macOS its flags
  (`chflags`'s: hidden, locked, restricted, not downloaded); on Windows
  its attributes instead (untried, but checked to build for it). Not its
  inode nor its extended attributes: they said little, and took room.
  It's colored as syntax is: each part has a `Kind` (`Text` is parts of
  a kind each), and `Info` gives their spans (a line, and where in it in
  UTF-16), which `InfoBox.color` gives `System.setSpanColors` (a
  `QSyntaxHighlighter` of spans) in `theme.infoColor`'s colors: labels, dirs as
  the listing's, links cyan, sizes green and their units teal, other
  numbers orange, dates and times purple, each permission as eza colors
  them (`r` yellow, `w` red, `x` green, setuid and the like magenta, `-`
  dim), an owner and group of the user's yellow and root's red, flags
  that lock red, and what only goes with the rest (brackets, how long
  ago) dim.
  It reads the link itself (`symlink_metadata`), but a link to a file
  shows the target's size, and one to a dir what it has. A volume's top
  dir (`info::volume`: on macOS `/`, one in `/Volumes`, or
  `/System/Volumes/Data`, by statfs's `f_mntonname`, as `/` and the data
  volume, where `/Users` is through a firmlink, have one device; not
  statvfs, whose block counts are 32 bits there; on Windows a drive's or
  a share's root, by `GetDiskFreeSpaceExW`; none on Linux, untried) is a
  Volume (a Drive on Windows), and shows its Capacity, what's Available
  and what's Used (and of how much, `space_rows`) instead of a size,
  which isn't counted (all of a drive, from the drives' listing). On
  macOS, Available is Finder's, with what macOS deletes when it needs the
  room (`importantCapacity` in finder_mac.mm, Foundation's
  `NSURLVolumeAvailableCapacityForImportantUsageKey`, as statfs leaves
  that out), which it says is purgeable (`68 GB (10 GB purgeable)`, as
  Finder's Get Info). A network share that doesn't answer keeps K waiting
  as reading any dir there does. A dir's size
  (not a link's: the counts don't follow links) is counted by `Sizes`, by
  the listing's measure (`measure`, as it counts by one at a time; by the
  other one too if it's kept), as `Koil.info` adds it to what it asks
  for (`inspected`, which `want_sizes` adds to every `want`, render's
  and sync's, so they don't stop it) and watches it (`watch`). While it's
  counted (`counting`), main.qml's `infoTimer` has `Koil.infoAgain` give
  it again every 300 ms, as `sizeTimer` does the notes, until it's done
  or the box closes or shows something else (`closeInfoCount`), which
  stops its count (`Koil.infoClosed`, keeping what's counted); done, Koil
  stops it itself (`give_info`). Its `...` (each `busy` span's end,
  `busyDots`) shows `infoDots` of the dots, the others spaces, so nothing
  moves, as the notes do. Following the cursor down a listing of
  dirs, each is counted while it's shown. `Sizes` reads a dir at a time, so one of 128,000
  files comes in at once: `target/` showed 2.8 GB for 9 s, then 16 GB, as
  its `debug/deps` was read.
- **Sorting** (koil-core's `Settings::sort`; read its CLAUDE.md): `gs`
  shows the sort menu (`SortMenu`, under the sort button beside the
  options, visible while vim's `pendingKeys` end in `gs`), and a key picks
  one: `gsn` name, `gsv` natural (`a2` before `a10`), `gse` extension,
  `gss` size (biggest first; a dir's is counted, see below), `gsd` size
  on disk (koil-core's `SortBy::Disk`; a dir's counted too), `gsm`
  modified, `gsc` created, `gsa` accessed (newest first), shifted the
  other way round (`gsS`). They're `commandKeys` of three keys
  (`root.sorts`, `sortKeys`: `"gss": "sort:size"`), so a key it doesn't
  know after `gs` is a bad command, and macros and counts work as for the
  others. The button and a click in the menu go through vim too
  (`vim.startCommand`: out of insert or visual mode first, then the keys:
  `gs`, or `gs` and the clicked key; none hides the menu). They set
  `:set sort` and `sortreverse` (`vim.sort`, `vim.sortReverse`, which
  `Koil` binds; `settingChanged` updates, and an update with only the sort
  changed isn't `moved`, so it's one change undo can take back, with the
  cursor and the view where they were). In a run (a macro's `gss`, `-c`'s
  `set sort=size`), vim waits for the update (`waiting`), which is a step
  of the run (`updateInRun`, through `endWait`'s `done`), so the keys
  after it have the listing sorted: updated once the event loop ran, as
  it is otherwise, it landed between the run's chunks (`-c` after `set
  wrap`'s layout) and stopped the run. Back from a file, sorted another
  way meanwhile, the view stays too (`shownSort`: every line moved, so
  following the file's would scroll the rest away), scrolling only to
  show the cursor. Sorted by size or a date, each line
  shows it, dimmed, after its end (`listing::notes`: `1.2 KB`,
  KB as 1000 bytes like macOS; a time as how long ago it was,
  `listing::time_ago`: `just now`, `5 min ago`, `2 days ago`, `3 weeks
  ago`, `5 months ago`, rounded down, or a year ago or more (or ahead
  of the clock), `2024-10-06 14:03`, local time through chrono, as the
  undo history shows its times too), before a warning's or an error's
  message (`notes` in Editor.qml), lined up (see Notes after lines).
  As time goes on, the listing has Koil give them again (`Koil.times`,
  `refreshTimes` in main.qml) once the first of them changes
  (`Notes::times_change`, which `timesDue` keeps by the clock, checked
  every 5 s: a `Timer` doesn't count the time the computer sleeps). They come as `infos`, `{ id: text }` (`Rendered`, and
  `Synced` with what sync read), so a line's goes with its ID wherever it's
  moved or copied, and a new entry has none. Only the lines in view are
  looked up (`firstAt` in the sorted hidden text). While the listing shows
  them, the watcher doesn't skip writes to files (`DiskWatcher::writes`),
  so a file written shows its new size or time; its line stays where it is
  until the next update sorts it again. The sort isn't saved, like Koil's
  other options. Whether dirs go before files is a setting the Settings
  window saves (Folders first, `:set dirsfirst`, koil-core's
  `Sort::dirs_first`); off, they're sorted together (`1/`, `2.txt`, `3/`),
  and by a size, koil-core puts the dirs after the files, as it knows
  only how many entries each has, so here a dir counted goes among the
  files by its size (`listing::together`, `size`), and one not counted
  yet stays after them.
- **Dir sizes** (sizes.rs): sorted by size or size on disk, a dir's size
  is everything in it, counted on other threads (koil-core's `entries`,
  how many it has, is only the order until then). By size (`Measure::Size`)
  it's the files' bytes as Finder counts; on disk (`Measure::Disk`), their
  blocks (koil-core's `disk_size`, which the files' notes use too) and the
  dirs' own, as `du` counts (`du -skx` gives the same). Either way a link
  is counted itself, not followed, what's on another device isn't
  (`du -x`), and a file with hard links counts once (as `du`: Cargo
  hard-links its builds, which made `target/` a GB too big). Counting on
  disk takes as long as by size on macOS (3 s for `/System/Library`
  either way: the blocks come with the same `lstat`), but on Windows it
  opens every file, which is why the menu says it's slower there.
  `Sizes` counts by one measure at a time (asked for by another one,
  `gss` then `gsd`, its counts stop), and keeps what it counted by each
  apart, so a render never shows the other one's sizes. `render` and
  `sync` give the dirs they show sizes for (`Notes::dirs`, by the path
  their ID was read at), and `Koil` has `Sizes::want` them: those not
  known or kept start, and every other count stops (`stop`), but what's
  read of a dir isn't read again: one in a dir that's counted goes on,
  and that count waits for it once it finds it (`add`: `-` while the
  dirs listed are counted, or a pattern listing a dir and one in it),
  and a dir asked for that's counted in another goes on from there as a
  count of its own (Enter). So the dirs being counted (`State::dirs`, a
  path once) are trees, each dir read for the closest `Count` of the
  dir it's in or itself (`count_of`), and each has what's counted of it
  so far, the dirs in it too (`Dir::bytes`), which its note shows. The
  paths are the same whichever way a dir was opened (`~`, `..`): koil
  canonicalizes them, and the threads join names to them. The counts
  take turns
  (`turns`), a dir each, so they all go on at once and small ones are
  done soon, on up to 8 threads that each read a dir at a time
  (reading is mostly waiting for the disk), and stop once no dir is left
  to read and none is being read, which could find more. Counting, a dir's
  note is its size so far with `...` after it (`listing::COUNTING`), and
  its ID is in `busy`; main.qml's `sizeTimer` polls `Koil.dirSizes` every
  300 ms while any is, and Editor.qml shows `infoDots` of the three dots,
  the note's place worked out with all of them (so nothing moves as they
  come and go), which `dotsTimer` steps while the notes or K's box count
  one, as a count can find nothing new for seconds (a dir of 128,000
  files is read at once). The dirs counted go first, by size (`listing::listing`,
  `compare`, which `merge` uses too, through `by_size`), and the others
  after, in koil's order (with Folders first off, among the files: see
  Sorting). Once they're all counted, `sortCounted` updates (`sortedCounting`:
  it was sorted before they were), keeping the view as for `gs`; not while
  the user is halfway through something (it waits), nor if the update
  would fail on errors or open a path typed in the field (the next update
  sorts it).
- **Kept sizes** (sizes.rs): a count finds the size of every dir in the
  dir counted on its way (each done once the dirs in it are), and keeps
  them (`kept`, but those that can't be read, and small ones), so a dir
  listed again, or one in it (Enter, `-`), shows its size at once. A small dir (`SMALL`:
  no dirs in it, and under 100 entries) is counted again instead, which
  takes no time, and most dirs are: `render` asks for the dirs it shows
  (`listing::size_dirs`) before it's made, and `want` waits for those it
  starts that nothing is known of (`Count::unknown`, which the threads
  read first; `WAIT`: 40 ms at most, and only while they're done one
  after another, `QUIET`, as the others take long), so they're known as
  it's sorted. The counting is on the threads, so a disk that doesn't
  answer never keeps Koil waiting longer; those not done show `...` as
  before. Going into `~/Library/Application Scripts` (1,059 small dirs)
  waits 34 ms, others a few. `sync` waits for those it starts too (dirs
  that changed, new ones), and `count_sizes` then gives their notes as
  they are. The listing looks sizes up as it's made (`SizeOf`;
  `Sizes::known` gives each dir's as it was first asked for, so sorting
  sees the same throughout). A count adds a dir kept instead of reading
  it, unless it's stale. A file with hard links counts once in each dir
  (`Link`, `Dir::links`, merged into the dir it's in, a file in both
  taken off once), so a dir's size is the same counted on its own or in
  another, and once all its links are found, it's forgotten. A dir kept
  keeps the files whose other links are outside it (`Kept::links`), so a
  count that adds it counts them once too: Cargo links each build file
  in `deps/` and `incremental/`, which `target/debug` has both of, and
  the home dir keeps 26,000 (1 MB). A dir kept with links used to be
  read again, so `-` from a home dir counted took 1.6 s rather than
  0.15. A home dir of 146,000 dirs keeps 40,000 (5 MB; all of them
  took 22 MB), and is counted in 10 s, as fast as before sizes were kept.
  What a listing hides isn't counted, so `-` from one counted that hides
  `.cargo` and such counts those (5 s in a home dir).
- **Stale sizes** (sizes.rs): what's kept goes stale when something
  changes in it on disk. The watcher (see Changes on disk) also watches
  the dirs counted and those asked for, with everything in them
  (`Sizes::watches`; more than `SIBLINGS` in one dir, that dir, as
  notify's FSEvents goes through every dir watched for each change; on
  Windows their drives' roots, as a dir with a watched one in it can't
  be renamed or deleted there), and tells `Sizes::changed` of every
  change but reads (`Change`): the dirs it's in go stale, and if it isn't
  a dir any more (gone, or a file), the dirs in it are forgotten; a dir
  still there changed itself (a file added), not what's in its dirs.
  Changes missed make everything in them stale (`lost`, for a rescan;
  `forget`, for a watcher error), and what's kept in a dir that can't be
  watched is forgotten (`unwatched`). Apply, undo and create tell it what
  they change themselves, as they show the listing before the watcher
  tells. A stale dir asked for is counted again, and until it's done it
  shows what it was with `...` after it (`DirSize::Stale`), and sorts by
  it, so nothing moves: `~/Library` changes all the time, and counted
  again it came in as `...`, after the dirs counted, then jumped to its
  place. Then it moves only if its place changed (`sortCounted`). A dir
  shown keeps its size until it's asked for again (the next update or
  sync), and is counted again then (`Wanted::changed`), so a build
  writing in it doesn't have it counted over and over. A change during a
  count makes the dirs it's in stale as they're done (`Dir::stale`, or
  not kept if it's gone: what was read of them may be from before), rather
  than dropping them, as they were before: going into a dir the first
  time showed `...` for those that changed while they were counted (and
  in `~/Library` some always do), which nothing was kept of. Its dir is
  counted again when it's asked for, which reads only those.
