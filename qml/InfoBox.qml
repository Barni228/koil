import QtQuick
import QtQuick.Controls

// K's box (see showInfo in main.qml): what's known of an entry on disk (see
// info.rs), its parts colored, in the middle of the window. It never takes
// the keys, which stay with the editor, so the cursor moves under it, and
// main.qml has it show what the cursor is on as it goes (see followInfo);
// Esc closes it, as the hint under its text says. Its text can be selected
// with the mouse and copied (the editor forwards Copy, see copySelection).
// It's under the hover box and the completions, which show what's under
// the pointer or the cursor.
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
    // While a dir's size is counted, how many of the three dots after it
    // show, which come and go as the listing's notes' do (main.qml's
    // infoDots). The others are spaces, so nothing moves.
    property int dots: 3
    // Where the three dots of each part that's counted start in `text`.
    property var dotsAt: []
    readonly property string shownText: {
        if (dots >= 3 || dotsAt.length === 0)
            return text;
        const kept = ".".repeat(dots) + " ".repeat(3 - dots);
        let shown = "", from = 0;
        for (const at of dotsAt) {
            shown += text.slice(from, at) + kept;
            from = at + 3;
        }
        return shown + text.slice(from);
    }
    readonly property real zoom: theme.zoom
    readonly property real margin: 32 * zoom

    // Shows `info` ({ text, spans }, see info::Info), its spans colored.
    function show(info) {
        dotsAt = busyDots(info.text, info.spans);
        text = info.text;
        color(info.spans);
        shown = true;
    }

    // Where the dots that end each part that's counted (" so far...", see
    // info::dir_size) start in `text`, by `spans`, a line and a place in it.
    function busyDots(text, spans) {
        const at = [];
        let line = 0, lineStart = 0;
        for (const span of spans) {
            if (span.kind !== "busy")
                continue;
            for (; line < span.line; line++)
                lineStart = text.indexOf("\n", lineStart) + 1;
            const end = lineStart + span.start + span.length;
            if (text.slice(end - 3, end) === "...")
                at.push(end - 3);
        }
        return at;
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
        readonly property real hintGap: 8 * box.zoom

        theme: box.theme
        raised: true
        width: Math.max(scroller.width, hint.implicitWidth) + 2 * padding
        height: scroller.height + hintGap + hint.height + 2 * padding

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
            height: Math.min(label.height, (box.parent ? box.parent.height : 600)
                - 2 * (box.margin + frame.padding) - frame.hintGap - hint.height)
            contentWidth: label.width
            contentHeight: label.height
            wheelStep: 3 * metrics.height

            SelectableText {
                id: label

                width: Math.min(naturalWidth, (box.parent ? box.parent.width : 800) - 2 * (box.margin + frame.padding))
                theme: box.theme
                system: box.system
                text: box.shownText
                font: box.theme.font
                color: box.theme.text
                textFormat: TextEdit.PlainText
                wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
            }
        }

        // The key that closes it, as the help's header says its own.
        CodeLabel {
            id: hint

            anchors.right: parent.right
            anchors.rightMargin: frame.padding
            y: scroller.y + scroller.height + frame.hintGap
            theme: box.theme
            markup: qsTr("`Esc` to close")
            font.pixelSize: Math.round(12 * box.zoom)
            color: box.theme.dim
        }
    }
}
