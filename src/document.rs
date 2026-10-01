use std::pin::Pin;

use cxx_qt_lib::{QString, QUrl};

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

        /// Emitted when reading or writing fails.
        #[qsignal]
        fn failed(self: Pin<&mut Document>, message: QString);

        #[qinvokable]
        fn open_file(self: Pin<&mut Document>, path: &QString);

        #[qinvokable]
        fn save_file(self: Pin<&mut Document>, path: &QString, text: &QString) -> bool;

        /// The path passed on the command line, if any: a file to open, or a
        /// dir (or pattern) for Koil to list. Absolute, from the dir Koil was
        /// started in.
        #[qinvokable]
        fn startup_path(self: &Document) -> QString;

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

        /// The home dir, which Koil lists when no path is given.
        #[qinvokable]
        fn home_dir(self: &Document) -> QString;

        #[qinvokable]
        fn url_to_path(self: &Document, url: &QUrl) -> QString;
    }
}

#[derive(Default)]
pub struct DocumentRust;

impl qobject::Document {
    fn open_file(self: Pin<&mut Self>, path: &QString) {
        match std::fs::read_to_string(path.to_string()) {
            Ok(text) => self.loaded(path.clone(), QString::from(text.as_str())),
            Err(err) => self.failed(QString::from(
                format!("Could not open {path}: {err}").as_str(),
            )),
        }
    }

    fn save_file(self: Pin<&mut Self>, path: &QString, text: &QString) -> bool {
        match std::fs::write(path.to_string(), text.to_string()) {
            Ok(()) => true,
            Err(err) => {
                self.failed(QString::from(
                    format!("Could not save {path}: {err}").as_str(),
                ));
                false
            }
        }
    }

    fn startup_path(&self) -> QString {
        std::env::args()
            .skip(1)
            .find(|arg| !arg.starts_with('-'))
            // Keeps a trailing `/` (a pattern's) and `..`, which koil reads.
            .and_then(|arg| std::path::absolute(arg).ok())
            .map(|path| QString::from(path.to_string_lossy().as_ref()))
            .unwrap_or_default()
    }

    fn shown_path(&self, path: &QString) -> QString {
        let path = std::path::PathBuf::from(path.to_string());
        QString::from(crate::listing::show_path(&path).as_str())
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
