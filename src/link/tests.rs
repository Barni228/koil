use std::fs;

use super::*;

/// The link in `line` at the first `|` (taken out), as its text.
fn link(line: &str, names: bool) -> Option<String> {
    let at = line.find('|').expect("a | marks where");
    let units: Vec<u16> = line.replacen('|', "", 1).encode_utf16().collect();
    let at = line[..at].encode_utf16().count();
    link_at(&units, at, names).map(|r| String::from_utf16(&units[r]).unwrap())
}

#[test]
fn urls_and_paths() {
    let url = Some("https://example.com/a?b=1".to_string());
    assert_eq!(link("see |https://example.com/a?b=1.", false), url);
    assert_eq!(link("see https://example.com/a|?b=1.", false), url);
    assert_eq!(
        link("(at ~/src/ko|il/main.rs)", false),
        Some("~/src/koil/main.rs".into())
    );
    assert_eq!(link("open src/main.rs|:42", false), None);
    assert_eq!(
        link("open src/main.r|s:42", false),
        Some("src/main.rs".into())
    );
    // a word isn't a link, unless gf or gx takes it as a file name
    assert_eq!(link("edit Cargo.t|oml", false), None);
    assert_eq!(link("edit Cargo.t|oml", true), Some("Cargo.toml".into()));
}

#[test]
fn file_names() {
    assert_eq!(link("see READ|ME.md.", true), Some("README.md".into()));
    assert_eq!(link("up to ..|", true), Some("..".into()));
    // the first one after the cursor, on the line only
    assert_eq!(link("|  (notes.txt)", true), Some("notes.txt".into()));
    assert_eq!(link("(|)", true), None);
    assert_eq!(link("|", true), None);
    // an escaped space goes on, as in a shell (on Windows, `\` separates)
    #[cfg(unix)]
    {
        assert_eq!(
            link("cat my\\ fi|le.txt", true),
            Some("my\\ file.txt".into())
        );
        assert_eq!(
            link("cat my|\\ file.txt", true),
            Some("my\\ file.txt".into())
        );
    }
    // after an emoji, in UTF-16
    assert_eq!(link("🍄 dir/fi|le", true), Some("dir/file".into()));
}

#[test]
fn urls() {
    let url = |s: &str| Target::Url(s.to_string());
    assert_eq!(
        target("https://example.com", &[]),
        url("https://example.com")
    );
    assert_eq!(target(" ssh://host ", &[]), url("ssh://host"));
    assert_eq!(
        target("www.example.com/a", &[]),
        url("https://www.example.com/a")
    );
    let empty = Target::Error("E446: No file name under cursor".into());
    assert_eq!(target("  ", &[]), empty);
    assert_eq!(target("a\nb", &[]), empty);
}

#[test]
fn paths() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path().canonicalize().unwrap();
    let (here, there) = (root.join("here"), root.join("there"));
    fs::create_dir_all(here.join("sub")).unwrap();
    fs::create_dir_all(&there).unwrap();
    fs::write(here.join("a.txt"), "").unwrap();
    fs::write(there.join("a.txt"), "").unwrap();
    fs::write(there.join("b.txt"), "").unwrap();
    fs::write(there.join("my file"), "").unwrap();
    let dirs = [here.clone(), there.clone()];
    let path = |p: &Path| Target::Path(with_slashes(p).to_string_lossy().into_owned());

    // in the first dir that has it
    assert_eq!(target("a.txt", &dirs), path(&here.join("a.txt")));
    assert_eq!(target("b.txt", &dirs), path(&there.join("b.txt")));
    assert_eq!(target("./sub/", &dirs), path(&here.join("sub")));
    assert_eq!(
        target("sub/../../there/b.txt", &dirs),
        path(&there.join("b.txt"))
    );
    let absolute = there.join("a.txt");
    assert_eq!(target(&absolute.to_string_lossy(), &[]), path(&absolute));
    assert_eq!(
        target("c.txt", &dirs),
        Target::Error("E447: Can't find file \"c.txt\" in path".into())
    );
    #[cfg(unix)]
    {
        assert_eq!(target("my\\ file", &dirs), path(&there.join("my file")));
        let url = format!("file://{}", there.join("my file").display()).replace(' ', "%20");
        assert_eq!(target(&url, &[]), path(&there.join("my file")));
    }
    let home = std::env::home_dir().unwrap();
    assert_eq!(target("~", &[]), path(&home));
}
