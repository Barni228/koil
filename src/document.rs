use std::io;
use std::path::{Component, Path};
use std::pin::Pin;

use cxx_qt::casting::{Downcast, Upcast};
use cxx_qt_lib::{QString, QUrl};

use crate::{ffi, listing};

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

        /// Emitted when writing fails, with why.
        #[qsignal]
        fn failed(self: Pin<&mut Document>, message: QString);

        /// Reads the file `path`, and emits `loaded`; or else returns why it
        /// can't (empty if it could).
        #[qinvokable]
        fn open_file(self: Pin<&mut Document>, path: &QString) -> QString;

        /// Has `file_opened` emitted from now on.
        #[qinvokable]
        fn watch_file_opens(self: Pin<&mut Document>);

        #[qinvokable]
        fn save_file(self: Pin<&mut Document>, path: &QString, text: &QString) -> bool;

        /// The path passed on the command line, if any: a file to open, or a
        /// dir (or pattern) for Koil to list. Absolute, from the dir Koil was
        /// started in.
        #[qinvokable]
        fn startup_path(self: &Document) -> QString;

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
}

#[derive(Default)]
pub struct DocumentRust;

impl qobject::Document {
    fn open_file(self: Pin<&mut Self>, path: &QString) -> QString {
        match read(&path.to_string()) {
            Ok(text) => {
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

    fn save_file(self: Pin<&mut Self>, path: &QString, text: &QString) -> bool {
        let path = path.to_string();
        match std::fs::write(&path, text.to_string()) {
            Ok(()) => true,
            Err(err) => {
                self.failed(QString::from(cannot("save", &path, &err).as_str()));
                false
            }
        }
    }

    fn startup_path(&self) -> QString {
        std::env::args()
            .skip(1)
            .find(|arg| !arg.starts_with('-'))
            .and_then(|arg| Some(absolute(&std::env::current_dir().ok()?, arg)))
            .map(|path| QString::from(path.as_str()))
            .unwrap_or_default()
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

/// The text of the file `path`, or why it can't be read.
fn read(path: &str) -> Result<String, String> {
    std::fs::read_to_string(path).map_err(|err| cannot("open", path, &err))
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
        // What read_to_string says about a picture, say.
        io::ErrorKind::InvalidData => "it isn't UTF-8 text".to_string(),
        _ => err.to_string(),
    };
    format!("Can't {doing} `{name}`: {why}")
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
        assert_eq!(read(path), Ok("text".to_string()));
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
