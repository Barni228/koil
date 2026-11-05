//! What `K` shows of an entry (see Info in CLAUDE.md): everything there is
//! to know of it on disk, as `ls -l`, `stat` and Finder's Get Info tell it.
//! A dir's size is counted on other threads (see sizes.rs), so it's put in
//! as it's shown, as far as it's counted then.

use std::fs::{self, FileType, Metadata};
use std::io;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

use serde::Serialize;

use crate::listing::{describe, show_path, show_size, slashed, time_ago};
use crate::sizes::{DirSize, Measure};

#[cfg(test)]
mod tests;

/// What `K` shows, as QML takes it.
#[derive(Debug, Default, Serialize)]
pub struct Info {
    pub text: String,
    /// The parts of `text` to color, by what they are.
    pub spans: Vec<Span>,
    /// A dir's size is still being counted, so it's shown again until it's
    /// done.
    pub counting: bool,
}

/// A part of a line of what `K` shows, from `start` (in UTF-16, as Qt has
/// it), `length` long, which the box colors as `kind` says (see
/// `theme.infoColor`).
#[derive(Debug, PartialEq, Eq, Serialize)]
pub struct Span {
    pub line: usize,
    pub start: usize,
    pub length: usize,
    pub kind: Kind,
}

/// What a part of what `K` shows is, which says its color.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum Kind {
    /// In the text's color, not colored.
    Plain,
    /// A row's label.
    Label,
    /// What only goes with what's around it: brackets, commas, how long
    /// ago, what a number counts.
    Muted,
    /// A dir, and the dirs a path is in, as the listing colors dirs.
    Dir,
    /// A symlink, and what it points to as it's written.
    Link,
    /// What isn't there or can't be read.
    Error,
    /// A pipe, a socket or a device, and other entries a dir has.
    Special,
    /// A size, and its unit.
    Size,
    Unit,
    /// Any other number: a count, an ID, a mode in octal.
    Number,
    /// A dir's size while it's counted.
    Busy,
    /// A date, and a time of day.
    Date,
    Time,
    /// A permission to read, write or execute, and setuid, setgid or the
    /// sticky bit.
    Read,
    Write,
    Execute,
    SetId,
    /// The user (or a group of the user) Koil runs as, and root.
    You,
    Root,
    /// A flag, and one that keeps what's there from changing.
    Flag,
    Locked,
}

/// Text in parts, each of a kind.
#[derive(Debug, Clone, Default)]
struct Text(Vec<(String, Kind)>);

impl Text {
    fn of(text: impl Into<String>, kind: Kind) -> Text {
        Text(vec![(text.into(), kind)])
    }

    fn and(mut self, text: impl Into<String>, kind: Kind) -> Text {
        self.0.push((text.into(), kind));
        self
    }

    fn then(mut self, text: Text) -> Text {
        self.0.extend(text.0);
        self
    }

    /// The parts of `texts`, with `between` between each two.
    fn joined(texts: impl IntoIterator<Item = Text>, between: &str) -> Text {
        let mut joined = Text::default();
        for (i, text) in texts.into_iter().enumerate() {
            if i > 0 {
                joined = joined.and(between, Kind::Muted);
            }
            joined = joined.then(text);
        }
        joined
    }

    /// Its text, without the kinds.
    #[cfg(test)]
    fn plain(&self) -> String {
        self.0.iter().map(|(text, _)| text.as_str()).collect()
    }
}

/// What was read of an entry on disk (see [`read`]).
#[derive(Debug)]
pub struct Entry {
    path: PathBuf,
    /// Its path, as Koil shows it, with a `/` after a dir's.
    heading: Text,
    rows: Vec<Row>,
}

#[derive(Debug)]
struct Row {
    label: &'static str,
    value: Value,
}

#[derive(Debug)]
enum Value {
    Text(Text),
    /// A dir's size by a measure, as far as it's known when it's shown.
    DirSize(Measure),
}

impl Entry {
    /// The dir whose size it shows, if it's one (a link to one isn't
    /// counted, as the counts don't follow links).
    pub fn dir(&self) -> Option<&Path> {
        let sized = self
            .rows
            .iter()
            .any(|r| matches!(r.value, Value::DirSize(_)));
        sized.then_some(self.path.as_path())
    }

    /// What `K` shows of it, a dir's size by `counted` as `size_of` knows
    /// it, and by the other measure if it's counted too, which isn't shown
    /// otherwise.
    pub fn show(&self, size_of: impl Fn(Measure) -> Option<DirSize>, counted: Measure) -> Info {
        let mut counting = false;
        let rows = self.rows.iter().filter_map(|row| {
            let text = match &row.value {
                Value::Text(text) => text.clone(),
                Value::DirSize(measure) if *measure == counted => {
                    let (text, busy) = dir_size(size_of(counted));
                    counting |= busy;
                    text
                }
                Value::DirSize(measure) => match size_of(*measure) {
                    Some(DirSize::Counted(bytes)) => size_text(bytes),
                    _ => return None,
                },
            };
            Some((row.label, text))
        });
        let rows: Vec<_> = rows.collect();
        let width = rows.iter().map(|(label, _)| label.len()).max().unwrap_or(0) + 2;
        let mut shown = Shown::default();
        shown.add(&self.heading);
        for (label, text) in rows {
            shown.new_line();
            shown.push(label, Kind::Label);
            shown.push(&" ".repeat(width - label.len()), Kind::Plain);
            shown.add(&text);
        }
        let Shown { text, spans, .. } = shown;
        Info {
            text,
            spans,
            counting,
        }
    }
}

/// What `K` shows, as it's put together (see [`Entry::show`]): its text,
/// and the spans of its parts with a color, the last line's where it ends.
#[derive(Default)]
struct Shown {
    text: String,
    spans: Vec<Span>,
    line: usize,
    column: usize,
}

impl Shown {
    fn push(&mut self, text: &str, kind: Kind) {
        let length = text.encode_utf16().count();
        if kind != Kind::Plain && length > 0 {
            let (line, start) = (self.line, self.column);
            self.spans.push(Span {
                line,
                start,
                length,
                kind,
            });
        }
        self.text.push_str(text);
        self.column += length;
    }

    fn add(&mut self, text: &Text) {
        for (part, kind) in &text.0 {
            self.push(part, *kind);
        }
    }

    fn new_line(&mut self) {
        self.text.push('\n');
        self.line += 1;
        self.column = 0;
    }
}

/// Everything there is to know of what's at `path`, the link itself for a
/// link: what it is (and a link's target), its size (a dir's is put in as
/// it's shown) and what a dir has, its times, its permissions and owner,
/// and what the system keeps of it besides (flags).
pub fn read(path: &Path) -> Entry {
    let entry = |heading, rows| Entry {
        path: path.to_path_buf(),
        heading,
        rows,
    };
    let meta = match fs::symlink_metadata(path) {
        Ok(meta) => meta,
        Err(error) => {
            let why = Text::of(format!("Can't be read: {}", describe(&error)), Kind::Error);
            return entry(
                path_text(&show_path(path), Kind::Plain),
                vec![row("Error", why)],
            );
        }
    };
    let kind = meta.file_type();
    // What a link points to, followed to the end.
    let target = kind.is_symlink().then(|| fs::metadata(path));
    let target_meta = target.as_ref().and_then(|t| t.as_ref().ok());
    let lists = kind.is_dir() || target_meta.is_some_and(Metadata::is_dir);
    let name = match () {
        _ if kind.is_symlink() => Kind::Link,
        _ if kind.is_dir() => Kind::Dir,
        _ => Kind::Plain,
    };
    let mut rows = vec![row("Kind", kind_text(&kind, target.as_ref()))];
    match &target {
        Some(target) => rows.extend(target_rows(path, target)),
        None => {
            let absolute = std::path::absolute(path).ok();
            if let Some(real) = real_path(path).filter(|real| Some(real) != absolute.as_ref()) {
                let real = path_text(&slashed(show_path(&real), lists), name);
                rows.push(row("Real path", real));
            }
        }
    }
    if kind.is_dir() {
        for (label, measure) in [("Size", Measure::Size), ("On disk", Measure::Disk)] {
            let value = Value::DirSize(measure);
            rows.push(Row { label, value });
        }
    } else if kind.is_file() {
        rows.push(row("Size", size_text(meta.len())));
        if let Some(bytes) = koil_core::disk_size(path, &meta) {
            rows.push(row("On disk", size_text(bytes)));
        }
    } else if let Some(target) = target_meta.filter(|t| t.is_file()) {
        let size = size_text(target.len()).and(", the target's", Kind::Muted);
        rows.push(row("Size", size));
    }
    if lists {
        rows.push(row("Contains", contents(path)));
    }
    let now = SystemTime::now();
    let times = [
        ("Modified", meta.modified()),
        ("Created", meta.created()),
        ("Accessed", meta.accessed()),
    ];
    for (label, time) in times {
        // 0 where the filesystem doesn't keep it (a device's creation).
        if let Some(time) = time.ok().filter(|&time| time != SystemTime::UNIX_EPOCH) {
            rows.push(row(label, time_text(time, now)));
        }
    }
    for (label, text) in system_rows(&meta, now) {
        rows.push(row(label, text));
    }
    entry(path_text(&slashed(show_path(path), lists), name), rows)
}

/// A row of text.
fn row(label: &'static str, text: Text) -> Row {
    let value = Value::Text(text);
    Row { label, value }
}

/// A path as Koil shows it (`shown`, with a `/` after a dir's): the dirs
/// it's in colored as the listing colors dirs, and its name as `name`.
fn path_text(shown: &str, name: Kind) -> Text {
    let trimmed = shown.strip_suffix('/').unwrap_or(shown);
    let at = trimmed.rfind('/').map_or(0, |i| i + 1);
    Text::of(&shown[..at], Kind::Dir).and(&shown[at..], name)
}

/// What `kind` is, and if it's a link, what `target` (its own metadata,
/// followed to the end) says it points to.
fn kind_text(kind: &FileType, target: Option<&io::Result<Metadata>>) -> Text {
    let (text, color) = match target {
        Some(Ok(target)) if target.is_dir() => ("Symlink to a dir", Kind::Link),
        Some(Ok(_)) => ("Symlink to a file", Kind::Link),
        Some(Err(error)) if error.kind() == io::ErrorKind::NotFound => {
            ("Broken symlink", Kind::Error)
        }
        Some(Err(_)) => ("Symlink", Kind::Link),
        None if kind.is_dir() => ("Dir", Kind::Dir),
        None if kind.is_file() => ("File", Kind::Plain),
        None => (special_kind(kind), Kind::Special),
    };
    Text::of(text, color)
}

#[cfg(unix)]
fn special_kind(kind: &FileType) -> &'static str {
    use std::os::unix::fs::FileTypeExt;
    match kind {
        _ if kind.is_fifo() => "Named pipe",
        _ if kind.is_socket() => "Socket",
        _ if kind.is_block_device() => "Block device",
        _ if kind.is_char_device() => "Character device",
        _ => "Unknown",
    }
}

#[cfg(not(unix))]
fn special_kind(_kind: &FileType) -> &'static str {
    "Unknown"
}

/// Where the link at `path` points, as it's written (Target), or that it
/// isn't there, from `target`, what's there; and where that is, followed
/// to the end (Real path), if it's written otherwise (relative, or to
/// another link). Not on one row with an arrow between, which read as the
/// link and its target, as `ls -l` shows them.
fn target_rows(path: &Path, target: &io::Result<Metadata>) -> Vec<Row> {
    let written = match fs::read_link(path) {
        Ok(written) => written,
        Err(error) => {
            let why = Text::of(format!("Can't be read: {}", describe(&error)), Kind::Error);
            return vec![row("Target", why)];
        }
    };
    let shown = Text::of(show_path(&written), Kind::Link);
    let target = match target {
        Ok(target) => target,
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            return vec![row("Target", shown.and(" (not there)", Kind::Error))];
        }
        Err(error) => {
            let why = format!(" (can't be read: {})", describe(error));
            return vec![row("Target", shown.and(why, Kind::Error))];
        }
    };
    let mut rows = vec![row("Target", shown)];
    if let Some(real) = real_path(path).filter(|real| *real != written) {
        let name = if target.is_dir() {
            Kind::Dir
        } else {
            Kind::Plain
        };
        let real = path_text(&slashed(show_path(&real), target.is_dir()), name);
        rows.push(row("Real path", real));
    }
    rows
}

/// `path` with every link in it followed, without the `\\?\` Windows puts
/// before a drive's path, which koil's paths don't have. None if it can't
/// be.
fn real_path(path: &Path) -> Option<PathBuf> {
    let real = fs::canonicalize(path).ok()?;
    #[cfg(windows)]
    if let Some(rest) = real.to_str().and_then(|s| s.strip_prefix(r"\\?\"))
        && rest.as_bytes().get(1) == Some(&b':')
    {
        return Some(PathBuf::from(rest));
    }
    Some(real)
}

/// A dir's size (see [`Entry::show`]), as far as it's counted (`size`),
/// and whether it's still being counted.
fn dir_size(size: Option<DirSize>) -> (Text, bool) {
    match size {
        Some(DirSize::Counted(bytes)) => (size_text(bytes), false),
        Some(DirSize::Counting(bytes @ 1..)) => {
            (short_size(bytes).and(" so far...", Kind::Busy), true)
        }
        Some(DirSize::Stale(bytes)) => (
            short_size(bytes).and(", counting again...", Kind::Busy),
            true,
        ),
        Some(DirSize::Counting(_)) | None => (Text::of("Counting...", Kind::Busy), true),
        Some(DirSize::Unreadable) => (Text::of("Can't be counted", Kind::Error), false),
    }
}

/// `bytes` as people read a size, and as they are past 1000: `1.2 KB
/// (1,234 bytes)`.
fn size_text(bytes: u64) -> Text {
    let unit = if bytes == 1 { " byte" } else { " bytes" };
    let exact = Text::of(grouped(bytes), Kind::Size).and(unit, Kind::Unit);
    match bytes {
        ..1000 => exact,
        _ => short_size(bytes)
            .and(" (", Kind::Muted)
            .then(exact)
            .and(")", Kind::Muted),
    }
}

/// `bytes` as people read a size (see `listing::show_size`): `1.2 KB`.
fn short_size(bytes: u64) -> Text {
    let shown = show_size(bytes);
    let (number, unit) = shown.split_once(' ').unwrap_or((&shown, ""));
    Text::of(number, Kind::Size).and(format!(" {unit}"), Kind::Unit)
}

/// `n` with a `,` between each three digits: `1,234,567`.
fn grouped(n: u64) -> String {
    let digits = n.to_string();
    let mut shown = String::new();
    for (i, digit) in digits.chars().enumerate() {
        if i > 0 && (digits.len() - i).is_multiple_of(3) {
            shown.push(',');
        }
        shown.push(digit);
    }
    shown
}

/// `n` of something, `one` or `many` (colored as `kind`), like `1 dir` or
/// `1,234 files`.
fn count(n: u64, one: &str, many: &str, kind: Kind) -> Text {
    let what = if n == 1 { one } else { many };
    Text::of(grouped(n), Kind::Number).and(format!(" {what}"), kind)
}

/// What the dir at `path` has: how many entries, of which kinds, and how
/// many of them are hidden (their names start with `.`, which the listing
/// hides unless `:set hidden` is on).
fn contents(path: &Path) -> Text {
    let entries = match fs::read_dir(path) {
        Ok(entries) => entries,
        Err(error) => {
            return Text::of(format!("Can't be read: {}", describe(&error)), Kind::Error);
        }
    };
    let [mut dirs, mut files, mut links, mut others, mut hidden] = [0; 5];
    for entry in entries.flatten() {
        if entry.file_name().as_encoded_bytes().starts_with(b".") {
            hidden += 1;
        }
        match entry.file_type() {
            Ok(kind) if kind.is_dir() => dirs += 1,
            Ok(kind) if kind.is_file() => files += 1,
            Ok(kind) if kind.is_symlink() => links += 1,
            _ => others += 1,
        }
    }
    let total = dirs + files + links + others;
    if total == 0 {
        return Text::of("Nothing", Kind::Muted);
    }
    let kinds = [
        (dirs, "dir", "dirs", Kind::Dir),
        (files, "file", "files", Kind::Plain),
        (links, "symlink", "symlinks", Kind::Link),
        (others, "other", "others", Kind::Special),
    ];
    let mut kinds: Vec<Text> = (kinds.into_iter())
        .filter(|&(n, ..)| n > 0)
        .map(|(n, one, many, kind)| count(n, one, many, kind))
        .collect();
    let shown = match kinds.len() {
        1 => kinds.remove(0),
        _ => count(total, "entry", "entries", Kind::Muted)
            .and(": ", Kind::Muted)
            .then(Text::joined(kinds, ", ")),
    };
    match hidden {
        0 => shown,
        _ if hidden == total => shown.and(", all hidden", Kind::Muted),
        _ => (shown.and(" (", Kind::Muted))
            .and(grouped(hidden), Kind::Number)
            .and(" hidden)", Kind::Muted),
    }
}

/// `time` in the local time zone, to the second, and how long before
/// `now` it was (see `listing::time_ago`), unless that's the time again.
fn time_text(time: SystemTime, now: SystemTime) -> Text {
    let local = chrono::DateTime::<chrono::Local>::from(time);
    let full = Text::of(local.format("%Y-%m-%d").to_string(), Kind::Date)
        .and(" ", Kind::Plain)
        .and(local.format("%H:%M:%S").to_string(), Kind::Time);
    match time_ago(time, now) {
        (ago, Some(_)) => full.and(format!(" ({ago})"), Kind::Muted),
        _ => full,
    }
}

/// Rows of text, by their labels.
type Rows = Vec<(&'static str, Text)>;

/// What Unix keeps of what's at a path (with `meta`, of the link itself for
/// a link) besides: when its metadata last changed, its permissions,
/// owner and group, its hard links (not a dir's, which count its dirs),
/// and on macOS its flags.
#[cfg(unix)]
fn system_rows(meta: &Metadata, now: SystemTime) -> Rows {
    use std::os::unix::fs::MetadataExt;
    use std::time::{Duration, UNIX_EPOCH};
    let mut rows = Vec::new();
    let changed = u64::try_from(meta.ctime()).ok().map(|secs| {
        let nanos = u32::try_from(meta.ctime_nsec()).unwrap_or(0);
        UNIX_EPOCH + Duration::new(secs, nanos)
    });
    if let Some(changed) = changed {
        rows.push(("Changed", time_text(changed, now)));
    }
    rows.push(("Permissions", permissions(&meta.file_type(), meta.mode())));
    let (uid, gid) = (meta.uid(), meta.gid());
    // SAFETY: geteuid can't fail.
    let owner = owner_kind(uid, uid == unsafe { libc::geteuid() });
    rows.push(("Owner", named(user_name(uid), uid, owner)));
    let group = owner_kind(gid, in_group(gid));
    rows.push(("Group", named(group_name(gid), gid, group)));
    if !meta.is_dir() {
        rows.push(("Hard links", Text::of(grouped(meta.nlink()), Kind::Number)));
    }
    #[cfg(target_os = "macos")]
    {
        use std::os::macos::fs::MetadataExt;
        let flags = flag_names(meta.st_flags());
        if !flags.is_empty() {
            let flags = flags.into_iter().map(|(name, kind)| Text::of(name, kind));
            rows.push(("Flags", Text::joined(flags, ", ")));
        }
    }
    rows
}

/// What Windows keeps of what's at a path besides: its attributes
/// (read-only, hidden, and so on).
#[cfg(windows)]
fn system_rows(meta: &Metadata, _now: SystemTime) -> Rows {
    use std::os::windows::fs::MetadataExt;
    let names = attribute_names(meta.file_attributes());
    let names = names.into_iter().map(|(name, kind)| Text::of(name, kind));
    match names.len() {
        0 => Vec::new(),
        _ => vec![("Attributes", Text::joined(names, ", "))],
    }
}

#[cfg(not(any(unix, windows)))]
fn system_rows(_meta: &Metadata, _now: SystemTime) -> Rows {
    Vec::new()
}

/// How an owner (or a group) `id` is colored: root's (0), the user's own
/// (`yours`), or not at all.
#[cfg(unix)]
fn owner_kind(id: u32, yours: bool) -> Kind {
    match () {
        _ if yours => Kind::You,
        _ if id == 0 => Kind::Root,
        _ => Kind::Plain,
    }
}

/// Whether the user Koil runs as is in the group `gid`.
#[cfg(unix)]
fn in_group(gid: u32) -> bool {
    // SAFETY: getegid can't fail, and getgroups with no room says how many
    // groups there are.
    let (own, count) = unsafe { (libc::getegid(), libc::getgroups(0, std::ptr::null_mut())) };
    if own == gid {
        return true;
    }
    let mut groups = vec![0; usize::try_from(count).unwrap_or(0)];
    // SAFETY: the buffer has room for `count` groups.
    let count = unsafe { libc::getgroups(count, groups.as_mut_ptr()) };
    groups.truncate(usize::try_from(count).unwrap_or(0));
    groups.contains(&gid)
}

/// A name colored as `kind` and its number, like `andy (501)`, or the
/// number alone if it has no name.
#[cfg(unix)]
fn named(name: Option<String>, id: u32, kind: Kind) -> Text {
    match name {
        Some(name) => (Text::of(name, kind).and(" (", Kind::Muted))
            .and(id.to_string(), Kind::Number)
            .and(")", Kind::Muted),
        None => Text::of(id.to_string(), Kind::Number),
    }
}

/// A mode as `ls -l` shows it, the kind first (`-` for a file, `d` for a
/// dir, `l` for a link), and in octal, like `-rw-r--r-- (644)`, each
/// permission colored by what it lets do.
#[cfg(unix)]
fn permissions(kind: &FileType, mode: u32) -> Text {
    use std::os::unix::fs::FileTypeExt;
    let kind = match kind {
        _ if kind.is_dir() => ('d', Kind::Dir),
        _ if kind.is_symlink() => ('l', Kind::Link),
        _ if kind.is_fifo() => ('p', Kind::Special),
        _ if kind.is_socket() => ('s', Kind::Special),
        _ if kind.is_block_device() => ('b', Kind::Special),
        _ if kind.is_char_device() => ('c', Kind::Special),
        _ => ('-', Kind::Muted),
    };
    let none = ('-', Kind::Muted);
    let bit = |bit: u32, c: char, kind: Kind| if mode & bit != 0 { (c, kind) } else { none };
    // Execute, with setuid, setgid or the sticky bit in its place.
    let exec = |bit: u32, special: u32, on: char| match (mode & bit != 0, mode & special != 0) {
        (true, true) => (on, Kind::SetId),
        (false, true) => (on.to_ascii_uppercase(), Kind::SetId),
        (true, false) => ('x', Kind::Execute),
        (false, false) => none,
    };
    let parts = [
        kind,
        bit(0o400, 'r', Kind::Read),
        bit(0o200, 'w', Kind::Write),
        exec(0o100, 0o4000, 's'),
        bit(0o040, 'r', Kind::Read),
        bit(0o020, 'w', Kind::Write),
        exec(0o010, 0o2000, 's'),
        bit(0o004, 'r', Kind::Read),
        bit(0o002, 'w', Kind::Write),
        exec(0o001, 0o1000, 't'),
    ];
    let shown = (parts.into_iter()).fold(Text::default(), |text, (c, kind)| text.and(c, kind));
    (shown.and(" (", Kind::Muted))
        .and(format!("{:03o}", mode & 0o7777), Kind::Number)
        .and(")", Kind::Muted)
}

/// The name of the user `uid`, if it has one.
#[cfg(unix)]
fn user_name(uid: u32) -> Option<String> {
    // SAFETY: all zeros is a valid `passwd` (null pointers and numbers),
    // which getpwuid_r fills in, its strings in `buffer`.
    let mut user: libc::passwd = unsafe { std::mem::zeroed() };
    with_buffer(|buffer, found: &mut *mut libc::passwd| {
        // SAFETY: the buffer is as long as the length given, and `user`
        // and `found` live through the call.
        let error =
            unsafe { libc::getpwuid_r(uid, &mut user, buffer.as_mut_ptr(), buffer.len(), found) };
        // SAFETY: once getpwuid_r found it, its name is a C string in the
        // buffer, which is still there.
        (
            error,
            (!found.is_null()).then(|| unsafe { c_string(user.pw_name) }),
        )
    })
}

/// The name of the group `gid`, if it has one.
#[cfg(unix)]
fn group_name(gid: u32) -> Option<String> {
    // SAFETY: as for `user_name`.
    let mut group: libc::group = unsafe { std::mem::zeroed() };
    with_buffer(|buffer, found: &mut *mut libc::group| {
        // SAFETY: as for `user_name`.
        let error =
            unsafe { libc::getgrgid_r(gid, &mut group, buffer.as_mut_ptr(), buffer.len(), found) };
        // SAFETY: as for `user_name`.
        (
            error,
            (!found.is_null()).then(|| unsafe { c_string(group.gr_name) }),
        )
    })
}

/// What `look_up` (getpwuid_r or getgrgid_r) gives, with a buffer for its
/// strings big enough for them: one twice as big while it says it's too
/// small (ERANGE), up to a MB.
#[cfg(unix)]
fn with_buffer<T>(
    mut look_up: impl FnMut(&mut [libc::c_char], &mut *mut T) -> (libc::c_int, Option<String>),
) -> Option<String> {
    let mut size = 1024;
    loop {
        let mut buffer = vec![0; size];
        let mut found = std::ptr::null_mut();
        match look_up(&mut buffer, &mut found) {
            (libc::ERANGE, _) if size < 1 << 20 => size *= 2,
            (0, name) => return name,
            _ => return None,
        }
    }
}

/// The C string at `s`, if it isn't null.
///
/// # Safety
///
/// `s` is null or a C string that lives through the call.
#[cfg(unix)]
unsafe fn c_string(s: *const libc::c_char) -> String {
    match s.is_null() {
        true => String::new(),
        // SAFETY: as the caller says.
        false => unsafe { std::ffi::CStr::from_ptr(s) }
            .to_string_lossy()
            .into_owned(),
    }
}

/// The flags macOS keeps of a file, as `chflags` sets them, named as
/// Finder and `ls -lO` tell them, and colored: those that keep it from
/// changing, and those that say little.
#[cfg(target_os = "macos")]
fn flag_names(flags: u32) -> Vec<(&'static str, Kind)> {
    use Kind::{Flag, Locked, Muted};
    const NAMES: [(u32, &str, Kind); 13] = [
        (0x8000, "hidden", Muted),               // UF_HIDDEN, hidden in Finder
        (0x2, "locked", Locked),                 // UF_IMMUTABLE (uchg), Finder's Locked
        (0x4, "append-only", Locked),            // UF_APPEND
        (0x20, "compressed", Flag),              // UF_COMPRESSED
        (0x1, "no dump", Muted),                 // UF_NODUMP
        (0x8, "opaque", Muted),                  // UF_OPAQUE
        (0x80, "data vault", Locked),            // UF_DATAVAULT
        (0x10000, "archived", Muted),            // SF_ARCHIVED
        (0x20000, "system locked", Locked),      // SF_IMMUTABLE (schg)
        (0x40000, "system append-only", Locked), // SF_APPEND
        (0x80000, "restricted", Locked),         // SF_RESTRICTED, System Integrity Protection's
        (0x100000, "can't be deleted", Locked),  // SF_NOUNLINK
        (0x40000000, "not downloaded", Flag),    // SF_DATALESS, in iCloud only
    ];
    (NAMES.into_iter())
        .filter(|&(flag, ..)| flags & flag != 0)
        .map(|(_, name, kind)| (name, kind))
        .collect()
}

/// The attributes Windows keeps of a file (`FILE_ATTRIBUTE_*`), as
/// Explorer's Properties and `attrib` tell them, and colored as macOS's
/// flags are.
#[cfg(windows)]
fn attribute_names(attributes: u32) -> Vec<(&'static str, Kind)> {
    use Kind::{Flag, Locked, Muted};
    const NAMES: [(u32, &str, Kind); 12] = [
        (0x1, "read-only", Locked),
        (0x2, "hidden", Muted),
        (0x4, "system", Locked),
        (0x20, "archive", Muted),
        (0x100, "temporary", Flag),
        (0x200, "sparse", Flag),
        (0x400, "reparse point", Flag),
        (0x800, "compressed", Flag),
        (0x1000, "offline", Flag),
        (0x2000, "not indexed", Muted),
        (0x4000, "encrypted", Flag),
        (0x80000, "always on this device", Flag), // FILE_ATTRIBUTE_PINNED
    ];
    let mut names: Vec<_> = (NAMES.into_iter())
        .filter(|&(attribute, ..)| attributes & attribute != 0)
        .map(|(_, name, kind)| (name, kind))
        .collect();
    // FILE_ATTRIBUTE_UNPINNED or RECALL_ON_DATA_ACCESS: OneDrive's "online
    // only".
    if attributes & (0x100000 | 0x400000) != 0 {
        names.push(("online only", Flag));
    }
    names
}
