//! A file's colors (see Syntax in CLAUDE.md): what most files have in
//! common, found without knowing their language: strings and their
//! escapes, numbers, comments, paths and URLs. A line is UTF-16, as Qt has
//! it, and positions are indexes into it.

use std::path::Path;

#[cfg(test)]
mod tests;

/// What a part of a line is, which its color says.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    String,
    /// A backslash and what it escapes, in a string.
    Escape,
    Number,
    Comment,
    Path,
    Url,
}

/// The part of a line from `start` to `end` that is a `kind`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Span {
    pub start: usize,
    pub end: usize,
    pub kind: Kind,
}

/// What a line ends in that goes on in the next one: a block comment, or
/// nothing.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum State {
    #[default]
    Code,
    /// In a `/* */` comment.
    Slashes,
    /// In a `<!-- -->` comment.
    Markup,
}

impl State {
    /// As a QSyntaxHighlighter's block state, which is -1 (`Code`) for a
    /// line it has none for.
    pub fn number(self) -> i32 {
        match self {
            State::Code => 0,
            State::Slashes => 1,
            State::Markup => 2,
        }
    }

    pub fn from_number(number: i32) -> State {
        match number {
            1 => State::Slashes,
            2 => State::Markup,
            _ => State::Code,
        }
    }

    /// What ends the comment it's in.
    fn close(self) -> Option<&'static str> {
        match self {
            State::Code => None,
            State::Slashes => Some("*/"),
            State::Markup => Some("-->"),
        }
    }
}

/// Which comments a file's lines can have, besides `<!-- -->`: `# like
/// this` and `//` or `/* */`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Comments {
    pub hash: bool,
    pub slashes: bool,
}

impl Comments {
    pub const ALL: Comments = Comments {
        hash: true,
        slashes: true,
    };

    /// The comments the file `name` can have: all of them, but in
    /// Markdown, where `#` starts a heading, and in Python, where `//` is
    /// a division.
    pub fn of(name: &str) -> Comments {
        let extension = Path::new(name)
            .extension()
            .and_then(|e| e.to_str())
            .map(str::to_ascii_lowercase);
        match extension.as_deref() {
            Some("md" | "markdown" | "mdx" | "mdown" | "mkd") => Comments {
                hash: false,
                slashes: true,
            },
            Some("py" | "pyi" | "pyw") => Comments {
                hash: true,
                slashes: false,
            },
            _ => Comments::ALL,
        }
    }
}

/// How much of a line is colored, as vim's `synmaxcol`: a long line (a
/// minified file's) takes long to color, and Qt longer to lay out with its
/// colors.
pub const MAX_LENGTH: usize = 3000;

/// The parts of `line` to color, which starts in `state`, in the order
/// they're colored (a later one over an earlier one: a path in a string),
/// and the state it ends in.
pub fn spans(line: &[u16], state: State, comments: Comments) -> (Vec<Span>, State) {
    let line = &line[..line.len().min(MAX_LENGTH)];
    let mut spans = Vec::new();
    let state = code(line, state, comments, &mut spans);
    links(line, &mut spans);
    (spans, state)
}

/// `spans` (as `spans` gives them) as they're drawn, sorted and apart: each
/// part the kind of the last one over it, so a path in a string splits it
/// in three. Qt Quick draws a line's formats so, but one that starts in
/// another lost its last character, and the other everything after it
/// (`QQuickTextNodeEngine::mergeFormats`): `"~/a.txt"` ended in a plain
/// `t"`, and `"a\nb"` in a plain `\nb"`.
pub fn apart(spans: &[Span]) -> Vec<Span> {
    let mut kinds = vec![None; spans.iter().map(|s| s.end).max().unwrap_or(0)];
    for s in spans {
        kinds[s.start..s.end].fill(Some(s.kind));
    }
    let mut parts: Vec<Span> = Vec::new();
    for (i, kind) in kinds.into_iter().enumerate() {
        let Some(kind) = kind else { continue };
        match parts.last_mut() {
            Some(last) if last.end == i && last.kind == kind => last.end = i + 1,
            _ => parts.push(span(i, i + 1, kind)),
        }
    }
    parts
}

const TAB: u16 = b'\t' as u16;
const SPACE: u16 = b' ' as u16;
const DOUBLE_QUOTE: u16 = b'"' as u16;
const QUOTE: u16 = b'\'' as u16;
const BACKTICK: u16 = b'`' as u16;
const BACKSLASH: u16 = b'\\' as u16;
const SLASH: u16 = b'/' as u16;
const STAR: u16 = b'*' as u16;
const HASH: u16 = b'#' as u16;
const BANG: u16 = b'!' as u16;
const DOT: u16 = b'.' as u16;
const COLON: u16 = b':' as u16;
const TILDE: u16 = b'~' as u16;
const UNDERSCORE: u16 = b'_' as u16;

fn span(start: usize, end: usize, kind: Kind) -> Span {
    Span { start, end, kind }
}

/// The unit at `i`, or 0 past the end, which is none of those above.
fn at(line: &[u16], i: usize) -> u16 {
    line.get(i).copied().unwrap_or(0)
}

/// The character starting at `i`, if one does (not half of a pair).
fn char_at(line: &[u16], i: usize) -> Option<char> {
    char::decode_utf16(line.get(i..)?.iter().copied().take(2))
        .next()?
        .ok()
}

/// The character ending at `i`.
fn char_before(line: &[u16], i: usize) -> Option<char> {
    match i {
        0 => None,
        1 => char_at(line, 0),
        _ if (0xdc00..0xe000).contains(&line[i - 1]) => char_at(line, i - 2),
        _ => char_at(line, i - 1),
    }
}

fn is_word(c: Option<char>) -> bool {
    c.is_some_and(|c| c.is_alphanumeric() || c == '_')
}

fn is_blank(u: u16) -> bool {
    u == SPACE || u == TAB
}

fn is_digit(u: u16) -> bool {
    (b'0' as u16..=b'9' as u16).contains(&u)
}

fn is_letter(u: u16) -> bool {
    (b'a' as u16..=b'z' as u16).contains(&(u | 0x20))
}

/// Whether `u` is one of the ASCII characters in `set`.
fn is_any(u: u16, set: &[u8]) -> bool {
    u < 0x80 && set.contains(&(u as u8))
}

fn starts_with(line: &[u16], i: usize, text: &str) -> bool {
    text.bytes()
        .enumerate()
        .all(|(k, b)| at(line, i + k) == b as u16)
}

/// Where `text` ends, the first time it's in `line` from `from`.
fn find_end(line: &[u16], from: usize, text: &str) -> Option<usize> {
    (from..line.len())
        .find(|&i| starts_with(line, i, text))
        .map(|i| i + text.len())
}

/// The strings, comments and numbers in `line`, which starts in `state`,
/// each found as its start comes first, so a `#` in a string isn't a
/// comment, nor a quote in a comment a string. Gives the state it ends in.
fn code(line: &[u16], state: State, comments: Comments, spans: &mut Vec<Span>) -> State {
    let n = line.len();
    let mut i = 0;
    if let Some(close) = state.close() {
        match find_end(line, 0, close) {
            Some(end) => {
                spans.push(span(0, end, Kind::Comment));
                i = end;
            }
            None => {
                spans.push(span(0, n, Kind::Comment));
                return state;
            }
        }
    }
    while i < n {
        let u = line[i];
        let before = if i == 0 { 0 } else { line[i - 1] };
        let blank_before = i == 0 || is_blank(before);
        let comment = if u == SLASH && comments.slashes && at(line, i + 1) == SLASH {
            // Not a URL's (`https://`), nor a division (`a//b`).
            (blank_before || is_any(before, b";{}")).then_some(State::Code)
        } else if u == SLASH && comments.slashes && at(line, i + 1) == STAR {
            // Not a glob's (`src/*`).
            (blank_before || is_any(before, b"({[,;=")).then_some(State::Slashes)
        } else if starts_with(line, i, "<!--") {
            Some(State::Markup)
        } else if u == HASH && comments.hash && blank_before && starts_hash_comment(line, i) {
            Some(State::Code)
        } else {
            None
        };
        if let Some(inside) = comment {
            // To its close, or the line's end, which it goes on from.
            let open = if inside == State::Markup { 4 } else { 2 };
            let end = inside
                .close()
                .and_then(|close| find_end(line, i + open, close));
            spans.push(span(i, end.unwrap_or(n), Kind::Comment));
            match end {
                Some(end) => i = end,
                None => return inside,
            }
            continue;
        }
        let string = match u {
            DOUBLE_QUOTE | BACKTICK => before != BACKSLASH,
            QUOTE => {
                before != BACKSLASH && (!is_word(char_before(line, i)) || after_prefix(line, i))
            }
            _ => false,
        };
        if string && let Some(end) = string_at(line, i, spans) {
            i = end;
            continue;
        }
        if is_digit(u) && !is_word(char_before(line, i)) {
            i = number_at(line, i, spans);
            continue;
        }
        i += 1;
    }
    State::Code
}

/// Whether the `#` at `i` (after a blank, or first) starts a comment: one
/// with a blank or the line's end after it (`# like this`), more `#`s or
/// a line of `-`s or `=`s, or a shebang (`#!/bin/sh`). Not one before a
/// word, as in `#include`, a CSS `#id` or `#123`, nor Rust's `#![attr]`.
fn starts_hash_comment(line: &[u16], i: usize) -> bool {
    let next = at(line, i + 1);
    next == 0
        || is_blank(next)
        || (next == BANG && at(line, i + 2) != b'[' as u16)
        || is_any(next, b"#-=*/~:+|")
}

/// Whether the `'` at `i` comes after a string's prefix, as in Python's
/// `f'…'` or `rb'…'`, rather than in a word, as in `it's`.
fn after_prefix(line: &[u16], i: usize) -> bool {
    let mut start = i;
    while start > 0 && is_letter(line[start - 1]) && i - start < 3 {
        start -= 1;
    }
    if is_word(char_before(line, start)) {
        return false;
    }
    let prefix: String = line[start..i]
        .iter()
        .map(|&u| (u as u8 as char).to_ascii_lowercase())
        .collect();
    matches!(
        prefix.as_str(),
        "r" | "b" | "f" | "u" | "rb" | "br" | "fr" | "rf"
    )
}

/// The string the quote at `i` starts, if it ends on the line: puts its
/// span and its escapes' in `spans` (none in a `` ` `` one, which is
/// Markdown's code too), and gives its end. A `'` one ends only at a `'`
/// that no word goes on from, so neither an apostrophe (`it's`) nor a
/// Rust lifetime (`&'a str`) is taken for one.
fn string_at(line: &[u16], i: usize, spans: &mut Vec<Span>) -> Option<usize> {
    let quote = line[i];
    let mut escapes = Vec::new();
    let mut j = i + 1;
    while j < line.len() {
        let u = line[j];
        if u == quote {
            if quote == QUOTE && is_word(char_at(line, j + 1)) {
                return None;
            }
            spans.push(span(i, j + 1, Kind::String));
            spans.extend(escapes);
            return Some(j + 1);
        }
        if u == BACKSLASH && quote != BACKTICK && j + 1 < line.len() {
            let end = j + 1 + char_at(line, j + 1).map_or(1, char::len_utf16);
            escapes.push(span(j, end, Kind::Escape));
            j = end;
            continue;
        }
        j += 1;
    }
    None
}

/// The number at `i`, a digit no word goes on to: `42`, `3.14`, `1e-9`,
/// `0xff`, `1_000`, or dotted, as a version or an address (`1.2.3`). Puts
/// its span in `spans`, but not of a unit after it (`10px`, `2nd`), and
/// none for what only starts with digits, as a hash does (`3f2a9c`), and
/// gives where the word it's in ends.
fn number_at(line: &[u16], i: usize, spans: &mut Vec<Span>) -> usize {
    let digits = |from: usize, digit: fn(u16) -> bool| {
        let mut j = from;
        while j < line.len() && (digit(line[j]) || line[j] == UNDERSCORE) {
            j += 1;
        }
        j
    };
    let radix: Option<fn(u16) -> bool> = match at(line, i + 1) | 0x20 {
        _ if line[i] != b'0' as u16 => None,
        0x78 => Some(|u| is_digit(u) || (b'a' as u16..=b'f' as u16).contains(&(u | 0x20))),
        0x62 => Some(|u| u == b'0' as u16 || u == b'1' as u16),
        0x6f => Some(|u| (b'0' as u16..=b'7' as u16).contains(&u)),
        _ => None,
    };
    let mut end = match radix {
        Some(digit) if digit(at(line, i + 2)) => digits(i + 2, digit),
        _ => {
            let mut end = digits(i, is_digit);
            while at(line, end) == DOT && is_digit(at(line, end + 1)) {
                end = digits(end + 1, is_digit);
            }
            if at(line, end) | 0x20 == b'e' as u16 {
                let from = end + 1 + usize::from(is_any(at(line, end + 1), b"+-"));
                if is_digit(at(line, from)) {
                    end = digits(from, is_digit);
                }
            }
            end
        }
    };
    let number = end;
    let mut unit = true;
    while let Some(c) = char_at(line, end).filter(|&c| is_word(Some(c))) {
        unit &= c.is_ascii_alphabetic();
        end += c.len_utf16();
    }
    if unit {
        spans.push(span(i, number, Kind::Number));
    }
    end
}

/// The URL or path in `line` (as `spans` colors it) with the character at
/// `at` in it, if any: what gf, gx and a click with Cmd open (see link.rs).
pub fn link_at(line: &[u16], at: usize) -> Option<Span> {
    colored_links(line).find(|s| s.start <= at && at < s.end)
}

/// The first URL or path in `line`, as `link_at` finds them.
pub fn first_link(line: &[u16]) -> Option<Span> {
    colored_links(line).next()
}

/// The URLs and paths in the part of `line` that's colored.
fn colored_links(line: &[u16]) -> impl Iterator<Item = Span> {
    let mut spans = Vec::new();
    links(&line[..line.len().min(MAX_LENGTH)], &mut spans);
    spans.into_iter()
}

/// The URLs and paths in `line`, which go over whatever they're in.
fn links(line: &[u16], spans: &mut Vec<Span>) {
    let mut i = 0;
    while i < line.len() {
        if let Some(end) = url_at(line, i) {
            spans.push(span(i, end, Kind::Url));
            i = end;
        } else if let Some(end) = path_at(line, i) {
            spans.push(span(i, end, Kind::Path));
            i = end;
        } else {
            i += 1;
        }
    }
}

/// Whether `c` can't be in a URL or a path, and ends one: a blank, or a
/// quote (also a typographic one).
fn ends_link(c: char) -> bool {
    c.is_whitespace() || matches!(c, '"' | '\'' | '`' | '“' | '”' | '‘' | '’' | '«' | '»')
}

/// `end` less what ends a sentence rather than the URL or path from
/// `from` (`.`, `,`, a `)` it didn't open), but not less than `from`.
fn trim_end(line: &[u16], from: usize, mut end: usize, also: &str) -> usize {
    let count = |part: &[u16], u: u8| part.iter().filter(|&&v| v == u as u16).count();
    while end > from {
        let part = &line[from..end];
        let u = line[end - 1];
        let unopened =
            |open: u8, close: u8| u == close as u16 && count(part, close) > count(part, open);
        let trailing = is_any(u, b".,:;!?") || is_any(u, also.as_bytes());
        if trailing || unopened(b'(', b')') || unopened(b'[', b']') {
            end -= 1;
        } else {
            break;
        }
    }
    end
}

/// The URL at `i`, if one starts there: a scheme and `://` (`https://…`,
/// `file:///…`), or `www.`. Gives its end.
fn url_at(line: &[u16], i: usize) -> Option<usize> {
    if !is_letter(line[i]) || is_word(char_before(line, i)) {
        return None;
    }
    let mut j = i + 1;
    while is_letter(at(line, j)) || is_digit(at(line, j)) || is_any(at(line, j), b"+-.") {
        j += 1;
    }
    let from = if starts_with(line, j, "://") {
        j + 3
    } else if starts_with(line, i, "www.") {
        i + 4
    } else {
        return None;
    };
    let mut end = from;
    while let Some(c) = char_at(line, end)
        .filter(|&c| !ends_link(c) && !matches!(c, '<' | '>' | '\\' | '^' | '{' | '}' | '|'))
    {
        end += c.len_utf16();
    }
    let end = trim_end(line, from, end, "*");
    (end > from).then_some(end)
}

/// Whether a path can start after `c`: first in the line, after a blank or
/// a quote, a bracket, `=` (`--dir=/tmp`), `:` (`$PATH`'s parts) or `>`
/// (`2>/dev/null`), which a path doesn't go on through.
fn starts_path_after(c: Option<char>) -> bool {
    c.is_none_or(|c| ends_link(c) || matches!(c, '(' | '[' | '{' | '=' | ':' | ',' | '>'))
}

/// Whether `c` can be in a path, after its start.
fn in_path(c: char) -> bool {
    !ends_link(c)
        && !matches!(
            c,
            '<' | '>'
                | '|'
                | ';'
                | ','
                | '('
                | ')'
                | '['
                | ']'
                | '{'
                | '}'
                | ':'
                | '='
                | '#'
                | '\\'
        )
}

/// Whether `c` can start a path's name: not `/` (`//` starts a comment),
/// `*` (`/*` does) or a blank (a division).
fn starts_name(c: Option<char>) -> bool {
    c.is_some_and(|c| {
        c.is_alphanumeric() || matches!(c, '.' | '_' | '-' | '~' | '$' | '@' | '%' | '+')
    })
}

/// The path at `i`, if one starts there: `/absolute`, `~/home`, `./here`,
/// `../there`, `C:\drive` (where `\` separates names too), or else one
/// that looks like a path (see `looks_relative`). A `\` before a space
/// escapes it, as in a shell. Gives its end.
fn path_at(line: &[u16], i: usize) -> Option<usize> {
    if !starts_path_after(char_before(line, i)) {
        return None;
    }
    let separator = |j: usize| at(line, j) == SLASH || at(line, j) == BACKSLASH;
    let u = line[i];
    let prefix = if u == SLASH {
        starts_name(char_at(line, i + 1)).then_some(1)
    } else if (u == TILDE || u == DOT) && separator(i + 1) {
        Some(2)
    } else if separator(i + 2)
        && (u == DOT && at(line, i + 1) == DOT || is_letter(u) && at(line, i + 1) == COLON)
    {
        Some(3)
    } else if starts_name(char_at(line, i)) && u != b'-' as u16 && u != TILDE {
        Some(0)
    } else {
        None
    }?;
    let backslashes = prefix > 0 && at(line, i + prefix - 1) == BACKSLASH;
    let mut end = i + prefix;
    loop {
        match char_at(line, end) {
            Some('\\') if at(line, end + 1) == SPACE => end += 2,
            Some('\\') if backslashes => end += 1,
            Some(c) if in_path(c) => end += c.len_utf16(),
            _ => break,
        }
    }
    let end = trim_end(line, i + prefix, end, "");
    (prefix > 0 || looks_relative(&line[i..end])).then_some(end)
}

/// Whether `token`, with no `/`, `~/`, `./` or drive before it, is a path
/// (`src/main.rs`, `docs/`, `a/b/c`) rather than words with a `/`
/// (`and/or`, `km/h`, `w/`) or a division (`1/2`, `a//b`): one with a
/// letter and a `/` (but no `//`), and either two of them, one at its end
/// after a name of two characters or more, or a last name with an
/// extension.
fn looks_relative(token: &[u16]) -> bool {
    let Some(last) = token.iter().rposition(|&u| u == SLASH) else {
        return false;
    };
    if token.windows(2).any(|w| w == [SLASH, SLASH])
        || !token.iter().any(|&u| is_letter(u) || u >= 0x80)
    {
        return false;
    }
    let slashes = token.iter().filter(|&&u| u == SLASH).count();
    if slashes >= 2 {
        return true;
    }
    if last == token.len() - 1 {
        return last >= 2;
    }
    let name = &token[last + 1..];
    name.iter().rposition(|&u| u == DOT).is_some_and(|dot| {
        let extension = &name[dot + 1..];
        extension.first().is_some_and(|&u| is_letter(u))
            && extension.iter().all(|&u| is_letter(u) || is_digit(u))
    })
}
