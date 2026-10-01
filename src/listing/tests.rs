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
/// line's name and returns the new line, or `None` to remove it. The hidden
/// texts stay with their lines.
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

/// Updates with the path that's open.
fn update_listing(koil: &mut Koil, text: &str, hidden: &[Hidden]) -> Updated {
    let settings = koil.settings().clone();
    let path = show_path(&koil.location());
    update(koil, &path, text, hidden, &settings, None)
}

#[test]
fn test_render() {
    let (_temp, koil) = koil();
    let rendered = render(&koil);
    let lines: Vec<&str> = rendered.text.split('\n').collect();
    assert_eq!(rendered.path, show_path(koil.current_dir()));
    assert_eq!(rendered.names, ["dir/", "file.rs", "notes"]);
    // dirs first, each line an icon, two spaces and the name
    assert_eq!(lines.len(), 3);
    for (line, name) in lines.iter().zip(&rendered.names) {
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
fn test_pending_color_apart() {
    // devicons' white and near-white icons, and its darkest light ones
    assert_eq!(apart("#ffffff", true), "#cccccc");
    assert_eq!(apart("#fff2f2", true), "#ccc2c2");
    assert_eq!(apart("#ffffcd", true), "#cccca4");
    assert_eq!(apart("#2f2f2f", false), "#585858");
    assert_eq!(apart("#000000", false), "#333333");
    // the rest stay
    assert_eq!(apart("#c8c8c8", true), "#c8c8c8");
    assert_eq!(apart("#ffffff", false), "#ffffff");
    assert_eq!(apart("#000000", true), "#000000");
    assert_eq!(apart("#e44d26", true), "#e44d26");
    assert_eq!(apart("not a color", true), "not a color");

    // files devicons gives white icons
    let temp = tempfile::tempdir().unwrap();
    for name in ["vercel.json", "gtkrc", "board.kicad_pcb"] {
        fs::write(temp.path().join(name), "").unwrap();
    }
    let mut koil = Koil::default();
    koil.open(temp.path()).unwrap();
    assert_eq!(icon(temp.path(), "vercel.json").1[0], "#cccccc");
    let rendered = render(&koil);
    assert_eq!(rendered.pending_color, PENDING_COLOR);
    for colors in rendered.colors.values() {
        assert_ne!(colors[0], PENDING_COLOR[0]);
        assert_ne!(colors[1], PENDING_COLOR[1]);
    }
}

#[test]
fn test_pending_lines() {
    let (_temp, mut koil) = koil();
    let rendered = render(&koil);
    assert!(pending_lines(&koil, &rendered.text, &rendered.hidden).is_empty());

    // file.rs renamed, notes copied as notes2, a new file, and `../`
    let lines: Vec<&str> = rendered.text.split('\n').collect();
    let text = [
        lines[0].to_string(),
        lines[1].replace("file.rs", "main.rs"),
        lines[2].to_string(),
        lines[2].replace("notes", "notes2"),
        "new.txt".to_string(),
        "../".to_string(),
    ]
    .join("\n");
    // Each line's icon keeps the ID of the line it came from.
    let ids = [Some(0), Some(1), Some(2), Some(2), None, None];
    let mut hidden = Vec::new();
    let mut at = 0;
    for (line, id) in text.split('\n').zip(ids) {
        if let Some(id) = id {
            hidden.push(Hidden {
                at,
                ..rendered.hidden[id].clone()
            });
        }
        at += utf16_len(line) + 1;
    }
    assert_eq!(pending_lines(&koil, &text, &hidden), [1, 3, 4]);

    // still pending once koil has read them, until they're applied
    let updated = update_listing(&mut koil, &text, &hidden);
    assert!(updated.ok, "{updated:?}");
    let rendered = render(&koil);
    let lines = pending_lines(&koil, &rendered.text, &rendered.hidden);
    let mut names: Vec<&str> = lines.iter().map(|&l| rendered.names[l].as_str()).collect();
    names.sort();
    assert_eq!(names, ["main.rs", "new.txt", "notes2"]);

    // an entry pasted into another dir is moved there
    let path = show_path(&koil.location());
    let updated = update(
        &mut koil,
        &path,
        &rendered.text,
        &rendered.hidden,
        &Settings::default(),
        Some("dir"),
    );
    assert!(updated.ok, "{updated:?}");
    let notes = rendered.names.iter().position(|n| n == "notes").unwrap();
    let line = rendered.text.split('\n').nth(notes).unwrap();
    let h = rendered
        .hidden
        .iter()
        .find(|h| h.text == hidden[2].text)
        .unwrap();
    let moved = [Hidden { at: 0, ..h.clone() }];
    assert_eq!(pending_lines(&koil, line, &moved), [0]);
}

#[test]
fn test_parse_rendered() {
    let (_temp, koil) = koil();
    let rendered = render(&koil);
    let parsed = parse(&rendered.text, &rendered.hidden);
    assert_eq!(parsed.problems, []);
    assert_eq!(parsed.entries, koil.listing());
    // the names start after the icon and two spaces
    assert_eq!(parsed.spots, [(0, 3), (1, 3), (2, 3)]);
}

#[test]
fn test_render_empty() {
    let temp = tempfile::tempdir().unwrap();
    let mut koil = Koil::default();
    koil.open(temp.path()).unwrap();
    let rendered = render(&koil);
    assert_eq!(rendered.text, "");
    assert_eq!(rendered.names, Vec::<String>::new());
    assert_eq!(parse(&rendered.text, &rendered.hidden).entries, []);
}

#[test]
fn test_parse_new_entries() {
    let text = "  new.txt  \n\n\u{f016}  icon but no ID\nsub/dir/\n../";
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
    assert_eq!(parsed.spots, [(0, 2), (2, 3), (3, 0), (4, 0)]);
}

#[test]
fn test_parse_not_an_id() {
    let hidden = [Hidden {
        at: 5,
        icon: "\u{f016}".into(),
        text: "Poppy".into(),
    }];
    let parsed = parse("new/\n\u{f016}  file", &hidden);
    assert_eq!(parsed.problems[0].line, 1);
    assert_eq!(
        parsed.problems[0].message,
        "The icon hides `Poppy`, which isn't an ID"
    );
    assert_eq!(parsed.entries.len(), 1);
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
    assert_eq!(rendered.names, ["dir/", "main.rs", "new/"]);
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
            2,
            3,
            Severity::Error,
            "`notes` appears more than once, first on line 2"
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
    assert_eq!(problems[0].line, 3);
    assert_eq!(problems[0].severity, Severity::Warning);
}

#[test]
fn test_navigate() {
    let (temp, mut koil) = koil();
    let root = koil.current_dir().to_path_buf();
    let settings = Settings::default();
    // Updates with `path` in the path field, opening `open`.
    let navigate = |koil: &mut Koil, path: &str, open| {
        let rendered = render(koil);
        update(
            koil,
            path,
            &rendered.text,
            &rendered.hidden,
            &settings,
            open,
        )
    };

    // Enter on a dir
    let rendered = render(&koil);
    assert_eq!(
        target_on_line(&koil, &rendered.text, &rendered.hidden, 0),
        Some(Target::Dir("dir".into()))
    );
    let updated = navigate(&mut koil, &rendered.path, Some("dir"));
    assert!(updated.ok && updated.moved, "{updated:?}");
    assert_eq!(koil.current_dir(), root.join("dir"));
    assert_eq!(updated.from, "");

    // `-`, which comes from `dir/`
    let path = show_path(&koil.location());
    let updated = navigate(&mut koil, &path, Some(".."));
    assert!(updated.ok && updated.moved);
    assert_eq!(koil.current_dir(), root);
    assert_eq!(updated.from, "dir/");

    // a changed path, even with spaces around it
    let path = format!("  {}  ", show_path(&temp.path().join("dir")));
    let updated = navigate(&mut koil, &path, None);
    assert!(updated.ok && updated.moved);
    assert_eq!(koil.current_dir(), root.join("dir"));

    // the same path reads the listing again, without moving
    let path = show_path(&koil.location());
    let updated = navigate(&mut koil, &path, None);
    assert!(updated.ok && !updated.moved);

    // one that can't be opened, which the path field says
    let updated = navigate(&mut koil, " [", None);
    assert!(!updated.ok);
    assert_eq!(updated.problems, []);
    assert_eq!(updated.path_problems.len(), 1);
    assert_eq!(updated.path_problems[0].column, 1);
    assert_eq!(updated.path_problems[0].message, updated.message);
    assert_eq!(koil.current_dir(), root.join("dir"));

    // one that isn't a dir, which the message names from its first part
    // that isn't one
    let cases = [
        ("missing/deeper", "missing", "does not exist"),
        ("missing/*.rs", "missing", "does not exist"),
        ("file.rs/inside", "file.rs", "is a file, not a directory"),
    ];
    for (path, part, problem) in cases {
        let updated = navigate(&mut koil, &show_path(&root.join(path)), None);
        assert!(!updated.ok, "{path}: {updated:?}");
        let part = show_path(&root.join(part));
        assert_eq!(updated.message, format!("`{part}` {problem}"));
        assert_eq!(updated.path_problems.len(), 1);
        assert_eq!(updated.path_problems[0].message, updated.message);
        assert_eq!(koil.current_dir(), root.join("dir"));
    }

    // no path at all
    let updated = navigate(&mut koil, "  ", None);
    assert!(!updated.ok);
    assert_eq!(updated.message, "Write the path to open");
    assert_eq!(updated.path_problems[0].line, 0);
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
    assert_eq!(target(0), Some(Target::Dir("dir".into())));
    assert_eq!(
        target(1),
        Some(Target::File {
            path: root.join("file.rs"),
            name: "main.rs".into()
        })
    );
    assert_eq!(target(2), Some(Target::New("new.txt".into())));
    assert_eq!(target(4), None);
    // `..`, a blank line, and a dir whose `/` was taken off
    let text = format!("../\n\n{}dir", rendered.hidden[0].icon);
    let hidden = [Hidden {
        at: 5,
        ..rendered.hidden[0].clone()
    }];
    assert_eq!(
        target_on_line(&koil, &text, &hidden, 0),
        Some(Target::Dir("..".into()))
    );
    assert_eq!(target_on_line(&koil, &text, &hidden, 1), None);
    assert_eq!(
        target_on_line(&koil, &text, &hidden, 2),
        Some(Target::Dir("dir".into()))
    );
}

#[test]
fn test_id_path() {
    let (_temp, mut koil) = koil();
    let root = koil.current_dir().to_path_buf();
    let rendered = render(&koil);
    let id = |name: &str| {
        let line = rendered.names.iter().position(|n| n == name).unwrap();
        let at: usize = rendered
            .text
            .split('\n')
            .take(line)
            .map(|l| utf16_len(l) + 1)
            .sum();
        let h = rendered.hidden.iter().find(|h| h.at == at).unwrap();
        h.text.clone()
    };
    assert_eq!(id_path(&koil, &id("dir/")), Some("dir/".into()));
    assert_eq!(id_path(&koil, &id("file.rs")), Some("file.rs".into()));
    // not an ID, or one koil doesn't know
    assert_eq!(id_path(&koil, "mushroom"), None);
    assert_eq!(id_path(&koil, "999999"), None);
    // outside the open dir: as show_path gives it
    koil.open(root.join("dir")).unwrap();
    let file = show_path(&root.join("file.rs"));
    assert_eq!(id_path(&koil, &id("file.rs")), Some(file));
}

// `g.` while the path field has a path that isn't there: the update fails,
// and koil keeps the settings the listing was shown with, so once the path
// is fixed the hidden entries the editor didn't show aren't deleted.
#[test]
fn test_failed_open_keeps_settings() {
    let (_temp, mut koil) = koil();
    let rendered = render(&koil);
    let settings = Settings {
        show_hidden: true,
        ..Settings::default()
    };
    let missing = show_path(&koil.current_dir().join("missing"));
    for path in [missing.as_str(), " [", rendered.path.as_str()] {
        let updated = update(
            &mut koil,
            path,
            &rendered.text,
            &rendered.hidden,
            &settings,
            None,
        );
        assert_eq!(updated.ok, path == rendered.path, "{path}: {updated:?}");
    }
    assert_eq!(koil.compute_actions(), []);
    assert_eq!(
        render(&koil).names,
        ["../", "dir/", ".hidden", "file.rs", "notes"]
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
    let updated = update(
        &mut koil,
        &rendered.path,
        &rendered.text,
        &rendered.hidden,
        &settings,
        None,
    );
    assert!(updated.ok && updated.moved);
    assert_eq!(
        render(&koil).names,
        ["../", "dir/", ".hidden", "file.rs", "notes"]
    );

    // regex changes how the path is read, not what's shown
    let rendered = render(&koil);
    let settings = Settings {
        regex: true,
        ..settings
    };
    let updated = update(
        &mut koil,
        &rendered.path,
        &rendered.text,
        &rendered.hidden,
        &settings,
        None,
    );
    assert!(updated.ok && !updated.moved);
    assert!(koil.settings().regex);
}

#[test]
fn test_dirs_pattern() {
    let (_temp, mut koil) = koil();
    let settings = Settings {
        regex: true,
        ..Settings::default()
    };
    // Updates with `path` in the path field.
    let navigate = |koil: &mut Koil, path: &str| {
        let rendered = render(koil);
        update(
            koil,
            path,
            &rendered.text,
            &rendered.hidden,
            &settings,
            None,
        )
    };
    let dir = render(&koil).path;

    // a pattern ending with `/` keeps it, and shows the dirs
    let path = format!("{dir}/,*/");
    let updated = navigate(&mut koil, &path);
    assert!(updated.ok && updated.moved, "{updated:?}");
    let rendered = render(&koil);
    assert_eq!(rendered.path, path);
    assert_eq!(rendered.names, ["dir/"]);
    // so the same path is what's open
    assert!(!navigate(&mut koil, &path).moved);
    assert_eq!(render(&koil).path, path);

    // without the `/`, it's another listing (the files)
    let path = format!("{dir}/,*");
    assert!(navigate(&mut koil, &path).moved);
    assert_eq!(render(&koil).path, path);
    assert_eq!(render(&koil).names, ["file.rs", "notes"]);
}

#[test]
fn test_home() {
    let Some(home) = std::env::home_dir() else {
        return;
    };
    assert_eq!(show_path(&home), "~");
    assert_eq!(show_path(&home.join("a")), format!("~{MAIN_SEPARATOR}a"));
    // a pattern's trailing `/` is kept
    assert_eq!(
        show_path(&home.join(",*/")),
        format!("~{MAIN_SEPARATOR},*/")
    );
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
