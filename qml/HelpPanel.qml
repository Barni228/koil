pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

import "help.js" as Help
import "text.js" as Txt

// :help, a box over the editor with what isn't obvious: Koil's listing,
// :set and its forms, the commands, shell commands, search, registers and
// macros, visual block and multiple cursors, marked lines, hidden text, the
// keys starting with g, z and Space, Ctrl keys and other keys.
// Its sections are folded, each to its title (see Folds): :help topic
// opens only the topic's section, at a key's row if it's one (see show).
// It can show a list of rows too (showList), and :! what a command wrote
// (showText), also while it runs (see Output), neither with folds.
// Keys scroll it as in a vim help buffer, / and ? search it (see Search);
// Esc or q closes it, and so does Enter (as after vim's :!) where there
// are no folds. Its text can be selected with the mouse and copied.
ModalBox {
    id: help

    // The font Koil ships, for :set guifont.
    property string defaultFontFamily

    readonly property bool isMac: Qt.platform.os === "osx"
    readonly property bool isWindows: Qt.platform.os === "windows"
    readonly property string monoFamily: theme.font.family
    // Modifier keys as the OS writes them.
    readonly property string cmdKey: isMac ? "⌘" : "Ctrl+"
    readonly property string altKey: isMac ? "⌥" : "Alt+"
    // Where Space r shows an entry (and Space o opens it as from there).
    readonly property string fileManager: isMac ? "Finder" : isWindows ? "Explorer" : "the file manager"
    // The shell :! runs commands in, unless Settings says otherwise.
    readonly property string systemShell: isWindows ? "cmd.exe" : "$SHELL"
    readonly property real lineStep: Math.round(20 * zoom)
    // What it shows: the help, or a list (see showList).
    property string heading: "Koil Help"
    // The heading as the title shows it, and its rows: one too long for
    // `headingRows` (a shell command on many paths) loses its middle, as
    // the status line's message does, or it took all of the box, and the
    // text under it couldn't be scrolled to.
    readonly property string shownHeading: headingMetrics.elidedText
    readonly property int shownHeadingRows: title.lineCount
    readonly property int headingRows: 3
    property var shownSections: sections

    // What it says, section by section (see help.js).
    readonly property var sections: Help.sections(help)

    // Opens the help with only the section for `topic` unfolded (none if
    // ""), at its row of that key if it has one (`:h gs`), or else at the
    // first row of that key (`:h zs`). Tags and keys match as typed first,
    // so `gI` isn't `gi`, then in any case. `<C-a>`, `^A` and `CTRL-A` are
    // `Ctrl-A`. False if there's no help for it.
    function show(topic) {
        const t = topic.trim().replace(/^:/, "").replace(/^'(.*)'$/, "$1")
            .replace(/^(?:<c-(.)>|\^(.)|ctrl[-+](.))$/i, (m, a, b, c) => "Ctrl-" + (a || b || c).toUpperCase());
        const lower = t.toLowerCase();
        let i = t === "" ? 0 : sections.findIndex(s => s.tags.includes(t));
        if (i < 0)
            i = sections.findIndex(s => s.tags.some(tag => tag.toLowerCase() === lower));
        // The key's row in that section, else in the first that has it.
        let row = -1;
        const looked = i >= 0 ? [i] : sections.map((s, k) => k);
        for (const exact of t === "" ? [] : [true, false]) {
            const s = looked.find(s => keyRow(sections[s], t, exact) >= 0);
            if (s !== undefined) {
                i = s;
                row = keyRow(sections[s], t, exact);
                break;
            }
        }
        if (i < 0)
            return false;
        output = false;
        running = false;
        live = false;
        let fold = i;
        while (fold > 0 && sections[fold].part)
            fold--;
        showBox("Koil Help", sections, i, row, sections.map((s, k) => t !== "" && k === fold));
        current = fold;
        return true;
    }

    // The row of `section` with `key` in its keys (as written, or unless
    // `exact`, in any case), or -1.
    function keyRow(section, key, exact) {
        const same = code => exact ? code === key : code.toLowerCase() === key.toLowerCase();
        return section.rows.findIndex(row => Txt.parseCode(row[0], false).codes.some(c => same(c.text)));
    }

    // Opens the box with `title` over `rows` of [keys, text], both shown
    // as they are in the editor's font, the keys taking `keyColumns`
    // characters.
    function showList(title, rows, keyColumns) {
        showPlain(title, { title: "", rows: rows, plain: true, keyColumns: keyColumns });
    }

    function showPlain(title, section) {
        showSections(title, [section], 0, -1);
    }

    // Opens the box with `title` over `list`, at the section `section` and
    // its row `row` (-1 for its top).
    function showSections(title, list, section, row) {
        output = false;
        running = false;
        live = false;
        showBox(title, list, section, row);
    }

    // `unfold`, if given, is which of `list` are unfolded (see Folds);
    // without it there are no folds. A folded section has no rows, so the
    // list is given while they're all folded: unfolded, each would make
    // all its rows first.
    function showBox(title, list, section, row, unfold) {
        heading = title;
        if (unfold) {
            folds = true;
            unfolded = [];
            shownSections = list;
            unfolded = unfold;
        } else {
            shownSections = list;
            folds = false;
            unfolded = [];
        }
        current = 0;
        zPending = false;
        clearSearch();
        open();
        unsettle();
        shownSection = section;
        shownRow = row;
        settle();
    }

    // The section :help went to, and its row (-1 for its top). Its text is
    // laid out over the first frames, so it's scrolled to again as the
    // layout changes (settle), until the user scrolls (unsettle). So are
    // the match a search went to in a section it unfolded (shownMatch),
    // and the section a key or a click folded or unfolded (keptSection),
    // whose rows are made and laid out only then.
    property int shownSection: -1
    property int shownRow: -1
    property var shownMatch: null
    property int keptSection: -1

    function settle() {
        if (shownSection >= 0) {
            const item = sectionRepeater.itemAt(shownSection);
            if (!item)
                return;
            const row = shownRow >= 0 ? textItems.get(shownSection + "/" + shownRow + "k") : null;
            scroller.contentY = Math.min(row ? row.mapToItem(body, 0, 0).y : item.y, scroller.maxY);
        } else if (shownMatch) {
            showMatch(shownMatch);
        } else if (keptSection >= 0) {
            // As much of it as fits, from its title.
            const s = span(keptSection);
            if (s)
                scroller.scrollTo(Math.min(s.top, Math.max(scroller.contentY, s.bottom - scroller.height)));
        } else if (folds && scroller.contentY > scroller.maxY) {
            scroller.contentY = scroller.maxY;
        }
    }

    function unsettle() {
        shownSection = -1;
        shownMatch = null;
        keptSection = -1;
    }

    function scrollBy(dy) {
        unsettle();
        scroller.scrollBy(dy);
        scrolled();
    }

    // ---- Folds -------------------------------------------------------------
    // The help's sections are folded, each to its title, which says what
    // there is help for; one unfolded shows its text under it. A section
    // that's a `part` of the one before (how to set an option, after the
    // options) has no fold of its own: it shows while that one is
    // unfolded. One section is the cursor's (`current`, its title
    // highlighted): j and k move it, going through the text of an unfolded
    // one first (by scrolling, as there's no cursor in the text), as vim's
    // do over folds; Enter, Space, Tab or za folds or unfolds it, as a
    // click on its title does, l or zo unfolds it, h or zc folds it, and
    // zR and zM do them all (Space pages down only where there are no
    // folds). A search unfolds the section of the match it goes to,
    // as vim's does. Scrolled out of view any other way, the cursor's is
    // the first section in view.

    // Whether the sections shown fold (the help's, not a list's), which
    // are unfolded (by index; a part's doesn't count), and the cursor's.
    property bool folds: true
    property var unfolded: []
    property int current: 0
    // Whether z was typed, and the next key is its fold command.
    property bool zPending: false

    // The section whose fold section i is in: itself, or the one it's a
    // part of.
    function foldOf(i) {
        while (i > 0 && shownSections[i].part)
            i--;
        return i;
    }

    function isOpen(i) {
        return !folds || unfolded[foldOf(i)] === true;
    }

    // The fold after i (`step` 1) or before it (-1), or -1.
    function nextFold(i, step) {
        for (let k = i + step; k >= 0 && k < shownSections.length; k += step) {
            if (!shownSections[k].part)
                return k;
        }
        return -1;
    }

    // Where fold i is in the body: its title's top and height, and its
    // bottom, with its parts if it's unfolded. Null before it's laid out.
    function span(i) {
        const first = sectionRepeater.itemAt(i);
        if (!first)
            return null;
        let last = i;
        while (isOpen(i) && last + 1 < shownSections.length && shownSections[last + 1].part)
            last++;
        const end = sectionRepeater.itemAt(last) || first;
        return { top: first.y, head: first.headHeight, bottom: end.y + end.height };
    }

    // Folds or unfolds fold i, which the cursor goes to, and keeps it in
    // view.
    function setOpen(i, open) {
        if (!folds || i < 0)
            return;
        if (isOpen(i) !== open) {
            const next = shownSections.map((s, k) => unfolded[k] === true);
            next[i] = open;
            unfolded = next;
        }
        current = i;
        unsettle();
        keptSection = i;
        settle();
    }

    function toggle(i) {
        setOpen(i, !isOpen(i));
    }

    // zR and zM.
    function setAllOpen(open) {
        if (!folds)
            return;
        unfolded = shownSections.map(s => open && !s.part);
        unsettle();
        keptSection = current;
        settle();
    }

    // j (`down`) and k: through the cursor's section while it's unfolded
    // and goes on past the view's edge, then to the next one's title; up
    // into an unfolded one, to its end.
    function moveCursor(down) {
        const top = scroller.contentY, bottom = top + scroller.height;
        const s = span(current);
        const more = s !== null && isOpen(current)
            && (down ? s.bottom > bottom + 0.5 && top < scroller.maxY : s.top < top - 0.5 && top > 0);
        const to = more ? -1 : nextFold(current, down ? 1 : -1);
        if (to < 0) {
            scrollBy(down ? lineStep : -lineStep);
            return;
        }
        unsettle();
        current = to;
        const t = span(to);
        if (!t)
            return;
        if (!down && isOpen(to) && t.bottom - t.top > t.head) {
            if (t.bottom < top + 2 * lineStep)
                scroller.scrollTo(Math.max(t.top, t.bottom - 2 * lineStep));
        } else if (t.top < top) {
            scroller.scrollTo(t.top);
        } else if (t.top + t.head > bottom) {
            scroller.scrollTo(t.top + t.head - scroller.height);
        }
    }

    // After a scroll: the cursor's section is the first in view, if its
    // own isn't any more.
    function followView() {
        if (!folds)
            return;
        const top = scroller.contentY, bottom = top + scroller.height;
        const s = span(current);
        if (s && s.bottom > top && s.top < bottom)
            return;
        for (let i = nextFold(-1, 1); i >= 0; i = nextFold(i, 1)) {
            const t = span(i);
            if (t && (t.bottom > top + lineStep || nextFold(i, 1) < 0)) {
                current = i;
                return;
            }
        }
    }

    // ---- Output ------------------------------------------------------------
    // What a shell command wrote, as a terminal's: its command over it, in
    // the editor's font, with how it ended beside it (or that it runs
    // still, and for how long), its text on the editor's background, and
    // the keys under it. Shown once it's done (showText), or as it runs
    // (showRunning, then addOutput as more comes, and endOutput): the view
    // then stays at the end as more is written (`following`), until it's
    // scrolled off it.

    // Whether it shows a command's output, and whether that's running
    // still: Esc then stops it (stopRequested) rather than closing the box,
    // which nothing else closes.
    property bool output: false
    property bool running: false
    // Whether it was opened while the command ran: it then grows down from
    // where its top is at its tallest, so what's written stays where it is
    // as more comes.
    property bool live: false
    // How it ended: "done", "failed" (with outputLabel, like "Exit 2") or
    // "stopped".
    property string outputState: ""
    property string outputLabel: ""
    // When it started, how long it took (ms, -1 if that's not known), and
    // the time as the timer has it while it runs, which steps `pulse` too.
    property real outputStart: 0
    property real outputTook: -1
    property real outputNow: 0
    property bool pulse: false
    // How many of its first lines aren't shown (see shell::Ran::cut).
    property int outputCut: 0
    // The lines shown that ended, by their lengths, where they end in the
    // text (before the line being written), and that line.
    property var outputLengths: []
    property int outputEnd: 0
    property string outputLine: ""
    // Whether the view stays at the text's end as more is written: until
    // it's scrolled off the end, and again once it's scrolled back there
    // (see scrolled).
    property bool following: false

    readonly property string outputStatus: {
        const took = running ? outputNow - outputStart : outputTook;
        const what = running ? qsTr("Running") : outputState === "done" ? qsTr("Done")
            : outputState === "stopped" ? qsTr("Stopped") : outputLabel;
        return what + (took >= (running ? 1000 : 0) ? " · " + duration(took, running) : "");
    }
    readonly property color outputColor: running ? theme.accent
        : outputState === "done" ? theme.changeColor("create")
        : outputState === "stopped" ? theme.changeColor("rename") : theme.error

    // Esc or Ctrl-C while the command runs.
    signal stopRequested

    // `ms` as "0.4s", "12s" or "1m 5s" (in whole seconds, if `whole`).
    function duration(ms, whole) {
        const s = ms / 1000;
        if (s < 10 && !whole)
            return s.toFixed(1) + "s";
        if (s < 60)
            return Math.floor(s) + "s";
        return Math.floor(s / 60) + "m " + Math.floor(s % 60) + "s";
    }

    function openOutput(title, isLive) {
        output = true;
        running = isLive;
        live = isLive;
        following = isLive;
        outputState = "";
        outputLabel = "";
        outputTook = -1;
        outputCut = 0;
        outputLengths = [];
        outputEnd = 0;
        outputLine = "";
        outputText.clear();
        showBox(title, [], -1, -1);
        scroller.contentY = 0;
    }

    // Opens the box with `title` (the command) over `text`, what it wrote,
    // as it is in the editor's font, with its line breaks. `info`, if
    // given, says more: `failed`, how it failed (like "Exit 2"), `took`,
    // how long it ran (ms), and `cut`, how many lines before `text` aren't
    // shown.
    function showText(title, text, info) {
        openOutput(title, false);
        outputText.text = text;
        outputState = info?.failed ? "failed" : "done";
        outputLabel = info?.failed ?? "";
        outputTook = info?.took ?? -1;
        outputCut = info?.cut ?? 0;
    }

    // Opens the box with `title` (the command) for what it writes while it
    // runs, since `start` (a time, in ms).
    function showRunning(title, start) {
        openOutput(title, true);
        outputStart = start;
        outputNow = Date.now();
    }

    // What the command wrote since (a shell::Output): the first lines go,
    // those that ended since are put after the others, and the line being
    // written after them, in place of what it was. The view stays at the
    // end if it was there, else on the lines it shows.
    function addOutput(out) {
        if (!running)
            return;
        const t = outputText;
        if (out.reset || out.drop > 0 && out.drop >= outputLengths.length) {
            t.clear();
            outputLengths = [];
            outputEnd = 0;
            outputLine = "";
        } else if (out.drop > 0) {
            let n = 0;
            for (let i = 0; i < out.drop; i++)
                n += outputLengths[i] + 1;
            const gone = t.positionToRectangle(n).y - t.positionToRectangle(0).y;
            t.remove(0, n);
            outputLengths.splice(0, out.drop);
            outputEnd -= n;
            if (!following)
                scroller.scrollTo(scroller.contentY - gone);
        }
        if (out.lines.length || out.line !== outputLine) {
            let count = outputLengths.length, ended = "";
            for (const line of out.lines) {
                ended += (count++ ? "\n" : "") + line;
                outputLengths.push(line.length);
            }
            t.remove(outputEnd, t.length);
            t.insert(outputEnd, ended + (out.line === "" ? "" : (count ? "\n" : "") + out.line));
            outputEnd += ended.length;
            outputLine = out.line;
        }
        outputCut = out.cut;
        if (following)
            scroller.scrollTo(scroller.maxY);
    }

    // The command is done: how (see outputState), and `label` for one that
    // failed.
    function endOutput(state, label) {
        if (!running)
            return;
        running = false;
        outputState = state;
        outputLabel = label || "";
        outputTook = Date.now() - outputStart;
    }

    // What the output shows, for the tests.
    function outputShown() {
        return outputText.text;
    }

    // The view was scrolled (by a key, the wheel, the scroll bar or a
    // search): it follows what a running command writes only at the end.
    // Not by the view's place changing, which it also does as the box
    // grows.
    function scrolled() {
        following = live && scroller.contentY >= scroller.maxY - 1;
        followView();
    }

    // The text with a selection. Each text selects on its own, so selecting
    // in one clears the last one.
    property TextEdit selected: null

    function copySelection() {
        if (selected && selected.selectedText !== "")
            selected.copy();
    }

    // How far a code's shade reaches past its text, as in a Tip.
    readonly property real codePadding: 4 * zoom

    // ---- Search ------------------------------------------------------------
    // As vim's: / and ? type a search (on the search line, at the bottom),
    // highlighting its matches and going to the one Enter goes to as it's
    // typed; n and N go on. A search goes from the match it went to last,
    // if that's in view, else from the top of the view. Esc clears the
    // highlights, and then closes the help.

    // The search being typed ("/" or "?"), or "".
    property string searchKind: ""
    // The pattern whose matches are highlighted ("" for none), the last one
    // searched for (which n searches for again), and which way.
    property string searchPattern: ""
    property string lastPattern: ""
    property bool lastForward: true
    // The match a search went to (in matches), or -1.
    property int matchIndex: -1
    // What the search line says after a search went round the end, or
    // found nothing (searchFailed).
    property string searchMessage: ""
    property bool searchFailed: false
    // The patterns searched for (the newest last), which Up and Down go
    // through as a search is typed (from historyAt, the one shown).
    property var searchHistory: []
    property int historyAt: -1
    property string typedSearch: ""
    // The view, highlights and match before a search was typed, which
    // cancelling it goes back to, and the match it goes from (or null).
    property var searchStart: null
    // The CodeTexts by key, to find a match on the screen. A Map, as
    // keys come and go: qmlcachegen compiles ({}) to a QVariantMap, not a
    // JS object, and in Qt 6.10 taking a key after one was deleted
    // crashed (showing what :! wrote, on Windows).
    property var textItems: new Map()

    readonly property bool searchShown: searchPattern !== "" || searchMessage !== ""

    // Every text of shownSections, in order, as search sees them ({ key,
    // text }, where key is CodeText's), and each key's place in that order.
    readonly property var searchTexts: {
        const list = [], order = {};
        if (output)
            return { list: [{ key: "output", text: outputText.text }], order: { output: 0 } };
        shownSections.forEach((section, s) => {
            const add = (part, markup) => {
                if (!markup)
                    return;
                order[s + "/" + part] = list.length;
                list.push({ key: s + "/" + part, text: Txt.parseCode(markup, !!section.plain).text });
            };
            add("title", section.title);
            add("intro", section.intro);
            section.rows.forEach((row, r) => {
                add(r + "k", row[0]);
                add(r + "t", row[1]);
            });
            add("note", section.note);
        });
        return { list: list, order: order };
    }

    // Each match of searchPattern: { key, start, end }, in order. Empty
    // ones don't count.
    readonly property var matches: {
        if (searchPattern === "")
            return [];
        const re = Txt.searchRegExp(searchPattern), found = [];
        for (const t of searchTexts.list) {
            re.lastIndex = 0;
            let m;
            while ((m = re.exec(t.text)) !== null) {
                if (m[0] === "")
                    re.lastIndex++;
                else
                    found.push({ key: t.key, start: m.index, end: m.index + m[0].length });
            }
        }
        return found;
    }

    // Each text's matches, as CodeText.marks: "start,end,current;…" (a
    // string, so a text whose matches stay the same isn't laid out again).
    readonly property var matchMarks: {
        const marks = {};
        matches.forEach((m, i) => {
            const mark = m.start + "," + m.end + "," + (i === matchIndex ? 1 : 0);
            marks[m.key] = marks[m.key] ? marks[m.key] + ";" + mark : mark;
        });
        return marks;
    }

    // The text match m is in, or null if it isn't shown: its section is
    // folded.
    function matchItem(m) {
        const item = textItems.get(m.key);
        return item && item.visible ? item : null;
    }

    // Where match m's line is in the body (its section's title, if it's
    // folded).
    function matchY(m) {
        const item = matchItem(m);
        if (item)
            return item.mapToItem(body, 0, item.positionToRectangle(m.start).y).y;
        const section = folds ? sectionRepeater.itemAt(foldOf(parseInt(m.key))) : null;
        return section ? section.y : 0;
    }

    function inView(m) {
        if (!matchItem(m))
            return false;
        const y = matchY(m);
        return y >= scroller.contentY && y < scroller.contentY + scroller.height;
    }

    // Scrolls match i to the middle, if it's out of view, unfolding its
    // section first, which the cursor goes to.
    function reveal(i) {
        const m = matches[i];
        unsettle();
        if (folds) {
            const fold = foldOf(parseInt(m.key));
            if (matchItem(m))
                current = fold;
            else
                setOpen(fold, true);
            unsettle();
            shownMatch = m;
        }
        showMatch(m);
        scrolled();
    }

    function showMatch(m) {
        const item = matchItem(m);
        if (!item)
            return;
        const height = item.positionToRectangle(m.start).height;
        const y = matchY(m);
        if (y < scroller.contentY || y + height > scroller.contentY + scroller.height)
            scroller.contentY = Math.max(0, Math.min(scroller.maxY, y - (scroller.height - height) / 2));
    }

    // The view's top as a place a search goes from (see nextMatch): in the
    // first text shown that reaches past it, before the character there.
    // Told by the texts' order, not by where they are, which changes as a
    // search being typed unfolds sections. Null if no text is there.
    function viewTop() {
        const top = scroller.contentY;
        for (const t of searchTexts.list) {
            const item = textItems.get(t.key);
            if (!item || !item.visible)
                continue;
            const y = item.mapToItem(body, 0, 0).y;
            if (y + item.height > top)
                return { key: t.key, start: (y >= top ? 0 : item.positionAt(0, top - y)) - 0.5 };
        }
        return null;
    }

    // The match a search goes to, from `from` (a match, maybe of another
    // search), else from the top of the view, going round at the end:
    // { index, wrapped }, or null if there's none.
    function nextMatch(forward, from) {
        const order = searchTexts.order;
        const compare = m => from ? order[m.key] - order[from.key] || m.start - from.start
            : matchY(m) >= scroller.contentY ? 1 : -1;
        if (forward) {
            const i = matches.findIndex(m => compare(m) > 0);
            return i >= 0 ? { index: i, wrapped: false } : matches.length ? { index: 0, wrapped: true } : null;
        }
        for (let i = matches.length - 1; i >= 0; i--) {
            if (compare(matches[i]) < 0)
                return { index: i, wrapped: false };
        }
        return matches.length ? { index: matches.length - 1, wrapped: true } : null;
    }

    // Searches for lastPattern from `from` (see nextMatch).
    function goToMatch(forward, from) {
        searchPattern = lastPattern;
        const target = nextMatch(forward, from);
        matchIndex = target ? target.index : -1;
        searchFailed = !target;
        searchMessage = !target ? "E486: Pattern not found: " + lastPattern
            : !target.wrapped ? "" : forward ? "search hit BOTTOM, continuing at TOP"
            : "search hit TOP, continuing at BOTTOM";
        if (target)
            reveal(target.index);
    }

    // n and N (and Find Next and Previous, `forward` or not).
    function searchAgain(forward) {
        if (lastPattern === "") {
            searchFailed = true;
            searchMessage = "E35: No previous regular expression";
            return;
        }
        const from = matchIndex >= 0 && inView(matches[matchIndex]) ? matches[matchIndex] : viewTop();
        goToMatch(forward, from);
    }

    // / or ? (and Find). Find while a search is typed selects it.
    function startSearch(kind) {
        if (searchKind) {
            searchField.selectAll();
            return;
        }
        const from = matchIndex >= 0 && inView(matches[matchIndex]) ? matches[matchIndex] : viewTop();
        searchStart = { pattern: searchPattern, index: matchIndex, from: from, contentY: scroller.contentY,
            unfolded: unfolded, current: current };
        unsettle();
        searchMessage = "";
        historyAt = -1;
        searchField.text = "";
        searchKind = kind;
        searchField.forceActiveFocus();
    }

    // Shows the matches of the search being typed, and the one Enter would
    // go to (vim's 'incsearch').
    function previewSearch(pattern) {
        leaveSearch();
        searchPattern = pattern || searchStart.pattern;
        const target = pattern ? nextMatch(searchKind === "/", searchStart.from) : null;
        matchIndex = pattern ? (target ? target.index : -1) : searchStart.index;
        if (target)
            reveal(target.index);
    }

    // The view, the folds and the cursor's section as they were before the
    // search was typed.
    function leaveSearch() {
        unsettle();
        if (folds) {
            unfolded = searchStart.unfolded;
            current = searchStart.current;
        }
        scroller.contentY = searchStart.contentY;
        scrolled();
        if (folds)
            current = searchStart.current;
    }

    // Enter (`accept`), or Esc. An empty search searches for the last
    // pattern again.
    function finishSearch(accept) {
        const typed = searchField.text, forward = searchKind === "/";
        searchKind = "";
        scroller.forceActiveFocus();
        leaveSearch();
        searchPattern = searchStart.pattern;
        matchIndex = searchStart.index;
        if (!accept || !typed && !lastPattern)
            return;
        if (typed) {
            searchHistory = searchHistory.filter(p => p !== typed).concat([typed]).slice(-100);
            lastPattern = typed;
        }
        lastForward = forward;
        goToMatch(forward, searchStart.from);
    }

    // Up (`back`) and Down while a search is typed.
    function browseHistory(back) {
        if (historyAt < 0) {
            if (!back || searchHistory.length === 0)
                return;
            typedSearch = searchField.text;
            historyAt = searchHistory.length - 1;
        } else if (back) {
            historyAt = Math.max(0, historyAt - 1);
        } else if (++historyAt >= searchHistory.length) {
            historyAt = -1;
        }
        searchField.text = historyAt < 0 ? typedSearch : searchHistory[historyAt];
    }

    // Whether item is in the help (as the item with the keys, say).
    function holds(item) {
        for (let i = item; i; i = i.parent) {
            if (i === contentItem.parent)
                return true;
        }
        return false;
    }

    function clearSearch() {
        searchKind = "";
        searchPattern = "";
        matchIndex = -1;
        searchMessage = "";
        searchFailed = false;
    }

    // How tall it may be, and the room between the output's frame and its
    // text.
    readonly property real maxHeight: parent ? parent.height - 48 * zoom : 500
    readonly property real framePad: output ? 8 * zoom : 0

    width: Math.min(parent ? parent.width - 48 * zoom : 700, 760 * zoom)
    height: Math.min(maxHeight,
        body.height + header.height + footer.height + searchLine.height + 2 * padding + 2 * framePad)
    // In the middle, but one that grows as a command writes (see live).
    anchors.centerIn: live ? undefined : parent
    x: Math.round(((parent ? parent.width : width) - width) / 2)
    y: Math.round(((parent ? parent.height : maxHeight) - maxHeight) / 2)
    closePolicy: running ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onClosed: {
        running = false;
        if (selected)
            selected.deselect();
    }

    // The time a command has run for, and its dot's pulse.
    Timer {
        interval: 500
        repeat: true
        running: help.running && help.opened
        onTriggered: {
            help.outputNow = Date.now();
            help.pulse = !help.pulse;
        }
    }

    FontMetrics {
        id: monoMetrics

        font.family: help.monoFamily
        font.pixelSize: Math.round(13 * help.zoom)
    }

    // Selectable, but never focused, so keys stay with the help (which
    // forwards Copy, see copySelection).
    component HelpText: SelectableText {
        id: helpText

        theme: help.theme
        onSelectedTextChanged: {
            if (selectedText === "" || help.selected === helpText)
                return;
            if (help.selected)
                help.selected.deselect();
            help.selected = helpText;
        }
    }

    // Text with `code` (see Txt.parseCode), each code on a shade of its own,
    // drawn behind the text so it still selects and copies, and its search
    // matches highlighted. `plain` shows the text as it is (showList's).
    component CodeText: HelpText {
        id: codeText

        property string markup
        property bool plain
        // Which text of shownSections it is ("" for none), which search
        // goes through (see searchTexts).
        property string key
        readonly property var parsed: Txt.parseCode(markup, plain)
        // Its search matches, if search went through its text: the
        // Repeater deletes the old texts some time after shownSections
        // changes, and those mustn't take the new ones' matches.
        readonly property string marks: key !== "" && help.matchMarks[key]
            && help.searchTexts.list[help.searchTexts.order[key]].text === parsed.text ? help.matchMarks[key] : ""
        readonly property var markList: marks === "" ? [] : marks.split(";").map(m => m.split(",").map(Number))
        // The shades and highlights are placed once the text is laid out.
        readonly property var layout: [text, width, contentWidth, contentHeight]
        property var shades: []
        property var highlights: []
        readonly property FontMetrics codeMetrics: FontMetrics {
            font.family: help.monoFamily
            font.pixelSize: codeText.font.pixelSize
        }
        readonly property FontMetrics textMetrics: FontMetrics {
            font: codeText.font
        }

        function inCode(i) {
            return parsed.codes.some(code => i >= code.start && i < code.start + code.text.length);
        }

        // Rectangles over the characters [start, end), one per line they're
        // on (a code can break at a `/` or `-`): from `before` px before
        // start (`pad` on the next lines) to where the character after end
        // starts (past its letter spacing), less `trim`, or `pad` past a
        // line's last character.
        function rectsOver(start, end, before, pad, trim) {
            const rects = [];
            let from = positionToRectangle(start), left = from.x - before;
            for (let i = start + 1; i <= end; i++) {
                const at = positionToRectangle(i);
                if (at.y === from.y && i < end)
                    continue;
                const right = at.y === from.y ? at.x - trim : positionToRectangle(i - 1).x
                    + (inCode(i - 1) ? codeMetrics : textMetrics).advanceWidth(parsed.text[i - 1]) + pad;
                rects.push(Qt.rect(left, from.y, right - left, from.height));
                from = at;
                left = at.x - pad;
            }
            return rects;
        }

        // A shade behind each code, and a highlight behind each match. One
        // that starts or ends with a code covers its shade there.
        function place() {
            const pad = help.codePadding;
            const starts = parsed.codes.map(code => code.start);
            const s = [], h = [];
            for (const code of parsed.codes)
                s.push(...rectsOver(code.start, code.start + code.text.length, pad, pad, 0));
            for (const [start, end, current] of markList) {
                for (const r of rectsOver(start, end, starts.includes(start) ? pad : 0, 0, starts.includes(end) ? pad : 0))
                    h.push({ rect: r, current: current === 1 });
            }
            shades = s;
            highlights = h;
        }

        // Room for a shade at a line's start (so all text has it).
        leftPadding: help.codePadding
        text: Txt.codeHtml(parsed, markList, plain, help.monoFamily, help.codePadding)
        textFormat: TextEdit.RichText
        wrapMode: TextEdit.Wrap
        onLayoutChanged: Qt.callLater(place)
        Component.onCompleted: {
            if (key !== "")
                help.textItems.set(key, codeText);
        }
        Component.onDestruction: {
            if (help.textItems.get(key) === codeText)
                help.textItems.delete(key);
        }

        Repeater {
            model: codeText.shades

            Rectangle {
                required property rect modelData

                z: -1
                x: modelData.x
                y: modelData.y
                width: modelData.width
                height: modelData.height
                radius: 3 * help.zoom
                color: help.theme.code
            }
        }
        Repeater {
            model: codeText.highlights

            Rectangle {
                required property var modelData

                z: -0.5
                x: modelData.rect.x
                y: modelData.rect.y
                width: modelData.rect.width
                height: modelData.rect.height
                radius: 3 * help.zoom
                color: modelData.current ? help.theme.currentMatch : help.theme.searchMatch
            }
        }
    }

    contentItem: Item {
        Item {
            id: header

            width: parent.width
            height: title.height + 12 * help.zoom

            HelpText {
                id: title

                // A long one (a shell command) wraps, clear of the keys (or
                // of how the command ended).
                // That's given room for a time, so the command isn't cut
                // off elsewhere as it's counted.
                readonly property real room: parent.width - 12 * help.zoom
                    - (help.output ? Math.max(outputStatus.implicitWidth + 16 * help.zoom, 150 * help.zoom)
                        : keysHint.implicitWidth)

                width: Math.min(implicitWidth, room)
                wrapMode: TextEdit.WrapAnywhere
                leftPadding: help.codePadding // as CodeText's
                text: help.shownHeading
                // A command in the editor's font, as it was typed.
                font.family: help.output ? help.monoFamily : help.font.family
                font.pixelSize: Math.round((help.output ? 14 : 18) * help.zoom)
                font.bold: !help.output
                color: help.theme.text
            }
            TextMetrics {
                id: headingMetrics

                font: title.font
                text: help.heading
                elide: Qt.ElideMiddle
                // A row wrapped anywhere ends short of its room by less
                // than a character, which the em taken off each makes up.
                elideWidth: help.headingRows
                    * (title.room - title.leftPadding - title.rightPadding - title.font.pixelSize)
            }
            CodeText {
                id: keysHint

                anchors.right: parent.right
                anchors.baseline: title.baseline
                visible: !help.output
                markup: help.folds ? "`j` `k` to move · `Enter` to open · `/` to search · `q` to close"
                    : "`/` to search · `j` `k` to scroll · `Esc` or `q` to close"
                font.pixelSize: Math.round(12 * help.zoom)
                color: help.theme.dim
            }

            // How the command ended, or that it runs still, after a dot in
            // its color, which pulses while it runs.
            Text {
                id: outputStatus

                anchors.right: parent.right
                anchors.rightMargin: help.codePadding
                anchors.baseline: title.baseline
                visible: help.output
                text: help.outputStatus
                textFormat: Text.PlainText
                font.pixelSize: Math.round(12 * help.zoom)
                color: help.running ? help.theme.dim : help.outputColor
            }
            Rectangle {
                anchors.right: outputStatus.left
                anchors.rightMargin: 6 * help.zoom
                anchors.verticalCenter: outputStatus.verticalCenter
                visible: help.output
                width: 8 * help.zoom
                height: width
                radius: width / 2
                color: help.outputColor
                opacity: help.running && help.pulse ? 0.35 : 1
            }
        }

        // Behind a command's output: the editor's background, framed.
        Rectangle {
            anchors.top: header.bottom
            anchors.bottom: footer.top
            width: parent.width
            visible: help.output
            radius: 4 * help.zoom
            color: help.theme.base
            border.color: help.theme.panelBorder
        }

        WheelFlickable {
            id: scroller

            objectName: "helpScroller"
            anchors.top: header.bottom
            anchors.bottom: footer.top
            anchors.topMargin: help.framePad
            anchors.bottomMargin: help.framePad
            x: help.framePad
            // Its scroll bar clear of the frame's border.
            width: parent.width - x - (help.output ? 2 * help.zoom : 0)
            contentWidth: width
            contentHeight: body.height
            focus: true
            wheelStep: 3 * help.lineStep
            onScrolled: {
                help.unsettle();
                help.scrolled();
            }
            onMaxYChanged: {
                help.settle();
                if (help.following)
                    scrollTo(maxY);
            }

            Connections {
                target: scroller.scrollBar

                function onPressedChanged() {
                    help.unsettle();
                    if (scroller.scrollBar.pressed)
                        help.following = false;
                    else
                        help.scrolled();
                }
            }

            // As in a vim help buffer, and the usual keys.
            Keys.onPressed: event => {
                const ctrl = event.modifiers & (help.isMac ? Qt.MetaModifier : Qt.ControlModifier);
                const page = height - help.lineStep;
                // While a command runs, Esc and Ctrl-C stop it (Ctrl+C
                // copies a selection first, where it's Copy), and nothing
                // closes the box.
                const selection = help.selected !== null && help.selected.selectedText !== "";
                const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter;
                // z and a fold's key (see Folds); Shift alone, before R or
                // M, isn't one yet.
                if (help.zPending) {
                    if ([Qt.Key_Shift, Qt.Key_Control, Qt.Key_Meta, Qt.Key_Alt].includes(event.key))
                        return;
                    help.zPending = false;
                    if (event.text === "a")
                        help.toggle(help.current);
                    else if (event.text === "o" || event.text === "c")
                        help.setOpen(help.current, event.text === "o");
                    else if (event.text === "R" || event.text === "M")
                        help.setAllOpen(event.text === "R");
                    event.accepted = true;
                    return;
                }
                if (help.running && (event.key === Qt.Key_Escape && !help.searchShown
                        || ctrl && event.key === Qt.Key_C && !selection))
                    help.stopRequested();
                else if (event.matches(StandardKey.Copy))
                    help.copySelection();
                else if (event.key === Qt.Key_Escape && help.searchShown)
                    help.clearSearch();
                else if (help.folds && !ctrl && event.text === "z")
                    help.zPending = true;
                else if (help.folds && (enter || event.key === Qt.Key_Tab || event.key === Qt.Key_Space))
                    help.toggle(help.current);
                else if (help.folds && (event.key === Qt.Key_L && !ctrl || event.key === Qt.Key_Right))
                    help.setOpen(help.current, true);
                else if (help.folds && (event.key === Qt.Key_H && !ctrl || event.key === Qt.Key_Left))
                    help.setOpen(help.current, false);
                else if (help.folds && (event.key === Qt.Key_J && !ctrl || event.key === Qt.Key_Down))
                    help.moveCursor(true);
                else if (help.folds && (event.key === Qt.Key_K && !ctrl || event.key === Qt.Key_Up))
                    help.moveCursor(false);
                else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q && !event.modifiers || enter) {
                    if (!help.running)
                        help.close();
                }
                else if (!ctrl && (event.text === "/" || event.text === "?"))
                    help.startSearch(event.text);
                else if (!ctrl && (event.text === "n" || event.text === "N"))
                    help.searchAgain(event.text === "n" ? help.lastForward : !help.lastForward);
                else if (event.key === Qt.Key_J && !ctrl || event.key === Qt.Key_Down || ctrl && event.key === Qt.Key_E)
                    help.scrollBy(help.lineStep);
                else if (event.key === Qt.Key_K && !ctrl || event.key === Qt.Key_Up || ctrl && event.key === Qt.Key_Y)
                    help.scrollBy(-help.lineStep);
                else if (ctrl && event.key === Qt.Key_D)
                    help.scrollBy(height / 2);
                else if (ctrl && event.key === Qt.Key_U)
                    help.scrollBy(-height / 2);
                else if (ctrl && event.key === Qt.Key_F || event.key === Qt.Key_PageDown || event.key === Qt.Key_Space)
                    help.scrollBy(page);
                else if (ctrl && event.key === Qt.Key_B || event.key === Qt.Key_PageUp)
                    help.scrollBy(-page);
                else if (event.text === "G" || event.key === Qt.Key_G && event.modifiers & Qt.ShiftModifier
                        || event.key === Qt.Key_End) {
                    help.scrollBy(maxY);
                    if (help.folds)
                        help.current = help.nextFold(help.shownSections.length, -1);
                } else if (event.key === Qt.Key_G || event.key === Qt.Key_Home) {
                    help.scrollBy(-contentY);
                    if (help.folds)
                        help.current = help.nextFold(-1, 1);
                }
                else
                    return;
                event.accepted = true;
            }

            Column {
                id: body

                width: scroller.width - 12 * help.zoom // clear of the scroll bar
                spacing: (help.output ? 6 : help.folds ? 2 : 18) * help.zoom
                onHeightChanged: help.settle()

                // Over a command's output, if its first lines aren't kept.
                CodeText {
                    width: parent.width
                    visible: help.output && help.outputCut > 0
                    markup: "… " + help.outputCut + (help.outputCut === 1 ? " earlier line" : " earlier lines")
                        + " not shown: `:_!` puts all of it in the scratchpad (`_`)."
                    font.pixelSize: Math.round(12 * help.zoom)
                    color: help.theme.dim
                }

                Repeater {
                    id: sectionRepeater

                    model: help.shownSections

                    // A section: its title, and under it, while it's
                    // unfolded, its text, further in than the title's
                    // arrow. One that's a part of the one before shows
                    // only then too, title and all.
                    Column {
                        id: section

                        required property var modelData
                        required property int index
                        readonly property bool part: help.folds && !!modelData.part
                        // Whether its title is a fold's: with an arrow, and
                        // highlighted if it's the cursor's.
                        readonly property bool folding: help.folds && !part
                        readonly property bool open: help.isOpen(index)
                        readonly property real indent: help.folds ? 20 * help.zoom : 0
                        readonly property real headHeight: head.height

                        width: body.width
                        visible: open || !part
                        spacing: 6 * help.zoom
                        bottomPadding: help.folds && open ? 12 * help.zoom : 0

                        Item {
                            id: head

                            width: parent.width
                            height: sectionTitle.height + (section.folding ? 8 * help.zoom : 0)
                            visible: !!section.modelData.title

                            Rectangle {
                                anchors.fill: parent
                                visible: section.folding
                                radius: 4 * help.zoom
                                color: help.current === section.index ? help.theme.checked
                                    : headArea.containsMouse ? help.theme.hover : "transparent"
                            }
                            Icon {
                                x: 2 * help.zoom
                                anchors.verticalCenter: parent.verticalCenter
                                visible: section.folding
                                theme: help.theme
                                path: "M6 4.5 L9.5 8 L6 11.5"
                                rotation: section.open ? 90 : 0
                                color: help.theme.dim
                            }
                            CodeText {
                                id: sectionTitle

                                x: section.indent
                                anchors.verticalCenter: parent.verticalCenter
                                key: section.index + "/title"
                                markup: section.modelData.title
                                font.pixelSize: Math.round((section.part ? 13 : 15) * help.zoom)
                                font.bold: true
                                color: section.part ? help.theme.text : help.theme.accent
                            }
                            // Over the title, which isn't selected then: a
                            // click folds or unfolds.
                            MouseArea {
                                id: headArea

                                anchors.fill: parent
                                enabled: section.folding
                                visible: section.folding
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: help.toggle(section.index)
                            }
                        }
                        CodeText {
                            x: section.indent
                            width: parent.width - x
                            visible: section.open && !!section.modelData.intro
                            key: section.index + "/intro"
                            markup: section.modelData.intro || ""
                            plain: !!section.modelData.plain
                            font.family: plain ? help.monoFamily : help.font.family
                            font.pixelSize: Math.round(13 * help.zoom)
                            color: help.theme.text
                        }
                        Repeater {
                            // A folded section has no rows, so the help
                            // opens without making every one.
                            model: section.open ? section.modelData.rows : []

                            Row {
                                id: row

                                required property var modelData
                                required property int index

                                x: section.indent
                                spacing: 12 * help.zoom

                                CodeText {
                                    id: keysText

                                    width: section.modelData.keyColumns
                                        ? Math.ceil(section.modelData.keyColumns * monoMetrics.averageCharacterWidth)
                                        : Math.round(body.width * 0.34)
                                    key: section.index + "/" + row.index + "k"
                                    markup: row.modelData[0]
                                    plain: !!section.modelData.plain
                                    font.family: help.monoFamily
                                    font.pixelSize: Math.round(13 * help.zoom)
                                    color: help.theme.text
                                }
                                CodeText {
                                    width: body.width - section.indent - keysText.width - row.spacing
                                    key: section.index + "/" + row.index + "t"
                                    markup: row.modelData[1]
                                    plain: !!section.modelData.plain
                                    wrapMode: plain ? TextEdit.WrapAnywhere : TextEdit.Wrap
                                    font.family: plain ? help.monoFamily : help.font.family
                                    font.pixelSize: Math.round(13 * help.zoom)
                                    color: help.theme.text
                                }
                            }
                        }
                        CodeText {
                            x: section.indent
                            width: parent.width - x
                            visible: section.open && !!section.modelData.note
                            key: section.index + "/note"
                            markup: section.modelData.note || ""
                            font.pixelSize: Math.round(12 * help.zoom)
                            color: help.theme.dim
                        }
                    }
                }

                // A command's output: plain text, which is added to as
                // more comes (see addOutput), rather than set again, so
                // only what's new is laid out. Its search matches in view
                // are drawn over it, each part of one on a row (`marks`),
                // with its text in black, as CodeText's rich text has it.
                HelpText {
                    id: outputText

                    property var marks: []
                    readonly property var markInputs: [help.matches, help.matchIndex, scroller.contentY,
                        scroller.height, width, contentHeight]

                    function placeMarks() {
                        const found = help.output ? help.matches : [];
                        if (!found.length) {
                            if (marks.length)
                                marks = [];
                            return;
                        }
                        const top = Math.max(0, scroller.contentY - y);
                        const first = positionAt(0, top), last = positionAt(width, top + scroller.height);
                        const t = text, list = [];
                        found.forEach((m, i) => {
                            if (m.end <= first || m.start > last)
                                return;
                            let from = m.start, at = positionToRectangle(from);
                            for (let p = from + 1; p <= m.end; p++) {
                                const next = positionToRectangle(p);
                                if (p < m.end && next.y === at.y)
                                    continue;
                                // To where the next character starts, or
                                // past the row's last one.
                                const right = next.y === at.y ? next.x
                                    : positionToRectangle(p - 1).x + outputMetrics.advanceWidth(t[p - 1]);
                                list.push({ x: at.x, y: at.y, width: right - at.x, height: at.height,
                                    text: t.slice(from, p).replace(/\n/g, ""), current: i === help.matchIndex });
                                from = p;
                                at = next;
                            }
                        });
                        marks = list;
                    }

                    width: parent.width
                    visible: help.output
                    leftPadding: help.codePadding
                    textFormat: TextEdit.PlainText
                    wrapMode: TextEdit.WrapAnywhere
                    font.family: help.monoFamily
                    font.pixelSize: Math.round(13 * help.zoom)
                    color: help.theme.text
                    onMarkInputsChanged: Qt.callLater(placeMarks)
                    Component.onCompleted: help.textItems.set("output", outputText)

                    FontMetrics {
                        id: outputMetrics

                        font: outputText.font
                    }

                    Repeater {
                        model: outputText.marks

                        Rectangle {
                            id: mark

                            required property var modelData

                            x: modelData.x
                            y: modelData.y
                            width: modelData.width
                            height: modelData.height
                            radius: 2 * help.zoom
                            color: modelData.current ? help.theme.currentMatch : help.theme.searchMatch

                            Text {
                                text: mark.modelData.text
                                textFormat: Text.PlainText
                                font: outputText.font
                                color: "black"
                            }
                        }
                    }
                }
            }
        }

        // Under a command's output: the keys.
        Item {
            id: footer

            anchors.bottom: searchLine.top
            width: parent.width
            height: visible ? footerHint.height + 10 * help.zoom : 0
            visible: help.output

            CodeText {
                id: footerHint

                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2 * help.zoom
                markup: help.running ? "`Esc` to stop · `/` to search · `j` `k` to scroll"
                    : "`/` to search · `j` `k` to scroll · `Esc` or `q` to close"
                font.pixelSize: Math.round(12 * help.zoom)
                color: help.theme.dim
            }
        }

        // The search line, as vim's command line: the search being typed,
        // else the last one, or what it says, and which match it's at.
        Item {
            id: searchLine

            anchors.bottom: parent.bottom
            width: parent.width
            height: visible ? searchPrefix.height + 6 * help.zoom : 0
            visible: help.searchKind !== "" || help.searchShown

            Rectangle {
                width: parent.width
                height: 1
                color: help.theme.panelBorder
            }
            Text {
                id: searchPrefix

                anchors.left: parent.left
                anchors.leftMargin: help.codePadding
                anchors.bottom: parent.bottom
                width: help.searchKind ? implicitWidth : Math.min(implicitWidth, matchCount.x - x - 12 * help.zoom)
                text: help.searchKind || help.searchMessage || (help.lastForward ? "/" : "?") + help.lastPattern
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.family: help.monoFamily
                font.pixelSize: Math.round(13 * help.zoom)
                color: help.searchFailed && !help.searchKind ? help.theme.error : help.theme.text
            }
            TextInput {
                id: searchField

                anchors.left: searchPrefix.right
                anchors.right: matchCount.left
                anchors.rightMargin: 12 * help.zoom
                anchors.baseline: searchPrefix.baseline
                visible: help.searchKind !== ""
                clip: true
                font: searchPrefix.font
                color: help.theme.text
                selectByMouse: true
                selectionColor: help.theme.highlight
                selectedTextColor: help.theme.highlightedText
                onTextChanged: {
                    if (help.searchKind)
                        help.previewSearch(text);
                }
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        help.finishSearch(true);
                    else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace && text === "")
                        help.finishSearch(false);
                    else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down)
                        help.browseHistory(event.key === Qt.Key_Up);
                    else
                        return;
                    event.accepted = true;
                }
            }
            Text {
                id: matchCount

                anchors.right: parent.right
                anchors.rightMargin: help.codePadding
                anchors.baseline: searchPrefix.baseline
                text: help.matchIndex >= 0 ? "[" + (help.matchIndex + 1) + "/" + help.matches.length + "]" : ""
                font: searchPrefix.font
                color: help.theme.dim
            }
        }

        // A press anywhere but on the selected text (or the scroll bar)
        // clears the selection, as in other apps. The handler only watches,
        // so the press goes on to what's under it. Not a MouseArea, which
        // would show its arrow cursor over the text's I-beam.
        Item {
            id: pressWatcher

            anchors.fill: parent
            anchors.margins: -help.padding
            z: 1

            PointHandler {
                acceptedButtons: Qt.LeftButton
                onActiveChanged: {
                    const s = help.selected, p = point.position;
                    if (active && s && !s.contains(pressWatcher.mapToItem(s, p))
                        && !scroller.scrollBar.contains(pressWatcher.mapToItem(scroller.scrollBar, p)))
                        s.deselect();
                }
            }
        }
    }
}
