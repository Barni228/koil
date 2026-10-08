use std::ffi::OsString;
use std::io::{IsTerminal, Read, Stdin};
use std::sync::Mutex;

use clap::error::ErrorKind;
use clap::{Arg, ArgMatches, Command, arg, command};

use crate::document;

/// What Koil starts with, as the command line says.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct Args {
    /// The dir, pattern or file to open, as written.
    pub path: Option<String>,
    /// Whether Koil starts in the scratchpad: `-s` (`-t`), or text from
    /// stdin.
    pub scratchpad: bool,
    /// Whether to read stdin even if it's a terminal (`-`).
    pub stdin: bool,
    /// The line to put the cursor on (`+N`), 0 for the last one (`+`).
    pub line: Option<u32>,
    /// The scratchpad's text, from stdin (see `read_stdin`).
    pub text: Option<String>,
}

/// The command line Koil was started with, for the Document to give QML:
/// `main` sets it before the app runs.
pub static ARGS: Mutex<Args> = Mutex::new(Args {
    path: None,
    scratchpad: false,
    stdin: false,
    line: None,
    text: None,
});

/// command line options, which `parse` reads. clap fills the positionals in
/// order, but `+N` and `-` can come before the path or after it, so they're
/// told apart by what they are; `[+N]` is only there for the help. After
/// `--`, every one is a path (`escaped`), as in vim, even `-` or `+N`.
pub fn command() -> Command {
    command!()
        .about("Koil edits a directory as text, with vim's keys.")
        .arg(
            arg!(-s --scratchpad "Start in the scratchpad, over PATH's listing")
                .visible_short_alias('t')
                .visible_alias("temp"),
        )
        .arg(arg!([PATH] "A directory, or a glob or regex of files, to list, or a file to edit"))
        .arg(arg!([line] "Put the cursor on line N (+ alone: the last line)").value_name("+N"))
        .arg(Arg::new("more").num_args(0..).hide(true))
        .arg(Arg::new("escaped").num_args(0..).last(true).hide(true))
        .after_help(
            "Without a PATH, Koil lists the Start in setting's directory, or else your\n\
             home directory. A PATH of - puts the text read from stdin in the\n\
             scratchpad, as does text piped in (git diff | koil).",
        )
}

/// Reads the command line `args`, the program's name first. Qt is given
/// them too (cxx-qt passes it all of them), so options it reads
/// (`-platform`, `-style`, `-reverse`) can't be Koil's, and here they're
/// unknown: Qt's environment variables (`QT_QPA_PLATFORM`) still work. The
/// error is clap's, `--help` and `--version` too, which `exit` prints.
pub fn parse(args: impl IntoIterator<Item = impl Into<OsString>>) -> Result<Args, clap::Error> {
    // The process serial number older macOS gives an app it launches, which
    // clap would read as -p, -s, -n and so on.
    let args = args
        .into_iter()
        .map(Into::into)
        .filter(|arg| !arg.to_string_lossy().starts_with("-psn_"));
    let mut command = command();
    let matches = command.try_get_matches_from_mut(args)?;
    let mut parsed = Args {
        scratchpad: matches.get_flag("scratchpad"),
        ..Args::default()
    };
    let mut paths = values(&matches, "escaped");
    for arg in ["PATH", "line", "more"]
        .into_iter()
        .flat_map(|id| values(&matches, id))
    {
        if arg == "-" {
            parsed.stdin = true;
        } else if let Some(n) = arg.strip_prefix('+') {
            let line = line(n).ok_or_else(|| {
                let message = format!("'{arg}' isn't a line number, like +42");
                command.error(ErrorKind::ValueValidation, message)
            })?;
            parsed.line = Some(line);
        } else {
            paths.push(arg);
        }
    }
    if paths.len() > 1 {
        // Most likely a pattern the shell expanded.
        let message = format!(
            "one PATH at a time, not {}\n\n  \
             tip: quote a pattern, like '*.rs', for Koil to read it, not the shell",
            paths.len()
        );
        return Err(command.error(ErrorKind::TooManyValues, message));
    }
    parsed.path = paths.pop();
    Ok(parsed)
}

/// The values the command line gave the argument `id`.
fn values(matches: &ArgMatches, id: &str) -> Vec<String> {
    matches
        .get_many::<String>(id)
        .map_or_else(Vec::new, |values| values.cloned().collect())
}

/// The line `+N` stands for, `n` being what's after the `+`, as vim reads
/// it: 0 (the last line) for none, and the first line for 0.
fn line(n: &str) -> Option<u32> {
    match n {
        "" => Some(0),
        n => n.parse::<u32>().ok().map(|n| n.max(1)),
    }
}

/// Puts what's read from stdin in `args.text` if it's asked for (`-`), from
/// a terminal until Ctrl-D, or else if it's a pipe or a file (`< notes.txt`)
/// and has something in it; either way, Koil then starts in the scratchpad.
/// It's read to its end before the window opens, as vim's `-` does.
pub fn read_stdin(args: &mut Args) {
    let stdin = std::io::stdin();
    if !args.stdin && !piped(&stdin) {
        return;
    }
    if stdin.is_terminal() {
        let end = if cfg!(windows) {
            "Ctrl-Z, Enter"
        } else {
            "Ctrl-D"
        };
        eprintln!("koil: reading the scratchpad's text from stdin, until {end}");
    }
    let mut bytes = Vec::new();
    // What it could read, if something went wrong after.
    let _ = stdin.lock().read_to_end(&mut bytes);
    if args.stdin || !bytes.is_empty() {
        args.text = Some(document::decode_lossy(bytes));
        args.scratchpad = true;
    }
}

/// Whether stdin is a pipe or a file. Not a terminal, nor `/dev/null`,
/// which an app launched from Finder or the Dock has, nor a device that
/// never ends, like `/dev/zero`.
#[cfg(unix)]
fn piped(stdin: &Stdin) -> bool {
    use std::fs::File;
    use std::os::fd::AsFd;
    use std::os::unix::fs::FileTypeExt;

    let Ok(fd) = stdin.as_fd().try_clone_to_owned() else {
        return false;
    };
    File::from(fd)
        .metadata()
        .is_ok_and(|meta| meta.file_type().is_fifo() || meta.is_file())
}

/// Whether stdin is a pipe or a file: not a console. An app launched from
/// Explorer has none, which reads as empty.
#[cfg(windows)]
fn piped(stdin: &Stdin) -> bool {
    !stdin.is_terminal()
}

/// Has what's printed next show in the console Koil was started from, on
/// Windows, where a release build is a GUI app, which has none of its own:
/// `--help` would show nothing. Not if its output goes somewhere already
/// (`koil --help > help.txt`). Untried.
pub fn attach_console() {
    #[cfg(windows)]
    {
        use std::os::windows::io::AsRawHandle;

        const ATTACH_PARENT_PROCESS: u32 = u32::MAX;
        unsafe extern "system" {
            fn AttachConsole(process_id: u32) -> i32;
        }
        if std::io::stdout().as_raw_handle().is_null() {
            // SAFETY: it only fails if there's no console to attach to.
            unsafe { AttachConsole(ATTACH_PARENT_PROCESS) };
        }
    }
}

#[cfg(test)]
mod tests {
    use clap::error::ErrorKind;

    use super::*;

    fn parse(args: &[&str]) -> Result<Args, clap::Error> {
        super::parse(std::iter::once("koil").chain(args.iter().copied()))
    }

    fn run(args: &[&str]) -> Args {
        parse(args).unwrap_or_else(|err| panic!("{args:?} gave {err}"))
    }

    fn error(args: &[&str]) -> ErrorKind {
        parse(args).expect_err("an error").kind()
    }

    #[test]
    fn test_command() {
        command().debug_assert();
    }

    #[test]
    fn test_parse() {
        assert_eq!(run(&[]), Args::default());
        assert_eq!(run(&["src"]).path.as_deref(), Some("src"));
        for flag in ["-s", "--scratchpad", "-t", "--temp"] {
            let args = run(&[flag, "src"]);
            assert!(args.scratchpad);
            assert_eq!(args.path.as_deref(), Some("src"));
        }
        let args = run(&["-"]);
        assert!(args.stdin && !args.scratchpad && args.path.is_none());
        let args = run(&["src", "-"]);
        assert!(args.stdin);
        assert_eq!(args.path.as_deref(), Some("src"));
        assert_eq!(run(&["-psn_0_1234"]), Args::default());
        assert_eq!(error(&["-s", "--help", "--bogus"]), ErrorKind::DisplayHelp);
        assert_eq!(error(&["-h"]), ErrorKind::DisplayHelp);
        assert_eq!(error(&["-V"]), ErrorKind::DisplayVersion);
        assert_eq!(error(&["--bogus", "--help"]), ErrorKind::UnknownArgument);
        assert_eq!(
            error(&["-platform", "offscreen"]),
            ErrorKind::UnknownArgument
        );
        assert_eq!(error(&["a.rs", "b.rs"]), ErrorKind::TooManyValues);
        assert_eq!(error(&["a.rs", "b.rs", "c.rs"]), ErrorKind::TooManyValues);
        let message = parse(&["a.rs", "b.rs"]).unwrap_err().to_string();
        assert!(message.contains("one PATH at a time, not 2"), "{message}");
    }

    #[test]
    fn test_parse_after_dashes() {
        let args = run(&["-s", "--", "-s"]);
        assert!(args.scratchpad);
        assert_eq!(args.path.as_deref(), Some("-s"));
        let args = run(&["--", "-"]);
        assert!(!args.stdin);
        assert_eq!(args.path.as_deref(), Some("-"));
        let args = run(&["--", "+3"]);
        assert_eq!(args.line, None);
        assert_eq!(args.path.as_deref(), Some("+3"));
        assert_eq!(run(&["--", "--"]).path.as_deref(), Some("--"));
        assert_eq!(run(&["+3", "--", "a"]).line, Some(3));
        assert_eq!(error(&["--", "a", "b"]), ErrorKind::TooManyValues);
        assert_eq!(error(&["a", "--", "b"]), ErrorKind::TooManyValues);
    }

    #[test]
    fn test_parse_line() {
        let args = run(&["+42", "notes.txt"]);
        assert_eq!(args.line, Some(42));
        assert_eq!(args.path.as_deref(), Some("notes.txt"));
        let args = run(&["notes.txt", "+42"]);
        assert_eq!(args.line, Some(42));
        assert_eq!(args.path.as_deref(), Some("notes.txt"));
        let args = run(&["-", "+3", "src"]);
        assert!(args.stdin);
        assert_eq!(args.line, Some(3));
        assert_eq!(args.path.as_deref(), Some("src"));
        assert_eq!(run(&["+"]).line, Some(0));
        assert_eq!(run(&["+0"]).line, Some(1));
        assert_eq!(run(&["+1", "+7"]).line, Some(7));
        assert_eq!(error(&["+x"]), ErrorKind::ValueValidation);
        assert_eq!(error(&["+-1"]), ErrorKind::ValueValidation);
    }
}
