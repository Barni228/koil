import QtQuick
import Qt.labs.platform as Platform

// The menus on macOS: its native menu bar. The Quit and Preferences roles
// have Qt move those items into the app's ("Koil") menu. WindowMenuBar has
// the same items elsewhere.
Platform.MenuBar {
    id: menus

    // The window (main.qml), which has what the items do.
    required property var app

    Platform.Menu {
        title: qsTr("File")

        Platform.MenuItem {
            text: qsTr("Open…")
            enabled: !menus.app.boxOpen
            shortcut: StandardKey.Open
            onTriggered: menus.app.openFile()
        }
        Platform.MenuItem {
            text: qsTr("Open Folder…")
            enabled: !menus.app.boxOpen
            shortcut: "Ctrl+Shift+O"
            onTriggered: menus.app.openFolderDialog()
        }
        // In the listing, Cmd+S updates; applying is its own item,
        // which always asks first, as Space a does.
        Platform.MenuItem {
            text: menus.app.listing ? qsTr("Update") : qsTr("Save")
            enabled: !menus.app.boxOpen
            shortcut: StandardKey.Save
            onTriggered: menus.app.saveOrUpdate()
        }
        Platform.MenuItem {
            text: qsTr("Apply Changes…")
            enabled: menus.app.listing && !menus.app.boxOpen
            onTriggered: menus.app.applyChanges(false, true)
        }
        Platform.MenuItem {
            text: qsTr("Save As…")
            enabled: !menus.app.listing && !menus.app.boxOpen
            shortcut: StandardKey.SaveAs
            onTriggered: menus.app.saveAs()
        }
        Platform.MenuItem {
            text: qsTr("Settings…")
            role: Platform.MenuItem.PreferencesRole
            shortcut: StandardKey.Preferences
            onTriggered: menus.app.openSettings()
        }
        // In the app menu, under Settings.
        Platform.MenuItem {
            text: qsTr("Shortcuts…")
            role: Platform.MenuItem.ApplicationSpecificRole
            onTriggered: menus.app.openShortcuts(false)
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
            enabled: !menus.app.asking
            shortcut: StandardKey.Find
            onTriggered: menus.app.find(false)
        }
        Platform.MenuItem {
            text: qsTr("Replace")
            enabled: !menus.app.asking
            shortcut: "Ctrl+Alt+F" // Cmd+Option+F, as in VS Code
            onTriggered: menus.app.find(true)
        }
        Platform.MenuItem {
            text: qsTr("Find Next")
            enabled: !menus.app.asking
            shortcut: StandardKey.FindNext
            onTriggered: menus.app.findNext(1)
        }
        Platform.MenuItem {
            text: qsTr("Find Previous")
            enabled: !menus.app.asking
            shortcut: StandardKey.FindPrevious
            onTriggered: menus.app.findNext(-1)
        }
    }
    Platform.Menu {
        title: qsTr("View")

        Platform.MenuItem {
            text: qsTr("Zoom In")
            shortcut: StandardKey.ZoomIn
            onTriggered: menus.app.zoom(1)
        }
        Platform.MenuItem {
            text: qsTr("Zoom Out")
            shortcut: StandardKey.ZoomOut
            onTriggered: menus.app.zoom(-1)
        }
        Platform.MenuItem {
            text: qsTr("Actual Size")
            shortcut: "Ctrl+0" // no StandardKey; Qt maps Ctrl to Cmd
            onTriggered: menus.app.actualSize()
        }
        Platform.MenuSeparator {}
        // :set wrap, until Koil quits, as :set is. It toggles itself
        // before it's triggered, which unbinds it.
        Platform.MenuItem {
            text: qsTr("Word Wrap")
            shortcut: "Alt+Z" // Option+Z, as in VS Code
            checkable: true
            checked: menus.app.wordWrap
            onTriggered: {
                menus.app.wordWrap = checked;
                checked = Qt.binding(() => menus.app.wordWrap);
            }
        }
    }
}
