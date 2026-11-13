import QtQuick

// Text that can be selected and copied, but never takes the keys, which
// stay with the box it's in (which forwards Copy): the hover box's, K's
// and :help's.
// Given `system` (main.qml's System), Koil lays its text out, as the
// editor's (see setLineFormat in native.h): rows that wrap break after a
// space or where a word starts or ends. Then `naturalWidth` is how wide it
// is unwrapped, which implicitWidth isn't (Qt has that from its own layout
// only).
TextEdit {
    id: selectable

    required property Theme theme
    property var system: null
    readonly property real naturalWidth: system ? measured : implicitWidth
    property real measured: 0
    property bool measuring: false

    // naturalWidth, once the text, its font or its layout are new: but not
    // as its own new width (a box as wide as naturalWidth) lays the text out
    // again, which can't change how wide it is unwrapped. Bound to
    // contentHeight, that was a binding loop. Rounded up, as a layout gives
    // its items whole pixels: 399.48 made a question 399 wide, which wrapped
    // its last word.
    function measure() {
        if (!system || measuring)
            return;
        measuring = true;
        measured = Math.ceil(system.layoutWidth(textDocument) + leftPadding + rightPadding);
        measuring = false;
    }

    // Rows as tall as the font's lines (a line height of 0), and no line too
    // long to lay out (see longLength in Editor.qml).
    function useLayout() {
        system?.setLineFormat(selectable, 0, 0, 0, false, 1 << 30);
        measure();
    }

    readOnly: true
    selectByMouse: true
    activeFocusOnPress: false
    persistentSelection: true
    selectionColor: theme.highlight
    selectedTextColor: theme.highlightedText
    onSystemChanged: useLayout()
    onTextChanged: measure()
    onFontChanged: measure()
    onContentHeightChanged: measure()
    Component.onCompleted: useLayout()

    HoverHandler {
        cursorShape: Qt.IBeamCursor
    }
}
