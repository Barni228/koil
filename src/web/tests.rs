use std::io::{Cursor, Read};

use super::*;

/// Makes `paths` in `dir`: a dir for one that ends in `/`, else a file with
/// its own path as its text.
fn make(dir: &Path, paths: &[&str]) {
    for path in paths {
        let at = dir.join(path);
        if path.ends_with('/') {
            fs::create_dir_all(at).unwrap();
        } else {
            fs::create_dir_all(at.parent().unwrap()).unwrap();
            fs::write(at, path).unwrap();
        }
    }
}

/// What's in `dir`, as paths in it (a dir's with a `/`), sorted.
fn listed(dir: &Path) -> Vec<String> {
    let mut found = Vec::new();
    let mut dirs = vec![dir.to_path_buf()];
    while let Some(at) = dirs.pop() {
        for entry in fs::read_dir(&at).unwrap() {
            let path = entry.unwrap().path();
            let name = zip_name(path.strip_prefix(dir).unwrap());
            if path.is_dir() {
                found.push(name + "/");
                dirs.push(path);
            } else {
                found.push(name);
            }
        }
    }
    found.sort();
    found
}

#[test]
fn test_import() {
    let temp = tempfile::tempdir().unwrap();
    let (staging, dir) = (temp.path().join("staging"), temp.path().join("dir"));
    make(
        &staging,
        &["notes.txt", "photos/a.png", "photos/trip/b.png"],
    );
    make(&dir, &["old.txt"]);
    let made = import(&staging, &dir).unwrap();
    assert_eq!(vec![dir.join("notes.txt"), dir.join("photos")], made);
    assert_eq!(
        [
            "notes.txt",
            "old.txt",
            "photos/",
            "photos/a.png",
            "photos/trip/",
            "photos/trip/b.png"
        ],
        listed(&dir).as_slice()
    );
    assert_eq!(
        "photos/trip/b.png",
        fs::read_to_string(dir.join("photos/trip/b.png")).unwrap()
    );
    // emptied, for the next one
    assert!(!staging.exists());
}

#[test]
fn test_import_taken_names() {
    let temp = tempfile::tempdir().unwrap();
    let (staging, dir) = (temp.path().join("staging"), temp.path().join("dir"));
    make(
        &staging,
        &["notes.txt", "src/main.rs", ".env", "Makefile", "a.tar.gz"],
    );
    make(
        &dir,
        &[
            "notes.txt",
            "notes (2).txt",
            "src/",
            ".env",
            "Makefile",
            "a.tar.gz",
        ],
    );
    let made = import(&staging, &dir).unwrap();
    let names: Vec<_> = made
        .iter()
        .map(|p| p.file_name().unwrap().to_str().unwrap())
        .collect();
    // after the extension's last dot; a name's first dot is no extension's
    assert_eq!(
        [
            ".env (2)",
            "Makefile (2)",
            "a.tar (2).gz",
            "notes (3).txt",
            "src (2)"
        ],
        names.as_slice()
    );
    // nothing replaced
    assert_eq!(
        "notes.txt",
        fs::read_to_string(dir.join("notes.txt")).unwrap()
    );
    assert_eq!(
        "src/main.rs",
        fs::read_to_string(dir.join("src (2)/main.rs")).unwrap()
    );
}

#[test]
fn test_zip_dir() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path().join("project");
    make(
        &dir,
        &[
            "README",
            ".hidden",
            "src/main.rs",
            "src/empty/",
            "data/koil/history.json",
        ],
    );
    let mut out = Cursor::new(Vec::new());
    zip_dir(&dir, "project", &[dir.join("data/koil")], &mut out).unwrap();
    let mut zip = zip::ZipArchive::new(out).unwrap();
    let mut names: Vec<_> = zip
        .file_names()
        .map(|name| name.unwrap().into_owned())
        .collect();
    names.sort();
    // under the name, with what's hidden, and empty dirs, without what's
    // left out
    assert_eq!(
        [
            "project/",
            "project/.hidden",
            "project/README",
            "project/data/",
            "project/src/",
            "project/src/empty/",
            "project/src/main.rs"
        ],
        names.as_slice()
    );
    let mut text = String::new();
    let mut file = zip.by_name("project/src/main.rs").unwrap();
    file.read_to_string(&mut text).unwrap();
    assert_eq!("src/main.rs", text);
    // when it was modified (a moment ago), not zip's 1980
    assert!(file.last_modified().unwrap().year() > 2000);
}

#[cfg(unix)]
#[test]
fn test_zip_dir_links() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path().join("project");
    make(&dir, &["file", "sub/"]);
    std::os::unix::fs::symlink(dir.join("file"), dir.join("to-file")).unwrap();
    // a link to the dir it's in, which would never end
    std::os::unix::fs::symlink(&dir, dir.join("sub/up")).unwrap();
    let mut out = Cursor::new(Vec::new());
    zip_dir(&dir, "project", &[], &mut out).unwrap();
    let zip = zip::ZipArchive::new(out).unwrap();
    let mut names: Vec<_> = zip
        .file_names()
        .map(|name| name.unwrap().into_owned())
        .collect();
    names.sort();
    assert_eq!(
        [
            "project/",
            "project/file",
            "project/sub/",
            "project/to-file"
        ],
        names.as_slice()
    );
}

#[test]
fn test_first_visit() {
    let temp = tempfile::tempdir().unwrap();
    let home = temp.path();
    let welcome = first_visit(home).unwrap();
    assert_eq!(home.join("welcome.txt"), welcome);
    assert!(
        fs::read_to_string(&welcome)
            .unwrap()
            .starts_with("Koil in your browser\n")
    );
    // once
    assert_eq!(None, first_visit(home));
    // a file of the user's of that name stays as it is
    let temp = tempfile::tempdir().unwrap();
    fs::write(temp.path().join("welcome.txt"), "mine").unwrap();
    assert_eq!(
        Some(temp.path().join("welcome.txt")),
        first_visit(temp.path())
    );
    assert_eq!(
        "mine",
        fs::read_to_string(temp.path().join("welcome.txt")).unwrap()
    );
}
