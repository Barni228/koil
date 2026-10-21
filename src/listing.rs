//! Koil's listing, as the editor shows it: a line per entry: its icon, which
//! hides its ID (the editor's hidden text), two spaces, and its name, with a
//! `/` after a dir's. A new entry has no ID, so the user writes just its name.
//! The open dir (or pattern) is in the path field above it, which is read
//! with it.
//!
//! Positions in the text are in UTF-16 code units, as QML counts them.

use std::cmp::Ordering;
use std::collections::{BTreeMap, HashMap};
use std::error::Error;
use std::path::{Component, Path, PathBuf};
use std::time::SystemTime;

use devicons::Theme;
use koil_core::apply::{Blocked, Undo};
use koil_core::{
    Action, Applied, Conflict, ConflictKind, Edit, Entry, EntryErrorKind, EntryWarning, Id, Koil,
    KoilError, Location, Metadata, OpenError, Pattern, Settings, Sort, SortBy, UpdateError,
    UpdateOpenError, Warning, with_slashes,
};
use serde::{Deserialize, Serialize};

use crate::link;
use crate::sizes::{DirSize, Measure, SizeOf};

/// The icon of a file devicons has none for (its own is `*`, a glob character).
const FILE_ICON: char = '\u{f016}';
/// The color devicons gives its default icons.
const FILE_COLOR: &str = "#7e8ea8";
/// The color of a pending entry's icon (see [`pending_lines`]), in a dark
/// and in a light theme, which no other icon comes near (see [`apart`]).
const PENDING_COLOR: [&str; 2] = ["#ffffff", "#000000"];
/// How far every other icon stays from a pending entry's color, in some
/// channel.
const APART: u8 = 0x33;

/// An icon in the text that hides some text: an entry's ID.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Hidden {
    /// Where the icon starts.
    pub at: usize,
    pub icon: String,
    pub text: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Severity {
    Warning,
    Error,
}

/// A warning or an error about a line of the listing.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Problem {
    /// Counted from 0.
    pub line: usize,
    /// Where the line's name starts (after its icon), so that's what gets
    /// underlined.
    pub column: usize,
    pub severity: Severity,
    pub message: String,
}

/// A listing as the editor shows it.
#[derive(Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Rendered {
    /// What's open, for the path field.
    pub path: String,
    pub text: String,
    /// The IDs, behind the icons.
    pub hidden: Vec<Hidden>,
    /// The name on each line, with a `/` after a dir's.
    pub names: Vec<String>,
    /// The color of each icon, in a dark and in a light theme.
    pub colors: HashMap<String, [String; 2]>,
    /// The color of a pending entry's icon (see `PENDING_COLOR`).
    pub pending_color: [&'static str; 2],
    #[serde(flatten)]
    pub notes: Notes,
}

/// The listing of what `koil` has open, with the sizes of its dirs counted
/// so far (see [`listing`]).
pub fn render(koil: &Koil, sizes: &dyn SizeOf) -> Rendered {
    let entries = listing(koil, sizes);
    let mut rendered = Rendered {
        path: show_location(koil),
        pending_color: PENDING_COLOR,
        notes: notes(koil, sizes, entries.iter().filter_map(|e| e.id)),
        ..Rendered::default()
    };
    // The text's length, kept rather than counted for each line.
    let mut length = 0;
    for entry in &entries {
        if !rendered.names.is_empty() {
            rendered.text.push('\n');
            length += 1;
        }
        let line = entry_line(koil, entry, &mut rendered.colors);
        rendered
            .hidden
            .extend(line.hidden.map(|h| Hidden { at: length, ..h }));
        rendered.text.push_str(&line.text);
        length += utf16_len(&line.text);
        rendered.names.push(entry_name(entry));
    }
    rendered
}

/// What dirs' sizes count when the listing is sorted by `by` (see
/// sizes.rs), None if it isn't sorted by a size.
pub fn measure(by: SortBy) -> Option<Measure> {
    match by {
        SortBy::Size => Some(Measure::Size),
        SortBy::Disk => Some(Measure::Disk),
        _ => None,
    }
}

/// `Koil::listing`, but sorted by size (or size on disk), its dirs go by
/// their sizes as far as they're counted (see [`compare`]).
fn listing(koil: &Koil, sizes: &dyn SizeOf) -> Vec<Entry> {
    let mut entries = koil.listing();
    let sort = koil.settings().sort;
    if let Some(measure) = measure(sort.by) {
        // Koil lists them together, and its order stays for the ones that
        // compare equal. Each size is looked up once, not at each comparison.
        let start = entries.iter().position(|e| together(sort, e)).unwrap_or(0);
        let together = entries[start..].iter().take_while(|e| together(sort, e));
        let end = start + together.count();
        let mut sized: Vec<(Option<u64>, Entry)> = (entries.drain(start..end))
            .map(|e| (size(koil, sizes, measure, &e), e))
            .collect();
        sized.sort_by(|(a, _), (b, _)| by_size(sort, *a, *b));
        entries.splice(start..start, sized.into_iter().map(|(_, e)| e));
    }
    entries
}

/// Where `render` lists `a` against `b`: as `Koil::compare` does, but
/// sorted by a size, dirs go by their sizes as far as they're counted (see
/// [`by_size`]).
fn compare(koil: &Koil, sizes: &dyn SizeOf, a: &Entry, b: &Entry) -> Ordering {
    let sort = koil.settings().sort;
    let by_size = match measure(sort.by) {
        Some(measure) if together(sort, a) && together(sort, b) => {
            let size = |entry| size(koil, sizes, measure, entry);
            by_size(sort, size(a), size(b))
        }
        _ => Ordering::Equal,
    };
    by_size.then_with(|| koil.compare(a, b))
}

/// Whether Koil lists `entry` with the ones sorted by a size here: its
/// dirs with IDs, and its files with IDs too unless dirs go first (then
/// Koil puts the dirs after the files, as it doesn't know their sizes).
fn together(sort: Sort, entry: &Entry) -> bool {
    entry.id.is_some() && (entry.is_dir || !sort.dirs_first)
}

/// What `entry` (with an ID) is sorted by when the listing is sorted by
/// `measure`: a file's own size, or a dir's as far as it's counted (see
/// sizes.rs), None until then.
fn size(koil: &Koil, sizes: &dyn SizeOf, measure: Measure, entry: &Entry) -> Option<u64> {
    if entry.is_dir {
        return match sizes.size_of(koil.path_of(entry.id?)?) {
            // Counted again, it stays where it was until it's done.
            Some(DirSize::Counted(bytes) | DirSize::Stale(bytes)) => Some(bytes),
            _ => None,
        };
    }
    let meta = koil.metadata(entry.id?)?;
    match measure {
        Measure::Size => Some(meta.size),
        Measure::Disk => meta.disk_size,
    }
}

/// Where an entry of size `a` goes against one of size `b` (see [`size`])
/// when the listing is sorted by size or size on disk: the biggest first,
/// and the dirs not counted after them (the other way round with
/// `reverse`, as Koil sorts what it can't read). Equal where Koil's own
/// order (how many entries a dir has) decides.
fn by_size(sort: Sort, a: Option<u64>, b: Option<u64>) -> Ordering {
    let order = b.cmp(&a);
    match sort.reverse {
        true => order.reverse(),
        false => order,
    }
}

/// A line of the listing, and the ID its icon hides (at its start).
struct Line {
    text: String,
    hidden: Option<Hidden>,
}

/// The line of `entry` in the listing of what `koil` has open, with its
/// icon's colors added to `colors`.
fn entry_line(koil: &Koil, entry: &Entry, colors: &mut HashMap<String, [String; 2]>) -> Line {
    let name = entry_name(entry);
    let (icon, icon_colors) = icon(koil.current_dir(), &name);
    colors.entry(icon.to_string()).or_insert(icon_colors);
    Line {
        text: format!("{icon}  {name}"),
        hidden: entry.id.map(|id| Hidden {
            at: 0,
            icon: icon.to_string(),
            text: id.0.to_string(),
        }),
    }
}

/// An entry's name as the listing shows it, with a `/` after a dir's.
fn entry_name(entry: &Entry) -> String {
    slashed(entry.name.to_string_lossy(), entry.is_dir)
}

/// `name`, with a `/` after it if it's a dir's.
fn slashed(name: impl std::fmt::Display, is_dir: bool) -> String {
    format!("{name}{}", if is_dir { "/" } else { "" })
}

/// The icon of the entry `name` in `dir`, and its color in a dark and in a
/// light theme.
fn icon(dir: &Path, name: &str) -> (char, [String; 2]) {
    // A dir's name ends with `/`, which tells devicons it's a dir without
    // asking the filesystem.
    let path = dir.join(name);
    let dark = devicons::icon_for_file(&path, &Some(Theme::Dark));
    let light = devicons::icon_for_file(&path, &Some(Theme::Light));
    if dark.icon == '*' {
        return (FILE_ICON, [FILE_COLOR.into(), FILE_COLOR.into()]);
    }
    (
        dark.icon,
        [apart(dark.color, true), apart(light.color, false)],
    )
}

/// `color` (like `#rrggbb`, for a dark theme if `dark`), unless it's within
/// `APART` of a pending entry's icon color (see `PENDING_COLOR`) in every
/// channel, like devicons' white icons: then a fifth of the way from it,
/// darker in a dark theme and lighter in a light one.
fn apart(color: &str, dark: bool) -> String {
    let channel = |i: usize| u8::from_str_radix(color.get(1 + 2 * i..3 + 2 * i)?, 16).ok();
    let Some(channels) = [channel(0), channel(1), channel(2)]
        .into_iter()
        .collect::<Option<Vec<u8>>>()
    else {
        return color.to_string();
    };
    let near = match dark {
        true => channels.iter().all(|&c| c > u8::MAX - APART),
        false => channels.iter().all(|&c| c < APART),
    };
    if !near {
        return color.to_string();
    }
    let moved = channels.iter().map(|&c| match dark {
        true => c - c / 5,
        false => c + (u8::MAX - c) / 5,
    });
    format!("#{}", moved.map(|c| format!("{c:02x}")).collect::<String>())
}

/// What a dir's size ends with while it's being counted, whose dots the
/// editor animates.
const COUNTING: &str = "...";

/// What the editor shows after the listing's lines: what it's sorted by
/// (see [`notes`]).
#[derive(Debug, Default, Serialize)]
pub struct Notes {
    /// By the ID as its icon hides it.
    pub infos: HashMap<String, String>,
    /// The IDs whose infos are the sizes of dirs still being counted, which
    /// end with `COUNTING`.
    pub busy: Vec<String>,
    /// The IDs whose infos are dirs' sizes, and their dirs: what to count
    /// (see sizes.rs).
    #[serde(skip)]
    pub dirs: Vec<(Id, PathBuf)>,
}

/// The dirs whose sizes the listing of what `koil` has open shows (see
/// [`notes`]), to count before it's rendered: none unless it's sorted by
/// size or size on disk.
pub fn size_dirs(koil: &Koil) -> Vec<PathBuf> {
    if measure(koil.settings().sort.by).is_none() {
        return Vec::new();
    }
    let ids = koil.listing().into_iter().filter_map(|e| e.id);
    let dirs = ids.filter(|&id| koil.metadata(id).is_some_and(|meta| meta.is_dir));
    dirs.filter_map(|id| Some(koil.path_of(id)?.to_path_buf()))
        .collect()
}

/// What the listing is sorted by, for each of `ids` (see `Koil::metadata`):
/// a file's size (or size on disk), a dir's as far as `sizes` has it, or
/// when it was modified, created or accessed. None when it's sorted by name.
pub fn notes(koil: &Koil, sizes: &dyn SizeOf, ids: impl IntoIterator<Item = Id>) -> Notes {
    let mut notes = Notes::default();
    let by = koil.settings().sort.by;
    if !by.reads_metadata() {
        return notes;
    }
    for id in ids {
        let key = id.0.to_string();
        if notes.infos.contains_key(&key) {
            continue;
        }
        let Some(meta) = koil.metadata(id) else {
            continue;
        };
        let dir = (measure(by).is_some() && meta.is_dir)
            .then(|| koil.path_of(id))
            .flatten();
        let info = match dir {
            Some(dir) => {
                notes.dirs.push((id, dir.to_path_buf()));
                let size = sizes.size_of(dir);
                if !matches!(size, Some(DirSize::Counted(_) | DirSize::Unreadable)) {
                    notes.busy.push(key.clone());
                }
                dir_info(size)
            }
            None => info(by, &meta),
        };
        if let Some(info) = info {
            notes.infos.insert(key, info);
        }
    }
    notes
}

/// What the listing is sorted by, for an entry with `meta` on disk: a
/// file's size or size on disk, or when it was modified, created or
/// accessed. None if it isn't known, and for a dir's size (see
/// [`dir_info`]).
fn info(by: SortBy, meta: &Metadata) -> Option<String> {
    match by {
        SortBy::Size | SortBy::Disk if meta.is_dir => None,
        SortBy::Size => Some(show_size(meta.size)),
        SortBy::Disk => meta.disk_size.map(show_size),
        SortBy::Modified => meta.modified.map(show_time),
        SortBy::Created => meta.created.map(show_time),
        SortBy::Accessed => meta.accessed.map(show_time),
        SortBy::Name | SortBy::Natural | SortBy::Extension => None,
    }
}

/// A dir's size, as far as it's counted (`size`, None before it starts),
/// with `COUNTING` after it until it is (or what it was, while it's counted
/// again). None if it can't be read.
fn dir_info(size: Option<DirSize>) -> Option<String> {
    match size {
        Some(DirSize::Counted(bytes)) => Some(show_size(bytes)),
        Some(DirSize::Counting(bytes @ 1..) | DirSize::Stale(bytes)) => {
            Some(format!("{}{COUNTING}", show_size(bytes)))
        }
        Some(DirSize::Counting(_)) | None => Some(COUNTING.to_string()),
        Some(DirSize::Unreadable) => None,
    }
}

/// `bytes` as people read a size, with a KB of 1000 bytes, as macOS counts:
/// `340 B`, `1.2 KB`, `56 MB`.
fn show_size(bytes: u64) -> String {
    if bytes < 1000 {
        return format!("{bytes} B");
    }
    let mut size = bytes as f64;
    let mut shown = String::new();
    for unit in ["KB", "MB", "GB", "TB", "PB", "EB"] {
        size /= 1000.0;
        // A decimal below 10 (1.2 KB, but 12 KB), and 999,999 bytes are
        // 1.0 MB, not 1000 KB.
        let number = match size < 9.95 {
            true => format!("{size:.1}"),
            false => format!("{size:.0}"),
        };
        shown = format!("{number} {unit}");
        if size < 999.5 {
            break;
        }
    }
    shown
}

/// `time` in the local time zone, like `2026-10-06 14:03`.
fn show_time(time: SystemTime) -> String {
    let time = chrono::DateTime::<chrono::Local>::from(time);
    time.format("%Y-%m-%d %H:%M").to_string()
}

/// A listing as the user edited it.
#[derive(Debug, Default)]
pub struct Parsed {
    pub entries: Vec<Entry>,
    /// Where each entry is: its line, and where its name starts on it.
    pub spots: Vec<(usize, usize)>,
    /// Lines that can't be read: an icon that hides something other than an
    /// ID.
    pub problems: Vec<Problem>,
}

impl Parsed {
    fn problem(&mut self, line: usize, column: usize, message: impl Into<String>) {
        self.problems.push(Problem {
            line,
            column,
            severity: Severity::Error,
            message: message.into(),
        });
    }
}

/// Reads the listing back from its text and hidden texts. A line is an
/// existing entry if its first character is an icon that hides an ID, and a
/// new one otherwise (an icon without an ID, as `render` gives a new entry,
/// isn't part of the name). Blank lines are left out, and names are trimmed.
pub fn parse(text: &str, hidden: &[Hidden]) -> Parsed {
    let hidden: HashMap<usize, &Hidden> = hidden.iter().map(|h| (h.at, h)).collect();
    let mut parsed = Parsed::default();
    // Where the next line starts.
    let mut next = 0;
    for (i, line) in text.split('\n').enumerate() {
        let start = next;
        next += utf16_len(line) + 1;
        if line.trim().is_empty() {
            continue;
        }
        let (icon, rest) = line_icon(&hidden, line, start);
        let (id, rest) = match icon {
            Some(h) => match h.text.parse() {
                Ok(id) => (Some(Id(id)), &rest[h.icon.len()..]),
                Err(_) => {
                    parsed.problem(
                        i,
                        0,
                        format!("The icon hides `{}`, which isn't an ID", h.text),
                    );
                    continue;
                }
            },
            _ => (None, rest.strip_prefix(is_private_use).unwrap_or(rest)),
        };
        let name = rest.trim();
        let column = utf16_len(&line[..line.len() - rest.trim_start().len()]);
        let (name, is_dir) = match name.strip_suffix('/') {
            Some(dir) => (dir.trim_end_matches('/'), true),
            None => (name, false),
        };
        parsed.entries.push(Entry {
            id,
            name: name.into(),
            is_dir,
        });
        parsed.spots.push((i, column));
    }
    parsed
}

/// [`parse`], with each entry as `koil` reads it back (`Koil::read_shown`):
/// a name that isn't Unicode (only on Linux, or a malformed one on Windows)
/// is shown with `�`, which would otherwise read as a rename to that.
fn read(koil: &Koil, text: &str, hidden: &[Hidden]) -> Parsed {
    let mut parsed = parse(text, hidden);
    let entries = std::mem::take(&mut parsed.entries);
    parsed.entries = (entries.into_iter())
        .map(|entry| koil.read_shown(entry))
        .collect();
    parsed
}

/// The icon hiding something that `line` (which starts at `start`) starts
/// with, after its indent, if any, and the line after its indent.
fn line_icon<'a, 'l>(
    hidden: &HashMap<usize, &'a Hidden>,
    line: &'l str,
    start: usize,
) -> (Option<&'a Hidden>, &'l str) {
    let rest = &line[indent(line).len()..];
    let icon = hidden.get(&(start + utf16_len(indent(line))));
    (icon.filter(|h| rest.starts_with(&h.icon)).copied(), rest)
}

/// The spaces at the start of `line`.
fn indent(line: &str) -> &str {
    &line[..line.len() - line.trim_start().len()]
}

/// Whether `c` is in a Private Use Area, where Nerd Fonts put their icons.
fn is_private_use(c: char) -> bool {
    matches!(c, '\u{e000}'..='\u{f8ff}' | '\u{f0000}'..='\u{ffffd}' | '\u{100000}'..='\u{10fffd}')
}

fn utf16_len(s: &str) -> usize {
    s.chars().map(char::len_utf16).sum()
}

/// The warnings and errors in the edited listing (see `Koil::check`), sorted
/// by line.
pub fn check(koil: &Koil, text: &str, hidden: &[Hidden]) -> Vec<Problem> {
    let parsed = read(koil, text, hidden);
    let mut problems = parsed.problems.clone();
    match koil.check(&parsed.entries) {
        Ok(warnings) => problems.extend(warning_problems(&parsed, &warnings)),
        Err(error) => problems.extend(update_problems(&parsed, &error)),
    }
    problems.sort_by_key(|p| p.line);
    problems
}

fn update_problems(parsed: &Parsed, error: &UpdateError) -> Vec<Problem> {
    let errors = error.errors.iter().map(|e| {
        let message = match &e.kind {
            EntryErrorKind::Duplicate { path, first } => format!(
                "`{}` appears more than once, first on line {}",
                path.display(),
                parsed.spots[*first].0 + 1
            ),
            kind => kind.to_string(),
        };
        problem(parsed, e.entry, Severity::Error, message)
    });
    errors
        .chain(warning_problems(parsed, &error.warnings))
        .collect()
}

fn warning_problems(parsed: &Parsed, warnings: &[EntryWarning]) -> Vec<Problem> {
    let problems = warnings
        .iter()
        .map(|w| problem(parsed, w.entry, Severity::Warning, w.kind.to_string()));
    problems.collect()
}

fn problem(parsed: &Parsed, entry: usize, severity: Severity, message: String) -> Problem {
    let (line, column) = parsed.spots[entry];
    Problem {
        line,
        column,
        severity,
        message,
    }
}

/// The lines (from 0) of entries that aren't on disk as the listing shows
/// them yet, which applying would change (`Koil::is_pending`): new ones, and
/// ones whose path isn't their ID's (renamed, copied, or moved here from
/// another dir). Their icons get `PENDING_COLOR`.
pub fn pending_lines(koil: &Koil, text: &str, hidden: &[Hidden]) -> Vec<usize> {
    let parsed = read(koil, text, hidden);
    let entries = parsed.entries.iter().zip(&parsed.spots);
    entries
        .filter(|(entry, _)| koil.is_pending(entry))
        .map(|(_, &(line, _))| line)
        .collect()
}

/// What [`update`] did.
#[derive(Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Updated {
    /// False if the listing wasn't read, or the location to open couldn't be
    /// opened: the problems and `message` say why. Koil is then as it was.
    pub ok: bool,
    /// The listing's.
    pub problems: Vec<Problem>,
    /// The path field's: there's no path, or it can't be opened.
    pub path_problems: Vec<Problem>,
    /// Whether a different dir (or pattern) is open now, or the settings
    /// changed which entries are shown.
    pub moved: bool,
    /// If the dir open now is above the one that was, the entry that leads
    /// back to it, like `dir/`, so the cursor can go there.
    pub from: String,
    /// Something to tell the user, like an error or a dir that wasn't found.
    pub message: String,
}

/// Reads the edited listing into `koil`, then uses `settings`, and then opens
/// `open` (a dir, relative to the open one) if given, else `path` (the path
/// field, as written) if it changed, or if the pattern open must be read
/// again with `settings` (see [`rereads`]), all in `Koil::update_and_open`,
/// which reads the entries with the settings they were listed with. If
/// anything fails, `koil` is left as it was.
pub fn update(
    koil: &mut Koil,
    path: &str,
    text: &str,
    hidden: &[Hidden],
    settings: &Settings,
    open: Option<&str>,
) -> Updated {
    let parsed = read(koil, text, hidden);
    let failed = |problems: Vec<Problem>, path_problems: Vec<Problem>, message: String| Updated {
        problems,
        path_problems,
        message,
        ..Updated::default()
    };
    if let Some(p) = parsed.problems.first() {
        return failed(parsed.problems.clone(), Vec::new(), p.message.clone());
    }
    let location = path.trim();
    if location.is_empty() {
        let message = "Write the path to open".to_string();
        return failed(Vec::new(), vec![path_problem(path, &message)], message);
    }
    let before_dir = koil.current_dir().to_path_buf();
    let changed = location != show_location(koil) || rereads(koil, settings);
    let target = open.or(changed.then_some(location));
    let entries = &parsed.entries;
    let updated = match koil.update_and_open(entries, settings.clone(), target.map(Path::new)) {
        Ok(updated) => updated,
        Err(UpdateOpenError::Update(error)) => {
            let problems = update_problems(&parsed, &error);
            let count = error.errors.len();
            let message = match count {
                1 => problems[0].message.clone(),
                _ => format!("{count} errors in the listing"),
            };
            return failed(problems, Vec::new(), message);
        }
        Err(UpdateOpenError::Open(error)) => {
            let message = describe_open(&error);
            // The path field's, unless the dir was Enter's or `-`'s.
            let path_problems = match (open, target) {
                (None, Some(_)) => vec![path_problem(path, &message)],
                _ => Vec::new(),
            };
            return failed(Vec::new(), path_problems, message);
        }
    };
    let from = before_dir.strip_prefix(koil.current_dir()).ok();
    let from = from.and_then(|rest| rest.components().next());
    Updated {
        ok: true,
        problems: warning_problems(&parsed, &updated.warnings),
        moved: updated.moved,
        from: from
            .map(|dir| format!("{}/", dir.as_os_str().to_string_lossy()))
            .unwrap_or_default(),
        message: (updated.warning.as_ref())
            .map(describe_warning)
            .unwrap_or_default(),
        ..Updated::default()
    }
}

/// Whether the pattern `koil` has open must be read again for `settings`:
/// it's a glob and they read patterns as regexes, or the other way round.
/// Koil keeps a pattern as it was read when only the settings change, so
/// `:set regex` would leave the field's pattern read as it wasn't anymore.
pub fn rereads(koil: &Koil, settings: &Settings) -> bool {
    (koil.pattern()).is_some_and(|p| matches!(p, Pattern::Regex(_)) != settings.regex)
}

/// An error about the path field (`path`, as written), underlined from
/// where the path starts.
fn path_problem(path: &str, message: &str) -> Problem {
    Problem {
        line: 0,
        column: utf16_len(indent(path)),
        severity: Severity::Error,
        message: message.to_string(),
    }
}

/// A change to the listing's text: `text` replaces [`start`, `end`), and
/// its icons hide `hidden` (whose `at` count from `start`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct TextEdit {
    pub start: usize,
    pub end: usize,
    pub text: String,
    pub hidden: Vec<Hidden>,
}

/// Edits to the listing's text, in order and apart, and the colors of the
/// icons they add.
#[derive(Debug, Default, Serialize)]
pub struct Merge {
    pub edits: Vec<TextEdit>,
    pub colors: HashMap<String, [String; 2]>,
}

/// What [`sync`] found changed on disk.
#[derive(Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Synced {
    /// How the listing changes to show it, with the user's edits kept.
    #[serde(flatten)]
    pub merge: Merge,
    /// What changed against the user's edits, to ask about one at a time.
    pub questions: Vec<Question>,
    /// Whether the listing must be shown as a new one, as something else is
    /// open now (the open dir is gone): `edits` are of no use then.
    pub moved: bool,
    /// What's open, for the path field: the open dir may have been renamed.
    pub path: String,
    /// Why something else is open, or why it couldn't be read.
    pub message: String,
    /// Whether `message` is an error: nothing changed.
    pub failed: bool,
    /// What's shown after the lines, as it is on disk now.
    #[serde(flatten)]
    pub notes: Notes,
}

/// A question about the conflicts of one kind, which Yes resolves (see
/// `Koil::resolve`) and No leaves as they are.
#[derive(Debug, Serialize)]
pub struct Question {
    pub text: String,
    pub details: String,
    pub conflicts: Vec<Conflict>,
}

/// Reads what `koil` has open from disk again (see `Koil::sync`), and
/// returns how the listing `text` (with `hidden`), as the user has it now,
/// changes to show what changed there, and what to ask about. `sizes` are
/// its dirs' as far as they're counted.
pub fn sync(koil: &mut Koil, sizes: &dyn SizeOf, text: &str, hidden: &[Hidden]) -> Synced {
    let parsed = read(koil, text, hidden);
    let synced = match koil.sync(&parsed.entries) {
        Ok(synced) => synced,
        Err(error) => {
            let dir = show_path(koil.current_dir());
            return Synced {
                path: show_location(koil),
                message: format!("Can't read `{dir}`: {}", describe(&error)),
                failed: true,
                ..Synced::default()
            };
        }
    };
    let added = synced.edits.iter().filter_map(|edit| match edit {
        Edit::Add(entry) | Edit::Change { to: entry, .. } => Some(entry),
        Edit::Remove(_) => None,
    });
    let ids = parsed.entries.iter().chain(added).filter_map(|e| e.id);
    Synced {
        notes: notes(koil, sizes, ids),
        merge: match synced.moved {
            true => Merge::default(),
            false => merge(koil, sizes, text, &parsed, &synced.edits),
        },
        questions: questions(koil, &synced.conflicts),
        moved: synced.moved,
        path: show_location(koil),
        message: (synced.warning.as_ref())
            .map(describe_warning)
            .unwrap_or_default(),
        failed: false,
    }
}

/// Takes the other way in `conflicts` (a [`Question`]'s, which the user
/// said yes to), and returns how the listing `text` (with `hidden`) changes
/// for it.
pub fn resolve(
    koil: &mut Koil,
    sizes: &dyn SizeOf,
    text: &str,
    hidden: &[Hidden],
    conflicts: &[Conflict],
) -> Merge {
    let edits: Vec<Edit> = conflicts.iter().flat_map(|c| koil.resolve(c)).collect();
    merge(koil, sizes, text, &read(koil, text, hidden), &edits)
}

/// `edits` to the entries of the listing `text` (read as `parsed`) as
/// edits to the text: a line changes or goes for the entry on it, and a new
/// one goes among the others where `render` would put it (with `sizes`).
fn merge(koil: &Koil, sizes: &dyn SizeOf, text: &str, parsed: &Parsed, edits: &[Edit]) -> Merge {
    let lines: Vec<&str> = text.split('\n').collect();
    let mut colors = HashMap::new();
    // The lines of each ID's entries (new entries under none), as a listing
    // can have thousands.
    let mut by_id: HashMap<Option<Id>, Vec<(usize, &Entry)>> = HashMap::new();
    for (&(line, _), entry) in parsed.spots.iter().zip(&parsed.entries) {
        by_id.entry(entry.id).or_default().push((line, entry));
    }
    let lines_of = |entry: &Entry| -> Vec<usize> {
        let like =
            |e: &&Entry| e.name == entry.name && (e.id.is_some() || e.is_dir == entry.is_dir);
        let of = by_id.get(&entry.id).into_iter().flatten();
        of.filter(|(_, e)| like(e)).map(|&(line, _)| line).collect()
    };
    let existing: Vec<(&Entry, usize)> = (parsed.entries.iter().zip(&parsed.spots))
        .filter(|(e, _)| e.id.is_some())
        .map(|(e, &(line, _))| (e, line))
        .collect();
    let sorted = existing
        .windows(2)
        .all(|w| compare(koil, sizes, w[0].0, w[1].0).is_le());
    // What each changed line becomes (nothing, if it goes), and the lines
    // that go before each line (or at the end, after the last).
    let mut replaced: BTreeMap<usize, Option<Line>> = BTreeMap::new();
    let mut inserted: BTreeMap<usize, Vec<(Entry, Line)>> = BTreeMap::new();
    for edit in edits {
        match edit {
            Edit::Remove(entry) => {
                for line in lines_of(entry) {
                    replaced.insert(line, None);
                }
            }
            Edit::Change { from, to } => {
                for line in lines_of(from) {
                    replaced.insert(line, Some(entry_line(koil, to, &mut colors)));
                }
            }
            Edit::Add(entry) => {
                let line = entry_line(koil, entry, &mut colors);
                let at = insert_at(koil, sizes, parsed, &existing, sorted, entry, lines.len());
                inserted.entry(at).or_default().push((entry.clone(), line));
            }
        }
    }

    let mut starts = Vec::with_capacity(lines.len() + 1);
    let (mut at, mut byte) = (0, 0);
    for line in &lines {
        starts.push((at, byte));
        at += utf16_len(line) + 1;
        byte += line.len() + 1;
    }
    // The end of the text, where a line break after the last line would
    // end.
    starts.push((at, byte));
    let n = lines.len();
    let mut merged = Merge {
        colors,
        ..Merge::default()
    };
    let mut i = 0;
    while i <= n {
        if !inserted.contains_key(&i) && !replaced.contains_key(&i) {
            i += 1;
            continue;
        }
        // The lines from `first` up to `i` are replaced by `new`.
        let first = i;
        let mut new = Vec::new();
        loop {
            if let Some(mut lines) = inserted.remove(&i) {
                lines.sort_by(|(a, _), (b, _)| compare(koil, sizes, a, b));
                new.extend(lines.into_iter().map(|(_, line)| line));
            }
            match replaced.remove(&i) {
                Some(line) => {
                    new.extend(line);
                    i += 1;
                }
                None => break,
            }
        }
        merged.edits.push(region(text, &starts, first, i, new));
    }
    merged
}

/// The line a new line for `entry` goes before (`lines`, the number of
/// lines, for after the last one): one with an ID before the first of the
/// `existing` entries (those with IDs, and their lines; `sorted` if they're
/// in `render`'s order, as they usually are) that `render` lists after it
/// ([`compare`]), or after the last of them; a new one (or one with an ID,
/// if no other has one) after the last entry.
fn insert_at(
    koil: &Koil,
    sizes: &dyn SizeOf,
    parsed: &Parsed,
    existing: &[(&Entry, usize)],
    sorted: bool,
    entry: &Entry,
    lines: usize,
) -> usize {
    if entry.id.is_some()
        && let Some(&(_, last)) = existing.last()
    {
        let after = |&(e, _): &(&Entry, usize)| compare(koil, sizes, e, entry).is_gt();
        let first = match sorted {
            true => Some(existing.partition_point(|e| !after(e))).filter(|&i| i < existing.len()),
            false => existing.iter().position(after),
        };
        return first.map_or(last + 1, |i| existing[i].1);
    }
    parsed.spots.last().map_or(lines, |&(line, _)| line + 1)
}

/// The edit that replaces the lines of `text` from `first` up to `last`
/// (the number of lines, for all the rest) with `new`, where `starts` has
/// where each line starts (and the text ends), in UTF-16 and in bytes.
fn region(
    text: &str,
    starts: &[(usize, usize)],
    first: usize,
    last: usize,
    new: Vec<Line>,
) -> TextEdit {
    let n = starts.len() - 1;
    let empty = new.is_empty();
    let mut joined = String::new();
    let mut hidden = Vec::new();
    // `joined`'s length, kept rather than counted for each line (thousands of files can
    // appear at once)
    let mut at = 0;
    for (k, line) in new.into_iter().enumerate() {
        if k > 0 {
            joined.push('\n');
            at += 1;
        }
        hidden.extend(line.hidden.map(|h| Hidden { at, ..h }));
        joined.push_str(&line.text);
        at += utf16_len(&line.text);
    }
    // The text's end, without the line break `starts` counts after it.
    let end = (starts[n].0 - 1, starts[n].1 - 1);
    let (start, stop, new_text) = if last < n {
        // Each line with its line break.
        let with_breaks = match empty {
            true => String::new(),
            false => joined + "\n",
        };
        (starts[first], starts[last], with_breaks)
    } else if first == n && text.is_empty() {
        ((0, 0), (0, 0), joined)
    } else if first == n {
        (end, end, format!("\n{joined}"))
    } else if !empty || first == 0 {
        (starts[first], end, joined)
    } else {
        // The last lines go, with the line break before them.
        let before = (starts[first].0 - 1, starts[first].1 - 1);
        (before, end, String::new())
    };
    let shift = utf16_len(&new_text) - utf16_len(new_text.trim_start_matches('\n'));
    let hidden = hidden.into_iter().map(|h| Hidden {
        at: h.at + shift,
        ..h
    });
    trim_breaks(
        TextEdit {
            start: start.0,
            end: stop.0,
            text: new_text,
            hidden: hidden.collect(),
        },
        &text[start.1..stop.1],
    )
}

/// `edit` (of `old`) without the line breaks it keeps at its start and end,
/// so it touches only the lines it changes.
fn trim_breaks(mut edit: TextEdit, mut old: &str) -> TextEdit {
    while let (Some(rest), Some(text)) = (old.strip_prefix('\n'), edit.text.strip_prefix('\n')) {
        old = rest;
        edit.text = text.to_string();
        edit.start += 1;
        for h in &mut edit.hidden {
            h.at -= 1;
        }
    }
    while let (Some(rest), Some(text)) = (old.strip_suffix('\n'), edit.text.strip_suffix('\n')) {
        old = rest;
        edit.text = text.to_string();
        edit.end -= 1;
    }
    edit
}

/// What to ask about `conflicts`: a question for each kind there is.
fn questions(koil: &Koil, conflicts: &[Conflict]) -> Vec<Question> {
    let kinds = [
        ConflictKind::Deleted,
        ConflictKind::Renamed,
        ConflictKind::Gone,
        ConflictKind::Taken,
    ];
    let questions = kinds.into_iter().filter_map(|kind| {
        let of: Vec<&Conflict> = conflicts.iter().filter(|c| c.kind == kind).collect();
        (!of.is_empty()).then(|| question(koil, kind, &of))
    });
    questions.collect()
}

/// The question about `conflicts`, all of `kind`: what happened, with
/// paths as the confirmations show them, and what Yes does.
fn question(koil: &Koil, kind: ConflictKind, conflicts: &[&Conflict]) -> Question {
    let path = |p: &Path, is_dir: bool| slashed(relative(koil, p), is_dir);
    let from = |c: &Conflict| path(&c.from, c.is_dir);
    let to = |c: &Conflict| {
        c.to.as_deref()
            .map(|p| path(p, c.is_dir))
            .unwrap_or_default()
    };
    // The paths the user put it at.
    let yours = |c: &Conflict| {
        let listed = c
            .listed
            .iter()
            .map(|e| path(&koil.current_dir().join(&e.name), c.is_dir));
        let elsewhere = c.elsewhere.iter().map(|p| path(p, c.is_dir));
        listed.chain(elsewhere).collect::<Vec<_>>()
    };
    let quoted = |paths: &[String]| {
        let quoted: Vec<String> = paths.iter().map(|p| format!("`{p}`")).collect();
        quoted.join(", ")
    };
    // Renamed in the dir it was in, or moved to another.
    let moved = |c: &Conflict| match c.to.as_deref().and_then(Path::parent) == c.from.parent() {
        true => "renamed",
        false => "moved",
    };
    // What the user did, to put it at `yours`.
    let renamed = |yours: &[String]| match yours.len() {
        1 => "renamed",
        _ => "renamed or copied",
    };
    let one = conflicts.len() == 1;
    let c = conflicts[0];
    let (text, details) = match kind {
        ConflictKind::Deleted if one => (
            format!(
                "`{}` was {} to `{}` on disk, but you deleted it. Delete it anyway?",
                from(c),
                moved(c),
                to(c)
            ),
            Vec::new(),
        ),
        ConflictKind::Deleted => (
            "These were renamed or moved on disk, but you deleted them. Delete them anyway?"
                .to_string(),
            conflicts
                .iter()
                .map(|c| format!("{} -> {}", from(c), to(c)))
                .collect(),
        ),
        ConflictKind::Renamed if one => (
            format!(
                "`{}` was {} to `{}` on disk, but you {} it to {}. Keep `{}` instead?",
                from(c),
                moved(c),
                to(c),
                renamed(&yours(c)),
                quoted(&yours(c)),
                to(c)
            ),
            Vec::new(),
        ),
        ConflictKind::Renamed => (
            "These were renamed or moved on disk, but you renamed them too. Keep the names \
             they have on disk instead?"
                .to_string(),
            (conflicts.iter())
                .map(|c| format!("{} -> {} (yours: {})", from(c), to(c), yours(c).join(", ")))
                .collect(),
        ),
        ConflictKind::Gone if one => {
            let yours = yours(c);
            let what = if c.is_dir { "dir" } else { "file" };
            let (them, what) = match yours.len() {
                1 => ("it", format!("a new, empty {what}")),
                _ => ("them", format!("new, empty {what}s")),
            };
            (
                format!(
                    "`{}` is no longer on disk, but you {} it to {}. Create {them} as {what} \
                     instead?",
                    from(c),
                    renamed(&yours),
                    quoted(&yours),
                ),
                Vec::new(),
            )
        }
        ConflictKind::Gone => (
            "These are no longer on disk, but you renamed or copied them. Create what you \
             wrote as new, empty files and dirs instead?"
                .to_string(),
            (conflicts.iter())
                .map(|c| format!("{} -> {}", from(c), yours(c).join(", ")))
                .collect(),
        ),
        ConflictKind::Taken => {
            // What the user put there: an entry renamed (or moved) there, or
            // a new one.
            let theirs = |c: &Conflict| {
                let entry = c.listed.first();
                match entry.and_then(|e| koil.path_of(e.id?)) {
                    Some(p) => format!("{} -> {}", path(p, p.is_dir()), to(c)),
                    None => format!("new {}", to(c)),
                }
            };
            match one {
                true => (
                    format!(
                        "`{}` appeared on disk, where you put `{}`. Replace it with yours? \
                         It goes to the trash when the changes are applied.",
                        to(c),
                        theirs(c)
                    ),
                    Vec::new(),
                ),
                false => (
                    "These appeared on disk where you put other entries. Replace them with \
                     yours? They go to the trash when the changes are applied."
                        .to_string(),
                    (conflicts.iter())
                        .map(|c| format!("{} (yours: {})", to(c), theirs(c)))
                        .collect(),
                ),
            }
        }
    };
    Question {
        text,
        details: details.join("\n"),
        conflicts: conflicts.iter().map(|&c| c.clone()).collect(),
    }
}

/// What Enter on a line of the listing opens (see [`target_on_line`]).
#[derive(Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Target {
    /// A dir, relative to the open one.
    Dir(String),
    /// A file on disk, and its name on the line.
    File { path: String, name: String },
    /// A new file, which isn't there until the changes are applied (or
    /// until it's created on its own, see [`create_steps`]): where it goes,
    /// and its name on the line.
    New { path: String, name: String },
    /// Why it can't be opened (see [`unicode`]).
    Error(String),
}

/// What Enter on `line` opens: the dir of an entry whose name ends with `/`,
/// or else the file the entry is on disk (where its ID points, even if the
/// line renames it). None on a line without an entry, or with an ID koil
/// doesn't know.
pub fn target_on_line(koil: &Koil, text: &str, hidden: &[Hidden], line: usize) -> Option<Target> {
    let parsed = read(koil, text, hidden);
    let i = parsed.spots.iter().position(|&(l, _)| l == line)?;
    let entry = &parsed.entries[i];
    let name = entry.name.to_string_lossy().into_owned();
    let target = match entry.id {
        _ if entry.is_dir => unicode(&entry.name).map(Target::Dir),
        None => {
            let path = koil.current_dir().join(&entry.name);
            unicode(&path).map(|path| Target::New { path, name })
        }
        Some(id) => match koil.path_of(id)? {
            // a dir with the `/` taken off its name
            path if path.is_dir() => unicode(&entry.name).map(Target::Dir),
            path => unicode(path).map(|path| Target::File { path, name }),
        },
    };
    Some(target.unwrap_or_else(Target::Error))
}

/// Where `-` goes (see [`up`]).
#[derive(Debug, Default, PartialEq, Eq, Serialize)]
pub struct Up {
    /// What [`update`] opens, relative to the open dir.
    pub open: String,
    /// The entry there to put the cursor on, if `update`'s `from` doesn't
    /// find it (it finds the dir it came from, not the pattern): the dir
    /// (or file) the entry on the cursor's line is in, else none.
    pub from: String,
}

/// Where `-` goes, `count` levels up from what `koil` has open, where a
/// pattern is a level of its own: `dir/*` goes to `dir` (on the dir or
/// file there that the entry on `line` is in), then to the dir it's in.
pub fn up(koil: &Koil, text: &str, hidden: &[Hidden], line: usize, count: usize) -> Up {
    let levels = count.max(1);
    let parents = |n: usize| vec![".."; n].join("/");
    if koil.pattern().is_none() {
        return Up {
            open: parents(levels),
            ..Up::default()
        };
    }
    if levels > 1 {
        return Up {
            open: parents(levels - 1),
            ..Up::default()
        };
    }
    let parsed = read(koil, text, hidden);
    let i = parsed.spots.iter().position(|&(l, _)| l == line);
    let from = i.and_then(|i| {
        let entry = &parsed.entries[i];
        let mut parts = entry.name.components();
        let Some(Component::Normal(first)) = parts.next() else {
            return None;
        };
        let slash = if entry.is_dir || parts.next().is_some() {
            "/"
        } else {
            ""
        };
        Some(format!("{}{slash}", first.to_string_lossy()))
    });
    Up {
        open: ".".to_string(),
        from: from.unwrap_or_default(),
    }
}

/// The file `:e` opens for `location`, if it's one on disk: read as the
/// path field reads a location (quotes, `\`, `~`, from the open dir: see
/// `Koil::read_location`), but as written first, as a dir is, so a name
/// like `a[1].txt` isn't a pattern. None for anything else, which is
/// listed (a dir or a pattern) or can't be opened, as the path field says.
pub fn file_at(koil: &Koil, location: &str) -> Option<PathBuf> {
    let location = location.trim();
    let written = koil
        .current_dir()
        .join(link::home_expanded(Path::new(location)));
    if written.is_file() {
        return Some(link::normalized(&written));
    }
    match koil.read_location(location, false) {
        Location {
            dir, pattern: None, ..
        } if dir.is_file() => Some(dir),
        _ => None,
    }
}

/// Where the entry on `line` is on disk, for Space r to show: where its ID
/// points, even if the line renames it (as Enter opens it); or else why
/// there's none (see [`on_disk`]), or no entry on the line (or one with an
/// ID koil doesn't know).
pub fn path_on_line(
    koil: &Koil,
    text: &str,
    hidden: &[Hidden],
    line: usize,
) -> Result<String, String> {
    let parsed = read(koil, text, hidden);
    let i = parsed.spots.iter().position(|&(l, _)| l == line);
    let path = i.and_then(|i| on_disk(koil, &parsed.entries[i]));
    path.unwrap_or_else(|| Err(NO_ENTRY.to_string()))
}

/// Where the entries on `lines` are on disk, as [`path_on_line`] finds
/// each, leaving out lines without one, for a shell command run on them; or
/// else why it can't be: one of them is new, or there are none. `lines` are
/// spans of lines, `(first, last)`, in order and apart: a range's, or the
/// marked lines (see Marked lines in Vim.qml).
pub fn paths_on_lines(
    koil: &Koil,
    text: &str,
    hidden: &[Hidden],
    lines: &[(usize, usize)],
) -> Result<Vec<String>, String> {
    let parsed = read(koil, text, hidden);
    let mut paths = Vec::new();
    for (&(line, _), entry) in parsed.spots.iter().zip(&parsed.entries) {
        if on_lines(lines, line)
            && let Some(path) = on_disk(koil, entry)
        {
            paths.push(path?);
        }
    }
    match (paths.is_empty(), lines) {
        (false, _) => Ok(paths),
        (true, [(first, last)]) if first == last => Err(NO_ENTRY.to_string()),
        (true, _) => Err("No entries on these lines".to_string()),
    }
}

/// What `<cfile>` stands for on `lines` of a file's or the scratchpad's
/// text, in a shell command run on them (see `shell::expand`), as on the
/// listing's entries (see [`paths_on_lines`]): with `at` (a column, in
/// UTF-16, of the only line, the cursor's), the link there, as gf opens it
/// (see `link::link_at`), and else on each line, its first (see
/// `link::first_link`). A relative path is looked for in each of `dirs` in
/// turn, and must be on disk (see `link::target`), and a URL is as it
/// opens. A line with an entry pasted with its ID is where that is on
/// disk. Blank lines are left out, and a line without a link says why.
pub fn links_on_lines(
    koil: &Koil,
    text: &str,
    hidden: &[Hidden],
    lines: &[(usize, usize)],
    at: Option<usize>,
    dirs: &[PathBuf],
) -> Result<Vec<String>, String> {
    let hidden: HashMap<usize, &Hidden> = hidden.iter().map(|h| (h.at, h)).collect();
    let end = lines.last().map_or(0, |&(_, last)| last + 1);
    let mut paths = Vec::new();
    // Where the next line starts, while there are icons to find.
    let mut next = 0;
    for (i, line) in text.split('\n').enumerate().take(end) {
        let start = next;
        if !hidden.is_empty() {
            next += utf16_len(line) + 1;
        }
        if !on_lines(lines, i) || line.trim().is_empty() {
            continue;
        }
        let (icon, _) = line_icon(&hidden, line, start);
        let entry = icon.and_then(|h| koil.path_of(Id(h.text.parse().ok()?)));
        if let Some(path) = entry {
            paths.push(unicode(path)?);
            continue;
        }
        let units: Vec<u16> = line.encode_utf16().collect();
        let link = match at {
            Some(at) => link::link_at(&units, at, true),
            None => link::first_link(&units),
        };
        let Some(link) = link else {
            return Err(match at {
                Some(_) => NO_FILE_NAME.to_string(),
                None => format!("No file name on line {}", i + 1),
            });
        };
        match link::target(&String::from_utf16_lossy(&units[link]), dirs) {
            link::Target::Path(path) | link::Target::Url(path) => paths.push(path),
            link::Target::Error(why) => return Err(why),
        }
    }
    match (paths.is_empty(), lines) {
        (false, _) => Ok(paths),
        (true, _) if at.is_some() => Err(NO_FILE_NAME.to_string()),
        (true, [(first, last)]) if first == last => Err("No file name on this line".to_string()),
        (true, _) => Err("No file names on these lines".to_string()),
    }
}

/// Whether `line` is in one of the spans of `lines` (see [`paths_on_lines`]).
fn on_lines(lines: &[(usize, usize)], line: usize) -> bool {
    let i = lines.partition_point(|&(_, last)| last < line);
    lines.get(i).is_some_and(|&(first, _)| first <= line)
}

/// vim's error for `<cfile>` with no file name under the cursor.
const NO_FILE_NAME: &str = "E446: No file name under cursor";

/// Why the cursor's line stands for no entry on disk.
const NO_ENTRY: &str = "No entry on this line";

/// Where `entry` is on disk, as QML takes it: where its ID points, even if
/// the line renames it; or else why there's none to give: it's new, so it
/// isn't on disk until the changes are applied, or its path isn't Unicode
/// (see [`unicode`]). None if its ID isn't one koil knows.
fn on_disk(koil: &Koil, entry: &Entry) -> Option<Result<String, String>> {
    match entry.id {
        Some(id) => Some(unicode(koil.path_of(id)?)),
        None => Some(Err(format!(
            "“{}” isn't on disk until the changes are applied",
            entry_name(entry)
        ))),
    }
}

/// The path the ID `id` (an icon's hidden text) stands for, as the hover
/// shows it: like the confirmations (see [`relative`]), with a `/` after a
/// dir's. None if it isn't an ID koil knows.
pub fn id_path(koil: &Koil, id: &str) -> Option<String> {
    let path = koil.path_of(Id(id.parse().ok()?))?;
    Some(slashed(relative(koil, path), path.is_dir()))
}

/// A line of what applying would do (see [`actions`]).
#[derive(Debug, PartialEq, Eq, Serialize)]
pub struct ActionLine {
    /// Like `MOVE a -> b`.
    pub text: String,
    /// The lines it can't be applied without (`Change::needs`), which the
    /// confirmation picks with it, and leaves out without it.
    pub needs: Vec<usize>,
    /// Whether it deletes something, which the "When deleting" setting
    /// asks about before applying.
    pub deletes: bool,
    /// What it does, for `Koil::apply_only`.
    #[serde(skip)]
    pub action: Action,
}

/// What applying would do (`Koil::changes`), as the user sees it, like
/// `MOVE a -> b`: a swap's renames are two lines, not the three steps
/// through a temp name that `Koil::apply` takes.
pub fn actions(koil: &Koil) -> Vec<ActionLine> {
    (koil.changes().into_iter())
        .map(|change| ActionLine {
            text: action_text(koil, &change.action),
            needs: change.needs,
            deletes: matches!(change.action, Action::DeleteFile(_) | Action::DeleteDir(_)),
            action: change.action,
        })
        .collect()
}

/// `action` as the user sees it, like `MOVE a -> b`.
fn action_text(koil: &Koil, action: &Action) -> String {
    let path = |p: &Path| relative(koil, p);
    let dir = |p: &Path| slashed(path(p), p.is_dir());
    match action {
        Action::CreateFile(p) => format!("CREATE {}", path(p)),
        Action::CreateDir(p) => format!("CREATE {}/", path(p)),
        Action::DeleteFile(p) => format!("DELETE {}", path(p)),
        Action::DeleteDir(p) => format!("DELETE {}/", path(p)),
        Action::Rename(s, d) => format!("MOVE   {} -> {}", dir(s), path(d)),
        Action::Copy(s, d) => format!("COPY   {} -> {}", dir(s), path(d)),
    }
}

/// What creating the new file at `path` before the other changes are
/// applied takes (`Koil::create_steps`), like `actions`' lines: its create,
/// after those of the new dirs it's in. Fails if it can't be created on its
/// own (see [`describe_create`]).
pub fn create_steps(koil: &Koil, path: &Path) -> Result<Vec<String>, String> {
    let steps = koil
        .create_steps(path)
        .map_err(|e| describe_create(koil, &e))?;
    Ok(steps.iter().map(|a| action_text(koil, a)).collect())
}

/// Creates the new file at `path` now, with the new dirs it's in, keeping
/// the other changes (`Koil::create_now`). Returns what the status line
/// says, like "`notes` created", or why it can't be created.
pub fn create_now(koil: &mut Koil, path: &Path) -> Result<String, String> {
    let name = relative(koil, path);
    match koil.create_now(path) {
        Ok(report) => Ok(match report.warning {
            Some(warning) => format!("`{name}` created; {}", describe_warning(&warning)),
            None => format!("`{name}` created"),
        }),
        Err(error) => Err(describe_create(koil, &error)),
    }
}

/// Why `Koil::create_steps` or `Koil::create_now` failed, naming the path
/// as the listing does.
pub fn describe_create(koil: &Koil, error: &KoilError) -> String {
    match error {
        KoilError::NotNew(path) => format!("`{}` isn't new", relative(koil, path)),
        KoilError::NeedsChanges(path) => format!(
            "`{}` can't be created before the other changes are applied (Space Space)",
            relative(koil, path)
        ),
        error => describe(error),
    }
}

/// How many of an apply's steps the undo history shows; the rest are
/// counted.
const SHOWN_STEPS: usize = 10;

/// An apply of the undo history, as the confirmation shows it to pick from
/// (see [`history`]).
#[derive(Debug, Serialize)]
pub struct HistoryLine {
    /// When it was applied, and where, if not in the open dir, then what
    /// undoing it does, a step a line (like `TRASH   a`, relative to where
    /// it was applied), and why it can't be undone now, if it can't.
    pub text: String,
    /// The lines (in the list) it can't be undone without: newer applies
    /// that changed the same paths.
    pub needs: Vec<usize>,
    /// Why it can't be undone now (see `Undoable::blocked`), if it can't.
    pub blocked: Option<String>,
    /// What undoing it does, every step, relative to the open dir, as `u`
    /// lists the last apply on its own.
    pub steps: Vec<String>,
    #[serde(skip)]
    pub applied: Applied,
}

/// Koil's undo history (`Koil::undoable`), newest first, as lines to pick
/// from. Fails if there are changes that aren't applied.
pub fn history(koil: &Koil) -> Result<Vec<HistoryLine>, String> {
    let undoable = koil.undoable().map_err(|e| describe(&e))?;
    let newest = undoable.len().saturating_sub(1);
    let lines = undoable.into_iter().rev().map(|undoable| {
        let dir = &undoable.applied.dir;
        let time = show_time(undoable.applied.time);
        // Where, if it's not the open dir.
        let mut text = match dir == koil.current_dir() {
            true => time,
            false => format!("{time}  {}", show_path(dir)),
        };
        let steps = &undoable.applied.steps;
        for step in steps.iter().take(SHOWN_STEPS) {
            text += &format!("\n{}", undo_text(dir, step));
        }
        if steps.len() > SHOWN_STEPS {
            text += &format!("\n… {} more", steps.len() - SHOWN_STEPS);
        }
        let blocked =
            (undoable.blocked.as_ref()).map(|(_, blocked)| describe_blocked(dir, blocked));
        if let Some(why) = &blocked {
            text += &format!("\nCan't be undone: {why}");
        }
        let open = koil.current_dir();
        HistoryLine {
            text,
            needs: undoable.needs.iter().map(|j| newest - j).collect(),
            blocked,
            steps: steps.iter().map(|step| undo_text(open, step)).collect(),
            applied: undoable.applied,
        }
    });
    Ok(lines.collect())
}

/// What undo `step` of an apply in `dir` does, as the user sees it, like
/// `TRASH   a`.
fn undo_text(dir: &Path, step: &Undo) -> String {
    let path = |p: &Path| shown_in(dir, p);
    let dir_path = |p: &Path| slashed(path(p), p.is_dir());
    match step {
        Undo::Trash(p) => format!("TRASH   {}", dir_path(p)),
        Undo::Restore(t) => format!("RESTORE {}", path(&t.original)),
        Undo::Rename(s, d) => format!("MOVE    {} -> {}", dir_path(s), path(d)),
    }
}

/// Why an undo step can't run, with its path relative to `dir` (an apply's,
/// or the open dir).
pub fn describe_blocked(dir: &Path, blocked: &Blocked) -> String {
    match blocked {
        Blocked::Missing(p) => format!("`{}` is gone", shown_in(dir, p)),
        Blocked::Taken(p) => format!("`{}` already exists", shown_in(dir, p)),
        Blocked::NotInTrash(p) => format!("`{}` is no longer in the trash", shown_in(dir, p)),
    }
}

/// `path` relative to `dir` if it's in it, else as [`show_path`] does.
fn shown_in(dir: &Path, path: &Path) -> String {
    match path.strip_prefix(dir) {
        Ok(rest) if !rest.as_os_str().is_empty() => {
            with_slashes(rest).to_string_lossy().into_owned()
        }
        _ => show_path(path),
    }
}

/// What Tab completes in the path field (see [`complete`]).
#[derive(Debug, Default, PartialEq, Eq, Serialize)]
pub struct Completion {
    /// Where the part of the path being written starts (after its last
    /// `/`): each option replaces it, up to the cursor.
    pub start: usize,
    /// What Tab fills in at once: the only option, or the longest start
    /// all of them share, if that's more than what's written. Empty if
    /// it's neither, and Tab shows the options.
    pub fill: String,
    pub options: Vec<Choice>,
}

/// A dir the path can go on to, shown like its line in the listing.
#[derive(Debug, PartialEq, Eq, Serialize)]
pub struct Choice {
    /// With a `/` after it.
    pub name: String,
    pub icon: String,
    /// The icon's color in a dark and in a light theme.
    pub colors: [String; 2],
}

/// The dirs the path field `line` can go on to from the cursor (`cursor`),
/// as `Koil::complete` reads the path from its start up to there, with the
/// settings the next update uses.
pub fn complete(koil: &Koil, line: &str, cursor: usize, settings: &Settings) -> Completion {
    let before = &line[..byte_index(line, cursor)];
    let path = before.trim_start();
    let completion = koil.complete(path, settings);
    let options = completion.names.iter().map(|name| {
        let (icon, colors) = icon(&completion.dir, name);
        Choice {
            name: name.clone(),
            icon: icon.to_string(),
            colors,
        }
    });
    let shared = shared_start(&completion.names);
    let part = &completion.part;
    let fill = match completion.names.as_slice() {
        [name] => name.clone(),
        _ if shared.chars().count() > part.chars().count() && has_in_order(shared, part) => {
            shared.to_string()
        }
        _ => String::new(),
    };
    Completion {
        start: utf16_len(indent(before)) + utf16_len(&path[..completion.start]),
        fill,
        options: options.collect(),
    }
}

/// Whether `text` has the characters of `part` in order, with case ignored
/// unless `part` has an uppercase letter, as `Koil::complete` matches a part
/// no dir starts with: what all of the dirs `ts` gives start with
/// (`my_t`, of `my_tests/` and `my_tools/`) mustn't fill in without its `s`.
fn has_in_order(text: &str, part: &str) -> bool {
    let ignore_case = !part.chars().any(char::is_uppercase);
    let as_matched = |s: &str| match ignore_case {
        true => s.to_lowercase(),
        false => s.to_string(),
    };
    let text = as_matched(text);
    let mut rest = text.chars();
    as_matched(part).chars().all(|c| rest.any(|t| t == c))
}

/// The longest text all of `names` start with.
fn shared_start(names: &[String]) -> &str {
    let Some((first, rest)) = names.split_first() else {
        return "";
    };
    let mut shared = first.as_str();
    for name in rest {
        let differs = shared
            .char_indices()
            .zip(name.chars())
            .find(|((_, a), b)| a != b);
        let end = differs.map_or(shared.len().min(name.len()), |((i, _), _)| i);
        shared = &shared[..end];
    }
    shared
}

/// Where the UTF-16 position `at` is in `s`, in bytes (its end, if past it).
fn byte_index(s: &str, at: usize) -> usize {
    let mut units = 0;
    for (i, c) in s.char_indices() {
        if units >= at {
            return i;
        }
        units += c.len_utf16();
    }
    s.len()
}

/// A part of the path field to color: the `pattern` (all of it, after the
/// dirs it's in, so it's told apart from them), then its parts: an
/// `escape`, a `class`, a regex's `quantifier`, a `group` (or a regex's
/// `|`, a glob's `{a,b}`), or an `anchor` (a regex's `.`, `,`, `^` and `$`,
/// a glob's `*` and `?`, which match any character, or a place).
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Span {
    pub start: usize,
    pub length: usize,
    pub kind: &'static str,
}

/// The parts of the pattern in the path field `line`, to color. None unless
/// it has one. It's read as a regex if `regex` (the setting the next update
/// reads it with, see [`rereads`]) is on, else as a glob. The pattern
/// starts where `Koil::open` would read it from (see [`pattern_start`]).
pub fn path_syntax(koil: &Koil, line: &str, regex: bool) -> Vec<Span> {
    let path = line.trim();
    let Some(start) = pattern_start(koil, path, regex) else {
        return Vec::new();
    };
    let pattern = &path[start..];
    let at = utf16_len(indent(line)) + utf16_len(&path[..start]);
    let span = |s: usize, e: usize, kind| Span {
        start: at + utf16_len(&pattern[..s]),
        length: utf16_len(&pattern[s..e]),
        kind,
    };
    let parts = match regex {
        true => regex_parts(pattern),
        false => glob_parts(pattern),
    };
    let parts = parts.into_iter().map(|(s, e, kind)| span(s, e, kind));
    [span(0, pattern.len(), "pattern")]
        .into_iter()
        .chain(parts)
        .collect()
}

/// Where the pattern (a regex if `regex`, else a glob) starts in `path`
/// (the path field, as written), as `Koil::read_location` says: after the
/// longest part of the path that's a dir, at the first part with a special
/// character that isn't quoted. None if it isn't a pattern.
fn pattern_start(koil: &Koil, path: &str, regex: bool) -> Option<usize> {
    let start = koil.read_location(path, regex).pattern_start?;
    path.is_char_boundary(start).then_some(start)
}

/// The parts of `glob` to color, as byte ranges and their kinds (see
/// [`Span`]), as globset reads it: a `,` is a `group` only in `{...}`, and
/// a class ends at its first `]` (but one first in it). One that isn't
/// valid (yet) is colored too, as [`regex_parts`] colors a regex.
fn glob_parts(glob: &str) -> Vec<(usize, usize, &'static str)> {
    let chars: Vec<(usize, char)> = glob.char_indices().collect();
    let at = |i: usize| chars.get(i).map_or(glob.len(), |&(at, _)| at);
    let is = |i: usize, c: char| chars.get(i).is_some_and(|&(_, d)| d == c);
    let mut parts = Vec::new();
    let mut braces = 0;
    let mut i = 0;
    while i < chars.len() {
        let start = i;
        i += 1;
        let kind = match chars[start].1 {
            '\\' => {
                i += 1;
                "escape"
            }
            '[' => {
                // `!` or `^` negates it, and a `]` first is in it
                if is(i, '!') || is(i, '^') {
                    i += 1;
                }
                if is(i, ']') {
                    i += 1;
                }
                while i < chars.len() && !is(i, ']') {
                    i += 1;
                }
                i += 1;
                "class"
            }
            '*' | '?' => "anchor",
            '{' => {
                braces += 1;
                "group"
            }
            '}' if braces > 0 => {
                braces -= 1;
                "group"
            }
            ',' if braces > 0 => "group",
            _ => continue,
        };
        parts.push((at(start), at(i), kind));
    }
    parts
}

/// The parts of `regex` to color, as byte ranges and their kinds (see
/// [`Span`]). Only its syntax is read, so one that isn't valid (yet) is
/// colored too.
fn regex_parts(regex: &str) -> Vec<(usize, usize, &'static str)> {
    let chars: Vec<(usize, char)> = regex.char_indices().collect();
    let at = |i: usize| chars.get(i).map_or(regex.len(), |&(at, _)| at);
    let is = |i: usize, c: char| chars.get(i).is_some_and(|&(_, d)| d == c);
    let mut parts = Vec::new();
    let mut i = 0;
    while i < chars.len() {
        let start = i;
        let kind = match chars[i].1 {
            '\\' => {
                i += 2;
                "escape"
            }
            '[' => {
                i = class_end(&chars, i);
                "class"
            }
            '(' => {
                i += 1;
                // Flags or a name, like `(?:`, `(?i)` or `(?P<name>`.
                if is(i, '?') {
                    while i < chars.len() && !matches!(chars[i].1, ':' | ')' | '>') {
                        i += 1;
                    }
                    i += 1;
                }
                "group"
            }
            ')' | '|' => {
                i += 1;
                "group"
            }
            '*' | '+' | '?' => {
                i += if is(i + 1, '?') { 2 } else { 1 };
                "quantifier"
            }
            '{' => match repetition_end(&chars, i) {
                Some(end) => {
                    i = if is(end, '?') { end + 1 } else { end };
                    "quantifier"
                }
                None => {
                    i += 1;
                    continue;
                }
            },
            '.' | ',' | '^' | '$' => {
                i += 1;
                "anchor"
            }
            _ => {
                i += 1;
                continue;
            }
        };
        parts.push((at(start), at(i), kind));
    }
    parts
}

/// Where the class that starts at `chars[i]` (a `[`) ends: after its `]`.
/// Classes nest, like `[a[:digit:]]`, and a `]` first in one is in it.
fn class_end(chars: &[(usize, char)], mut i: usize) -> usize {
    let is = |i: usize, c: char| chars.get(i).is_some_and(|&(_, d)| d == c);
    let mut depth = 0;
    while i < chars.len() {
        match chars[i].1 {
            '\\' => i += 1,
            '[' => {
                depth += 1;
                if is(i + 1, '^') {
                    i += 1;
                }
                if is(i + 1, ']') {
                    i += 1;
                }
            }
            ']' => {
                depth -= 1;
                if depth == 0 {
                    return i + 1;
                }
            }
            _ => {}
        }
        i += 1;
    }
    i
}

/// Where the repetition that starts at `chars[i]` (a `{`) ends, like `{2}`
/// or `{1,3}`: after its `}`. None if it isn't one, so `{` is a character.
fn repetition_end(chars: &[(usize, char)], i: usize) -> Option<usize> {
    let close = (i + 1..chars.len()).find(|&j| chars[j].1 == '}')?;
    let inside: String = chars[i + 1..close].iter().map(|&(_, c)| c).collect();
    let (min, max) = inside.split_once(',').unwrap_or((&inside, ""));
    let digits = |s: &str| s.chars().all(|c| c.is_ascii_digit());
    (!min.is_empty() && digits(min) && digits(max)).then_some(close + 1)
}

/// `path` as the confirmations show it: relative to the open dir if it's in
/// it (as `Koil::relative` gives it), else as [`show_path`] does.
fn relative(koil: &Koil, path: &Path) -> String {
    shown_in(koil.current_dir(), path)
}

/// `path` as QML takes it, a string (as it is, with `\` on Windows), or
/// else why it can't be: it isn't Unicode (only on Linux, or a malformed
/// name on Windows), which a string can't hold, so Koil only shows it, with
/// `�` (see [`read`]), and can neither open it nor put it in a command.
pub fn unicode(path: &Path) -> Result<String, String> {
    match path.to_str() {
        Some(path) => Ok(path.to_string()),
        None => Err(format!(
            "Koil can't use `{}`, as its path isn't valid Unicode",
            show_path(path)
        )),
    }
}

/// What `koil` has open, as the path field shows it: `Koil::location` (the
/// dir, then a `/` and the pattern as written, if there is one), with `~`
/// for the home dir.
pub fn show_location(koil: &Koil) -> String {
    with_tilde(&koil.location().to_string_lossy())
}

/// `path` (a dir or a file, not a pattern) as Koil shows it: with `/`
/// between its parts, also on Windows (`koil_core::with_slashes`: users
/// write only `/`, as koil reads a `\` in a pattern as an escape, and ends a
/// pattern's base dir only at a `/`), and `~` for the home dir.
pub fn show_path(path: &Path) -> String {
    with_tilde(&with_slashes(path).to_string_lossy())
}

/// `path` (as Koil shows it, with `/`) with `~` for the home dir at its
/// start. Only that part is read, so a pattern after it stays as written.
pub fn with_tilde(path: &str) -> String {
    let Some(home) = home() else {
        return path.to_string();
    };
    match path.strip_prefix(&home) {
        Some("") => "~".to_string(),
        Some(rest) if rest.starts_with('/') && !home.ends_with('/') => format!("~{rest}"),
        _ => path.to_string(),
    }
}

/// `rest` (a pattern or a relative path) after the dir `dir`, with a `/`
/// between them, unless `dir` (a root, like `/` or `C:/`) ends with one.
pub fn join_shown(dir: String, rest: &str) -> String {
    match dir.ends_with('/') {
        true => dir + rest,
        false => format!("{dir}/{rest}"),
    }
}

/// The home dir, as Koil shows it (see [`show_path`]).
fn home() -> Option<String> {
    let home = std::env::home_dir()?;
    Some(with_slashes(&home).to_string_lossy().into_owned())
}

/// A warning from opening the dir again, with its paths as Koil shows them.
pub fn describe_warning(warning: &Warning) -> String {
    match warning {
        Warning::DirNotFound { requested, opened } => format!(
            "`{}` is not a directory, opened `{}` instead",
            show_path(requested),
            show_path(opened)
        ),
        Warning::OverLimit { error, opened } => {
            format!("{error}, opened `{}` instead", show_path(opened))
        }
    }
}

/// Why `Koil::open` failed, with `~` for the home dir in a path it names
/// (see [`show_path`]).
pub fn describe_open(error: &OpenError) -> String {
    match error {
        OpenError::NotFound(path) => format!("`{}` does not exist", show_path(path)),
        OpenError::NotADirectory(path) => {
            format!("`{}` is a file, not a directory", show_path(path))
        }
        error => describe(error),
    }
}

/// An error, followed by what caused it.
pub fn describe(error: &dyn Error) -> String {
    let causes = std::iter::successors(error.source(), |&e| e.source());
    causes.fold(error.to_string(), |message, e| format!("{message}: {e}"))
}

#[cfg(test)]
mod tests;
