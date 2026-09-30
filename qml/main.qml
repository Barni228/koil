pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import Qt.labs.platform as Platform

import Koil

// The app's window: the editor and its status line, the find bar, the
// dialogs, the menus and the settings.
ApplicationWindow {
    id: root

    readonly property bool isMac: Qt.platform.os === "osx"
    property string filePath: ""
    readonly property string fileName: filePath ? filePath.split(/[\\/]/).pop() : "Untitled"
    property bool modified: false
    // Quit once the Save dialog has saved the file (:wq, or Save in the
    // :confirm q dialog, for a file that has no path yet).
    property bool quitAfterSave: false
    readonly property int defaultFontSize: 16
    readonly property int minFontSize: 6
    readonly property int maxFontSize: 72
    readonly property string defaultFontFamily: isMac ? "Menlo" : "Consolas"
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
    title: fileName + (modified ? " •" : "") + " — Koil"

    // Shows `text` as a new document, whose icons hide the texts in
    // `entries` (see Hidden text in Vim.qml). `path` is its file, if any.
    function load(text, entries, path) {
        editorView.setText(text);
        vim.reset(entries);
        filePath = path;
        modified = false;
        editorView.textArea.forceActiveFocus();
    }

    // Shows a listing (see Document.listing): each line is an icon, which
    // hides some text, then two spaces and the line's text.
    function showListing(lines) {
        let text = "";
        const entries = [];
        lines.forEach((line, i) => {
            if (i > 0)
                text += "\n";
            entries.push({
                at: text.length,
                icon: line.icon,
                text: line.hidden
            });
            text += line.icon + "  " + line.text;
        });
        load(text, entries, "");
    }

    function openFile() {
        openDialog.open();
    }

    // Saves the file, asking for a path if it has none, then quits if
    // `quit` is set and the save worked.
    function save(quit) {
        if (!filePath) {
            saveAs();
            quitAfterSave = !!quit;
            return;
        }
        if (doc.saveFile(filePath, editorView.textArea.text)) {
            modified = false;
            if (quit)
                Qt.quit();
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

    // Changes a setting now and saves it: one of vimSettings, or colorScheme.
    function changeSetting(name, value) {
        (vimSettings.includes(name) ? vim : root)[name] = value;
        settings[name] = value;
    }

    // Saves a setting vim changed (the zoom or :set), if keepChanges says to.
    function keepChange(name) {
        if (settings.keepChanges)
            settings[name] = vim[name];
    }

    // The saved settings. The Settings window changes them along with the
    // ones in use; the zoom and :set change them only with keepChanges, and
    // otherwise just for this session.
    Settings {
        id: settings

        property int fontSize: root.defaultFontSize
        property string fontFamily: root.defaultFontFamily
        property string colorScheme: "system"
        property bool number: false
        property bool relativeNumber: false
        property bool keepChanges: false

        // Turning it on saves what's in use, as if it had been on.
        onKeepChangesChanged: {
            if (keepChanges)
                root.vimSettings.forEach(name => root.keepChange(name));
        }
    }

    Connections {
        target: vim

        function onFontSizeChanged() {
            root.keepChange("fontSize");
        }
        function onFontFamilyChanged() {
            root.keepChange("fontFamily");
        }
        function onNumberChanged() {
            root.keepChange("number");
        }
        function onRelativeNumberChanged() {
            root.keepChange("relativeNumber");
        }
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

        onLoaded: (path, text) => root.load(text, [], path)
        onFailed: message => {
            errorDialog.text = message;
            errorDialog.open();
        }
    }

    Vim {
        id: vim

        editor: editorView.textArea
        flickable: editorView.flickable
        clipboard: system
        lineHeight: editorView.lineHeight
        number: settings.number
        relativeNumber: settings.relativeNumber
        fontSize: settings.fontSize
        defaultFontSize: root.defaultFontSize
        minFontSize: root.minFontSize
        maxFontSize: root.maxFontSize
        fontFamily: settings.fontFamily
        defaultFontFamily: root.defaultFontFamily
        fontFamilies: root.fontFamilies

        onFontFamiliesNeeded: root.loadFontFamilies()
        onWriteRequested: quit => root.save(quit)
        onQuitRequested: (force, confirm) => {
            if (force || !root.modified)
                Qt.quit();
            else if (confirm)
                confirmDialog.ask("Save changes to “" + root.fileName + "”?");
            else
                vim.showError("E37: No write since last change (add ! to override)");
        }
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
        onEdited: root.modified = true
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
        onClosed: editorView.textArea.forceActiveFocus()
    }

    // :confirm q with unsaved changes.
    ConfirmDialog {
        id: confirmDialog

        theme: theme
        onYes: root.save(true)
        onNo: Qt.quit()
        onClosed: editorView.textArea.forceActiveFocus()
    }

    SettingsWindow {
        id: settingsWindow

        app: root
        vim: vim
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
        onAccepted: doc.openFile(doc.urlToPath(selectedFile))
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
                    Qt.quit();
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
                    text: qsTr("Save")
                    shortcut: StandardKey.Save
                    onTriggered: root.save()
                }
                Platform.MenuItem {
                    text: qsTr("Save As…")
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
                    onTriggered: vim.fontSize = root.defaultFontSize
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
                    text: qsTr("&Save")
                    shortcut: StandardKey.Save
                    onTriggered: root.save()
                }
                Action {
                    text: qsTr("Save &As…")
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
                    onTriggered: vim.fontSize = root.defaultFontSize
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
        const startup = doc.startupFile();
        if (startup)
            doc.openFile(startup);
        else
            showListing(JSON.parse(doc.listing()));
        // The editor sits in a ScrollView, which is its own focus scope, so
        // `focus: true` alone doesn't give it the keyboard.
        editorView.textArea.forceActiveFocus();
    }
}
