import QtQuick
import QtQuick.Controls

// The menus on Windows and Linux: a menu bar in the window, with the items
// MacMenuBar has on macOS.
MenuBar {
    id: menus

    // The window (main.qml), which has what the items do.
    required property var app

    Menu {
        title: qsTr("&File")

        Action {
            text: qsTr("&Open…")
            enabled: !menus.app.boxOpen
            shortcut: StandardKey.Open
            onTriggered: menus.app.openFile()
        }
        Action {
            text: qsTr("Open &Folder…")
            enabled: !menus.app.boxOpen
            shortcut: "Ctrl+Shift+O"
            onTriggered: menus.app.openFolderDialog()
        }
        Action {
            text: menus.app.listing ? qsTr("&Update") : qsTr("&Save")
            enabled: !menus.app.boxOpen
            shortcut: StandardKey.Save
            onTriggered: menus.app.saveOrUpdate()
        }
        Action {
            text: qsTr("A&pply Changes…")
            enabled: menus.app.listing && !menus.app.boxOpen
            onTriggered: menus.app.applyChanges(false, false, true)
        }
        Action {
            text: qsTr("Save &As…")
            enabled: !menus.app.listing && !menus.app.boxOpen
            shortcut: StandardKey.SaveAs
            onTriggered: menus.app.saveAs()
        }
        MenuSeparator {}
        Action {
            text: qsTr("Se&ttings")
            // Preferences and Quit have no Ctrl binding on Windows.
            shortcut: "Ctrl+,"
            onTriggered: menus.app.openSettings()
        }
        Action {
            text: qsTr("S&hortcuts…")
            onTriggered: menus.app.openShortcuts(false)
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
            enabled: !menus.app.asking
            shortcut: StandardKey.Find
            onTriggered: menus.app.find(false)
        }
        Action {
            text: qsTr("&Replace")
            enabled: !menus.app.asking
            shortcut: StandardKey.Replace // Ctrl+H, as in VS Code
            onTriggered: menus.app.find(true)
        }
        // F3, plus Ctrl+G from main.qml's Shortcut. Written out, since
        // an Action takes only the first of a StandardKey's keys.
        Action {
            text: qsTr("Find &Next")
            enabled: !menus.app.asking
            shortcut: "F3"
            onTriggered: menus.app.findNext(1)
        }
        Action {
            text: qsTr("Find &Previous")
            enabled: !menus.app.asking
            shortcut: "Shift+F3"
            onTriggered: menus.app.findNext(-1)
        }
    }
    Menu {
        title: qsTr("&View")

        Action {
            text: qsTr("Zoom &In")
            // StandardKey.ZoomIn is only Ctrl++ (Ctrl+Shift+=) here;
            // main.qml's Shortcut adds that.
            shortcut: "Ctrl+="
            onTriggered: menus.app.zoom(1)
        }
        Action {
            text: qsTr("Zoom &Out")
            shortcut: StandardKey.ZoomOut
            onTriggered: menus.app.zoom(-1)
        }
        Action {
            text: qsTr("&Actual Size")
            shortcut: "Ctrl+0" // no StandardKey for this
            onTriggered: menus.app.actualSize()
        }
        MenuSeparator {}
        // As on macOS (see MacMenuBar).
        Action {
            text: qsTr("&Word Wrap")
            shortcut: "Alt+Z"
            checkable: true
            checked: menus.app.wordWrap
            onTriggered: {
                menus.app.wordWrap = checked;
                checked = Qt.binding(() => menus.app.wordWrap);
            }
        }
    }
}
