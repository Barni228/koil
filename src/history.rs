//! Koil's undo history (`koil_core::Koil::history`), kept in a file so it
//! lasts across sessions, and shared by every Koil running at once.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::time::SystemTime;
use std::{fs, io};

use koil_core::{Applied, Koil};

/// How many applies are kept, the newest.
pub const KEPT: usize = 100;

/// The file the history is kept in, and the history as it was the last
/// time Koil's and the file's were merged.
pub struct History {
    /// None if there's nowhere to keep it (no home dir).
    path: Option<PathBuf>,
    last: Vec<Applied>,
}

impl Default for History {
    fn default() -> Self {
        History::at(data_dir().map(|dir| dir.join("history.json")))
    }
}

impl History {
    /// The history kept at `path`.
    pub fn at(path: Option<PathBuf>) -> History {
        History {
            path,
            last: Vec::new(),
        }
    }

    /// Brings `koil`'s history and the file's together, both ways: what
    /// another Koil added or undid since the last merge, and what this one
    /// did, keeping the newest `KEPT`.
    pub fn merge(&mut self, koil: &mut Koil) {
        let Some(path) = &self.path else {
            return;
        };
        // One that can't be read is as it was at the last merge: taken for empty, every
        // apply in it would be one another Koil undid, and go.
        let saved = read(path).unwrap_or_else(|| self.last.clone());
        let merged = merge(&saved, koil.history(), &self.last);
        if merged != koil.history() {
            koil.set_history(merged.clone());
        }
        if merged != saved {
            // Kept in memory anyway, and written with the next one.
            let _ = write(path, &merged);
        }
        self.last = merged;
    }

    /// `merge`, if `koil`'s history changed since the last one: a sync can
    /// change it, as the steps follow what's renamed on disk.
    pub fn merge_changed(&mut self, koil: &mut Koil) {
        if koil.history() != self.last {
            self.merge(koil);
        }
    }
}

/// The history `saved` in the file and `ours` (Koil's) together, given
/// `last`, what both were at the last merge (applies are told apart by
/// their time). One that only one of them has is new there if `last`
/// doesn't have it, else the other undid it. One that both have is
/// `ours`, unless only the file's changed since.
pub fn merge(saved: &[Applied], ours: &[Applied], last: &[Applied]) -> Vec<Applied> {
    let by_time = |list: &[Applied]| -> HashMap<SystemTime, Applied> {
        list.iter().map(|a| (a.time, a.clone())).collect()
    };
    let (ours_now, before) = (by_time(ours), by_time(last));
    let saved_times: HashSet<SystemTime> = saved.iter().map(|a| a.time).collect();
    let mut merged: Vec<Applied> = Vec::new();
    for applied in saved {
        match ours_now.get(&applied.time) {
            Some(our) if before.get(&applied.time) == Some(our) => merged.push(applied.clone()),
            Some(our) => merged.push(our.clone()),
            None if !before.contains_key(&applied.time) => merged.push(applied.clone()),
            None => {}
        }
    }
    let new = ours
        .iter()
        .filter(|a| !saved_times.contains(&a.time) && !before.contains_key(&a.time));
    merged.extend(new.cloned());
    merged.sort_by_key(|a| a.time);
    let old = merged.len().saturating_sub(KEPT);
    merged.drain(..old);
    merged
}

/// What `path` has: nothing if it isn't there, None if it can't be read.
fn read(path: &Path) -> Option<Vec<Applied>> {
    match fs::read_to_string(path) {
        Ok(text) => serde_json::from_str(&text).ok(),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Some(Vec::new()),
        Err(_) => None,
    }
}

/// Writes `history` to `path` all at once (through a file next to it, this
/// Koil's own, as two writing one could put the other's half written in
/// place), so another Koil never reads it half written.
fn write(path: &Path, history: &[Applied]) -> io::Result<()> {
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir)?;
    }
    let temp = path.with_extension(format!("json.{}.new", std::process::id()));
    fs::write(&temp, serde_json::to_string(history)?)?;
    fs::rename(&temp, path)
}

/// Where Koil keeps its data: `~/Library/Application Support/Koil` on
/// macOS, `%APPDATA%\Koil` on Windows, else `$XDG_DATA_HOME/koil` or
/// `~/.local/share/koil`.
fn data_dir() -> Option<PathBuf> {
    if cfg!(target_os = "macos") {
        let home = std::env::home_dir()?;
        Some(home.join("Library/Application Support/Koil"))
    } else if cfg!(windows) {
        let app_data = std::env::var_os("APPDATA")?;
        Some(PathBuf::from(app_data).join("Koil"))
    } else {
        let xdg = std::env::var_os("XDG_DATA_HOME").map(PathBuf::from);
        let data = match xdg.filter(|dir| dir.is_absolute()) {
            Some(dir) => dir,
            None => std::env::home_dir()?.join(".local/share"),
        };
        Some(data.join("koil"))
    }
}

#[cfg(test)]
mod tests;
