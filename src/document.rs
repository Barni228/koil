use std::io;
use std::path::{Component, Path, PathBuf};
use std::pin::Pin;
use std::time::{SystemTime, UNIX_EPOCH};

use cxx_qt::casting::{Downcast, Upcast};
use cxx_qt::{CxxQtThread, CxxQtType, Threading};
use cxx_qt_lib::{QString, QUrl};
use notify::{EventKind, RecommendedWatcher, RecursiveMode, Watcher};

use crate::convert::{Coalesced, path_string, to_json};
#[cfg(target_os = "macos")]
use crate::install;
use crate::{cli, ffi, listing};

/// Files the editor opens and saves, and the path on the command line.
#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qurl.h");
        type QUrl = cxx_qt_lib::QUrl;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qobject]
        #[qml_element]
        type Document = super::DocumentRust;

        /// Emitted after a file was read successfully.
        #[qsignal]
        fn loaded(self: Pin<&mut Document>, path: QString, text: QString);

        /// Emitted for each file the system asks Koil to open, once
        /// `watch_file_opens` was called: macOS's Open With, which gives no
        /// path on the command line.
        #[qsignal]
        fn file_opened(self: Pin<&mut Document>, path: QString);

        /// Emitted for each request of "Open in Koil", once
        /// `watch_finder_service` was called: the macOS service, with what's
        /// selected in Finder (the first, if there are several), and with
        /// `file` if it isn't a folder (or is an app, which Finder shows as
        /// a file), whose folder then opens.
        #[qsignal]
        fn folder_requested(self: Pin<&mut Document>, path: QString, file: bool);

        /// Emitted when writing fails, with why.
        #[qsignal]
        fn failed(self: Pin<&mut Document>, message: QString);

        /// Emitted when the file `watch_file` watches may have changed on
        /// disk (see `file_change`), on the GUI thread, once for a burst of
        /// changes.
        #[qsignal]
        fn file_changed(self: Pin<&mut Document>);

        /// Emitted once `change_command` is done, with why it failed, or
        /// empty (also when the user cancelled macOS's password dialog).
        #[qsignal]
        fn command_changed(self: Pin<&mut Document>, error: QString);

        /// Reads the file `path`, and emits `loaded`; or else returns why it
        /// can't (empty if it could). It must be UTF-8, or UTF-16 after a BOM,
        /// which `save_file` then writes back the same way.
        #[qinvokable]
        fn open_file(self: Pin<&mut Document>, path: &QString) -> QString;

        /// Has `file_opened` emitted from now on.
        #[qinvokable]
        fn watch_file_opens(self: Pin<&mut Document>);

        /// Watches the file `path` (none, if it's empty) for `file_changed`.
        #[qinvokable]
        fn watch_file(self: Pin<&mut Document>, path: &QString);

        /// How the file `path` changed on disk since Koil last read or wrote
        /// it, as its size and the time it was modified tell: "changed",
        /// "gone", or "" if it didn't (or Koil read or wrote another one
        /// since). Each change is told once.
        #[qinvokable]
        fn file_change(self: Pin<&mut Document>, path: &QString) -> QString;

        /// Has `folder_requested` emitted from now on; call it before the
        /// app runs, so the request that launched it comes. macOS only.
        #[qinvokable]
        fn watch_finder_service(self: Pin<&mut Document>);

        /// The shortcut of "Open in Koil" (see `folder_requested`), as
        /// macOS shows it (⌃⇧K). Empty if it has none or is off, outside an
        /// app bundle, or not on macOS.
        #[qinvokable]
        fn finder_service_shortcut(self: &Document) -> QString;

        /// What's where the `koil` command goes (see install.rs):
        /// "missing", "installed" (this Koil's), "otherKoil" (one moved, or
        /// another copy) or "other" (another program). Empty if not on
        /// macOS.
        #[qinvokable]
        fn command_status(self: &Document) -> QString;

        /// Installs the `koil` command for this Koil, or with `remove`,
        /// removes it, on another thread (macOS may ask for a password),
        /// then emits `command_changed`. macOS only.
        #[qinvokable]
        fn change_command(self: Pin<&mut Document>, remove: bool);

        /// Writes `text` to the file `path`, stored as the file opened last
        /// was; or else emits `failed`.
        #[qinvokable]
        fn save_file(self: Pin<&mut Document>, path: &QString, text: &QString) -> bool;

        /// Writes `text`, which wasn't read from a file (the scratchpad's),
        /// to the file `path` as UTF-8; or else emits `failed`.
        #[qinvokable]
        fn save_new_file(self: Pin<&mut Document>, path: &QString, text: &QString) -> bool;

        /// Writes `text` (the scratchpad's) to the scratchpad's own file, as
        /// UTF-8, for `%` in a shell command run there, and returns its
        /// path: `scratchpad.txt` in a dir of this Koil's in the temp dir,
        /// which goes when it quits. Or else emits `failed`, and returns
        /// "". A line break ends its last line, as vim writes one, so
        /// `echo hi >> %` writes a line of its own.
        #[qinvokable]
        fn write_scratchpad(self: Pin<&mut Document>, text: &QString) -> QString;

        /// The text in the scratchpad's file (see `write_scratchpad`), as a
        /// command left it, with what isn't text as `�`, like text piped in,
        /// and without the line break at its end if the scratchpad had
        /// none.
        #[qinvokable]
        fn read_scratchpad(self: &Document) -> QString;

        /// The path passed on the command line, if any: a file to open, or a
        /// dir (or pattern) for Koil to list. Absolute, from the dir Koil was
        /// started in.
        #[qinvokable]
        fn startup_path(self: &Document) -> QString;

        /// Whether Koil starts in the scratchpad: `-s` on the command line,
        /// or text from stdin (see `cli::read_stdin`).
        #[qinvokable]
        fn startup_scratchpad(self: &Document) -> bool;

        /// The scratchpad's text from stdin, given once (empty after).
        #[qinvokable]
        fn take_startup_text(self: &Document) -> QString;

        /// Prints `text`, the scratchpad's as Koil quits, if `-p` on the
        /// command line asked for it (see `cli::print_scratchpad`).
        #[qinvokable]
        fn print_scratchpad(self: &Document, text: &QString);

        /// The line `+N` on the command line puts the cursor on: 0 for the
        /// last one, -1 for none.
        #[qinvokable]
        fn startup_line(self: &Document) -> i32;

        /// The Ex commands `-c` on the command line runs once what's shown
        /// is, in order, as JSON: a list of strings.
        #[qinvokable]
        fn startup_commands(self: &Document) -> QString;

        /// The dir (or pattern) Koil lists when no path is given, as the
        /// Settings window's "Start in" `setting` has it: read from the home
        /// dir if it's relative (and doesn't start with `~`). Empty if the
        /// setting is, for the home dir.
        #[qinvokable]
        fn start_dir(self: &Document, setting: &QString) -> QString;

        /// `path` as the path field shows it, with `~` for the home dir.
        #[qinvokable]
        fn shown_path(self: &Document, path: &QString) -> QString;

        /// Whether `path` is a file (or a link to one), rather than a dir or
        /// nothing.
        #[qinvokable]
        fn is_file(self: &Document, path: &QString) -> bool;

        /// Whether `path` is a dir (or a link to one), which the listing
        /// shows with a `/` after its name.
        #[qinvokable]
        fn is_dir(self: &Document, path: &QString) -> bool;

        /// The dir `path` is in, as an absolute path.
        #[qinvokable]
        fn dir_of(self: &Document, path: &QString) -> QString;

        /// The home dir, which Koil lists when no path is given (and the
        /// Settings window doesn't say otherwise).
        #[qinvokable]
        fn home_dir(self: &Document) -> QString;

        #[qinvokable]
        fn url_to_path(self: &Document, url: &QUrl) -> QString;
    }

    impl cxx_qt::Threading for Document {}
}

#[derive(Default)]
pub struct DocumentRust {
    /// How the file opened last was stored.
    encoding: Encoding,
    /// The file Koil read or wrote last, as it was then (none if it wasn't
    /// there), which `file_change` tells changes from.
    known: Option<(PathBuf, Option<Stamp>)>,
    /// Watches the file shown, for `file_changed`.
    watcher: Option<FileWatcher>,
    /// The dir the scratchpad's file is in, once it's made, and whether
    /// the line break at its end was added.
    scratch_dir: Option<PathBuf>,
    scratch_break: bool,
}

impl DocumentRust {
    /// The scratchpad's file (see `Document::write_scratchpad`), making its
    /// dir the first time: a new one, which only the user can read, so
    /// nothing else can be in its place (`/tmp` is everyone's on Linux).
    fn scratchpad_file(&mut self) -> io::Result<PathBuf> {
        if self.scratch_dir.is_none() {
            let nanos = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map_or(0, |d| d.subsec_nanos());
            let dir = std::env::temp_dir().join(format!("koil-{}-{nanos}", std::process::id()));
            let mut builder = std::fs::DirBuilder::new();
            #[cfg(unix)]
            std::os::unix::fs::DirBuilderExt::mode(&mut builder, 0o700);
            builder.create(&dir)?;
            self.scratch_dir = Some(dir);
        }
        Ok(self.scratch_dir.as_ref().unwrap().join(SCRATCHPAD))
    }
}

impl Drop for DocumentRust {
    fn drop(&mut self) {
        if let Some(dir) = &self.scratch_dir {
            let _ = std::fs::remove_dir_all(dir);
        }
    }
}

/// The name of the scratchpad's file.
const SCRATCHPAD: &str = "scratchpad.txt";

/// What tells that a file changed on disk: its size, and when it was
/// modified.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Stamp {
    len: u64,
    modified: Option<SystemTime>,
}

impl Stamp {
    /// The file `path`'s, or None if it isn't there.
    fn of(path: &Path) -> Option<Stamp> {
        let metadata = std::fs::metadata(path).ok()?;
        Some(Stamp {
            len: metadata.len(),
            modified: metadata.modified().ok(),
        })
    }
}

/// Watches a file for changes on disk, through the dir it's in, as an app
/// may save it by writing another file and renaming that over it.
struct FileWatcher {
    path: PathBuf,
    _watcher: RecommendedWatcher,
}

impl FileWatcher {
    /// Watches `path`, emitting `file_changed` once for each burst of
    /// changes to it. None if it can't.
    fn new(path: PathBuf, thread: CxxQtThread<qobject::Document>) -> Option<FileWatcher> {
        // Links followed, as the changes name it.
        let target = std::fs::canonicalize(&path).ok()?;
        let dir = target.parent()?.to_path_buf();
        let changed = Coalesced::new(thread);
        let handler = move |event: notify::Result<notify::Event>| {
            let matters = match &event {
                Ok(event) => {
                    !matches!(event.kind, EventKind::Access(_))
                        && (event.need_rescan() || event.paths.contains(&target))
                }
                // Changes may have been missed.
                Err(_) => true,
            };
            if matters {
                changed.emit(|document| document.file_changed());
            }
        };
        let mut watcher = notify::recommended_watcher(handler).ok()?;
        watcher.watch(&dir, RecursiveMode::NonRecursive).ok()?;
        Some(FileWatcher {
            path,
            _watcher: watcher,
        })
    }
}

impl qobject::Document {
    fn open_file(mut self: Pin<&mut Self>, path: &QString) -> QString {
        let file = PathBuf::from(path.to_string());
        // Before it's read: a change after it is one.
        let stamp = Stamp::of(&file);
        match read(&path.to_string()) {
            Ok((text, encoding)) => {
                let mut rust = self.as_mut().rust_mut();
                rust.encoding = encoding;
                rust.known = Some((file, stamp));
                // Not kept while QML shows it: a long file's is a gigabyte.
                let shown = QString::from(text.as_str());
                drop(text);
                self.loaded(path.clone(), shown);
                QString::default()
            }
            Err(message) => QString::from(message.as_str()),
        }
    }

    /// This Document as the QObject native.cpp emits its signals on.
    fn object(self: Pin<&mut Self>) -> &mut cxx_qt::QObject {
        // SAFETY: the QObject is only used where it is.
        unsafe { Pin::into_inner_unchecked(self.upcast_pin()) }
    }

    fn watch_file_opens(self: Pin<&mut Self>) {
        // SAFETY: the pointer is to this Document, a live QObject, which
        // fileOpened is emitted on (it's in its meta-object).
        unsafe { ffi::watch_file_opens(self.object()) };
    }

    fn watch_file(self: Pin<&mut Self>, path: &QString) {
        let path = PathBuf::from(path.to_string());
        let thread = self.qt_thread();
        let mut rust = self.rust_mut();
        if rust.watcher.as_ref().is_some_and(|w| w.path == path) {
            return;
        }
        rust.watcher = None;
        if !path.as_os_str().is_empty() {
            rust.watcher = FileWatcher::new(path, thread);
        }
    }

    fn file_change(self: Pin<&mut Self>, path: &QString) -> QString {
        let path = PathBuf::from(path.to_string());
        let mut rust = self.rust_mut();
        let Some((known, was)) = &mut rust.known else {
            return QString::default();
        };
        let now = Stamp::of(&path);
        if *known != path || now == *was {
            return QString::default();
        }
        *was = now;
        QString::from(if now.is_some() { "changed" } else { "gone" })
    }

    fn watch_finder_service(self: Pin<&mut Self>) {
        // SAFETY: the pointer is to this Document, a live QObject, which
        // folderRequested is emitted on (it's in its meta-object).
        unsafe { ffi::watch_finder_service(self.object()) };
    }

    fn finder_service_shortcut(&self) -> QString {
        ffi::finder_service_shortcut()
    }

    fn command_status(&self) -> QString {
        #[cfg(target_os = "macos")]
        if let Ok(exe) = this_exe() {
            let status = install::status(Path::new(install::COMMAND), &exe);
            return QString::from(status.name());
        }
        QString::default()
    }

    fn change_command(self: Pin<&mut Self>, remove: bool) {
        let thread = self.qt_thread();
        std::thread::spawn(move || {
            let error = change_command(remove);
            let _ = thread.queue(move |document| document.command_changed(QString::from(&error)));
        });
    }

    fn save_file(self: Pin<&mut Self>, path: &QString, text: &QString) -> bool {
        let encoding = self.encoding;
        self.write(path, &text.to_string(), encoding)
    }

    fn save_new_file(self: Pin<&mut Self>, path: &QString, text: &QString) -> bool {
        self.write(path, &text.to_string(), Encoding::Utf8)
    }

    fn write_scratchpad(mut self: Pin<&mut Self>, text: &QString) -> QString {
        let mut rust = self.as_mut().rust_mut();
        let path = match rust.scratchpad_file() {
            Ok(path) => path_string(&path),
            Err(err) => {
                self.failed(QString::from(cannot("save", SCRATCHPAD, &err).as_str()));
                return QString::default();
            }
        };
        let mut text = text.to_string();
        rust.scratch_break = !text.is_empty() && !text.ends_with('\n');
        if rust.scratch_break {
            text.push('\n');
        }
        match self.write(&path, &text, Encoding::Utf8) {
            true => path,
            false => QString::default(),
        }
    }

    fn read_scratchpad(&self) -> QString {
        let file = self.scratch_dir.as_ref().map(|dir| dir.join(SCRATCHPAD));
        let bytes = file.and_then(|file| std::fs::read(file).ok());
        let text = decode_lossy(bytes.unwrap_or_default());
        let text = match self.scratch_break {
            true => text.strip_suffix('\n').unwrap_or(&text),
            false => &text,
        };
        QString::from(text)
    }

    /// Writes `text` to the file `path`, stored as `encoding` says; or else
    /// emits `failed`.
    fn write(mut self: Pin<&mut Self>, path: &QString, text: &str, encoding: Encoding) -> bool {
        let path = path.to_string();
        match std::fs::write(&path, encode(text, encoding)) {
            Ok(()) => {
                let path = PathBuf::from(path);
                let stamp = Stamp::of(&path);
                self.as_mut().rust_mut().known = Some((path, stamp));
                true
            }
            Err(err) => {
                self.failed(QString::from(cannot("save", &path, &err).as_str()));
                false
            }
        }
    }

    fn startup_path(&self) -> QString {
        cli::ARGS
            .lock()
            .unwrap()
            .path
            .clone()
            .map(command_line_path)
            .and_then(|arg| Some(absolute(&std::env::current_dir().ok()?, arg)))
            .map(|path| QString::from(path.as_str()))
            .unwrap_or_default()
    }

    fn startup_scratchpad(&self) -> bool {
        cli::ARGS.lock().unwrap().scratchpad
    }

    fn take_startup_text(&self) -> QString {
        let text = cli::ARGS.lock().unwrap().text.take();
        QString::from(text.unwrap_or_default().as_str())
    }

    fn print_scratchpad(&self, text: &QString) {
        if cli::ARGS.lock().unwrap().print {
            cli::print_scratchpad(&text.to_string());
        }
    }

    fn startup_line(&self) -> i32 {
        let line = cli::ARGS.lock().unwrap().line;
        line.map_or(-1, |line| i32::try_from(line).unwrap_or(i32::MAX))
    }

    fn startup_commands(&self) -> QString {
        to_json(&cli::ARGS.lock().unwrap().commands)
    }

    fn start_dir(&self, setting: &QString) -> QString {
        QString::from(start_dir(setting.to_string()).as_str())
    }

    fn shown_path(&self, path: &QString) -> QString {
        QString::from(listing::with_tilde(&path.to_string()).as_str())
    }

    fn is_file(&self, path: &QString) -> bool {
        std::path::Path::new(&path.to_string()).is_file()
    }

    fn is_dir(&self, path: &QString) -> bool {
        std::path::Path::new(&path.to_string()).is_dir()
    }

    fn dir_of(&self, path: &QString) -> QString {
        let path = std::path::absolute(path.to_string()).unwrap_or_default();
        let dir = path.parent().unwrap_or(&path);
        path_string(dir)
    }

    fn home_dir(&self) -> QString {
        path_string(&std::env::home_dir().unwrap_or_default())
    }

    fn url_to_path(&self, url: &QUrl) -> QString {
        url.to_local_file().unwrap_or_default()
    }
}

/// Installs the `koil` command for this Koil, or removes it, and returns
/// why it can't, or "" (also if the user cancels the password dialog).
fn change_command(remove: bool) -> String {
    #[cfg(target_os = "macos")]
    {
        let command = Path::new(install::COMMAND);
        let changed = if remove {
            install::remove(command)
        } else {
            this_exe().and_then(|exe| install::install(command, &exe))
        };
        let doing = if remove { "remove" } else { "install" };
        match changed {
            Ok(()) => String::new(),
            Err(err) if err.kind() == io::ErrorKind::Interrupted => String::new(),
            Err(err) => format!("Can't {doing} the koil command: {err}"),
        }
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = remove;
        "Only Koil for macOS installs the koil command".to_string()
    }
}

/// Koil's own binary, as the `koil` command runs it.
#[cfg(target_os = "macos")]
fn this_exe() -> io::Result<std::path::PathBuf> {
    std::env::current_exe().and_then(std::fs::canonicalize)
}

/// Emits `file_opened(path)` on `document`, if it's a Document: what
/// native.cpp's watchFileOpens calls.
///
/// # Safety
///
/// `document` must point to a live QObject.
pub unsafe fn file_opened(document: *mut cxx_qt::QObject, path: &QString) {
    // SAFETY: the caller's.
    if let Some(document) = unsafe { as_document(document) } {
        document.file_opened(path.clone());
    }
}

/// Emits `folder_requested(path, file)` on `document`, if it's a Document:
/// what the macOS service (finder_mac.mm) calls.
///
/// # Safety
///
/// `document` must point to a live QObject.
pub unsafe fn folder_requested(document: *mut cxx_qt::QObject, path: &QString, file: bool) {
    // SAFETY: the caller's.
    if let Some(document) = unsafe { as_document(document) } {
        document.folder_requested(path.clone(), file);
    }
}

/// `object` as a Document, if it's one.
///
/// # Safety
///
/// `object` must point to a live QObject.
unsafe fn as_document<'a>(object: *mut cxx_qt::QObject) -> Option<Pin<&'a mut qobject::Document>> {
    // SAFETY: the caller's.
    unsafe { Pin::new_unchecked(&mut *object) }.downcast_pin::<qobject::Document>()
}

/// How a file's text is stored, so saving it writes it back the same way.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
enum Encoding {
    #[default]
    Utf8,
    /// UTF-8 after a BOM.
    Utf8Bom,
    /// UTF-16 after a BOM, little-endian: what Windows PowerShell 5 writes.
    Utf16Le,
    /// UTF-16 after a BOM, big-endian.
    Utf16Be,
}

impl Encoding {
    /// The bytes a file stored this way starts with.
    fn bom(self) -> &'static [u8] {
        match self {
            Encoding::Utf8 => &[],
            Encoding::Utf8Bom => &[0xef, 0xbb, 0xbf],
            Encoding::Utf16Le => &[0xff, 0xfe],
            Encoding::Utf16Be => &[0xfe, 0xff],
        }
    }

    /// How `bytes` are stored, by the BOM they start with, which is taken
    /// off them.
    fn take(bytes: &mut Vec<u8>) -> Encoding {
        let encoding = [Encoding::Utf8Bom, Encoding::Utf16Le, Encoding::Utf16Be]
            .into_iter()
            .find(|encoding| bytes.starts_with(encoding.bom()))
            .unwrap_or(Encoding::Utf8);
        bytes.drain(..encoding.bom().len());
        encoding
    }

    /// How two bytes make a unit of UTF-16, or None for UTF-8.
    fn unit(self) -> Option<fn([u8; 2]) -> u16> {
        match self {
            Encoding::Utf8 | Encoding::Utf8Bom => None,
            Encoding::Utf16Le => Some(u16::from_le_bytes),
            Encoding::Utf16Be => Some(u16::from_be_bytes),
        }
    }
}

/// The text of the file `path` and how it's stored, or why it can't be
/// read.
fn read(path: &str) -> Result<(String, Encoding), String> {
    let bytes = std::fs::read(path).map_err(|err| cannot("open", path, &err))?;
    decode(bytes).ok_or_else(|| cannot("open", path, &io::ErrorKind::InvalidData.into()))
}

/// The text in `bytes` and how it's stored there: UTF-8, or UTF-16 after a
/// BOM (without one, UTF-16 can't be told from other bytes). None if it's
/// neither, like a picture.
fn decode(mut bytes: Vec<u8>) -> Option<(String, Encoding)> {
    let encoding = Encoding::take(&mut bytes);
    let text = match encoding.unit() {
        None => String::from_utf8(bytes).ok()?,
        // An odd byte at the end is half a unit.
        Some(_) if !bytes.len().is_multiple_of(2) => return None,
        Some(unit) => utf16(&bytes, unit).collect::<Result<_, _>>().ok()?,
    };
    Some((text, encoding))
}

/// The text in `bytes` as `decode` reads it, but with what isn't text as
/// `�` rather than none of it: for text piped in, which is given on purpose,
/// unlike a file, which may be a picture opened by mistake.
pub fn decode_lossy(mut bytes: Vec<u8>) -> String {
    match Encoding::take(&mut bytes).unit() {
        None => String::from_utf8(bytes)
            .unwrap_or_else(|err| String::from_utf8_lossy(err.as_bytes()).into_owned()),
        // An odd byte at the end is half a unit, which is dropped.
        Some(unit) => (utf16(&bytes, unit))
            .map(|c| c.unwrap_or(char::REPLACEMENT_CHARACTER))
            .collect(),
    }
}

/// The characters of `bytes` read as UTF-16, each two of them made a unit
/// by `unit` (an odd one at the end left out).
fn utf16(
    bytes: &[u8],
    unit: fn([u8; 2]) -> u16,
) -> std::char::DecodeUtf16<impl Iterator<Item = u16>> {
    let (units, _) = bytes.as_chunks();
    char::decode_utf16(units.iter().map(move |&pair| unit(pair)))
}

/// `text` stored as `encoding` says, BOM and all.
fn encode(text: &str, encoding: Encoding) -> Vec<u8> {
    let mut bytes = encoding.bom().to_vec();
    match encoding {
        Encoding::Utf8 | Encoding::Utf8Bom => bytes.extend_from_slice(text.as_bytes()),
        Encoding::Utf16Le => bytes.extend(text.encode_utf16().flat_map(u16::to_le_bytes)),
        Encoding::Utf16Be => bytes.extend(text.encode_utf16().flat_map(u16::to_be_bytes)),
    }
    bytes
}

/// Why the file `path` can't be opened or saved (`doing`), as the status
/// line says it: by its name, since the listing (or the title) shows where
/// it is, and a long path would push why out of view.
fn cannot(doing: &str, path: &str, err: &io::Error) -> String {
    let path = Path::new(path);
    let name = path.file_name().map_or_else(
        || listing::show_path(path),
        |name| name.to_string_lossy().into_owned(),
    );
    let why = match err.kind() {
        // What `read` says about a picture, say.
        io::ErrorKind::InvalidData => "it isn't UTF-8 text".to_string(),
        _ => err.to_string(),
    };
    format!("Can't {doing} `{name}`: {why}")
}

/// The path `arg` from the command line stands for. On Windows, Explorer's
/// "Open in Koil" quotes the folder (`"%V"`), and a drive's root, `"C:\"`,
/// comes as `C:"` (`\"` is a quote); a path can't have a quote in it.
fn command_line_path(arg: String) -> String {
    match arg.strip_suffix('"') {
        Some(path) if cfg!(windows) => format!("{path}\\"),
        _ => arg,
    }
}

/// See `Document::start_dir`.
fn start_dir(setting: String) -> String {
    if setting.is_empty() || setting == "~" || setting.starts_with("~/") {
        return setting;
    }
    absolute(&std::env::home_dir().unwrap_or_default(), setting)
}

/// `path` (from the command line, or a setting) made absolute from `dir`
/// (the dir Koil started in, or the home dir), by writing it after that dir
/// and a `/` (`koil_core::with_slashes`), so it keeps a trailing `/` (a
/// pattern's), `..` and `\` as written, which koil reads: on Windows
/// `std::path::absolute` would make every `/` a `\`, and `join` would put a
/// `\` before it, where koil doesn't end a pattern's base dir.
fn absolute(dir: &Path, path: String) -> String {
    let first = Path::new(&path).components().next();
    if matches!(first, Some(Component::Prefix(_) | Component::RootDir)) {
        return path;
    }
    let dir = koil_core::with_slashes(dir).to_string_lossy().into_owned();
    listing::join_shown(dir, &path)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_read() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("photo.jpg");
        std::fs::write(&path, [0xff, 0xd8, 0xff, 0xe0]).unwrap();
        let path = path.to_str().unwrap();
        assert_eq!(
            read(path),
            Err("Can't open `photo.jpg`: it isn't UTF-8 text".to_string())
        );
        std::fs::write(path, "text").unwrap();
        assert_eq!(read(path), Ok(("text".to_string(), Encoding::Utf8)));
    }

    #[test]
    fn test_encodings() {
        let text = "héllo 🍄\r\n";
        for encoding in [
            Encoding::Utf8,
            Encoding::Utf8Bom,
            Encoding::Utf16Le,
            Encoding::Utf16Be,
        ] {
            let bytes = encode(text, encoding);
            assert!(bytes.starts_with(encoding.bom()));
            assert_eq!(decode(bytes), Some((text.to_string(), encoding)));
        }
        assert_eq!(&encode("a", Encoding::Utf16Le), &[0xff, 0xfe, b'a', 0]);
        assert_eq!(&encode("a", Encoding::Utf16Be), &[0xfe, 0xff, 0, b'a']);
        // A BOM with nothing after it.
        assert_eq!(
            decode(vec![0xff, 0xfe]),
            Some((String::new(), Encoding::Utf16Le))
        );
        // UTF-16 without a BOM isn't read as UTF-16.
        assert_eq!(
            decode(vec![b'a', 0]),
            Some(("a\0".to_string(), Encoding::Utf8))
        );
        assert_eq!(decode(vec![0, 0xd8]), None);
        // An odd byte, and a lone surrogate.
        assert_eq!(decode(vec![0xff, 0xfe, b'a', 0, b'b']), None);
        assert_eq!(decode(vec![0xff, 0xfe, 0, 0xd8]), None);
    }

    #[test]
    fn test_decode_lossy() {
        assert_eq!(decode_lossy(b"text".to_vec()), "text");
        assert_eq!(decode_lossy(vec![0xff, 0xfe, b'a', 0]), "a");
        assert_eq!(decode_lossy(vec![b'a', 0xff, b'b']), "a\u{fffd}b");
        // A UTF-8 BOM isn't text, nor is half a UTF-16 unit.
        assert_eq!(
            decode_lossy(vec![0xef, 0xbb, 0xbf, b'a', 0xff]),
            "a\u{fffd}"
        );
        assert_eq!(decode_lossy(vec![0xff, 0xfe, b'a', 0, b'b']), "a");
        assert_eq!(
            decode_lossy(vec![0xfe, 0xff, 0xd8, 0, 0, b'a']),
            "\u{fffd}a"
        );
    }

    #[test]
    fn test_start_dir() {
        let home = std::env::home_dir().unwrap();
        let home = koil_core::with_slashes(&home)
            .to_string_lossy()
            .into_owned();
        for setting in ["", "~", "~/src", "~/src/*.rs", "/tmp"] {
            assert_eq!(start_dir(setting.to_string()), setting);
        }
        assert_eq!(start_dir("src".to_string()), format!("{home}/src"));
        assert_eq!(start_dir("../x".to_string()), format!("{home}/../x"));
        assert_eq!(start_dir("~x".to_string()), format!("{home}/~x"));
    }
}
