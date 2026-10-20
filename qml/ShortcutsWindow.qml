pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The user's shortcuts (Space q, Koil > Shortcuts…, or a button in
// Settings): each is keys (Space c, gc, <C-k>) that run keys of theirs, as
// a macro does (see Vim.shortcuts), in normal mode, visual mode or both,
// with a name, and on or off. The list shows each by its name, else its
// keys, else the keys it runs, and under them, with the lock button on,
// Koil's own keys, which can be run but not changed, nor taken (see
// problemOf). A click on one (or
// Enter) runs it in the main window, also one with no keys (main.qml's
// runShortcut); its pencil shows all of it in a form, which Save saves,
// used at once (saveShortcuts), and + (or Cmd+N) does for a new one. The
// search over the list has the keys, and shows only the ones it matches:
// Up and Down pick one, and Enter runs it. The keys it runs can be typed
// or taken from a macro recorded (a register q records into). Tab goes
// through all of it (see tab).
Window {
    id: win

    // main.qml's window: the shortcuts, saveShortcuts, runShortcut, Koil's
    // own keys (ownShortcuts, and menuShortcuts, which the list doesn't
    // show), whether they do something where vim is (commandHere), and
    // whether the list shows them (showOwnShortcuts, saved with
    // changeSetting), the macros recorded (macroList), keys written out in
    // parts (keyParts), one by one (keyTokens) and as shown (keysName), a
    // key typed (keyToken), and what of vim's a shortcut takes the place
    // of (vimCommandIn).
    required property var app
    required property Theme theme

    readonly property real zoom: theme.zoom
    readonly property bool isMac: Qt.platform.os === "osx"
    // Whether this window has the keys, which its shortcuts are only for.
    // A Shortcut takes its window as active while any of the main
    // window's has the keys (Settings, or the main one): Esc there closed
    // this one, and with Settings open too, the two Escs were ambiguous,
    // so neither did anything.
    readonly property bool focused: activeFocusItem !== null
    readonly property var shortcuts: app.shortcuts
    readonly property var modes: [
        { label: qsTr("Normal"), value: "normal" },
        { label: qsTr("Visual"), value: "visual" },
        { label: qsTr("Both"), value: "both" }
    ]
    // The search's words, in lower case.
    readonly property var searchWords: searchField.input.text.toLowerCase().split(/\s+/).filter(w => w)
    // The shortcuts the list shows, by their index, and Koil's own (if it
    // shows them), by theirs in app.ownShortcuts: those the search matches
    // (see matches).
    readonly property var shown: shortcuts.map((s, i) => i).filter(i => matches(shortcuts[i], searchWords))
    readonly property var shownOwn: !app.showOwnShortcuts ? [] : app.ownShortcuts.map((s, i) => i)
        .filter(i => matches(app.ownShortcuts[i], searchWords))
    // The list's rows, the user's shortcuts first, as { at, shortcut, own,
    // heading }: `at` the shortcut's index (-1 for Koil's own), and
    // `heading` on the first of Koil's own, which shows one over it.
    readonly property var rows: shown.map(i => ({ at: i, shortcut: shortcuts[i], own: false, heading: false }))
        .concat(shownOwn.map((i, n) => ({ at: -1, shortcut: app.ownShortcuts[i], own: true, heading: n === 0 })))
    // Whether the form shows, and the shortcut it edits (-1 for a new one).
    property bool editing: false
    property int editIndex: -1
    // What the form has, and why it can't be saved, if it can't.
    readonly property var draft: ({
        name: nameField.input.text.trim(),
        keys: keyBox.keys,
        macro: macroField.input.text,
        mode: modes[Math.max(0, modeChoice.current)].value,
        enabled: enabledBox.checked
    })
    readonly property string problem: problemOf(draft)
    // What it takes the place of, which it can be saved with.
    readonly property string note: problem ? "" : noteOf(draft)
    readonly property bool canSave: draft.macro !== "" && problem === ""

    // Whether the search's `words` all match the shortcut `s`, in any case:
    // in its name or the keys it runs, or as a word of its keys as shown
    // ("space c" matches Space c; a part of "space", like "pa", doesn't
    // match every shortcut with Space).
    function matches(s, words) {
        const text = (s.name + "\n" + (s.macro || "")).toLowerCase();
        const keyWords = s.keys ? app.keysName(s.keys).toLowerCase().split(" ") : [];
        return words.every(w => text.includes(w) || keyWords.includes(w));
    }
    // What the list calls a shortcut: its name, else its keys, else the
    // keys it runs.
    function titleOf(s) {
        return s.name || (s.keys ? app.keysName(s.keys) : s.macro);
    }
    // Whether the keys `a` (as keyTokens gives them) start with `b`.
    function startsWith(a, b) {
        return b.length <= a.length && b.every((t, i) => t === a[i]);
    }
    // Whether shortcuts in `a` and `b` mode can have the same keys.
    function sameMode(a, b) {
        return a === "both" || b === "both" || a === b;
    }
    // Keys written out (a shortcut's), as StyledText: the names of keys,
    // like <CR>, in `color` (the theme's for them, if not given), so they
    // stand out from the characters that type themselves.
    function styledKeys(keys, color) {
        const escape = t => t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
            .replace(/ /g, "&nbsp;");
        return app.keyParts(keys).map(p => p.special ? "<font color=\"" + (color || theme.specialKey) + "\">"
            + escape(p.text) + "</font>" : escape(p.text)).join("");
    }
    function modeLabel(s) {
        return !s.enabled ? qsTr("Off") : s.mode === "both" ? qsTr("Normal, visual")
            : s.mode === "visual" ? qsTr("Visual") : qsTr("Normal");
    }
    // Why the shortcut `d` can't be saved: its keys start with a count or a
    // register, which vim reads first, or in the same mode they're Koil's
    // own (app.ownShortcuts, and the menus' Cmd keys, app.menuShortcuts,
    // which vim never gets), or another shortcut's that's on, or start
    // with those or are their start: as nothing waits to tell keys apart
    // from the longer ones they start, one of the two would never run.
    // "" if it can.
    function problemOf(d) {
        const ks = app.keyTokens(d.keys);
        if (!ks.length)
            return "";
        const name = app.keysName(d.keys);
        if (/^[1-9]$/.test(ks[0]))
            return qsTr("%1 can't start with %2, which is a count.").arg(name).arg(ks[0]);
        if (ks[0] === "\"")
            return qsTr("%1 can't start with \", which picks a register.").arg(name);
        for (const o of app.ownShortcuts.concat(app.menuShortcuts)) {
            const os = app.keyTokens(o.keys);
            if (!sameMode(o.mode, d.mode) || !startsWith(os, ks) && !startsWith(ks, os))
                continue;
            if (os.length === ks.length)
                return qsTr("%1 is the built-in “%2”.").arg(name).arg(o.name);
            return (os.length > ks.length ? qsTr("%1 starts the built-in %2 (“%3”).")
                : qsTr("%1 starts with the built-in %2 (“%3”).")).arg(name).arg(app.keysName(o.keys)).arg(o.name);
        }
        if (!d.enabled)
            return "";
        const other = shortcuts.find((s, i) => i !== editIndex && s.enabled && s.keys && sameMode(s.mode, d.mode)
            && (startsWith(app.keyTokens(s.keys), ks) || startsWith(ks, app.keyTokens(s.keys))));
        if (!other)
            return "";
        const what = other.name || (other.macro.length > 40 ? other.macro.slice(0, 39) + "…" : other.macro);
        const where = other.mode === "normal" ? qsTr(" in normal mode") : other.mode === "visual"
            ? qsTr(" in visual mode") : "";
        const os = app.keyTokens(other.keys);
        if (os.length === ks.length)
            return qsTr("%1 already runs “%2”%3.").arg(name).arg(what).arg(where);
        return (os.length > ks.length ? qsTr("%1 starts %2, which already runs “%3”%4.")
            : qsTr("%1 starts with %2, which already runs “%3”%4.")).arg(name).arg(app.keysName(other.keys))
            .arg(what).arg(where);
    }
    // What of vim's own the shortcut `d` takes the place of, as it comes
    // first (see app.vimCommandIn), unless Koil's own keys already did
    // (Space, which starts Koil's, no longer moves). "" if nothing.
    function noteOf(d) {
        for (const visual of [false, true]) {
            if (!d.keys || d.mode === (visual ? "normal" : "visual"))
                continue;
            const c = app.vimCommandIn(d.keys, visual);
            const cs = c ? app.keyTokens(c.keys) : [];
            if (!c || app.ownShortcuts.some(o => sameMode(o.mode, visual ? "visual" : "normal")
                    && startsWith(app.keyTokens(o.keys), cs)))
                continue;
            return (c.whole ? qsTr("It takes the place of vim's %1.")
                : qsTr("It takes the place of vim's commands that start with %1.")).arg(app.keysName(c.keys));
        }
        return "";
    }

    // Shows the window, with the list, centered near the top of the main
    // window the first time and whenever it was closed, and then on its
    // first shortcut, with no search, which has the keys: typing searches
    // at once.
    function open() {
        if (!visible) {
            x = app.x + Math.round((app.width - width) / 2);
            y = app.y + Math.round(Math.min(80 * zoom, Math.max(0, (app.height - height) / 2)));
            editing = false;
            searchField.input.text = "";
            shortcutList.currentIndex = rows.length ? 0 : -1;
        }
        show();
        raise();
        requestActivate();
        if (!editing)
            focusSearch();
    }
    // The keys to the search, with a shortcut picked if any is shown.
    function focusSearch(reason) {
        if (shortcutList.currentIndex < 0 && shortcutList.count)
            shortcutList.currentIndex = 0;
        searchField.input.forceActiveFocus(reason === undefined ? Qt.OtherFocusReason : reason);
    }
    // Tab and Shift+Tab: the keys to the next or previous of what the page
    // shown has, that's there and enabled. Qt's own Tab reaches only text
    // fields and lists on macOS, unless Keyboard navigation is on in
    // System Settings. From `from` if given, else from what has the keys.
    function tab(event, from) {
        const forward = event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier);
        const reason = forward ? Qt.TabFocusReason : Qt.BacktabFocusReason;
        const row = shortcutList.currentItem as ShortcutRow;
        const chain = (editing ? [nameField.input, keyBox, macroField.input, macroButton, modeChoice, enabledBox,
            deleteButton, cancelButton, saveButton] : [searchField.input, row ? row.editButton : null,
            row ? row.deleteButton : null, ownButton, newButton]).filter(i => i && i.visible && i.enabled);
        const at = chain.indexOf(from || activeFocusItem);
        const next = chain[at < 0 ? (forward ? 0 : chain.length - 1) : (at + (forward ? 1 : chain.length - 1)) % chain.length];
        if (macroList.visible) {
            macroList.close();
            requestActivate();
        }
        if (next === searchField.input)
            focusSearch(reason);
        else if (next)
            next.forceActiveFocus(reason);
        event.accepted = true;
    }
    // Runs the shortcut of the list's `row` (see rows) in the main window,
    // which this one closes for; one of Koil's own only where it does
    // something.
    function run(row) {
        if (row.own && !app.commandHere(row.shortcut.keys))
            return;
        close();
        app.runShortcut(row.shortcut, row.own);
    }
    // Back to the list from the form, on the shortcut it showed (by its
    // index), if the search shows it.
    function showList(index) {
        editing = false;
        shortcutList.currentIndex = index === undefined ? -1 : shown.indexOf(index);
        focusSearch();
    }
    // The shortcut the list's current row shows, by its index; -1 if none,
    // or one of Koil's own.
    function currentShortcut() {
        const row = rows[shortcutList.currentIndex];
        return row ? row.at : -1;
    }
    // Esc: from the form back to the list; in the list, it empties the
    // search, as in a macOS search field, or with none, it closes.
    function back() {
        if (editing) {
            showList(editIndex);
        } else if (searchField.input.text) {
            searchField.input.text = "";
            focusSearch();
        } else {
            close();
        }
    }
    // The form for the shortcut at `index`, or for a new one (-1).
    function edit(index) {
        const s = index < 0 ? { name: "", keys: "", macro: "", mode: "normal", enabled: true } : shortcuts[index];
        editIndex = index;
        nameField.input.text = s.name;
        keyBox.keys = s.keys;
        macroField.input.text = s.macro;
        // From its start, rather than scrolled to its end.
        macroField.input.cursorPosition = 0;
        modeChoice.current = Math.max(0, modes.findIndex(m => m.value === s.mode));
        enabledBox.checked = s.enabled;
        editing = true;
        nameField.input.forceActiveFocus();
    }
    function save() {
        if (!canSave)
            return;
        const list = shortcuts.slice();
        if (editIndex < 0)
            list.push(draft);
        else
            list[editIndex] = draft;
        app.saveShortcuts(list);
        showList(editIndex < 0 ? list.length - 1 : editIndex);
    }
    function remove(index) {
        const row = shortcutList.currentIndex;
        app.saveShortcuts(shortcuts.filter((s, i) => i !== index));
        editing = false;
        // On the user's shortcuts, rather than on Koil's own after them.
        shortcutList.currentIndex = rows.length ? Math.min(row, Math.max(shown.length - 1, 0)) : -1;
        focusSearch();
    }
    // A key while the macros are listed, which the list's window gets
    // (else the button that shows them): Down and Up go through them,
    // Enter takes one, and Tab goes on from the button.
    function macroKey(event) {
        const last = macroList.macros.length - 1;
        if (event.key === Qt.Key_Down)
            macroList.highlighted = Math.min(last, macroList.highlighted + 1);
        else if (event.key === Qt.Key_Up)
            macroList.highlighted = Math.max(0, macroList.highlighted - 1);
        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && macroList.highlighted >= 0)
            takeMacro(macroList.macros[macroList.highlighted]);
        else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
            tab(event, macroButton);
        else
            return;
        event.accepted = true;
    }
    // A macro picked from the list of them, as the keys to run.
    function takeMacro(macro) {
        macroField.input.text = macro.keys;
        macroList.close();
        // Back from the list's window, which some platforms leave active.
        requestActivate();
        macroField.input.forceActiveFocus();
    }
    // A key typed in the form's key box, which goes after its keys, as vim
    // names it (Space, g, <C-k>): Backspace takes the last one back, and
    // Cmd+Backspace all of them. Tab, Enter and Esc go through the form.
    function typeKey(event) {
        const typed = app.keyToken(event);
        if (typed === "<BS>" || typed === "<Del>")
            keyBox.keys = app.keyTokens(keyBox.keys).slice(0, -1).join("");
        else if (typed === "<D-BS>")
            keyBox.keys = "";
        else if (typed !== null)
            keyBox.keys += typed;
        else
            return;
        event.accepted = true;
    }

    title: qsTr("Shortcuts")
    flags: Qt.Dialog
    color: theme.window
    // Its size follows the zoom, so it isn't resizable; the list scrolls.
    readonly property int fitWidth: Math.ceil(480 * zoom)
    readonly property int fitHeight: Math.ceil(pages.implicitHeight + 2 * pages.y)

    width: fitWidth
    height: fitHeight
    minimumWidth: fitWidth
    maximumWidth: fitWidth
    minimumHeight: fitHeight
    maximumHeight: fitHeight

    // Not in the key box, which takes Cmd+W as a shortcut's key.
    Shortcut {
        sequences: [StandardKey.Close]
        enabled: win.focused && !keyBox.activeFocus
        onActivated: win.close()
    }
    // Not while the macros are listed, which Esc closes.
    Shortcut {
        sequence: "Escape"
        enabled: win.focused && !macroList.visible
        onActivated: win.back()
    }
    Shortcut {
        sequences: [StandardKey.New]
        enabled: win.focused && !win.editing
        onActivated: win.edit(-1)
    }
    // In the form, Enter saves, whatever has the keys (Space clicks a
    // button), as Return does a macOS dialog's default button. Not while
    // the macros are listed, where it takes one (see macroKey).
    Shortcut {
        sequences: ["Return", "Enter"]
        enabled: win.focused && win.editing && !macroList.visible
        onActivated: win.save()
    }

    // A small button with an icon, which Tab reaches.
    component WindowButton: IconButton {
        theme: win.theme
        color: win.theme.windowText
        focusPolicy: Qt.TabFocus
        Keys.onTabPressed: event => win.tab(event)
        Keys.onBacktabPressed: event => win.tab(event)
    }

    component FormButton: TextButton {
        theme: win.theme
        Keys.onTabPressed: event => win.tab(event)
        Keys.onBacktabPressed: event => win.tab(event)
    }

    // A text field.
    component Field: Rectangle {
        id: field

        property alias input: fieldInput
        property string label
        property string placeholder
        // Keys, in the editor's font.
        property bool mono
        // Room on the left for an icon, and on the right for a button.
        property real leftRoom: 8 * win.zoom
        property real rightRoom: 8 * win.zoom

        // A key, before the field types it, unless this takes it.
        signal keyPressed(var event)

        implicitWidth: 200 * win.zoom
        implicitHeight: 26 * win.zoom
        radius: 4 * win.zoom
        color: win.theme.field
        border.color: fieldInput.activeFocus ? win.theme.accent : win.theme.fieldBorder

        TextInput {
            id: fieldInput

            x: field.leftRoom
            width: field.width - x - field.rightRoom
            height: field.height
            clip: true
            font.family: field.mono ? win.theme.font.family : Application.font.family
            font.pixelSize: Math.round(13 * win.zoom)
            // Keys are drawn by `keysShown` over it, in colors.
            color: field.mono ? "transparent" : win.theme.windowText
            verticalAlignment: TextInput.AlignVCenter
            selectByMouse: true
            selectionColor: win.theme.highlight
            selectedTextColor: field.mono ? "transparent" : win.theme.highlightedText
            // Qt's own cursor has the text's color, which is clear for keys.
            // Like it, this one blinks (but stays while it moves), and like
            // macOS's, it hides while text is selected.
            cursorDelegate: Rectangle {
                id: caret

                width: fieldInput.cursorRectangle.width
                color: win.theme.windowText
                visible: fieldInput.activeFocus && fieldInput.selectionStart === fieldInput.selectionEnd

                Timer {
                    id: blink

                    interval: Qt.styleHints.cursorFlashTime / 2
                    running: caret.visible && interval > 0
                    repeat: true
                    onTriggered: caret.opacity = caret.opacity ? 0 : 1
                    onRunningChanged: caret.opacity = 1
                }
                Connections {
                    target: fieldInput

                    function onCursorPositionChanged() {
                        caret.opacity = 1;
                        blink.restart();
                    }
                }
            }
            Accessible.name: field.label
            Keys.onPressed: event => field.keyPressed(event)
            Keys.onTabPressed: event => win.tab(event)
            Keys.onBacktabPressed: event => win.tab(event)

            // The keys typed, with their names colored (see styledKeys),
            // where the field shows its text, as it scrolls sideways: the
            // cursor's place, less the text before it (a font of one
            // width, so the colors don't move the characters).
            Text {
                id: keysShown

                x: fieldInput.cursorRectangle.x - beforeCursor.advanceWidth
                height: fieldInput.height
                visible: field.mono
                text: field.mono ? win.styledKeys(fieldInput.text) : ""
                textFormat: Text.StyledText
                font: fieldInput.font
                color: win.theme.windowText
                verticalAlignment: Text.AlignVCenter

                TextMetrics {
                    id: beforeCursor

                    font: fieldInput.font
                    text: fieldInput.text.slice(0, fieldInput.cursorPosition)
                }
            }
            Text {
                anchors.fill: parent
                visible: !fieldInput.text
                text: field.placeholder
                font: fieldInput.font
                color: win.theme.windowText
                opacity: 0.5
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }
    }

    // A shortcut in the list: a click runs it, as Enter does while it's the
    // current one, and its buttons edit or delete it. One of Koil's own has
    // a lock instead, says where it works, and is dimmed where vim is if
    // it does nothing there; the first of them is under a heading.
    component ShortcutRow: AbstractButton {
        id: row

        // One of `rows`. It comes with the shortcut, as the shortcuts
        // change before the list does.
        required property var modelData
        readonly property int at: modelData.at
        readonly property var shortcut: modelData.shortcut
        readonly property bool own: modelData.own
        readonly property real headingHeight: modelData.heading ? 26 * win.zoom : 0
        readonly property bool usable: own ? win.app.commandHere(shortcut.keys) : shortcut.enabled
        readonly property Item editButton: editIcon
        readonly property Item deleteButton: deleteIcon
        // Highlighted while the keys are in the search, where Up and Down
        // move it and Enter runs it, or on its buttons.
        readonly property bool current: row.ListView.isCurrentItem
            && (searchField.input.activeFocus || editIcon.activeFocus || deleteIcon.activeFocus)

        width: ListView.view.width
        implicitHeight: 30 * win.zoom + headingHeight
        topInset: headingHeight
        topPadding: headingHeight
        focusPolicy: Qt.NoFocus
        hoverEnabled: true
        Accessible.name: win.titleOf(shortcut)
        Accessible.description: own ? qsTr("Built-in, which runs it") : qsTr("Runs it")
        onClicked: win.run(modelData)

        background: Rectangle {
            radius: 3 * win.zoom
            color: row.current ? win.theme.checked : row.hovered && !headingArea.containsMouse ? win.theme.hover
                : "transparent"
        }
        Text {
            visible: row.headingHeight > 0
            height: row.headingHeight
            leftPadding: 6 * win.zoom
            verticalAlignment: Text.AlignVCenter
            text: qsTr("Built-in shortcuts, which can't be changed")
            font.pixelSize: Math.round(12 * win.zoom)
            color: win.theme.windowText
            opacity: 0.6

            // Not a part of the row, which a click here doesn't run.
            MouseArea {
                id: headingArea

                width: row.width
                height: parent.height
                enabled: parent.visible
                hoverEnabled: true
            }
        }
        contentItem: RowLayout {
            spacing: 8 * win.zoom

            Text {
                Layout.fillWidth: true
                leftPadding: 6 * win.zoom
                // Keys (it has no name) in the editor's font, and with
                // neither a name nor keys, the keys it runs, colored.
                readonly property bool showsKeys: !row.shortcut.name && !row.shortcut.keys
                text: showsKeys ? win.styledKeys(row.shortcut.macro) : win.titleOf(row.shortcut)
                font.family: row.shortcut.name ? Application.font.family : win.theme.font.family
                font.pixelSize: Math.round(13 * win.zoom)
                color: win.theme.windowText
                opacity: row.usable ? 1 : 0.5
                elide: Text.ElideRight
                textFormat: showsKeys ? Text.StyledText : Text.PlainText
            }
            Text {
                visible: text !== ""
                text: row.own ? row.shortcut.where : win.modeLabel(row.shortcut)
                font.pixelSize: Math.round(12 * win.zoom)
                color: win.theme.windowText
                opacity: 0.6
            }
            KeyCap {
                visible: row.shortcut.name !== "" && row.shortcut.keys !== ""
                opacity: row.usable ? 1 : 0.5
                theme: win.theme
                text: win.app.keysName(row.shortcut.keys)
                padding: 5 * win.zoom
                textColor: win.theme.windowText
            }
            WindowButton {
                id: editIcon

                visible: !row.own
                iconPath: "M10.5 3 L13 5.5 L6 12.5 L3 13 L3.5 10 Z M9 4.5 L11.5 7"
                tip: qsTr("Edit")
                onClicked: win.edit(row.at)
            }
            WindowButton {
                id: deleteIcon

                visible: !row.own
                Layout.rightMargin: 2 * win.zoom
                iconPath: "M3 4.5 H13 M6.5 4.5 V3 H9.5 V4.5 M4.5 4.5 L5.2 13 H10.8 L11.5 4.5 M6.8 7 V11 M9.2 7 V11"
                tip: qsTr("Delete")
                onClicked: win.remove(row.at)
            }
            // In the room of the two buttons, under the trash, so the
            // keys line up with the user's.
            Item {
                visible: row.own
                Layout.rightMargin: 2 * win.zoom
                implicitWidth: 52 * win.zoom
                implicitHeight: 22 * win.zoom

                Icon {
                    anchors.right: parent.right
                    anchors.rightMargin: 3 * win.zoom
                    anchors.verticalCenter: parent.verticalCenter
                    theme: win.theme
                    path: "M4 7.5 H12 V13.5 H4 Z M5.5 7.5 V5.5 A2.5 2.5 0 0 1 10.5 5.5 V7.5"
                    color: win.theme.windowText
                    opacity: 0.6

                    HoverHandler {
                        id: lockHover
                    }
                    Tip {
                        theme: win.theme
                        visible: lockHover.hovered
                        text: qsTr("Built-in: it can't be changed")
                        x: Math.round((parent.width - width) / 2)
                        y: parent.height + 9 * win.zoom
                    }
                }
            }
        }
    }

    component FormLabel: Label {
        font.pixelSize: Math.round(13 * win.zoom)
        color: win.theme.windowText
    }

    // Text that matters less, like a hint.
    component Hint: Text {
        font.pixelSize: Math.round(12 * win.zoom)
        color: win.theme.windowText
        opacity: 0.6
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        Accessible.role: Accessible.StaticText
        Accessible.name: text
    }

    // The list and the form, as tall as the taller one.
    StackLayout {
        id: pages

        x: 20 * win.zoom
        y: 16 * win.zoom
        width: win.width - 2 * x
        height: win.height - 2 * y
        currentIndex: win.editing ? 1 : 0

        ColumnLayout {
            spacing: 10 * win.zoom

            RowLayout {
                Layout.fillWidth: true
                spacing: 8 * win.zoom

                // It has the keys: Up and Down pick a shortcut, Enter runs
                // it, and Esc empties it (see back).
                Field {
                    id: searchField

                    Layout.fillWidth: true
                    label: qsTr("Search shortcuts")
                    placeholder: qsTr("Search")
                    leftRoom: searchIcon.width + 8 * win.zoom

                    Icon {
                        id: searchIcon

                        x: 5 * win.zoom
                        anchors.verticalCenter: parent.verticalCenter
                        theme: win.theme
                        path: "M3 7 A4 4 0 1 0 11 7 A4 4 0 1 0 3 7 Z M10 10 L13.5 13.5"
                        color: win.theme.windowText
                        opacity: 0.6
                    }

                    Connections {
                        target: searchField.input

                        function onTextChanged() {
                            shortcutList.currentIndex = win.rows.length ? 0 : -1;
                        }
                    }
                    onKeyPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (shortcutList.currentIndex >= 0)
                                win.run(win.rows[shortcutList.currentIndex]);
                        } else if (event.key === Qt.Key_Down)
                            shortcutList.incrementCurrentIndex();
                        else if (event.key === Qt.Key_Up)
                            shortcutList.decrementCurrentIndex();
                        else
                            return;
                        event.accepted = true;
                    }
                }
                // Koil's own keys (the built-in shortcuts) under the
                // user's, or not (saved).
                WindowButton {
                    id: ownButton

                    iconPath: "M4 7.5 H12 V13.5 H4 Z M5.5 7.5 V5.5 A2.5 2.5 0 0 1 10.5 5.5 V7.5"
                    tip: qsTr("Show Built-in Shortcuts")
                    checked: win.app.showOwnShortcuts
                    Accessible.checkable: true
                    Accessible.checked: checked
                    onClicked: {
                        win.app.changeSetting("showOwnShortcuts", !win.app.showOwnShortcuts);
                        // On a row still shown, if it was on one of Koil's.
                        shortcutList.currentIndex = Math.min(shortcutList.currentIndex, win.rows.length - 1);
                    }
                }
                WindowButton {
                    id: newButton

                    iconPath: "M4 8 H12 M8 4 V12"
                    tip: qsTr("New Shortcut")
                    shortcuts: [win.isMac ? "⌘N" : "Ctrl+N"]
                    onClicked: win.edit(-1)
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 4 * win.zoom
                color: win.theme.field
                border.color: win.theme.fieldBorder

                ListView {
                    id: shortcutList

                    anchors.fill: parent
                    anchors.margins: 4 * win.zoom
                    clip: true
                    model: win.rows
                    currentIndex: -1
                    boundsBehavior: Flickable.StopAtBounds
                    Accessible.name: qsTr("Shortcuts")
                    ScrollIndicator.vertical: ScrollIndicator {}

                    // Picked from the search, which keeps the keys.
                    delegate: ShortcutRow {}
                    // Over Koil's own, while the user has none. The text
                    // keeps the height it wraps to (its own, bound to its
                    // implicit one, was a binding loop), which this takes.
                    header: Item {
                        width: shortcutList.width
                        height: noneYet.visible ? noneYet.implicitHeight : 0

                        Hint {
                            id: noneYet

                            width: parent.width
                            visible: !win.shortcuts.length && !win.searchWords.length && win.app.showOwnShortcuts
                            leftPadding: 6 * win.zoom
                            topPadding: 6 * win.zoom
                            bottomPadding: 6 * win.zoom
                            text: qsTr("No shortcuts of yours yet: + makes one.")
                        }
                    }

                    Hint {
                        anchors.centerIn: parent
                        width: parent.width - 40 * win.zoom
                        visible: !shortcutList.count
                        horizontalAlignment: Text.AlignHCenter
                        text: win.searchWords.length ? qsTr("No shortcut matches “%1”.").arg(searchField.input.text.trim())
                            : qsTr("No shortcuts yet: + makes one.")
                    }
                }
            }

            Hint {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                text: qsTr("↑ and ↓ pick one, and Enter or a click runs it.")
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }
        }

        ColumnLayout {
            spacing: 12 * win.zoom

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 12 * win.zoom
                rowSpacing: 10 * win.zoom

                FormLabel {
                    text: qsTr("Name")
                }
                Field {
                    id: nameField

                    Layout.fillWidth: true
                    label: qsTr("Name")
                    placeholder: qsTr("Optional, like “Copy the path”")
                }

                FormLabel {
                    text: qsTr("Shortcut")
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6 * win.zoom

                    // The keys that run it, which keys typed here go after
                    // (see typeKey). None is fine: the shortcut then keeps
                    // its keys for later.
                    Rectangle {
                        id: keyBox

                        // As Vim.commandKeys' are written: " c" is Space c.
                        property string keys

                        Layout.maximumWidth: 240 * win.zoom
                        implicitWidth: Math.max(40 * win.zoom, keyText.implicitWidth + 16 * win.zoom)
                        implicitHeight: 26 * win.zoom
                        radius: 4 * win.zoom
                        color: win.theme.field
                        border.color: activeFocus ? win.theme.accent : win.theme.fieldBorder
                        activeFocusOnTab: true
                        Accessible.role: Accessible.EditableText
                        Accessible.name: qsTr("Shortcut keys")
                        Accessible.description: keys ? win.app.keysName(keys) : ""
                        Keys.onPressed: event => win.typeKey(event)
                        Keys.onTabPressed: event => win.tab(event)
                        Keys.onBacktabPressed: event => win.tab(event)

                        // The last keys, if they don't all fit.
                        Text {
                            id: keyText

                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, keyBox.width - 16 * win.zoom)
                            text: keyBox.keys ? win.app.keysName(keyBox.keys) : qsTr("None")
                            font.family: keyBox.keys ? win.theme.font.family : Application.font.family
                            font.pixelSize: Math.round(13 * win.zoom)
                            color: win.theme.windowText
                            opacity: keyBox.keys ? 1 : 0.5
                            elide: Text.ElideLeft
                            textFormat: Text.PlainText
                        }
                        TapHandler {
                            onTapped: keyBox.forceActiveFocus()
                        }
                    }
                    Hint {
                        Layout.fillWidth: true
                        visible: keyBox.activeFocus
                        text: qsTr("Type the keys, like gc (Backspace takes one back)")
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                    }
                }

                FormLabel {
                    text: qsTr("Runs")
                }
                Field {
                    id: macroField

                    Layout.fillWidth: true
                    label: qsTr("Keys it runs")
                    mono: true
                    rightRoom: macroButton.width + 4 * win.zoom
                    placeholder: Qt.platform.os === "osx" ? ":!echo %:p | pbcopy<CR>"
                        : Qt.platform.os === "windows" ? ":!echo %:p | clip<CR>" : ":!echo %:p<CR>"

                    WindowButton {
                        id: macroButton

                        anchors.right: parent.right
                        anchors.rightMargin: 2 * win.zoom
                        anchors.verticalCenter: parent.verticalCenter
                        iconPath: "M5 6.5 L8 9.5 L11 6.5"
                        tip: qsTr("Recorded Macros")
                        onClicked: macroList.visible ? macroList.close() : macroList.open()
                        Keys.onPressed: event => {
                            if (macroList.visible)
                                win.macroKey(event);
                        }
                    }

                    // The registers q records into that hold something,
                    // in its own window, as Settings' font list.
                    DropList {
                        id: macroList

                        property var macros: []
                        // The one Enter takes.
                        property int highlighted: -1

                        theme: win.theme
                        field: macroField
                        maxHeight: 240 * win.zoom
                        model: macros
                        // Its window gets the keys while it's open (see
                        // macroKey).
                        takesKeys: true
                        emptyText: qsTr("No macros recorded: qa records one in a, and q stops.")
                        emptySize: Math.round(12 * win.zoom)
                        onKeyPressed: event => win.macroKey(event)
                        onAboutToShow: {
                            macros = win.app.macroList();
                            highlighted = macros.length ? 0 : -1;
                        }
                        onHighlightedChanged: {
                            if (highlighted >= 0)
                                view.positionViewAtIndex(highlighted, ListView.Contain);
                        }

                        delegate: DropList.Option {
                            id: macro

                            required property var modelData
                            required property int index
                            readonly property bool highlighted: macroList.highlighted === index

                            theme: win.theme
                            lit: highlighted
                            Accessible.name: "\"" + modelData.name + " " + modelData.keys
                            onHoveredChanged: if (hovered) macroList.highlighted = index
                            onClicked: win.takeMacro(modelData)

                            // The register, dimmed, then its keys.
                            contentItem: Row {
                                leftPadding: 4 * win.zoom
                                rightPadding: 4 * win.zoom
                                spacing: 10 * win.zoom

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "\"" + macro.modelData.name
                                    font.family: win.theme.font.family
                                    font.pixelSize: Math.round(13 * win.zoom)
                                    color: macro.highlighted ? win.theme.highlightedText : win.theme.dim
                                    textFormat: Text.PlainText
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: macro.width - x - 4 * win.zoom
                                    text: win.styledKeys(macro.modelData.keys, macro.highlighted
                                        ? win.theme.highlightedText : undefined)
                                    font.family: win.theme.font.family
                                    font.pixelSize: Math.round(13 * win.zoom)
                                    color: macro.highlighted ? win.theme.highlightedText : win.theme.windowText
                                    elide: Text.ElideRight
                                    textFormat: Text.StyledText
                                }
                            }
                        }
                    }
                }

                // One line, so the form is as tall before it's first laid
                // out (when the window's height is worked out) as after.
                Item {}
                Hint {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    Layout.topMargin: -4 * win.zoom
                    text: qsTr("Keys as q records them, like <CR> for Enter and <Esc>.")
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }

                FormLabel {
                    text: qsTr("Mode")
                }
                Segmented {
                    id: modeChoice

                    theme: win.theme
                    options: win.modes
                    Accessible.name: qsTr("Mode")
                    onPicked: index => current = index
                    Keys.onTabPressed: event => win.tab(event)
                    Keys.onBacktabPressed: event => win.tab(event)
                }

                Item {}
                AbstractButton {
                    id: enabledBox

                    checkable: true
                    focusPolicy: Qt.TabFocus
                    text: qsTr("Enabled")
                    Accessible.role: Accessible.CheckBox
                    Accessible.name: text
                    Accessible.checked: checked
                    Keys.onTabPressed: event => win.tab(event)
                    Keys.onBacktabPressed: event => win.tab(event)
                    Keys.onReturnPressed: click()
                    Keys.onEnterPressed: click()

                    // Its ring, as the box is the accent's color when on.
                    background: Rectangle {
                        x: -4 * win.zoom
                        y: -3 * win.zoom
                        width: parent.width + 8 * win.zoom
                        height: parent.height + 6 * win.zoom
                        radius: 4 * win.zoom
                        color: "transparent"
                        border.color: enabledBox.visualFocus ? win.theme.accent : "transparent"
                    }

                    contentItem: Row {
                        spacing: 8 * win.zoom

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16 * win.zoom
                            height: 16 * win.zoom
                            radius: 3 * win.zoom
                            color: enabledBox.checked ? win.theme.accent : win.theme.field
                            border.color: enabledBox.checked || enabledBox.visualFocus ? win.theme.accent : win.theme.fieldBorder

                            Icon {
                                anchors.centerIn: parent
                                visible: enabledBox.checked
                                theme: win.theme
                                path: "M4 8.5 L7 11.5 L12 5"
                                color: win.theme.highlightedText
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: enabledBox.text
                            font.pixelSize: Math.round(13 * win.zoom)
                            color: win.theme.windowText
                        }
                    }
                }
            }

            // Why it can't be saved, or else what of vim's it takes the
            // place of, in room kept for two lines, so the window doesn't
            // change size.
            Hint {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                Layout.preferredHeight: Math.ceil(2 * problemMetrics.height)
                text: win.problem || win.note
                color: win.problem ? win.theme.error : win.theme.severityColor("warning")
                opacity: 1
                verticalAlignment: Text.AlignTop

                FontMetrics {
                    id: problemMetrics

                    font.pixelSize: Math.round(12 * win.zoom)
                }
            }

            Item {
                Layout.fillHeight: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8 * win.zoom

                FormButton {
                    id: deleteButton

                    visible: win.editIndex >= 0
                    text: qsTr("Delete")
                    onClicked: win.remove(win.editIndex)
                }
                Item {
                    Layout.fillWidth: true
                }
                FormButton {
                    id: cancelButton

                    text: qsTr("Cancel")
                    onClicked: win.showList(win.editIndex)
                }
                FormButton {
                    id: saveButton

                    primary: true
                    text: win.editIndex < 0 ? qsTr("Create") : qsTr("Save")
                    enabled: win.canSave
                    onClicked: win.save()
                }
            }
        }
    }
}
