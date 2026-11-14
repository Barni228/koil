pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A question in a box over the editor like :help's, with its choices as
// buttons, Yes, No and Cancel, each with the key that answers it: y answers
// yes, n no, and c or Esc cancels. Yes and No are named by what they do, if
// the question says (Apply, Don't Save), with the same keys. Yes is in the
// accent's color, and Enter answers it: no key makes another button the
// one Enter clicks (h, l and Tab moved a highlight through them at first,
// which was little use). It keeps the keys itself: no button takes them. The question is in the window's font, with `code` in
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
// list: the rows v selected, or all of it. The lines to pick from can be in
// groups (the undo history's applies), each a heading over its lines, with
// a box that picks them all. Then the cursor is on all of a group, and j
// and k go from group to group, Space picks all of one, and Y and D take
// it, until l (or Right, or Tab) goes into it: there it's on one of its
// lines, the first at first, and j and k stay in the group, until h (or
// Left, or Tab again) goes out. A group with many lines shows only some
// while the cursor isn't in it (those picked first), then a row that says
// how many more it has, and after its heading how many of its lines are of
// each kind; going into it shows them all (see ask's `groups`).
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
    // The groups the lines to pick from are in, if any (see ask's
    // `groups`), each a heading over its lines, and the lines of each; and
    // the group the cursor is in (-1: none, see goIn), where it's on a line
    // rather than on all of a group.
    property var groups: []
    property var groupItems: []
    property int inside: -1
    // How many lines of a closed group still show, under its heading,
    // before the row that says how many more it has; and for each group,
    // the keywords its lines start with and how many do, most first
    // (`{ word, count }`), or none if a line starts with none, which a
    // closed one's heading shows (see groupNote).
    property int preview: 3
    property var groupKinds: []
    // The rows of a list to pick from, as shown (see updateRows): `{ item
    // }`, a line, by its index, and with groups `{ group }`, a group's
    // heading, with its lines after it, or if it's closed only the first
    // of them, then `{ more }`, a row for the others (by its group). And
    // what tells each line apart, for a question asked again (see place).
    property var rows: []
    property var itemKeys: []
    readonly property int pickedCount: picked.filter(p => p).length
    // Whether a line Yes can't do is picked, which turns Yes off, and
    // whether all it can do are (Select All then picks none).
    readonly property bool blockedPicked: items.some((item, i) => item.blocked && picked[i])
    readonly property bool allPicked: !items.some((item, i) => !item.blocked && !picked[i])
    // The row j and k move (its index in `rows`, which is a line's own
    // without groups), and Space picks or leaves out, and whether it's
    // highlighted (see moveRow), and the other end of the rows v selected
    // with it, or -1. With groups, it's a group's heading while the cursor
    // isn't in one, and the cursor is on all of that group's rows
    // (`cursorRows`, the first and last of them; `selectedRows`, of those
    // v selected, or -1).
    property int row: 0
    property bool rowShown: false
    property int anchor: -1
    readonly property var cursorRows: spanOf(row)
    readonly property var selectedRows: anchor < 0 ? [-1, -1]
        : [Math.min(spanOf(anchor)[0], cursorRows[0]), Math.max(spanOf(anchor)[1], cursorRows[1])]
    // The list's text, measured as it's asked (see ask): how many
    // characters its longest line has, how many lines each line to pick
    // from takes, or the list as text (an empty one counts half, as it's
    // drawn), so how many the rows shown have, and whether a line to pick
    // takes several.
    property int longest: 0
    property var itemLines: []
    property real detailLines: 0
    readonly property real textLines: !items.length ? detailLines
        : rows.reduce((count, row) => count + (row.item === undefined ? 1 : itemLines[row.item] ?? 1), 0)
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
    readonly property real textGap: 8 * zoom
    // With groups, the room before a heading's box for its arrow, and how
    // much further in a line's box is: under its heading's text.
    readonly property real groupIndent: groups.length ? 14 * zoom : 0
    readonly property real itemIndent: groups.length ? boxSize + textGap : 0
    readonly property real textX: rowMargin + (items.length ? groupIndent + itemIndent + boxSize + textGap : 0)
    readonly property real rowGap: spaced ? 4 * zoom : 0
    readonly property int rowCount: items.length ? rows.length : lines.length
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
    // The key of the button apart, as its button shows it (`d`).
    readonly property string extraKeys: extra ? String.fromCharCode(extra.key).toLowerCase() : ""
    // The keys of a list to pick from that no button shows, listed under
    // it: `{ keys, label }` each.
    readonly property var hints: !items.length ? [] : [
        { keys: ["j", "k"], label: "move" },
        { keys: ["Space"], label: "pick" },
        { keys: ["v"], label: "select" }
    ].concat(groups.length ? [{ keys: ["l", "h", "Tab"], label: "go in, out" }] : [],
        [{ keys: ["Y"].concat(extra ? [extraKeys.toUpperCase()] : []), label: "current row only" }],
        undoAction ? [{ keys: ["u"], label: "undo" }] : [])

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
    // are in that color (when an apply was made, by how old it is), and
    // `group`, the index of the group it's in (see `groups`): then
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
    // the same keys; `groups`, which the lines are in (each has its
    // `group`, a group's lines one after another, in the groups' order),
    // `{ key, text, lead, open, note }` each: a heading over its lines,
    // with `text` (and its `lead`), and `note` after it, dimmed, whose box
    // picks them all or leaves them out, and shows whether all, some or
    // none are picked; its lines show under it, further in, but if `open`
    // is false only some of them (`preview`, see previewOf), with a row
    // after them that says how many more it has, while the cursor isn't in
    // it (l goes into it, or a click on that row or the heading's arrow;
    // h goes out), and then its heading shows how many of its lines start
    // with each keyword in place of `note`; one with too few lines for
    // that always shows them all; and `key` tells it apart from the
    // others, also asked again; and
    // `again`, to ask
    // it again with other lines as if it never closed: those of the last
    // question (by their text, and their group's key) are picked as they
    // were, the cursor in the group it was in, the current line
    // stays on its line (or goes to the next one left, or else the last),
    // and it's highlighted, and the list scrolled
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
        // No rows while their lines are replaced.
        rows = [];
        items = pick ? details : [];
        groups = pick && options.groups || [];
        const inGroup = groups.map(() => []);
        if (groups.length)
            items.forEach((item, i) => inGroup[item.group].push(i));
        groupItems = inGroup;
        dialog.details = pick ? "" : details || "";
        let most = 0, count = 0;
        const counts = [];
        for (const text of pick ? details.map(item => item.text) : dialog.lines) {
            const before = count;
            for (const line of text.split("\n")) {
                most = Math.max(most, line.length);
                count += line === "" ? 0.5 : 1;
            }
            counts.push(count - before);
        }
        // The keyword each line of a group starts with, if they all do.
        groupKinds = inGroup.map(lines => {
            const counts = [], at = Object.create(null);
            for (const i of lines) {
                const word = /^\S*/.exec(items[i].text)[0];
                if (typeof dialog.keywords[word] !== "string")
                    return [];
                if (at[word] === undefined) {
                    at[word] = counts.length;
                    counts.push({ word: word, count: 0 });
                }
                counts[at[word]].count += 1;
            }
            // Most first; a sort keeps the order of those with as many.
            return counts.sort((a, b) => b.count - a.count);
        });
        groups.forEach((group, g) => {
            const kinds = groupKinds[g].reduce((length, kind) => length + String(kind.count).length + kind.word.length + 4, 0);
            most = Math.max(most, group.text.length + Math.max(group.note ? group.note.length : 0, kinds) + 2
                - itemIndent / charWidth);
        });
        longest = Math.ceil(most);
        itemLines = pick ? counts : [];
        detailLines = pick ? 0 : count;
        // A group's lines are told apart from the next one's by its heading.
        spaced = pick && !groups.length && details.some(item => item.text.includes("\n"));
        itemKeys = items.map(item => (groups.length ? groups[item.group].key + "\n" : "") + item.text);
        // Each line's index in the last question, or -1 (an object of
        // keys: a Set is slow, see CLAUDE.md).
        const index = Object.create(null);
        was?.keys.forEach((key, i) => index[key] = i);
        const before = itemKeys.map(key => index[key] ?? -1);
        picked = items.map((item, i) => !item.blocked && (before[i] >= 0 ? was.picked[before[i]] : item.picked !== false));
        const by = items.map(() => []);
        items.forEach((item, i) => {
            for (const j of item.needs)
                by[j].push(i);
        });
        neededBy = by;
        // In the group it was in, if that's still there.
        inside = was && groups.length && was.inside !== null ? groups.findIndex(group => group.key === was.inside) : -1;
        updateRows();
        anchor = -1;
        const last = Math.max(0, rows.length - 1);
        // With groups, the row it was on (a group that's closed now has
        // other rows after it), else as the lines are now.
        const same = was && groups.length ? rows.findIndex(at => rowKey(at) === was.rowKey) : -1;
        row = options.row !== undefined ? Math.max(0, Math.min(options.row, last))
            : !was ? 0 : same >= 0 ? same : groups.length ? Math.min(was.row, last) : rowAfter(before, was.row);
        rowShown = was ? was.shown : !!options.showRow;
        dialog.question = question;
        yesAction = yes;
        noAction = no || null;
        afterAction = after || null;
        // Once the list is laid out, as far as it goes.
        const y = was ? was.y : 0;
        Qt.callLater(() => {
            list.scrollTo(y);
            showRow();
        });
        open();
    }

    // Makes `rows` what the list shows (see shownRows).
    function updateRows() {
        rows = shownRows();
    }

    // What the list shows: its lines, or with groups, each one's heading,
    // and its lines, or of a closed one only some of them (see previewOf)
    // and a row for the others.
    function shownRows() {
        const shown = [];
        if (!groups.length) {
            items.forEach((item, i) => shown.push({ item: i }));
        } else {
            groups.forEach((group, g) => {
                const open = isOpen(g);
                shown.push({ group: g });
                for (const i of open ? groupItems[g] : previewOf(g))
                    shown.push({ item: i });
                if (!open)
                    shown.push({ more: g });
            });
        }
        return shown;
    }

    // The lines of a closed group `g` that show: the first `preview` of
    // those picked, and if they're fewer, the first of the others, in
    // their order, so what's picked of it shows.
    function previewOf(g) {
        const lines = groupItems[g], shown = lines.filter(i => picked[i]).slice(0, preview);
        for (const i of lines) {
            if (shown.length >= preview)
                break;
            if (!picked[i])
                shown.push(i);
        }
        return shown.sort((a, b) => a - b);
    }

    // After the picks changed: shows other lines of the closed groups, if
    // they show others now (see previewOf), with the list scrolled as far.
    function syncRows() {
        if (!groups.some((group, g) => !isOpen(g)))
            return;
        const now = shownRows();
        if (now.length === rows.length && now.every((at, r) => at.item === rows[r].item))
            return;
        const y = list.contentY - list.originY;
        rows = now;
        Qt.callLater(() => {
            list.scrollTo(y);
            showRow();
        });
    }

    // Whether group `g` is closed while the cursor isn't in it: if it says
    // so (`open` false), and that hides more than the row for its other
    // lines takes.
    function canClose(g) {
        return groups[g]?.open === false && (groupItems[g] || []).length > preview + 1;
    }

    // Whether all of group `g`'s lines show.
    function isOpen(g) {
        return inside === g || !canClose(g);
    }

    // The row of group `g`'s heading.
    function headingRow(g) {
        return rows.findIndex(at => at.group === g);
    }

    // The first and last of the rows the cursor covers, on row `r`: that
    // row, or with groups, while the cursor isn't in one, all of the rows
    // of the group whose heading it is.
    function spanOf(r) {
        if (!groups.length || inside >= 0)
            return [r, r];
        let last = r;
        while (last + 1 < rows.length && rows[last + 1].group === undefined)
            last += 1;
        return [r, last];
    }

    // What the row for a closed group's other lines says.
    function moreText(g) {
        return qsTr("… %1 more").arg((groupItems[g] || []).length - preview);
    }

    // What tells the row `at` (one of `rows`) apart from the others.
    function rowKey(at) {
        return at.group !== undefined ? "group\n" + groups[at.group].key
            : at.more !== undefined ? "more\n" + groups[at.more].key : itemKeys[at.item];
    }

    // The group the row `at` is of, or in.
    function groupOf(at) {
        return at.group !== undefined ? at.group : at.more !== undefined ? at.more : items[at.item].group;
    }

    // How many of group `g`'s lines are picked: none (0), some (1), or all
    // that Yes can do, and so the others only if they're all picked (2).
    function groupPicks(g) {
        const lines = groupItems[g] || [];
        if (!lines.some(i => picked[i]))
            return 0;
        return lines.every(i => picked[i] || items[i].blocked) ? 2 : 1;
    }

    // Whether Yes can do none of group `g`'s lines.
    function groupBlocked(g) {
        return (groupItems[g] || []).every(i => items[i].blocked);
    }

    // What goes after group `g`'s heading, as styled text: its `note`, or
    // while it's closed, how many of its lines start with each keyword,
    // the keywords in their colors (`18 MOVE · 4 TRASH`), as most of them
    // don't show then; and whether it's that.
    function groupNote(g) {
        const escaped = text => text.replace(/&/g, "&amp;").replace(/</g, "&lt;");
        if (!showsKinds(g))
            return escaped(groups[g]?.note ?? "");
        return groupKinds[g].map(kind => kind.count + " <font color=\"" + theme.changeColor(keywords[kind.word]) + "\">"
            + escaped(kind.word) + "</font>").join(" · ");
    }

    function showsKinds(g) {
        return g < groups.length && !isOpen(g) && (groupKinds[g] || []).length > 0;
    }

    // l: goes into the current group, so the cursor is on a line of it, its
    // first, and all its lines show; but only shows the cursor if it isn't
    // shown yet, as j does.
    function goIn() {
        if (!groups.length || inside >= 0 || !rows.length)
            return;
        if (rowShown)
            putIn(groupOf(rows[row]));
        rowShown = true;
    }

    // h: goes out of the group the cursor is in, so it's on all of it
    // again, and it closes, if it's one that does.
    function goOut() {
        if (inside >= 0)
            putIn(-1);
    }

    // Puts the cursor in group `g`, on its first line (or with -1 out of
    // the one it's in, on all of that), with the list scrolled as far as
    // it was.
    function putIn(g) {
        if (g === inside || (g >= 0 && !groupItems[g].length))
            return;
        const from = inside >= 0 ? inside : rows.length ? groupOf(rows[row]) : 0;
        const y = list.contentY - list.originY;
        inside = g;
        anchor = -1;
        updateRows();
        row = g >= 0 ? headingRow(g) + 1 : headingRow(from);
        rowShown = true;
        // Once the list is laid out, as in ask.
        Qt.callLater(() => {
            list.scrollTo(y);
            showRow();
        });
    }

    // The lines of rows `first` to `last`, in order: a line's own, and a
    // heading's, its group's (the row for a closed group's other lines
    // has none, as it only opens it). With `toPick`, those Space would
    // pick: a line that can be picked, and of a group, those Yes can do,
    // or if it can do none, those that can be picked.
    function linesOf(first, last, toPick) {
        const lines = [], seen = items.map(() => false);
        const add = i => {
            if (!seen[i])
                lines.push(i);
            seen[i] = true;
        };
        for (let r = first; r <= last && r < rows.length; r++) {
            const at = rows[r];
            if (at.more !== undefined)
                continue;
            if (at.item !== undefined) {
                if (!toPick || canPick(at.item))
                    add(at.item);
                continue;
            }
            const all = groupItems[at.group], can = all.filter(i => !items[i].blocked);
            (!toPick ? all : can.length ? can : all.filter(i => canPick(i))).forEach(add);
        }
        return lines.sort((a, b) => a - b);
    }

    // The lines of text of a row of the list (a line to pick from, a
    // group's heading, or a line of `details`), each as `{ word, rest, color, error }`: the
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

    // What Copy copies: the rows v selected, or all of the list, as text,
    // with groups each one's heading and its lines after it, further in
    // (also those of a closed one, when it's all of the list).
    function copyText() {
        if (!items.length)
            return details;
        const inner = i => groups.length ? "  " + items[i].text.replace(/\n/g, "\n  ") : items[i].text;
        if (anchor < 0 && groups.length)
            return groups.map((group, g) => [group.text].concat(groupItems[g].map(inner)).join("\n")).join("\n");
        const first = anchor < 0 ? 0 : Math.min(anchor, row), last = anchor < 0 ? rows.length - 1 : Math.max(anchor, row);
        return rows.slice(first, last + 1).map(at => at.group !== undefined ? groups[at.group].text
            : at.more !== undefined ? "  " + moreText(at.more) : inner(at.item))
            .join(spaced ? "\n\n" : "\n");
    }

    // Where the question's lines are, for ask's `again` to ask it again so
    // after another question: what tells each line apart and whether it's
    // picked, the group the cursor is in (by its key), and the current
    // row, by its index and what tells it apart.
    function place() {
        return { keys: itemKeys, picked: picked, row: row, rowKey: row < rows.length ? rowKey(rows[row]) : "",
            shown: rowShown, inside: inside >= 0 ? groups[inside].key : null, y: list.contentY - list.originY };
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

    // Space and x: toggles the current line, or the lines v selected (a
    // heading's are its group's): all of them picked, if one is left out,
    // else all left out, which ends the selection.
    function toggleSelected() {
        const lines = linesOf(anchor < 0 ? row : Math.min(anchor, row), Math.max(anchor, row), true);
        anchor = -1;
        if (lines.length)
            setPicked(lines, lines.some(i => !picked[i]));
    }

    // Y and D: answers `choice` with the current line, or the lines
    // v selected, but only shows the current line if it isn't yet, as the
    // first j does.
    function answerHighlighted(choice) {
        if (!rowShown) {
            rowShown = true;
            return;
        }
        const lines = chosenLines();
        if (lines.length)
            answer(choice, lines);
    }

    // The current line, or the lines v selected, which ends the selection.
    function chosenLines() {
        const lines = linesOf(anchor < 0 ? row : Math.min(anchor, row), Math.max(anchor, row), false);
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
        syncRows();
    }

    // j and k: moves the current line by `step`, but only shows it if it
    // isn't yet, as the user hasn't seen where it is. With groups, to the
    // next group that way, or while the cursor is in one, to its next
    // line, as far as its first or last.
    function moveRow(step) {
        if (!rowShown) {
            rowShown = true;
        } else if (!groups.length) {
            row = Math.max(0, Math.min(rows.length - 1, row + step));
        } else if (inside >= 0) {
            const first = headingRow(inside) + 1;
            row = Math.max(first, Math.min(first + groupItems[inside].length - 1, row + step));
        } else {
            let to = row + step;
            while (to >= 0 && to < rows.length && rows[to].group === undefined)
                to += step;
            if (to >= 0 && to < rows.length)
                row = to;
        }
    }

    // g and G: makes the first line the current one (or the last, with
    // `last`), shown at once, as where it goes doesn't depend on where it
    // was. With groups, the first or last group, or while the cursor is in
    // one, its first or last line.
    function moveToEnd(last) {
        if (!groups.length) {
            row = last ? rows.length - 1 : 0;
        } else if (inside >= 0) {
            const first = headingRow(inside) + 1;
            row = last ? first + groupItems[inside].length - 1 : first;
        } else {
            row = headingRow(last ? groups.length - 1 : 0);
        }
        rowShown = true;
    }

    // Those Yes can do.
    function pickAll() {
        const all = items.some((item, i) => !item.blocked && !picked[i]);
        picked = items.map(item => all && !item.blocked);
        syncRows();
    }

    // A click on row `i`: picks it or leaves it out, as Space on it. With
    // groups, it's the line or the group clicked, wherever the cursor is,
    // which goes there only where that moves no row: to the group, or to
    // the line of the group it's in; and on the row for a closed group's
    // other lines, the cursor goes into the group, which shows them.
    function clickRow(i) {
        const at = rows[i];
        anchor = -1;
        if (!groups.length) {
            row = i;
            rowShown = true;
            toggleSelected();
            return;
        }
        if (at.more !== undefined) {
            putIn(at.more);
            return;
        }
        const g = groupOf(at), lines = linesOf(i, i, true);
        if (lines.length)
            setPicked(lines, lines.some(line => !picked[line]));
        if (inside >= 0 && (inside !== g || at.item === undefined))
            return;
        row = inside < 0 ? headingRow(g) : rows.findIndex(other => other.item === at.item);
        rowShown = true;
    }

    // Select All: a, without showing the current row.
    function clickAll() {
        anchor = -1;
        pickAll();
    }

    // Scrolls to the rows the cursor is on, if it's shown: to their last,
    // then their first, which shows if they don't all fit. Twice, as a
    // row made as the list jumps to it is placed by a guess of its
    // height: the last line of a row of two was cut off after G.
    function showRow() {
        if (!items.length || !rowShown || !rows.length)
            return;
        const last = Math.min(cursorRows[1], rows.length - 1), first = Math.min(cursorRows[0], last);
        for (let pass = 0; pass < 2; pass++) {
            if (last === rows.length - 1)
                list.positionViewAtEnd();
            else
                list.positionViewAtIndex(last, ListView.Contain);
            list.positionViewAtIndex(first, ListView.Contain);
            list.forceLayout();
        }
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
    // keys, which stay with the question. Yes is in the accent's color, as
    // Enter answers it.
    component Choice: TextButton {
        required property var modelData

        theme: dialog.theme
        focusPolicy: Qt.NoFocus
        primary: modelData.answer === "yes"
        enabled: dialog.canAnswer(modelData.answer)
        text: modelData.label
        keys: modelData.keys
        onClicked: dialog.answer(modelData.answer)
    }

    // A row of the list: a line of `details`, or a line to pick from, with
    // its box, which a click picks or leaves out, or a group's heading,
    // whose box is its lines', with an arrow before it, which a click opens
    // or closes it with.
    component ListRow: Item {
        id: listRow

        required property var modelData
        required property int index
        readonly property bool pickable: typeof modelData !== "string"
        readonly property bool isGroup: pickable && modelData.group !== undefined
        // The row for a closed group's other lines, which opens it.
        readonly property bool isMore: pickable && modelData.more !== undefined
        // Its line, or its group, if it's still there (the rows go before
        // the lines do, but a binding can run in between).
        readonly property var item: pickable && !isGroup && !isMore ? dialog.items[modelData.item] ?? null : null
        readonly property var group: isGroup ? dialog.groups[modelData.group] ?? null : null
        readonly property bool blocked: isGroup ? dialog.groupBlocked(modelData.group) : !!item?.blocked
        // Whether it's picked: 2, or for a heading, 1 if only some of its
        // lines are.
        readonly property int picks: isGroup ? dialog.groupPicks(modelData.group)
            : item && dialog.picked[modelData.item] === true ? 2 : 0
        // One of the rows the cursor is on, or of those v selected, and
        // those rows' first and last, whose corners are round.
        readonly property bool isCurrent: pickable && dialog.rowShown && index >= dialog.cursorRows[0]
            && index <= dialog.cursorRows[1]
        readonly property bool selected: pickable && dialog.anchor >= 0 && index >= dialog.selectedRows[0]
            && index <= dialog.selectedRows[1]
        readonly property var span: selected ? dialog.selectedRows : isCurrent ? dialog.cursorRows : [index, index]
        readonly property real boxX: dialog.rowMargin + dialog.groupIndent + (isGroup ? 0 : dialog.itemIndent)

        width: list.width
        // Whole pixels, so rows the cursor is on together show no line
        // between them.
        implicitHeight: Math.ceil(body.implicitHeight + 2 * dialog.rowPad)
        Accessible.role: isMore ? Accessible.Button : pickable ? Accessible.CheckBox : Accessible.StaticText
        Accessible.name: item?.text ?? group?.text ?? (isMore ? dialog.moreText(modelData.more) : pickable ? "" : modelData)
        Accessible.checkable: pickable && !isMore
        Accessible.checked: picks === 2

        // The rows v selected as the editor's marked lines; rows next to
        // each other are one shape: each goes a pixel under the next, in a
        // color that's the same where they overlap (see through, the
        // overlap was darker, and without it a line showed between them).
        Rectangle {
            readonly property real round: 3 * dialog.zoom
            readonly property bool joined: listRow.index < listRow.span[1]

            anchors.fill: parent
            anchors.bottomMargin: joined ? -1 : 0
            topLeftRadius: listRow.index === listRow.span[0] ? round : 0
            topRightRadius: topLeftRadius
            bottomLeftRadius: joined ? 0 : round
            bottomRightRadius: bottomLeftRadius
            color: listRow.selected ? Qt.tint(dialog.theme.base, dialog.theme.marked)
                : listRow.isCurrent ? Qt.tint(dialog.theme.base, dialog.theme.checked)
                : rowHover.hovered ? dialog.theme.hover : "transparent"
        }

        HoverHandler {
            id: rowHover

            enabled: listRow.pickable
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            enabled: listRow.pickable
            onTapped: point => {
                if (listRow.isGroup && point.position.x < listRow.boxX && dialog.canClose(listRow.modelData.group))
                    dialog.putIn(dialog.inside === listRow.modelData.group ? -1 : listRow.modelData.group);
                else
                    dialog.clickRow(listRow.index);
            }
        }

        // A heading's arrow, if its group can be closed: down while all its
        // lines show.
        Icon {
            x: dialog.rowMargin - 3 * dialog.zoom
            y: dialog.rowPad + Math.round((dialog.lineHeight - height) / 2)
            visible: listRow.isGroup && dialog.canClose(listRow.modelData.group)
            theme: dialog.theme
            path: "M6 4.5 L9.5 8 L6 11.5"
            rotation: listRow.isGroup && dialog.isOpen(listRow.modelData.group) ? 90 : 0
            color: dialog.theme.dim
        }

        // The box, beside the first line of text: checked if the line is
        // picked (a heading's with a dash, if only some of its lines are),
        // and crossed out if Yes can't do it (in the error's color once
        // it's picked, which is only for the button apart).
        Rectangle {
            x: listRow.boxX
            y: dialog.rowPad + Math.round((dialog.lineHeight - height) / 2)
            width: dialog.boxSize
            height: dialog.boxSize
            visible: listRow.pickable && !listRow.isMore
            radius: 3 * dialog.zoom
            color: !listRow.picks ? dialog.theme.field : listRow.blocked ? dialog.theme.error : dialog.theme.accent
            border.color: listRow.picks ? color : dialog.theme.fieldBorder
            opacity: listRow.blocked && !listRow.picks ? 0.6 : 1

            Icon {
                anchors.centerIn: parent
                visible: listRow.picks > 0 || listRow.blocked
                theme: dialog.theme
                path: listRow.blocked ? (listRow.picks ? "M4.5 4.5 L11.5 11.5 M11.5 4.5 L4.5 11.5" : "M4.5 11.5 L11.5 4.5")
                    : listRow.picks === 1 ? "M4.5 8 L11.5 8" : "M4 8.5 L7 11.5 L12 5"
                color: listRow.picks ? dialog.theme.highlightedText : dialog.theme.text
            }
        }

        // After a heading's text, at the row's end (see groupNote): the
        // keywords of a closed one in the editor's font, as its lines'.
        Text {
            id: note

            readonly property bool kinds: listRow.isGroup && dialog.showsKinds(listRow.modelData.group)

            anchors.right: parent.right
            anchors.rightMargin: dialog.rowMargin + bar.width
            y: dialog.rowPad + Math.round((dialog.lineHeight - height) / 2)
            visible: text !== ""
            text: listRow.isGroup ? dialog.groupNote(listRow.modelData.group) : ""
            font.family: kinds ? dialog.theme.font.family : Application.font.family
            font.pixelSize: Math.round(12 * dialog.zoom)
            color: dialog.theme.dim
            textFormat: Text.StyledText
        }

        // Its lines of text: a keyword in its color, and the rest, which
        // wraps under itself.
        Column {
            id: body

            x: listRow.pickable ? listRow.boxX + dialog.boxSize + dialog.textGap : dialog.rowMargin
            y: dialog.rowPad
            // Less the room for the scroll bar, which is over the row:
            // the width can't depend on needing one, as that depends on
            // the height, which depends on the width.
            width: listRow.width - x - dialog.rowMargin - bar.width - (note.visible ? note.width + dialog.textGap : 0)

            Repeater {
                model: dialog.rowParts(listRow.isMore ? dialog.moreText(listRow.modelData.more)
                    : listRow.pickable ? listRow.item ?? listRow.group ?? "" : listRow.modelData)

                Item {
                    id: line

                    required property var modelData

                    width: body.width
                    // An empty line (between the lines `details` lists)
                    // is half a line tall.
                    implicitHeight: modelData.word === "" && modelData.rest === "" ? dialog.lineHeight / 2
                        : Math.max(word.implicitHeight, rest.implicitHeight)
                    // What Yes can't do is dimmed, but why, and so is
                    // the row for a group's other lines.
                    opacity: listRow.isMore || (listRow.blocked && !modelData.error) ? 0.6 : 1

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
            else if (event.key === Qt.Key_L || event.key === Qt.Key_Right)
                dialog.goIn();
            else if (event.key === Qt.Key_H || event.key === Qt.Key_Left)
                dialog.goOut();
            else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
                dialog.inside >= 0 ? dialog.goOut() : dialog.goIn();
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
                dialog.answer("yes");
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
                model: dialog.items.length ? dialog.rows : dialog.lines
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
