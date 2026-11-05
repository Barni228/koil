import QtQuick

// Text that can be selected and copied, but never takes the keys, which
// stay with the box it's in (which forwards Copy): the hover box's, K's,
// :help's and a question's.
// Given `system` (main.qml's System), Koil lays its text out, as the
// editor's (see setLineFormat in native.h): rows that wrap break after a
// space or where a word starts or ends, and with `listing` (lines that start
// with a box and two spaces), never after the box alone, the rest of a line
// under its text. Then `naturalWidth` is how wide it is unwrapped, which
// implicitWidth isn't (Qt has that from its own layout only).
TextEdit {
    id: selectable

    required property Theme theme
    property var system: null
    property bool listing: false
    readonly property real naturalWidth: system ? measured : implicitWidth
    property real measured: 0
    property bool measuring: false

    // naturalWidth, once the text, its font or its layout are new: but not
    // as its own new width (a box as wide as naturalWidth) lays the text out
    // again, which can't change how wide it is unwrapped. Bound to
    // contentHeight, that was a binding loop.
    function measure() {
        if (!system || measuring)
            return;
        measuring = true;
        measured = system.layoutWidth(textDocument) + leftPadding + rightPadding;
        measuring = false;
    }

    // Rows as tall as the font's lines (a line height of 0), and no line too
    // long to lay out (see longLength in Editor.qml).
    function useLayout() {
        system?.setLineFormat(selectable, 0, 0, 0, listing, 1 << 30);
        measure();
    }

    readOnly: true
    selectByMouse: true
    activeFocusOnPress: false
    persistentSelection: true
    selectionColor: theme.highlight
    selectedTextColor: theme.highlightedText
    onListingChanged: useLayout()
    onSystemChanged: useLayout()
    onTextChanged: measure()
    onFontChanged: measure()
    onContentHeightChanged: measure()
    Component.onCompleted: useLayout()

    HoverHandler {
        cursorShape: Qt.IBeamCursor
    }
}
