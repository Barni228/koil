use std::collections::BTreeSet;
use std::fs;

use super::*;

/// What `K` shows of `path`, a dir's size as `size` and `disk` say.
fn shown(path: &Path, size: Option<DirSize>, disk: Option<DirSize>) -> Info {
    let size_of = |measure| match measure {
        Measure::Size => size,
        Measure::Disk => disk,
    };
    read(path).show(size_of, Measure::Size)
}

/// The value of the row `label` in `text`, its first line.
fn row(text: &str, label: &str) -> Option<String> {
    let line = text
        .lines()
        .skip(1)
        .find(|line| (line.strip_prefix(label)).is_some_and(|rest| rest.starts_with("  ")))?;
    Some(line[label.len()..].trim().to_string())
}

#[test]
fn a_file() {
    let dir = tempfile::tempdir().unwrap();
    let file = dir.path().join("a.txt");
    fs::write(&file, "hello").unwrap();
    let info = shown(&file, None, None);
    assert!(!info.counting);
    assert_eq!(info.text.lines().next(), Some(show_path(&file).as_str()));
    assert_eq!(row(&info.text, "Kind").as_deref(), Some("File"));
    assert_eq!(row(&info.text, "Size").as_deref(), Some("5 bytes"));
    assert!(row(&info.text, "Modified").is_some());
    assert_eq!(row(&info.text, "Contains"), None);
    assert_eq!(read(&file).dir(), None);
    // every value starts in the same column, after the labels and two
    // spaces (a label has one at most, like "Hard links")
    let column = |line: &str| {
        let gap = line.find("  ").unwrap();
        gap + line[gap..].find(|c| c != ' ').unwrap()
    };
    let columns: BTreeSet<usize> = info.text.lines().skip(1).map(column).collect();
    assert_eq!(columns.len(), 1, "{}", info.text);
}

#[test]
fn a_dir() {
    let dir = tempfile::tempdir().unwrap();
    fs::create_dir(dir.path().join("sub")).unwrap();
    fs::write(dir.path().join("a.txt"), "a").unwrap();
    fs::write(dir.path().join(".hidden"), "").unwrap();
    let path = dir.path();
    assert_eq!(read(path).dir(), Some(path));
    let info = shown(path, Some(DirSize::Counted(1234)), None);
    assert!(!info.counting);
    let heading = info.text.lines().next().unwrap();
    assert!(heading.ends_with('/'), "{heading}");
    assert_eq!(row(&info.text, "Kind").as_deref(), Some("Dir"));
    assert_eq!(
        row(&info.text, "Size").as_deref(),
        Some("1.2 KB (1,234 bytes)")
    );
    // not counted by the other measure, it isn't shown
    assert_eq!(row(&info.text, "On disk"), None);
    assert_eq!(
        row(&info.text, "Contains").as_deref(),
        Some("3 entries: 1 dir, 2 files (1 hidden)")
    );
    #[cfg(unix)]
    assert_eq!(row(&info.text, "Hard links"), None);

    let counted = Some(DirSize::Counted(4096));
    let info = shown(path, Some(DirSize::Counting(0)), counted);
    assert!(info.counting);
    assert_eq!(row(&info.text, "Size").as_deref(), Some("Counting..."));
    assert_eq!(
        row(&info.text, "On disk").as_deref(),
        Some("4.1 KB (4,096 bytes)")
    );
    let info = shown(path, Some(DirSize::Counting(5000)), None);
    assert!(info.counting);
    assert_eq!(row(&info.text, "Size").as_deref(), Some("5.0 KB so far..."));
    let info = shown(path, Some(DirSize::Stale(5000)), None);
    assert!(info.counting);
    let info = shown(path, Some(DirSize::Unreadable), None);
    assert!(!info.counting);
    assert_eq!(row(&info.text, "Size").as_deref(), Some("Can't be counted"));
}

#[test]
fn what_a_dir_has() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path();
    assert_eq!(contents(path).plain(), "Nothing");
    fs::write(path.join(".env"), "").unwrap();
    assert_eq!(contents(path).plain(), "1 file, all hidden");
    fs::write(path.join("a"), "").unwrap();
    assert_eq!(contents(path).plain(), "2 files (1 hidden)");
    fs::create_dir(path.join("b")).unwrap();
    assert_eq!(
        contents(path).plain(),
        "3 entries: 1 dir, 2 files (1 hidden)"
    );
    #[cfg(unix)]
    {
        std::os::unix::fs::symlink("a", path.join("c")).unwrap();
        assert_eq!(
            contents(path).plain(),
            "4 entries: 1 dir, 2 files, 1 symlink (1 hidden)"
        );
    }
    assert!(
        contents(&path.join("gone"))
            .plain()
            .starts_with("Can't be read: ")
    );
}

#[test]
fn not_there() {
    let dir = tempfile::tempdir().unwrap();
    let info = shown(&dir.path().join("gone"), None, None);
    assert!(!info.counting);
    let error = row(&info.text, "Error").unwrap();
    assert!(error.starts_with("Can't be read: "), "{error}");
}

#[cfg(unix)]
#[test]
fn symlinks() {
    use std::os::unix::fs::symlink;
    let dir = tempfile::tempdir().unwrap();
    // canonical, as the target's real path is (/tmp is /private/tmp)
    let path = dir.path().canonicalize().unwrap();
    fs::write(path.join("a.txt"), "hello").unwrap();
    fs::create_dir(path.join("sub")).unwrap();
    symlink("a.txt", path.join("to-file")).unwrap();
    symlink("sub", path.join("to-dir")).unwrap();
    symlink("gone", path.join("broken")).unwrap();

    let info = shown(&path.join("to-file"), None, None);
    assert_eq!(
        row(&info.text, "Kind").as_deref(),
        Some("Symlink to a file")
    );
    assert_eq!(row(&info.text, "Target").as_deref(), Some("a.txt"));
    let real = show_path(&path.join("a.txt"));
    assert_eq!(row(&info.text, "Real path"), Some(real));
    assert_eq!(
        row(&info.text, "Size").as_deref(),
        Some("5 bytes, the target's")
    );
    let permissions = row(&info.text, "Permissions").unwrap();
    assert!(permissions.starts_with('l'), "{permissions}");

    // a link to a dir isn't counted, but what it has is shown
    let to_dir = path.join("to-dir");
    let info = shown(&to_dir, Some(DirSize::Counting(0)), None);
    assert!(!info.counting);
    assert_eq!(read(&to_dir).dir(), None);
    assert!(info.text.lines().next().unwrap().ends_with("to-dir/"));
    assert_eq!(row(&info.text, "Kind").as_deref(), Some("Symlink to a dir"));
    assert_eq!(row(&info.text, "Target").as_deref(), Some("sub"));
    let real = format!("{}/", show_path(&path.join("sub")));
    assert_eq!(row(&info.text, "Real path"), Some(real));
    assert_eq!(row(&info.text, "Contains").as_deref(), Some("Nothing"));
    assert_eq!(row(&info.text, "Size"), None);

    let info = shown(&path.join("broken"), None, None);
    assert_eq!(row(&info.text, "Kind").as_deref(), Some("Broken symlink"));
    assert_eq!(
        row(&info.text, "Target").as_deref(),
        Some("gone (not there)")
    );
    assert_eq!(row(&info.text, "Real path"), None);
    assert_eq!(row(&info.text, "Size"), None);

    // an absolute link written as it resolves shows it once
    symlink(path.join("a.txt"), path.join("absolute")).unwrap();
    let info = shown(&path.join("absolute"), None, None);
    assert_eq!(
        row(&info.text, "Target"),
        Some(show_path(&path.join("a.txt")))
    );
    assert_eq!(row(&info.text, "Real path"), None);
}

#[cfg(unix)]
#[test]
fn a_path_through_a_link() {
    use std::os::unix::fs::symlink;
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().canonicalize().unwrap();
    fs::create_dir(path.join("real")).unwrap();
    fs::write(path.join("real/a.txt"), "").unwrap();
    symlink("real", path.join("link")).unwrap();
    let info = shown(&path.join("link/a.txt"), None, None);
    let real = show_path(&path.join("real/a.txt"));
    assert_eq!(row(&info.text, "Real path"), Some(real));
    assert_eq!(
        row(
            &shown(&path.join("real/a.txt"), None, None).text,
            "Real path"
        ),
        None
    );
}

#[cfg(unix)]
#[test]
fn permissions_as_ls_shows_them() {
    let dir = tempfile::tempdir().unwrap();
    let file = dir.path().join("a");
    fs::write(&file, "").unwrap();
    let file = fs::symlink_metadata(&file).unwrap().file_type();
    let dir = fs::symlink_metadata(dir.path()).unwrap().file_type();
    assert_eq!(permissions(&file, 0o100644).plain(), "-rw-r--r-- (644)");
    assert_eq!(permissions(&file, 0o100755).plain(), "-rwxr-xr-x (755)");
    assert_eq!(permissions(&file, 0o104755).plain(), "-rwsr-xr-x (4755)");
    assert_eq!(permissions(&file, 0o104644).plain(), "-rwSr--r-- (4644)");
    assert_eq!(permissions(&file, 0o102755).plain(), "-rwxr-sr-x (2755)");
    assert_eq!(permissions(&file, 0o100000).plain(), "---------- (000)");
    assert_eq!(permissions(&dir, 0o041777).plain(), "drwxrwxrwt (1777)");
    assert_eq!(permissions(&dir, 0o041776).plain(), "drwxrwxrwT (1776)");
}

#[cfg(unix)]
#[test]
fn owner_and_group() {
    use std::os::unix::fs::MetadataExt;
    let dir = tempfile::tempdir().unwrap();
    let meta = fs::metadata(dir.path()).unwrap();
    let info = shown(dir.path(), None, None);
    let owner = row(&info.text, "Owner").unwrap();
    assert!(owner.ends_with(&format!(" ({})", meta.uid())), "{owner}");
    assert_eq!(user_name(meta.uid()).as_deref(), owner.split(' ').next());
    let group = row(&info.text, "Group").unwrap();
    assert!(group.ends_with(&format!("({})", meta.gid())), "{group}");
    // (u32::MAX - 1 is nobody, as -2)
    assert_eq!(user_name(987_654_321), None);
    assert!(row(&info.text, "Changed").is_some());
    assert_eq!(row(&info.text, "Inode"), None);
    assert_eq!(row(&info.text, "Xattrs"), None);
}

#[cfg(target_os = "macos")]
#[test]
fn flags() {
    use std::ffi::CString;
    use std::os::unix::ffi::OsStrExt;
    let dir = tempfile::tempdir().unwrap();
    let file = dir.path().join("a");
    fs::write(&file, "").unwrap();
    assert_eq!(row(&shown(&file, None, None).text, "Flags"), None);
    assert_eq!(flag_names(0), []);
    let flags = [("hidden", Kind::Muted), ("locked", Kind::Locked)];
    assert_eq!(flag_names(0x8000 | 0x2), flags);
    let path = CString::new(file.as_os_str().as_bytes()).unwrap();
    // SAFETY: a C string.
    assert_eq!(unsafe { libc::chflags(path.as_ptr(), 0x8000) }, 0);
    assert_eq!(
        row(&shown(&file, None, None).text, "Flags").as_deref(),
        Some("hidden")
    );
}

#[test]
fn sizes_and_counts() {
    assert_eq!(grouped(0), "0");
    assert_eq!(grouped(999), "999");
    assert_eq!(grouped(1000), "1,000");
    assert_eq!(grouped(1_234_567), "1,234,567");
    assert_eq!(size_text(0).plain(), "0 bytes");
    assert_eq!(size_text(1).plain(), "1 byte");
    assert_eq!(size_text(999).plain(), "999 bytes");
    assert_eq!(size_text(1000).plain(), "1.0 KB (1,000 bytes)");
    let count = |n| count(n, "entry", "entries", Kind::Muted).plain();
    assert_eq!(count(1), "1 entry");
    assert_eq!(count(1200), "1,200 entries");
}

#[test]
fn a_volumes_space() {
    let rows = |space| -> Vec<(&str, String)> {
        let rows = space_rows(space).into_iter();
        rows.map(|(label, text)| (label, text.plain())).collect()
    };
    let space = Space {
        total: 500_000_000_000,
        available: 120_000_000_000,
        purgeable: 20_000_000_000,
    };
    assert_eq!(
        rows(space),
        [
            ("Capacity", "500 GB".to_string()),
            ("Available", "120 GB (20 GB purgeable)".to_string()),
            ("Used", "380 GB (76%)".to_string()),
        ]
    );
    // nothing purgeable (on Windows), and none of it used
    let space = Space {
        total: 1000,
        available: 1000,
        purgeable: 0,
    };
    assert_eq!(rows(space)[1].1, "1.0 KB");
    assert_eq!(rows(space)[2].1, "0 B (0%)");
}

#[cfg(target_os = "macos")]
#[test]
fn a_volume() {
    // `/` is a volume's top dir: its space, rather than all of it counted
    let root = Path::new("/");
    let info = shown(root, None, None);
    assert_eq!(row(&info.text, "Kind").as_deref(), Some("Volume"));
    for label in ["Capacity", "Available", "Used"] {
        assert!(row(&info.text, label).is_some(), "{}", info.text);
    }
    assert_eq!(row(&info.text, "Size"), None);
    assert!(!info.counting);
    assert_eq!(read(root).dir(), None);
    // the data volume is one, where `/Users` really is, though `/Users`
    // isn't (a firmlink), nor a dir on it
    let data = volume(Path::new("/System/Volumes/Data")).unwrap();
    assert!(data.total > 0 && data.available <= data.total, "{data:?}");
    assert_eq!(volume(Path::new("/Users")), None);
    let dir = tempfile::tempdir().unwrap();
    assert_eq!(volume(dir.path()), None);
}

#[test]
fn times() {
    let now = SystemTime::now();
    let five = now - std::time::Duration::from_secs(5 * 60);
    let shown = time_text(five, now).plain();
    assert!(shown.ends_with(" (5 min ago)"), "{shown}");
    // a year or more ago, `time_ago` is the date, which isn't said twice
    let old = now - std::time::Duration::from_secs(400 * 24 * 60 * 60);
    let shown = time_text(old, now).plain();
    assert!(!shown.contains('('), "{shown}");
    assert_eq!(shown.len(), "2026-11-04 14:03:51".len());
}

/// The parts of `info`'s text its spans color, as (text, kind).
fn colored(info: &Info) -> Vec<(String, Kind)> {
    let lines: Vec<Vec<u16>> = info
        .text
        .lines()
        .map(|l| l.encode_utf16().collect())
        .collect();
    (info.spans.iter())
        .map(|span| {
            let line = &lines[span.line][span.start..span.start + span.length];
            (String::from_utf16(line).unwrap(), span.kind)
        })
        .collect()
}

/// The kind of the part of `info` that's `text`, the first.
fn kind_of(info: &Info, text: &str) -> Option<Kind> {
    let parts = colored(info);
    parts
        .into_iter()
        .find(|(part, _)| part == text)
        .map(|(_, kind)| kind)
}

#[test]
fn colors() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().canonicalize().unwrap();
    let file = path.join("a.txt");
    fs::write(&file, "x".repeat(1234)).unwrap();
    let info = shown(&file, None, None);
    // every span is in its line, and none is empty
    for span in &info.spans {
        let line = info.text.lines().nth(span.line).unwrap();
        assert!(span.length > 0 && span.start + span.length <= line.encode_utf16().count());
    }
    // the heading: its dirs as the listing colors them, its name not
    let heading = show_path(&file);
    let dirs = &heading[..heading.len() - "a.txt".len()];
    assert_eq!(kind_of(&info, dirs), Some(Kind::Dir));
    assert_eq!(kind_of(&info, "a.txt"), None);
    for label in ["Kind", "Size", "Modified"] {
        assert_eq!(kind_of(&info, label), Some(Kind::Label), "{label}");
    }
    assert_eq!(kind_of(&info, "File"), None);
    assert_eq!(kind_of(&info, "1.2"), Some(Kind::Size));
    assert_eq!(kind_of(&info, " KB"), Some(Kind::Unit));
    assert_eq!(kind_of(&info, "1,234"), Some(Kind::Size));
    assert_eq!(kind_of(&info, " bytes"), Some(Kind::Unit));
    assert_eq!(kind_of(&info, " ("), Some(Kind::Muted));

    let info = shown(&path, Some(DirSize::Counting(5000)), None);
    assert_eq!(kind_of(&info, "Dir"), Some(Kind::Dir));
    assert_eq!(kind_of(&info, " so far..."), Some(Kind::Busy));
    // files are in the text's color, which no span colors
    assert_eq!(kind_of(&info, " file"), None);
    assert_eq!(kind_of(&info, "1"), Some(Kind::Number));
}

#[test]
fn colored_times_and_contents() {
    let now = SystemTime::now();
    let time = time_text(now - std::time::Duration::from_secs(120), now);
    let kinds: Vec<Kind> = time.0.iter().map(|&(_, kind)| kind).collect();
    assert_eq!(kinds, [Kind::Date, Kind::Plain, Kind::Time, Kind::Muted]);
    assert_eq!(time.0[3].0, " (2 min ago)");

    let dir = tempfile::tempdir().unwrap();
    fs::create_dir(dir.path().join("a")).unwrap();
    fs::write(dir.path().join("b"), "").unwrap();
    let parts = contents(dir.path()).0;
    let parts: Vec<(&str, Kind)> = parts.iter().map(|(t, k)| (t.as_str(), *k)).collect();
    assert_eq!(
        parts,
        [
            ("2", Kind::Number),
            (" entries", Kind::Muted),
            (": ", Kind::Muted),
            ("1", Kind::Number),
            (" dir", Kind::Dir),
            (", ", Kind::Muted),
            ("1", Kind::Number),
            (" file", Kind::Plain),
        ]
    );
}

#[cfg(unix)]
#[test]
fn colored_permissions_and_owner() {
    use std::os::unix::fs::MetadataExt;
    let dir = tempfile::tempdir().unwrap();
    let kind = fs::symlink_metadata(dir.path()).unwrap().file_type();
    let mode = permissions(&kind, 0o044751);
    let kinds: Vec<(String, Kind)> = mode.0.clone();
    use Kind::*;
    let expected = [
        ("d", Dir),
        ("r", Read),
        ("w", Write),
        ("s", SetId),
        ("r", Read),
        ("-", Muted),
        ("x", Execute),
        ("-", Muted),
        ("-", Muted),
        ("x", Execute),
        (" (", Muted),
        ("4751", Number),
        (")", Muted),
    ];
    let expected: Vec<(String, Kind)> = expected.iter().map(|&(t, k)| (t.to_string(), k)).collect();
    assert_eq!(kinds, expected);

    // the user's own files and groups are told apart, and root's
    let meta = fs::metadata(dir.path()).unwrap();
    let info = shown(dir.path(), None, None);
    let name = user_name(meta.uid()).unwrap();
    assert_eq!(kind_of(&info, &name), Some(You));
    assert!(in_group(meta.gid()));
    assert_eq!(owner_kind(0, false), Root);
    assert_eq!(owner_kind(987_654_321, false), Plain);
}

#[cfg(unix)]
#[test]
fn colored_links() {
    use std::os::unix::fs::symlink;
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().canonicalize().unwrap();
    fs::create_dir(path.join("sub")).unwrap();
    symlink("sub", path.join("to-dir")).unwrap();
    symlink("gone", path.join("broken")).unwrap();
    let info = shown(&path.join("to-dir"), None, None);
    assert_eq!(kind_of(&info, "to-dir/"), Some(Kind::Link));
    assert_eq!(kind_of(&info, "Symlink to a dir"), Some(Kind::Link));
    assert_eq!(kind_of(&info, "sub"), Some(Kind::Link));
    assert_eq!(kind_of(&info, "sub/"), Some(Kind::Dir));
    let info = shown(&path.join("broken"), None, None);
    assert_eq!(kind_of(&info, "Broken symlink"), Some(Kind::Error));
    assert_eq!(kind_of(&info, " (not there)"), Some(Kind::Error));
}
