import QtQuick

import "text.js" as Txt

// Vim emulation for a TextEdit. The editor keeps the text; this object keeps
// the mode, the cursor (a character index: in normal and visual mode the
// cursor sits *on* the character at `cursor`), registers and undo history.
// While a key runs, vim edits a copy of the text, which the editor then gets
// as one edit through editor.insert/remove, so the view keeps its scroll
// position (see Batches).
QtObject {
    id: vim

    required property Item editor
    property Flickable flickable: null
    // Object with clipboardText(), clipboardData() and setClipboardText(text,
    // data): backs the "+ and "* registers. No other register touches the
    // system clipboard. data is Koil's own (the hidden texts).
    property var clipboard: null
    property real lineHeight: 16
    // How wide a column is (a character of the editor's font).
    property real charWidth: 8
    readonly property int pageLines: flickable ? Math.max(2, Math.floor(flickable.height / lineHeight)) : 20

    // "normal", "insert", "replace", "visual", "visualLine" or "visualBlock"
    property string mode: "normal"
    property int cursor: 0
    property int anchor: 0
    property string pendingKeys: ""
    property bool awaitingReplaceChar: false
    property string commandLine: ""
    // Index in commandLine that the command-line cursor sits on (1 or more;
    // index 0 holds the ":", "/" or "?").
    property int commandCursor: 1
    property string message: ""
    property bool messageIsError: false
    // :set number and :set relativenumber (the view draws the line numbers),
    // with their defaults.
    property bool number: false
    property bool defaultNumber: false
    property bool relativeNumber: false
    property bool defaultRelativeNumber: false
    // :set fontsize, in points (the view sets the editor's font), with its
    // default and range.
    property int fontSize: 16
    property int defaultFontSize: 16
    property int minFontSize: 1
    property int maxFontSize: 999
    // :set guifont, a font family (the view sets the editor's font), with
    // its default and the families it can be (any, if empty), which
    // fontFamiliesNeeded asks the view to fill in.
    property string fontFamily: ""
    property string defaultFontFamily: ""
    property var fontFamilies: []
    // :set sidescrolloff: the columns kept in view on either side of the
    // cursor when the view scrolls sideways (see showColumn). Vim's
    // default is 0.
    property int sideScrollOff: 4
    // Koil's :set hidden, gitignore and regex: show hidden entries (and
    // ../), hide what git ignores, and read the path to open as a regex
    // (see Settings in koil-core). The view applies them to the listing.
    property bool showHidden: false
    property bool gitignore: false
    property bool regex: false
    // Keys that run one of Koil's commands in normal mode instead of what
    // they do in vim, as { keys: name }, like { "-": "parent" }: " " is
    // Space and "<CR>" Enter. Only at the start of a command, so "d-" still
    // deletes up a line. Typing one emits keyCommand.
    property var commandKeys: ({})
    // A buffer of one line (Koil's path field): a line break put in it
    // becomes a space, and Enter while typing leaves insert mode, then does
    // what it does in normal mode.
    property bool singleLine: false
    // Where Tab while typing completes (Koil's path field, see Completion):
    // a function of the text and the cursor that gives { start, fill,
    // options } (see listing::Completion), each option { name, icon,
    // colors } to write from `start` to the cursor. Null elsewhere.
    property var completer: null
    // The options Tab shows once it can't fill in more, as { start,
    // options, index } (the picked one), or null. Moving the cursor (or
    // leaving insert mode) closes them.
    property var completion: null
    // The lines a buffer of one line had before (Koil's path field: the
    // locations listed), oldest first: k and j (and Up and Down, also
    // while typing) put the one before or after in (see browseLines). Null
    // where there's none.
    property var lineHistory: null
    // While going through it: { index, typed, shown }, the entry shown
    // (lineHistory.length for `typed`), what the line was before, and the
    // text put in, so a line edited since starts over.
    property var lineBrowse: null
    // Koil's listing: each line starts with a prefix, its entry's icon
    // and two spaces, or three spaces on a line that has none, which the
    // cursor never goes into (see Prefixes). A line without one is plain.
    property bool linePrefixes: false
    // What a new line starts with, and a line break that starts one.
    readonly property string blankPrefix: linePrefixes ? "   " : ""
    readonly property string lineBreak: "\n" + blankPrefix

    readonly property bool isVisual: mode === "visual" || mode === "visualLine" || mode === "visualBlock"
    // Insert or replace mode: typing edits the text, at the editor's cursor.
    readonly property bool inserting: mode === "insert" || mode === "replace"
    readonly property string cursorShape: mode === "insert" ? "bar"
        : mode === "replace" || awaitingReplaceChar ? "underline" : "block"
    readonly property string modeLabel: [({
            insert: "-- INSERT --",
            replace: "-- REPLACE --",
            visual: "-- VISUAL --",
            visualLine: "-- VISUAL LINE --",
            visualBlock: "-- VISUAL BLOCK --"
        })[mode] || "", cursors.length ? "MULTI CURSOR" : "", recording ? "recording @" + recording : ""]
        .filter(s => s).join(" ")

    signal fontFamiliesNeeded
    // `confirm` (ZZ): if writing asks first (Koil's apply), No quits
    // without writing.
    signal writeRequested(bool quit, bool confirm)
    // `confirm` (:confirm q): ask whether to save unsaved changes instead
    // of failing. `all` (:qa, :qa!): quit everything, not just what's shown.
    signal quitRequested(bool force, bool confirm, bool all)
    // gh: show what's under the cursor at `at` (the text an icon hides, or a
    // warning or error), if anything.
    signal hoverRequested(int at)
    // Esc in normal mode, or :noh: search highlights should go.
    signal highlightsCleared()
    // :help, or :help topic.
    signal helpRequested(string topic)
    // :reg, with what registerList gives.
    signal registersRequested(var rows)
    // One of commandKeys was typed, with its count (0 if none).
    signal keyCommand(string name, int count)
    // u (or Cmd+Z) with no change left to undo: Koil offers to undo its last
    // apply.
    signal nothingToUndo()

    readonly property bool isMac: Qt.platform.os === "osx"
    readonly property var operators: ["d", "c", "y", ">", "<", "g~", "gu", "gU", "g?"]
    readonly property var motions: ["h", "j", "k", "l", "<Left>", "<Right>", "<Up>", "<Down>", "<BS>", " ",
        "w", "W", "b", "B", "e", "E", "ge", "gE", "0", "^", "$", "<Home>", "<End>", "gg", "G",
        ";", ",", "%", "{", "}", "+", "-", "_", "<CR>", "<S-CR>", "|", "n", "N", "*", "#", "H", "M", "L",
        "<C-d>", "<C-u>", "<C-f>", "<C-b>", "<PageDown>", "<PageUp>"]
    readonly property var normalActions: ["i", "a", "I", "A", "gI", "o", "O", "v", "V", "x", "<Del>", "X",
        "s", "S", "C", "D", "Y", "p", "P", "J", "gJ", "u", "<C-r>", ".", "~", "r", "R", ":", "/", "?",
        "ZZ", "ZQ", "zz", "zt", "zb", "<C-e>", "<C-y>", "gv", "gh", "<C-a>", "<C-x>", "q", "@", "<C-v>", "<Esc>"]
    readonly property var visualActions: ["<Esc>", "v", "V", "<C-v>", "o", "O", "x", "<Del>", "X", "D", "s",
        "C", "S", "R", "Y", "~", "u", "U", "r", "J", "gJ", "p", "P", ":", "/", "?", "q", "I", "A", "<C-e>", "<C-y>"]
    // Normal-mode commands that run at every cursor (as do operators and
    // motions). "." does too, through the command it repeats.
    readonly property var everyCursorActions: ["i", "a", "I", "A", "gI", "o", "O", "x", "<Del>", "X", "s",
        "S", "C", "D", "Y", "p", "P", "J", "gJ", "~", "r", "R", "<C-a>", "<C-x>"]
    // The registers vim fills itself, and the actions that write a register.
    readonly property var readOnlyRegisters: [".", ":", "/", "%"]
    readonly property var writingActions: ["d", "c", "y", "x", "<Del>", "X", "s", "S", "C", "D", "Y"]
    readonly property var visualModes: ({ "v": "visual", "V": "visualLine", "<C-v>": "visualBlock" })
    // Marks the clipboard data this Koil writes. Another Koil's hidden texts
    // (IDs) mean other things, so its icons are pasted without them.
    readonly property string clipboardSession: Math.random().toString(36).slice(2)
    // Normal-mode commands that modify the text (and so can be repeated with ".").
    readonly property var changeActions: ["i", "a", "I", "A", "gI", "o", "O", "x", "<Del>", "X", "s", "S",
        "C", "D", "p", "P", "J", "gJ", "~", "r", "R", "<C-a>", "<C-x>"]
    readonly property var textObjects: ["w", "W", "p", "\"", "'", "`", "(", ")", "b", "[", "]", "{", "}",
        "B", "<", ">"]

    property var keys: []
    property var registers: ({})
    // The text the last insert typed (the ". register).
    property string lastInsert: ""
    // The file or listing being edited (the "% register).
    property string fileName: ""
    property var undoStack: []
    property var redoStack: []
    property var change: null
    property var wantCol: 0
    property var lastFind: null
    property var lastSearch: null
    property var lastVisual: null
    property var dot: null
    property var insertSession: null
    // Extra cursors (Alt+click, or one per line of a block insert), sorted:
    // { pos, col, registers, replaceStack }, where col is its wantCol,
    // registers its own (see atEveryCursor) and replaceStack what it
    // replaced in replace mode. Commands work at all of them, and leaving
    // insert or replace mode removes them. Edits move them (see
    // replaceRange). Replaced, never changed in place, so the view sees
    // every change.
    property var cursors: []
    // While editAll runs: every cursor, the main one too, for edits to move
    // (none while editAtOnce runs, which places them itself).
    property var shifting: null
    // During a block insert: where it started ({ line, offset, moved }), to go
    // back to after it unless the cursors moved.
    property var blockHome: null
    property var replaceStack: []
    property bool syncing: false
    property bool replaying: false
    // Macros: the register being recorded into ("" when not recording) and
    // the keys typed so far. Running a macro puts its keys in `typeahead`,
    // which runs them one by one; a failing command empties it, as in vim.
    property string recording: ""
    property var recordKeys: []
    // The keys left to run, as a stack of { keys, next, runs }: the top
    // one's keys[next] is next, and each runs its keys `runs` times
    // (rather than holding them that many times: 10000@q copied them
    // 10000 times over).
    property var typeahead: []
    // A long command running in steps (see startTask), before any more
    // keys: { steps, done, step, finish }. Null if none.
    property var task: null
    // The run that hasn't finished (a macro's, or a long command's; see
    // Runs), as { label, frame, runs }: what the status line calls it, and
    // for a macro, its frame in typeahead and how many times it runs. Null
    // if none.
    property var running: null
    // While a chunk of it runs (runChunk).
    property bool inChunk: false
    // How long a chunk runs, in ms (at least one key or step): the editor
    // gets its edits, the status line its progress, and the user a chance
    // to stop it after each one.
    property int chunkTime: 50
    // Qt draws only once nothing is waiting, which a timer that's due never
    // lets it: the chunks run back to back, but now and then the next one
    // waits drawTime ms, for Qt to show the edits and the progress. As it
    // takes a while to draw a long text (over 100 ms at 40000 lines), that's
    // only as often as keeps drawing to about a fifth of the time, and at
    // most 4 times a second (drawEvery ms). `nextDraw` is when the next
    // chunk lets Qt draw, and `drawStart` when it did, until the next one.
    readonly property int drawTime: 20
    readonly property int drawEvery: 250
    property real nextDraw: 0
    property real drawStart: 0
    readonly property Timer chunkTimer: Timer {
        onTriggered: vim.runChunk()
    }
    // While a key or a chunk runs: the text vim edits instead of the
    // editor's, with the cursor, anchor and mode the editor has, as { text,
    // cursor, anchor, mode } (see bufferText and flush). Null otherwise.
    property var batch: null
    // While a run goes on: what the status line shows instead of the
    // cursor's position, like "@q 34%".
    property string progress: ""
    property string lastMacro: ""
    // As vim's 'maxmapdepth': macros running macros, past this, fail.
    readonly property int maxMacroDepth: 1000
    // Command-line history: ":" commands, and "/" and "?" searches together.
    property var history: ({ ":": [], "/": [] })
    property int historyIndex: -1 // -1 while not browsing
    property string historyTyped: ""
    // While a search is typed: where Enter would jump (-1 if nowhere), and
    // the view to go back to if the search is cancelled.
    property int searchTarget: -1
    property var searchView: null
    // The last search stays highlighted until Esc in normal mode (or :noh).
    property string highlightPattern: ""
    // Start of the match to show as current: the one a typed search would
    // jump to, otherwise the one under the cursor.
    readonly property int highlightTarget: commandLine[0] === "/" || commandLine[0] === "?" ? searchTarget : cursor

    onCommandLineChanged: previewSearch()
    // The options are for where they were found (completing sets them again
    // after it moves the cursor).
    onCursorChanged: completion = null
    onModeChanged: completion = null
    onLineHistoryChanged: lineBrowse = null

    // ---- Entry points ------------------------------------------------------

    // Starts over with the editor's new text, whose icons hide the texts in
    // `entries` (see Hidden text). Leaves other buffers alone (see Buffers).
    function reset(entries) {
        interrupt();
        keys = [];
        pendingKeys = "";
        awaitingReplaceChar = false;
        commandLine = "";
        message = "";
        undoStack = [];
        redoStack = [];
        change = null;
        hidden = entries || [];
        trackedText = bufferText();
        insertSession = null;
        cursors = [];
        blockHome = null;
        setMode("normal");
        setCursor(0);
    }

    // Returns whether the key was consumed; unconsumed keys go to the editor.
    function handleKey(event) {
        const tok = tokenFor(event);
        // While a run goes on (keys come between its chunks), Esc or Ctrl-C
        // stops it, and other keys do nothing.
        if (running) {
            if (tok === "<Esc>" || tok === "<C-c>")
                stopRun();
            return true;
        }
        // However many edits the key makes, the editor gets one.
        return batched(() => keyPressed(tok, event));
    }

    function keyPressed(tok, event) {
        // Enter with a modifier vim doesn't know (Cmd+Enter), which the
        // editor would make a line break.
        if (singleLine && tok === null && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter))
            return true;
        if (commandLine !== "")
            return typedKey(tok, event);
        if (!isVisual && mode !== "insert")
            message = "";
        // Ctrl+Y is also Redo on Windows and Linux, and Paste (yank) on
        // macOS, except outside insert mode, where it scrolls as in vim.
        const scrollKey = mode !== "insert" && tok === "<C-y>";
        if ((event.matches(StandardKey.Undo) || event.matches(StandardKey.Redo)) && !scrollKey) {
            nativeUndo(event.matches(StandardKey.Redo));
            return true;
        }
        if (mode === "insert") {
            // Also through the "+ register, so hidden text stays hidden
            // when pasted here.
            const s = editor.selectionStart, e = editor.selectionEnd;
            if (event.matches(StandardKey.Copy) || event.matches(StandardKey.Cut)) {
                if (e > s) {
                    setRegister("+", bufferText().slice(s, e), false, true, hiddenIn(hidden, s, e));
                    if (event.matches(StandardKey.Cut)) {
                        replaceRange(s, e, "");
                        setCursor(s);
                    }
                }
                return true;
            }
            // Ctrl+V pastes too, also on macOS (where Paste is Cmd+V).
            if (event.matches(StandardKey.Paste) || tok === "<C-v>") {
                const r = getRegister("+");
                if (r)
                    insertPaste(r);
                return true;
            }
        } else {
            // On Windows and Linux, Ctrl+A and Ctrl+X are Select All and Cut,
            // except in normal mode, where they add to a number as in vim.
            // Ctrl+V (Paste there) starts visual block mode.
            const addKey = mode === "normal" && ["<C-a>", "<C-x>"].includes(tok);
            const blockKey = tok === "<C-v>";
            if (event.matches(StandardKey.Copy)) {
                if (isVisual)
                    execute({ reg: "+", count: 0, action: "y" });
                return true;
            }
            if (event.matches(StandardKey.Cut) && !addKey) {
                if (isVisual)
                    execute({ reg: "+", count: 0, action: "d" });
                return true;
            }
            if (event.matches(StandardKey.Paste) && !blockKey && !scrollKey) {
                if (mode !== "replace")
                    execute({ reg: "+", count: 0, action: "P" });
                return true;
            }
            if (event.matches(StandardKey.SelectAll) && !addKey) {
                if (mode !== "replace") {
                    setMode("visualLine");
                    anchor = clampNormal(bufferText(), 0);
                    setCursor(bufferText().length);
                }
                return true;
            }
        }
        return typedKey(tok, event);
    }

    // A key the user typed, which a macro being recorded keeps.
    function typedKey(tok, event) {
        if (recording && tok !== null)
            recordKeys.push(tok);
        return runKey(tok, event);
    }

    // Runs a typed key, or one from a macro (with no event).
    function runKey(tok, event) {
        // Shift+Enter is Enter, except as a motion: then it's vim's Enter
        // where Koil's does something else (see commandKeys). In one line,
        // Enter and Shift+Enter while typing are normal mode's (Koil's).
        if (tok === "<S-CR>" && (commandLine !== "" || inserting && !singleLine))
            tok = "<CR>";
        if (commandLine !== "")
            return commandLineKey(tok);
        if (mode === "insert" && completer && (completion || tok === "<Tab>") && completionKey(tok))
            return true;
        if (singleLine && inserting && (tok === "<CR>" || tok === "<S-CR>")) {
            leaveInsert();
            // After the insert's repeat, if it goes on (see Runs).
            if (task)
                typeahead.push({ keys: [tok], next: 0, runs: 1 });
            else
                feed(tok);
            return true;
        }
        if (mode === "insert")
            return insertKey(tok, event);
        // Cmd+Backspace deletes only while typing (and in the command line),
        // and Shift+Tab only picks from the completion's options.
        if (tok === null || tok === "<D-BS>" || tok === "<S-Tab>")
            return true;
        if (mode === "replace") {
            if (tok === "<Esc>") {
                leaveInsert();
            } else if (!isSpecial(tok) || ["<CR>", "<Tab>", "<BS>"].includes(tok)) {
                if (insertSession && !insertSession.broken)
                    insertSession.keys.push(tok);
                replaceKey(tok);
            }
            return true;
        }
        feed(tok);
        return true;
    }

    // Called when the editor's cursor or selection changes, e.g. by the mouse.
    function syncFromEditor() {
        if (syncing)
            return;
        interrupt();
        const p = editor.cursorPosition, t = editor.text;
        if (inserting) {
            // Not into a line's prefix (by an arrow key, Home or a click):
            // to its end instead. Typing moves the cursor before `text`
            // has the typed character (`length` does), and never into one.
            const q = editor.length === t.length ? outOfPrefix(t, p) : p;
            if (q !== p && editor.selectionStart === editor.selectionEnd) {
                setCursor(q);
                return;
            }
            if (q !== p) {
                syncing = true;
                editor.moveCursorSelection(q);
                syncing = false;
            }
            cursor = q;
            // The editor scrolls only as far as shows its cursor: the room
            // beside it, once `text` has what was typed.
            if (editor.selectionStart === editor.selectionEnd)
                Qt.callLater(showColumn);
            return;
        }
        keys = [];
        pendingKeys = "";
        awaitingReplaceChar = false;
        const s = editor.selectionStart, e = editor.selectionEnd;
        if (s !== e) {
            mode = "visual";
            const a = p === e ? s : Txt.charStart(t, e - 1), c = p === e ? Txt.charStart(t, e - 1) : s;
            anchor = outOfPrefix(t, a);
            cursor = outOfPrefix(t, c);
            if (anchor !== a || cursor !== c) {
                syncing = true;
                updateSelection();
                syncing = false;
            }
            return;
        }
        if (isVisual)
            mode = "normal";
        const c = clampNormal(t, p);
        wantCol = Txt.column(t, c);
        if (c !== p)
            setCursor(c);
        else
            cursor = c;
    }

    // Runs an edit made outside vim (e.g. from a menu) as its own undo step.
    function externalEdit(fn) {
        interrupt();
        commitChange();
        beginChange();
        fn();
        commitChange();
        if (inserting)
            beginChange();
    }

    // Cmd+Z / Cmd+Shift+Z, in any mode (also from the find bar).
    function nativeUndo(isRedo) {
        interrupt();
        if (commandLine !== "")
            commandLineKey("<Esc>");
        const wasInserting = inserting;
        if (wasInserting)
            breakInsert();
        if (isVisual) {
            setMode("normal");
            setCursor(clampNormal(bufferText(), cursor));
        }
        if (isRedo)
            redo(1);
        else
            undo(1);
        if (wasInserting)
            beginChange();
    }

    // Moves the cursor to p from outside vim (the find bar): back to one
    // cursor, out of visual mode, and a new undo step in insert mode.
    function jumpTo(p) {
        interrupt();
        if (commandLine !== "")
            commandLineKey("<Esc>");
        keys = [];
        pendingKeys = "";
        awaitingReplaceChar = false;
        clearCursors();
        if (isVisual)
            setMode("normal");
        if (inserting) {
            breakInsert();
            replaceStack = [];
        }
        const t = bufferText();
        p = mode === "normal" ? clampNormal(t, p) : outOfPrefix(t, Math.max(0, Math.min(p, t.length)));
        setCursor(p);
        wantCol = Txt.column(t, p);
    }

    // Runs a motion from outside vim, as if typed (Koil's Enter, on a line
    // it doesn't open).
    function runMotion(name, count) {
        interrupt();
        execute({ reg: null, count: count, motion: { name: name } });
    }

    // Columns count from where a line's prefix ends, as the cursor can't
    // go before it.
    function positionLabel() {
        const t = bufferText(), ls = Txt.lineStart(t, cursor);
        return Txt.lineOf(t, cursor) + ":" + (Txt.column(t, cursor) - Txt.column(t, prefixEnd(t, ls)) + 1);
    }

    function showError(text) {
        message = text;
        messageIsError = true;
        typeahead = [];
    }

    function showMessage(text) {
        message = text;
        messageIsError = false;
    }

    // ---- Buffers -----------------------------------------------------------
    // Vim can edit several editors (buffers, in vim's words), one at a time:
    // Koil's path field and its listing. To switch, leaveBuffer the one it
    // edits, give vim the other one's `editor` and `flickable`, and
    // enterBuffer it. Registers, searches, macros, the command line and the
    // options are shared; each buffer has its own cursor, undo history and
    // hidden text, which leaveBuffer gives back.

    // Leaves the buffer vim edits in normal mode, and returns its state for
    // enterBuffer: { cursor, wantCol, undoStack, redoStack, hidden,
    // lastVisual }.
    function leaveBuffer() {
        interrupt();
        if (commandLine !== "")
            commandLineKey("<Esc>");
        // Without the count's repeat, which would go on after (see Runs), as
        // when the cursor moves.
        if (inserting)
            leaveInsert(false);
        if (isVisual) {
            setMode("normal");
            setCursor(clampNormal(bufferText(), cursor));
        }
        commitChange(true); // even in a macro: the step is this buffer's
        clearCursors();
        keys = [];
        pendingKeys = "";
        awaitingReplaceChar = false;
        return { cursor: cursor, wantCol: wantCol, undoStack: undoStack, redoStack: redoStack,
            hidden: hidden, lastVisual: lastVisual };
    }

    // Edits the buffer vim was just given, from the state leaveBuffer gave
    // for it. Whatever `state` leaves out starts empty (all of it for null),
    // and the cursor at 0.
    function enterBuffer(state) {
        const s = state || {}, t = bufferText();
        undoStack = s.undoStack || [];
        redoStack = s.redoStack || [];
        hidden = s.hidden || [];
        lastVisual = s.lastVisual || null;
        trackedText = t;
        cursor = clampNormal(t, s.cursor || 0);
        setMode("normal");
        setCursor(cursor);
        wantCol = s.wantCol === undefined ? Txt.column(t, cursor) : s.wantCol;
    }

    // ---- Keys --------------------------------------------------------------

    // Turns a key event into a vim key: a character, or a name like "<Esc>",
    // "<CR>" or "<C-r>". Returns null for keys vim doesn't handle.
    function tokenFor(event) {
        const ctrl = isMac ? Qt.MetaModifier : Qt.ControlModifier;
        if ((event.modifiers & ctrl) && !(event.modifiers & Qt.AltModifier)) {
            if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z)
                return "<C-" + String.fromCharCode(event.key - Qt.Key_A + 97) + ">";
            if (event.key === Qt.Key_BracketLeft)
                return "<Esc>";
            return null;
        }
        if (isMac && (event.modifiers & Qt.ControlModifier)) // Cmd
            return event.key === Qt.Key_Backspace ? "<D-BS>" : null;
        const named = {
            [Qt.Key_Escape]: "<Esc>",
            [Qt.Key_Return]: "<CR>",
            [Qt.Key_Enter]: "<CR>",
            [Qt.Key_Backspace]: "<BS>",
            [Qt.Key_Delete]: "<Del>",
            [Qt.Key_Tab]: "<Tab>",
            [Qt.Key_Backtab]: "<S-Tab>",
            [Qt.Key_Left]: "<Left>",
            [Qt.Key_Right]: "<Right>",
            [Qt.Key_Up]: "<Up>",
            [Qt.Key_Down]: "<Down>",
            [Qt.Key_Home]: "<Home>",
            [Qt.Key_End]: "<End>",
            [Qt.Key_PageUp]: "<PageUp>",
            [Qt.Key_PageDown]: "<PageDown>"
        }[event.key];
        if (named === "<CR>" && event.modifiers & Qt.ShiftModifier)
            return "<S-CR>";
        if (named)
            return named;
        const text = event.text;
        if (text.length > 0 && text.charCodeAt(0) >= 32 && text !== "\x7f")
            return text;
        return null;
    }

    function isSpecial(tok) {
        return tok.length > 2 && tok[0] === "<" && tok[tok.length - 1] === ">";
    }

    function insertKey(tok, event) {
        if (tok === "<Esc>") {
            leaveInsert();
            return true;
        }
        const own = linePrefixes && event && tok !== "<D-BS>" ? prefixKey(event) : null;
        if (own)
            tok = own;
        if (tok === null)
            return false;
        if ((tok === "<Up>" || tok === "<Down>") && lineStep(tok)) {
            breakInsert();
            browseLines(lineStep(tok), 1);
            return true;
        }
        const s = insertSession;
        const move =["<Left>", "<Right>", "<Up>", "<Down>", "<Home>", "<End>", "<PageUp>", "<PageDown>"].includes(tok);
        const typed = !isSpecial(tok) || ["<CR>", "<Tab>", "<BS>", "<Del>", "<D-BS>"].includes(tok);
        if (move)
            breakInsert();
        else if (s && !s.broken && typed)
            s.keys.push(tok);
        // The editor doesn't know Cmd+Backspace: with a selection, it
        // deletes that, as Backspace does.
        const from = editor.selectionStart, to = editor.selectionEnd;
        if (tok === "<D-BS>" && event && to > from) {
            replaceRange(from, to, "");
            setCursor(from);
            return true;
        }
        // A macro has no event for the editor to handle, and the editor
        // knows only one cursor, so vim does it. Shift+Enter too, which the
        // editor would make a line separator rather than a line break,
        // Cmd+Backspace, and the keys that must keep the prefixes.
        if (!event || own || tok === "<D-BS>" || cursors.length && (move || typed)
                || tok === "<CR>" && event.modifiers & Qt.ShiftModifier) {
            if (move)
                insertMove(tok);
            else if (typed)
                typeKey(tok);
            return true;
        }
        // The editor's backspace deletes one code point, which would leave
        // most of an emoji (or of an icon hiding text) behind.
        if (tok === "<BS>" && event.modifiers === Qt.NoModifier && editor.selectionStart === editor.selectionEnd) {
            typeKey(tok);
            return true;
        }
        return false;
    }

    // In Koil's listing, the insert-mode key `event` as vim's <CR>, <BS> or
    // <Del> if vim must type it to keep the prefixes (see Prefixes): Enter,
    // so the new line gets one, and the keys that delete (like
    // Alt+Backspace) back from a name's start or forward from a line's
    // end, into a prefix. Null for the others, which the editor types.
    function prefixKey(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            return "<CR>";
        if (editor.selectionStart !== editor.selectionEnd)
            return null;
        const t = bufferText(), p = editor.cursorPosition;
        if (event.key === Qt.Key_Backspace || event.matches(StandardKey.Backspace)
                || event.matches(StandardKey.DeleteStartOfWord))
            return /^[ \t]*$/.test(t.slice(prefixEnd(t, Txt.lineStart(t, p)), p)) ? "<BS>" : null;
        if (event.key === Qt.Key_Delete || event.matches(StandardKey.Delete)
                || event.matches(StandardKey.DeleteEndOfWord))
            return p === Txt.lineEnd(t, p) ? "<Del>" : null;
        return null;
    }

    // Moves the insert-mode cursors like the editor does for these keys.
    function insertMove(tok) {
        setCursor(editAll(p => insertMoved(bufferText(), p, tok)));
    }

    function insertMoved(t, p, tok) {
        let q = p;
        if (tok === "<Left>") {
            q = p > 0 ? Txt.charStart(t, p - 1) : p;
        } else if (tok === "<Right>") {
            q = p < t.length ? Txt.charEnd(t, p) : p;
        } else if (tok === "<Home>") {
            q = Txt.lineStart(t, p);
        } else if (tok === "<End>") {
            q = Txt.lineEnd(t, p);
        } else {
            const lines = tok === "<Up>" ? -1 : tok === "<Down>" ? 1 : tok === "<PageUp>" ? -pageLines : pageLines;
            const col = Txt.column(t, p);
            const r = lineMotion(t, p, lines);
            if (r) {
                const ls = Txt.lineStart(t, r.pos);
                q = Txt.advance(t, ls, col, Txt.lineEnd(t, ls));
            }
        }
        return outOfPrefix(t, q);
    }

    function openCommandLine(kind) {
        commandCursor = 1;
        commandLine = kind;
    }

    // Replaces commandLine[from, to) with text and puts the cursor after it.
    function editCommandLine(from, to, text) {
        commandCursor = from + text.length;
        commandLine = commandLine.slice(0, from) + text + commandLine.slice(to);
    }

    function commandLineKey(tok) {
        if (tok === "<Up>" || tok === "<Down>") {
            browseHistory(tok === "<Up>" ? -1 : 1);
            return true;
        }
        const c = commandCursor, n = commandLine.length;
        if (["<Left>", "<Right>", "<Home>", "<End>", "<C-b>", "<C-e>"].includes(tok)) {
            commandCursor = tok === "<Left>" ? Math.max(1, c - 1)
                : tok === "<Right>" ? Math.min(n, c + 1)
                : tok === "<Home>" || tok === "<C-b>" ? 1 : n;
            return true;
        }
        historyIndex = -1;
        if (tok === "<Esc>" || tok === "<C-c>") {
            commandLine = "";
        } else if (tok === "<CR>") {
            const line = commandLine;
            if (searchTarget >= 0)
                searchView = null; // keep the view on the match
            commandLine = "";
            addToHistory(line);
            runCommandLine(line);
        } else if (tok === "<BS>") {
            if (n === 1)
                commandLine = ""; // backspace on an empty line leaves it
            else if (c > 1)
                editCommandLine(c - 1, c, "");
        } else if (tok === "<Del>") {
            if (c < n)
                editCommandLine(c, c + 1, "");
        } else if (tok === "<C-u>" || tok === "<D-BS>") {
            editCommandLine(1, c, "");
        } else if (tok === "<C-w>") {
            let s = c;
            while (s > 1 && Txt.isBlank(commandLine[s - 1]))
                s--;
            const cls = Txt.charClass(commandLine[s - 1], false);
            while (s > 1 && !Txt.isBlank(commandLine[s - 1]) && Txt.charClass(commandLine[s - 1], false) === cls)
                s--;
            editCommandLine(s, c, "");
        } else if (tok === "<Tab>") {
            editCommandLine(c, c, "\t");
        } else if (tok !== null && !isSpecial(tok)) {
            editCommandLine(c, c, tok);
        }
        return true;
    }

    function historyList(kind) {
        return history[kind === ":" ? ":" : "/"];
    }

    function addToHistory(line) {
        const body = line.slice(1);
        if (!body)
            return;
        const list = historyList(line[0]);
        const i = list.indexOf(body);
        if (i >= 0)
            list.splice(i, 1);
        list.push(body);
        if (list.length > 200)
            list.shift();
    }

    // Steps to the previous (-1) or next (1) entry that starts with what was
    // typed before browsing; stepping past the newest restores the typed text.
    function browseHistory(step) {
        const kind = commandLine[0];
        const list = historyList(kind);
        if (historyIndex < 0) {
            historyTyped = commandLine.slice(1);
            historyIndex = list.length;
        }
        let i = historyIndex + step;
        while (i >= 0 && i < list.length && !list[i].startsWith(historyTyped))
            i += step;
        if (i < 0)
            return;
        historyIndex = Math.min(i, list.length);
        const text = kind + (i >= list.length ? historyTyped : list[i]);
        commandCursor = text.length;
        commandLine = text;
    }

    // Where k and j (Up and Down) go in lineHistory, where there's one: a
    // step back (-1) or on (1). 0 elsewhere, and for other keys.
    function lineStep(tok) {
        return singleLine && lineHistory ? ({ "k": -1, "<Up>": -1, "j": 1, "<Down>": 1 })[tok] || 0 : 0;
    }

    // Puts the entry of lineHistory `count` steps before (-1) or after (1)
    // the one shown in the line, with the cursor at its end, as a change of
    // its own. Entries that are what the line was before are skipped, as
    // they'd change nothing, and after the newest it's that again. False if
    // there's nothing there.
    function browseLines(step, count) {
        const list = lineHistory, t = bufferText();
        const b = lineBrowse && lineBrowse.shown === t ? lineBrowse : { index: list.length, typed: t };
        let i = b.index;
        for (let n = 0; n < count; n++) {
            let j = i + step;
            while (j >= 0 && j < list.length && list[j] === b.typed)
                j += step;
            if (j < 0 || j > list.length)
                break;
            i = j;
        }
        if (i === b.index)
            return false;
        const text = i < list.length ? list[i] : b.typed;
        clearCursors();
        commitChange();
        beginChange();
        replaceRange(0, t.length, text);
        commitChange();
        if (inserting)
            beginChange();
        lineBrowse = { index: i, typed: b.typed, shown: text };
        setCursor(inserting ? text.length : clampNormal(text, text.length));
        wantCol = Txt.column(text, cursor);
        return true;
    }

    function feed(tok) {
        if (recording && tok === "q" && keys.length === 0) {
            stopRecording();
            return;
        }
        keys.push(tok);
        const r = parse(keys, isVisual);
        if (r.status === "more") {
            pendingKeys = keys.join("");
            awaitingReplaceChar = tok === "r" && keys[keys.length - 2] !== "\"";
            return;
        }
        keys = [];
        pendingKeys = "";
        awaitingReplaceChar = false;
        if (r.status === "ok")
            execute(r.cmd);
        else
            typeahead = [];
    }

    // ---- Parsing -----------------------------------------------------------

    // Parses a key sequence into a command:
    //   ["x] [count] operator [count] (motion | text object | operator again)
    //   ["x] [count] (motion | action)
    // Returns { status: "more" | "bad" | "ok", cmd }.
    function parse(keys, visual) {
        const more = { status: "more" }, bad = { status: "bad" };
        const cmd = { reg: null, count: 0 };
        let i = 0;
        if (keys[0] === "\"") {
            if (keys.length < 2)
                return more;
            if (!/^[a-zA-Z0-9"+*_\-.:\/%]$/.test(keys[1]))
                return bad;
            cmd.reg = keys[1];
            i = 2;
        }
        const c1 = readCount(keys, i);
        cmd.count = c1.count;
        i = c1.next;
        if (!visual && i < keys.length) {
            const c = commandFor(keys.slice(i));
            if (c && c.name) {
                cmd.command = c.name;
                return { status: "ok", cmd };
            }
            if (c)
                return more;
            // Keys that started one, then went on differently, are bad
            // (Space l), unless they went on as a name of vim's (gg, where
            // g. is one).
            let started = 0;
            while (commandFor(keys.slice(i, i + started + 1)))
                started++;
            if (started && readName(keys, i).next - i <= started)
                return bad;
        }
        const w = readName(keys, i);
        if (!w)
            return more;

        if (operators.includes(w.name)) {
            if (visual) {
                cmd.action = w.name;
                return { status: "ok", cmd };
            }
            cmd.op = w.name;
            const c2 = readCount(keys, w.next);
            if (c2.count)
                cmd.count = Math.max(cmd.count, 1) * c2.count;
            const j = c2.next;
            if (j >= keys.length)
                return more;
            const k = keys[j];
            const last = cmd.op[cmd.op.length - 1];
            if (k === last) {
                cmd.linewise = true;
                return { status: "ok", cmd };
            }
            if (cmd.op.length === 2 && k === "g") {
                if (j + 1 >= keys.length)
                    return more;
                if (keys[j + 1] === last) {
                    cmd.linewise = true;
                    return { status: "ok", cmd };
                }
            }
            if (k === "i" || k === "a") {
                if (j + 1 >= keys.length)
                    return more;
                if (!textObjects.includes(keys[j + 1]))
                    return bad;
                cmd.textObj = { around: k === "a", ch: keys[j + 1] };
                return { status: "ok", cmd };
            }
            const m = parseMotion(keys, j);
            if (m.status !== "ok")
                return m;
            cmd.motion = m.motion;
            return { status: "ok", cmd };
        }

        if (visual && (w.name === "i" || w.name === "a")) {
            if (w.next >= keys.length)
                return more;
            if (!textObjects.includes(keys[w.next]))
                return bad;
            cmd.textObj = { around: w.name === "a", ch: keys[w.next] };
            return { status: "ok", cmd };
        }

        const m = parseMotion(keys, i);
        if (m.status === "more")
            return more;
        if (m.status === "ok") {
            cmd.motion = m.motion;
            return { status: "ok", cmd };
        }
        if (!(visual ? visualActions : normalActions).includes(w.name))
            return bad;
        cmd.action = w.name;
        if (w.name === "r") {
            if (w.next >= keys.length)
                return more;
            const ch = charArg(keys[w.next], true);
            if (ch === null)
                return bad;
            cmd.ch = ch;
        } else if (w.name === "q" || w.name === "@") {
            // The register to record into, or to run. A plain "q" stops a
            // recording (see feed).
            if (w.name === "q" && recording)
                return bad;
            if (w.next >= keys.length)
                return more;
            if (!(w.name === "q" ? /^[0-9a-zA-Z"]$/ : /^[0-9a-zA-Z"+*:@-]$/).test(keys[w.next]))
                return bad;
            cmd.ch = keys[w.next];
        }
        return { status: "ok", cmd };
    }

    // The command of commandKeys that `keys` type, as { name }, where name
    // is "" while they're only the start of its keys. Null if none.
    function commandFor(keys) {
        for (const k in commandKeys) {
            const ks = macroKeys(k);
            if (keys.length <= ks.length && keys.every((t, j) => t === ks[j]))
                return { name: keys.length === ks.length ? commandKeys[k] : "" };
        }
        return null;
    }

    function parseMotion(keys, i) {
        const w = readName(keys, i);
        if (!w)
            return { status: "more" };
        if (["f", "F", "t", "T"].includes(w.name)) {
            if (w.next >= keys.length)
                return { status: "more" };
            const ch = charArg(keys[w.next], false);
            if (ch === null)
                return { status: "bad" };
            return { status: "ok", motion: { name: w.name, ch } };
        }
        if (motions.includes(w.name))
            return { status: "ok", motion: { name: w.name } };
        return { status: "bad" };
    }

    // A command name: one key, or two for the g, z and Z prefixes.
    function readName(keys, i) {
        if (i >= keys.length)
            return null;
        const k = keys[i];
        if (k === "g" || k === "z" || k === "Z") {
            if (i + 1 >= keys.length)
                return null;
            return { name: k + keys[i + 1], next: i + 2 };
        }
        return { name: k, next: i + 1 };
    }

    function readCount(keys, i) {
        let s = "";
        while (i < keys.length && /^[0-9]$/.test(keys[i]) && !(s === "" && keys[i] === "0"))
            s += keys[i++];
        return { count: s ? parseInt(s, 10) : 0, next: i };
    }

    function charArg(tok, allowNewline) {
        if (tok === "<Tab>")
            return "\t";
        if (tok === "<CR>" || tok === "<S-CR>")
            return allowNewline ? "\n" : null;
        return isSpecial(tok) ? null : tok;
    }

    // ---- Execution ---------------------------------------------------------

    function isChange(cmd) {
        if (isVisual)
            return !cmd.motion && !cmd.textObj
                && !["<Esc>", "v", "V", "<C-v>", "o", "O", ":", "/", "?", "y", "Y", "q"].includes(cmd.action);
        return cmd.op ? cmd.op !== "y" : changeActions.includes(cmd.action);
    }

    function execute(cmd) {
        if (cmd.command) {
            outside(() => keyCommand(cmd.command, cmd.count));
            return;
        }
        // ". ": "/ and "% can only be pasted.
        if (readOnlyRegisters.includes(cmd.reg) && (cmd.op || writingActions.includes(cmd.action)
                || isVisual && cmd.action === "R")) {
            typeahead = [];
            return;
        }
        const changing = isChange(cmd);
        if (changing) {
            beginChange();
            if (!isVisual && !replaying)
                dot = { cmd: Object.assign({}, cmd), insertKeys: [] };
        }
        if (isVisual)
            executeVisual(cmd);
        else if (cmd.op && cursors.length)
            atEveryCursor(() => executeOperator(cmd));
        else if (cmd.op)
            executeOperator(cmd);
        else if (cmd.motion && lineStep(cmd.motion.name)) {
            if (!browseLines(lineStep(cmd.motion.name), Math.max(cmd.count, 1)))
                typeahead = []; // as a motion that fails
        } else if (cmd.motion)
            moveBy(cmd); // moves the extra cursors itself
        else if (cursors.length && everyCursorActions.includes(cmd.action))
            atEveryCursor(() => executeAction(cmd));
        else
            executeAction(cmd);
        // What the status line calls the insert's repeat (see repeatInsert).
        if (insertSession && insertSession.count > 1)
            insertSession.label = insertSession.count + cmd.action;
        if (changing && !inserting)
            commitChange();
    }

    function moveBy(cmd) {
        const t = bufferText();
        const count = Math.max(cmd.count, 1);
        const r = motion(t, cursor, cmd.motion, count, cmd.count > 0, false);
        if (r) {
            let p = r.pos;
            if (isVisual)
                p = r.eol ? Math.min(p, t.length) : clampNormal(t, p);
            else
                p = clampNormal(t, p);
            if (!r.keepCol)
                wantCol = r.eol ? Infinity : Txt.column(t, p);
            setCursor(p);
        } else {
            typeahead = [];
        }
        if (cursors.length && mode === "normal")
            moveCursors(t, cmd.motion, count, cmd.count > 0);
    }

    // Moves the extra cursors as the main one moved. Each keeps its own
    // column for j and k (`col`, like wantCol).
    function moveCursors(t, m, count, explicit) {
        // "*" and "#" search for the main cursor's word, which is now the
        // last search, from every cursor.
        if (m.name === "*" || m.name === "#")
            m = { name: "n" };
        const mainCol = wantCol;
        setCursors(cursors.map(c => {
            wantCol = c.col === undefined ? Txt.column(t, c.pos) : c.col;
            const r = motion(t, c.pos, m, count, explicit, false, true);
            if (!r)
                return Object.assign({}, c, { col: wantCol });
            const p = clampNormal(t, r.pos);
            return Object.assign({}, c, { pos: p, col: r.keepCol ? wantCol : r.eol ? Infinity : Txt.column(t, p) });
        }));
        wantCol = mainCol;
    }

    function executeOperator(cmd) {
        const t = bufferText();
        const n = t.length;
        const count = Math.max(cmd.count, 1);
        if (cmd.op === "d" && cmd.motion && ["h", "<Left>", "<BS>"].includes(cmd.motion.name)) {
            // dh and X at a name's start clear its line's icon (the ID
            // goes), as Backspace does there (see typedEdit), and leave the
            // registers alone like it. They don't join the line to the one
            // above, as vim's don't at a line's start: with no icon, h fails.
            const ls = Txt.lineStart(t, cursor), pe = prefixEnd(t, ls);
            if (cursor > ls && cursor === pe && t.slice(ls, pe) !== blankPrefix) {
                replaceRange(ls, pe, blankPrefix);
                setCursor(clampNormal(bufferText(), ls + blankPrefix.length));
                return;
            }
        }
        let range, target = cursor;
        if (cmd.linewise) {
            let le = Txt.lineEnd(t, cursor);
            for (let i = 1; i < count && le < n; i++)
                le = Txt.lineEnd(t, le + 1);
            range = { start: Txt.lineStart(t, cursor), end: Math.min(le + 1, n), linewise: true };
        } else if (cmd.textObj) {
            range = textObject(t, cursor, cmd.textObj, count);
            if (!range) {
                typeahead = [];
                return;
            }
            target = range.start;
        } else {
            let r;
            // "cw" on a word changes to the end of the word, like "ce", but
            // stays on the current word when the cursor is at its last letter.
            if (cmd.op === "c" && (cmd.motion.name === "w" || cmd.motion.name === "W")
                    && Txt.charClass(t[cursor], false) !== 0) {
                const big = cmd.motion.name === "W";
                const last = Txt.charClass(t[Txt.charEnd(t, cursor)], big) !== Txt.charClass(t[cursor], big);
                const end = steps(cursor, last ? count - 1 : count, q => wordStep(t, q, q => Txt.wordEnd(t, q, big)));
                r = { pos: end, type: "inclusive" };
            } else {
                r = motion(t, cursor, cmd.motion, count, cmd.count > 0, true);
            }
            if (!r) {
                typeahead = [];
                return;
            }
            target = r.pos;
            const a = Math.min(cursor, r.pos), b = Math.max(cursor, r.pos);
            if (r.type === "linewise")
                range = { start: Txt.lineStart(t, a), end: Math.min(Txt.lineEnd(t, b) + 1, n), linewise: true };
            else
                range = { start: a, end: r.type === "inclusive" ? Txt.charEnd(t, b) : Math.min(b, n), linewise: false };
            // Deleting with these always fills "1, even within a line, as in Vi.
            range.regOne = ["%", "n", "N", "{", "}"].includes(cmd.motion.name);
        }
        applyOperator(cmd.op, range, cmd.reg, count,
            range.linewise ? Math.min(cursor, target) : range.start);
    }

    function applyOperator(op, range, reg, count, yankCursor) {
        const t = bufferText();
        if (!range.linewise && range.end <= range.start && op !== "c")
            return;
        const lines = range.linewise ? Txt.spannedLines(t.slice(range.start, range.end)) : 0;
        switch (op) {
        case "y":
            yank(t, range, reg);
            if (lines > 2)
                showMessage(lines + " lines yanked");
            setCursor(clampNormal(t, yankCursor));
            break;
        case "d":
            deleteRange(t, range, reg);
            if (lines > 2)
                showMessage(lines + " fewer lines");
            break;
        case "c": {
            yank(t, range, reg, true);
            let s = range.start, e = range.end;
            if (range.linewise) {
                if (e > s && t[e - 1] === "\n")
                    e--; // keep an empty line to type on
                s = Math.min(prefixEnd(t, s), e); // and its prefix, icon and all
            }
            replaceRange(s, e, "");
            startInsert(1, s, null);
            break;
        }
        case ">":
        case "<":
            shiftLines(range, op === ">" ? 1 : -1, 1);
            break;
        default: // g~, gu, gU
            changeCase(range, op[1]);
            break;
        }
    }

    function executeAction(cmd) {
        const t = bufferText();
        const count = Math.max(cmd.count, 1);
        const p = cursor;
        switch (cmd.action) {
        case "i":
            startInsert(count, p, null);
            break;
        case "a":
            startInsert(count, p < Txt.lineEnd(t, p) ? Txt.charEnd(t, p) : p, null);
            break;
        case "I":
            startInsert(count, firstNonBlank(t, p), null);
            break;
        case "gI":
            startInsert(count, prefixEnd(t, Txt.lineStart(t, p)), null);
            break;
        case "A":
            startInsert(count, Txt.lineEnd(t, p), null);
            break;
        case "o": {
            const le = Txt.lineEnd(t, p);
            replaceRange(le, le, lineBreak);
            startInsert(count, le + lineBreak.length, "o");
            break;
        }
        case "O": {
            const ls = Txt.lineStart(t, p);
            replaceRange(ls, ls, blankPrefix + "\n");
            startInsert(count, ls + blankPrefix.length, "O");
            break;
        }
        case "v":
        case "V":
        case "<C-v>":
            anchor = p;
            setMode(visualModes[cmd.action]);
            setCursor(p);
            break;
        case "x":
        case "<Del>":
            executeOperator({ op: "d", reg: cmd.reg, count: cmd.count, motion: { name: "l" } });
            break;
        case "X":
            executeOperator({ op: "d", reg: cmd.reg, count: cmd.count, motion: { name: "h" } });
            break;
        case "s":
            applyOperator("c", { start: p, end: Txt.advance(t, p, count, Txt.lineEnd(t, p)), linewise: false }, cmd.reg);
            break;
        case "S":
            executeOperator({ op: "c", reg: cmd.reg, count: cmd.count, linewise: true });
            break;
        case "C":
            executeOperator({ op: "c", reg: cmd.reg, count: cmd.count, motion: { name: "$" } });
            break;
        case "D":
            executeOperator({ op: "d", reg: cmd.reg, count: cmd.count, motion: { name: "$" } });
            break;
        case "Y":
            executeOperator({ op: "y", reg: cmd.reg, count: cmd.count, linewise: true });
            break;
        case "p":
        case "P":
            paste(cmd.reg, cmd.action === "p", count);
            break;
        case "J":
        case "gJ":
            joinLines(count, cmd.action === "J");
            break;
        case "u":
            undo(count);
            break;
        case "<C-r>":
            redo(count);
            break;
        case ".":
            repeatDot(cmd.count);
            break;
        case "~": {
            const e = Txt.advance(t, p, count, Txt.lineEnd(t, p));
            if (e > p) {
                const text = Txt.toggleCase(t.slice(p, e));
                replaceRange(p, e, text, carriedHidden(p, e, text));
                setCursor(clampNormal(bufferText(), e));
            }
            break;
        }
        case "r": {
            const le = Txt.lineEnd(t, p);
            let e = p, k = 0;
            for (; k < count && e < le; k++)
                e = Txt.charEnd(t, e);
            if (k < count)
                break;
            if (cmd.ch === "\n") {
                replaceRange(p, e, lineBreak);
                setCursor(p + lineBreak.length);
            } else {
                replaceRange(p, e, cmd.ch.repeat(count));
                setCursor(p + cmd.ch.length * (count - 1));
            }
            break;
        }
        case "R":
            setMode("replace");
            setCursor(prefixEmptyLine(p));
            replaceStack = [];
            insertSession = { count: count, keys: [], openLine: null, dot: replaying ? null : dot, broken: false };
            break;
        case ":":
        case "/":
        case "?":
            openCommandLine(cmd.action);
            break;
        case "ZZ":
            outside(() => writeRequested(true, true));
            break;
        case "ZQ":
            outside(() => quitRequested(true, false, false));
            break;
        case "zz":
        case "zt":
        case "zb":
            scrollToCursor(cmd.action[1]);
            break;
        case "<C-e>":
        case "<C-y>":
            scrollText(cmd.action === "<C-e>" ? count : -count);
            break;
        case "<Esc>":
            highlightPattern = "";
            cursors = [];
            highlightsCleared();
            break;
        case "gv":
            if (lastVisual) {
                anchor = Math.min(lastVisual.anchor, t.length);
                setMode(lastVisual.mode);
                setCursor(Math.min(lastVisual.cursor, t.length));
            }
            break;
        case "gh":
            outside(() => hoverRequested(p));
            break;
        case "<C-a>":
        case "<C-x>":
            addToNumber(cmd.action === "<C-a>" ? count : -count);
            break;
        case "q":
            startRecording(cmd.ch);
            break;
        case "@":
            runMacro(cmd.ch, count);
            break;
        }
    }

    function executeVisual(cmd) {
        const t = bufferText();
        const n = t.length;
        const count = Math.max(cmd.count, 1);
        if (cmd.motion) {
            moveBy(cmd);
            return;
        }
        if (cmd.textObj) {
            const r = textObject(t, cursor, cmd.textObj, count);
            if (r && r.end > r.start) {
                anchor = r.start;
                setCursor(Txt.charStart(t, r.end - 1));
            }
            return;
        }
        const a = cmd.action;
        lastVisual = { mode: mode, anchor: anchor, cursor: cursor };
        if (a === "<Esc>" || visualModes[a] === mode) {
            setMode("normal");
            setCursor(clampNormal(t, cursor));
            return;
        }
        if (visualModes[a]) {
            setMode(visualModes[a]);
            setCursor(cursor);
            return;
        }
        if (a === "O" && mode === "visualBlock") {
            // To the other corner on the same line.
            const ca = Txt.column(t, anchor), cc = Txt.column(t, cursor);
            const la = Txt.lineStart(t, anchor), lc = Txt.lineStart(t, cursor);
            anchor = Txt.advance(t, la, cc, Txt.lineEnd(t, la));
            setCursor(Txt.advance(t, lc, ca, Txt.lineEnd(t, lc)));
            return;
        }
        if (a === "o" || a === "O") {
            const c = cursor;
            cursor = anchor;
            anchor = c;
            setCursor(cursor);
            return;
        }
        if (a === ":" || a === "/" || a === "?") {
            openCommandLine(a);
            return;
        }
        if (a === "q") {
            startRecording(cmd.ch);
            return;
        }
        if (a === "<C-e>" || a === "<C-y>") {
            scrollText(a === "<C-e>" ? count : -count);
            return;
        }
        if (mode === "visualBlock" && executeBlock(cmd))
            return;

        const lo = Math.min(anchor, cursor), hi = Math.max(anchor, cursor);
        const lineRange = { start: Txt.lineStart(t, lo), end: Math.min(Txt.lineEnd(t, hi) + 1, n), linewise: true };
        const range = mode === "visualLine" ? lineRange : { start: lo, end: Txt.charEnd(t, hi), linewise: false };
        setMode("normal");
        setCursor(clampNormal(t, lo));
        switch (a) {
        case "d":
        case "x":
        case "<Del>":
            applyOperator("d", range, cmd.reg);
            break;
        case "X":
        case "D":
            applyOperator("d", lineRange, cmd.reg);
            break;
        case "c":
        case "s":
            applyOperator("c", range, cmd.reg);
            break;
        case "C":
        case "S":
        case "R":
            applyOperator("c", lineRange, cmd.reg);
            break;
        case "y":
            applyOperator("y", range, cmd.reg, 0, lo);
            break;
        case "Y":
            applyOperator("y", lineRange, cmd.reg, 0, lo);
            break;
        case ">":
        case "<":
            shiftLines(range, a === ">" ? 1 : -1, count);
            break;
        case "~":
        case "g~":
            changeCase(range, "~");
            break;
        case "u":
        case "gu":
            changeCase(range, "u");
            break;
        case "U":
        case "gU":
            changeCase(range, "U");
            break;
        case "g?":
            changeCase(range, "?");
            break;
        case "r": {
            if (cmd.ch !== "\n") {
                // Line breaks and prefixes stay as they are.
                let s = "";
                for (let q = range.start; q < range.end; q = Txt.charEnd(t, q))
                    s += t[q] === "\n" || inPrefix(t, q) ? t.slice(q, Txt.charEnd(t, q)) : cmd.ch;
                replaceRange(range.start, range.end, s, carriedHidden(range.start, range.end, s));
            }
            setCursor(clampNormal(bufferText(), range.start));
            break;
        }
        case "J":
        case "gJ":
            joinLines(Txt.spannedLines(t.slice(lineRange.start, lineRange.end)), a === "J");
            break;
        case "I":
            startInsert(1, range.start, null);
            insertSession.dot = null;
            break;
        case "A":
            startInsert(1, range.linewise ? Txt.lineEnd(t, hi) : range.end, null);
            insertSession.dot = null;
            break;
        case "p":
        case "P": {
            const r = registerToPaste(cmd.reg);
            if (!r)
                break;
            let text = r.text, entries = r.hidden;
            if (r.linewise && !range.linewise) {
                text = "\n" + text;
                entries = shifted(entries, 1);
            } else if (!r.linewise && range.linewise) {
                text = text + "\n";
            }
            const removed = t.slice(range.start, range.end);
            const removedHidden = hiddenIn(hidden, range.start, range.end);
            const x = prefixLines(range.start, range.end, text, entries);
            replaceRange(range.start, range.end, x.text, x.entries);
            if (a === "p")
                setRegister(null, removed, range.linewise, false, removedHidden);
            const nt = bufferText();
            setCursor(clampNormal(nt, r.linewise
                ? firstNonBlank(nt, range.start + (range.linewise ? 0 : 1))
                : Txt.charStart(nt, range.start + x.text.length - 1)));
            break;
        }
        }
    }

    // ---- Insert and replace mode ------------------------------------------

    function startInsert(count, pos, openLine) {
        beginChange();
        setMode("insert");
        setCursor(prefixEmptyLine(pos));
        insertSession = { count: count, keys: [], openLine: openLine, dot: replaying ? null : dot, broken: false };
    }

    // In Koil's listing, puts a prefix on p's line if it's empty, to type
    // after (see Prefixes). Returns where p is then.
    function prefixEmptyLine(p) {
        const t = bufferText(), ls = Txt.lineStart(t, p);
        if (!linePrefixes || ls !== Txt.lineEnd(t, ls))
            return p;
        replaceRange(ls, ls, blankPrefix);
        return ls + blankPrefix.length;
    }

    // Moving around in insert mode ends the repeatable part of the insert and
    // starts a new undo step, like in vim.
    function breakInsert() {
        if (blockHome)
            blockHome.moved = true;
        const s = insertSession;
        if (s && !s.broken) {
            if (s.dot)
                s.dot.insertKeys = s.keys.slice();
            s.broken = true;
        }
        commitChange();
        beginChange();
    }

    // Types what the insert typed again for its count (unless the cursor
    // moved, or `repeat` is false), then goes back to normal mode. A long
    // repeat runs in chunks (see repeatInsert), and leaving insert mode
    // waits for it.
    function leaveInsert(repeat) {
        const s = insertSession;
        insertSession = null;
        if (s)
            lastInsert = insertedText(s.keys);
        if (s && !s.broken) {
            if (s.dot)
                s.dot.insertKeys = s.keys.slice();
            if (repeat !== false) {
                repeatInsert(s, endInsert);
                return;
            }
        }
        endInsert();
    }

    function endInsert() {
        replaceStack = [];
        // Back to one cursor. After a block insert it goes back to where the
        // insert started (unless the cursors moved), otherwise it steps back
        // onto what was typed, as in vim.
        const block = blockHome;
        clearCursors();
        const t = bufferText();
        const p = block && !block.moved ? Txt.lineToPos(t, block.line) + block.offset
            : cursor > Txt.lineStart(t, cursor) ? Txt.charStart(t, cursor - 1) : cursor;
        setMode("normal");
        commitChange();
        setCursor(clampNormal(t, p));
        wantCol = Txt.column(t, cursor);
    }

    // Types what the insert `s` typed count - 1 more times (3ix<Esc>), each
    // time on a new line for o and O, then calls done(). Text alone goes in
    // as one edit at each cursor rather than key by key, as each edit has
    // Qt and vim go over all the text (10000osome text<Esc> took about two
    // minutes). Keys that delete, Enter in the listing (which depends on
    // where it's typed, see typedEdit) and replace mode go key by key, as a
    // long command (see startTask): 10000ia<BS>b<Esc> took over a minute,
    // which nothing could stop.
    function repeatInsert(s, done) {
        const n = s.count - 1;
        const keyByKey = k => k === "<BS>" || k === "<Del>" || k === "<D-BS>" || linePrefixes && k === "<CR>";
        if (n > 0 && (mode !== "insert" || s.keys.some(keyByKey))) {
            let i = 0;
            startTask(s.label, n, () => {
                if (s.openLine) {
                    setCursor(editAll(q => {
                        const le = Txt.lineEnd(bufferText(), q);
                        replaceRange(le, le, lineBreak);
                        return le + lineBreak.length;
                    }));
                }
                for (const k of s.keys)
                    typeKey(k);
                return ++i < n;
            }, done);
            return;
        }
        if (n > 0) {
            const typed = s.keys.map(typedText).join("");
            const text = (s.openLine ? lineBreak + typed : typed).repeat(n);
            setCursor(editAll(q => {
                const at = s.openLine ? Txt.lineEnd(bufferText(), q) : q;
                replaceRange(at, at, text);
                return at + text.length;
            }));
        }
        done();
    }

    // The text the keys of an insert typed, with what its Backspaces took
    // back from it (not from the text before the insert) gone.
    function insertedText(keys) {
        let s = "";
        for (const k of keys) {
            if (k === "<BS>")
                s = s.slice(0, s ? Txt.charStart(s, s.length - 1) : 0);
            else if (k === "<D-BS>")
                s = s.slice(0, s.lastIndexOf("\n") + 1);
            else if (k === "<CR>" || k === "<Tab>" || !isSpecial(k))
                s += k === "<CR>" ? "\n" : typedText(k);
        }
        return s;
    }

    // The text an insert-mode key types (one that isn't <BS> or <Del>).
    function typedText(tok) {
        return tok === "<CR>" ? lineBreak : tok === "<Tab>" ? "\t" : tok;
    }

    // Types an insert-mode key at every cursor (for extra cursors, macros,
    // "." and counts; otherwise the editor does it).
    function typeKey(tok) {
        if (mode === "replace") {
            replaceKey(tok);
            return;
        }
        const edit = (t, p) => typedEdit(t, p, tok);
        if (cursors.length && editAtOnce(edit))
            return;
        setCursor(editAll(p => {
            const e = edit(bufferText(), p);
            if (!e)
                return p;
            replaceRange(e.start, e.end, e.text);
            return e.start + editCursor(e);
        }));
    }

    // What the insert-mode key `tok` does at p in t: replaces [start, end)
    // with text, and puts the cursor `cursor` characters after start (after
    // the text, if not given). Null if nothing. Cmd+Backspace deletes back
    // to the line's start, and there is Backspace. In Koil's listing (see
    // Prefixes), a line starts after its prefix; Backspace at a name's
    // start clears its line's icon, and on a line without one, joins it to
    // the line above; Delete at a line's end joins the next line without
    // its prefix; and Enter at a name's start puts the new line above, so
    // the name keeps its icon.
    function typedEdit(t, p, tok) {
        const ls = Txt.lineStart(t, p), pe = prefixEnd(t, ls);
        if (tok === "<D-BS>")
            return p > pe ? { start: pe, end: p, text: "" } : typedEdit(t, p, "<BS>");
        if (tok === "<BS>") {
            if (pe > ls && p === pe)
                return t.slice(ls, pe) !== blankPrefix ? { start: ls, end: pe, text: blankPrefix }
                    : ls > 0 ? { start: ls - 1, end: pe, text: "" } : null;
            return p > 0 ? { start: Txt.charStart(t, p - 1), end: p, text: "" } : null;
        }
        if (tok === "<Del>") {
            if (p < t.length && t[p] === "\n")
                return { start: p, end: prefixEnd(t, p + 1), text: "" };
            return p < t.length ? { start: p, end: Txt.charEnd(t, p), text: "" } : null;
        }
        if (tok === "<CR>" && pe > ls && p === pe && p < Txt.lineEnd(t, p))
            return { start: ls, end: ls, text: blankPrefix + "\n", cursor: blankPrefix.length + 1 + pe - ls };
        return { start: p, end: p, text: typedText(tok) };
    }

    // Where an edit (see typedEdit) puts the cursor, from its start.
    function editCursor(e) {
        return e.cursor === undefined ? e.text.length : e.cursor;
    }

    // Makes the edit `edit(text, pos)` gives (see typedEdit) at every
    // cursor, as one edit from the first to the last, and puts each cursor
    // where its edit says. One edit per cursor (editAll) has Qt and vim go
    // over all the text and hidden text each time, so with thousands of
    // cursors (a block insert in a long listing) typing a key took seconds.
    // Not for edits that overlap, or cursors over 1000 characters apart on
    // average, where the one edit would be long: returns whether it made it.
    function editAtOnce(edit) {
        const t = bufferText();
        const all = sortedBy([{ pos: cursor, main: true }].concat(cursors.filter(c => c.pos !== cursor))
            .map(c => ({ c: c, e: edit(t, c.pos) || { start: c.pos, end: c.pos, text: "" } })), x => x.e.start);
        for (let i = 1; i < all.length; i++) {
            if (all[i].e.start < all[i - 1].e.end)
                return false;
        }
        if (all[all.length - 1].e.end - all[0].e.start > 1000 * all.length)
            return false;
        // The cursors are placed below, so the edit needn't move them.
        shifting = [];
        const ends = replaceRanges(all.map(x => x.e));
        shifting = null;
        const placed = all.map((x, i) => Object.assign({}, x.c, { pos: ends[i] - x.e.text.length + editCursor(x.e) }));
        const main = placed.find(c => c.main);
        setCursors(placed.filter(c => c !== main), main.pos);
        setCursor(main.pos);
        showCursor();
        return true;
    }

    // Makes `edits` ({ start, end, text, entries }, in order and not
    // overlapping; `entries` are its text's, if any) as one replaceRange,
    // keeping the hidden text between them, and returns where each one's
    // text ends.
    function replaceRanges(edits) {
        const t = bufferText(), list = hidden, first = edits[0].start, last = edits[edits.length - 1].end;
        // The new text, with the entries of the icons it keeps (hidden is
        // sorted, so one pass finds them).
        const parts = [], entries = [], ends = [];
        let at = first, length = 0, k = firstAt(list, first);
        for (const e of edits) {
            for (; k < list.length && list[k].at < e.start; k++) {
                const h = list[k];
                if (h.at >= at && h.at + h.icon.length <= e.start)
                    entries.push({ at: h.at - at + length, icon: h.icon, text: h.text });
            }
            parts.push(t.slice(at, e.start), e.text);
            length += e.start - at;
            for (const h of e.entries || [])
                entries.push({ at: h.at + length, icon: h.icon, text: h.text });
            length += e.text.length;
            ends.push(first + length);
            at = e.end;
        }
        // The editor's cursor moves to the end of the new text, and the view
        // follows it: keep the view where it was.
        const view = flickable && { x: flickable.contentX, y: flickable.contentY };
        replaceRange(first, last, parts.join(""), entries);
        if (view) {
            flickable.contentX = view.x;
            flickable.contentY = view.y;
        }
        return ends;
    }

    // Types a replace-mode key at every cursor. Each cursor keeps what it
    // replaced (the main one in replaceStack), for Backspace to put back.
    function replaceKey(tok) {
        setCursor(editAll((p, c) => {
            if (!c.main && !c.replaceStack)
                c.replaceStack = [];
            return replaceAt(p, c.main ? replaceStack : c.replaceStack, tok);
        }));
    }

    // Each entry of `stack` is what a typed character replaced ({ text,
    // hidden }), null if it replaced nothing, or for a line break, { text:
    // "", hidden: [], typed }, with the length of what it typed.
    function replaceAt(p, stack, tok) {
        const t = bufferText();
        if (tok === "<BS>") {
            const q = Txt.charStart(t, p - 1);
            if (stack.length) {
                const orig = stack.pop();
                const from = orig && orig.typed ? p - orig.typed : q;
                replaceRange(from, p, orig ? orig.text : "", orig ? orig.hidden : []);
                return from;
            }
            return p > prefixEnd(t, Txt.lineStart(t, p)) ? q : p;
        }
        // A line break is inserted without replacing anything, with the new
        // line's prefix.
        if (tok === "<CR>") {
            stack.push({ text: "", hidden: [], typed: lineBreak.length });
            replaceRange(p, p, lineBreak);
            return p + lineBreak.length;
        }
        for (const ch of tok === "<Tab>" ? "\t" : tok) {
            const t = bufferText();
            if (ch !== "\n" && p < t.length && t[p] !== "\n") {
                const e = Txt.charEnd(t, p);
                stack.push({ text: t.slice(p, e), hidden: hiddenIn(hidden, p, e) });
                replaceRange(p, e, ch);
            } else {
                stack.push(null);
                replaceRange(p, p, ch);
            }
            p += ch.length;
        }
        return p;
    }

    function repeatDot(count) {
        if (!dot)
            return;
        const cmd = Object.assign({}, dot.cmd);
        if (count)
            cmd.count = count;
        replaying = true;
        execute(cmd);
        if (inserting && insertSession) {
            for (const k of dot.insertKeys) {
                insertSession.keys.push(k);
                typeKey(k);
            }
            leaveInsert();
        }
        replaying = false;
    }

    // ---- Completion --------------------------------------------------------
    // Where `completer` is set (Koil's path field), Tab while typing
    // completes what's before the cursor, like a shell: to the only option,
    // or else as far as all of them go alike. Once that adds nothing, it
    // shows them (`completion`, which Editor's CompletionList draws, like VS
    // Code's suggestions): Tab and Shift+Tab (Down and Up, Ctrl-N and
    // Ctrl-P) pick the next or previous one, Enter takes it, and Esc closes
    // them. Typing (and Backspace) narrows them, so a `/` shows that dir's.
    // Any other key closes them, then does what it does. A completion is
    // typed into the insert as Backspaces and its text, which "." and
    // counts repeat.

    // A key while typing, where Tab completes: Tab, or any key while the
    // options show. Returns whether it took the key.
    function completionKey(tok) {
        const c = completion;
        if (!c) {
            complete();
            return true;
        }
        const step = { "<Tab>": 1, "<Down>": 1, "<C-n>": 1, "<S-Tab>": -1, "<Up>": -1, "<C-p>": -1 }[tok];
        if (step) {
            const n = c.options.length;
            completion = Object.assign({}, c, { index: (c.index + step + n) % n });
            return true;
        }
        if (tok === "<CR>") {
            completeWith(c.start, c.options[c.index].name);
            return true;
        }
        // Like a lone modifier, which may start Ctrl-N.
        if (tok === null)
            return false;
        completion = null;
        if (tok === "<Esc>")
            return true;
        if (!isSpecial(tok) || tok === "<BS>") {
            insertKey(tok, null); // vim types it, so the options follow at once
            showCompletions(c.options[c.index].name);
            return true;
        }
        return false;
    }

    // Tab: fills in what it can, or else shows the options.
    function complete() {
        const r = completer(bufferText(), cursor);
        if (r.fill)
            completeWith(r.start, r.fill);
        else if (r.options.length)
            completion = { start: r.start, options: r.options, index: 0 };
    }

    // Shows the options for what's before the cursor (none if there are
    // none), with `picked` picked if it's one of them.
    function showCompletions(picked) {
        const r = completer(bufferText(), cursor);
        if (r.options.length)
            completion = { start: r.start, options: r.options, index: Math.max(0, r.options.findIndex(o => o.name === picked)) };
    }

    // Takes option i of the ones shown (a click).
    function takeCompletion(i) {
        interrupt();
        if (completion)
            batched(() => completeWith(completion.start, completion.options[i].name));
    }

    // Writes `text` in place of what's from `start` to the cursor, as if
    // typed. A dir's `/` steps over one right after the cursor, rather than
    // doubling it.
    function completeWith(start, text) {
        const t = bufferText(), s = insertSession, over = text.endsWith("/") && t[cursor] === "/";
        if (over)
            text = text.slice(0, -1);
        if (s && !s.broken) {
            for (let p = cursor; p > start; p = Txt.charStart(t, p - 1))
                s.keys.push("<BS>");
            for (const ch of text)
                s.keys.push(ch);
        }
        replaceRange(start, cursor, text);
        setCursor(start + text.length + (over ? 1 : 0));
    }

    // ---- Visual block ------------------------------------------------------
    // Columns count characters, as elsewhere. After "$" the block reaches the
    // end of every line.

    // The block's columns (right is Infinity after "$") and one entry per
    // line, top to bottom: { line, ls, le, start, end, cols }, where
    // [start, end) is the part in the block (empty if the line is too short)
    // and cols the line's length. Only the lines in [from, to], if given.
    function blockShape(t, from, to) {
        const ca = Txt.column(t, anchor), cc = Txt.column(t, cursor);
        const left = Math.min(ca, cc), right = wantCol === Infinity ? Infinity : Math.max(ca, cc);
        let ls = Txt.lineStart(t, Math.min(anchor, cursor));
        let last = Txt.lineStart(t, Math.max(anchor, cursor));
        if (from !== undefined) {
            ls = Math.max(ls, Txt.lineStart(t, from));
            last = Math.min(last, Txt.lineStart(t, to));
        }
        const lines = [];
        for (let line = Txt.lineOf(t, ls); ls <= last; line++) {
            const le = Txt.lineEnd(t, ls);
            const start = Txt.advance(t, ls, left, le);
            lines.push({ line: line, ls: ls, le: le, start: start,
                end: right === Infinity ? le : Txt.advance(t, start, right - left + 1, le), cols: Txt.column(t, le) });
            ls = le + 1;
        }
        return { left: left, right: right, lines: lines };
    }

    // The block as { start, end } spans, for drawing it: only its lines in
    // [from, to], as all of a 100,000-line block took a second a key.
    function blockSpans(from, to) {
        return blockShape(bufferText(), from, to).lines.filter(l => l.end > l.start).map(l => ({ start: l.start, end: l.end }));
    }

    // Runs a visual block command. Returns false for the ones that work on
    // whole lines, as in the other visual modes.
    function executeBlock(cmd) {
        const t = bufferText();
        const a = cmd.action;
        const b = blockShape(t);
        const lines = b.lines;
        if (["D", "C"].includes(a))
            for (const l of lines)
                l.end = l.le;
        // Lines that reach the block; the others are left alone.
        const reached = lines.filter(l => l.cols > b.left);
        const points = (reached.length ? reached : lines.slice(0, 1))
            .map(l => ({ line: l.line, offset: l.start - l.ls, pad: "" }));
        const home = () => {
            const nt = bufferText();
            const ls = Txt.lineToPos(nt, lines[0].line);
            setCursor(clampNormal(nt, Txt.advance(nt, ls, b.left, Txt.lineEnd(nt, ls))));
            wantCol = Txt.column(nt, cursor);
        };
        switch (a) {
        case "y":
        case "d":
        case "x":
        case "<Del>":
        case "D":
        case "c":
        case "s":
        case "C": {
            const r = blockText(t, lines);
            setRegister(cmd.reg, r.text, false, a === "y", r.entries, true);
            setMode("normal");
            if (a !== "y")
                deleteBlock(lines);
            if (["c", "s", "C"].includes(a))
                startBlockInsert(points);
            else
                home();
            return true;
        }
        case "I":
        case "A": {
            setMode("normal");
            if (a === "A") {
                const col = b.right + 1;
                points.length = 0;
                for (const l of lines) {
                    if (b.right === Infinity || l.cols < col)
                        points.push({ line: l.line, offset: l.le - l.ls,
                            pad: b.right === Infinity ? "" : " ".repeat(col - l.cols) });
                    else
                        points.push({ line: l.line, offset: Txt.advance(t, l.ls, col, l.le) - l.ls, pad: "" });
                }
            }
            startBlockInsert(points);
            return true;
        }
        case "~":
        case "u":
        case "U":
        case "g~":
        case "gu":
        case "gU":
        case "g?":
            setMode("normal");
            editBlock(lines, l => {
                const text = caseChanged(t.slice(l.start, l.end), a[a.length - 1]);
                return { start: l.start, end: l.end, text: text, entries: carriedHidden(l.start, l.end, text) };
            });
            home();
            return true;
        case "r":
            setMode("normal");
            if (cmd.ch !== "\n") {
                editBlock(lines, l => {
                    let s = "";
                    for (let q = l.start; q < l.end; q = Txt.charEnd(t, q))
                        s += cmd.ch;
                    return { start: l.start, end: l.end, text: s };
                });
            }
            home();
            return true;
        case "p":
        case "P": {
            const r = registerToPaste(cmd.reg);
            if (!r)
                return true;
            const removed = blockText(t, lines);
            setMode("normal");
            deleteBlock(lines);
            if (r.blockwise) {
                putBlock(r, lines[0].line, b.left, 1);
            } else if (!r.linewise && !r.text.includes("\n")) {
                // One line of text goes on every line of the block.
                const nt = bufferText();
                replaceRanges(points.map(q => {
                    const p = Txt.lineToPos(nt, q.line) + q.offset;
                    return { start: p, end: p, text: r.text, entries: r.hidden };
                }));
            } else {
                const nt = bufferText();
                setCursor(r.linewise ? Txt.lineToPos(nt, lines[lines.length - 1].line)
                    : Txt.lineToPos(nt, points[0].line) + points[0].offset);
                paste(cmd.reg, r.linewise, 1);
            }
            if (a === "p")
                setRegister(null, removed.text, false, false, removed.entries, true);
            if (!r.linewise)
                home();
            return true;
        }
        }
        return false;
    }

    // The text of a block's lines, one per line, with its hidden entries.
    function blockText(t, lines) {
        let text = "";
        const entries = [];
        lines.forEach((l, i) => {
            if (i > 0)
                text += "\n";
            for (const h of shifted(hiddenIn(hidden, l.start, l.end), text.length))
                entries.push(h);
            text += t.slice(l.start, l.end);
        });
        return { text: text, entries: entries };
    }

    function deleteBlock(lines) {
        editBlock(lines, l => ({ start: l.start, end: l.end, text: "" }));
    }

    // Makes the edits that `edit(l)` gives for the block's lines that have a
    // part in it, as one (one per line had a block of 4000 lines take
    // seconds).
    function editBlock(lines, edit) {
        const edits = lines.filter(l => l.end > l.start).map(edit);
        if (edits.length)
            replaceRanges(edits);
    }

    // Puts a blockwise register's lines at column `col` of line `line` and
    // the lines below it, adding lines at the end and padding short lines
    // with spaces where needed. As one edit, after the lines it adds.
    function putBlock(r, line, col, count) {
        const pieces = r.text.split("\n");
        const width = pieces.reduce((w, s) => Math.max(w, Txt.column(s, s.length)), 0);
        const missing = line + pieces.length - 1 - Txt.countLines(bufferText());
        if (missing > 0) {
            const n = bufferText().length;
            replaceRange(n, n, lineBreak.repeat(missing));
        }
        const t = bufferText(), edits = [];
        let from = 0;
        pieces.forEach((piece, i) => {
            const entries = hiddenIn(r.hidden, from, from + piece.length);
            from += piece.length + 1;
            const ls = Txt.lineToPos(t, line + i), le = Txt.lineEnd(t, ls);
            const cols = Txt.column(t, le);
            const at = Txt.advance(t, ls, col, le);
            const lead = " ".repeat(Math.max(0, col - cols));
            // Pad each copy to the block's width, unless nothing follows it.
            const padded = piece + " ".repeat(width - Txt.column(piece, piece.length));
            const body = lead + (at < le ? padded.repeat(count) : padded.repeat(count - 1) + piece);
            edits.push({ start: at, end: at, text: body,
                entries: shifted(repeated(entries, padded.length, count), lead.length) });
        });
        replaceRanges(edits);
    }

    // Starts insert mode with a cursor at each of `points` ({ line, offset,
    // pad }, top to bottom: offset is from the line's start, and the spaces
    // in pad are added there first, to line the cursors up), the first being
    // the main one.
    function startBlockInsert(points) {
        // The lines' starts, in one pass (the points are in order of their
        // lines; lineToPos goes over every line before), then the padding,
        // as one edit.
        const t = bufferText(), starts = [];
        let line = points[0].line, ls = Txt.lineToPos(t, line);
        for (const q of points) {
            for (; line < q.line; line++)
                ls = Txt.lineEnd(t, ls) + 1;
            starts.push(ls);
        }
        const pads = points.map((q, i) => ({ start: starts[i] + q.offset, end: starts[i] + q.offset, text: q.pad }));
        const at = pads.some(e => e.text) ? replaceRanges(pads) : pads.map(e => e.start);
        startInsert(1, at[0], null);
        insertSession.dot = null;
        setCursors(at.slice(1).map(p => ({ pos: p })));
        blockHome = { line: points[0].line, offset: points[0].offset + points[0].pad.length };
    }

    // ---- Multiple cursors --------------------------------------------------

    // Sets the extra cursors, sorted and without doubles or one at `main`
    // (the main cursor, unless given).
    function setCursors(list, main) {
        if (main === undefined)
            main = cursor;
        const sorted = sortedBy(list, c => c.pos);
        cursors = sorted.filter((c, i) => c.pos !== main && (i === 0 || c.pos !== sorted[i - 1].pos));
        if (cursors.length)
            trackedText = bufferText();
    }

    // `list` sorted by key(item), without changing it: itself if it already
    // is, as cursors almost always are (with a block insert's 100,000,
    // sorting them took a tenth of a second a key).
    function sortedBy(list, key) {
        for (let i = 1; i < list.length; i++) {
            if (key(list[i]) < key(list[i - 1]))
                return list.slice().sort((a, b) => key(a) - key(b));
        }
        return list;
    }

    // Alt+click: adds a cursor at pos, or removes the one there.
    function toggleCursor(pos) {
        interrupt();
        if (isVisual) {
            setMode("normal");
            setCursor(clampNormal(bufferText(), cursor));
        }
        if (mode !== "normal" && mode !== "insert")
            return;
        const t = bufferText();
        const p = mode === "normal" ? clampNormal(t, pos) : outOfPrefix(t, Math.min(pos, t.length));
        if (cursors.some(c => c.pos === p))
            setCursors(cursors.filter(c => c.pos !== p));
        else
            setCursors(cursors.concat([{ pos: p }]));
    }

    // Back to one cursor (a plain click, or leaving insert mode).
    function clearCursors() {
        cursors = [];
        blockHome = null;
    }

    // Runs fn(pos, c) at every cursor, the main one too, from the last to the
    // first, so that each edit moves only cursors that are done (see
    // shiftCursors). fn returns the cursor's new position. Updates the extra
    // cursors and returns the main one's position.
    function editAll(fn) {
        const main = { pos: cursor, main: true };
        const all = [main].concat(cursors.filter(c => c.pos !== cursor).map(c => Object.assign({}, c)));
        shifting = all;
        for (const c of all.slice().sort((a, b) => b.pos - a.pos))
            c.pos = fn(c.pos, c);
        shifting = null;
        setCursors(all.filter(c => c !== main), main.pos);
        return main.pos;
    }

    // Runs a normal-mode command (fn, which works at `cursor`) at every
    // cursor, like editAll. Each extra cursor has registers of its own (the
    // main ones at first), so "yyp" copies every cursor's own line.
    function atEveryCursor(fn) {
        const mainRegisters = registers, initial = Object.assign({}, registers);
        setCursor(editAll((p, c) => {
            if (!c.main)
                registers = c.registers || Object.assign({}, initial);
            setCursor(p);
            fn();
            if (!c.main) {
                c.registers = registers;
                registers = mainRegisters;
            }
            return cursor;
        }));
    }

    // Moves the extra cursors for an edit that replaced [start, end) with
    // `length` characters: the ones after it along, the ones in it to the
    // same offset in the new text if it's that long (so undo keeps them),
    // otherwise to its end.
    function shiftCursors(start, end, length) {
        const move = q => q >= end ? q + length - (end - start) : Math.min(q, start + length);
        if (shifting) {
            for (const c of shifting)
                c.pos = move(c.pos);
        } else if (cursors.length) {
            setCursors(cursors.map(c => Object.assign({}, c, { pos: move(c.pos) })), -1);
        }
    }

    // ---- Macros ------------------------------------------------------------
    // A register holds a macro as text, with keys like Esc written "<Esc>".
    // A recorded one also keeps its keys, so typed text like "<CR>" stays text.
    // Running one (@q) runs its keys (with the macros they run) in chunks
    // (see Runs).

    function startRecording(reg) {
        recording = reg;
        recordKeys = [];
    }

    function stopRecording() {
        const reg = recording.toLowerCase();
        let ks = recordKeys;
        if (!running)
            ks = ks.slice(0, -1); // the "q" that stopped it
        // "qA" appends to register a.
        const old = recording !== reg ? registers[reg] : null;
        if (old)
            ks = (old.keys || macroKeys(old.text)).concat(ks);
        registers[reg] = { text: ks.join(""), linewise: false, hidden: [], keys: ks };
        recording = "";
        recordKeys = [];
    }

    // Splits register text into keys.
    function macroKeys(text) {
        const named = { "\n": "<CR>", "\r": "<CR>", "\t": "<Tab>", "\x1b": "<Esc>" };
        const re = /<(?:Esc|CR|S-CR|BS|Del|Tab|S-Tab|Left|Right|Up|Down|Home|End|PageUp|PageDown|C-[a-z])>|[\s\S]/gu;
        return (text.match(re) || []).map(k => named[k] || k);
    }

    function runMacro(reg, count) {
        if (reg === "@") {
            if (!lastMacro) {
                showError("E748: No previously used register");
                return;
            }
            reg = lastMacro;
        }
        lastMacro = reg;
        if (reg === ":") {
            const list = history[":"];
            if (!list.length) {
                showError("E30: No previous command line");
                return;
            }
            const c = list[list.length - 1].trim();
            let n = 0;
            startTask((count > 1 ? count : "") + "@:", count, () => {
                runEx(c);
                return ++n < count;
            }, () => {});
            return;
        }
        const r = getRegister(reg);
        if (!r)
            return;
        const ks = r.keys || macroKeys(r.text);
        if (!ks.length)
            return;
        if (typeahead.length >= maxMacroDepth) {
            showError("E223: recursive mapping");
            return;
        }
        // A macro run from a macro goes before the rest of that one.
        const frame = { keys: ks, next: 0, runs: count };
        typeahead.push(frame);
        if (!running)
            startRun("@" + reg, frame, count);
    }

    // The next key of the macros running (see typeahead).
    function nextMacroKey() {
        const f = typeahead[typeahead.length - 1];
        const k = f.keys[f.next++];
        if (f.next === f.keys.length) {
            f.next = 0;
            // Gone before its last key runs, so a macro that runs itself
            // last (qa…@aq) doesn't stack up.
            if (--f.runs === 0)
                typeahead.pop();
        }
        return k;
    }

    // ---- Runs --------------------------------------------------------------
    // A macro (its keys, see typeahead) or a long command (its steps, see
    // startTask) runs in chunks (see runChunk), after each of which the
    // editor shows its edits, and the status line how far it is. Esc or
    // Ctrl-C stops it (see handleKey). A run is one undo step, as in vim.

    // Starts a run of `frame` (a macro's, run `runs` times) or `task`,
    // called `label` on the status line.
    function startRun(label, frame, runs) {
        running = { label: label, frame: frame, runs: runs };
        // Already, so the status line doesn't follow the cursor (see
        // main.qml), which in a long text takes a while each time.
        progress = label;
        nextDraw = 0; // shown after the first chunk
        runChunk();
    }

    // Runs a long command as calls to step(), each doing a part of it and
    // returning whether there's more, then finish() (also if it's stopped).
    // As a macro's keys, they run in chunks, and before a macro's next key,
    // if a macro runs it. `steps` is about how many there are, for the
    // progress. One that's done in the first chunk is done at once.
    function startTask(label, steps, step, finish) {
        task = { steps: steps, done: 0, step: step, finish: finish };
        if (!running)
            startRun(label, null, 0);
    }

    function stepTask() {
        const t = task;
        t.done++;
        if (!t.step()) {
            task = null;
            t.finish();
        }
    }

    // Runs the run's keys and steps for chunkTime ms, editing a copy of the
    // text (`batch`) rather than the editor, where each edit has Qt go over
    // all the text (10000@q with yyp<C-a> in q took minutes, without
    // returning to Qt to free the memory it took, which ran out). Then the
    // editor gets the chunk's edits as one, and the next chunk runs once Qt
    // has drawn it and handled the keys typed meanwhile.
    function runChunk() {
        if (!running)
            return;
        const start = Date.now();
        if (drawStart) {
            nextDraw = start + Math.max(drawEvery, 4 * (start - drawStart));
            drawStart = 0;
        }
        inChunk = true;
        // A key's batch, if the key started the run (see batched).
        const own = !batch;
        if (own)
            batch = newBatch();
        try {
            while (task || typeahead.length) {
                if (task)
                    stepTask();
                else
                    runKey(nextMacroKey(), null);
                if (Date.now() - start >= chunkTime)
                    break;
            }
        } catch (e) {
            // A bug: not the rest of it.
            typeahead = [];
            task = null;
            throw e;
        } finally {
            flush();
            if (own)
                batch = null;
            inChunk = false;
            if (task || typeahead.length) {
                progress = progressLabel();
                const now = Date.now(), draw = now >= nextDraw;
                if (draw)
                    drawStart = now;
                chunkTimer.interval = draw ? drawTime : 0;
                chunkTimer.start();
            } else {
                endRun();
            }
        }
    }

    // How far the run is, for the status line: "@q 34%", "5000u 34%", or
    // only "@q" once it's running a macro it ran last.
    function progressLabel() {
        const r = running, f = r.frame;
        if (!f)
            return task ? r.label + " " + Math.floor(100 * task.done / task.steps) + "%" : r.label;
        if (typeahead[0] !== f)
            return r.label;
        const done = (r.runs - f.runs) * f.keys.length + f.next;
        return r.label + " " + Math.floor(100 * done / (r.runs * f.keys.length)) + "%";
    }

    // The run ended: its keys and steps ran out, one failed, or it was
    // stopped.
    function endRun() {
        chunkTimer.stop();
        drawStart = 0;
        typeahead = [];
        if (task) {
            const t = task;
            task = null;
            t.finish();
        }
        running = null;
        progress = "";
        if (!inserting)
            commitChange();
    }

    // Also drops what a macro left half typed (a command, a command line).
    function stopRun() {
        endRun();
        if (commandLine !== "")
            commandLineKey("<Esc>");
        keys = [];
        pendingKeys = "";
        awaitingReplaceChar = false;
        showMessage("Interrupted");
    }

    // Called first by what changes the text or moves vim from outside (a
    // click, the find bar, main.qml): a run going on then, between its
    // chunks, would go on from somewhere else, so it stops.
    function interrupt() {
        if (running && !inChunk)
            stopRun();
    }

    // ---- Batches -----------------------------------------------------------
    // While a key or a chunk of a run runs, vim edits a copy of the text
    // (`batch`), and the editor gets the edits as one after it (flush): a
    // command that edits in many places (a block's lines, at many cursors)
    // made an edit each, and each has Qt go over all the text.

    // A batch of the editor as it is.
    function newBatch() {
        return { text: editor.text, cursor: cursor, anchor: anchor, mode: mode };
    }

    // Runs fn (a key) in a batch.
    function batched(fn) {
        if (batch)
            return fn();
        batch = newBatch();
        try {
            return fn();
        } finally {
            flush();
            batch = null;
        }
    }

    // Runs fn, which emits a signal main.qml handles by reading or changing
    // the editor, with the editor up to date.
    function outside(fn) {
        if (!batch) {
            fn();
            return;
        }
        flush();
        batch = null;
        try {
            fn();
        } finally {
            batch = newBatch();
        }
    }

    // Gives the editor the text vim edited in its place, as one edit, and
    // vim's mode and cursor (or selection), as setMode and setCursor would
    // have: the edit doesn't scroll (it moves the editor's cursor), but the
    // cursor does, as Qt does it, with room beside it (showColumn), and a
    // new mode as setMode does. So does an edit, which may have moved the
    // editor's cursor to where vim's goes, so that setting it there doesn't
    // scroll (deleting up to the text's start from below left the view on
    // what had been below). If none of them changed, the view stays where
    // it is, even if the mouse scrolled the cursor out of it.
    function flush() {
        const b = batch, old = editor.text, edited = b.text !== old;
        if (!edited && b.cursor === cursor && b.anchor === anchor && b.mode === mode)
            return;
        batch = null;
        const view = flickable && { x: flickable.contentX, y: flickable.contentY };
        // Where the view was, as far as the text still reaches: put back
        // past the end of a shorter text, it showed nothing.
        const restore = () => {
            if (view) {
                flickable.contentX = Math.min(view.x, Math.max(0, flickable.contentWidth - flickable.width));
                flickable.contentY = Math.min(view.y, Math.max(0, flickable.contentHeight - flickable.height));
            }
        };
        syncing = true;
        if (edited) {
            const d = diff(old, b.text, [], []);
            editing = true;
            if (d.end1 > d.start)
                editor.remove(d.start, d.end1);
            if (d.end2 > d.start)
                editor.insert(d.start, b.text.slice(d.start, d.end2));
            editing = false;
        }
        const newMode = b.mode !== mode;
        if (!newMode)
            restore();
        editor.readOnly = mode !== "insert";
        if (isVisual)
            updateSelection();
        else
            editor.cursorPosition = Math.min(cursor, editor.length);
        if (newMode)
            restore();
        if (newMode || edited)
            showCursor();
        else if (b.cursor !== cursor)
            showColumn();
        syncing = false;
        b.text = editor.text;
        b.cursor = cursor;
        b.anchor = anchor;
        b.mode = mode;
        if (hidden.length || cursors.length)
            trackedText = b.text;
        batch = b;
    }

    // ---- Editing primitives ----------------------------------------------

    // The text of the buffer vim edits: the editor's, or during a key or a
    // chunk of a run, the copy vim edits in its place (see Batches).
    function bufferText() {
        return batch ? batch.text : editor.text;
    }

    // `entries` are the hidden-text entries for `text`, if it has any.
    function replaceRange(start, end, text, entries) {
        // A space is as long as a line break, so positions stay right.
        if (singleLine)
            text = text.replace(new RegExp("[\\r\\n\\u2028\\u2029]", "g"), " ");
        if (batch) {
            const t = batch.text;
            batch.text = t.slice(0, start) + text + t.slice(end);
        } else {
            syncing = true;
            editing = true;
            if (end > start)
                editor.remove(start, end);
            if (text.length)
                editor.insert(start, text);
            editing = false;
            syncing = false;
        }
        if (hidden.length || entries && entries.length)
            shiftHidden(start, end, text.length, entries || []);
        shiftCursors(start, end, text.length);
        if (!batch && (hidden.length || cursors.length))
            trackedText = editor.text;
    }

    function setMode(m) {
        const wasVisual = isVisual;
        mode = m;
        if (batch)
            return; // the editor gets it after the chunk (see flush)
        syncing = true;
        // Changing readOnly makes the editor scroll to where the cursor used
        // to be, then setting the cursor puts its line at the top. Keep the
        // view instead, and only scroll if the cursor is out of it.
        const view = flickable && { x: flickable.contentX, y: flickable.contentY };
        // Read-only outside insert mode, so macOS doesn't turn held keys into
        // the accent picker and nothing but vim edits the text.
        editor.readOnly = m !== "insert";
        if (wasVisual && !isVisual)
            editor.deselect();
        if (!isVisual)
            editor.cursorPosition = Math.min(cursor, bufferText().length);
        if (view) {
            flickable.contentX = view.x;
            flickable.contentY = view.y;
            showCursor();
        }
        syncing = false;
    }

    // Never in a line's prefix (see Prefixes).
    function setCursor(p) {
        cursor = outOfPrefix(bufferText(), p);
        if (batch)
            return; // as setMode
        syncing = true;
        if (isVisual)
            updateSelection();
        else
            editor.cursorPosition = cursor;
        syncing = false;
        showColumn();
    }

    function updateSelection() {
        const t = bufferText();
        const n = t.length;
        if (mode === "visualBlock") {
            // The editor's selection can't be a block: the view draws it.
            editor.deselect();
            editor.cursorPosition = Math.min(cursor, n);
        } else if (mode === "visualLine") {
            const s = Txt.lineStart(t, Math.min(anchor, cursor));
            const e = Math.min(Txt.lineEnd(t, Math.max(anchor, cursor)) + 1, n);
            if (cursor >= anchor)
                editor.select(s, e);
            else
                editor.select(e, s);
        } else if (cursor >= anchor) {
            editor.select(anchor, Txt.charEnd(t, cursor));
        } else {
            editor.select(Txt.charEnd(t, anchor), cursor);
        }
    }

    // ---- Undo ------------------------------------------------------------
    // Each change (a normal-mode command, everything typed in one insert, or
    // a macro run) is stored as the span it replaced, found by diffing the
    // text around it.

    function beginChange() {
        if (!change)
            change = { before: bufferText(), hidden: hidden, cursor: cursor };
    }

    // During a run, its changes add up to one, which only ends with it,
    // unless `force` (to undo, or leave the buffer).
    function commitChange(force) {
        if (!change || running && !force)
            return;
        const before = change.before, after = bufferText();
        const c = change.cursor, bh = change.hidden;
        change = null;
        const d = diff(before, after, bh, hidden);
        if (!d)
            return;
        const s = d.start, e1 = d.end1, e2 = d.end2;
        undoStack.push({ start: s, removed: own(before.slice(s, e1)), inserted: own(after.slice(s, e2)),
            removedHidden: hiddenIn(bh, s, e1), insertedHidden: hiddenIn(hidden, s, e2), cursor: c });
        redoStack = [];
    }

    // s as a string of its own. V4 keeps the whole string a slice was cut
    // from until the slice is read (here by charCodeAt), so each undo step
    // and register kept a copy of all the text.
    function own(s) {
        s.charCodeAt(0);
        return s;
    }

    // u, `count` times, as a long command (see startTask): each step is an
    // edit, which can be anywhere.
    function undo(count) {
        commitChange(true);
        let last = null, n = 0;
        startTask((count > 1 ? count : "") + "u", count, () => {
            if (!undoStack.length)
                return false;
            last = undoStack.pop();
            replaceRange(last.start, last.start + last.inserted.length, last.removed, last.removedHidden);
            redoStack.push(last);
            return ++n < count && undoStack.length > 0;
        }, () => {
            if (!last) {
                showMessage("Already at oldest change");
                outside(() => nothingToUndo());
                return;
            }
            const p = Math.min(last.cursor, bufferText().length);
            setCursor(mode === "normal" ? clampNormal(bufferText(), p) : p);
        });
    }

    // Ctrl-R, as undo.
    function redo(count) {
        commitChange(true);
        let last = null, n = 0;
        startTask((count > 1 ? count : "") + "^R", count, () => {
            if (!redoStack.length)
                return false;
            last = redoStack.pop();
            replaceRange(last.start, last.start + last.removed.length, last.inserted, last.insertedHidden);
            undoStack.push(last);
            return ++n < count && redoStack.length > 0;
        }, () => {
            if (!last) {
                showMessage("Already at newest change");
                return;
            }
            // Land on an inserted line rather than the end of the line above it.
            const p = last.start + (last.inserted[0] === "\n" ? 1 : 0);
            setCursor(mode === "normal" ? clampNormal(bufferText(), p) : p);
        });
    }

    // ---- Registers -------------------------------------------------------

    // `entries` are the hidden-text entries for `text`, if it has any. A
    // blockwise register holds a visual block, one line of it per line.
    // With no name, a yank goes in "0, and a delete of lines (or with a
    // `regOne` motion) in "1, the older ones moving up to "9, else in "-.
    function setRegister(name, text, linewise, isYank, entries, blockwise, regOne) {
        if (name === "_" || readOnlyRegisters.includes(name))
            return;
        entries = entries || [];
        blockwise = !!blockwise;
        // The clipboard registers are separate: writing them leaves the
        // unnamed register (what plain "p" pastes) alone. Other apps get the
        // text as shown, icons and all; Koil gets the hidden texts back from
        // its own data.
        if (name === "+" || name === "*") {
            if (clipboard)
                clipboard.setClipboardText(text, entries.length || blockwise
                    ? JSON.stringify({ text: text, hidden: entries, block: blockwise, session: clipboardSession }) : "");
            return;
        }
        const entry = { text: own(text), linewise: linewise, hidden: entries, blockwise: blockwise };
        if (name && /^[A-Z]$/.test(name)) {
            const key = name.toLowerCase();
            const old = registers[key];
            if (old) {
                const sep = linewise && !old.linewise ? "\n" : "";
                entry.text = own(old.text + sep + text);
                entry.hidden = old.hidden.concat(shifted(entries, old.text.length + sep.length));
            }
            entry.linewise = linewise || (old && old.linewise);
            registers[key] = entry;
        } else if (name && name !== "\"") {
            registers[name] = entry;
        } else if (isYank) {
            registers["0"] = entry;
        } else {
            const small = !linewise && !text.includes("\n");
            if (!small || regOne) {
                for (let i = 9; i > 1; i--)
                    registers[i] = registers[i - 1];
                registers["1"] = entry;
            }
            if (small)
                registers["-"] = entry;
        }
        registers["\""] = entry;
    }

    function getRegister(name) {
        if (name === "+" || name === "*") {
            if (!clipboard)
                return null;
            try {
                const d = JSON.parse(clipboard.clipboardData() || "null");
                if (d && typeof d.text === "string" && validHidden(d.text, d.hidden))
                    return { text: d.text, linewise: !d.block && d.text.endsWith("\n"),
                        hidden: d.session === clipboardSession ? shifted(d.hidden, 0) : [], blockwise: !!d.block };
            } catch (e) {
                // not ours after all: use the text
            }
            const s = clipboard.clipboardText();
            return s ? { text: s, linewise: s.endsWith("\n"), hidden: [] } : null;
        }
        if (readOnlyRegisters.includes(name)) {
            const commands = history[":"];
            const s = name === "." ? lastInsert : name === "/" ? (lastSearch ? lastSearch.pattern : "")
                : name === ":" ? (commands.length ? commands[commands.length - 1] : "") : fileName;
            return s ? { text: s, linewise: false, hidden: [] } : null;
        }
        return registers[(name || "\"").toLowerCase()] || null;
    }

    // :reg lists the registers that hold something (those in `names`, if
    // it isn't blank), in vim's order, as rows of [type and name, text]:
    // ["l  \"0", "one^J"]. The type is c (characters), l (lines) or b (a
    // block), and control characters are written like ^J, so each is one
    // line (cut off, as a register can hold all of a long file).
    function registerList(names) {
        const all = "\"0123456789abcdefghijklmnopqrstuvwxyz-*+.:%/";
        const wanted = names.replace(/\s/g, "").toLowerCase();
        const rows = [];
        for (const name of all) {
            if (wanted && !wanted.includes(name))
                continue;
            const r = getRegister(name);
            if (!r || !r.text)
                continue;
            const max = 300, cut = r.text.length > max;
            const text = (cut ? r.text.slice(0, Txt.charStart(r.text, max)) : r.text).replace(/[\x00-\x1f\x7f]/g,
                ch => "^" + (ch === "\x7f" ? "?" : String.fromCharCode(ch.charCodeAt(0) + 64)));
            rows.push([(r.blockwise ? "b" : r.linewise ? "l" : "c") + "  \"" + name, cut ? text + "…" : text]);
        }
        return rows;
    }

    function showRegisters(names) {
        const rows = registerList(names);
        if (rows.length)
            registersRequested(rows);
        else
            showMessage(names.trim() ? "Nothing in those registers" : "Nothing in the registers");
    }

    // `deleting` for the text a change deletes.
    function yank(t, range, reg, deleting) {
        let text = t.slice(range.start, range.end);
        if (range.linewise && !text.endsWith("\n"))
            text += "\n";
        setRegister(reg, text, range.linewise, !deleting, hiddenIn(hidden, range.start, range.end), false,
            range.regOne);
    }

    function deleteRange(t, range, reg) {
        let s = range.start;
        let text = t.slice(s, range.end);
        if (range.linewise && !text.endsWith("\n")) {
            // Last line without a trailing newline: take the one before it.
            text += "\n";
            if (s > 0)
                s--;
        }
        setRegister(reg, text, range.linewise, false, hiddenIn(hidden, range.start, range.end), false,
            range.regOne);
        replaceRange(s, range.end, "");
        const nt = bufferText();
        if (range.linewise)
            setCursor(clampNormal(nt, firstNonBlank(nt, Math.min(s, nt.length))));
        else
            setCursor(clampNormal(nt, s));
    }

    function paste(reg, after, count) {
        const r = registerToPaste(reg);
        if (!r)
            return;
        const t = bufferText();
        const p = cursor;
        if (r.blockwise) {
            const line = Txt.lineOf(t, p);
            const col = Txt.column(t, p) + (after && p < Txt.lineEnd(t, p) ? 1 : 0);
            putBlock(r, line, col, count);
            const nt = bufferText();
            const ls = Txt.lineToPos(nt, line);
            setCursor(clampNormal(nt, Txt.advance(nt, ls, col, Txt.lineEnd(nt, ls))));
            return;
        }
        let entries = repeated(r.hidden, r.text.length, count);
        if (r.linewise) {
            let body = r.text.repeat(count);
            let at;
            if (!after) {
                at = Txt.lineStart(t, p);
            } else {
                const le = Txt.lineEnd(t, p);
                if (le < t.length) {
                    at = le + 1;
                } else {
                    at = t.length;
                    body = "\n" + body.slice(0, -1);
                    entries = shifted(entries, 1);
                }
            }
            const x = prefixLines(at, at, body, entries);
            replaceRange(at, at, x.text, x.entries);
            const nt = bufferText();
            setCursor(clampNormal(nt, firstNonBlank(nt, body[0] === "\n" ? at + 1 : at)));
        } else {
            const at = after && p < Txt.lineEnd(t, p) ? Txt.charEnd(t, p) : p;
            const x = prefixLines(at, at, r.text.repeat(count), entries);
            replaceRange(at, at, x.text, x.entries);
            setCursor(clampNormal(bufferText(), at + Math.max(x.text.length - 1, 0)));
        }
    }

    // Cmd+V in insert mode: pastes `r` at every cursor, or in Koil's
    // listing, lines with an entry's icon (see pastesLines) above the
    // cursor's line, as a copied line pastes in VS Code.
    function insertPaste(r) {
        if (pastesLines(r)) {
            const text = r.text.endsWith("\n") ? r.text : r.text + "\n";
            setCursor(editAll(p => {
                const ls = Txt.lineStart(bufferText(), p);
                const x = prefixLines(ls, ls, text, r.hidden);
                replaceRange(ls, ls, x.text, x.entries);
                return p + x.text.length;
            }));
            return;
        }
        const s = editor.selectionStart, e = editor.selectionEnd;
        const put = (from, to) => {
            const x = prefixLines(from, to, r.text, r.hidden);
            replaceRange(from, to, x.text, x.entries);
            return from + x.text.length;
        };
        setCursor(cursors.length ? editAll(p => put(p, p)) : put(s, e));
    }

    // Register `reg` (see getRegister) as it pastes: in Koil's listing,
    // text that starts with an entry's icon pastes as lines.
    function registerToPaste(reg) {
        const r = getRegister(reg);
        if (!r || r.linewise || !pastesLines(r))
            return r;
        return { text: r.text.endsWith("\n") ? r.text : r.text + "\n", linewise: true, hidden: r.hidden, blockwise: false };
    }

    // Whether register `r` starts with a prefix that has an icon (an ID's,
    // or a Nerd Font one), in Koil's listing: its icon goes first on a
    // line, so it pastes as lines.
    function pastesLines(r) {
        return linePrefixes && !r.blockwise && r.text[0] !== " "
            && prefixLength(r.text, 0, q => r.hidden.some(h => h.at === q)) > 0;
    }

    // ---- Hidden text -------------------------------------------------------
    // An icon (one character, like a file's icon in Koil's listing, whose ID
    // it hides) can hide some text: the document holds the plain icon, and
    // the text is kept beside it in `hidden`, a list of { at, icon, text }
    // sorted by position. Only the text the editor is given has them (see
    // reset and replaceText); the user can't make new ones, and an icon
    // without an entry is a plain character. Every edit shifts the list:
    // vim's own in replaceRange, the editor's (typing in insert mode) by
    // diffing the text. Registers, undo steps and the clipboard carry the
    // entries for the text they hold (with `at` from its start), so an icon
    // yanks, pastes and undoes like any character. Files get the plain icon.

    // Replaced, never changed in place, so a copy of the reference is a snapshot.
    property var hidden: []
    // The text `hidden` and `cursors` match, to diff the editor's own edits
    // against.
    property string trackedText: ""
    property bool editing: false
    readonly property Connections editorEdits: Connections {
        target: vim.editor

        function onTextChanged() {
            vim.trackEdit();
        }
    }

    // The entries of `list` whose icon is in [start, end), from start.
    function hiddenIn(list, start, end) {
        const r = [];
        for (let i = firstAt(list, start); i < list.length && list[i].at < end; i++) {
            const h = list[i];
            if (h.at + h.icon.length <= end)
                r.push({ at: h.at - start, icon: h.icon, text: h.text });
        }
        return r;
    }

    // The index of the first entry of `list` at p or after it (or its
    // length). Entries are sorted, so with thousands of them (a long
    // listing) edits look them up rather than going over them all.
    function firstAt(list, p) {
        let lo = 0, hi = list.length;
        while (lo < hi) {
            const mid = (lo + hi) >> 1;
            if (list[mid].at < p)
                lo = mid + 1;
            else
                hi = mid;
        }
        return lo;
    }

    function shifted(list, by) {
        return list.map(h => ({ at: h.at + by, icon: h.icon, text: h.text }));
    }

    // `list` for text repeated `count` times. Pushed, not concatenated,
    // which copies all of it each time (8000p of a listing line took a
    // second).
    function repeated(list, length, count) {
        const r = [];
        for (let i = 0; i < count; i++) {
            for (const h of shifted(list, i * length))
                r.push(h);
        }
        return r;
    }

    // Whether two entries hide the same text behind the same icon.
    function sameHidden(a, b) {
        return a.icon === b.icon && a.text === b.text;
    }

    // Updates `hidden` for text [start, end) replaced by `length` characters
    // with the entries `entries`. An icon the edit touches loses its text.
    function shiftHidden(start, end, length, entries) {
        const list = hidden, d = length - (end - start);
        let i = firstAt(list, start);
        if (i > 0 && list[i - 1].at + list[i - 1].icon.length > start)
            i--;
        const after = list.slice(firstAt(list, end));
        hidden = list.slice(0, i).concat(shifted(entries, start), d ? shifted(after, d) : after);
    }

    // Edits made by the editor itself, rather than through replaceRange.
    function trackEdit() {
        if (editing || !hidden.length && !cursors.length)
            return;
        const before = trackedText, after = editor.text;
        if (after === before)
            return; // only its colors changed
        trackedText = after;
        const d = diff(before, after, [], []);
        if (d) {
            if (hidden.length)
                shiftHidden(d.start, d.end1, d.end2 - d.start, []);
            shiftCursors(d.start, d.end1, d.end2 - d.start);
        }
    }

    // How many characters a and b have in common at their starts (or ends,
    // if `fromEnd`), up to max. It compares slices, which V4 does natively,
    // rather than characters, each of which it makes a string of (in a long
    // text, a diff took milliseconds).
    function sameLength(a, b, fromEnd, max) {
        let n = 0;
        for (let step = 1024; step > 0;) {
            const same = n + step <= max && (fromEnd
                ? a.slice(a.length - n - step, a.length - n) === b.slice(b.length - n - step, b.length - n)
                : a.slice(n, n + step) === b.slice(n, n + step));
            if (same)
                n += step;
            else
                step >>= 1;
        }
        return n;
    }

    // The span that differs between two texts with their entries: `before`
    // [start, end1) became `after` [start, end2). Null if nothing differs.
    function diff(before, after, beforeHidden, afterHidden) {
        const bh = beforeHidden, ah = afterHidden;
        const max = Math.min(before.length, after.length);
        let s = sameLength(before, after, false, max);
        const same = sameLength(before, after, true, max - s);
        let e1 = before.length - same, e2 = after.length - same;
        // An icon on both sides is only unchanged if its hidden text is too.
        for (let i = 0; ; i++) {
            const b = bh[i], a = ah[i];
            const bIn = b && b.at < s, aIn = a && a.at < s;
            if (!bIn && !aIn)
                break;
            if (bIn && aIn && b.at === a.at && sameHidden(b, a))
                continue;
            s = Math.min(bIn ? b.at : s, aIn ? a.at : s);
            break;
        }
        for (let i = 1; ; i++) {
            const b = bh[bh.length - i], a = ah[ah.length - i];
            const bIn = b && b.at >= e1, aIn = a && a.at >= e2;
            if (!bIn && !aIn)
                break;
            if (bIn && aIn && before.length - b.at === after.length - a.at && sameHidden(b, a))
                continue;
            const cut = Math.max(bIn ? b.at + b.icon.length - e1 : 0, aIn ? a.at + a.icon.length - e2 : 0);
            e1 += cut;
            e2 += cut;
            break;
        }
        if (s === e1 && s === e2)
            return null;
        return { start: s, end1: e1, end2: e2 };
    }

    // Entries for `text` replacing [start, end) with the same icons in the
    // same order (a case change or indenting), which keep their texts: the
    // k-th 🍄 of the old text is the k-th 🍄 of the new one.
    function carriedHidden(start, end, text) {
        const old = bufferText().slice(start, end);
        const r = [];
        for (const h of hiddenIn(hidden, start, end)) {
            let i = old.indexOf(h.icon), j = text.indexOf(h.icon);
            while (i >= 0 && i < h.at && j >= 0) {
                i = old.indexOf(h.icon, i + h.icon.length);
                j = text.indexOf(h.icon, j + h.icon.length);
            }
            if (i === h.at && j >= 0)
                r.push({ at: j, icon: h.icon, text: h.text });
        }
        return r;
    }

    // The entry of the icon at p, or null.
    function hiddenAt(p) {
        const list = hidden, i = firstAt(list, p);
        return i < list.length && list[i].at === p ? list[i] : null;
    }

    // Replaces the whole text with `text`, whose icons hide `entries`, as
    // one undo step (Koil's listing, read again). Only the part that differs
    // changes, so the view stays where it is.
    function replaceText(text, entries) {
        externalEdit(() => {
            const d = diff(bufferText(), text, hidden, entries);
            if (d)
                replaceRange(d.start, d.end1, text.slice(d.start, d.end2), hiddenIn(entries, d.start, d.end2));
        });
    }

    // Makes `edits` ({ start, end, text, hidden }: in the text as it is, in
    // order and apart, `hidden` the entries for `text`, from its start) as
    // one edit, which isn't the user's (Koil's listing, as it changed on
    // disk): undo and redo don't take it back, but go on around it, as their
    // steps move past it (see movedSteps). With `undoable`, it's a change
    // like any other. The cursors stay on the text they were on.
    function mergeEdits(edits, undoable) {
        if (!edits.length)
            return;
        interrupt();
        const wasInserting = inserting;
        // What was typed so far is a change of its own.
        commitChange(true);
        if (undoable)
            beginChange();
        batched(() => {
            const c = movedPast(cursor, edits), a = movedPast(anchor, edits);
            for (let i = edits.length - 1; i >= 0; i--) {
                const e = edits[i];
                replaceRange(e.start, e.end, e.text, e.hidden);
            }
            if (!undoable) {
                undoStack = movedSteps(undoStack, edits, true);
                redoStack = movedSteps(redoStack, edits, false);
            }
            if (lastVisual) {
                lastVisual = { mode: lastVisual.mode, anchor: movedPast(lastVisual.anchor, edits),
                    cursor: movedPast(lastVisual.cursor, edits) };
            }
            const t = bufferText();
            anchor = Math.min(a, t.length);
            setCursor(mode === "normal" ? clampNormal(t, c) : Math.min(c, t.length));
        });
        if (undoable)
            commitChange(true);
        if (wasInserting)
            beginChange();
    }

    // Where p is after `edits` (as mergeEdits takes them, or with `length`
    // for the length of the text): past the ones before it, and in one that
    // replaces it, as far into its text as it was, at most its last
    // character.
    function movedPast(p, edits) {
        let d = 0;
        for (const e of edits) {
            if (e.start > p)
                break;
            const length = e.text !== undefined ? e.text.length : e.length;
            if (e.end <= p) {
                d += length - (e.end - e.start);
                continue;
            }
            return e.start + d + Math.min(p - e.start, Math.max(0, length - 1));
        }
        return p + d;
    }

    // An undo (or redo, if not `undoing`) stack, newest last, with its steps
    // moved past `edits` (as mergeEdits takes them), which were made to the
    // text the newest one left: each step is where its text is after them,
    // and the edits are taken back through it, to where they are in the
    // text before it, for the next one. A step that an edit touches can't be
    // undone (or redone) any more, nor can the ones after it: the stack
    // keeps only the newer ones.
    function movedSteps(stack, edits, undoing) {
        let spans = edits.map(e => ({ start: e.start, end: e.end, length: e.text.length }));
        const kept = [];
        for (let k = stack.length - 1; k >= 0; k--) {
            const step = stack[k];
            // Its text in the text as it is, and what it puts back.
            const now = (undoing ? step.inserted : step.removed).length;
            const then = (undoing ? step.removed : step.inserted).length;
            const s = step.start, e = s + now;
            let shift = 0, clash = false;
            const before = [];
            for (const x of spans) {
                if (x.end <= s) {
                    shift += x.length - (x.end - x.start);
                    before.push(x);
                } else if (x.start >= e) {
                    before.push({ start: x.start + then - now, end: x.end + then - now, length: x.length });
                } else {
                    clash = true;
                    break;
                }
            }
            if (clash)
                break;
            const moved = Object.assign({}, step, { start: s + shift });
            if (undoing)
                moved.cursor = movedPast(step.cursor, before);
            kept.push(moved);
            spans = before;
        }
        return kept.reverse();
    }

    // Entries read from the clipboard: checked, since any app could have
    // put them there.
    function validHidden(text, list) {
        if (!Array.isArray(list))
            return false;
        let next = 0; // where the next entry can start
        for (const h of list) {
            if (!h || !Number.isInteger(h.at) || h.at < next || typeof h.icon !== "string" || h.icon === ""
                    || Txt.charEnd(h.icon, 0) !== h.icon.length || !text.startsWith(h.icon, h.at)
                    || typeof h.text !== "string")
                return false;
            next = h.at + h.icon.length;
        }
        return true;
    }

    // ---- Prefixes ----------------------------------------------------------
    // In Koil's listing (linePrefixes), a line starts with a prefix: its
    // entry's icon (which hides its ID) and two spaces, or three spaces for
    // a new entry. The cursor never goes into one, as if the name started
    // the line: motions stop after it (word motions skip it like blanks),
    // and typing, joining and splitting lines keep it first on its line.
    // Whole lines (dd, yy, V) take it along. A line without one (that
    // isn't an icon or a space, then two spaces) is plain.

    // The length of the prefix that starts at ls in s, 0 if none.
    // `hidesText(i)` says whether the icon at i hides text; a Nerd Font one
    // (a rendered new entry's) is an icon too.
    function prefixLength(s, ls, hidesText) {
        if (ls >= s.length || s[ls] === "\n")
            return 0;
        const e = Txt.charEnd(s, ls);
        if (s[e] !== " " || s[e + 1] !== " ")
            return 0;
        return s[ls] === " " || Txt.isPrivateUse(s, ls) || hidesText(ls) ? e + 2 - ls : 0;
    }

    // Where the prefix of the line that starts at ls ends: ls if it has none.
    function prefixEnd(t, ls) {
        return linePrefixes ? ls + prefixLength(t, ls, hiddenAt) : ls;
    }

    // p, or if it's in a prefix, where that ends.
    function outOfPrefix(t, p) {
        if (!linePrefixes)
            return p;
        const pe = prefixEnd(t, Txt.lineStart(t, p));
        return p < pe ? pe : p;
    }

    function inPrefix(t, p) {
        return outOfPrefix(t, p) !== p;
    }

    // Normal mode keeps the cursor on a character (see Txt.clampNormal),
    // after the prefix.
    function clampNormal(t, p) {
        return outOfPrefix(t, Txt.clampNormal(t, p));
    }

    // The first character of p's line that isn't blank, after its prefix
    // (or the line's end).
    function firstNonBlank(t, p) {
        let q = prefixEnd(t, Txt.lineStart(t, p));
        while (q < t.length && Txt.isBlank(t[q]))
            q++;
        return q;
    }

    // `text` (whose icons hide `entries`) to put in place of [start, end),
    // with three spaces added before each line it starts that has no
    // prefix: text from another app has none, and a line break leaves the
    // rest of its line without one. Returns { text, entries }.
    function prefixLines(start, end, text, entries) {
        const t = bufferText(), first = start === Txt.lineStart(t, start);
        if (!linePrefixes || !first && text.indexOf("\n") < 0)
            return { text: text, entries: entries };
        // The rest of the line after the text, which its last line starts.
        const rest = t.slice(end, Txt.lineEnd(t, end));
        const icons = new Set(entries.map(h => h.at));
        const pieces = text.split("\n"), added = [];
        let from = 0; // where the piece starts in text
        pieces.forEach((piece, k) => {
            const line = k === pieces.length - 1 ? piece + rest : piece;
            const hides = i => i < piece.length ? icons.has(from + i) : hiddenAt(end + i - piece.length) !== null;
            if ((k > 0 || first && piece !== "") && !prefixLength(line, 0, hides))
                added.push(from);
            from += piece.length + 1;
        });
        if (!added.length)
            return { text: text, entries: entries };
        let r = "", i = 0;
        for (const at of added) {
            r += text.slice(i, at) + blankPrefix;
            i = at;
        }
        // Each entry moves by the prefixes added before it (both sorted).
        let k = 0;
        const moved = entries.map(h => {
            while (k < added.length && added[k] <= h.at)
                k++;
            return { at: h.at + k * blankPrefix.length, icon: h.icon, text: h.text };
        });
        return { text: r + text.slice(i), entries: moved };
    }

    // A step of a word motion (`step`, from q), stepping again while it's
    // in a prefix, as if that were blank. Stuck in the first line's prefix
    // (at the text's start), it ends after it.
    function wordStep(t, q, step) {
        let r = step(q);
        while (inPrefix(t, r)) {
            const next = step(r);
            if (next === r)
                return outOfPrefix(t, r);
            r = next;
        }
        return r;
    }

    // q after `count` steps of a motion (step(q)), or after the first that
    // doesn't move.
    function steps(q, count, step) {
        for (let i = 0; i < count; i++) {
            const next = step(q);
            if (next === q)
                break;
            q = next;
        }
        return q;
    }

    // A text object (see Txt.textObject), which doesn't start in a prefix:
    // `aw` takes the blanks before a name's first word, say.
    function textObject(t, p, obj, count) {
        const r = Txt.textObject(t, p, obj, count);
        if (r && !r.linewise)
            r.start = Math.min(outOfPrefix(t, r.start), r.end);
        return r;
    }

    // ---- Other edits -------------------------------------------------------

    // J and gJ: joins `count` lines (at least two) from the cursor's, as one
    // edit (one per line break had 4000J take two minutes).
    function joinLines(count, spaces) {
        const t = bufferText(), ls = Txt.lineStart(t, cursor), edits = [];
        let le = Txt.lineEnd(t, ls);
        // The line joined so far: whether there's more than its prefix, and
        // its last character.
        let filled = le > prefixEnd(t, ls), last = t[le - 1];
        for (let i = 1; i < Math.max(count, 2) && le < t.length; i++) {
            const next = le + 1, end = Txt.lineEnd(t, next);
            // The next line's prefix goes with the line break.
            let e = prefixEnd(t, next), sep = "";
            if (spaces) {
                while (e < end && (t[e] === " " || t[e] === "\t"))
                    e++;
                if (filled && e < end && t[e] !== ")" && last !== " " && last !== "\t")
                    sep = " ";
            }
            edits.push({ start: le, end: e, text: sep });
            if (end > e) {
                filled = true;
                last = t[end - 1];
            } else if (sep) {
                filled = true;
                last = sep;
            }
            le = end;
        }
        if (!edits.length) {
            setCursor(clampNormal(t, cursor));
            return;
        }
        // On the last line break.
        const ends = replaceRanges(edits);
        setCursor(clampNormal(bufferText(), ends[ends.length - 1] - edits[edits.length - 1].text.length));
    }

    // Adds `delta` to the number under or after the cursor on its line:
    // decimal (with an optional "-"), 0x hex or 0b binary. Hex and binary
    // numbers, and decimals with leading zeros, keep their width.
    function addToNumber(delta) {
        const t = bufferText();
        const ls = Txt.lineStart(t, cursor), le = Txt.lineEnd(t, cursor);
        const re = /0[xX][0-9a-fA-F]+|0[bB][01]+|-?(?!0[xX][0-9a-fA-F]|0[bB][01])[0-9]+/g;
        const line = t.slice(ls, le);
        let m;
        do
            m = re.exec(line);
        while (m && ls + m.index + m[0].length <= cursor);
        if (!m) {
            typeahead = [];
            return;
        }
        const s = m[0];
        let text;
        if (/^0[xXbB]/.test(s)) {
            const base = /^0[xX]/.test(s) ? 16 : 2;
            const digits = s.slice(2);
            text = Math.max(0, parseInt(digits, base) + delta).toString(base).padStart(digits.length, "0");
            const letters = digits.match(/[a-fA-F]/g);
            if (letters && /[A-F]/.test(letters[letters.length - 1]))
                text = text.toUpperCase();
            text = s.slice(0, 2) + text;
        } else {
            const n = parseInt(s, 10) + delta;
            const digits = s.replace("-", "");
            const width = digits.length > 1 && digits[0] === "0" ? digits.length : 1;
            text = (n < 0 ? "-" : "") + String(Math.abs(n)).padStart(width, "0");
        }
        const start = ls + m.index;
        replaceRange(start, start + s.length, text);
        setCursor(start + text.length - 1);
    }

    function shiftLines(range, dir, times) {
        const t = bufferText();
        const s = Txt.lineStart(t, range.start);
        const e = Txt.lineEnd(t, Math.max(range.start, range.end - 1));
        let ls = s;
        const lines = t.slice(s, e).split("\n").map(whole => {
            // After the prefix, which stays first.
            const head = whole.slice(0, prefixEnd(t, ls) - ls), line = whole.slice(head.length);
            ls += whole.length + 1;
            if (dir > 0)
                return head + (line.length ? (line[0] === "\t" ? "\t" : "    ").repeat(times) + line : line);
            let k = 0, cols = 0;
            while (k < line.length && cols < 4 * times && (line[k] === " " || line[k] === "\t")) {
                cols += line[k] === "\t" ? 4 : 1;
                k++;
            }
            return head + line.slice(k);
        });
        const text = lines.join("\n");
        replaceRange(s, e, text, carriedHidden(s, e, text));
        setCursor(clampNormal(bufferText(), firstNonBlank(bufferText(), s)));
    }

    // how: "~" toggles the case, "u" lowers it, "U" raises it, and "?" (g?)
    // is ROT13.
    function changeCase(range, how) {
        const text = caseChanged(bufferText().slice(range.start, range.end), how);
        replaceRange(range.start, range.end, text, carriedHidden(range.start, range.end, text));
        setCursor(clampNormal(bufferText(), range.start));
    }

    function caseChanged(s, how) {
        return how === "u" ? s.toLowerCase() : how === "U" ? s.toUpperCase()
            : how === "?" ? Txt.rot13(s) : Txt.toggleCase(s);
    }

    // ---- Command line ------------------------------------------------------

    function runCommandLine(line) {
        const kind = line[0], body = line.slice(1);
        if (kind === ":") {
            runEx(body.trim());
            return;
        }
        const pattern = body || (lastSearch && lastSearch.pattern);
        if (!pattern)
            return;
        lastSearch = { pattern: pattern, forward: kind === "/" };
        moveBy({ count: 0, motion: { name: "n" } });
    }

    // `confirm` is set by :confirm, which runs the command after it.
    function runEx(c, confirm) {
        if (c === "")
            return;
        if (/^conf(i|ir|irm)?(\s|$)/.test(c)) {
            const rest = c.replace(/^\S+\s*/, "");
            if (rest)
                runEx(rest, true);
            else
                showError("E471: Argument required");
            return;
        }
        if (/^\d+$/.test(c) || c === "$") {
            const t = bufferText();
            const line = c === "$" ? Txt.countLines(t) : Math.max(1, Math.min(parseInt(c, 10), Txt.countLines(t)));
            if (isVisual)
                setMode("normal");
            setCursor(clampNormal(t, firstNonBlank(t, Txt.lineToPos(t, line))));
            return;
        }
        if (["w", "write"].includes(c))
            outside(() => writeRequested(false, false));
        else if (["wq", "x", "wq!", "x!", "xit", "exit"].includes(c))
            outside(() => writeRequested(true, false));
        else if (["q", "quit", "qa", "qall"].includes(c))
            outside(() => quitRequested(false, !!confirm, c.startsWith("qa")));
        else if (["q!", "quit!", "qa!", "qall!"].includes(c))
            outside(() => quitRequested(true, false, c.startsWith("qa")));
        else if (["noh", "nohl", "nohlsearch"].includes(c)) {
            highlightPattern = "";
            highlightsCleared();
        }
        else if (/^se(t)?(\s|$)/.test(c))
            setOptions(c.replace(/^\S+\s*/, ""));
        else if (/^h(elp)?(\s|$)/.test(c))
            outside(() => helpRequested(c.replace(/^\S+\s*/, "")));
        else if (/^(reg(i|is|ist|iste|ister|isters)?|di(s|sp|spl|spla|splay)?)(\s|$)/.test(c))
            showRegisters(c.replace(/^\S+\s*/, ""));
        else
            showError("E492: Not an editor command: " + c);
    }

    // The options :set knows: full name, short name, property, default,
    // and for a number option its range. fontsize isn't vim's (gvim has
    // guifont); its short name is vim's for fsync, which Koil hasn't.
    // guifont is only the family (gvim's also takes a size, like Menlo:h14).
    // hidden, gitignore and regex are Koil's (vim's hidden is about buffers).
    readonly property var options: [
        { name: "fontsize", short: "fs", property: "fontSize", default: defaultFontSize,
            min: minFontSize, max: maxFontSize },
        { name: "guifont", short: "gfn", property: "fontFamily", default: defaultFontFamily },
        { name: "number", short: "nu", property: "number", default: defaultNumber },
        { name: "relativenumber", short: "rnu", property: "relativeNumber", default: defaultRelativeNumber },
        { name: "sidescrolloff", short: "siso", property: "sideScrollOff", default: 4, min: 0, max: 999 },
        { name: "hidden", short: "hid", property: "showHidden", default: false },
        { name: "gitignore", short: "ignore", property: "gitignore", default: false },
        { name: "regex", short: "re", property: "regex", default: false }
    ]

    // An option as :set shows it: "  nu", "nonu", "  fs=16" or
    // "  gfn=Fira Code".
    function optionLabel(o) {
        const value = vim[o.property];
        return typeof value === "boolean" ? (value ? "  " : "no") + o.name : "  " + o.name + "=" + value;
    }

    // :set with args like "nu", "nonu", "nu!", "invnu", "nu?" or "nu&", for
    // a number option "fs=16" (or "fs:16"), "fs+=2", "fs-=2", "fs^=2"
    // (multiplies), "fs" or "fs?" (shows it) and "fs&", and for a string
    // option "gfn=Fira\ Code" (a backslash escapes a space; empty is the
    // default), "gfn", "gfn?" and "gfn&". No args lists the options that
    // aren't at their default.
    function setOptions(args) {
        const words = args.match(/(?:\\.|\S)+/g) || [];
        const shown = [];
        if (!words.length)
            shown.push(...options.filter(o => vim[o.property] !== o.default).map(optionLabel));
        for (const w of words) {
            const m = /^(no|inv)?([a-z]+)(?:([!?&])|([-+^]?[=:])(.*))?$/.exec(w);
            const o = m && options.find(o => o.name === m[2] || o.short === m[2]);
            if (!o) {
                showError("E518: Unknown option: " + w);
                return;
            }
            const prefix = m[1] || "", suffix = m[3] || "", op = m[4] || "";
            const isNumber = typeof o.default === "number", isString = typeof o.default === "string";
            if (prefix && (suffix || isNumber || isString) || op && !isNumber && !isString
                    || (isNumber || isString) && suffix === "!" || isString && op.length > 1) {
                showError("E474: Invalid argument: " + w);
                return;
            }
            if (suffix === "?" || (isNumber || isString) && !suffix && !op) {
                shown.push(optionLabel(o));
            } else if (suffix === "&") {
                vim[o.property] = o.default;
            } else if (isString) {
                const value = m[5].replace(/\\(.)/g, "$1");
                if (value)
                    fontFamiliesNeeded();
                const family = value ? fontFamilies.find(f => f.toLowerCase() === value.toLowerCase())
                    || (fontFamilies.length ? "" : value) : o.default;
                if (!family) {
                    showError("E596: Invalid font(s): " + w);
                    return;
                }
                vim[o.property] = family;
            } else if (op) {
                if (!/^-?\d+$/.test(m[5])) {
                    showError("E521: Number required after =: " + w);
                    return;
                }
                const n = parseInt(m[5], 10), value = vim[o.property];
                const result = op[0] === "+" ? value + n : op[0] === "-" ? value - n : op[0] === "^" ? value * n : n;
                if (result < o.min || result > o.max) {
                    showError("E474: Invalid argument: " + w + " (" + o.min + " to " + o.max + ")");
                    return;
                }
                vim[o.property] = result;
            } else if (suffix === "!" || prefix === "inv") {
                vim[o.property] = !vim[o.property];
            } else {
                vim[o.property] = prefix !== "no";
            }
        }
        if (shown.length)
            showMessage(shown.join(" "));
    }

    // ---- Motions -----------------------------------------------------------
    // Each returns { pos, type: "exclusive" | "inclusive" | "linewise" } or
    // null when the motion fails. `quiet` (for extra cursors) leaves the view
    // where it is. None ends in a prefix (see Prefixes): one that would ends
    // after it, but a character found there isn't found. One that goes
    // `count` steps stops at the first that doesn't move, as no later one
    // would (99999999w took a minute), and a search stops going round its
    // matches (see search).

    function motion(t, p, m, count, explicit, forOp, quiet) {
        const r = rawMotion(t, p, m, count, explicit, forOp, quiet);
        if (r && inPrefix(t, r.pos)) {
            if (["f", "F", "t", "T", ";", ","].includes(m.name))
                return null;
            r.pos = outOfPrefix(t, r.pos);
        }
        return r;
    }

    // The motion as it would go, which motion() keeps out of prefixes.
    function rawMotion(t, p, m, count, explicit, forOp, quiet) {
        const n = t.length;
        switch (m.name) {
        case "h":
        case "<Left>":
        case "<BS>": {
            const ls = prefixEnd(t, Txt.lineStart(t, p));
            return p > ls ? { pos: Txt.retreat(t, p, count, ls), type: "exclusive" } : null;
        }
        case "l":
        case "<Right>":
        case " ": {
            const le = Txt.lineEnd(t, p);
            return p < le ? { pos: Txt.advance(t, p, count, le), type: "exclusive" } : null;
        }
        case "j":
        case "<Down>":
            return lineMotion(t, p, count);
        case "k":
        case "<Up>":
            return lineMotion(t, p, -count);
        case "+":
        case "<CR>":
        case "<S-CR>":
        case "-": {
            const r = lineMotion(t, p, m.name === "-" ? -count : count);
            return r && { pos: firstNonBlank(t, r.pos), type: "linewise" };
        }
        case "_": {
            const r = count > 1 ? lineMotion(t, p, count - 1) : { pos: p };
            return r && { pos: firstNonBlank(t, r.pos), type: "linewise" };
        }
        case "0":
        case "<Home>":
            return { pos: prefixEnd(t, Txt.lineStart(t, p)), type: "exclusive" };
        case "^":
            return { pos: firstNonBlank(t, p), type: "exclusive" };
        case "$":
        case "<End>": {
            let q = p;
            if (count > 1) {
                const r = lineMotion(t, p, count - 1);
                if (!r)
                    return null;
                q = r.pos;
            }
            return { pos: Txt.lineEnd(t, q), type: "exclusive", eol: true };
        }
        case "|": {
            // Columns count from the prefix's end, as in positionLabel.
            return { pos: Txt.atColumn(t, prefixEnd(t, Txt.lineStart(t, p)), count - 1), type: "exclusive" };
        }
        case "gg":
        case "G": {
            const lines = Txt.countLines(t);
            const line = explicit ? Math.min(count, lines) : m.name === "gg" ? 1 : lines;
            return { pos: firstNonBlank(t, Txt.lineToPos(t, line)), type: "linewise" };
        }
        case "w":
        case "W": {
            const big = m.name === "W";
            let q = p, prev = p;
            for (let i = 0; i < count && (i === 0 || q !== prev); i++) {
                prev = q;
                q = wordStep(t, q, q => Txt.nextWordStart(t, q, big));
            }
            // "dw" on the last word of a line stops at the end of that line.
            if (forOp) {
                const le = Txt.lineEnd(t, prev);
                if (q > le && le > prev)
                    q = le;
            }
            return q === p ? null : { pos: q, type: "exclusive" };
        }
        case "b":
        case "B": {
            const q = steps(p, count, q => wordStep(t, q, q => Txt.prevWordStart(t, q, m.name === "B")));
            return q === p ? null : { pos: q, type: "exclusive" };
        }
        case "e":
        case "E": {
            const q = steps(p, count, q => wordStep(t, q, q => Txt.wordEnd(t, q, m.name === "E")));
            return q === p ? null : { pos: q, type: "inclusive" };
        }
        case "ge":
        case "gE": {
            const q = steps(p, count, q => wordStep(t, q, q => Txt.prevWordEnd(t, q, m.name === "gE")));
            return q === p ? null : { pos: q, type: "inclusive" };
        }
        case "f":
        case "F":
        case "t":
        case "T":
            lastFind = { kind: m.name, ch: m.ch };
            return Txt.findChar(t, p, m.name, m.ch, count, false);
        case ";":
        case ",": {
            if (!lastFind)
                return null;
            const reverse = { f: "F", F: "f", t: "T", T: "t" };
            const kind = m.name === ";" ? lastFind.kind : reverse[lastFind.kind];
            return Txt.findChar(t, p, kind, lastFind.ch, count, true);
        }
        case "%": {
            if (explicit) {
                const line = Math.min(Math.ceil(count * Txt.countLines(t) / 100), Txt.countLines(t));
                return { pos: firstNonBlank(t, Txt.lineToPos(t, line)), type: "linewise" };
            }
            return Txt.matchPair(t, p);
        }
        case "}":
            return { pos: steps(p, count, q => Txt.nextParagraph(t, q)), type: "exclusive" };
        case "{":
            return { pos: steps(p, count, q => Txt.prevParagraph(t, q)), type: "exclusive" };
        case "n":
        case "N": {
            if (!lastSearch) {
                showError("E35: No previous regular expression");
                return null;
            }
            const forward = m.name === "n" ? lastSearch.forward : !lastSearch.forward;
            const q = search(t, lastSearch.pattern, forward, count, p);
            // One that found nothing highlights nothing, even once the text
            // has it (until n finds it).
            highlightPattern = q === null ? "" : lastSearch.pattern;
            return q === null ? null : { pos: q, type: "exclusive" };
        }
        case "*":
        case "#": {
            const w = Txt.wordAt(t, p);
            if (!w)
                return null;
            lastSearch = { pattern: "\\b" + Txt.escapeRegExp(w.text) + "\\b", forward: m.name === "*" };
            highlightPattern = lastSearch.pattern;
            const q = search(t, lastSearch.pattern, lastSearch.forward, count, lastSearch.forward ? p : w.start);
            return q === null ? null : { pos: q, type: "exclusive" };
        }
        case "H":
        case "M":
        case "L": {
            if (!flickable)
                return null;
            if (batch)
                flush(); // for where the view is
            const lines = Txt.countLines(t);
            const top = Math.min(lines - 1, Math.max(0, Math.ceil((flickable.contentY - editor.topPadding) / lineHeight)));
            const bottom = Math.max(top, Math.min(lines - 1,
                Math.floor((flickable.contentY + flickable.height - editor.topPadding) / lineHeight) - 1));
            const line = m.name === "H" ? Math.min(top + count - 1, bottom)
                : m.name === "L" ? Math.max(bottom - count + 1, top) : Math.floor((top + bottom) / 2);
            return { pos: firstNonBlank(t, Txt.lineToPos(t, line + 1)), type: "linewise" };
        }
        default: { // page scrolling
            const half = m.name === "<C-d>" || m.name === "<C-u>";
            const down = ["<C-d>", "<C-f>", "<PageDown>"].includes(m.name);
            const lines = (half ? Math.floor(pageLines / 2) : pageLines - 2) * (down ? 1 : -1);
            if (!forOp && !quiet)
                scrollLines(lines);
            return lineMotion(t, p, lines);
        }
        }
    }

    function lineMotion(t, p, delta) {
        let ls = Txt.lineStart(t, p);
        let moved = 0;
        if (delta > 0) {
            while (moved < delta) {
                const le = Txt.lineEnd(t, ls);
                if (le >= t.length)
                    break;
                ls = le + 1;
                moved++;
            }
        } else {
            while (moved < -delta && ls > 0) {
                ls = Txt.lineStart(t, ls - 1);
                moved++;
            }
        }
        if (moved === 0)
            return null;
        return { pos: Txt.atColumn(t, ls, wantCol), type: "linewise", keepCol: true };
    }

    // A pattern that isn't a valid regular expression (e.g. while it's still
    // being typed) is searched for literally. Either way, one without an
    // uppercase letter ignores case (smart case).
    function searchRegExp(pattern) {
        try {
            return new RegExp(pattern, Txt.ignoresCase(pattern, true) ? "gmi" : "gm");
        } catch (e) {
            return new RegExp(Txt.escapeRegExp(pattern), Txt.ignoresCase(pattern, false) ? "gmi" : "gm");
        }
    }

    // Back at the first match it found, a search has gone round all of them
    // (wrapping at the end), and would go round again and again: the rounds
    // left are skipped (999999n).
    function search(t, pattern, forward, count, from) {
        const re = searchRegExp(pattern);
        let p = from, first = -1;
        for (let i = 0; i < count; i++) {
            const q = forward ? searchForward(re, t, p, false) : searchBackward(re, t, p, false);
            if (q < 0) {
                showError("E486: Pattern not found: " + pattern);
                return null;
            }
            if (i === 0)
                first = q;
            else if (q === first)
                i += Math.floor((count - 1 - i) / i) * i;
            p = q;
        }
        return p;
    }

    function searchForward(re, t, p, quiet) {
        let m = matchFrom(re, t, p + 1);
        if (!m) {
            m = matchFrom(re, t, 0);
            if (m && !quiet)
                showMessage("search hit BOTTOM, continuing at TOP");
        }
        return m ? m.index : -1;
    }

    // The first match of `re` in t from `from` on, or null. One that starts
    // in a prefix (see Prefixes) doesn't count.
    function matchFrom(re, t, from) {
        if (from > t.length)
            return null;
        re.lastIndex = from;
        let m;
        while ((m = re.exec(t)) !== null && inPrefix(t, m.index))
            re.lastIndex = m.index + 1;
        return m;
    }

    function searchBackward(re, t, p, quiet) {
        let before = -1, last = -1, m;
        re.lastIndex = 0;
        while ((m = re.exec(t)) !== null) {
            if (!inPrefix(t, m.index)) {
                if (m.index < p)
                    before = m.index;
                last = m.index;
            }
            if (m[0] === "")
                re.lastIndex++;
        }
        if (before < 0 && last >= 0 && !quiet)
            showMessage("search hit TOP, continuing at BOTTOM");
        return before >= 0 ? before : last;
    }

    // ---- Search preview ----------------------------------------------------

    function typedSearch() {
        const kind = commandLine[0];
        return kind === "/" || kind === "?" ? commandLine.slice(1) : null;
    }

    // Like vim's 'incsearch': while a search is typed, scroll to the match
    // Enter would jump to, and restore the view when the search is cancelled.
    function previewSearch() {
        if (inChunk)
            return; // not for a search a macro types
        if (batch)
            flush(); // to scroll from where the editor is
        const pattern = typedSearch();
        if (pattern === null) {
            if (searchView && flickable) {
                flickable.contentX = searchView.x;
                flickable.contentY = searchView.y;
            }
            searchView = null;
            searchTarget = -1;
            return;
        }
        if (!searchView && flickable)
            searchView = { x: flickable.contentX, y: flickable.contentY };
        const t = bufferText();
        const re = searchRegExp(pattern);
        searchTarget = pattern === "" ? -1
            : commandLine[0] === "/" ? searchForward(re, t, cursor, true) : searchBackward(re, t, cursor, true);
        if (!flickable)
            return;
        if (searchTarget < 0) {
            flickable.contentX = searchView.x;
            flickable.contentY = searchView.y;
            return;
        }
        const r = editor.positionToRectangle(searchTarget);
        const maxX = Math.max(0, flickable.contentWidth - flickable.width);
        const maxY = Math.max(0, flickable.contentHeight - flickable.height);
        // Text in the left padding is under the line numbers, if they're on.
        const x = r.x < searchView.x + editor.leftPadding || r.x + r.width > searchView.x + flickable.width
            ? r.x - flickable.width / 2 : searchView.x;
        const y = r.y < searchView.y || r.y + r.height > searchView.y + flickable.height
            ? r.y - flickable.height / 2 : searchView.y;
        flickable.contentX = Math.max(0, Math.min(x, maxX));
        flickable.contentY = Math.max(0, Math.min(y, maxY));
    }

    // Matches of the search being typed (or else of the last search, until
    // it's cleared) that fall in the visible lines, as highlightSpans.
    function searchHighlights() {
        const typed = typedSearch();
        const pattern = typed !== null ? typed : highlightPattern;
        if (!pattern)
            return [];
        const t = bufferText();
        const v = visibleRange(t);
        const re = searchRegExp(pattern);
        const spans = [];
        re.lastIndex = v.from;
        let m;
        while ((m = re.exec(t)) !== null && m.index <= v.to && spans.length < 5000) {
            if (m[0] === "") {
                re.lastIndex++;
                continue;
            }
            if (inPrefix(t, m.index))
                continue;
            Txt.addHighlight(t, spans, m.index, m.index + m[0].length, m.index === highlightTarget);
        }
        return spans;
    }

    // ---- View --------------------------------------------------------------

    // The lines in view, even partly, as { top, bottom } counted from 0
    // (bottom can be past the last line).
    function visibleLines() {
        if (!flickable)
            return { top: 0, bottom: Txt.countLines(bufferText()) - 1 };
        const y = flickable.contentY - editor.topPadding;
        return { top: Math.max(0, Math.floor(y / lineHeight)), bottom: Math.max(0, Math.ceil((y + flickable.height) / lineHeight)) };
    }

    // The part of the text [from, to] in the visible lines.
    function visibleRange(t) {
        const v = visibleLines();
        return { from: Txt.lineToPos(t, v.top + 1), to: Txt.lineEnd(t, Txt.lineToPos(t, v.bottom + 1)) };
    }

    function scrollLines(lines) {
        if (!flickable)
            return;
        if (batch)
            flush(); // the view follows the cursor only after a chunk
        const max = Math.max(0, flickable.contentHeight - flickable.height);
        flickable.contentY = Math.max(0, Math.min(flickable.contentY + lines * lineHeight, max));
    }

    // Scrolls as little as shows the cursor (sideways, as showColumn does).
    function showCursor() {
        if (!flickable || batch)
            return; // after the chunk (see flush)
        const f = flickable, top = editor.topPadding + (Txt.lineOf(bufferText(), cursor) - 1) * lineHeight;
        const maxY = Math.max(0, f.contentHeight - f.height);
        if (top < f.contentY)
            f.contentY = top <= editor.topPadding ? 0 : top;
        else if (top + lineHeight > f.contentY + f.height)
            f.contentY = Math.min(maxY, top + lineHeight - f.height);
        showColumn();
    }

    // Scrolls sideways as little as shows all of the character the cursor
    // is on (the editor's cursor rectangle is a bar, only as wide as a
    // line), sideScrollOff columns on either side of it (fewer if the view
    // is too narrow for them) and the padding after them. Room that
    // reaches the start of a name shows its prefix too, the icon that
    // hides its ID, so 0 scrolls all the way left.
    function showColumn() {
        if (!flickable || batch)
            return; // as showCursor
        const t = bufferText(), p = Math.min(cursor, t.length), ls = Txt.lineStart(t, p);
        const f = flickable, r = editor.positionToRectangle(p);
        const columns = Math.floor((f.width - editor.leftPadding - editor.rightPadding) / charWidth);
        const room = Math.max(0, Math.min(sideScrollOff, Math.floor((columns - 1) / 2))) * charWidth;
        let left = r.x - room;
        if (left <= editor.positionToRectangle(prefixEnd(t, ls)).x)
            left = editor.positionToRectangle(ls).x;
        const right = (p < Txt.lineEnd(t, p) ? editor.positionToRectangle(Txt.charEnd(t, p)).x : r.x + charWidth)
            + room + editor.rightPadding;
        // The left edge is the padding, where the line numbers are. If both
        // sides can't be in view, the left one is.
        let x = f.contentX;
        if (right > x + f.width)
            x = right - f.width;
        if (left < x + editor.leftPadding)
            x = left - editor.leftPadding;
        x = Math.max(0, Math.min(x, f.contentWidth - f.width));
        if (x !== f.contentX)
            f.contentX = x;
    }

    // Ctrl-E and Ctrl-Y: scrolls the view `lines` whole lines (down if
    // positive), and moves the cursor only as far as keeps it in view.
    function scrollText(lines) {
        if (!flickable)
            return;
        if (batch)
            flush(); // as scrollLines
        const f = flickable, h = lineHeight, pad = editor.topPadding;
        const at = Math.max(0, (f.contentY - pad) / h); // the top line, maybe partly hidden
        const top = Math.max(0, lines > 0 ? Math.floor(at + 1e-6) + lines : Math.ceil(at - 1e-6) + lines);
        f.contentY = top === 0 ? 0 : Math.min(Math.max(0, f.contentHeight - f.height), pad + top * h);
        const t = bufferText(), n = Txt.countLines(t);
        const first = Math.min(n - 1, Math.max(0, Math.ceil((f.contentY - pad) / h - 1e-6)));
        // A line counts as shown with the space below its text cut off.
        const last = Math.max(first, Math.min(n - 1, Math.floor((f.contentY + f.height - pad) / h + 0.25) - 1));
        const line = Txt.lineOf(t, cursor) - 1;
        const d = line < first ? first - line : line > last ? last - line : 0;
        if (d)
            moveBy({ count: Math.abs(d), motion: { name: d > 0 ? "j" : "k" } });
    }

    function scrollToCursor(where) {
        if (!flickable)
            return;
        if (batch)
            flush(); // as scrollLines
        const r = editor.positionToRectangle(cursor);
        const y = where === "t" ? r.y - editor.topPadding
            : where === "b" ? r.y + r.height + editor.bottomPadding - flickable.height
            : r.y + r.height / 2 - flickable.height / 2;
        const max = Math.max(0, flickable.contentHeight - flickable.height);
        flickable.contentY = Math.max(0, Math.min(y, max));
    }
}
