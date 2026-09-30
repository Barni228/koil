use std::fs;

use koil_core::{Entry, Koil, Settings};
use tempfile::TempDir;

use super::*;

/// A temp dir with `dir/`, `.hidden`, `file.rs` and `notes`, and a Koil that
/// has it open.
fn koil() -> (TempDir, Koil) {
    let temp = tempfile::tempdir().unwrap();
    fs::create_dir(temp.path().join("dir")).unwrap();
    for name in [".hidden", "file.rs", "notes"] {
        fs::write(temp.path().join(name), "").unwrap();
    }
    let mut koil = Koil::default();
    koil.open(temp.path()).unwrap();
    (temp, koil)
}

/// The rendered listing with each line changed by `edit`, which gets the
/// line's name ("" for the first two) and returns the new line, or `None` to
/// remove it. The hidden texts stay with their lines.
fn edited(
    rendered: &Rendered,
    edit: impl Fn(&str, &str) -> Option<String>,
) -> (String, Vec<Hidden>) {
    let mut text = String::new();
    let mut hidden = Vec::new();
    let mut old_at = 0;
    for (line, name) in rendered.text.split('\n').zip(&rendered.names) {
        if let Some(new) = edit(line, name) {
            if !text.is_empty() {
                text.push('\n');
            }
            // An icon keeps its hidden text if the line still starts with it.
            if let Some(h) = rendered.hidden.iter().find(|h| h.at == old_at)
                && new.starts_with(&h.icon)
            {
                hidden.push(Hidden {
                    at: utf16_len(&text),
                    ..h.clone()
                });
            }
            text.push_str(&new);
        }
        old_at += utf16_len(line) + 1;
    }
    (text, hidden)
}

fn update_listing(koil: &mut Koil, text: &str, hidden: &[Hidden]) -> Updated {
    let settings = koil.settings().clone();
    update(koil, text, hidden, &settings, None)
}

#[test]
fn test_render() {
    let (_temp, koil) = koil();
    let rendered = render(&koil);
    let lines: Vec<&str> = rendered.text.split('\n').collect();
    let location = show_path(koil.current_dir());
    assert_eq!(lines[0], location);
    assert_eq!(lines[1], "=".repeat(location.chars().count().max(42)));
    assert_eq!(rendered.names, ["", "", "dir/", "file.rs", "notes"]);
    // dirs first, each line an icon, two spaces and the name
    for (line, name) in lines.iter().zip(&rendered.names).skip(2) {
        let icon = line.chars().next().unwrap();
        assert!(is_private_use(icon), "{line}");
        assert_eq!(&line[icon.len_utf8()..], format!("  {name}"));
    }
    // each icon hides its entry's ID
    assert_eq!(rendered.hidden.len(), 3);
    for (h, entry) in rendered.hidden.iter().zip(koil.listing()) {
        let utf16: Vec<u16> = rendered.text.encode_utf16().collect();
        let icon: Vec<u16> = h.icon.encode_utf16().collect();
        assert_eq!(&utf16[h.at..h.at + icon.len()], icon.as_slice());
        assert_eq!(h.text, entry.id.unwrap().0.to_string());
    }
    assert_eq!(rendered.colors.len(), 3);
}

#[test]
fn test_parse_rendered() {
    let (_temp, koil) = koil();
    let rendered = render(&koil);
    let parsed = parse(&rendered.text, &rendered.hidden);
    assert_eq!(parsed.problems, []);
    assert_eq!(parsed.location, show_path(koil.current_dir()));
    assert_eq!(parsed.entries, koil.listing());
    // the names start after the icon and two spaces
    assert_eq!(parsed.spots, [(2, 3), (3, 3), (4, 3)]);
}

#[test]
fn test_parse_new_entries() {
    let text = "/dir\n===\n  new.txt  \n\n\u{f016}  icon but no ID\nsub/dir/\n../";
    let parsed = parse(text, &[]);
    assert_eq!(parsed.problems, []);
    let new = |name: &str, is_dir| Entry {
        id: None,
        name: name.into(),
        is_dir,
    };
    assert_eq!(
        parsed.entries,
        [
            new("new.txt", false),
            new("icon but no ID", false),
            new("sub/dir", true),
            Entry::parent()
        ]
    );
    assert_eq!(parsed.spots, [(2, 2), (4, 3), (5, 0), (6, 0)]);
}

#[test]
fn test_parse_header_problems() {
    let lines = |text: &str| -> Vec<(usize, String)> {
        let parsed = parse(text, &[]);
        parsed
            .problems
            .into_iter()
            .map(|p| (p.line, p.message))
            .collect()
    };
    assert_eq!(
        lines("/dir\nfile"),
        [(0, "The path must be followed by a line of `=`".to_string())]
    );
    assert_eq!(
        lines("\n===\nfile"),
        [(
            1,
            "Write the path to open above the line of `=`".to_string()
        )]
    );
    assert_eq!(
        lines("/a\n/b\n===\nfile"),
        [(
            1,
            "Only one path can be written above the line of `=`".to_string()
        )]
    );
}

#[test]
fn test_parse_not_an_id() {
    let hidden = [Hidden {
        at: 9,
        icon: "\u{f016}".into(),
        text: "Poppy".into(),
    }];
    let parsed = parse("/dir\n===\n\u{f016}  file", &hidden);
    assert_eq!(parsed.problems[0].line, 2);
    assert_eq!(
        parsed.problems[0].message,
        "The icon hides `Poppy`, which isn't an ID"
    );
    assert_eq!(parsed.entries, []);
}

#[test]
fn test_update_actions() {
    let (_temp, mut koil) = koil();
    let rendered = render(&koil);
    let (text, hidden) = edited(&rendered, |line, name| match name {
        "file.rs" => Some(line.replace("file.rs", "main.rs")),
        "notes" => None,
        "dir/" => Some(format!("{line}\nnew/inside.txt")),
        _ => Some(line.to_string()),
    });
    let updated = update_listing(&mut koil, &text, &hidden);
    assert!(updated.ok, "{updated:?}");
    assert!(!updated.moved);
    let mut actions = actions(&koil);
    actions.sort();
    assert_eq!(
        actions,
        [
            "CREATE new/",
            "CREATE new/inside.txt",
            "DELETE notes",
            "MOVE   file.rs -> main.rs"
        ]
    );
    // the listing shows the changes, and reads back the same
    let rendered = render(&koil);
    assert_eq!(rendered.names, ["", "", "dir/", "main.rs", "new/"]);
    let parsed = parse(&rendered.text, &rendered.hidden);
    assert_eq!(parsed.entries, koil.listing());
}

#[test]
fn test_update_errors() {
    let (_temp, mut koil) = koil();
    let rendered = render(&koil);
    let (text, hidden) = edited(&rendered, |line, name| match name {
        "file.rs" => Some(line.replace("file.rs", "notes")),
        _ => Some(line.to_string()),
    });
    let before = koil.compute_actions();
    let updated = update_listing(&mut koil, &text, &hidden);
    assert!(!updated.ok);
    assert_eq!(koil.compute_actions(), before);
    let problems: Vec<(usize, usize, Severity, &str)> = updated
        .problems
        .iter()
        .map(|p| (p.line, p.column, p.severity, p.message.as_str()))
        .collect();
    assert_eq!(
        problems,
        [(
            4,
            3,
            Severity::Error,
            "`notes` appears more than once, first on line 4"
        )]
    );
    assert_eq!(updated.message, problems[0].3);
    // check says the same, without changing anything
    assert_eq!(check(&koil, &text, &hidden), updated.problems);
}

#[test]
fn test_check_warnings() {
    let (_temp, koil) = koil();
    let text = format!("{}\n-dash", render(&koil).text);
    let problems = check(&koil, &text, &render(&koil).hidden);
    assert_eq!(problems.len(), 1);
    assert_eq!(problems[0].line, 5);
    assert_eq!(problems[0].severity, Severity::Warning);
}

#[test]
fn test_navigate() {
    let (temp, mut koil) = koil();
    let root = koil.current_dir().to_path_buf();
    let settings = Settings::default();
    let rendered = render(&koil);

    // Enter on a dir
    let target =
        |koil: &Koil, text: &str, hidden: &[Hidden], line| target_on_line(koil, text, hidden, line);
    assert_eq!(
        target(&koil, &rendered.text, &rendered.hidden, 2),
        Some(Target::Dir("dir".into()))
    );
    let updated = update(
        &mut koil,
        &rendered.text,
        &rendered.hidden,
        &settings,
        Some("dir"),
    );
    assert!(updated.ok && updated.moved, "{updated:?}");
    assert_eq!(koil.current_dir(), root.join("dir"));

    assert_eq!(updated.from, "");

    // `-`, which comes from `dir/`
    let rendered = render(&koil);
    let updated = update(
        &mut koil,
        &rendered.text,
        &rendered.hidden,
        &settings,
        Some(".."),
    );
    assert!(updated.ok && updated.moved);
    assert_eq!(koil.current_dir(), root);
    assert_eq!(updated.from, "dir/");

    // a changed path on the first line
    let rendered = render(&koil);
    let text = rendered
        .text
        .replacen(&show_path(&root), &show_path(&temp.path().join("dir")), 1);
    let updated = update(&mut koil, &text, &rendered.hidden, &settings, None);
    assert!(updated.ok && updated.moved);
    assert_eq!(koil.current_dir(), root.join("dir"));

    // one that can't be opened
    let rendered = render(&koil);
    let text = rendered
        .text
        .replacen(&show_path(koil.current_dir()), "[", 1);
    let updated = update(&mut koil, &text, &rendered.hidden, &settings, None);
    assert!(!updated.ok);
    assert_eq!(updated.problems[0].line, 0);
    assert_eq!(koil.current_dir(), root.join("dir"));
}

#[test]
fn test_target_on_line() {
    let (_temp, koil) = koil();
    let root = koil.current_dir().to_path_buf();
    let rendered = render(&koil);
    // file.rs renamed on its line, and a new file
    let (text, hidden) = edited(&rendered, |line, name| match name {
        "file.rs" => Some(format!("{}\nnew.txt", line.replace("file.rs", "main.rs"))),
        _ => Some(line.to_string()),
    });
    let target = |line| target_on_line(&koil, &text, &hidden, line);
    assert_eq!(target(0), None);
    assert_eq!(target(1), None);
    assert_eq!(target(2), Some(Target::Dir("dir".into())));
    assert_eq!(
        target(3),
        Some(Target::File {
            path: root.join("file.rs"),
            name: "main.rs".into()
        })
    );
    assert_eq!(target(4), Some(Target::New("new.txt".into())));
    // `..`, and a dir whose `/` was taken off
    let text = format!("/\n===\n../\n{}dir", rendered.hidden[0].icon);
    let hidden = [Hidden {
        at: 10,
        ..rendered.hidden[0].clone()
    }];
    assert_eq!(
        target_on_line(&koil, &text, &hidden, 2),
        Some(Target::Dir("..".into()))
    );
    assert_eq!(
        target_on_line(&koil, &text, &hidden, 3),
        Some(Target::Dir("dir".into()))
    );
}

#[test]
fn test_settings() {
    let (_temp, mut koil) = koil();
    let rendered = render(&koil);
    let settings = Settings {
        show_hidden: true,
        ..Settings::default()
    };
    let updated = update(&mut koil, &rendered.text, &rendered.hidden, &settings, None);
    assert!(updated.ok && updated.moved);
    assert_eq!(
        render(&koil).names,
        ["", "", "../", "dir/", ".hidden", "file.rs", "notes"]
    );

    // regex changes how the path is read, not what's shown
    let rendered = render(&koil);
    let settings = Settings {
        regex: true,
        ..settings
    };
    let updated = update(&mut koil, &rendered.text, &rendered.hidden, &settings, None);
    assert!(updated.ok && !updated.moved);
    assert!(koil.settings().regex);
}

#[test]
fn test_home() {
    let Some(home) = std::env::home_dir() else {
        return;
    };
    assert_eq!(show_path(&home), "~");
    assert_eq!(show_path(&home.join("a")), format!("~{MAIN_SEPARATOR}a"));
    assert_eq!(expand_home("~"), home);
    assert_eq!(expand_home("~/a"), home.join("a"));
    assert_eq!(expand_home("/~/a"), PathBuf::from("/~/a"));
}

/// The parts of `regex` as (text, kind).
fn parts(regex: &str) -> Vec<(&str, &str)> {
    let parts = regex_parts(regex).into_iter();
    parts.map(|(s, e, kind)| (&regex[s..e], kind)).collect()
}

#[test]
fn test_regex_parts() {
    assert_eq!(
        parts(r"src/.*\.rs"),
        [(".", "anchor"), ("*", "quantifier"), (r"\.", "escape")]
    );
    assert_eq!(
        parts("(?:a|b)+?[^]x[:digit:]]{2,3}z{x},^$"),
        [
            ("(?:", "group"),
            ("|", "group"),
            (")", "group"),
            ("+?", "quantifier"),
            ("[^]x[:digit:]]", "class"),
            ("{2,3}", "quantifier"),
            (",", "anchor"),
            ("^", "anchor"),
            ("$", "anchor")
        ]
    );
    // unfinished, as it is while it's typed
    assert_eq!(parts(r"(?P<n[a\"), [("(?P<n[a\\", "group")]);
}

#[test]
fn test_path_syntax() {
    let (_temp, koil) = koil();
    let dir = show_path(koil.current_dir());
    let spans = |line: &str, regex| -> Vec<(String, &str)> {
        let utf16: Vec<u16> = line.encode_utf16().collect();
        let spans = path_syntax(&koil, line, regex).into_iter();
        let text = |s: &Span| String::from_utf16(&utf16[s.start..s.start + s.length]).unwrap();
        spans.map(|s| (text(&s), s.kind)).collect()
    };
    // after the dirs, from the first part with a special character (`x`
    // isn't a dir, but it's plain, so the regex is in it)
    let line = format!("  {dir}/dir/x/.+\\.rs");
    assert_eq!(
        spans(&line, true),
        [
            (".+\\.rs".to_string(), "pattern"),
            (".".to_string(), "anchor"),
            ("+".to_string(), "quantifier"),
            ("\\.".to_string(), "escape")
        ]
    );
    // only when it's read as a regex
    assert_eq!(spans(&line, false), []);
    // a dir, even with a special character, and the path that's open
    assert_eq!(spans(&dir, true), []);
    assert_eq!(spans("dir", true), []);
}
