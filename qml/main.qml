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
    // What the listing shows after each entry's line, by its ID: its size
    // or a date, when it's sorted by one (see Editor.infos). Sorted by
    // size, `busyInfos` has the dirs whose sizes are being counted (see
    // pollSizes), whose notes show `infoDots` of their three dots.
    property var infos: ({})
    property var busyInfos: ({})
    property bool counting: false
    property int infoDots: 1
    // How the listing shown is sorted (see showListing), and whether it
    // was sorted before every dir's size was counted, so it's sorted again
    // once they are (see sortCounted).
    property string shownSort: ""
    property bool sortedCounting: false
    // What gs and a key sort the listing by (see Vim.sort), and with the
    // key shifted the other way round: { key, by, label, first, other },
    // as the sort menu shows them (`first` and `other` are each way).
    readonly property var sorts: [
        { key: "n", by: "name", label: qsTr("Name"), first: qsTr("A to Z"), other: qsTr("Z to A") },
        { key: "v", by: "natural", label: qsTr("Natural"), first: "a2, a10, B", other: "B, a10, a2" },
        { key: "e", by: "extension", label: qsTr("Extension"), first: qsTr("A to Z"), other: qsTr("Z to A") },
        { key: "s", by: "size", label: qsTr("Size"), first: qsTr("Largest first"), other: qsTr("Smallest first") },
        // Windows has no size on disk in a dir's listing, so every file is
        // opened for it (see disk_size in koil-core).
        { key: "d", by: "disk", label: Qt.platform.os === "windows" ? qsTr("Size on Disk (slower)") : qsTr("Size on Disk"), first: qsTr("Largest first"), other: qsTr("Smallest first") },
        { key: "m", by: "modified", label: qsTr("Modified"), first: qsTr("Newest first"), other: qsTr("Oldest first") },
        { key: "c", by: "created", label: qsTr("Created"), first: qsTr("Newest first"), other: qsTr("Oldest first") },
        { key: "a", by: "accessed", label: qsTr("Accessed"), first: qsTr("Newest first"), other: qsTr("Oldest first") }
    ]
    // The keys of `sorts`, as Vim.commandKeys: "gss" is "sort:size", "gsS"
    // "sortReverse:size".
    readonly property var sortKeys: {
        const keys = {};
        for (const s of sorts) {
            keys["gs" + s.key] = "sort:" + s.by;
            keys["gs" + s.key.toUpperCase()] = "sortReverse:" + s.by;
        }
        return keys;
    }
    // The words the lines of what applying or undoing does start with
    // (listing::action_text and undo_text), and the kind of change each is,
    // which colors it (see ConfirmDialog.keywords).
    readonly property var changeKeywords: ({
        CREATE: "create",
        RESTORE: "create",
        DELETE: "delete",
        TRASH: "delete",
        MOVE: "rename",
        COPY: "copy"
    })
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
    // Whether the editor shows the scratchpad (see openScratch), and what
    // it had when it was left, for when it's back: { text, buffer (see
    // Vim.leaveBuffer), contentY }, null until it's first left. Whether vim
    // was in the path field when it opened, to go back there.
    property bool scratchpad: false
    property var scratchState: null
    property bool scratchFromPath: false
    // A file's unsaved changes, or the listing's edits and changes that
    // aren't applied.
    property bool modified: false
    // Whether something changed on disk that the listing may not show yet
    // (see syncListing), and whether what goes against the user's edits is
    // being asked about.
    property bool diskChanged: false
    property bool askingConflicts: false
    // A box over the editor that has the keys (:help, or a question), while
    // which the menu can't open, save or edit anything (see also
    // keepHelpKeys).
    readonly property bool boxOpen: help.opened || confirmDialog.opened
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
    // "system", "light" or "dark".
    property string colorScheme: settings.colorScheme
    // When applying asks first (see asksFirst): "always", "deleting" or
    // "never". The other settings in use are vim's.
    property string confirmChanges: settings.confirmChanges
    // The settings vim keeps, which :set changes (see changeSetting).
    readonly property var vimSettings: ["fontSize", "fontFamily", "number", "relativeNumber"]

    width: 900
    height: 650
    visible: true
    title: (listing ? location : scratchpad ? "👻" : fileName) + (modified ? " •" : "") + " — Koil"

    // Last in the history, however it got there (the path field, Enter, -,
    // a dir renamed on disk), keeping the newest 100.
    onLocationChanged: {
        if (location)
            pathHistory = pathHistory.filter(p => p !== location).concat([location]).slice(-100);
    }

    // Shows `text` as a new document, whose icons hide the texts in
    // `entries` (see Hidden text in Vim.qml). `path` is its file, if any.
    function load(text, entries, path) {
        keepScratch();
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

    // _ in the listing: the scratchpad, a text of the user's that's never
    // saved, as it was left (its cursor, undo history and view: see
    // keepScratch), until Koil quits. Like a file, it leaves the listing
    // (whose edits Koil keeps), and _ or - goes back to where the cursor
    // was (see leaveFile).
    function openScratch() {
        if (!updateListing())
            return;
        fileSpot = listingSpot();
        scratchFromPath = activeView === pathView;
        listing = false;
        problems = [];
        const s = scratchState || { text: "", buffer: null, contentY: 0 };
        // Its hidden text comes back with the buffer: entries pasted there
        // keep their IDs on purpose, so they can be put aside and pasted
        // back into a listing (and gh shows their paths).
        load(s.text, [], "");
        scratchpad = true;
        // Before vim's cursor, which then scrolls only if it's out of view.
        const f = editorView.flickable;
        f.contentY = Math.max(0, Math.min(s.contentY, f.contentHeight + f.bottomMargin - f.height));
        vim.enterBuffer(s.buffer);
        updatePathSyntax();
    }

    // Keeps what the scratchpad has as it's left (anything else shown in
    // the editor goes through showListing or load), for openScratch.
    function keepScratch() {
        if (!scratchpad)
            return;
        scratchState = {
            text: editorView.textArea.text,
            buffer: vim.leaveBuffer(),
            contentY: editorView.flickable.contentY
        };
        scratchpad = false;
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
    // `keep` (see listingSpot), it goes back to where it was: the same line
    // and the same view, even if an update moved its entry (a rename, a new
    // one, which go where they sort); so it does whenever the same location
    // is shown again, as the same listing, with other entries (:set hidden,
    // gitignore), or sorted another way. With `from` too (back from a file),
    // it goes to `from`'s line, which stays where the cursor was in the
    // view, unless it's sorted another way: everything moved, and the view
    // stays instead (scrolling only to show the cursor). Vim stays in the
    // path field if it was there.
    function showListing(moved, from, keep) {
        // Before it's the listing, whose prefixes vim would keep out of.
        keepScratch();
        const r = JSON.parse(koil.render());
        if (listing && !keep && (!moved || r.path === location))
            keep = listingSpot();
        const sort = vim.sort + (vim.sortReverse ? " reversed" : "");
        const resorted = sort !== shownSort || sortedCounting && !r.busy.length;
        shownSort = sort;
        sortedCounting = r.busy.length > 0;
        iconColors = Object.assign({}, iconColors, r.colors);
        pendingIconColor = r.pendingColor;
        setNotes(r);
        location = r.path;
        const inPath = listing && activeView === pathView;
        activate(editorView);
        if (listing && !moved) {
            vim.replaceText(r.text, r.hidden);
        } else {
            listing = true;
            load(r.text, r.hidden, "");
        }
        const i = from ? r.names.indexOf(from) : -1;
        const line = i >= 0 ? i : keep ? keep.line : 0;
        const column = keep ? keep.column : 0; // 0: jumpTo puts it after the icon and two spaces
        const f = editorView.flickable;
        const y = !keep ? f.contentY : resorted ? keep.contentY : keep.contentY + (line - keep.line) * editorView.lineHeight;
        // Before jumpTo, which then scrolls only if the line is out of view.
        // Entries that came or went above it don't move it.
        if (y !== f.contentY)
            f.contentY = Math.max(0, Math.min(y, f.contentHeight + f.bottomMargin - f.height));
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
        // Not under :help either, as merging can switch to the listing.
        if (boxOpen || askingConflicts || vim.running || activeView === pathView && vim.inserting) {
            syncTimer.start();
            return;
        }
        diskChanged = false;
        const started = Date.now();
        const r = JSON.parse(koil.sync(editorView.textArea.text, JSON.stringify(editorView.hidden)));
        if (r.moved) {
            showListing(true, "");
        } else {
            if (!r.failed)
                setNotes(r);
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

    // Takes what the listing shows after its lines (see listing::Notes):
    // all of it, or with `sizes`, the dirs' sizes as far as they're
    // counted (see Koil.dirSizes), which change only those.
    function setNotes(notes, sizes) {
        const busy = {};
        for (const id of notes.busy)
            busy[id] = true;
        if (!sizes) {
            infos = notes.infos;
        } else {
            // A dir that can't be read has none.
            const changed = Object.keys(busyInfos).some(id => infos[id] !== notes.infos[id]);
            if (changed) {
                const all = Object.assign({}, infos);
                for (const id in busyInfos)
                    delete all[id];
                infos = Object.assign(all, notes.infos);
            }
        }
        busyInfos = busy;
        counting = notes.busy.length > 0;
    }

    // While dirs' sizes are being counted (sizeTimer), shows them as far
    // as they are, with the dots after them coming and going, and sorts
    // the listing by them once they're all counted.
    function pollSizes() {
        if (counting) {
            infoDots = infoDots % 3 + 1;
            setNotes(JSON.parse(koil.dirSizes()), true);
        }
        if (!counting && sortedCounting)
            sortCounted();
    }

    // Sorts the listing again once every dir's size is counted (an update,
    // like gs), as it was sorted before they were (see sortedCounting),
    // keeping the cursor on its line. Not while the listing can't change
    // under the user (as syncListing), or they're halfway through
    // something: typing, a selection, a command (it waits for those). Not
    // if the update would do more than sort it, opening a path typed in the
    // path field, or fail on the listing's errors: the next one sorts it.
    function sortCounted() {
        if (boxOpen || askingConflicts || vim.running || vim.mode !== "normal" || vim.pendingKeys || vim.commandLine)
            return;
        checkListing();
        // showListing keeps the view, as for gs, while sortedCounting is
        // set, and then clears it.
        if (pathView.textArea.text !== location || problems.some(p => p.severity === "error") || !updateListing())
            sortedCounting = false;
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

    // Find and Replace (`replace`): in :help while it's open (its `/`),
    // else the find bar.
    function find(replace) {
        if (help.opened)
            help.startSearch("/");
        else
            findBar.open(replace);
    }

    // Find Next (`step` 1) and Previous (-1): in :help while it's open.
    function findNext(step) {
        if (help.opened)
            help.searchAgain(step > 0);
        else
            findBar.findNext(step);
    }

    // Nothing else may take the keys while :help is open: it would stay
    // open over the editor, with no key reaching it to close it. If
    // something does (boxOpen keeps the menu from it), it closes. Not when
    // the window just isn't active (another app, the Settings window).
    function keepHelpKeys() {
        if (help.opened && active && activeFocusItem && !help.holds(activeFocusItem))
            help.close();
    }

    onActiveFocusItemChanged: {
        if (help.opened)
            Qt.callLater(keepHelpKeys);
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
        else if (name === "applyAsking")
            applyChanges(false, false, true);
        else if (name === "undoApply")
            undoApply(true);
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
        else if (name.startsWith("sort"))
            sortBy(name.split(":")[1], name.startsWith("sortReverse"));
        else if (name === "back")
            leaveFile(false);
        else if (name === "scratch")
            openScratch();
    }

    // Sorts the listing by `by` (one of Vim.sorts), the other way round if
    // `reverse`, as :set sort and sortreverse do.
    function sortBy(by, reverse) {
        vim.sort = by;
        vim.sortReverse = reverse;
    }

    // The sort button: types gs, which shows the sort menu, or hides it,
    // with the keys going to the editor vim edits.
    function toggleSortMenu() {
        vim.startCommand(sortMenu.visible ? [] : ["g", "s"]);
        activeView.textArea.forceActiveFocus();
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
        const create = () => {
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
        };
        if (!asksFirst(false)) {
            create();
            return;
        }
        // Only the new dirs need saying.
        const details = r.steps.length > 1 ? r.steps.join("\n") : "";
        confirmDialog.ask("“" + target.name + "” doesn't exist yet. Create it?", details, create, null, null,
            changeKeywords);
    }

    // Whether changing files asks first, as the confirmChanges setting
    // says: always, only if something is deleted, or never.
    function asksFirst(deletes) {
        return confirmChanges === "always" || confirmChanges === "deleting" && deletes;
    }

    // `-` in a file: back to the listing it was opened from, or else its
    // dir's, with the cursor on its entry. Unsaved changes are saved (or
    // dropped) first, if the user says so. From the scratchpad (also _),
    // back to where the cursor was, in the path field if it was there.
    function leaveFile(force) {
        if (!force) {
            askToSave(() => leaveFile(true));
            return;
        }
        if (scratchpad) {
            showListing(true, "", fileSpot);
            if (scratchFromPath)
                activate(pathView);
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
    // Space, Space a, :w, File > Apply Changes…), those they leave picked
    // (the others are forgotten), then quits if `quit` is set. When
    // confirmChanges says not to ask (asksFirst), it applies them all,
    // unless `ask` is set (Space a, File > Apply Changes…). With `orQuit` (:confirm q, ZZ), it
    // always asks, and No quits without applying; if the listing can't be read (its errors, or a path that
    // can't be opened), it asks to quit without the changes, saying why (the
    // status line's error, which updateListing just showed).
    function applyChanges(quit, orQuit, ask) {
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
        const apply = picked => {
            const spot = listingSpot();
            const r = JSON.parse(koil.apply(JSON.stringify(picked)));
            showListing(true, "", spot);
            report(r);
            if (r.ok && quit)
                Qt.quit();
        };
        if (!ask && !orQuit && !asksFirst(actions.some(a => a.deletes))) {
            apply(actions.map((a, i) => i));
            return;
        }
        // With none picked, Yes applies nothing, which forgets them all.
        const total = actions.length;
        const these = total === 1 ? "this change" : "these " + total + " changes";
        const what = picked => !picked ? "Discard " + these : picked === total ? "Apply " + these
            : "Apply " + picked + " of " + these;
        confirmDialog.ask(picked => what(picked) + (orQuit ? " before quitting?" : "?"), actions, apply,
            orQuit ? () => Qt.quit() : null, null, changeKeywords);
    }

    // Space u, or u with no change left to undo: lists the applies Koil can
    // undo, of every session (see history.rs), newest first, to pick from
    // (with the newer ones each needs, see Koil::undoable), the last one
    // picked; Yes undoes the picked ones. Those that can't be undone now say
    // why, and can't be picked. With `say` (Space u), it says so when
    // there's nothing to undo (u has already).
    function undoApply(say) {
        // Undo may have taken the listing back to before an update, which
        // Koil must see before anything can be undone.
        if (!updateListing())
            return;
        const r = JSON.parse(koil.history());
        if (r.message) {
            vim.showError(r.message);
            return;
        }
        if (!r.applies.length) {
            if (say)
                vim.showMessage("Nothing to undo");
            return;
        }
        vim.showMessage("");
        // The last apply picked, as u and Space u undo that.
        const applies = r.applies.map((a, i) => Object.assign({ picked: i === 0 }, a));
        const any = applies.some(a => !a.blocked);
        const question = (count, picked) => !any ? "Nothing can be undone now"
            : !count ? "Pick what to undo (Space)"
            : count === 1 && picked[0] ? "Undo the last apply?"
            : "Undo " + count + (count === 1 ? " apply?" : " applies?");
        confirmDialog.ask(question, applies, picked => {
            if (!picked.length)
                return;
            const spot = listingSpot();
            const u = JSON.parse(koil.undo(JSON.stringify(picked)));
            showListing(true, "", spot);
            report(u);
        }, null, null, changeKeywords);
    }

    // Where the cursor is in the listing (its line and column) and how far
    // it's scrolled, for showListing to keep when it shows the listing from
    // scratch (an apply, its undo, back from a file). The listing's cursor,
    // also while vim is in the path field.
    function listingSpot() {
        const t = editorView.textArea.text;
        const p = activeView === editorView ? vim.cursor : editorView.saved?.cursor ?? 0;
        return {
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

    // :set hidden, gitignore, regex, sort or sortreverse. As in koil-cli,
    // the listing is read with the settings it was shown with, and then
    // shown with the new ones.
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
        // Nothing to write: :wq and ZZ quit as :q does.
        if (scratchpad) {
            if (quit)
                quitApp(orQuit);
            else
                vim.showMessage("The scratchpad isn't saved: it's kept until Koil quits");
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

    // Save As in the scratchpad: writes its text to the file `path`, and
    // opens that in its place, as File > Open would, with the cursor and
    // the view where they were. The scratchpad keeps its text.
    function saveScratch(path) {
        if (!doc.saveNewFile(path, editorView.textArea.text))
            return;
        const cursor = vim.cursor;
        const contentY = editorView.flickable.contentY;
        openedFrom = "";
        readFile(path);
        if (scratchpad)
            return;
        // Before vim's cursor, which then scrolls only if it's out of view.
        const f = editorView.flickable;
        f.contentY = Math.max(0, Math.min(contentY, f.contentHeight + f.bottomMargin - f.height));
        vim.jumpTo(cursor);
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

    // Saves a setting and uses it now: one of vimSettings, colorScheme or
    // confirmChanges.
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
        property string confirmChanges: "always"
        property bool number: false
        property bool relativeNumber: false
        // The dir Koil lists when no path is given (see Document.startDir),
        // read only at startup; empty for the home dir.
        property string startDir: ""
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
        // "Open in Koil" in Finder (see watchFinderService): Koil comes to
        // the front (macOS has launched it if it wasn't running), and opens
        // the folder as if it was dropped, unless a dialog is open.
        onFolderRequested: (path, error) => {
            if (root.visibility === Window.Minimized)
                root.showNormal();
            root.raise();
            root.requestActivate();
            if (error)
                vim.showError(error);
            else if (dropArea.enabled)
                Qt.callLater(root.openDropped, path);
        }
        Component.onCompleted: {
            watchFileOpens();
            watchFinderService();
        }
    }

    Koil {
        id: koil

        showHidden: vim.showHidden
        gitignore: vim.gitignore
        regex: vim.regex
        sort: vim.sort
        sortReverse: vim.sortReverse

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

    // Polls the dirs' sizes being counted (see pollSizes), and waits to
    // sort the listing by them.
    Timer {
        id: sizeTimer

        interval: 300
        repeat: true
        running: root.listing && (root.counting || root.sortedCounting)
        onTriggered: root.pollSizes()
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
            " a": "applyAsking",
            " u": "undoApply",
            "-": "parent",
            "<CR>": root.activeView === pathView ? "openPath" : "open",
            "<Tab>": "switch",
            "g.": "hidden",
            "gi": "gitignore",
            "gr": "regex",
            "_": "scratch"
        }, root.sortKeys, root.activeView === pathView ? {
            "<S-CR>": "update"
        } : {}) : root.filePath ? ({
                "-": "back"
            }) : root.scratchpad ? ({
                "-": "back",
                "_": "back"
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
        onSortChanged: root.settingChanged()
        onSortReverseChanged: root.settingChanged()
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
    // Koil's options beside it, which g., gi and gr toggle too, and the
    // sort menu's button (gs).
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
            // Checked while the listing isn't sorted as by default.
            IconButton {
                id: sortButton

                theme: theme
                iconPath: "M2 4 H14 M2 8 H10 M2 12 H6"
                checked: vim.sort !== "name" || vim.sortReverse
                tip: qsTr("Sort")
                shortcuts: ["gs"]
                onClicked: root.toggleSortMenu()
            }
        }
    }

    // What gs and a key sort by, under the sort button, while gs waits for
    // the key (the button types gs too). A click on one sorts by it.
    SortMenu {
        id: sortMenu

        theme: theme
        sorts: root.sorts
        sort: vim.sort
        reverse: vim.sortReverse
        visible: root.listing && /gs$/.test(vim.pendingKeys)
        anchor: sortButton
        onPicked: key => vim.startCommand(["g", "s", key])
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
        infos: root.listing ? root.infos : ({})
        busyInfos: root.listing ? root.busyInfos : ({})
        infoDots: root.infoDots
        onActivated: root.activate(editorView)
        onEdited: {
            // The scratchpad is never saved, so there's nothing to ask about.
            if (!root.scratchpad)
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

        // Whether it had the keys as it closed: if something else took
        // them (see keepHelpKeys), that keeps them.
        property bool hadKeys

        theme: theme
        defaultFontFamily: root.defaultFontFamily
        onAboutToHide: hadKeys = !root.activeFocusItem || holds(root.activeFocusItem)
        onClosed: {
            if (hadKeys)
                root.activeView.textArea.forceActiveFocus();
        }
    }

    // :confirm q with unsaved changes, and applying the listing's changes
    // (or undoing them).
    ConfirmDialog {
        id: confirmDialog

        theme: theme
        system: system
        onClosed: root.activeView.textArea.forceActiveFocus()
    }

    SettingsWindow {
        id: settingsWindow

        app: root
        settings: settings
        theme: theme
        document: doc
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
            if (root.scratchpad) {
                root.saveScratch(path);
                return;
            }
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
                    enabled: !root.boxOpen
                    shortcut: StandardKey.Open
                    onTriggered: root.openFile()
                }
                Platform.MenuItem {
                    text: qsTr("Open Folder…")
                    enabled: !root.boxOpen
                    shortcut: "Ctrl+Shift+O"
                    onTriggered: folderDialog.open()
                }
                // In the listing, Cmd+S updates; applying is its own item,
                // which always asks first, as Space a does.
                Platform.MenuItem {
                    text: root.listing ? qsTr("Update") : qsTr("Save")
                    enabled: !root.boxOpen
                    shortcut: StandardKey.Save
                    onTriggered: root.listing ? root.updateListing() : root.save()
                }
                Platform.MenuItem {
                    text: qsTr("Apply Changes…")
                    enabled: root.listing && !root.boxOpen
                    onTriggered: root.applyChanges(false, false, true)
                }
                Platform.MenuItem {
                    text: qsTr("Save As…")
                    enabled: !root.listing && !root.boxOpen
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
                    enabled: !confirmDialog.opened
                    shortcut: StandardKey.Find
                    onTriggered: root.find(false)
                }
                Platform.MenuItem {
                    text: qsTr("Replace")
                    enabled: !confirmDialog.opened
                    shortcut: "Ctrl+Alt+F" // Cmd+Option+F, as in VS Code
                    onTriggered: root.find(true)
                }
                Platform.MenuItem {
                    text: qsTr("Find Next")
                    enabled: !confirmDialog.opened
                    shortcut: StandardKey.FindNext
                    onTriggered: root.findNext(1)
                }
                Platform.MenuItem {
                    text: qsTr("Find Previous")
                    enabled: !confirmDialog.opened
                    shortcut: StandardKey.FindPrevious
                    onTriggered: root.findNext(-1)
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
                    enabled: !root.boxOpen
                    shortcut: StandardKey.Open
                    onTriggered: root.openFile()
                }
                Action {
                    text: qsTr("Open &Folder…")
                    enabled: !root.boxOpen
                    shortcut: "Ctrl+Shift+O"
                    onTriggered: folderDialog.open()
                }
                Action {
                    text: root.listing ? qsTr("&Update") : qsTr("&Save")
                    enabled: !root.boxOpen
                    shortcut: StandardKey.Save
                    onTriggered: root.listing ? root.updateListing() : root.save()
                }
                Action {
                    text: qsTr("A&pply Changes…")
                    enabled: root.listing && !root.boxOpen
                    onTriggered: root.applyChanges(false, false, true)
                }
                Action {
                    text: qsTr("Save &As…")
                    enabled: !root.listing && !root.boxOpen
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
                    enabled: !confirmDialog.opened
                    shortcut: StandardKey.Find
                    onTriggered: root.find(false)
                }
                Action {
                    text: qsTr("&Replace")
                    enabled: !confirmDialog.opened
                    shortcut: StandardKey.Replace // Ctrl+H, as in VS Code
                    onTriggered: root.find(true)
                }
                // F3, plus Ctrl+G from findNextShortcut. Written out, since
                // an Action takes only the first of a StandardKey's keys.
                Action {
                    text: qsTr("Find &Next")
                    enabled: !confirmDialog.opened
                    shortcut: "F3"
                    onTriggered: root.findNext(1)
                }
                Action {
                    text: qsTr("Find &Previous")
                    enabled: !confirmDialog.opened
                    shortcut: "Shift+F3"
                    onTriggered: root.findNext(-1)
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

        enabled: !root.isMac && !confirmDialog.opened
        sequence: "Ctrl+G"
        onActivated: root.findNext(1)
    }
    Shortcut {
        enabled: !root.isMac && !confirmDialog.opened
        sequence: "Ctrl+Shift+G"
        onActivated: root.findNext(-1)
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
        // lists, and with nothing given, the dir the Settings window's
        // "Start in" says (which, like the path field, can't be a file), else
        // the home dir.
        const arg = doc.startupPath();
        const start = arg || doc.startDir(settings.startDir);
        if (arg && doc.isFile(arg)) {
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
