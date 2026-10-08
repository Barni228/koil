//! The sizes of dirs, counted on other threads, so the listing can show them
//! when it's sorted by size or size on disk (see `listing::notes`) without
//! Koil waiting for them (but a moment, for small ones). Once a dir is
//! counted, its size is kept, and so are those of the dirs in it (but small
//! ones, see `SMALL`), until something changes in it on disk (see
//! `Sizes::changed`), so it isn't counted again when it's listed again, nor
//! are the dirs in it when they're listed, nor the dirs in a dir counted
//! (`-`). Nor is what's read of a dir that isn't done: counting the dir it's
//! in waits for its count (`-` while the dirs listed are counted), and a dir
//! counted in another goes on from there (Enter).

use std::cell::RefCell;
use std::collections::hash_map::Entry;
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet, VecDeque};
use std::fs;
use std::ops::Bound;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::thread;
use std::time::{Duration, Instant};

/// What's known of the size of a dir: everything in it, as `Measure` says,
/// but what's on another device (a disk mounted in it, as `du -x`), and a
/// file with hard links in it once (as `du`: Cargo links its builds). A
/// link is counted itself, not followed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DirSize {
    /// The bytes counted so far.
    Counting(u64),
    /// What it was counted at before something in it changed on disk, while
    /// it's counted again.
    Stale(u64),
    Counted(u64),
    /// It can't be read, or isn't there.
    Unreadable,
}

/// The sizes known, by the dirs' paths.
pub type DirSizes = HashMap<PathBuf, DirSize>;

/// What's known of the sizes of dirs, by their paths.
pub trait SizeOf {
    fn size_of(&self, dir: &Path) -> Option<DirSize>;
}

impl SizeOf for DirSizes {
    fn size_of(&self, dir: &Path) -> Option<DirSize> {
        self.get(dir).copied()
    }
}

/// What a dir's size counts.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum Measure {
    /// The bytes of the files in it, as Finder counts (not the dirs' own).
    #[default]
    Size,
    /// The space they take on disk (see `koil_core::disk_size`), the dirs'
    /// own too, as `du` counts. On Windows every file is opened for it.
    Disk,
}

impl Measure {
    /// Where its sizes are in `State::kept`.
    fn index(self) -> usize {
        self as usize
    }
}

/// Counts the sizes of the dirs asked for (see `want`), and keeps them. A
/// clone is the same one, which another thread can tell what changed on
/// disk.
#[derive(Default, Clone)]
pub struct Sizes {
    shared: Arc<Shared>,
}

#[derive(Default)]
struct Shared {
    state: Mutex<State>,
    /// Signalled when there are dirs to read, or nothing is read any more.
    wake: Condvar,
    /// Signalled when a dir asked for is counted.
    counted: Condvar,
}

/// A dir with no dirs in it and fewer entries than this isn't kept: it's
/// counted again in a moment (see `WAIT`), and most dirs are like that.
const SMALL: usize = 100;

/// How long `want` waits for the dirs it starts counting, so small ones are
/// known at once, at most, and with none counted for `QUIET`: the others
/// take long. The counting is on other threads, so a disk that doesn't
/// answer never keeps Koil waiting longer.
const WAIT: Duration = Duration::from_millis(40);
const QUIET: Duration = Duration::from_millis(8);

/// More dirs to watch in one dir than this, and that one is watched
/// instead: notify goes through every dir watched for each change on macOS.
const SIBLINGS: usize = 8;

#[derive(Default)]
struct State {
    /// What the dirs asked for are counted by.
    measure: Measure,
    /// The dirs asked for last.
    wanted: BTreeMap<PathBuf, Wanted>,
    /// The sizes kept, by each measure (see `Measure::index`): of every dir
    /// counted, and of every dir in it, but those that can't be read and
    /// small ones (see `Dir::keep`).
    kept: [BTreeMap<PathBuf, Kept>; 2],
    /// The dirs counted, whose sizes are kept with those of the dirs in
    /// them, or which are asked for, which `watches` watches.
    roots: BTreeSet<PathBuf>,
    /// The dirs being counted, by a number of their own, never given again,
    /// so that a read for one that was dropped isn't added to another: the
    /// dirs asked for, and the dirs in them found and not done yet. Each is
    /// in a tree of them (see `Dir::parent`) and is read for a `Count`, its
    /// own or that of a dir it's in.
    dirs: HashMap<u64, Dir>,
    /// Their numbers, by their paths (one each).
    paths: BTreeMap<PathBuf, u64>,
    next: u64,
    /// The dirs counted on their own, by their numbers, so in the order
    /// they started: those asked for, and those that aren't any more but
    /// are in a dir that's counted, which waits for them once it finds them
    /// (see `add`).
    counts: BTreeMap<u64, Count>,
    /// The counts with dirs to read, which take turns, so they all go on
    /// at once, and small ones are done soon.
    turns: VecDeque<u64>,
    /// The threads counting, and how many dirs they're reading.
    threads: usize,
    reading: usize,
}

/// A dir asked for.
struct Wanted {
    size: DirSize,
    /// Its dir in `State::dirs`, while it's counted.
    count: Option<u64>,
    /// Whether something changed in it on disk since it was counted (or
    /// while), so it's counted again when it's asked for again.
    changed: bool,
}

/// A dir's size, kept.
#[derive(Debug, PartialEq, Eq)]
struct Kept {
    bytes: u64,
    /// The files in it with hard links outside it (see `Link`), which a
    /// count it's added to may find there too.
    links: Option<Box<Links>>,
    /// Whether something changed in it on disk since it was counted: then
    /// it's only shown until it's counted again (see `DirSize::Stale`), and
    /// it can't be added to another count.
    stale: bool,
}

/// A file with other hard links (see `hard_link`), which a count counts
/// once: its size, and how many of its links were found, and it has. Once
/// they all are, nothing else in the count can be it, and it's forgotten
/// (Cargo links its builds in `target/debug`, which has both).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Link {
    size: u64,
    found: u64,
    links: u64,
}

/// The files with other hard links found in a dir, and not all their
/// links, by their device and inode.
type Links = HashMap<(u64, u64), Link>;

/// A dir counted on its own (see `State::counts`), with the dirs in it that
/// aren't.
struct Count {
    /// Whether nothing is known of its size until it's counted (it was
    /// never kept), so `want` waits for it, and it's read first.
    unknown: bool,
    /// The dirs in it found and not read yet, the dir itself first.
    unread: Vec<u64>,
    /// The device the dir is on, once it was read.
    device: Option<u64>,
}

/// What changed at a path on disk (see `State::changed`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Change {
    /// Something in it (a file added, or written), or it, if it's a file.
    Itself,
    /// It's gone, or it isn't a dir any more: so are the dirs in it.
    Gone,
    /// What changed in it wasn't told: the dirs in it may have changed too.
    Missed,
}

/// A dir being counted.
struct Dir {
    path: PathBuf,
    /// The dir it's in, which waits for it, None for one counted on its own
    /// that isn't in a dir counted.
    parent: Option<u64>,
    /// What's counted of it so far: the files in it, the dirs in it as far
    /// as they're counted, and its own size, once it's known.
    bytes: u64,
    /// Whether its own size is in `bytes`: for a dir counted on its own,
    /// once it's read; for the others, from when they're found.
    own: bool,
    /// How many dirs in it aren't counted yet, and one more until it's
    /// read.
    left: usize,
    /// The files in it with other hard links (see `Link`).
    links: Links,
    /// Whether its size is kept: not if it can't be read, nor if it's small
    /// (see `SMALL`), nor if it's gone (see `State::changed`).
    keep: bool,
    /// Whether it can't be read: it counts as empty.
    unreadable: bool,
    /// Whether something changed in it on disk while it was counted (see
    /// `Sizes::changed`), or changes in it were missed: what was read of it
    /// may be from before, so it's kept stale.
    stale: bool,
}

/// A dir to read: which one, whether to read its own size (see
/// `Dir::own`), the device the dir counted is on, and what's counted.
struct Job {
    dir: u64,
    path: PathBuf,
    own: bool,
    device: Option<u64>,
    measure: Measure,
}

/// What reading a dir found: its own size (if the job asked for it), the
/// size of what's in it, but the files with other hard links, which are
/// counted once (see `Link`), the dirs in it to read next, with their own
/// sizes, how many entries it has, and the device it's on.
#[derive(Default)]
struct Read {
    own: Option<u64>,
    bytes: u64,
    links: Vec<((u64, u64), Link)>,
    dirs: Vec<(PathBuf, u64)>,
    entries: usize,
    device: Option<u64>,
    /// It can't be read.
    unreadable: bool,
}

/// What `Sizes` knows of dirs' sizes by a measure (see `Sizes::known`).
pub struct Known<'a> {
    sizes: &'a Sizes,
    measure: Measure,
    /// Each dir's, as it was when it was first asked for.
    seen: RefCell<HashMap<PathBuf, Option<DirSize>>>,
}

impl SizeOf for Known<'_> {
    fn size_of(&self, dir: &Path) -> Option<DirSize> {
        if let Some(&size) = self.seen.borrow().get(dir) {
            return size;
        }
        let size = self.sizes.lock().size_of(dir, self.measure);
        self.seen.borrow_mut().insert(dir.to_path_buf(), size);
        size
    }
}

impl Sizes {
    /// What's known of dirs' sizes by `measure`: of the dirs asked for, as
    /// far as they're counted, and the sizes kept. Each is as it was when
    /// it was first asked for, so a listing sorted by them sees the same
    /// throughout.
    pub fn known(&self, measure: Measure) -> Known<'_> {
        Known {
            sizes: self,
            measure,
            seen: RefCell::default(),
        }
    }

    /// Counts `dirs` by `measure`, those whose sizes aren't known or kept,
    /// and stops counting every other one (keeping the sizes of the dirs in
    /// it counted so far), but those in a dir it counts, which that count
    /// waits for. One that's counted in the count of a dir it's in goes on
    /// from there. Waits a moment (see `WAIT`) for those it starts that
    /// nothing was known of (those stale show what they were). True if it
    /// starts any.
    pub fn want(&self, dirs: impl IntoIterator<Item = PathBuf>, measure: Measure) -> bool {
        let mut state = self.lock();
        let started = state.want(dirs, measure);
        let waits = |state: &State| {
            (started.iter()).any(|n| state.counts.get(n).is_some_and(|c| c.unknown))
        };
        // Reading is mostly waiting for the disk, which takes more than one
        // read at a time.
        let max = thread::available_parallelism().map_or(4, |n| n.get().clamp(2, 8));
        while state.threads < max && !state.turns.is_empty() {
            let shared = self.shared.clone();
            match thread::Builder::new()
                .name("dir sizes".into())
                .spawn(move || count(&shared))
            {
                Ok(_) => state.threads += 1,
                Err(_) => break,
            }
        }
        self.shared.wake.notify_all();
        let until = Instant::now() + WAIT;
        while waits(&state) {
            let wait = until.saturating_duration_since(Instant::now()).min(QUIET);
            let (waited, time) = self.shared.counted.wait_timeout(state, wait).unwrap();
            state = waited;
            if time.timed_out() {
                break;
            }
        }
        !started.is_empty()
    }

    /// Takes in that something was created, removed, renamed or written at
    /// `path` on disk: the sizes it can change (of the dirs it's in, and if
    /// it isn't a dir any more, of the dirs that were in it, which are
    /// forgotten) are stale, and the dirs asked for among them are counted
    /// again when they're asked for again.
    pub fn changed(&self, path: &Path) {
        // Still a dir, it changed itself (a file was added), not what's in
        // its dirs.
        let change = match fs::symlink_metadata(path).is_ok_and(|meta| meta.is_dir()) {
            true => Change::Itself,
            false => Change::Gone,
        };
        self.lock().changed(path, change);
    }

    /// Takes in that changes in `path` may have been missed: every size
    /// kept in it is stale too (see `changed`).
    pub fn lost(&self, path: &Path) {
        self.lock().changed(path, Change::Missed);
    }

    /// Takes in that changes anywhere may have been missed: every size kept
    /// is stale (see `changed`).
    pub fn forget(&self) {
        self.lock().forget();
    }

    /// Forgets the sizes kept of `dir` and of the dirs in it, as changes
    /// there can't be seen.
    pub fn unwatched(&self, dir: &Path) {
        self.lock().forget_in(dir);
    }

    /// The dirs to watch (with every dir in them) for what changes the
    /// sizes kept or asked for, to tell `changed`. None is in another.
    pub fn watches(&self) -> Vec<PathBuf> {
        self.lock().watches()
    }

    fn lock(&self) -> MutexGuard<'_, State> {
        self.shared.state.lock().unwrap()
    }
}

impl State {
    /// See `Sizes::want`, which starts the threads. Returns the dirs it
    /// starts counting, or that go on from the count they were in.
    fn want(&mut self, dirs: impl IntoIterator<Item = PathBuf>, measure: Measure) -> Vec<u64> {
        if measure != self.measure {
            self.measure = measure;
            self.wanted.clear();
            self.dirs.clear();
            self.paths.clear();
            self.counts.clear();
        }
        let mut old = std::mem::take(&mut self.wanted);
        let mut started = Vec::new();
        for dir in dirs {
            if self.wanted.contains_key(&dir) {
                continue;
            }
            let was = old.remove(&dir);
            let kept = self.kept[measure.index()].get(&dir);
            let wanted = match (was, kept.map(|kept| (kept.bytes, kept.stale))) {
                // Known, or being counted, even if it changed since it
                // started: it's counted again once it's done.
                (Some(was), _) if !was.changed || was.count.is_some() => was,
                (_, Some((bytes, false))) => Wanted {
                    size: DirSize::Counted(bytes),
                    count: None,
                    changed: false,
                },
                (was, kept) => {
                    // Shown until it's counted again, so it stays where it
                    // was sorted.
                    let before = match was.map(|w| w.size) {
                        Some(DirSize::Counted(bytes) | DirSize::Stale(bytes)) => Some(bytes),
                        _ => kept.map(|(bytes, _)| bytes),
                    };
                    // Still counted from before (in a dir that was asked
                    // for, or on its own in one), it goes on.
                    let n = match self.paths.get(&dir) {
                        Some(&n) => {
                            self.roots.insert(dir.clone());
                            n
                        }
                        None => self.start(dir.clone(), before.is_none()),
                    };
                    started.push(n);
                    Wanted {
                        size: before.map_or(DirSize::Counting(0), DirSize::Stale),
                        count: Some(n),
                        changed: self.dirs[&n].stale,
                    }
                }
            };
            self.wanted.insert(dir, wanted);
        }
        self.stop();
        // Those unknown first, so small ones are done in the moment `want`
        // waits.
        let turns = std::mem::take(&mut self.turns).into_iter();
        let turns = turns.filter_map(|n| Some((n, self.counts.get(&n)?.unknown)));
        let (unknown, others): (VecDeque<_>, VecDeque<_>) = turns.partition(|&(_, u)| u);
        self.turns = unknown.into_iter().chain(others).map(|(n, _)| n).collect();
        started
    }

    /// Stops the counts of the dirs that aren't asked for (see `want`), and
    /// that aren't in a dir counted, but those in a dir that's counted,
    /// which waits for them once it finds them (see `add`). The dirs asked
    /// for in the others go on as counts of their own, and the rest of them
    /// is dropped.
    fn stop(&mut self) {
        let counted = |dir: &Path| self.wanted.get(dir).is_some_and(|w| w.count.is_some());
        let stopped: HashSet<u64> = (self.counts.keys().copied())
            .filter(|n| {
                let dir = &self.dirs[n];
                let path = &dir.path;
                dir.parent.is_none()
                    && !self.wanted.contains_key(path)
                    && !path.ancestors().skip(1).any(counted)
            })
            .collect();
        if stopped.is_empty() {
            return;
        }
        // The dirs asked for in them, but those in another one asked for,
        // and the counts they're in.
        let mut apart = BTreeMap::new();
        for wanted in self.wanted.values() {
            let Some(n) = wanted.count else {
                continue;
            };
            let (mut top, mut at) = (n, n);
            while let Some(parent) = self.dirs[&at].parent {
                at = parent;
                if counted(&self.dirs[&at].path) {
                    top = at;
                }
            }
            if stopped.contains(&at) {
                apart.insert(top, at);
            }
        }
        for n in apart.into_keys() {
            let dir = &self.dirs[&n];
            if !self.counts.contains_key(&n) {
                let from = self.count_of(dir.parent.unwrap());
                let from = self.counts.get_mut(&from).unwrap();
                let (unread, rest): (Vec<u64>, Vec<u64>) = std::mem::take(&mut from.unread)
                    .into_iter()
                    .partition(|u| self.dirs[u].path.starts_with(&dir.path));
                from.unread = rest;
                let count = Count {
                    unknown: matches!(self.wanted[&dir.path].size, DirSize::Counting(_)),
                    unread,
                    device: from.device,
                };
                if !count.unread.is_empty() {
                    self.turns.push_back(n);
                }
                self.counts.insert(n, count);
            }
            self.dirs.get_mut(&n).unwrap().parent = None;
        }
        let dropped: Vec<u64> = (self.dirs.keys().copied())
            .filter(|&n| stopped.contains(&self.root_of(n)))
            .collect();
        for n in dropped {
            let dir = self.dirs.remove(&n).unwrap();
            self.paths.remove(&dir.path);
        }
        self.counts.retain(|n, _| self.dirs.contains_key(n));
    }

    /// Starts counting `dir` on its own (`unknown`, see `Count::unknown`),
    /// returning its number.
    fn start(&mut self, dir: PathBuf, unknown: bool) -> u64 {
        self.roots.insert(dir.clone());
        let n = self.found(dir, None, None);
        let count = Count {
            unknown,
            unread: vec![n],
            device: None,
        };
        self.counts.insert(n, count);
        self.turns.push_back(n);
        n
    }

    /// Adds the dir at `path` in `parent` to those being counted, with its
    /// own size, if it's known, returning its number.
    fn found(&mut self, path: PathBuf, parent: Option<u64>, own: Option<u64>) -> u64 {
        let n = self.next;
        self.next += 1;
        self.paths.insert(path.clone(), n);
        let dir = Dir {
            path,
            parent,
            bytes: own.unwrap_or(0),
            own: own.is_some(),
            left: 1,
            links: Links::new(),
            keep: true,
            unreadable: false,
            stale: false,
        };
        self.dirs.insert(n, dir);
        n
    }

    /// The dir at the top of the tree the dir `n` is in (see `Dir::parent`).
    fn root_of(&self, mut n: u64) -> u64 {
        while let Some(parent) = self.dirs[&n].parent {
            n = parent;
        }
        n
    }

    /// The dir counted on its own that the dir `n` is read for: it, or the
    /// closest one it's in.
    fn count_of(&self, mut n: u64) -> u64 {
        while !self.counts.contains_key(&n) {
            n = self.dirs[&n].parent.unwrap();
        }
        n
    }

    /// What's known of the size of `dir` by `measure` (see `Sizes::known`).
    fn size_of(&self, dir: &Path, measure: Measure) -> Option<DirSize> {
        match self.wanted.get(dir) {
            Some(wanted) if measure == self.measure => match (wanted.size, wanted.count) {
                (DirSize::Counting(_), Some(n)) => {
                    let bytes = self.dirs.get(&n).map_or(0, |dir| dir.bytes);
                    Some(DirSize::Counting(bytes))
                }
                (size, _) => Some(size),
            },
            _ => (self.kept[measure.index()].get(dir)).map(|kept| match kept.stale {
                true => DirSize::Stale(kept.bytes),
                false => DirSize::Counted(kept.bytes),
            }),
        }
    }

    /// Takes in `change` at `path`: the sizes kept of `path` and of the
    /// dirs it's in are stale, and so are those of the dirs in it if changes
    /// there were missed, or they're forgotten if it's gone. The dirs asked
    /// for among them are counted again when they're asked for again, and
    /// those being counted are kept stale, or not at all.
    fn changed(&mut self, path: &Path, change: Change) {
        if change == Change::Gone {
            self.forget_in(path);
        }
        for kept in &mut self.kept {
            for dir in path.ancestors() {
                if let Some(kept) = kept.get_mut(dir) {
                    kept.stale = true;
                }
            }
            if change == Change::Missed {
                for (_, kept) in inside_mut(kept, path) {
                    kept.stale = true;
                }
            }
        }
        let mut dirs: Vec<PathBuf> = path.ancestors().map(Path::to_path_buf).collect();
        if change != Change::Itself {
            dirs.extend(inside(&self.wanted, path).map(|(d, _)| d.clone()));
        }
        for dir in dirs {
            if let Some(wanted) = self.wanted.get_mut(&dir) {
                wanted.changed = true;
            }
        }
        for dir in path.ancestors() {
            if let Some(n) = self.paths.get(dir) {
                self.dirs.get_mut(n).unwrap().stale = true;
            }
        }
        if change != Change::Itself {
            let from = (Bound::Included(path), Bound::Unbounded);
            let at = self.paths.range::<Path, _>(from);
            for (_, n) in at.take_while(|(d, _)| d.starts_with(path)) {
                let dir = self.dirs.get_mut(n).unwrap();
                match change {
                    Change::Gone => dir.keep = false,
                    _ => dir.stale = true,
                }
            }
        }
    }

    /// See `Sizes::forget`.
    fn forget(&mut self) {
        for kept in self.kept.iter_mut().flat_map(|kept| kept.values_mut()) {
            kept.stale = true;
        }
        for wanted in self.wanted.values_mut() {
            wanted.changed = true;
        }
        for dir in self.dirs.values_mut() {
            dir.stale = true;
        }
    }

    /// Stops keeping the sizes of `dir` and of the dirs in it.
    fn forget_in(&mut self, dir: &Path) {
        for kept in &mut self.kept {
            let gone: Vec<PathBuf> = inside(kept, dir).map(|(d, _)| d.clone()).collect();
            for d in gone.iter().map(PathBuf::as_path).chain([dir]) {
                kept.remove(d);
            }
        }
    }

    /// See `Sizes::watches`. Forgets the dirs counted that nothing is kept
    /// of any more, and that aren't asked for.
    fn watches(&mut self) -> Vec<PathBuf> {
        let State {
            roots,
            kept,
            wanted,
            ..
        } = self;
        roots.retain(|root| {
            let kept_in = |kept: &BTreeMap<PathBuf, Kept>| {
                kept.contains_key(root) || inside(kept, root).next().is_some()
            };
            wanted.contains_key(root) || kept.iter().any(kept_in)
        });
        let mut in_dir: HashMap<&Path, usize> = HashMap::new();
        for dir in outermost(roots.iter()) {
            *in_dir.entry(dir.parent().unwrap_or(dir)).or_default() += 1;
        }
        let dirs = outermost(roots.iter()).map(|dir| match dir.parent() {
            Some(parent) if in_dir[parent] > SIBLINGS => parent,
            _ => dir,
        });
        let dirs: BTreeSet<&Path> = dirs.collect();
        outermost(dirs.into_iter()).map(Path::to_path_buf).collect()
    }

    /// The next dir to read, taking turns.
    fn take(&mut self) -> Option<Job> {
        while let Some(n) = self.turns.pop_front() {
            let Some(count) = self.counts.get_mut(&n) else {
                continue;
            };
            let Some(dir) = count.unread.pop() else {
                continue;
            };
            if !count.unread.is_empty() {
                self.turns.push_back(n);
            }
            self.reading += 1;
            let found = &self.dirs[&dir];
            return Some(Job {
                dir,
                path: found.path.clone(),
                own: !found.own,
                device: count.device,
                measure: self.measure,
            });
        }
        None
    }

    /// Adds what reading the dir `dir` found, taking the sizes kept of the
    /// dirs in it that can be, and waiting for those counted on their own.
    /// True if there are more dirs to read now.
    fn add(&mut self, dir: u64, read: Read) -> bool {
        self.reading -= 1;
        // Dropped while it was read.
        let Some(read_dir) = self.dirs.get_mut(&dir) else {
            return false;
        };
        let small = read.dirs.is_empty() && read.entries < SMALL;
        read_dir.keep &= !read.unreadable && !small;
        read_dir.unreadable = read.unreadable;
        read_dir.left -= 1;
        let mut bytes = read.bytes;
        // Unless the dir it's in found it meanwhile.
        if let Some(own) = read.own.filter(|_| !read_dir.own) {
            bytes += own;
            read_dir.own = true;
        }
        for (file, link) in read.links {
            bytes += link.size;
            bytes -= add_link(&mut read_dir.links, file, link);
        }
        let kept = &self.kept[self.measure.index()];
        let (mut found, mut counted) = (Vec::new(), Vec::new());
        for (path, own) in read.dirs {
            match (kept.get(&path), self.paths.get(&path)) {
                // Counted before, and nothing changed in it since: its files
                // that this count can have elsewhere are counted once.
                (Some(k), _) if !k.stale => {
                    bytes += k.bytes;
                    for (&file, &link) in k.links.iter().flat_map(|links| links.iter()) {
                        bytes -= add_link(&mut read_dir.links, file, link);
                    }
                }
                (_, Some(&n)) if self.counts.contains_key(&n) => counted.push((n, own)),
                _ => found.push((path, own)),
            }
        }
        read_dir.left += found.len() + counted.len();
        let count = self.count_of(dir);
        let device = self.counts[&count].device.or(read.device);
        // Counted on their own (asked for, or in a dir that is), they go on,
        // and this one waits for them.
        for (n, own) in counted {
            let other = self.dirs.get_mut(&n).unwrap();
            other.parent = Some(dir);
            if !other.own {
                other.bytes += own;
                other.own = true;
            }
            bytes += other.bytes;
            let other = self.counts.get_mut(&n).unwrap();
            other.device = other.device.or(device);
        }
        let mut unread = Vec::new();
        for (path, own) in found {
            unread.push(self.found(path, Some(dir), Some(own)));
            bytes += own;
        }
        adjust(&mut self.dirs, dir, |counted| counted + bytes);
        let more = !unread.is_empty();
        let read_for = self.counts.get_mut(&count).unwrap();
        read_for.device = device;
        if more && read_for.unread.is_empty() {
            self.turns.push_back(count);
        }
        read_for.unread.extend(unread);
        self.finish(dir);
        more
    }

    /// Keeps the size of the dir `n` if every dir in it is counted, and
    /// then of the dirs it's in that are.
    fn finish(&mut self, mut n: u64) {
        let kept = &mut self.kept[self.measure.index()];
        while self.dirs[&n].left == 0 {
            let done = self.dirs.remove(&n).unwrap();
            self.paths.remove(&done.path);
            self.counts.remove(&n);
            if done.keep {
                let links = (!done.links.is_empty()).then(|| Box::new(done.links.clone()));
                let size = Kept {
                    bytes: done.bytes,
                    links,
                    stale: done.stale,
                };
                kept.insert(done.path.clone(), size);
            }
            if let Some(wanted) = self.wanted.get_mut(&done.path) {
                wanted.size = match done.unreadable {
                    true => DirSize::Unreadable,
                    false => DirSize::Counted(done.bytes),
                };
                wanted.count = None;
            }
            let Some(p) = done.parent else {
                return;
            };
            let parent = self.dirs.get_mut(&p).unwrap();
            parent.left -= 1;
            // A file in both was added twice.
            let (mut links, others) = match parent.links.len() >= done.links.len() {
                true => (std::mem::take(&mut parent.links), done.links),
                false => (done.links, std::mem::take(&mut parent.links)),
            };
            let mut twice = 0;
            for (file, link) in others {
                twice += add_link(&mut links, file, link);
            }
            parent.links = links;
            adjust(&mut self.dirs, p, |counted| counted - twice);
            n = p;
        }
    }
}

/// Adds `link` of the file `file` to `links`, returning the bytes counted
/// twice: its size, if it was in them. Once all its links are found, it's
/// forgotten.
fn add_link(links: &mut Links, file: (u64, u64), link: Link) -> u64 {
    match links.entry(file) {
        Entry::Vacant(entry) => {
            if link.found < link.links {
                entry.insert(link);
            }
            0
        }
        Entry::Occupied(mut entry) => {
            let had = entry.get_mut();
            had.found += link.found;
            if had.found >= had.links {
                entry.remove();
            }
            link.size
        }
    }
}

/// Changes what's counted of the dir `n` in `dirs` with `change`, and of
/// the dirs it's in.
fn adjust(dirs: &mut HashMap<u64, Dir>, n: u64, change: impl Fn(u64) -> u64) {
    let mut at = Some(n);
    while let Some(dir) = at.and_then(|n| dirs.get_mut(&n)) {
        dir.bytes = change(dir.bytes);
        at = dir.parent;
    }
}

/// The dirs of `dirs` (in order) that aren't in another of them.
fn outermost<D: AsRef<Path>>(dirs: impl Iterator<Item = D>) -> impl Iterator<Item = D> {
    let mut last: Option<PathBuf> = None;
    dirs.filter(move |dir| {
        let dir = dir.as_ref();
        if last.as_ref().is_some_and(|l| dir.starts_with(l)) {
            return false;
        }
        last = Some(dir.to_path_buf());
        true
    })
}

/// What `map` has of the dirs in `dir` (but `dir`), which come right after
/// it in order.
fn inside<'a, V>(
    map: &'a BTreeMap<PathBuf, V>,
    dir: &'a Path,
) -> impl Iterator<Item = (&'a PathBuf, &'a V)> {
    let after = (Bound::Excluded(dir), Bound::Unbounded);
    (map.range::<Path, _>(after)).take_while(move |(d, _)| d.starts_with(dir))
}

/// As `inside`, to change them.
fn inside_mut<'a, V>(
    map: &'a mut BTreeMap<PathBuf, V>,
    dir: &'a Path,
) -> impl Iterator<Item = (&'a PathBuf, &'a mut V)> {
    let after = (Bound::Excluded(dir), Bound::Unbounded);
    (map.range_mut::<Path, _>(after)).take_while(move |(d, _)| d.starts_with(dir))
}

/// A counting thread: reads the dirs to read until there are none, and none
/// is being read, which could find more.
fn count(shared: &Shared) {
    let mut state = shared.state.lock().unwrap();
    loop {
        let Some(job) = state.take() else {
            if state.reading == 0 {
                state.threads -= 1;
                return;
            }
            state = shared.wake.wait(state).unwrap();
            continue;
        };
        drop(state);
        let read = read(&job);
        state = shared.state.lock().unwrap();
        let counting = state.counts.len();
        if state.add(job.dir, read) || state.reading == 0 {
            shared.wake.notify_all();
        }
        if state.counts.len() < counting {
            shared.counted.notify_all();
        }
    }
}

/// Reads the dir of `job`: its own size (if the job asks for it), the size
/// of what's in it, and the dirs in it on the same device.
fn read(job: &Job) -> Read {
    let mut read = Read {
        device: job.device,
        ..Read::default()
    };
    if job.own {
        let Ok(meta) = job.path.symlink_metadata() else {
            read.unreadable = true;
            return read;
        };
        read.own = Some(size(job.measure, || job.path.clone(), &meta));
        // A link to a dir: the link's size, as a file's.
        if !meta.is_dir() {
            return read;
        }
        read.device = device(&meta);
    }
    let Ok(entries) = fs::read_dir(&job.path) else {
        read.unreadable = true;
        return read;
    };
    for entry in entries.flatten() {
        read.entries += 1;
        // Of a link itself.
        let Ok(meta) = entry.metadata() else {
            continue;
        };
        if !meta.is_dir() {
            let bytes = size(job.measure, || entry.path(), &meta);
            match hard_link(&meta) {
                Some((file, links)) => {
                    let link = Link {
                        size: bytes,
                        found: 1,
                        links,
                    };
                    read.links.push((file, link));
                }
                None => read.bytes += bytes,
            }
        } else if read.device.is_none() || device(&meta) == read.device {
            let dir = entry.path();
            let own = size(job.measure, || dir.clone(), &meta);
            read.dirs.push((dir, own));
        }
    }
    read
}

/// The size of a file as `measure` counts it (with `Measure::Disk`, a dir's
/// own too), whose metadata is `meta`, at the path `path` gives (only read
/// for the size on disk, on Windows).
fn size(measure: Measure, path: impl FnOnce() -> PathBuf, meta: &fs::Metadata) -> u64 {
    match measure {
        Measure::Size if meta.is_dir() => 0,
        Measure::Size => meta.len(),
        Measure::Disk => koil_core::disk_size(&path(), meta).unwrap_or(0),
    }
}

/// The file `meta` is, if it has other hard links and that can be told:
/// its device and inode, and how many links it has.
fn hard_link(meta: &fs::Metadata) -> Option<((u64, u64), u64)> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        (meta.nlink() > 1).then(|| ((meta.dev(), meta.ino()), meta.nlink()))
    }
    #[cfg(not(unix))]
    {
        let _ = meta;
        None
    }
}

/// The device `meta` is on, where that can be told.
fn device(meta: &fs::Metadata) -> Option<u64> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        Some(meta.dev())
    }
    #[cfg(not(unix))]
    {
        let _ = meta;
        None
    }
}

#[cfg(test)]
mod tests;
