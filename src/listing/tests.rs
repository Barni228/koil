use std::fs;

use koil_core::{Entry, Koil, Settings};
use tempfile::TempDir;

use super::*;

/// The lines of what applying would do.
fn action_texts(koil: &Koil) -> Vec<String> {
    actions(koil).into_iter().map(|line| line.text).collect()
}

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
    let path = show_location(koil);
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
    let path = show_location(&koil);
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
    let mut actions = action_texts(&koil);
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
    let path = show_location(&koil);
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
    let path = show_location(&koil);
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
    assert_eq!(
        target(2),
        Some(Target::New {
            path: root.join("new.txt"),
            name: "new.txt".into()
        })
    );
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
    // with `/`, also on Windows
    assert_eq!(show_path(&home.join("a").join("b")), "~/a/b");
    // only the home dir is read, so a pattern's `\` and trailing `/` stay
    let shown = with_slashes(&home).to_string_lossy().into_owned();
    assert_eq!(with_tilde(&format!(r"{shown}/\w+/")), r"~/\w+/");
    assert_eq!(with_tilde(&format!("{shown}x")), format!("{shown}x"));
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
    // after a `/`, `\` is the regex's, also on Windows
    assert_eq!(
        spans("dir/\\w+", true),
        [
            ("\\w+".to_string(), "pattern"),
            ("\\w".to_string(), "escape"),
            ("+".to_string(), "quantifier")
        ]
    );
}

#[test]
fn test_show_location() {
    let (_temp, mut koil) = koil();
    let dir = show_path(koil.current_dir());
    let settings = Settings {
        regex: true,
        ..koil.settings().clone()
    };
    koil.set_settings(settings.clone()).unwrap();
    koil.open(r"dir/\w+").unwrap();
    // the dir, then the pattern as written
    let rendered = render(&koil);
    assert_eq!(rendered.path, format!(r"{dir}/dir/\w+"));
    // which reads as what's open, so it isn't opened again
    let (text, hidden) = (&rendered.text, &rendered.hidden);
    let updated = update(&mut koil, &rendered.path, text, hidden, &settings, None);
    assert!(updated.ok && !updated.moved, "{updated:?}");
}

#[test]
fn test_pasted_path() {
    let (temp, mut koil) = koil();
    let dir = koil.current_dir().to_path_buf();
    // a path as the OS writes it (with `\` on Windows), like a pasted one,
    // opens, and is then shown with `/`
    let pasted = dir.join("dir").display().to_string();
    let rendered = render(&koil);
    let (text, hidden) = (&rendered.text, &rendered.hidden);
    let settings = koil.settings().clone();
    let updated = update(&mut koil, &pasted, text, hidden, &settings, None);
    assert!(updated.ok && updated.moved, "{updated:?}");
    let path = render(&koil).path;
    assert_eq!(path, show_path(&dir.join("dir")));
    assert!(!path.contains('\\'), "{path}");
    // so a pattern written after it is one in that dir
    fs::write(temp.path().join("dir/a.rs"), "").unwrap();
    let location = join_shown(path, "*.rs");
    let rendered = render(&koil);
    let (text, hidden) = (&rendered.text, &rendered.hidden);
    let updated = update(&mut koil, &location, text, hidden, &settings, None);
    assert!(updated.ok && updated.moved, "{updated:?}");
    assert_eq!(koil.current_dir(), dir.join("dir"));
    assert_eq!(koil.pattern(), Some(&Pattern::Glob("*.rs".into())));
    assert_eq!(render(&koil).path, location);
}

#[test]
fn test_quoted_path() {
    let (temp, mut koil) = koil();
    fs::create_dir(temp.path().join("my dir")).unwrap();
    fs::write(temp.path().join("my dir/a.rs"), "").unwrap();
    let settings = koil.settings().clone();
    let dir = show_path(koil.current_dir());
    let mut paths = vec![
        format!(r#""{dir}/my dir""#),
        format!("'{dir}/my dir'"),
        format!(r#"{dir}/"my dir""#),
    ];
    if cfg!(not(windows)) {
        paths.push(format!(r"{dir}/my\ dir"));
    }
    for path in paths {
        let mut koil = koil.clone();
        // a path as a terminal writes it opens, and is then shown as it is
        let rendered = render(&koil);
        let (text, hidden) = (&rendered.text, &rendered.hidden);
        let updated = update(&mut koil, &path, text, hidden, &settings, None);
        assert!(updated.ok && updated.moved, "{path}: {updated:?}");
        assert_eq!(render(&koil).path, format!("{dir}/my dir"), "{path}");
    }
    // also with a pattern after it
    let path = format!(r#""{dir}/my dir"/*.rs"#);
    let rendered = render(&koil);
    let (text, hidden) = (&rendered.text, &rendered.hidden);
    let updated = update(&mut koil, &path, text, hidden, &settings, None);
    assert!(updated.ok && updated.moved, "{updated:?}");
    assert_eq!(render(&koil).path, format!("{dir}/my dir/*.rs"));
    assert_eq!(render(&koil).names, ["a.rs"]);
}

#[test]
fn test_quoted_path_syntax() {
    let (temp, koil) = koil();
    fs::create_dir(temp.path().join("my dir")).unwrap();
    let dir = show_path(koil.current_dir());
    let pattern = |line: &str| -> Vec<String> {
        let utf16: Vec<u16> = line.encode_utf16().collect();
        let spans = path_syntax(&koil, line, true).into_iter();
        let text = |s: &Span| String::from_utf16(&utf16[s.start..s.start + s.length]).unwrap();
        spans
            .filter(|s| s.kind == "pattern")
            .map(|s| text(&s))
            .collect()
    };
    // a quoted name isn't a regex, even with a `.` in it, and if it isn't
    // there
    assert_eq!(pattern(&format!(r#"{dir}/"my.dir"/.+"#)), [".+"]);
    assert_eq!(pattern(&format!("{dir}/my.dir/.+")), ["my.dir/.+"]);
    assert_eq!(pattern(&format!(r#"{dir}/"my dir"/.+"#)), [".+"]);
    assert_eq!(pattern(r#""my dir"/.+"#), [".+"]);
    assert_eq!(pattern(r#""my dir/x"/.+"#), [".+"]);
    assert_eq!(pattern(r#""my dir"/"x"."#), [r#""x"."#]);
    assert_eq!(pattern(r#""my dir""#), Vec::<String>::new());
    // after the home dir, which isn't a regex either
    if std::env::home_dir().is_some() {
        assert_eq!(pattern("~/.+"), [".+"]);
        assert_eq!(pattern(r#""~"/.+"#), [".+"]);
    }
    if cfg!(not(windows)) {
        assert_eq!(pattern(&format!(r"{dir}/my\ dir/.+")), [".+"]);
        assert_eq!(pattern(r"my\.dir/.+"), [".+"]);
    }
}

#[test]
fn test_home_path() {
    let (_temp, mut koil) = koil();
    if std::env::home_dir().is_none() {
        return;
    }
    let settings = koil.settings().clone();
    // `~` opens the home dir, also in quotes, like a pasted path
    for path in ["~", r#""~""#, "'~/'"] {
        let mut koil = koil.clone();
        let rendered = render(&koil);
        let (text, hidden) = (&rendered.text, &rendered.hidden);
        let updated = update(&mut koil, path, text, hidden, &settings, None);
        assert!(updated.ok && updated.moved, "{path}: {updated:?}");
        assert_eq!(render(&koil).path, "~", "{path}");
    }
    // but not after the start, where it's a name
    let rendered = render(&koil);
    let (text, hidden) = (&rendered.text, &rendered.hidden);
    let updated = update(&mut koil, "dir/~", text, hidden, &settings, None);
    assert!(!updated.ok);
    assert!(
        updated.message.ends_with("/dir/~` does not exist"),
        "{updated:?}"
    );
}

/// What Tab completes in the path field `line`, at its end, in a temp dir
/// with `src/`, `src-old/`, `Abc/`, `aBd/`, `🍄/sub/` and the file `script`:
/// where the options start, what it fills in, and the options.
fn completed(line: &str) -> (usize, String, Vec<String>) {
    let temp = tempfile::tempdir().unwrap();
    for dir in ["src", "src-old", "Abc", "aBd", "🍄/sub"] {
        fs::create_dir_all(temp.path().join(dir)).unwrap();
    }
    fs::write(temp.path().join("script"), "").unwrap();
    let mut koil = Koil::default();
    koil.open(temp.path()).unwrap();
    let cursor = utf16_len(line);
    let c = complete(&koil, line, cursor, &Settings::default());
    for option in &c.options {
        assert!(option.icon.chars().all(is_private_use), "{}", option.icon);
    }
    let names = c.options.into_iter().map(|o| o.name).collect();
    (c.start, c.fill, names)
}

#[test]
fn test_complete() {
    let fill = |line| completed(line).1;
    // the only option, or what all of them start with
    assert_eq!(fill("src-"), "src-old/");
    assert_eq!(fill("s"), "src");
    // else nothing, and Tab shows them
    assert_eq!(
        completed("src"),
        (0, String::new(), vec!["src/".into(), "src-old/".into()])
    );
    // nor when the options only match ignoring case, and share less than
    // what's written
    assert_eq!(
        completed("ab"),
        (0, String::new(), vec!["Abc/".into(), "aBd/".into()])
    );
    assert_eq!(fill("abc"), "Abc/");
    // after the spaces before the path, and in UTF-16
    assert_eq!(
        completed("  src-"),
        (2, "src-old/".into(), vec!["src-old/".into()])
    );
    assert_eq!(completed("🍄/"), (3, "sub/".into(), vec!["sub/".into()]));
    assert_eq!(completed("script/"), (0, String::new(), vec![]));
}

#[test]
fn test_complete_at_cursor() {
    let (_temp, koil) = koil();
    // only what's before the cursor
    let c = complete(&koil, "di/x", 2, &Settings::default());
    assert_eq!((c.start, c.fill.as_str()), (0, "dir/"));
    // and past the line's end, all of it
    let c = complete(&koil, "d", 5, &Settings::default());
    assert_eq!(c.fill, "dir/");
}

#[test]
fn test_shared_start() {
    let names = |names: &[&str]| names.iter().map(|n| n.to_string()).collect::<Vec<_>>();
    assert_eq!(shared_start(&names(&[])), "");
    assert_eq!(shared_start(&names(&["src/"])), "src/");
    assert_eq!(shared_start(&names(&["src/", "src-old/", "srv/"])), "sr");
    assert_eq!(shared_start(&names(&["ab/", "a/"])), "a");
    assert_eq!(shared_start(&names(&["🍄a/", "🍄b/"])), "🍄");
}

/// `text` (with `hidden`) after `edits`, as vim makes them: an icon an edit
/// touches loses its hidden text.
fn merged(text: &str, hidden: &[Hidden], edits: &[TextEdit]) -> (String, Vec<Hidden>) {
    let mut units: Vec<u16> = text.encode_utf16().collect();
    let mut hidden = hidden.to_vec();
    for edit in edits.iter().rev() {
        let new: Vec<u16> = edit.text.encode_utf16().collect();
        let (removed, added) = (edit.end - edit.start, new.len());
        units.splice(edit.start..edit.end, new);
        hidden.retain(|h| h.at + utf16_len(&h.icon) <= edit.start || h.at >= edit.end);
        for h in hidden.iter_mut().filter(|h| h.at >= edit.end) {
            h.at = h.at + added - removed;
        }
        let at = |h: &Hidden| Hidden {
            at: h.at + edit.start,
            ..h.clone()
        };
        hidden.extend(edit.hidden.iter().map(at));
        hidden.sort_by_key(|h| h.at);
    }
    (String::from_utf16(&units).unwrap(), hidden)
}

/// Syncs the listing `text` (with `hidden`), and returns it with what
/// changed on disk.
fn synced_text(koil: &mut Koil, text: &str, hidden: &[Hidden]) -> (Synced, String, Vec<Hidden>) {
    let synced = sync(koil, text, hidden);
    let (text, hidden) = merged(text, hidden, &synced.merge.edits);
    (synced, text, hidden)
}

#[test]
fn test_sync_unchanged_listing() {
    let (temp, mut koil) = koil();
    let rendered = render(&koil);
    let root = temp.path();
    fs::write(root.join("alpha"), "").unwrap();
    fs::create_dir(root.join("zdir")).unwrap();
    fs::remove_file(root.join("notes")).unwrap();
    fs::rename(root.join("file.rs"), root.join("main.rs")).unwrap();
    let (synced, text, hidden) = synced_text(&mut koil, &rendered.text, &rendered.hidden);
    assert!(synced.questions.is_empty());
    assert!(!synced.moved);
    // as if it was read again, as nothing was edited
    let again = render(&koil);
    assert_eq!(names(&text), again.names);
    assert_eq!((text, hidden), (again.text, again.hidden));
    // only the changed lines are edited (the ones after `dir/`, as one)
    assert_eq!(synced.merge.edits.len(), 1);
    let first = rendered.text.split('\n').next().unwrap();
    assert_eq!(synced.merge.edits[0].start, utf16_len(first) + 1);
    assert!(koil.compute_actions().is_empty());
}

/// The names in the listing `text`.
fn names(text: &str) -> Vec<String> {
    let parsed = parse(text, &[]);
    parsed.entries.iter().map(entry_name).collect()
}

#[test]
fn test_sync_keeps_edits() {
    let (temp, mut koil) = koil();
    let rendered = render(&koil);
    let (text, hidden) = edited(&rendered, |line, name| match name {
        "notes" => Some(line.replace("notes", "todo")),
        "file.rs" => None,
        _ => Some(line.to_string()),
    });
    fs::write(temp.path().join("alpha"), "").unwrap();
    let (synced, text, hidden) = synced_text(&mut koil, &text, &hidden);
    assert!(synced.questions.is_empty());
    assert_eq!(names(&text), ["dir/", "alpha", "todo"]);
    let updated = update_listing(&mut koil, &text, &hidden);
    assert!(updated.ok, "{updated:?}");
    let mut actions = action_texts(&koil);
    actions.sort();
    assert_eq!(actions, ["DELETE file.rs", "MOVE   notes -> todo"]);
}

#[test]
fn test_sync_asks() {
    let (temp, mut koil) = koil();
    let rendered = render(&koil);
    let (text, hidden) = edited(&rendered, |line, name| match name {
        "notes" => None,
        "file.rs" => Some(line.replace("file.rs", "lib.rs")),
        _ => Some(line.to_string()),
    });
    let root = temp.path();
    fs::rename(root.join("notes"), root.join("notes.md")).unwrap();
    fs::rename(root.join("file.rs"), root.join("main.rs")).unwrap();
    let (synced, text, hidden) = synced_text(&mut koil, &text, &hidden);
    // what the user deleted is kept, until they say otherwise
    assert_eq!(names(&text), ["dir/", "lib.rs", "notes.md"]);
    let questions: Vec<&str> = synced.questions.iter().map(|q| q.text.as_str()).collect();
    assert_eq!(
        questions,
        [
            "`notes` was renamed to `notes.md` on disk, but you deleted it. Delete it anyway?",
            "`file.rs` was renamed to `main.rs` on disk, but you renamed it to `lib.rs`. \
             Keep `main.rs` instead?",
        ]
    );
    // yes to both
    let mut text = text;
    let mut hidden = hidden;
    for question in &synced.questions {
        let merge = resolve(&mut koil, &text, &hidden, &question.conflicts);
        (text, hidden) = merged(&text, &hidden, &merge.edits);
    }
    assert_eq!(names(&text), ["dir/", "main.rs"]);
    let updated = update_listing(&mut koil, &text, &hidden);
    assert!(updated.ok, "{updated:?}");
    assert_eq!(action_texts(&koil), ["DELETE notes.md"]);
}

#[test]
fn test_sync_edits_at_the_ends() {
    let (temp, mut koil) = koil();
    let root = temp.path();
    let rendered = render(&koil);
    // the last line goes with the line break before it
    fs::remove_file(root.join("notes")).unwrap();
    let (synced, text, hidden) = synced_text(&mut koil, &rendered.text, &rendered.hidden);
    assert_eq!(names(&text), ["dir/", "file.rs"]);
    assert!(!text.ends_with('\n'));
    assert_eq!(synced.merge.edits[0].text, "");
    // all of them
    fs::remove_file(root.join("file.rs")).unwrap();
    fs::remove_dir(root.join("dir")).unwrap();
    let (_, text, hidden) = synced_text(&mut koil, &text, &hidden);
    assert_eq!((text.as_str(), hidden.len()), ("", 0));
    // into an empty listing, and after the last line
    fs::write(root.join("b"), "").unwrap();
    let (_, text, hidden) = synced_text(&mut koil, &text, &hidden);
    assert_eq!(names(&text), ["b"]);
    fs::write(root.join("c"), "").unwrap();
    let (_, text, hidden) = synced_text(&mut koil, &text, &hidden);
    assert_eq!(names(&text), ["b", "c"]);
    // a new entry the user wrote stays last, and one on disk goes before it
    let text = format!("{text}\nnew");
    fs::write(root.join("d"), "").unwrap();
    let (_, text, _) = synced_text(&mut koil, &text, &hidden);
    assert_eq!(names(&text), ["b", "c", "d", "new"]);
}

#[test]
fn test_sync_open_dir_gone() {
    let (temp, mut koil) = koil();
    koil.open("dir").unwrap();
    fs::remove_dir(temp.path().join("dir")).unwrap();
    let synced = sync(&mut koil, "", &[]);
    assert!(synced.moved);
    assert!(
        synced.message.contains("is not a directory, opened"),
        "{}",
        synced.message
    );
    assert_eq!(names(&render(&koil).text), ["file.rs", "notes"]);
}

#[test]
fn test_sync_lines_out_of_order() {
    let (temp, mut koil) = koil();
    let rendered = render(&koil);
    // the user moved `notes` up
    let lines: Vec<&str> = rendered.text.split('\n').collect();
    let text = [lines[0], lines[2], lines[1]].join("\n");
    let hidden = parse(&rendered.text, &rendered.hidden);
    let at = |line: usize| {
        utf16_len(
            &lines[..line]
                .iter()
                .map(|l| format!("{l}\n"))
                .collect::<String>(),
        )
    };
    let ids: Vec<String> = hidden
        .entries
        .iter()
        .map(|e| e.id.unwrap().0.to_string())
        .collect();
    let icon = |line: usize| {
        rendered
            .hidden
            .iter()
            .find(|h| h.at == at(line))
            .unwrap()
            .icon
            .clone()
    };
    let hidden = vec![
        Hidden {
            at: 0,
            icon: icon(0),
            text: ids[0].clone(),
        },
        Hidden {
            at: utf16_len(lines[0]) + 1,
            icon: icon(2),
            text: ids[2].clone(),
        },
        Hidden {
            at: utf16_len(lines[0]) + utf16_len(lines[2]) + 2,
            icon: icon(1),
            text: ids[1].clone(),
        },
    ];
    assert_eq!(names(&text), ["dir/", "notes", "file.rs"]);
    fs::write(temp.path().join("m"), "").unwrap();
    let (_, text, _) = synced_text(&mut koil, &text, &hidden);
    assert_eq!(names(&text), ["dir/", "m", "notes", "file.rs"]);
}

// Enter on a new file creates it (with its new dir) before the other
// changes, which stay, and the listing then shows it on disk.
#[test]
fn test_create_now() {
    let (temp, mut koil) = koil();
    let rendered = render(&koil);
    let (text, hidden) = edited(&rendered, |line, name| match name {
        "notes" => Some("new/file.txt\nother".to_string()),
        _ => Some(line.to_string()),
    });
    let settings = koil.settings().clone();
    let updated = update(&mut koil, &rendered.path, &text, &hidden, &settings, None);
    assert!(updated.ok, "{updated:?}");
    let path = koil.current_dir().join("new/file.txt");
    assert_eq!(
        create_steps(&koil, &path),
        Ok(vec![
            "CREATE new/".to_string(),
            "CREATE new/file.txt".to_string()
        ])
    );
    assert_eq!(
        create_now(&mut koil, &path),
        Ok("`new/file.txt` created".to_string())
    );
    assert!(temp.path().join("new/file.txt").is_file());
    assert_eq!(
        action_texts(&koil),
        ["DELETE notes", "CREATE other"].map(String::from)
    );
    // `new/` has an ID now, so it isn't pending
    let rendered = render(&koil);
    let line = rendered.names.iter().position(|n| n == "new/").unwrap();
    let (text, hidden) = (&rendered.text, &rendered.hidden);
    assert!(!pending_lines(&koil, text, hidden).contains(&line));
    // a file that's there until it's moved away can't be
    let (text, hidden) = edited(&rendered, |line, name| match name {
        "file.rs" => Some(format!("{}\nfile.rs", line.replace("file.rs", "main.rs"))),
        _ => Some(line.to_string()),
    });
    let updated = update(&mut koil, &rendered.path, &text, &hidden, &settings, None);
    assert!(updated.ok, "{updated:?}");
    assert_eq!(
        create_steps(&koil, &koil.current_dir().join("file.rs")),
        Err("`file.rs` can't be created before the other changes are applied (Space a)".into())
    );
}
