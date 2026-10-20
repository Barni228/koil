pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

// A box over the window that has the keys until it's closed, with the
// window dimmed behind it: :help and the questions.
Popup {
    id: box

    required property Theme theme
    readonly property real zoom: theme.zoom

    parent: Overlay.overlay
    anchors.centerIn: parent
    padding: 16 * zoom
    modal: true
    focus: true

    Overlay.modal: Rectangle {
        color: box.theme.dark ? "#60000000" : "#30000000"
    }

    background: Panel {
        theme: box.theme
        raised: true
    }
}
