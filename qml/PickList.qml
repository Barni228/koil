pragma ComponentBehavior: Bound

import QtQuick

// A list to pick from, without a look: its lines, which of them are
// picked, the row the cursor is on and the rows v selected, the groups the
// lines are in, what's searched for, and the keys that do all that (see
// key), so every such list has the same keys, however it's drawn: a
// question's list (ConfirmDialog, like the undo history) and the
// shortcuts to export (ShortcutsWindow) each draw their rows their own
// way, from `rows`, `picked`, `row`, `rowShown` and `selectedRows`. What
// has the keys gives each key event to `key`, and does its own (Enter,
// what Y takes: see cursorLines) with those it leaves. The search is typed
// on a ListSearch.
//
// j and k (or Up and Down) move the current row (g and G to the first and
// last), Space or x picks it or leaves it out, along with the lines it
// needs or that need it, and a picks all of them, or none if all are. v
// selects rows, from the current one to where j and k take it, and Space
// or x then picks them all, or leaves them all out if they're all picked,
// which ends the selection, as Esc and v do. / searches (see Search). The
// current row is shown only once one of those keys is used (the first j
// or k shows it where it is, on the first row), unless the list shows it
// at once (see load). A line can be one that can't be done (`blocked`),
// which can't be picked, unless the list says so (`pickBlocked`). The
// lines can be in groups, each a heading over its lines. Then the cursor
// is on all of a group, and j and k go from group to group, and Space
// picks all of one, until l (or Right, or Tab) goes into it: there it's on
// one of its lines, the first at first, and j and k stay in the group,
// until h (or Left, or Tab again) goes out. A group with many lines shows
// only some while the cursor isn't in it (those picked first), then a row
// for the others; going into it shows them all (see load's `groups`).
QtObject {
    id: picks

    // The lines to pick from (see load), which of them are picked, and
    // which need each one (`needs` the other way round).
    property var items: []
    property var picked: []
    property var neededBy: []
    // Whether a line that can't be done can still be picked (a question
    // with a button for the picked lines other than Yes).
    property bool pickBlocked: false
    // The groups the lines are in, if any (see load's `groups`), each a
    // heading over its lines, and the lines of each; and the group the
    // cursor is in (-1: none, see goIn), where it's on a line rather than
    // on all of a group.
    property var groups: []
    property var groupItems: []
    property int inside: -1
    // ---- Search ----
    // / types a search (on a ListSearch): only the lines that have each of
    // its words show (in their text, or their group's heading, so a path's
    // dir can be one word and its name another), whatever the case, unless
    // a letter of it is uppercase (smart case). It's shown as it's typed;
    // Enter keeps it, and the keys are the list's again, on the lines left
    // (Space on a heading picks those of its lines that show, and a all
    // that show), and Esc puts back what was searched for before. Esc in
    // the list then shows all of it again. It only says what shows: a line
    // that's picked stays picked, shown or not. `filter` is the search
    // (what's typed, while `filtering`), `shown` whether each line has it
    // (null with no search), and `shownItems` each group's lines that do,
    // which is what a group has for the rows, the cursor and the picks
    // from its heading.
    property string filter: ""
    property bool filtering: false
    property string filterBefore: ""
    property var shown: null
    property var shownItems: []
    readonly property int shownCount: shown ? shown.filter(s => s).length : items.length
    // How many picked lines the search hides.
    readonly property int hiddenPicked: shown ? picked.filter((p, i) => p && !shown[i]).length : 0
    // The search's words, as one regex's source and flags, for what
    // matched in a row's text (see withMarks), or "": strings, as a var
    // property may not keep a RegExp as one.
    property string markSource: ""
    property string markFlags: ""
    // How many lines of a closed group still show, under its heading,
    // before the row for the others.
    property int preview: 3
    // The rows, as shown (see updateRows): `{ item }`, a line, by its
    // index, and with groups `{ group }`, a group's heading, with its
    // lines after it, or if it's closed only the first of them, then
    // `{ more }`, a row for the others (by its group). And what tells each
    // line apart, for a list loaded again (see place).
    property var rows: []
    property var itemKeys: []
    readonly property int pickedCount: picked.filter(p => p).length
    // Whether a line that can't be done is picked, and whether all that
    // can are, of the lines that show (Select All then picks none); not
    // with none of them to pick (a search no line has), so its button
    // isn't named Select None then, which is wider.
    readonly property bool blockedPicked: items.some((item, i) => item.blocked && picked[i])
    readonly property bool allPicked: !items.some((item, i) => !item.blocked && !picked[i] && isShown(i))
        && items.some((item, i) => !item.blocked && isShown(i))
    // The row j and k move (its index in `rows`, which is a line's own
    // without groups or a search), and Space picks or leaves out, and
    // whether it's shown (see moveRow), and the other end of the rows v
    // selected with it, or -1. With groups, it's a group's heading while
    // the cursor isn't in one, and the cursor is on all of that group's
    // rows (`cursorRows`, the first and last of them; `selectedRows`, of
    // those v selected, or -1).
    property int row: 0
    property bool rowShown: false
    property int anchor: -1
    readonly property var cursorRows: spanOf(row)
    readonly property var selectedRows: anchor < 0 ? [-1, -1]
        : [Math.min(spanOf(anchor)[0], cursorRows[0]), Math.max(spanOf(anchor)[1], cursorRows[1])]

    // The rows are made again: `replacing` before, where what draws them
    // can keep how far it's scrolled, and `replaced` after, where it
    // scrolls back there, or with `top` to its top, and then to the
    // cursor's rows. Not from load, after which the list places itself.
    signal replacing
    signal replaced(bool top)

    // Takes the lines `lines` to pick from, `{ text, needs }` each: its
    // text, which the search goes through (and which tells it apart, see
    // `was`), and the indexes of the lines it can't go without, if any. A
    // line can also have `picked: false` (left out at first; else it's
    // picked), `blocked` (it can't be done, nor then a line that needs it:
    // it starts left out, and can be picked only with `pickBlocked`), and
    // `group`, the index of the group it's in. `options` can have
    // `groups`, which the lines are in (each has its `group`, a group's
    // lines one after another, in the groups' order), `{ key, text, open }`
    // each: a heading over its lines, with `text`, whose row picks them
    // all or leaves them out; its lines show under it, but if `open` is
    // false only some of them (`preview`, see previewOf), with a row after
    // them for the others, while the cursor isn't in it (l goes into it, h
    // out); one with too few lines for that always shows them all; and
    // `key` tells it apart from the others, also loaded again; `showRow`,
    // to show the current row at once; `was`, what `place` gave of a list
    // before this one, to go on as if that never went: its lines still
    // here (by their text, and their group's key) are picked as they were,
    // the cursor is in the group it was in, the current row stays on its
    // line (or goes to the next one left, or else the last), shown if it
    // was, with what was searched for, if a line still has it; and `row`,
    // the current row's index instead.
    function load(lines, options) {
        options = options || {};
        const was = options.was || null;
        // No rows, nor a group's lines, while the lines are replaced.
        rows = [];
        shown = null;
        shownItems = [];
        groupItems = [];
        items = lines;
        groups = lines.length && options.groups || [];
        const inGroup = groups.map(() => []);
        if (groups.length)
            items.forEach((item, i) => inGroup[item.group].push(i));
        groupItems = inGroup;
        // Until the search is (see updateShown), all of them.
        shownItems = inGroup;
        itemKeys = items.map(item => (groups.length ? groups[item.group].key + "\n" : "") + item.text);
        // Each line's index in the last list, or -1 (an object of keys: a
        // Set is slow, see CLAUDE.md).
        const index = Object.create(null);
        was?.keys.forEach((key, i) => index[key] = i);
        const before = itemKeys.map(key => index[key] ?? -1);
        picked = items.map((item, i) => !item.blocked && (before[i] >= 0 ? was.picked[before[i]] : item.picked !== false));
        const by = items.map(() => []);
        items.forEach((item, i) => {
            for (const j of item.needs || [])
                by[j].push(i);
        });
        neededBy = by;
        // What was searched for, unless no line has it now.
        filtering = false;
        filter = items.length && was?.filter || "";
        updateShown();
        if (shown && !shownCount) {
            filter = "";
            updateShown();
        }
        // In the group it was in, if that's still there, with lines to show.
        inside = was && groups.length && was.inside !== null ? groups.findIndex(group => group.key === was.inside) : -1;
        if (inside >= 0 && !shownItems[inside].length)
            inside = -1;
        updateRows();
        anchor = -1;
        const last = Math.max(0, rows.length - 1);
        // With groups, the row it was on (a group that's closed now has
        // other rows after it), else as the lines are now.
        const same = was && groups.length ? rows.findIndex(at => rowKey(at) === was.rowKey) : -1;
        row = options.row !== undefined ? Math.max(0, Math.min(options.row, last))
            : !was ? 0 : same >= 0 ? same : groups.length ? Math.min(was.row, last)
            : rowFrom(rowAfter(before, was.line ?? was.row));
        rowShown = was ? was.shown : !!options.showRow;
    }

    // ---- Keys ----

    // A key of the list's, as its event: does what it does, and says
    // whether it was one (what has the keys then accepts it, or else does
    // its own with it). Not while the search is typed, whose keys are its
    // field's, nor with a modifier but Shift: j, k, Up and Down (moveRow),
    // g and G (moveToEnd), Space and x (toggleSelected), v, a (pickAll),
    // / (startFilter), with groups l, h, Left, Right and Tab (goIn,
    // goOut), and Esc, if it ends something (see stepBack).
    function key(event) {
        if (filtering || !items.length || (event.modifiers & ~(Qt.ShiftModifier | Qt.KeypadModifier)))
            return false;
        const k = event.key;
        if (k === Qt.Key_Slash || event.text === "/") {
            startFilter();
        } else if (groups.length && (k === Qt.Key_L || k === Qt.Key_Right)) {
            goIn();
        } else if (groups.length && (k === Qt.Key_H || k === Qt.Key_Left)) {
            goOut();
        } else if (groups.length && (k === Qt.Key_Tab || k === Qt.Key_Backtab)) {
            inside >= 0 ? goOut() : goIn();
        } else if (k === Qt.Key_Down || k === Qt.Key_J) {
            moveRow(1);
        } else if (k === Qt.Key_Up || k === Qt.Key_K) {
            moveRow(-1);
        } else if (k === Qt.Key_G) {
            moveToEnd(!!(event.modifiers & Qt.ShiftModifier));
        } else if (k === Qt.Key_Space || k === Qt.Key_X) {
            rowShown = true;
            toggleSelected();
        } else if (k === Qt.Key_V) {
            rowShown = true;
            anchor = anchor < 0 ? row : -1;
        } else if (k === Qt.Key_A) {
            rowShown = true;
            clickAll();
        } else if (k === Qt.Key_Escape) {
            return stepBack();
        } else {
            return false;
        }
        return true;
    }

    // Esc: ends the search being typed, putting the one before back, else
    // the rows v selected, else shows all the lines again; and says
    // whether there was any of those to end (if not, Esc is for what has
    // the list: it cancels).
    function stepBack() {
        if (filtering)
            finishFilter(false);
        else if (anchor >= 0)
            anchor = -1;
        else if (filter !== "")
            clearFilter();
        else
            return false;
        return true;
    }

    // What an uppercase key acts on (Y in a question): the current line,
    // or the lines v selected, picked or not, which ends the selection.
    // None if the cursor wasn't shown yet, which it only shows, as the
    // first j does.
    function cursorLines() {
        if (!rowShown) {
            rowShown = true;
            return [];
        }
        return chosenLines();
    }

    // Makes `rows` what the list shows (see shownRows).
    function updateRows() {
        rows = shownRows();
    }

    // ---- Search (see `filter`) ----

    // Whether the search leaves line `i`.
    function isShown(i) {
        return !shown || shown[i] === true;
    }

    // Finds the lines that have `filter` (see `shown`), and what the
    // groups have of them.
    function updateShown() {
        const words = filter.split(/\s+/).filter(word => word !== "")
            .map(word => word.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
        // Smart case, as vim's search.
        const flags = filter === filter.toLowerCase() ? "i" : "";
        if (!words.length || !items.length) {
            shown = null;
            shownItems = groupItems;
            markSource = "";
        } else {
            const has = words.map(word => new RegExp(word, flags));
            const inHeading = groups.map(group => has.map(re => re.test(group.text)));
            shown = items.map(item => has.every((re, w) => (groups.length && inHeading[item.group][w]) || re.test(item.text)));
            shownItems = groupItems.map(lines => lines.filter(i => shown[i]));
            // The longest first, so a word that starts another doesn't
            // take its place.
            markFlags = "g" + flags;
            markSource = words.slice().sort((a, b) => b.length - a.length).join("|");
        }
    }

    // Searches for `text`: shows only the lines that have it, with the
    // cursor on the row it was on, if that still shows, else in its group,
    // or on the first row.
    function setFilter(text) {
        if (text === filter || !items.length)
            return;
        const at = row < rows.length ? rows[row] : null;
        const key = at ? rowKey(at) : "", group = at && groups.length ? groupOf(at) : -1;
        filter = text;
        updateShown();
        if (inside >= 0 && !shownItems[inside].length)
            inside = -1;
        anchor = -1;
        updateRows();
        let to = rows.findIndex(other => rowKey(other) === key);
        if (to < 0 && group >= 0)
            to = inside >= 0 ? headingRow(inside) + 1 : headingRow(group);
        row = Math.max(0, to);
        replaced(true);
    }

    // /: types a search (its ListSearch takes the keys), starting from
    // the one there is.
    function startFilter() {
        if (!items.length || filtering)
            return;
        filterBefore = filter;
        filtering = true;
    }

    // Enter in the search (`accept`), which keeps it, with the cursor
    // shown, on a line that has it; or Esc, which puts the one before
    // back. The keys are the list's again.
    function finishFilter(accept) {
        if (!filtering)
            return;
        filtering = false;
        if (!accept)
            setFilter(filterBefore);
        if (!shown)
            clearFilter();
        else if (accept && rows.length)
            rowShown = true;
    }

    // Shows all the lines again.
    function clearFilter() {
        setFilter("");
    }

    // `text` as styled text with what the search matched in it underlined,
    // in `color`, or "" if nothing did. Styled text runs spaces together,
    // so one before another is a no-break one.
    function withMarks(text, color) {
        if (markSource === "" || text === "")
            return "";
        const re = new RegExp(markSource, markFlags);
        const escaped = part => part.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
            .replace(/ (?= )/g, "&nbsp;");
        let styled = "", at = 0;
        for (let m = re.exec(text); m !== null && m[0] !== ""; m = re.exec(text)) {
            styled += escaped(text.slice(at, m.index)) + "<u><font color=\"" + color + "\">" + escaped(m[0])
                + "</font></u>";
            at = m.index + m[0].length;
        }
        return at ? styled + escaped(text.slice(at)) : "";
    }

    // ---- Rows ----

    // The row of line `line` without groups, or of the first line after
    // it that shows, or else the last row.
    function rowFrom(line) {
        const r = rows.findIndex(at => at.item >= line);
        return r >= 0 ? r : Math.max(0, rows.length - 1);
    }

    // What the list shows: its lines (those that have what's searched
    // for, see `filter`), or with groups, each one's heading, and its
    // lines, or of a closed one only some of them (see previewOf) and a
    // row for the others.
    function shownRows() {
        const list = [];
        if (!groups.length) {
            items.forEach((item, i) => {
                if (isShown(i))
                    list.push({ item: i });
            });
        } else {
            groups.forEach((group, g) => {
                // Not a group the search leaves no line of.
                if (!shownItems[g].length)
                    return;
                const open = isOpen(g);
                list.push({ group: g });
                for (const i of open ? shownItems[g] : previewOf(g))
                    list.push({ item: i });
                if (!open)
                    list.push({ more: g });
            });
        }
        return list;
    }

    // The lines of a closed group `g` that show: the first `preview` of
    // those picked, and if they're fewer, the first of the others, in
    // their order, so what's picked of it shows.
    function previewOf(g) {
        const lines = shownItems[g], first = lines.filter(i => picked[i]).slice(0, preview);
        for (const i of lines) {
            if (first.length >= preview)
                break;
            if (!picked[i])
                first.push(i);
        }
        return first.sort((a, b) => a - b);
    }

    // After the picks changed: shows other lines of the closed groups, if
    // they show others now (see previewOf), with the list scrolled as far.
    function syncRows() {
        if (!groups.some((group, g) => !isOpen(g)))
            return;
        const now = shownRows();
        if (now.length === rows.length && now.every((at, r) => at.item === rows[r].item))
            return;
        replacing();
        rows = now;
        replaced(false);
    }

    // Whether group `g` is closed while the cursor isn't in it: if it says
    // so (`open` false), and that hides more than the row for its other
    // lines takes.
    function canClose(g) {
        return groups[g]?.open === false && (shownItems[g] || []).length > preview + 1;
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

    // What tells the row `at` (one of `rows`) apart from the others.
    function rowKey(at) {
        return at.group !== undefined ? "group\n" + groups[at.group].key
            : at.more !== undefined ? "more\n" + groups[at.more].key : itemKeys[at.item];
    }

    // The group the row `at` is of, or in.
    function groupOf(at) {
        return at.group !== undefined ? at.group : at.more !== undefined ? at.more : items[at.item].group;
    }

    // How many of group `g`'s lines (that show) are picked: none (0), some
    // (1), or all that can be done, and so the others only if they're all
    // picked (2).
    function groupPicks(g) {
        const lines = shownItems[g] || [];
        if (!lines.some(i => picked[i]))
            return 0;
        return lines.every(i => picked[i] || items[i].blocked) ? 2 : 1;
    }

    // Whether none of group `g`'s lines can be done.
    function groupBlocked(g) {
        return (shownItems[g] || []).every(i => items[i].blocked);
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
        if (g === inside || (g >= 0 && !shownItems[g].length))
            return;
        const from = inside >= 0 ? inside : rows.length ? groupOf(rows[row]) : 0;
        replacing();
        inside = g;
        anchor = -1;
        updateRows();
        row = g >= 0 ? headingRow(g) + 1 : headingRow(from);
        rowShown = true;
        replaced(false);
    }

    // The lines of rows `first` to `last`, in order: a line's own, and a
    // heading's, its group's that show (the row for a closed group's other
    // lines has none, as it only opens it). With `toPick`, those Space would
    // pick: a line that can be picked, and of a group, those that can be
    // done, or if none can, those that can be picked.
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
            const all = shownItems[at.group], can = all.filter(i => !items[i].blocked);
            (!toPick ? all : can.length ? can : all.filter(i => canPick(i))).forEach(add);
        }
        return lines.sort((a, b) => a - b);
    }

    // Where the list's lines are, for load's `was` to go on from after
    // another list: what tells each line apart and whether it's picked,
    // the group the cursor is in (by its key), the current row, by its
    // index, its line (without groups) and what tells it apart, and what's
    // searched for.
    function place() {
        const at = row < rows.length ? rows[row] : null;
        return { keys: itemKeys, picked: picked, row: row, line: at?.item ?? row, rowKey: at ? rowKey(at) : "",
            shown: rowShown, inside: inside >= 0 ? groups[inside].key : null, filter: filter };
    }

    // The line that's the current one loaded again (see load's `was`),
    // where `before` is each line's index in the last list (or -1), and
    // `was` the current one there: its own line, or else the first after
    // it that's still there, or else the last.
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

    // ---- Picks ----

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
        return closure(lines, j => items[j].needs || []);
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

    // Whether line `i` can be picked: not one that can't be done, unless
    // the list says so (`pickBlocked`).
    function canPick(i) {
        return !items[i].blocked || pickBlocked;
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
            for (const k of on ? items[j].needs || [] : neededBy[j])
                todo.push(k);
        }
        picked = p;
        syncRows();
    }

    // Those that can be done, or none if they all are; searching, of the
    // lines that show, with what they need, or what needs them.
    function pickAll() {
        const all = items.some((item, i) => !item.blocked && !picked[i] && isShown(i));
        if (!shown) {
            picked = items.map(item => all && !item.blocked);
            syncRows();
            return;
        }
        const lines = [];
        items.forEach((item, i) => {
            if (shown[i] && (all ? !item.blocked : picked[i]))
                lines.push(i);
        });
        setPicked(lines, all);
    }

    // Select All: a, without showing the current row.
    function clickAll() {
        anchor = -1;
        pickAll();
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

    // ---- The cursor ----

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
            row = Math.max(first, Math.min(first + shownItems[inside].length - 1, row + step));
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
            row = last ? Math.max(0, rows.length - 1) : 0;
        } else if (inside >= 0) {
            const first = headingRow(inside) + 1;
            row = last ? first + shownItems[inside].length - 1 : first;
        } else {
            // The last heading: a group the search leaves nothing of has
            // none.
            let to = last ? rows.length - 1 : 0;
            while (to > 0 && rows[to].group === undefined)
                to -= 1;
            row = Math.max(0, to);
        }
        rowShown = true;
    }
}
