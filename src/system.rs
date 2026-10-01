use cxx_qt_lib::{QString, QStringList};

use crate::ffi;

/// What the QML needs from the system through Qt's C++ side: the clipboard,
/// the installed fonts and the one Koil ships, and the editor's line height
/// and the listing's and path field's colors.
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

        /// Gives every line of a TextEdit's `textDocument` the same height,
        /// plus a margin below it.
        #[qinvokable]
        unsafe fn set_line_format(
            self: &System,
            text_document: *mut QObject,
            height: f64,
            bottom_margin: f64,
        );

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
}
