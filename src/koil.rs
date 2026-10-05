use std::path::PathBuf;
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use cxx_qt::{CxxQtThread, CxxQtType, Threading};
use cxx_qt_lib::QString;
use koil_core::{Action, Conflict, Report, Settings, Watched};
use notify::event::ModifyKind;
use notify::{EventKind, RecommendedWatcher, RecursiveMode, Watcher};
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

        /// Emitted when something changed on disk that can change what
        /// `sync` finds (see `watch`), on the GUI thread, soon after.
        #[qsignal]
        fn changed_on_disk(self: Pin<&mut Koil>);

        /// Watches what's open, and the dirs of changes made in other
        /// listings, for `changedOnDisk` (see `koil_core::Koil::watched`).
        /// Call it after anything that may change them.
        #[qinvokable]
        fn watch(self: Pin<&mut Koil>);

        /// Reads what's open from disk again, to follow what changed there,
        /// and returns how the listing `text` (with `hidden`), as the user
        /// has it now, changes to show it, as `listing::Synced`.
        #[qinvokable]
        fn sync(self: Pin<&mut Koil>, text: &QString, hidden: &QString) -> QString;

        /// Takes the other way in `conflicts` (a `listing::Question`'s, as
        /// JSON), and returns how the listing `text` (with `hidden`) changes
        /// for it, as `listing::Merge`.
        #[qinvokable]
        fn resolve(
            self: Pin<&mut Koil>,
            text: &QString,
            hidden: &QString,
            conflicts: &QString,
        ) -> QString;

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

        /// What Tab completes in the path field `line` at `cursor`, as
        /// `listing::Completion`.
        #[qinvokable]
        fn complete(self: &Koil, line: &QString, cursor: i32) -> QString;

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

        /// What applying would do, as a list of `listing::ActionLine`s
        /// (`{ text, needs }`, `text` like `MOVE a -> b`), which `apply`
        /// picks from.
        #[qinvokable]
        fn actions(self: Pin<&mut Koil>) -> QString;

        /// Whether there are changes to apply.
        #[qinvokable]
        fn has_changes(self: &Koil) -> bool;

        /// Applies the changes of the lines `picked` (a list of indexes into
        /// what `actions` gave last), forgetting the others, then reads the
        /// open dir again. Returns `{ ok, message }`.
        #[qinvokable]
        fn apply(self: Pin<&mut Koil>, picked: &QString) -> QString;

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

    impl cxx_qt::Threading for Koil {}
}

#[derive(Default)]
pub struct KoilRust {
    show_hidden: bool,
    gitignore: bool,
    regex: bool,
    koil: koil_core::Koil,
    /// What `actions` showed, which `apply` picks from: what the user saw,
    /// so a change they didn't see is never applied.
    shown: Vec<Action>,
    /// Made on the first `watch`, None if it can't be.
    watcher: Option<DiskWatcher>,
}

/// Watches dirs for changes on disk, and emits `changedOnDisk` for those
/// that matter.
struct DiskWatcher {
    watcher: RecommendedWatcher,
    /// What it watches, as `Watched::dirs`.
    dirs: Vec<(PathBuf, bool)>,
    /// Which changes matter, which the watcher's thread reads.
    watched: Arc<Mutex<Watched>>,
}

impl DiskWatcher {
    fn new(thread: CxxQtThread<qobject::Koil>) -> Option<DiskWatcher> {
        let watched = Arc::new(Mutex::new(Watched::default()));
        // Whether `changedOnDisk` is on its way, so a burst of changes (a
        // build writing thousands of files) sends it once, not once each.
        let queued = Arc::new(AtomicBool::new(false));
        let filter = watched.clone();
        let handler = move |event: notify::Result<notify::Event>| {
            let matters = match event {
                Ok(event) => {
                    let watched = filter.lock().unwrap();
                    changes_listing(&event.kind)
                        && (event.need_rescan() || event.paths.iter().any(|p| watched.affects(p)))
                }
                // Changes may have been missed.
                Err(_) => true,
            };
            if matters && !queued.swap(true, Ordering::AcqRel) {
                let queued = queued.clone();
                let _ = thread.queue(move |koil| {
                    queued.store(false, Ordering::Release);
                    koil.changed_on_disk();
                });
            }
        };
        let watcher = notify::recommended_watcher(handler).ok()?;
        Some(DiskWatcher {
            watcher,
            dirs: Vec::new(),
            watched,
        })
    }

    /// Watches what `watched` says, instead of what it did. A watch is
    /// changed only if the dirs did (on macOS it starts over each time).
    fn set(&mut self, watched: Watched) {
        if watched.dirs != self.dirs {
            for (dir, _) in &self.dirs {
                let _ = self.watcher.unwatch(dir);
            }
            for (dir, recursive) in &watched.dirs {
                let mode = match recursive {
                    true => RecursiveMode::Recursive,
                    false => RecursiveMode::NonRecursive,
                };
                // A dir that isn't there yet (a new one) can't be watched.
                let _ = self.watcher.watch(dir, mode);
            }
            self.dirs = watched.dirs.clone();
        }
        *self.watched.lock().unwrap() = watched;
    }
}

/// Whether an event of `kind` can change a listing: not reading or writing
/// a file.
fn changes_listing(kind: &EventKind) -> bool {
    !matches!(
        kind,
        EventKind::Access(_) | EventKind::Modify(ModifyKind::Data(_) | ModifyKind::Metadata(_))
    )
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
    fn watch(self: Pin<&mut Self>) {
        let thread = self.qt_thread();
        let mut rust = self.rust_mut();
        if rust.watcher.is_none() {
            rust.watcher = DiskWatcher::new(thread);
        }
        let watched = rust.koil.watched();
        if let Some(watcher) = &mut rust.watcher {
            watcher.set(watched);
        }
    }

    fn sync(self: Pin<&mut Self>, text: &QString, hidden: &QString) -> QString {
        let mut rust = self.rust_mut();
        let hidden = read_hidden(hidden);
        to_json(&listing::sync(&mut rust.koil, &text.to_string(), &hidden))
    }

    fn resolve(
        self: Pin<&mut Self>,
        text: &QString,
        hidden: &QString,
        conflicts: &QString,
    ) -> QString {
        let mut rust = self.rust_mut();
        let hidden = read_hidden(hidden);
        let conflicts: Vec<Conflict> =
            serde_json::from_str(&conflicts.to_string()).unwrap_or_default();
        to_json(&listing::resolve(
            &mut rust.koil,
            &text.to_string(),
            &hidden,
            &conflicts,
        ))
    }

    fn open(self: Pin<&mut Self>, location: &QString) -> QString {
        let mut rust = self.rust_mut();
        let settings = rust.settings();
        let koil = &mut rust.koil;
        // This reopens what was open, if anything, which is left right away.
        let _ = koil.set_settings(settings);
        let outcome = match koil.open(location.to_string()) {
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

    fn complete(&self, line: &QString, cursor: i32) -> QString {
        to_json(&listing::complete(
            &self.koil,
            &line.to_string(),
            usize::try_from(cursor).unwrap_or(0),
            &self.settings(),
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

    fn actions(mut self: Pin<&mut Self>) -> QString {
        let lines = listing::actions(&self.koil);
        self.as_mut().rust_mut().shown = lines.iter().map(|l| l.action.clone()).collect();
        to_json(&lines)
    }

    fn has_changes(&self) -> bool {
        !self.koil.compute_actions().is_empty()
    }

    fn apply(self: Pin<&mut Self>, picked: &QString) -> QString {
        let picked: Vec<usize> = serde_json::from_str(&picked.to_string()).unwrap_or_default();
        let mut this = self.rust_mut();
        let actions: Vec<Action> = (picked.iter())
            .filter_map(|&i| this.shown.get(i).cloned())
            .collect();
        let outcome = match this.koil.apply_only(&actions) {
            // As many as the confirmation listed, not Koil's steps (a swap
            // takes three).
            Ok(report) => Outcome {
                ok: true,
                message: report_message(
                    Report {
                        changes: actions.len(),
                        ..report
                    },
                    "applied",
                ),
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
fn report_message(report: Report, done: &str) -> String {
    let changes = match report.changes {
        1 => "1 change".to_string(),
        n => format!("{n} changes"),
    };
    match report.warning {
        Some(warning) => format!("{changes} {done}; {}", listing::describe_warning(&warning)),
        None => format!("{changes} {done}"),
    }
}
