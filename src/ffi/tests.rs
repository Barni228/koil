use cxx_qt_lib::{QString, QStringList};

use super::*;

/// The numbers `regex_matches` gives for every match of `pattern` in `text`.
fn matches(text: &str, pattern: &str, flags: &str) -> Vec<i32> {
    matches_in(text, pattern, flags, 0, i32::MAX, i32::MAX, false)
}

fn matches_in(
    text: &str,
    pattern: &str,
    flags: &str,
    from: i32,
    to: i32,
    limit: i32,
    per_line: bool,
) -> Vec<i32> {
    let flags = format!("{flags}{}", if per_line { "l" } else { "" });
    let (text, pattern, flags) = (
        QString::from(text),
        QString::from(pattern),
        QString::from(&flags),
    );
    numbers(&regex_matches(&text, &pattern, &flags, from, to, limit))
}

/// The 32-bit numbers `bytes` are.
fn numbers(bytes: &cxx_qt_lib::QByteArray) -> Vec<i32> {
    let bytes = bytes.as_slice().chunks_exact(4);
    bytes
        .map(|n| i32::from_ne_bytes(n.try_into().unwrap()))
        .collect()
}

fn before(text: &str, pattern: &str, at: i32) -> Vec<i32> {
    let found = regex_before(
        &QString::from(text),
        &QString::from(pattern),
        &QString::from(""),
        at,
    );
    found.iter().copied().collect()
}

fn error(pattern: &str) -> String {
    regex_error(&QString::from(pattern), &QString::from("")).to_string()
}

#[test]
fn regex_looks_around() {
    // what QML's RegExp can't: a look behind
    assert_eq!(vec![2, 7, 10], matches("foobar bar", "(?<!foo)bar", ""));
    assert_eq!(vec![2, 1, 2, 4, 5], matches("ab cb ac", "(?<=[ac])b", ""));
    // one of a few lengths, but not of any length
    assert_eq!(vec![2, 3, 4], matches("abcx x", "(?<=ab|c)x", ""));
    assert_ne!("", error("(?<=a+)x"));
    assert_eq!(vec![2, 0, 1], matches("ab", "a(?=b)", ""));
    assert_eq!(vec![2, 3, 4], matches("ab ac", "a(?!b)", ""));
}

#[test]
fn regex_syntax() {
    // flags in the pattern, possessive and atomic, a class of a script
    assert_eq!(vec![2, 0, 1], matches("A", "(?i)a", ""));
    assert_eq!(Vec::<i32>::new(), matches("aaa", "a++a", "")[1..].to_vec());
    assert_eq!(
        Vec::<i32>::new(),
        matches("aaa", "(?>a+)a", "")[1..].to_vec()
    );
    assert_eq!(vec![2, 0, 2], matches("éa1", r"\p{L}+", ""));
    // \K: the match starts after it
    assert_eq!(vec![2, 3, 6], matches("foobar", r"foo\Kbar", ""));
    // a group again, by number and by name
    assert_eq!(vec![4, 0, 4, 0, 2], matches("abab abcd", r"(\w\w)\1", ""));
    assert_eq!(vec![4, 0, 2, 0, 1], matches("aa ab", r"(?<x>\w)\k<x>", ""));
    assert_eq!("", error(r"(?<x>\w)\k<x>"));
    assert_ne!("", error("(a"));
    assert_eq!(Vec::<i32>::new(), matches("a", "(a", ""));
}

#[test]
fn regex_options() {
    // case counts unless `i` says
    assert_eq!(vec![2, 2, 3], matches("AbaB", "a", ""));
    assert_eq!(vec![2, 0, 1, 2, 3], matches("AbaB", "a", "i"));
    assert_eq!(vec![2, 0, 1], matches("É", "é", "i"));
    // ^ and $ are a line's, and . isn't a line break
    assert_eq!(vec![2, 0, 1, 2, 3], matches("a\nb", "^.$", ""));
    assert_eq!(vec![2, 0, 1, 2, 3], matches("a\nb", ".+", ""));
    // \w, \d and \b know more than ASCII
    assert_eq!(vec![2, 0, 3], matches("été", r"\b\w+\b", ""));
    assert_eq!(vec![2, 0, 1], matches("٣", r"\d", ""));
    // . is a whole character, not half an emoji
    assert_eq!(vec![2, 0, 2, 2, 3], matches("😀a", ".", ""));
}

#[test]
fn regex_groups() {
    // a group that took no part is -1
    assert_eq!(
        vec![6, 0, 1, 0, 1, -1, -1, 1, 2, -1, -1, 1, 2],
        matches("ab", "(a)|(b)", "")
    );
    let names = regex_group_names(
        &QString::from(r"(?<year>\d+)-(\d+)-(?<day>\d+)"),
        &QString::from(""),
    );
    let mut expected = QStringList::default();
    for name in ["", "year", "", "day"] {
        expected.append(QString::from(name));
    }
    assert_eq!(expected, names);
}

#[test]
fn regex_matches_of_nothing() {
    // the next is looked for a whole character on
    assert_eq!(vec![2, 0, 0, 1, 2, 2, 2], matches("ax", "x*", ""));
    assert_eq!(vec![2, 0, 0, 2, 2, 3, 3], matches("😀a", "", ""));
    assert_eq!(vec![2, 0, 0], matches("", "^", ""));
}

#[test]
fn regex_range() {
    let text = "a a\na a\na";
    assert_eq!(
        vec![2, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
        matches(text, "a", "")
    );
    // those that start from `from` up to `to`
    assert_eq!(
        vec![2, 2, 3, 4, 5],
        matches_in(text, "a", "", 1, 4, i32::MAX, false)
    );
    assert_eq!(
        vec![2, 0, 1, 2, 3],
        matches_in(text, "a", "", 0, 99, 2, false)
    );
    // the first on each line
    assert_eq!(
        vec![2, 0, 1, 4, 5, 8, 9],
        matches_in(text, "a", "", 0, 99, 99, true)
    );
    // one that goes over lines: the next is looked for after it
    assert_eq!(
        vec![2, 0, 5, 6, 9],
        matches_in(text, r"a a\na|a\na", "", 0, 99, 99, true)
    );
    // from inside a character (an emoji is two long), it's from the next
    assert_eq!(
        vec![2, 2, 3, 3, 5],
        matches_in("😀a😀", "a|😀", "", 1, 99, 99, false)
    );
    // a look behind sees what's before `from`
    assert_eq!(
        vec![2, 3, 4],
        matches_in("ab b", "(?<= )b", "", 1, 99, 99, false)
    );
    assert_eq!(
        vec![2, 3, 4],
        matches_in("ab\nb", "^b", "", 1, 99, 99, false)
    );
}

#[test]
fn regex_search_backwards() {
    let text = "a b a b a";
    // the last before, and the last of all only without one
    assert_eq!(vec![4, 4], before(text, "a", 8));
    assert_eq!(vec![0, 0], before(text, "a", 4));
    assert_eq!(vec![-1, 8], before(text, "a", 0));
    assert_eq!(vec![-1, -1], before(text, "x", 4));
    assert_eq!(vec![-1, -1], before(text, "(", 4));
    assert_eq!(vec![6, 6], before(text, "(?<=a )b|$", 9));
}

/// A pattern that tries every way to split the text gives up (PCRE2's
/// match limit) as no match, where QML's RegExp went on for good.
#[test]
fn regex_gives_up() {
    let started = std::time::Instant::now();
    for (pattern, text) in [
        (r"^(\w+\s?)*$", format!("{}!", "a ".repeat(40))),
        (r"(a|aa)+(?<!a)$", "a".repeat(60)),
        (r"^(a+)+$", format!("{}!", "a".repeat(60))),
    ] {
        assert_eq!(vec![4], matches(&text, pattern, ""), "{pattern}");
    }
    assert!(started.elapsed().as_secs() < 5);
}

/// Half a surrogate pair, which PCRE2 can't read: no matches, as with a
/// pattern that isn't one.
#[test]
fn regex_not_utf16() {
    // an `a` and the first half of the emoji
    let text = QString::from("a😀").left(2);
    let found = regex_matches(&text, &QString::from("a"), &QString::from(""), 0, 99, 99);
    assert_eq!(vec![2], numbers(&found));
    let found = regex_before(&text, &QString::from("a"), &QString::from(""), 2);
    assert_eq!(vec![-1, -1], found.iter().copied().collect::<Vec<i32>>());
}
