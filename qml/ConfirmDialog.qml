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
// and k (or Up and Down) scroll it, g and G go to its top and bottom, and
// Ctrl-D and Ctrl-U scroll half a page, Ctrl-F and Ctrl-B (or PageDown
// and PageUp) a page, as in the help.
// The list can be one to pick from (what to apply, or to undo), each row
// with a box before it, checked if it's picked, all picked at first unless
// a line says otherwise. That list is a PickList (`picks`), which has its
// lines, picks, cursor, selection, groups and search, and the keys for
// them (j, k, g, G, Space, x, a, v, /, and with groups l, h and Tab: see
// PickList), as every list to pick from has; this draws it, and has the
// keys that answer. A
// question can also have u, which answers it with its own action (see
// ask's `undo`). Y, and Shift and the key of the button apart (D), do what
// y and the button do, but with the current row, or the rows v selected,
// whether they're picked or not (and only show the current row, if it
// isn't yet, as the first j does). A row can be one Yes can't do (an apply
// that can't be undone), with a crossed out box, dimmed, which can't be
// picked, unless the question has a button for the picked lines (see
// below): then Yes is off while one is picked (and a leaves them out). Yes
// is off while none are picked, as that button is, unless the question
// has Yes take the current row then (see ask's `current`: the registers,
// where Enter pastes the one the cursor is on). A line to pick can take
// several lines of text, all after its box, and then the rows are a little
// apart, so they're told apart, or the question has each on one line, cut
// off (ask's `cut`). By a list to pick
// from's buttons are how many are picked, and a ? button, which, as `?`,
// asks for the help on the keys that aren't a button's (helpRequested),
// shown in a window of its own, so this box stays. The word that starts a line of the list can be colored by what
// it stands for, like CREATE in green, and a question can have one more
// button, on the left, apart from the choices, which does something with
// the picked lines, and is off while none are (see ask). Copy copies the
// list: the rows v selected, or all of it. The lines to pick from can be in
// groups (the undo history's applies), each a heading over its lines, with
// a box that picks them all. A group with many lines shows only some
// while the cursor isn't in it (those picked first), then a row that says
// how many more it has, and after its heading how many of its lines are of
// each kind; going into it shows them all (see ask's `groups`). / searches
// a list to pick from: only the lines with what's typed show, with what
// matched underlined, in a color of its own (`markColor`), and the
// search's line (a ListSearch) says how many picked lines aren't shown.
ModalBox {
    id: dialog

    // The clipboard, for Copy (main.qml's System); none in the tests.
    property var system: null
    // macOS's keys (see main.qml's isMac).
    property bool isMac: Qt.platform.os === "osx"

    // The question, or a function of how many lines are picked (and which)
    // that gives it (see ask).
    property var question: ""
    readonly property string text: typeof question === "function" ? question(picks.pickedCount, picks.picked) : question
    // The list as text, a row a line, if it's not one to pick from.
    property string details
    readonly property var lines: details === "" ? [] : details.split("\n")
    // The kind of change (see theme.changeColor) each word that can
    // start a line of the list stands for, like `{ MOVE: "rename" }` (see
    // ask).
    property var keywords: ({})
    // The list to pick from, if the question has one (see ask): its lines
    // (`items`), which are picked, the rows as shown, the cursor, the
    // search, and its keys. A line Yes can't do can be picked only for the
    // button apart. Its rows made again, the list is scrolled back as far
    // as it was, or to its top, then to the cursor's rows, once it's laid
    // out. A page is the rows the list has room for, if they take a line
    // each.
    readonly property PickList picks: PickList {
        isMac: dialog.isMac
        property real keptY: 0

        pickBlocked: dialog.extra !== null
        pageRows: Math.max(1, Math.floor(list.height / dialog.rowStep))
        onScroll: rows => list.scrollBy(rows * dialog.rowStep)
        onReplacing: keptY = list.contentY - list.originY
        onReplaced: top => {
            const y = top ? 0 : keptY;
            Qt.callLater(() => {
                list.scrollTo(y);
                dialog.showRow();
            });
        }
        onRowChanged: Qt.callLater(dialog.showRow)
        onRowShownChanged: Qt.callLater(dialog.showRow)
        // As tall as the rows' room was before the search started, until
        // all the lines show again.
        onFilteringChanged: {
            if (filtering)
                dialog.heldHeight = Math.max(dialog.heldHeight, dialog.restHeight);
            else if (filter === "")
                dialog.heldHeight = 0;
        }
        onFilterChanged: {
            if (filter === "" && !filtering)
                dialog.heldHeight = 0;
        }
    }
    // What the search matched is in the search highlights' color on a dark
    // theme (the accent's is too dark there, on the current row's most of
    // all), and the accent's on a light one, where that one is too pale.
    readonly property color markColor: theme.dark ? theme.searchMatch : theme.accent
    // How tall the list was as the search started, which it stays at
    // least, so the box doesn't change its size at every key; and how tall
    // it is while no search is typed (`filtering` shows the search's line
    // before anything hears of it, which takes its room from the list).
    property real heldHeight: 0
    property real restHeight: 0
    // For each group, the keywords its lines (that show) start with and
    // how many do, most first (`{ word, count }`), or none if a line
    // starts with none, which a closed one's heading shows (see
    // groupNote).
    readonly property var groupKinds: picks.shownItems.map(kindsOf)
    // The list's text, measured as it's asked (see ask): how many
    // characters its longest line has, how many lines each line to pick
    // from takes, or the list as text (an empty one counts half, as it's
    // drawn), so how many the rows shown have, and whether a line to pick
    // takes several.
    property int longest: 0
    property var itemLines: []
    property real detailLines: 0
    readonly property real textLines: !picks.items.length ? detailLines
        : picks.rows.reduce((count, row) => count + (row.item === undefined ? 1 : itemLines[row.item] ?? 1), 0)
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
    readonly property real rowPad: (picks.items.length ? 3 : 1) * zoom
    readonly property real rowMargin: 6 * zoom
    readonly property real textGap: 8 * zoom
    // With groups, the room before a heading's box for its arrow, and how
    // much further in a line's box is: under its heading's text.
    readonly property real groupIndent: picks.groups.length ? 14 * zoom : 0
    readonly property real itemIndent: picks.groups.length ? boxSize + textGap : 0
    readonly property real textX: rowMargin + (picks.items.length ? groupIndent + itemIndent + boxSize + textGap : 0)
    readonly property real rowGap: spaced ? 4 * zoom : 0
    // From a row of one line to the next.
    readonly property real rowStep: lineHeight + 2 * rowPad + rowGap
    readonly property int rowCount: picks.items.length ? picks.rows.length : lines.length
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
    // With none picked, Yes takes the current row, or the rows v selected,
    // as Y does, so it isn't off then; and a line too long for the box is
    // cut off, not wrapped (see ask's `current` and `cut`).
    property bool takesCurrent: false
    property bool cutLines: false
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
    // The help's topic on the keys of what's listed ("" for none: a list
    // to pick from has more keys than its buttons show), which its ?
    // button and `?` ask for (helpRequested). Whoever shows it mustn't
    // take this box's place (main.qml's HelpWindow, a window of its own).
    readonly property string helpTopic: picks.items.length ? "pick" : ""
    signal helpRequested(string topic)

    // Asks for the help: after `?`, once the key is up, or a moment later,
    // as a window opened while it's down gets its release (see main.qml's
    // openShortcuts).
    function askHelp(afterKey) {
        if (!helpTopic)
            return;
        if (afterKey) {
            helpAfterKey.restart();
        } else {
            helpAfterKey.stop();
            helpRequested(helpTopic);
        }
    }

    Timer {
        id: helpAfterKey

        interval: 300
        onTriggered: {
            if (dialog.opened)
                dialog.askHelp(false);
        }
    }

    // Asks `question`, with `details` (a list, maybe "") under it. `yes` is
    // what Yes does, and `no` what No does, if anything. `after` runs after
    // either, or if it's closed some other way (the next question, say).
    // `details` can also be lines to pick from, `{ text, needs }` (see
    // PickList.load), where
    // `needs` are the indexes of the lines it can't go without, and a line
    // can also have `picked: false` (left out at first) and `blocked` (Yes
    // can't do it, nor then a line that needs it; it can be picked only
    // for `extra`, see below, and starts left out; if it's why, as text, the
    // line of its text that ends with that is in the error's color), and
    // `lead`, `{ length, color }`: that many characters at its text's start
    // are in that color (when an apply was made, by how old it is), or a
    // list of those, each after the one before (a register's type, then
    // its name), and
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
    // is false only some of them (PickList's `preview`), with a row
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
    // as they were, with what was searched for, if a line still has it
    // (with `row`, the current line is the one at that index
    // instead); `again` can also be what `place` gave, to ask a question
    // as it was before another one; `undo`, what u does, as an
    // answer's action does, with the picked lines; `current`, to have Yes
    // (its button, y and Enter) take the current line, or the lines v
    // selected, while none is picked, as Y does, so Enter on a line does
    // it (pasting a register); and `cut`, to show each line to pick from
    // on one line, cut off where the box ends, not wrapped.
    function ask(question, details, yes, no, after, options) {
        options = options || {};
        // Before they're replaced.
        const was = options.again === true ? place() : options.again || null;
        dialog.keywords = options.keywords || {};
        extra = options.extra || null;
        undoAction = options.undo || null;
        cancelOnly = !!options.cancel;
        takesCurrent = !!options.current;
        cutLines = !!options.cut;
        yesLabel = options.yes || "";
        noLabel = options.no || "";
        const pick = Array.isArray(details);
        // The keys are the question's, not a search's that was typed.
        content.focus = true;
        heldHeight = 0;
        picks.load(pick ? details : [], { groups: options.groups, was: was, row: options.row, showRow: options.showRow });
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
        // As wide as with every line shown, whatever is searched for.
        const allKinds = picks.groupItems.map(kindsOf);
        picks.groups.forEach((group, g) => {
            const kinds = allKinds[g].reduce((length, kind) => length + String(kind.count).length + kind.word.length + 4, 0);
            most = Math.max(most, group.text.length + Math.max(group.note ? group.note.length : 0, kinds) + 2
                - itemIndent / charWidth);
        });
        longest = Math.ceil(most);
        itemLines = pick ? counts : [];
        detailLines = pick ? 0 : count;
        // A group's lines are told apart from the next one's by its heading.
        spaced = pick && !picks.groups.length && details.some(item => item.text.includes("\n"));
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

    // The keywords the lines `lines` start with and how many do, most
    // first (see groupKinds), or none if one of them starts with none.
    function kindsOf(lines) {
        const counts = [], at = Object.create(null);
        for (const i of lines) {
            // No line, while the lines are replaced.
            const word = /^\S*/.exec(picks.items[i]?.text ?? "")[0];
            if (typeof keywords[word] !== "string")
                return [];
            if (at[word] === undefined) {
                at[word] = counts.length;
                counts.push({ word: word, count: 0 });
            }
            counts[at[word]].count += 1;
        }
        // Most first; a sort keeps the order of those with as many.
        return counts.sort((a, b) => b.count - a.count);
    }

    // `text` as styled text with what the search matched in it underlined,
    // in `markColor`, or "" if nothing did.
    function withMarks(text) {
        return picks.withMarks(text, markColor);
    }

    // What the row for a closed group's other lines says.
    function moreText(g) {
        return qsTr("… %1 more").arg((picks.shownItems[g] || []).length - picks.preview);
    }

    // What goes after group `g`'s heading, as styled text: its `note`, or
    // while it's closed, how many of its lines start with each keyword,
    // the keywords in their colors (`18 MOVE · 4 TRASH`), as most of them
    // don't show then; and whether it's that.
    function groupNote(g) {
        const escaped = text => text.replace(/&/g, "&amp;").replace(/</g, "&lt;");
        if (!showsKinds(g))
            return escaped(picks.groups[g]?.note ?? "");
        return groupKinds[g].map(kind => kind.count + " <font color=\"" + theme.changeColor(keywords[kind.word]) + "\">"
            + escaped(kind.word) + "</font>").join(" · ");
    }

    function showsKinds(g) {
        return g < picks.groups.length && !picks.isOpen(g) && (groupKinds[g] || []).length > 0;
    }

    // The lines of text of a row of the list (a line to pick from, a
    // group's heading, or a line of `details`), each as `{ word, rest, color, error }`: the
    // keyword it starts with, with the spaces after it, and its color (or
    // none of both), what's after it, and whether it says why the line
    // can't be done (see ask's `blocked`). A line to pick from with a
    // `lead` starts with that, as its first line's word, in its color;
    // with a lead of several, in the last one's, and `leads` has each
    // part's `{ text, color }` (see leadText).
    function rowParts(row) {
        const pick = typeof row !== "string";
        const why = pick && typeof row.blocked === "string" ? row.blocked : "";
        const lead = pick && row.lead ? row.lead : null;
        return (pick ? row.text : row).split("\n").map((line, i) => {
            if (lead && i === 0) {
                const several = Array.isArray(lead), parts = several ? lead : [lead];
                const length = parts.reduce((sum, part) => sum + part.length, 0);
                // With the spaces after it, as a keyword.
                const end = length + /^\s*/.exec(line.slice(length))[0].length;
                const first = { word: line.slice(0, end), rest: line.slice(end),
                    color: parts[parts.length - 1].color, error: false };
                if (several) {
                    let at = 0;
                    first.leads = parts.map((part, n) => {
                        const from = at;
                        at = n === parts.length - 1 ? end : at + part.length;
                        return { text: line.slice(from, at), color: String(part.color) };
                    });
                }
                return first;
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

    // The word of a line of a row (see rowParts) as styled text, if its
    // parts are in colors of their own (`leads`), each with what the search
    // matched in it underlined; else "". Styled text runs spaces together,
    // so one before another is a no-break one.
    function leadText(part) {
        if (!part.leads)
            return "";
        const escaped = text => text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
            .replace(/ (?= )/g, "&nbsp;");
        return part.leads.map(lead => "<font color=\"" + lead.color + "\">"
            + (withMarks(lead.text) || escaped(lead.text)) + "</font>").join("");
    }

    // What Copy copies: the rows v selected, or all of the list (of what
    // the search leaves of it), as text, with groups each one's heading
    // and its lines after it, further in (also those of a closed one, when
    // it's all of the list).
    function copyText() {
        const items = picks.items, groups = picks.groups, rows = picks.rows, anchor = picks.anchor, row = picks.row;
        if (!items.length)
            return details;
        const inner = i => groups.length ? "  " + items[i].text.replace(/\n/g, "\n  ") : items[i].text;
        if (anchor < 0 && groups.length)
            return groups.map((group, g) => picks.shownItems[g].length
                ? [group.text].concat(picks.shownItems[g].map(inner)).join("\n") : null)
                .filter(text => text !== null).join("\n");
        const first = anchor < 0 ? 0 : Math.min(anchor, row), last = anchor < 0 ? rows.length - 1 : Math.max(anchor, row);
        return rows.slice(first, last + 1).map(at => at.group !== undefined ? groups[at.group].text
            : at.more !== undefined ? "  " + moreText(at.more) : inner(at.item))
            .join(spaced ? "\n\n" : "\n");
    }

    // Where the question's lines are (see PickList.place), and how far
    // the list is scrolled, for ask's `again` to ask it again so after
    // another question.
    function place() {
        return Object.assign(picks.place(), { y: list.contentY - list.originY });
    }

    // Whether `choice` ("yes", "no", "cancel", "extra", "undo", or "all",
    // Select All) can be answered now: with lines to pick from, Yes and
    // the button apart only once one is picked, and Select All if Yes can
    // do any of those that show.
    function canAnswer(choice) {
        const none = picks.items.length > 0 && picks.pickedCount === 0;
        return choice === "all" ? picks.items.some((item, i) => !item.blocked && picks.isShown(i))
            : choice === "yes" ? !picks.blockedPicked && (!none || takesCurrent)
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
                picks.clickAll();
            return;
        }
        // Yes with none picked, where it takes the cursor's lines.
        if (choice === "yes" && !lines && takesCurrent && picks.items.length && !picks.pickedCount) {
            answerHighlighted(choice);
            return;
        }
        const can = !lines ? canAnswer(choice) : choice === "extra" ? extra !== null
            : choice === "yes" && !lines.some(i => picks.items[i].blocked);
        if (!can)
            return;
        const action = choice === "yes" ? yesAction : choice === "no" ? noAction
            : choice === "extra" ? extra?.action : choice === "undo" ? undoAction : null;
        const chosen = lines || [];
        if (!lines) {
            picks.picked.forEach((p, i) => {
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

    // Y and D: answers `choice` with the current line, or the lines
    // v selected, but only shows the current line if it isn't yet, as the
    // first j does (see PickList.cursorLines).
    function answerHighlighted(choice) {
        const lines = picks.cursorLines();
        if (lines.length)
            answer(choice, lines);
    }

    // Scrolls to the rows the cursor is on, if it's shown: to their last,
    // then their first, which shows if they don't all fit. Twice, as a
    // row made as the list jumps to it is placed by a guess of its
    // height: the last line of a row of two was cut off after G.
    function showRow() {
        if (!picks.items.length || !picks.rowShown || !picks.rows.length)
            return;
        const last = Math.min(picks.cursorRows[1], picks.rows.length - 1), first = Math.min(picks.cursorRows[0], last);
        for (let pass = 0; pass < 2; pass++) {
            if (last === picks.rows.length - 1)
                list.positionViewAtEnd();
            else
                list.positionViewAtIndex(last, ListView.Contain);
            list.positionViewAtIndex(first, ListView.Contain);
            list.forceLayout();
        }
    }

    // As wide as the question (up to a width it wraps past), the list and
    // the buttons take, but no wider than the window has room for.
    width: Math.min(parent ? parent.width - 48 * zoom : 500, Math.max(Math.min(questionText.implicitWidth, 560 * zoom),
        listWidth, buttons.sideBySide, (picks.items.length ? 480 : 280) * zoom) + 2 * padding)
    closePolicy: Popup.CloseOnPressOutside
    onClosed: {
        // Not typing a search any more, so the next question has the keys.
        picks.filtering = false;
        content.focus = true;
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
        readonly property var item: pickable && !isGroup && !isMore ? dialog.picks.items[modelData.item] ?? null : null
        readonly property var group: isGroup ? dialog.picks.groups[modelData.group] ?? null : null
        readonly property bool blocked: isGroup ? dialog.picks.groupBlocked(modelData.group) : !!item?.blocked
        // Whether it's picked: 2, or for a heading, 1 if only some of its
        // lines are.
        readonly property int picks: isGroup ? dialog.picks.groupPicks(modelData.group)
            : item && dialog.picks.picked[modelData.item] === true ? 2 : 0
        // One of the rows the cursor is on, or of those v selected, and
        // those rows' first and last, whose corners are round.
        readonly property bool isCurrent: pickable && dialog.picks.rowShown && index >= dialog.picks.cursorRows[0]
            && index <= dialog.picks.cursorRows[1]
        readonly property bool selected: pickable && dialog.picks.anchor >= 0 && index >= dialog.picks.selectedRows[0]
            && index <= dialog.picks.selectedRows[1]
        readonly property var span: selected ? dialog.picks.selectedRows : isCurrent ? dialog.picks.cursorRows : [index, index]
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
                if (listRow.isGroup && point.position.x < listRow.boxX && dialog.picks.canClose(listRow.modelData.group))
                    dialog.picks.putIn(dialog.picks.inside === listRow.modelData.group ? -1 : listRow.modelData.group);
                else
                    dialog.picks.clickRow(listRow.index);
            }
        }

        // A heading's arrow, if its group can be closed: down while all its
        // lines show.
        Icon {
            x: dialog.rowMargin - 3 * dialog.zoom
            y: dialog.rowPad + Math.round((dialog.lineHeight - height) / 2)
            visible: listRow.isGroup && dialog.picks.canClose(listRow.modelData.group)
            theme: dialog.theme
            path: "M6 4.5 L9.5 8 L6 11.5"
            rotation: listRow.isGroup && dialog.picks.isOpen(listRow.modelData.group) ? 90 : 0
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
                    // Styled only where the search matched in it (see
                    // withMarks), or with parts in colors of their own
                    // (see leadText).
                    Text {
                        id: word

                        readonly property string marks: listRow.isMore ? "" : dialog.leadText(line.modelData)
                            || dialog.withMarks(line.modelData.word)

                        width: line.modelData.word.length * dialog.charWidth
                        text: marks || line.modelData.word
                        font: dialog.theme.font
                        color: line.modelData.color || dialog.theme.text
                        textFormat: marks ? Text.StyledText : Text.PlainText
                    }
                    Text {
                        id: rest

                        readonly property string marks: listRow.isMore ? "" : dialog.withMarks(line.modelData.rest)

                        x: word.width
                        width: line.width - x
                        text: marks || line.modelData.rest
                        font: dialog.theme.font
                        color: line.modelData.error ? dialog.theme.error : dialog.theme.text
                        textFormat: marks ? Text.StyledText : Text.PlainText
                        wrapMode: dialog.cutLines ? Text.NoWrap : Text.Wrap
                        elide: dialog.cutLines ? Text.ElideRight : Text.ElideNone
                    }
                }
            }
        }
    }

    contentItem: ColumnLayout {
        id: content

        spacing: 12 * dialog.zoom
        focus: true

        Keys.onPressed: event => {
            // The search's, which it left.
            if (dialog.picks.filtering)
                return;
            const pick = dialog.picks.items.length > 0, shift = event.modifiers & Qt.ShiftModifier;
            // A list of text scrolls with Ctrl's keys as the help does
            // (a list to pick from has its own).
            const ctrl = !pick && (event.modifiers & ~Qt.KeypadModifier) === dialog.picks.ctrlKey;
            if (event.matches(StandardKey.Copy))
                dialog.system?.setClipboardText(dialog.copyText(), "");
            else if (dialog.helpTopic && (event.text === "?" || event.key === Qt.Key_Question))
                dialog.askHelp(true);
            else if (dialog.picks.key(event)) {
                // The list's (see PickList.key).
            } else if (ctrl && event.key === Qt.Key_D)
                list.scrollBy(list.height / 2);
            else if (ctrl && event.key === Qt.Key_U)
                list.scrollBy(-list.height / 2);
            else if (ctrl && event.key === Qt.Key_F)
                list.scrollBy(list.height);
            else if (ctrl && event.key === Qt.Key_B)
                list.scrollBy(-list.height);
            else if (ctrl && event.key === Qt.Key_E)
                list.scrollBy(dialog.lineHeight);
            else if (ctrl && event.key === Qt.Key_Y)
                list.scrollBy(-dialog.lineHeight);
            else if (event.modifiers & ~(Qt.ShiftModifier | Qt.KeypadModifier))
                return;
            else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                // Nothing here to go to.
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J)
                list.scrollBy(dialog.lineHeight);
            else if (event.key === Qt.Key_Up || event.key === Qt.Key_K)
                list.scrollBy(-dialog.lineHeight);
            else if (event.key === Qt.Key_PageDown)
                list.scrollBy(list.height);
            else if (event.key === Qt.Key_PageUp)
                list.scrollBy(-list.height);
            else if (event.key === Qt.Key_G || event.key === Qt.Key_Home || event.key === Qt.Key_End)
                list.scrollTo(shift && event.key === Qt.Key_G || event.key === Qt.Key_End ? list.maxY : 0);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                dialog.answer("yes");
            else if (dialog.extra && event.key === dialog.extra.key && pick && shift)
                dialog.answerHighlighted("extra");
            else if (event.key === Qt.Key_Y && pick && shift)
                dialog.answerHighlighted("yes");
            else if (dialog.extra && event.key === dialog.extra.key)
                dialog.answer("extra");
            else if (dialog.undoAction && event.key === Qt.Key_U)
                dialog.answer("undo");
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
        // `?` let go (not the Shift it's typed with, which can go first).
        Keys.onReleased: event => {
            const modifier = [Qt.Key_Shift, Qt.Key_Control, Qt.Key_Meta, Qt.Key_Alt].includes(event.key);
            if (helpAfterKey.running && !modifier && !event.isAutoRepeat)
                Qt.callLater(dialog.askHelp, false);
        }

        // Over the list, so it stays in view as the list scrolls.
        CodeLabel {
            id: questionText

            Layout.fillWidth: true
            theme: dialog.theme
            markup: dialog.text
            // A `:h topic` in a question is a link to it, in the help's
            // window, as the ? button's.
            links: true
            font.pixelSize: Math.round(14 * dialog.zoom)
            color: dialog.theme.text
            onHelpRequested: topic => dialog.helpRequested(topic)
        }

        // The list, on the editor's background, as its text is in the
        // editor's font: as tall as its rows, but no taller than the
        // window has room for.
        Rectangle {
            id: listFrame

            readonly property real margin: 4 * dialog.zoom
            // What else the box has, with the room around it.
            readonly property real others: 48 * dialog.zoom + 2 * dialog.padding + questionText.height + buttons.implicitHeight
                + 2 * content.spacing

            Layout.fillWidth: true
            // Until the rows are laid out, as tall as their lines
            // unwrapped take, which has the ListView make them; and
            // searching, as tall as it was, with the search's line.
            Layout.preferredHeight: Math.min(Math.max(list.contentHeight > 0 ? list.contentHeight : dialog.listHeight,
                    dialog.heldHeight) + 2 * margin + searchLine.height,
                Math.max(dialog.lineHeight + 2 * dialog.rowPad + 2 * margin + searchLine.height,
                    (dialog.parent ? dialog.parent.height : 500) - others))
            visible: dialog.rowCount > 0 || dialog.picks.items.length > 0
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
                anchors.bottomMargin: listFrame.margin + searchLine.height
                clip: true
                interactive: false
                keyNavigationEnabled: false
                model: dialog.picks.items.length ? dialog.picks.rows : dialog.lines
                spacing: dialog.rowGap
                onHeightChanged: {
                    if (!dialog.picks.filtering)
                        dialog.restHeight = height;
                }
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

            // In place of the rows, if no line has what's searched for.
            Text {
                x: listFrame.margin + dialog.rowMargin
                y: listFrame.margin + dialog.rowPad
                visible: dialog.picks.items.length > 0 && !dialog.picks.rows.length
                text: qsTr("No line has that")
                font: dialog.theme.font
                color: dialog.theme.dim
                textFormat: Text.PlainText
            }

            // The search's line.
            ListSearch {
                id: searchLine

                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                theme: dialog.theme
                picks: dialog.picks
                owner: content
                inset: listFrame.margin + dialog.rowMargin
            }
        }

        // The buttons: the list's on the left, and the choices on the
        // right, or under them where the box is too narrow for both.
        GridLayout {
            id: buttons

            // How wide they are side by side.
            readonly property real sideBySide: tools.implicitWidth + columnSpacing + answers.implicitWidth

            Layout.fillWidth: true
            columns: dialog.picks.items.length && sideBySide > dialog.availableWidth ? 1 : 2
            columnSpacing: 8 * dialog.zoom
            rowSpacing: 8 * dialog.zoom

            RowLayout {
                id: tools

                Layout.fillWidth: true
                spacing: 8 * dialog.zoom

                // The list's keys, in the help (`?` too).
                TextButton {
                    id: helpButton

                    objectName: "helpButton"
                    visible: dialog.helpTopic !== ""
                    theme: dialog.theme
                    focusPolicy: Qt.NoFocus
                    implicitWidth: implicitHeight
                    text: "?"
                    Accessible.name: qsTr("Help")
                    onClicked: dialog.askHelp(false)

                    Tip {
                        theme: dialog.theme
                        visible: helpButton.hovered
                        text: qsTr("Help")
                        shortcuts: ["?"]
                        x: Math.round((helpButton.width - width) / 2)
                        y: helpButton.height + 6 * dialog.zoom
                    }
                }
                Choice {
                    visible: dialog.picks.items.length > 0
                    modelData: ({ label: dialog.picks.allPicked ? qsTr("Select None") : qsTr("Select All"), keys: "a", answer: "all" })
                }
                Choice {
                    visible: dialog.extra !== null
                    modelData: ({ label: dialog.extra?.label ?? "", keys: dialog.extraKeys, answer: "extra" })
                }

                // How many are picked.
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4 * dialog.zoom
                    visible: dialog.picks.items.length > 0
                    text: qsTr("%1 of %2").arg(dialog.picks.pickedCount).arg(dialog.picks.items.length)
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
