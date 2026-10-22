pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

import "help.js" as Help
import "text.js" as Txt

// :help, a box over the editor with what isn't obvious: Koil's listing,
// :set and its forms, the commands, shell commands, search, registers and
// macros, visual block and multiple cursors, marked lines, hidden text, the
// keys starting with g, z and Space, Ctrl keys and other keys.
// :help topic scrolls to a section, or a key's row (see show). :reg shows
// the registers in it too (showList), and :! what a command wrote
// (showText).
// Keys scroll it as in a vim help buffer, / and ? search it (see Search);
// Esc, q or Enter (as after vim's :!) closes it. Its text can be selected
// with the mouse and copied.
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

    // Opens the help at the section for `topic` (all of it if ""), at its
    // row of that key if it has one (`:h gs`), or else at the first row of
    // that key (`:h zs`). Tags and keys match as typed first, so `gI` isn't
    // `gi`, then in any case. `<C-a>`, `^A` and `CTRL-A` are `Ctrl-A`. False
    // if there's no help for it.
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
        showSections("Koil Help", sections, i, row);
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
    // characters (:reg).
    function showList(title, rows, keyColumns) {
        showPlain(title, { title: "", rows: rows, plain: true, keyColumns: keyColumns });
    }

    // Opens the box with `title` over `text`, as it is in the editor's
    // font, with its line breaks, and `note` after it (what a shell command
    // wrote).
    function showText(title, text, note) {
        showPlain(title, { title: "", intro: text, plain: true, rows: [], note: note });
    }

    function showPlain(title, section) {
        showSections(title, [section], 0, -1);
    }

    // Opens the box with `title` over `list`, at the section `section` and
    // its row `row` (-1 for its top).
    function showSections(title, list, section, row) {
        heading = title;
        shownSections = list;
        clearSearch();
        open();
        shownSection = section;
        shownRow = row;
        showSection();
    }

    // The section :help went to, and its row (-1 for its top). Its text is
    // laid out over the first frames, so it's scrolled to again as the
    // layout changes, until the user scrolls.
    property int shownSection: -1
    property int shownRow: -1

    function showSection() {
        const item = shownSection >= 0 ? sectionRepeater.itemAt(shownSection) : null;
        if (!item)
            return;
        const row = shownRow >= 0 ? textItems.get(shownSection + "/" + shownRow + "k") : null;
        scroller.contentY = Math.min(row ? row.mapToItem(body, 0, 0).y : item.y, scroller.maxY);
    }

    function scrollBy(dy) {
        shownSection = -1;
        scroller.scrollBy(dy);
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

    // Where match m's line is in the body.
    function matchY(m) {
        const item = textItems.get(m.key);
        return item ? item.mapToItem(body, 0, item.positionToRectangle(m.start).y).y : 0;
    }

    function inView(m) {
        const y = matchY(m);
        return y >= scroller.contentY && y < scroller.contentY + scroller.height;
    }

    // Scrolls match i to the middle, if it's out of view.
    function reveal(i) {
        shownSection = -1;
        const item = textItems.get(matches[i].key);
        if (!item)
            return;
        const height = item.positionToRectangle(matches[i].start).height;
        const y = matchY(matches[i]);
        if (y < scroller.contentY || y + height > scroller.contentY + scroller.height)
            scroller.contentY = Math.max(0, Math.min(scroller.maxY, y - (scroller.height - height) / 2));
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
        const from = matchIndex >= 0 && inView(matches[matchIndex]) ? matches[matchIndex] : null;
        goToMatch(forward, from);
    }

    // / or ? (and Find). Find while a search is typed selects it.
    function startSearch(kind) {
        if (searchKind) {
            searchField.selectAll();
            return;
        }
        const from = matchIndex >= 0 && inView(matches[matchIndex]) ? matches[matchIndex] : null;
        searchStart = { pattern: searchPattern, index: matchIndex, from: from, contentY: scroller.contentY };
        shownSection = -1;
        searchMessage = "";
        historyAt = -1;
        searchField.text = "";
        searchKind = kind;
        searchField.forceActiveFocus();
    }

    // Shows the matches of the search being typed, and the one Enter would
    // go to (vim's 'incsearch').
    function previewSearch(pattern) {
        scroller.contentY = searchStart.contentY;
        searchPattern = pattern || searchStart.pattern;
        const target = pattern ? nextMatch(searchKind === "/", searchStart.from) : null;
        matchIndex = pattern ? (target ? target.index : -1) : searchStart.index;
        if (target)
            reveal(target.index);
    }

    // Enter (`accept`), or Esc. An empty search searches for the last
    // pattern again.
    function finishSearch(accept) {
        const typed = searchField.text, forward = searchKind === "/";
        searchKind = "";
        scroller.forceActiveFocus();
        scroller.contentY = searchStart.contentY;
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

    width: Math.min(parent ? parent.width - 48 * zoom : 700, 760 * zoom)
    height: Math.min(parent ? parent.height - 48 * zoom : 500,
        body.height + header.height + searchLine.height + 2 * padding)
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onClosed: {
        if (selected)
            selected.deselect();
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
    // matches highlighted. `plain` shows the text as it is (a :reg list).
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

                // A long one (a shell command) wraps, clear of the keys.
                readonly property real room: parent.width - keysHint.implicitWidth - 12 * help.zoom

                width: Math.min(implicitWidth, room)
                wrapMode: TextEdit.WrapAnywhere
                leftPadding: help.codePadding // as CodeText's
                text: help.shownHeading
                font.pixelSize: Math.round(18 * help.zoom)
                font.bold: true
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
                markup: "`/` to search · `j` `k` to scroll · `Esc` or `q` to close"
                font.pixelSize: Math.round(12 * help.zoom)
                color: help.theme.dim
            }
        }

        WheelFlickable {
            id: scroller

            anchors.top: header.bottom
            anchors.bottom: searchLine.top
            width: parent.width
            contentWidth: width
            contentHeight: body.height
            focus: true
            wheelStep: 3 * help.lineStep
            onScrolled: help.shownSection = -1
            onMaxYChanged: help.showSection()

            Connections {
                target: scroller.scrollBar

                function onPressedChanged() {
                    help.shownSection = -1;
                }
            }

            // As in a vim help buffer, and the usual keys.
            Keys.onPressed: event => {
                const ctrl = event.modifiers & (help.isMac ? Qt.MetaModifier : Qt.ControlModifier);
                const page = height - help.lineStep;
                if (event.matches(StandardKey.Copy))
                    help.copySelection();
                else if (event.key === Qt.Key_Escape && help.searchShown)
                    help.clearSearch();
                else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q && !event.modifiers
                        || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                    help.close();
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
                else if (event.key === Qt.Key_G && event.modifiers & Qt.ShiftModifier || event.key === Qt.Key_End)
                    help.scrollBy(maxY);
                else if (event.key === Qt.Key_G || event.key === Qt.Key_Home)
                    help.scrollBy(-contentY);
                else
                    return;
                event.accepted = true;
            }

            Column {
                id: body

                width: scroller.width - 12 * help.zoom // clear of the scroll bar
                spacing: 18 * help.zoom
                onHeightChanged: help.showSection()

                Repeater {
                    id: sectionRepeater

                    model: help.shownSections

                    Column {
                        id: section

                        required property var modelData
                        required property int index

                        width: body.width
                        spacing: 6 * help.zoom

                        CodeText {
                            visible: !!section.modelData.title
                            key: section.index + "/title"
                            markup: section.modelData.title
                            font.pixelSize: Math.round(15 * help.zoom)
                            font.bold: true
                            color: help.theme.accent
                        }
                        CodeText {
                            width: parent.width
                            visible: !!section.modelData.intro
                            key: section.index + "/intro"
                            markup: section.modelData.intro || ""
                            plain: !!section.modelData.plain
                            font.family: plain ? help.monoFamily : help.font.family
                            font.pixelSize: Math.round(13 * help.zoom)
                            color: help.theme.text
                        }
                        Repeater {
                            model: section.modelData.rows

                            Row {
                                id: row

                                required property var modelData
                                required property int index

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
                                    width: body.width - keysText.width - row.spacing
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
                            width: parent.width
                            visible: !!section.modelData.note
                            key: section.index + "/note"
                            markup: section.modelData.note || ""
                            font.pixelSize: Math.round(12 * help.zoom)
                            color: help.theme.dim
                        }
                    }
                }
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
