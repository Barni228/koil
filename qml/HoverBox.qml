import QtQuick
import QtQuick.Controls

import "text.js" as Txt

// The text an icon hides, or a warning's or error's message, shown like VS
// Code's hover: after the pointer rests on it (or on the message after its
// line), or on gh. Its text can be selected with the mouse and copied. Any
// other key, a scroll or an edit hides it, and one the pointer opened also
// hides once the pointer is on neither the target (nor its message) nor the
// box. It lives in the window's overlay so the editor doesn't clip it.
Item {
    id: hover

    // The Editor it shows things in: its textArea, cellAt, lineHeight and
    // metrics, its hidden text, and the warnings and errors. Untyped, since
    // Editor.qml can't name its own type.
    required property var editor
    required property Theme theme
    readonly property TextArea textArea: editor.textArea

    property int at: -1 // the start of the target
    property bool byMouse: false
    property string text: ""
    property string severity: "" // a diagnostic's: "warning" or "error"
    property rect anchorRect // what the box points at, in the overlay's coordinates
    property int mouseAt: -1 // the start of the target under the pointer
    property rect mouseRect // what's under the pointer: the target or its message
    readonly property real maxWidth: Math.min(parent ? parent.width - 32 : 600, 640)
    readonly property real maxHeight: Math.min(parent ? parent.height / 2 : 400, 20 * editor.lineHeight)
    readonly property bool held: mouseAt >= 0 && mouseAt === at || boxHover.hovered || press.active

    // Shows the target at pos, pointing at `rect` in the editor (the target
    // itself if not given).
    function show(pos, mouse, rect) {
        const target = targetAt(pos);
        if (!target)
            return;
        severity = target.severity;
        text = target.text;
        const a = editor.cellAt(target.start), b = editor.cellAt(target.end);
        const r = rect || Qt.rect(a.x, a.y, b.x - a.x, a.height);
        anchorRect = textArea.mapToItem(parent, r.x, r.y, r.width, r.height);
        scroller.contentY = 0;
        byMouse = mouse;
        at = target.start;
    }

    function hide() {
        at = -1;
        label.deselect();
        delay.stop();
        grace.stop();
    }

    // Copies the text selected in the box, if any.
    function copySelection() {
        if (at < 0 || label.selectedText === "")
            return false;
        label.copy();
        return true;
    }

    // What there is to show at pos, as { start, end, text, severity }: the
    // icon that starts there and what it hides (with no severity), or the
    // warning or error with the character there. Null if nothing.
    function targetAt(pos) {
        const h = editor.hiddenAt(pos);
        if (h)
            return {
                start: pos,
                end: pos + h.icon.length,
                text: h.text.replace(/\n$/, ""),
                severity: ""
            };
        const d = editor.diagnosticAt(pos);
        return d && {
            start: d.start,
            end: d.end,
            text: d.message,
            severity: d.severity
        };
    }

    // The target at point p in the editor, or with its message there, as
    // { start, rect } (the rectangle under p), or null.
    function targetUnder(p) {
        if (!p)
            return null;
        const t = textArea.text, pos = textArea.positionAt(p.x, p.y);
        // positionAt gives the nearest gap, which is after the character on its right half.
        for (const c of [pos, pos > 0 ? Txt.charStart(t, pos - 1) : -1]) {
            const target = c >= 0 ? targetAt(c) : null;
            if (!target)
                continue;
            const a = editor.cellAt(target.start), b = editor.cellAt(target.end);
            if (p.x >= a.x && p.x < b.x && p.y >= a.y && p.y < a.y + a.height)
                return {
                    start: target.start,
                    rect: Qt.rect(a.x, a.y, b.x - a.x, a.height)
                };
        }
        return editor.messageUnder(p);
    }

    function pointerAt(p) {
        const under = targetUnder(p);
        const c = under ? under.start : -1;
        if (c === mouseAt)
            return;
        mouseAt = c;
        if (under)
            mouseRect = under.rect;
        delay.stop();
        if (c >= 0 && c !== at)
            delay.restart();
    }

    parent: Overlay.overlay
    visible: at >= 0
    width: frame.width
    height: frame.height
    // Above the target, or below it when there's no room.
    x: Math.max(8, Math.min(anchorRect.x, (parent ? parent.width : 0) - width - 8))
    y: anchorRect.y - height - 4 >= 4 ? anchorRect.y - height - 4 : anchorRect.y + anchorRect.height + 4
    // A little time to cross the gap between the target and the box.
    onHeldChanged: {
        if (held || at < 0 || !byMouse)
            grace.stop();
        else
            grace.restart();
    }

    Timer {
        id: delay

        interval: 300
        onTriggered: hover.show(hover.mouseAt, true, hover.mouseRect)
    }

    Timer {
        id: grace

        interval: 300
        onTriggered: hover.hide()
    }

    Panel {
        id: frame

        theme: hover.theme
        width: scroller.x + scroller.width + 8
        height: scroller.height + 8

        HoverHandler {
            id: boxHover

            cursorShape: Qt.IBeamCursor
        }
        // Held while a selection is dragged, even outside the box.
        PointHandler {
            id: press

            acceptedButtons: Qt.LeftButton
        }

        // A diagnostic's icon, as in VS Code: a triangle for a warning, a
        // circle for an error. Centered on the first line.
        Icon {
            id: icon

            visible: hover.severity !== ""
            x: 8
            y: scroller.y + (hover.editor.metrics.height - height) / 2
            theme: hover.theme
            color: hover.theme.severityColor(hover.severity)
            path: hover.severity === "error" ? "M1.5 8 A6.5 6.5 0 1 1 14.5 8 A6.5 6.5 0 1 1 1.5 8 Z M5.7 5.7 L10.3 10.3 M10.3 5.7 L5.7 10.3" : "M8 1.8 L14.5 13.8 L1.5 13.8 Z M8 6.2 L8 9.6 M8 11.8 L8 11.9"
        }

        // Not interactive, since a drag selects text; the wheel scrolls it.
        Flickable {
            id: scroller

            x: icon.visible ? icon.x + icon.width + 6 * hover.theme.zoom : 8
            y: 4
            // Room beside the text for the scroll bar, when there is one.
            width: label.width + (contentHeight > height ? scrollBar.width + 4 : 0)
            height: Math.min(label.height, hover.maxHeight - 8)
            contentWidth: label.width
            contentHeight: label.height
            interactive: false
            clip: true

            ScrollBar.vertical: ScrollBar {
                id: scrollBar
            }

            WheelHandler {
                onWheel: event => {
                    const dy = event.pixelDelta.y || event.angleDelta.y / 120 * 3 * hover.editor.lineHeight;
                    scroller.contentY = Math.max(0, Math.min(scroller.contentHeight - scroller.height, scroller.contentY - dy));
                }
            }

            TextEdit {
                id: label

                width: Math.min(implicitWidth, hover.maxWidth - scroller.x - 8)
                text: hover.text
                font: hover.theme.font
                color: hover.theme.text
                textFormat: TextEdit.PlainText
                wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                readOnly: true
                selectByMouse: true
                // Keys stay with the editor, which forwards Copy (see copySelection).
                activeFocusOnPress: false
                persistentSelection: true
                selectionColor: hover.theme.highlight
                selectedTextColor: hover.theme.highlightedText
            }
        }
    }
}
