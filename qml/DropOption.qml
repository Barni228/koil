import QtQuick
import QtQuick.Controls

// An option in a DropList, in the accent color while it's `lit` (the
// pointer on it, or the one Return takes). A file of its own, not an
// inline component of DropList: DropList.qml's `ComponentBehavior: Bound`
// binds those to it, and Qt makes none from another file, so the lists
// were empty.
AbstractButton {
    id: option

    required property Theme theme
    property bool lit: hovered

    width: ListView.view.width
    implicitHeight: 24 * theme.zoom
    focusPolicy: Qt.NoFocus
    hoverEnabled: true

    background: Rectangle {
        radius: 3 * option.theme.zoom
        color: option.lit ? option.theme.accent : "transparent"
    }
}
