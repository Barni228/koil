//! The sizes of dirs, counted on other threads, so the listing can show them
//! when it's sorted by size (see `listing::info`) without Koil waiting for
//! them.

use std::collections::{HashMap, HashSet, VecDeque};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::thread;

/// What's known of the size of a dir: the bytes of everything in it, as
/// Finder counts (not the dirs' own, and a link's own, not followed), but
/// what's on another device (a disk mounted in it, as `du -x`), and a file
/// with hard links in it once (as `du`: Cargo links its builds).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DirSize {
    /// The bytes counted so far.
    Counting(u64),
    Counted(u64),
    /// It can't be read, or isn't there.
    Unreadable,
}

/// The sizes known, by the dirs' paths.
pub type DirSizes = HashMap<PathBuf, DirSize>;

/// Counts the sizes of the dirs asked for (see `want`).
#[derive(Default)]
pub struct Sizes {
    shared: Arc<Shared>,
}

#[derive(Default)]
struct Shared {
    state: Mutex<State>,
    /// Signalled when there are dirs to read, or nothing is read any more.
    wake: Condvar,
}

#[derive(Default)]
struct State {
    sizes: DirSizes,
    /// The dirs being counted, by a number of their own, so that a read
    /// for one that was dropped isn't added to a new count of it.
    counts: HashMap<u64, Count>,
    next: u64,
    /// The counts with dirs to read, which take turns, so they all go on
    /// at once, and small ones are done soon.
    turns: VecDeque<u64>,
    /// The threads counting, and how many dirs they're reading.
    threads: usize,
    reading: usize,
}

/// A dir being counted.
struct Count {
    dir: PathBuf,
    bytes: u64,
    /// The dirs in it found and not read yet, the dir itself first.
    unread: Vec<PathBuf>,
    /// Whether the dir itself was read, and how many dirs are being read.
    started: bool,
    reading: usize,
    /// The device the dir is on, once it was read.
    device: Option<u64>,
    /// The files counted that have other hard links (see `hard_link`).
    links: HashSet<(u64, u64)>,
}

/// A dir to read for a count: whether it's the dir counted, and the
/// device that dir is on.
struct Job {
    count: u64,
    dir: PathBuf,
    root: bool,
    device: Option<u64>,
}

/// What reading a dir found: the bytes of what's in it, but the files
/// with other hard links, which are counted once (see `hard_link`, with
/// their sizes), the dirs in it to read next, and the device it's on.
#[derive(Default)]
struct Read {
    bytes: u64,
    links: Vec<((u64, u64), u64)>,
    dirs: Vec<PathBuf>,
    device: Option<u64>,
}

impl Sizes {
    /// What's known of the dirs asked for.
    pub fn known(&self) -> DirSizes {
        self.lock().sizes.clone()
    }

    /// Counts `dirs` (those not counted or being counted yet), and forgets
    /// every other dir, stopping its count.
    pub fn want(&self, dirs: impl IntoIterator<Item = PathBuf>) {
        let dirs: Vec<PathBuf> = dirs.into_iter().collect();
        let wanted: HashSet<&Path> = dirs.iter().map(PathBuf::as_path).collect();
        let mut state = self.lock();
        let state = &mut *state;
        state.sizes.retain(|dir, _| wanted.contains(dir.as_path()));
        state.counts.retain(|_, c| wanted.contains(c.dir.as_path()));
        state.turns.retain(|n| state.counts.contains_key(n));
        for dir in dirs {
            if state.sizes.contains_key(&dir) {
                continue;
            }
            state.sizes.insert(dir.clone(), DirSize::Counting(0));
            let count = Count {
                dir: dir.clone(),
                bytes: 0,
                unread: vec![dir],
                started: false,
                reading: 0,
                device: None,
                links: HashSet::new(),
            };
            state.counts.insert(state.next, count);
            state.turns.push_back(state.next);
            state.next += 1;
        }
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
    }

    /// Forgets every size, as what's on disk changed: a dir asked for again
    /// is counted again.
    pub fn forget(&self) {
        self.want([]);
    }

    fn lock(&self) -> MutexGuard<'_, State> {
        self.shared.state.lock().unwrap()
    }
}

impl State {
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
            let root = !count.started;
            count.started = true;
            count.reading += 1;
            self.reading += 1;
            return Some(Job {
                count: n,
                dir,
                root,
                device: count.device,
            });
        }
        None
    }

    /// Adds what reading a dir for the count `n` found (None: the dir
    /// counted can't be read). True if there are more dirs to read now.
    fn add(&mut self, n: u64, read: Option<Read>) -> bool {
        self.reading -= 1;
        // Dropped while it was read.
        let Some(count) = self.counts.get_mut(&n) else {
            return false;
        };
        count.reading -= 1;
        let Some(read) = read else {
            let count = self.counts.remove(&n).unwrap();
            self.sizes.insert(count.dir, DirSize::Unreadable);
            return false;
        };
        count.bytes += read.bytes;
        for (file, bytes) in read.links {
            if count.links.insert(file) {
                count.bytes += bytes;
            }
        }
        count.device = count.device.or(read.device);
        let more = !read.dirs.is_empty();
        if more && count.unread.is_empty() {
            self.turns.push_back(n);
        }
        count.unread.extend(read.dirs);
        let size = match count.unread.is_empty() && count.reading == 0 {
            true => DirSize::Counted(count.bytes),
            false => DirSize::Counting(count.bytes),
        };
        if let Some(known) = self.sizes.get_mut(&count.dir) {
            *known = size;
        }
        if let DirSize::Counted(_) = size {
            self.counts.remove(&n);
        }
        more
    }
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
        if state.add(job.count, read) || state.reading == 0 {
            shared.wake.notify_all();
        }
    }
}

/// Reads the dir of `job`: the bytes of what's in it, and the dirs in it on
/// the same device. None if it's the dir counted, and it can't be read; a
/// dir in it that can't be read counts as empty.
fn read(job: &Job) -> Option<Read> {
    let mut read = Read {
        device: job.device,
        ..Read::default()
    };
    if job.root {
        let meta = job.dir.symlink_metadata().ok()?;
        // A link to a dir: the link's size, as a file's.
        if !meta.is_dir() {
            read.bytes = meta.len();
            return Some(read);
        }
        read.device = device(&meta);
    }
    let entries = match fs::read_dir(&job.dir) {
        Ok(entries) => entries,
        Err(_) if job.root => return None,
        Err(_) => return Some(read),
    };
    for entry in entries.flatten() {
        // Of a link itself.
        let Ok(meta) = entry.metadata() else {
            continue;
        };
        if !meta.is_dir() {
            match hard_link(&meta) {
                Some(file) => read.links.push((file, meta.len())),
                None => read.bytes += meta.len(),
            }
        } else if read.device.is_none() || device(&meta) == read.device {
            read.dirs.push(entry.path());
        }
    }
    Some(read)
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
