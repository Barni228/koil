#pragma once

#include <QtCore/QByteArray>
#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QStringList>

#include <cstdint>

// On macOS, Qt titles the PreferencesRole menu item "Preferences...".
// Rename it to "Settings…" to match current macOS conventions.
void useSettingsMenuTitle();

// Adds the Nerd Font Koil ships (`data`, the font file), the editor's default
// font, and lets the icons in Koil's listing (Nerd Font icons, in a Private
// Use Area) show in fonts that don't have them, like Menlo: it becomes the
// fallback for them. The fallback needs Qt 6.8.
void useNerdFont(const QByteArray& data);

// The family of the font useNerdFont added, as Qt names it.
QString nerdFontFamily();

// The windows' icon, from a PNG file (`png`). On macOS, also the Dock's.
void useWindowIcon(const QByteArray& png);

// Has Cmd+Backspace in every text field (a TextInput) delete back to its
// start, or the selection, as in macOS's own: Qt reads Cmd as Ctrl there,
// and a TextInput's Ctrl+Backspace deletes a word. Nothing elsewhere.
void useLineDeleteKey();

// Keeps a click on a popup window (a Popup.Window: Settings' font and
// shell lists, the Shortcuts window's macros) from the items of the window
// it's in, under it. While one is open, Qt has its window grab the mouse,
// so on Windows that window gets the clicks, and Qt hands each to the
// popup, then to the window if the popup didn't take it. In Qt 6.10
// (Windows'), a popup window never takes a press (QTBUG-141362, fixed in
// 6.11), so an item under a row took the press from it: a click on a
// shell opened the `:h shortcuts` link under the list, and picked nothing.
// Qt 6.11 still passes on a press on a popup's padding.
void keepPopupClicks();

// Has `document` (a Document) emit fileOpened(path) for each file the
// system asks the app to open: what Finder's Open With does on macOS, rather
// than giving the path on the command line (also to an app already running).
void watchFileOpens(QObject* document);

// Has `document` (a Document) emit folderRequested(path, file) for each
// request of "Open in Koil", the macOS service Info.plist declares, which
// macOS shows in Finder for what's selected (its right-click menu's
// Services, and the Services menu), and whose shortcut it handles
// (launching Koil first if it isn't running): with the first file, and
// whether it's a file (or an app, which Finder shows as one) rather than a
// folder. Call it before the app runs, so the request that launched it
// comes. Nothing elsewhere. In finder_mac.mm.
void watchFinderService(QObject* document);

// The service's shortcut as macOS shows it (⌃⇧K): Info.plist's, unless it
// was changed in System Settings. Empty if it has none or is off, or
// outside an app bundle (`cargo run`), or not on macOS.
QString finderServiceShortcut();

// How much is available on the volume `path` is on, in bytes, as Finder
// counts it: with what macOS deletes when it needs the room (purgeable:
// caches, local snapshots), which statfs leaves out. -1 if it can't say,
// or not on macOS. In finder_mac.mm.
std::int64_t importantCapacity(const QString& path);

// Sets the Qt Quick Controls style. Must run before QML is loaded.
void setControlsStyle(const QString& style);

// System clipboard access for the vim "+ and "* registers. Other registers
// never touch the clipboard. Along with the text, Koil can store data of its
// own (the texts hidden behind icons), which only Koil reads.
QString clipboardText();
QString clipboardData();
void setClipboardText(const QString& text, const QString& data);

// Lays out a TextEdit's document as Koil does, in place of Qt's layout
// (see TextLayout in native.cpp), with this grid: every line's rows
// `lineHeight` tall, the text's baseline `baseline` down a row (an emoji,
// from a taller font, doesn't make its line taller), or with a
// `lineHeight` of 0, as tall as the font's lines, and none reaching into
// the `rightMargin`. While lines wrap, a row ends after a space or where a
// word starts or ends (or after a `_`), if one fits, else anywhere; in the
// `listing` (or a list whose lines start with a box and two spaces), not in
// a line's prefix (its icon and two spaces), nor right after it, and the
// rows a line wraps to start under its name. A line longer than
// `longLength` characters is hidden from Qt, a column (a space's width) a
// UTF-16 unit (see the longLine functions). Call it again when any changes:
// the text is laid out again as far as it changes it, at once.
void setLineFormat(QObject* textEdit,
                   double lineHeight,
                   double baseline,
                   double rightMargin,
                   bool listing,
                   int longLength);

// How wide the widest line of a document setLineFormat lays out is,
// unwrapped (not the hidden ones), wrapped or not. Qt gives a TextEdit the
// text's width (QTextDocument::textWidth) as its content's, and the same as
// its implicitWidth, as its idealWidth is QTextDocumentLayout's only: so
// the TextEdit is made this wide while lines don't wrap, and what's sized
// to its text unwrapped is sized to this.
double layoutWidth(QObject* textDocument);

// Sets a TextEdit's text as one edit, and resets what setting its text
// does (the cursor at the start). Setting the text the TextEdit's way
// emptied it first, which changed its width as the scroll bar went, and
// that laid out the new text again.
void setText(QObject* textEdit, const QString& text);

// Call after each change to a TextEdit's text. Over 10,000 characters, a
// TextEdit builds only the lines in view, but Qt decides that only when its
// text is set: a text that grew by edits (a paste of 100,000 lines) had all
// its lines built, which made every key take seconds. This decides it by
// the text's length after an edit too.
void followTextLength(QObject* textEdit);

// Replaces [start, end) of a TextEdit's text with `text`, as its remove and
// insert would, but as one edit: Qt changes the text once, so the text in
// between (all of a long one, less what's removed) isn't made for QML,
// which took seconds for a gigabyte.
void replaceText(QObject* textEdit, int start, int end, const QString& text);

// Call before setting a TextEdit's text. With over 10,000 characters, a
// TextEdit builds only the lines in view, and after a change it builds again
// from where those started, so it skips all of a new text that ends before
// that (a Qt bug: a short listing after the end of a long file showed
// nothing). Then this has it build every line in view from scratch.
void redrawText(QObject* textEdit);

// The length of the longest hidden line (see setLineFormat), or 0 if
// there's none.
int longestLine(QObject* textDocument);

// Where the character at `position` is, if it's in a hidden line: its row
// and its column in the row (a UTF-16 index), as "row column", both from 0.
// Empty if it isn't.
QString longLineSpot(QObject* textDocument, int position);

// The position closest to `column` (a UTF-16 index) in row `row`, if the
// row is a hidden line's, else -1.
int longLinePosition(QObject* textDocument, int row, double column);

// What to draw of the hidden lines in rows `firstRow` to `lastRow`, from
// column `firstColumn` up to `lastColumn` of a row, as JSON: runs of text
// of one format, as { row, column, text, color, underline } (no color for
// the text's own), with a tab as a space.
QString longLineRuns(QObject* textDocument,
                     int firstRow,
                     int lastRow,
                     int firstColumn,
                     int lastColumn);

// Keeps what changes in the text of a TextEdit's document (a
// QQuickTextDocument), for takeTextChange.
void watchTextChanges(QObject* textDocument);

// What changed in the text of a document watchTextChanges watches since
// this was last called, as one change, from, removed and text: the text
// from `from`, `removed` long, became `text` (as toPlainText would give
// it). Empty if nothing changed. So the text needn't be read whole after
// each change (toPlainText took 100 ms for a long one). Without
// `withText`, it's taken but not given, also empty: for a change whose
// text is known (see System::kept_as_is), as making it took seconds for a
// text of a gigabyte.
QStringList takeTextChange(QObject* textDocument, bool withText);

// Stops a TextArea in a ScrollView from scrolling to show its cursor
// rectangle, which is at the line's start in a hidden line (see
// setLineFormat): its QML does it instead.
void scrollToCursorInQml(QObject* textArea);

// Colors Koil's listing in a TextEdit's document (a QQuickTextDocument):
// the icon at a line's start in its color (`iconColors` alternates icons and
// colors), or in `pendingIconColor` on a pending entry's line (see
// setEntryLines), a dir's name (a line ending in "/") in `directoryColor`,
// and the name of a file that can be run in `executableColor`. It follows
// edits. An empty `directoryColor` takes the colors away (a file is open).
void setListingColors(QObject* textDocument,
                      const QStringList& iconColors,
                      const QString& pendingIconColor,
                      const QString& executableColor,
                      const QString& directoryColor);

// Tells setListingColors which lines (numbers, from 0) have an entry that
// applying would change, and which a file that can be run. They move with
// edits, so this follows each one.
void setEntryLines(QObject* textDocument, const QStringList& pendingLines, const QStringList& executableLines);

// Colors the path field's document (a QQuickTextDocument): all of it in
// `directoryColor`, and parts of it (a regex's) over that: `spans` holds a
// start, a length and a color for each part, in that order.
void setPathColors(QObject* textDocument, const QString& directoryColor, const QStringList& spans);

// Colors spans of a TextEdit's document (a QQuickTextDocument), like the
// parts of what K shows: `spans` holds a line (from 0), a start and a
// length in it (in UTF-16) and a color for each span, in that order. It
// colors those lines whatever they are then, not following edits. None
// takes the colors away.
void setSpanColors(QObject* textDocument, const QStringList& spans);

// Colors a file's text in a TextEdit's document (a QQuickTextDocument),
// with what suits any file (see syntax.rs): its strings, numbers, comments,
// paths and URLs, in `colors`, one for each SyntaxKind, in its order (URLs
// are underlined too). `fileName` says which comments it can have. With
// `iconColors` (the scratchpad, where entries are pasted), a line of an
// entry pasted with its ID (see setTextEntryLines) is colored as the
// listing's instead (see setListingColors): its icon, its dirs, and its
// name if it can be run. It follows edits. Neither colors nor icons take
// them away.
void setTextColors(QObject* textDocument,
                   const QStringList& colors,
                   const QString& fileName,
                   const QStringList& iconColors,
                   const QString& directoryColor,
                   const QString& executableColor);

// Tells setTextColors which lines (numbers, from 0) start with an icon
// hiding an entry's ID, and which of those have a file that can be run, as
// setEntryLines tells setListingColors: a line that only starts with a
// listing's icon (an `eza --icons` written in the scratchpad) is a file's.
void setTextEntryLines(QObject* textDocument, const QStringList& entryLines, const QStringList& executableLines);

// The installed font families whose text characters are all the same width,
// in alphabetical order: the fonts the editor offers. It loads every font,
// which takes a moment (a few hundred ms for a few hundred families).
QStringList monospaceFamilies();

// ---- Regular expressions --------------------------------------------------
// What the search, :s, the find bar and the help's search look for: PCRE2's,
// through QRegularExpression, which has what QML's RegExp lacks (a look
// behind, `(?i)`, `a++`, `(?>a)`, `\p{L}`), compiled to machine code, and
// reads the text as it is, UTF-16, so positions are the editor's. `flags`
// has an `i` to ignore case; `^` and `$` are a line's, and `\w`, `\d` and
// `\b` know every script's letters and digits. The compiled
// regular expressions are kept, so the same one can be asked for at every
// key.

// Why `pattern` isn't a regular expression, or empty if it is one.
QString regexError(const QString& pattern, const QString& flags);

// The matches of `pattern` in `text` that start from `from` up to `to`, at
// most `limit`, in order, none overlapping: how many numbers a match takes
// (two for it and two for each group), then for each match where it and
// each of its groups start and end (-1 for a group that took no part).
// The numbers are 32 bits each, as bytes, which QML reads as an Int32Array:
// from a list, reading 800,000 (a :%s over 200,000 lines, with a group)
// took 65 ms, from the array 23.
// Empty if `pattern` isn't valid, and no matches in a text that isn't
// UTF-16 (half a surrogate pair). After a match of nothing, the next is
// looked for a character on. With an `l` in `flags`, only the first that
// starts on each line (:s without g).
QByteArray regexMatches(const QString& text,
                        const QString& pattern,
                        const QString& flags,
                        int from,
                        int to,
                        int limit);

// Where the last match of `pattern` in `text` that starts before `at`
// starts, and where the last one of all does (only looked for if none
// starts before `at`), -1 for none: what a search backwards from `at`
// finds, and where it goes once it wraps.
QList<int> regexBefore(const QString& text, const QString& pattern, const QString& flags, int at);

// The name of each group of `pattern`, in order, the whole match (empty)
// first; empty for one without a name.
QStringList regexGroupNames(const QString& pattern, const QString& flags);
