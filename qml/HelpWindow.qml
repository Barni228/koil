pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

// The help in a window of its own, for what asks for it while a box has
// the keys (a question's list, with ? or its ? button): :h's box would
// take the box's place, and this leaves it open, with the help beside it.
// It's a tool window, which floats over Koil's other windows, so going
// back to the box doesn't put it behind the main window. All it has is a
// HelpPanel that fills it, the same help as :h's, with its keys, which
// closes with it (q, Esc): a box in a window, until the help's text is a
// view both can show.
Window {
    id: win

    // main.qml's window, which it goes beside.
    required property var app
    required property Theme theme
    // The font Koil ships, for the help's :set guifont.
    property string defaultFontFamily

    readonly property real zoom: theme.zoom
    // Whether it was shown before: then it's where the user left it.
    property bool placed: false

    // Shows the help with `topic`'s section unfolded (see HelpPanel.show),
    // or all of it folded if there's none for it, and gives it the keys.
    function open(topic) {
        if (!placed) {
            place();
            placed = true;
        }
        show();
        raise();
        requestActivate();
        if (!panel.show(topic))
            panel.show("");
    }

    // Beside the main window, on its right, or its left, where its screen
    // has the room; else over its right side, at the screen's edge.
    function place() {
        const gap = 8, screen = app.screen;
        const left = screen.virtualX, right = left + screen.width;
        width = Math.round(620 * zoom);
        height = Math.round(Math.max(360 * zoom, Math.min(app.height, 760 * zoom)));
        let to = app.x + app.width + gap;
        if (to + width > right)
            to = app.x - width - gap;
        if (to < left)
            to = Math.max(left, right - width - gap);
        x = to;
        y = app.y;
    }

    title: qsTr("Koil Help")
    flags: Qt.Tool
    color: theme.panel
    minimumWidth: Math.round(420 * zoom)
    minimumHeight: Math.round(240 * zoom)
    onVisibleChanged: {
        if (!visible)
            panel.close();
    }

    HelpPanel {
        id: panel

        theme: win.theme
        defaultFontFamily: win.defaultFontFamily
        // All of the window, with nothing behind it to dim or to click.
        anchors.centerIn: undefined
        x: 0
        y: 0
        width: win.width
        height: win.height
        dim: false
        closePolicy: Popup.CloseOnEscape
        background: Rectangle {
            color: win.theme.panel
        }
        onClosed: win.close()

        // In the box, as a modal one keeps the window's own shortcuts
        // from running; and only while this window has the keys (see
        // ShortcutsWindow.focused).
        Shortcut {
            sequences: [StandardKey.Close]
            enabled: win.activeFocusItem !== null
            onActivated: win.close()
        }
    }
}
