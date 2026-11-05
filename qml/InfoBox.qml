import QtQuick
import QtQuick.Controls

// K's box (see showInfo in main.qml): what's known of an entry on disk (see
// info.rs), its parts colored, in the middle of the window. It never takes
// the keys, which stay with the editor, so the cursor moves under it, and
// main.qml has it show what the cursor is on as it goes (see followInfo);
// Esc closes it. Its text can be selected with the mouse and copied (the
// editor forwards Copy, see copySelection). It's under the hover box and
// the completions, which show what's under the pointer or the cursor.
Item {
    id: box

    required property Theme theme
    // main.qml's System, which lays out and colors its text.
    property var system: null
    property bool shown: false
    property string text: ""
    // What it shows: the path it read (none if it's why there's none), and
    // what the cursor was on then (see followInfo).
    property string path: ""
    property string spot: ""
    readonly property real zoom: theme.zoom
    readonly property real margin: 32 * zoom

    // Shows `info` ({ text, spans }, see info::Info), its spans colored.
    function show(info) {
        text = info.text;
        color(info.spans);
        shown = true;
    }

    function close() {
        shown = false;
        path = "";
        spot = "";
        label.deselect();
    }

    // Copies the text selected in it, if any.
    function copySelection() {
        if (!shown || label.selectedText === "")
            return false;
        label.copy();
        return true;
    }

    // Colors parts of the text: `spans`, as { line, start, length, kind }
    // (see info::Span), in theme.infoColor's colors.
    function color(spans) {
        const list = [];
        for (const span of spans)
            list.push(String(span.line), String(span.start), String(span.length), theme.infoColor(span.kind));
        system?.setSpanColors(label.textDocument, list);
    }

    parent: Overlay.overlay
    z: -1
    visible: shown
    width: frame.width
    height: frame.height
    x: Math.round(((parent ? parent.width : 0) - width) / 2)
    y: Math.round(((parent ? parent.height : 0) - height) / 2)

    FontMetrics {
        id: metrics

        font: box.theme.font
    }

    Panel {
        id: frame

        readonly property real padding: 12 * box.zoom

        theme: box.theme
        raised: true
        width: scroller.width + 2 * padding
        height: scroller.height + 2 * padding

        // A press on the box is its own, not the editor's under it.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        WheelFlickable {
            id: scroller

            x: frame.padding
            y: frame.padding
            // Room beside the text for the scroll bar, when there is one.
            width: label.width + (contentHeight > height ? scrollBar.width + 4 : 0)
            height: Math.min(label.height, (box.parent ? box.parent.height : 600) - 2 * (box.margin + frame.padding))
            contentWidth: label.width
            contentHeight: label.height
            wheelStep: 3 * metrics.height

            SelectableText {
                id: label

                width: Math.min(naturalWidth, (box.parent ? box.parent.width : 800) - 2 * (box.margin + frame.padding))
                theme: box.theme
                system: box.system
                text: box.text
                font: box.theme.font
                color: box.theme.text
                textFormat: TextEdit.PlainText
                wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
            }
        }
    }
}
