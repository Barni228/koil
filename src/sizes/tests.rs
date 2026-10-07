use std::fs;
use std::time::{Duration, Instant};

use super::*;

/// What `sizes` knows of `dir` once it's no longer counting (failing after
/// a few seconds).
fn counted(sizes: &Sizes, dir: &Path) -> Option<DirSize> {
    let start = Instant::now();
    loop {
        let size = sizes.known().get(dir).copied();
        if !matches!(size, Some(DirSize::Counting(_))) || start.elapsed() > Duration::from_secs(5) {
            return size;
        }
        thread::sleep(Duration::from_millis(5));
    }
}

#[test]
fn test_counts_dirs() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    for dir in ["a/b/c", "a/d", "empty"] {
        fs::create_dir_all(root.join(dir)).unwrap();
    }
    fs::write(root.join("a/top"), "x".repeat(100)).unwrap();
    fs::write(root.join("a/b/c/deep"), "x".repeat(20)).unwrap();
    fs::write(root.join("a/d/.hidden"), "123").unwrap();
    let sizes = Sizes::default();
    let (a, empty) = (root.join("a"), root.join("empty"));
    sizes.want([a.clone(), empty.clone(), root.join("gone")]);
    assert_eq!(counted(&sizes, &a), Some(DirSize::Counted(123)));
    assert_eq!(counted(&sizes, &empty), Some(DirSize::Counted(0)));
    assert_eq!(
        counted(&sizes, &root.join("gone")),
        Some(DirSize::Unreadable)
    );

    // asked for again, it isn't counted again
    fs::write(root.join("a/more"), "x".repeat(1000)).unwrap();
    sizes.want([a.clone()]);
    assert_eq!(
        sizes.known(),
        DirSizes::from([(a.clone(), DirSize::Counted(123))])
    );
    // until it's forgotten
    sizes.forget();
    assert!(sizes.known().is_empty());
    sizes.want([a.clone()]);
    assert_eq!(counted(&sizes, &a), Some(DirSize::Counted(1123)));
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
    sizes.want([root.join("links"), root.join("dir-link")]);
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
    fs::create_dir_all(root.join("dir/deps")).unwrap();
    fs::write(root.join("dir/deps/build"), "x".repeat(1000)).unwrap();
    fs::hard_link(root.join("dir/deps/build"), root.join("dir/build")).unwrap();
    fs::hard_link(root.join("dir/deps/build"), root.join("elsewhere")).unwrap();
    let sizes = Sizes::default();
    sizes.want([root.join("dir")]);
    assert_eq!(
        counted(&sizes, &root.join("dir")),
        Some(DirSize::Counted(1000))
    );
}
