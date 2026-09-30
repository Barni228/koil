use std::pin::Pin;

use cxx_qt_lib::{QString, QUrl};

/// The icons that hide text in the editor (`Vim.icons` in qml/Vim.qml).
const MUSHROOM: &str = "🍄";
const CHAIR: &str = "🪑";

/// What the editor shows and saves: the listing it starts with, and files.
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

        /// The lines the editor starts with, as a JSON array of
        /// `{ icon, hidden, text }`: the line shows `icon`, which hides
        /// `hidden`, then `text`.
        #[qinvokable]
        fn listing(self: &Document) -> QString;

        #[qinvokable]
        fn open_file(self: Pin<&mut Document>, path: &QString);

        #[qinvokable]
        fn save_file(self: Pin<&mut Document>, path: &QString, text: &QString) -> bool;

        /// The path passed on the command line, if any.
        #[qinvokable]
        fn startup_file(self: &Document) -> QString;

        #[qinvokable]
        fn url_to_path(self: &Document, url: &QUrl) -> QString;
    }
}

#[derive(Default)]
pub struct DocumentRust;

impl qobject::Document {
    // A sample until Koil lists a directory here.
    fn listing(&self) -> QString {
        let lines = serde_json::json!([
            { "icon": MUSHROOM, "hidden": "Poppy", "text": "some other text" },
            { "icon": MUSHROOM, "hidden": "Other one", "text": "maybe-dir/" },
            { "icon": CHAIR, "hidden": "what", "text": "this" },
        ]);
        QString::from(lines.to_string().as_str())
    }

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

    fn startup_file(&self) -> QString {
        std::env::args()
            .skip(1)
            .find(|arg| !arg.starts_with('-'))
            .map(|arg| QString::from(arg.as_str()))
            .unwrap_or_default()
    }

    fn url_to_path(&self, url: &QUrl) -> QString {
        url.to_local_file().unwrap_or_default()
    }
}
