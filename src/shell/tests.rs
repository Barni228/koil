use super::*;

/// `command` expanded for sh in `/home/me/dir`, with `files` (relative to
/// it) for `%`.
fn sh(command: &str, files: &[&str]) -> Result<String, String> {
    expanded(command, Kind::Sh, files)
}

fn expanded(command: &str, kind: Kind, files: &[&str]) -> Result<String, String> {
    let cwd = Path::new("/home/me/dir");
    let files: Vec<PathBuf> = files.iter().map(|f| cwd.join(f)).collect();
    expand(command, kind, cwd, &files, "no file")
}

#[test]
fn test_kind() {
    assert_eq!(Kind::of("/bin/zsh"), Kind::Sh);
    assert_eq!(Kind::of(r"C:\Program Files\Git\bin\bash.exe"), Kind::Sh);
    assert_eq!(Kind::of(r"C:\Windows\system32\cmd.exe"), Kind::Cmd);
    assert_eq!(Kind::of("CMD.EXE"), Kind::Cmd);
    assert_eq!(Kind::of("pwsh"), Kind::PowerShell);
    assert_eq!(
        Kind::of(r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"),
        Kind::PowerShell
    );
}

#[test]
fn test_quoted() {
    assert_eq!(quoted("src/main.rs", Kind::Sh), "src/main.rs");
    assert_eq!(quoted("café.txt", Kind::Sh), "café.txt");
    assert_eq!(quoted("my file", Kind::Sh), "'my file'");
    assert_eq!(quoted("it's", Kind::Sh), r"'it'\''s'");
    assert_eq!(quoted("$HOME", Kind::Sh), "'$HOME'");
    assert_eq!(quoted("~x", Kind::Sh), "'~x'");
    assert_eq!(quoted("", Kind::Sh), "''");
    assert_eq!(quoted(r"src\a b.rs", Kind::Cmd), r#""src\a b.rs""#);
    assert_eq!(quoted("a&b", Kind::Cmd), r#""a&b""#);
    assert_eq!(quoted(r"C:\src\a.rs", Kind::PowerShell), r"C:\src\a.rs");
    assert_eq!(quoted("it's here", Kind::PowerShell), "'it''s here'");
    assert_eq!(quoted("$x", Kind::PowerShell), "'$x'");
}

#[test]
fn test_expand() {
    assert_eq!(sh("git add %", &["a.rs"]), Ok("git add a.rs".into()));
    assert_eq!(sh("git add %", &["a b.rs"]), Ok("git add 'a b.rs'".into()));
    assert_eq!(sh("rm %", &["a", "b c"]), Ok("rm a 'b c'".into()));
    // the dir itself, one outside it, and a name like an option
    assert_eq!(sh("du %", &[""]), Ok("du .".into()));
    assert_eq!(sh("ls %", &["../x"]), Ok("ls ../x".into()));
    assert_eq!(
        expand(
            "ls %",
            Kind::Sh,
            Path::new("/a"),
            &[PathBuf::from("/b/c d")],
            ""
        ),
        Ok("ls '/b/c d'".into())
    );
    assert_eq!(sh("rm %", &["-rf"]), Ok("rm ./-rf".into()));
    // no %: as it is, and \% is a %
    assert_eq!(sh("date +\\%s", &[]), Ok("date +%s".into()));
    assert_eq!(sh(r"echo a\ b", &[]), Ok(r"echo a\ b".into()));
    assert_eq!(sh("ls %", &[]), Err("no file".into()));
}

#[test]
fn test_expand_modifiers() {
    assert_eq!(
        sh("echo %:p", &["src/a.rs"]),
        Ok("echo /home/me/dir/src/a.rs".into())
    );
    assert_eq!(sh("echo %:h", &["src/a.rs"]), Ok("echo src".into()));
    assert_eq!(sh("echo %:h", &["a.rs"]), Ok("echo .".into()));
    assert_eq!(sh("echo %:p:h", &["a.rs"]), Ok("echo /home/me/dir".into()));
    assert_eq!(sh("echo %:t", &["src/a.rs"]), Ok("echo a.rs".into()));
    assert_eq!(
        sh("echo %:r", &["src/a.tar.gz"]),
        Ok("echo src/a.tar".into())
    );
    assert_eq!(sh("echo %:e", &["src/a.rs"]), Ok("echo rs".into()));
    assert_eq!(sh("echo %:r", &[".bashrc"]), Ok("echo .bashrc".into()));
    assert_eq!(sh("echo %:e", &["Makefile"]), Ok("echo ''".into()));
    assert_eq!(sh("echo %:t:r", &["src/a.rs"]), Ok("echo a".into()));
    assert_eq!(
        expand(
            "echo %:h",
            Kind::Sh,
            Path::new("/a"),
            &[PathBuf::from("/x")],
            ""
        ),
        Ok("echo /".into())
    );
    // not a modifier: as it is
    assert_eq!(sh("echo %:x %:", &["a"]), Ok("echo a:x a:".into()));
}

#[test]
fn test_expand_in_quotes() {
    assert_eq!(sh("git add \"%\"", &["a b"]), Ok("git add \"a b\"".into()));
    assert_eq!(sh("echo \"%\"", &["$x`y"]), Ok(r#"echo "\$x\`y""#.into()));
    assert_eq!(sh("echo '%'", &["it's"]), Ok(r"echo 'it'\''s'".into()));
    // several, each a word: '' 'a b' c ''
    assert_eq!(sh("echo '%'", &["a b", "c"]), Ok("echo '''a b' c''".into()));
    // as in vim, a % in quotes is one too
    assert_eq!(sh("printf '%s'", &["a"]), Ok("printf 'as'".into()));
    // a quote that's escaped doesn't open one
    assert_eq!(sh(r#"echo \" %"#, &["a b"]), Ok(r#"echo \" 'a b'"#.into()));
    assert_eq!(
        sh(r#"echo "\"" %"#, &["a b"]),
        Ok(r#"echo "\"" 'a b'"#.into())
    );
    // cmd has no single quotes
    let cmd = |command, files: &[&str]| expanded(command, Kind::Cmd, files);
    assert_eq!(cmd("type '%'", &["a b"]), Ok("type '\"a b\"'".into()));
    assert_eq!(cmd("type \"%\"", &["a b"]), Ok("type \"a b\"".into()));
    let ps = |command, files: &[&str]| expanded(command, Kind::PowerShell, files);
    assert_eq!(ps("cat '%'", &["it's"]), Ok("cat 'it''s'".into()));
    assert_eq!(ps("cat 'x''%'", &["it's"]), Ok("cat 'x''it''s'".into()));
    assert_eq!(ps("cat \"%\"", &["$a"]), Ok("cat \"`$a\"".into()));
}

#[test]
fn test_msvc_quoted() {
    assert_eq!(msvc_quoted("ls"), r#""ls""#);
    assert_eq!(msvc_quoted(r#"echo "a b""#), r#""echo \"a b\"""#);
    assert_eq!(msvc_quoted(r"a\b\"), r#""a\b\\""#);
    assert_eq!(msvc_quoted(r#"a\"b"#), r#""a\\\"b""#);
}

#[test]
fn test_encoded() {
    assert_eq!(encoded("a"), "YQA=");
    assert_eq!(encoded("ab"), "YQBiAA==");
    assert_eq!(encoded("abc"), "YQBiAGMA");
}

#[test]
fn test_as_shown() {
    let shown = |s: &str| as_shown(s.as_bytes().to_vec(), false);
    assert_eq!(shown("a\r\nb\n\n\n"), "a\nb");
    assert_eq!(shown("\x1b[1;31mred\x1b[0m done"), "red done");
    assert_eq!(shown("\x1b]0;title\x07x\x1b]8;;url\x1b\\y"), "xy");
    assert_eq!(shown("10%\r20%\r100%\n"), "100%");
    assert_eq!(shown("abc\rx"), "xbc");
    assert_eq!(shown("b\x08bo\x08old"), "bold");
    assert_eq!(shown("a\tb\n\tc"), "a       b\n        c");
    assert_eq!(shown("a  \nb"), "a\nb");
    // kept, each a column
    let with_tabs = |s: &str| as_shown(s.as_bytes().to_vec(), true);
    assert_eq!(with_tabs("a\tb\n\tc\t\n"), "a\tb\n\tc");
    assert_eq!(with_tabs("\t10%\r\t100%"), "\t100%");
}

#[test]
fn test_shown_lines() {
    let text = (1..=SHOWN_LINES + 5)
        .map(|n| n.to_string())
        .collect::<Vec<_>>()
        .join("\n");
    let (shown, cut) = shown_lines(text, 2);
    assert_eq!(shown.lines().count(), SHOWN_LINES);
    assert_eq!(shown.lines().last(), Some(SHOWN_LINES.to_string().as_str()));
    assert_eq!(cut, 7);
    assert_eq!(shown_lines("a\nb".into(), 0), ("a\nb".into(), 0));
}

#[cfg(unix)]
mod running {
    use super::*;

    /// Runs `command` in sh, in `cwd`, with `input` for a filter.
    fn run(command: &str, cwd: &Path, input: Option<&str>) -> Ran {
        run_request(Request {
            shell: "/bin/sh".into(),
            command: command.into(),
            cwd: cwd.into(),
            input: input.map(String::from),
            ..Request::default()
        })
    }

    fn run_request(request: Request) -> Ran {
        let running = Running::default();
        let (_, started) = start(&request, &running).unwrap();
        started.finish(&running)
    }

    #[test]
    fn test_run() {
        let temp = tempfile::tempdir().unwrap();
        std::fs::write(temp.path().join("a b"), "").unwrap();
        let ran = run("ls; echo oops >&2; exit 3", temp.path(), None);
        assert_eq!(ran.output, "a b\noops");
        assert_eq!(ran.code, Some(3));
        assert!(!ran.stopped);
        // a file, with %
        let request = Request {
            shell: "/bin/sh".into(),
            command: r"printf '[\%s]' %".into(),
            cwd: temp.path().into(),
            files: vec![temp.path().join("a b")],
            ..Request::default()
        };
        let running = Running::default();
        let (line, started) = start(&request, &running).unwrap();
        assert_eq!(line, "printf '[%s]' 'a b'");
        assert_eq!(started.finish(&running).output, "[a b]");
    }

    #[test]
    fn test_filter() {
        let temp = tempfile::tempdir().unwrap();
        let ran = run("tr a-z A-Z; echo note >&2", temp.path(), Some("one\ntwo\n"));
        assert_eq!(ran.output, "ONE\nTWO");
        assert_eq!(ran.errors, "note");
        assert_eq!(ran.code, Some(0));
        // one that doesn't read it all
        let input = "x\n".repeat(1 << 20);
        assert_eq!(run("head -n 1", temp.path(), Some(&input)).output, "x");
    }

    #[test]
    fn test_scratchpad() {
        // all of it, stderr too, with its tabs
        let temp = tempfile::tempdir().unwrap();
        let command = format!("seq {}; printf 'a\\tb\\n'; echo oops >&2", SHOWN_LINES + 5);
        let ran = run_request(Request {
            shell: "/bin/sh".into(),
            command,
            cwd: temp.path().into(),
            scratchpad: true,
            ..Request::default()
        });
        let lines: Vec<&str> = ran.output.lines().collect();
        assert_eq!(lines.len(), SHOWN_LINES + 7);
        assert_eq!(lines[SHOWN_LINES + 5..], ["a\tb", "oops"]);
        assert_eq!(ran.cut, 0);
        // with the lines of a range on its stdin
        let ran = run_request(Request {
            shell: "/bin/sh".into(),
            command: "sort -r; exit 2".into(),
            cwd: temp.path().into(),
            input: Some("a\nb\n".into()),
            scratchpad: true,
            ..Request::default()
        });
        assert_eq!(ran.output, "b\na");
        assert_eq!(ran.code, Some(2));
    }

    #[test]
    fn test_cant_run() {
        let temp = tempfile::tempdir().unwrap();
        let request = Request {
            shell: "/no/such/shell".into(),
            command: "ls".into(),
            cwd: temp.path().into(),
            ..Request::default()
        };
        let running = Running::default();
        let error = start(&request, &running).err().unwrap();
        assert!(error.starts_with("Can't run /no/such/shell"), "{error}");
        assert!(!running.is_running());
        // the dir is gone
        let request = Request {
            shell: "/bin/sh".into(),
            cwd: temp.path().join("gone"),
            command: "ls".into(),
            ..Request::default()
        };
        assert!(
            start(&request, &running)
                .err()
                .unwrap()
                .ends_with("isn't there any more")
        );
    }

    #[test]
    fn test_stop() {
        let temp = tempfile::tempdir().unwrap();
        let request = Request {
            shell: "/bin/sh".into(),
            // what it starts too: the second sleep
            command: "echo started; sleep 30; sleep 30".into(),
            cwd: temp.path().into(),
            ..Request::default()
        };
        let running = Running::default();
        let (_, started) = start(&request, &running).unwrap();
        assert!(running.is_running());
        assert!(start(&request, &running).is_err());
        let stopper = running.clone();
        let begun = Instant::now();
        thread::spawn(move || {
            thread::sleep(Duration::from_millis(200));
            stopper.stop();
        });
        let ran = started.finish(&running);
        assert!(ran.stopped);
        assert_eq!(ran.output, "started");
        assert!(begun.elapsed() < Duration::from_secs(5));
        assert!(!running.is_running());
    }

    #[test]
    fn test_in_background() {
        // what it leaves running keeps its output open, which isn't waited for
        let temp = tempfile::tempdir().unwrap();
        let begun = Instant::now();
        let ran = run("sleep 5 & echo done", temp.path(), None);
        assert_eq!(ran.output, "done");
        assert!(begun.elapsed() < Duration::from_secs(3));
    }

    /// A shell named `name` in `dir`, which runs `profile`, then the
    /// command it's given (after `-l -i -c`) in sh.
    fn fake_shell(dir: &Path, name: &str, profile: &str) -> String {
        use std::os::unix::fs::PermissionsExt;
        let path = dir.join(name);
        let script = format!("#!/bin/sh\n{profile}\nexec /bin/sh -c \"$4\"\n");
        std::fs::write(&path, script).unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
        path.to_string_lossy().into_owned()
    }

    fn var<'a>(vars: &'a [(OsString, OsString)], name: &str) -> Option<&'a str> {
        let mut found = vars.iter().filter(|(n, _)| n == name);
        found.next().map(|(_, value)| value.to_str().unwrap())
    }

    #[test]
    fn test_read_environment() {
        let temp = tempfile::tempdir().unwrap();
        let second = Duration::from_secs(5);
        // what the profile prints goes around it
        let profile = "echo hello; export FROM_RC='a\nb'; export SAW=$KOIL_RESOLVING_ENVIRONMENT";
        let shell = fake_shell(temp.path(), "zsh", profile);
        let vars = read_environment(&shell, temp.path(), second).unwrap();
        assert_eq!(var(&vars, "FROM_RC"), Some("a\nb"));
        assert_eq!(var(&vars, "SAW"), Some("1"));
        assert!(var(&vars, "PATH").is_some());
        for name in NOT_ENVIRONMENT {
            assert_eq!(var(&vars, name), None);
        }
        // not a shell whose environment can be read
        let shell = fake_shell(temp.path(), "nu", "");
        assert_eq!(read_environment(&shell, temp.path(), second), None);
        // one that fails, or has no PATH
        let shell = fake_shell(temp.path(), "bash", "exit 1");
        assert_eq!(read_environment(&shell, temp.path(), second), None);
        let shell = fake_shell(temp.path(), "dash", "unset PATH");
        assert_eq!(read_environment(&shell, temp.path(), second), None);
        // one that hangs is stopped
        let shell = fake_shell(temp.path(), "ksh", "sleep 30");
        let begun = Instant::now();
        let short = Duration::from_millis(300);
        assert_eq!(read_environment(&shell, temp.path(), short), None);
        assert!(begun.elapsed() < Duration::from_secs(3));
    }
}

#[test]
fn test_between_marks() {
    let output = format!("noise{MARK}A=1\0B=x=y\0PWD=/\0\0{MARK}more");
    let vars = between_marks(output.as_bytes()).unwrap();
    let expected = [("A", "1"), ("B", "x=y")].map(|(n, v)| (n.into(), v.into()));
    assert_eq!(vars, expected);
    assert_eq!(between_marks(format!("noise{MARK}A=1\0").as_bytes()), None);
    assert_eq!(between_marks(b"noise"), None);
}
