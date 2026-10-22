pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs

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
    // The parts of the pattern in the path field (see Editor.pathSyntax), and
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
    // was in the path field when it opened, to go back there, or the file
    // it opened over, to go back to, as it was left: { path, text, buffer,
    // contentY, unedited, modified, openedFrom, fileSpot }, or null.
    property bool scratchpad: false
    property var scratchState: null
    property bool scratchFromPath: false
    property var scratchFromFile: null
    // A file's unsaved changes, or the listing's edits and changes that
    // aren't applied: only while the text isn't what it was (see
    // checkModified), so not once an edit is taken back (`a` typed and
    // deleted).
    property bool modified: false
    // The text of a file as it was opened or last saved, or of the listing
    // (with its hidden text) as it was last shown, as { text, hidden },
    // which `modified` compares the editor's with. Null when that isn't
    // known (see mergeListing).
    property var unedited: null
    // Whether the listing had changes that aren't applied when it was last
    // shown (koil.hasChanges()), which make it modified whatever its text.
    property bool pendingChanges: false
    // Whether something changed on disk that the listing may not show yet
    // (see syncListing), and whether what goes against the user's edits is
    // being asked about.
    property bool diskChanged: false
    property bool askingConflicts: false
    // The shell command running (see runShell), which vim waits for: {
    // line, filter, scratch }, or null.
    property var shellRun: null
    // A box over the editor that has the keys (:help, or a question), a
    // shell command vim waits for, or a :s or the find bar's replace field
    // showing what it would do in the buffer (see Vim.previewSubstitute,
    // Vim.previewReplacements), while which the menu can't open, save or
    // edit anything, and the listing doesn't sync (see also keepHelpKeys).
    readonly property bool boxOpen: help.opened || confirmDialog.opened || shellRun !== null || vim.previewing
    // A question is open, which the Edit menu waits for (see MacMenuBar).
    readonly property bool asking: confirmDialog.opened
    // :set wrap, which View > Word Wrap toggles.
    property alias wordWrap: vim.wrap
    // While :e reads the file again (see reloadFile): what the status line
    // then says (none if ""), else null.
    property var reloading: null
    // How the file shown changed on disk, still to be dealt with (see
    // checkFile): "changed", "gone", or "".
    property string fileChange: ""
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
    // "never". The other settings in use are vim's, and shellEnvironment.
    property string confirmChanges: settings.confirmChanges
    // Whether :! runs commands in the environment read from the user's
    // shell, on macOS (see shell.rs's `environment`), which is read once,
    // as Koil starts or the setting is turned on.
    property bool shellEnvironment: settings.shellEnvironment

    onShellEnvironmentChanged: {
        if (shellEnvironment)
            system.loadShellEnvironment();
    }
    // The settings vim keeps, which :set changes (see changeSetting).
    readonly property var vimSettings: ["fontSize", "fontFamily", "number", "relativeNumber", "syntax", "wrap", "shell",
        "dirsFirst"]
    // The shell :! runs commands in when the shell setting is empty: $SHELL,
    // or cmd.exe on Windows.
    readonly property string systemShell: system.defaultShell()
    // The user's shortcuts (see ShortcutsWindow), as saved: { name, keys,
    // macro, mode, enabled }, where `keys` are those that run it, written
    // as Vim.commandKeys' are (" c" is Space c, "gc"; "" for none), `macro`
    // the keys it runs (as a register's text), and `mode` "normal",
    // "visual" or "both".
    readonly property var shortcuts: readShortcuts(settings.shortcuts)
    // Koil's own keys (see Vim.commandKeys), which the shortcuts' list
    // shows under the user's, to run but not to change, as { keys, name,
    // mode, where }: where they work, if not everywhere. No shortcut can
    // have them, start with them, or be their start (in the same mode), so
    // gs, which stands for the sort keys after it, keeps them all.
    readonly property var ownShortcuts: [
        { keys: "  ", name: qsTr("Apply the changes (in a file, save)"), mode: "normal", where: "" },
        { keys: " a", name: qsTr("Apply, listing the changes first"), mode: "normal", where: qsTr("Listing") },
        { keys: " u", name: qsTr("List the applies to undo"), mode: "normal", where: qsTr("Listing") },
        { keys: " r", name: (isMac ? qsTr("Show the entry in Finder") : Qt.platform.os === "windows"
            ? qsTr("Show the entry in Explorer") : qsTr("Show the entry in the file manager"))
            + qsTr(" (in a file, the file)"), mode: "normal", where: "" },
        { keys: " o", name: qsTr("Open the entry in its default app (in a file, the file)"), mode: "normal",
            where: "" },
        { keys: " q", name: qsTr("List your shortcuts"), mode: "both", where: "" },
        { keys: "<CR>", name: qsTr("Open the dir or file on the line"), mode: "normal", where: qsTr("Listing") },
        { keys: "<S-CR>", name: qsTr("Update, staying in the path field"), mode: "normal",
            where: qsTr("Path field") },
        { keys: "-", name: qsTr("The dir above (in a file, back to the listing)"), mode: "normal", where: "" },
        { keys: "<Tab>", name: qsTr("Go between the listing and the path field"), mode: "normal",
            where: qsTr("Listing") },
        { keys: "g.", name: qsTr("Toggle hidden entries"), mode: "normal", where: qsTr("Listing") },
        { keys: "gi", name: qsTr("Toggle hiding what git ignores"), mode: "normal", where: qsTr("Listing") },
        { keys: "gr", name: qsTr("Toggle reading the path as a regex"), mode: "normal", where: qsTr("Listing") },
        { keys: "gs", name: qsTr("Sort the listing, by the key after it"), mode: "normal", where: qsTr("Listing") },
        { keys: "_", name: qsTr("The scratchpad (in it, back)"), mode: "normal", where: "" },
        { keys: "!", name: qsTr("Run a shell command on the entry"), mode: "normal", where: "" }
    ]
    // The keys Koil's menus (and the editor's copy, paste and undo) take
    // before vim gets them, as vim names them (see Vim.tokenFor: Cmd on
    // macOS, Ctrl elsewhere, with Shift only for Cmd), which no shortcut
    // can have, as ownShortcuts are, but which the list doesn't show.
    readonly property var menuShortcuts: {
        const key = (k, name) => ({ keys: "<" + (isMac ? "D" : "C") + "-" + k + ">", name: name, mode: "both",
            where: "" });
        const both = [key("o", qsTr("Open…")), key("s", qsTr("Save")), key("q", qsTr("Quit")), key("f", qsTr("Find")),
            key("g", qsTr("Find Next")), key("z", qsTr("Undo")), key("c", qsTr("Copy"))];
        return both.concat(isMac ? [key("O", qsTr("Open Folder…")), key("S", qsTr("Save As…")),
            key(",", qsTr("Settings…")), key("G", qsTr("Find Previous")), key("=", qsTr("Zoom In")),
            key("+", qsTr("Zoom In")), key("-", qsTr("Zoom Out")), key("0", qsTr("Actual Size")),
            key("Z", qsTr("Redo")), key("x", qsTr("Cut")), key("v", qsTr("Paste")), key("a", qsTr("Select All")),
            key("h", qsTr("Hide Koil"))] : [key("h", qsTr("Replace…"))]);
    }
    // Whether the shortcuts' list shows Koil's own under the user's (saved).
    property bool showOwnShortcuts: settings.showOwnShortcuts

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
    // The file shown is watched for changes on disk (see checkFile).
    onFilePathChanged: {
        fileChange = "";
        doc.watchFile(filePath);
    }

    // Shows `text` as a new document, whose icons hide the texts in
    // `entries` (see Hidden text in Vim.qml). `path` is its file, if any:
    // before the text, which is colored as it goes in, by the comments the
    // file's name says it can have (see Editor.filePath).
    function load(text, entries, path) {
        keepScratch();
        activate(editorView);
        filePath = path;
        editorView.setText(text);
        vim.reset(entries);
        markUnedited();
        editorView.textArea.forceActiveFocus();
    }

    // Takes what the editor has as unedited (see `unedited`): a file opened
    // or saved, or the listing shown.
    function markUnedited() {
        unedited = { text: editorView.textArea.latest.text, hidden: listing ? editorView.hidden : null };
        modified = listing && pendingChanges;
    }

    // Whether the editor's text isn't `unedited`'s. The texts are compared
    // only if they're as long, and by System (V4's `===` hashes all of
    // both), and the hidden text only if they're the same.
    function isEdited() {
        const u = unedited, users = usersText(), t = users.text;
        if (!u || t.length !== u.text.length || !system.sameText(t, u.text))
            return true;
        const h = users.hidden, was = u.hidden;
        return !!was && h !== was && (h.length !== was.length
            || h.some((e, i) => e.at !== was[i].at || e.icon !== was[i].icon || e.text !== was[i].text));
    }

    // The editor's text and hidden text, as { text, hidden }, without a
    // preview of what a :s or the find bar would make of it (see
    // Vim.substitution), which isn't the user's change.
    function usersText() {
        const s = vim.substitution, before = s && s.before;
        return before && activeView === editorView ? before
            : { text: editorView.textArea.latest.text, hidden: editorView.hidden };
    }

    // Works out `modified` after an edit. The scratchpad is never saved, so
    // there's nothing to ask about.
    function checkModified() {
        if (!scratchpad)
            modified = listing && pendingChanges || isEdited();
    }

    // Shows a file that was read, leaving the listing (whose edits Koil
    // keeps, if they can be read).
    function loadFile(text, path) {
        if (reloading !== null) {
            const t = editorView.textArea.latest.text, p = vim.cursor;
            const line = Txt.lineOf(t, p), column = Txt.column(t, p);
            vim.replaceText(text, []);
            const u = editorView.textArea.latest.text;
            vim.jumpTo(Txt.atColumn(u, Txt.lineToPos(u, line), column));
            markUnedited();
            if (reloading)
                vim.showMessage(reloading);
            return;
        }
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

    // _ in the listing or a file: the scratchpad, a text of the user's
    // that's never saved, as it was left (its cursor, undo history and
    // view: see keepScratch), until Koil quits. Like a file, it leaves the
    // listing (whose edits Koil keeps), and _ or - goes back to where the
    // cursor was (see leaveFile), or to the file, as it was left.
    function openScratch() {
        if (!listing || updateListing())
            showScratch();
    }

    // The scratchpad, once Koil has the listing's edits (see openScratch;
    // at startup, there are none yet), or over the file, which it keeps as
    // it is, unsaved changes and all (see askToSave and quitCommand, which
    // ask about them).
    function showScratch() {
        if (listing)
            fileSpot = listingSpot();
        scratchFromPath = listing && activeView === pathView;
        scratchFromFile = filePath ? {
            path: filePath,
            text: editorView.textArea.latest.text,
            buffer: vim.leaveBuffer(),
            contentY: editorView.flickable.contentY,
            unedited: unedited,
            modified: modified,
            openedFrom: openedFrom,
            fileSpot: fileSpot
        } : null;
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
    // the editor goes through showListing or load), for openScratch. The
    // file it opened over is shown again (see backToFile), or else left.
    function keepScratch() {
        if (!scratchpad)
            return;
        scratchState = {
            text: editorView.textArea.latest.text,
            buffer: vim.leaveBuffer(),
            contentY: editorView.flickable.contentY
        };
        scratchpad = false;
        scratchFromFile = null;
    }

    // _ or - in the scratchpad opened over a file: the file `file` (see
    // scratchFromFile), as it was left: its unsaved changes, cursor, undo
    // history and view. What changed on disk meanwhile is then read again,
    // or asked about (see checkFile), as the file wasn't watched.
    function backToFile(file) {
        load(file.text, [], file.path);
        unedited = file.unedited;
        modified = file.modified;
        openedFrom = file.openedFrom;
        fileSpot = file.fileSpot;
        // Before vim's cursor, which then scrolls only if it's out of view.
        const f = editorView.flickable;
        f.contentY = Math.max(0, Math.min(file.contentY, f.contentHeight + f.bottomMargin - f.height));
        vim.enterBuffer(file.buffer);
        updatePathSyntax();
        checkFile();
    }

    // The scratchpad's text, shown or kept (see keepScratch), as the user
    // has it (see usersText).
    function scratchText() {
        return scratchpad ? usersText().text : scratchState ? scratchState.text : "";
    }

    // Opens the file `path` (see loadFile), from the entry `from` of the
    // listing (see openedFrom), or says in the status line why it can't, as
    // vim does (a picture isn't text).
    function readFile(path, from) {
        openedFrom = from || "";
        const error = doc.openFile(path);
        if (error)
            vim.showError(error);
    }

    // Lists the dir (or pattern) `path`: File > Open Folder, and at startup.
    // The cursor goes to the entry `from`, if given. False if it can't be
    // opened (the status line says why).
    function openFolder(path, from) {
        if (listing)
            return updateListing(path, from);
        const r = JSON.parse(koil.open(path));
        if (!r.ok) {
            vim.showError(r.message);
            return false;
        }
        showListing(true, from || "");
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
    // stays instead (scrolling only to show the cursor). Then the entries
    // that were marked stay marked (see Vim.markTexts), wherever they go.
    // Vim stays in the path field if it was there.
    function showListing(moved, from, keep) {
        // Before it's the listing, whose prefixes vim would keep out of.
        keepScratch();
        // Vim's :set options, as one typed in a file left them: nothing of
        // the listing shown before is read now.
        const warning = moved ? koil.takeSettings() : "";
        const r = JSON.parse(koil.render());
        if (listing && !keep && (!moved || r.path === location))
            keep = listingSpot();
        const sort = vim.sort + (vim.sortReverse ? " reversed" : "") + (vim.dirsFirst ? "" : " mixed");
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
        vim.markTexts(keep?.marks ?? []);
        const i = from ? r.names.indexOf(from) : -1;
        const line = i >= 0 ? i : keep ? keep.line : 0;
        const column = keep ? keep.column : 0; // 0: jumpTo puts it after the icon and two spaces
        const f = editorView.flickable, t = editorView.textArea.text;
        const ls = Txt.lineToPos(t, Math.min(line + 1, Txt.countLines(t)));
        const y = !keep ? f.contentY : resorted ? keep.contentY : editorView.cellAt(ls).y - keep.offset;
        // Before jumpTo, which then scrolls only if the line is out of view.
        // Entries that came or went above it don't move it.
        if (y !== f.contentY)
            f.contentY = Math.max(0, Math.min(y, f.contentHeight + f.bottomMargin - f.height));
        vim.jumpTo(Txt.atColumn(t, ls, column));
        showPath(r.path);
        pendingChanges = koil.hasChanges();
        markUnedited();
        checkListing();
        updatePendingLines();
        updatePathSyntax(true);
        if (inPath)
            activate(pathView);
        koil.watch();
        if (warning)
            vim.showMessage(warning);
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
    // changed, and shows the listing again, with the cursor on the entry
    // `from` if given. False if it can't (the problems and the status line
    // say why).
    function updateListing(open, from) {
        // Not a preview (a :s's, the find bar's): the text as it was.
        vim.endPreview();
        const r = JSON.parse(koil.update(pathView.textArea.text, editorView.textArea.text, JSON.stringify(editorView.hidden), open || ""));
        if (!r.ok) {
            if (r.problems.length)
                problems = r.problems;
            if (r.pathProblems.length)
                pathProblems = r.pathProblems;
            vim.showError(r.message);
            return false;
        }
        showListing(r.moved, from || r.from);
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
    // the listing modified: unedited, it's still unedited, but edited, what
    // it would be without the edits isn't known, so it stays modified until
    // it's shown again.
    function mergeListing(merge, undoable) {
        if (!merge.edits.length)
            return;
        iconColors = Object.assign({}, iconColors, merge.colors);
        const inPath = activeView === pathView, wasEdited = isEdited();
        activate(editorView);
        vim.mergeEdits(merge.edits, undoable);
        if (inPath)
            activate(pathView);
        if (undoable)
            checkModified();
        else if (wasEdited)
            unedited = null;
        else
            markUnedited();
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
            pendingChanges = pendingChanges || koil.hasChanges();
            checkModified();
            koil.watch();
        }, null, () => Qt.callLater(askConflicts, questions.slice(1)));
    }

    // Finds the parts of the pattern in the path field again, if the path
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

    // Koil's keys in the listing and the path field, and the few in a file
    // (see Vim.commandKeys).
    function runKeyCommand(name, count) {
        if (name.startsWith("sort")) {
            sortBy(name.split(":")[1], name.startsWith("sortReverse"));
            return;
        }
        const commands = {
            update: () => updateListing(),
            apply: () => applyChanges(false),
            save: () => save(false),
            applyAsking: () => applyChanges(false, true),
            undoApply: () => undoApply(),
            reveal: () => reveal(),
            openInApp: () => openInApp(),
            parent: () => goUp(count),
            open: () => openLine(count),
            openPath: () => openPath(),
            switch: () => activate(activeView === pathView ? editorView : pathView),
            hidden: () => vim.showHidden = !vim.showHidden,
            gitignore: () => vim.gitignore = !vim.gitignore,
            regex: () => vim.regex = !vim.regex,
            back: () => leaveFile(false, count),
            scratch: () => scratchpad ? leaveFile(false) : openScratch(),
            shell: () => bangLines(count),
            shortcuts: () => openShortcuts(true)
        };
        if (commands[name])
            commands[name]();
    }

    // !: the command line for a shell command on what % stands for (see
    // runShell), with the cursor before it: :!| %. With a count, or on the
    // marked lines, the range of those lines (as many as there are from
    // the cursor's), with a % for their entries in the listing (see
    // Vim.bangEntries), but elsewhere for vim's filter, as g! types it.
    function bangLines(count) {
        if (vim.marked.length) {
            vim.commandOnMarked(true, vim.bangEntries);
        } else if (count && activeView !== pathView) {
            const t = activeView.textArea.latest.text;
            const more = Math.min(count - 1, Txt.countLines(t) - Txt.lineOf(t, vim.cursor));
            vim.openBang(more ? ".,.+" + more : ".", vim.bangEntries);
        } else {
            vim.openBang("", true);
        }
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

    // -: `count` levels up, where a pattern is a level of its own (see
    // Koil.up), on the entry it came from: the listing's cursor's, also
    // from the path field.
    function goUp(count) {
        const t = editorView.textArea.text;
        const p = activeView === editorView ? vim.cursor : editorView.saved?.cursor ?? 0;
        const up = JSON.parse(koil.up(t, JSON.stringify(editorView.hidden), Txt.lineOf(t, p) - 1, count));
        updateListing(up.open, up.from);
    }

    // Enter in the listing: opens the dir or file on the cursor's line. On a
    // line without an entry it's vim's Enter.
    function openLine(count) {
        if (!openEntry())
            vim.runMotion("<CR>", count);
    }

    // Opens the dir or file on the cursor's line in the listing (Enter, gf),
    // creating a new file first. False if the line has no entry.
    function openEntry() {
        const t = editorView.textArea.text, line = Txt.lineOf(t, vim.cursor) - 1;
        const target = JSON.parse(koil.targetOnLine(t, JSON.stringify(vim.hidden), line));
        if (!target) {
            return false;
        } else if (target.error !== undefined) {
            vim.showError(target.error);
        } else if (target.dir !== undefined) {
            updateListing(target.dir);
        } else if (target.new !== undefined) {
            createFile(target.new);
        } else {
            // The file on disk, even if the line renames it; loadFile updates
            // the listing first.
            readFile(target.file.path, target.file.name);
        }
        return true;
    }

    // gf and gx (see Vim.linkRequested), and a click with Cmd on a link
    // (see clickLink). In the listing, the entry on the cursor's line: gf
    // opens it as Enter does, and gx as Space o (from the path field, gf
    // opens the path, and gx the open dir). In a file or the scratchpad,
    // the link at `at` (see linkTargetAt), or `text`, what visual mode
    // selected (see link.rs): gf opens a file or dir in Koil, as a drop
    // does, and gx in its default app, and either opens a URL in the
    // browser. A relative path is the file's dir's, or else the open dir's.
    function openLink(at, text, external) {
        if (listing) {
            if (external)
                openInApp();
            else if (activeView === pathView)
                openPath();
            else if (!openEntry())
                vim.showError("No entry on this line");
            return;
        }
        const target = text ? JSON.parse(system.linkTarget(text, linkDirs()))
            : linkTargetAt(editorView.textArea.text, at);
        if (target.error !== undefined) {
            vim.showError(target.error);
        } else if (target.url !== undefined) {
            if (!Qt.openUrlExternally(target.url))
                vim.showError("Can't open “" + target.url + "”");
        } else if (external) {
            const why = system.openInApp(target.path);
            if (why)
                vim.showError(why);
        } else {
            openDropped(target.path);
        }
    }

    // What gf opens at `at` in a file's or the scratchpad's text `t`, as
    // System.linkTarget gives it: on a line with an entry pasted with its
    // ID, wherever `at` is, where that is on disk, as <cfile> and the
    // listing's gf take it (see Koil.pastedEntry); else the URL or path
    // there, or the file name there or after it, as vim's gf takes it.
    function linkTargetAt(t, at) {
        const ls = Txt.lineStart(t, at), le = Txt.lineEnd(t, at), line = t.slice(ls, le);
        const entry = JSON.parse(koil.pastedEntry(line, JSON.stringify(vim.hiddenIn(vim.hidden, ls, le))));
        if (entry.message)
            return { error: entry.message };
        if (entry.path)
            return { path: entry.path };
        const span = JSON.parse(system.linkAt(line, at - ls, true));
        return JSON.parse(system.linkTarget(span ? line.slice(span.start, span.end) : "", linkDirs()));
    }

    // Where a relative path in a file or the scratchpad is looked for, in
    // turn: the file's dir, then the open dir, as vim's `path` (.,,).
    function linkDirs() {
        return (filePath ? [doc.dirOf(filePath)] : []).concat([koil.currentDir()]);
    }

    // A click with Cmd on a link in the editor (see Editor.link), on the
    // character `at`: the cursor goes there, and it opens as gf opens it.
    function clickLink(at) {
        if (boxOpen)
            return;
        vim.jumpTo(at);
        openLink(at, "", false);
    }

    // Space r and Space o: what % stands for in a shell command: where the
    // entry on the cursor's line is on disk, even if the line renames it,
    // or from the path field, the open dir, and in a file, the file; or
    // else "", once the status line says why there's none (the scratchpad
    // isn't on disk).
    function entryPath() {
        if (!listing) {
            if (!filePath)
                vim.showError("The scratchpad isn't a file on disk");
            return filePath;
        }
        const t = editorView.textArea.text;
        const line = activeView === pathView ? -1 : Txt.lineOf(t, vim.cursor) - 1;
        const r = JSON.parse(koil.pathOnLine(t, JSON.stringify(vim.hidden), line));
        if (r.message)
            vim.showError(r.message);
        return r.path;
    }

    // Space r: shows the entry on the cursor's line (the file, in one) in
    // Finder (Explorer on Windows).
    function reveal() {
        const path = entryPath();
        const why = path && system.reveal(path);
        if (why)
            vim.showError(why);
    }

    // Space o: opens the entry on the cursor's line (the file, in one) as a
    // double-click in Finder (Explorer) does: a file in its default app.
    function openInApp() {
        const path = entryPath();
        const why = path && system.openInApp(path);
        if (why)
            vim.showError(why);
    }

    // :!command, and with a range (see Vim.shellRequested): runs it in the
    // shell (:set shell), in the dir Koil has open, while vim waits for it
    // (Esc stops it), then shows what it wrote (see shellDone). % is the
    // entry on the cursor's line (from the path field, the open dir), or
    // the file: in the scratchpad, its own, which its text is written to
    // first (see Document.writeScratchpad), and read back from after. And
    // <cfile> is the path written on the cursor's line (see
    // Koil.writtenPaths), or in the listing, as %, its entry. A range is
    // filtered: its lines go through the command (without their
    // prefixes), whose output replaces them; but one with <cfile>, or in
    // the listing with %, is run on the range's entries (or paths)
    // instead, which they stand for. With `scratch` (:_!), the output goes
    // in the scratchpad instead (see showInScratch), and a filter's lines
    // only go through it. A range of marked lines (with `lines`) is only
    // those, as if they were together.
    function runShell(command, range, scratch) {
        const t = activeView.textArea.latest.text;
        // A % and a <cfile> that aren't escaped (\%, \<cfile>: see
        // shell::expand).
        const percent = /(^|[^\\])%/.test(command);
        const cfile = /(^|[^\\])<cfile>/.test(command);
        const onLines = cfile || percent && listing;
        const filter = !!range && !onLines;
        // A file's last line break ends its last line, as in vim: the empty
        // line after it isn't one to filter (:%!sort would sort it first).
        const end = Txt.countLines(t), past = l => l === end && t.endsWith("\n");
        const last = filter && range.last > range.first && past(range.last) ? range.last - 1 : range && range.last;
        // The marked lines it's for (see Vim.exRange), from 1.
        const lines = range && range.lines ? range.lines.filter((l, i) => i === 0 || !filter || !past(l)) : null;
        // The lines % stands for the entries on, as spans of lines from 0.
        const line = Txt.lineOf(t, vim.cursor) - 1;
        const spans = filter || !range ? [[line, line]] : lines ? lineSpans(lines) : [[range.first - 1, range.last - 1]];
        const hidden = JSON.stringify(editorView.hidden);
        // What they stand for, as { paths, message } (why there are none).
        const none = { paths: [], message: "" };
        const found = !onLines ? none
            : listing ? JSON.parse(koil.pathsOnLines(editorView.textArea.latest.text, hidden,
                JSON.stringify(activeView === pathView ? [] : spans)))
            : JSON.parse(koil.linksOnLines(t, hidden, JSON.stringify(spans),
                range ? -1 : vim.cursor - Txt.lineStart(t, vim.cursor), linkDirs()));
        const scratchFile = percent && scratchpad ? doc.writeScratchpad(t) : "";
        // It couldn't be written (the status line says why).
        if (percent && scratchpad && !scratchFile)
            return;
        const file = listing ? found : { paths: scratchFile ? [scratchFile] : filePath ? [filePath] : [], message: "" };
        const request = JSON.stringify({
            shell: vim.shell || systemShell,
            command: command,
            cwd: koil.currentDir(),
            file: file,
            cfile: cfile ? found : none,
            input: filter ? vim.filterInput(range.first, last, lines) : null,
            scratchpad: scratch,
            environment: shellEnvironment
        });
        // Koil takes the listing's edits before leaving it for the
        // scratchpad, as _ does: before the command runs, after which they
        // might not read (an entry it deleted).
        if (scratch && listing && !updateListing())
            return;
        const r = JSON.parse(system.runShell(request));
        if (r.error) {
            vim.showError(r.error);
            return;
        }
        shellRun = {
            line: r.line,
            filter: filter && !scratch ? { first: range.first, last: last, lines: lines, text: t, view: activeView,
                listing: listing, path: filePath, scratchpad: scratchpad } : null,
            scratch: scratch,
            // What it may change on disk that's shown, unless its output
            // goes in place of the text: the scratchpad's file, which it
            // was written to, or the file (see afterShell).
            disk: filter || scratch || listing ? null : scratchFile || (scratchpad ? null : filePath)
        };
        vim.showMessage((scratch ? ":_!" : ":!") + r.line);
        vim.waiting = "Running";
    }

    // Line numbers (from 1, in order) as spans of lines from 0, [first,
    // last], of those next to each other.
    function lineSpans(lines) {
        const spans = [];
        for (const l of lines) {
            const last = spans[spans.length - 1];
            if (last && last[1] === l - 2)
                last[1] = l - 1;
            else
                spans.push([l - 1, l - 1]);
        }
        return spans;
    }

    // The command runShell started is done: `ran` is what it did (see
    // shell::Ran). A failed one says why in the status line, which stops
    // a macro running it.
    function shellDone(ran) {
        const run = shellRun, title = (run.scratch ? ":_!" : ":!") + run.line;
        shellRun = null;
        const exit = ran.code === 0 ? "" : ran.code === null ? "killed" : "shell returned " + ran.code;
        const f = run.filter;
        if (ran.stopped) {
            vim.showMessage("Interrupted");
        } else if (ran.error) {
            vim.showError(ran.error);
        } else if (run.scratch) {
            // A macro that ran it goes on in the scratchpad.
            vim.endWait(false, () => showInScratch(title, ran.output, exit));
            return;
        } else if (!f) {
            showOutput(title, ran.output, ran.cut, exit);
        } else if (exit) {
            // The lines stay.
            showOutput(title, ran.errors, ran.cut, exit);
        } else if (activeView !== f.view || listing !== f.listing || filePath !== f.path || scratchpad !== f.scratchpad
                || f.view.textArea.latest.text !== f.text) {
            vim.showError("The text changed while the command ran, so its output wasn't put in");
        } else {
            vim.filterLines(f.first, f.last, ran.output, f.lines);
            if (ran.errors)
                showOutput(title, ran.errors, ran.cut, "");
        }
        vim.endWait(ran.stopped, run.disk ? () => afterShell(run.disk) : null);
    }

    // What the command that's done may have changed on disk (`path`): the
    // scratchpad's file, whose text goes in place of the scratchpad's (as
    // `!echo hi >> %` writes it), or the file's (see checkFile), as a change
    // `u` takes back, before a macro that ran it goes on.
    function afterShell(path) {
        if (!scratchpad)
            checkFile(true);
        else if (doc.fileChange(path) === "changed")
            vim.replaceTextKeeping(doc.readScratchpad());
    }

    // The file shown changed on disk (see Document.watchFile), or a shell
    // command may have changed it (`now`, see afterShell): it's read again,
    // in place of its text, as a change `u` takes back (see reloadFile),
    // but if it has unsaved changes, only once the user says so. Not while
    // they're halfway through something (it waits), but after a command,
    // at once, so a macro that ran it goes on with what it made. Gone, it
    // has unsaved changes: its text isn't on disk.
    function checkFile(now) {
        if (listing || scratchpad || !filePath) {
            fileChange = "";
            return;
        }
        fileChange = doc.fileChange(filePath) || fileChange;
        if (!fileChange)
            return;
        const busy = boxOpen || vim.running || vim.inserting || vim.isVisual || vim.commandLine !== "";
        if (busy && !(now && (fileChange === "gone" || !modified))) {
            fileTimer.start();
            return;
        }
        const change = fileChange;
        fileChange = "";
        if (change === "gone") {
            unedited = null;
            checkModified();
            vim.showError("“" + fileName + "” isn't on disk any more");
        } else if (!modified) {
            reloadFile(now ? "" : "“" + fileName + "” changed on disk");
        } else {
            confirmDialog.ask("“" + fileName + "” changed on disk. Read it again, in place of your changes?",
                "Undo (u) brings them back.", () => reloadFile());
        }
    }

    // What :_! ran wrote (`text`), in place of the scratchpad's text, as a
    // change undo takes back, which shows it as _ does (from the listing,
    // Koil took its edits before it ran). Nothing changes if it wrote
    // nothing. `exit` says why it failed, if it did (see shellDone).
    function showInScratch(title, text, exit) {
        if (text && !scratchpad)
            showScratch();
        if (text)
            vim.replaceWhole(text);
        if (exit)
            vim.showError(title + " (" + exit + ")");
        else
            vim.showMessage(title);
    }

    // What a shell command wrote (`text`, and `cut` lines after it), and
    // why it failed (`exit`, like "shell returned 1"): in the status line,
    // if it's a line that fits there, else in a box over the editor (the
    // help's, where / searches it).
    function showOutput(title, text, cut, exit) {
        const failed = exit ? title + " (" + exit + ")" : "";
        if (!text) {
            if (failed)
                vim.showError(failed);
        } else if (!cut && !text.includes("\n") && statusLine.fits(text)) {
            if (exit)
                vim.showError(text);
            else
                vim.showMessage(text);
        } else {
            const notes = (exit ? [exit[0].toUpperCase() + exit.slice(1) + "."] : []).concat(cut
                ? [cut + (cut === 1 ? " more line" : " more lines") + " not shown: `:_!` puts all of it in "
                    + "the scratchpad (`_`)."] : []);
            help.showText(title, text, notes.join(" "));
            if (failed)
                vim.showError(failed);
        }
    }

    // The shells the Settings window offers: [{ name, path }].
    function shellChoices() {
        return JSON.parse(system.shells());
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
            readFile(target.path, target.name);
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
            { keywords: changeKeywords });
    }

    // Whether changing files asks first, as the confirmChanges setting
    // says: always, only if something is deleted, or never.
    function asksFirst(deletes) {
        return confirmChanges === "always" || confirmChanges === "deleting" && deletes;
    }

    // `-` in a file: back to the listing it was opened from, or else its
    // dir's, with the cursor on its entry, which is a level up, so with a
    // `count` over 1 (`3-`), the others go up from there (see goUp).
    // Unsaved changes are saved (or dropped) first, if the user says so.
    // From the scratchpad (also _, with no count), back to where the cursor
    // was, in the path field if it was there, or to the file it opened over
    // (see backToFile), which is a level too, so `3-` is `-` twice more
    // from there.
    function leaveFile(force, count) {
        if (!force && !scratchpad) {
            askToSave(() => leaveFile(true, count));
            return;
        }
        if (scratchpad && scratchFromFile) {
            backToFile(scratchFromFile);
            if (count > 1)
                leaveFile(false, count - 1);
            return;
        }
        if (scratchpad) {
            showListing(true, "", fileSpot);
            if (scratchFromPath)
                activate(pathView);
            if (count > 1)
                goUp(count - 1);
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
        if (count > 1)
            goUp(count - 1);
    }

    // Applies the listing's changes once the user confirms them (Space
    // Space, Space a, File > Apply Changes…), those they leave picked (the
    // others are forgotten). When confirmChanges says not to ask
    // (asksFirst), it applies them all, unless `ask` is set (Space a, File
    // > Apply Changes…). With `quit` (:confirm q, ZZ), it always asks, then
    // quits, and No quits without applying; if the listing can't be read
    // (its errors, or a path that can't be opened), it asks to quit without
    // the changes, saying why (the status line's error, which updateListing
    // just showed).
    function applyChanges(quit, ask) {
        if (!updateListing()) {
            if (quit)
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
        if (!ask && !quit && !asksFirst(actions.some(a => a.deletes))) {
            apply(actions.map((a, i) => i));
            return;
        }
        // With none picked, Yes applies nothing, which forgets them all.
        const total = actions.length;
        const these = total === 1 ? "this change" : "these " + total + " changes";
        const what = picked => !picked ? "Discard " + these : picked === total ? "Apply " + these
            : "Apply " + picked + " of " + these;
        confirmDialog.ask(picked => what(picked) + (quit ? " before quitting?" : "?"), actions, apply,
            quit ? () => Qt.quit() : null, null, { keywords: changeKeywords });
    }

    // Space u: lists the applies Koil can undo, of every session (see
    // history.rs), newest first, to pick from (with the newer ones each
    // needs, see Koil::undoable), none picked, the first highlighted; Yes
    // undoes the picked ones, and Delete from History (d) forgets them,
    // once the user confirms it. Those that can't be undone now say why,
    // and can be picked only to delete them.
    function undoApply() {
        const applies = undoHistory();
        if (!applies)
            return;
        if (!applies.length) {
            vim.showMessage("Nothing to undo");
            return;
        }
        vim.showMessage("");
        const lines = applies.map(a => Object.assign({ picked: false }, a));
        const any = lines.some(a => !a.blocked);
        const question = (count, picked) => {
            const blocked = lines.filter((a, i) => a.blocked && picked[i]).length;
            return !count ? (any ? "Pick what to undo (Space)" : "Nothing can be undone now")
                : blocked ? (blocked < count ? blocked + " of the picked applies"
                    : count === 1 ? "The picked apply" : "The picked applies") + " can't be undone, only deleted"
                : count === 1 && picked[0] ? "Undo the last apply?"
                : "Undo " + count + (count === 1 ? " apply?" : " applies?");
        };
        confirmDialog.ask(question, lines, picked => {
            if (picked.length)
                undoPicked(picked);
        }, null, null, {
            keywords: changeKeywords,
            showRow: true,
            extra: { label: "(D)elete from History", key: Qt.Key_D, action: forgetApplies }
        });
    }

    // Forgets the applies `picked` (indexes into what `Koil.history`
    // gave), once the user confirms it, so they can't be undone.
    function forgetApplies(picked) {
        const one = picked.length === 1;
        const them = one ? "the picked apply" : picked.length + " applies";
        confirmDialog.ask("Delete " + them + " from the undo history? " + (one ? "It" : "They")
            + " can't be undone after that.", "", () => {
            koil.forgetHistory(JSON.stringify(picked));
            vim.showMessage((one ? "1 apply" : picked.length + " applies") + " deleted from the undo history");
        });
    }

    // u with no change left to undo: undoes the last apply alone (the
    // newest of every session), once the user confirms it, listing what
    // undoing it does. With nothing to undo it says nothing (u has already).
    function undoLast() {
        const applies = undoHistory();
        if (!applies?.length)
            return;
        const last = applies[0];
        if (last.blocked) {
            vim.showError("Can't undo: " + last.blocked);
            return;
        }
        vim.showMessage("");
        confirmDialog.ask("Undo the last apply?", last.steps.join("\n"), () => undoPicked([0]), null, null,
            { keywords: changeKeywords });
    }

    // The applies Koil can undo (`Koil.history`), newest first, or null if
    // the listing can't be read, or nothing can be undone now (which the
    // status line says why).
    function undoHistory() {
        // Undo may have taken the listing back to before an update, which
        // Koil must see before anything can be undone.
        if (!updateListing())
            return null;
        const r = JSON.parse(koil.history());
        if (r.message) {
            vim.showError(r.message);
            return null;
        }
        return r.applies;
    }

    // Undoes the applies `picked` (indexes into what `Koil.history` gave),
    // and shows the listing again where it was.
    function undoPicked(picked) {
        const spot = listingSpot();
        const u = JSON.parse(koil.undo(JSON.stringify(picked)));
        showListing(true, "", spot);
        report(u);
    }

    // Where the cursor is in the listing (its line and column) and how far
    // it's scrolled, for showListing to keep when it shows the listing from
    // scratch (an apply, its undo, back from a file), with how far down the
    // view its line starts (`offset`), and the IDs of the entries marked
    // (`marks`, see Vim.markedTexts). The listing's, also while vim is in
    // the path field.
    function listingSpot() {
        const t = editorView.textArea.text, inListing = activeView === editorView;
        const p = inListing ? vim.cursor : editorView.saved?.cursor ?? 0;
        const contentY = editorView.flickable.contentY;
        return {
            line: Txt.lineOf(t, p) - 1,
            column: Txt.column(t, p),
            contentY: contentY,
            offset: editorView.cellAt(Txt.lineStart(t, p)).y - contentY,
            marks: vim.markedTexts(inListing ? null : editorView.saved)
        };
    }

    // Shows what apply or undo did, `{ ok, message }`.
    function report(r) {
        if (r.ok)
            vim.showMessage(r.message);
        else
            vim.showError(r.message);
    }

    // :set hidden, gitignore, regex, sort, sortreverse or dirsfirst. As in
    // koil-cli, the listing is read with the settings it was shown with, and
    // then shown with the new ones. In a run (a macro's gss, -c's set
    // sort=size), vim waits for it, as a step of the run (see updateInRun).
    function settingChanged() {
        if (listing && vim.running) {
            vim.waiting = "Updating";
            Qt.callLater(updateInRun);
        } else if (listing) {
            Qt.callLater(updateListing);
        }
        // Even if the listing can't be read yet.
        Qt.callLater(updatePathSyntax, true);
    }

    // The update a run's setting asks for, as a step of it, so its next
    // keys have the listing sorted, and the update doesn't stop it, as it
    // did when the run's chunk ended before it (a startup's -c after the
    // layout of `set wrap`).
    function updateInRun() {
        vim.endWait(false, () => updateListing());
    }

    // Whether quitting would lose something: a file's unsaved changes, or
    // the listing's changes that aren't applied (which it reads first).
    function unsaved() {
        return listing ? !updateListing() || koil.hasChanges() : modified || koil.hasChanges();
    }

    // :q (see Vim.quitRequested): quits, unless what's open has unsaved
    // changes (E37), which with `confirm` (:confirm q) it asks about, and
    // `force` (:q!) drops, and with `all` (:qa!) the listing's changes
    // too. In the scratchpad opened over a file, it goes back to the file
    // first, whose unsaved changes it kept.
    function quitCommand(force, confirm, all) {
        if (force && all) {
            Qt.quit();
            return;
        }
        if (scratchpad && scratchFromFile)
            leaveFile(true);
        if (force || !unsaved()) {
            quitApp(false);
        } else if (!listing && !modified) {
            // The listing's changes, while a file is open.
            quitApp(confirm);
        } else if (confirm) {
            if (listing)
                applyChanges(true);
            else
                confirmDialog.ask("Save changes to “" + fileName + "”?", "", () => save(true, true), () => quitApp(true));
        } else {
            vim.showError("E37: No write since last change (add ! to override)");
        }
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
            applyChanges(true);
        else
            vim.showMessage("Not quitting: the listing has changes that aren't applied");
    }

    function openFile() {
        openDialog.open();
    }

    // Runs `open`, which shows something else in place of the file, once
    // the file's unsaved changes are saved or dropped, as the user says
    // (Cancel keeps the file open). At once in the listing, whose edits
    // Koil keeps. In the scratchpad, the file it opened over is asked
    // about (see showScratch), as it's left too.
    function askToSave(open) {
        const kept = scratchpad ? scratchFromFile : null;
        if (listing || !(kept ? kept.modified : modified)) {
            open();
            return;
        }
        const path = kept ? kept.path : filePath;
        confirmDialog.ask("Save changes to “" + path.split(/[\\/]/).pop() + "”?", "", () => {
            const text = kept ? kept.text : editorView.textArea.latest.text;
            if (!doc.saveFile(path, text))
                return;
            // Saved, even if what's opened next can't be.
            if (kept) {
                kept.unedited = { text: text, hidden: null };
                kept.modified = false;
            } else {
                markUnedited();
            }
            open();
        }, open);
    }

    // Opens a file or dir dropped on the window, as File > Open or Open
    // Folder would.
    function openDropped(path) {
        askToSave(() => {
            if (doc.isFile(path)) {
                readFile(path);
            } else {
                openFolder(path);
            }
        });
    }

    // :e path: opens the file at `path` (see Koil.fileAt), or else lists
    // the dir or pattern, read as the path field reads it, from the open
    // dir (vim's cwd), as a drop opens one: unsaved changes are asked about
    // first, unless `force` (:e!) drops them. Vim then edits the listing,
    // also from the path field, as Enter there goes to it, so a shortcut of
    // `:e ~/src<CR>` ends in the same place wherever it's run. :e alone
    // reads what's shown again: the listing (an update, which keeps its
    // edits, as Koil does), or the file, unless it has unsaved changes,
    // which :e! drops.
    function edit(path, force) {
        if (!path) {
            if (listing)
                updateListing();
            else if (!filePath)
                vim.showError("E32: No file name");
            else if (modified && !force)
                vim.showError("E37: No write since last change (add ! to override)");
            else
                reloadFile();
            return;
        }
        const file = koil.fileAt(path);
        const open = () => {
            if (file) {
                readFile(file);
            } else if (openFolder(path)) {
                // From the path field too, as Enter there does.
                activate(editorView);
            }
        };
        if (force)
            open();
        else
            askToSave(open);
    }

    // :e in a file (and as it changed on disk, see checkFile): reads it
    // from disk again, in place of its text as one change, so the cursor
    // stays on its line, the view stays, and `u` brings back what it had.
    // The status line then says `message`, if it isn't "", or else that
    // it was read again.
    function reloadFile(message) {
        reloading = message ?? "“" + fileName + "” read again";
        const error = doc.openFile(filePath);
        reloading = null;
        if (error)
            vim.showError(error);
    }

    // Saves the file (vim's E32 if there's none: nothing is shown), then
    // quits if `quit` is set and the save worked (see quitApp, which `orQuit` is
    // passed to). Nothing is written in the listing, whose changes only
    // Space Space and Space a apply (:w updates, as Cmd+S does), nor in the
    // scratchpad: there :wq and ZZ quit as :q and :confirm q do.
    function save(quit, orQuit) {
        if (listing || scratchpad) {
            if (quit)
                quitCommand(false, orQuit, false);
            else if (listing)
                updateListing();
            else
                vim.showMessage("The scratchpad isn't saved: it's kept until Koil quits");
            return;
        }
        if (!filePath) {
            vim.showError("E32: No file name");
            return;
        }
        if (doc.saveFile(filePath, editorView.textArea.latest.text)) {
            markUnedited();
            if (quit)
                quitApp(orQuit);
        }
    }

    function saveAs() {
        saveDialog.open();
    }

    // Save As in the scratchpad: writes its text to the file `path`, and
    // opens that in its place, as File > Open would, with the cursor and
    // the view where they were. The scratchpad keeps its text.
    function saveScratch(path) {
        if (!doc.saveNewFile(path, editorView.textArea.latest.text))
            return;
        const cursor = vim.cursor;
        const contentY = editorView.flickable.contentY;
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

    // Saves a setting and uses it now: one of vimSettings, colorScheme,
    // confirmChanges, shellEnvironment or showOwnShortcuts.
    function changeSetting(name, value) {
        (vimSettings.includes(name) ? vim : root)[name] = value;
        settings[name] = value;
    }

    // The shortcuts saved as `json` (see shortcuts), leaving out what isn't
    // one, as the settings can be edited by hand.
    function readShortcuts(json) {
        let list;
        try {
            list = JSON.parse(json);
        } catch (e) {
            return [];
        }
        return Array.isArray(list) ? list.filter(s => s && typeof s.macro === "string").map(s => ({
            name: typeof s.name === "string" ? s.name : "",
            keys: typeof s.keys === "string" ? s.keys : "",
            macro: s.macro,
            mode: ["normal", "visual", "both"].includes(s.mode) ? s.mode : "normal",
            enabled: s.enabled !== false
        })) : [];
    }

    // Saves the shortcuts, which vim then runs.
    function saveShortcuts(list) {
        settings.shortcuts = JSON.stringify(list);
    }

    // A shortcut as vim has it (see Vim.shortcuts).
    function vimShortcut(s) {
        return {
            keys: s.keys,
            macro: s.macro,
            label: s.keys ? vim.keysName(s.keys) : s.name || qsTr("Shortcut"),
            normal: s.mode !== "visual",
            visual: s.mode !== "normal"
        };
    }

    // A click in the shortcuts' list: runs the shortcut in the editor vim
    // edits, as its keys would (see Vim.runShortcut), or one of Koil's own
    // (`own`, of ownShortcuts) as if they were typed in normal mode, unless
    // a box over it has the keys or vim waits for a shell command.
    function runShortcut(s, own) {
        requestActivate();
        if (boxOpen || askingConflicts)
            return;
        activeView.textArea.forceActiveFocus();
        if (own)
            vim.startCommand(vim.macroKeys(s.keys));
        else
            vim.runShortcut(vimShortcut(s));
    }

    // Whether Koil's own `keys` (ownShortcuts') do something where vim is
    // now, in normal mode: they're one of commandKeys, or their start (gs).
    function commandHere(keys) {
        const ks = vim.macroKeys(keys);
        return Object.keys(vim.commandKeys).some(k => {
            const own = vim.macroKeys(k);
            return ks.length <= own.length && ks.every((t, i) => t === own[i]);
        });
    }

    // A shortcut's keys in parts, the names of keys apart (see
    // Vim.keyParts), one by one (Vim.macroKeys), and as Koil shows them
    // (Vim.keysName).
    function keyParts(text) {
        return vim.keyParts(text);
    }
    function keyTokens(text) {
        return vim.macroKeys(text);
    }
    function keysName(text) {
        return vim.keysName(text);
    }

    // A key typed in the shortcuts' window, as vim names it (see
    // Vim.tokenFor), or null.
    function keyToken(event) {
        return vim.tokenFor(event);
    }

    // What of vim's own keys a shortcut's take the place of (see
    // Vim.vimCommandIn).
    function vimCommandIn(text, visual) {
        return vim.vimCommandIn(text, visual);
    }

    // The macros recorded, which a shortcut can run (see Vim.macroList).
    function macroList() {
        return vim.macroList();
    }

    // The shortcuts' window. After a key (Space q), once it's up (or a
    // moment later, if the keys came from a macro): opened while it's
    // down, its release goes to the window, and macOS's text input, which
    // watches a held key for its accent menu, logs warnings
    // ("TSMSendMessageToUIServer: … FAILED").
    function openShortcuts(afterKey) {
        if (afterKey) {
            shortcutsAfterKey.restart();
        } else {
            shortcutsAfterKey.stop();
            shortcutsWindow.open();
        }
    }

    // A key let go in the editor: the shortcuts' window, if Space q waits
    // for it (see openShortcuts).
    function keyReleased() {
        if (shortcutsAfterKey.running) {
            shortcutsAfterKey.stop();
            Qt.callLater(openShortcuts, false);
        }
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
        // Whether files and the scratchpad are colored (:set syntax).
        property bool syntax: true
        // Whether long lines wrap (:set wrap).
        property bool wrap: false
        // Whether the listing has its dirs before its files, else sorted
        // with them (:set dirsfirst).
        property bool dirsFirst: true
        // The shell :! runs commands in: a path, or a name on the PATH;
        // empty for the system's (root.systemShell).
        property string shell: ""
        // Whether :! commands get the environment the user's shell sets
        // up (root.shellEnvironment), off at first, as reading it runs
        // their rc file.
        property bool shellEnvironment: false
        // The dir Koil lists when no path is given (see Document.startDir),
        // read only at startup; empty for the home dir.
        property string startDir: ""
        // The user's shortcuts, as JSON (see root.shortcuts).
        property string shortcuts: "[]"
        // Whether their list shows Koil's own too (root.showOwnShortcuts).
        property bool showOwnShortcuts: false
    }

    Theme {
        id: theme

        palette: editorView.textArea.palette
        font: editorView.textArea.font
        zoom: vim.fontSize / root.defaultFontSize
    }

    System {
        id: system

        onOpenFailed: message => vim.showError(message)
        onShellDone: result => root.shellDone(JSON.parse(result))
    }

    // -p on the command line prints the scratchpad's text as Koil quits,
    // however it does (:q, Cmd+Q, the window closed).
    Connections {
        target: Qt.application

        function onAboutToQuit() {
            doc.printScratchpad(root.scratchText());
        }
    }

    Document {
        id: doc

        onLoaded: (path, text) => root.loadFile(text, path)
        onFailed: message => vim.showError(message)
        onFileChanged: {
            if (!fileTimer.running)
                fileTimer.start();
        }
        // Finder's Open With on macOS (see watchFileOpens): opened as if
        // dropped on the window, and likewise not while a dialog is open.
        // Later, so Finder isn't kept waiting.
        onFileOpened: path => {
            if (dropArea.enabled)
                Qt.callLater(root.openDropped, path);
        }
        // "Open in Koil" in Finder (see watchFinderService): Koil comes to
        // the front (macOS has launched it if it wasn't running), and opens
        // the folder as if it was dropped, or a file's, on its entry, unless
        // a dialog is open.
        onFolderRequested: (path, file) => {
            if (root.visibility === Window.Minimized)
                root.showNormal();
            root.raise();
            root.requestActivate();
            if (!dropArea.enabled)
                return;
            if (file)
                Qt.callLater(() => root.askToSave(() => root.showFileDir(path)));
            else
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
        dirsFirst: vim.dirsFirst

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

    // Checks the file shown a moment after it changed on disk (once for a
    // burst of changes), and again until the user isn't halfway through
    // something (see checkFile).
    Timer {
        id: fileTimer

        interval: 100
        onTriggered: root.checkFile(false)
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
        bangEntries: root.listing
        clipboard: system
        fileName: root.listing ? root.location : root.filePath
        lineHeight: editorView.lineHeight
        charWidth: editorView.charWidth
        textTop: root.activeView.textTop
        number: settings.number
        defaultNumber: settings.number
        relativeNumber: settings.relativeNumber
        defaultRelativeNumber: settings.relativeNumber
        syntax: settings.syntax
        defaultSyntax: settings.syntax
        wrap: settings.wrap
        defaultWrap: settings.wrap
        dirsFirst: settings.dirsFirst
        defaultDirsFirst: settings.dirsFirst
        fontSize: settings.fontSize
        defaultFontSize: settings.fontSize
        minFontSize: root.minFontSize
        maxFontSize: root.maxFontSize
        fontFamily: settings.fontFamily
        defaultFontFamily: settings.fontFamily
        fontFamilies: root.fontFamilies
        shell: settings.shell
        defaultShell: settings.shell
        systemShell: root.systemShell
        // In the path field, Shift+Enter updates like Enter but stays
        // there; in the listing it's vim's Enter.
        commandKeys: root.listing ? Object.assign({
            "  ": "apply",
            " a": "applyAsking",
            " u": "undoApply",
            " r": "reveal",
            " o": "openInApp",
            " q": "shortcuts",
            "-": "parent",
            "<CR>": root.activeView === pathView ? "openPath" : "open",
            "<Tab>": "switch",
            "g.": "hidden",
            "gi": "gitignore",
            "gr": "regex",
            "_": "scratch",
            "!": "shell"
        }, root.sortKeys, root.activeView === pathView ? {
            "<S-CR>": "update"
        } : {}) : Object.assign({
            "  ": "save",
            " q": "shortcuts",
            "!": "shell"
        }, root.filePath ? {
            " r": "reveal",
            " o": "openInApp",
            "-": "back",
            "_": "scratch"
        } : root.scratchpad ? {
            " r": "reveal",
            " o": "openInApp",
            "-": "back",
            "_": "scratch"
        } : {})
        // With a selection too, so the list can run a shortcut on it.
        visualCommandKeys: ({
            " q": "shortcuts"
        })
        // The user's, which are on and have keys, everywhere.
        shortcuts: root.shortcuts.filter(s => s.enabled && s.keys && s.macro).map(root.vimShortcut)

        onFontFamiliesNeeded: root.loadFontFamilies()
        onWriteRequested: (quit, confirm) => root.save(quit, confirm)
        onQuitRequested: (force, confirm, all) => root.quitCommand(force, confirm, all)
        onKeyCommand: (name, count) => root.runKeyCommand(name, count)
        onLinkRequested: (at, text, external) => root.openLink(at, text, external)
        onEditRequested: (path, force) => root.edit(path, force)
        onShellRequested: (command, range, scratchpad) => root.runShell(command, range, scratchpad)
        onStopRequested: system.stopShell()
        onNothingToUndo: {
            if (root.listing && root.activeView === editorView)
                root.undoLast();
        }
        onShowHiddenChanged: root.settingChanged()
        onGitignoreChanged: root.settingChanged()
        onRegexChanged: root.settingChanged()
        onSortChanged: root.settingChanged()
        onSortReverseChanged: root.settingChanged()
        onDirsFirstChanged: root.settingChanged()
        // The text without the preview can change while the editor's
        // doesn't (the find bar's Replace from its replace field).
        onSubstitutionChanged: Qt.callLater(root.checkModified)
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
            onKeyReleased: root.keyReleased()
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
        filePath: root.filePath
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
        onKeyReleased: root.keyReleased()
        onLinkClicked: at => root.clickLink(at)
        onEdited: {
            if (root.listing) {
                checkTimer.restart();
                Qt.callLater(root.updatePendingLines);
                // Once vim has the hidden text of the editor's own edits
                // (typing: see trackEdit), which come after this.
                Qt.callLater(root.checkModified);
            } else {
                root.checkModified();
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
        enabled: !root.boxOpen && !root.askingConflicts

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

    ShortcutsWindow {
        id: shortcutsWindow

        app: root
        theme: theme
    }

    Timer {
        id: shortcutsAfterKey

        interval: 300
        onTriggered: shortcutsWindow.open()
    }

    footer: StatusLine {
        id: statusLine

        vim: vim
        theme: theme
    }

    FileDialog {
        id: openDialog

        fileMode: FileDialog.OpenFile
        onAccepted: {
            const path = doc.urlToPath(selectedFile);
            root.askToSave(() => {
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
            // Shown in its place, as File > Open shows one.
            if (root.scratchpad) {
                root.askToSave(() => root.saveScratch(path));
                return;
            }
            if (doc.saveFile(path, editorView.textArea.latest.text)) {
                root.filePath = path;
                root.markUnedited();
            }
        }
    }

    // The menus: macOS's own, or in the window elsewhere (see Component.onCompleted).
    Component {
        id: macMenuBar

        MacMenuBar {
            app: root
        }
    }

    Component {
        id: windowMenuBar

        WindowMenuBar {
            app: root
        }
    }

    // What the menus do, but for the window's functions.
    function openFolderDialog() {
        folderDialog.open();
    }

    function openSettings() {
        settingsWindow.open();
    }

    // About Koil: its version (for a bug report) and where it's from, in
    // the help's box.
    function about() {
        help.showPlain(qsTr("About Koil"), {
            title: "",
            intro: "Koil edits a directory as text, like oil.nvim, with vim's keys. `:h` shows the help.",
            keyColumns: 8,
            rows: [
                ["version", Qt.application.version],
                ["source", "`https://github.com/Barni228/koil`"]
            ]
        });
    }

    function actualSize() {
        vim.fontSize = settings.fontSize;
    }

    function saveOrUpdate() {
        if (listing)
            updateListing();
        else
            save();
    }

    // Windows / Linux: the menu's Zoom In is Ctrl+=; this keeps Ctrl++ too.
    // On macOS, StandardKey.ZoomIn already covers both.
    Shortcut {
        enabled: !root.isMac
        sequences: [StandardKey.ZoomIn]
        onActivated: root.zoom(1)
    }

    // Windows / Linux: the menu's Find Next and Find Previous are F3 and
    // Shift+F3; these add Ctrl+G and Ctrl+Shift+G, like Cmd+G on macOS.
    Shortcut {
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
        if (shellEnvironment)
            system.loadShellEnvironment();
        // Before any text is looked through (see Txt.lineIndex).
        Txt.compareStringsWith((a, b) => system.sameString(a, b));
        startUp();
        // The editor sits in a ScrollView, which is its own focus scope, so
        // `focus: true` alone doesn't give it the keyboard.
        editorView.textArea.forceActiveFocus();
    }

    // Shows what the command line says (see cli.rs). A file opens as a
    // file; anything else (a dir, a pattern) Koil lists, and with nothing
    // given, the dir the Settings window's "Start in" says (which, like the
    // path field, can't be a file), else the home dir. The scratchpad (-s,
    // or text from stdin) opens over that file or listing. +N puts the
    // cursor on line N of what's shown, and then -c's commands run (see
    // shown).
    function startUp() {
        const arg = doc.startupPath();
        const start = arg || doc.startDir(settings.startDir);
        const scratch = doc.startupScratchpad();
        const line = doc.startupLine();
        const file = arg && doc.isFile(arg);
        if (file) {
            // Once the editor is done: before its own onCompleted, it doesn't
            // have the line numbers' padding, and adding it then had Qt lay
            // out all of a long file again (100,000 lines took a second).
            Qt.callLater(() => {
                const error = doc.openFile(start);
                // One it can't read: its dir, on its entry, as `-` from it
                // would show, and why.
                if (error)
                    showFileDir(start);
                if (scratch) {
                    startScratch(error, line);
                    return;
                }
                if (error)
                    vim.showError(error);
                shown(error ? -1 : line);
            });
            return;
        }
        let error = "";
        if (!openFolder(start || doc.homeDir()) && start) {
            error = vim.message; // why, which openFolder showed
            if (openFolder(doc.homeDir()) && !scratch) {
                // One that isn't there: the home dir, with it in the path
                // field and why it can't be opened, to fix like one written
                // there.
                showPath(doc.shownPath(start));
                updatePathSyntax();
                updateListing();
            }
        }
        if (!scratch) {
            shown(line);
            return;
        }
        // Once the editor is done, as a file (a long text piped in). Back
        // from it, the path field shows the listing's path, not one that
        // can't be opened, so only the status line says why.
        Qt.callLater(() => startScratch(error, line));
    }

    // The scratchpad at startup (-s, or text from stdin), with that text,
    // over what's shown, then `error` (why what was asked for can't be
    // shown, if it can't) in the status line, and +N and -c (see shown).
    function startScratch(error, line) {
        scratchState = {
            text: doc.takeStartupText(),
            buffer: null,
            contentY: 0
        };
        showScratch();
        if (error)
            vim.showError(error);
        shown(line);
    }

    // What the command line asked for is shown: +N's line, if any (see
    // goToLine), then -c's commands, as a macro runs them, so a setting or
    // keys (`-c 'set sort=size'`, `-c 'norm G'`) apply to it, and Koil
    // needn't have an option for each.
    function shown(line) {
        goToLine(line);
        vim.runCommands(JSON.parse(doc.startupCommands()), "-c");
    }

    // Lists the dir the file `path` is in, on its entry, as `-` from it
    // would: at startup, and "Open in Koil" on a file (or an app, which
    // Finder shows as one, so it's a dir's).
    function showFileDir(path) {
        const name = path.split(/[\\/]/).pop();
        openFolder(doc.dirOf(path), doc.isDir(path) ? name + "/" : name);
    }

    // +N on the command line: the cursor on line `line` (the last for 0,
    // none for -1) in the middle of the view, as vim's.
    function goToLine(line) {
        if (line >= 0)
            vim.startCommand((line ? String(line).split("") : []).concat(["G", "z", "z"]));
    }

}
