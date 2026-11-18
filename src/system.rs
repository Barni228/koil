use std::io;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::process::{Command, Stdio};
use std::thread;

use cxx_qt::Threading;
use cxx_qt_lib::{QByteArray, QList, QString, QStringList};
use serde::{Deserialize, Serialize};
use serde_json::json;

use crate::convert::{paths, to_json};
use crate::ffi;
use crate::link;
use crate::listing;
use crate::shell;

#[cfg(test)]
mod tests;

/// What the QML needs from the system, mostly through Qt's C++ side: the
/// clipboard, the installed fonts and the one Koil ships, the editor's line
/// height and the listing's and path field's colors, showing a path in
/// Finder (or Explorer) or opening it in its default app (or another that
/// can open it, as Open With does), the links gf,
/// gx and a click with Cmd open (see link.rs), and running shell commands
/// (see shell.rs).
#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qstringlist.h");
        type QStringList = cxx_qt_lib::QStringList;
        include!("cxx-qt-lib/qlist.h");
        type QList_i32 = cxx_qt_lib::QList<i32>;
        include!("cxx-qt-lib/qbytearray.h");
        type QByteArray = cxx_qt_lib::QByteArray;
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

        /// The apps that can open `path`, as Finder's (Explorer's) Open
        /// With lists them, for Space O: `{ apps, message }`, each app
        /// `{ name, path, default, place }` (see `sorted_apps`), or with
        /// `name`, only those it names, or that name alone, for an app
        /// the system looks for (see `named`); `message` says why there's
        /// none.
        #[qinvokable]
        fn apps_to_open(self: &System, path: &QString, name: &QString) -> QString;

        /// Opens `path` with the app at `app` (one `apps_to_open` gave,
        /// `name` what it's called; or an app's name or path, which the
        /// system looks for), for Space O, without waiting for it.
        /// Returns why it can't, or "", and emits `open_failed` if it fails
        /// after.
        #[qinvokable]
        fn open_with(
            self: Pin<&mut System>,
            path: &QString,
            app: &QString,
            name: &QString,
        ) -> QString;

        /// Emitted when `open_in_app` or `open_with` failed after it
        /// returned, with why.
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

        /// Emitted while that command runs, with what it wrote since, as
        /// shown (a `shell::Output`, as JSON), and all of it before
        /// `shell_done`.
        #[qsignal]
        fn shell_output(self: Pin<&mut System>, output: QString);

        /// Lays out a TextEdit's text as Koil does: every line's rows
        /// `line_height` tall, its baseline `baseline` down a row, clear of
        /// the `right_margin`, broken after spaces or at a word's edge (not
        /// in a `listing` line's prefix), and lines longer than
        /// `long_length` hidden from Qt (see native.h).
        #[qinvokable]
        unsafe fn set_line_format(
            self: &System,
            text_edit: *mut QObject,
            line_height: f64,
            baseline: f64,
            right_margin: f64,
            listing: bool,
            long_length: i32,
        );

        /// How wide the widest line `set_line_format` lays out is,
        /// unwrapped, which the TextEdit is made as wide as while lines
        /// don't wrap (see native.h).
        #[qinvokable]
        unsafe fn layout_width(self: &System, text_document: *mut QObject) -> f64;

        /// Sets a TextEdit's text as one edit (see native.h).
        #[qinvokable]
        unsafe fn set_text(self: &System, text_edit: *mut QObject, text: &QString);

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

        /// Why `pattern` isn't a regular expression, or empty if it is
        /// one: PCRE2's, which the search, :s, the find bar and the help's
        /// search look for (see text.js's `regExp`). `flags` has an `i` to
        /// ignore case.
        #[qinvokable]
        fn regex_error(self: &System, pattern: &QString, flags: &QString) -> QString;

        /// The matches of `pattern` in `text` that start from `from` up to
        /// `to` (UTF-16 indexes), at most `limit`, and with an `l` in
        /// `flags` only the first that starts on each line: how many
        /// numbers a match takes, then for each where it and each of its
        /// groups start and end (-1 for a group that took no part), as
        /// the bytes of an `Int32Array` (QML's `ArrayBuffer`). Empty if
        /// `pattern` isn't valid.
        #[qinvokable]
        fn regex_matches(
            self: &System,
            text: &QString,
            pattern: &QString,
            flags: &QString,
            from: i32,
            to: i32,
            limit: i32,
        ) -> QByteArray;

        /// Where the last match of `pattern` in `text` that starts before
        /// `at` starts, then where the last of all does (looked for only
        /// without the first), -1 for none.
        #[qinvokable]
        fn regex_before(
            self: &System,
            text: &QString,
            pattern: &QString,
            flags: &QString,
            at: i32,
        ) -> QList_i32;

        /// The name of each group of `pattern`, the whole match (empty)
        /// first; empty for one without a name.
        #[qinvokable]
        fn regex_group_names(self: &System, pattern: &QString, flags: &QString) -> QStringList;

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

        /// Has a TextArea in a ScrollView leave scrolling to its cursor to
        /// its QML (see native.h).
        #[qinvokable]
        unsafe fn scroll_to_cursor_in_qml(self: &System, text_area: *mut QObject);

        /// Colors Koil's listing in a TextEdit's `textDocument`: each icon in
        /// `icon_colors` (icons and colors, alternating), or a pending
        /// entry's in `pending_icon_color`, the names of files that can be
        /// run in `executable_color`, and dirs in `directory_color`. No
        /// `directory_color` takes the colors away.
        #[qinvokable]
        unsafe fn set_listing_colors(
            self: &System,
            text_document: *mut QObject,
            icon_colors: &QStringList,
            pending_icon_color: &QString,
            executable_color: &QString,
            directory_color: &QString,
        );

        /// The lines of the listing in `textDocument` (numbers, from 0) whose
        /// entries applying would change, whose icons get the pending color,
        /// and those of files that can be run, whose names get theirs.
        #[qinvokable]
        unsafe fn set_entry_lines(
            self: &System,
            text_document: *mut QObject,
            pending_lines: &QStringList,
            executable_lines: &QStringList,
        );

        /// Colors the path field's `textDocument`: all of it in
        /// `directory_color`, and parts of it (a pattern's) over that: `spans`
        /// holds a start, a length and a color for each part.
        #[qinvokable]
        unsafe fn set_path_colors(
            self: &System,
            text_document: *mut QObject,
            directory_color: &QString,
            spans: &QStringList,
        );

        /// Colors spans of the lines of `textDocument`: `spans` holds a
        /// line (from 0), a start and a length in it (in UTF-16) and a
        /// color for each span, in that order. None takes the colors away.
        #[qinvokable]
        unsafe fn set_span_colors(self: &System, text_document: *mut QObject, spans: &QStringList);

        /// Colors a file's `textDocument` (see syntax.rs): `colors` has a
        /// color for each kind of part, in the order of `SyntaxKind`, and
        /// `file_name` says which comments it can have. `icon_colors`
        /// (the scratchpad's), `directory_color` and `executable_color`
        /// are the listing's, as `set_listing_colors` takes them, for the
        /// lines that start with an icon. Neither colors nor icons take
        /// them away.
        #[qinvokable]
        unsafe fn set_text_colors(
            self: &System,
            text_document: *mut QObject,
            colors: &QStringList,
            file_name: &QString,
            icon_colors: &QStringList,
            directory_color: &QString,
            executable_color: &QString,
        );

        /// Tells `set_text_colors` which lines (numbers, from 0) have an
        /// entry pasted with its ID, colored as the listing's, and which of
        /// those a file that can be run, whose name is green.
        #[qinvokable]
        unsafe fn set_text_entry_lines(
            self: &System,
            text_document: *mut QObject,
            entry_lines: &QStringList,
            executable_lines: &QStringList,
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

    fn apps_to_open(&self, path: &QString, name: &QString) -> QString {
        let path = PathBuf::from(path.to_string());
        let shown = listing::show_path(&path);
        let name = name.to_string();
        let name = name.trim();
        let found = match gone(&path) {
            Some(why) => Err(why),
            None => apps_to_open(&path).and_then(|apps| {
                if !name.is_empty() {
                    Ok(named(&apps, name))
                } else if apps.is_empty() {
                    Err(format!("No app opens “{shown}”"))
                } else {
                    Ok(apps)
                }
            }),
        };
        let (apps, message) = match found {
            Ok(apps) => (apps, String::new()),
            Err(why) => (Vec::new(), why),
        };
        to_json(&json!({ "apps": apps, "message": message }))
    }

    fn open_with(self: Pin<&mut Self>, path: &QString, app: &QString, name: &QString) -> QString {
        let path = PathBuf::from(path.to_string());
        if let Some(why) = gone(&path) {
            return QString::from(why.as_str());
        }
        let shown = listing::show_path(&path);
        let name = name.to_string();
        let failed = move |why: String| format!("Can't open “{shown}” with {name}: {why}");
        // `open -a` takes an app's path, as the list gives, or its name,
        // which Launch Services looks for, whatever it claims.
        #[cfg(target_os = "macos")]
        {
            let app = PathBuf::from(app.to_string());
            // which `open` would say with the whole NSError
            if app.is_absolute() && app.symlink_metadata().is_err() {
                return QString::from(failed("it isn't on disk any more".to_string()).as_str());
            }
            let thread = self.qt_thread();
            thread::spawn(move || {
                let opened = run_open(Command::new("open").arg("-a").arg(app).arg(&path));
                if let Err(why) = opened {
                    let why = failed(if why.starts_with("Unable to find application named") {
                        NO_APP.to_string()
                    } else {
                        why
                    });
                    let _ = thread.queue(move |system| system.open_failed(QString::from(&why)));
                }
            });
            QString::default()
        }
        // The shell's handler runs the app's own command, and doesn't wait
        // for it.
        #[cfg(windows)]
        {
            let _ = self;
            let why = ffi::open_with_app(&QString::from(path.to_string_lossy().as_ref()), app);
            if why.is_empty() {
                why
            } else {
                QString::from(failed(why.to_string()).as_str())
            }
        }
        #[cfg(not(any(target_os = "macos", windows)))]
        {
            let _ = (self, app, failed);
            QString::from("Koil can't open a file with another app here")
        }
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
                    let ran = started.finish(&running, |output| {
                        let _ = thread.queue(move |system| {
                            system.shell_output(to_json(&output));
                        });
                    });
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

    fn regex_error(&self, pattern: &QString, flags: &QString) -> QString {
        ffi::regex_error(pattern, flags)
    }

    fn regex_matches(
        &self,
        text: &QString,
        pattern: &QString,
        flags: &QString,
        from: i32,
        to: i32,
        limit: i32,
    ) -> QByteArray {
        ffi::regex_matches(text, pattern, flags, from, to, limit)
    }

    fn regex_before(
        &self,
        text: &QString,
        pattern: &QString,
        flags: &QString,
        at: i32,
    ) -> QList<i32> {
        ffi::regex_before(text, pattern, flags, at)
    }

    fn regex_group_names(&self, pattern: &QString, flags: &QString) -> QStringList {
        ffi::regex_group_names(pattern, flags)
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
            text_edit, line_height: f64, baseline: f64, right_margin: f64, listing: bool,
            long_length: i32
        );
        layout_width(text_document) -> f64;
        set_text(text_edit, text: &QString);
        follow_text_length(text_edit);
        redraw_text(text_edit);
        replace_text(text_edit, start: i32, end: i32, text: &QString);
        longest_line(text_document) -> i32;
        long_line_spot(text_document, position: i32) -> QString;
        long_line_position(text_document, row: i32, column: f64) -> i32;
        long_line_runs(
            text_document, first_row: i32, last_row: i32, first_column: i32, last_column: i32
        ) -> QString;
        watch_text_changes(text_document);
        take_text_change(text_document, with_text: bool) -> QStringList;
        scroll_to_cursor_in_qml(text_area);
        set_listing_colors(
            text_document, icon_colors: &QStringList, pending_icon_color: &QString,
            executable_color: &QString, directory_color: &QString
        );
        set_entry_lines(
            text_document, pending_lines: &QStringList, executable_lines: &QStringList
        );
        set_path_colors(text_document, directory_color: &QString, spans: &QStringList);
        set_span_colors(text_document, spans: &QStringList);
        set_text_colors(
            text_document, colors: &QStringList, file_name: &QString, icon_colors: &QStringList,
            directory_color: &QString, executable_color: &QString
        );
        set_text_entry_lines(
            text_document, entry_lines: &QStringList, executable_lines: &QStringList
        );
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
        run_open(Command::new("open").arg(path)).map_err(|why| {
            // which `open` says with the URL and the whole NSError
            if why.contains("kLSApplicationNotFoundErr") {
                format!("No app opens “{shown}”")
            } else {
                format!("Can't open “{shown}”: {why}")
            }
        })
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

/// Runs `command`, macOS's `open`, and waits for it (not for the app it
/// launches), so it's for a thread. The error is why it failed: the first
/// line of what it wrote, or else how it exited.
#[cfg(target_os = "macos")]
fn run_open(command: &mut Command) -> Result<(), String> {
    let output = command.output().map_err(|e| e.to_string())?;
    if output.status.success() {
        return Ok(());
    }
    let stderr = String::from_utf8_lossy(&output.stderr);
    match stderr.lines().next().map(str::trim) {
        Some(why) if !why.is_empty() => Err(why.to_string()),
        _ => Err(output.status.to_string()),
    }
}

/// Why an app named but not listed can't open a file: the system found
/// none of that name (see `named`), as native.h's `openWithApp` says too.
#[cfg(target_os = "macos")]
const NO_APP: &str = "there's no app of that name";

/// An app that can open a file, as Finder's (Explorer's) Open With lists
/// it (see native.h's `appsToOpen`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct App {
    /// What the system calls it (Finder's name, without `.app`).
    pub name: String,
    /// Where it is, which opens the file with it (see `System::open_with`),
    /// or for one that isn't listed, as typed (see `named`).
    pub path: String,
    /// Whether it's the file's default app.
    #[serde(default)]
    pub default: bool,
    /// Where it is, as shown, if another app in the list has its name (two
    /// versions of one), to tell them apart; else "".
    #[serde(default)]
    pub place: String,
}

/// The apps that can open `path`, as `sorted_apps` puts them, or why Koil
/// can't tell.
fn apps_to_open(path: &Path) -> Result<Vec<App>, String> {
    let json = ffi::apps_to_open(&QString::from(path.to_string_lossy().as_ref())).to_string();
    if json.is_empty() {
        return Err("Koil can't tell which apps open a file here".to_string());
    }
    let apps = serde_json::from_str::<Vec<App>>(&json).map_err(|e| e.to_string())?;
    Ok(sorted_apps(apps))
}

/// `apps` as the list shows them: the default first, then by name (case
/// left out), each once (by its path), with where it is if another has its
/// name.
pub fn sorted_apps(apps: Vec<App>) -> Vec<App> {
    let mut kept: Vec<App> = Vec::new();
    for app in apps {
        match kept.iter_mut().find(|k| k.path == app.path) {
            Some(same) => same.default |= app.default,
            None => kept.push(app),
        }
    }
    kept.sort_by_cached_key(|app| (!app.default, app.name.to_lowercase(), app.path.clone()));
    let names: Vec<String> = kept.iter().map(|app| app.name.to_lowercase()).collect();
    for (i, app) in kept.iter_mut().enumerate() {
        let twin = names
            .iter()
            .enumerate()
            .any(|(j, n)| j != i && *n == names[i]);
        app.place = if twin {
            listing::show_path(Path::new(&app.path))
        } else {
            String::new()
        };
    }
    kept
}

/// The apps of `apps` that `name` names (case left out): those it's the
/// name or the path of, or else those whose names start with it, or else
/// those whose names have it. If none does, an app `name` is the name or
/// path of, which the system looks for as it opens the file (`open -a`,
/// ShellExecute; see `System::open_with`), as an app can open a file of a
/// type it doesn't claim.
pub fn named(apps: &[App], name: &str) -> Vec<App> {
    let typed = name;
    let name = name.to_lowercase();
    let tests: [&dyn Fn(&App) -> bool; 3] = [
        &|app| app.name.to_lowercase() == name || app.path.to_lowercase() == name,
        &|app| app.name.to_lowercase().starts_with(&name),
        &|app| app.name.to_lowercase().contains(&name),
    ];
    tests
        .iter()
        .map(|test| {
            apps.iter()
                .filter(|app| test(app))
                .cloned()
                .collect::<Vec<_>>()
        })
        .find(|found| !found.is_empty())
        .unwrap_or_else(|| {
            vec![App {
                name: typed.to_string(),
                path: typed.to_string(),
                default: false,
                place: String::new(),
            }]
        })
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
