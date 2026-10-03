//! Koil's listing, as the editor shows it: a line per entry: its icon, which
//! hides its ID (the editor's hidden text), two spaces, and its name, with a
//! `/` after a dir's. A new entry has no ID, so the user writes just its name.
//! The open dir (or pattern) is in the path field above it, which is read
//! with it.
//!
//! Positions in the text are in UTF-16 code units, as QML counts them.

use std::collections::HashMap;
use std::error::Error;
use std::path::{Path, PathBuf};

use devicons::Theme;
use koil_core::apply::Undo;
use koil_core::{
    Action, Entry, EntryErrorKind, EntryWarning, Id, Koil, OpenError, Pattern, Settings,
    UpdateError, UpdateOpenError, Warning, with_slashes,
};
use serde::{Deserialize, Serialize};

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
}

/// The listing of what `koil` has open.
pub fn render(koil: &Koil) -> Rendered {
    let mut rendered = Rendered {
        path: show_location(koil),
        pending_color: PENDING_COLOR,
        ..Rendered::default()
    };
    // The text's length, kept rather than counted for each line.
    let mut length = 0;
    for entry in koil.listing() {
        if !rendered.names.is_empty() {
            rendered.text.push('\n');
            length += 1;
        }
        let name = entry_name(&entry);
        let (icon, colors) = icon(koil.current_dir(), &name);
        let line = format!("{icon}  {name}");
        if let Some(id) = entry.id {
            rendered.hidden.push(Hidden {
                at: length,
                icon: icon.to_string(),
                text: id.0.to_string(),
            });
        }
        rendered.colors.entry(icon.to_string()).or_insert(colors);
        rendered.text.push_str(&line);
        length += utf16_len(&line);
        rendered.names.push(name);
    }
    rendered
}

/// An entry's name as the listing shows it, with a `/` after a dir's.
fn entry_name(entry: &Entry) -> String {
    let slash = if entry.is_dir { "/" } else { "" };
    format!("{}{slash}", entry.name.to_string_lossy())
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
        let rest = &line[indent(line).len()..];
        let (id, rest) = match hidden.get(&(start + utf16_len(indent(line)))) {
            Some(h) if rest.starts_with(&h.icon) => match h.text.parse() {
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
        let entry = match name.strip_suffix('/') {
            Some("..") if id.is_none() => Entry::parent(),
            Some(dir) => Entry {
                id,
                name: dir.trim_end_matches('/').into(),
                is_dir: true,
            },
            None => Entry {
                id,
                name: name.into(),
                is_dir: false,
            },
        };
        parsed.entries.push(entry);
        parsed.spots.push((i, column));
    }
    parsed
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
    let parsed = parse(text, hidden);
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
/// them yet, which applying would change (`Koil::is_pending`): new ones (but
/// `../`), and ones whose path isn't their ID's (renamed, copied, or moved
/// here from another dir). Their icons get `PENDING_COLOR`.
pub fn pending_lines(koil: &Koil, text: &str, hidden: &[Hidden]) -> Vec<usize> {
    let parsed = parse(text, hidden);
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
/// field, as written) if it changed, all in `Koil::update_and_open`, which
/// reads the entries with the settings they were listed with. If anything
/// fails, `koil` is left as it was.
pub fn update(
    koil: &mut Koil,
    path: &str,
    text: &str,
    hidden: &[Hidden],
    settings: &Settings,
    open: Option<&str>,
) -> Updated {
    let parsed = parse(text, hidden);
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
    let target = open.or((location != show_location(koil)).then_some(location));
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

/// What Enter on a line of the listing opens (see [`target_on_line`]).
#[derive(Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Target {
    /// A dir, relative to the open one.
    Dir(String),
    /// A file on disk, and its name on the line.
    File { path: PathBuf, name: String },
    /// A new file, which isn't there until the changes are applied.
    New(String),
}

/// What Enter on `line` opens: the dir of an entry whose name ends with `/`,
/// or else the file the entry is on disk (where its ID points, even if the
/// line renames it). None on a line without an entry, or with an ID koil
/// doesn't know.
pub fn target_on_line(koil: &Koil, text: &str, hidden: &[Hidden], line: usize) -> Option<Target> {
    let parsed = parse(text, hidden);
    let i = parsed.spots.iter().position(|&(l, _)| l == line)?;
    let entry = &parsed.entries[i];
    let name = entry.name.to_string_lossy().into_owned();
    if entry.is_dir {
        return Some(Target::Dir(name));
    }
    let Some(id) = entry.id else {
        return Some(Target::New(name));
    };
    let path = koil.path_of(id)?;
    Some(match path.is_dir() {
        // a dir with the `/` taken off its name
        true => Target::Dir(name),
        false => Target::File {
            path: path.to_path_buf(),
            name,
        },
    })
}

/// The path the ID `id` (an icon's hidden text) stands for, as the hover
/// shows it: like the confirmations (see [`relative`]), with a `/` after a
/// dir's. None if it isn't an ID koil knows.
pub fn id_path(koil: &Koil, id: &str) -> Option<String> {
    let path = koil.path_of(Id(id.parse().ok()?))?;
    let slash = if path.is_dir() { "/" } else { "" };
    Some(format!("{}{slash}", relative(koil, path)))
}

/// What `Koil::apply` would do, as the user sees it, like `MOVE a -> b`.
pub fn actions(koil: &Koil) -> Vec<String> {
    let path = |p: &Path| relative(koil, p);
    let dir = |p: &Path| format!("{}{}", path(p), if p.is_dir() { "/" } else { "" });
    let action = |action: &Action| match action {
        Action::CreateFile(p) => format!("CREATE {}", path(p)),
        Action::CreateDir(p) => format!("CREATE {}/", path(p)),
        Action::DeleteFile(p) => format!("DELETE {}", path(p)),
        Action::DeleteDir(p) => format!("DELETE {}/", path(p)),
        Action::Rename(s, d) => format!("MOVE   {} -> {}", dir(s), path(d)),
        Action::Copy(s, d) => format!("COPY   {} -> {}", dir(s), path(d)),
    };
    koil.compute_actions().iter().map(action).collect()
}

/// What `Koil::undo` would do, as the user sees it, like `TRASH a`: empty if
/// there's nothing to undo. Fails if there are changes that aren't applied.
pub fn undo_steps(koil: &Koil) -> Result<Vec<String>, String> {
    let path = |p: &Path| relative(koil, p);
    let dir = |p: &Path| format!("{}{}", path(p), if p.is_dir() { "/" } else { "" });
    let step = |step: &Undo| match step {
        Undo::Trash(p) => format!("TRASH   {}", dir(p)),
        Undo::Restore(t) => format!("RESTORE {}", path(&t.original)),
        Undo::Rename(s, d) => format!("MOVE    {} -> {}", dir(s), path(d)),
    };
    let steps = koil.undo_steps().map_err(|e| describe(&e))?;
    Ok(steps.unwrap_or_default().iter().map(step).collect())
}

/// A part of the path field to color: the `pattern` (all of it, after the
/// dirs it's in), then its regex's parts: an `escape`, a `class`, a
/// `quantifier`, a `group` (or `|`), or an `anchor` (`.`, `,`, `^` and `$`,
/// which match any character, or a place).
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Span {
    pub start: usize,
    pub length: usize,
    pub kind: &'static str,
}

/// The parts of the regex in the path field `line`, to color. None unless
/// the path is read as a regex: it's the regex that's open, or it changed
/// and `regex` (the setting the next update uses) is on. The regex starts
/// where `Koil::open` would read it from (see [`pattern_start`]).
pub fn path_syntax(koil: &Koil, line: &str, regex: bool) -> Vec<Span> {
    let path = line.trim();
    let is_regex = match path == show_location(koil) {
        true => matches!(koil.pattern(), Some(Pattern::Regex(_))),
        false => regex,
    };
    let Some(start) = is_regex.then(|| pattern_start(koil, path)).flatten() else {
        return Vec::new();
    };
    let pattern = &path[start..];
    let at = utf16_len(indent(line)) + utf16_len(&path[..start]);
    let span = |s: usize, e: usize, kind| Span {
        start: at + utf16_len(&pattern[..s]),
        length: utf16_len(&pattern[s..e]),
        kind,
    };
    let parts = regex_parts(pattern)
        .into_iter()
        .map(|(s, e, kind)| span(s, e, kind));
    [span(0, pattern.len(), "pattern")]
        .into_iter()
        .chain(parts)
        .collect()
}

/// Where the regex starts in `path` (the path field, as written), as
/// `Koil::read_location` says: after the longest part of the path that's a
/// dir, at the first part with a special character that isn't quoted. None
/// if it isn't a pattern.
fn pattern_start(koil: &Koil, path: &str) -> Option<usize> {
    let start = koil.read_location(path, true).pattern_start?;
    path.is_char_boundary(start).then_some(start)
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
/// it (`Koil::relative`), else as [`show_path`] does.
fn relative(koil: &Koil, path: &Path) -> String {
    match koil.relative(path) {
        Some(rest) => rest.to_string_lossy().into_owned(),
        None => show_path(path),
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
    let mut message = error.to_string();
    let mut source = error.source();
    while let Some(e) = source {
        message = format!("{message}: {e}");
        source = e.source();
    }
    message
}

#[cfg(test)]
mod tests;
