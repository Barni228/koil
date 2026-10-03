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

// Has `document` (a Document) emit fileOpened(path) for each file the
// system asks the app to open: what Finder's Open With does on macOS, rather
// than giving the path on the command line (also to an app already running).
void watchFileOpens(QObject* document);

// Sets the Qt Quick Controls style. Must run before QML is loaded.
void setControlsStyle(const QString& style);

// System clipboard access for the vim "+ and "* registers. Other registers
// never touch the clipboard. Along with the text, Koil can store data of its
// own (the texts hidden behind icons), which only Koil reads.
QString clipboardText();
QString clipboardData();
void setClipboardText(const QString& text, const QString& data);

// Gives every line of a TextEdit's document (a QQuickTextDocument) the same
// height, so a line with an emoji (from a taller font) doesn't grow. New
// lines inherit it, but setting the TextEdit's text resets it. The bottom
// margin adds to each line's height; Qt puts a fixed-height line's baseline
// at 4/5 of it, and the margin lets the text sit higher in the whole line.
void setLineFormat(QObject* textDocument, double height, double bottomMargin);

// Sets a TextEdit's text, with the line format setLineFormat gives, as one
// edit, and resets what setting its text does (the cursor at the start).
// Qt lays out all of a text for each change to it or its format, and
// setting the text and then the format laid out 100,000 lines twice (a
// second each).
void setText(QObject* textEdit, const QString& text, double height, double bottomMargin);

// Call after each change to a TextEdit's text. Over 10,000 characters, a
// TextEdit builds only the lines in view, but Qt decides that only when its
// text is set: a text that grew by edits (a paste of 100,000 lines) had all
// its lines built, which made every key take seconds. This decides it by
// the text's length after an edit too.
void followTextLength(QObject* textEdit);

// Call before setting a TextEdit's text. With over 10,000 characters, a
// TextEdit builds only the lines in view, and after a change it builds again
// from where those started, so it skips all of a new text that ends before
// that (a Qt bug: a short listing after the end of a long file showed
// nothing). Then this has it build every line in view from scratch.
void redrawText(QObject* textEdit);

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

// The installed font families whose text characters are all the same width,
// in alphabetical order: the fonts the editor offers. It loads every font,
// which takes a moment (a few hundred ms for a few hundred families).
QStringList monospaceFamilies();
