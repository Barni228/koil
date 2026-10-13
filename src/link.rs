//! What gf, gx and a click with Cmd open (see Links in CLAUDE.md): the
//! link at a place in a line, and what its text stands for, a web page or
//! a file or dir on disk.

use std::ops::Range;
use std::path::{Component, Path, PathBuf};

use koil_core::with_slashes;
use serde::Serialize;

use crate::syntax;

#[cfg(test)]
mod tests;

/// The link in `line` (UTF-16, as Qt has it) with the character at `at` in
/// it, as indexes into it: a URL or a path, as syntax.rs colors them (what
/// a click with Cmd opens), or else, with `names` (gf and gx), the file
/// name there or the first one after it on the line, as vim's gf finds it.
pub fn link_at(line: &[u16], at: usize, names: bool) -> Option<Range<usize>> {
    match syntax::link_at(line, at) {
        Some(span) => Some(span.start..span.end),
        None if names => name_at(line, at),
        None => None,
    }
}

/// Whether `c` can be in a file name, as vim's `isfname` says by default:
/// letters, digits and `/.-_+,#$%~=` (and `\`, which separates names on
/// Windows).
fn in_name(c: char) -> bool {
    c.is_alphanumeric() || "/.-_+,#$%~=".contains(c) || cfg!(windows) && c == '\\'
}

/// The file name at `at` in `line`, or else the first one after it on the
/// line, as vim's gf takes it: `\ ` (an escaped space, as in a shell) goes
/// on, and a `.`, `,`, `:`, `;` or `!` at its end is a sentence's, not its
/// (but `..` is a dir).
fn name_at(line: &[u16], at: usize) -> Option<Range<usize>> {
    let mut chars = Vec::new();
    let mut i = 0;
    for c in char::decode_utf16(line.iter().copied()) {
        let c = c.unwrap_or(char::REPLACEMENT_CHARACTER);
        chars.push((i, c));
        i += c.len_utf16();
    }
    let c = |k: usize| chars.get(k).map(|&(_, c)| c);
    let escape = |k: usize| c(k) == Some('\\') && c(k + 1) == Some(' ');
    let mut start = chars.partition_point(|&(i, _)| i <= at).checked_sub(1)?;
    while !in_name(c(start)?) {
        start += 1;
    }
    let mut end = start + 1;
    loop {
        if c(end).is_some_and(in_name) {
            end += 1;
        } else if escape(end) {
            end += 2;
        } else {
            break;
        }
    }
    loop {
        if start > 0 && in_name(chars[start - 1].1) {
            start -= 1;
        } else if start > 1 && escape(start - 2) {
            start -= 2;
        } else {
            break;
        }
    }
    if end - start > 2 && ".,:;!".contains(chars[end - 1].1) && chars[end - 2].1 != '.' {
        end -= 1;
    }
    Some(chars[start].0..chars.get(end).map_or(line.len(), |&(i, _)| i))
}

/// What a link opens (see [`target`]).
#[derive(Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum Target {
    /// A URL that isn't a file's, for the browser (or the app it's for).
    Url(String),
    /// A file or dir that's on disk, as an absolute path (with `/`, also
    /// on Windows, as Koil shows paths).
    Path(String),
    /// Why it opens nothing, as vim says it.
    Error(String),
}

/// What `link` opens (a link's text, or what visual mode selected): a URL
/// (`scheme://…`, or `www.…`, which is `https://www.…`), but a `file://`
/// one is the file it names; or else a path (`~` first is the home dir, and
/// `\ ` a space, as in a shell, but not on Windows), which must be on disk.
/// A relative one is looked for in each of `dirs` in turn, as vim's `path`
/// (`.,,`) has gf look in the file's dir, then the current one.
pub fn target(link: &str, dirs: &[PathBuf]) -> Target {
    let link = link.trim();
    if link.is_empty() || link.contains('\n') {
        return Target::Error("E446: No file name under cursor".to_string());
    }
    let path = match scheme(link) {
        Some(scheme) if scheme.eq_ignore_ascii_case("file") => {
            file_path(&link[scheme.len() + "://".len()..])
        }
        Some(_) => return Target::Url(link.to_string()),
        None if link
            .get(..4)
            .is_some_and(|s| s.eq_ignore_ascii_case("www.")) =>
        {
            return Target::Url(format!("https://{link}"));
        }
        None if cfg!(windows) => PathBuf::from(link),
        None => PathBuf::from(link.replace("\\ ", " ")),
    };
    let path = match (path.strip_prefix("~"), std::env::home_dir()) {
        (Ok(rest), Some(home)) => home.join(rest),
        _ => path,
    };
    let found = if path.is_absolute() {
        Some(normalized(&path)).filter(|p| p.exists())
    } else {
        dirs.iter()
            .map(|dir| normalized(&dir.join(&path)))
            .find(|p| p.exists())
    };
    match found {
        Some(path) => Target::Path(with_slashes(&path).to_string_lossy().into_owned()),
        None => Target::Error(format!("E447: Can't find file \"{link}\" in path")),
    }
}

/// The scheme `link` starts with, before a `://`: a letter, then letters,
/// digits, `+`, `-` or `.`.
fn scheme(link: &str) -> Option<&str> {
    let scheme = &link[..link.find("://")?];
    let mut chars = scheme.chars();
    let valid = chars.next()?.is_ascii_alphabetic()
        && chars.all(|c| c.is_ascii_alphanumeric() || "+-.".contains(c));
    valid.then_some(scheme)
}

/// The path of a `file://` URL, from what's after the `//`: no host or
/// `localhost`, then the path, with its `%20`s and such decoded (and on
/// Windows, `/C:/…` is `C:/…`).
fn file_path(rest: &str) -> PathBuf {
    let rest = rest.strip_prefix("localhost").unwrap_or(rest);
    let bytes = rest.as_bytes();
    let hex = |k: usize| bytes.get(k).and_then(|&b| (b as char).to_digit(16));
    let mut decoded = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%'
            && let (Some(high), Some(low)) = (hex(i + 1), hex(i + 2))
        {
            decoded.push((high * 16 + low) as u8);
            i += 3;
        } else {
            decoded.push(bytes[i]);
            i += 1;
        }
    }
    let path = String::from_utf8_lossy(&decoded).into_owned();
    #[cfg(windows)]
    if let Some(drive) = path.strip_prefix('/')
        && drive.as_bytes().get(1) == Some(&b':')
    {
        return PathBuf::from(drive);
    }
    PathBuf::from(path)
}

/// `path` without its `.` parts, and each `..` taking away the part before
/// it, as it's written, not as the disk has it (a link stays a link): so
/// a file opened as `src/../README.md` is shown as `README.md`.
fn normalized(path: &Path) -> PathBuf {
    let mut parts = PathBuf::new();
    for part in path.components() {
        match (part, parts.components().next_back()) {
            (Component::CurDir, _) => {}
            (Component::ParentDir, Some(Component::Normal(_))) => {
                parts.pop();
            }
            // a root's parent is itself
            (Component::ParentDir, Some(Component::RootDir | Component::Prefix(_))) => {}
            (part, _) => parts.push(part),
        }
    }
    parts
}
