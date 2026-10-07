use std::fs;
use std::time::{Duration, Instant};

use super::*;

/// What `sizes` knows of `dir` once it's no longer counting (failing after
/// a few seconds).
fn counted(sizes: &Sizes, dir: &Path) -> Option<DirSize> {
    counted_by(sizes, dir, Measure::Size)
}

/// As `counted`, measured by `measure`.
fn counted_by(sizes: &Sizes, dir: &Path, measure: Measure) -> Option<DirSize> {
    let start = Instant::now();
    loop {
        let size = sizes.known(measure).size_of(dir);
        let counting = matches!(size, Some(DirSize::Counting(_) | DirSize::Stale(_)));
        if !counting || start.elapsed() > Duration::from_secs(5) {
            return size;
        }
        thread::sleep(Duration::from_millis(5));
    }
}

/// What `sizes` knows of `dir` now.
fn known(sizes: &Sizes, dir: &Path) -> Option<DirSize> {
    sizes.known(Measure::Size).size_of(dir)
}

/// Counts what `state` has to count on this thread, by size, with the
/// paths of the dirs it reads in `reads`, running `between` after each is
/// read, before what it found is added.
fn count_here(state: &mut State, reads: &mut Vec<PathBuf>, between: impl Fn(&mut State, &Path)) {
    while let Some(job) = state.take() {
        let read = read(&job);
        reads.push(job.path.clone());
        between(state, &job.path);
        state.add(job.count, job.dir, read);
    }
}

/// `a` with 100 bytes in it, `a/b/c` with 20 and `a/d` with 3 (and an
/// empty `a/d/e`, so it isn't small), and an empty `empty`, in `root`.
fn make_tree(root: &Path) {
    for dir in ["a/b/c", "a/d/e", "empty"] {
        fs::create_dir_all(root.join(dir)).unwrap();
    }
    fs::write(root.join("a/top"), "x".repeat(100)).unwrap();
    fs::write(root.join("a/b/c/deep"), "x".repeat(20)).unwrap();
    fs::write(root.join("a/d/.hidden"), "123").unwrap();
}

#[test]
fn test_counts_dirs() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    make_tree(root);
    let sizes = Sizes::default();
    let (a, empty) = (root.join("a"), root.join("empty"));
    sizes.want([a.clone(), empty.clone(), root.join("gone")], Measure::Size);
    assert_eq!(counted(&sizes, &a), Some(DirSize::Counted(123)));
    assert_eq!(counted(&sizes, &empty), Some(DirSize::Counted(0)));
    assert_eq!(
        counted(&sizes, &root.join("gone")),
        Some(DirSize::Unreadable)
    );

    // asked for again, it isn't counted again
    fs::write(root.join("a/more"), "x".repeat(1000)).unwrap();
    assert!(!sizes.want([a.clone()], Measure::Size));
    assert_eq!(known(&sizes, &a), Some(DirSize::Counted(123)));
    // nor once it wasn't asked for
    sizes.want([], Measure::Size);
    assert!(!sizes.want([a.clone()], Measure::Size));
    assert_eq!(known(&sizes, &a), Some(DirSize::Counted(123)));
    // until it's forgotten, which it still shows until it's asked for
    sizes.forget();
    assert_eq!(known(&sizes, &a), Some(DirSize::Counted(123)));
    assert!(sizes.want([a.clone()], Measure::Size));
    assert_eq!(counted(&sizes, &a), Some(DirSize::Counted(1123)));

    // a small dir isn't kept, but counted again before `want` is done
    assert!(sizes.want([empty.clone()], Measure::Size));
    assert_eq!(known(&sizes, &empty), Some(DirSize::Counted(0)));
}

#[test]
fn test_keeps_dirs_in_it() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    make_tree(root);
    let sizes = Sizes::default();
    let a = root.join("a");
    sizes.want([a.clone()], Measure::Size);
    assert_eq!(counted(&sizes, &a), Some(DirSize::Counted(123)));
    // known before they're asked for
    let (b, c, d) = (a.join("b"), a.join("b/c"), a.join("d"));
    assert_eq!(known(&sizes, &b), Some(DirSize::Counted(20)));
    assert_eq!(known(&sizes, &d), Some(DirSize::Counted(3)));
    // but small ones, counted again before `want` is done
    assert_eq!(known(&sizes, &c), None);
    assert!(sizes.want([c.clone()], Measure::Size));
    assert_eq!(known(&sizes, &c), Some(DirSize::Counted(20)));
    assert!(!sizes.want([b.clone(), d.clone()], Measure::Size));
    assert_eq!(known(&sizes, &b), Some(DirSize::Counted(20)));
    // and back
    assert!(!sizes.want([a.clone()], Measure::Size));
    assert_eq!(known(&sizes, &a), Some(DirSize::Counted(123)));
}

#[test]
fn test_small() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    let (few, many, deep) = (root.join("few"), root.join("many"), root.join("deep"));
    fs::create_dir_all(deep.join("in")).unwrap();
    for (dir, files) in [(&few, SMALL - 1), (&many, SMALL)] {
        fs::create_dir(dir).unwrap();
        for i in 0..files {
            fs::write(dir.join(i.to_string()), "x").unwrap();
        }
    }
    let sizes = Sizes::default();
    sizes.want([root.to_path_buf()], Measure::Size);
    let bytes = 2 * SMALL as u64 - 1;
    assert_eq!(counted(&sizes, root), Some(DirSize::Counted(bytes)));
    sizes.want([], Measure::Size);
    for (dir, kept) in [(root, true), (&few, false), (&many, true), (&deep, true)] {
        assert_eq!(known(&sizes, dir).is_some(), kept, "{dir:?}");
    }
}

#[test]
fn test_changed() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    make_tree(root);
    let sizes = Sizes::default();
    let a = root.join("a");
    let (b, c, d) = (a.join("b"), a.join("b/c"), a.join("d"));
    sizes.want([a.clone()], Measure::Size);
    assert_eq!(counted(&sizes, &a), Some(DirSize::Counted(123)));

    // the dirs it's in, and it
    fs::write(c.join("deep"), "x".repeat(40)).unwrap();
    sizes.changed(&c.join("deep"));
    // shown until it's asked for again
    assert_eq!(known(&sizes, &a), Some(DirSize::Counted(123)));
    sizes.want([], Measure::Size);
    assert_eq!(known(&sizes, &a), Some(DirSize::Stale(123)));
    assert_eq!(known(&sizes, &b), Some(DirSize::Stale(20)));
    assert_eq!(known(&sizes, &d), Some(DirSize::Counted(3)));
    fs::write(d.join(".hidden"), "1234").unwrap();
    sizes.want([a.clone()], Measure::Size);
    // `d` was kept, so it isn't read again
    assert_eq!(counted(&sizes, &a), Some(DirSize::Counted(143)));
    assert_eq!(known(&sizes, &b), Some(DirSize::Counted(40)));

    // a dir changed itself (a file added): not the dirs in it
    sizes.changed(&a);
    assert_eq!(known(&sizes, &b), Some(DirSize::Counted(40)));
    // a dir renamed: what was in it isn't there
    fs::rename(&d, a.join("f")).unwrap();
    sizes.changed(&d);
    sizes.changed(&a.join("f"));
    assert_eq!(known(&sizes, &d), None);
    assert_eq!(known(&sizes, &b), Some(DirSize::Counted(40)));
    // changes in it missed
    sizes.lost(&a);
    assert_eq!(known(&sizes, &b), Some(DirSize::Stale(40)));
}

#[test]
fn test_stale() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    make_tree(root);
    let mut state = State::default();
    let a = root.join("a");
    let b = a.join("b");
    state.want([a.clone()], Measure::Size);
    count_here(&mut state, &mut Vec::new(), |_, _| {});
    fs::write(b.join("c/deep"), "x".repeat(40)).unwrap();
    state.changed(&b.join("c/deep"), Change::Gone);
    // counted again, what it was until it's done
    assert!(state.want([a.clone(), b.clone()], Measure::Size));
    assert_eq!(state.size_of(&a, Measure::Size), Some(DirSize::Stale(123)));
    assert_eq!(state.size_of(&b, Measure::Size), Some(DirSize::Stale(20)));
    count_here(&mut state, &mut Vec::new(), |_, _| {});
    assert_eq!(
        state.size_of(&a, Measure::Size),
        Some(DirSize::Counted(143))
    );
    assert_eq!(state.size_of(&b, Measure::Size), Some(DirSize::Counted(40)));
}

#[test]
fn test_changed_while_counting() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    make_tree(root);
    let mut state = State::default();
    let a = root.join("a");
    let (b, c, d) = (a.join("b"), a.join("b/c"), a.join("d"));
    state.want([a.clone()], Measure::Size);
    let mut reads = Vec::new();
    let deep = c.join("deep");
    count_here(&mut state, &mut reads, |state, dir| {
        // after it was read
        if dir == c {
            state.changed(&deep, Change::Gone);
        }
    });
    assert_eq!(
        state.size_of(&a, Measure::Size),
        Some(DirSize::Counted(123))
    );
    // what it's in is kept stale, as the change may have come before
    for dir in [&a, &b] {
        assert!(state.kept[0][dir.as_path()].stale, "{dir:?}");
    }
    let kept = Kept {
        bytes: 3,
        links: false,
        stale: false,
    };
    assert_eq!(state.kept[0].get(&d), Some(&kept));
    // counted again, what was kept isn't read
    assert!(state.want([a.clone()], Measure::Size));
    reads.clear();
    count_here(&mut state, &mut reads, |_, _| {});
    assert_eq!(reads, [a.clone(), b, c]);
    assert!(state.kept[0].contains_key(&a));
}

#[test]
fn test_watches() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    make_tree(root);
    let sizes = Sizes::default();
    let (a, b, empty) = (root.join("a"), root.join("a/b"), root.join("empty"));
    sizes.want([b.clone()], Measure::Size);
    assert_eq!(sizes.watches(), [b.as_path()]);
    assert_eq!(counted(&sizes, &b), Some(DirSize::Counted(20)));
    sizes.want([a.clone(), empty.clone()], Measure::Size);
    assert_eq!(counted(&sizes, &a), Some(DirSize::Counted(123)));
    assert_eq!(counted(&sizes, &empty), Some(DirSize::Counted(0)));
    // not one in another
    assert_eq!(sizes.watches(), [a.clone(), empty.clone()]);
    // nor one that's neither asked for nor kept
    sizes.want([a.clone()], Measure::Size);
    assert_eq!(sizes.watches(), [a.as_path()]);
    sizes.unwatched(&a);
    assert_eq!(known(&sizes, &b), None);
    sizes.want([], Measure::Size);
    assert!(sizes.watches().is_empty());

    // many in one dir: that dir
    let dirs: Vec<PathBuf> = (0..=SIBLINGS).map(|i| root.join(format!("{i}"))).collect();
    for dir in &dirs {
        fs::create_dir(dir).unwrap();
    }
    sizes.want(dirs.clone(), Measure::Size);
    assert_eq!(sizes.watches(), [root]);
    sizes.want(dirs[1..].to_vec(), Measure::Size);
    assert_eq!(sizes.watches(), &dirs[1..]);
}

#[cfg(unix)]
#[test]
fn test_links_not_followed() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    fs::create_dir_all(root.join("dir/inside")).unwrap();
    fs::write(root.join("dir/inside/file"), "x".repeat(500)).unwrap();
    fs::create_dir(root.join("links")).unwrap();
    std::os::unix::fs::symlink(root.join("dir"), root.join("links/to-dir")).unwrap();
    std::os::unix::fs::symlink(root.join("dir"), root.join("dir-link")).unwrap();
    let sizes = Sizes::default();
    sizes.want([root.join("links"), root.join("dir-link")], Measure::Size);
    // a link's own size: its target's path
    let link = root.join("dir").as_os_str().len() as u64;
    assert_eq!(
        counted(&sizes, &root.join("links")),
        Some(DirSize::Counted(link))
    );
    assert_eq!(
        counted(&sizes, &root.join("dir-link")),
        Some(DirSize::Counted(link))
    );
}

#[cfg(unix)]
#[test]
fn test_hard_links_once() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    let dir = root.join("dir");
    // not small
    for d in ["deps/in", "x/in", "y/in"] {
        fs::create_dir_all(dir.join(d)).unwrap();
    }
    fs::write(dir.join("deps/build"), "x".repeat(1000)).unwrap();
    fs::hard_link(dir.join("deps/build"), dir.join("build")).unwrap();
    fs::hard_link(dir.join("deps/build"), root.join("elsewhere")).unwrap();
    fs::write(dir.join("x/same"), "x".repeat(10)).unwrap();
    fs::hard_link(dir.join("x/same"), dir.join("y/same")).unwrap();
    // counted in another count first, which has them once too
    let sizes = Sizes::default();
    sizes.want([dir.join("x")], Measure::Size);
    assert_eq!(counted(&sizes, &dir.join("x")), Some(DirSize::Counted(10)));
    sizes.want([dir.clone()], Measure::Size);
    assert_eq!(counted(&sizes, &dir), Some(DirSize::Counted(1010)));
    // each dir in it as if it was counted on its own
    for (d, bytes) in [("deps", 1000), ("x", 10), ("y", 10)] {
        assert_eq!(known(&sizes, &dir.join(d)), Some(DirSize::Counted(bytes)));
    }
}

#[cfg(unix)]
#[test]
fn test_counts_disk_size() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    // not small
    fs::create_dir_all(root.join("dir/inside/more")).unwrap();
    fs::write(root.join("dir/inside/written"), vec![1; 100_000]).unwrap();
    // bigger, but with nothing on disk
    let sparse = fs::File::create(root.join("dir/sparse")).unwrap();
    sparse.set_len(10_000_000).unwrap();
    let dir = root.join("dir");
    let sizes = Sizes::default();
    sizes.want([dir.clone()], Measure::Size);
    assert_eq!(counted(&sizes, &dir), Some(DirSize::Counted(10_100_000)));

    // measured the other way, it's counted again
    assert!(sizes.want([dir.clone()], Measure::Disk));
    let Some(DirSize::Counted(bytes)) = counted_by(&sizes, &dir, Measure::Disk) else {
        panic!("not counted");
    };
    // the file's blocks, and the dirs' own, as `du` counts
    let du = std::process::Command::new("du")
        .args(["-skx".as_ref(), dir.as_os_str()])
        .output()
        .unwrap();
    let du = String::from_utf8(du.stdout).unwrap();
    let kb: u64 = du.split_whitespace().next().unwrap().parse().unwrap();
    assert_eq!(bytes / 1024, kb, "{bytes}");
    assert!(bytes < 1_000_000, "{bytes}");
    // both are kept
    assert!(!sizes.want([dir.clone()], Measure::Size));
    assert_eq!(known(&sizes, &dir), Some(DirSize::Counted(10_100_000)));

    // the dir in it as if it was counted on its own
    let inside = dir.join("inside");
    let Some(DirSize::Counted(kept)) = counted_by(&sizes, &inside, Measure::Disk) else {
        panic!("not kept");
    };
    sizes.forget();
    sizes.want([inside.clone()], Measure::Disk);
    assert_eq!(
        counted_by(&sizes, &inside, Measure::Disk),
        Some(DirSize::Counted(kept))
    );
}
