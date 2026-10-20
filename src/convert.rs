use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use cxx_qt::{CxxQtThread, Threading};
use cxx_qt_lib::{QString, QStringList};
use serde::Serialize;
use serde::de::DeserializeOwned;

/// `value` as JSON, which QML parses.
pub fn to_json(value: &impl Serialize) -> QString {
    QString::from(
        serde_json::to_string(value)
            .expect("always valid JSON")
            .as_str(),
    )
}

/// What QML gave as JSON, or the default if it isn't that.
pub fn from_json<T: DeserializeOwned + Default>(json: &QString) -> T {
    serde_json::from_str(&json.to_string()).unwrap_or_default()
}

/// `path` as QML takes it.
pub fn path_string(path: &Path) -> QString {
    QString::from(path.to_string_lossy().as_ref())
}

/// The paths in a list QML gave.
pub fn paths(list: &QStringList) -> Vec<PathBuf> {
    list.iter().map(|p| PathBuf::from(p.to_string())).collect()
}

/// Emits a signal from a watcher's thread once per burst of changes (a
/// build writing thousands of files), not once each: it isn't queued again
/// until the one on its way is emitted.
pub struct Coalesced<T: Threading + 'static> {
    thread: CxxQtThread<T>,
    queued: Arc<AtomicBool>,
}

impl<T: Threading + 'static> Coalesced<T> {
    pub fn new(thread: CxxQtThread<T>) -> Self {
        Coalesced {
            thread,
            queued: Arc::new(AtomicBool::new(false)),
        }
    }

    pub fn emit(&self, signal: fn(Pin<&mut T>)) {
        if !self.queued.swap(true, Ordering::AcqRel) {
            let queued = self.queued.clone();
            let _ = self.thread.queue(move |object| {
                queued.store(false, Ordering::Release);
                signal(object);
            });
        }
    }
}
