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
// j and k (or Up and Down) scroll, and g and G go to its top and bottom. Its text is in the editor's font and
// can be selected and copied.
// The list can be one to pick from (what to apply, or to undo), each line
// with a checked box (picked) or an empty one before it, all picked at
// first unless a line says otherwise. Then j and k move the current line
// instead (g and G to the first and last), Space or x (or a click on its box) picks it or leaves it out,
// along with the lines it needs or that need it, and a picks all of them,
// or none if all are. v selects lines, from the current one to where j and
// k take it, and Space or x then picks them all, or leaves them all out if
// they're all picked, which ends the selection, as Esc and v do (Esc
// cancels only once there's none). A question can also have u, which
// answers it with its own action (see ask's `undo`). Y, and Shift and the
// key of the button apart (D), do what y and the button do, but with
// the current line, or the lines v selected, whether they're picked or not
// (and only show the current line, if it isn't yet, as the first j does). A line can be one Yes can't do (an apply that can't
// be undone), with a crossed out box, which can't be picked, unless the
// question has a button for the picked lines (see below): then Yes is off
// while one is picked (and a leaves them out). Yes is off while none are
// picked, as that button is. A line to pick can take several lines of
// text, the rest lined up after its box, and then an empty line goes
// between each and the next, so they're told apart. The current line is
// highlighted only once one of those is used (the first j or k shows it
// where it is, on the first line), unless the question shows it at once.
// The word that starts a line of the list (after its box) can be colored
// by what it stands for, like CREATE in green, and a question can have one
// more button, on the left, apart from the choices, which does something
// with the picked lines, and is off while none are (see ask).
ModalBox {
    id: dialog

    // Colors the list's keywords (see `keywords`), and lays out the text,
    // so its rows break where words do (see SelectableText); none in the
    // tests.
    property var system: null

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
    // Whether a line Yes can't do is picked, which turns Yes off.
    readonly property bool blockedPicked: items.some((item, i) => item.blocked && picked[i])
    // The line j and k move, and Space picks or leaves out, and whether
    // it's highlighted (see moveRow), and the other end of the lines v
    // selected with it, or -1.
    property int row: 0
    property bool rowShown: false
    property int anchor: -1
    // What goes before a line to pick from, left out, picked, and one Yes
    // can't do, left out and picked: the Nerd Font's
    // nf-md-checkbox_blank_outline, nf-md-checkbox_marked,
    // nf-md-checkbox_blank_off_outline and nf-md-checkbox_blank_off, and two
    // spaces, as it draws them wider than a column (as the listing's icons).
    // All are as long. Each takes three columns, which `pad` fills on the
    // lines of text after a line's first.
    readonly property var boxes: ["󰄱  ", "󰄲  ", "󱋭  ", "󱋬  "]
    readonly property string pad: "   "
    readonly property string list: items.length ? items.map((item, i) => boxes[(item.blocked ? 2 : 0) + (picked[i] ? 1 : 0)]
        + rows[i]).join(gap) : details
    // What the answers do, and what's done after any of them (see ask).
    property var yesAction: null
    property var noAction: null
    property var afterAction: null
    // The button apart from the choices, `{ label, key, action }`, or null,
    // and what u does, or null (see ask).
    property var extra: null
    property var undoAction: null
    // Without anything for No to do, No is the same as Cancel, so it's
    // offered alone, named Cancel if the question says so (see ask).
    property bool cancelOnly: false
    readonly property var choices: [{ label: "[Y]es", answer: "yes" }].concat(noAction
        ? [{ label: "(N)o", answer: "no" }, { label: "(C)ancel", answer: "cancel" }]
        : [cancelOnly ? { label: "(C)ancel", answer: "cancel" } : { label: "(N)o", answer: "no" }])
    // The highlighted choice, which Enter answers.
    property int current: 0

    // Asks `question`, with `details` (a list, maybe "") under it. `yes` is
    // what Yes does, and `no` what No does, if anything. `after` runs after
    // either, or if it's closed some other way (the next question, say).
    // `details` can also be lines to pick from, `{ text, needs }`, where
    // `needs` are the indexes of the lines it can't go without, and a line
    // can also have `picked: false` (left out at first) and `blocked: true`
    // (Yes can't do it, nor then a line that needs it; it can be picked
    // only for `extra`, see below, and starts left out): then
    // `question` can be a function of how many are picked (and the list of
    // whether each is), and `yes` gets the indexes of the picked ones.
    // `options` can have `keywords`, which colors the word a line of the
    // list starts with by the kind of change it stands for (see
    // `keywords`), if it's one of them; `showRow`, to highlight the current
    // line to pick from at once; `extra`, a button apart from the
    // choices, `{ label, key, action }`, which `key` (like Qt.Key_D) clicks
    // too, and whose action runs as an answer's would, with the picked
    // lines; with lines to pick from, it's off while none are;
    // `cancel`, to name No Cancel when it has nothing to do (a list to pick
    // from, where No would read as leaving them out); and `again`, to ask
    // it again with other lines as if it never closed: those of the last
    // question (by their text) are picked as they were, the current line
    // stays on its line (or goes to the next one left, or else the last),
    // and it's highlighted, the list scrolled and the choice highlighted
    // as they were (with `row`, the current line is the one at that index
    // instead); `again` can also be what `place` gave, to ask a question
    // as it was before another one; and `undo`, what u does, as an
    // answer's action does, with the picked lines.
    function ask(question, details, yes, no, after, options) {
        options = options || {};
        // Before they're replaced.
        const was = options.again === true ? place() : options.again || null;
        dialog.keywords = options.keywords || {};
        extra = options.extra || null;
        undoAction = options.undo || null;
        cancelOnly = !!options.cancel;
        const pick = Array.isArray(details);
        rows = pick ? details.map(item => item.text.replace(/\n/g, "\n" + pad)) : [];
        gap = rows.some(row => row.includes("\n")) ? "\n\n" : "\n";
        items = pick ? details : [];
        dialog.details = pick ? "" : details || "";
        // Each line's index in the last question, or -1 (an object of
        // keys: a Set is slow, see CLAUDE.md).
        const index = Object.create(null);
        was?.texts.forEach((text, i) => index[text] = i);
        const before = items.map(item => index[item.text] ?? -1);
        picked = items.map((item, i) => !item.blocked && (before[i] >= 0 ? was.picked[before[i]] : item.picked !== false));
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
        anchor = -1;
        row = options.row !== undefined ? Math.max(0, Math.min(options.row, items.length - 1))
            : was ? rowAfter(before, was.row) : 0;
        rowShown = was ? was.shown : !!options.showRow;
        dialog.question = question;
        yesAction = yes;
        noAction = no || null;
        afterAction = after || null;
        current = was ? Math.min(was.current, choices.length - 1) : 0;
        scroller.contentY = 0;
        // Once the list is laid out, as far as it goes.
        const y = was ? was.y : 0;
        Qt.callLater(() => {
            scroller.scrollTo(y);
            showRow();
        });
        open();
    }

    // Where the question's lines are, for ask's `again` to ask it again so
    // after another question.
    function place() {
        return { texts: items.map(item => item.text), picked: picked, row: row, shown: rowShown,
            y: scroller.contentY, current: current };
    }

    // The line that's the current one asked again (see ask's `again`),
    // where `before` is each line's index in the last question (or -1),
    // and `was` the current one there: its own line, or else the first
    // after it that's still there, or else the last.
    function rowAfter(before, was) {
        let next = -1, last = -1;
        before.forEach((b, i) => {
            if (b >= was && (next < 0 || b < before[next]))
                next = i;
            if (b >= 0 && (last < 0 || b > before[last]))
                last = i;
        });
        return next >= 0 ? next : last >= 0 ? last : Math.max(0, Math.min(was, items.length - 1));
    }

    // Whether `choice` ("yes", "no", "cancel", "extra" or "undo") can be
    // answered now: with lines to pick from, Yes and the button apart only
    // once one is picked.
    function canAnswer(choice) {
        const none = items.length > 0 && pickedCount === 0;
        return choice === "yes" ? !blockedPicked && !none
            : choice === "extra" ? extra !== null && !none
            : choice === "undo" ? undoAction !== null : true;
    }

    // Answers `choice`, whose action gets the picked lines, or `lines`
    // (Y, D: see answerHighlighted), which Yes can't do if one of
    // them is a line it can't do.
    function answer(choice, lines) {
        const can = !lines ? canAnswer(choice) : choice === "extra" ? extra !== null
            : choice === "yes" && !lines.some(i => items[i].blocked);
        if (!can)
            return;
        const action = choice === "yes" ? yesAction : choice === "no" ? noAction
            : choice === "extra" ? extra?.action : choice === "undo" ? undoAction : null;
        const chosen = lines || [];
        if (!lines) {
            picked.forEach((p, i) => {
                if (p)
                    chosen.push(i);
            });
        }
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
        if (canPick(i))
            setPicked([i], !picked[i]);
    }

    // Space and x: toggles the current line, or the lines v selected: all
    // of them picked, if one is left out, else all left out, which ends
    // the selection.
    function toggleSelected() {
        if (anchor < 0) {
            toggle(row);
            return;
        }
        const lines = [];
        for (let i = Math.min(anchor, row); i <= Math.max(anchor, row); i++) {
            if (canPick(i))
                lines.push(i);
        }
        anchor = -1;
        setPicked(lines, lines.some(i => !picked[i]));
    }

    // Y and D: answers `choice` with the current line, or the lines
    // v selected, but only shows the current line if it isn't yet, as the
    // first j does.
    function answerHighlighted(choice) {
        if (rowShown)
            answer(choice, chosenLines());
        else
            rowShown = true;
    }

    // The current line, or the lines v selected, which ends the selection.
    function chosenLines() {
        const lines = [];
        for (let i = anchor < 0 ? row : Math.min(anchor, row); i <= Math.max(anchor, row); i++)
            lines.push(i);
        anchor = -1;
        return lines;
    }

    // `lines`, with every line that needs one of them, also through others,
    // in order: what can't be done without them.
    function withDependents(lines) {
        return closure(lines, j => neededBy[j]);
    }

    // `lines`, with every line one of them needs, also through others, in
    // order: what they can't be done without.
    function withNeeds(lines) {
        return closure(lines, j => items[j].needs);
    }

    // `lines`, with those `next` gives for each, and for those, in order.
    function closure(lines, next) {
        const with_ = items.map(() => false), todo = lines.slice();
        while (todo.length) {
            const j = todo.pop();
            if (with_[j])
                continue;
            with_[j] = true;
            for (const k of next(j))
                todo.push(k);
        }
        const r = [];
        with_.forEach((w, i) => {
            if (w)
                r.push(i);
        });
        return r;
    }

    // Whether line `i` can be picked: not one Yes can't do, unless there's
    // a button for the picked lines (see ask).
    function canPick(i) {
        return !items[i].blocked || extra !== null;
    }

    // Picks `lines`, with the lines they need, or leaves them out (`on`
    // false), with the lines that need them.
    function setPicked(lines, on) {
        const p = picked.slice(), todo = lines.slice();
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

    // g and G: makes the first line the current one (or the last, with
    // `last`), shown at once, as where it goes doesn't depend on where it
    // was.
    function moveToEnd(last) {
        row = last ? items.length - 1 : 0;
        rowShown = true;
    }

    // Those Yes can do.
    function pickAll() {
        const all = items.some((item, i) => !item.blocked && !picked[i]);
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
        // The top and bottom of line i.
        const top = i => label.positionToRectangle(starts[i]).y;
        const bottom = i => {
            const r = label.positionToRectangle(starts[i] + boxes[0].length + rows[i].length);
            return r.y + r.height;
        };
        // The lines v selected, or the current one.
        const first = anchor < 0 ? row : Math.min(anchor, row), last = anchor < 0 ? row : Math.max(anchor, row);
        rowHighlight.y = top(first);
        rowHighlight.height = bottom(last) - rowHighlight.y;
        if (top(row) < scroller.contentY)
            scroller.scrollTo(top(row));
        else if (bottom(row) > scroller.contentY + scroller.height)
            scroller.scrollTo(bottom(row) - scroller.height);
    }

    onKeywordColorsChanged: system?.setKeywordColors(label.textDocument, keywordColors)
    onRowChanged: Qt.callLater(showRow)
    onRowShownChanged: Qt.callLater(showRow)
    onAnchorChanged: Qt.callLater(showRow)

    width: Math.min(parent ? parent.width - 48 * zoom : 500,
        Math.max(questionText.naturalWidth, label.naturalWidth + scroller.scrollBar.width, buttons.implicitWidth) + 2 * padding)
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

    component Choice: AbstractButton {
        id: choice

        required property var modelData
        required property int index
        readonly property bool isCurrent: index === dialog.current

        padding: 4 * dialog.zoom
        leftPadding: 12 * dialog.zoom
        rightPadding: 12 * dialog.zoom
        enabled: dialog.canAnswer(modelData.answer)
        opacity: enabled ? 1 : 0.4
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
    component Selectable: SelectableText {
        id: selectable

        theme: dialog.theme
        system: dialog.system
        font: dialog.theme.font
        color: dialog.theme.text
        textFormat: TextEdit.PlainText
        wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
        onSelectedTextChanged: {
            if (selectedText)
                (selectable === label ? questionText : label).deselect();
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
            else if (dialog.items.length && event.key === Qt.Key_G)
                dialog.moveToEnd(event.modifiers & Qt.ShiftModifier);
            else if (dialog.items.length && (event.key === Qt.Key_Space || event.key === Qt.Key_X)) {
                dialog.rowShown = true;
                dialog.toggleSelected();
            } else if (dialog.items.length && event.key === Qt.Key_V) {
                dialog.rowShown = true;
                dialog.anchor = dialog.anchor < 0 ? dialog.row : -1;
            } else if (dialog.items.length && event.key === Qt.Key_A) {
                dialog.rowShown = true;
                dialog.anchor = -1;
                dialog.pickAll();
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J)
                scroller.scrollBy(step);
            else if (event.key === Qt.Key_Up || event.key === Qt.Key_K)
                scroller.scrollBy(-step);
            else if (event.key === Qt.Key_G)
                scroller.scrollTo(event.modifiers & Qt.ShiftModifier ? scroller.maxY : 0);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                dialog.answer(dialog.choices[dialog.current].answer);
            else if (dialog.extra && event.key === dialog.extra.key && dialog.items.length
                    && (event.modifiers & Qt.ShiftModifier))
                dialog.answerHighlighted("extra");
            else if (event.key === Qt.Key_Y && dialog.items.length && (event.modifiers & Qt.ShiftModifier))
                dialog.answerHighlighted("yes");
            else if (dialog.extra && event.key === dialog.extra.key)
                dialog.answer("extra");
            else if (dialog.undoAction && event.key === Qt.Key_U)
                dialog.answer("undo");
            else if (event.key === Qt.Key_Escape && dialog.anchor >= 0)
                dialog.anchor = -1;
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

        WheelFlickable {
            id: scroller

            Layout.fillWidth: true
            // As tall as the list, but no taller than the window has room for.
            Layout.preferredHeight: Math.min(label.implicitHeight, (dialog.parent ? dialog.parent.height : 500)
                - 48 * dialog.zoom - 2 * dialog.padding - questionText.height - buttons.implicitHeight
                - 2 * parent.spacing)
            visible: dialog.list !== ""
            contentWidth: width
            contentHeight: label.implicitHeight
            wheelStep: 60 * dialog.zoom

            Selectable {
                id: label

                // Room for the scroll bar, which the width can't depend on
                // needing: that depends on the height, which depends on it.
                width: scroller.width - scroller.scrollBar.width
                text: dialog.list
                // A wrapped line to pick from goes on under its text, not
                // under its box.
                listing: dialog.items.length > 0
                onTextChanged: Qt.callLater(dialog.showRow)
                onContentHeightChanged: Qt.callLater(dialog.showRow)

                // The current line to pick from, under the text.
                Rectangle {
                    id: rowHighlight

                    z: -1
                    width: label.width
                    visible: dialog.items.length > 0 && dialog.rowShown
                    radius: 2 * dialog.zoom
                    // The lines v selected as the editor's marked lines.
                    color: dialog.anchor >= 0 ? dialog.theme.marked : dialog.theme.hover
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
                        dialog.anchor = -1;
                        dialog.toggle(i);
                    }
                }
            }
        }

        RowLayout {
            id: buttons

            Layout.fillWidth: true
            spacing: 8 * dialog.zoom

            // Never highlighted, so Enter doesn't answer it.
            Choice {
                visible: dialog.extra !== null
                modelData: ({ label: dialog.extra?.label ?? "", answer: "extra" })
                index: -1
            }

            Item {
                Layout.fillWidth: true
            }

            Repeater {
                model: dialog.choices

                Choice {}
            }
        }
    }
}
