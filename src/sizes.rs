//! The sizes of dirs, counted on other threads, so the listing can show them
//! when it's sorted by size or size on disk (see `listing::notes`) without
//! Koil waiting for them (but a moment, for small ones). Once a dir is
//! counted, its size is kept, and so are those of the dirs in it (but small
//! ones, see `SMALL`), until something changes in it on disk (see
//! `Sizes::changed`), so it isn't counted again when it's listed again, nor
//! are the dirs in it when they're listed.

use std::cell::RefCell;
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
    /// The dirs being counted, by a number of their own, in the order they
    /// started, so that a read for one that was dropped isn't added to a
    /// new count of it.
    counts: BTreeMap<u64, Count>,
    next: u64,
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
    /// Its count, while it's counted.
    count: Option<u64>,
    /// Whether something changed in it on disk since it was counted (or
    /// while), so it's counted again when it's asked for again.
    changed: bool,
}

/// A dir's size, kept.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Kept {
    bytes: u64,
    /// Whether files with other hard links are in it, which a count counts
    /// once (see `hard_link`): it can't be added to another count, which
    /// may have one of them elsewhere.
    links: bool,
    /// Whether something changed in it on disk since it was counted: then
    /// it's only shown until it's counted again (see `DirSize::Stale`), and
    /// it can't be added to another count.
    stale: bool,
}

/// A dir being counted.
struct Count {
    root: PathBuf,
    /// Whether nothing is known of its size until it's counted (it was
    /// never kept), so `want` waits for it, and it's read first.
    unknown: bool,
    /// The bytes counted so far.
    bytes: u64,
    /// The dirs in it being counted (and itself), by a number of their own.
    dirs: HashMap<usize, Dir>,
    next: usize,
    /// The dirs in it found and not read yet, the dir itself first.
    unread: Vec<usize>,
    /// How many dirs are being read.
    reading: usize,
    /// The device the dir is on, once it was read.
    device: Option<u64>,
    /// The dirs in it something changed in on disk while it was counted
    /// (see `Sizes::changed`), and those changes in which were missed: what
    /// was read of them (and of the dirs in those) may be from before, so
    /// they're kept stale. Nothing in those gone is kept.
    changed: HashSet<PathBuf>,
    missed: HashSet<PathBuf>,
    gone: HashSet<PathBuf>,
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

/// A dir in a count.
struct Dir {
    path: PathBuf,
    /// The dir it's in, None for the dir counted.
    parent: Option<usize>,
    /// What's counted of it so far, its own size too.
    bytes: u64,
    /// How many dirs in it aren't counted yet, and one more until it's
    /// read.
    left: usize,
    /// The files in it with other hard links (see `hard_link`), counted
    /// once, with their sizes.
    links: HashMap<(u64, u64), u64>,
    /// Whether its size is kept: not if it can't be read (it counts as
    /// empty), nor if it's small (see `SMALL`).
    keep: bool,
}

/// A dir to read for a count: which one, whether it's the dir counted, the
/// device that dir is on, and what's counted.
struct Job {
    count: u64,
    dir: usize,
    path: PathBuf,
    root: bool,
    device: Option<u64>,
    measure: Measure,
}

/// What reading a dir found: the size of what's in it (and its own, for
/// the dir counted), but the files with other hard links, which are
/// counted once (see `hard_link`, with their sizes), the dirs in it to read
/// next, with their own sizes, how many entries it has, and the device
/// it's on.
#[derive(Default)]
struct Read {
    bytes: u64,
    links: Vec<((u64, u64), u64)>,
    dirs: Vec<(PathBuf, u64)>,
    entries: usize,
    device: Option<u64>,
    /// It can't be read (a dir in the dir counted).
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
    /// it counted so far). Waits a moment (see `WAIT`) for those it starts
    /// that nothing was known of (those stale show what they were). True if
    /// it starts any.
    pub fn want(&self, dirs: impl IntoIterator<Item = PathBuf>, measure: Measure) -> bool {
        let mut state = self.lock();
        let first = state.next;
        let started = state.want(dirs, measure);
        let waits = |state: &State| state.counts.range(first..).any(|(_, c)| c.unknown);
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
        started
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
    /// See `Sizes::want`, which starts the threads.
    fn want(&mut self, dirs: impl IntoIterator<Item = PathBuf>, measure: Measure) -> bool {
        if measure != self.measure {
            self.measure = measure;
            self.wanted.clear();
            self.counts.clear();
        }
        let mut old = std::mem::take(&mut self.wanted);
        let mut started = false;
        for dir in dirs {
            if self.wanted.contains_key(&dir) {
                continue;
            }
            let was = old.remove(&dir);
            let kept = self.kept[measure.index()].get(&dir).copied();
            let wanted = match (was, kept) {
                // Known, or being counted, even if it changed since it
                // started: it's counted again once it's done.
                (Some(was), _) if !was.changed || was.count.is_some() => was,
                (_, Some(kept)) if !kept.stale => Wanted {
                    size: DirSize::Counted(kept.bytes),
                    count: None,
                    changed: false,
                },
                (was, kept) => {
                    started = true;
                    // Shown until it's counted again, so it stays where it
                    // was sorted.
                    let before = match was.map(|w| w.size) {
                        Some(DirSize::Counted(bytes) | DirSize::Stale(bytes)) => Some(bytes),
                        _ => kept.map(|kept| kept.bytes),
                    };
                    Wanted {
                        size: before.map_or(DirSize::Counting(0), DirSize::Stale),
                        count: Some(self.start(dir.clone(), before.is_none())),
                        changed: false,
                    }
                }
            };
            self.wanted.insert(dir, wanted);
        }
        for wanted in old.values() {
            if let Some(n) = wanted.count {
                self.counts.remove(&n);
            }
        }
        // Those unknown first, so small ones are done in the moment `want`
        // waits.
        let turns = std::mem::take(&mut self.turns).into_iter();
        let turns = turns.filter_map(|n| Some((n, self.counts.get(&n)?.unknown)));
        let (unknown, others): (VecDeque<_>, VecDeque<_>) = turns.partition(|&(_, u)| u);
        self.turns = unknown.into_iter().chain(others).map(|(n, _)| n).collect();
        started
    }

    /// Starts counting `dir` (`unknown`, see `Count::unknown`), returning
    /// its count's number.
    fn start(&mut self, dir: PathBuf, unknown: bool) -> u64 {
        self.roots.insert(dir.clone());
        let root = Dir {
            path: dir.clone(),
            parent: None,
            bytes: 0,
            left: 1,
            links: HashMap::new(),
            keep: true,
        };
        let count = Count {
            root: dir,
            unknown,
            bytes: 0,
            dirs: HashMap::from([(0, root)]),
            next: 1,
            unread: vec![0],
            reading: 0,
            device: None,
            changed: HashSet::new(),
            missed: HashSet::new(),
            gone: HashSet::new(),
        };
        let n = self.next;
        self.next += 1;
        self.counts.insert(n, count);
        self.turns.push_back(n);
        n
    }

    /// What's known of the size of `dir` by `measure` (see `Sizes::known`).
    fn size_of(&self, dir: &Path, measure: Measure) -> Option<DirSize> {
        match self.wanted.get(dir) {
            Some(wanted) if measure == self.measure => Some(wanted.size),
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
    /// their counts keep them stale, or not at all.
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
            let Some(wanted) = self.wanted.get_mut(&dir) else {
                continue;
            };
            wanted.changed = true;
            let Some(count) = wanted.count.and_then(|n| self.counts.get_mut(&n)) else {
                continue;
            };
            let root = &count.root;
            let changed = path.ancestors().take_while(|dir| dir.starts_with(root));
            count.changed.extend(changed.map(Path::to_path_buf));
            match change {
                Change::Itself => {}
                Change::Gone => _ = count.gone.insert(path.to_path_buf()),
                Change::Missed => _ = count.missed.insert(path.to_path_buf()),
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
        for count in self.counts.values_mut() {
            count.missed.insert(count.root.clone());
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
            count.reading += 1;
            self.reading += 1;
            let found = &count.dirs[&dir];
            return Some(Job {
                count: n,
                dir,
                path: found.path.clone(),
                root: found.parent.is_none(),
                device: count.device,
                measure: self.measure,
            });
        }
        None
    }

    /// Adds what reading the dir `dir` for the count `n` found (None: the
    /// dir counted can't be read), taking the sizes kept of the dirs in it
    /// that can be. True if there are more dirs to read now.
    fn add(&mut self, n: u64, dir: usize, read: Option<Read>) -> bool {
        self.reading -= 1;
        let State {
            wanted,
            kept,
            counts,
            turns,
            measure,
            ..
        } = self;
        let kept = &mut kept[measure.index()];
        // Dropped while it was read.
        let Some(count) = counts.get_mut(&n) else {
            return false;
        };
        count.reading -= 1;
        let Some(read) = read else {
            let count = counts.remove(&n).unwrap();
            if let Some(wanted) = wanted.get_mut(&count.root) {
                wanted.size = DirSize::Unreadable;
                wanted.count = None;
            }
            return false;
        };
        count.device = count.device.or(read.device);
        let mut found = Vec::new();
        let read_dir = count.dirs.get_mut(&dir).unwrap();
        let small = read.dirs.is_empty() && read.entries < SMALL;
        read_dir.keep = !read.unreadable && !small;
        read_dir.left -= 1;
        let mut bytes = read.bytes;
        for (file, size) in read.links {
            if read_dir.links.insert(file, size).is_none() {
                bytes += size;
            }
        }
        for (path, own) in read.dirs {
            match kept.get(&path) {
                // Counted before, with nothing in it this count can have
                // elsewhere, and nothing changed in it since.
                Some(k) if !k.links && !k.stale => bytes += k.bytes,
                _ => {
                    bytes += own;
                    read_dir.left += 1;
                    found.push(Dir {
                        path,
                        parent: Some(dir),
                        bytes: own,
                        left: 1,
                        links: HashMap::new(),
                        keep: true,
                    });
                }
            }
        }
        read_dir.bytes += bytes;
        count.bytes += bytes;
        let more = !found.is_empty();
        if more && count.unread.is_empty() {
            turns.push_back(n);
        }
        for d in found {
            count.dirs.insert(count.next, d);
            count.unread.push(count.next);
            count.next += 1;
        }
        // The dirs it finished, from it up.
        let mut at = dir;
        while count.dirs[&at].left == 0 {
            let done = count.dirs.remove(&at).unwrap();
            let stale = count.stale(&done.path);
            if let Some(stale) = stale.filter(|_| done.keep) {
                let links = !done.links.is_empty();
                let size = Kept {
                    bytes: done.bytes,
                    links,
                    stale,
                };
                kept.insert(done.path.clone(), size);
            }
            let Some(p) = done.parent else {
                counts.remove(&n);
                if let Some(wanted) = wanted.get_mut(&done.path) {
                    wanted.size = DirSize::Counted(done.bytes);
                    wanted.count = None;
                }
                return more;
            };
            let parent = count.dirs.get_mut(&p).unwrap();
            parent.bytes += done.bytes;
            parent.left -= 1;
            // A file in both was added twice.
            let (mut links, others) = match parent.links.len() >= done.links.len() {
                true => (std::mem::take(&mut parent.links), done.links),
                false => (done.links, std::mem::take(&mut parent.links)),
            };
            for (file, size) in others {
                if links.insert(file, size).is_some() {
                    parent.bytes -= size;
                    count.bytes -= size;
                }
            }
            parent.links = links;
            at = p;
        }
        // Counted again, it shows what it was until it's done.
        let size = wanted.get_mut(&count.root).map(|wanted| &mut wanted.size);
        if let Some(size @ DirSize::Counting(_)) = size {
            *size = DirSize::Counting(count.bytes);
        }
        more
    }
}

impl Count {
    /// Whether the size of `dir` in it is kept stale, as something changed
    /// in it on disk while it was counted (see `changed`), or None if it
    /// isn't kept, as it's gone.
    fn stale(&self, dir: &Path) -> Option<bool> {
        let in_one =
            |dirs: &HashSet<PathBuf>| !dirs.is_empty() && dir.ancestors().any(|d| dirs.contains(d));
        match in_one(&self.gone) {
            true => None,
            false => Some(self.changed.contains(dir) || in_one(&self.missed)),
        }
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
        if state.add(job.count, job.dir, read) || state.reading == 0 {
            shared.wake.notify_all();
        }
        if state.counts.len() < counting {
            shared.counted.notify_all();
        }
    }
}

/// Reads the dir of `job`: the size of what's in it, and the dirs in it on
/// the same device. None if it's the dir counted, and it can't be read; a
/// dir in it that can't be read counts as empty.
fn read(job: &Job) -> Option<Read> {
    let mut read = Read {
        device: job.device,
        ..Read::default()
    };
    if job.root {
        let meta = job.path.symlink_metadata().ok()?;
        read.bytes = size(job.measure, || job.path.clone(), &meta);
        // A link to a dir: the link's size, as a file's.
        if !meta.is_dir() {
            return Some(read);
        }
        read.device = device(&meta);
    }
    let entries = match fs::read_dir(&job.path) {
        Ok(entries) => entries,
        Err(_) if job.root => return None,
        Err(_) => {
            read.unreadable = true;
            return Some(read);
        }
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
                Some(file) => read.links.push((file, bytes)),
                None => read.bytes += bytes,
            }
        } else if read.device.is_none() || device(&meta) == read.device {
            let dir = entry.path();
            let own = size(job.measure, || dir.clone(), &meta);
            read.dirs.push((dir, own));
        }
    }
    Some(read)
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
/// its device and inode.
fn hard_link(meta: &fs::Metadata) -> Option<(u64, u64)> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        (meta.nlink() > 1).then(|| (meta.dev(), meta.ino()))
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
