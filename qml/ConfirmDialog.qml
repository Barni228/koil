pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A question with vim's :confirm choices, [Y]es, (N)o and (C)ancel, in a box
// over the editor like :help's, with an optional list under it (what
// applying would do, say), which scrolls if it's long, while the question
// stays where it is, over it. y answers yes, n no,
// and c or Esc cancels; Left and Right (or h and l, Tab and Shift+Tab) move
// the highlight, which starts on Yes, Enter answers the highlighted choice,
// and j and k (or Up and Down) scroll. Its text is in the editor's font and
// can be selected and copied.
// The list can be one to pick from (what to apply, or to undo), each line
// with a checked box (picked) or an empty one before it, all picked at
// first unless a line says otherwise. Then j and k move the current line
// instead, Space or x (or a click on its box) picks it or leaves it out,
// along with the lines it needs or that need it, and a picks all of them,
// or none if all are. A line can be one that can't be picked (an apply
// that can't be undone), with a crossed out box. What Yes does with none
// picked is up to the question (applying none forgets them all: see
// applyChanges in main.qml). A line to pick can take several lines of
// text, the rest lined up after its box, and then an empty line goes
// between each and the next, so they're told apart. The current line is
// highlighted only once one of those is used: the first j or k shows it
// where it is, on the first line.
// The word that starts a line of the list (after its box) can be colored
// by what it stands for, like CREATE in green (see ask).
Popup {
    id: dialog

    required property Theme theme
    // Colors the list's keywords (see `keywords`); none in the tests.
    property var system: null

    readonly property real zoom: theme.zoom
    // The question, or a function of how many lines are picked (and which)
    // that gives it (see ask).
    property var question: ""
    readonly property string text: typeof question === "function" ? question(pickedCount, picked) : question
    property string details
    // The kind of change (see theme.changeColor) each word that can
    // start a line of the list stands for, like `{ MOVE: "rename" }`, and
    // the colors that gives (see ask).
    property var keywords: ({})
    readonly property var keywordColors: Object.keys(keywords)
        .reduce((list, word) => list.concat([word, theme.changeColor(keywords[word])]), [])
    // The lines to pick from (see ask), their text as shown (lined up after
    // the box), what goes between them (an empty line too, if one takes
    // several), which of them are picked, which need each one (`needs` the
    // other way round), and where each starts in `list`.
    property var items: []
    property var rows: []
    property string gap: "\n"
    property var picked: []
    property var neededBy: []
    property var starts: []
    readonly property int pickedCount: picked.filter(p => p).length
    // The line j and k move, and Space picks or leaves out, and whether
    // it's highlighted (see moveRow).
    property int row: 0
    property bool rowShown: false
    // What goes before a line to pick from, left out, picked and one that
    // can't be: the Nerd Font's nf-md-checkbox_blank_outline,
    // nf-md-checkbox_marked and nf-md-checkbox_blank_off_outline, and two
    // spaces, as it draws them wider than a column (as the listing's icons).
    // All are as long. Each takes three columns, which `pad` fills on the
    // lines of text after a line's first.
    readonly property var boxes: ["󰄱  ", "󰄲  ", "󱋭  "]
    readonly property string pad: "   "
    readonly property string list: items.length ? items.map((item, i) => boxes[item.blocked ? 2 : picked[i] ? 1 : 0] + rows[i])
        .join(gap) : details
    // What the answers do, and what's done after any of them (see ask).
    property var yesAction: null
    property var noAction: null
    property var afterAction: null
    // Without anything for No to do, No is the same as Cancel, so it's
    // offered alone.
    readonly property var choices: [
        { label: "[Y]es", answer: "yes" },
        { label: "(N)o", answer: "no" }
    ].concat(noAction ? [{ label: "(C)ancel", answer: "cancel" }] : [])
    // The highlighted choice, which Enter answers.
    property int current: 0

    // Asks `question`, with `details` (a list, maybe "") under it. `yes` is
    // what Yes does, and `no` what No does, if anything. `after` runs after
    // either, or if it's closed some other way (the next question, say).
    // `details` can also be lines to pick from, `{ text, needs }`, where
    // `needs` are the indexes of the lines it can't go without, and a line
    // can also have `picked: false` (left out at first) and `blocked: true`
    // (it can't be picked; nor then can a line that needs it): then
    // `question` can be a function of how many are picked (and the list of
    // whether each is), and `yes` gets the indexes of the picked ones.
    // `keywords` colors the word a line of the list starts with by the kind
    // of change it stands for (see `keywords`), if it's one of them.
    function ask(question, details, yes, no, after, keywords) {
        dialog.keywords = keywords || {};
        const pick = Array.isArray(details);
        rows = pick ? details.map(item => item.text.replace(/\n/g, "\n" + pad)) : [];
        gap = rows.some(row => row.includes("\n")) ? "\n\n" : "\n";
        items = pick ? details : [];
        dialog.details = pick ? "" : details || "";
        picked = items.map(item => !item.blocked && item.picked !== false);
        const by = items.map(() => []);
        let start = 0;
        starts = items.map((item, i) => {
            for (const j of item.needs)
                by[j].push(i);
            const at = start;
            start += boxes[0].length + rows[i].length + gap.length;
            return at;
        });
        neededBy = by;
        row = 0;
        rowShown = false;
        dialog.question = question;
        yesAction = yes;
        noAction = no || null;
        afterAction = after || null;
        current = 0;
        scroller.contentY = 0;
        open();
    }

    function answer(choice) {
        const action = choice === "yes" ? yesAction : choice === "no" ? noAction : null;
        const chosen = [];
        picked.forEach((p, i) => {
            if (p)
                chosen.push(i);
        });
        const after = afterAction;
        afterAction = null;
        close();
        if (action)
            action(chosen);
        if (after)
            after();
    }

    // Picks line `i`, with the lines it needs, or leaves it out, with the
    // lines that need it. One that can't be picked stays as it is.
    function toggle(i) {
        if (items[i].blocked)
            return;
        const on = !picked[i], p = picked.slice(), todo = [i];
        while (todo.length) {
            const j = todo.pop();
            if (p[j] === on)
                continue;
            p[j] = on;
            for (const k of on ? items[j].needs : neededBy[j])
                todo.push(k);
        }
        picked = p;
    }

    // j and k: moves the current line by `step`, but only shows it if it
    // isn't yet, as the user hasn't seen where it is.
    function moveRow(step) {
        if (rowShown)
            row = Math.max(0, Math.min(items.length - 1, row + step));
        rowShown = true;
    }

    // Those that can be picked.
    function pickAll() {
        const all = pickedCount < items.filter(item => !item.blocked).length;
        picked = items.map(item => all && !item.blocked);
    }

    // The line to pick from at `position` in the list, or -1 (also on the
    // empty line after one).
    function itemAt(position) {
        if (!items.length)
            return -1;
        let low = 0, high = starts.length - 1;
        while (low < high) {
            const mid = (low + high + 1) >> 1;
            if (starts[mid] <= position)
                low = mid;
            else
                high = mid - 1;
        }
        return position <= starts[low] + boxes[0].length + rows[low].length ? low : -1;
    }

    // Puts the highlight on the current line, and scrolls to it.
    function showRow() {
        if (!items.length)
            return;
        const start = starts[row];
        const top = label.positionToRectangle(start);
        const bottom = label.positionToRectangle(start + boxes[0].length + rows[row].length);
        rowHighlight.y = top.y;
        rowHighlight.height = bottom.y + bottom.height - top.y;
        if (top.y < scroller.contentY)
            scrollTo(top.y);
        else if (bottom.y + bottom.height > scroller.contentY + scroller.height)
            scrollTo(bottom.y + bottom.height - scroller.height);
    }

    function scrollBy(dy) {
        scrollTo(scroller.contentY + dy);
    }

    function scrollTo(y) {
        scroller.contentY = Math.max(0, Math.min(scroller.contentHeight - scroller.height, y));
    }

    onKeywordColorsChanged: system?.setKeywordColors(label.textDocument, keywordColors)
    onRowChanged: Qt.callLater(showRow)
    onRowShownChanged: Qt.callLater(showRow)

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(parent ? parent.width - 48 * zoom : 500,
        Math.max(questionText.implicitWidth, label.implicitWidth + scrollBar.width, buttons.implicitWidth) + 2 * padding)
    padding: 16 * zoom
    modal: true
    focus: true
    closePolicy: Popup.CloseOnPressOutside
    onClosed: {
        questionText.deselect();
        label.deselect();
        // Closed by a click outside it.
        const after = afterAction;
        afterAction = null;
        if (after)
            after();
    }

    Overlay.modal: Rectangle {
        color: dialog.theme.dark ? "#60000000" : "#30000000"
    }

    background: Panel {
        theme: dialog.theme
        raised: true
    }

    component Choice: AbstractButton {
        id: choice

        required property var modelData
        required property int index
        readonly property bool isCurrent: index === dialog.current

        padding: 4 * dialog.zoom
        leftPadding: 12 * dialog.zoom
        rightPadding: 12 * dialog.zoom
        focusPolicy: Qt.NoFocus
        hoverEnabled: true
        text: modelData.label
        onClicked: dialog.answer(modelData.answer)

        background: Rectangle {
            readonly property color accent: dialog.theme.accent

            radius: 4 * dialog.zoom
            color: choice.isCurrent ? Qt.rgba(accent.r, accent.g, accent.b, choice.hovered || choice.pressed ? 0.4 : 0.25)
                : choice.hovered || choice.pressed ? dialog.theme.hover : "transparent"
            border.color: choice.isCurrent ? accent : dialog.theme.panelBorder
        }
        contentItem: Text {
            text: choice.text
            font: dialog.theme.font
            color: dialog.theme.text
            textFormat: Text.PlainText
        }
    }

    // The question's and the list's text, which can be selected (one at a
    // time) and copied.
    component Selectable: TextEdit {
        id: selectable

        font: dialog.theme.font
        color: dialog.theme.text
        textFormat: TextEdit.PlainText
        wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
        readOnly: true
        selectByMouse: true
        // Keys stay with the dialog, which forwards Copy.
        activeFocusOnPress: false
        persistentSelection: true
        selectionColor: dialog.theme.highlight
        selectedTextColor: dialog.theme.highlightedText
        onSelectedTextChanged: {
            if (selectedText)
                (selectable === label ? questionText : label).deselect();
        }

        HoverHandler {
            cursorShape: Qt.IBeamCursor
        }
    }

    contentItem: ColumnLayout {
        spacing: 16 * dialog.zoom
        focus: true

        Keys.onPressed: event => {
            const step = label.implicitHeight / Math.max(1, label.lineCount);
            if (event.matches(StandardKey.Copy))
                (questionText.selectedText ? questionText : label).copy();
            else if (event.modifiers & ~(Qt.ShiftModifier | Qt.KeypadModifier))
                return;
            else if (event.key === Qt.Key_Left || event.key === Qt.Key_H || event.key === Qt.Key_Backtab)
                dialog.current = Math.max(0, dialog.current - 1);
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_L || event.key === Qt.Key_Tab)
                dialog.current = Math.min(dialog.choices.length - 1, dialog.current + 1);
            else if (dialog.items.length && (event.key === Qt.Key_Down || event.key === Qt.Key_J))
                dialog.moveRow(1);
            else if (dialog.items.length && (event.key === Qt.Key_Up || event.key === Qt.Key_K))
                dialog.moveRow(-1);
            else if (dialog.items.length && (event.key === Qt.Key_Space || event.key === Qt.Key_X)) {
                dialog.rowShown = true;
                dialog.toggle(dialog.row);
            } else if (dialog.items.length && event.key === Qt.Key_A) {
                dialog.rowShown = true;
                dialog.pickAll();
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J)
                dialog.scrollBy(step);
            else if (event.key === Qt.Key_Up || event.key === Qt.Key_K)
                dialog.scrollBy(-step);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                dialog.answer(dialog.choices[dialog.current].answer);
            else if (event.key === Qt.Key_Y)
                dialog.answer("yes");
            else if (event.key === Qt.Key_N)
                dialog.answer("no");
            else if (event.key === Qt.Key_C || event.key === Qt.Key_Escape)
                dialog.answer("cancel");
            else
                return;
            event.accepted = true;
        }

        // Over the list, so it stays in view as the list scrolls.
        Selectable {
            id: questionText

            Layout.fillWidth: true
            text: dialog.text
        }

        // Not interactive, since a drag selects text; the wheel scrolls it.
        Flickable {
            id: scroller

            Layout.fillWidth: true
            // As tall as the list, but no taller than the window has room for.
            Layout.preferredHeight: Math.min(label.implicitHeight, (dialog.parent ? dialog.parent.height : 500)
                - 48 * dialog.zoom - 2 * dialog.padding - questionText.height - buttons.implicitHeight
                - 2 * parent.spacing)
            visible: dialog.list !== ""
            contentWidth: width
            contentHeight: label.implicitHeight
            interactive: false
            clip: true

            ScrollBar.vertical: ScrollBar {
                id: scrollBar
            }

            // The trackpad too, which a WheelHandler leaves out by default.
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => dialog.scrollBy(-(event.pixelDelta.y || event.angleDelta.y / 120 * 60 * dialog.zoom))
            }

            Selectable {
                id: label

                // Room for the scroll bar, which the width can't depend on
                // needing: that depends on the height, which depends on it.
                width: scroller.width - scrollBar.width
                text: dialog.list
                onTextChanged: Qt.callLater(dialog.showRow)
                onContentHeightChanged: Qt.callLater(dialog.showRow)

                // The current line to pick from, under the text.
                Rectangle {
                    id: rowHighlight

                    z: -1
                    width: label.width
                    visible: dialog.items.length > 0 && dialog.rowShown
                    radius: 2 * dialog.zoom
                    color: dialog.theme.hover
                }

                TextMetrics {
                    id: box

                    font: dialog.theme.font
                    text: dialog.boxes[1]
                }

                // The boxes: a click on one picks its line or leaves it out.
                MouseArea {
                    width: box.advanceWidth
                    height: label.height
                    visible: dialog.items.length > 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        const i = dialog.itemAt(label.positionAt(mouse.x, mouse.y));
                        if (i < 0)
                            return;
                        dialog.row = i;
                        dialog.rowShown = true;
                        dialog.toggle(i);
                    }
                }
            }
        }

        Row {
            id: buttons

            Layout.alignment: Qt.AlignRight
            spacing: 8 * dialog.zoom

            Repeater {
                model: dialog.choices

                Choice {}
            }
        }
    }
}
