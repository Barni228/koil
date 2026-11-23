//! Shell commands, as vim's `:!`: `:!cmd` runs `cmd` in the dir Koil has
//! open, with `%` in it for the entries (or the file) it's run on, and a
//! filter (`:{range}!cmd`) puts lines through it, and `:_!cmd` puts what
//! it writes in the scratchpad (see `Request`).
//! It runs in the shell the `shell` setting names, else the system's (see
//! `default_shell`), whose kind says how the command line is passed and how
//! a path is quoted in it (see `Kind`). One runs at a time, on another
//! thread, while Koil waits for it; `Running::stop` ends it.

use std::collections::VecDeque;
use std::env;
use std::ffi::OsString;
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, SyncSender};
use std::sync::{Arc, Mutex, MutexGuard, OnceLock, PoisonError};
use std::thread;
use std::time::{Duration, Instant};

use cxx_qt_lib::{QByteArray, QByteArrayBase64Options};
use serde::{Deserialize, Serialize};

use crate::{document, listing};

/// How much of a command's output (stdout and stderr together) is kept to
/// show, its last lines: how many of them, of how many bytes together, and
/// how long a line may be, in characters (see `Screen::last`).
const SHOWN_LINES: usize = 1000;
const SHOWN_BYTES: usize = 1 << 20;
const SHOWN_COLUMNS: usize = 1 << 16;
/// How much of a filter's output (or one for the scratchpad) is kept: past
/// that, it isn't put in, as the lines would be lost (or the rest of it).
const FILTER_BYTES: usize = 256 << 20;
/// How often a command that's running is checked for having ended.
const POLL: Duration = Duration::from_millis(50);
/// How long what a command started (`&`) may keep its output open after
/// it ended, before Koil stops reading it.
const AFTER_EXIT: Duration = Duration::from_millis(500);
/// How long a command `stop` sent Ctrl-C's signal has to end, before it's
/// killed.
const KILL_AFTER: Duration = Duration::from_secs(1);
/// How often what a running command wrote is told at most (see `Live`).
const LIVE_EVERY: Duration = Duration::from_millis(100);

/// The shells whose environment can be read (see `environment`), and that
/// get `-l` if it couldn't be, so they read the profile at least, as
/// MacVim's do. csh and tcsh take `-l` only on its own.
const LOGIN_SHELLS: [&str; 6] = ["sh", "bash", "zsh", "fish", "dash", "ksh"];
/// How long reading the user's shell's environment may take (as long as
/// VS Code gives it), after which it's stopped.
const ENVIRONMENT_TIMEOUT: Duration = Duration::from_secs(10);
/// What the environment is printed between, as a shell's profile may
/// print something of its own.
const MARK: &str = "__KOIL_ENVIRONMENT__";
/// Set while the environment is read, so a profile can leave out what
/// takes long, as VS Code's `VSCODE_RESOLVING_ENVIRONMENT`.
const READING: &str = "KOIL_RESOLVING_ENVIRONMENT";
/// What a shell prints that's its own, not the environment it sets up
/// (where it was, how deep it is), or this read's.
const NOT_ENVIRONMENT: [&str; 5] = ["PWD", "OLDPWD", "SHLVL", "_", READING];

/// cmd.exe and the shells it starts get no console window.
#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

/// How a shell reads its command line.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    /// sh, bash, zsh, fish, Git Bash and the like: `-c`, and single quotes.
    Sh,
    /// cmd.exe: `/s /c`, and double quotes.
    Cmd,
    /// Windows PowerShell and PowerShell 7: the command encoded, and single
    /// quotes.
    PowerShell,
}

impl Kind {
    /// The kind of `shell` (a path, or a name on the PATH), by its name:
    /// sh's, unless it's cmd's or PowerShell's.
    pub fn of(shell: &str) -> Kind {
        match program_name(shell).as_str() {
            "cmd" => Kind::Cmd,
            "powershell" | "pwsh" => Kind::PowerShell,
            _ => Kind::Sh,
        }
    }
}

/// The name of the program `shell`, in lowercase, without its dir or
/// `.exe`: `bash` for `C:\Program Files\Git\bin\bash.exe`, also on Unix.
fn program_name(shell: &str) -> String {
    let name = shell.rsplit(['/', '\\']).next().unwrap_or(shell);
    let name = name.to_lowercase();
    match name.strip_suffix(".exe") {
        Some(stem) => stem.to_string(),
        None => name,
    }
}

/// The shell commands run in when the setting names none: `$SHELL` (else
/// `/bin/sh`), or on Windows cmd.exe (`%ComSpec%`), as in vim.
pub fn default_shell() -> String {
    let (var, fallback) = match cfg!(windows) {
        true => ("ComSpec", "cmd.exe"),
        false => ("SHELL", "/bin/sh"),
    };
    (env::var(var).ok())
        .filter(|shell| !shell.is_empty())
        .unwrap_or_else(|| fallback.to_string())
}

/// A shell the Settings window offers.
#[derive(Debug, PartialEq, Eq, Serialize)]
pub struct Found {
    /// What it's called: `zsh`, `Git Bash`.
    pub name: String,
    pub path: String,
}

/// The shells installed: those in `/etc/shells`, or on Windows cmd.exe,
/// both PowerShells and Git Bash, if they're there.
pub fn shells() -> Vec<Found> {
    let mut found: Vec<Found> = Vec::new();
    let mut add = |name: &str, path: PathBuf| {
        let path = path.to_string_lossy().into_owned();
        let known = |f: &Found| f.path.eq_ignore_ascii_case(&path);
        if Path::new(&path).is_file() && !found.iter().any(known) {
            let name = name.to_string();
            found.push(Found { name, path });
        }
    };
    #[cfg(not(windows))]
    {
        let list = std::fs::read_to_string("/etc/shells").unwrap_or_default();
        for line in list.lines().map(str::trim) {
            if line.starts_with('/') {
                add(&program_name(line), PathBuf::from(line));
            }
        }
        add(&program_name(&default_shell()), default_shell().into());
    }
    #[cfg(windows)]
    {
        let under =
            |var: &str, rest: &str| env::var_os(var).map(|dir| PathBuf::from(dir).join(rest));
        let candidates = [
            ("Command Prompt", env::var_os("ComSpec").map(PathBuf::from)),
            (
                "Windows PowerShell",
                under(
                    "SystemRoot",
                    r"System32\WindowsPowerShell\v1.0\powershell.exe",
                ),
            ),
            (
                "PowerShell 7",
                under("ProgramFiles", r"PowerShell\7\pwsh.exe"),
            ),
            ("PowerShell 7", on_path("pwsh.exe")),
            ("Git Bash", under("ProgramFiles", r"Git\bin\bash.exe")),
            ("Git Bash", under("ProgramFiles(x86)", r"Git\bin\bash.exe")),
            (
                "Git Bash",
                under("LOCALAPPDATA", r"Programs\Git\bin\bash.exe"),
            ),
            ("Git Bash", git_bash()),
        ];
        for (name, path) in candidates {
            if let Some(path) = path {
                add(name, path);
            }
        }
    }
    found
}

/// Where `program` is on the PATH.
#[cfg(windows)]
fn on_path(program: &str) -> Option<PathBuf> {
    let path = env::var_os("PATH")?;
    env::split_paths(&path)
        .map(|dir| dir.join(program))
        .find(|file| file.is_file())
}

/// Git Bash, from where git is on the PATH: Git's `bin\bash.exe`, which
/// sets up its PATH (not `usr\bin\bash.exe`), with git in its `cmd` (or
/// `mingw64\bin`).
#[cfg(windows)]
fn git_bash() -> Option<PathBuf> {
    let git = on_path("git.exe")?;
    (git.ancestors().skip(1).take(3))
        .map(|dir| dir.join(r"bin\bash.exe"))
        .find(|bash| bash.is_file())
}

/// A command to run, as QML gives it (as JSON).
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct Request {
    /// The shell, as the setting names it: a path, or a name on the PATH.
    pub shell: String,
    /// As typed after `:!`.
    pub command: String,
    /// The dir it runs in: the one Koil has open, or the home dir while
    /// that's the drives (see [`Request::dir`]).
    pub cwd: PathBuf,
    /// What `%` stands for: the entries on the lines it's run on (in the
    /// listing), or the file (the scratchpad's own, see
    /// `Document::write_scratchpad`).
    pub file: Paths,
    /// What `<cfile>` stands for: the paths written on the lines it's run
    /// on (in the listing, their entries).
    pub cfile: Paths,
    /// The lines a filter (or one for the scratchpad) puts through it,
    /// which it gets on its stdin; none for a command whose output is
    /// shown, which gets nothing there.
    pub input: Option<String>,
    /// Whether what it writes goes in the scratchpad (`:_!`): stdout and
    /// stderr together, as for one whose output is shown, but all of it,
    /// and with its tabs.
    pub scratchpad: bool,
    /// Whether it runs in the environment read from the user's shell (see
    /// `environment`), as the Settings window says; else, in Koil's, in a
    /// login shell on macOS.
    pub environment: bool,
}

/// The paths `%` or `<cfile>` stands for in a command, each absolute, or
/// else why there are none, as Koil gives them (`{ paths, message }`).
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct Paths {
    pub paths: Vec<PathBuf>,
    pub message: String,
}

impl Request {
    /// The dir it runs in: `cwd`, but the home dir for the drives (see
    /// `Koil::shows_drives`), `/`, which is no dir on disk, though Windows
    /// would run it in its current drive's root.
    fn dir(&self) -> PathBuf {
        match koil_core::in_drives(&self.cwd) {
            true => env::home_dir().unwrap_or_else(|| self.cwd.clone()),
            false => self.cwd.clone(),
        }
    }
}

impl Paths {
    /// `paths`, or if there are none, why: `message`, or else `why`.
    fn or(&self, why: &str) -> Result<&[PathBuf], String> {
        match (self.paths.is_empty(), self.message.as_str()) {
            (false, _) => Ok(&self.paths),
            (true, "") => Err(why.to_string()),
            (true, message) => Err(message.to_string()),
        }
    }
}

/// What a command did.
#[derive(Debug, Default, PartialEq, Eq, Serialize)]
pub struct Ran {
    /// What it wrote: a filter's stdout as it is (but `\r\n`, and the line
    /// break at its end), or else stdout and stderr together, as shown (see
    /// `as_shown`; all of it, with its tabs, for the scratchpad).
    pub output: String,
    /// What a filter wrote to stderr, as shown.
    pub errors: String,
    /// How many lines of what's shown were left out, as it was too long:
    /// its first ones, as a terminal keeps the last.
    pub cut: usize,
    /// Its exit code; none if a signal ended it.
    pub code: Option<i32>,
    /// Whether `Running::stop` ended it.
    pub stopped: bool,
    /// Why a filter's output (or the scratchpad's) can't be put in, or why
    /// waiting failed.
    pub error: String,
}

/// The command running, if any, which `stop` ends.
#[derive(Debug, Default, Clone)]
pub struct Running(Arc<Mutex<Option<Process>>>);

#[derive(Debug)]
struct Process {
    pid: u32,
    stopped: bool,
}

impl Running {
    pub fn is_running(&self) -> bool {
        self.lock().is_some()
    }

    fn lock(&self) -> MutexGuard<'_, Option<Process>> {
        self.0.lock().unwrap_or_else(PoisonError::into_inner)
    }

    fn start(&self, pid: u32) {
        *self.lock() = Some(Process {
            pid,
            stopped: false,
        });
    }

    /// The command ended: whether `stop` ended it.
    fn end(&self) -> bool {
        self.lock().take().is_some_and(|p| p.stopped)
    }

    /// Ends the command running, and what it started: sends them Ctrl-C's
    /// signal, and kills them if they're still there a moment later (on
    /// Windows, kills them at once).
    pub fn stop(&self) {
        let pid = match self.lock().as_mut() {
            Some(process) => {
                process.stopped = true;
                process.pid
            }
            None => return,
        };
        signal(pid, false);
        let running = self.clone();
        thread::spawn(move || {
            thread::sleep(KILL_AFTER);
            if running.lock().as_ref().is_some_and(|p| p.pid == pid) {
                signal(pid, true);
            }
        });
    }
}

/// Sends the command `pid` and what it started (its process group, see
/// `command`) Ctrl-C's signal, or with `kill`, kills them. On Windows,
/// kills its process tree either way.
fn signal(pid: u32, kill: bool) {
    #[cfg(unix)]
    {
        let Ok(group) = libc::pid_t::try_from(pid) else {
            return;
        };
        let signal = if kill { libc::SIGKILL } else { libc::SIGINT };
        // SAFETY: kill only sends a signal; a group that's gone is an error
        // it returns, which doesn't matter here.
        unsafe { libc::kill(-group, signal) };
    }
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        let _ = kill;
        let _ = Command::new("taskkill")
            .args(["/T", "/F", "/PID", &pid.to_string()])
            .creation_flags(CREATE_NO_WINDOW)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }
}

/// A command started (see `start`), whose output is being read.
pub struct Started {
    child: Child,
    /// What it writes, as it comes: from stdout (0; stderr too, unless it's
    /// a filter) or stderr (1), and `None` once that's closed.
    output: Receiver<(usize, Option<Vec<u8>>)>,
    filter: bool,
    scratchpad: bool,
}

/// Starts `request`'s command: returns the command line as it runs, with
/// the files `%` and `<cfile>` stand for, and the command, to `finish`
/// (on another thread); or else why it can't run.
pub fn start(request: &Request, running: &Running) -> Result<(String, Started), String> {
    if running.is_running() {
        return Err("A command is still running".to_string());
    }
    let kind = Kind::of(&request.shell);
    let file = request.file.or("E499: Empty file name for '%'");
    let cfile = request.cfile.or("E446: No file name under cursor");
    let cwd = request.dir();
    let line = expand(&request.command, kind, &cwd, file, cfile)?;
    if !cwd.is_dir() {
        let shown = listing::show_path(&cwd);
        return Err(format!("“{shown}” isn't there any more"));
    }
    let cant = |err: io::Error| format!("Can't run {}: {err}", request.shell);
    let mut command = command(&request.shell, &line, &cwd, request.environment);
    let filter = request.input.is_some() && !request.scratchpad;
    let (sender, output) = mpsc::sync_channel(16);
    let mut child;
    command.stdin(if request.input.is_some() {
        Stdio::piped()
    } else {
        Stdio::null()
    });
    if filter {
        command.stdout(Stdio::piped()).stderr(Stdio::piped());
        child = command.spawn().map_err(cant)?;
        read(child.stdout.take(), 0, sender.clone());
        read(child.stderr.take(), 1, sender);
    } else {
        // Both through one pipe, so they're in the order they were written.
        let (reader, writer) = io::pipe().map_err(cant)?;
        command
            .stdout(writer.try_clone().map_err(cant)?)
            .stderr(writer);
        child = command.spawn().map_err(cant)?;
        // Its ends of the pipe, without which reading would never end.
        drop(command);
        read(Some(reader), 0, sender);
    }
    running.start(child.id());
    if let (Some(input), Some(mut stdin)) = (request.input.clone(), child.stdin.take()) {
        // A command that ends without reading all of it makes this fail,
        // which doesn't matter.
        thread::spawn(move || stdin.write_all(input.as_bytes()));
    }
    let started = Started {
        child,
        output,
        filter,
        scratchpad: request.scratchpad,
    };
    Ok((line, started))
}

/// Sends what `reader` reads to `sender`, as `stream`'s, from another
/// thread, then `None` once it's done.
fn read(
    reader: Option<impl Read + Send + 'static>,
    stream: usize,
    sender: SyncSender<(usize, Option<Vec<u8>>)>,
) {
    thread::spawn(move || {
        if let Some(mut reader) = reader {
            let mut buffer = vec![0; 64 << 10];
            while let Ok(n @ 1..) = reader.read(&mut buffer) {
                if sender.send((stream, Some(buffer[..n].to_vec()))).is_err() {
                    return;
                }
            }
        }
        let _ = sender.send((stream, None));
    });
}

impl Started {
    /// Waits for the command to end, keeping what it writes, and a moment
    /// longer for what it started (`&`), if that still has its output open.
    /// Meanwhile `tell` gets what it wrote since, as shown (see `Live`),
    /// and all of it has been told once this returns; not a filter's, whose
    /// output is the lines it gives back.
    pub fn finish(mut self, running: &Running, mut tell: impl FnMut(Output)) -> Ran {
        // A filter's stdout and what goes in the scratchpad are kept as
        // written; what's shown, as shown (the scratchpad's too, while it
        // runs).
        let mut kept = Kept::new(FILTER_BYTES);
        let mut live = Live::default();
        let mut errors = Screen::last();
        let mut open = if self.filter { 2 } else { 1 };
        let mut ended: Option<Instant> = None;
        let mut status = None;
        while open > 0 {
            let wait = match ended {
                Some(at) => AFTER_EXIT.saturating_sub(at.elapsed()),
                None => POLL,
            };
            match self.output.recv_timeout(wait) {
                Ok((0, Some(bytes))) => {
                    if self.filter || self.scratchpad {
                        kept.add(&bytes);
                    }
                    if !self.filter {
                        live.add(&bytes);
                    }
                }
                Ok((_, Some(bytes))) => errors.write(&bytes),
                Ok((_, None)) => open -= 1,
                Err(RecvTimeoutError::Timeout) if ended.is_some() => break,
                Err(RecvTimeoutError::Timeout) => {}
                Err(RecvTimeoutError::Disconnected) => break,
            }
            if let Some(output) = live.due(false) {
                tell(output);
            }
            if ended.is_none()
                && let Ok(Some(s)) = self.child.try_wait()
            {
                status = Some(s);
                ended = Some(Instant::now());
            }
        }
        // It closed its output, but may still run.
        let status = match status {
            Some(status) => Ok(status),
            None => self.child.wait(),
        };
        let stopped = running.end();
        live.screen.end();
        errors.end();
        if let Some(output) = live.due(true) {
            tell(output);
        }
        let mut ran = Ran {
            code: status.as_ref().ok().and_then(|s| s.code()),
            stopped,
            error: status.err().map(|e| e.to_string()).unwrap_or_default(),
            ..Ran::default()
        };
        if kept.over {
            ran.error = "The output is too long to put in".to_string();
        }
        if self.filter {
            let output = document::decode_lossy(kept.bytes).replace("\r\n", "\n");
            ran.output = match output.strip_suffix('\n') {
                Some(output) => output.to_string(),
                None => output,
            };
            (ran.errors, ran.cut) = (errors.text(), errors.cut());
        } else if self.scratchpad {
            ran.output = as_shown(kept.bytes, true);
        } else {
            (ran.output, ran.cut) = (live.screen.text(), live.screen.cut());
        }
        ran
    }
}

/// What's kept of what a command wrote, as written: up to `limit` bytes.
struct Kept {
    bytes: Vec<u8>,
    limit: usize,
    over: bool,
}

impl Kept {
    fn new(limit: usize) -> Kept {
        Kept {
            bytes: Vec::new(),
            limit,
            over: false,
        }
    }

    fn add(&mut self, bytes: &[u8]) {
        let room = self.limit.saturating_sub(self.bytes.len());
        let (kept, rest) = bytes.split_at(room.min(bytes.len()));
        self.bytes.extend_from_slice(kept);
        self.over |= !rest.is_empty();
    }
}

/// What a running command wrote since it was last told, as shown (see
/// `Screen`), for Koil to show it as it comes: the lines it has are those
/// told so far, less the first `drop` of them, with `lines` after them, and
/// then `line`.
#[derive(Debug, Default, PartialEq, Eq, Serialize)]
pub struct Output {
    /// Whether none of the lines told before are kept any more: so much
    /// was written since that lines between them and `lines` are gone too.
    pub reset: bool,
    /// How many of the lines told before, from the first, aren't kept any
    /// more (see `SHOWN_LINES`).
    pub drop: usize,
    /// The lines that ended since.
    pub lines: Vec<String>,
    /// The line being written, as it is now (a progress bar, as `\r` wrote
    /// it last).
    pub line: String,
    /// How many lines aren't kept in all (see `Ran::cut`).
    pub cut: usize,
}

/// What a running command wrote so far, as shown, which `due` tells as it
/// changes (see `Output`), at most every `LIVE_EVERY`. Blank lines at the
/// end aren't told until something comes after them, as `Screen::text`
/// leaves them out, so what's been told is what that gives in the end.
#[derive(Default)]
struct Live {
    screen: Screen,
    /// Whether more was written since `due` last looked, and when it did.
    changed: bool,
    looked: Option<Instant>,
    /// Of the lines that ended (counted from the first ever), the first
    /// one told that's still kept, and the one after the last told.
    from: usize,
    told: usize,
    /// The line being written, as told last.
    line: String,
}

impl Live {
    fn add(&mut self, bytes: &[u8]) {
        self.screen.write(bytes);
        self.changed = true;
    }

    /// What changed since it last told, if anything did and it's time to
    /// tell it (or `now`).
    fn due(&mut self, now: bool) -> Option<Output> {
        if !self.changed || !now && self.looked.is_some_and(|at| at.elapsed() < LIVE_EVERY) {
            return None;
        }
        self.changed = false;
        self.looked = Some(Instant::now());
        let screen = &self.screen;
        let first = screen.cut();
        let line = screen.current();
        let start = self.told.max(first);
        let mut end = screen.ended;
        while line.is_empty() && end > start && screen.lines[end - 1 - first].is_empty() {
            end -= 1;
        }
        let output = Output {
            reset: first > self.told,
            drop: first.min(self.told).saturating_sub(self.from),
            lines: (start..end)
                .map(|i| screen.lines[i - first].clone())
                .collect(),
            line,
            cut: first,
        };
        if !output.reset && output.drop == 0 && output.lines.is_empty() && output.line == self.line
        {
            return None;
        }
        self.from = self.from.max(first);
        self.told = end;
        self.line.clone_from(&output.line);
        Some(output)
    }
}

/// How two bytes make a unit of UTF-16.
type Unit = fn([u8; 2]) -> u16;

/// Reads what a command writes as text, as it comes, as
/// `document::decode_lossy` reads all of it: UTF-8, or UTF-16 after its
/// BOM, with what isn't text as `�`. A character whose bytes haven't all
/// come waits for the rest.
#[derive(Default)]
struct Decoder {
    /// Whether the first bytes said how it's stored: as UTF-16, whose
    /// units two bytes make so, or else as UTF-8.
    started: bool,
    utf16: Option<Unit>,
    /// The bytes not read yet: a character's first ones, or a BOM's.
    rest: Vec<u8>,
}

impl Decoder {
    fn read(&mut self, bytes: &[u8]) -> String {
        self.rest.extend_from_slice(bytes);
        if !self.started {
            let boms: [(&[u8], Option<Unit>); 3] = [
                (&[0xef, 0xbb, 0xbf], None),
                (&[0xff, 0xfe], Some(u16::from_le_bytes)),
                (&[0xfe, 0xff], Some(u16::from_be_bytes)),
            ];
            // It may still be one, once the rest of it comes.
            let rest = &self.rest;
            if boms
                .iter()
                .any(|(bom, _)| bom.len() > rest.len() && bom.starts_with(rest))
            {
                return String::new();
            }
            if let Some((bom, utf16)) = boms.iter().find(|(bom, _)| rest.starts_with(bom)) {
                self.utf16 = *utf16;
                self.rest.drain(..bom.len());
            }
            self.started = true;
        }
        let bytes = std::mem::take(&mut self.rest);
        match self.utf16 {
            None => self.utf8(&bytes),
            Some(unit) => self.utf16(&bytes, unit),
        }
    }

    fn utf8(&mut self, bytes: &[u8]) -> String {
        let mut text = String::new();
        let mut chunks = bytes.utf8_chunks().peekable();
        while let Some(chunk) = chunks.next() {
            text.push_str(chunk.valid());
            let invalid = chunk.invalid();
            // A character's first bytes at the end: the rest may come.
            let cut_off = chunks.peek().is_none()
                && std::str::from_utf8(invalid).is_err_and(|e| e.error_len().is_none());
            if cut_off {
                self.rest = invalid.to_vec();
            } else if !invalid.is_empty() {
                text.push(char::REPLACEMENT_CHARACTER);
            }
        }
        text
    }

    fn utf16(&mut self, bytes: &[u8], unit: Unit) -> String {
        let (pairs, odd) = bytes.as_chunks();
        let mut units: Vec<u16> = pairs.iter().map(|&pair| unit(pair)).collect();
        let mut read = bytes.len() - odd.len();
        // Half a character at the end: the other half may come.
        if units.last().is_some_and(|u| (0xd800..0xdc00).contains(u)) {
            units.pop();
            read -= 2;
        }
        self.rest = bytes[read..].to_vec();
        char::decode_utf16(units)
            .map(|c| c.unwrap_or(char::REPLACEMENT_CHARACTER))
            .collect()
    }

    /// What the bytes still waiting are, as nothing more comes: `�`, or
    /// nothing (a BOM alone, or half a unit of UTF-16, which
    /// `decode_lossy` drops too).
    fn end(&mut self) -> String {
        let rest = std::mem::take(&mut self.rest);
        let lost = self.utf16.is_none() || rest.len() >= 2;
        self.started = true;
        match lost && !rest.is_empty() {
            true => char::REPLACEMENT_CHARACTER.to_string(),
            false => String::new(),
        }
    }
}

/// An escape sequence a `Screen` is in, which is left out.
#[derive(Clone, Copy, Default)]
enum Escape {
    #[default]
    None,
    /// After ESC.
    Started,
    /// CSI: parameters and intermediates, then its final byte.
    Csi,
    /// OSC (a title, a link): up to BEL or ESC \.
    Osc,
    /// After an ESC in an OSC.
    OscEnd,
}

/// What a command wrote as a terminal would show it, as plain text, given
/// as it comes (`write`): without what's for the terminal (colors and other
/// escapes, the control characters), with what `\r` or a backspace went
/// back and wrote over written over (a progress bar, a man page's bold),
/// tabs as spaces (to every 8th column; with `tabs`, kept, each a column),
/// and no blanks at the ends of lines.
struct Screen {
    tabs: bool,
    /// How many lines are kept at most, the last ones, and bytes of them
    /// (but the last line always), and how long a line may be, in
    /// characters: what's written past that is left out.
    keep: usize,
    room: usize,
    width: usize,
    decoder: Decoder,
    escape: Escape,
    /// The lines that ended, those kept, with how many bytes they have,
    /// and how many ended in all.
    lines: VecDeque<String>,
    bytes: usize,
    ended: usize,
    /// The line being written, and where in it.
    line: Vec<char>,
    column: usize,
}

impl Default for Screen {
    fn default() -> Screen {
        Screen::last()
    }
}

impl Screen {
    /// All of it.
    fn all(tabs: bool) -> Screen {
        Screen {
            tabs,
            keep: usize::MAX,
            room: usize::MAX,
            width: usize::MAX,
            decoder: Decoder::default(),
            escape: Escape::None,
            lines: VecDeque::new(),
            bytes: 0,
            ended: 0,
            line: Vec::new(),
            column: 0,
        }
    }

    /// As much as Koil shows of a command's output: its last lines.
    fn last() -> Screen {
        Screen {
            keep: SHOWN_LINES,
            room: SHOWN_BYTES,
            width: SHOWN_COLUMNS,
            ..Screen::all(false)
        }
    }

    fn write(&mut self, bytes: &[u8]) {
        let text = self.decoder.read(bytes);
        self.write_text(&text);
    }

    /// Nothing more comes.
    fn end(&mut self) {
        let text = self.decoder.end();
        self.write_text(&text);
    }

    fn write_text(&mut self, text: &str) {
        for c in text.chars() {
            // An escape that's going on takes it, or ends before it.
            match self.escape {
                Escape::None => {}
                Escape::Started => {
                    self.escape = match c {
                        '[' => Escape::Csi,
                        ']' => Escape::Osc,
                        _ => Escape::None,
                    };
                    continue;
                }
                Escape::Csi => {
                    if ('\x20'..'\x40').contains(&c) {
                        continue;
                    }
                    self.escape = Escape::None;
                    if ('\x40'..'\x7f').contains(&c) {
                        continue;
                    }
                }
                Escape::Osc | Escape::OscEnd => {
                    self.escape = match c {
                        '\\' if matches!(self.escape, Escape::OscEnd) => Escape::None,
                        '\x07' => Escape::None,
                        '\x1b' => Escape::OscEnd,
                        _ => Escape::Osc,
                    };
                    continue;
                }
            }
            match c {
                '\n' => self.end_line(),
                '\r' => self.column = 0,
                '\x08' => self.column = self.column.saturating_sub(1),
                '\t' if !self.tabs => {
                    for _ in 0..8 - self.column % 8 {
                        self.put(' ');
                    }
                }
                '\x1b' => self.escape = Escape::Started,
                c if c.is_control() && c != '\t' => {}
                c => self.put(c),
            }
        }
    }

    /// Writes `c` over what's there, as a terminal does.
    fn put(&mut self, c: char) {
        if self.column >= self.width {
            return;
        }
        if self.column < self.line.len() {
            self.line[self.column] = c;
        } else {
            self.line.push(c);
        }
        self.column += 1;
    }

    fn end_line(&mut self) {
        let line = self.current();
        self.line.clear();
        self.column = 0;
        self.bytes += line.len();
        self.lines.push_back(line);
        self.ended += 1;
        while self.lines.len() > self.keep || self.bytes > self.room && self.lines.len() > 1 {
            self.bytes -= self.lines.pop_front().map_or(0, |line| line.len());
        }
    }

    /// The line being written, as it is now.
    fn current(&self) -> String {
        let line: String = self.line.iter().collect();
        line.trim_end().to_string()
    }

    /// How many lines ended that aren't kept any more.
    fn cut(&self) -> usize {
        self.ended - self.lines.len()
    }

    /// The lines kept and the one being written, without the blank lines
    /// at the end.
    fn text(&self) -> String {
        let mut lines: Vec<String> = self.lines.iter().cloned().collect();
        lines.push(self.current());
        while lines.last().is_some_and(String::is_empty) {
            lines.pop();
        }
        lines.join("\n")
    }
}

/// All of `bytes` as a terminal would show it (see `Screen`), without the
/// blank lines at the end.
pub fn as_shown(bytes: Vec<u8>, tabs: bool) -> String {
    let mut screen = Screen::all(tabs);
    screen.write_text(&document::decode_lossy(bytes));
    screen.text()
}

/// The environment commands run in (see `environment`).
#[derive(Debug)]
enum Environment {
    /// Koil's own: it was started from a terminal (or isn't on macOS), so
    /// it has what the user's shell set up.
    Inherited,
    /// What the user's shell set up, as `read_environment` read it.
    Read(Vec<(OsString, OsString)>),
    /// It couldn't be read (or the setting is off), so on macOS commands
    /// run in a login shell, which reads the profile at least.
    Unread,
}

static ENVIRONMENT: OnceLock<Environment> = OnceLock::new();

/// Reads the environment commands run in, on another thread, so the first
/// one needn't wait for it. Only while the setting is on, as it runs the
/// user's shell.
pub fn load_environment() {
    // The web runs no commands, nor has threads.
    if cfg!(target_os = "emscripten") {
        return;
    }
    thread::spawn(|| {
        environment();
    });
}

/// The environment commands run in. On macOS, an app opened from Finder
/// (or the Dock, or `open`) has launchd's, whose PATH is the system's
/// (`/usr/bin:/bin:…`), without what the user's shell adds (Homebrew's),
/// so it's read from `$SHELL` once, as VS Code and Zed do. Not when Koil
/// was started from a terminal (`TERM` is set), as it has it then, with
/// what was set for it alone.
fn environment() -> &'static Environment {
    ENVIRONMENT.get_or_init(|| {
        if !cfg!(target_os = "macos") || cfg!(test) || env::var_os("TERM").is_some() {
            return Environment::Inherited;
        }
        let home = env::var_os("HOME").map_or_else(|| PathBuf::from("/"), PathBuf::from);
        match read_environment(&default_shell(), &home, ENVIRONMENT_TIMEOUT) {
            Some(vars) => Environment::Read(vars),
            None => Environment::Unread,
        }
    })
}

/// The environment `shell` (one of `LOGIN_SHELLS`) sets up, as in a
/// terminal: a login shell that's interactive too, so it reads the rc file
/// (`.zshrc`, where Homebrew's PATH often is) as well as the profile, run
/// in `home`. What the rc file prints goes around it, so the environment
/// is printed between `MARK`s (by `env -0`, as a value may have a line
/// break). None if it can't run, has no PATH, or isn't done in `timeout`
/// (then it's killed, with what it started).
fn read_environment(
    shell: &str,
    home: &Path,
    timeout: Duration,
) -> Option<Vec<(OsString, OsString)>> {
    if !LOGIN_SHELLS.contains(&program_name(shell).as_str()) {
        return None;
    }
    let line = format!("printf {MARK}; /usr/bin/env -0; printf {MARK}");
    let mut command = Command::new(shell);
    command
        .args(["-l", "-i", "-c", &line])
        .current_dir(home)
        .env(READING, "1")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        command.process_group(0);
    }
    let mut child = command.spawn().ok()?;
    let (sender, output) = mpsc::sync_channel(16);
    read(child.stdout.take(), 0, sender);
    let deadline = Instant::now() + timeout;
    let mut bytes = Vec::new();
    let vars = loop {
        if let Some(vars) = between_marks(&bytes) {
            break Some(vars);
        }
        match output.recv_timeout(deadline.saturating_duration_since(Instant::now())) {
            Ok((_, Some(chunk))) => bytes.extend(chunk),
            Ok((_, None)) | Err(RecvTimeoutError::Disconnected) => break None,
            Err(RecvTimeoutError::Timeout) => {
                signal(child.id(), true);
                break None;
            }
        }
    };
    // It ends once it has printed them (unless it hangs), not waited for.
    thread::spawn(move || child.wait());
    vars.filter(|vars| vars.iter().any(|(name, _)| name == "PATH"))
}

/// The variables printed between two `MARK`s in `output`, once both are
/// there, as `env -0` prints them, but `NOT_ENVIRONMENT`.
fn between_marks(output: &[u8]) -> Option<Vec<(OsString, OsString)>> {
    let mark = MARK.as_bytes();
    let find = |from: usize| {
        (output[from..].windows(mark.len()))
            .position(|bytes| bytes == mark)
            .map(|at| from + at)
    };
    let start = find(0)? + mark.len();
    let end = find(start)?;
    let vars = (output[start..end].split(|&b| b == 0))
        .filter_map(|var| {
            let eq = var.iter().position(|&b| b == b'=')?;
            let (name, value) = (&var[..eq], &var[eq + 1..]);
            let shells = NOT_ENVIRONMENT.iter().any(|n| n.as_bytes() == name);
            (!name.is_empty() && !shells).then(|| (os_string(name), os_string(value)))
        })
        .collect();
    Some(vars)
}

/// `bytes` as an OsString: as they are on Unix, where it's bytes.
fn os_string(bytes: &[u8]) -> OsString {
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStrExt;
        std::ffi::OsStr::from_bytes(bytes).to_os_string()
    }
    #[cfg(not(unix))]
    {
        String::from_utf8_lossy(bytes).into_owned().into()
    }
}

/// The process that runs `line` in `shell` (of its kind), in `cwd`, with
/// `read`, in the environment the user's shell sets up (see
/// `environment`). It leads a process group of its own, so `stop` ends
/// what it starts too.
fn command(shell: &str, line: &str, cwd: &Path, read: bool) -> Command {
    let mut command = Command::new(shell);
    let environment = match read {
        true => environment(),
        false => &Environment::Unread,
    };
    // Its PATH finds `shell` too.
    if let Environment::Read(vars) = environment {
        command.env_clear();
        command.envs(vars.iter().map(|(name, value)| (name, value)));
    }
    match Kind::of(shell) {
        Kind::Sh => {
            if cfg!(target_os = "macos")
                && matches!(environment, Environment::Unread)
                && LOGIN_SHELLS.contains(&program_name(shell).as_str())
            {
                command.arg("-l");
            }
            // Quoted, always: Git Bash's runtime reads its command line
            // itself, and expands a glob in an argument that isn't quoted,
            // which Command leaves one without a space.
            #[cfg(windows)]
            {
                use std::os::windows::process::CommandExt;
                command.raw_arg(format!("-c {}", msvc_quoted(line)));
            }
            #[cfg(not(windows))]
            command.arg("-c").arg(line);
        }
        Kind::Cmd => {
            // /d: not cmd's AutoRun commands. With /s /c, cmd takes off the
            // first and last quote, and runs what's between as it is (as in
            // vim).
            #[cfg(windows)]
            {
                use std::os::windows::process::CommandExt;
                command.raw_arg(format!("/d /s /c \"{line}\""));
            }
            #[cfg(not(windows))]
            command.args(["/d", "/s", "/c", line]);
        }
        Kind::PowerShell => {
            // Encoded, as Windows PowerShell drops the quotes in a command
            // given as an argument; without the progress records it writes
            // to stderr when that isn't a console.
            let script = format!("$ProgressPreference = 'SilentlyContinue'\n{line}");
            let flags = [
                "-NoLogo",
                "-NoProfile",
                "-NonInteractive",
                "-EncodedCommand",
            ];
            command.args(flags).arg(encoded(&script));
        }
    }
    command.current_dir(cwd);
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        command.process_group(0);
    }
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(CREATE_NO_WINDOW);
    }
    command
}

/// `arg` quoted as a Windows program reads its command line (MSVC's
/// rules): always, unlike Command, which quotes only what has a space.
#[cfg(any(windows, test))]
fn msvc_quoted(arg: &str) -> String {
    let mut quoted = String::from('"');
    let mut backslashes = 0;
    for c in arg.chars() {
        match c {
            '\\' => backslashes += 1,
            '"' => {
                quoted.extend(std::iter::repeat_n('\\', 2 * backslashes + 1));
                quoted.push('"');
                backslashes = 0;
            }
            c => {
                quoted.extend(std::iter::repeat_n('\\', backslashes));
                quoted.push(c);
                backslashes = 0;
            }
        }
    }
    quoted.extend(std::iter::repeat_n('\\', 2 * backslashes));
    quoted.push('"');
    quoted
}

/// `script` as PowerShell's `-EncodedCommand` takes it: UTF-16LE, in
/// base64.
fn encoded(script: &str) -> String {
    let bytes: Vec<u8> = script.encode_utf16().flat_map(u16::to_le_bytes).collect();
    let base64 = QByteArray::from(bytes.as_slice()).to_base64(QByteArrayBase64Options::default());
    String::from_utf8_lossy(base64.as_slice()).into_owned()
}

/// Which quote a place in a command line is in.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Quote {
    None,
    Single,
    Double,
}

/// What stands for the paths written on the cursor's line in a command,
/// as in vim (see `expand`).
const CFILE: &str = "<cfile>";

/// The command line `command` (as typed after `:!`) is in `kind`'s shell,
/// run in `cwd`: each `%` is `file`, and each `<cfile>` is `cfile` (as
/// `written` has them, see `word`), with vim's modifiers after it (`%:p`),
/// quoted as they must be where it is (so `"%"` works too); if one has
/// none, the error is why. `\%` is a `%`, and `\<cfile>` a `<cfile>`.
pub fn expand(
    command: &str,
    kind: Kind,
    cwd: &Path,
    file: Result<&[PathBuf], String>,
    cfile: Result<&[PathBuf], String>,
) -> Result<String, String> {
    let words = |paths: &Result<&[PathBuf], String>, modifiers: &[char]| match paths {
        Ok(paths) => Ok((paths.iter())
            .map(|path| word(path, cwd, kind, modifiers))
            .collect::<Vec<_>>()),
        Err(why) => Err(why.clone()),
    };
    let chars: Vec<char> = command.chars().collect();
    let cfile_at = |i: usize| {
        (chars.get(i..i + CFILE.len())).is_some_and(|s| s.iter().copied().eq(CFILE.chars()))
    };
    let mut line = String::new();
    let mut quote = Quote::None;
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        let next = chars.get(i + 1).copied();
        if c == '\\' && next == Some('%') {
            line.push('%');
            i += 2;
            continue;
        }
        if c == '\\' && cfile_at(i + 1) {
            line.push_str(CFILE);
            i += 1 + CFILE.len();
            continue;
        }
        let paths = if c == '%' {
            i += 1;
            Some(&file)
        } else if cfile_at(i) {
            i += CFILE.len();
            Some(&cfile)
        } else {
            None
        };
        if let Some(paths) = paths {
            let modifiers = modifiers(&chars, &mut i);
            line.push_str(&inserted(&words(paths, &modifiers)?, kind, quote));
            continue;
        }
        let escape = match (kind, quote) {
            (Kind::Sh, Quote::None | Quote::Double) => c == '\\',
            (Kind::Cmd, Quote::None) => c == '^',
            (Kind::PowerShell, Quote::None | Quote::Double) => c == '`',
            _ => false,
        };
        line.push(c);
        i += 1;
        if escape {
            if let Some(next) = next.filter(|&n| n != '%' && !cfile_at(i)) {
                line.push(next);
                i += 1;
            }
            continue;
        }
        // PowerShell's '' in single quotes (cmd's "" in double ones) goes
        // out and back in, which comes to the same.
        quote = match (kind, quote, c) {
            (Kind::Sh | Kind::PowerShell, Quote::None, '\'') => Quote::Single,
            (Kind::Sh | Kind::PowerShell, Quote::Single, '\'') => Quote::None,
            (_, Quote::None, '"') => Quote::Double,
            (_, Quote::Double, '"') => Quote::None,
            (_, quote, _) => quote,
        };
    }
    Ok(line)
}

/// vim's file name modifiers (`:p:h`) at `chars[*i..]`, which `i` goes
/// past.
fn modifiers(chars: &[char], i: &mut usize) -> Vec<char> {
    let mut modifiers = Vec::new();
    while chars.get(*i) == Some(&':') && chars.get(*i + 1).is_some_and(|m| "phtre".contains(*m)) {
        modifiers.push(chars[*i + 1]);
        *i += 2;
    }
    modifiers
}

/// `words` (paths) put in a command line of `kind`'s, where `quote` is
/// open: each quoted if it must be. One in quotes is escaped as they need;
/// several close them, to be words of their own, and open them again
/// after.
fn inserted(words: &[String], kind: Kind, quote: Quote) -> String {
    let apart = || (words.iter().map(|w| quoted(w, kind)).collect::<Vec<_>>()).join(" ");
    match (quote, words) {
        (Quote::None, _) => apart(),
        (Quote::Single, [word]) => match kind {
            Kind::PowerShell => word.replace('\'', "''"),
            _ => word.replace('\'', r"'\''"),
        },
        (Quote::Double, [word]) => {
            let (escape, special): (char, &[char]) = match kind {
                Kind::Sh => ('\\', &['\\', '"', '$', '`']),
                Kind::PowerShell => ('`', &['`', '"', '$']),
                // which a path on Windows can't have
                Kind::Cmd => return word.clone(),
            };
            let mut escaped = String::new();
            for c in word.chars() {
                if special.contains(&c) {
                    escaped.push(escape);
                }
                escaped.push(c);
            }
            escaped
        }
        (Quote::Single, _) => format!("'{}'", apart()),
        (Quote::Double, _) => format!("\"{}\"", apart()),
    }
}

/// `word` as one word of `kind`'s command line: as it is if nothing in it
/// is special there, else quoted.
pub fn quoted(word: &str, kind: Kind) -> String {
    let plain = match kind {
        Kind::Sh => "_-./:+,@",
        Kind::Cmd => r"_-.\/:+@~#",
        Kind::PowerShell => r"_-.\/:+~",
    };
    if !word.is_empty()
        && word
            .chars()
            .all(|c| c.is_alphanumeric() || plain.contains(c))
    {
        return word.to_string();
    }
    match kind {
        Kind::Sh => format!("'{}'", word.replace('\'', r"'\''")),
        Kind::Cmd => format!("\"{word}\""),
        Kind::PowerShell => format!("'{}'", word.replace('\'', "''")),
    }
}

/// How `%` writes `file` (an absolute path, or a URL for `<cfile>`) in a
/// command run in `cwd`: relative to it if it's in it (`.` for itself),
/// else as it is, with vim's `modifiers` (see `modified`), and with `/`
/// between its parts, but for cmd.exe and PowerShell on Windows, `\`. A
/// relative path that starts with `-` starts with `./`, so it isn't read
/// as an option.
fn word(file: &Path, cwd: &Path, kind: Kind, modifiers: &[char]) -> String {
    let slashes = |path: &Path| match cfg!(windows) {
        true => path.to_string_lossy().replace('\\', "/"),
        false => path.to_string_lossy().into_owned(),
    };
    let full = slashes(file);
    let mut word = match file.strip_prefix(cwd) {
        Ok(rest) if rest.as_os_str().is_empty() => ".".to_string(),
        Ok(rest) => slashes(rest),
        Err(_) => full.clone(),
    };
    for &modifier in modifiers {
        word = modified(&word, &full, modifier);
    }
    if word.starts_with('-') {
        word = format!("./{word}");
    }
    // A URL (`<cfile>` on one) keeps its `/`s.
    match cfg!(windows) && kind != Kind::Sh && !full.contains("://") {
        true => word.replace('/', "\\"),
        false => word,
    }
}

/// `path` (with `/` between its parts) with one of vim's file name
/// modifiers: `p` is `full` (the absolute path), `h` the dir it's in (`.`
/// if it's relative and has none), `t` its name, `r` it without its
/// extension, and `e` its extension.
fn modified(path: &str, full: &str, modifier: char) -> String {
    let (dir, name) = match path.rfind('/') {
        Some(i) => (&path[..i], &path[i + 1..]),
        None => ("", path),
    };
    let dot = name.rfind('.').filter(|&i| i > 0);
    match modifier {
        'p' => full.to_string(),
        'h' if path.rfind('/').is_none() => ".".to_string(),
        // a root (`/`, `C:/`) keeps its slash
        'h' if dir.is_empty() || dir.ends_with(':') => format!("{dir}/"),
        'h' => dir.to_string(),
        't' => name.to_string(),
        'r' => match dot {
            Some(i) => path[..path.len() - name.len() + i].to_string(),
            None => path.to_string(),
        },
        'e' => dot.map(|i| name[i + 1..].to_string()).unwrap_or_default(),
        _ => path.to_string(),
    }
}

#[cfg(test)]
mod tests;
