use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;

use cxx_qt_lib::{QString, QStringList};

use crate::ffi;
use crate::listing;

/// What the QML needs from the system, mostly through Qt's C++ side: the
/// clipboard, the installed fonts and the one Koil ships, the editor's line
/// height and the listing's and path field's colors, and showing a path in
/// Finder (or Explorer).
#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qstringlist.h");
        type QStringList = cxx_qt_lib::QStringList;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qobject]
        #[qml_element]
        type System = super::SystemRust;

        #[qinvokable]
        fn clipboard_text(self: &System) -> QString;

        #[qinvokable]
        fn clipboard_data(self: &System) -> QString;

        #[qinvokable]
        fn set_clipboard_text(self: &System, text: &QString, data: &QString);

        /// The installed monospaced font families (the fonts the editor offers).
        #[qinvokable]
        fn monospace_families(self: &System) -> QStringList;

        /// The family of the Nerd Font Koil ships, the editor's default font.
        #[qinvokable]
        fn nerd_font_family(self: &System) -> QString;

        /// Shows `path` in Finder (Explorer on Windows), selected in the dir
        /// it's in (elsewhere, opens that dir), for Space r. Returns why it
        /// can't, or "".
        #[qinvokable]
        fn reveal(self: &System, path: &QString) -> QString;

        /// Gives every line of a TextEdit's `textDocument` the same height,
        /// plus a margin below it.
        #[qinvokable]
        unsafe fn set_line_format(
            self: &System,
            text_document: *mut QObject,
            height: f64,
            bottom_margin: f64,
        );

        /// Sets a TextEdit's text, every line with the format
        /// `set_line_format` gives, laying it out once (see native.h).
        #[qinvokable]
        unsafe fn set_text(
            self: &System,
            text_edit: *mut QObject,
            text: &QString,
            height: f64,
            bottom_margin: f64,
        );

        /// Call after each change to a TextEdit's text: has it build only
        /// the lines in view while the text is long (see native.h).
        #[qinvokable]
        unsafe fn follow_text_length(self: &System, text_edit: *mut QObject);

        /// Call before setting a TextEdit's text: works around a Qt bug that
        /// can leave it blank (see native.h).
        #[qinvokable]
        unsafe fn redraw_text(self: &System, text_edit: *mut QObject);

        /// Colors Koil's listing in a TextEdit's `textDocument`: each icon in
        /// `icon_colors` (icons and colors, alternating), or a pending
        /// entry's in `pending_icon_color`, and dirs in `directory_color`. No
        /// `directory_color` takes the colors away.
        #[qinvokable]
        unsafe fn set_listing_colors(
            self: &System,
            text_document: *mut QObject,
            icon_colors: &QStringList,
            pending_icon_color: &QString,
            directory_color: &QString,
        );

        /// The lines of the listing in `textDocument` (numbers, from 0) whose
        /// entries applying would change, whose icons get the pending color.
        #[qinvokable]
        unsafe fn set_pending_lines(
            self: &System,
            text_document: *mut QObject,
            lines: &QStringList,
        );

        /// Colors the path field's `textDocument`: all of it in
        /// `directory_color`, and parts of it (a regex's) over that: `spans`
        /// holds a start, a length and a color for each part.
        #[qinvokable]
        unsafe fn set_path_colors(
            self: &System,
            text_document: *mut QObject,
            directory_color: &QString,
            spans: &QStringList,
        );

        /// Colors the first word of each line of `textDocument` (after the box
        /// of a line to pick from) if it's a keyword: `keyword_colors`
        /// alternates keywords and their colors. None takes the colors away.
        #[qinvokable]
        unsafe fn set_keyword_colors(
            self: &System,
            text_document: *mut QObject,
            keyword_colors: &QStringList,
        );
    }
}

#[derive(Default)]
pub struct SystemRust;

impl qobject::System {
    fn clipboard_text(&self) -> QString {
        ffi::clipboard_text()
    }

    fn clipboard_data(&self) -> QString {
        ffi::clipboard_data()
    }

    fn set_clipboard_text(&self, text: &QString, data: &QString) {
        ffi::set_clipboard_text(text, data);
    }

    fn monospace_families(&self) -> QStringList {
        ffi::monospace_families()
    }

    fn nerd_font_family(&self) -> QString {
        ffi::nerd_font_family()
    }

    fn reveal(&self, path: &QString) -> QString {
        let path = PathBuf::from(path.to_string());
        let why = if path.symlink_metadata().is_err() {
            format!("“{}” isn't on disk any more", listing::show_path(&path))
        } else if let Err(e) = reveal(&path) {
            format!("Can't show “{}”: {e}", listing::show_path(&path))
        } else {
            String::new()
        };
        QString::from(why.as_str())
    }

    /// # Safety
    ///
    /// `text_document` must be null or point to a live QObject.
    unsafe fn set_line_format(
        &self,
        text_document: *mut qobject::QObject,
        height: f64,
        bottom_margin: f64,
    ) {
        unsafe { ffi::set_line_format(text_document.cast(), height, bottom_margin) };
    }

    /// # Safety
    ///
    /// `text_edit` must be null or point to a live QObject.
    unsafe fn set_text(
        &self,
        text_edit: *mut qobject::QObject,
        text: &QString,
        height: f64,
        bottom_margin: f64,
    ) {
        unsafe { ffi::set_text(text_edit.cast(), text, height, bottom_margin) };
    }

    /// # Safety
    ///
    /// `text_edit` must be null or point to a live QObject.
    unsafe fn follow_text_length(&self, text_edit: *mut qobject::QObject) {
        unsafe { ffi::follow_text_length(text_edit.cast()) };
    }

    /// # Safety
    ///
    /// `text_edit` must be null or point to a live QObject.
    unsafe fn redraw_text(&self, text_edit: *mut qobject::QObject) {
        unsafe { ffi::redraw_text(text_edit.cast()) };
    }

    /// # Safety
    ///
    /// `text_document` must be null or point to a live QObject.
    unsafe fn set_listing_colors(
        &self,
        text_document: *mut qobject::QObject,
        icon_colors: &QStringList,
        pending_icon_color: &QString,
        directory_color: &QString,
    ) {
        unsafe {
            ffi::set_listing_colors(
                text_document.cast(),
                icon_colors,
                pending_icon_color,
                directory_color,
            )
        };
    }

    /// # Safety
    ///
    /// `text_document` must be null or point to a live QObject.
    unsafe fn set_pending_lines(&self, text_document: *mut qobject::QObject, lines: &QStringList) {
        unsafe { ffi::set_pending_lines(text_document.cast(), lines) };
    }

    /// # Safety
    ///
    /// `text_document` must be null or point to a live QObject.
    unsafe fn set_path_colors(
        &self,
        text_document: *mut qobject::QObject,
        directory_color: &QString,
        spans: &QStringList,
    ) {
        unsafe { ffi::set_path_colors(text_document.cast(), directory_color, spans) };
    }

    /// # Safety
    ///
    /// `text_document` must be null or point to a live QObject.
    unsafe fn set_keyword_colors(
        &self,
        text_document: *mut qobject::QObject,
        keyword_colors: &QStringList,
    ) {
        unsafe { ffi::set_keyword_colors(text_document.cast(), keyword_colors) };
    }
}

/// Shows `path` selected in the dir it's in, in Finder or Explorer, or
/// elsewhere opens that dir, without waiting for it.
fn reveal(path: &Path) -> io::Result<()> {
    #[cfg(target_os = "macos")]
    let mut command = {
        let mut command = Command::new("open");
        command.arg("-R").arg(path);
        command
    };
    #[cfg(windows)]
    let mut command = {
        use std::os::windows::process::CommandExt;
        // Explorer reads its command line itself: the path, with `\` only,
        // quoted after the comma (Command would quote all of it).
        let path = path.to_string_lossy().replace('/', "\\");
        let mut command = Command::new("explorer");
        command.raw_arg(format!("/select,\"{path}\""));
        command
    };
    #[cfg(not(any(target_os = "macos", windows)))]
    let mut command = {
        let mut command = Command::new("xdg-open");
        command.arg(path.parent().unwrap_or(path));
        command
    };
    let mut child = command.spawn()?;
    // waited for, so it doesn't stay a zombie once it's done
    thread::spawn(move || child.wait());
    Ok(())
}
