use std::pin::Pin;

use cxx_qt::CxxQtType;
use cxx_qt_lib::QString;
use koil_core::Settings;
use serde::Serialize;
use serde_json::json;

use crate::listing::{self, Hidden};

/// Koil itself (koil-core): the dir or pattern that's open, the changes
/// written in its listings so far, and applying and undoing them. Takes and
/// gives the listing as the editor shows it (see listing.rs), with anything
/// structured as JSON.
#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(bool, show_hidden)]
        #[qproperty(bool, gitignore)]
        #[qproperty(bool, regex)]
        type Koil = super::KoilRust;

        /// Opens `location`, a dir or a pattern (see `Koil::open`), dropping
        /// the listing shown so far (see `update` for keeping it). Returns
        /// `{ ok, message }`.
        #[qinvokable]
        fn open(self: Pin<&mut Koil>, location: &QString) -> QString;

        /// The listing of what's open: `{ path, text, hidden, names, colors }`
        /// (see `listing::Rendered`).
        #[qinvokable]
        fn render(self: &Koil) -> QString;

        /// The parts of the regex in the path field `line` to color, as a
        /// list of `listing::Span`: none unless it's read as a regex.
        #[qinvokable]
        fn path_syntax(self: &Koil, line: &QString) -> QString;

        /// The warnings and errors in the listing `text`, whose icons hide
        /// `hidden` (JSON, as vim keeps it), as a list of `listing::Problem`.
        #[qinvokable]
        fn check(self: &Koil, text: &QString, hidden: &QString) -> QString;

        /// Reads the listing `text` (with `hidden`), uses the settings, and
        /// opens `open` (relative to the open dir) if it isn't empty, else
        /// `path` (the path field) if it changed. Returns `listing::Updated`.
        #[qinvokable]
        fn update(
            self: Pin<&mut Koil>,
            path: &QString,
            text: &QString,
            hidden: &QString,
            open: &QString,
        ) -> QString;

        /// The lines of the listing `text` (with `hidden`) whose entries
        /// applying would change (see `listing::pending_lines`), as a list.
        #[qinvokable]
        fn pending_lines(self: &Koil, text: &QString, hidden: &QString) -> QString;

        /// What Enter on `line` (from 0) opens, as `listing::Target` (like
        /// `{ "dir": "src" }`), or null.
        #[qinvokable]
        fn target_on_line(self: &Koil, text: &QString, hidden: &QString, line: i32) -> QString;

        /// The path the ID `id` (an icon's hidden text) stands for (see
        /// `listing::id_path`), or "" if koil doesn't know it.
        #[qinvokable]
        fn id_path(self: &Koil, id: &QString) -> QString;

        /// What applying would do, as a list of lines like `MOVE a -> b`.
        #[qinvokable]
        fn actions(self: &Koil) -> QString;

        /// Whether there are changes to apply.
        #[qinvokable]
        fn has_changes(self: &Koil) -> bool;

        /// Applies the changes, then reads the open dir again. Returns
        /// `{ ok, message }`.
        #[qinvokable]
        fn apply(self: Pin<&mut Koil>) -> QString;

        /// What undoing the last apply would do: `{ steps, message }`, where
        /// `steps` is empty if there's nothing to undo, and `message` says why
        /// it can't be undone now.
        #[qinvokable]
        fn undo_steps(self: &Koil) -> QString;

        /// Undoes the last apply, then reads the open dir again. Returns
        /// `{ ok, message }`.
        #[qinvokable]
        fn undo(self: Pin<&mut Koil>) -> QString;
    }
}

#[derive(Default)]
pub struct KoilRust {
    show_hidden: bool,
    gitignore: bool,
    regex: bool,
    koil: koil_core::Koil,
}

impl KoilRust {
    fn settings(&self) -> Settings {
        Settings {
            show_hidden: self.show_hidden,
            respect_gitignore: self.gitignore,
            regex: self.regex,
        }
    }
}

/// What `open`, `apply` and `undo` did.
#[derive(Serialize)]
struct Outcome {
    ok: bool,
    message: String,
}

fn to_json(value: &impl Serialize) -> QString {
    QString::from(
        serde_json::to_string(value)
            .expect("always valid JSON")
            .as_str(),
    )
}

fn read_hidden(hidden: &QString) -> Vec<Hidden> {
    serde_json::from_str(&hidden.to_string()).unwrap_or_default()
}

impl qobject::Koil {
    fn open(self: Pin<&mut Self>, location: &QString) -> QString {
        let mut rust = self.rust_mut();
        let settings = rust.settings();
        let koil = &mut rust.koil;
        // This reopens what was open, if anything, which is left right away.
        let _ = koil.set_settings(settings);
        let outcome = match koil.open(listing::expand_home(&location.to_string())) {
            Ok(()) => Outcome {
                ok: true,
                message: String::new(),
            },
            Err(error) => Outcome {
                ok: false,
                message: listing::describe_open(&error),
            },
        };
        to_json(&outcome)
    }

    fn render(&self) -> QString {
        to_json(&listing::render(&self.koil))
    }

    fn path_syntax(&self, line: &QString) -> QString {
        to_json(&listing::path_syntax(
            &self.koil,
            &line.to_string(),
            self.regex,
        ))
    }

    fn check(&self, text: &QString, hidden: &QString) -> QString {
        to_json(&listing::check(
            &self.koil,
            &text.to_string(),
            &read_hidden(hidden),
        ))
    }

    fn update(
        self: Pin<&mut Self>,
        path: &QString,
        text: &QString,
        hidden: &QString,
        open: &QString,
    ) -> QString {
        let mut rust = self.rust_mut();
        let settings = rust.settings();
        let open = open.to_string();
        let open = (!open.is_empty()).then_some(open.as_str());
        let hidden = read_hidden(hidden);
        to_json(&listing::update(
            &mut rust.koil,
            &path.to_string(),
            &text.to_string(),
            &hidden,
            &settings,
            open,
        ))
    }

    fn pending_lines(&self, text: &QString, hidden: &QString) -> QString {
        to_json(&listing::pending_lines(
            &self.koil,
            &text.to_string(),
            &read_hidden(hidden),
        ))
    }

    fn target_on_line(&self, text: &QString, hidden: &QString, line: i32) -> QString {
        let target = usize::try_from(line).ok().and_then(|line| {
            listing::target_on_line(&self.koil, &text.to_string(), &read_hidden(hidden), line)
        });
        to_json(&target)
    }

    fn id_path(&self, id: &QString) -> QString {
        let path = listing::id_path(&self.koil, &id.to_string());
        QString::from(path.unwrap_or_default().as_str())
    }

    fn actions(&self) -> QString {
        to_json(&listing::actions(&self.koil))
    }

    fn has_changes(&self) -> bool {
        !self.koil.compute_actions().is_empty()
    }

    fn apply(self: Pin<&mut Self>) -> QString {
        let outcome = match self.rust_mut().koil.apply() {
            Ok(report) => Outcome {
                ok: true,
                message: report_message(report, "applied"),
            },
            Err(error) => Outcome {
                ok: false,
                message: listing::describe(&error),
            },
        };
        to_json(&outcome)
    }

    fn undo_steps(&self) -> QString {
        let value = match listing::undo_steps(&self.koil) {
            Ok(steps) => json!({ "steps": steps, "message": "" }),
            Err(message) => json!({ "steps": [], "message": message }),
        };
        to_json(&value)
    }

    fn undo(self: Pin<&mut Self>) -> QString {
        let outcome = match self.rust_mut().koil.undo() {
            Ok(report) => Outcome {
                ok: true,
                message: report_message(report, "undone"),
            },
            Err(error) => Outcome {
                ok: false,
                message: listing::describe(&error),
            },
        };
        to_json(&outcome)
    }
}

/// Like "3 changes applied", and a warning if there is one.
fn report_message(report: koil_core::Report, done: &str) -> String {
    let changes = match report.changes {
        1 => "1 change".to_string(),
        n => format!("{n} changes"),
    };
    match report.warning {
        Some(warning) => format!("{changes} {done}; {warning}"),
        None => format!("{changes} {done}"),
    }
}
