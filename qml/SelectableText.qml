import QtQuick

// Text that can be selected and copied, but never takes the keys, which
// stay with the box it's in (which forwards Copy): the hover box's, :help's
// and a question's.
TextEdit {
    required property Theme theme

    readOnly: true
    selectByMouse: true
    activeFocusOnPress: false
    persistentSelection: true
    selectionColor: theme.highlight
    selectedTextColor: theme.highlightedText

    HoverHandler {
        cursorShape: Qt.IBeamCursor
    }
}
