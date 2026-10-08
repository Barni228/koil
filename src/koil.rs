use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use cxx_qt::{CxxQtThread, CxxQtType, Threading};
use cxx_qt_lib::QString;
use koil_core::{Action, Applied, Conflict, Id, KoilError, Report, Settings, Sort, Watched};
use notify::event::ModifyKind;
use notify::{EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use serde::Serialize;
use serde_json::json;

use crate::history::History;
use crate::listing::{self, Hidden, Notes};
use crate::sizes::{Measure, Sizes};

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
        #[qproperty(QString, sort)]
        #[qproperty(bool, sort_reverse)]
        type Koil = super::KoilRust;

        /// Emitted when something changed on disk that can change what
        /// `sync` finds (see `watch`), on the GUI thread, soon after.
        #[qsignal]
        fn changed_on_disk(self: Pin<&mut Koil>);

        /// Watches what's open, and the dirs of changes made in other
        /// listings, for `changedOnDisk` (see `koil_core::Koil::watched`),
        /// and the dirs whose sizes are kept (see `Sizes::watches`). Call
        /// it after anything that may change them.
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

        /// The listing of what's open: `{ path, text, hidden, names, colors,
        /// infos, busy }` (see `listing::Rendered`). Counts the sizes of its
        /// dirs, when it's sorted by size (see `dirSizes`).
        #[qinvokable]
        fn render(self: Pin<&mut Koil>) -> QString;

        /// What's shown after the lines of the dirs whose sizes are being
        /// counted, as far as they are, and which still are: `{ infos, busy
        /// }` (see `listing::Notes`), for the dirs of the last `render` or
        /// `sync`.
        #[qinvokable]
        fn dir_sizes(self: &Koil) -> QString;

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
        /// (`{ text, needs, deletes }`, `text` like `MOVE a -> b`), which
        /// `apply` picks from.
        #[qinvokable]
        fn actions(self: Pin<&mut Koil>) -> QString;

        /// Whether there are changes to apply.
        #[qinvokable]
        fn has_changes(self: &Koil) -> bool;

        /// Applies the changes of the lines `picked` (a list of indexes into
        /// what `actions` gave last), forgetting the others (all of them, if
        /// none is picked), then reads the open dir again. Returns `{ ok,
        /// message }`.
        #[qinvokable]
        fn apply(self: Pin<&mut Koil>, picked: &QString) -> QString;

        /// What creating the new file at `path` before the other changes
        /// are applied takes (see `listing::create_steps`): `{ steps,
        /// message }`, where `message` says why it can't be, and then
        /// `steps` is empty.
        #[qinvokable]
        fn create_steps(self: &Koil, path: &QString) -> QString;

        /// Creates the new file at `path` now, with the new dirs it's in,
        /// keeping the other changes, then reads the open dir again (see
        /// `listing::create_now`). Returns `{ ok, message }`.
        #[qinvokable]
        fn create(self: Pin<&mut Koil>, path: &QString) -> QString;

        /// The applies that can be undone, newest first, as a list of
        /// `listing::HistoryLine`s (`{ text, needs, blocked }`), which `undo`
        /// picks from: `{ applies, message }`, where `message` says why
        /// nothing can be undone now. They're those of every session (see
        /// history.rs).
        #[qinvokable]
        fn history(self: Pin<&mut Koil>) -> QString;

        /// Undoes the applies `picked` (a list of indexes into what `history`
        /// gave last), newest first, then reads the open dir again. Returns
        /// `{ ok, message }`.
        #[qinvokable]
        fn undo(self: Pin<&mut Koil>, picked: &QString) -> QString;
    }

    impl cxx_qt::Threading for Koil {}
}

#[derive(Default)]
pub struct KoilRust {
    show_hidden: bool,
    gitignore: bool,
    regex: bool,
    /// What the listing is sorted by, as `koil_core::SortBy` names it (like
    /// "size"), and whether the other way round.
    sort: QString,
    sort_reverse: bool,
    koil: koil_core::Koil,
    /// What `actions` showed, which `apply` picks from: what the user saw,
    /// so a change they didn't see is never applied.
    shown: Vec<Action>,
    /// The undo history kept across sessions, and what `history` showed of
    /// it, which `undo` picks from.
    history: History,
    shown_history: Vec<Applied>,
    /// Made on the first `watch`, None if it can't be.
    watcher: Option<DiskWatcher>,
    /// Counts the sizes of the dirs listed, when it's sorted by size, and
    /// keeps them, and the IDs of the dirs listed.
    sizes: Sizes,
    sized: Vec<Id>,
}

/// Watches dirs for changes on disk, and emits `changedOnDisk` for those
/// that matter, and tells `Sizes` what changed.
struct DiskWatcher {
    watcher: RecommendedWatcher,
    /// What it's asked to watch, and whether what's inside its dirs too,
    /// and those it couldn't.
    dirs: BTreeMap<PathBuf, bool>,
    failed: BTreeSet<PathBuf>,
    /// Which changes matter, which the watcher's thread reads.
    watched: Arc<Mutex<Watched>>,
    /// Whether writing a file matters too: the listing shows its size or
    /// when it changed (see `listing::info`).
    writes: Arc<AtomicBool>,
}

impl DiskWatcher {
    fn new(thread: CxxQtThread<qobject::Koil>, sizes: Sizes) -> Option<DiskWatcher> {
        let watched = Arc::new(Mutex::new(Watched::default()));
        let writes = Arc::new(AtomicBool::new(false));
        // Whether `changedOnDisk` is on its way, so a burst of changes (a
        // build writing thousands of files) sends it once, not once each.
        let queued = Arc::new(AtomicBool::new(false));
        let (filter, with_writes) = (watched.clone(), writes.clone());
        let handler = move |event: notify::Result<notify::Event>| {
            match &event {
                // Reading changes no size.
                Ok(event) if matches!(event.kind, EventKind::Access(_)) => {}
                Ok(event) if event.paths.is_empty() && event.need_rescan() => sizes.forget(),
                // What changed in them wasn't told.
                Ok(event) if event.need_rescan() => {
                    for path in &event.paths {
                        sizes.lost(path);
                    }
                }
                Ok(event) => {
                    for path in &event.paths {
                        sizes.changed(path);
                    }
                }
                Err(_) => sizes.forget(),
            }
            let matters = match event {
                Ok(event) => {
                    let watched = filter.lock().unwrap();
                    changes_listing(&event.kind, with_writes.load(Ordering::Relaxed))
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
            dirs: BTreeMap::new(),
            failed: BTreeSet::new(),
            watched,
            writes,
        })
    }

    /// Watches what `watched` says, and `sizes` with what's inside them,
    /// instead of what it did, and with `writes`, files being written too.
    /// Returns the dirs of `sizes` it can't watch. The watches are changed
    /// only if the dirs did, and only those that did, at once (on macOS
    /// it starts over each time), trying again those it couldn't watch.
    fn set(&mut self, watched: Watched, writes: bool, sizes: &[PathBuf]) -> Vec<PathBuf> {
        self.writes.store(writes, Ordering::Relaxed);
        let mut dirs: BTreeMap<PathBuf, bool> = watched.dirs.iter().cloned().collect();
        dirs.extend(sizes.iter().map(|dir| (dir.clone(), true)));
        *self.watched.lock().unwrap() = watched;
        if dirs == self.dirs {
            return Vec::new();
        }
        let mut paths = self.watcher.paths_mut();
        for (dir, recursive) in &self.dirs {
            if dirs.get(dir) != Some(recursive) && !self.failed.contains(dir) {
                let _ = paths.remove(dir);
            }
        }
        let mut failed = BTreeSet::new();
        for (dir, &recursive) in &dirs {
            if self.dirs.get(dir) == Some(&recursive) && !self.failed.contains(dir) {
                continue;
            }
            let mode = match recursive {
                true => RecursiveMode::Recursive,
                false => RecursiveMode::NonRecursive,
            };
            // A dir that isn't there yet (a new one) can't be watched.
            if paths.add(dir, mode).is_err() {
                failed.insert(dir.clone());
            }
        }
        let _ = paths.commit();
        self.dirs = dirs;
        self.failed = failed;
        (sizes.iter())
            .filter(|dir| self.failed.contains(*dir))
            .cloned()
            .collect()
    }
}

/// What to watch for the sizes kept in `dirs` (see `Sizes::watches`): the
/// dirs, but on Windows the roots of their drives, as a dir that has one
/// watched in it can't be renamed or deleted there, and the user may want
/// to, long after leaving it.
fn size_watches(dirs: Vec<PathBuf>) -> Vec<PathBuf> {
    #[cfg(windows)]
    {
        let roots = dirs.iter().filter_map(|dir| dir.ancestors().last());
        let roots: BTreeSet<PathBuf> = roots.map(|root| root.to_path_buf()).collect();
        roots.into_iter().collect()
    }
    #[cfg(not(windows))]
    dirs
}

/// Whether an event of `kind` can change a listing: not reading a file, nor
/// writing one, unless `writes` (the listing shows its size or when it
/// changed).
fn changes_listing(kind: &EventKind, writes: bool) -> bool {
    match kind {
        EventKind::Access(_) => false,
        EventKind::Modify(ModifyKind::Data(_) | ModifyKind::Metadata(_)) => writes,
        _ => true,
    }
}

impl KoilRust {
    /// Counts the sizes of the dirs `notes` show them for (those that
    /// aren't known or kept), and stops counting every other one. Those it
    /// starts are in `notes` as they are after the moment it waits for
    /// them (see `Sizes::want`).
    fn count_sizes(&mut self, notes: &mut Notes) {
        self.sized = notes.dirs.iter().map(|&(id, _)| id).collect();
        let dirs = notes.dirs.iter().map(|(_, dir)| dir.clone());
        if !self.sizes.want(dirs, self.measure()) {
            return;
        }
        let sizes = self.sizes.known(self.measure());
        let now = listing::notes(&self.koil, &sizes, self.sized.iter().copied());
        for id in &self.sized {
            notes.infos.remove(&id.0.to_string());
        }
        notes.infos.extend(now.infos);
        notes.busy = now.busy;
    }

    /// What dirs' sizes are measured by, when the listing is sorted by them
    /// (only then are they asked for).
    fn measure(&self) -> Measure {
        listing::measure(self.koil.settings().sort.by).unwrap_or_default()
    }

    fn settings(&self) -> Settings {
        let by = serde_json::Value::String(self.sort.to_string());
        Settings {
            show_hidden: self.show_hidden,
            respect_gitignore: self.gitignore,
            regex: self.regex,
            sort: Sort {
                by: serde_json::from_value(by).unwrap_or_default(),
                reverse: self.sort_reverse,
            },
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
        let rust = &mut *rust;
        if rust.watcher.is_none() {
            rust.watcher = DiskWatcher::new(thread, rust.sizes.clone());
        }
        let watched = rust.koil.watched();
        let writes = rust.koil.settings().sort.by.reads_metadata();
        let sizes = size_watches(rust.sizes.watches());
        if let Some(watcher) = &mut rust.watcher {
            for dir in watcher.set(watched, writes, &sizes) {
                rust.sizes.unwatched(&dir);
            }
        }
    }

    fn sync(self: Pin<&mut Self>, text: &QString, hidden: &QString) -> QString {
        let mut rust = self.rust_mut();
        let rust = &mut *rust;
        let hidden = read_hidden(hidden);
        let sizes = rust.sizes.known(rust.measure());
        let mut synced = listing::sync(&mut rust.koil, &sizes, &text.to_string(), &hidden);
        // Moved, the listing is rendered again.
        if !synced.failed && !synced.moved {
            rust.count_sizes(&mut synced.notes);
        }
        // The undo steps follow what was renamed on disk.
        rust.history.merge_changed(&mut rust.koil);
        to_json(&synced)
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
        let rust = &mut *rust;
        let sizes = rust.sizes.known(rust.measure());
        to_json(&listing::resolve(
            &mut rust.koil,
            &sizes,
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

    fn render(self: Pin<&mut Self>) -> QString {
        let mut rust = self.rust_mut();
        // Before it's sorted by them, so the small ones are known.
        let dirs = listing::size_dirs(&rust.koil);
        rust.sizes.want(dirs, rust.measure());
        let sizes = rust.sizes.known(rust.measure());
        let mut rendered = listing::render(&rust.koil, &sizes);
        rust.count_sizes(&mut rendered.notes);
        to_json(&rendered)
    }

    fn dir_sizes(&self) -> QString {
        let sized = self.sized.iter().copied();
        let sizes = self.sizes.known(self.measure());
        to_json(&listing::notes(&self.koil, &sizes, sized))
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
        let this = &mut *this;
        let actions: Vec<Action> = (picked.iter())
            .filter_map(|&i| this.shown.get(i).cloned())
            .collect();
        let shown = this.shown.len();
        let outcome = match this.koil.apply_only(&actions) {
            // Nothing picked: every change is forgotten.
            Ok(report) if actions.is_empty() => Outcome {
                ok: true,
                message: report_message(
                    Report {
                        changes: shown,
                        ..report
                    },
                    "discarded",
                ),
            },
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
        // The sizes kept that it changed, before the watcher tells.
        for action in &actions {
            for path in action.removes().into_iter().chain(action.creates()) {
                this.sizes.changed(path);
            }
        }
        this.history.merge(&mut this.koil);
        to_json(&outcome)
    }

    fn create_steps(&self, path: &QString) -> QString {
        let path = PathBuf::from(path.to_string());
        let value = match listing::create_steps(&self.koil, &path) {
            Ok(steps) => json!({ "steps": steps, "message": "" }),
            Err(message) => json!({ "steps": [], "message": message }),
        };
        to_json(&value)
    }

    fn create(self: Pin<&mut Self>, path: &QString) -> QString {
        let path = PathBuf::from(path.to_string());
        let mut rust = self.rust_mut();
        let rust = &mut *rust;
        let outcome = match listing::create_now(&mut rust.koil, &path) {
            Ok(message) => Outcome { ok: true, message },
            Err(message) => Outcome { ok: false, message },
        };
        // With the new dirs it's in.
        rust.sizes.changed(&path);
        rust.history.merge(&mut rust.koil);
        to_json(&outcome)
    }

    fn history(self: Pin<&mut Self>) -> QString {
        let mut rust = self.rust_mut();
        let rust = &mut *rust;
        // With what other Koils applied or undid.
        rust.history.merge(&mut rust.koil);
        let value = match listing::history(&rust.koil) {
            Ok(lines) => {
                rust.shown_history = lines.iter().map(|l| l.applied.clone()).collect();
                json!({ "applies": lines, "message": "" })
            }
            Err(message) => json!({ "applies": [], "message": message }),
        };
        to_json(&value)
    }

    fn undo(self: Pin<&mut Self>, picked: &QString) -> QString {
        let picked: Vec<usize> = serde_json::from_str(&picked.to_string()).unwrap_or_default();
        let mut rust = self.rust_mut();
        let rust = &mut *rust;
        let applies: Vec<Applied> = (picked.iter())
            .filter_map(|&i| rust.shown_history.get(i).cloned())
            .collect();
        // Those another Koil undid since aren't undone again.
        rust.history.merge(&mut rust.koil);
        let outcome = match rust.koil.undo_only(&applies) {
            Ok(report) => Outcome {
                ok: true,
                message: report_message(report, "undone"),
            },
            Err(KoilError::UndoBlocked { blocked, .. }) => Outcome {
                ok: false,
                message: format!(
                    "Can't undo: {}",
                    listing::describe_blocked(rust.koil.current_dir(), &blocked)
                ),
            },
            Err(error) => Outcome {
                ok: false,
                message: listing::describe(&error),
            },
        };
        // The sizes kept that it changed, before the watcher tells.
        for step in applies.iter().flat_map(|applied| &applied.steps) {
            for path in step.paths() {
                rust.sizes.changed(path);
            }
        }
        rust.history.merge(&mut rust.koil);
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
