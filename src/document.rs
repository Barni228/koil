use std::io;
use std::path::{Component, Path};
use std::pin::Pin;

use cxx_qt::casting::{Downcast, Upcast};
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QString, QUrl};

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
        /// `watch_finder_service` was called: the macOS service, with the
        /// folder selected in Finder (the first, if there are several).
        #[qsignal]
        fn folder_requested(self: Pin<&mut Document>, path: QString);

        /// Emitted when writing fails, with why.
        #[qsignal]
        fn failed(self: Pin<&mut Document>, message: QString);

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

        /// The line `+N` on the command line puts the cursor on: 0 for the
        /// last one, -1 for none.
        #[qinvokable]
        fn startup_line(self: &Document) -> i32;

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
}

impl qobject::Document {
    fn open_file(mut self: Pin<&mut Self>, path: &QString) -> QString {
        match read(&path.to_string()) {
            Ok((text, encoding)) => {
                self.as_mut().rust_mut().encoding = encoding;
                self.loaded(path.clone(), QString::from(text.as_str()));
                QString::default()
            }
            Err(message) => QString::from(message.as_str()),
        }
    }

    fn watch_file_opens(self: Pin<&mut Self>) {
        // SAFETY: the pointer is to this Document, a live QObject, which
        // fileOpened is emitted on (it's in its meta-object).
        unsafe {
            let object: &mut cxx_qt::QObject = Pin::into_inner_unchecked(self.upcast_pin());
            ffi::watch_file_opens(object);
        }
    }

    fn watch_finder_service(self: Pin<&mut Self>) {
        // SAFETY: the pointer is to this Document, a live QObject, which
        // folderRequested is emitted on (it's in its meta-object).
        unsafe {
            let object: &mut cxx_qt::QObject = Pin::into_inner_unchecked(self.upcast_pin());
            ffi::watch_finder_service(object);
        }
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
        self.write(path, text, encoding)
    }

    fn save_new_file(self: Pin<&mut Self>, path: &QString, text: &QString) -> bool {
        self.write(path, text, Encoding::Utf8)
    }

    /// Writes `text` to the file `path`, stored as `encoding` says; or else
    /// emits `failed`.
    fn write(self: Pin<&mut Self>, path: &QString, text: &QString, encoding: Encoding) -> bool {
        let path = path.to_string();
        match std::fs::write(&path, encode(&text.to_string(), encoding)) {
            Ok(()) => true,
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

    fn startup_line(&self) -> i32 {
        let line = cli::ARGS.lock().unwrap().line;
        line.map_or(-1, |line| i32::try_from(line).unwrap_or(i32::MAX))
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

    fn dir_of(&self, path: &QString) -> QString {
        let path = std::path::absolute(path.to_string()).unwrap_or_default();
        let dir = path.parent().unwrap_or(&path);
        QString::from(dir.to_string_lossy().as_ref())
    }

    fn home_dir(&self) -> QString {
        let home = std::env::home_dir().unwrap_or_default();
        QString::from(home.to_string_lossy().as_ref())
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
    let document = unsafe { Pin::new_unchecked(&mut *document) };
    if let Some(document) = document.downcast_pin::<qobject::Document>() {
        document.file_opened(path.clone());
    }
}

/// Emits `folder_requested(path)` on `document`, if it's a Document: what
/// the macOS service (finder_mac.mm) calls.
///
/// # Safety
///
/// `document` must point to a live QObject.
pub unsafe fn folder_requested(document: *mut cxx_qt::QObject, path: &QString) {
    // SAFETY: the caller's.
    let document = unsafe { Pin::new_unchecked(&mut *document) };
    if let Some(document) = document.downcast_pin::<qobject::Document>() {
        document.folder_requested(path.clone());
    }
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
    let encoding = [Encoding::Utf8Bom, Encoding::Utf16Le, Encoding::Utf16Be]
        .into_iter()
        .find(|encoding| bytes.starts_with(encoding.bom()))
        .unwrap_or(Encoding::Utf8);
    bytes.drain(..encoding.bom().len());
    let text = match encoding {
        Encoding::Utf8 | Encoding::Utf8Bom => String::from_utf8(bytes).ok()?,
        Encoding::Utf16Le => utf16(&bytes, u16::from_le_bytes)?,
        Encoding::Utf16Be => utf16(&bytes, u16::from_be_bytes)?,
    };
    Some((text, encoding))
}

/// The text in `bytes` as `decode` reads it, but with what isn't text as
/// `�` rather than none of it: for text piped in, which is given on purpose,
/// unlike a file, which may be a picture opened by mistake.
pub fn decode_lossy(mut bytes: Vec<u8>) -> String {
    let unit: fn([u8; 2]) -> u16 = if bytes.starts_with(Encoding::Utf16Le.bom()) {
        u16::from_le_bytes
    } else if bytes.starts_with(Encoding::Utf16Be.bom()) {
        u16::from_be_bytes
    } else {
        if bytes.starts_with(Encoding::Utf8Bom.bom()) {
            bytes.drain(..Encoding::Utf8Bom.bom().len());
        }
        return String::from_utf8(bytes)
            .unwrap_or_else(|err| String::from_utf8_lossy(err.as_bytes()).into_owned());
    };
    // An odd byte at the end is half a unit, which is dropped.
    let (units, _) = bytes[2..].as_chunks();
    char::decode_utf16(units.iter().map(|&pair| unit(pair)))
        .map(|c| c.unwrap_or(char::REPLACEMENT_CHARACTER))
        .collect()
}

/// `bytes` read as UTF-16, each two of them made a unit by `unit`; None if
/// they aren't UTF-16.
fn utf16(bytes: &[u8], unit: fn([u8; 2]) -> u16) -> Option<String> {
    let (units, rest) = bytes.as_chunks();
    if !rest.is_empty() {
        return None;
    }
    char::decode_utf16(units.iter().map(|&pair| unit(pair)))
        .collect::<Result<_, _>>()
        .ok()
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
