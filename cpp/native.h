#pragma once

#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QStringList>

// On macOS, Qt titles the PreferencesRole menu item "Preferences...".
// Rename it to "Settings…" to match current macOS conventions.
void useSettingsMenuTitle();

// Lets the icons in Koil's listing (Nerd Font icons, in a Private Use Area)
// show in fonts that don't have them, like Menlo: an installed Nerd Font
// becomes the fallback for them. Does nothing before Qt 6.8, or with no Nerd
// Font installed.
void useIconFallbackFont();

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

// Colors Koil's listing in a TextEdit's document (a QQuickTextDocument):
// the icon at a line's start in its color (`iconColors` alternates icons and
// colors), the path on the first line and a dir's name (a line ending in
// "/") in `directoryColor`, and the line of "=" in `ruleColor`. It follows
// edits. An empty `directoryColor` takes the colors away (a file is open).
void setListingColors(QObject* textDocument,
                      const QStringList& iconColors,
                      const QString& directoryColor,
                      const QString& ruleColor);

// Colors parts of the path on the listing's first line (a regex's) over the
// colors setListingColors gives it: `spans` holds a start, a length and a
// color for each part, in that order.
void setPathColors(QObject* textDocument, const QStringList& spans);

// The installed font families whose text characters are all the same width,
// in alphabetical order: the fonts the editor offers. It loads every font,
// which takes a moment (a few hundred ms for a few hundred families).
QStringList monospaceFamilies();
