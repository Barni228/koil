use std::io;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::process::{Command, Stdio};
use std::thread;

use cxx_qt::Threading;
use cxx_qt_lib::{QString, QStringList};
use serde_json::json;

use crate::convert::{paths, to_json};
use crate::ffi;
use crate::link;
use crate::listing;
use crate::shell;

/// What the QML needs from the system, mostly through Qt's C++ side: the
/// clipboard, the installed fonts and the one Koil ships, the editor's line
/// height and the listing's and path field's colors, showing a path in
/// Finder (or Explorer) or opening it in its default app, the links gf,
/// gx and a click with Cmd open (see link.rs), and running shell commands
/// (see shell.rs).
#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qstringlist.h");
        type QStringList = cxx_qt_lib::QStringList;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qobject]
        #[qml_element]
        type System = super::SystemRust;

        #[qinvokable]
        fn clipboard_text(self: &System) -> QString;

        #[qinvokable]
        fn clipboard_data(self: &System) -> QString;

        #[qinvokable]
        fn set_clipboard_text(self: &System, text: &QString, data: &QString);

        /// The installed monospaced font families (the fonts the editor offers).
        #[qinvokable]
        fn monospace_families(self: &System) -> QStringList;

        /// The family of the Nerd Font Koil ships, the editor's default font.
        #[qinvokable]
        fn nerd_font_family(self: &System) -> QString;

        /// Shows `path` in Finder (Explorer on Windows), selected in the dir
        /// it's in (elsewhere, opens that dir), for Space r. Returns why it
        /// can't, or "".
        #[qinvokable]
        fn reveal(self: &System, path: &QString) -> QString;

        /// Opens `path` as a double-click in Finder or Explorer does (a
        /// file in its default app, a dir in the file manager, an app
        /// launched), for Space o, without waiting for it. Returns why it
        /// can't, or "", and emits `open_failed` if it fails after.
        #[qinvokable]
        fn open_in_app(self: Pin<&mut System>, path: &QString) -> QString;

        /// Emitted when `open_in_app` failed after it returned, with why.
        #[qsignal]
        fn open_failed(self: Pin<&mut System>, message: QString);

        /// The link with the character at `column` (a UTF-16 index) in
        /// `line`, as `{ start, end }`, or `null` (see `link::link_at`:
        /// `names` takes a file name too, for gf and gx).
        #[qinvokable]
        fn link_at(self: &System, line: &QString, column: i32, names: bool) -> QString;

        /// What the link `text` opens, a relative path looked for in each
        /// of `dirs` in turn (see `link::target`): `{ url }`, `{ path }` or
        /// `{ error }`.
        #[qinvokable]
        fn link_target(self: &System, text: &QString, dirs: &QStringList) -> QString;

        /// The shell commands run in when the setting names none (see
        /// `shell::default_shell`).
        #[qinvokable]
        fn default_shell(self: &System) -> QString;

        /// The shells installed, for the Settings window to offer, as a
        /// list of `shell::Found` (`{ name, path }`).
        #[qinvokable]
        fn shells(self: &System) -> QString;

        /// Reads the environment commands run in from the user's shell, on
        /// another thread (see `shell::load_environment`).
        #[qinvokable]
        fn load_shell_environment(self: &System);

        /// Starts the shell command `request` (a `shell::Request`, as JSON)
        /// on another thread, and emits `shell_done` once it's done. Returns
        /// `{ line, error }`: the command line as it runs, or else why it
        /// can't.
        #[qinvokable]
        fn run_shell(self: Pin<&mut System>, request: &QString) -> QString;

        /// Ends the shell command running, if any (see `Running::stop`).
        #[qinvokable]
        fn stop_shell(self: &System);

        /// Emitted when the command `run_shell` started is done, with what
        /// it did (a `shell::Ran`, as JSON).
        #[qsignal]
        fn shell_done(self: Pin<&mut System>, result: QString);

        /// Gives every line of a TextEdit's `textDocument` the same height,
        /// plus a margin below it, and the rows a wrapped line goes on to an
        /// indent and a margin on their right.
        #[qinvokable]
        unsafe fn set_line_format(
            self: &System,
            text_document: *mut QObject,
            height: f64,
            bottom_margin: f64,
            indent: f64,
            right_margin: f64,
        );

        /// Sets a TextEdit's text, every line with the format
        /// `set_line_format` gives, laying it out once (see native.h).
        #[qinvokable]
        unsafe fn set_text(
            self: &System,
            text_edit: *mut QObject,
            text: &QString,
            height: f64,
            bottom_margin: f64,
            indent: f64,
            right_margin: f64,
        );

        /// Call after each change to a TextEdit's text: has it build only
        /// the lines in view while the text is long (see native.h).
        #[qinvokable]
        unsafe fn follow_text_length(self: &System, text_edit: *mut QObject);

        /// Call before setting a TextEdit's text: works around a Qt bug that
        /// can leave it blank (see native.h).
        #[qinvokable]
        unsafe fn redraw_text(self: &System, text_edit: *mut QObject);

        /// Replaces [start, end) of a TextEdit's text with `text`, as its
        /// remove and insert would, but as one edit (see native.h).
        #[qinvokable]
        unsafe fn replace_text(
            self: &System,
            text_edit: *mut QObject,
            start: i32,
            end: i32,
            text: &QString,
        );

        /// Whether `a` and `b` are the same string, not only the same text:
        /// the same QString's, as QML gives a string it keeps. In O(1),
        /// where QML's `===` hashes all of two strings that are long (a
        /// second for a gigabyte), unless they're the same one.
        #[qinvokable]
        fn same_string(self: &System, a: &QString, b: &QString) -> bool;

        /// Whether `a` and `b` are the same text, going through them only
        /// as far as they're the same, rather than hashing both, as QML's
        /// `===` does.
        #[qinvokable]
        fn same_text(self: &System, a: &QString, b: &QString) -> bool;

        /// Hides the lines of a TextEdit's `textDocument` longer than
        /// `long_length` from Qt, as they're edited, which Koil places and
        /// draws itself (see native.h).
        #[qinvokable]
        unsafe fn watch_long_lines(self: &System, text_document: *mut QObject, long_length: i32);

        /// Call after each change to the text or the line format of a
        /// `textDocument` with hidden lines: places them on the grid of
        /// rows `line_height` tall, `row_length` characters a row while
        /// lines wrap, else 0 (see native.h).
        #[qinvokable]
        unsafe fn place_long_lines(
            self: &System,
            text_document: *mut QObject,
            line_height: f64,
            bottom_margin: f64,
            row_length: i32,
        );

        /// The length of the longest hidden line, or 0 for none.
        #[qinvokable]
        unsafe fn longest_line(self: &System, text_document: *mut QObject) -> i32;

        /// The row and the column in it of `position`, as "row column", if
        /// it's in a hidden line, else "".
        #[qinvokable]
        unsafe fn long_line_spot(
            self: &System,
            text_document: *mut QObject,
            position: i32,
        ) -> QString;

        /// The position closest to `column` in row `row`, if the row is a
        /// hidden line's, else -1.
        #[qinvokable]
        unsafe fn long_line_position(
            self: &System,
            text_document: *mut QObject,
            row: i32,
            column: f64,
        ) -> i32;

        /// What to draw of the hidden lines in rows `first_row` to
        /// `last_row`, columns `first_column` up to `last_column`, as JSON
        /// runs `{ row, column, text, color, underline }`.
        #[qinvokable]
        unsafe fn long_line_runs(
            self: &System,
            text_document: *mut QObject,
            first_row: i32,
            last_row: i32,
            first_column: i32,
            last_column: i32,
        ) -> QString;

        /// Keeps what changes in a TextEdit's `textDocument`, for
        /// `take_text_change`.
        #[qinvokable]
        unsafe fn watch_text_changes(self: &System, text_document: *mut QObject);

        /// What changed in the text of `textDocument` since this was last
        /// called, as from, removed and text: the text from `from`,
        /// `removed` long, became `text`. Empty if nothing did, or if not
        /// `with_text` (a change whose text is known).
        #[qinvokable]
        unsafe fn take_text_change(
            self: &System,
            text_document: *mut QObject,
            with_text: bool,
        ) -> QStringList;

        /// Whether a TextEdit's text is `text` as it is once it's put in:
        /// Qt makes a `\r` a line break, and its text gives a no-break
        /// space as a space, and the separators it keeps as `\n`s (see
        /// takeTextChange in native.h).
        #[qinvokable]
        fn kept_as_is(self: &System, text: &QString) -> bool;

        /// Has a TextEdit build all its lines in view again, after its
        /// selection changed in a text with long lines (see native.h).
        #[qinvokable]
        unsafe fn rebuild_text_nodes(self: &System, text_edit: *mut QObject);

        /// Has a TextArea in a ScrollView leave scrolling to its cursor to
        /// its QML (see native.h).
        #[qinvokable]
        unsafe fn scroll_to_cursor_in_qml(self: &System, text_area: *mut QObject);

        /// Colors Koil's listing in a TextEdit's `textDocument`: each icon in
        /// `icon_colors` (icons and colors, alternating), or a pending
        /// entry's in `pending_icon_color`, and dirs in `directory_color`. No
        /// `directory_color` takes the colors away.
        #[qinvokable]
        unsafe fn set_listing_colors(
            self: &System,
            text_document: *mut QObject,
            icon_colors: &QStringList,
            pending_icon_color: &QString,
            directory_color: &QString,
        );

        /// The lines of the listing in `textDocument` (numbers, from 0) whose
        /// entries applying would change, whose icons get the pending color.
        #[qinvokable]
        unsafe fn set_pending_lines(
            self: &System,
            text_document: *mut QObject,
            lines: &QStringList,
        );

        /// Colors the path field's `textDocument`: all of it in
        /// `directory_color`, and parts of it (a regex's) over that: `spans`
        /// holds a start, a length and a color for each part.
        #[qinvokable]
        unsafe fn set_path_colors(
            self: &System,
            text_document: *mut QObject,
            directory_color: &QString,
            spans: &QStringList,
        );

        /// Colors the first word of each line of `textDocument` (after the box
        /// of a line to pick from) if it's a keyword: `keyword_colors`
        /// alternates keywords and their colors. None takes the colors away.
        #[qinvokable]
        unsafe fn set_keyword_colors(
            self: &System,
            text_document: *mut QObject,
            keyword_colors: &QStringList,
        );

        /// Colors a file's `textDocument` (see syntax.rs): `colors` has a
        /// color for each kind of part, in the order of `SyntaxKind`, and
        /// `file_name` says which comments it can have. No colors take
        /// them away.
        #[qinvokable]
        unsafe fn set_text_colors(
            self: &System,
            text_document: *mut QObject,
            colors: &QStringList,
            file_name: &QString,
        );
    }

    impl cxx_qt::Threading for System {}
}

#[derive(Default)]
pub struct SystemRust {
    /// The shell command running, if any.
    running: shell::Running,
}

/// A command still running as Koil quits ends with it.
impl Drop for SystemRust {
    fn drop(&mut self) {
        self.running.stop();
    }
}

/// Methods that hand a QML item (or its `textDocument`) to the C++ helper of
/// the same name in native.h.
macro_rules! forward {
    ($($name:ident($object:ident $(, $arg:ident: $type:ty)*) $(-> $result:ty)?;)*) => {$(
        #[doc = concat!(
            "# Safety\n\n`", stringify!($object), "` must be null or point to a live QObject."
        )]
        unsafe fn $name(&self, $object: *mut qobject::QObject $(, $arg: $type)*) $(-> $result)? {
            unsafe { ffi::$name($object.cast() $(, $arg)*) }
        }
    )*};
}

impl qobject::System {
    fn clipboard_text(&self) -> QString {
        ffi::clipboard_text()
    }

    fn clipboard_data(&self) -> QString {
        ffi::clipboard_data()
    }

    fn set_clipboard_text(&self, text: &QString, data: &QString) {
        ffi::set_clipboard_text(text, data);
    }

    fn monospace_families(&self) -> QStringList {
        ffi::monospace_families()
    }

    fn nerd_font_family(&self) -> QString {
        ffi::nerd_font_family()
    }

    fn reveal(&self, path: &QString) -> QString {
        let path = PathBuf::from(path.to_string());
        let why = match gone(&path) {
            Some(why) => why,
            None => match reveal(&path) {
                Ok(()) => String::new(),
                Err(e) => format!("Can't show “{}”: {e}", listing::show_path(&path)),
            },
        };
        QString::from(why.as_str())
    }

    fn open_in_app(self: Pin<&mut Self>, path: &QString) -> QString {
        let path = PathBuf::from(path.to_string());
        if let Some(why) = gone(&path) {
            return QString::from(why.as_str());
        }
        let thread = self.qt_thread();
        thread::spawn(move || {
            if let Err(why) = open_in_app(&path) {
                let _ = thread.queue(move |system| system.open_failed(QString::from(&why)));
            }
        });
        QString::default()
    }

    fn link_at(&self, line: &QString, column: i32, names: bool) -> QString {
        let found = usize::try_from(column)
            .ok()
            .and_then(|at| link::link_at(line.as_slice(), at, names));
        to_json(&found.map(|r| json!({ "start": r.start, "end": r.end })))
    }

    fn link_target(&self, text: &QString, dirs: &QStringList) -> QString {
        to_json(&link::target(&text.to_string(), &paths(dirs)))
    }

    fn default_shell(&self) -> QString {
        QString::from(shell::default_shell().as_str())
    }

    fn shells(&self) -> QString {
        to_json(&shell::shells())
    }

    fn load_shell_environment(&self) {
        shell::load_environment();
    }

    fn run_shell(self: Pin<&mut Self>, request: &QString) -> QString {
        let started = serde_json::from_str::<shell::Request>(&request.to_string())
            .map_err(|e| e.to_string())
            .and_then(|request| shell::start(&request, &self.running));
        let (line, error) = match started {
            Ok((line, started)) => {
                let thread = self.qt_thread();
                let running = self.running.clone();
                thread::spawn(move || {
                    let ran = started.finish(&running);
                    let _ = thread.queue(move |system| system.shell_done(to_json(&ran)));
                });
                (line, String::new())
            }
            Err(error) => (String::new(), error),
        };
        to_json(&json!({ "line": line, "error": error }))
    }

    fn stop_shell(&self) {
        self.running.stop();
    }

    fn same_string(&self, a: &QString, b: &QString) -> bool {
        let (a, b) = (a.as_slice(), b.as_slice());
        a.len() == b.len() && a.as_ptr() == b.as_ptr()
    }

    fn same_text(&self, a: &QString, b: &QString) -> bool {
        self.same_string(a, b) || a.as_slice() == b.as_slice()
    }

    fn kept_as_is(&self, text: &QString) -> bool {
        // \r, a no-break space, the line and paragraph separators (U+2028
        // and U+2029) and the frame's start and end (U+FDD0 and U+FDD1). A
        // chunk at a time, each gone through whole, which the compiler does
        // many characters at once: a character at a time, a gigabyte took a
        // second.
        !text.as_slice().chunks(1 << 16).any(|chunk| {
            chunk.iter().fold(0u16, |found, &c| {
                found
                    | u16::from(c == 0x0d)
                    | u16::from(c == 0xa0)
                    | u16::from((c | 1) == 0x2029)
                    | u16::from((c | 1) == 0xfdd1)
            }) != 0
        })
    }

    forward! {
        set_line_format(
            text_document, height: f64, bottom_margin: f64, indent: f64, right_margin: f64
        );
        set_text(
            text_edit, text: &QString, height: f64, bottom_margin: f64, indent: f64,
            right_margin: f64
        );
        follow_text_length(text_edit);
        redraw_text(text_edit);
        replace_text(text_edit, start: i32, end: i32, text: &QString);
        watch_long_lines(text_document, long_length: i32);
        place_long_lines(text_document, line_height: f64, bottom_margin: f64, row_length: i32);
        longest_line(text_document) -> i32;
        long_line_spot(text_document, position: i32) -> QString;
        long_line_position(text_document, row: i32, column: f64) -> i32;
        long_line_runs(
            text_document, first_row: i32, last_row: i32, first_column: i32, last_column: i32
        ) -> QString;
        watch_text_changes(text_document);
        take_text_change(text_document, with_text: bool) -> QStringList;
        rebuild_text_nodes(text_edit);
        scroll_to_cursor_in_qml(text_area);
        set_listing_colors(
            text_document, icon_colors: &QStringList, pending_icon_color: &QString,
            directory_color: &QString
        );
        set_pending_lines(text_document, lines: &QStringList);
        set_path_colors(text_document, directory_color: &QString, spans: &QStringList);
        set_keyword_colors(text_document, keyword_colors: &QStringList);
        set_text_colors(text_document, colors: &QStringList, file_name: &QString);
    }
}

/// Why `path` can't be shown or opened, if it's gone from disk.
fn gone(path: &Path) -> Option<String> {
    let shown = listing::show_path(path);
    (path.symlink_metadata().is_err()).then(|| format!("“{shown}” isn't on disk any more"))
}

/// Shows `path` selected in the dir it's in, in Finder or Explorer, or
/// elsewhere opens that dir, without waiting for it.
fn reveal(path: &Path) -> io::Result<()> {
    #[cfg(target_os = "macos")]
    let mut command = {
        let mut command = Command::new("open");
        command.arg("-R").arg(path);
        command
    };
    #[cfg(not(target_os = "macos"))]
    let mut command = file_manager(path, true);
    // Koil's stdout is the scratchpad's text with -p (see cli.rs).
    let mut child = command.stdout(Stdio::null()).spawn()?;
    // waited for, so it doesn't stay a zombie once it's done
    thread::spawn(move || child.wait());
    Ok(())
}

/// Opens `path` as a double-click in Finder or Explorer does, and waits for
/// the command (not for the app), so it's for a thread. The error is why it
/// failed, to show.
fn open_in_app(path: &Path) -> Result<(), String> {
    let shown = listing::show_path(path);
    #[cfg(target_os = "macos")]
    {
        let output = Command::new("open")
            .arg(path)
            .output()
            .map_err(|e| format!("Can't open “{shown}”: {e}"))?;
        if output.status.success() {
            return Ok(());
        }
        let stderr = String::from_utf8_lossy(&output.stderr);
        // which `open` says with the URL and the whole NSError
        if stderr.contains("kLSApplicationNotFoundErr") {
            return Err(format!("No app opens “{shown}”"));
        }
        let why = stderr.lines().next().map(str::trim).unwrap_or_default();
        let why = if why.is_empty() {
            output.status.to_string()
        } else {
            why.to_string()
        };
        Err(format!("Can't open “{shown}”: {why}"))
    }
    // Explorer exits with 1 whatever happened (and asks which app itself),
    // and xdg-open's app can keep its output open, so only starting it is
    // checked.
    #[cfg(not(target_os = "macos"))]
    {
        // Not Koil's stdout, which is the scratchpad's text with -p: the
        // app would write in it, and keep a pipe reading it from ending.
        let mut child = file_manager(path, false)
            .stdout(Stdio::null())
            .spawn()
            .map_err(|e| format!("Can't open “{shown}”: {e}"))?;
        // so it doesn't stay a zombie once it's done
        let _ = child.wait();
        Ok(())
    }
}

/// Explorer (or elsewhere xdg-open) opening `path`, or with `select`,
/// showing it selected in the dir it's in (xdg-open opens that dir).
#[cfg(not(target_os = "macos"))]
fn file_manager(path: &Path, select: bool) -> Command {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        // Explorer reads its command line itself: the path, with `\` only,
        // quoted (after the comma: Command would quote all of it).
        let path = path.to_string_lossy().replace('/', "\\");
        let mut command = Command::new("explorer");
        command.raw_arg(format!(
            "{}\"{path}\"",
            if select { "/select," } else { "" }
        ));
        command
    }
    #[cfg(not(windows))]
    {
        let mut command = Command::new("xdg-open");
        command.arg(if select {
            path.parent().unwrap_or(path)
        } else {
            path
        });
        command
    }
}
