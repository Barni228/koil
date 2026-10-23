#pragma once

#include <QtCore/QByteArray>
#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QStringList>

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
// setPendingLines), and a dir's name (a line ending in "/") in
// `directoryColor`. It follows edits. An empty `directoryColor` takes the
// colors away (a file is open).
void setListingColors(QObject* textDocument,
                      const QStringList& iconColors,
                      const QString& pendingIconColor,
                      const QString& directoryColor);

// Tells setListingColors which lines (numbers, from 0) have an entry that
// applying would change. They move with edits, so this follows each one.
void setPendingLines(QObject* textDocument, const QStringList& lines);

// Colors the path field's document (a QQuickTextDocument): all of it in
// `directoryColor`, and parts of it (a regex's) over that: `spans` holds a
// start, a length and a color for each part, in that order.
void setPathColors(QObject* textDocument, const QString& directoryColor, const QStringList& spans);

// Colors the first word of each line of a TextEdit's document (a
// QQuickTextDocument), after the box before a line to pick from (a Private
// Use Area character) if there is one, if it's one of the keywords
// (`keywordColors` alternates keywords and colors), like the CREATE that
// starts a line of the changes to apply. It follows edits. None takes the
// colors away.
void setKeywordColors(QObject* textDocument, const QStringList& keywordColors);

// Colors a file's text in a TextEdit's document (a QQuickTextDocument),
// with what suits any file (see syntax.rs): its strings, numbers, comments,
// paths and URLs, in `colors`, one for each SyntaxKind, in its order (URLs
// are underlined too). `fileName` says which comments it can have. It
// follows edits. No colors take them away.
void setTextColors(QObject* textDocument, const QStringList& colors, const QString& fileName);

// The installed font families whose text characters are all the same width,
// in alphabetical order: the fonts the editor offers. It loads every font,
// which takes a moment (a few hundred ms for a few hundred families).
QStringList monospaceFamilies();
