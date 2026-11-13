pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A question in a box over the editor like :help's, with its choices as
// buttons, Yes, No and Cancel, each with the key that answers it: y answers
// yes, n no, and c or Esc cancels. Yes and No are named by what they do, if
// the question says (Apply, Don't Save), with the same keys. Left and Right
// (or h and l, Tab and Shift+Tab) move the highlight (the accent's color),
// which starts on Yes, through every button that's on, the list's too, left
// to right, and round from the last to the first, and Enter clicks the
// highlighted one. It keeps the keys itself: no button takes them. The question is in the window's font, with `code` in
// backquotes as the help shows it. Under it there can be a list (what
// applying would do, say), in the editor's font, a row a line, which
// scrolls if it's long, while the question stays where it is, over it: j
// and k (or Up and Down) scroll it, and g and G go to its top and bottom.
// The list can be one to pick from (what to apply, or to undo), each row
// with a box before it, checked if it's picked, all picked at first unless
// a line says otherwise. Then j and k move the current row instead (g and
// G to the first and last), Space or x (or a click on the row) picks it or
// leaves it out, along with the lines it needs or that need it, and a (or
// Select All) picks all of them, or none if all are. v selects rows, from
// the current one to where j and k take it, and Space or x then picks them
// all, or leaves them all out if they're all picked, which ends the
// selection, as Esc and v do (Esc cancels only once there's none). A
// question can also have u, which answers it with its own action (see
// ask's `undo`). Y, and Shift and the key of the button apart (D), do what
// y and the button do, but with the current row, or the rows v selected,
// whether they're picked or not (and only show the current row, if it
// isn't yet, as the first j does). A row can be one Yes can't do (an apply
// that can't be undone), with a crossed out box, dimmed, which can't be
// picked, unless the question has a button for the picked lines (see
// below): then Yes is off while one is picked (and a leaves them out). Yes
// is off while none are picked, as that button is. A line to pick can take
// several lines of text, all after its box, and then the rows are a little
// apart, so they're told apart. The current row is highlighted only once
// one of those keys is used (the first j or k shows it where it is, on the
// first row), unless the question shows it at once. Under a list to pick
// from, the keys that aren't a button's are listed, and by the buttons, how
// many are picked. The word that starts a line of the list can be colored by what
// it stands for, like CREATE in green, and a question can have one more
// button, on the left, apart from the choices, which does something with
// the picked lines, and is off while none are (see ask). Copy copies the
// list: the rows v selected, or all of it.
ModalBox {
    id: dialog

    // The clipboard, for Copy (main.qml's System); none in the tests.
    property var system: null

    // The question, or a function of how many lines are picked (and which)
    // that gives it (see ask).
    property var question: ""
    readonly property string text: typeof question === "function" ? question(pickedCount, picked) : question
    // The list as text, a row a line, if it's not one to pick from.
    property string details
    readonly property var lines: details === "" ? [] : details.split("\n")
    // The kind of change (see theme.changeColor) each word that can
    // start a line of the list stands for, like `{ MOVE: "rename" }` (see
    // ask).
    property var keywords: ({})
    // The lines to pick from (see ask), which of them are picked, and
    // which need each one (`needs` the other way round).
    property var items: []
    property var picked: []
    property var neededBy: []
    readonly property int pickedCount: picked.filter(p => p).length
    // Whether a line Yes can't do is picked, which turns Yes off, and
    // whether all it can do are (Select All then picks none).
    readonly property bool blockedPicked: items.some((item, i) => item.blocked && picked[i])
    readonly property bool allPicked: !items.some((item, i) => !item.blocked && !picked[i])
    // The row j and k move, and Space picks or leaves out, and whether
    // it's highlighted (see moveRow), and the other end of the rows v
    // selected with it, or -1.
    property int row: 0
    property bool rowShown: false
    property int anchor: -1
    // The list's text, measured as it's asked (see ask): how many
    // characters its longest line has, how many lines it has (an empty one
    // counts half, as it's drawn), and whether a line to pick takes several.
    property int longest: 0
    property real textLines: 0
    property bool spaced: false
    // The list's sizes: the editor's font's, a box, the room over and
    // under a row's text (more in a list to pick from, whose rows are
    // clicked), where a row's text starts, and how far apart the rows are.
    readonly property TextMetrics metrics: TextMetrics {
        font: dialog.theme.font
        text: "0"
    }
    readonly property FontMetrics fontMetrics: FontMetrics {
        font: dialog.theme.font
    }
    readonly property real charWidth: metrics.advanceWidth
    readonly property real lineHeight: Math.ceil(fontMetrics.height)
    readonly property real boxSize: 16 * zoom
    readonly property real rowPad: (items.length ? 3 : 1) * zoom
    readonly property real rowMargin: 6 * zoom
    readonly property real textX: rowMargin + (items.length ? boxSize + 8 * zoom : 0)
    readonly property real rowGap: spaced ? 4 * zoom : 0
    readonly property int rowCount: items.length || lines.length
    // How wide the list is with no line wrapped, and how tall, until its
    // rows are laid out (see listFrame).
    readonly property real listWidth: rowCount ? Math.ceil(longest * charWidth) + textX + rowMargin + bar.width
        + 2 * listFrame.margin : 0
    readonly property real listHeight: textLines * lineHeight + rowCount * 2 * rowPad + (rowCount - 1) * rowGap
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
    // What Yes and No are named, if not that (see ask).
    property string yesLabel
    property string noLabel
    readonly property var choices: {
        const yes = { label: yesLabel || qsTr("Yes"), keys: "y", answer: "yes" };
        const no = { label: noLabel || qsTr("No"), keys: "n", answer: "no" };
        const cancel = { label: qsTr("Cancel"), keys: "c", answer: "cancel" };
        return noAction ? [yes, no, cancel] : [yes, cancelOnly ? cancel : no];
    }
    // Every button, left to right, by what it answers: Select All ("all")
    // and the button apart ("extra"), then the choices.
    readonly property var order: (items.length ? ["all"] : []).concat(extra ? ["extra"] : [])
        .concat(choices.map(choice => choice.answer))
    // The highlighted button (what it answers), which Enter clicks.
    property string current: "yes"
    // The key of the button apart, as its button shows it (`d`).
    readonly property string extraKeys: extra ? String.fromCharCode(extra.key).toLowerCase() : ""
    // The keys of a list to pick from that no button shows, listed under
    // it: `{ keys, label }` each.
    readonly property var hints: !items.length ? [] : [
        { keys: ["j", "k"], label: "move" },
        { keys: ["Space"], label: "pick" },
        { keys: ["v"], label: "select" },
        { keys: ["Y"].concat(extra ? [extraKeys.toUpperCase()] : []), label: "current row only" }
    ].concat(undoAction ? [{ keys: ["u"], label: "undo" }] : [])

    // Asks `question`, with `details` (a list, maybe "") under it. `yes` is
    // what Yes does, and `no` what No does, if anything. `after` runs after
    // either, or if it's closed some other way (the next question, say).
    // `details` can also be lines to pick from, `{ text, needs }`, where
    // `needs` are the indexes of the lines it can't go without, and a line
    // can also have `picked: false` (left out at first) and `blocked` (Yes
    // can't do it, nor then a line that needs it; it can be picked only
    // for `extra`, see below, and starts left out; if it's why, as text, the
    // line of its text that ends with that is in the error's color), and
    // `lead`, `{ length, color }`: that many characters at its text's start
    // are in that color (when an apply was made, by how old it is): then
    // `question` can be a function of how many are picked (and the list of
    // whether each is), and `yes` gets the indexes of the picked ones.
    // `options` can have `keywords`, which colors the word a line of the
    // list starts with by the kind of change it stands for (see
    // `keywords`), if it's one of them; `showRow`, to highlight the current
    // line to pick from at once; `extra`, a button apart from the
    // choices, `{ label, key, action }`, which `key` (a letter's, like
    // Qt.Key_D, shown on it) clicks too, and whose action runs as an
    // answer's would, with the picked lines; with lines to pick from, it's
    // off while none are;
    // `cancel`, to name No Cancel when it has nothing to do (a list to pick
    // from, where No would read as leaving them out); `yes` and `no`, what
    // Yes and No are named, by what they do ("Apply", "Don't Save"), with
    // the same keys; and `again`, to ask
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
        yesLabel = options.yes || "";
        noLabel = options.no || "";
        const pick = Array.isArray(details);
        items = pick ? details : [];
        dialog.details = pick ? "" : details || "";
        let most = 0, count = 0;
        for (const text of pick ? details.map(item => item.text) : dialog.lines) {
            for (const line of text.split("\n")) {
                most = Math.max(most, line.length);
                count += line === "" ? 0.5 : 1;
            }
        }
        longest = most;
        textLines = count;
        spaced = pick && details.some(item => item.text.includes("\n"));
        // Each line's index in the last question, or -1 (an object of
        // keys: a Set is slow, see CLAUDE.md).
        const index = Object.create(null);
        was?.texts.forEach((text, i) => index[text] = i);
        const before = items.map(item => index[item.text] ?? -1);
        picked = items.map((item, i) => !item.blocked && (before[i] >= 0 ? was.picked[before[i]] : item.picked !== false));
        const by = items.map(() => []);
        items.forEach((item, i) => {
            for (const j of item.needs)
                by[j].push(i);
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
        current = was && order.includes(was.current) ? was.current : "yes";
        // Once the list is laid out, as far as it goes.
        const y = was ? was.y : 0;
        Qt.callLater(() => {
            list.scrollTo(y);
            showRow();
        });
        open();
    }

    // The lines of text of a row of the list (a line to pick from, or a
    // line of `details`), each as `{ word, rest, color, error }`: the
    // keyword it starts with, with the spaces after it, and its color (or
    // none of both), what's after it, and whether it says why the line
    // can't be done (see ask's `blocked`). A line to pick from with a
    // `lead` starts with that, as its first line's word, in its color.
    function rowParts(row) {
        const pick = typeof row !== "string";
        const why = pick && typeof row.blocked === "string" ? row.blocked : "";
        const lead = pick && row.lead ? row.lead : null;
        return (pick ? row.text : row).split("\n").map((line, i) => {
            if (lead && i === 0) {
                // With the spaces after it, as a keyword.
                const end = lead.length + /^\s*/.exec(line.slice(lead.length))[0].length;
                return { word: line.slice(0, end), rest: line.slice(end), color: lead.color, error: false };
            }
            const m = /^(\S+)(\s+)(.*)$/.exec(line);
            const kind = m ? keywords[m[1]] : undefined;
            const colored = typeof kind === "string";
            return {
                word: colored ? m[1] + m[2] : "",
                rest: colored ? m[3] : line,
                color: colored ? theme.changeColor(kind) : "",
                error: why !== "" && line.endsWith(why)
            };
        });
    }

    // What Copy copies: the rows v selected, or all of the list, as text.
    function copyText() {
        if (!items.length)
            return details;
        const first = anchor < 0 ? 0 : Math.min(anchor, row), last = anchor < 0 ? items.length - 1 : Math.max(anchor, row);
        return items.slice(first, last + 1).map(item => item.text).join(spaced ? "\n\n" : "\n");
    }

    // Where the question's lines are, for ask's `again` to ask it again so
    // after another question.
    function place() {
        return { texts: items.map(item => item.text), picked: picked, row: row, shown: rowShown,
            y: list.contentY - list.originY, current: current };
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

    // Whether `choice` ("yes", "no", "cancel", "extra", "undo", or "all",
    // Select All) can be answered now: with lines to pick from, Yes and
    // the button apart only once one is picked, and Select All if Yes can
    // do any of them.
    function canAnswer(choice) {
        const none = items.length > 0 && pickedCount === 0;
        return choice === "all" ? items.some(item => !item.blocked)
            : choice === "yes" ? !blockedPicked && !none
            : choice === "extra" ? extra !== null && !none
            : choice === "undo" ? undoAction !== null : true;
    }

    // Answers `choice`, whose action gets the picked lines, or `lines`
    // (Y, D: see answerHighlighted), which Yes can't do if one of
    // them is a line it can't do.
    function answer(choice, lines) {
        // Select All's, which leaves the question open.
        if (choice === "all") {
            if (canAnswer(choice))
                clickAll();
            return;
        }
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

    // Left and Right: moves the highlight to the next button that's on
    // (`step` 1), or the one before (-1), round from the last to the first.
    function moveCurrent(step) {
        const n = order.length;
        let i = order.indexOf(current);
        for (let tried = 0; tried < n; tried++) {
            i = (i + step + n) % n;
            if (canAnswer(order[i]))
                break;
        }
        current = order[i];
    }

    // A click on row `i`: picks it or leaves it out, as Space on it.
    function clickRow(i) {
        row = i;
        rowShown = true;
        anchor = -1;
        toggle(i);
    }

    // Select All: a, without showing the current row.
    function clickAll() {
        anchor = -1;
        pickAll();
    }

    // Scrolls to the current row, if it's shown.
    function showRow() {
        if (items.length && rowShown)
            list.positionViewAtIndex(row, ListView.Contain);
    }

    onRowChanged: Qt.callLater(showRow)
    onRowShownChanged: Qt.callLater(showRow)

    // As wide as the question (up to a width it wraps past), the list and
    // the buttons take, but no wider than the window has room for.
    width: Math.min(parent ? parent.width - 48 * zoom : 500, Math.max(Math.min(questionText.implicitWidth, 560 * zoom),
        listWidth, buttons.sideBySide, (items.length ? 480 : 280) * zoom) + 2 * padding)
    closePolicy: Popup.CloseOnPressOutside
    onClosed: {
        // Closed by a click outside it.
        const after = afterAction;
        afterAction = null;
        if (after)
            after();
    }

    // A button of the question (`{ label, keys, answer }`): never with the
    // keys, which stay with the question. The highlighted one is in the
    // accent's color, as Enter clicks it.
    component Choice: TextButton {
        required property var modelData

        theme: dialog.theme
        focusPolicy: Qt.NoFocus
        primary: modelData.answer === dialog.current
        enabled: dialog.canAnswer(modelData.answer)
        text: modelData.label
        keys: modelData.keys
        onClicked: dialog.answer(modelData.answer)
    }

    // A row of the list: a line of `details`, or a line to pick from, with
    // its box, which a click picks or leaves out.
    component ListRow: Item {
        id: listRow

        required property var modelData
        required property int index
        readonly property bool pickable: typeof modelData !== "string"
        readonly property bool blocked: pickable && !!modelData.blocked
        readonly property bool isPicked: pickable && dialog.picked[index] === true
        readonly property bool isCurrent: pickable && dialog.rowShown && index === dialog.row
        // One of the rows v selected.
        readonly property bool selected: pickable && dialog.anchor >= 0 && index >= Math.min(dialog.anchor, dialog.row)
            && index <= Math.max(dialog.anchor, dialog.row)

        width: list.width
        implicitHeight: body.implicitHeight + 2 * dialog.rowPad
        Accessible.role: pickable ? Accessible.CheckBox : Accessible.StaticText
        Accessible.name: pickable ? modelData.text : modelData
        Accessible.checkable: pickable
        Accessible.checked: isPicked

        // The rows v selected as the editor's marked lines.
        Rectangle {
            anchors.fill: parent
            radius: 3 * dialog.zoom
            color: listRow.selected ? dialog.theme.marked : listRow.isCurrent ? dialog.theme.checked
                : rowHover.hovered ? dialog.theme.hover : "transparent"
        }

        HoverHandler {
            id: rowHover

            enabled: listRow.pickable
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            enabled: listRow.pickable
            onTapped: dialog.clickRow(listRow.index)
        }

        // The box, beside the first line of text: checked if the line is
        // picked, and crossed out if Yes can't do it (in the error's
        // color once it's picked, which is only for the button apart).
        Rectangle {
            x: dialog.rowMargin
            y: dialog.rowPad + Math.round((dialog.lineHeight - height) / 2)
            width: dialog.boxSize
            height: dialog.boxSize
            visible: listRow.pickable
            radius: 3 * dialog.zoom
            color: !listRow.isPicked ? dialog.theme.field : listRow.blocked ? dialog.theme.error : dialog.theme.accent
            border.color: listRow.isPicked ? color : dialog.theme.fieldBorder
            opacity: listRow.blocked && !listRow.isPicked ? 0.6 : 1

            Icon {
                anchors.centerIn: parent
                visible: listRow.isPicked || listRow.blocked
                theme: dialog.theme
                path: !listRow.blocked ? "M4 8.5 L7 11.5 L12 5"
                    : listRow.isPicked ? "M4.5 4.5 L11.5 11.5 M11.5 4.5 L4.5 11.5" : "M4.5 11.5 L11.5 4.5"
                color: listRow.isPicked ? dialog.theme.highlightedText : dialog.theme.text
            }
        }

        // Its lines of text: a keyword in its color, and the rest, which
        // wraps under itself.
        Column {
            id: body

            x: dialog.textX
            y: dialog.rowPad
            // Less the room for the scroll bar, which is over the row:
            // the width can't depend on needing one, as that depends on
            // the height, which depends on the width.
            width: listRow.width - x - dialog.rowMargin - bar.width

            Repeater {
                model: dialog.rowParts(listRow.modelData)

                Item {
                    id: line

                    required property var modelData

                    width: body.width
                    // An empty line (between the lines `details` lists)
                    // is half a line tall.
                    implicitHeight: modelData.word === "" && modelData.rest === "" ? dialog.lineHeight / 2
                        : Math.max(word.implicitHeight, rest.implicitHeight)
                    // What Yes can't do is dimmed, but why.
                    opacity: listRow.blocked && !modelData.error ? 0.6 : 1

                    // As wide as its characters: a Text leaves the spaces
                    // it ends with out of its width.
                    Text {
                        id: word

                        width: line.modelData.word.length * dialog.charWidth
                        text: line.modelData.word
                        font: dialog.theme.font
                        color: line.modelData.color || dialog.theme.text
                        textFormat: Text.PlainText
                    }
                    Text {
                        id: rest

                        x: word.width
                        width: line.width - x
                        text: line.modelData.rest
                        font: dialog.theme.font
                        color: line.modelData.error ? dialog.theme.error : dialog.theme.text
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }

    // A key of the list, or two, and what they do.
    component KeyHint: Row {
        id: hint

        required property var modelData

        spacing: 4 * dialog.zoom

        Repeater {
            model: hint.modelData.keys

            KeyCap {
                required property string modelData

                anchors.verticalCenter: parent?.verticalCenter
                theme: dialog.theme
                text: modelData
                fontSize: Math.round(11 * dialog.zoom)
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: hint.modelData.label
            font.pixelSize: Math.round(12 * dialog.zoom)
            color: dialog.theme.dim
            textFormat: Text.PlainText
        }
    }

    contentItem: ColumnLayout {
        id: content

        spacing: 12 * dialog.zoom
        focus: true

        Keys.onPressed: event => {
            if (event.matches(StandardKey.Copy))
                dialog.system?.setClipboardText(dialog.copyText(), "");
            else if (event.modifiers & ~(Qt.ShiftModifier | Qt.KeypadModifier))
                return;
            else if (event.key === Qt.Key_Left || event.key === Qt.Key_H || event.key === Qt.Key_Backtab)
                dialog.moveCurrent(-1);
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_L || event.key === Qt.Key_Tab)
                dialog.moveCurrent(1);
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
                dialog.clickAll();
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J)
                list.scrollBy(dialog.lineHeight);
            else if (event.key === Qt.Key_Up || event.key === Qt.Key_K)
                list.scrollBy(-dialog.lineHeight);
            else if (event.key === Qt.Key_G)
                list.scrollTo(event.modifiers & Qt.ShiftModifier ? list.maxY : 0);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                dialog.answer(dialog.current);
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
        CodeLabel {
            id: questionText

            Layout.fillWidth: true
            theme: dialog.theme
            markup: dialog.text
            font.pixelSize: Math.round(14 * dialog.zoom)
            color: dialog.theme.text
        }

        // The list, on the editor's background, as its text is in the
        // editor's font: as tall as its rows, but no taller than the
        // window has room for.
        Rectangle {
            id: listFrame

            readonly property real margin: 4 * dialog.zoom
            // What else the box has, with the room around it.
            readonly property real others: 48 * dialog.zoom + 2 * dialog.padding + questionText.height + buttons.implicitHeight
                + (hintRow.visible ? hintRow.height + content.spacing : 0) + 2 * content.spacing

            Layout.fillWidth: true
            // Until the rows are laid out, as tall as their lines
            // unwrapped take, which has the ListView make them.
            Layout.preferredHeight: Math.min((list.contentHeight > 0 ? list.contentHeight : dialog.listHeight) + 2 * margin,
                Math.max(dialog.lineHeight + 2 * dialog.rowPad + 2 * margin,
                    (dialog.parent ? dialog.parent.height : 500) - others))
            visible: dialog.rowCount > 0
            radius: 4 * dialog.zoom
            color: dialog.theme.base
            border.color: dialog.theme.panelBorder

            // Only the rows in view are made. The wheel and the trackpad
            // scroll it, not a drag (as a WheelFlickable), and it never
            // has the keys.
            ListView {
                id: list

                readonly property real maxY: Math.max(0, contentHeight - height)

                // To `y` from the list's top.
                function scrollTo(y) {
                    contentY = originY + Math.max(0, Math.min(maxY, y));
                }

                function scrollBy(dy) {
                    scrollTo(contentY - originY + dy);
                }

                anchors.fill: parent
                anchors.margins: listFrame.margin
                clip: true
                interactive: false
                keyNavigationEnabled: false
                model: dialog.items.length ? dialog.items : dialog.lines
                spacing: dialog.rowGap
                Accessible.role: Accessible.List

                ScrollBar.vertical: ScrollBar {
                    id: bar
                }

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => list.scrollBy(-(event.pixelDelta.y || event.angleDelta.y / 120 * 60 * dialog.zoom))
                }

                delegate: ListRow {}
            }
        }

        // The keys of a list to pick from that no button shows.
        Flow {
            id: hintRow

            Layout.fillWidth: true
            visible: dialog.items.length > 0
            spacing: 12 * dialog.zoom

            Repeater {
                model: dialog.hints

                KeyHint {}
            }
        }

        // The buttons: the list's on the left, and the choices on the
        // right, or under them where the box is too narrow for both.
        GridLayout {
            id: buttons

            // How wide they are side by side.
            readonly property real sideBySide: tools.implicitWidth + columnSpacing + answers.implicitWidth

            Layout.fillWidth: true
            columns: dialog.items.length && sideBySide > dialog.availableWidth ? 1 : 2
            columnSpacing: 8 * dialog.zoom
            rowSpacing: 8 * dialog.zoom

            RowLayout {
                id: tools

                Layout.fillWidth: true
                spacing: 8 * dialog.zoom

                Choice {
                    visible: dialog.items.length > 0
                    modelData: ({ label: dialog.allPicked ? qsTr("Select None") : qsTr("Select All"), keys: "a", answer: "all" })
                }
                Choice {
                    visible: dialog.extra !== null
                    modelData: ({ label: dialog.extra?.label ?? "", keys: dialog.extraKeys, answer: "extra" })
                }

                // How many are picked.
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4 * dialog.zoom
                    visible: dialog.items.length > 0
                    text: qsTr("%1 of %2").arg(dialog.pickedCount).arg(dialog.items.length)
                    font.pixelSize: Math.round(12 * dialog.zoom)
                    color: dialog.theme.dim
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                id: answers

                Layout.alignment: Qt.AlignRight
                spacing: 8 * dialog.zoom

                Repeater {
                    model: dialog.choices

                    Choice {}
                }
            }
        }
    }
}
