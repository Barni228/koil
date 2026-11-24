#pragma once

#include <QtCore/QObject>
#include <QtCore/QString>

// The web version's helpers (see docs/platform.md, Web): what only the
// browser's JavaScript can do. Built for the web alone (build.rs).

// Whether the browser runs on a Mac, where Koil acts as the Mac app does:
// Qt for the web hands Cmd as Ctrl there too (and Ctrl as Meta).
bool webOnMac();

// Gives the page Koil's colors, now and as they change (CSS variables and
// `data-theme` on its root), for the page to draw the windows' frames
// (Qt's own, in the page's HTML) in them, and its background.
void useWebPage();

// While `on`, has Qt's color scheme follow the browser's light or dark
// mode, now and as it changes. Qt for the web reads neither (its scheme
// is Unknown), and then gives windows a light palette but text areas a
// dark one.
void followBrowserColorScheme(bool on);

// Saves the home dir to the browser's storage (IndexedDB) a moment from
// now, once Koil wrote it (web/pre.js mounts it, and saves it).
void saveWebDisk();

// Opens the browser's picker of files, or of a folder (with `folder`),
// which puts what's picked in the dir `staging` (each file, or the folder
// with the files in it, as the browser has their paths), then calls
// webFilesPicked(document, why it couldn't, or ""). The browser opens it
// only right after the user's key or click, which Koil's commands are.
void pickWebFiles(QObject* document, const QString& staging, bool folder);

// Has the browser download the file `path` as `name`, deleting it once it's
// read if `remove`.
void downloadWebFile(const QString& path, const QString& name, bool remove);

// Has the browser read its clipboard (which it may ask the user first),
// then emits clipboardRead(text, error) on `system`: the text, or why it
// couldn't. Qt for the web learns of the clipboard only from the browser's
// paste (Cmd+V), so "+p would have what was copied before that.
void readWebClipboard(QObject* system);

// Emits storageFailed(why) on `system` when Koil's files can't be kept in
// the browser's storage: a save failed, or they couldn't be read as Koil
// started (then nothing is saved, see web/pre.js), which is said at once
// if it happened already.
void watchWebStorage(QObject* system);

// Has the page take the files and folders dropped on it, which browsers
// give Qt no paths of: each goes in the dir `staging` (a folder with
// what's in it), then filesDropped(why it couldn't, or "") is emitted on
// `document`. webDragChanged(on) is emitted as a drag of files comes over
// the page, and leaves it.
void watchWebDrops(QObject* document, const QString& staging);
