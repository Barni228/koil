pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import Qt.labs.platform as Platform

import Koil

import "text.js" as Txt

// The app's window: the editor and its status line, Koil's listing, the find
// bar, the dialogs, the menus and the settings.
ApplicationWindow {
    id: root

    readonly property bool isMac: Qt.platform.os === "osx"
    property string filePath: ""
    readonly property string fileName: filePath ? filePath.split(/[\\/]/).pop() : "Untitled"
    // Whether the editor shows Koil's listing of `location`, rather than a
    // file.
    property bool listing: false
    property string location: ""
    // Koil's warnings and errors about the listing (see Editor.problems).
    property var problems: []
    // The colors of the icons the listings have shown (see
    // Editor.iconColors).
    property var iconColors: ({})
    // The parts of the regex on the path line (see Editor.pathSyntax), and
    // the line they're for.
    property var pathSyntax: []
    property string pathLine: ""
    // The listing's entry a file was opened from (with Enter), which `-`
    // goes back to; "" for a file opened otherwise.
    property string openedFrom: ""
    // A file's unsaved changes, or the listing's edits and changes that
    // aren't applied.
    property bool modified: false
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

    // Shows `text` as a new document, whose icons hide the texts in
    // `entries` (see Hidden text in Vim.qml). `path` is its file, if any.
    function load(text, entries, path) {
        editorView.setText(text);
        vim.reset(entries);
        filePath = path;
        modified = false;
        editorView.textArea.forceActiveFocus();
    }

    // Shows a file that was read, leaving the listing (whose edits Koil
    // keeps, if they can be read).
    function loadFile(text, path) {
        if (listing && !updateListing())
            return;
        listing = false;
        problems = [];
        load(text, [], path);
        updatePathSyntax();
    }

    // Lists the dir (or pattern) `path`: File > Open Folder, and at startup.
    function openFolder(path) {
        if (listing) {
            updateListing(path);
            return;
        }
        const r = JSON.parse(koil.open(path));
        if (!r.ok) {
            vim.showError(r.message);
            return;
        }
        showListing(true, "");
        if (r.message)
            vim.showMessage(r.message);
    }

    // Shows Koil's listing of what's open (see listing.rs). For the same
    // listing as before (`moved` false), the new text replaces the old as an
    // edit, which undo can take back, and the cursor stays on its line.
    // Otherwise it starts over: undo mustn't bring back another dir's
    // entries, which Koil would read as this one's. The cursor goes to the
    // entry `from` (the dir `-` came from), or else to the first one.
    function showListing(moved, from) {
        const r = JSON.parse(koil.render());
        iconColors = Object.assign({}, iconColors, r.colors);
        location = koil.location();
        let line, column;
        if (listing && !moved) {
            const t = editorView.textArea.text;
            line = Txt.lineOf(t, vim.cursor) - 1;
            column = Txt.column(t, vim.cursor);
            vim.replaceText(r.text, r.hidden);
        } else {
            listing = true;
            load(r.text, r.hidden, "");
            const i = from ? r.names.indexOf(from) : -1;
            line = Math.min(i >= 0 ? i : 2, r.names.length - 1);
            column = line >= 2 ? 3 : 0; // after the icon and two spaces
        }
        const t = editorView.textArea.text;
        const ls = Txt.lineToPos(t, Math.min(line, r.names.length - 1) + 1);
        vim.jumpTo(Txt.atColumn(t, ls, column));
        modified = koil.hasChanges();
        checkListing();
        updatePathSyntax(true);
    }

    // Reads the edited listing into Koil, then opens `open` (a dir, relative
    // to the open one) if given, else the path on the first line if it
    // changed, and shows the listing again. False if it can't (the problems
    // and the status line say why).
    function updateListing(open) {
        const r = JSON.parse(koil.update(editorView.textArea.text, JSON.stringify(vim.hidden), open || ""));
        if (!r.ok) {
            if (r.problems.length)
                problems = r.problems;
            vim.showError(r.message);
            return false;
        }
        showListing(r.moved, r.from);
        if (r.message)
            vim.showMessage(r.message);
        return true;
    }

    // Finds the parts of the regex on the path line again, if the line
    // changed (or `force`, when the regex setting did).
    function updatePathSyntax(force) {
        const t = editorView.textArea.text, nl = t.indexOf("\n");
        const line = listing ? (nl < 0 ? t : t.slice(0, nl)) : "";
        if (line === pathLine && !force)
            return;
        pathLine = line;
        pathSyntax = listing ? JSON.parse(koil.pathSyntax(line)) : [];
    }

    function checkListing() {
        checkTimer.stop();
        problems = listing ? JSON.parse(koil.check(editorView.textArea.text, JSON.stringify(vim.hidden))) : [];
    }

    // Koil's keys in the listing (see Vim.commandKeys).
    function runKeyCommand(name, count) {
        if (name === "update")
            updateListing();
        else if (name === "apply")
            applyChanges(false, false);
        else if (name === "parent")
            updateListing(Array(Math.max(count, 1)).fill("..").join("/"));
        else if (name === "open")
            openLine(count);
        else if (name === "back")
            leaveFile(false);
    }

    // Enter: opens the dir or file on the cursor's line, or the path on the
    // first line. On a line without an entry it's vim's Enter.
    function openLine(count) {
        const t = editorView.textArea.text, line = Txt.lineOf(t, vim.cursor) - 1;
        const target = line === 0 ? { dir: "" } : JSON.parse(koil.targetOnLine(t, JSON.stringify(vim.hidden), line));
        if (!target) {
            vim.runMotion("<CR>", count);
        } else if (target.dir !== undefined) {
            updateListing(target.dir);
        } else if (target.new !== undefined) {
            vim.showError("“" + target.new + "” isn't there until the changes are applied (Space a)");
        } else {
            // The file on disk, even if the line renames it; loadFile updates
            // the listing first.
            openedFrom = target.file.name;
            doc.openFile(target.file.path);
        }
    }

    // `-` in a file: back to the listing it was opened from, or else its
    // dir's, with the cursor on its entry. Unsaved changes are saved (or
    // dropped) first, if the user says so.
    function leaveFile(force) {
        if (modified && !force) {
            confirmDialog.ask("Save changes to “" + fileName + "”?", "", () => {
                if (doc.saveFile(filePath, editorView.textArea.text))
                    leaveFile(true);
            }, () => leaveFile(true));
            return;
        }
        if (!openedFrom) {
            const r = JSON.parse(koil.open(doc.dirOf(filePath)));
            if (!r.ok) {
                vim.showError(r.message);
                return;
            }
        }
        showListing(true, openedFrom || fileName);
    }

    // Applies the listing's changes once the user confirms them (Space a,
    // :w), then quits if `quit` is set. With `orQuit` (:confirm q, ZZ), No
    // quits without applying.
    function applyChanges(quit, orQuit) {
        if (!updateListing())
            return;
        const actions = JSON.parse(koil.actions());
        if (!actions.length) {
            if (quit)
                Qt.quit();
            else
                vim.showMessage("Nothing to apply");
            return;
        }
        const what = actions.length === 1 ? "this change" : "these " + actions.length + " changes";
        confirmDialog.ask("Apply " + what + (orQuit ? " before quitting?" : "?"), actions.join("\n"), () => {
            const r = JSON.parse(koil.apply());
            showListing(true, "");
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
            const u = JSON.parse(koil.undo());
            showListing(true, "");
            report(u);
        });
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
        onFailed: message => {
            errorDialog.text = message;
            errorDialog.open();
        }
    }

    Koil {
        id: koil

        showHidden: vim.showHidden
        gitignore: vim.gitignore
        regex: vim.regex
    }

    // Checks the listing for problems once typing stops for a moment.
    Timer {
        id: checkTimer

        interval: 200
        onTriggered: root.checkListing()
    }

    Vim {
        id: vim

        editor: editorView.textArea
        flickable: editorView.flickable
        clipboard: system
        lineHeight: editorView.lineHeight
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
        commandKeys: root.listing ? ({
                "  ": "update",
                " a": "apply",
                "-": "parent",
                "<CR>": "open"
            }) : root.filePath ? ({
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
            if (root.listing)
                root.undoApply();
        }
        onShowHiddenChanged: root.settingChanged()
        onGitignoreChanged: root.settingChanged()
        onRegexChanged: root.settingChanged()
        onHelpRequested: topic => {
            if (!help.show(topic))
                vim.showError("E149: Sorry, no help for " + topic);
        }
    }

    Editor {
        id: editorView

        anchors.fill: parent
        vim: vim
        findBar: findBar
        theme: theme
        system: system
        listing: root.listing
        iconColors: root.iconColors
        pathSyntax: root.pathSyntax
        problems: root.problems
        onEdited: {
            root.modified = true;
            if (root.listing) {
                checkTimer.restart();
                root.updatePathSyntax();
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
            editor: editorView.textArea
            vim: vim
            theme: theme
        }
    }

    HelpPanel {
        id: help

        theme: theme
        defaultFontFamily: root.defaultFontFamily
        onClosed: editorView.textArea.forceActiveFocus()
    }

    // :confirm q with unsaved changes, and applying the listing's changes
    // (or undoing them).
    ConfirmDialog {
        id: confirmDialog

        theme: theme
        onClosed: editorView.textArea.forceActiveFocus()
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
            elide: Text.ElideRight
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
            text: vim.pendingKeys + "    " + vim.positionLabel()
        }
    }

    FileDialog {
        id: openDialog

        fileMode: FileDialog.OpenFile
        onAccepted: {
            root.openedFrom = "";
            doc.openFile(doc.urlToPath(selectedFile));
        }
    }

    FolderDialog {
        id: folderDialog

        onAccepted: root.openFolder(doc.urlToPath(selectedFolder))
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

    MessageDialog {
        id: errorDialog

        buttons: MessageDialog.Ok
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
                Platform.MenuItem {
                    text: root.listing ? qsTr("Apply Changes…") : qsTr("Save")
                    shortcut: StandardKey.Save
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
                    text: root.listing ? qsTr("&Apply Changes…") : qsTr("&Save")
                    shortcut: StandardKey.Save
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
        if (start && doc.isFile(start))
            doc.openFile(start);
        else
            openFolder(start || doc.homeDir());
        // The editor sits in a ScrollView, which is its own focus scope, so
        // `focus: true` alone doesn't give it the keyboard.
        editorView.textArea.forceActiveFocus();
    }
}
