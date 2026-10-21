use std::ffi::{OsStr, OsString};
use std::fs;

use koil_core::{Entry, Koil, Settings, Sort, SortBy};
use tempfile::TempDir;

use super::*;
use crate::sizes::DirSizes;

/// The listing, with none of its dirs' sizes counted.
fn render(koil: &Koil) -> Rendered {
    super::render(koil, &DirSizes::new())
}

/// [`super::sync`], with none of the dirs' sizes counted.
fn sync(koil: &mut Koil, text: &str, hidden: &[Hidden]) -> Synced {
    super::sync(koil, &DirSizes::new(), text, hidden)
}

/// `name` in the dir `koil` has open, as QML takes a path.
fn path_in(koil: &Koil, name: &str) -> String {
    unicode(&koil.current_dir().join(name)).unwrap()
}

/// The lines of what applying would do.
fn action_texts(koil: &Koil) -> Vec<String> {
    actions(koil).into_iter().map(|line| line.text).collect()
}

/// A temp dir with `dir/`, `.hidden`, `file.rs` and `notes`, and a Koil that
/// has it open.
fn koil() -> (TempDir, Koil) {
    koil_with(&["dir"], &[".hidden", "file.rs", "notes"])
}

/// A temp dir with `dirs` (and the dirs they're in) and the empty files
/// `files`, and a Koil that has it open.
fn koil_with(dirs: &[&str], files: &[&str]) -> (TempDir, Koil) {
    let temp = tempfile::tempdir().unwrap();
    for dir in dirs {
        fs::create_dir_all(temp.path().join(dir)).unwrap();
    }
    for file in files {
        fs::write(temp.path().join(file), "").unwrap();
    }
    let mut koil = Koil::default();
    koil.open(temp.path()).unwrap();
    (temp, koil)
}

/// Updates the listing as it's rendered, with `path` in the path field,
/// opening `open`.
fn navigate(koil: &mut Koil, path: &str, settings: &Settings, open: Option<&str>) -> Updated {
    let rendered = render(koil);
    update(koil, path, &rendered.text, &rendered.hidden, settings, open)
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
    let (temp, koil) = koil_with(&[], &["vercel.json", "gtkrc", "board.kicad_pcb"]);
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

    // file.rs renamed, notes copied as notes2, and a new file
    let lines: Vec<&str> = rendered.text.split('\n').collect();
    let text = [
        lines[0].to_string(),
        lines[1].replace("file.rs", "main.rs"),
        lines[2].to_string(),
        lines[2].replace("notes", "notes2"),
        "new.txt".to_string(),
    ]
    .join("\n");
    // Each line's icon keeps the ID of the line it came from.
    let ids = [Some(0), Some(1), Some(2), Some(2), None];
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
    let (_temp, koil) = koil_with(&[], &[]);
    let rendered = render(&koil);
    assert_eq!(rendered.text, "");
    assert_eq!(rendered.names, Vec::<String>::new());
    assert_eq!(parse(&rendered.text, &rendered.hidden).entries, []);
}

#[test]
fn test_parse_new_entries() {
    let text = "  new.txt  \n\n\u{f016}  icon but no ID\nsub/dir/";
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
        ]
    );
    assert_eq!(parsed.spots, [(0, 2), (2, 3), (3, 0)]);
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
    // only the delete says it deletes
    let deletes: Vec<_> = (super::actions(&koil).into_iter())
        .filter(|line| line.deletes)
        .map(|line| line.text)
        .collect();
    assert_eq!(deletes, ["DELETE notes"]);
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

    // Enter on a dir
    let rendered = render(&koil);
    assert_eq!(
        target_on_line(&koil, &rendered.text, &rendered.hidden, 0),
        Some(Target::Dir("dir".into()))
    );
    let updated = navigate(&mut koil, &rendered.path, &settings, Some("dir"));
    assert!(updated.ok && updated.moved, "{updated:?}");
    assert_eq!(koil.current_dir(), root.join("dir"));
    assert_eq!(updated.from, "");

    // `-`, which comes from `dir/`
    let path = show_location(&koil);
    let updated = navigate(&mut koil, &path, &settings, Some(".."));
    assert!(updated.ok && updated.moved);
    assert_eq!(koil.current_dir(), root);
    assert_eq!(updated.from, "dir/");

    // a changed path, even with spaces around it
    let path = format!("  {}  ", show_path(&temp.path().join("dir")));
    let updated = navigate(&mut koil, &path, &settings, None);
    assert!(updated.ok && updated.moved);
    assert_eq!(koil.current_dir(), root.join("dir"));

    // the same path reads the listing again, without moving
    let path = show_location(&koil);
    let updated = navigate(&mut koil, &path, &settings, None);
    assert!(updated.ok && !updated.moved);

    // one that can't be opened, which the path field says
    let updated = navigate(&mut koil, " [", &settings, None);
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
        let updated = navigate(&mut koil, &show_path(&root.join(path)), &settings, None);
        assert!(!updated.ok, "{path}: {updated:?}");
        let part = show_path(&root.join(part));
        assert_eq!(updated.message, format!("`{part}` {problem}"));
        assert_eq!(updated.path_problems.len(), 1);
        assert_eq!(updated.path_problems[0].message, updated.message);
        assert_eq!(koil.current_dir(), root.join("dir"));
    }

    // no path at all
    let updated = navigate(&mut koil, "  ", &settings, None);
    assert!(!updated.ok);
    assert_eq!(updated.message, "Write the path to open");
    assert_eq!(updated.path_problems[0].line, 0);
}

#[test]
fn test_target_on_line() {
    let (_temp, koil) = koil();
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
            path: path_in(&koil, "file.rs"),
            name: "main.rs".into()
        })
    );
    assert_eq!(
        target(2),
        Some(Target::New {
            path: path_in(&koil, "new.txt"),
            name: "new.txt".into()
        })
    );
    assert_eq!(target(4), None);
    // a new dir, a blank line, and a dir whose `/` was taken off
    let text = format!("new/\n\n{}dir", rendered.hidden[0].icon);
    let hidden = [Hidden {
        at: 6,
        ..rendered.hidden[0].clone()
    }];
    assert_eq!(
        target_on_line(&koil, &text, &hidden, 0),
        Some(Target::Dir("new".into()))
    );
    assert_eq!(target_on_line(&koil, &text, &hidden, 1), None);
    assert_eq!(
        target_on_line(&koil, &text, &hidden, 2),
        Some(Target::Dir("dir".into()))
    );
}

#[test]
fn test_file_at() {
    let (_temp, koil) = koil();
    let root = koil.current_dir().to_path_buf();
    for name in ["my file.txt", "a[1].txt", "~x"] {
        fs::write(root.join(name), "").unwrap();
    }
    let file = |location| file_at(&koil, location);
    // `~` is the home dir only as a whole part
    assert_eq!(file("~x"), Some(root.join("~x")));
    assert_eq!(file("file.rs"), Some(root.join("file.rs")));
    assert_eq!(file(" notes "), Some(root.join("notes")));
    assert_eq!(file("dir/../notes"), Some(root.join("notes")));
    let absolute = root.join("file.rs");
    assert_eq!(file(absolute.to_str().unwrap()), Some(absolute.clone()));
    // read as the path field reads it, but as written first
    assert_eq!(file("\"my file.txt\""), Some(root.join("my file.txt")));
    assert_eq!(file("a[1].txt"), Some(root.join("a[1].txt")));
    // listed, or not there
    for location in ["dir", "dir/", ".", "*.rs", "missing.txt", "file.rs/x", ""] {
        assert_eq!(file(location), None, "{location}");
    }
    assert_eq!(file("~"), None);
}

#[test]
fn test_path_on_line() {
    let (_temp, koil) = koil();
    let rendered = render(&koil);
    // dir renamed on its line, and a new file and dir
    let (text, hidden) = edited(&rendered, |line, name| match name {
        "dir/" => Some(format!(
            "{}\nnew.txt\n   new/",
            line.replace("dir/", "renamed/")
        )),
        _ => Some(line.to_string()),
    });
    let path = |line| path_on_line(&koil, &text, &hidden, line);
    let new = |name| {
        Err(format!(
            "“{name}” isn't on disk until the changes are applied"
        ))
    };
    assert_eq!(path(0), Ok(path_in(&koil, "dir")));
    assert_eq!(path(1), new("new.txt"));
    assert_eq!(path(2), new("new/"));
    assert_eq!(path(3), Ok(path_in(&koil, "file.rs")));
    let none = Err("No entry on this line".to_string());
    assert_eq!(path(5), none);
    // a blank line
    assert_eq!(path_on_line(&koil, "\n", &[], 0), none);
}

#[test]
fn test_paths_on_lines() {
    let (_temp, koil) = koil();
    let rendered = render(&koil);
    // dir renamed on its line, then a blank line and a new file
    let (text, hidden) = edited(&rendered, |line, name| match name {
        "dir/" => Some(format!("{}\n\nnew.txt", line.replace("dir/", "renamed/"))),
        _ => Some(line.to_string()),
    });
    let paths = |lines: &[(usize, usize)]| paths_on_lines(&koil, &text, &hidden, lines);
    assert_eq!(paths(&[(0, 1)]), Ok(vec![path_in(&koil, "dir")]));
    assert_eq!(
        paths(&[(3, 4)]),
        Ok(vec![path_in(&koil, "file.rs"), path_in(&koil, "notes")])
    );
    assert_eq!(
        paths(&[(0, 2)]),
        Err("“new.txt” isn't on disk until the changes are applied".into())
    );
    assert_eq!(paths(&[(1, 1)]), Err("No entry on this line".into()));
    assert_eq!(paths(&[(7, 9)]), Err("No entries on these lines".into()));
    // marked lines, apart: not the new file and file.rs between them
    assert_eq!(
        paths(&[(0, 0), (4, 4)]),
        Ok(vec![path_in(&koil, "dir"), path_in(&koil, "notes")])
    );
    assert_eq!(
        paths(&[(1, 1), (7, 7)]),
        Err("No entries on these lines".into())
    );
}

#[test]
fn test_links_on_lines() {
    let (_temp, koil) = koil();
    let root = koil.current_dir().to_path_buf();
    fs::write(root.join("dir/inner.txt"), "").unwrap();
    // an entry pasted with its ID, renamed on its line
    let text = "file.rs\n\n  inner.txt \n\u{e612}  renamed\nmissing\nhttps://a.b\n~\n M dir/inner.txt\n\
                see `file.rs`, then";
    let hidden = [Hidden {
        at: 22,
        icon: "\u{e612}".into(),
        text: id_text(&koil, "notes"),
    }];
    let dirs = [root.join("dir"), root.clone()];
    let links =
        |lines: &[(usize, usize)], at| links_on_lines(&koil, text, &hidden, lines, at, &dirs);
    let paths = |lines: &[(usize, usize)]| links(lines, None);
    // each line's first, a relative one in the first of the dirs it's in
    assert_eq!(
        paths(&[(0, 3)]),
        Ok(vec![
            path_in(&koil, "file.rs"),
            path_in(&koil, "dir/inner.txt"),
            path_in(&koil, "notes")
        ])
    );
    assert_eq!(paths(&[(1, 1)]), Err("No file name on this line".into()));
    assert_eq!(
        paths(&[(1, 1), (9, 9)]),
        Err("No file names on these lines".into())
    );
    assert_eq!(
        paths(&[(0, 0), (4, 4)]),
        Err("E447: Can't find file \"missing\" in path".into())
    );
    assert_eq!(paths(&[(5, 5)]), Ok(vec!["https://a.b".to_string()]));
    let home = std::env::home_dir().unwrap();
    assert_eq!(paths(&[(6, 6)]), Ok(vec![unicode(&home).unwrap()]));
    // a path before a name: not ` M`
    assert_eq!(paths(&[(7, 7)]), Ok(vec![path_in(&koil, "dir/inner.txt")]));
    // at the cursor, as gf takes it: there or after it
    assert_eq!(
        links(&[(8, 8)], Some(5)),
        Ok(vec![path_in(&koil, "file.rs")])
    );
    assert_eq!(
        links(&[(8, 8)], Some(3)),
        Ok(vec![path_in(&koil, "file.rs")])
    );
    assert_eq!(
        links(&[(8, 8)], Some(0)),
        Err("E447: Can't find file \"see\" in path".into())
    );
    let none = Err("E446: No file name under cursor".into());
    assert_eq!(links(&[(2, 2)], Some(11)), none);
    assert_eq!(links(&[(1, 1)], Some(0)), none);
    // the entry, wherever the cursor is on its line
    assert_eq!(links(&[(3, 3)], Some(5)), Ok(vec![path_in(&koil, "notes")]));
}

/// `start` and a part that isn't Unicode, as a name can be on Linux (a
/// byte that isn't UTF-8) or Windows (a lone surrogate), not on macOS.
fn not_unicode(start: &str) -> OsString {
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStringExt;
        OsString::from_vec([start.as_bytes(), b"\xff"].concat())
    }
    #[cfg(windows)]
    {
        use std::os::windows::ffi::OsStringExt;
        let mut wide: Vec<u16> = start.encode_utf16().collect();
        wide.push(0xd800);
        OsString::from_wide(&wide)
    }
}

/// `koil` with an entry listed whose name is `name`: through its saved
/// state, as koil-core gives no other way to have one that isn't on disk,
/// and no such file can be made on macOS.
fn with_entry(koil: &Koil, name: &OsStr) -> Koil {
    let mut state: serde_json::Value = serde_json::from_str(&koil.save_state()).unwrap();
    let ids = state["ids"].as_array_mut().unwrap();
    let path = koil.current_dir().join(name);
    ids.push(serde_json::to_value(path.as_os_str()).unwrap());
    let id = ids.len() - 1;
    state["current_listing"]
        .as_array_mut()
        .unwrap()
        .push(id.into());
    Koil::load_state(&state.to_string()).unwrap()
}

#[test]
fn test_name_not_unicode() {
    // shown with `�`, it's read back as it is, and what QML is given of
    // it is JSON, but Koil can't open it, nor give a command its path
    let (_temp, koil) = koil();
    let name = not_unicode("a");
    let koil = with_entry(&koil, &name);
    let rendered = render(&koil);
    serde_json::to_string(&rendered).unwrap();
    let (text, hidden) = (&rendered.text, &rendered.hidden);
    let line = (rendered.names.iter())
        .position(|n| *n == name.to_string_lossy())
        .unwrap();
    assert_eq!(pending_lines(&koil, text, hidden), Vec::<usize>::new());
    assert_eq!(check(&koil, text, hidden), []);
    let path = koil.current_dir().join(&name);
    let why = format!(
        "Koil can't use `{}`, as its path isn't valid Unicode",
        show_path(&path)
    );
    let target = target_on_line(&koil, text, hidden, line);
    assert_eq!(target, Some(Target::Error(why.clone())));
    assert_eq!(path_on_line(&koil, text, hidden, line), Err(why.clone()));
    let paths = paths_on_lines(&koil, text, hidden, &[(0, line)]);
    assert_eq!(paths, Err(why));
}

#[test]
fn test_update_name_not_unicode() {
    // unchanged, it isn't renamed to what it's shown as
    let (_temp, koil) = koil();
    let mut koil = with_entry(&koil, &not_unicode("a"));
    let path = show_location(&koil);
    let updated = navigate(&mut koil, &path, &Settings::default(), None);
    assert!(updated.ok, "{}", updated.message);
    assert_eq!(action_texts(&koil), Vec::<String>::new());
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
    assert_eq!(render(&koil).names, ["dir/", ".hidden", "file.rs", "notes"]);
}

#[test]
fn test_settings() {
    let (_temp, mut koil) = koil();
    let rendered = render(&koil);
    let settings = Settings {
        show_hidden: true,
        ..Settings::default()
    };
    let updated = navigate(&mut koil, &rendered.path, &settings, None);
    assert!(updated.ok && updated.moved);
    assert_eq!(render(&koil).names, ["dir/", ".hidden", "file.rs", "notes"]);

    // regex changes how the path is read, not what's shown
    let rendered = render(&koil);
    let settings = Settings {
        regex: true,
        ..settings
    };
    let updated = navigate(&mut koil, &rendered.path, &settings, None);
    assert!(updated.ok && !updated.moved);
    assert!(koil.settings().regex);

    // and so does the order
    let rendered = render(&koil);
    let settings = Settings {
        sort: Sort {
            by: SortBy::Name,
            reverse: true,
            ..Sort::default()
        },
        ..settings
    };
    let updated = navigate(&mut koil, &rendered.path, &settings, None);
    assert!(updated.ok && !updated.moved);
    assert_eq!(render(&koil).names, ["dir/", "notes", "file.rs", ".hidden"]);
}

/// The settings with the listing sorted by `by`.
fn sorted_by(by: SortBy) -> Settings {
    Settings {
        sort: Sort {
            by,
            ..Sort::default()
        },
        ..Settings::default()
    }
}

/// The ID of `name` in the open dir, as its icon hides it.
fn id_text(koil: &Koil, name: &str) -> String {
    let id = koil.id_of(&koil.current_dir().join(name)).unwrap();
    id.0.to_string()
}

#[test]
fn test_show_size() {
    let sizes = [0, 999, 1000, 1234, 9949, 9950, 12_345, 999_499];
    assert_eq!(
        sizes.map(show_size),
        [
            "0 B", "999 B", "1.0 KB", "1.2 KB", "9.9 KB", "10 KB", "12 KB", "999 KB"
        ]
    );
    assert_eq!(show_size(999_999), "1.0 MB");
    assert_eq!(show_size(5_600_000_000), "5.6 GB");
    assert_eq!(show_size(u64::MAX), "18 EB");
}

#[test]
fn test_infos() {
    let (temp, mut koil) = koil();
    fs::write(temp.path().join("notes"), "x".repeat(1234)).unwrap();
    fs::write(temp.path().join("dir/a"), "").unwrap();
    // nothing to show when sorted by name
    assert!(render(&koil).notes.infos.is_empty());

    koil.set_settings(sorted_by(SortBy::Size)).unwrap();
    let rendered = render(&koil);
    assert_eq!(rendered.names, ["dir/", "notes", "file.rs"]);
    let info = |name| rendered.notes.infos[&id_text(&koil, name)].as_str();
    // a dir's size isn't counted yet
    assert_eq!(
        [info("dir"), info("notes"), info("file.rs")],
        ["...", "1.2 KB", "0 B"]
    );
    assert_eq!(rendered.notes.busy, [id_text(&koil, "dir")]);
    let dir = koil.current_dir().join("dir");
    assert_eq!(rendered.notes.dirs, [(koil.id_of(&dir).unwrap(), dir)]);

    koil.set_settings(sorted_by(SortBy::Modified)).unwrap();
    let rendered = render(&koil);
    let date = &rendered.notes.infos[&id_text(&koil, "notes")];
    // like 2026-10-06 14:03
    let digits: String = date.chars().filter(char::is_ascii_digit).collect();
    assert_eq!((date.len(), digits.len()), (16, 12), "{date}");
}

#[test]
fn test_sync_sorted() {
    let (temp, mut koil) = koil();
    let root = temp.path();
    fs::write(root.join("notes"), "1234").unwrap();
    koil.set_settings(sorted_by(SortBy::Size)).unwrap();
    let rendered = render(&koil);
    assert_eq!(rendered.names, ["dir/", "notes", "file.rs"]);
    // new files go where they sort, with what's shown after them
    fs::write(root.join("big"), "x".repeat(100)).unwrap();
    fs::write(root.join("mid"), "12").unwrap();
    let (synced, text, hidden) = synced_text(&mut koil, &rendered.text, &rendered.hidden);
    assert_eq!(names(&text), ["dir/", "big", "notes", "mid", "file.rs"]);
    assert_eq!(synced.notes.infos[&id_text(&koil, "big")], "100 B");
    // a file written to stays where it is, but shows its new size
    fs::write(root.join("file.rs"), "x".repeat(5000)).unwrap();
    let (synced, text, _) = synced_text(&mut koil, &text, &hidden);
    assert!(synced.merge.edits.is_empty());
    assert_eq!(names(&text), ["dir/", "big", "notes", "mid", "file.rs"]);
    assert_eq!(synced.notes.infos[&id_text(&koil, "file.rs")], "5.0 KB");
}

#[test]
fn test_disk_size_infos() {
    let (_temp, mut koil) = koil();
    let notes = koil.current_dir().join("notes");
    fs::write(&notes, vec![1; 100_000]).unwrap();
    koil.set_settings(sorted_by(SortBy::Disk)).unwrap();
    let rendered = render(&koil);
    assert_eq!(rendered.names, ["dir/", "notes", "file.rs"]);
    let info = |name| rendered.notes.infos[&id_text(&koil, name)].as_str();
    let on_disk = koil_core::disk_size(&notes, &notes.symlink_metadata().unwrap()).unwrap();
    assert_eq!(info("notes"), show_size(on_disk));
    // a dir's is counted, as by size
    assert_eq!(info("dir"), "...");
    assert_eq!(rendered.notes.busy, [id_text(&koil, "dir")]);
    let sizes = DirSizes::from([(koil.current_dir().join("dir"), DirSize::Counted(1))]);
    let rendered = super::render(&koil, &sizes);
    assert_eq!(rendered.notes.infos[&id_text(&koil, "dir")], "1 B");
}

#[test]
fn test_dir_sizes() {
    let (_temp, mut koil) = koil();
    let root = koil.current_dir().to_path_buf();
    for dir in ["big", "mid", "small", "unread"] {
        fs::create_dir(root.join(dir)).unwrap();
    }
    // Koil's own order is by how many entries each has
    fs::write(root.join("small/a"), "").unwrap();
    fs::write(root.join("small/b"), "").unwrap();
    koil.set_settings(sorted_by(SortBy::Size)).unwrap();
    assert_eq!(
        render(&koil).names,
        [
            "small/", "big/", "dir/", "mid/", "unread/", "file.rs", "notes"
        ]
    );
    // the ones counted go first, by size, as far as they're counted
    let sizes = DirSizes::from([
        (root.join("big"), DirSize::Counted(5000)),
        (root.join("mid"), DirSize::Counting(1234)),
        (root.join("small"), DirSize::Counted(10)),
        (root.join("unread"), DirSize::Unreadable),
    ]);
    let rendered = super::render(&koil, &sizes);
    assert_eq!(
        rendered.names,
        [
            "big/", "small/", "dir/", "mid/", "unread/", "file.rs", "notes"
        ]
    );
    let info = |name| rendered.notes.infos.get(&id_text(&koil, name)).cloned();
    assert_eq!(
        ["big", "small", "dir", "mid", "unread"].map(info),
        [
            Some("5.0 KB".into()),
            Some("10 B".into()),
            Some("...".into()),
            Some("1.2 KB...".into()),
            None
        ]
    );
    let mut busy = rendered.notes.busy.clone();
    busy.sort();
    let mut expected = [id_text(&koil, "dir"), id_text(&koil, "mid")];
    expected.sort();
    assert_eq!(busy, expected);
    // counted again, it stays where it was, with what it was
    let mut stale = sizes.clone();
    stale.insert(root.join("small"), DirSize::Stale(10));
    let rendered = super::render(&koil, &stale);
    assert_eq!(
        rendered.names,
        [
            "big/", "small/", "dir/", "mid/", "unread/", "file.rs", "notes"
        ]
    );
    let small = id_text(&koil, "small");
    assert_eq!(rendered.notes.infos[&small], "10 B...");
    assert!(rendered.notes.busy.contains(&small));
    // the other way round, the ones not counted first
    koil.set_settings(Settings {
        sort: Sort {
            by: SortBy::Size,
            reverse: true,
            ..Sort::default()
        },
        ..Settings::default()
    })
    .unwrap();
    assert_eq!(
        super::render(&koil, &sizes).names,
        [
            "unread/", "mid/", "dir/", "small/", "big/", "notes", "file.rs"
        ]
    );

    // a dir made on disk goes where its size puts it
    koil.set_settings(sorted_by(SortBy::Size)).unwrap();
    let rendered = super::render(&koil, &sizes);
    fs::create_dir(root.join("huge")).unwrap();
    let mut sizes = sizes;
    sizes.insert(root.join("huge"), DirSize::Counted(9000));
    let synced = super::sync(&mut koil, &sizes, &rendered.text, &rendered.hidden);
    let (text, _) = merged(&rendered.text, &rendered.hidden, &synced.merge.edits);
    assert_eq!(
        names(&text),
        [
            "huge/", "big/", "small/", "dir/", "mid/", "unread/", "file.rs", "notes"
        ]
    );
    assert_eq!(synced.notes.infos[&id_text(&koil, "huge")], "9.0 KB");
}

#[test]
fn test_dir_sizes_with_files() {
    let (_temp, mut koil) = koil();
    let root = koil.current_dir().to_path_buf();
    fs::create_dir(root.join("big")).unwrap();
    fs::write(root.join("notes"), "x".repeat(100)).unwrap();
    fs::write(root.join("file.rs"), "x".repeat(10)).unwrap();
    let mixed = |reverse| Settings {
        sort: Sort {
            by: SortBy::Size,
            reverse,
            dirs_first: false,
        },
        ..Settings::default()
    };
    koil.set_settings(mixed(false)).unwrap();
    // Koil puts the dirs after the files, as it doesn't know their sizes
    assert_eq!(render(&koil).names, ["notes", "file.rs", "big/", "dir/"]);
    // the ones counted go among the files, by size
    let mut sizes = DirSizes::from([(root.join("big"), DirSize::Counted(50))]);
    let rendered = super::render(&koil, &sizes);
    assert_eq!(rendered.names, ["notes", "big/", "file.rs", "dir/"]);
    // and so do a dir and a file made on disk
    fs::create_dir(root.join("huge")).unwrap();
    sizes.insert(root.join("huge"), DirSize::Counted(1000));
    fs::write(root.join("mid"), "x".repeat(20)).unwrap();
    let synced = super::sync(&mut koil, &sizes, &rendered.text, &rendered.hidden);
    let (text, _) = merged(&rendered.text, &rendered.hidden, &synced.merge.edits);
    assert_eq!(
        names(&text),
        ["huge/", "notes", "big/", "mid", "file.rs", "dir/"]
    );
    // the other way round, the ones not counted first
    koil.set_settings(mixed(true)).unwrap();
    assert_eq!(
        super::render(&koil, &sizes).names,
        ["dir/", "file.rs", "mid", "big/", "notes", "huge/"]
    );
}

#[test]
fn test_dirs_pattern() {
    let (_temp, mut koil) = koil();
    let settings = Settings {
        regex: true,
        ..Settings::default()
    };
    let dir = render(&koil).path;

    // a pattern ending with `/` keeps it, and shows the dirs
    let path = format!("{dir}/,*/");
    let updated = navigate(&mut koil, &path, &settings, None);
    assert!(updated.ok && updated.moved, "{updated:?}");
    let rendered = render(&koil);
    assert_eq!(rendered.path, path);
    assert_eq!(rendered.names, ["dir/"]);
    // so the same path is what's open
    assert!(!navigate(&mut koil, &path, &settings, None).moved);
    assert_eq!(render(&koil).path, path);

    // without the `/`, it's another listing (the files)
    let path = format!("{dir}/,*");
    assert!(navigate(&mut koil, &path, &settings, None).moved);
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

/// The parts of `glob` as (text, kind).
fn glob(glob: &str) -> Vec<(&str, &str)> {
    let parts = glob_parts(glob).into_iter();
    parts.map(|(s, e, kind)| (&glob[s..e], kind)).collect()
}

#[test]
fn test_glob_parts() {
    assert_eq!(
        glob(r"src/**/?\*.rs"),
        [
            ("*", "anchor"),
            ("*", "anchor"),
            ("?", "anchor"),
            (r"\*", "escape")
        ]
    );
    // a `,` only between braces, and a `]` first in a class
    assert_eq!(
        glob("a,{b,[]}]}[!x]"),
        [
            ("{", "group"),
            (",", "group"),
            ("[]}]", "class"),
            ("}", "group"),
            ("[!x]", "class")
        ]
    );
    // unfinished, as it is while it's typed
    assert_eq!(glob("[a{"), [("[a{", "class")]);
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
    // as a glob, it has no special character, so it's a path
    assert_eq!(spans(&line, false), []);
    // a glob's, in the dirs
    assert_eq!(
        spans(&format!("{dir}/dir/*.{{rs,md}}"), false),
        [
            ("*.{rs,md}".to_string(), "pattern"),
            ("*".to_string(), "anchor"),
            ("{".to_string(), "group"),
            (",".to_string(), "group"),
            ("}".to_string(), "group")
        ]
    );
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
fn test_regex_setting() {
    let (_temp, mut koil) = koil();
    let dir = render(&koil).path;
    let glob = koil.settings().clone();
    let regex = Settings {
        regex: true,
        ..glob.clone()
    };
    // a regex written while patterns are globs matches nothing
    let updated = navigate(&mut koil, &format!("{dir}/.*rs"), &glob, None);
    assert!(updated.ok, "{updated:?}");
    assert!(render(&koil).names.is_empty());
    // the setting reads it again as a regex, though the path didn't change
    let path = render(&koil).path;
    let updated = navigate(&mut koil, &path, &regex, None);
    assert!(updated.ok && updated.moved, "{updated:?}");
    assert_eq!(koil.pattern(), Some(&Pattern::Regex(".*rs".into())));
    assert_eq!(render(&koil).names, ["file.rs"]);
    // and back
    let path = render(&koil).path;
    assert!(navigate(&mut koil, &path, &glob, None).moved);
    assert_eq!(koil.pattern(), Some(&Pattern::Glob(".*rs".into())));
    // one that isn't a regex is the path field's error, and koil stays
    let updated = navigate(&mut koil, &format!("{dir}/*.rs"), &glob, None);
    assert!(updated.ok, "{updated:?}");
    let path = render(&koil).path;
    let updated = navigate(&mut koil, &path, &regex, None);
    assert!(
        !updated.ok && !updated.path_problems.is_empty(),
        "{updated:?}"
    );
    assert_eq!(koil.pattern(), Some(&Pattern::Glob("*.rs".into())));
}

#[test]
fn test_up() {
    let (_temp, mut koil) = koil_with(&["dir/src"], &["dir/a.rs", "dir/src/main.rs"]);
    let settings = koil.settings().clone();
    let up = |koil: &Koil, name: &str, count| {
        let rendered = render(koil);
        let line = rendered.names.iter().position(|n| n == name).unwrap();
        super::up(koil, &rendered.text, &rendered.hidden, line, count)
    };
    let to = |open: &str, from: &str| Up {
        open: open.to_string(),
        from: from.to_string(),
    };
    // a dir's parents
    assert_eq!(up(&koil, "dir/", 1), to("..", ""));
    assert_eq!(up(&koil, "dir/", 3), to("../../..", ""));
    // a pattern is a level of its own: its base dir, on what the entry is in
    let path = format!("{}/dir/**/*.rs", render(&koil).path);
    assert!(navigate(&mut koil, &path, &settings, None).ok);
    assert_eq!(render(&koil).names, ["a.rs", "src/main.rs"]);
    assert_eq!(up(&koil, "src/main.rs", 1), to(".", "src/"));
    assert_eq!(up(&koil, "a.rs", 0), to(".", "a.rs"));
    assert_eq!(up(&koil, "a.rs", 2), to("..", ""));
    // which opens the base dir, without the pattern
    let dir = koil.current_dir().to_path_buf();
    assert!(navigate(&mut koil, &path, &settings, Some(".")).moved);
    assert_eq!((koil.current_dir(), koil.pattern()), (dir.as_path(), None));
    assert_eq!(render(&koil).names, ["src/", "a.rs"]);
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
/// with `src/`, `src-old/`, `Abc/`, `aBd/`, `my_tests/`, `my_tools/`,
/// `🍄/sub/` and the file `script`: where the options start, what it fills
/// in, and the options.
fn completed(line: &str) -> (usize, String, Vec<String>) {
    let dirs = [
        "src", "src-old", "Abc", "aBd", "my_tests", "my_tools", "🍄/sub",
    ];
    let (_temp, koil) = koil_with(&dirs, &["script"]);
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
    // case is ignored unless what's written has an uppercase letter, and
    // what they share is read with case, so it can be less than that
    assert_eq!(
        completed("a"),
        (0, String::new(), vec!["Abc/".into(), "aBd/".into()])
    );
    assert_eq!(
        completed("ab"),
        (0, String::new(), vec!["Abc/".into(), "aBd/".into()])
    );
    assert_eq!(fill("abc"), "Abc/");
    assert_eq!(fill("A"), "Abc/");
    assert_eq!(completed("AB"), (0, String::new(), vec![]));
    // with no dir starting with it, the ones with its characters in order,
    // and what they all start with only if it keeps them
    let tools = || vec!["my_tests/".to_string(), "my_tools/".into()];
    assert_eq!(fill("myto"), "my_tools/");
    assert_eq!(completed("myt"), (0, "my_t".into(), tools()));
    assert_eq!(completed("ts"), (0, String::new(), tools()));
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
        let merge = resolve(
            &mut koil,
            &DirSizes::new(),
            &text,
            &hidden,
            &question.conflicts,
        );
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
        Err("`file.rs` can't be created before the other changes are applied (Space Space)".into())
    );
}

/// Renames `from` (in the open dir) to `to`, and applies it.
fn apply_rename(koil: &mut Koil, from: &str, to: &str) {
    let entries: Vec<Entry> = (koil.listing().into_iter())
        .map(|entry| match entry.name == Path::new(from) {
            true => Entry {
                name: to.into(),
                ..entry
            },
            false => entry,
        })
        .collect();
    koil.update(&entries).unwrap();
    koil.apply().unwrap();
}

#[test]
fn test_history() {
    let (temp, mut koil) = koil();
    apply_rename(&mut koil, "notes", "notes2");
    apply_rename(&mut koil, "notes2", "notes3");
    apply_rename(&mut koil, "file.rs", "main.rs");
    let lines = history(&koil).unwrap();
    // newest first, each with when it was applied and what undoing it does
    let texts: Vec<Vec<&str>> = (lines.iter())
        .map(|line| line.text.lines().skip(1).collect())
        .collect();
    assert_eq!(
        texts,
        [
            ["MOVE    main.rs -> file.rs"],
            ["MOVE    notes3 -> notes2"],
            ["MOVE    notes2 -> notes"]
        ]
    );
    let time = |line: &HistoryLine| show_time(line.applied.time);
    assert!(
        lines
            .iter()
            .all(|line| line.text.starts_with(&(time(line) + "\n")))
    );
    // the first rename can't be undone without the second one
    let needs: Vec<&[usize]> = lines.iter().map(|line| line.needs.as_slice()).collect();
    assert_eq!(needs, [&[][..], &[], &[1]]);
    assert!(lines.iter().all(|line| line.blocked.is_none()));

    // what's gone on disk can't be put back
    fs::remove_file(temp.path().join("main.rs")).unwrap();
    let lines = history(&koil).unwrap();
    assert_eq!(lines[0].blocked.as_deref(), Some("`main.rs` is gone"));
    assert_eq!(
        lines[0].text.lines().last(),
        Some("Can't be undone: `main.rs` is gone")
    );
    assert!(lines[1].blocked.is_none());

    // and where it was applied, from another dir
    let dir = show_path(koil.current_dir());
    koil.open(temp.path().join("dir")).unwrap();
    let lines = history(&koil).unwrap();
    let header = format!("{}  {dir}", time(&lines[1]));
    assert_eq!(lines[1].text.lines().next(), Some(header.as_str()));
    // while its steps, as `u` lists them, are relative to the open dir
    assert_eq!(
        lines[1].steps,
        [format!("MOVE    {dir}/notes3 -> {dir}/notes2")]
    );
}
