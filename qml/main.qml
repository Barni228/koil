pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import Qt.labs.platform as Platform

import Koil

import "text.js" as Txt

// The app's window: the editor and its status line, Koil's listing and the
// path field over it, the find bar, the dialogs, the menus and the settings.
ApplicationWindow {
    id: root

    readonly property bool isMac: Qt.platform.os === "osx"
    property string filePath: ""
    readonly property string fileName: filePath ? filePath.split(/[\\/]/).pop() : "Untitled"
    // Whether the editor shows Koil's listing of `location`, rather than a
    // file.
    property bool listing: false
    property string location: ""
    // Koil's warnings and errors about the listing, and about the path
    // field (see Editor.problems).
    property var problems: []
    property var pathProblems: []
    // The editor vim edits: the listing's (or the file's), or the path
    // field (see activate).
    property Editor activeView: editorView
    // The colors of the icons the listings have shown, and of a pending
    // entry's, and the lines of the pending ones (see Editor.iconColors).
    property var iconColors: ({})
    property var pendingIconColor: ["", ""]
    property var pendingLines: []
    // The parts of the regex in the path field (see Editor.pathSyntax), and
    // the path they're for.
    property var pathSyntax: []
    property string pathLine: ""
    // Every location listed since Koil started, oldest first, each once,
    // which k and j in the path field put back (see Vim.lineHistory).
    property var pathHistory: []
    // The listing's entry a file was opened from (with Enter), which `-`
    // goes back to; "" for a file opened otherwise.
    property string openedFrom: ""
    // Where the cursor was in the listing when a file was opened (see
    // listingSpot), which `-` goes back to with openedFrom.
    property var fileSpot: null
    // A file's unsaved changes, or the listing's edits and changes that
    // aren't applied.
    property bool modified: false
    // Whether something changed on disk that the listing may not show yet
    // (see syncListing), and whether what goes against the user's edits is
    // being asked about.
    property bool diskChanged: false
    property bool askingConflicts: false
    // Quit once the Save dialog has saved the file (:wq, or Save in the
    // :confirm q dialog, for a file that has no path yet).
    property bool quitAfterSave: false
    readonly property int defaultFontSize: 16
    readonly property int minFontSize: 6
    readonly property int maxFontSize: 72
    // The Nerd Font Koil ships (JetBrains Mono NL), which has the icons.
    readonly property string defaultFontFamily: system.nerdFontFamily()
    // The fonts the editor offers: the installed monospaced ones. Finding
    // them loads every font, which takes a moment, so it waits until
    // they're needed (loadFontFamilies).
    property var fontFamilies: []
    // "system", "light" or "dark". The other settings in use are vim's.
    property string colorScheme: settings.colorScheme
    // The settings vim keeps, which :set changes (see changeSetting).
    readonly property var vimSettings: ["fontSize", "fontFamily", "number", "relativeNumber"]

    width: 900
    height: 650
    visible: true
    title: (listing ? location : fileName) + (modified ? " •" : "") + " — Koil"

    // Last in the history, however it got there (the path field, Enter, -,
    // a dir renamed on disk), keeping the newest 100.
    onLocationChanged: {
        if (location)
            pathHistory = pathHistory.filter(p => p !== location).concat([location]).slice(-100);
    }

    // Shows `text` as a new document, whose icons hide the texts in
    // `entries` (see Hidden text in Vim.qml). `path` is its file, if any.
    function load(text, entries, path) {
        activate(editorView);
        editorView.setText(text);
        vim.reset(entries);
        filePath = path;
        modified = false;
        editorView.textArea.forceActiveFocus();
    }

    // Shows a file that was read, leaving the listing (whose edits Koil
    // keeps, if they can be read).
    function loadFile(text, path) {
        if (listing) {
            if (!updateListing())
                return;
            fileSpot = listingSpot();
        }
        listing = false;
        problems = [];
        load(text, [], path);
        updatePathSyntax();
    }

    // Opens the file `path` (see loadFile), or says in the status line why
    // it can't, as vim does (a picture isn't text).
    function readFile(path) {
        const error = doc.openFile(path);
        if (error)
            vim.showError(error);
    }

    // Lists the dir (or pattern) `path`: File > Open Folder, and at startup.
    // False if it can't be opened (the status line says why).
    function openFolder(path) {
        if (listing)
            return updateListing(path);
        const r = JSON.parse(koil.open(path));
        if (!r.ok) {
            vim.showError(r.message);
            return false;
        }
        showListing(true, "");
        return true;
    }

    // Shows Koil's listing of what's open (see listing.rs), and its path in
    // the path field. For the same listing as before (`moved` false), the
    // new text replaces the old as an edit, which undo can take back.
    // Otherwise it starts over: undo mustn't bring back another dir's
    // entries, which Koil would read as this one's. The cursor goes to the
    // entry `from` (the dir `-` came from), or else to the first one. With
    // `keep` (see listingSpot), it goes back to where it was, on its entry's
    // line if that's still there (or `from`'s), which stays where it was in
    // the view; so it does whenever the same location is shown again, as
    // the same listing, or with other entries (:set hidden, gitignore). Vim
    // stays in the path field if it was there.
    function showListing(moved, from, keep) {
        const r = JSON.parse(koil.render());
        if (listing && !keep && (!moved || r.path === location))
            keep = listingSpot();
        iconColors = Object.assign({}, iconColors, r.colors);
        pendingIconColor = r.pendingColor;
        location = r.path;
        const inPath = listing && activeView === pathView;
        activate(editorView);
        if (listing && !moved) {
            vim.replaceText(r.text, r.hidden);
        } else {
            listing = true;
            load(r.text, r.hidden, "");
        }
        // An entry an update moved (a rename, a new one, which go where
        // they sort) takes the cursor with it.
        const name = from || (keep ? keep.name : "");
        const i = name ? r.names.indexOf(name) : -1;
        const line = i >= 0 ? i : keep ? keep.line : 0;
        const column = keep ? keep.column : 0; // 0: jumpTo puts it after the icon and two spaces
        const f = editorView.flickable;
        const y = keep ? keep.contentY + (line - keep.line) * editorView.lineHeight : f.contentY;
        // Before jumpTo, which then scrolls only if the line is out of view.
        // Entries that came or went above it don't move it.
        if (y !== f.contentY)
            f.contentY = Math.max(0, Math.min(y, f.contentHeight - f.height));
        const t = editorView.textArea.text;
        const ls = Txt.lineToPos(t, Math.min(line + 1, Txt.countLines(t)));
        vim.jumpTo(Txt.atColumn(t, ls, column));
        showPath(r.path);
        modified = koil.hasChanges();
        checkListing();
        updatePendingLines();
        updatePathSyntax(true);
        if (inPath)
            activate(pathView);
        koil.watch();
        // What changed while a file was open.
        if (diskChanged)
            Qt.callLater(syncListing);
    }

    // Puts `path` in the path field (while vim edits the listing), unless
    // it's there already: then it keeps its undo history.
    function showPath(path) {
        pathProblems = [];
        if (pathView.textArea.text === path)
            return;
        pathView.setText(path);
        // A new buffer, with the cursor at the end.
        pathView.saved = {
            cursor: path.length
        };
    }

    // Reads the edited listing into Koil, then opens `open` (a dir, relative
    // to the open one) if given, else the path in the path field if it
    // changed, and shows the listing again. False if it can't (the problems
    // and the status line say why).
    function updateListing(open) {
        const r = JSON.parse(koil.update(pathView.textArea.text, editorView.textArea.text, JSON.stringify(editorView.hidden), open || ""));
        if (!r.ok) {
            if (r.problems.length)
                problems = r.problems;
            if (r.pathProblems.length)
                pathProblems = r.pathProblems;
            vim.showError(r.message);
            return false;
        }
        showListing(r.moved, r.from);
        if (r.message)
            vim.showMessage(r.message);
        return true;
    }

    // Shows what changed on disk in the listing (see Koil.sync), keeping the
    // user's edits, as edits undo doesn't take back. Not while a file is
    // open (showListing comes back to it), nor while the listing can't
    // change under the user: a dialog, a macro, typing in the path field.
    function syncListing() {
        if (!diskChanged || !listing)
            return;
        if (confirmDialog.opened || askingConflicts || vim.running || activeView === pathView && vim.inserting) {
            syncTimer.start();
            return;
        }
        diskChanged = false;
        const started = Date.now();
        const r = JSON.parse(koil.sync(editorView.textArea.text, JSON.stringify(editorView.hidden)));
        if (r.moved) {
            showListing(true, "");
        } else {
            mergeListing(r, false);
            // The open dir was renamed.
            if (r.path !== location) {
                location = r.path;
                showPath(r.path);
                updatePathSyntax(true);
            }
            koil.watch();
        }
        if (r.failed)
            vim.showError(r.message);
        else if (r.message)
            vim.showMessage(r.message);
        // A pattern's can take a while: not more than a fifth of the time.
        syncTimer.interval = Math.max(100, 4 * (Date.now() - started));
        askConflicts(r.questions);
    }

    // Puts `merge`'s edits (see Koil.sync) in the listing, while vim edits
    // it (back in the path field after, if it was there). Undo takes them
    // back only if `undoable`; else they aren't the user's, and don't make
    // the listing modified.
    function mergeListing(merge, undoable) {
        if (!merge.edits.length)
            return;
        iconColors = Object.assign({}, iconColors, merge.colors);
        const inPath = activeView === pathView, wasModified = modified;
        activate(editorView);
        vim.mergeEdits(merge.edits, undoable);
        if (inPath)
            activate(pathView);
        modified = undoable || wasModified;
        checkListing();
        updatePendingLines();
    }

    // Asks about each of `questions` (see listing::Question) in turn: Yes
    // takes the other way (Koil.resolve), as an edit undo can take back.
    function askConflicts(questions) {
        askingConflicts = questions.length > 0;
        if (!askingConflicts)
            return;
        const q = questions[0];
        confirmDialog.ask(q.text, q.details, () => {
            const r = JSON.parse(koil.resolve(editorView.textArea.text, JSON.stringify(editorView.hidden), JSON.stringify(q.conflicts)));
            mergeListing(r, true);
            modified = modified || koil.hasChanges();
            koil.watch();
        }, null, () => Qt.callLater(askConflicts, questions.slice(1)));
    }

    // Finds the parts of the regex in the path field again, if the path
    // changed (or `force`, when the regex setting did).
    function updatePathSyntax(force) {
        const line = listing ? pathView.textArea.text : "";
        if (line === pathLine && !force)
            return;
        pathLine = line;
        pathSyntax = listing ? JSON.parse(koil.pathSyntax(line)) : [];
    }

    // Finds the listing's lines whose entries applying would change, after
    // every edit. Called later after vim's: halfway through one, its hidden
    // text isn't up to date, and coloring counts as a text change, which
    // would make it shift that text again.
    function updatePendingLines() {
        pendingLines = listing ? JSON.parse(koil.pendingLines(editorView.textArea.text, JSON.stringify(editorView.hidden))) : [];
    }

    function checkListing() {
        checkTimer.stop();
        problems = listing ? JSON.parse(koil.check(editorView.textArea.text, JSON.stringify(editorView.hidden))) : [];
    }

    // Makes vim edit `view`: the listing's editor or the path field. It
    // keeps the other one's cursor and undo history for when it's back (see
    // Buffers in Vim.qml).
    function activate(view) {
        if (view === activeView)
            return;
        activeView.saved = vim.leaveBuffer();
        activeView = view; // which vim's editor follows
        vim.enterBuffer(view.saved);
        view.textArea.forceActiveFocus();
    }

    // Enter in the path field: opens the path (or reads the listing again,
    // if it didn't change), then goes to the listing.
    function openPath() {
        if (updateListing())
            activate(editorView);
    }

    // Koil's keys in the listing and the path field (see Vim.commandKeys).
    function runKeyCommand(name, count) {
        if (name === "update")
            updateListing();
        else if (name === "apply")
            applyChanges(false, false);
        else if (name === "parent")
            updateListing(Array(Math.max(count, 1)).fill("..").join("/"));
        else if (name === "open")
            openLine(count);
        else if (name === "openPath")
            openPath();
        else if (name === "switch")
            activate(activeView === pathView ? editorView : pathView);
        else if (name === "hidden")
            vim.showHidden = !vim.showHidden;
        else if (name === "gitignore")
            vim.gitignore = !vim.gitignore;
        else if (name === "regex")
            vim.regex = !vim.regex;
        else if (name === "back")
            leaveFile(false);
    }

    // Enter in the listing: opens the dir or file on the cursor's line. On a
    // line without an entry it's vim's Enter.
    function openLine(count) {
        const t = editorView.textArea.text, line = Txt.lineOf(t, vim.cursor) - 1;
        const target = JSON.parse(koil.targetOnLine(t, JSON.stringify(vim.hidden), line));
        if (!target) {
            vim.runMotion("<CR>", count);
        } else if (target.dir !== undefined) {
            updateListing(target.dir);
        } else if (target.new !== undefined) {
            createFile(target.new);
        } else {
            // The file on disk, even if the line renames it; loadFile updates
            // the listing first.
            openedFrom = target.file.name;
            readFile(target.file.path);
        }
    }

    // Enter on a new file (`{ path, name }`): once the user says so, creates
    // it (with the new dirs it's in) before the other changes, which stay,
    // and opens it.
    function createFile(target) {
        // Koil must have the new entry, and the rest of the listing.
        if (!updateListing())
            return;
        const r = JSON.parse(koil.createSteps(target.path));
        if (r.message) {
            vim.showError(r.message);
            return;
        }
        // Only the new dirs need saying.
        const details = r.steps.length > 1 ? r.steps.join("\n") : "";
        confirmDialog.ask("“" + target.name + "” doesn't exist yet. Create it?", details, () => {
            const spot = listingSpot();
            const c = JSON.parse(koil.create(target.path));
            // From scratch, as after an apply: undo mustn't bring back its
            // line without its ID, which Koil would read as new again.
            showListing(true, "", spot);
            if (!c.ok) {
                vim.showError(c.message);
                return;
            }
            openedFrom = target.name;
            readFile(target.path);
            // Opened, else the status line says why.
            if (!listing)
                vim.showMessage(c.message);
        });
    }

    // `-` in a file: back to the listing it was opened from, or else its
    // dir's, with the cursor on its entry. Unsaved changes are saved (or
    // dropped) first, if the user says so.
    function leaveFile(force) {
        if (!force) {
            askToSave(() => leaveFile(true));
            return;
        }
        if (!openedFrom) {
            const r = JSON.parse(koil.open(doc.dirOf(filePath)));
            if (!r.ok) {
                vim.showError(r.message);
                return;
            }
        }
        showListing(true, openedFrom || fileName, openedFrom ? fileSpot : null);
    }

    // Applies the listing's changes once the user confirms them (Space
    // Space, :w, File > Apply Changes…), those they leave picked (the
    // others are forgotten), then quits if `quit` is set. With `orQuit`
    // (:confirm q, ZZ), No quits without applying, and if the listing can't be read (its errors, or a path that
    // can't be opened), it asks to quit without the changes, saying why (the
    // status line's error, which updateListing just showed).
    function applyChanges(quit, orQuit) {
        if (!updateListing()) {
            if (orQuit)
                confirmDialog.ask("The changes can't be applied. Quit without them?", vim.message, () => Qt.quit());
            return;
        }
        const actions = JSON.parse(koil.actions());
        if (!actions.length) {
            if (quit)
                Qt.quit();
            else
                vim.showMessage("Nothing to apply");
            return;
        }
        const total = actions.length;
        const what = picked => total === 1 ? "this change" : picked === total ? "these " + total + " changes"
            : picked + " of these " + total + " changes";
        confirmDialog.ask(picked => "Apply " + what(picked) + (orQuit ? " before quitting?" : "?"), actions, picked => {
            const spot = listingSpot();
            const r = JSON.parse(koil.apply(JSON.stringify(picked)));
            showListing(true, "", spot);
            report(r);
            if (r.ok && quit)
                Qt.quit();
        }, orQuit ? () => Qt.quit() : null);
    }

    // u with no change left to undo: undoes Koil's last apply, once the user
    // confirms it.
    function undoApply() {
        // Undo may have taken the listing back to before an update, which
        // Koil must see before anything can be undone.
        if (!updateListing())
            return;
        const r = JSON.parse(koil.undoSteps());
        if (r.message) {
            vim.showError(r.message);
            return;
        }
        if (!r.steps.length)
            return;
        vim.showMessage("");
        confirmDialog.ask("Undo the last apply?", r.steps.join("\n"), () => {
            const spot = listingSpot();
            const u = JSON.parse(koil.undo());
            showListing(true, "", spot);
            report(u);
        });
    }

    // Where the cursor is in the listing (its line's name, line and column)
    // and how far it's scrolled, for showListing to keep when it shows the
    // listing from scratch (an apply, its undo, back from a file). The
    // listing's cursor, also while vim is in the path field.
    function listingSpot() {
        const t = editorView.textArea.text;
        const p = activeView === editorView ? vim.cursor : editorView.saved?.cursor ?? 0;
        const ls = Txt.lineStart(t, p), text = t.slice(ls, Txt.lineEnd(t, ls));
        const gap = text.indexOf("  ");
        return {
            name: gap < 0 ? "" : text.slice(gap + 2).trim(),
            line: Txt.lineOf(t, p) - 1,
            column: Txt.column(t, p),
            contentY: editorView.flickable.contentY
        };
    }

    // Shows what apply or undo did, `{ ok, message }`.
    function report(r) {
        if (r.ok)
            vim.showMessage(r.message);
        else
            vim.showError(r.message);
    }

    // :set hidden, gitignore or regex. As in koil-cli, the listing is read
    // with the settings it was shown with, and then shown with the new ones.
    function settingChanged() {
        if (listing)
            Qt.callLater(updateListing);
        // Even if the listing can't be read yet.
        Qt.callLater(updatePathSyntax, true);
    }

    // Whether quitting would lose something: a file's unsaved changes, or
    // the listing's changes that aren't applied (which it reads first).
    function unsaved() {
        return listing ? !updateListing() || koil.hasChanges() : modified || koil.hasChanges();
    }

    // Quits, unless a file is open while the listing has changes that
    // aren't applied: then it goes back to the listing instead (dropping
    // the file's unsaved changes), so they aren't lost, and with `confirm`
    // (:confirm q, ZZ) asks to apply them before quitting.
    function quitApp(confirm) {
        if (listing || !koil.hasChanges()) {
            Qt.quit();
            return;
        }
        leaveFile(true);
        if (!listing)
            return;
        if (confirm)
            applyChanges(true, true);
        else
            vim.showMessage("Not quitting: the listing has changes that aren't applied");
    }

    function openFile() {
        openDialog.open();
    }

    // Runs `open`, which shows something else in place of the file, once
    // the file's unsaved changes are saved or dropped, as the user says
    // (Cancel keeps the file open). At once in the listing, whose edits
    // Koil keeps.
    function askToSave(open) {
        if (listing || !modified) {
            open();
            return;
        }
        confirmDialog.ask("Save changes to “" + fileName + "”?", "", () => {
            if (!doc.saveFile(filePath, editorView.textArea.text))
                return;
            // Saved, even if what's opened next can't be.
            modified = false;
            open();
        }, open);
    }

    // Opens a file or dir dropped on the window, as File > Open or Open
    // Folder would.
    function openDropped(path) {
        askToSave(() => {
            if (doc.isFile(path)) {
                openedFrom = "";
                readFile(path);
            } else {
                openFolder(path);
            }
        });
    }

    // Saves the file, asking for a path if it has none, then quits if
    // `quit` is set and the save worked (see quitApp, which `orQuit` is
    // passed to). The listing's changes are applied instead, once they're
    // confirmed; with `orQuit` (ZZ), No quits without applying.
    function save(quit, orQuit) {
        if (listing) {
            applyChanges(!!quit, !!orQuit);
            return;
        }
        if (!filePath) {
            saveAs();
            quitAfterSave = !!quit;
            return;
        }
        if (doc.saveFile(filePath, editorView.textArea.text)) {
            modified = false;
            if (quit)
                quitApp(orQuit);
        }
    }

    function saveAs() {
        quitAfterSave = false;
        saveDialog.open();
    }

    function loadFontFamilies() {
        if (fontFamilies.length)
            return;
        const families = system.monospaceFamilies();
        fontFamilies = families.includes(defaultFontFamily) ? families : families.concat(defaultFontFamily).sort((a, b) => a.localeCompare(b));
    }

    function zoom(step) {
        vim.fontSize = Math.max(minFontSize, Math.min(maxFontSize, vim.fontSize + step));
    }

    // Qt 6.8 and later can override the system's light or dark mode, which
    // also changes the palette, the title bar and the menus.
    function applyColorScheme() {
        Application.styleHints.colorScheme = colorScheme === "light" ? Qt.ColorScheme.Light : colorScheme === "dark" ? Qt.ColorScheme.Dark : Qt.ColorScheme.Unknown;
    }

    onColorSchemeChanged: applyColorScheme()

    // Saves a setting and uses it now: one of vimSettings, or colorScheme.
    function changeSetting(name, value) {
        (vimSettings.includes(name) ? vim : root)[name] = value;
        settings[name] = value;
    }

    // The saved settings, which Koil starts with. The Settings window shows
    // and changes them (along with the ones in use); the zoom and :set change
    // only the ones in use, until Koil quits, and Cmd+0 or :set fs& goes back
    // to the saved ones.
    Settings {
        id: settings

        property int fontSize: root.defaultFontSize
        property string fontFamily: root.defaultFontFamily
        property string colorScheme: "system"
        property bool number: false
        property bool relativeNumber: false
    }

    Theme {
        id: theme

        palette: editorView.textArea.palette
        font: editorView.textArea.font
        zoom: vim.fontSize / root.defaultFontSize
    }

    System {
        id: system
    }

    Document {
        id: doc

        onLoaded: (path, text) => root.loadFile(text, path)
        onFailed: message => vim.showError(message)
        // Finder's Open With on macOS (see watchFileOpens): opened as if
        // dropped on the window, and likewise not while a dialog is open.
        // Later, so Finder isn't kept waiting.
        onFileOpened: path => {
            if (dropArea.enabled)
                Qt.callLater(root.openDropped, path);
        }
        Component.onCompleted: watchFileOpens()
    }

    Koil {
        id: koil

        showHidden: vim.showHidden
        gitignore: vim.gitignore
        regex: vim.regex

        onChangedOnDisk: {
            root.diskChanged = true;
            if (!syncTimer.running)
                syncTimer.start();
        }
    }

    // Syncs the listing a moment after something changed on disk (once for
    // a burst of changes), and then not again for a while if it took long.
    Timer {
        id: syncTimer

        interval: 100
        onTriggered: root.syncListing()
    }

    // Checks the listing for problems once typing stops for a moment.
    Timer {
        id: checkTimer

        interval: 200
        onTriggered: root.checkListing()
    }

    Vim {
        id: vim

        editor: root.activeView.textArea
        flickable: root.activeView.flickable
        singleLine: root.activeView === pathView
        // Tab while typing in the path field completes the dir being
        // written (see Koil.complete).
        completer: root.listing && root.activeView === pathView ? (line, cursor) => JSON.parse(koil.complete(line, cursor)) : null
        lineHistory: root.pathHistory
        linePrefixes: root.listing && root.activeView === editorView
        clipboard: system
        fileName: root.listing ? root.location : root.filePath
        lineHeight: editorView.lineHeight
        charWidth: editorView.charWidth
        number: settings.number
        defaultNumber: settings.number
        relativeNumber: settings.relativeNumber
        defaultRelativeNumber: settings.relativeNumber
        fontSize: settings.fontSize
        defaultFontSize: settings.fontSize
        minFontSize: root.minFontSize
        maxFontSize: root.maxFontSize
        fontFamily: settings.fontFamily
        defaultFontFamily: settings.fontFamily
        fontFamilies: root.fontFamilies
        // In the path field, Shift+Enter updates like Enter but stays
        // there; in the listing it's vim's Enter.
        commandKeys: root.listing ? Object.assign({
            "  ": "apply",
            "-": "parent",
            "<CR>": root.activeView === pathView ? "openPath" : "open",
            "<Tab>": "switch",
            "g.": "hidden",
            "gi": "gitignore",
            "gr": "regex"
        }, root.activeView === pathView ? {
            "<S-CR>": "update"
        } : {}) : root.filePath ? ({
                "-": "back"
            }) : ({})

        onFontFamiliesNeeded: root.loadFontFamilies()
        onWriteRequested: (quit, confirm) => root.save(quit, confirm)
        onQuitRequested: (force, confirm, all) => {
            if (force && all) {
                Qt.quit();
            } else if (force || !root.unsaved()) {
                root.quitApp(false);
            } else if (!root.listing && !root.modified) {
                // The listing's changes, while a file is open.
                root.quitApp(confirm);
            } else if (confirm) {
                if (root.listing)
                    root.applyChanges(true, true);
                else
                    confirmDialog.ask("Save changes to “" + root.fileName + "”?", "", () => root.save(true, true), () => root.quitApp(true));
            } else {
                vim.showError("E37: No write since last change (add ! to override)");
            }
        }
        onKeyCommand: (name, count) => root.runKeyCommand(name, count)
        onNothingToUndo: {
            if (root.listing && root.activeView === editorView)
                root.undoApply();
        }
        onShowHiddenChanged: root.settingChanged()
        onGitignoreChanged: root.settingChanged()
        onRegexChanged: root.settingChanged()
        onHelpRequested: topic => {
            if (!help.show(topic))
                vim.showError("E149: Sorry, no help for " + topic);
        }
        onRegistersRequested: rows => help.showList("Registers", rows, 6)
    }

    // Behind the path field and the space under it, as behind the text.
    Rectangle {
        anchors.fill: parent
        color: (editorView.textArea.background as Rectangle).color
    }

    // Over the listing, a field with the path of what's listed, which vim
    // edits like the listing (Tab goes from one to the other, Enter opens
    // the path, and Shift+Enter opens it but stays in the field), and
    // Koil's options beside it, which g., gi and gr toggle too.
    Rectangle {
        id: pathBar

        visible: root.listing
        x: 8 * theme.zoom
        y: 6 * theme.zoom
        width: parent.width - 2 * x
        height: pathView.height + 6 * theme.zoom
        radius: 3 * theme.zoom
        color: theme.field
        border.color: pathView.textArea.activeFocus ? theme.accent : theme.dark ? "transparent" : "#cecece"

        Editor {
            id: pathView

            anchors.left: parent.left
            anchors.right: options.left
            anchors.leftMargin: 1
            anchors.rightMargin: 4 * theme.zoom
            anchors.verticalCenter: parent.verticalCenter
            height: lineHeight
            pathField: true
            vim: vim
            findBar: findBar
            theme: theme
            system: system
            pathSyntax: root.pathSyntax
            problems: root.pathProblems
            onActivated: root.activate(pathView)
            onEdited: {
                root.pathProblems = [];
                root.updatePathSyntax();
            }
        }

        Row {
            id: options

            anchors.right: parent.right
            anchors.rightMargin: 3 * theme.zoom
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1 * theme.zoom

            IconButton {
                theme: theme
                iconPath: "M1.5 8 C3.5 4.8 5.6 3.5 8 3.5 C10.4 3.5 12.5 4.8 14.5 8 C12.5 11.2 10.4 12.5 8 12.5 C5.6 12.5 3.5 11.2 1.5 8 Z M6 8 A2 2 0 1 0 10 8 A2 2 0 1 0 6 8 Z"
                checkable: true
                checked: vim.showHidden
                tip: qsTr("Show Hidden Entries")
                shortcuts: ["g."]
                onToggled: vim.showHidden = checked
            }
            IconButton {
                theme: theme
                iconPath: "M2 3.5 H14 L9.5 8.5 V13 L6.5 11.5 V8.5 Z"
                checkable: true
                checked: vim.gitignore
                tip: qsTr("Hide Ignored Entries")
                shortcuts: ["gi"]
                onToggled: vim.gitignore = checked
            }
            IconButton {
                theme: theme
                label: ".*"
                checkable: true
                checked: vim.regex
                tip: qsTr("Use Regular Expression")
                shortcuts: ["gr"]
                onToggled: vim.regex = checked
            }
        }
    }

    Editor {
        id: editorView

        anchors.top: root.listing ? pathBar.bottom : parent.top
        // A line's height between the field and the listing's first line.
        anchors.topMargin: root.listing ? lineHeight - textArea.topPadding : 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        vim: vim
        findBar: findBar
        theme: theme
        system: system
        listing: root.listing
        iconColors: root.iconColors
        pendingIconColor: root.pendingIconColor
        pendingLines: root.pendingLines
        problems: root.problems
        // An ID as the path it stands for, so the hover says whose it is.
        describeHidden: text => koil.idPath(text) || text
        onActivated: root.activate(editorView)
        onEdited: {
            root.modified = true;
            if (root.listing) {
                checkTimer.restart();
                Qt.callLater(root.updatePendingLines);
            }
        }
    }

    // Clips the find bar as it slides in from above the editor.
    Item {
        anchors.fill: editorView
        clip: true

        FindBar {
            id: findBar

            anchors.right: parent.right
            anchors.rightMargin: 16 // clear of the scroll bar
            editor: root.activeView.textArea
            vim: vim
            theme: theme
        }
    }

    // A file or dir dragged over the window: dropped, it opens (the first
    // one, if there are several; see openDropped). In the overlay, so the
    // status line takes it too. Not while a dialog is open.
    DropArea {
        id: dropArea

        // The path of what the drag would open, and its name.
        property string path: ""
        readonly property string name: path.split(/[\\/]/).filter(part => part).pop() || path

        parent: root.Overlay.overlay
        anchors.fill: parent
        keys: ["text/uri-list"]
        enabled: !confirmDialog.opened && !help.opened && !root.askingConflicts

        onEntered: event => {
            dropArea.path = "";
            for (const url of event.urls) {
                dropArea.path = doc.urlToPath(url);
                if (dropArea.path)
                    break;
            }
            // Something else, like a web link.
            event.accepted = dropArea.path !== "";
        }
        onDropped: event => {
            event.accept(Qt.CopyAction);
            // Later, so the app the drag came from isn't kept waiting while
            // a long file or listing opens.
            Qt.callLater(root.openDropped, dropArea.path);
        }

        Rectangle {
            anchors.fill: parent
            visible: dropArea.containsDrag
            color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.08)
            border.color: theme.accent
            border.width: 2 * theme.zoom

            Panel {
                anchors.centerIn: parent
                width: dropLabel.implicitWidth
                height: dropLabel.implicitHeight
                theme: theme

                Text {
                    id: dropLabel

                    padding: 10 * theme.zoom
                    text: qsTr("Open “%1”").arg(dropArea.name)
                    font.pixelSize: Math.round(13 * theme.zoom)
                    color: theme.text
                    textFormat: Text.PlainText
                }
            }
        }
    }

    HelpPanel {
        id: help

        theme: theme
        defaultFontFamily: root.defaultFontFamily
        onClosed: root.activeView.textArea.forceActiveFocus()
    }

    // :confirm q with unsaved changes, and applying the listing's changes
    // (or undoing them).
    ConfirmDialog {
        id: confirmDialog

        theme: theme
        onClosed: root.activeView.textArea.forceActiveFocus()
    }

    SettingsWindow {
        id: settingsWindow

        app: root
        settings: settings
        theme: theme
    }

    footer: Pane {
        contentHeight: position.implicitHeight
        padding: 4
        leftPadding: 8
        rightPadding: 8

        Label {
            id: status

            anchors.left: parent.left
            anchors.right: position.left
            // A message too long to fit loses its middle, as its end often
            // says why (a path can be long); the command line its end, as
            // its cursor is measured from its start.
            elide: vim.commandLine === "" ? Text.ElideMiddle : Text.ElideRight
            font.family: vim.fontFamily
            font.pointSize: vim.fontSize
            textFormat: Text.PlainText
            color: vim.commandLine === "" && vim.message !== "" && vim.messageIsError ? "#d33" : theme.windowText
            text: vim.commandLine || vim.message || vim.modeLabel || " "

            // Measured with TextMetrics, whose widths are properties, so they
            // follow font size changes (FontMetrics.advanceWidth() is a call).
            TextMetrics {
                id: beforeCursor

                font: status.font
                text: vim.commandLine.slice(0, vim.commandCursor)
            }
            TextMetrics {
                id: underCursor

                font: status.font
                text: commandCursor.character || " "
            }

            // Command-line cursor: a block over the character it's on.
            Rectangle {
                id: commandCursor

                readonly property string character: vim.commandLine.charAt(vim.commandCursor)

                visible: vim.commandLine !== ""
                x: beforeCursor.advanceWidth
                width: underCursor.advanceWidth
                height: parent.height
                color: status.color

                Text {
                    text: commandCursor.character
                    font: status.font
                    color: theme.window
                    textFormat: Text.PlainText
                }
            }
        }

        Label {
            id: position

            anchors.right: parent.right
            font.family: vim.fontFamily
            font.pointSize: vim.fontSize
            // A macro's progress while it runs: not the position, which
            // would be found again at every key it runs.
            text: vim.progress ? vim.progress + " (Esc to stop)" : vim.pendingKeys + "    " + vim.positionLabel()
        }
    }

    FileDialog {
        id: openDialog

        fileMode: FileDialog.OpenFile
        onAccepted: {
            const path = doc.urlToPath(selectedFile);
            root.askToSave(() => {
                root.openedFrom = "";
                root.readFile(path);
            });
        }
    }

    FolderDialog {
        id: folderDialog

        onAccepted: {
            const path = doc.urlToPath(selectedFolder);
            root.askToSave(() => root.openFolder(path));
        }
    }

    FileDialog {
        id: saveDialog

        fileMode: FileDialog.SaveFile
        onAccepted: {
            const path = doc.urlToPath(selectedFile);
            if (doc.saveFile(path, editorView.textArea.text)) {
                root.filePath = path;
                root.modified = false;
                if (root.quitAfterSave)
                    root.quitApp(false);
            }
            root.quitAfterSave = false;
        }
        onRejected: root.quitAfterSave = false
    }

    // macOS: native menu bar. The Quit/Preferences roles make Qt move those
    // items into the application ("Koil") menu.
    Component {
        id: macMenuBar

        Platform.MenuBar {
            Platform.Menu {
                title: qsTr("File")

                Platform.MenuItem {
                    text: qsTr("Open…")
                    shortcut: StandardKey.Open
                    onTriggered: root.openFile()
                }
                Platform.MenuItem {
                    text: qsTr("Open Folder…")
                    shortcut: "Ctrl+Shift+O"
                    onTriggered: folderDialog.open()
                }
                // In the listing, Cmd+S updates; applying is its own item.
                Platform.MenuItem {
                    text: root.listing ? qsTr("Update") : qsTr("Save")
                    shortcut: StandardKey.Save
                    onTriggered: root.listing ? root.updateListing() : root.save()
                }
                Platform.MenuItem {
                    text: qsTr("Apply Changes…")
                    enabled: root.listing
                    onTriggered: root.save()
                }
                Platform.MenuItem {
                    text: qsTr("Save As…")
                    enabled: !root.listing
                    shortcut: StandardKey.SaveAs
                    onTriggered: root.saveAs()
                }
                Platform.MenuItem {
                    text: qsTr("Settings…")
                    role: Platform.MenuItem.PreferencesRole
                    shortcut: StandardKey.Preferences
                    onTriggered: settingsWindow.open()
                }
                Platform.MenuItem {
                    text: qsTr("Quit Koil")
                    role: Platform.MenuItem.QuitRole
                    shortcut: StandardKey.Quit
                    onTriggered: Qt.quit()
                }
            }
            Platform.Menu {
                title: qsTr("Edit")

                Platform.MenuItem {
                    text: qsTr("Find")
                    shortcut: StandardKey.Find
                    onTriggered: findBar.open(false)
                }
                Platform.MenuItem {
                    text: qsTr("Replace")
                    shortcut: "Ctrl+Alt+F" // Cmd+Option+F, as in VS Code
                    onTriggered: findBar.open(true)
                }
                Platform.MenuItem {
                    text: qsTr("Find Next")
                    shortcut: StandardKey.FindNext
                    onTriggered: findBar.findNext(1)
                }
                Platform.MenuItem {
                    text: qsTr("Find Previous")
                    shortcut: StandardKey.FindPrevious
                    onTriggered: findBar.findNext(-1)
                }
            }
            Platform.Menu {
                title: qsTr("View")

                Platform.MenuItem {
                    text: qsTr("Zoom In")
                    shortcut: StandardKey.ZoomIn
                    onTriggered: root.zoom(1)
                }
                Platform.MenuItem {
                    text: qsTr("Zoom Out")
                    shortcut: StandardKey.ZoomOut
                    onTriggered: root.zoom(-1)
                }
                Platform.MenuItem {
                    text: qsTr("Actual Size")
                    shortcut: "Ctrl+0" // no StandardKey; Qt maps Ctrl to Cmd
                    onTriggered: vim.fontSize = settings.fontSize
                }
            }
        }
    }

    // Windows / Linux: regular in-window menu bar.
    Component {
        id: windowMenuBar

        MenuBar {
            Menu {
                title: qsTr("&File")

                Action {
                    text: qsTr("&Open…")
                    shortcut: StandardKey.Open
                    onTriggered: root.openFile()
                }
                Action {
                    text: qsTr("Open &Folder…")
                    shortcut: "Ctrl+Shift+O"
                    onTriggered: folderDialog.open()
                }
                Action {
                    text: root.listing ? qsTr("&Update") : qsTr("&Save")
                    shortcut: StandardKey.Save
                    onTriggered: root.listing ? root.updateListing() : root.save()
                }
                Action {
                    text: qsTr("A&pply Changes…")
                    enabled: root.listing
                    onTriggered: root.save()
                }
                Action {
                    text: qsTr("Save &As…")
                    enabled: !root.listing
                    shortcut: StandardKey.SaveAs
                    onTriggered: root.saveAs()
                }
                MenuSeparator {}
                Action {
                    text: qsTr("Se&ttings")
                    // Preferences and Quit have no Ctrl binding on Windows.
                    shortcut: "Ctrl+,"
                    onTriggered: settingsWindow.open()
                }
                MenuSeparator {}
                Action {
                    text: qsTr("E&xit")
                    shortcut: "Ctrl+Q"
                    onTriggered: Qt.quit()
                }
            }
            Menu {
                title: qsTr("&Edit")

                Action {
                    text: qsTr("&Find")
                    shortcut: StandardKey.Find
                    onTriggered: findBar.open(false)
                }
                Action {
                    text: qsTr("&Replace")
                    shortcut: StandardKey.Replace // Ctrl+H, as in VS Code
                    onTriggered: findBar.open(true)
                }
                // F3, plus Ctrl+G from findNextShortcut. Written out, since
                // an Action takes only the first of a StandardKey's keys.
                Action {
                    text: qsTr("Find &Next")
                    shortcut: "F3"
                    onTriggered: findBar.findNext(1)
                }
                Action {
                    text: qsTr("Find &Previous")
                    shortcut: "Shift+F3"
                    onTriggered: findBar.findNext(-1)
                }
            }
            Menu {
                title: qsTr("&View")

                Action {
                    text: qsTr("Zoom &In")
                    // StandardKey.ZoomIn is only Ctrl++ (Ctrl+Shift+=) here;
                    // zoomInShortcut adds that.
                    shortcut: "Ctrl+="
                    onTriggered: root.zoom(1)
                }
                Action {
                    text: qsTr("Zoom &Out")
                    shortcut: StandardKey.ZoomOut
                    onTriggered: root.zoom(-1)
                }
                Action {
                    text: qsTr("&Actual Size")
                    shortcut: "Ctrl+0" // no StandardKey for this
                    onTriggered: vim.fontSize = settings.fontSize
                }
            }
        }
    }

    // Windows / Linux: the menu's Zoom In is Ctrl+=; this keeps Ctrl++ too.
    // On macOS, StandardKey.ZoomIn already covers both.
    Shortcut {
        id: zoomInShortcut

        enabled: !root.isMac
        sequences: [StandardKey.ZoomIn]
        onActivated: root.zoom(1)
    }

    // Windows / Linux: the menu's Find Next and Find Previous are F3 and
    // Shift+F3; these add Ctrl+G and Ctrl+Shift+G, like Cmd+G on macOS.
    Shortcut {
        id: findNextShortcut

        enabled: !root.isMac
        sequence: "Ctrl+G"
        onActivated: findBar.findNext(1)
    }
    Shortcut {
        enabled: !root.isMac
        sequence: "Ctrl+Shift+G"
        onActivated: findBar.findNext(-1)
    }

    Component.onCompleted: {
        if (isMac)
            macMenuBar.createObject(root, {
                window: root
            });
        else
            root.menuBar = windowMenuBar.createObject(root);

        applyColorScheme();
        // A file opens as a file; anything else (a dir, a pattern) Koil
        // lists, and with nothing given, the home dir.
        const start = doc.startupPath();
        if (start && doc.isFile(start)) {
            // Once the editor is done: before its own onCompleted, it doesn't
            // have the line numbers' padding, and adding it then had Qt lay
            // out all of a long file again (100,000 lines took a second).
            Qt.callLater(() => {
                const error = doc.openFile(start);
                if (!error)
                    return;
                // One it can't read: its dir, on its entry, as `-` from it
                // would show, and why.
                const r = JSON.parse(koil.open(doc.dirOf(start)));
                if (r.ok)
                    showListing(true, start.split(/[\\/]/).pop());
                vim.showError(error);
            });
        } else if (!openFolder(start || doc.homeDir()) && start && openFolder(doc.homeDir())) {
            // One that isn't there: the home dir, with it in the path field
            // and why it can't be opened, to fix like one written there.
            showPath(doc.shownPath(start));
            updatePathSyntax();
            updateListing();
        }
        // The editor sits in a ScrollView, which is its own focus scope, so
        // `focus: true` alone doesn't give it the keyboard.
        editorView.textArea.forceActiveFocus();
    }
}
