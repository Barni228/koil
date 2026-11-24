//! What only the web version does with files (see docs/files.md, Web
//! files): the welcome file of a first visit (`first_visit`), bringing in
//! what the browser's picker gave (`import`), and the `.zip` of a folder
//! to download (`zip_dir`). The browser's side (the picker, downloads,
//! saving the disk to the browser's storage) is web.cpp's. Built
//! everywhere, so the tests run on desktop.

use std::fs;
use std::io::{self, Seek, Write};
use std::path::{Path, PathBuf};

/// Where the picker puts what's picked, before `import` moves it into place:
/// in the browser's memory, not in its storage.
pub const STAGING: &str = "/tmp/koil-import";

/// What a first visit opens (see `first_visit`).
const WELCOME: &str = "\
Koil in your browser

Edit with vim, as in the desktop app. Files stay in this browser.
File > Import File… / Import Folder… brings in files from your computer.
File > Export… downloads a file, or a folder as a .zip.
";

/// On the first visit (nothing in `home` says Koil ran there before),
/// writes the welcome file there (`welcome.txt`, unless there's one) and
/// returns it, for Koil to open as if it were on the command line. None
/// after, or if it can't.
pub fn first_visit(home: &Path) -> Option<PathBuf> {
    let visited = home.join(".local/share/koil/visited");
    if visited.symlink_metadata().is_ok() {
        return None;
    }
    fs::create_dir_all(visited.parent()?).ok()?;
    fs::write(&visited, "").ok()?;
    let welcome = home.join("welcome.txt");
    if welcome.symlink_metadata().is_err() {
        fs::write(&welcome, WELCOME).ok()?;
    }
    disk_changed();
    Some(welcome)
}

/// Tells the web version that Koil wrote its disk, which it saves to the
/// browser's storage a moment after (web.cpp's `saveWebDisk`). Nothing on
/// desktop, whose disk is the disk.
pub fn disk_changed() {
    #[cfg(target_os = "emscripten")]
    crate::ffi::save_web_disk();
}

/// Brings what the picker put in `staging` (each file picked, or the folder,
/// with what's in it) into `dir`, and empties `staging`. One whose name is
/// taken in `dir` gets another (see `free_name`): an import never replaces
/// anything. Returns the paths made in `dir`, in the order of their names.
pub fn import(staging: &Path, dir: &Path) -> io::Result<Vec<PathBuf>> {
    // Nothing picked, or a folder with no files, which the browser gives
    // none of.
    if !staging.exists() {
        return Ok(Vec::new());
    }
    let mut names: Vec<_> = fs::read_dir(staging)?
        .map(|entry| entry.map(|e| e.file_name()))
        .collect::<io::Result<_>>()?;
    names.sort();
    let mut made = Vec::new();
    for name in names {
        let to = free_name(dir, &name.to_string_lossy());
        copy_tree(&staging.join(&name), &to)?;
        made.push(to);
    }
    fs::remove_dir_all(staging)?;
    disk_changed();
    Ok(made)
}

/// `name` in `dir`, or if that's taken, the first of `name (2)`, `name (3)`…
/// that isn't, before the extension of a file's name (`notes (2).txt`), as
/// browsers name a download whose name is taken.
fn free_name(dir: &Path, name: &str) -> PathBuf {
    let taken = |path: &Path| path.symlink_metadata().is_ok();
    let path = dir.join(name);
    if !taken(&path) {
        return path;
    }
    // A dot that starts the name (`.env`) is no extension's.
    let (stem, extension) = match name.rfind('.') {
        Some(dot) if dot > 0 => name.split_at(dot),
        _ => (name, ""),
    };
    (2..)
        .map(|n| dir.join(format!("{stem} ({n}){extension}")))
        .find(|path| !taken(path))
        .expect("some number is free")
}

/// Copies the file or dir `from` to `to`, with what's in it: across the
/// browser's file systems, which `fs::rename` can't move between.
fn copy_tree(from: &Path, to: &Path) -> io::Result<()> {
    if from.symlink_metadata()?.is_dir() {
        fs::create_dir(to)?;
        for entry in fs::read_dir(from)? {
            let entry = entry?;
            copy_tree(&entry.path(), &to.join(entry.file_name()))?;
        }
        Ok(())
    } else {
        fs::copy(from, to).map(drop)
    }
}

/// Writes a `.zip` of the dir `dir` to `out`: everything in it (hidden
/// entries too) but the paths `left_out`, under `name`, as a folder's zip
/// unpacks into a folder of its name, each with the time it was modified.
/// A link is followed to a file, and left out if it's to a dir, which could
/// be one it's in.
pub fn zip_dir(
    dir: &Path,
    name: &str,
    left_out: &[PathBuf],
    out: impl Write + Seek,
) -> io::Result<()> {
    use zip::write::SimpleFileOptions;

    let mut zip = zip::ZipWriter::new(out);
    let in_zip = |path: &Path| {
        let inside = zip_name(path.strip_prefix(dir).unwrap_or(path));
        if inside.is_empty() {
            name.to_string()
        } else {
            format!("{name}/{inside}")
        }
    };
    let mut dirs = vec![dir.to_path_buf()];
    while let Some(at) = dirs.pop() {
        let options = SimpleFileOptions::default().last_modified_time(zip_time(&at));
        zip.add_directory(in_zip(&at), options)
            .map_err(io::Error::other)?;
        let mut entries: Vec<_> = fs::read_dir(&at)?.collect::<io::Result<_>>()?;
        entries.sort_by_key(|entry| entry.file_name());
        for entry in entries {
            let path = entry.path();
            let is_link = entry.file_type()?.is_symlink();
            let Ok(meta) = fs::metadata(&path) else {
                continue;
            };
            if left_out.contains(&path) {
                continue;
            }
            if meta.is_dir() {
                if !is_link {
                    dirs.push(path);
                }
                continue;
            }
            let options = SimpleFileOptions::default().last_modified_time(zip_time(&path));
            zip.start_file(in_zip(&path), options)
                .map_err(io::Error::other)?;
            io::copy(&mut fs::File::open(&path)?, &mut zip)?;
        }
    }
    zip.finish().map_err(io::Error::other)?;
    Ok(())
}

/// When `path` was last modified, in the local time zone, as a zip keeps
/// it (or 1980, its first, if that can't be told).
fn zip_time(path: &Path) -> zip::DateTime {
    use chrono::{Datelike, Timelike};

    let time = fs::metadata(path).and_then(|meta| meta.modified()).ok();
    time.map(crate::listing::local_time)
        .and_then(|t| {
            let (month, day) = (t.month() as u8, t.day() as u8);
            let (hour, minute, second) = (t.hour() as u8, t.minute() as u8, t.second() as u8);
            let year = u16::try_from(t.year()).ok()?;
            zip::DateTime::from_date_and_time(year, month, day, hour, minute, second).ok()
        })
        .unwrap_or_default()
}

/// Downloads `path` (from `dir`, if relative; `~` at its start is the home
/// dir): a file as it is, a dir as a `.zip` of it, made in `/tmp` and
/// deleted once read. Returns why it can't.
pub fn export(dir: &Path, path: &str) -> Result<(), String> {
    let home = std::env::home_dir().unwrap_or_default();
    let path = match path.strip_prefix('~') {
        Some(rest) if rest.is_empty() || rest.starts_with('/') => {
            home.join(rest.trim_start_matches('/'))
        }
        _ => dir.join(path),
    };
    let shown = crate::listing::show_path(&path);
    let cannot = |why: io::Error| format!("Can't export “{shown}”: {why}");
    // Without `..` and `.`, whose names a download can't have.
    let path = dunce::canonicalize(&path).map_err(cannot)?;
    let name = match path.file_name() {
        _ if path == home => "home".to_string(),
        Some(name) => name.to_string_lossy().into_owned(),
        None => "files".to_string(),
    };
    if !path.is_dir() {
        download(&path, &name, false);
        return Ok(());
    }
    // Koil's own: its undo history (and `visited`), and the trash.
    let data = home.join(".local/share");
    let left_out = [data.join("koil"), data.join("Trash")];
    let zip = std::env::temp_dir().join(format!("{name}.zip"));
    let file = fs::File::create(&zip).map_err(cannot)?;
    zip_dir(&path, &name, &left_out, io::BufWriter::new(file)).map_err(cannot)?;
    download(&zip, &format!("{name}.zip"), true);
    Ok(())
}

/// Has the browser download the file `path` as `name`, deleting it once it's
/// read if `remove` (web.cpp's `downloadWebFile`). Nothing on desktop.
fn download(path: &Path, name: &str, remove: bool) {
    #[cfg(target_os = "emscripten")]
    crate::ffi::download_web_file(
        &crate::convert::path_string(path),
        &cxx_qt_lib::QString::from(name),
        remove,
    );
    #[cfg(not(target_os = "emscripten"))]
    let _ = (path, name, remove);
}

/// A path in a zip: its parts joined with `/`, as zips have them.
fn zip_name(path: &Path) -> String {
    let parts: Vec<_> = path.iter().map(|part| part.to_string_lossy()).collect();
    parts.join("/")
}

#[cfg(test)]
mod tests;
