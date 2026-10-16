//! The C++ helpers in `cpp/native.cpp`: what Qt offers only to C++.

pub use bridge::*;

use cxx_qt_lib::QString;

use crate::document::{file_opened, folder_requested};
use crate::syntax;

#[cxx_qt::bridge]
mod bridge {
    /// What a part of a file's line is (see `syntax::Kind`), in the order
    /// of the colors `setTextColors` takes.
    enum SyntaxKind {
        String,
        Escape,
        Number,
        Comment,
        Path,
        Url,
    }

    /// A part of a line to color, from `start`, `length` UTF-16 units long.
    struct SyntaxSpan {
        start: i32,
        length: i32,
        kind: SyntaxKind,
    }

    /// Which comments a file can have (see `syntax::Comments`).
    struct SyntaxComments {
        hash: bool,
        slashes: bool,
    }

    extern "Rust" {
        /// Emits `fileOpened(path)` on `document`, a Document (see
        /// `watch_file_opens`).
        #[cxx_name = "fileOpened"]
        unsafe fn file_opened(document: *mut QObject, path: &QString);

        /// Emits `folderRequested(path, file)` on `document`, a Document
        /// (see `watch_finder_service`).
        #[cxx_name = "folderRequested"]
        unsafe fn folder_requested(document: *mut QObject, path: &QString, file: bool);

        /// The comments the file `file_name` can have (see
        /// `syntax::Comments::of`).
        #[cxx_name = "syntaxComments"]
        fn syntax_comments(file_name: &QString) -> SyntaxComments;

        /// Puts the parts of a file's `line` to color in `spans` (see
        /// `syntax::spans`), apart (`syntax::apart`), for a line that
        /// starts in `state`, and gives the state it ends in
        /// (QSyntaxHighlighter's block states).
        #[cxx_name = "syntaxSpans"]
        fn syntax_spans(
            line: &[u16],
            state: i32,
            comments: SyntaxComments,
            spans: &mut Vec<SyntaxSpan>,
        ) -> i32;
    }

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

        /// Sets the windows' icon from a PNG file (`png`).
        #[cxx_name = "useWindowIcon"]
        #[allow(dead_code)] // not used on Windows
        fn use_window_icon(png: &QByteArray);

        /// Has `document`, a Document, emit `fileOpened(path)` for each file
        /// the system asks the app to open (macOS's Open With; see native.h).
        #[cxx_name = "watchFileOpens"]
        unsafe fn watch_file_opens(document: *mut QObject);

        /// Has `document`, a Document, emit `folderRequested` for each
        /// request of the macOS service "Open in Koil" (see native.h).
        #[cxx_name = "watchFinderService"]
        unsafe fn watch_finder_service(document: *mut QObject);

        /// The macOS service's shortcut as macOS shows it, or empty (see
        /// native.h).
        #[cxx_name = "finderServiceShortcut"]
        fn finder_service_shortcut() -> QString;

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
            pending_icon_color: &QString,
            directory_color: &QString,
        );

        /// The listing's lines whose entries are pending (see native.h).
        #[cxx_name = "setPendingLines"]
        unsafe fn set_pending_lines(text_document: *mut QObject, lines: &QStringList);

        /// Colors the path field's QQuickTextDocument (see native.h).
        #[cxx_name = "setPathColors"]
        unsafe fn set_path_colors(
            text_document: *mut QObject,
            directory_color: &QString,
            spans: &QStringList,
        );

        /// Colors the keywords that start the lines of a QQuickTextDocument
        /// (see native.h).
        #[cxx_name = "setKeywordColors"]
        unsafe fn set_keyword_colors(text_document: *mut QObject, keyword_colors: &QStringList);

        /// Colors a file's QQuickTextDocument (see native.h).
        #[cxx_name = "setTextColors"]
        unsafe fn set_text_colors(
            text_document: *mut QObject,
            colors: &QStringList,
            file_name: &QString,
        );

        /// The installed monospaced font families.
        #[cxx_name = "monospaceFamilies"]
        fn monospace_families() -> QStringList;

        /// Gives every line of a QQuickTextDocument the same height, plus a
        /// margin below it, and the rows a wrapped line goes on to an indent
        /// and a margin on their right.
        #[cxx_name = "setLineFormat"]
        unsafe fn set_line_format(
            text_document: *mut QObject,
            height: f64,
            bottom_margin: f64,
            indent: f64,
            right_margin: f64,
        );

        /// Sets a TextEdit's text with that line format, as one edit (see
        /// native.h).
        #[cxx_name = "setText"]
        unsafe fn set_text(
            text_edit: *mut QObject,
            text: &QString,
            height: f64,
            bottom_margin: f64,
            indent: f64,
            right_margin: f64,
        );

        /// Has a TextEdit build only the lines in view while its text is
        /// long, after an edit too (see native.h).
        #[cxx_name = "followTextLength"]
        unsafe fn follow_text_length(text_edit: *mut QObject);

        /// Replaces part of a TextEdit's text, as one edit (see native.h).
        #[cxx_name = "replaceText"]
        unsafe fn replace_text(text_edit: *mut QObject, start: i32, end: i32, text: &QString);

        /// Has a TextEdit build the lines in view from scratch, around a Qt
        /// bug; call it before setting its text (see native.h).
        #[cxx_name = "redrawText"]
        unsafe fn redraw_text(text_edit: *mut QObject);

        /// Hides a QQuickTextDocument's lines longer than `long_length`
        /// from Qt, as they're edited (see native.h).
        #[cxx_name = "watchLongLines"]
        unsafe fn watch_long_lines(text_document: *mut QObject, long_length: i32);

        /// Places the hidden lines on the line grid (see native.h).
        #[cxx_name = "placeLongLines"]
        unsafe fn place_long_lines(
            text_document: *mut QObject,
            line_height: f64,
            bottom_margin: f64,
            row_length: i32,
        );

        /// The longest hidden line's length, or 0 (see native.h).
        #[cxx_name = "longestLine"]
        unsafe fn longest_line(text_document: *mut QObject) -> i32;

        /// The row and column of a position in a hidden line (see
        /// native.h).
        #[cxx_name = "longLineSpot"]
        unsafe fn long_line_spot(text_document: *mut QObject, position: i32) -> QString;

        /// The position at a row and column of a hidden line, or -1 (see
        /// native.h).
        #[cxx_name = "longLinePosition"]
        unsafe fn long_line_position(text_document: *mut QObject, row: i32, column: f64) -> i32;

        /// What to draw of the hidden lines in view, as JSON (see
        /// native.h).
        #[cxx_name = "longLineRuns"]
        unsafe fn long_line_runs(
            text_document: *mut QObject,
            first_row: i32,
            last_row: i32,
            first_column: i32,
            last_column: i32,
        ) -> QString;

        /// Keeps what changes in a QQuickTextDocument's text (see
        /// native.h).
        #[cxx_name = "watchTextChanges"]
        unsafe fn watch_text_changes(text_document: *mut QObject);

        /// What changed in the text since it was last asked, as from,
        /// removed and text, or nothing (see native.h).
        #[cxx_name = "takeTextChange"]
        unsafe fn take_text_change(text_document: *mut QObject, with_text: bool) -> QStringList;

        /// Has a TextEdit build all its lines in view again (see
        /// native.h).
        #[cxx_name = "rebuildTextNodes"]
        unsafe fn rebuild_text_nodes(text_edit: *mut QObject);

        /// Has a TextArea's QML scroll to its cursor rather than Qt (see
        /// native.h).
        #[cxx_name = "scrollToCursorInQml"]
        unsafe fn scroll_to_cursor_in_qml(text_area: *mut QObject);
    }
}

fn syntax_comments(file_name: &QString) -> SyntaxComments {
    let comments = syntax::Comments::of(&String::from(file_name));
    SyntaxComments {
        hash: comments.hash,
        slashes: comments.slashes,
    }
}

fn syntax_spans(
    line: &[u16],
    state: i32,
    comments: SyntaxComments,
    spans: &mut Vec<SyntaxSpan>,
) -> i32 {
    let comments = syntax::Comments {
        hash: comments.hash,
        slashes: comments.slashes,
    };
    let (found, state) = syntax::spans(line, syntax::State::from_number(state), comments);
    spans.extend(syntax::apart(&found).iter().map(|span| SyntaxSpan {
        // A line is at most syntax::MAX_LENGTH long.
        start: span.start as i32,
        length: (span.end - span.start) as i32,
        kind: match span.kind {
            syntax::Kind::String => SyntaxKind::String,
            syntax::Kind::Escape => SyntaxKind::Escape,
            syntax::Kind::Number => SyntaxKind::Number,
            syntax::Kind::Comment => SyntaxKind::Comment,
            syntax::Kind::Path => SyntaxKind::Path,
            syntax::Kind::Url => SyntaxKind::Url,
        },
    }));
    state.number()
}
