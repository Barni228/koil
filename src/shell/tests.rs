use super::*;

/// `command` expanded for sh in `/home/me/dir`, with `files` (relative to
/// it) for `%`.
fn sh(command: &str, files: &[&str]) -> Result<String, String> {
    expanded(command, Kind::Sh, files)
}

fn expanded(command: &str, kind: Kind, files: &[&str]) -> Result<String, String> {
    let cwd = Path::new("/home/me/dir");
    let files: Vec<PathBuf> = files.iter().map(|f| cwd.join(f)).collect();
    let file = match files.is_empty() {
        true => Err("no file".to_string()),
        false => Ok(files.as_slice()),
    };
    expand(command, kind, cwd, file, Err("no cfile".to_string()))
}

/// `command` expanded for sh in `/`, with `file` for `%`, and nothing for
/// `<cfile>`.
fn in_root(command: &str, file: &str) -> Result<String, String> {
    let file = [PathBuf::from(file)];
    expand(
        command,
        Kind::Sh,
        Path::new("/a"),
        Ok(&file),
        Err(String::new()),
    )
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
    assert_eq!(in_root("ls %", "/b/c d"), Ok("ls '/b/c d'".into()));
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
    assert_eq!(in_root("echo %:h", "/x"), Ok("echo /".into()));
    // not a modifier: as it is
    assert_eq!(sh("echo %:x %:", &["a"]), Ok("echo a:x a:".into()));
}

#[test]
fn test_expand_cfile() {
    let cwd = Path::new("/home/me/dir");
    let file = [cwd.join("a b.rs")];
    let cfile = [cwd.join("src/x.rs"), cwd.join("y")];
    let sh = |command| expand(command, Kind::Sh, cwd, Ok(&file), Ok(&cfile));
    assert_eq!(sh("cp <cfile> %:h"), Ok("cp src/x.rs y .".into()));
    assert_eq!(sh("echo <cfile>:t:r"), Ok("echo x y".into()));
    assert_eq!(sh("echo \"<cfile>\""), Ok("echo \"\"src/x.rs y\"\"".into()));
    // \<cfile> is a <cfile>; anything else with < is as it is
    assert_eq!(
        sh(r"echo \<cfile> <cfil > \<a <CFILE>"),
        Ok(r"echo <cfile> <cfil > \<a <CFILE>".into())
    );
    // Only what the command has must be there.
    let none = || Err("E446".to_string());
    assert_eq!(
        expand("ls <cfile>", Kind::Sh, cwd, Ok(&file), none()),
        Err("E446".into())
    );
    assert_eq!(
        expand("ls %", Kind::Sh, cwd, Ok(&file), none()),
        Ok("ls 'a b.rs'".into())
    );
    // after cmd's escape, as %
    let cmd = expand("type ^<cfile>", Kind::Cmd, cwd, Ok(&file), Ok(&cfile));
    assert_eq!(cmd, Ok("type ^src/x.rs y".into()));
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
fn test_screen() {
    // given in pieces, it's as given at once: an escape, a character and a
    // line can each come in two
    let text = "a\x1b[1;31mred\x1b[0m\r\né\x1b]0;title\x1b\\x\n10%\r20%";
    for at in 0..=text.len() {
        let mut screen = Screen::last();
        screen.write(&text.as_bytes()[..at]);
        screen.write(&text.as_bytes()[at..]);
        screen.end();
        assert_eq!(screen.text(), "ared\néx\n20%", "cut at {at}");
        assert_eq!(screen.current(), "20%");
    }
    // the last lines are kept, and those before are counted
    let mut screen = Screen::last();
    for n in 1..=SHOWN_LINES + 5 {
        screen.write(format!("{n}\n").as_bytes());
    }
    screen.write(b"\n\n");
    assert_eq!(screen.cut(), 7);
    let text = screen.text();
    assert_eq!(text.lines().next(), Some("8"));
    assert_eq!(text.lines().count(), SHOWN_LINES - 2);
    assert_eq!(
        text.lines().last(),
        Some((SHOWN_LINES + 5).to_string().as_str())
    );
    // a line's end past SHOWN_COLUMNS is left out
    let mut screen = Screen::last();
    screen.write("x".repeat(SHOWN_COLUMNS + 9).as_bytes());
    assert_eq!(screen.current().len(), SHOWN_COLUMNS);
    // UTF-16 after its BOM, which can come a byte at a time, and what
    // isn't text
    let mut screen = Screen::last();
    for byte in [0xff, 0xfe, b'a', 0, 0x3d, 0xd8, 0x00, 0xde, b'b', 0, 7] {
        screen.write(&[byte]);
    }
    screen.end();
    assert_eq!(screen.text(), "a😀b");
    let mut screen = Screen::last();
    screen.write(&[0xef, 0xbb]);
    screen.write(&[0xbf, b'a', 0xff, b'b', 0xe2, 0x82]);
    screen.end();
    assert_eq!(screen.text(), "a\u{fffd}b\u{fffd}");
    let mut screen = Screen::last();
    screen.write(&[0xef]);
    screen.end();
    assert_eq!(screen.text(), "\u{fffd}");
}

#[test]
fn test_live() {
    let output = |reset, drop, lines: &[&str], line: &str, cut| Output {
        reset,
        drop,
        lines: lines.iter().map(|l| l.to_string()).collect(),
        line: line.to_string(),
        cut,
    };
    let mut live = Live::default();
    assert_eq!(live.due(true), None);
    live.add(b"one\ntwo\nha");
    assert_eq!(
        live.due(false),
        Some(output(false, 0, &["one", "two"], "ha", 0))
    );
    // not again so soon, but `now`
    live.add(b"lf\r");
    assert_eq!(live.due(false), None);
    assert_eq!(live.due(true), Some(output(false, 0, &[], "half", 0)));
    // nor what's the same
    live.add(b"half\r");
    assert_eq!(live.due(true), None);
    // blank lines at the end wait for what comes after them
    live.add(b"\n\n\n");
    assert_eq!(live.due(true), Some(output(false, 0, &["half"], "", 0)));
    live.add(b"\n");
    assert_eq!(live.due(true), None);
    live.add(b"x");
    assert_eq!(
        live.due(true),
        Some(output(false, 0, &["", "", ""], "x", 0))
    );
    assert_eq!(live.screen.text(), "one\ntwo\nhalf\n\n\n\nx");
    // the first lines told go as more are kept than SHOWN_LINES
    let more: String = (0..SHOWN_LINES - 4).map(|n| format!("\n{n}")).collect();
    live.add(more.as_bytes());
    let told = live.due(true).unwrap();
    assert_eq!((told.reset, told.drop, told.cut), (false, 2, 2));
    assert_eq!(told.lines.len(), SHOWN_LINES - 4);
    assert_eq!(told.lines[0], "x");
    // and all of them, once so many more were written
    let many: String = (0..2 * SHOWN_LINES).map(|n| format!("\n{n}")).collect();
    live.add(many.as_bytes());
    let told = live.due(true).unwrap();
    assert_eq!((told.reset, told.drop), (true, SHOWN_LINES));
    assert_eq!(told.lines.len(), SHOWN_LINES);
    assert_eq!(told.cut, 2 + 2 * SHOWN_LINES);
    assert_eq!(told.line, (2 * SHOWN_LINES - 1).to_string());
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
        started.finish(&running, |_| {})
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
            file: Paths {
                paths: vec![temp.path().join("a b")],
                message: String::new(),
            },
            ..Request::default()
        };
        let running = Running::default();
        let (line, started) = start(&request, &running).unwrap();
        assert_eq!(line, "printf '[%s]' 'a b'");
        assert_eq!(started.finish(&running, |_| {}).output, "[a b]");
        // <cfile> with none: vim's error, or why
        let request = Request {
            command: "ls <cfile>".into(),
            ..request
        };
        let e446 = "E446: No file name under cursor".to_string();
        assert_eq!(start(&request, &running).err(), Some(e446));
        let request = Request {
            cfile: Paths {
                paths: Vec::new(),
                message: "No path on this line".into(),
            },
            ..request
        };
        let why = "No path on this line".to_string();
        assert_eq!(start(&request, &running).err(), Some(why));
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
        let ran = started.finish(&running, |_| {});
        assert!(ran.stopped);
        assert_eq!(ran.output, "started");
        assert!(begun.elapsed() < Duration::from_secs(5));
        assert!(!running.is_running());
    }

    #[test]
    fn test_live_output() {
        // what it writes is told as it comes: a progress bar as \r wrote it
        // last, and in the end all of it, as `output` has it
        let temp = tempfile::tempdir().unwrap();
        let request = |input: Option<&str>| Request {
            shell: "/bin/sh".into(),
            command:
                r"printf 'one\nhalf\r'; sleep 0.4; printf 'most\r'; sleep 0.4; printf '\ndone\n\n'"
                    .into(),
            cwd: temp.path().into(),
            input: input.map(String::from),
            ..Request::default()
        };
        let running = Running::default();
        let (_, started) = start(&request(None), &running).unwrap();
        let mut told = Vec::new();
        let ran = started.finish(&running, |output| told.push(output));
        let lines: Vec<&str> = told
            .iter()
            .flat_map(|o| o.lines.iter().map(String::as_str))
            .collect();
        let current: Vec<&str> = told.iter().map(|o| o.line.as_str()).collect();
        assert_eq!(lines, ["one", "most", "done"]);
        assert_eq!(current, ["half", "most", ""]);
        assert!(told.iter().all(|o| !o.reset && o.drop == 0 && o.cut == 0));
        assert_eq!(ran.output, "one\nmost\ndone");
        // not a filter's, which are the lines it gives back
        let (_, started) = start(&request(Some("a")), &running).unwrap();
        let mut told = Vec::new();
        let ran = started.finish(&running, |output| told.push(output));
        assert_eq!(told, []);
        assert_eq!(ran.output, "one\nhalf\rmost\ndone\n");
        // the last lines of a long one, and how many came before
        let mut told = Vec::new();
        let (_, started) = start(
            &Request {
                shell: "/bin/sh".into(),
                command: "seq 1 3000".into(),
                cwd: temp.path().into(),
                ..Request::default()
            },
            &running,
        )
        .unwrap();
        let ran = started.finish(&running, |output| told.push(output));
        assert_eq!(ran.cut, 3000 - SHOWN_LINES);
        assert_eq!(ran.output.lines().count(), SHOWN_LINES);
        assert_eq!(ran.output.lines().last(), Some("3000"));
        assert_eq!(told.last().unwrap().cut, ran.cut);
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
