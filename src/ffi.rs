//! The C++ helpers in `cpp/native.cpp`: what Qt offers only to C++.

pub use bridge::*;

#[cxx_qt::bridge]
mod bridge {
    unsafe extern "C++" {
        include!(<QtCore/QObject>);
        type QObject = cxx_qt::QObject;
        include!("cxx-qt-lib/qbytearray.h");
        type QByteArray = cxx_qt_lib::QByteArray;
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qstringlist.h");
        type QStringList = cxx_qt_lib::QStringList;

        include!("native.h");

        /// Titles the macOS app-menu PreferencesRole item "Settings…".
        #[cxx_name = "useSettingsMenuTitle"]
        fn use_settings_menu_title();

        /// Adds the Nerd Font Koil ships (`data`, the font file) and makes it
        /// the fallback for the listing's icons.
        #[cxx_name = "useNerdFont"]
        fn use_nerd_font(data: &QByteArray);

        /// The family of the font `use_nerd_font` added.
        #[cxx_name = "nerdFontFamily"]
        fn nerd_font_family() -> QString;

        /// Sets the Qt Quick Controls style; call it before loading QML.
        #[cxx_name = "setControlsStyle"]
        #[allow(dead_code)] // used on Windows only
        fn set_controls_style(style: &QString);

        /// Reads the system clipboard (vim's "+ and "* registers).
        #[cxx_name = "clipboardText"]
        fn clipboard_text() -> QString;

        /// Reads the Koil-only data stored with the clipboard text.
        #[cxx_name = "clipboardData"]
        fn clipboard_data() -> QString;

        /// Writes the system clipboard, with Koil-only `data` if not empty.
        #[cxx_name = "setClipboardText"]
        fn set_clipboard_text(text: &QString, data: &QString);

        /// Colors Koil's listing in a QQuickTextDocument (see native.h).
        #[cxx_name = "setListingColors"]
        unsafe fn set_listing_colors(
            text_document: *mut QObject,
            icon_colors: &QStringList,
            directory_color: &QString,
        );

        /// Colors the path field's QQuickTextDocument (see native.h).
        #[cxx_name = "setPathColors"]
        unsafe fn set_path_colors(
            text_document: *mut QObject,
            directory_color: &QString,
            spans: &QStringList,
        );

        /// The installed monospaced font families.
        #[cxx_name = "monospaceFamilies"]
        fn monospace_families() -> QStringList;

        /// Gives every line of a QQuickTextDocument the same height, plus a
        /// margin below it.
        #[cxx_name = "setLineFormat"]
        unsafe fn set_line_format(text_document: *mut QObject, height: f64, bottom_margin: f64);
    }
}
