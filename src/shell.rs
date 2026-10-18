//! Shell commands, as vim's `:!`: `:!cmd` runs `cmd` in the dir Koil has
//! open, with `%` in it for the entries (or the paths on lines, or the
//! file) it's run on, and `:_!cmd` puts what it writes in the scratchpad
//! (see `Request`).
//! It runs in the shell the `shell` setting names, else the system's (see
//! `default_shell`), whose kind says how the command line is passed and how
//! a path is quoted in it (see `Kind`). One runs at a time, on another
//! thread, while Koil waits for it; `Running::stop` ends it.

use std::env;
use std::ffi::OsString;
use std::io::{self, Read};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, SyncSender};
use std::sync::{Arc, Mutex, MutexGuard, OnceLock, PoisonError};
use std::thread;
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};

use crate::{document, listing};

/// How much of a command's output (stdout and stderr together) is kept to
/// show, and how many of its lines are shown: the help box lays out all of
/// what it shows at once (3000 lines took half a second).
const SHOWN_BYTES: usize = 1 << 20;
const SHOWN_LINES: usize = 1000;
/// How much of the output of one for the scratchpad is kept: past that, it
/// isn't put in, as the rest of it would be lost.
const SCRATCHPAD_BYTES: usize = 256 << 20;
/// How often a command that's running is checked for having ended.
const POLL: Duration = Duration::from_millis(50);
/// How long what a command started (`&`) may keep its output open after
/// it ended, before Koil stops reading it.
const AFTER_EXIT: Duration = Duration::from_millis(500);
/// How long a command `stop` sent Ctrl-C's signal has to end, before it's
/// killed.
const KILL_AFTER: Duration = Duration::from_secs(1);

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
    /// The dir it runs in: the one Koil has open.
    pub cwd: PathBuf,
    /// What `%` stands for: the entries (or paths) on the lines it's run
    /// on, or the file, each an absolute path; or else, why there are none.
    pub files: Vec<PathBuf>,
    pub why: String,
    /// Whether the files go after a command that has no `%` (one run on
    /// lines).
    pub append: bool,
    /// Whether what it writes goes in the scratchpad (`:_!`): stdout and
    /// stderr together, as for one whose output is shown, but all of it,
    /// and with its tabs.
    pub scratchpad: bool,
    /// Whether it runs in the environment read from the user's shell (see
    /// `environment`), as the Settings window says; else, in Koil's, in a
    /// login shell on macOS.
    pub environment: bool,
}

/// What a command did.
#[derive(Debug, Default, PartialEq, Eq, Serialize)]
pub struct Ran {
    /// What it wrote, stdout and stderr together, as shown (see
    /// `as_shown`; all of it, with its tabs, for the scratchpad).
    pub output: String,
    /// How many lines of what's shown were left out, as it was too long.
    pub cut: usize,
    /// Its exit code; none if a signal ended it.
    pub code: Option<i32>,
    /// Whether `Running::stop` ended it.
    pub stopped: bool,
    /// Why the scratchpad's output can't be put in, or why waiting failed.
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
    /// What it writes (stdout and stderr together), as it comes, and `None`
    /// once that's closed.
    output: Receiver<Option<Vec<u8>>>,
    scratchpad: bool,
}

/// Starts `request`'s command: returns the command line as it runs, with
/// the files `%` stands for, and the command, to `finish` (on another
/// thread); or else why it can't run.
pub fn start(request: &Request, running: &Running) -> Result<(String, Started), String> {
    if running.is_running() {
        return Err("A command is still running".to_string());
    }
    let kind = Kind::of(&request.shell);
    let why = match request.why.as_str() {
        "" => "E499: Empty file name for '%'",
        why => why,
    };
    let line = expand(
        &request.command,
        kind,
        &request.cwd,
        &request.files,
        why,
        request.append,
    )?;
    if !request.cwd.is_dir() {
        let shown = listing::show_path(&request.cwd);
        return Err(format!("“{shown}” isn't there any more"));
    }
    let cant = |err: io::Error| format!("Can't run {}: {err}", request.shell);
    let mut command = command(&request.shell, &line, &request.cwd, request.environment);
    let (sender, output) = mpsc::sync_channel(16);
    // Stdout and stderr through one pipe, so they're in the order they
    // were written.
    let (reader, writer) = io::pipe().map_err(cant)?;
    command
        .stdin(Stdio::null())
        .stdout(writer.try_clone().map_err(cant)?)
        .stderr(writer);
    let child = command.spawn().map_err(cant)?;
    // Its ends of the pipe, without which reading would never end.
    drop(command);
    read(reader, sender);
    running.start(child.id());
    let started = Started {
        child,
        output,
        scratchpad: request.scratchpad,
    };
    Ok((line, started))
}

/// Sends what `reader` reads to `sender`, from another thread, then
/// `None` once it's done.
fn read(mut reader: impl Read + Send + 'static, sender: SyncSender<Option<Vec<u8>>>) {
    thread::spawn(move || {
        let mut buffer = vec![0; 64 << 10];
        while let Ok(n @ 1..) = reader.read(&mut buffer) {
            if sender.send(Some(buffer[..n].to_vec())).is_err() {
                return;
            }
        }
        let _ = sender.send(None);
    });
}

impl Started {
    /// Waits for the command to end, keeping what it writes, and a moment
    /// longer for what it started (`&`), if that still has its output open.
    pub fn finish(mut self, running: &Running) -> Ran {
        let mut out = Kept::new(if self.scratchpad {
            SCRATCHPAD_BYTES
        } else {
            SHOWN_BYTES
        });
        let mut ended: Option<Instant> = None;
        let mut status = None;
        loop {
            let wait = match ended {
                Some(at) => AFTER_EXIT.saturating_sub(at.elapsed()),
                None => POLL,
            };
            match self.output.recv_timeout(wait) {
                Ok(Some(bytes)) => out.add(&bytes),
                Ok(None) => break,
                Err(RecvTimeoutError::Timeout) if ended.is_some() => break,
                Err(RecvTimeoutError::Timeout) => {}
                Err(RecvTimeoutError::Disconnected) => break,
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
        let mut ran = Ran {
            code: status.as_ref().ok().and_then(|s| s.code()),
            stopped,
            error: status.err().map(|e| e.to_string()).unwrap_or_default(),
            ..Ran::default()
        };
        if self.scratchpad {
            if out.over {
                ran.error = "The output is too long to put in".to_string();
            }
            ran.output = as_shown(out.bytes, true);
        } else {
            (ran.output, ran.cut) = shown_lines(as_shown(out.bytes, false), out.more_lines);
        }
        ran
    }
}

/// What's kept of what a command wrote: up to `limit` bytes, and how many
/// lines there were after.
struct Kept {
    bytes: Vec<u8>,
    limit: usize,
    over: bool,
    more_lines: usize,
}

impl Kept {
    fn new(limit: usize) -> Kept {
        Kept {
            bytes: Vec::new(),
            limit,
            over: false,
            more_lines: 0,
        }
    }

    fn add(&mut self, bytes: &[u8]) {
        let room = self.limit.saturating_sub(self.bytes.len());
        let (kept, rest) = bytes.split_at(room.min(bytes.len()));
        self.bytes.extend_from_slice(kept);
        if !rest.is_empty() {
            self.over = true;
            self.more_lines += rest.iter().filter(|&&b| b == b'\n').count();
        }
    }
}

/// `text` with at most `SHOWN_LINES` lines, and how many were left out (and
/// `more` before that).
fn shown_lines(text: String, more: usize) -> (String, usize) {
    let Some((end, _)) = text.match_indices('\n').nth(SHOWN_LINES - 1) else {
        return (text, more);
    };
    let left = text[end + 1..].split('\n').count();
    (text[..end].to_string(), more + left)
}

/// Output as a terminal would show it, as plain text: without what's for
/// the terminal (colors and other escapes, the control characters), with
/// what `\r` or a backspace went back and wrote over written over (a
/// progress bar, a man page's bold), tabs as spaces (to every 8th column;
/// with `tabs`, kept, each a column), and no blanks at the ends of lines, or
/// blank lines at the end.
pub fn as_shown(bytes: Vec<u8>, tabs: bool) -> String {
    let text = document::decode_lossy(bytes);
    let mut lines: Vec<String> = Vec::new();
    let mut line: Vec<char> = Vec::new();
    let mut column: usize = 0;
    let mut chars = text.chars().peekable();
    // over what's there, as a terminal writes
    let put = |line: &mut Vec<char>, column: &mut usize, c: char| {
        if *column < line.len() {
            line[*column] = c;
        } else {
            line.push(c);
        }
        *column += 1;
    };
    while let Some(c) = chars.next() {
        match c {
            '\n' => {
                lines.push(line.drain(..).collect::<String>().trim_end().to_string());
                column = 0;
            }
            '\r' => column = 0,
            '\x08' => column = column.saturating_sub(1),
            '\t' if tabs => put(&mut line, &mut column, c),
            '\t' => {
                for _ in 0..8 - column % 8 {
                    put(&mut line, &mut column, ' ');
                }
            }
            '\x1b' => match chars.next() {
                // CSI: parameters and intermediates, then its final byte
                Some('[') => {
                    while chars.next_if(|c| ('\x20'..'\x40').contains(c)).is_some() {}
                    chars.next_if(|c| ('\x40'..'\x7f').contains(c));
                }
                // OSC (a title, a link): up to BEL or ESC \
                Some(']') => {
                    while let Some(c) = chars.next() {
                        if c == '\x07' || c == '\x1b' && chars.next_if_eq(&'\\').is_some() {
                            break;
                        }
                    }
                }
                _ => {}
            },
            c if c.is_control() => {}
            c => put(&mut line, &mut column, c),
        }
    }
    lines.push(line.into_iter().collect::<String>().trim_end().to_string());
    while lines.last().is_some_and(String::is_empty) {
        lines.pop();
    }
    lines.join("\n")
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
    read(child.stdout.take()?, sender);
    let deadline = Instant::now() + timeout;
    let mut bytes = Vec::new();
    let vars = loop {
        if let Some(vars) = between_marks(&bytes) {
            break Some(vars);
        }
        match output.recv_timeout(deadline.saturating_duration_since(Instant::now())) {
            Ok(Some(chunk)) => bytes.extend(chunk),
            Ok(None) | Err(RecvTimeoutError::Disconnected) => break None,
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
    const DIGITS: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let bytes: Vec<u8> = script.encode_utf16().flat_map(u16::to_le_bytes).collect();
    let mut base64 = String::new();
    for chunk in bytes.chunks(3) {
        let n =
            (chunk.iter().enumerate()).fold(0u32, |n, (i, &b)| n | u32::from(b) << (16 - 8 * i));
        for i in 0..4 {
            base64.push(match i <= chunk.len() {
                true => char::from(DIGITS[(n >> (18 - 6 * i) & 63) as usize]),
                false => '=',
            });
        }
    }
    base64
}

/// Which quote a place in a command line is in.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Quote {
    None,
    Single,
    Double,
}

/// The command line `command` (as typed after `:!`) is in `kind`'s shell,
/// run in `cwd`: each `%` is `files` (as `written` has them, see `word`),
/// quoted as they must be where it is (so `"%"` works too), and `\%` is a
/// `%`. With `append`, they go after a command that has no `%`. If there
/// are no files where they're wanted, the error is `why`.
pub fn expand(
    command: &str,
    kind: Kind,
    cwd: &Path,
    files: &[PathBuf],
    why: &str,
    append: bool,
) -> Result<String, String> {
    let words = |modifiers: &[char]| match files.is_empty() {
        true => Err(why.to_string()),
        false => Ok((files.iter())
            .map(|file| word(file, cwd, kind, modifiers))
            .collect::<Vec<_>>()),
    };
    let chars: Vec<char> = command.chars().collect();
    let mut line = String::new();
    let mut quote = Quote::None;
    let mut used = false;
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        let next = chars.get(i + 1).copied();
        if c == '\\' && next == Some('%') {
            line.push('%');
            i += 2;
            continue;
        }
        if c == '%' {
            // vim's modifiers: %:p:h
            let mut modifiers = Vec::new();
            i += 1;
            while chars.get(i) == Some(&':')
                && chars.get(i + 1).is_some_and(|m| "phtre".contains(*m))
            {
                modifiers.push(chars[i + 1]);
                i += 2;
            }
            line.push_str(&inserted(&words(&modifiers)?, kind, quote));
            used = true;
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
            if let Some(next) = next.filter(|&n| n != '%') {
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
    if append && !used {
        let words = words(&[])?;
        line = format!(
            "{} {}",
            line.trim_end(),
            inserted(&words, kind, Quote::None)
        );
    }
    Ok(line)
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

/// How `%` writes `file` (an absolute path) in a command run in `cwd`:
/// relative to it if it's in it (`.` for itself), else as it is, with
/// vim's `modifiers` (see `modified`), and with `/` between its parts, but
/// for cmd.exe and PowerShell on Windows, `\`. A relative path that starts
/// with `-` starts with `./`, so it isn't read as an option.
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
    match cfg!(windows) && kind != Kind::Sh {
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
